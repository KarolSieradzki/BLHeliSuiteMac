import Foundation

public typealias ProgressHandler = (_ done: Int, _ total: Int) -> Void

public enum ProgrammerError: Error, LocalizedError {
    case notSupported(String)
    case escNotFound(Int)
    case cancelled
    case verifyFailed(address: Int)
    case unknownDevice(String)
    case lockedDevice

    public var errorDescription: String? {
        switch self {
        case .notSupported(let s): return s
        case .escNotFound(let i): return "No ESC answered on channel \(i + 1). Check the ESC power and signal connection."
        case .cancelled: return "Operation cancelled."
        case .verifyFailed(let a): return String(format: "Flash verify failed at address 0x%04X.", a)
        case .unknownDevice(let s): return "Unknown target device: \(s)"
        case .lockedDevice: return "You cannot flash locked ESC with current bootloader interface."
        }
    }
}

/// What InitFlash told us about the target MCU.
public struct DeviceInfo: Equatable, Sendable {
    public var interfaceMode: FourWayInterfaceMode
    public var mcu: MCUInfo?
    /// Signature word (bootloader modes) or C2 device/derivative (C2 mode).
    public var signature: UInt16
    /// Last char of the bootloader message "471x" (bootloader modes) or C2 line state.
    public var bootInfo: UInt8
    public var raw: [UInt8]
    /// Direct ISP access (avrdude) – full memory access, no bootloader involved.
    public var isISP = false

    public var family: MCUFamily { mcu?.family ?? interfaceMode.family }

    public var pageSize: Int { mcu?.pageSize ?? (family == .silabs ? 0x200 : 0x40) }
    public var eepromSize: Int { mcu?.eepromSize ?? 0x200 }
    public var flashSize: Int { mcu?.flashSize ?? (family == .silabs ? 0x2000 : 0x2000) }

    /// Flash range usable for firmware (TUniSerialInterface.FUN_005e29cc).
    public var userFlashSize: Int {
        switch interfaceMode {
        case .siLabsC2: return flashSize
        case .siLabsBLB: return 0x1C00
        case .atmelBLB: return flashSize - 0x200
        case .atmelSK: return flashSize - 0x400
        case .armBLB: return flashSize
        }
    }

    /// Atmel BLHeli bootloaders before "471c" cannot read flash (FUN_005e2844).
    public var canReadFlash: Bool {
        interfaceMode != .atmelBLB || bootInfo > 0x62
    }

    public var c2LinesOK: Bool { bootInfo & 3 == 3 }

    public var description: String {
        let name = mcu?.name ?? String(format: "0x%04X", signature)
        return "\(name) [\(isISP ? "ISP" : interfaceMode.description)]"
    }

    /// Decodes the 4 parameter bytes of a cmd_DeviceInitFlash answer.
    public static func fromInitFlash(_ p: [UInt8]) -> DeviceInfo {
        let b0 = p.count > 0 ? p[0] : 0, b1 = p.count > 1 ? p[1] : 0, b2 = p.count > 2 ? p[2] : 0
        let mode = FourWayInterfaceMode(rawValue: p.count > 3 ? p[3] : 1) ?? .siLabsBLB
        if mode == .siLabsC2 {
            // C2: DeviceID, DerivativeID, LineState
            let mcu = MCUTable.bySiLabsC2(deviceID: b0, derivativeID: b1)
            return DeviceInfo(interfaceMode: mode, mcu: mcu, signature: UInt16(b0) << 8 | UInt16(b1), bootInfo: b2, raw: p)
        }
        // Bootloader: bytes[0] = signature low, bytes[1] = signature high (Betaflight BL_ConnectEx)
        let sig = UInt16(b1) << 8 | UInt16(b0)
        var mcu = MCUTable.byBootSignature(sig)
        if mcu == nil {
            // Some interfaces report the signature high byte first.
            let swapped = UInt16(b0) << 8 | UInt16(b1)
            if let m = MCUTable.byBootSignature(swapped) { mcu = m; return DeviceInfo(interfaceMode: mode, mcu: m, signature: swapped, bootInfo: b2, raw: p) }
        }
        return DeviceInfo(interfaceMode: mode, mcu: mcu, signature: sig, bootInfo: b2, raw: p)
    }
}

/// Common interface of all programming paths (4-way via FC or Arduino, Toolstick C2, ISP).
public protocol ESCProgrammer: AnyObject {
    var interfaceName: String { get }
    /// Number of addressable ESC channels (1 for single ESC interfaces).
    var escCount: Int { get }
    var isConnected: Bool { get }
    var cancelRequested: Bool { get set }

    func selectESC(_ index: Int) throws -> DeviceInfo
    func readFlash(address: Int, count: Int, progress: ProgressHandler?) throws -> [UInt8]
    func writeFlash(address: Int, data: [UInt8], progress: ProgressHandler?) throws
    func erasePage(address: Int) throws
    func eraseChip() throws
    func readEEPROM(address: Int, count: Int) throws -> [UInt8]
    func writeEEPROM(address: Int, data: [UInt8], progress: ProgressHandler?) throws
    func resetESC(_ index: Int) throws
    func keepAlive() throws
    func disconnect()
}

public extension ESCProgrammer {
    func checkCancel() throws {
        if cancelRequested { cancelRequested = false; throw ProgrammerError.cancelled }
    }
}
