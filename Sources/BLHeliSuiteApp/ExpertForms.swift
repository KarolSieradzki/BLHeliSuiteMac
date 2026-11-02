import AppKit
import VCL
import BLHeliCore

// MARK: - TfrmMemoView (hex view of memory / files)

@objc(TfrmMemoView) final class TfrmMemoView: TForm {
    @objc var pnlBottom: TPanel!
    @objc var StatusBar1: TStatusBar!
    @objc var aclMain: TActionList!
    @objc var actHideShowFF: TAction!
    @objc var actSaveToBinFile: TAction!
    @objc var actSaveToHexFile: TAction!
    @objc var btnOK: TButton!
    @objc var btnSaveToBinaryFile: TButton!
    @objc var btnSaveToHexFile: TButton!
    @objc var actTakeScreenshot: TAction!
    @objc var pnlMemoViewMain: TPanel!
    @objc var pnlMemoViewTop: TPanel!
    @objc var sgdMemo: TDrawGrid!
    @objc var lblRightTitle: TLabel!
    @objc var lblLeftTitle: TLabel!

    var image = MemoryImage()
    var base = 0
    var hideFF = false
    var fileName: URL?

    /// FUN_0067D108: shows memory content in a 16 bytes per row grid.
    static func show(_ img: MemoryImage, title: String, fileName: URL?) {
        let f = TfrmMemoView(resource: "TFRMMEMOVIEW", owner: Application.shared.mainForm)
        f.image = img
        f.fileName = fileName
        f.caption = title
        f.lblLeftTitle.caption = title
        f.lblRightTitle.caption = String(format: "%d bytes", img.bytes.count)
        f.fill()
        f.showModal()
        f.release()
    }

    func fill() {
        let lo = (image.bytes.keys.min() ?? 0) & ~0xF
        let hi = image.highestAddress ?? lo
        base = lo
        let rows = (hi - lo) / 16 + 1
        let g = sgdMemo!
        g.colCount = 18
        g.rowCount = rows + 1
        g.fixedCols = 1
        g.fixedRows = 1
        g.setColWidth(0, 70)
        for c in 1...16 { g.setColWidth(c, 24) }
        g.setColWidth(17, 140)
        g[0, 0] = "Address"
        for c in 0..<16 { g[c + 1, 0] = String(format: "%X", c) }
        g[17, 0] = "ASCII"
        for r in 0..<rows {
            let a = lo + r * 16
            g[0, r + 1] = String(format: "0x%04X", a)
            var ascii = ""
            for c in 0..<16 {
                if let b = image.bytes[a + c] {
                    g[c + 1, r + 1] = hideFF && b == 0xFF ? "" : String(format: "%02X", b)
                    ascii += (0x20..<0x7F).contains(b) ? String(UnicodeScalar(b)) : "."
                } else {
                    g[c + 1, r + 1] = ""
                    ascii += " "
                }
            }
            g[17, r + 1] = ascii
        }
        StatusBar1?.setPanelText(0, String(format: "0x%04X – 0x%04X", lo, hi))
        g.needsDisplay = true
    }

    @objc func FormShow(_ sender: TObject) { fill() }
    @objc func actHideShowFFExecute(_ sender: TObject) { hideFF.toggle(); actHideShowFF.checked = hideFF; fill() }

    @objc func actSaveToBinFileExecute(_ sender: TObject) {
        guard let url = SaveDialog.execute(fileName: (fileName?.deletingPathExtension().lastPathComponent ?? "memory") + ".bin",
                                           filter: "Binary file (*.bin)|*.bin", initialDir: AppFolders.hexFolder) else { return }
        let n = (image.highestAddress ?? -1) + 1
        try? Data(image.read(0, n)).write(to: url)
    }

    @objc func actSaveToHexFileExecute(_ sender: TObject) {
        guard let url = SaveDialog.execute(fileName: (fileName?.deletingPathExtension().lastPathComponent ?? "memory") + ".hex",
                                           filter: "Hex file (*.hex)|*.hex", initialDir: AppFolders.hexFolder) else { return }
        try? image.intelHex().write(to: url, atomically: true, encoding: .ascii)
    }

    @objc func actTakeScreenshotExecute(_ sender: TObject) { saveScreenshot(of: self, prefix: "BLHeliSuiteMemoView") }

    /// sgdMemoDrawCell: erased bytes (FF) in grey.
    @objc func sgdMemoDrawCell(_ sender: TObject, _ a: TDrawCellArgs) {
        guard a.col >= 1, a.col <= 16, a.row >= 1, sgdMemo[a.col, a.row] == "FF" else { return }
        sgdMemo.canvas.font.color = clGray
        sgdMemo.canvas.brushColor = clWindow
        sgdMemo.canvas.textRect(a.rect, a.rect.minX + 2, a.rect.minY + 2, "FF")
    }
    @objc func sgdMemoMouseMove(_ sender: TObject, _ a: TMouseArgs) {
        let (c, r) = sgdMemo.mouseToCell(a.x, a.y)
        guard c >= 1, c <= 16, r >= 1 else { return }
        let addr: Int = base + (r - 1) * 16 + c - 1
        StatusBar1?.setPanelText(0, String(format: "Address 0x%04X", addr))
    }
}

// MARK: - TfrmErasePageDlg

@objc(TfrmErasePageDlg) final class TfrmErasePageDlg: TForm {
    @objc var Bevel1: TBevel!
    @objc var speFirstPage: TSpinEdit!
    @objc var btnOK: TButton!
    @objc var btnAbort: TButton!
    @objc var speLastPage: TSpinEdit!
    @objc var lblFirstPage: TLabel!
    @objc var lblLastPage: TLabel!
    @objc var lblFirstAddress: TLabel!
    @objc var lblLastAddress: TLabel!
    var pageSize = 0x200

    func prepare(pageSize ps: Int, pages: Int) {
        pageSize = ps
        speFirstPage.minValue = 0
        speFirstPage.maxValue = Double(max(0, pages - 1))
        speLastPage.minValue = 0
        speLastPage.maxValue = Double(max(0, pages - 1))
        speFirstPage.value = 0
        speLastPage.value = 0
        speFirstPageChange(self)
        speLastPageChange(self)
    }

    @objc func speFirstPageChange(_ sender: TObject) {
        if speLastPage.intValue < speFirstPage.intValue { speLastPage.value = speFirstPage.value }
        lblFirstAddress.caption = String(format: "0x%04X", speFirstPage.intValue * pageSize)
    }

    @objc func speLastPageChange(_ sender: TObject) {
        if speLastPage.intValue < speFirstPage.intValue { speFirstPage.value = speLastPage.value }
        lblLastAddress.caption = String(format: "0x%04X", (speLastPage.intValue + 1) * pageSize - 1)
    }
}

// MARK: - TfrmCompareResults (verify flash)

@objc(TfrmCompareResults) final class TfrmCompareResults: TForm {
    @objc var pnlBottom: TPanel!
    @objc var btnOK: TButton!
    @objc var grid: TDrawGrid!
    @objc var Button1: TButton!

    static func show(_ diffs: [(Int, UInt8, UInt8)], title: String) {
        let f = TfrmCompareResults(resource: "TFRMCOMPARERESULTS", owner: Application.shared.mainForm)
        f.caption = title + (diffs.isEmpty ? " – identical" : " – \(diffs.count) differences")
        let g = f.grid!
        g.colCount = 3
        g.rowCount = max(2, diffs.count + 1)
        g[0, 0] = "Address"; g[1, 0] = "File"; g[2, 0] = "ESC"
        for (i, d) in diffs.enumerated() {
            g[0, i + 1] = String(format: "0x%04X", d.0)
            g[1, i + 1] = String(format: "%02X", d.1)
            g[2, i + 1] = String(format: "%02X", d.2)
        }
        if diffs.isEmpty { g[0, 1] = "identical" }
        f.showModal()
        f.release()
    }

    @objc func Button1Click(_ sender: TObject) { saveScreenshot(of: self, prefix: "BLHeliSuiteCompareResults") }
}

// MARK: - TfrmFuseEditor / TfraAVRFuses

/// Fuse bit names per device (datasheets of the ATmegas used in ESCs).
struct FuseLayout {
    let low: [String]   // bit 7 … 0
    let high: [String]
    let ext: [String]?

    static func forSignature(_ s: UInt32) -> FuseLayout {
        switch s {
        case 0x1E9307:  // ATmega8
            return FuseLayout(low: ["BODLEVEL", "BODEN", "SUT1", "SUT0", "CKSEL3", "CKSEL2", "CKSEL1", "CKSEL0"],
                              high: ["RSTDISBL", "WDTON", "SPIEN", "CKOPT", "EESAVE", "BOOTSZ1", "BOOTSZ0", "BOOTRST"], ext: nil)
        case 0x1E950F, 0x1E9514:  // ATmega328(P)
            return FuseLayout(low: ["CKDIV8", "CKOUT", "SUT1", "SUT0", "CKSEL3", "CKSEL2", "CKSEL1", "CKSEL0"],
                              high: ["RSTDISBL", "DWEN", "SPIEN", "WDTON", "EESAVE", "BOOTSZ1", "BOOTSZ0", "BOOTRST"],
                              ext: ["-", "-", "-", "-", "-", "BODLEVEL2", "BODLEVEL1", "BODLEVEL0"])
        default:  // ATmega48/88/168
            return FuseLayout(low: ["CKDIV8", "CKOUT", "SUT1", "SUT0", "CKSEL3", "CKSEL2", "CKSEL1", "CKSEL0"],
                              high: ["RSTDISBL", "DWEN", "SPIEN", "WDTON", "EESAVE", "BODLEVEL2", "BODLEVEL1", "BODLEVEL0"],
                              ext: ["-", "-", "-", "-", "-", "BOOTSZ1", "BOOTSZ0", "BOOTRST"])
        }
    }
}

@objc(TfraAVRFuses) final class TfraAVRFuses: TFrame {
    @objc var cbxAVRDevice: TComboBox!
    @objc var lblDeviceSign: TLabel!
    @objc var edtLowFuse: TEdit!
    @objc var edtHighFuse: TEdit!
    @objc var edtExtFuse: TEdit!
    @objc var edtLockbyte: TEdit!
    @objc var btnOK: TButton!
    @objc var btnCancel: TButton!
    @objc var btnRead: TButton!
    @objc var btnWrite: TButton!
    @objc var btnLoadFusesDefault: TButton!
    @objc var btnUndoFusesChanges: TButton!
    @objc var btnLoadFusesCurrent: TButton!
    @objc var actCriticalFeaturesEnabled: TAction!
    @objc var ccbBodlevel: TComboBox!
    @objc var ccbBOOTSZ: TComboBox!
    @objc var ccbCKSEL_SUT: TComboBox!
    @objc var ccbLB: TComboBox!
    @objc var ccbBLB0: TComboBox!
    @objc var ccbBLB1: TComboBox!

    var isp: ISPProgrammer?
    var signature: UInt32 = 0
    var fuses = AVRFuses(low: 0xFF, high: 0xFF, ext: nil)
    var original = AVRFuses(low: 0xFF, high: 0xFF, ext: nil)
    var updating = false

    func bitBoxes(_ prefix: String) -> [TCheckBox] {
        (0...7).compactMap { component("cbx\(prefix)\($0)") as TCheckBox? }
    }

    func setup(isp: ISPProgrammer?, signature sig: UInt32, fuses f: AVRFuses) {
        btnRead?.enabled = isp != nil
        btnWrite?.enabled = isp != nil
        self.isp = isp
        signature = sig
        fuses = f
        original = f
        let layout = FuseLayout.forSignature(sig)
        cbxAVRDevice.items = [MCUTable.byAVRSignature(sig)?.name ?? String(format: "0x%06X", sig)]
        cbxAVRDevice.itemIndex = 0
        lblDeviceSign.caption = String(format: "0x%06X", sig)
        for (prefix, names) in [("LF", layout.low), ("HF", layout.high), ("EF", layout.ext ?? [])] {
            for b in bitBoxes(prefix) {
                let bit = Int(b.name.suffix(1)) ?? 0
                if names.count == 8 { b.caption = names[7 - bit]; b.enabled = names[7 - bit] != "-" } else { b.enabled = false }
                b.onClick = { [weak self] _ in self?.bitsChanged() }
            }
        }
        edtExtFuse.enabled = layout.ext != nil
        show()
    }

    func show() {
        updating = true
        edtLowFuse.text = String(format: "%02X", fuses.low)
        edtHighFuse.text = String(format: "%02X", fuses.high)
        edtExtFuse.text = fuses.ext.map { String(format: "%02X", $0) } ?? ""
        for (prefix, v) in [("LF", fuses.low), ("HF", fuses.high), ("EF", fuses.ext ?? 0xFF)] {
            for b in bitBoxes(prefix) {
                let bit = Int(b.name.suffix(1)) ?? 0
                b.checked = (v >> bit) & 1 == 0   // checked = programmed
            }
        }
        updating = false
    }

    func bitsChanged() {
        guard !updating else { return }
        func value(_ prefix: String) -> UInt8 {
            var v: UInt8 = 0xFF
            for b in bitBoxes(prefix) where b.checked { v &= ~(1 << UInt8(Int(b.name.suffix(1)) ?? 0)) }
            return v
        }
        fuses.low = value("LF")
        fuses.high = value("HF")
        if fuses.ext != nil { fuses.ext = value("EF") }
        show()
    }

    @objc func edtFuseKeyPress(_ sender: TObject, _ args: TKeyArgs) {
        if !(args.key.isHexDigit || args.key == "\u{8}" || args.key == "\r") { args.key = "\0" }
    }

    @objc func cbxFuseBitsKeyUp(_ sender: TObject, _ args: TKeyArgs) {
        guard !updating else { return }
        if let v = UInt8(edtLowFuse.text, radix: 16) { fuses.low = v }
        if let v = UInt8(edtHighFuse.text, radix: 16) { fuses.high = v }
        if fuses.ext != nil, let v = UInt8(edtExtFuse.text, radix: 16) { fuses.ext = v }
        show()
    }

    @objc func btnReadClick(_ sender: TObject) {
        guard let isp else { return }
        Screen.busy = true
        defer { Screen.busy = false }
        do {
            fuses = try isp.readFuses()
            original = fuses
            show()
        } catch {
            MsgDlg.error(error.localizedDescription)
        }
    }

    @objc func btnWriteClick(_ sender: TObject) {
        guard let isp else { return }
        if (fuses.high >> 5) & 1 == 1 && signature != 0 {
            MsgDlg.error(NL("SPIEN must stay programmed – the device could no longer be programmed over ISP."))
            return
        }
        guard MsgDlg.show(String(format: NL("Write fuses L:0x%02X H:0x%02X%@?"), fuses.low, fuses.high,
                                 fuses.ext.map { String(format: " E:0x%02X", $0) } ?? ""), .mtWarning, [.mbYes, .mbNo]) == mrYes else { return }
        Screen.busy = true
        defer { Screen.busy = false }
        do {
            try isp.writeFuses(fuses)
            original = fuses
            MsgDlg.show(NL("Avrdude successfully."), .mtInformation, [.mbOK])
        } catch {
            MsgDlg.error(DFormat(NL("Avrdude FAILED!\\n\\n\"%s\""), [error.localizedDescription]))
        }
    }

    // MARK: named bits and fields

    var layout: FuseLayout { FuseLayout.forSignature(signature) }

    /// (fuse byte 0 low / 1 high / 2 ext, bit) of a fuse bit name.
    func location(_ name: String) -> (Int, Int)? {
        for (i, names) in [layout.low, layout.high, layout.ext ?? []].enumerated() {
            if let j = names.firstIndex(of: name) { return (i, 7 - j) }
        }
        return nil
    }

    func get(_ byte: Int) -> UInt8 { byte == 0 ? fuses.low : byte == 1 ? fuses.high : (fuses.ext ?? 0xFF) }
    func set(_ byte: Int, _ v: UInt8) {
        if byte == 0 { fuses.low = v } else if byte == 1 { fuses.high = v } else if fuses.ext != nil { fuses.ext = v }
    }

    /// Toggles a fuse bit by name (programmed = 0).
    func toggle(_ name: String) {
        guard let (b, bit) = location(name) else { return }
        set(b, get(b) ^ (1 << UInt8(bit)))
        show()
        updateFields()
    }

    /// Bits of a multi bit field ("BODLEVEL" → BODLEVEL2…0), highest first.
    func fieldBits(_ prefix: String) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        for (i, names) in [layout.low, layout.high, layout.ext ?? []].enumerated() {
            for (j, n) in names.enumerated() where n.hasPrefix(prefix) && n != prefix + "_" { out.append((i, 7 - j)) }
        }
        return out
    }

    func fieldValue(_ bits: [(Int, Int)]) -> Int { bits.reduce(0) { ($0 << 1) | Int((get($1.0) >> UInt8($1.1)) & 1) } }

    func setField(_ bits: [(Int, Int)], _ v: Int) {
        for (k, (b, bit)) in bits.enumerated() {
            let one = (v >> (bits.count - 1 - k)) & 1 == 1
            let cur = get(b)
            set(b, one ? cur | (1 << UInt8(bit)) : cur & ~(1 << UInt8(bit)))
        }
    }

    var fieldCombos: [(TComboBox?, [String])] {
        [(ccbBodlevel, ["BODLEVEL"]), (ccbBOOTSZ, ["BOOTSZ"]), (ccbCKSEL_SUT, ["SUT", "CKSEL"])]
    }

    func comboBits(_ prefixes: [String]) -> [(Int, Int)] { prefixes.flatMap { fieldBits($0) } }

    /// Combo boxes of the multi bit fields: "1111" patterns.
    func updateFields() {
        updating = true
        for (c, prefixes) in fieldCombos {
            guard let c else { continue }
            let bits = comboBits(prefixes)
            c.enabled = !bits.isEmpty
            guard !bits.isEmpty else { c.items = []; continue }
            c.items = (0..<(1 << bits.count)).map { v in
                prefixes.joined(separator: "_") + " = " + String(String(v, radix: 2).reversed()).padding(toLength: bits.count, withPad: "0", startingAt: 0).reversed()
            }
            c.itemIndex = fieldValue(bits)
        }
        updating = false
    }

    func fieldChanged(_ c: TComboBox?, _ prefixes: [String]) {
        guard !updating, let c, c.itemIndex >= 0 else { return }
        setField(comboBits(prefixes), c.itemIndex)
        show()
    }

    @objc func ccbBodlevelChange(_ sender: TObject) { fieldChanged(ccbBodlevel, ["BODLEVEL"]) }
    @objc func ccbBOOTSZChange(_ sender: TObject) { fieldChanged(ccbBOOTSZ, ["BOOTSZ"]) }
    @objc func ccbCKSEL_SUTChange(_ sender: TObject) { fieldChanged(ccbCKSEL_SUT, ["SUT", "CKSEL"]) }
    @objc func ccbBodlevelCloseUp(_ sender: TObject) { ccbBodlevelChange(sender) }
    @objc func ccbCKSEL_SUTCloseUp(_ sender: TObject) { ccbCKSEL_SUTChange(sender) }
    @objc func ccbBodlevelDropDown(_ sender: TObject) { updateFields() }
    @objc func ccbCKSEL_SUTDropDown(_ sender: TObject) { updateFields() }

    /// Lock bits are not changed by BLHeliSuite (no lock byte write) – the lists only show the meaning.
    @objc func ccbLBChange(_ sender: TObject) {}
    @objc func ccbLBCloseUp(_ sender: TObject) {}
    @objc func ccbLBDropDown(_ sender: TObject) {}
    @objc func ccbBLB0Change(_ sender: TObject) {}
    @objc func ccbBLB1Change(_ sender: TObject) {}

    @objc func actBODENExecute(_ sender: TObject) { toggle("BODEN") }
    @objc func actBOOTRSTExecute(_ sender: TObject) { toggle("BOOTRST") }
    @objc func actCKDIV8Execute(_ sender: TObject) { toggle("CKDIV8") }
    @objc func actCKOPTExecute(_ sender: TObject) { toggle("CKOPT") }
    @objc func actCKOUTExecute(_ sender: TObject) { toggle("CKOUT") }
    @objc func actDWENExecute(_ sender: TObject) { toggle("DWEN") }
    @objc func actEESAVEExecute(_ sender: TObject) { toggle("EESAVE") }
    @objc func actRSTDISBLExecute(_ sender: TObject) { toggle("RSTDISBL") }
    @objc func actSELFPRGENExecute(_ sender: TObject) { toggle("SELFPRGEN") }
    @objc func actSPIENExecute(_ sender: TObject) { toggle("SPIEN") }
    @objc func actWDTONExecute(_ sender: TObject) { toggle("WDTON") }

    /// actCriticalFeaturesEnabledExecute: RSTDISBL / SPIEN / DWEN / WDTON can only be changed after unlocking.
    @objc func actCriticalFeaturesEnabledExecute(_ sender: TObject) {
        actCriticalFeaturesEnabled.checked.toggle()
        for n in ["cbxRSTDISBL", "cbxSPIEN", "cbxDWEN", "cbxWDTON"] {
            (component(n) as TCheckBox?)?.enabled = actCriticalFeaturesEnabled.checked
        }
    }

    @objc func cbxAVRDeviceChange(_ sender: TObject) { show(); updateFields() }
    @objc func cbxFuseBitsKeyDown(_ sender: TObject, _ a: TKeyArgs) {}
    @objc func cbxFuseBitsKeyPress(_ sender: TObject, _ a: TKeyArgs) { /* empty in BLHeliSuite (0x629BCC) */ }
    @objc func cbxFuseBitsMouseUp(_ sender: TObject, _ a: TMouseArgs) { bitsChanged(); updateFields() }
    @objc func edtFuseContextPopup(_ sender: TObject) {}
    @objc func FrameResize(_ sender: TObject) { needsDisplay = true }
    @objc func aclMainUpdate(_ sender: TObject) {
        btnUndoFusesChanges?.enabled = fuses != original
    }

    @objc func actUndoFusesChangesExecute(_ sender: TObject) { fuses = original; show() }
    @objc func actLoadFusesCurrentExecute(_ sender: TObject) { btnReadClick(sender) }
    @objc func actLoadFusesDefaultExecute(_ sender: TObject) {
        switch signature {
        case 0x1E9307: fuses = AVRFuses(low: 0x3F, high: 0xCA, ext: nil)          // BLHeli ATmega8 ESC defaults
        case 0x1E950F, 0x1E9514: fuses = AVRFuses(low: 0xFF, high: 0xDA, ext: 0xFD)
        default: fuses = AVRFuses(low: 0xFF, high: 0xDD, ext: 0xFA)
        }
        show()
    }
    @objc func bntSaveScreenshotClick(_ sender: TObject) {
        if let f = window?.delegate as? TForm { saveScreenshot(of: f, prefix: "BLHeliSuiteFuses") }
    }
}

@objc(TfrmFuseEditor) final class TfrmFuseEditor: TForm {
    @objc var fraAVRFuses1: TfraAVRFuses!

    /// Editing only (Confirm Flash dialog): the changed fuses or nil.
    static func edit(signature: UInt32, fuses: AVRFuses) -> AVRFuses? {
        let f = TfrmFuseEditor(resource: "TFRMFUSEEDITOR", owner: Application.shared.mainForm)
        defer { f.release() }
        f.fraAVRFuses1.setup(isp: nil, signature: signature, fuses: fuses)
        return f.showModal() == mrOk ? f.fraAVRFuses1.fuses : nil
    }

    static func execute(isp: ISPProgrammer, signature: UInt32, fuses: AVRFuses) {
        let f = TfrmFuseEditor(resource: "TFRMFUSEEDITOR", owner: Application.shared.mainForm)
        f.fraAVRFuses1.setup(isp: isp, signature: signature, fuses: fuses)
        f.showModal()
        f.release()
    }

    @objc func FormShow(_ sender: TObject) { fraAVRFuses1.show() }
}
