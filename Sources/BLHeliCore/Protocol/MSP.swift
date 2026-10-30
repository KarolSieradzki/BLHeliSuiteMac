import Foundation

public enum MSPError: Error, LocalizedError {
    case timeout(UInt8)
    case errorResponse(UInt8)
    case badChecksum(UInt8)

    public var errorDescription: String? {
        switch self {
        case .timeout(let c): return "Flight controller did not answer MSP command \(c)."
        case .errorResponse(let c): return "Flight controller rejected MSP command \(c)."
        case .badChecksum(let c): return "MSP checksum error (command \(c))."
        }
    }
}

public enum MSPCommand {
    public static let apiVersion: UInt8 = 1
    public static let fcVariant: UInt8 = 2
    public static let fcVersion: UInt8 = 3
    public static let boardInfo: UInt8 = 4
    public static let buildInfo: UInt8 = 5
    public static let feature: UInt8 = 36
    public static let reboot: UInt8 = 68
    public static let status: UInt8 = 101
    public static let motor: UInt8 = 104
    public static let motorConfig: UInt8 = 131
    public static let setMotor: UInt8 = 214
    public static let set1Wire: UInt8 = 243
    public static let set4WayIf: UInt8 = 245
}

public struct FlightControllerInfo: Sendable {
    public var apiVersion: String = "?"
    public var apiMajor = 0
    public var apiMinor = 0
    public var variant: String = "?"
    public var version: String = "?"
    public var boardIdentifier: String = "?"
    public var targetName: String = ""
    public var buildDate: String = ""
    public var armed = false
    public var motorCount = 0
    public var motorValues: [Int] = []

    public var description: String {
        var s = "\(variant) \(version) (API \(apiVersion)) on \(boardIdentifier)"
        if !targetName.isEmpty { s += " / \(targetName)" }
        return s
    }
}

/// MSP v1 client (the subset BLHeliSuite uses: identification, motor check, motor test,
/// and MSP_SET_4WAY_IF to switch the flight controller into 4-way passthrough mode).
public final class MSPClient {
    public let channel: ByteChannel

    public init(channel: ByteChannel) { self.channel = channel }

    public func send(_ cmd: UInt8, payload: [UInt8] = []) throws {
        var frame: [UInt8] = [0x24, 0x4D, 0x3C, UInt8(payload.count), cmd]
        frame += payload
        frame.append(Checksum.xor([UInt8(payload.count), cmd] + payload))
        Log.debug("MSP > \(frame.hexString)")
        try channel.write(frame)
    }

    public func request(_ cmd: UInt8, payload: [UInt8] = [], timeout: TimeInterval = 1.0) throws -> [UInt8] {
        try send(cmd, payload: payload)
        return try receive(cmd, timeout: timeout)
    }

    public func receive(_ cmd: UInt8, timeout: TimeInterval) throws -> [UInt8] {
        let deadline = monotonicNow() + timeout
        var buf: [UInt8] = []
        while monotonicNow() < deadline {
            buf += try channel.read(maxCount: 512, timeout: min(0.05, max(0.001, deadline - monotonicNow())))
            // scan for a complete frame
            while let start = buf.firstIndex(of: 0x24) {
                if start > 0 { buf.removeFirst(start) }
                if buf.count < 5 { break }
                guard buf[1] == 0x4D, buf[2] == 0x3E || buf[2] == 0x21 else { buf.removeFirst(); continue }
                let len = Int(buf[3])
                if buf.count < 6 + len { break }
                let frame = Array(buf[0..<(6 + len)])
                buf.removeFirst(6 + len)
                let rcmd = frame[4]
                let payload = Array(frame[5..<(5 + len)])
                Log.debug("MSP < \(frame.hexString)")
                if Checksum.xor([frame[3], rcmd] + payload) != frame[5 + len] { throw MSPError.badChecksum(rcmd) }
                if rcmd != cmd { continue }
                if frame[2] == 0x21 { throw MSPError.errorResponse(cmd) }
                return payload
            }
        }
        throw MSPError.timeout(cmd)
    }

    // MARK: Identification

    public func identify() throws -> FlightControllerInfo {
        var info = FlightControllerInfo()
        let api = try request(MSPCommand.apiVersion)
        if api.count >= 3 {
            info.apiMajor = Int(api[1]); info.apiMinor = Int(api[2])
            info.apiVersion = "\(api[1]).\(api[2])"
        }
        if let v = try? request(MSPCommand.fcVariant), v.count >= 4 {
            info.variant = String(bytes: v.prefix(4), encoding: .ascii) ?? "?"
            switch info.variant {
            case "BTFL": info.variant = "Betaflight"
            case "CLFL": info.variant = "Cleanflight"
            case "INAV": info.variant = "INAV"
            case "EMUF": info.variant = "EmuFlight"
            case "MWII": info.variant = "MultiWii"
            case "BAFL": info.variant = "Baseflight"
            default: break
            }
        }
        if let v = try? request(MSPCommand.fcVersion), v.count >= 3 {
            info.version = "\(v[0]).\(v[1]).\(v[2])"
        }
        if let b = try? request(MSPCommand.boardInfo), b.count >= 4 {
            info.boardIdentifier = String(bytes: b.prefix(4), encoding: .ascii) ?? "?"
            // Betaflight 4.x: ... targetNameLength at offset 9 (after hwRev(2), type(1), caps(1)) – best effort
            if b.count > 9 {
                var p = 4 + 2 + 1 + 1
                if p < b.count {
                    let n = Int(b[p]); p += 1
                    if p + n <= b.count { info.targetName = String(bytes: b[p..<(p + n)], encoding: .ascii) ?? "" }
                }
            }
        }
        if let b = try? request(MSPCommand.buildInfo), b.count >= 19 {
            info.buildDate = String(bytes: b.prefix(19), encoding: .ascii) ?? ""
        }
        return info
    }

    /// MSP_STATUS flag bit 0 (ARM) – only meaningful for Betaflight/Cleanflight.
    public func isArmed() throws -> Bool {
        let s = try request(MSPCommand.status)
        guard s.count >= 10 else { return false }
        let flags = UInt32(s[6]) | UInt32(s[7]) << 8 | UInt32(s[8]) << 16 | UInt32(s[9]) << 24
        return flags & 1 != 0
    }

    public func motorValues() throws -> [Int] {
        let m = try request(MSPCommand.motor)
        return stride(from: 0, to: m.count - 1, by: 2).map { Int(m[$0]) | Int(m[$0 + 1]) << 8 }
    }

    public func setMotors(_ values: [Int]) throws {
        var payload: [UInt8] = []
        for i in 0..<8 {
            let v = i < values.count ? values[i] : 0
            payload += [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]
        }
        _ = try request(MSPCommand.setMotor, payload: payload, timeout: 0.5)
    }

    /// MSP_MOTOR_CONFIG: (minthrottle, maxthrottle, mincommand)
    public func motorConfig() throws -> (min: Int, max: Int, command: Int) {
        let m = try request(MSPCommand.motorConfig)
        guard m.count >= 6 else { return (1070, 2000, 1000) }
        return (Int(m[0]) | Int(m[1]) << 8, Int(m[2]) | Int(m[3]) << 8, Int(m[4]) | Int(m[5]) << 8)
    }

    /// Switches the FC to the 4-way interface. Returns the number of ESCs the FC can address.
    public func enter4Way() throws -> Int {
        let r = try request(MSPCommand.set4WayIf, timeout: 2.0)
        return r.first.map(Int.init) ?? 0
    }
}
