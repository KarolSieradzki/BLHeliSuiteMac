import AppKit
import VCL
import BLHeliCore

// MARK: - TfrmMemoView (hex view of memory / files, verify results)

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
    @objc var mniHideFFValues: TMenuItem!

    var mem1: [UInt8] = []      // +0x3C4 ESC / file content
    var mem2: [UInt8] = []      // +0x3C8 original (verify mode)
    var startAddress = 0        // +0x3CC
    var verifyMode = false      // +0x3D0

    /// FUN_0067D108: shows one memory block, or two blocks side by side (differences only, verify mode).
    static func execute(start: Int, mem: [UInt8], leftCaption: String = "", rightHint: String = "",
                        rightCaption: String = "", mem2: [UInt8] = [], leftHint: String = "") {
        let f = TfrmMemoView(resource: "TFRMMEMOVIEW", owner: Application.shared.mainForm)
        f.startAddress = start
        f.mem1 = mem
        f.lblLeftTitle.caption = leftCaption
        f.lblLeftTitle.hint = leftHint
        f.mem2 = mem2
        f.lblRightTitle.caption = rightCaption
        f.lblRightTitle.hint = rightHint
        f.showModal()
        f.release()
    }

    /// FormShow (0x67D998)
    @objc func FormShow(_ sender: TObject) {
        clientWidth = mem2.isEmpty ? 480 : 800
        showMemory()
    }

    /// FUN_0067DD74
    func showMemory() {
        guard !mem1.isEmpty else { return }
        if mem2.isEmpty {
            verifyMode = false
            pnlMemoViewTop.visible = false
            actHideShowFF.visible = true
            fillSingle()
        } else {
            verifyMode = true
            pnlMemoViewTop.visible = true
            actHideShowFF.visible = false
            fillCompare()
        }
    }

    /// LStrFromChar: the byte as ANSI character (control characters show the missing glyph box).
    static func ansiChar(_ b: UInt8) -> String {
        if b < 0x20 || b == 0x7F || [0x81, 0x8D, 0x8F, 0x90, 0x9D].contains(b) { return "\u{25A1}" }
        return String(data: Data([b]), encoding: .windowsCP1252) ?? "\u{25A1}"
    }

    static func hex2(_ v: Int) -> String { String(format: "%02X", v) }

    /// FUN_0067E268: 16 bytes per row, offset column and ASCII column.
    func fillSingle() {
        let g = sgdMemo!
        g.clear()
        guard !mem1.isEmpty else { return }
        g.rowCount = 2
        g.rowCount = mem1.count / 16 + 2
        g[0, 0] = "Offset"
        g.colCount = 0x12
        g.setColWidth(0, 0x2D)
        g.setColWidth(0x11, 0x78)
        for c in 1...16 { g[c, 0] = Self.hex2(c - 1) }
        g[0x11, 0] = "ASCII"
        for r in 1..<g.rowCount { g[0, r] = "0x" + String(format: "%04X", (r - 1) * 16 + startAddress) }
        let hide = actHideShowFF.checked
        var i = 0
        for r in 1..<g.rowCount {
            var ascii = ""
            for c in 1...16 {
                if i < mem1.count {
                    let b = mem1[i]
                    i += 1
                    if !hide {
                        g[c, r] = Self.hex2(Int(b))
                        ascii += Self.ansiChar(b)
                    } else {
                        g[c, r] = b == 0xFF ? "" : Self.hex2(Int(b))
                        if b != 0xFF { ascii += Self.ansiChar(b) }
                    }
                } else {
                    g[c, r] = ""
                }
            }
            g[0x11, r] = ascii
        }
    }

    /// FUN_0067DDE8: rows with differences only; left ESC, right original; caption tells the result.
    func fillCompare() {
        mniHideFFValues?.visible = false
        let g = sgdMemo!
        g.clear()
        guard !mem1.isEmpty || !mem2.isEmpty else { return }
        g.rowCount = 2
        g.fixedRows = 1
        g.colCount = 0x22
        g[0, 0] = "Offset"
        g.setColWidth(0, 0x37)
        g.setColWidth(0x11, 0x78)
        for c in 1...16 {
            g[c, 0] = Self.hex2(c - 1)
            g[c + 0x11, 0] = Self.hex2(c - 1)
        }
        g[0x11, 0] = "            ASCII"
        while mem1.count < mem2.count { mem1.append(0xFF) }
        while mem2.count < mem1.count { mem2.append(0xFF) }
        var i = 0, offset = 0, rows = 0
        while i < mem1.count {
            var l1: [UInt8] = [], l2: [UInt8] = []
            var differ = false
            for _ in 0..<16 where i < mem1.count {
                if mem2[i] != mem1[i] { differ = true }
                l1.append(mem1[i])
                l2.append(mem2[i])
                i += 1
            }
            if differ {
                rows += 1
                if rows > 1 { g.rowCount += 1 }
                let r = g.rowCount - 1
                g[0, r] = "0x" + String(format: "%04X", startAddress + offset)
                for (k, b) in l1.enumerated() {
                    g[k + 1, r] = Self.hex2(Int(b))
                    g[k + 1 + 0x11, r] = Self.hex2(Int(l2[k]))
                }
                g[0x11, r] = l1.map { Self.ansiChar($0) }.joined()
            }
            offset += 16
        }
        caption = rows == 0 ? "No differences found" : "Differences as shown in red..."
    }

    /// actHideShowFFExecute (0x67D248)
    @objc func actHideShowFFExecute(_ sender: TObject) {
        actHideShowFF.checked.toggle()
        showMemory()
    }

    /// actTakeScreenshotExecute (0x67D268)
    @objc func actTakeScreenshotExecute(_ sender: TObject) { saveScreenshot(of: self, name: verifyMode ? "VerifyResult" : "MemoryView") }

    /// "l_" / "r_" + file name in verify mode.
    func sideName(_ url: URL, _ p: String) -> URL { url.deletingLastPathComponent().appendingPathComponent(p + url.lastPathComponent) }

    /// actSaveToBinFileExecute (0x67D310)
    @objc func actSaveToBinFileExecute(_ sender: TObject) {
        guard let url = SaveDialog.execute(filter: "Binary file (*.bin)|*.bin", initialDir: AppFolders.folder(1)) else { return }
        AppFolders.setFolder(1, url.deletingLastPathComponent())
        var f = url.deletingPathExtension().appendingPathExtension("bin")
        if verifyMode { f = sideName(f, "l_") }
        try? Data(mem1).write(to: f)
    }

    /// actSaveToHexFileExecute (0x67D62C)
    @objc func actSaveToHexFileExecute(_ sender: TObject) {
        guard let url = SaveDialog.execute(filter: "Hex file (*.hex)|*.hex", initialDir: AppFolders.folder(1)) else { return }
        AppFolders.setFolder(1, url.deletingLastPathComponent())
        var f = url
        let ext = url.pathExtension.lowercased()
        if ext != "eep" && ext != "hex" { f = url.deletingPathExtension().appendingPathExtension("hex") }
        var skip = MsgDlg.show(NL("Skip 0xFF bytes?"), .mtConfirmation, [.mbYes, .mbNo]) == mrYes
        HexFile.write(mem1, start: startAddress, to: verifyMode ? sideName(f, "l_") : f, skipFF: skip)
        if verifyMode {
            skip = MsgDlg.show(NL("Skip 0xFF bytes?"), .mtConfirmation, [.mbYes, .mbNo]) == mrYes
            HexFile.write(mem2, start: startAddress, to: sideName(f, "r_"), skipFF: skip)
        }
    }

    /// sgdMemoDrawCell (0x67DA18): ESC bytes green, original bytes blue, differences red.
    @objc func sgdMemoDrawCell(_ sender: TObject, _ a: TDrawCellArgs) {
        let g = sgdMemo!
        var color: TColor?
        if a.col >= 1 && a.col <= 0x10 && a.row >= 1 {
            color = clGreen
            if !mem2.isEmpty && g[a.col, a.row] != g[a.col + 0x11, a.row] { color = clRed }
        } else if a.col > 0x11 && a.col < 0x22 && a.row >= 1 {
            color = clBlue
            if !mem2.isEmpty && g[a.col, a.row] != g[a.col - 0x11, a.row] { color = clRed }
        }
        guard let c = color else { return }
        g.canvas.font.color = c
        g.canvas.textRect(a.rect, a.rect.minX + 2, a.rect.minY + 2, g[a.col, a.row])
    }

    /// sgdMemoMouseMove (0x67DBA8): value of the byte under the mouse as hint.
    @objc func sgdMemoMouseMove(_ sender: TObject, _ a: TMouseArgs) {
        let (c, r) = sgdMemo.mouseToCell(a.x, a.y)
        if c < 1 || r < 1 || sgdMemo.colCount <= c {
            if verifyMode { hint = NL("Left = ESC (green) - Right = Original (blue)") }
            return
        }
        let s = sgdMemo[c, r]
        guard !s.isEmpty, let v = Int(s, radix: 16), v >= 0 else { return }   // FUN_00555224
        hint = "$" + s + " = #" + String(v) + " = \"" + Self.ansiChar(UInt8(v & 0xFF)) + "\""
    }
}

/// Intel hex files as written by BLHeliSuite (FUN_00556330 → FUN_005558CC, FUN_0055618C).
enum HexFile {
    /// FUN_005558CC: 16 byte data records, an extended segment address record (type 02) per 64 KiB block;
    /// with skipFF runs of $FF bytes are left out.
    static func records(_ mem: [UInt8], start: Int, skipFF: Bool) -> [[UInt8]] {
        var recs: [[UInt8]] = []
        func add(_ len: Int, _ addr: Int, _ type: UInt8, _ data: [UInt8]) {
            var r: [UInt8] = [UInt8(len & 0xFF), UInt8((addr >> 8) & 0xFF), UInt8(addr & 0xFF), type] + data
            r.append(0 &- r.reduce(0, { $0 &+ $1 }))
            recs.append(r)
        }
        let blocks = (mem.count + 0xFFFF) / 0x10000
        for b in 0..<blocks {
            let base = b * 0x10000
            let chunk = Array(mem[base..<min(mem.count, base + 0x10000)])
            if b > 0 { add(2, 0, 2, [UInt8(((base >> 4) >> 8) & 0xFF), UInt8((base >> 4) & 0xFF)]) }
            var i = 0          // index of the next byte
            var done = false
            while !done {
                if skipFF { while i < chunk.count && chunk[i] == 0xFF { i += 1 } }
                if i >= chunk.count { break }
                var line: [UInt8] = [chunk[i]]
                let addr = (i + start - base) & 0xFFFF
                i += 1
                var run = 0
                var cut = false
                while line.count != 16 && !cut {
                    if i >= chunk.count { done = true; break }
                    let v = chunk[i]
                    i += 1
                    line.append(v)
                    if skipFF {
                        if v == 0xFF {
                            run += 1
                            if 16 - line.count < run { cut = true; line.removeLast(run) }
                        } else {
                            run = 0
                        }
                    }
                }
                if !line.isEmpty { add(line.count, addr, 0, line) }
            }
        }
        add(0, 0, 1, [])
        return recs
    }

    /// FUN_00556330 / FUN_0055618C: ":LLAAAATT…CC" lines; nothing is written without data records.
    @discardableResult
    static func write(_ mem: [UInt8], start: Int, to url: URL, skipFF: Bool) -> Bool {
        let recs = records(mem, start: start, skipFF: skipFF)
        guard recs.count > 1 else { return false }
        let text = recs.map { ":" + $0.map { String(format: "%02X", $0) }.joined() + "\r\n" }.joined()
        return (try? text.write(to: url, atomically: true, encoding: .ascii)) != nil
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

    /// FormCreate (0x65ADC4).
    @objc func FormCreate(_ sender: TObject) {
        btnOK.caption = NL("OK")
        btnAbort.caption = NL("Abort")
        lblFirstPage.caption = NL("First Page")
        lblLastPage.caption = NL("Last Page")
        caption = NL("Erase flash pages")
    }

    /// FUN_0065ACF0: dialog with the first and last page; false = aborted.
    static func execute(_ first: inout Int, _ last: inout Int) -> Bool {
        let f = TfrmErasePageDlg(resource: "TFRMERASEPAGEDLG", owner: nil)
        defer { f.release() }
        f.speFirstPage.value = Double(first)
        f.speLastPage.value = Double(last)
        f.speFirstPageChange(f)
        f.speLastPageChange(f)
        guard f.showModal() == mrOk else { return false }
        first = f.speFirstPage.intValue
        last = f.speLastPage.intValue
        return true
    }

    /// speFirstPageChange (0x65AEEC): start address of the page (page size 0x200).
    @objc func speFirstPageChange(_ sender: TObject) {
        lblFirstAddress.caption = DFormat("0x%0.4x", [speFirstPage.intValue << 9])
    }

    /// speLastPageChange (0x65AF70)
    @objc func speLastPageChange(_ sender: TObject) {
        lblLastAddress.caption = DFormat("0x%0.4x", [speLastPage.intValue << 9])
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

    @objc func Button1Click(_ sender: TObject) { saveScreenshot(of: self, name: "CompareResults") }

    /// btnOKClick (0x658E30): Close.
    @objc func btnOKClick(_ sender: TObject) { close() }
}
