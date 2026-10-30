import Foundation

public enum MCUFamily: Int, Codable, Sendable {
    case unknown = 0
    case silabs = 1
    case atmel = 2
    case arm = 3

    public var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .silabs: return "SiLabs"
        case .atmel: return "Atmel"
        case .arm: return "ARM"
        }
    }
}

/// MCU description. Values come from the device table of BLHeliSuite (TDeviceInfo list at
/// 0x68D100 and the SiLabs C2 table in FUN_005a2184).
public struct MCUInfo: Equatable, Sendable {
    public let name: String
    public let family: MCUFamily
    /// 2-byte signature reported by the BLHeli bootloader (e.g. 0xF330, 0xE8B2, 0x9307).
    public let bootSignature: UInt16
    /// Full AVR signature (0x1E9307) or C2 device/derivative id (0x0A60) for SiLabs.
    public let signature: UInt32
    public let flashSize: Int
    public let eepromSize: Int
    public let pageSize: Int
    /// MCU code used by the firmware database (C2 device id for SiLabs, AVR signature for Atmel).
    public var databaseCode: Int {
        switch family {
        case .silabs: return Int(signature >> 8)
        case .atmel: return Int(signature)
        default: return Int(signature)
        }
    }

    public var c2DeviceID: UInt8 { UInt8((signature >> 8) & 0xFF) }
    public var c2DerivativeID: UInt8 { UInt8(signature & 0xFF) }
}

public enum MCUTable {
    public static let all: [MCUInfo] = [
        // SiLabs / EFM8 (bootloader signature -> C2 device + derivative id)
        MCUInfo(name: "C8051F310", family: .silabs, bootSignature: 0xF310, signature: 0x0850, flashSize: 0x4000, eepromSize: 0, pageSize: 0x200),
        MCUInfo(name: "C8051F330", family: .silabs, bootSignature: 0xF330, signature: 0x0A60, flashSize: 0x2000, eepromSize: 0, pageSize: 0x200),
        MCUInfo(name: "C8051F390", family: .silabs, bootSignature: 0xF390, signature: 0x2BD0, flashSize: 0x4000, eepromSize: 0, pageSize: 0x200),
        MCUInfo(name: "C8051F410", family: .silabs, bootSignature: 0xF410, signature: 0x0C67, flashSize: 0x8000, eepromSize: 0, pageSize: 0x200),
        MCUInfo(name: "C8051F850", family: .silabs, bootSignature: 0xF850, signature: 0x30F0, flashSize: 0x2000, eepromSize: 0, pageSize: 0x200),
        MCUInfo(name: "C8051F853", family: .silabs, bootSignature: 0xF853, signature: 0x30F3, flashSize: 0x2000, eepromSize: 0, pageSize: 0x200),
        MCUInfo(name: "C8051F860", family: .silabs, bootSignature: 0xF860, signature: 0x30E0, flashSize: 0x2000, eepromSize: 0, pageSize: 0x200),
        MCUInfo(name: "C8051F863", family: .silabs, bootSignature: 0xF863, signature: 0x30E3, flashSize: 0x2000, eepromSize: 0, pageSize: 0x200),
        MCUInfo(name: "EFM8BB10F8G", family: .silabs, bootSignature: 0xE8B1, signature: 0x3001, flashSize: 0x2000, eepromSize: 0, pageSize: 0x200),
        MCUInfo(name: "EFM8BB21F16G", family: .silabs, bootSignature: 0xE8B2, signature: 0x3201, flashSize: 0x4000, eepromSize: 0, pageSize: 0x200),
        // Atmel AVR
        MCUInfo(name: "ATmega8", family: .atmel, bootSignature: 0x9307, signature: 0x1E9307, flashSize: 0x2000, eepromSize: 0x200, pageSize: 0x40),
        MCUInfo(name: "ATmega88", family: .atmel, bootSignature: 0x930A, signature: 0x1E930A, flashSize: 0x2000, eepromSize: 0x200, pageSize: 0x40),
        MCUInfo(name: "ATmega88PA", family: .atmel, bootSignature: 0x930F, signature: 0x1E930F, flashSize: 0x2000, eepromSize: 0x200, pageSize: 0x40),
        MCUInfo(name: "ATmega168", family: .atmel, bootSignature: 0x9406, signature: 0x1E9406, flashSize: 0x4000, eepromSize: 0x200, pageSize: 0x80),
        MCUInfo(name: "ATmega168PA", family: .atmel, bootSignature: 0x940B, signature: 0x1E940B, flashSize: 0x4000, eepromSize: 0x200, pageSize: 0x80),
        MCUInfo(name: "ATmega328P", family: .atmel, bootSignature: 0x950F, signature: 0x1E950F, flashSize: 0x8000, eepromSize: 0x400, pageSize: 0x80),
        MCUInfo(name: "ATmega328", family: .atmel, bootSignature: 0x9514, signature: 0x1E9514, flashSize: 0x8000, eepromSize: 0x400, pageSize: 0x80),
        MCUInfo(name: "ATmega48P", family: .atmel, bootSignature: 0x920A, signature: 0x1E920A, flashSize: 0x1000, eepromSize: 0x100, pageSize: 0x40),
        // ARM (BLHeli_32 / AM32) – detected only to warn the user.
        MCUInfo(name: "STM32F031x6", family: .arm, bootSignature: 0x1F06, signature: 0x1F06, flashSize: 0x8000, eepromSize: 0, pageSize: 0x400),
        MCUInfo(name: "STM32F051x6", family: .arm, bootSignature: 0x3306, signature: 0x3306, flashSize: 0x8000, eepromSize: 0, pageSize: 0x400),
        MCUInfo(name: "GD32F150x6", family: .arm, bootSignature: 0x3406, signature: 0x3406, flashSize: 0x8000, eepromSize: 0, pageSize: 0x400),
        MCUInfo(name: "GD32F350x6", family: .arm, bootSignature: 0x3506, signature: 0x3506, flashSize: 0x8000, eepromSize: 0, pageSize: 0x400),
    ]

    public static func byBootSignature(_ sig: UInt16) -> MCUInfo? {
        all.first { $0.bootSignature == sig }
    }

    public static func byAVRSignature(_ sig: UInt32) -> MCUInfo? {
        all.first { $0.family == .atmel && $0.signature == sig }
    }

    /// SiLabs device from C2 device id / derivative id (FUN_005a2184 equivalent, reduced to
    /// the parts BLHeli runs on).
    public static func bySiLabsC2(deviceID: UInt8, derivativeID: UInt8) -> MCUInfo? {
        if let exact = all.first(where: { $0.family == .silabs && $0.c2DeviceID == deviceID && $0.c2DerivativeID == derivativeID }) {
            return exact
        }
        switch deviceID {
        case 0x08: return MCUInfo(name: "C8051F31x", family: .silabs, bootSignature: 0xF310, signature: UInt32(deviceID) << 8 | UInt32(derivativeID), flashSize: 0x4000, eepromSize: 0, pageSize: 0x200)
        case 0x0A: return MCUInfo(name: "C8051F33x", family: .silabs, bootSignature: 0xF330, signature: UInt32(deviceID) << 8 | UInt32(derivativeID), flashSize: 0x2000, eepromSize: 0, pageSize: 0x200)
        case 0x0C: return MCUInfo(name: "C8051F41x", family: .silabs, bootSignature: 0xF410, signature: UInt32(deviceID) << 8 | UInt32(derivativeID), flashSize: 0x8000, eepromSize: 0, pageSize: 0x200)
        case 0x2B: return MCUInfo(name: "C8051F39x", family: .silabs, bootSignature: 0xF390, signature: UInt32(deviceID) << 8 | UInt32(derivativeID), flashSize: 0x4000, eepromSize: 0, pageSize: 0x200)
        case 0x30:
            if derivativeID < 0xD0 {
                let flash = derivativeID == 5 ? 0x1000 : (derivativeID == 8 ? 0x800 : 0x2000)
                return MCUInfo(name: "EFM8BB10Fx", family: .silabs, bootSignature: 0xE8B1, signature: 0x3000 | UInt32(derivativeID), flashSize: flash, eepromSize: 0, pageSize: 0x200)
            }
            return MCUInfo(name: "C8051F85x/86x", family: .silabs, bootSignature: 0xF850, signature: 0x3000 | UInt32(derivativeID), flashSize: 0x2000, eepromSize: 0, pageSize: 0x200)
        case 0x32: return MCUInfo(name: "EFM8BB2x", family: .silabs, bootSignature: 0xE8B2, signature: 0x3200 | UInt32(derivativeID), flashSize: 0x4000, eepromSize: 0, pageSize: 0x200)
        default: return nil
        }
    }

    /// MCU code used in the firmware database for an MCU type string stored in the BLHeli
    /// EEPROM ("#BLHELI$EFM8B21#"), FUN_005a6b88.
    public static func databaseCode(forEepromMCU mcu: String) -> (family: MCUFamily, code: Int)? {
        switch mcu {
        case "F330": return (.silabs, 0x0A)
        case "F310": return (.silabs, 0x08)
        case "F390": return (.silabs, 0x2B)
        case "F850", "EFM8B10": return (.silabs, 0x30)
        case "EFM8B21": return (.silabs, 0x32)
        case "Am8A", "Am8L": return (.atmel, 0x1E9307)
        case "Am168": return (.atmel, 0x1E9406)
        case "Am168PA": return (.atmel, 0x1E940B)
        default: return nil
        }
    }
}
