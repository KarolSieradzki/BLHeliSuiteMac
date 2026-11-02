import AppKit
import VCL
import BLHeliCore

// "Expert tools" page, setup files and the remaining actions of TfrmBLHeliSuiteMain.

extension TfrmBLHeliSuiteMain {
    // MARK: - address fields (edtGetStartAddressChange 0x664E08 …)

    /// FUN_0065DA7C + FUN_0065DBCC: value of an address field. A leading "$" or "0x" marks a hex number; the prefix
    /// is remembered for the texts written back (empty for decimal numbers). Invalid input raises EConvertError in
    /// the original – shown as error message here.
    func addressValue(_ text: String, _ prefix: inout String) -> Int? {
        var s = text
        guard !s.isEmpty else { return 0 }
        var hex = false
        let c = Array(s)
        if c[0] == "$" {
            s.removeFirst(); prefix = "$"; hex = true
        } else if c[0] == "0", c.count > 1, c[1] == "x" || c[1] == "X" {
            s.removeFirst(2); prefix = "0x"; hex = true
        } else {
            prefix = ""
        }
        guard !s.isEmpty else { return 0 }
        guard hex else {
            guard let v = Int(s.trimmingCharacters(in: .whitespaces)) else {
                MsgDlg.error(DFormat("'%s' is not a valid integer value", [s]))
                return nil
            }
            return v
        }
        var v = 0
        for ch in s.uppercased().unicodeScalars {
            switch ch.value {
            case 0x30...0x39: v = v * 16 + Int(ch.value) - 0x30
            case 0x41...0x46: v = v * 16 + Int(ch.value) - 0x37
            default:
                MsgDlg.error(NL("Invalid hex-number"))
                return nil
            }
        }
        return v
    }

    /// Text of an address field: decimal, or prefix + IntToHex(v, 2).
    func addressText(_ v: Int, _ prefix: String) -> String { prefix.isEmpty ? String(v) : prefix + String(format: "%02X", v) }

    func addressHint(_ title: String, _ v: Int) -> String { NL(title) + " Hex: 0x" + String(format: "%02X", v) + "  Dec: " + String(v) }

    /// edtGetStartAddressChange (0x664E08).
    @objc func edtGetStartAddressChange(_ sender: TObject) {
        let m = expertMem
        guard let v = addressValue(edtGetStartAddress.text, &m.startPrefix) else { return }
        edtGetStartAddress.hint = addressHint("Start:", v)
        m.start = v
        if m.stop < v {
            m.stop = v
            m.length = v - m.start + 1
            edtGetStopAdress.text = addressText(m.stop, m.startPrefix)
        } else {
            m.length = m.stop - v + 1
            edtGetLength.text = addressText(m.length, m.lengthPrefix)
        }
    }

    /// edtGetStopAdressChange (0x664FD8) – the hint says "Start:" in the original too.
    @objc func edtGetStopAdressChange(_ sender: TObject) {
        let m = expertMem
        guard !m.updating, let v = addressValue(edtGetStopAdress.text, &m.stopPrefix) else { return }
        edtGetStopAdress.hint = addressHint("Start:", v)
        m.stop = v
        if m.start <= v {
            m.length = v - m.start + 1
            m.updating = true
            edtGetLength.text = addressText(m.length, m.lengthPrefix)
            m.updating = false
        }
    }

    /// edtGetLengthChange (0x67A850).
    @objc func edtGetLengthChange(_ sender: TObject) {
        let m = expertMem
        guard !m.updating, let v = addressValue(edtGetLength.text, &m.lengthPrefix) else { return }
        edtGetLength.hint = addressHint("Length:", v)
        m.length = v
        if v > 0 {
            m.stop = m.start + v - 1
            m.updating = true
            edtGetStopAdress.text = addressText(m.stop, m.startPrefix)
            m.updating = false
        }
    }

    /// edtSetStartAddressChange (0x664B40).
    @objc func edtSetStartAddressChange(_ sender: TObject) {
        guard let v = addressValue(edtSetStartAddress.text, &expertMem.setStartPrefix) else { return }
        edtSetStartAddress.hint = addressHint("Start:", v)
    }

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

    /// edtSetMemKeyPress (0x664DC4): hex digits (letters upper case), backspace and return.
    @objc func edtSetMemKeyPress(_ sender: TObject, _ args: TKeyArgs) {
        let c = args.key
        if c == "\u{8}" || c == "\r" { return }
        if c.isASCII && c.isHexDigit { args.key = Character(c.uppercased()); return }
        args.key = "\0"
    }

    /// rgpMemTypeClick (0x6783D0): default ranges of flash / EEPROM.
    @objc func rgpMemTypeClick(_ sender: TObject) {
        let i = rgpMemType.itemIndex
        if i == 0 {
            edtGetStartAddress.text = "0x00"
            edtGetLength.text = "0x2000"
            edtGetStopAdress.text = "0x1FFF"
            edtSetStartAddress.text = "0x00"
            cbxPersistFlashWriteMem.checked = true
        }
        if i == 1 {
            edtGetStartAddress.text = "0x00"
            edtGetLength.text = "0x200"
            edtGetStopAdress.text = "0x1FF"
            edtSetStartAddress.text = "0x00"
            cbxPersistFlashWriteMem.checked = false
        }
    }

    // MARK: - memory access

    /// Master ESC connected (FUN_00663EC8).
    func connectForExpertTool() -> Bool {
        selectESC(masterESC, load: true)
        if !intfConnected && !connectInterface(true) { return false }
        if targetDevice == nil && !connectESC(true) { return false }
        return programmer != nil && targetDevice != nil
    }

    /// FUN_0066F570: flash page size of the target.
    var targetPageSize: Int { max(1, targetDevice?.pageSize ?? (intf.brand == 1 ? 0x200 : 0x40)) }
    /// FUN_0066F4C4: EEPROM size of the target.
    var targetEEpromSize: Int { max(1, targetDevice?.eepromSize ?? 0x200) }
    /// FUN_0066F36C: flash size of the target.
    var targetFlashSize: Int { targetDevice?.flashSize ?? 0x2000 }

    /// FUN_0067953C: reads flash memory of the target.
    func readTargetFlash(_ address: Int, _ count: Int) -> [UInt8]? {
        guard let p = programmer else { return nil }
        Led_Read.isOn = true
        defer { Led_Read.isOn = false }
        return try? p.readFlash(address: address, count: count, progress: nil)
    }

    /// FUN_00679464: reads EEPROM memory (Atmel interfaces only).
    func readTargetEEprom(_ address: Int, _ count: Int) -> [UInt8]? {
        guard intf.brand == 2, let p = programmer else { return nil }
        Led_Read.isOn = true
        defer { Led_Read.isOn = false }
        return try? p.readEEPROM(address: address, count: count)
    }

    /// FUN_0067ACD4: writes flash memory; nil = aborted ("Nothing to write").
    func writeTargetFlash(_ data: [UInt8], _ address: Int) -> Bool? {
        guard !data.isEmpty else {
            MsgDlg.error(NL("Nothing to write (memory size = 0)."))
            return nil
        }
        guard let p = programmer else { return false }
        Screen.busy = true
        Led_Write.isOn = true
        defer { Led_Write.isOn = false; Screen.busy = false }
        let t0 = Date()
        let ok = (try? p.writeFlash(address: address, data: data, progress: nil)) != nil
        TfrmLogForm.addBlue("Time elapsed (s): " + String(format: "%.2f", Date().timeIntervalSince(t0)))
        return ok
    }

    /// FUN_0067A9D0: writes EEPROM memory (Atmel interfaces only); nil = aborted.
    func writeTargetEEprom(_ data: [UInt8], _ address: Int) -> Bool? {
        if data.count > targetEEpromSize {
            MsgDlg.error(DFormat(NL("The size of the EEprom Hex you picked exceeds the available target space\\nAvailable space: %d Bytes.\\nRequired space: %d Bytes."),
                                 [targetEEpromSize, data.count]))
            return nil
        }
        guard !data.isEmpty else {
            MsgDlg.error(NL("Nothing to write (memory size = 0)."))
            return nil
        }
        guard intf.brand == 2, let p = programmer else { return false }
        Screen.busy = true
        Led_Write.isOn = true
        defer { Led_Write.isOn = false; Screen.busy = false }
        let t0 = Date()
        let ok = (try? p.writeEEPROM(address: address, data: data, progress: nil)) != nil
        TfrmLogForm.addBlue("Time elapsed (s): " + String(format: "%.2f", Date().timeIntervalSince(t0)))
        return ok
    }

    /// FUN_006652E4: erases the flash pages first…last (SiLabs interfaces).
    @discardableResult
    func erasePages(_ first: Int, _ last: Int) -> Bool {
        Screen.busy = true
        defer { Screen.busy = false }
        guard let p = programmer, intf.brand == 1 else { return false }
        var ok = true
        for page in (first <= last ? Array(first...last) : Array((last...first).reversed())) {
            if (try? p.erasePage(address: targetPageSize * page)) == nil { ok = false }
        }
        return ok
    }

    /// actReadMemExecute (0x67C028).
    @objc func actReadMemExecute(_ sender: TObject) {
        TfrmLogForm.addNavy2(NL("Expert: read memory"))
        TfrmLogForm.indent(1)
        var data: [UInt8]?
        let m = expertMem
        if connectForExpertTool() {
            data = rgpMemType.itemIndex == 0 ? readTargetFlash(m.start, m.length) : readTargetEEprom(m.start, m.length)
            if data == nil { MsgDlg.error(NL("Read failed!")) }
        }
        TfrmLogForm.indent(-1)
        TfrmLogForm.result(data != nil)
        if let d = data { TfrmMemoView.execute(start: m.start, mem: d) }   // FUN_0067D108
    }

    /// actWriteMemExecute (0x67C18C).
    @objc func actWriteMemExecute(_ sender: TObject) {
        TfrmLogForm.addNavy2(NL("Expert: write memory"))
        TfrmLogForm.indent(1)
        var ok: Bool? = false
        defer {
            TfrmLogForm.indent(-1)
            if let r = ok {
                if r { MsgDlg.show(NL("Memory write operation succeeded."), .mtInformation, [.mbOK]) }
                else { MsgDlg.error(NL("Memory write operation failed.")) }
            }
        }
        guard connectForExpertTool() else { return }
        let memType = rgpMemType.itemIndex
        // hex string → bytes (pairs of hex digits, a single digit gets a leading "0")
        var s = edtSetMem.text.uppercased().trimmingCharacters(in: .whitespaces)
        if s.count == 1 { s = "0" + s }
        let chars = Array(s.unicodeScalars)
        var bytes: [UInt8] = []
        var acc = 0
        var i = 0
        while chars.count >= i + 2 {
            for k in 0..<2 {
                let ch = chars[i + k].value
                switch ch {
                case 0x30...0x39: acc = acc * 16 + Int(ch) - 0x30
                case 0x41...0x46: acc = acc * 16 + Int(ch) - 0x37
                default:
                    MsgDlg.error(NL("Invalid HEX String"))
                    ok = nil   // Abort
                    return
                }
            }
            bytes.append(UInt8(acc & 0xFF))
            i += 2
        }
        guard var addr = addressValue(edtSetStartAddress.text, &expertMem.setStartPrefix) else { ok = nil; return }
        let count = bytes.count
        var data = bytes
        if cbxPersistFlashWriteMem.checked {
            // keep the rest of the touched pages: read them, overlay the bytes, (SiLabs: erase,) write back
            var base = addr, offset = 0
            var read: [UInt8]?
            var good = false
            if memType == 0 {
                let ps = targetPageSize
                let first = (addr / ps) & 0xFF, last = ((count - 1 + addr) / ps) & 0xFF
                base = first * ps
                if intf == .atmISP {
                    offset = addr
                    read = readTargetFlash(0, targetFlashSize)
                } else {
                    offset = addr - base
                    read = readTargetFlash(base, ((last - first + 1) & 0xFF) * ps)
                }
                good = read != nil
                if intf.brand == 1 { good = erasePages(first, last) }
            } else if memType == 1 {
                let es = targetEEpromSize
                let first = (addr / es) & 0xFF, last = ((count - 1 + addr) / es) & 0xFF
                base = first * es
                offset = addr - base
                read = readTargetEEprom(base, ((last - first + 1) & 0xFF) * es)
                good = read != nil
            }
            addr = base
            guard good, var buf = read else { ok = nil; return }   // Abort
            for (k, b) in bytes.enumerated() where offset + k < buf.count { buf[offset + k] = b }
            data = buf
        }
        if memType == 0 {
            // ISP writes the image from address 0 (as in the original, also without "persist")
            ok = writeTargetFlash(data, intf == .atmISP ? 0 : addr)
        } else if memType == 1 {
            ok = writeTargetEEprom(data, addr)
        }
    }

    /// actDeviceErasePageExecute (0x65E434): page of the "write" start address.
    @objc func actDeviceErasePageExecute(_ sender: TObject) {
        guard let a = addressValue(edtSetStartAddress.text, &expertMem.setStartPrefix) else { return }
        let ps = targetPageSize
        let page = (a / ps) & 0xFF
        let start = ps * page
        guard MsgDlg.show(DFormat(NL("Erase Page %d?\\n(Start address: 0x%x)"), [page, start]), .mtConfirmation, [.mbYes, .mbNo]) == mrYes else { return }
        Screen.busy = true
        defer { Screen.busy = false }
        selectESC(masterESC, load: true)
        if connectForExpertTool(), escConnected, let p = programmer, intf.brand == 1 {
            try? p.erasePage(address: start)
        }
    }

    /// actDeviceEraseMultiplePagesExecute (0x65E3D8).
    @objc func actDeviceEraseMultiplePagesExecute(_ sender: TObject) {
        var first = 0, last = 0
        guard connectForExpertTool(), escConnected, TfrmErasePageDlg.execute(&first, &last) else { return }   // FUN_0065ACF0
        erasePages(first, last)
    }

    /// actEraseChipExecute (0x67CB5C).
    @objc func actEraseChipExecute(_ sender: TObject) {
        selectESC(masterESC, load: true)
        guard MsgDlg.show(DFormat(NL("Erase the whole memory of the %s chip?"), [escText]), .mtWarning, [.mbYes, .mbNo]) == mrYes else { return }
        if eraseChip() {
            MsgDlg.show(NL("Chip erased successfully."), .mtInformation, [.mbOK])
        } else {
            MsgDlg.error(NL("Chip erase failed."))
        }
    }

    /// FUN_00665158: erases the whole target memory.
    func eraseChip() -> Bool {
        TfrmLogForm.addNavy2(NL("Erase chip"))
        TfrmLogForm.indent(1)
        var ok = false
        if connectInterface(true) && connectESC(true), let p = programmer {
            Screen.busy = true
            ok = (try? p.eraseChip()) != nil
            Screen.busy = false
        }
        TfrmLogForm.indent(-1)
        TfrmLogForm.result(ok)
        return ok
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

    /// actShowHexFileExecute (0x67C660)
    @objc func actShowHexFileExecute(_ sender: TObject) {
        guard let url = OpenDialog.execute(filter: "Hex file (*.hex;*.eep)|*.hex;*.eep", initialDir: AppFolders.folder(0)) else { return }
        AppFolders.setFolder(0, url.deletingLastPathComponent())
        do {
            let img = try MemoryImage.loadIntelHex(url: url)                         // FUN_005564C4
            TfrmMemoView.execute(start: 0, mem: img.read(0, (img.highestAddress ?? -1) + 1), leftCaption: url.path)
        } catch {
            MsgDlg.error(error.localizedDescription)
        }
    }

    /// actShowBinaryFileExecute (0x660F08)
    @objc func actShowBinaryFileExecute(_ sender: TObject) {
        guard let url = OpenDialog.execute(filter: "Binary file (*.bin or *.*)|*.bin;*.*", initialDir: AppFolders.folder(0)),
              let d = try? Data(contentsOf: url) else { return }                     // FUN_005563E8
        AppFolders.setFolder(0, url.deletingLastPathComponent())
        TfrmMemoView.execute(start: 0, mem: [UInt8](d), leftCaption: url.path)
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
        guard let url = OpenDialog.execute(title: NL("Read default parameters from HEX"), filter: filter, initialDir: AppFolders.hexFolder),
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

/// Fields of the "Expert" page (+0x880 … +0x8B8 of TfrmBLHeliSuiteMain).
final class ExpertMemState {
    var length = 0            // +0x880
    var start = 0             // +0x884
    var stop = 0              // +0x888
    var updating = false      // +0x8A0
    var lengthPrefix = ""     // +0x8A4
    var startPrefix = ""      // +0x8A8
    var stopPrefix = ""       // +0x8AC
    var setStartPrefix = ""   // +0x8B8
}

private var expertMemKey = 0
private var progsWidthKey = 0

extension TfrmBLHeliSuiteMain {
    var expertMem: ExpertMemState {
        if let m = objc_getAssociatedObject(self, &expertMemKey) as? ExpertMemState { return m }
        let m = ExpertMemState()
        objc_setAssociatedObject(self, &expertMemKey, m, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return m
    }
    var avrdudeProgsWidth: Int {
        get { (objc_getAssociatedObject(self, &progsWidthKey) as? Int) ?? 0 }
        set { objc_setAssociatedObject(self, &progsWidthKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}
