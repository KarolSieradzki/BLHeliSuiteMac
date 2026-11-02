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

    @objc func actTakeScreenshotExecute(_ sender: TObject) { saveScreenshot(of: self, name: "MemoryView") }

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

    @objc func Button1Click(_ sender: TObject) { saveScreenshot(of: self, name: "CompareResults") }
}
