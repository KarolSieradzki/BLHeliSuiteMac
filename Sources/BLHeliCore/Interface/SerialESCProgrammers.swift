import Foundation

// Programming paths without a 4-way interface:
//  * "SILABS / ATMEL BLHeli Bootloader (USB/Com)" – a USB-UART bridge on the ESC signal wire (1-wire, echo),
//    the PC speaks the BLHeli bootloader protocol itself (TBLBInterface, VMT 0x637B74).
//  * "ATMEL SK Bootloader (ArduinoUSBLinker / Afro-Turnigy USB Linker)" – the linker forwards STK500 v2
//    messages to the SimonK bootloader (TStk500v2, VMT 0x63B69C; TStk500v2Interface, VMT 0x63F880).

// MARK: - BLHeli bootloader over USB/Com

public final class BLHeliBootloaderProgrammer: ESCProgrammer {
    public let port: SerialPort
    public let boot: BLHeliBootloader
    public let family: MCUFamily
    public var cancelRequested = false
    public private(set) var isConnected = true
    public private(set) var device: DeviceInfo?

    public var interfaceName: String { "BLHeli Bootloader (USB/Com)" }
    public var escCount: Int { 1 }

    public init(port: SerialPort, family: MCUFamily) {
        self.port = port
        self.family = family
        boot = BLHeliBootloader(channel: port, oneWire: true)
        boot.timeout = 0.5
    }

    public static func open(portPath: String, baud: Int, family: MCUFamily) throws -> BLHeliBootloaderProgrammer {
        let sp = SerialPort(path: portPath)
        try sp.open(baudRate: baud)
        return BLHeliBootloaderProgrammer(port: sp, family: family)
    }

    public func selectESC(_ index: Int) throws -> DeviceInfo {
        try boot.connect(bootSign: "BLHeli", attempts: 9)
        let mcu = MCUTable.byBootSignature(boot.signature)
        let fam = mcu?.family ?? family
        let mode: FourWayInterfaceMode = fam == .silabs ? .siLabsBLB : .atmelBLB
        let dev = DeviceInfo(interfaceMode: mode, mcu: mcu, signature: boot.signature,
                             bootInfo: boot.bootMessage.utf8.last ?? 0, raw: boot.bootInfo)
        device = dev
        Log.info("BLHeli bootloader: \(dev.description) \"\(boot.bootMessage)\"")
        return dev
    }

    var atmel: Bool { (device?.family ?? family) == .atmel }

    public func readFlash(address: Int, count: Int, progress: ProgressHandler?) throws -> [UInt8] {
        var out: [UInt8] = []
        while out.count < count {
            try checkCancel()
            let n = min(256, count - out.count)
            out += try boot.readFlash(address: address + out.count, count: n, atmel: atmel)
            progress?(out.count, count)
        }
        return out
    }

    public func writeFlash(address: Int, data: [UInt8], progress: ProgressHandler?) throws {
        var off = 0
        while off < data.count {
            try checkCancel()
            let n = min(256, data.count - off)
            try boot.writeFlash(address: address + off, data: Array(data[off..<(off + n)]))
            off += n
            progress?(off, data.count)
        }
    }

    public func erasePage(address: Int) throws {
        if atmel {
            try writeFlash(address: address, data: [UInt8](repeating: 0xFF, count: device?.pageSize ?? 0x40), progress: nil)
        } else {
            try boot.erasePage(address: address)
        }
    }

    public func eraseChip() throws {
        throw ProgrammerError.notSupported("Erase chip is only available in C2 mode.")
    }

    public func readEEPROM(address: Int, count: Int) throws -> [UInt8] {
        try boot.readEEprom(address: address, count: count)
    }

    public func writeEEPROM(address: Int, data: [UInt8], progress: ProgressHandler?) throws {
        var off = 0
        while off < data.count {
            let n = min(256, data.count - off)
            try boot.writeEEprom(address: address + off, data: Array(data[off..<(off + n)]))
            off += n
            progress?(off, data.count)
        }
    }

    public func resetESC(_ index: Int) throws { boot.run() }
    public func keepAlive() throws { try boot.keepAlive() }

    public func disconnect() {
        guard isConnected else { return }
        isConnected = false
        boot.run()
        port.close()
    }
}

// MARK: - STK500 v2 (SimonK bootloader)

public enum STK500v2Error: Error, LocalizedError {
    case noAnswer(String)
    case failed(String, UInt8)
    public var errorDescription: String? {
        switch self {
        case .noAnswer(let c): return "SK bootloader: no answer (\(c))"
        case .failed(let c, let s): return String(format: "SK bootloader: %@ failed (status 0x%02X)", c, s)
        }
    }
}

/// STK500 v2 framing: 0x1B seq sizeHi sizeLo 0x0E body xor.
public final class STK500v2 {
    public let channel: ByteChannel
    var seq: UInt8 = 0
    public var timeout: TimeInterval = 1.0

    public init(channel: ByteChannel) { self.channel = channel }

    public func transact(_ body: [UInt8], _ name: String, timeout t: TimeInterval? = nil) throws -> [UInt8] {
        seq &+= 1
        var msg: [UInt8] = [0x1B, seq, UInt8(body.count >> 8), UInt8(body.count & 0xFF), 0x0E] + body
        msg.append(msg.reduce(0, ^))
        channel.discardInput()
        try channel.write(msg)
        let deadline = monotonicNow() + (t ?? timeout)
        var buf: [UInt8] = []
        while monotonicNow() < deadline {
            buf += try channel.read(maxCount: 300, timeout: 0.05)
            // drop anything before the start byte (echo of the linker, noise)
            while let s = buf.firstIndex(of: 0x1B), s > 0 { buf.removeFirst(s) }
            if buf.count >= 6, buf[0] == 0x1B, buf[4] == 0x0E {
                let n = Int(buf[2]) << 8 | Int(buf[3])
                if buf.count >= 6 + n {
                    let frame = Array(buf[0..<(6 + n)])
                    if frame.dropLast().reduce(0, ^) == frame.last!, frame[1] == seq || n > 0 {
                        let answer = Array(frame[5..<(5 + n)])
                        if answer.first == body.first { return answer }
                    }
                    buf.removeFirst(6 + n)
                }
            }
        }
        throw STK500v2Error.noAnswer(name)
    }

    func ok(_ body: [UInt8], _ name: String, timeout t: TimeInterval? = nil) throws -> [UInt8] {
        let a = try transact(body, name, timeout: t)
        guard a.count >= 2, a[1] == 0x00 else { throw STK500v2Error.failed(name, a.count > 1 ? a[1] : 0xFF) }
        return a
    }

    public func signOn() throws -> String {
        let a = try ok([0x01], "CMD_SIGN_ON")
        guard a.count >= 3 else { return "" }
        let n = Int(a[2])
        return String(decoding: a.dropFirst(3).prefix(n), as: UTF8.self)
    }

    public func enterProgMode() throws {
        _ = try ok([0x10, 200, 100, 25, 32, 0, 0x53, 3, 0xAC, 0x53, 0, 0], "CMD_ENTER_PROGMODE_ISP")
    }

    public func leaveProgMode() throws { _ = try ok([0x11, 1, 1], "CMD_LEAVE_PROGMODE_ISP") }

    public func readSignature() throws -> UInt32 {
        var sig: UInt32 = 0
        for i in 0..<3 {
            let a = try ok([0x1B, 4, 0x30, 0, UInt8(i), 0], "CMD_READ_SIGNATURE_ISP")
            sig = sig << 8 | UInt32(a.count > 2 ? a[2] : 0)
        }
        return sig
    }

    /// LOAD_ADDRESS (word address for flash, byte address for EEPROM).
    public func loadAddress(_ a: Int) throws {
        _ = try ok([0x06, UInt8((a >> 24) & 0xFF), UInt8((a >> 16) & 0xFF), UInt8((a >> 8) & 0xFF), UInt8(a & 0xFF)], "CMD_LOAD_ADDRESS")
    }

    public func readFlash(byteAddress: Int, count: Int) throws -> [UInt8] {
        try loadAddress(byteAddress / 2)
        let a = try ok([0x14, UInt8(count >> 8), UInt8(count & 0xFF), 0x20], "CMD_READ_FLASH_ISP", timeout: 2)
        return Array(a.dropFirst(2).prefix(count))
    }

    public func programFlash(byteAddress: Int, data: [UInt8]) throws {
        try loadAddress(byteAddress / 2)
        _ = try ok([0x13, UInt8(data.count >> 8), UInt8(data.count & 0xFF), 0xC1, 10, 0x40, 0x4C, 0x20, 0, 0] + data,
                   "CMD_PROGRAM_FLASH_ISP", timeout: 3)
    }

    public func readEEPROM(address: Int, count: Int) throws -> [UInt8] {
        try loadAddress(address)
        let a = try ok([0x16, UInt8(count >> 8), UInt8(count & 0xFF), 0xA0], "CMD_READ_EEPROM_ISP", timeout: 2)
        return Array(a.dropFirst(2).prefix(count))
    }

    public func programEEPROM(address: Int, data: [UInt8]) throws {
        try loadAddress(address)
        _ = try ok([0x15, UInt8(data.count >> 8), UInt8(data.count & 0xFF), 0xC1, 10, 0xC1, 0xC2, 0xA0, 0, 0] + data,
                   "CMD_PROGRAM_EEPROM_ISP", timeout: 5)
    }
}

/// SimonK bootloader through ArduinoUSBLinker or an Afro/Turnigy USB linker.
public final class SimonKProgrammer: ESCProgrammer {
    public let port: SerialPort
    public let stk: STK500v2
    public let linkerName: String
    public var cancelRequested = false
    public private(set) var isConnected = true
    public private(set) var device: DeviceInfo?
    public private(set) var signOnText = ""

    public var interfaceName: String { linkerName }
    public var escCount: Int { 1 }

    public init(port: SerialPort, linkerName: String) {
        self.port = port
        self.linkerName = linkerName
        stk = STK500v2(channel: port)
    }

    public func selectESC(_ index: Int) throws -> DeviceInfo {
        var lastError: Error = STK500v2Error.noAnswer("CMD_SIGN_ON")
        for _ in 0..<5 {
            do {
                signOnText = try stk.signOn()
                try stk.enterProgMode()
                let sig = try stk.readSignature()
                let mcu = MCUTable.byAVRSignature(sig)
                let dev = DeviceInfo(interfaceMode: .atmelSK, mcu: mcu, signature: mcu?.bootSignature ?? UInt16(sig & 0xFFFF),
                                     bootInfo: 0x63, raw: [])
                device = dev
                Log.info("SK bootloader \"\(signOnText)\": \(dev.description)")
                return dev
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    public func readFlash(address: Int, count: Int, progress: ProgressHandler?) throws -> [UInt8] {
        var out: [UInt8] = []
        while out.count < count {
            try checkCancel()
            let n = min(256, count - out.count)
            out += try stk.readFlash(byteAddress: address + out.count, count: n)
            progress?(out.count, count)
        }
        return out
    }

    public func writeFlash(address: Int, data: [UInt8], progress: ProgressHandler?) throws {
        let ps = device?.pageSize ?? 64
        var off = 0
        while off < data.count {
            try checkCancel()
            let n = min(ps, data.count - off)
            try stk.programFlash(byteAddress: address + off, data: Array(data[off..<(off + n)]))
            off += n
            progress?(off, data.count)
        }
    }

    public func erasePage(address: Int) throws {
        try writeFlash(address: address, data: [UInt8](repeating: 0xFF, count: device?.pageSize ?? 64), progress: nil)
    }

    public func eraseChip() throws {
        throw ProgrammerError.notSupported("Erase chip is only available in C2 mode.")
    }

    public func readEEPROM(address: Int, count: Int) throws -> [UInt8] {
        var out: [UInt8] = []
        while out.count < count {
            let n = min(128, count - out.count)
            out += try stk.readEEPROM(address: address + out.count, count: n)
        }
        return out
    }

    public func writeEEPROM(address: Int, data: [UInt8], progress: ProgressHandler?) throws {
        var off = 0
        while off < data.count {
            let n = min(64, data.count - off)
            try stk.programEEPROM(address: address + off, data: Array(data[off..<(off + n)]))
            off += n
            progress?(off, data.count)
        }
    }

    /// CMD_LEAVE_PROGMODE starts the ESC firmware.
    public func resetESC(_ index: Int) throws { try stk.leaveProgMode() }

    public func keepAlive() throws { _ = try stk.signOn() }

    public func disconnect() {
        guard isConnected else { return }
        isConnected = false
        try? stk.leaveProgMode()
        port.close()
    }
}
