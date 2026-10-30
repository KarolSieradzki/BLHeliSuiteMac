import Foundation

/// Interface selection – mirrors the "Select ATMEL / SILABS Interface" menu of BLHeliSuite.
public enum InterfaceType: String, CaseIterable, Codable, Identifiable, Sendable {
    case silabsC2Toolstick = "A"
    case silabsC2FourWay = "B"
    case silabsBLBFourWay = "D"
    case silabsBLBFlightController = "E"
    case atmelBLBFourWay = "2"
    case atmelSKFourWay = "3"
    case atmelFlightController = "6"
    case atmelISP = "X"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .silabsC2Toolstick: return "SILABS C2 (Toolstick)"
        case .silabsC2FourWay: return "SILABS C2 (4way-if)"
        case .silabsBLBFourWay: return "SILABS BLHeli Bootloader (4way-if)"
        case .silabsBLBFlightController: return "SILABS BLHeli Bootloader (Betaflight/Cleanflight)"
        case .atmelBLBFourWay: return "ATMEL BLHeli Bootloader (4way-if)"
        case .atmelSKFourWay: return "ATMEL SK Bootloader (4way-if)"
        case .atmelFlightController: return "ATMEL BLHeli/SK Bootloader (Betaflight/Cleanflight)"
        case .atmelISP: return "ATMEL ISP Interface (AVRDude / USBasp)"
        }
    }

    public var family: MCUFamily {
        switch self {
        case .silabsC2Toolstick, .silabsC2FourWay, .silabsBLBFourWay, .silabsBLBFlightController: return .silabs
        default: return .atmel
        }
    }

    public var usesSerialPort: Bool { self != .silabsC2Toolstick && self != .atmelISP }
    public var isFlightController: Bool { self == .silabsBLBFlightController || self == .atmelFlightController }

    public var defaultBaud: Int { isFlightController ? 115200 : 38400 }

    public var fourWayMode: FourWayInterfaceMode {
        switch self {
        case .silabsC2Toolstick, .silabsC2FourWay: return .siLabsC2
        case .silabsBLBFourWay, .silabsBLBFlightController: return .siLabsBLB
        case .atmelBLBFourWay, .atmelFlightController, .atmelISP: return .atmelBLB
        case .atmelSKFourWay: return .atmelSK
        }
    }
}

/// Opens a programmer for a serial based interface.
public enum ProgrammerFactory {
    public static func openSerial(_ type: InterfaceType, portPath: String, baud: Int, arduinoResetDelay: TimeInterval = 2.0,
                                  checkArmed: Bool = true) throws -> FourWayProgrammer {
        let port = SerialPort(path: portPath)
        try port.open(baudRate: baud)
        do {
            if type.isFlightController {
                return try FourWayProgrammer.connectFlightController(channel: port, family: type.family, checkArmed: checkArmed)
            }
            return try FourWayProgrammer.connectBox(channel: port, mode: type.fourWayMode, resetDelay: arduinoResetDelay)
        } catch {
            port.close()
            throw error
        }
    }
}
