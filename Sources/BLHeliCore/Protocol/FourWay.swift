import Foundation

/// 4-way interface commands (BLHeliSuite 4w-if protocol V6/V106 + 0x40 verify from 107/108).
public enum FourWayCommand: UInt8, CustomStringConvertible, Sendable {
    case interfaceTestAlive = 0x30
    case protocolGetVersion = 0x31
    case interfaceGetName = 0x32
    case interfaceGetVersion = 0x33
    case interfaceExit = 0x34
    case deviceReset = 0x35
    case deviceGetID = 0x36
    case deviceInitFlash = 0x37
    case deviceEraseAll = 0x38
    case devicePageErase = 0x39
    case deviceRead = 0x3A
    case deviceWrite = 0x3B
    case deviceC2CKLow = 0x3C
    case deviceReadEEprom = 0x3D
    case deviceWriteEEprom = 0x3E
    case interfaceSetMode = 0x3F
    case deviceVerify = 0x40

    public var description: String {
        switch self {
        case .interfaceTestAlive: return "cmd_InterfaceTestAlive"
        case .protocolGetVersion: return "cmd_ProtocolGetVersion"
        case .interfaceGetName: return "cmd_InterfaceGetName"
        case .interfaceGetVersion: return "cmd_InterfaceGetVersion"
        case .interfaceExit: return "cmd_InterfaceExit"
        case .deviceReset: return "cmd_DeviceReset"
        case .deviceGetID: return "cmd_DeviceGetID"
        case .deviceInitFlash: return "cmd_DeviceInitFlash"
        case .deviceEraseAll: return "cmd_DeviceEraseAll"
        case .devicePageErase: return "cmd_DevicePageErase"
        case .deviceRead: return "cmd_DeviceRead"
        case .deviceWrite: return "cmd_DeviceWrite"
        case .deviceC2CKLow: return "cmd_DeviceC2CK_LOW"
        case .deviceReadEEprom: return "cmd_DeviceReadEEprom"
        case .deviceWriteEEprom: return "cmd_DeviceWriteEEprom"
        case .interfaceSetMode: return "cmd_InterfaceSetMode"
        case .deviceVerify: return "cmd_DeviceVerify"
        }
    }
}

public enum FourWayInterfaceMode: UInt8, Sendable, CustomStringConvertible {
    case siLabsC2 = 0, siLabsBLB = 1, atmelBLB = 2, atmelSK = 3, armBLB = 4

    public var description: String {
        switch self {
        case .siLabsC2: return "SiLabsC2"
        case .siLabsBLB: return "SiLabsBLB"
        case .atmelBLB: return "AtmelBLB"
        case .atmelSK: return "AtmelSK"
        case .armBLB: return "ArmBLB"
        }
    }

    public var family: MCUFamily {
        switch self {
        case .siLabsC2, .siLabsBLB: return .silabs
        case .atmelBLB, .atmelSK: return .atmel
        case .armBLB: return .arm
        }
    }
}

public enum FourWayAck: UInt8, Sendable {
    case ok = 0x00
    case unknownError = 0x01
    case invalidCommand = 0x02
    case invalidCRC = 0x03
    case verifyError = 0x04
    case deviceInvalidCommand = 0x05
    case deviceCommandFailed = 0x06
    case deviceUnknownError = 0x07
    case invalidChannel = 0x08
    case invalidParam = 0x09
    case deviceGeneralError = 0x0F

    public var text: String {
        switch self {
        case .ok: return "OK"
        case .unknownError: return "ACK_I_UNKNOWN_ERROR"
        case .invalidCommand: return "ACK_I_INVALID_CMD"
        case .invalidCRC: return "ACK_I_INVALID_CRC"
        case .verifyError: return "ACK_I_VERIFY_ERROR"
        case .deviceInvalidCommand: return "ACK_D_INVALID_COMMAND"
        case .deviceCommandFailed: return "ACK_D_COMMAND_FAILED"
        case .deviceUnknownError: return "ACK_D_UNKNOWN_ERROR"
        case .invalidChannel: return "ACK_I_INVALID_CHANNEL"
        case .invalidParam: return "ACK_I_INVALID_PARAM"
        case .deviceGeneralError: return "ACK_D_GENERAL_ERROR"
        }
    }
}

public enum FourWayError: Error, LocalizedError {
    case timeout(FourWayCommand)
    case nack(FourWayCommand, UInt8)
    case badCRC(FourWayCommand)
    case unexpectedLength(FourWayCommand, Int)

    public var errorDescription: String? {
        switch self {
        case .timeout(let c): return "No answer from the 4-way interface (\(c))."
        case .nack(let c, let a):
            return "\(c) failed: \(FourWayAck(rawValue: a)?.text ?? String(format: "error 0x%02X", a))"
        case .badCRC(let c): return "CRC error in answer to \(c)."
        case .unexpectedLength(let c, let n): return "Unexpected answer length \(n) for \(c)."
        }
    }

    public var ack: UInt8? {
        if case .nack(_, let a) = self { return a }
        return nil
    }
}

public struct FourWayResponse: Sendable {
    public let command: UInt8
    public let address: UInt16
    public let params: [UInt8]
    public let ack: UInt8
}

/// Client side of the 4-way interface protocol (Arduino 4w-if and Betaflight/Cleanflight
/// passthrough). Frame format and the retry behaviour follow TUniSerialInterface.
public final class FourWayClient {
    public let channel: ByteChannel
    public var defaultTimeout: TimeInterval = 2.0
    public var retries = 3

    public init(channel: ByteChannel) { self.channel = channel }

    public static func frame(_ cmd: UInt8, address: UInt16, params: [UInt8]) -> [UInt8] {
        precondition(!params.isEmpty && params.count <= 256)
        var f: [UInt8] = [0x2F, cmd, UInt8(address >> 8), UInt8(address & 0xFF), UInt8(params.count & 0xFF)]
        f += params
        let crc = Checksum.crc16XModem(f)
        f += [UInt8(crc >> 8), UInt8(crc & 0xFF)]
        return f
    }

    /// Sends a command and returns the decoded response (ACK must be OK).
    @discardableResult
    public func send(_ cmd: FourWayCommand, address: Int = 0, params: [UInt8] = [0], timeout: TimeInterval? = nil) throws -> FourWayResponse {
        let frame = FourWayClient.frame(cmd.rawValue, address: UInt16(truncatingIfNeeded: address), params: params)
        var lastError: Error = FourWayError.timeout(cmd)
        for attempt in 0...retries {
            if attempt > 0 { Log.debug("4way: send again #\(attempt) (\(cmd))") }
            channel.discardInput()
            Log.debug("4way > \(cmd) addr=\(hex4(address)) \(frame.count <= 24 ? frame.hexString : frame.prefix(12).hexString + " … (\(frame.count) bytes)")")
            try channel.write(frame)
            do {
                let r = try receive(cmd, timeout: timeout ?? defaultTimeout)
                if r.ack != FourWayAck.ok.rawValue {
                    // CRC errors seen by the interface are worth a retry, other NACKs are final.
                    if r.ack == FourWayAck.invalidCRC.rawValue { lastError = FourWayError.nack(cmd, r.ack); continue }
                    throw FourWayError.nack(cmd, r.ack)
                }
                return r
            } catch let e as FourWayError {
                switch e {
                case .timeout, .badCRC: lastError = e; continue
                default: throw e
                }
            }
        }
        throw lastError
    }

    func receive(_ cmd: FourWayCommand, timeout: TimeInterval) throws -> FourWayResponse {
        let deadline = monotonicNow() + timeout
        var buf: [UInt8] = []
        func need(_ n: Int) throws -> Bool {
            while buf.count < n {
                let left = deadline - monotonicNow()
                if left <= 0 { return false }
                buf += try channel.read(maxCount: 512, timeout: min(left, 0.25))
            }
            return true
        }
        while true {
            guard try need(1) else { throw FourWayError.timeout(cmd) }
            if let s = buf.firstIndex(of: 0x2E) {
                if s > 0 { buf.removeFirst(s) }
            } else {
                buf.removeAll()
                continue
            }
            guard try need(5) else { throw FourWayError.timeout(cmd) }
            let len = buf[4] == 0 ? 256 : Int(buf[4])
            guard try need(5 + len + 3) else { throw FourWayError.timeout(cmd) }
            let frame = Array(buf[0..<(5 + len + 3)])
            let crc = Checksum.crc16XModem(frame[0..<(5 + len + 1)])
            let got = UInt16(frame[5 + len + 1]) << 8 | UInt16(frame[5 + len + 2])
            if crc != got {
                // Could be a stray 0x2E inside garbage – resync one byte further.
                Log.debug("4way < CRC mismatch, resync")
                buf.removeFirst()
                if buf.isEmpty && monotonicNow() >= deadline { throw FourWayError.badCRC(cmd) }
                continue
            }
            buf.removeFirst(frame.count)
            let resp = FourWayResponse(command: frame[1], address: UInt16(frame[2]) << 8 | UInt16(frame[3]),
                                       params: Array(frame[5..<(5 + len)]), ack: frame[5 + len])
            Log.debug("4way < \(FourWayCommand(rawValue: resp.command)?.description ?? hex2(resp.command)) ack=\(hex2(resp.ack)) \(frame.count <= 24 ? frame.hexString : frame.prefix(12).hexString + " … (\(frame.count) bytes)")")
            if resp.command != cmd.rawValue { continue }
            return resp
        }
    }

    // MARK: Commands

    public func testAlive() throws {
        try send(.interfaceTestAlive, timeout: 1.0)
    }

    public func protocolVersion() throws -> UInt8 {
        try send(.protocolGetVersion).params.first ?? 0
    }

    public func interfaceName() throws -> String {
        let p = try send(.interfaceGetName).params
        return String(bytes: p.filter { $0 != 0 }, encoding: .isoLatin1) ?? "?"
    }

    public func interfaceVersion() throws -> UInt16 {
        let p = try send(.interfaceGetVersion).params
        return p.count >= 2 ? UInt16(p[0]) << 8 | UInt16(p[1]) : UInt16(p.first ?? 0)
    }

    public func exit() throws {
        try send(.interfaceExit, timeout: 1.0)
    }

    public func deviceReset(esc: Int) throws {
        try send(.deviceReset, params: [UInt8(esc)], timeout: 2.0)
    }

    public func initFlash(esc: Int) throws -> [UInt8] {
        let r = try send(.deviceInitFlash, params: [UInt8(esc)], timeout: 3.0)
        return r.params
    }

    public func eraseAll() throws {
        try send(.deviceEraseAll, timeout: 10.0)
    }

    public func pageErase(page: Int) throws {
        try send(.devicePageErase, params: [UInt8(page)], timeout: 3.0)
    }

    public func read(address: Int, count: Int) throws -> [UInt8] {
        precondition(count > 0 && count <= 256)
        let r = try send(.deviceRead, address: address, params: [UInt8(count & 0xFF)], timeout: 3.0)
        guard r.params.count == count else { throw FourWayError.unexpectedLength(.deviceRead, r.params.count) }
        return r.params
    }

    public func write(address: Int, data: [UInt8]) throws {
        try send(.deviceWrite, address: address, params: data, timeout: 3.0)
    }

    public func readEEPROM(address: Int, count: Int) throws -> [UInt8] {
        precondition(count > 0 && count <= 256)
        let r = try send(.deviceReadEEprom, address: address, params: [UInt8(count & 0xFF)], timeout: 3.0)
        guard r.params.count == count else { throw FourWayError.unexpectedLength(.deviceReadEEprom, r.params.count) }
        return r.params
    }

    public func writeEEPROM(address: Int, data: [UInt8]) throws {
        try send(.deviceWriteEEprom, address: address, params: data, timeout: 5.0)
    }

    public func setMode(_ mode: FourWayInterfaceMode) throws {
        try send(.interfaceSetMode, params: [mode.rawValue])
    }

    public func c2ckLow(esc: Int) throws {
        try send(.deviceC2CKLow, params: [UInt8(esc)])
    }
}
