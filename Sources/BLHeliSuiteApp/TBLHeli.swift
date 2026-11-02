import Foundation
import VCL
import BLHeliCore

/// Port of BLHeliSuite's TBLHeli data object (VMT 0x5A41F8): one ESC setup (EEPROM block) plus state.
final class TBLHeli {
    /// Raw 0x70 byte setup block (BLHeliCore representation).
    var settings: BLHeliSettings
    /// Number of valid parameter bytes read (Self+0x20; 0 = no valid setup).
    var count = 0
    /// BLHeli_S data (Self+0x52) and brand of the interface it was read with (Self+0x51).
    var isS = false
    var brand: UInt8 = 0
    /// Signature / MCU id of the device the setup was read from (Self+0x4C).
    var deviceSignature = 0
    /// Self+0x44: message of the last Paste.
    var errorText = ""

    init(isS: Bool = false) {
        settings = BLHeliSettings(raw: [UInt8](repeating: 0xFF, count: BLHeliSettings.size))
        clear(isS: isS)
    }

    /// FUN_005A4348 – reset to an empty setup of the current brand.
    func clear(isS s: Bool) {
        count = 0
        brand = Brand.current
        isS = brand == 1 ? s : false
        var raw = [UInt8](repeating: 0xFF, count: BLHeliSettings.size)
        if isS {
            raw[0] = 0x10; raw[1] = 6; raw[2] = 0x21
            raw.replaceSubrange(0x50..<0x58, with: Array("#BLHELI$".utf8))
        } else {
            raw[0] = 0x0E; raw[1] = 9; raw[2] = 0x15
            raw.replaceSubrange(0x50..<0x58, with: Array("#BLHELI#".utf8))
        }
        raw.replaceSubrange(0x40..<0x50, with: [UInt8](repeating: 0x20, count: 16))
        raw.replaceSubrange(0x60..<0x70, with: [UInt8](repeating: 0x20, count: 16))
        settings = BLHeliSettings(raw: raw)
        deviceSignature = 0
    }

    var isValid: Bool { count > 0 }
    var isFlashFailed: Bool { settings.name == "**FLASH*FAILED**" }
    /// FUN_005A59A0: 0 Main, 1 Tail, 2 Multi, 3 invalid.
    var mode: Int { settings.mode.rawValue }
    var modeName: String { escModeNames[min(mode, 3)] }
    var name: String { settings.name }
    var layoutName: String { settings.layoutName }
    var mcuString: String { settings.mcuString }
    /// FUN_005A5760: "main.sub".
    var revisionString: String { "\(settings.raw[0]).\(settings.raw[1])" }
    var revision: Int { settings.revision }

    func context(_ db: FirmwareDatabase?) -> ParamContext { settings.context(database: db, firmware: db?.matchingEntry(for: settings)) }

    func value(_ p: BLHeliParam) -> Int {
        switch p {
        case .mainRevision: return Int(settings.raw[0])
        case .subRevision: return Int(settings.raw[1])
        case .layoutRevision: return Int(settings.raw[2])
        default: return settings.value(p)
        }
    }

    func setValue(_ p: BLHeliParam, _ v: Int) { settings.setValue(p, v) }

    func exists(_ p: BLHeliParam, _ db: FirmwareDatabase?) -> Bool { BLHeliParamLogic.exists(p, context(db)) }

    /// FUN_005A63C0: parameter name ("Eep_" name in dumps).
    func paramName(_ p: BLHeliParam) -> String { p.eepName }

    /// FUN_005A63C0 → FUN_005AB2F0: display name of a parameter for this setup ("Closed Loop P-Gain" …).
    func displayName(_ p: BLHeliParam, _ db: FirmwareDatabase?) -> String { p.displayName(context(db)) }

    /// FUN_005A6534: the parameter exists for this setup; BEC voltage and LED control only when the
    /// layout has them (layout table +0x102 / +0x408).
    func has(_ p: BLHeliParam, _ db: FirmwareDatabase?) -> Bool {
        let ctx = context(db)
        guard BLHeliParamLogic.exists(p, ctx) else { return false }
        if p == .becVoltageHigh { return (ctx.layout?.becHV ?? 0) != 0 }
        if p == .ledControl { return (ctx.layout?.leds ?? 0) != 0 }
        return true
    }

    /// FUN_005A6098: default value of a parameter.
    func defaultValue(_ p: BLHeliParam, _ db: FirmwareDatabase?) -> Int? { BLHeliParamLogic.defaultValue(p, context(db)) }

    /// FUN_005A63F0: current value == default value.
    func isDefault(_ p: BLHeliParam, _ db: FirmwareDatabase?) -> Bool {
        guard let d = defaultValue(p, db) else { return true }
        return value(p) == d
    }

    /// FUN_005A5700 → FUN_005AA724: value list of a parameter (texts, Objects = values).
    func valueList(_ p: BLHeliParam, _ db: FirmwareDatabase?) -> [(text: String, value: Int)] {
        let ctx = context(db)
        guard BLHeliParamLogic.exists(p, ctx) else { return [] }
        return BLHeliParamLogic.allowedValues(p, ctx).map { (BLHeliParamLogic.label(p, value: $0, ctx), $0) }
    }

    /// FUN_005A566C: value text.
    func valueText(_ p: BLHeliParam, _ v: Int, _ db: FirmwareDatabase?) -> String {
        switch p {
        case .escLayout: return settings.rawLayoutString
        case .name: return settings.name
        case .escMCU: return settings.mcuString
        default: return BLHeliParamLogic.label(p, value: v, context(db))
        }
    }

    /// FUN_005A443C: same parameter values (optionally name, throttle and direction).
    func sameAs(_ o: TBLHeli?, compareName: Bool, syncThrottle: Bool, syncDirection: Bool, _ db: FirmwareDatabase?) -> Bool {
        guard let o else { return false }
        if compareName && name != o.name { return false }
        guard o.isS == isS else { return false }
        for raw in 4..<42 {
            guard let p = BLHeliParam(rawValue: raw) else { continue }
            if !exists(p, db) { continue }
            if p == .direction && !syncDirection { continue }
            if (p == .ppmMinThrottle || p == .ppmMaxThrottle || p == .ppmCenterThrottle) && !syncThrottle { continue }
            if value(p) != o.value(p) { return false }
        }
        return true
    }

    /// FUN_005A44C8: Assign (copy of the setup data).
    func assign(to dst: TBLHeli) {
        if !isValid {
            dst.clear(isS: isS)
        } else {
            dst.settings = settings
            dst.count = count
            dst.isS = isS
            dst.brand = brand
            dst.deviceSignature = deviceSignature
        }
    }

    func copy() -> TBLHeli {
        let t = TBLHeli(isS: isS)
        assign(to: t)
        return t
    }

    /// FUN_005A5814: "Name - Layout - Rev. x.y - Mode".
    func shortInfo() -> String {
        guard isValid else { return "" }
        let n = name.isEmpty ? "Noname" : name
        return n + " - " + layoutName + " - Rev. " + revisionString + " - " + modeName
    }

    /// FUN_005A59D4: parameter dump shown in the Copy/Paste hints.
    func dumpText(_ db: FirmwareDatabase?) -> String {
        guard isValid else { return "" }
        var s = "Name: " + name + "\r\n"
        s += (isS ? "BLHeli_S Rev.: " : "BLHeli Rev.: ") + revisionString + "\r\n"
        s += BLHeliParam.escLayout.eepName + ": " + settings.rawLayoutString + "\r\n"
        s += "ESC Mode: " + modeName + "\r\n"
        s += "ESC MCU: " + settings.mcuString + "\r\n"
        s += BLHeliParam.layoutRevision.eepName + ": \(value(.layoutRevision))\r\n"
        for raw in 4..<42 where raw != 14 && raw != 15 {
            guard let p = BLHeliParam(rawValue: raw), exists(p, db) else { continue }
            let v = value(p)
            s += p.eepName + ": " + valueText(p, v, db) + " (\(v))\r\n"
        }
        return s
    }

    struct LoadError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Checks of TBLHeli.Load (FUN_005A6E64) with the messages of BLHeliSuite; "BLHeli revision check disabled"
    /// (Options) accepts newer firmware and layouts that are not in the list.
    static func checkLoad(_ s: BLHeliSettings, rawCount: Int) throws {
        guard rawCount >= 0x70 else { throw LoadError(message: DFormat(NL("Setup section size too small: %d"), [rawCount])) }
        guard s.mcuType != nil, s.mcuDatabaseCode != nil else {
            throw LoadError(message: DFormat(NL("MCU ID error!\\n\"%s\"\\n\\nUnflashed, erased or invald ESC type?"), [s.mcuString]))
        }
        let check = !Globals.revisionCheckDisabled
        let main = Int(s.raw[0]), lr = Int(s.raw[2])
        let found = DFormat(NL("Found Firmware revision: %s / EEProm layout revision: %d."), [s.revisionString, lr])
        if !s.isBLHeliS {
            if main < 0x0F && (lr < 7 || lr > 0x15) {
                if lr < 2 || lr > 0x1E {
                    throw LoadError(message: DFormat(NL("Firmware EEProm layout error!\\n(Found Rev.%d)\\nUnflashed, erased or invald ESC type?"), [lr]))
                }
                if lr < 7 {
                    throw LoadError(message: DFormat(NL("Firmware revision <2.0 is not supported!\\nFound EEProm layout rev %d"), [lr]))
                }
                if check {
                    throw LoadError(message: DFormat(NL("This application supports EEProm layouts up to revision %d."), [0x15]) + "\n\n" + found +
                                    "\n\n" + DFormat(NL("Please get the latest revision of BLHeliSuite or reflash the ESC with rev %d.%d ..."), [14, 9]))
                }
            }
        } else if main > 0x10 && check {
            throw LoadError(message: DFormat(NL("This application supports firmware up to revision %d.%d."), [16, 7]) + "\n" + found +
                            "\n\n" + DFormat(NL("Please get the latest revision of BLHeliSuite or reflash the ESC with rev %d.%d ..."), [16, 7]))
        }
        if s.mode == .invalid {
            throw LoadError(message: NL(String(format: "Unsupported or invald ESC Mode: 0x%.2x 0x%.2x", s.raw[0x0D], s.raw[0x0E])))
        }
        let fam: MCUFamily = s.family == .atmel ? .atmel : .silabs
        if check, let db = try? FirmwareDatabase.shared(), db.layoutIndex(family: fam, name: s.layoutName) == nil {
            throw LoadError(message: DFormat(NL("ESC not in list: %s"), [s.layoutName]))
        }
    }

    /// Loads a setup block (FUN_005A6E64). `checks`: the checks and messages of BLHeliSuite for a setup read from an
    /// ESC; otherwise only the basic plausibility test (setups of hex files while flashing).
    func load(raw: [UInt8], signature: Int = 0, checks: Bool = false) throws {
        var s = BLHeliSettings(raw: Array(raw.prefix(max(BLHeliSettings.size, raw.count))))
        s.normalizeOldHeader()
        if checks { try TBLHeli.checkLoad(s, rawCount: raw.count) } else { try s.validate() }
        settings = s
        isS = s.isBLHeliS
        brand = s.family == .atmel ? 2 : (s.family == .silabs ? 1 : Brand.current)
        count = BLHeliSettings.size
        deviceSignature = signature
    }
}

// MARK: - layout / revision lookups of TBLHeli.Load (FUN_005A6E64)

extension TBLHeli {
    var family: MCUFamily { brand == 2 ? .atmel : .silabs }

    /// FUN_005A5734: revision as number (16.6 -> 1660, 14.12 -> 1412).
    var revNum: Int {
        let m = Int(settings.raw[0]), s = Int(settings.raw[1])
        return m * 100 + (s < 10 ? s * 10 : s)
    }

    /// Self+0x20: index in the layout table (< 1: not in list).
    func layoutIndex(_ db: FirmwareDatabase?) -> Int { db?.layoutIndex(family: family, name: layoutName) ?? 0 }

    /// Self+0x14: layout name ("A_H_30").
    func layoutTag(_ db: FirmwareDatabase?) -> String {
        let i = layoutIndex(db)
        return i > 0 ? (db?.layout(family: family, index: i)?.name ?? layoutName) : layoutName
    }

    /// Self+0x48: layout description of the table (+0x103) or "<name> [NOT in List]".
    func layoutDescription(_ db: FirmwareDatabase?) -> String {
        let i = layoutIndex(db)
        if i > 0, let l = db?.layout(family: family, index: i) { return l.desc }
        return layoutName + " [NOT in List]"
    }

    /// Self+0x40 (FUN_0059ED98): index of the firmware in the hex list,
    /// -1 = unknown revision, -2 = only a higher revision of this layout is in the list.
    func revisionStatus(_ db: FirmwareDatabase?) -> Int {
        guard let db, let fam = db.family(family) else { return -1 }
        let li = layoutIndex(db)
        func find(_ rev: Int) -> Int {
            fam.firmware.firstIndex { $0.rev == rev && $0.layout == li && $0.mode == mode } ?? -1
        }
        let r = find(revNum)
        if r >= 0 { return r }
        return find((revNum / 10) * 10 + 10) >= 0 ? -2 : -1
    }

    /// MCU class code of the setup (Self+0x4C, FUN_005A6B88).
    var mcuCode: Int { settings.mcuDatabaseCode?.code ?? 0 }
}

/// FUN_005A3F38: MCU class name.
func mcuClassName(_ code: Int) -> String {
    switch code {
    case 0x2B: return "C8051F39x/37x"
    case 0x08: return "C8051F31x"
    case 0x0A: return "C8051F33x"
    case 0x0C: return "C8051F41x"
    case 0x30: return "C8051F85x/86x or EFM8BB10Fx"
    case 0x32: return "EFM8BB21Fx"
    default:
        if code >= 0x1E9000, let m = MCUTable.byAVRSignature(UInt32(code)) { return m.name }
        return "Unknown Device"
    }
}

// MARK: - FUN_005A65C8: apply the settings of another setup

extension TBLHeli {
    /// Copies the parameter values of `src` (translating between EEPROM revisions when `translate`).
    /// Returns false with `errorText` set (Self+0x44) when the settings cannot be applied.
    @discardableResult
    func paste(from src: TBLHeli, translate: Bool, showMsg: Bool, syncThrottle: Bool, syncDirection: Bool, _ db: FirmwareDatabase?) -> Bool {
        errorText = ""
        if mode != src.mode {
            errorText = NL("Cannot apply settings: ESC mode (MAIN - TAIL - MULTI) does not match.")
            return false
        }
        if isS != src.isS {
            errorText = NL("Cannot apply settings: BLHeli \"S\"  does not match BLHeli \"non S\".")
            return false
        }
        if value(.layoutRevision) == src.value(.layoutRevision) && revNum == src.revNum {
            let dstLayout = db?.layout(family: family, index: layoutIndex(db)), srcLayout = db?.layout(family: src.family, index: src.layoutIndex(db))
            for raw in 4..<42 {
                guard let p = BLHeliParam(rawValue: raw), exists(p, db) else { continue }
                if p == .direction && !syncDirection { continue }
                if (p == .ppmMinThrottle || p == .ppmMaxThrottle || p == .ppmCenterThrottle) && !syncThrottle { continue }
                if p == .becVoltageHigh && dstLayout?.becHV != srcLayout?.becHV { continue }
                if p == .ledControl && dstLayout?.leds != srcLayout?.leds { continue }
                setValue(p, src.value(p))
            }
        } else if translate {
            guard let t = try? SettingsTranslator(copyName: false).translate(from: src.settings, oldContext: src.context(db),
                                                                             to: settings, newContext: context(db)) else {
                errorText = NL("Cannot apply settings: Found different version of EEprom structure.")
                return false
            }
            let keepDir = value(.direction)
            let keepThr = [BLHeliParam.ppmMinThrottle, .ppmMaxThrottle, .ppmCenterThrottle].map { value($0) }
            settings = t
            if !syncDirection { setValue(.direction, keepDir) }
            if !syncThrottle {
                for (i, p) in [BLHeliParam.ppmMinThrottle, .ppmMaxThrottle, .ppmCenterThrottle].enumerated() { setValue(p, keepThr[i]) }
            }
            return true
        } else {
            errorText = NL("Cannot apply settings: Found different version of EEprom structure.")
        }
        if !errorText.isEmpty && showMsg { MsgDlg.show(errorText, .mtWarning, [.mbOK]) }
        return errorText.isEmpty
    }
}
