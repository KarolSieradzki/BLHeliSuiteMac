import AppKit
import VCL
import BLHeliCore

// "Expert tools" page, setup files and the remaining actions of TfrmBLHeliSuiteMain.

extension TfrmBLHeliSuiteMain {
    // MARK: - address fields (edtGetStartAddressChange 0x664E08 …)

    /// Hex ("0x1A00", "$1A00") or decimal value of an address field.
    func parseNumber(_ s: String) -> Int? {
        var t = s.trimmingCharacters(in: .whitespaces)
        if let r = t.range(of: " ") { t = String(t[..<r.lowerBound]) }
        if t.lowercased().hasPrefix("0x") { return Int(t.dropFirst(2), radix: 16) }
        if t.hasPrefix("$") { return Int(t.dropFirst(), radix: 16) }
        return Int(t)
    }

    var memIsFlash: Bool { rgpMemType.itemIndex == 0 }

    var readStart: Int { parseNumber(edtGetStartAddress.text) ?? 0 }
    var readLength: Int { parseNumber(edtGetLength.text) ?? 0 }

    @objc func edtGetStartAddressChange(_ sender: TObject) {
        guard !addressUpdating, let a = parseNumber(edtGetStartAddress.text), let stop = parseNumber(edtGetStopAdress.text) else { return }
        addressUpdating = true
        edtGetLength.text = String(format: "0x%X", max(0, stop - a + 1))
        addressUpdating = false
    }

    @objc func edtGetStopAdressChange(_ sender: TObject) {
        guard !addressUpdating, let stop = parseNumber(edtGetStopAdress.text) else { return }
        let a = readStart
        guard stop >= a else { return }
        addressUpdating = true
        edtGetLength.text = String(format: "0x%X", stop - a + 1)
        addressUpdating = false
    }

    @objc func edtGetLengthChange(_ sender: TObject) {
        guard !addressUpdating, let n = parseNumber(edtGetLength.text), n > 0 else { return }
        addressUpdating = true
        edtGetStopAdress.text = String(format: "0x%X", readStart + n - 1)
        addressUpdating = false
    }

    /// edtSetStartAddressChange (0x664B40): decimal and hex value as hint.
    @objc func edtSetStartAddressChange(_ sender: TObject) {
        guard let a = parseNumber(edtSetStartAddress.text) else { edtSetStartAddress.hint = ""; return }
        edtSetStartAddress.hint = edtSetStartAddress.text + " Dec: " + String(a) + String(format: " Hex: 0x%02X", a)
    }

    /// edtAdressKeyPress (0x664C2C): digits, hex letters, "x", "$", backspace and return.
    /// edtAdressKeyPress (0x664C2C): decimal numbers, hex after a leading "$" or "0x" (letters upper case).
    @objc func edtAdressKeyPress(_ sender: TObject, _ args: TKeyArgs) {
        let c = args.key
        guard c != "\u{8}", c != "\r", let e = sender as? TEdit else { return }
        let s = Array(e.text)
        func hexDigit() {
            if c.isNumber && c.isASCII { return }
            if c.isHexDigit { args.key = Character(c.uppercased()) } else { args.key = "\0" }
        }
        if !s.isEmpty && s[0] == "$" {
            hexDigit()
        } else if s.count > 1 && s[0] == "0" && (s[1] == "x" || s[1] == "X") {
            hexDigit()
        } else if c == "$" {
            args.key = s.isEmpty ? "$" : "\0"
        } else if !(c.isNumber && c.isASCII) {
            args.key = (c == "x" || c == "X") && s.count == 1 && s[0] == "0" ? "x" : "\0"
        }
    }

    /// edtSetMemKeyPress (0x664DC4): hex digits (upper case), separators.
    @objc func edtSetMemKeyPress(_ sender: TObject, _ args: TKeyArgs) {
        let c = args.key
        if c == "\u{8}" || c == "\r" || c == " " || c == "," { return }
        if c.isHexDigit { args.key = Character(c.uppercased()); return }
        args.key = "\0"
    }

    /// rgpMemTypeClick (0x6783D0): default ranges of flash / EEPROM.
    @objc func rgpMemTypeClick(_ sender: TObject) {
        addressUpdating = true
        if rgpMemType.itemIndex == 0 {
            edtGetStartAddress.text = "0x00"
            edtGetLength.text = "0x2000"
            edtGetStopAdress.text = "0x1FFF"
            edtSetStartAddress.text = "0x00"
            cbxPersistFlashWriteMem.enabled = true
        } else if rgpMemType.itemIndex == 1 {
            edtGetStartAddress.text = "0x00"
            edtGetLength.text = "0x200"
            edtGetStopAdress.text = "0x1FF"
            edtSetStartAddress.text = "0x00"
            cbxPersistFlashWriteMem.enabled = false
        }
        addressUpdating = false
    }

    // MARK: - memory access

    /// Master ESC connected (FUN_00663EC8).
    func connectForExpertTool() -> Bool {
        selectESC(masterESC, load: true)
        if !intfConnected && !connectInterface(true) { return false }
        if targetDevice == nil && !connectESC(true) { return false }
        return programmer != nil && targetDevice != nil
    }

    @objc func actReadMemExecute(_ sender: TObject) {
        TfrmLogForm.addBlue(NL("Read Memory:"))
        TfrmLogForm.indent(1)
        var data: [UInt8]?
        if connectForExpertTool(), let p = programmer {
            Screen.busy = true
            Led_Read.isOn = true
            data = try? memIsFlash ? p.readFlash(address: readStart, count: readLength, progress: nil)
                                    : p.readEEPROM(address: readStart, count: readLength)
            Led_Read.isOn = false
            Screen.busy = false
        }
        TfrmLogForm.indent(-1)
        TfrmLogForm.result(data != nil)
        if let d = data {
            var img = MemoryImage()
            img.write(d, at: readStart)
            TfrmMemoView.show(img, title: escText + (memIsFlash ? " Flash" : " EEprom"), fileName: nil)
        } else {
            MsgDlg.error(DFormat(NL(Res.couldNotConnectESC), [escText]))
        }
    }

    /// Hex bytes of edtSetMem ("01 02 0A", "01,02").
    var bytesToWrite: [UInt8]? {
        let parts = edtSetMem.text.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        var out: [UInt8] = []
        for p in parts {
            var t = p
            if t.lowercased().hasPrefix("0x") { t.removeFirst(2) }
            if t.count > 2 {
                var i = t.startIndex
                while i < t.endIndex {
                    let j = t.index(i, offsetBy: 2, limitedBy: t.endIndex) ?? t.endIndex
                    guard let b = UInt8(t[i..<j], radix: 16) else { return nil }
                    out.append(b)
                    i = j
                }
            } else {
                guard let b = UInt8(t, radix: 16) else { return nil }
                out.append(b)
            }
        }
        return out.isEmpty ? nil : out
    }

    /// actWriteMemExecute (0x67C18C).
    @objc func actWriteMemExecute(_ sender: TObject) {
        guard let bytes = bytesToWrite, let addr = parseNumber(edtSetStartAddress.text) else {
            MsgDlg.error(NL("Invalid Parameter"))
            return
        }
        guard connectForExpertTool(), let p = programmer, let dev = targetDevice else { return }
        let q = DFormat(NL("Write %d byte(s) to %s address 0x%X of %s?"), [bytes.count, memIsFlash ? "Flash" : "EEprom", addr, escText])
        guard MsgDlg.show(q, .mtConfirmation, [.mbYes, .mbNo]) == mrYes else { return }
        Screen.busy = true
        Led_Write.isOn = true
        defer { Led_Write.isOn = false; Screen.busy = false }
        do {
            if memIsFlash {
                if cbxPersistFlashWriteMem.checked {
                    // keep the rest of the page: read, erase, write the whole page
                    let ps = dev.pageSize
                    let first = (addr / ps) * ps
                    let last = ((addr + bytes.count - 1) / ps) * ps
                    var page = first
                    while page <= last {
                        var d = try p.readFlash(address: page, count: ps, progress: nil)
                        for (i, b) in bytes.enumerated() where addr + i >= page && addr + i < page + ps { d[addr + i - page] = b }
                        try p.erasePage(address: page)
                        try p.writeFlash(address: page, data: d, progress: nil)
                        page += ps
                    }
                } else {
                    try p.writeFlash(address: addr, data: bytes, progress: nil)
                }
            } else {
                try p.writeEEPROM(address: addr, data: bytes, progress: nil)
            }
            TfrmLogForm.result(true)
        } catch {
            TfrmLogForm.result(false)
            MsgDlg.error(error.localizedDescription)
        }
    }

    /// actDeviceErasePageExecute (0x65E434): page of the start address.
    @objc func actDeviceErasePageExecute(_ sender: TObject) {
        guard connectForExpertTool(), let p = programmer, let dev = targetDevice else { return }
        let page = readStart / dev.pageSize
        guard MsgDlg.show(DFormat(NL("Erase flash page %d (0x%X…0x%X) of %s?"), [page, page * dev.pageSize, (page + 1) * dev.pageSize - 1, escText]),
                          .mtConfirmation, [.mbYes, .mbNo]) == mrYes else { return }
        do { try p.erasePage(address: page * dev.pageSize) } catch { MsgDlg.error(error.localizedDescription) }
    }

    /// actDeviceEraseMultiplePagesExecute (0x65E3D8).
    @objc func actDeviceEraseMultiplePagesExecute(_ sender: TObject) {
        guard connectForExpertTool(), let p = programmer, let dev = targetDevice else { return }
        let f = TfrmErasePageDlg(resource: "TFRMERASEPAGEDLG", owner: self)
        defer { f.release() }
        f.prepare(pageSize: dev.pageSize, pages: dev.userFlashSize / dev.pageSize)
        guard f.showModal() == mrOk else { return }
        Screen.busy = true
        defer { Screen.busy = false }
        do {
            for page in f.speFirstPage.intValue...max(f.speFirstPage.intValue, f.speLastPage.intValue) {
                try p.erasePage(address: page * dev.pageSize)
            }
        } catch {
            MsgDlg.error(error.localizedDescription)
        }
    }

    /// actEraseChipExecute (0x67CB5C).
    @objc func actEraseChipExecute(_ sender: TObject) {
        selectESC(masterESC, load: true)
        guard MsgDlg.show(DFormat(NL("Erase the complete flash memory of %s?"), [escText]), .mtWarning, [.mbYes, .mbNo]) == mrYes else { return }
        guard connectForExpertTool(), let p = programmer else { return }
        Screen.busy = true
        defer { Screen.busy = false }
        do {
            try p.eraseChip()
            setStatus(escText + NL(" erased"))
        } catch {
            MsgDlg.error(error.localizedDescription)
        }
    }

    /// actFlashAnyFileExecute (0x67B48C): any hex/eep file, no BLHeli checks.
    @objc func actFlashAnyFileExecute(_ sender: TObject) {
        guard let url = OpenDialog.execute(filter: "Hex file (*.hex;*.eep)|*.hex;*.eep", initialDir: AppFolders.hexFolder) else { return }
        AppFolders.hexFolder = url.deletingLastPathComponent()
        guard let img = try? MemoryImage.loadIntelHex(url: url) else { MsgDlg.error(NL("Invalid Package")); return }
        guard connectForExpertTool(), let p = programmer, let dev = targetDevice else { return }
        let eeprom = url.pathExtension.lowercased() == "eep"
        guard MsgDlg.show(DFormat(NL("Flash %s with \"%s\"?"), [escText, url.lastPathComponent]), .mtConfirmation, [.mbYes, .mbNo]) == mrYes else { return }
        let n = (img.highestAddress ?? -1) + 1
        let info = TfrmInfo.showInfo(NL("Flashing ") + escText + " ...", cancel: false)
        Screen.busy = true
        defer { Screen.busy = false; info.hideInfo() }
        do {
            if eeprom {
                try p.writeEEPROM(address: 0, data: img.read(0, n), progress: nil)
            } else {
                let ps = dev.pageSize
                var a = 0
                while a < n {
                    let d = img.read(a, min(ps, n - a))
                    if dev.family == .silabs { try p.erasePage(address: a) }
                    if d.contains(where: { $0 != 0xFF }) { try p.writeFlash(address: a, data: d, progress: nil) }
                    a += ps
                    info.setProgress(a, n)
                }
            }
            setStatus(escText + NL(" flashed successfully"))
        } catch {
            MsgDlg.error(error.localizedDescription)
        }
    }

    // MARK: - file viewers

    @objc func actShowHexFileExecute(_ sender: TObject) {
        guard let url = OpenDialog.execute(filter: "Hex file (*.hex;*.eep)|*.hex;*.eep", initialDir: AppFolders.hexFolder) else { return }
        AppFolders.hexFolder = url.deletingLastPathComponent()
        do {
            TfrmMemoView.show(try MemoryImage.loadIntelHex(url: url), title: url.lastPathComponent, fileName: url)
        } catch {
            MsgDlg.error(error.localizedDescription)
        }
    }

    @objc func actShowBinaryFileExecute(_ sender: TObject) {
        guard let url = OpenDialog.execute(filter: "Binary file (*.bin or *.*)|*.bin;*.*", initialDir: AppFolders.hexFolder),
              let d = try? Data(contentsOf: url) else { return }
        AppFolders.hexFolder = url.deletingLastPathComponent()
        TfrmMemoView.show(MemoryImage(contiguous: [UInt8](d)), title: url.lastPathComponent, fileName: url)
    }

    /// actIdentifyFlashMemoryExecute (0x661220).
    @objc func actIdentifyFlashMemoryExecute(_ sender: TObject) {
        if Brand.current == 1 { MsgDlg.show(NL("Sorry, not supported yet..."), .mtInformation, [.mbOK]); return }
        guard Brand.current == 2, let db, connectForExpertTool(), let p = programmer, let dev = targetDevice else { return }
        Screen.busy = true
        let flash = try? p.readFlash(address: 0, count: dev.userFlashSize, progress: nil)
        Screen.busy = false
        guard let f = flash else { MsgDlg.error(DFormat(NL(Res.couldNotConnectESC), [escText])); return }
        var best: (FirmwareEntry, Int)?
        for e in db.entries(family: .atmel, mcuCode: Int(dev.mcu?.signature ?? 0)) + db.entries(family: .atmel, mcuCode: 0) {
            let img = db.flashImage(e)
            var same = 0
            for (a, b) in img.bytes where a < f.count && f[a] == b { same += 1 }
            let score = img.bytes.isEmpty ? 0 : same * 100 / img.bytes.count
            if score > (best?.1 ?? 0) { best = (e, score) }
        }
        if let (e, score) = best, score >= 90 {
            MsgDlg.show(DFormat(NL("%s: %s %s Rev. %s (%d%% identical)"), [escText, e.name, e.isS != 0 ? "BLHeli_S" : "BLHeli", e.revStr, score]), .mtInformation, [.mbOK])
        } else {
            MsgDlg.show(escText + NL(": Erased or of unknown firmware"), .mtInformation, [.mbOK])
        }
    }

    /// actVerifyFlashMemoryExecute (0x67C9A4): compares the ESC flash with a hex file.
    @objc func actVerifyFlashMemoryExecute(_ sender: TObject) {
        guard let url = OpenDialog.execute(filter: "Hex file (*.hex)|*.hex", initialDir: AppFolders.hexFolder),
              let img = try? MemoryImage.loadIntelHex(url: url) else { return }
        guard connectForExpertTool(), let p = programmer, let dev = targetDevice else { return }
        Screen.busy = true
        let n = min((img.highestAddress ?? -1) + 1, dev.flashSize)
        let flash = try? p.readFlash(address: 0, count: n, progress: nil)
        Screen.busy = false
        guard let f = flash else { MsgDlg.error(DFormat(NL(Res.couldNotConnectESC), [escText])); return }
        var diffs: [(Int, UInt8, UInt8)] = []
        for (a, b) in img.bytes.sorted(by: { $0.key < $1.key }) where a < f.count && f[a] != b { diffs.append((a, b, f[a])) }
        TfrmCompareResults.show(diffs, title: url.lastPathComponent + " / " + escText)
    }

    // MARK: - setup files

    // actSave/ReadSetupTo/FromIniFile, actSave/ReadMultipleESCSetup…: SetupFiles.swift

    /// actReadSetupFromHexFileExecute (0x65FE14): setup block of a flash (SiLabs) or EEPROM (Atmel) hex file.
    @objc func actReadSetupFromHexFileExecute(_ sender: TObject) {
        let filter = Brand.current == 2 ? "EEprom file (*.eep;*.hex)|*.eep;*.hex" : "Hex file (*.hex)|*.hex"
        guard let url = OpenDialog.execute(filter: filter, initialDir: AppFolders.hexFolder),
              let img = try? MemoryImage.loadIntelHex(url: url) else { return }
        AppFolders.hexFolder = url.deletingLastPathComponent()
        let addr = (Brand.current == 1 && url.pathExtension.lowercased() != "eep") ? BLHeliSettings.silabsAddress : 0
        let t = TBLHeli()
        do {
            try t.load(raw: img.read(addr, BLHeliSettings.size))
        } catch {
            MsgDlg.error(error.localizedDescription)
            return
        }
        t.assign(to: workspace)
        if !intfConnected { t.assign(to: current) }
        showESCData()
    }

    /// actAtmSaveSetupAsEEpromFileExecute (0x65E01C → TBLHeli.SaveAsEEprom 0x5A45B8).
    @objc func actAtmSaveSetupAsEEpromFileExecute(_ sender: TObject) {
        guard workspace.isValid else { return }
        guard let url = SaveDialog.execute(fileName: (workspace.layoutName.isEmpty ? "BLHeli" : workspace.layoutName) + ".eep",
                                           filter: "EEprom file (*.eep)|*.eep", initialDir: AppFolders.hexFolder) else { return }
        do {
            try MemoryImage(contiguous: workspace.settings.raw).intelHex().write(to: url, atomically: true, encoding: .ascii)
        } catch {
            MsgDlg.error(error.localizedDescription)
        }
    }

    // MARK: - fuses (actEditFusesExecute 0x67C9C8)

    /// Connects avrdude, identifies the target and reads all fuses, then opens the fuse editor
    /// (device fixed, critical features off: FUN_0062C320(avrdude, False, False)).
    @objc func actEditFusesExecute(_ sender: TObject) {
        var chip: UInt32 = 0
        var sig = 0
        do {
            Screen.busy = true
            defer { Screen.busy = false }
            if !avrdude.connected { try avrdude.connect() }
            guard let isp = avrdude.isp else { return }
            let d = try isp.selectESC(0)
            avrdude.device = d
            sig = Int(d.mcu?.signature ?? 0)
            chip = try isp.readFuseBytes()
        } catch {
            MsgDlg.error(DFormat(NL("Avrdude FAILED!\\n\\n\"%s\""), [error.localizedDescription]))
            return
        }
        if avrdude.bootloaderMode {
            MsgDlg.error(NL("Cannot read fuses in bootloader mode."))
            return
        }
        TfrmFuseEditor.execute(avrdude: avrdude, signature: sig, chip: chip, deviceChangeable: false, critical: false)
    }

    // MARK: - misc

    /// JvFormStorage events: the stored values are handled by restoreStoredValues / saveStoredValues.
    @objc func FormStorageStoredValuesRestore(_ sender: TObject) { restoreStoredValues() }
    @objc func FormStorageStoredValuesSave(_ sender: TObject) { saveStoredValues() }

    @objc func cbxAVRDudeProgsDropDown(_ sender: TObject) {
        if avrdudeProgsWidth == 0 { avrdudeProgsWidth = cbxAVRDudeProgs.width }
        cbxAVRDudeProgs.width = 600
    }
}

/// Fields of the expert page and of the AVRDude combo (+0x880… in the original).
private var addressUpdatingKey = 0
private var progsWidthKey = 0

extension TfrmBLHeliSuiteMain {
    var addressUpdating: Bool {
        get { (objc_getAssociatedObject(self, &addressUpdatingKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &addressUpdatingKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    var avrdudeProgsWidth: Int {
        get { (objc_getAssociatedObject(self, &progsWidthKey) as? Int) ?? 0 }
        set { objc_setAssociatedObject(self, &progsWidthKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}
