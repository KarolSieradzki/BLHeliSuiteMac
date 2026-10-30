import Foundation

/// Logic behind the "Flash BLHeli" assistant (TfrmFlashAssistant): which built-in files fit
/// the connected ESC, which one is preselected, and how the final flash plan is built.
public enum FirmwareSelection {
    /// MCU code (firmware database key) for a connected device.
    public static func databaseCode(for device: DeviceInfo) -> Int? {
        device.mcu?.databaseCode
    }

    /// All built-in files suitable for the device MCU (or all files of the family when
    /// `ignoreMCU` is set, like "show all firmware files" in BLHeliSuite).
    public static func candidates(_ db: FirmwareDatabase, device: DeviceInfo, ignoreMCU: Bool = false) -> [FirmwareEntry] {
        let fam = device.family
        let code = ignoreMCU ? nil : databaseCode(for: device)
        return db.entries(family: fam, mcuCode: code)
    }

    /// Distinct layouts within `entries`, sorted by description.
    public static func layouts(_ db: FirmwareDatabase, family: MCUFamily, entries: [FirmwareEntry]) -> [(index: Int, layout: ESCLayout)] {
        var seen = Set<Int>()
        var out: [(Int, ESCLayout)] = []
        for e in entries where !seen.contains(e.layout) {
            seen.insert(e.layout)
            if let l = db.layout(family: family, index: e.layout) { out.append((e.layout, l)) }
        }
        return out.sorted { $0.1.displayName.localizedStandardCompare($1.1.displayName) == .orderedAscending }
            .map { (index: $0.0, layout: $0.1) }
    }

    /// Preferred file: same layout & mode & firmware type as the ESC, highest revision.
    public static func preferred(_ db: FirmwareDatabase, device: DeviceInfo, settings: BLHeliSettings?) -> FirmwareEntry? {
        let all = candidates(db, device: device)
        guard !all.isEmpty else { return nil }
        var pool = all
        if let s = settings, (try? s.validate()) != nil {
            if let li = db.layoutIndex(family: device.family, name: s.layoutName) {
                let same = pool.filter { $0.layout == li && $0.mode == s.mode.rawValue }
                if !same.isEmpty { pool = same }
            }
            let sameType = pool.filter { $0.isBLHeliS == s.isBLHeliS }
            if !sameType.isEmpty { pool = sameType }
        } else {
            return nil
        }
        return pool.max { a, b in a.rev < b.rev }
    }

    /// Builds the flash plan: file content + translated user settings.
    public static func makePlan(_ db: FirmwareDatabase, entry: FirmwareEntry, current: BLHeliSettings?,
                                translator: SettingsTranslator = SettingsTranslator()) -> (plan: FlashPlan, warning: String?) {
        let flash = db.flashImage(entry)
        let eeprom = entry.mcuFamily == .atmel ? db.eepromImage(entry) : nil
        let layout = db.layout(family: entry.mcuFamily, index: entry.layout)
        let title = "\(layout?.displayName ?? entry.name) – \(entry.firmwareName) \(entry.revStr) \(entry.modeName)"
        var plan = FlashPlan(flash: flash, eeprom: eeprom, settings: nil, title: title)
        var warning: String?
        if let defaults = plan.defaultSettings {
            plan.settings = defaults
            if let cur = current, (try? cur.validate()) != nil, !cur.flashFailedMarker {
                let oc = cur.context(database: db)
                let nc = defaults.context(database: db, firmware: entry)
                do {
                    plan.settings = try translator.translate(from: cur, oldContext: oc, to: defaults, newContext: nc)
                } catch {
                    warning = error.localizedDescription + "\nDefault settings of the new firmware will be used."
                }
            }
        }
        return (plan, warning)
    }

    /// Plan for an external .hex (+ .eep) file ("Flash Other").
    public static func makePlan(hexURL: URL, eepURL: URL?, current: BLHeliSettings?, db: FirmwareDatabase?) throws -> (plan: FlashPlan, warning: String?) {
        let flash = try MemoryImage.loadIntelHex(url: hexURL)
        var eep: MemoryImage?
        if let e = eepURL { eep = try MemoryImage.loadIntelHex(url: e) }
        var plan = FlashPlan(flash: flash, eeprom: eep, settings: nil, title: hexURL.lastPathComponent)
        var warning: String?
        if let defaults = plan.defaultSettings, (try? defaults.validate()) != nil {
            plan.settings = defaults
            if let cur = current, (try? cur.validate()) != nil, !cur.flashFailedMarker {
                do {
                    plan.settings = try SettingsTranslator().translate(from: cur, oldContext: cur.context(database: db),
                                                                       to: defaults, newContext: defaults.context(database: db))
                } catch {
                    warning = error.localizedDescription
                }
            }
        } else {
            warning = "The file contains no BLHeli setup data – the ESC setup area keeps the file content."
        }
        return (plan, warning)
    }

    /// ISP extras for an Atmel layout: BLHeli bootloader resource (BLHELI_<MCU>_<MHz>_<pin>) and fuses
    /// from the layout record (ESC.cfg columns Freq/Bootl/InPin/lfuse/hfuse/efuse).
    public static func ispExtras(_ db: FirmwareDatabase, entry: FirmwareEntry) -> (bootloaderName: String?, bootloader: MemoryImage?, fuses: AVRFuses?) {
        guard entry.mcuFamily == .atmel, let l = db.layout(family: .atmel, index: entry.layout) else { return (nil, nil, nil) }
        let mcuTag: String
        switch entry.mcu {
        case 0x1E9307: mcuTag = "M8"
        case 0x1E9406: mcuTag = "M168"
        case 0x1E940B: mcuTag = "M168PA"
        default: mcuTag = ""
        }
        var name: String?
        var boot: MemoryImage?
        if l.bootloader, !mcuTag.isEmpty, !l.inPin.isEmpty {
            let n = "BLHELI_\(mcuTag)_\(l.mhz)_\(l.inPin.uppercased())"
            if let img = db.bootloaderImage(named: n) { name = n; boot = img }
        }
        let fuses: AVRFuses? = (l.lfuse == 0 && l.hfuse == 0) ? nil : AVRFuses(low: l.lfuse, high: l.hfuse, ext: entry.mcu == 0x1E9307 ? nil : l.efuse)
        return (name, boot, fuses)
    }

    /// Safety checks done by BLHeliSuite before flashing (MCU / layout mismatch).
    public static func check(plan: FlashPlan, entry: FirmwareEntry?, device: DeviceInfo, current: BLHeliSettings?,
                             db: FirmwareDatabase?) -> [String] {
        var warnings: [String] = []
        if let e = entry, let code = databaseCode(for: device), e.mcu != code {
            warnings.append("The selected firmware is made for another MCU than the connected ESC (\(device.mcu?.name ?? "?")).")
        }
        if let e = entry, e.mcuFamily != device.family {
            warnings.append("The selected firmware is for \(e.mcuFamily.displayName) ESCs, the connected ESC is \(device.family.displayName).")
        }
        if let cur = current, (try? cur.validate()) != nil, let newS = plan.settings {
            if cur.layoutName.uppercased() != newS.layoutName.uppercased() {
                warnings.append("The ESC layout changes from \"\(cur.layoutName)\" to \"\(newS.layoutName)\".\nFlashing this ESC with an inappropriate hex file may cause severe damage of the ESC and motor!")
            }
            if cur.isBLHeliS != newS.isBLHeliS {
                warnings.append("The firmware type changes (\(cur.isBLHeliS ? "BLHeli_S" : "BLHeli") → \(newS.isBLHeliS ? "BLHeli_S" : "BLHeli")).")
            }
        }
        return warnings
    }
}
