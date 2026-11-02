import AppKit
import VCL
import BLHeliCore

/// Delphi's Abort (EAbort): silently cancels the running operation.
struct EAbort: Error {}

extension TfrmBLHeliSuiteMain {
    // MARK: - helpers of the flash/write procedures

    /// FUN_00675438: number of ESC channels of the interface.
    var escSlotCount: Int { multiESCCapable ? max(1, escCount) : 1 }

    /// FUN_006754AC: clears the per-ESC status texts.
    func clearSlotStatus() { for n in 1...8 { slots[n].statusText = "" } }

    /// FUN_00666F364/FUN_0066F29C based check (FUN_006638F0): current ESC is the master.
    var isMaster: Bool { escNo == masterESC }

    /// FUN_00673108: status line + status text of the current ESC.
    func setStatusESC(_ s: String) {
        setStatus(s)
        slots[escNo].statusText = statusText
    }

    /// FUN_006796A0: reads the setup memory of the current ESC (nil = read failed).
    func readSetupMem() -> [UInt8]? {
        guard let p = programmer, let dev = targetDevice else { return nil }
        do {
            return try ESCOperations(programmer: p).readSettings(device: dev).raw
        } catch {
            if error is SerialError { connectionLost() }
            return nil
        }
    }

    /// FUN_006798B8: checks the connected ESC; `locked` = code memory locked.
    func checkESC() -> (ok: Bool, locked: Bool) {
        guard escConnected else { return (false, false) }
        return (true, slots[escNo].locked)
    }

    /// FUN_0065F034: classifies the read setup memory (Self+0x8BC). Returns true when it is no usable setup.
    @discardableResult
    func classifyRead(locked: Bool, mem: inout [UInt8]?) -> Bool {
        readResult = .unknown
        if locked {
            readResult = .locked
            return true
        }
        guard let m = mem, !m.isEmpty else { return true }
        readResult = m.allSatisfy { $0 == 0xFF } ? .erased : .unknown
        if readResult == .erased { mem = nil }
        if readResult == .unknown && intf == .silC2Toolstick && m.allSatisfy({ $0 == 0 }) { readResult = .locked }
        if readResult != .unknown { return true }
        let t = current
        do {
            try t.load(raw: m)
        } catch {
            let lr = m.count > 2 ? m[2] : 0
            if lr < 7 { readResult = .outdated } else if lr > 0x15 && lr < 0x19 { readResult = .ok }
            return readResult != .ok
        }
        if t.isFlashFailed { readResult = .flashFailed; return true }
        let r = t.revNum
        if r == 900 || (t.value(.mainRevision) == 9 && t.value(.subRevision) == 10) || (r > 0x65D && r < 0x668) {
            readResult = .removed
        } else if r > 0x5BD && r < 0x5C8 && !t.isS {
            readResult = .removed
        } else if t.layoutTag(db) == "FC_Fairy_30A" && r > 0x59F && r < 0x5D2 {
            readResult = .removedLayout
        } else {
            readResult = .ok
        }
        return readResult != .ok
    }

    // MARK: - Flash BLHeli / Flash Other (FUN_00665658)

    /// `file`: pick a file at once (Flash Other), `blheli`: Flash BLHeli. Returns true when the last result was not 0.
    func flashStart(file: Bool, blheli: Bool) throws -> Bool {
        guard connectInterface(true) else { return false }
        if multiESCCapable && !checkedMultiESC { checkMultiESC(1, escSlotCount) }
        clearSlotStatus()
        TfrmLogForm.addBlue("Flash" + (blheli ? " BLHeli" : " Other"))
        TfrmLogForm.indent(1)
        var result = 0
        var flashed = 0
        do {
            defer {
                TfrmLogForm.indent(-1)
                if result > 0 { TfrmLogForm.add("OK", color: 0x8000) }
                else if result == -1 { TfrmLogForm.add("Aborted", color: 0x800080) }
                else { TfrmLogForm.add("FAILED", color: 0xFF) }
            }
            for n in 1...escSlotCount {
                if multiESCCapable && !slots[n].selected { continue }
                selectESC(n, load: true)
                TfrmLogForm.addBlue2("Flash " + escText)
                TfrmLogForm.indent(1)
                defer {
                    TfrmLogForm.indent(-1)
                    if result == 1 { TfrmLogForm.result(true) }
                    else if result == -1 { TfrmLogForm.add("Aborted", color: 0x800080) }
                    else { TfrmLogForm.result(false) }
                }
                result = 0
                guard connectESC(true) else { continue }
                let chk = checkESC()
                guard chk.ok else { continue }
                var mem: [UInt8]?
                if !chk.locked, let m = readSetupMem() {
                    mem = m
                    try? workspace.load(raw: m)
                    showESCData()
                }
                classifyRead(locked: chk.locked, mem: &mem)
                result = try flashOne(mem: mem, file: file, blheli: blheli)
                if result > 0 {
                    flashed += 1
                    TfrmLogForm.add(DFormat("#%d", [n]), color: 0x8000)
                    if let m = readSetupMem() {
                        try? workspace.load(raw: m)
                        showESCData()
                    }
                } else if result == -1 {
                    TfrmLogForm.add(DFormat("#%d", [n]), color: 0x800080)
                    throw EAbort()
                } else {
                    TfrmLogForm.add(DFormat("#%d", [n]), color: 0xFF)
                    throw EAbort()
                }
            }
        }
        if multiESCCapable && (flashed > 0 || result == 0) { checkMultiESC(1, escSlotCount) }
        selectESC(masterESC, load: true)
        return result != 0
    }

    // MARK: - Flash Assistant / file selection (FUN_00665B2C)

    /// Returns 1 = flashed, 0 = failed, -1 = cancelled.
    func flashOne(mem: [UInt8]?, file: Bool, blheli isBLHeli: Bool) throws -> Int {
        guard let db else { return 0 }
        if !file {
            let ignoreAllowed = !bootloaderInterfaceLocked && expertMode
            let current: TBLHeli? = blheli[escNo].isValid ? blheli[escNo] : nil
            let (entry, pickFile) = TfrmFlashAssistant.execute(db: db, mcu: deviceMCUCode, current: current, escTitle: escText,
                                                               ignoreMCUAllowed: ignoreAllowed)
            if let e = entry {
                if Brand.current == 1 {
                    return try flashSiLabs(mem: mem, image: db.flashImage(e), fileName: nil) ? 1 : 0
                }
                return try flashAtmel(mem: mem, flash: db.flashImage(e), eeprom: db.eepromImage(e), fileName: nil, entry: e) ? 1 : 0
            }
            guard pickFile else { return -1 }
        }
        let filter = Brand.current == 1 || isBLHeli ? "Hex file (*.hex)|*.hex" : "Hex file (*.hex;*.eep)|*.hex;*.eep"
        guard let url = OpenDialog.execute(filter: filter, initialDir: AppFolders.hexFolder) else { return -1 }
        AppFolders.hexFolder = url.deletingLastPathComponent()
        return try flashFile(mem: mem, url: url, blheli: isBLHeli)
    }

    /// FUN_0066546C: flash a hex (and eep) file.
    func flashFile(mem: [UInt8]?, url: URL, blheli: Bool) throws -> Int {
        let image: MemoryImage
        do {
            image = try MemoryImage.loadIntelHex(url: url)
        } catch {
            MsgDlg.error(error.localizedDescription)
            return 0
        }
        if Brand.current == 1 {
            return try flashSiLabs(mem: mem, image: image, fileName: url.lastPathComponent) ? 1 : 0
        }
        var eep: MemoryImage?
        let eepURL = url.deletingPathExtension().appendingPathExtension("eep")
        if url.pathExtension.lowercased() == "eep" {
            eep = image
        } else if FileManager.default.fileExists(atPath: eepURL.path) {
            eep = try? MemoryImage.loadIntelHex(url: eepURL)
        }
        let flash = url.pathExtension.lowercased() == "eep" ? MemoryImage() : image
        return try flashAtmel(mem: mem, flash: flash, eeprom: eep, fileName: url.lastPathComponent, entry: nil) ? 1 : 0
    }

    /// FUN_00661944 / Self+0x87C based: memory locked at a bootloader interface.
    var bootloaderInterfaceLocked: Bool { intf.rawValue < 2 ? false : slots[escNo].locked }

    /// FUN_0066F60C: MCU class code of the connected device.
    var deviceMCUCode: Int {
        guard let d = targetDevice else { return 0 }
        return FirmwareSelection.databaseCode(for: d) ?? 0
    }

    // MARK: - SiLabs flash (FUN_0066AC14)

    func flashSiLabs(mem: [UInt8]?, image: MemoryImage, fileName: String?) throws -> Bool {
        guard let dev = targetDevice, let prog = programmer else { return false }
        if image.isEmpty { MsgDlg.error("CodeMem empty."); throw EAbort() }
        let newBL = TBLHeli(isS: false)
        let plan0 = FlashPlan(flash: image, title: fileName ?? "")
        guard let defaults = plan0.defaultSettings, (try? newBL.load(raw: defaults.raw)) != nil else {
            setStatusESC(NL("!!!CAUTION!!!\\n\\nEither the Flash file is wrong or corrupted\\nor of an unsupported revision."))
            MsgDlg.error(statusText)
            throw EAbort()
        }
        let nr = newBL.revNum
        if (nr >= 0x65E && nr <= 0x667) || (nr >= 0x5BE && nr <= 0x5C7) {
            setStatusESC(DFormat(NL("!!!CAUTION!!!\\n\\nThe flash file is of an unsupported revision: %s\\nIt is not recommended to ignore this warning!"),
                                 [newBL.revisionString]))
            if MsgDlg.show(statusText, .mtError, [.mbCancel, .mbIgnore]) != mrIgnore { throw EAbort() }
        }
        if newBL.layoutTag(db) == "FC_Fairy_30A" && nr >= 0x5A0 && nr <= 0x5C8 {
            setStatusESC(DFormat(NL("!!!CAUTION!!!\\n\\nThe \"%s\" flash file is of an unsupported revision: %s"),
                                 [newBL.layoutTag(db), newBL.revisionString]))
            if MsgDlg.show(statusText, .mtError, [.mbCancel]) != mrIgnore { throw EAbort() }
        }
        if !connectESC(true) { throw EAbort() }

        var curName = "", line2 = "", unknownText = ""
        var fUnknown = false, fSevere = true, fMode = false, fRev = false, fMCU = false
        switch readResult {
        case .unknown:
            curName = NL("Unknown ESC"); line2 = NL("(Unknown layout)")
            unknownText = NL("WARNING: The code memory will be erased.") + "\r\n" + NL("After doing so, there is no way back to the original state....")
            fUnknown = true
        case .locked:
            curName = NL("Brand new ESC"); line2 = NL("(code memory locked)")
            unknownText = NL("Just to let You know:") + "\r\n\r\n" + NL("The original Firmware will be erased.") + "\r\n" +
                NL("After doing so, there is no way back") + "\r\n" + NL("to the Vendor supplied state....")
            fUnknown = true
        case .erased:
            curName = NL("Erased ESC"); line2 = NL("(code memory empty)")
        default:
            fSevere = false
        }
        var mcuText = ""
        if deviceMCUCode != newBL.mcuCode {
            mcuText = NL("Found different MCU classes!") + "\r\n" + NL("Current Target: ") + escText + ": " + mcuClassName(deviceMCUCode) +
                "\r\n" + NL("Hex File is for: ") + mcuClassName(newBL.mcuCode)
            if !expertMode {
                MsgDlg.error(mcuText)
                throw EAbort()
            }
            if MsgDlg.show(mcuText, .mtError, [.mbCancel, .mbIgnore]) != mrIgnore { throw EAbort() }
            fMCU = true
        }
        var severeText = "", modeText = "", revText = ""
        var old: TBLHeli?
        if let m = mem, !m.isEmpty {
            let o = TBLHeli(isS: false)
            if (try? o.load(raw: m)) != nil {
                old = o
                let st = o.revisionStatus(db)
                let oldLayout = o.layoutTag(db), oldRev = o.revisionString
                if st < 0 {
                    if st == -1 {
                        let q = NL("                                      ! ! !  S E V E R E  W A R N I N G ! ! !") + "\r\n\r\n" +
                            NL("Unknown or undocumented modified BLHeli \"" + oldLayout + "\" revision \"") + oldRev + NL("\" found!") + "\r\n\r\n" +
                            NL("Flashing this ESC with an inappropriate hex file, may cause severe damage of ") + escText + "\r\n" +
                            NL("                                                 and/or your motor!") + "\r\n\r\n" +
                            NL("                                                  Continue anyway?") + "\r\n"
                        if MsgDlg.show(q, .mtWarning, [.mbYes, .mbNo]) != mrYes { throw EAbort() }
                        severeText = NL("! ! !  S E V E R E  W A R N I N G ! ! !") + "\r\n\r\n" +
                            NL("Unknown or undocumented modified BLHeli \"" + oldLayout + "\" revision \"") + oldRev + NL("\" found!") + "\r\n\r\n" +
                            NL("Selected hex file is for: ") + newBL.layoutDescription(db)
                        fSevere = true
                    } else if readResult == .removed {
                        if oldLayout != newBL.layoutTag(db) {
                            severeText = NL("Found different ESC Layouts!") + "\r\n" + NL("Current Target ") + escText + ": " + oldLayout + "\r\n" +
                                NL("Selected hex File is for: ") + newBL.layoutTag(db)
                            fSevere = true
                        }
                    } else {
                        severeText = NL("BLHeli \"" + oldLayout + "\" revision \"") + oldRev + NL("\" found!") + "\r\n" + NL("\"") + oldLayout +
                            NL("\" is only included in the current hex repository with a higher revision number.") + "\r\n" +
                            NL("This might be a hint, that the ESC was produced with a beta hex file.")
                        fSevere = true
                    }
                } else if o.layoutIndex(db) != newBL.layoutIndex(db) {
                    severeText = NL("Found different ESC Layouts!") + "\r\n" + NL("Current Target ") + escText + ": " + o.layoutDescription(db) + "\r\n" +
                        NL("Hex File is for: ") + newBL.layoutDescription(db)
                    fSevere = true
                }
                if o.mode != newBL.mode {
                    modeText = NL("Found different ESC modes!") + "\r\n" + NL("Current ") + escText + " Mode (" + o.modeName + ")" + "\r\n" +
                        NL(" does not match ESC Mode of the Hex File") + " (" + newBL.modeName + ")"
                    fMode = true
                }
                if !o.isFlashFailed {
                    if o.revNum > newBL.revNum {
                        revText = escText + NL(" Firmware Revision is higher: ") + o.revisionString + "\r\n" +
                            NL("than the Revision of the Hex File: ") + newBL.revisionString
                        fRev = true
                    } else if o.revNum == newBL.revNum {
                        revText = escText + NL(" and Hex File have the same Firmware Revision: ") + o.revisionString
                        fRev = true
                    }
                }
                if !o.name.isEmpty { curName = "\"" + o.name + "\" " }
                curName += oldLayout + " (" + o.modeName + ") " + "BLHeli Rev: " + o.revisionString
            }
        }
        var newName = newBL.name.isEmpty ? "" : "\"" + newBL.name + "\" "
        newName += newBL.layoutTag(db) + " (" + newBL.modeName + ") " + "BLHeli Rev: " + newBL.revisionString
        let flashTo2 = fileName.map { "(" + $0 + ")" } ?? ""
        if !line2.isEmpty { line2 += "\r\n" }
        let info = NL("Do You want to flash target ") + escText + " : " + "\r\n" + curName + "\r\n" + line2 + NL("to:")
        if [.silBLBCom, .silBLB4wif, .silBLBCF].contains(intf) && newBL.revNum < 0x84 {
            setStatusESC(NL("Flash file is of rev ") + newBL.revisionString + "\r\n" + NL("and cannot be flashed over a bootloader"))
            MsgDlg.error("               " + statusText)
            throw EAbort()
        }
        var severe = fUnknown ? unknownText : ""
        if fMCU { if !severe.isEmpty { severe += "\r\n\r\n" }; severe += mcuText }
        if fSevere { if !severe.isEmpty { severe += "\r\n\r\n" }; severe += severeText }
        if fSevere || fMCU {
            if !severe.isEmpty { severe += "\r\n\r\n" }
            severe += NL(Res.choosingWrongMCU)
        }
        var warning = ""
        if fMode { warning = modeText }
        if !fMCU && !fUnknown && !fMode && !fSevere && fRev {
            if !warning.isEmpty { warning += "\r\n\r\n" }
            warning += revText
        }
        let dlg = TfrmConfirmFlash(resource: "TFRMCONFIRMFLASH", owner: self)
        dlg.brand = 1
        dlg.severeText = severe
        dlg.warningText = warning
        dlg.infoText = info
        dlg.flashToText = newName
        dlg.flashTo2Text = flashTo2
        let yes = dlg.execute() == 1
        dlg.release()
        if !yes { throw EAbort() }

        // write the flash (FUN_0067AF08) – the image is written as is, the old settings are offered afterwards
        let t0 = Date()
        let ops = ESCOperations(programmer: prog)
        ops.verify = true
        let infoForm = TfrmInfo.showInfo(NL("Flashing ") + escText + " ...", cancel: false)
        ops.onProgress = { [weak infoForm] p in
            infoForm?.setProgress(Int(p.fraction * 1000), 1000)
            Application.shared.processMessages()
        }
        Led_Write.isOn = true
        do {
            defer { Led_Write.isOn = false; infoForm.hideInfo() }
            try ops.flash(plan0, device: dev, currentSettings: nil)
        } catch {
            if error is SerialError { connectionLost() }
            setStatusESC(escText + ": " + NL("Flashing failed!") + "\r\n" + error.localizedDescription)
            MsgDlg.error(statusText)
            return false
        }
        let elapsed = Self.elapsedSeconds(since: t0)
        guard let back = readSetupMem() else { return false }
        let cur = current
        guard (try? cur.load(raw: back)) != nil, newBL.sameAs(cur, compareName: true, syncThrottle: true, syncDirection: true, db) else { return false }
        setStatusESC(escText + NL(": Flashed File ") + "\r\n" + newBL.layoutTag(db) + "\r\n" +
                     NL("successfully in " + Self.floatToStr(elapsed) + " s"))
        MsgDlg.show(statusText + NL("\\n\\n" + Res.keepCaution), .mtInformation, [.mbOK])
        if let o = old, cur.mode == o.mode {
            let same = cur.sameAs(o, compareName: isMaster && !o.isFlashFailed,
                                  syncThrottle: isMaster || actMergeThrottle.checked,
                                  syncDirection: isMaster || actMergeMotorDir.checked, db)
            if !same {
                if MsgDlg.show(NL("Do You want to write current setting to ") + escText + " ?", .mtConfirmation, [.mbYes, .mbNo]) == mrYes {
                    let saved = workspace
                    workspace = o
                    _ = writeSetupESC(compareName: !o.isFlashFailed, syncDirection: true, syncThrottle: true)
                    workspace = saved
                    if isMaster && connectESC(true), let m = readSetupMem() {
                        try? workspace.load(raw: m)
                        showESCData()
                    }
                    return true
                }
            }
        }
        if isMaster {
            try? workspace.load(raw: back)
            showESCData()
        }
        return true
    }

    /// Delphi FloatToStr (general format, 15 significant digits).
    /// GetTickCount difference / 1000 (millisecond resolution like the original).
    static func elapsedSeconds(since t0: Date) -> Double { Double(Int(Date().timeIntervalSince(t0) * 1000)) / 1000.0 }

    static func floatToStr(_ v: Double) -> String {
        var s = String(format: "%.15g", v)
        if s.contains("e") { s = String(v) }
        return s
    }

    // MARK: - Atmel flash (FUN_00665FE0)

    func flashAtmel(mem: [UInt8]?, flash: MemoryImage, eeprom: MemoryImage?, fileName: String?, entry: FirmwareEntry?) throws -> Bool {
        guard let dev = targetDevice, let prog = programmer else { return false }
        if readResult == .locked && intf != .atmISP {
            let m = NL("The Memory of ") + escText + NL(" seems to be locked.") + "\r\n\r\n" + NL("(Typical for newly acquired ESCs)") + "\r\n\r\n" +
                NL("You cannot flash locked ESC with current bootloader interface.") + "\r\n" + NL("Please use a ISP 6-pin interface type!")
            setStatusESC(m)
            MsgDlg.error(m)
            throw EAbort()
        }
        let newBL = TBLHeli(isS: false)
        var plan = FlashPlan(flash: flash, eeprom: eeprom, title: fileName ?? "")
        let isBLHeliFile = plan.defaultSettings.map { (try? newBL.load(raw: $0.raw)) != nil } ?? false
        if !isBLHeliFile && eeprom != nil && fileName == nil {
            setStatusESC(NL("!!!CAUTION!!!\r\n\r\nEither the Flash/EEprom file is wrong or corrupted\r\nor of an unsupported revision."))
            MsgDlg.error(statusText)
            throw EAbort()
        }
        if !connectESC(true) { throw EAbort() }
        var curName = "", line2 = "", unknownText = ""
        var fUnknown = false, fSevere = readResult != .ok, fMode = false, fRev = false, fMCU = false
        switch readResult {
        case .unknown:
            curName = NL("Unknown ESC"); line2 = NL("(Unknown layout)")
            unknownText = isBLHeliFile
                ? NL("WARNING: The EEProm memory will be overriden.") + "\r\n" + NL("After doing so, the way back original state needs the original EEprom file....")
                : NL("WARNING: The code memory will be erased.") + "\r\n" + NL("After doing so, there is no way back to the original state....")
            fUnknown = true
        case .locked:
            curName = NL("Brand new ESC"); line2 = NL("(code memory locked)")
            unknownText = NL("Just to let You know:") + "\r\n\r\n" + NL("The original Firmware will be erased.") + "\r\n" +
                NL("After doing so, there is no way back") + "\r\n" + NL("to the Vendor supplied state....")
            fUnknown = true
        case .erased:
            curName = NL("Unkown or erased ESC"); line2 = NL("(EEprom empty)")
        default:
            fSevere = false
        }
        var mcuText = ""
        if isBLHeliFile && newBL.mcuCode != 0 && deviceMCUCode != newBL.mcuCode {
            mcuText = NL("Found different MCU classes!") + "\r\n" + NL("Current Target: ") + escText + ": " + mcuClassName(deviceMCUCode) +
                "\r\n" + NL("Hex File is for: ") + mcuClassName(newBL.mcuCode)
            if !expertMode { MsgDlg.error(mcuText); throw EAbort() }
            if MsgDlg.show(mcuText, .mtError, [.mbCancel, .mbIgnore]) != mrIgnore { throw EAbort() }
            fMCU = true
        }
        var severeText = "", modeText = "", revText = ""
        var old: TBLHeli?
        if let m = mem, !m.isEmpty {
            let o = TBLHeli(isS: false)
            if (try? o.load(raw: m)) != nil {
                old = o
                if isBLHeliFile {
                    if o.layoutIndex(db) != newBL.layoutIndex(db) {
                        severeText = NL("Found different ESC Layouts!") + "\r\n" + NL("Current Target ") + escText + ": " + o.layoutDescription(db) + "\r\n" +
                            NL("Selected hex File is for: ") + newBL.layoutDescription(db)
                        fSevere = true
                    }
                    if o.mode != newBL.mode {
                        modeText = NL("Found different ESC modes!") + "\r\n" + NL("Current ") + escText + " Mode (" + o.modeName + ")" + "\r\n" +
                            NL(" does not match ESC Mode of the Hex File") + " (" + newBL.modeName + ")"
                        fMode = true
                    }
                    if !o.isFlashFailed {
                        if o.revNum > newBL.revNum {
                            revText = escText + NL(" Firmware Revision is higher: ") + o.revisionString + "\r\n" +
                                NL("than the Revision of the Hex File: ") + newBL.revisionString
                            fRev = true
                        } else if o.revNum == newBL.revNum {
                            revText = escText + NL(" and Hex File have the same Firmware Revision: ") + o.revisionString
                            fRev = true
                        }
                    }
                } else {
                    severeText = NL("! ! !  W A R N I N G ! ! !") + "\r\n\r\n" + NL("You are about to flash a BLHeli ESC with an unknown firmware file.")
                    fSevere = true
                }
                if !o.name.isEmpty { curName = "\"" + o.name + "\" " }
                curName += o.layoutTag(db) + " (" + o.modeName + ") " + "BLHeli Rev: " + o.revisionString
            }
        }
        var newName: String
        if isBLHeliFile {
            newName = newBL.name.isEmpty ? "" : "\"" + newBL.name + "\" "
            newName += newBL.layoutTag(db) + " (" + newBL.modeName + ") " + "BLHeli Rev: " + newBL.revisionString
        } else {
            newName = NL("SimonK or WiiESC ESC \"") + (fileName ?? "") + "\""
        }
        let flashTo2 = fileName.map { "(" + $0 + ")" } ?? ""
        if !line2.isEmpty { line2 += "\r\n" }
        let info = NL("Do You want to flash target ") + escText + " : " + "\r\n" + curName + "\r\n" + line2 + NL("to:")
        var severe = fUnknown ? unknownText : ""
        if fMCU { if !severe.isEmpty { severe += "\r\n\r\n" }; severe += mcuText }
        if fSevere && !severeText.isEmpty { if !severe.isEmpty { severe += "\r\n\r\n" }; severe += severeText }
        if fSevere || fMCU {
            if !severe.isEmpty { severe += "\r\n\r\n" }
            severe += NL(Res.choosingWrongMCU)
        }
        var warning = fMode ? modeText : ""
        if !fMCU && !fUnknown && !fMode && !fSevere && fRev { warning = revText }
        if intf == .atmISP, let e = entry {
            let x = FirmwareSelection.ispExtras(db!, entry: e)
            plan.ispBootloader = x.bootloader
            plan.ispFuses = x.fuses
        }
        let dlg = TfrmConfirmFlash(resource: "TFRMCONFIRMFLASH", owner: self)
        dlg.brand = 2
        dlg.severeText = severe
        dlg.warningText = warning
        dlg.infoText = info
        dlg.flashToText = newName
        dlg.flashTo2Text = flashTo2
        dlg.plan = plan
        let res = dlg.execute()
        if let f = dlg.fuses { plan.ispFuses = f }
        if dlg.bootloaderChoice == 4 { plan.ispBootloader = nil }
        dlg.release()
        if res == 0 { throw EAbort() }
        let t0 = Date()
        let ops = ESCOperations(programmer: prog)
        ops.verify = true
        let infoForm = TfrmInfo.showInfo(NL("Flashing ") + escText + " ...", cancel: false)
        ops.onProgress = { [weak infoForm] p in
            infoForm?.setProgress(Int(p.fraction * 1000), 1000)
            Application.shared.processMessages()
        }
        Led_Write.isOn = true
        do {
            defer { Led_Write.isOn = false; infoForm.hideInfo() }
            try ops.flash(plan, device: dev, currentSettings: nil)
        } catch {
            if error is SerialError { connectionLost() }
            setStatusESC(escText + ": " + NL("Flashing failed!") + "\r\n" + error.localizedDescription)
            MsgDlg.error(statusText)
            return false
        }
        let elapsed = Self.elapsedSeconds(since: t0)
        // 0x668E42: Format(': Flashed\n%s\nsuccessfully in %.2f s', [target, ticks / 1000])
        setStatusESC(escText + NL(String(format: ": Flashed\\n%@\\nsuccessfully in %.2f s", newName, elapsed)))
        MsgDlg.show(statusText + NL("\\n\\n" + Res.keepCaution), .mtInformation, [.mbOK])
        guard isBLHeliFile, let back = readSetupMem() else { return true }
        let cur = current
        if (try? cur.load(raw: back)) != nil, let o = old, cur.mode == o.mode,
           !cur.sameAs(o, compareName: isMaster && !o.isFlashFailed, syncThrottle: isMaster || actMergeThrottle.checked,
                       syncDirection: isMaster || actMergeMotorDir.checked, db) {
            if MsgDlg.show(NL("Do You want to write current setting to ") + escText + " ?", .mtConfirmation, [.mbYes, .mbNo]) == mrYes {
                let saved = workspace
                workspace = o
                _ = writeSetupESC(compareName: !o.isFlashFailed, syncDirection: true, syncThrottle: true)
                workspace = saved
            }
        }
        if isMaster, let m = readSetupMem() {
            try? workspace.load(raw: m)
            showESCData()
        }
        return true
    }
}
