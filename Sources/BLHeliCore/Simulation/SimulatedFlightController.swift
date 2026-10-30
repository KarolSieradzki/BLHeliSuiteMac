import Foundation

/// Emulates the host side of the protocols BLHeliSuite talks to:
///  * a Betaflight flight controller (MSP v1 + MSP_SET_4WAY_IF → 4-way, modelled on serial_4way.c)
///  * an Arduino 4w-if box (4-way only, switchable C2 / bootloader mode)
/// It serves a ByteChannel (normally the master side of a pseudo terminal).
public final class SimulatedFlightController {
    public enum Personality {
        case betaflight
        case arduinoBox(multi: Bool)
    }

    public let personality: Personality
    public var escs: [SimulatedESC]
    public var armed = false
    public var motorValues: [Int]
    public var protocolVersion: UInt8 = 108
    public var interfaceMode: FourWayInterfaceMode = .siLabsBLB
    /// Artificial per-command latency to mimic the 1-wire link (seconds).
    public var latency: TimeInterval = 0
    public private(set) var commandLog: [UInt8] = []

    private var in4Way: Bool
    private var selected = 0
    private var connectedESC = false
    private var buffer: [UInt8] = []
    private let channel: ByteChannel
    private var thread: Thread?
    private var running = false
    private let lock = NSLock()

    public init(channel: ByteChannel, personality: Personality, escs: [SimulatedESC]) {
        self.channel = channel
        self.personality = personality
        self.escs = escs
        self.motorValues = [Int](repeating: 1000, count: 8)
        if case .arduinoBox = personality { in4Way = true } else { in4Way = false }
    }

    public func start() {
        running = true
        let t = Thread { [weak self] in self?.run() }
        t.name = "SimulatedFlightController"
        thread = t
        t.start()
    }

    public func stop() { running = false }

    public var isIn4WayMode: Bool { lock.lock(); defer { lock.unlock() }; return in4Way }

    private func run() {
        while running {
            guard let chunk = try? channel.read(maxCount: 1024, timeout: 0.05) else { continue }
            if chunk.isEmpty { continue }
            buffer += chunk
            process()
        }
    }

    private func reply(_ bytes: [UInt8]) {
        if latency > 0 { sleepSeconds(latency) }
        try? channel.write(bytes)
    }

    private func process() {
        while !buffer.isEmpty {
            if isIn4WayMode {
                guard let start = buffer.firstIndex(of: 0x2F) else { buffer.removeAll(); return }
                if start > 0 { buffer.removeFirst(start) }
                if buffer.count < 5 { return }
                let len = buffer[4] == 0 ? 256 : Int(buffer[4])
                if buffer.count < 5 + len + 2 { return }
                let frame = Array(buffer[0..<(5 + len + 2)])
                buffer.removeFirst(frame.count)
                handle4Way(frame)
            } else {
                guard let start = buffer.firstIndex(of: 0x24) else { buffer.removeAll(); return }
                if start > 0 { buffer.removeFirst(start) }
                if buffer.count < 6 { return }
                guard buffer[1] == 0x4D, buffer[2] == 0x3C else { buffer.removeFirst(); continue }
                let len = Int(buffer[3])
                if buffer.count < 6 + len { return }
                let frame = Array(buffer[0..<(6 + len)])
                buffer.removeFirst(frame.count)
                handleMSP(frame)
            }
        }
    }

    // MARK: MSP

    private func mspReply(_ cmd: UInt8, _ payload: [UInt8], error: Bool = false) {
        var f: [UInt8] = [0x24, 0x4D, error ? 0x21 : 0x3E, UInt8(payload.count), cmd] + payload
        f.append(Checksum.xor([UInt8(payload.count), cmd] + payload))
        reply(f)
    }

    private func handleMSP(_ f: [UInt8]) {
        let len = Int(f[3]), cmd = f[4]
        let payload = Array(f[5..<(5 + len)])
        guard Checksum.xor([f[3], cmd] + payload) == f[5 + len] else { return }
        commandLog.append(cmd)
        switch cmd {
        case MSPCommand.apiVersion: mspReply(cmd, [0, 1, 45])
        case MSPCommand.fcVariant: mspReply(cmd, Array("BTFL".utf8))
        case MSPCommand.fcVersion: mspReply(cmd, [4, 4, 3])
        case MSPCommand.boardInfo:
            let name = Array("SIMULATOR".utf8)
            mspReply(cmd, Array("S405".utf8) + [0, 0, 2, 0, UInt8(name.count)] + name)
        case MSPCommand.buildInfo: mspReply(cmd, Array("Oct 14 2026".utf8) + Array("12:00:00".utf8) + Array("abcdef0".utf8))
        case MSPCommand.status:
            var p = [UInt8](repeating: 0, count: 11)
            if armed { p[6] = 1 }
            mspReply(cmd, p)
        case MSPCommand.motor:
            var p: [UInt8] = []
            for v in motorValues { p += [UInt8(v & 0xFF), UInt8(v >> 8)] }
            mspReply(cmd, p)
        case MSPCommand.motorConfig: mspReply(cmd, [0x2E, 0x04, 0xD0, 0x07, 0xE8, 0x03])
        case MSPCommand.setMotor:
            for i in 0..<min(8, payload.count / 2) { motorValues[i] = Int(payload[2 * i]) | Int(payload[2 * i + 1]) << 8 }
            mspReply(cmd, [])
        case MSPCommand.set4WayIf:
            if armed { mspReply(cmd, [], error: true); return }
            mspReply(cmd, [UInt8(escs.count)])
            lock.lock(); in4Way = true; lock.unlock()
            connectedESC = false
        default:
            mspReply(cmd, [], error: true)
        }
    }

    // MARK: 4-way (serial_4way.c behaviour)

    private func fourWayReply(_ cmd: UInt8, _ addr: UInt16, _ params: [UInt8], _ ack: FourWayAck) {
        let p = params.isEmpty ? [UInt8(0)] : params
        var f: [UInt8] = [0x2E, cmd, UInt8(addr >> 8), UInt8(addr & 0xFF), UInt8(p.count & 0xFF)] + p + [ack.rawValue]
        let crc = Checksum.crc16XModem(f)
        f += [UInt8(crc >> 8), UInt8(crc & 0xFF)]
        reply(f)
    }

    private var isBox: Bool { if case .arduinoBox = personality { return true }; return false }

    private var esc: SimulatedESC? { selected < escs.count ? escs[selected] : nil }

    private func handle4Way(_ f: [UInt8]) {
        let cmd = f[1]
        let addr = UInt16(f[2]) << 8 | UInt16(f[3])
        let len = f[4] == 0 ? 256 : Int(f[4])
        let params = Array(f[5..<(5 + len)])
        let crc = UInt16(f[5 + len]) << 8 | UInt16(f[6 + len])
        commandLog.append(cmd)
        if Checksum.crc16XModem(f[0..<(5 + len)]) != crc {
            fourWayReply(cmd, addr, [0], .invalidCRC); return
        }
        guard let c = FourWayCommand(rawValue: cmd) else { fourWayReply(cmd, addr, [0], .invalidCommand); return }
        let a = Int(addr)
        switch c {
        case .interfaceTestAlive:
            if connectedESC, let e = esc, !e.checkPower() { fourWayReply(cmd, addr, [0], .deviceGeneralError) }
            else { fourWayReply(cmd, addr, [0], .ok) }
        case .protocolGetVersion:
            fourWayReply(cmd, addr, [protocolVersion], .ok)
        case .interfaceGetName:
            let name: String
            switch personality {
            case .betaflight: name = "m4wFCIntf"
            case .arduinoBox(let multi): name = multi ? "m4wArduino" : "4wArduino"
            }
            fourWayReply(cmd, addr, Array(name.utf8), .ok)
        case .interfaceGetVersion:
            fourWayReply(cmd, addr, isBox ? [20, 5] : [200, 27], .ok)
        case .interfaceExit:
            fourWayReply(cmd, addr, [0], .ok)
            if !isBox { lock.lock(); in4Way = false; lock.unlock() }
            connectedESC = false
        case .interfaceSetMode:
            let m = params[0]
            if isBox {
                if m <= 3 { interfaceMode = FourWayInterfaceMode(rawValue: m)!; fourWayReply(cmd, addr, [m], .ok) }
                else { fourWayReply(cmd, addr, [m], .invalidParam) }
            } else if m >= 1 && m <= 4 {
                interfaceMode = FourWayInterfaceMode(rawValue: m)!
                fourWayReply(cmd, addr, [m], .ok)
            } else {
                fourWayReply(cmd, addr, [m], .invalidParam)
            }
        case .deviceReset:
            guard Int(params[0]) < escs.count else { fourWayReply(cmd, addr, params, .invalidChannel); return }
            selected = Int(params[0]); connectedESC = false
            fourWayReply(cmd, addr, params, .ok)
        case .deviceInitFlash:
            guard Int(params[0]) < max(escs.count, isBox ? 1 : 0) else { fourWayReply(cmd, addr, [0], .invalidChannel); return }
            selected = Int(params[0])
            guard let e = esc, e.checkPower() else { connectedESC = false; fourWayReply(cmd, addr, [0], .deviceGeneralError); return }
            connectedESC = true
            if interfaceMode == .siLabsC2 {
                guard e.family == .silabs else { fourWayReply(cmd, addr, [0], .deviceGeneralError); return }
                fourWayReply(cmd, addr, [e.mcu.c2DeviceID, e.mcu.c2DerivativeID, 0x03, 0], .ok)
            } else {
                let mode: FourWayInterfaceMode = e.family == .silabs ? .siLabsBLB : .atmelBLB
                if !isBox { interfaceMode = mode }
                let sig = e.mcu.bootSignature
                fourWayReply(cmd, addr, [UInt8(sig & 0xFF), UInt8(sig >> 8), e.bootVersion, mode.rawValue], .ok)
            }
        case .deviceEraseAll:
            guard interfaceMode == .siLabsC2, let e = esc else { fourWayReply(cmd, addr, [0], .invalidCommand); return }
            fourWayReply(cmd, addr, [0], e.c2EraseAll() ? .ok : .deviceGeneralError)
        case .devicePageErase:
            guard let e = esc, connectedESC else { fourWayReply(cmd, addr, params, .deviceGeneralError); return }
            switch interfaceMode {
            case .siLabsBLB: fourWayReply(cmd, addr, params, e.blErasePage(Int(params[0])) ? .ok : .deviceGeneralError)
            case .siLabsC2: fourWayReply(cmd, addr, params, e.c2ErasePage(Int(params[0])) ? .ok : .deviceGeneralError)
            default: fourWayReply(cmd, addr, params, .invalidCommand)
            }
        case .deviceRead:
            guard let e = esc, connectedESC else { fourWayReply(cmd, addr, [0], .deviceGeneralError); return }
            let n = params[0] == 0 ? 256 : Int(params[0])
            if let d = e.blRead(a, n) { fourWayReply(cmd, addr, d, .ok) } else { fourWayReply(cmd, addr, [0], .deviceGeneralError) }
        case .deviceWrite:
            guard let e = esc, connectedESC else { fourWayReply(cmd, addr, [0], .deviceGeneralError); return }
            let ok = interfaceMode == .siLabsC2 ? e.c2Write(a, params) : e.blWrite(a, params)
            fourWayReply(cmd, addr, [0], ok ? .ok : .deviceGeneralError)
        case .deviceReadEEprom:
            guard let e = esc, connectedESC, e.family == .atmel else { fourWayReply(cmd, addr, [0], .invalidCommand); return }
            let n = params[0] == 0 ? 256 : Int(params[0])
            if let d = e.eepromRead(a, n) { fourWayReply(cmd, addr, d, .ok) } else { fourWayReply(cmd, addr, [0], .deviceGeneralError) }
        case .deviceWriteEEprom:
            guard let e = esc, connectedESC, e.family == .atmel else { fourWayReply(cmd, addr, [0], .invalidCommand); return }
            fourWayReply(cmd, addr, [0], e.eepromWrite(a, params) ? .ok : .deviceGeneralError)
        case .deviceC2CKLow, .deviceGetID, .deviceVerify:
            fourWayReply(cmd, addr, [0], .invalidCommand)
        }
    }
}
