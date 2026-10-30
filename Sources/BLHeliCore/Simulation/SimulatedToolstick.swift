import Foundation

/// ToolStick base adapter model speaking the SiUtil C2 command set, for tests.
public final class SimulatedToolstick: ToolstickTransport {
    public let esc: SimulatedESC
    private var pending: [[UInt8]] = []
    private var connected = false
    public var firmwareVersion: UInt8 = 0x12

    public init(esc: SimulatedESC) { self.esc = esc }

    func reply(_ payload: [UInt8]) {
        var report = [UInt8](repeating: 0, count: 64)
        report[0] = UInt8(payload.count)
        for (i, b) in payload.prefix(63).enumerated() { report[1 + i] = b }
        pending.append(report)
    }

    public func write(_ data: [UInt8]) throws {
        guard let cmd = data.first else { return }
        let ok: UInt8 = 0x0D, fail: UInt8 = 0x02
        switch cmd {
        case 0x40: reply([ok])
        case 0x20: connected = esc.responding; reply([connected ? ok : fail])
        case 0x21: connected = false; reply([ok])
        case 0x22: reply([esc.mcu.c2DeviceID, 0x01])
        case 0x23: reply([esc.mcu.c2DerivativeID, 0x00])
        case 0x2E:
            let a = Int(data[1]) | Int(data[2]) << 8, n = Int(data[3])
            guard connected, n <= 60, a + n <= esc.flash.count else { reply([fail]); return }
            reply(Array(esc.flash[a..<(a + n)]) + [ok])
        case 0x2F:
            let a = Int(data[1]) | Int(data[2]) << 8, n = Int(data[3])
            guard connected, n <= 60, data.count == 4 + n else { reply([fail]); return }
            reply([esc.c2Write(a, Array(data[4...])) ? ok : fail])
        case 0x30: reply([connected && esc.c2ErasePage(Int(data[1])) ? ok : fail])
        case 0x3C: reply([connected && esc.c2EraseAll() ? ok : fail])
        default: reply([0x57])
        }
    }

    public func read(timeout: TimeInterval) throws -> [UInt8] {
        guard !pending.isEmpty else { throw ToolstickError.transferFailed("timeout") }
        return Array(pending.removeFirst().dropFirst())
    }

    public func discardInput() { pending.removeAll() }
    public func setFeature(_ id: UInt8, _ value: UInt8) throws {}
    public func getFeature(_ id: UInt8) throws -> UInt8 {
        switch id {
        case 0x43: return 1
        case 0x42: return 1
        case 0x44: return firmwareVersion
        default: return 0
        }
    }
    public func close() {}
}
