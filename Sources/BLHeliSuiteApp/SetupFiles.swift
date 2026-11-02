import AppKit
import VCL
import BLHeliCore

// MARK: - BLHeli setup files (TBLHeli 0x5A4D80 SaveToIni, 0x5A4F6C LoadFromIni, dialogs 0x5A48A8 / 0x5A4BD4)
//
// Same format as BLHeliSuite for Windows (TIniFile): one section "ESC<n>" – "ESC0" for a single setup (*.ini),
// "ESC1" … "ESC8" in Multiple ESC files (*.ixi) – with Eep_Name, Eep_ESC_Layout, Eep_ESC_MCU, Eep_ESC_Mode and
// the parameters of the setup. Old files (sections "Name", "Hardware", "Setup" with Eep_BESC_* keys) are read too.

extension TBLHeli {
    /// FUN_005AB1DC: ini key of a parameter (old names before layout revision 11 / 17).
    static func iniKey(_ p: BLHeliParam, layoutRevision lr: Int) -> String {
        switch p {
        case .motorGain where lr < 0x0B: return "Eep_Pgm_Tail_Gain"
        case .motorIdle where lr < 0x0B: return "Eep_Pgm_Tail_Idle"
        case .direction where lr < 0x11: return "Eep_Pgm_Direction_Rev"
        default: return p.eepName
        }
    }

    /// FUN_005553B8: characters that are not allowed in Windows file names removed.
    static func fileNameSafe(_ s: String) -> String { s.filter { !"\"*/:<>?\\|".contains($0) } }

    /// Folder of the setup file dialogs (the Windows dialogs remember the last folder).
    static var setupFolder: URL = {
        let d = AppFolders.userFolder.appendingPathComponent("Settings")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// FUN_005A48A8: save dialog with "BLHeli_<Name - Layout - Rev. - Mode>_<YYMMDD>.ini" (Multiple ESC: .ixi);
    /// an existing file is replaced.
    func iniSaveURL(multi: Bool) -> URL? {
        guard isValid else { MsgDlg.error(NL("Settings are not initialized and cannnot be saved.")); return nil }
        guard value(.layoutRevision) >= 7 else {
            MsgDlg.error(NL("Settings of Version < 2.0 cannot be saved by this application."))
            return nil
        }
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: Date())
        let date = String(format: "%02d%02d%02d", (c.year ?? 2000) - 2000, c.month ?? 1, c.day ?? 1)
        let ext = multi ? "ixi" : "ini"
        let filter = multi ? "BLHeli Multiple-ESC Setup file (*.ixi)|*.ixi" : "BLHeli Setup file (*.ini)|*.ini"
        let name = "BLHeli_" + TBLHeli.fileNameSafe(shortInfo()) + "_" + date + "." + ext
        guard let url = SaveDialog.execute(fileName: name, filter: filter, initialDir: TBLHeli.setupFolder) else { return nil }
        TBLHeli.setupFolder = url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: url)
        return url
    }

    /// FUN_005A4BD4: open dialog for setup files.
    static func iniOpenURL(multi: Bool) -> URL? {
        let filter = multi ? "BLHeli Setup file (*.ixi)|*.ixi" : "BLHeli Setup file (*.ini)|*.ini"
        guard let url = OpenDialog.execute(filter: filter, initialDir: setupFolder) else { return nil }
        setupFolder = url.deletingLastPathComponent()
        return url
    }

    /// FUN_005A4D80: writes the setup as section "ESC<escNo>".
    @discardableResult
    func saveToIni(_ url: URL, escNo: Int, _ db: FirmwareDatabase?) -> Bool {
        let ini = TIniFile(url: url)
        let sec = "ESC" + String(escNo)
        let lr = value(.layoutRevision)
        ini.writeString(sec, TBLHeli.iniKey(.name, layoutRevision: lr), isFlashFailed ? "" : name)
        ini.writeString(sec, TBLHeli.iniKey(.escLayout, layoutRevision: lr), layoutTag(db))
        ini.writeString(sec, TBLHeli.iniKey(.escMCU, layoutRevision: lr), mcuString)
        ini.writeInteger(sec, "Eep_ESC_Mode", mode)
        for raw in 1..<0x2A where raw != 0x0E && raw != 0x0F {
            guard let p = BLHeliParam(rawValue: raw), exists(p, db) else { continue }
            ini.writeInteger(sec, TBLHeli.iniKey(p, layoutRevision: lr), value(p))
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// FUN_005A53FC: ESC mode → Eep_Initialized_L/H.
    func setMode(_ m: Int) {
        let b: (UInt8, UInt8)
        switch m {
        case 0: b = (0xA5, 0x5A)
        case 1: b = (0x5A, 0xA5)
        case 2: b = (0x55, 0xAA)
        default: b = (0xFF, 0xFF)
        }
        settings.raw[0x0D] = b.0
        settings.raw[0x0E] = b.1
    }

    private static func padded(_ s: String) -> [UInt8] {
        var b = Array(s.data(using: .isoLatin1, allowLossyConversion: true) ?? Data()).prefix(16)
        while b.count < 16 { b.append(0x20) }
        return Array(b)
    }

    /// FUN_005A4F6C: reads section "ESC<escNo>" (or an old "Hardware" file). `found`: there was data to read.
    func loadFromIni(_ url: URL, escNo: Int, _ db: FirmwareDatabase?, found: inout Bool) -> Bool {
        found = false
        let ini = TIniFile(url: url)
        let has = { (s: String) in ini.sectionNames().contains { $0.caseInsensitiveCompare(s) == .orderedSame } }
        let legacy = has("Hardware")
        var sec = "ESC" + String(escNo)
        guard has(sec) || legacy else { return false }
        clear(isS: false)                                                      // FUN_005A4348
        found = true
        if legacy { sec = "Name" }
        settings.name = ini.readString(sec, TBLHeli.iniKey(.name, layoutRevision: value(.layoutRevision)),
                                       ini.readString(sec, "Name", ""))
        if legacy { sec = "Hardware" }
        let mcu = ini.readString(sec, "Eep_ESC_MCU", ini.readString(sec, "Eep_BESC_MCU", ""))
        settings.raw.replaceSubrange(0x50..<0x60, with: TBLHeli.padded(mcu))
        guard settings.mcuDatabaseCode != nil else {                           // FUN_005A6B88
            clear(isS: isS)
            MsgDlg.error(DFormat(NL("MCU ID error!\\n\"%s\"\\n\\nUnflashed, erased or invald ESC type?"), [mcu]))
            return false
        }
        isS = settings.isBLHeliS
        brand = settings.family == .atmel ? 2 : 1
        let lay = ini.readString(sec, "Eep_ESC_Layout", ini.readString(sec, "Eep_BESC_Layout", ""))
        let key = lay.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
        guard let li = db?.layoutIndex(family: settings.family, name: key),
              let layout = db?.layout(family: settings.family, index: li) else {          // FUN_0059BAA0
            clear(isS: isS)
            MsgDlg.error(DFormat(NL("Unsupported or invald ESC Type: \"%s\""), [lay]))
            return false
        }
        settings.raw.replaceSubrange(0x40..<0x50, with: TBLHeli.padded("#" + layout.name + "#"))
        setMode(ini.readInteger(sec, "Eep_ESC_Mode", ini.readInteger(sec, "Eep_BESC_Mode", ini.readInteger(sec, "Eep_IsTail", 0))))
        count = BLHeliSettings.size
        for raw in 1..<0x2A where raw != 0x0E && raw != 0x0F {
            if legacy && raw == 4 { sec = "Setup" }
            guard let p = BLHeliParam(rawValue: raw), exists(p, db) else { continue }
            let def = defaultValue(p, db) ?? value(p)                                  // FUN_005A6098
            setValue(p, ini.readInteger(sec, TBLHeli.iniKey(p, layoutRevision: value(.layoutRevision)), def))
        }
        return true
    }
}

// MARK: - menu "ESC setup" → setup files (0x660C74, 0x6602F8, 0x66095C, 0x660388)

extension TfrmBLHeliSuiteMain {
    /// WM_DROPFILES (dynamic method 0x65DD30): a single .ini file imports settings, a .hex file updates the
    /// firmware of the master ESC.
    func dropFiles(_ urls: [URL]) {
        guard urls.count == 1 else {
            setStatus(NL("Drag and drop is only allowed for a single file."))
            MsgDlg.error(statusText)
            return
        }
        let url = urls[0]
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        switch url.pathExtension.uppercased() {
        case "INI":
            guard MsgDlg.show(DFormat(NL("Import settings from file \"%s\"?"), [url.path]), .mtConfirmation, [.mbYes, .mbNo]) == mrYes else { return }
            var found = false
            if workspace.loadFromIni(url, escNo: 0, db, found: &found) {
                if !escConnected { workspace.assign(to: current) }
                showESCData()
            }
        case "HEX":
            guard MsgDlg.show(DFormat(NL("Update Firmware with file \"%s\"?"), [url.path]), .mtConfirmation, [.mbYes, .mbNo]) == mrYes else { return }
            guard connectForExpertTool() else { return }                          // FUN_00663EC8
            var mem: [UInt8]?
            if let m = readSetupMem() {                                           // FUN_006796A0
                mem = m
                try? workspace.load(raw: m)
                showESCData()
            }
            do { _ = try flashFile(mem: mem, url: url, blheli: false) } catch {}  // FUN_0066546C
            updateESCButtons()
        default:
            break
        }
    }

    @objc func actSaveSetupToIniFileExecute(_ sender: TObject) {
        guard workspace.isValid, let url = workspace.iniSaveURL(multi: false) else { return }
        if workspace.saveToIni(url, escNo: 0, db) {
            MsgDlg.show(DFormat(NL("Saved Setup to \"%s\""), [url.path]), .mtInformation, [.mbOK])
        } else {
            MsgDlg.error(DFormat(NL("Saving Setup to \"%s\" failed"), [url.path]))
        }
    }

    @objc func actReadSetupFromIniFileExecute(_ sender: TObject) {
        guard let url = TBLHeli.iniOpenURL(multi: false) else { return }
        var found = false
        guard workspace.loadFromIni(url, escNo: 0, db, found: &found) else { return }
        if !escConnected { workspace.assign(to: current) }
        showESCData()
    }

    @objc func actSaveMultipleESCSetupToIniFileExecute(_ sender: TObject) {
        if multiESCCapable && !checkedMultiESC { checkMultiESC(1, escCount) }
        guard let url = workspace.iniSaveURL(multi: true) else { return }
        var msgs = ""
        for n in 1...max(1, escCount) where slots[n].selected {
            let b = blheli[n]
            var m = b.name.isEmpty ? DFormat(NL("ESC# %d :\\n"), [n]) : DFormat(NL("ESC# %d \"%s\":\\n"), [n, b.name])
            if !b.isValid {
                m += NL("No data to save.")
            } else if b.saveToIni(url, escNo: n, db) {
                m += NL("Saved successfully.")
            } else {
                m += NL("Save failed.")
            }
            msgs += m + "\n\n"
        }
        MsgDlg.show(DFormat(NL("Saved Setup to \"%s\"\\n\\n%s"), [url.path, msgs]), .mtInformation, [.mbOK])
    }

    @objc func actReadMultipleESCSetupFromIniFileExecute(_ sender: TObject) {
        if multiESCCapable && !checkedMultiESC { checkMultiESC(1, escCount) }
        guard let url = TBLHeli.iniOpenURL(multi: true) else { return }
        var allOK = true
        var read = 0
        var msgs = ""
        for n in 1...max(1, escCount) where slots[n].selected {
            var found = false
            var m: String
            if !blheli[n].loadFromIni(url, escNo: n, db, found: &found) {
                m = DFormat(NL("ESC# %d :\\n"), [n])
                if !found {
                    m += NL("No data to available to read.")
                } else {
                    allOK = false
                    m += NL("Read failed.")
                }
            } else {
                read += 1
                let nm = blheli[n].name
                m = nm.isEmpty ? DFormat(NL("ESC# %d :\\n"), [n]) : DFormat(NL("ESC# %d \"%s\":\\n"), [n, nm])
                m += NL("Read successfully.")
            }
            msgs += m + "\n\n"
        }
        if !allOK || read == 0 {
            MsgDlg.show(DFormat(NL("Read Setups from \"%s\"\\n\\n%s\\n\\n"), [url.path, msgs]), .mtConfirmation, [.mbOK])
        } else {
            let q = DFormat(NL("Read Setups from \"%s\"\\n\\n%s\\n\\nDo you want to write the paramters now to each individual ESCs?\\n\\nNote: the application is now in a special mode, with the ability to handle the ESCs individually.\\nRight after the write operation (Yes) or closing this dialog (no) the application will fall back into the normal Master/Slave mode.\\nIn Master/Slave mode, the paramters loaded from the ini can be reviewed and/or written individually, if each ESC is selected in single mode (right mouse button)."), [url.path, msgs])
            if MsgDlg.show(q, .mtConfirmation, [.mbYes, .mbNo]) == mrYes { _ = writeSetup(false) }
        }
        selectESC(masterESC, load: true)
        updateESCButtons()
    }
}
