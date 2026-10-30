import Foundation

public enum SettingsError: Error, LocalizedError {
    case tooShort
    case mcuIDError(String)
    case layoutRevisionError(Int)
    case outdatedRevision(String)
    case unsupportedRevision(String)
    case unknownLayout(String)
    case invalidMode

    public var errorDescription: String? {
        switch self {
        case .tooShort: return "ESC setup data too short."
        case .mcuIDError(let s): return "MCU ID error!\n\"\(s)\"\n\nUnflashed, erased or invalid ESC type?"
        case .layoutRevisionError(let r): return "Firmware EEProm layout error!\n(Found Rev.\(r))\nUnflashed, erased or invalid ESC type?"
        case .outdatedRevision(let r): return "BLHeli firmware revision \(r) is outdated and not supported."
        case .unsupportedRevision(let r): return "BLHeli firmware revision \(r) is newer than supported by this program."
        case .unknownLayout(let s): return "ESC layout \"\(s)\" is unknown."
        case .invalidMode: return "Invalid ESC mode (Eep_Initialized_L/H)."
        }
    }
}

/// The 0x70 byte BLHeli EEPROM block (SiLabs: flash 0x1A00, Atmel: EEPROM 0x0000).
public struct BLHeliSettings: Equatable, Sendable {
    public static let size = 0x70
    public static let silabsAddress = 0x1A00

    public var raw: [UInt8]

    public init(raw: [UInt8]) {
        var r = Array(raw.prefix(BLHeliSettings.size))
        while r.count < BLHeliSettings.size { r.append(0xFF) }
        self.raw = r
    }

    public subscript(_ p: BLHeliParam) -> UInt8 {
        get { p.eepromOffset >= 0 && p.eepromOffset < 0x40 ? raw[p.eepromOffset] : 0xFF }
        set { if p.eepromOffset >= 0 && p.eepromOffset < 0x40 { raw[p.eepromOffset] = newValue } }
    }

    public var mainRevision: UInt8 { raw[0] }
    public var subRevision: UInt8 { raw[1] }
    public var layoutRevision: UInt8 { raw[2] }

    /// FUN_005a5734
    public var revision: Int {
        let main = Int(raw[0]), sub = Int(raw[1])
        return sub < 10 ? main * 100 + sub * 10 : main * 100 + sub
    }

    public var revisionString: String { "\(raw[0]).\(raw[1])" }

    public var mode: ESCMode { ESCMode(initL: raw[0x0D], initH: raw[0x0E]) }

    private static func text(_ bytes: ArraySlice<UInt8>) -> String {
        let mapped = bytes.map { ($0 == 0xFF || $0 == 0) ? UInt8(0x20) : $0 }
        return (String(bytes: mapped, encoding: .isoLatin1) ?? "").trimmingCharacters(in: .whitespaces)
    }

    /// Eep_ESC_Layout with "#" removed ("#A_H_30#" -> "A_H_30").
    public var layoutName: String {
        BLHeliSettings.text(raw[0x40..<0x50]).replacingOccurrences(of: "#", with: " ").trimmingCharacters(in: .whitespaces)
    }

    public var rawLayoutString: String { BLHeliSettings.text(raw[0x40..<0x50]) }
    public var mcuString: String { BLHeliSettings.text(raw[0x50..<0x60]) }

    public var name: String {
        get { BLHeliSettings.text(raw[0x60..<0x70]) }
        set { raw.replaceSubrange(0x60..<0x70, with: paddedLatin1(newValue, length: 16)) }
    }

    /// "#BLHELI$" marks BLHeli_S, "#BLHELI#" classic BLHeli (FUN_005a6b88).
    public var isBLHeliS: Bool { mcuString.hasPrefix("#BLHELI$") }

    public var mcuType: String? {
        let s = mcuString
        guard s.hasPrefix("#BLHELI$") || s.hasPrefix("#BLHELI#") else { return nil }
        var t = String(s.dropFirst(8))
        if t.hasSuffix("#") { t.removeLast() }
        return t.trimmingCharacters(in: .whitespaces)
    }

    public var mcuDatabaseCode: (family: MCUFamily, code: Int)? {
        mcuType.flatMap { MCUTable.databaseCode(forEepromMCU: $0) }
    }

    public var family: MCUFamily { mcuDatabaseCode?.family ?? .unknown }

    public var flashFailedMarker: Bool { name == "**FLASH*FAILED**" }

    /// Basic plausibility check of a block read from an ESC (FUN_005a6e64).
    public func validate() throws {
        guard mcuType != nil, mcuDatabaseCode != nil else { throw SettingsError.mcuIDError(mcuString) }
        let main = raw[0], lr = raw[2]
        if !isBLHeliS {
            if main < 0x0F {
                if lr < 7 || lr > 0x15 {
                    if lr < 2 || lr > 0x1E { throw SettingsError.layoutRevisionError(Int(lr)) }
                    if lr < 7 { throw SettingsError.outdatedRevision(revisionString) }
                    throw SettingsError.unsupportedRevision(revisionString)
                }
            } else {
                throw SettingsError.unsupportedRevision(revisionString)
            }
        } else if main > 0x10 {
            throw SettingsError.unsupportedRevision(revisionString)
        }
        if mode == .invalid { throw SettingsError.invalidMode }
    }

    /// Repairs the known-bad rev 9.0/9.10 header exactly like BLHeliSuite does.
    public mutating func normalizeOldHeader() {
        if raw[0] == 9 && (raw[1] == 0 || raw[1] == 10) {
            raw[1] = 0
            raw[2] = 0x0F
        }
    }

    public func context(database db: FirmwareDatabase?, firmware: FirmwareEntry? = nil) -> ParamContext {
        let fam = family
        var layout: ESCLayout?
        if let db = db, let idx = db.layoutIndex(family: fam, name: layoutName) {
            layout = db.layout(family: fam, index: idx)
        }
        return ParamContext(layoutRevision: layoutRevision, revision: revision, isBLHeliS: isBLHeliS,
                            family: fam, mode: mode, layout: layout, firmware: firmware)
    }

    public func value(_ p: BLHeliParam) -> Int { Int(self[p]) }

    public mutating func setValue(_ p: BLHeliParam, _ v: Int) {
        self[p] = UInt8(clamping: v)
    }

    /// One line summary for logs and the ESC overview.
    public func summary(database db: FirmwareDatabase?) -> String {
        var layoutDesc = layoutName
        if let db = db, let idx = db.layoutIndex(family: family, name: layoutName),
           let l = db.layout(family: family, index: idx) {
            layoutDesc = l.displayName
        }
        let fw = isBLHeliS ? "BLHeli_S" : "BLHeli"
        return "\(layoutDesc) (\(mcuType ?? "?")) \(fw) \(revisionString) \(mode.displayName)"
    }
}
