import Foundation

public enum BootloaderError: Error, LocalizedError {
    case noConnection(String)
    case ack(UInt8, String)
    case oneWireTest(String)
    case bufferTooLarge(Int, Int)

    public var errorDescription: String? {
        switch self {
        case .noConnection(let s): return s
        case .ack(let a, let cmd): return "\(cmd): \(BLHeliBootloader.ackName(a))"
        case .oneWireTest(let s): return "Test of the 1-Wire connection failed.\n" + s
        case .bufferTooLarge(let n, let m): return String(format: "Length of data exeeds buffer size: %d > %d", n, m)
        }
    }
}

/// Serial side of the BLHeli bootloaders (AVRootloader based Atmel bootloader, SiLabs BLHeli bootloader)
/// as BLHeliSuite's TBootloader (class at 0x5E3F70) speaks it: directly over a USB-UART bridge
/// ("BLHeli Bootloader (USB/Com)", 1-wire – every sent byte comes back as echo) and to update the
/// BLHeliSuite boxes (bootsign "BOOT").
public final class BLHeliBootloader {
    /// Commands (names of FUN_005E8714).
    public enum Command: UInt8 {
        case run = 0, progFlash = 1, eraseFlash = 2, readFlashSiLabsOrVerify = 3, readEEprom = 4, progEEprom = 5
        case readSram = 6, readFlashAtmel = 7, keepAlive = 0xFD, setBuffer = 0xFE, setAddress = 0xFF
    }

    public static let success: UInt8 = 0x30
    public static let errorCommand: UInt8 = 0xC1
    public static let noAnswer: UInt8 = 0xFF

    /// FUN_005E8378: names of the answer codes.
    public static func ackName(_ a: UInt8) -> String {
        if (0x30...0x3F).contains(a) { return "SUCCESS" }
        switch a {
        case 0xC0: return "ERROR_VERIFY"
        case 0xC1: return "ERROR_COMMAND"
        case 0xC2: return "ERROR_CRC"
        case 0xC3: return "ERROR_BOUNDS"
        case 0xC4: return "ERROR_CRYPT"
        case 0xC5: return "ERROR_PROG"
        case 0xC6: return "ERROR_VERSION"
        case 0xC7: return "ERROR_COM_WRITE"
        case 0xC8: return "ERROR_COM_READ"
        case 0xC9: return "ERROR_COM_ECHO"
        case 0xCA: return "ERROR_CRC"
        case 0xCB: return "ERROR_UNKNOWN"
        case 0xFF: return "NO_ANSWER"
        default: return "UNKNOWN ACK"
        }
    }

    public let channel: ByteChannel
    /// 1-wire connection: the bridge echoes every byte that is sent.
    public var oneWire: Bool
    /// Answer timeout (TBootloader+0xB0, 500 ms for the boxes).
    public var timeout: TimeInterval = 0.5
    /// Maximum buffer of the bootloader (256 bytes).
    public var bufferSize = 256
    public private(set) var lastAck: UInt8 = noAnswer
    /// Answer of the boot init: message ("471d", box name …), signature, boot version, pages, ack.
    public private(set) var bootInfo: [UInt8] = []
    public private(set) var bootMessage = ""
    public private(set) var signature: UInt16 = 0
    public private(set) var bootVersion: UInt8 = 0
    public private(set) var bootPages: Int = 0
    public var log: ((String) -> Void)?

    public init(channel: ByteChannel, oneWire: Bool) {
        self.channel = channel
        self.oneWire = oneWire
    }

    // MARK: framing (FUN_005E8BAC / FUN_005E69F0)

    /// Writes `data` (+ CRC16) and swallows the echo on 1-wire connections.
    func send(_ data: [UInt8], crc: Bool = true) throws {
        var out = data
        if crc {
            let c = Checksum.crc16BLHeli(data)
            out += [UInt8(c & 0xFF), UInt8(c >> 8)]
        }
        channel.discardInput()
        do { try channel.write(out) } catch { lastAck = 0xC7; throw error }
        if oneWire {
            let echo = try channel.readExactly(out.count, timeout: 0.25 + Double(out.count) * 0.002)
            if echo != out {
                lastAck = 0xC9
                throw BootloaderError.ack(0xC9, "Echo")
            }
        }
    }

    /// Reads the one byte answer of a command.
    func ack(_ name: String, timeout t: TimeInterval? = nil) throws -> UInt8 {
        let r = try channel.readExactly(1, timeout: t ?? timeout)
        lastAck = r.first ?? BLHeliBootloader.noAnswer
        return lastAck
    }

    func expectSuccess(_ name: String, timeout t: TimeInterval? = nil) throws {
        let a = try ack(name, timeout: t)
        guard a == BLHeliBootloader.success else { throw BootloaderError.ack(a, name) }
    }

    // MARK: connect (FUN_005E4AFC, FUN_005E7568, FUN_005E5468)

    /// Sends "<sign><CRC>" (preceded by the wake up bytes of the 4-way interface for the ESC sign)
    /// and evaluates the boot info. `attempts` like TBootloader (9 for a waiting device, 1 otherwise).
    public func connect(bootSign: String, attempts: Int = 9) throws {
        if oneWire {
            log?("Check 1-Wire Connection:")
            channel.discardInput()
            try channel.write([0x00])
            let e = try channel.readExactly(1, timeout: 0.3)
            if e != [0x00] { throw BootloaderError.oneWireTest("No echo from the 1-wire bridge.") }
        }
        let sign = Array(bootSign.utf8)
        var initMsg: [UInt8] = []
        if bootSign == "BLHeli" { initMsg = [UInt8](repeating: 0, count: 8) + [0x0D] }
        let c = Checksum.crc16BLHeli(sign)
        initMsg += sign + [UInt8(c & 0xFF), UInt8(c >> 8)]
        log?("Waiting for Device:")
        for _ in 0..<max(1, attempts) {
            log?("BOOTSTART")
            do {
                try send(initMsg, crc: false)
            } catch BootloaderError.ack {
                continue
            }
            var answer: [UInt8] = []
            let deadline = monotonicNow() + max(timeout, 0.5)
            while monotonicNow() < deadline {
                let r = try channel.read(maxCount: 64, timeout: 0.05)
                answer += r
                if !r.isEmpty, answer.count >= 8, (0x30...0x3F).contains(answer.last!) {
                    // short pause: some bootloaders send their info in two parts
                    let more = try channel.read(maxCount: 64, timeout: 0.03)
                    if more.isEmpty { break }
                    answer += more
                }
            }
            if parseBootInfo(answer) {
                log?("OK: " + bootMessage)
                return
            }
            log?("BOOTINFO WRONG")
        }
        throw BootloaderError.noConnection("NO_ANSWER")
    }

    /// FUN_005E5468: "<message><sigHi><sigLo><bootVersion><pages><ack 0x30…0x3F>".
    func parseBootInfo(_ b: [UInt8]) -> Bool {
        guard let i = b.lastIndex(where: { (0x30...0x3F).contains($0) }), i > 5 else { return false }
        lastAck = b[i]
        var end = i
        if b[i] & 8 == 8 && end >= 8 { end -= 4 }   // FLAG_Versioning: 4 version bytes
        bootPages = Int(b[end - 1])
        bootVersion = b[end - 2]
        signature = UInt16(b[end - 4]) << 8 | UInt16(b[end - 3])
        bootMessage = String(decoding: b[0..<(end - 4)].filter { $0 >= 0x20 && $0 < 0x7F }, as: UTF8.self)
        bootInfo = Array(b[0...i])
        return true
    }

    // MARK: commands

    public func setAddress(_ a: Int) throws {
        try send([Command.setAddress.rawValue, 0, UInt8((a >> 8) & 0xFF), UInt8(a & 0xFF)])
        try expectSuccess("CMD_SET_ADDRESS")
    }

    public func setBuffer(_ data: [UInt8]) throws {
        guard data.count <= bufferSize else { throw BootloaderError.bufferTooLarge(data.count, bufferSize) }
        try send([Command.setBuffer.rawValue, 0, UInt8(data.count >> 8), UInt8(data.count & 0xFF)])
        // no answer expected before the data
        let early = try channel.read(maxCount: 1, timeout: 0.02)
        if let a = early.first, a != BLHeliBootloader.noAnswer {
            lastAck = a
            throw BootloaderError.ack(a, "CMD_SET_BUFFER")
        }
        try send(data)
        try expectSuccess("CMD_SET_BUFFER", timeout: max(timeout, 1.0))
    }

    /// Reads `count` (≤ 256) bytes: data + CRC + ack.
    func readBuffer(_ cmd: Command, _ name: String, count: Int) throws -> [UInt8] {
        try send([cmd.rawValue, UInt8(count & 0xFF)])
        let r = try channel.readExactly(count + 3, timeout: max(timeout, 0.2) + Double(count) * 0.002)
        guard r.count == count + 3 else { lastAck = 0xC8; throw BootloaderError.ack(0xC8, name) }
        let data = Array(r[0..<count])
        let crc = UInt16(r[count]) | UInt16(r[count + 1]) << 8
        lastAck = r[count + 2]
        if crc != Checksum.crc16BLHeli(data) { lastAck = 0xCA; throw BootloaderError.ack(0xCA, name) }
        guard lastAck == BLHeliBootloader.success else { throw BootloaderError.ack(lastAck, name) }
        return data
    }

    public func readFlash(address: Int, count: Int, atmel: Bool) throws -> [UInt8] {
        var out: [UInt8] = []
        var a = address
        while out.count < count {
            let n = min(256, count - out.count)
            try setAddress(atmel ? a : a)
            out += try readBuffer(atmel ? .readFlashAtmel : .readFlashSiLabsOrVerify, atmel ? "CMD_READ_FLASH_ATM" : "CMD_READ_FLASH_SIL", count: n)
            a += n
        }
        return out
    }

    public func readEEprom(address: Int, count: Int) throws -> [UInt8] {
        var out: [UInt8] = []
        var a = address
        while out.count < count {
            let n = min(256, count - out.count)
            try setAddress(a)
            out += try readBuffer(.readEEprom, "CMD_READ_EEPROM", count: n)
            a += n
        }
        return out
    }

    func write(_ cmd: Command, _ name: String, address: Int, data: [UInt8], timeout t: TimeInterval) throws {
        try setAddress(address)
        try setBuffer(data)
        try send([cmd.rawValue, 0x01])
        try expectSuccess(name, timeout: t)
    }

    public func writeFlash(address: Int, data: [UInt8]) throws {
        try write(.progFlash, "CMD_PROG_FLASH", address: address, data: data, timeout: max(timeout, 0.5))
    }

    /// Atmel bootloaders compare the buffer with the flash (ERROR_VERIFY on a difference).
    public func verifyFlash(address: Int, data: [UInt8]) throws {
        try write(.readFlashSiLabsOrVerify, "CMD_VERIFY_FLASH", address: address, data: data, timeout: max(timeout, 0.5))
    }

    public func writeEEprom(address: Int, data: [UInt8]) throws {
        try write(.progEEprom, "CMD_PROG_EEPROM", address: address, data: data, timeout: max(timeout, 3.0))
    }

    public func erasePage(address: Int) throws {
        try setAddress(address)
        try send([Command.eraseFlash.rawValue, 0x01])
        try expectSuccess("CMD_ERASE_FLASH", timeout: max(timeout, 1.0))
    }

    /// The bootloader answers keep alive with ERROR_COMMAND.
    public func keepAlive() throws {
        try send([Command.keepAlive.rawValue, 0])
        let a = try ack("CMD_KEEP_ALIVE", timeout: 0.1)
        guard a == BLHeliBootloader.errorCommand else { throw BootloaderError.ack(a, "CMD_KEEP_ALIVE") }
    }

    /// Starts the application (CMD_RUN, no answer).
    public func run() {
        try? send([Command.run.rawValue, 0])
    }
}
