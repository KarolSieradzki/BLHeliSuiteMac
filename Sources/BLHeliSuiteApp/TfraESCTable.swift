import AppKit
import VCL
import BLHeliCore

/// Frame TfraESCTable (DFM resource TFRAESCTABLE, unit at 0x64C768) – the "ESC overview" page:
/// one column per ESC, one row per parameter.
@objc(TfraESCTable) final class TfraESCTable: TFrame {
    @objc var grdMain: TDrawGrid!
    @objc var ccbEdit: TComboBox!
    final class WeakRef { weak var obj: AnyObject? }
    let mainRef = WeakRef()
    /// Self+0x278: cell editing. Nothing in BLHeliSuite 16.7.14.9.0.2 sets this flag, so the table is read only
    /// (grdMainSelectCell refuses every cell and the edit combo box is never shown).
    var editable = false
    /// Self+0x279 / +0x27A / +0x27B: arguments of the last update.
    var syncDir = false
    var syncThrottle = false
    var escCount = 0
    /// Items.Objects of ccbEdit (the parameter values of the listed texts).
    var editValues: [Int] = []
}

extension TfraESCTable {
    var main: TfrmBLHeliSuiteMain? {
        get { mainRef.obj as? TfrmBLHeliSuiteMain }
        set { mainRef.obj = newValue }
    }

    /// port_attach (FUN_0064D3DC): links the ESC setups (Self+0x270) and ESC buttons (Self+0x274) of the main form.
    func attach(_ m: TfrmBLHeliSuiteMain) {
        ccbEdit.visible = false
        main = m
    }

    func blheli(_ i: Int) -> TBLHeli? {
        guard let m = main, i >= 1, i < m.blheli.count else { return nil }
        return m.blheli[i]
    }

    /// FUN_0064CCFC: master ESC.
    var master: Int { main?.masterESC ?? 1 }

    // MARK: - port_update (FUN_0064D884)

    func update(_ m: TfrmBLHeliSuiteMain, syncDir: Bool, syncThrottle: Bool, count: Int) {
        main = m
        self.syncDir = syncDir
        self.syncThrottle = syncThrottle
        escCount = count
        let g = grdMain!
        let db = m.db
        g.clear()                                           // FUN_00560F90
        g.colCount = count + 1
        g.rowCount = 1
        g.defaultRowHeight = ccbEdit.height
        g.defaultColWidth = 0x50
        g.colWidths = [:]
        g.rowHeights = [:]
        var col = 0
        if g.colCount > 1 {
            for i in 1..<g.colCount {
                col += 1
                g.setColWidth(col, 0x50)
                guard let b = blheli(i), b.isValid else { continue }
                g[col, 0] = DFormat("ESC#%d", [i])
                addParamRow(.name, b, col, db)              // FUN_0064D788(0x2D)
                var r = row(b.displayName(.escLayout, db), 0)
                g[col, r] = b.layoutDescription(db)
                r = row(b.isS ? "BLHeli_S Rev." : "BLHeli Rev.", 0)
                g[col, r] = b.revisionString
                r = row("Mode", 0)
                g[col, r] = b.modeName                      // FUN_005A6074
                for raw in 0..<0x2E where raw > 3 && !(14...15).contains(raw) && !(42...45).contains(raw) {
                    if let p = BLHeliParam(rawValue: raw) { addParamRow(p, b, col, db) }
                }
            }
        }
        if g.colCount < 2 { g.colCount = 2 }
        if g.rowCount < 2 { g.rowCount = 2 }
        g.fixedRows = 1
        g.fixedCols = 1
        g.autoSizeCol(0, 0x50)                              // FUN_005610CC
        updateCaption()                                     // FUN_0064D528
        g.setRowHeight(0, 0x18)                             // FUN_0051183C
        var h = g.rowCount * g.defaultRowHeight + 0x24
        if h < 0x1B9 { h = 0x1B9 }
        g.height = h
        height = h
        g.needsDisplay = true
    }

    /// FUN_0064D6B8: row of a parameter name in column 0; a new row (Objects[0] = parameter index) when missing.
    func row(_ name: String, _ param: Int) -> Int {
        let g = grdMain!
        var r = g.indexInCol(0, name)                       // FUN_0064CC50
        if r == -1 {
            g.rowCount += 1
            r = g.rowCount - 1
            g[0, r] = name
            g.setObject(0, r, param)
        }
        return r
    }

    /// FUN_0064D788: value text (Cells) and value (Objects) of one parameter of an ESC.
    func addParamRow(_ p: BLHeliParam, _ b: TBLHeli, _ col: Int, _ db: FirmwareDatabase?) {
        guard b.has(p, db) else { return }                  // FUN_005A6534
        let r = row(b.displayName(p, db), p.rawValue)
        let v = b.value(p)                                  // FUN_005A61DC
        grdMain[col, r] = b.valueText(p, v, db)             // FUN_005A566C
        grdMain.setObject(col, r, v)
    }

    /// FUN_0064D528: "Single ESC#n" / "Multiple ESC" / "Multiple ESC / Master#n" – shown as window caption when the
    /// frame is hosted directly by a form (TfrmESCTable); inside the main form's page control it has no visible effect.
    func updateCaption() {
        guard let m = main else { return }
        let n = (1...8).filter { m.slots[$0].selected }.count   // FUN_0064CCAC
        let c: String
        if n == 1 {
            c = DFormat("Single ESC#%d", [master])
        } else if n < 2 {
            c = NL("Multiple ESC")
        } else {
            c = DFormat("Multiple ESC / Master#%d", [master])
        }
        caption = c
    }

    // MARK: - drawing (grdMainDrawCell 0x64CD38)

    @objc func grdMainDrawCell(_ sender: TObject, _ a: TDrawCellArgs) {
        guard let m = main else { return }
        let g = grdMain!
        let cv = g.canvas
        let ms = master
        let db = m.db
        let r = a.rect
        if a.col > 0 && a.row > 2, let b = blheli(a.col), b.isValid {
            let p = BLHeliParam(rawValue: g.object(0, a.row)) ?? .invalid
            if p != .invalid && !b.isDefault(p, db) { cv.font.style = [.fsBold] }
            if a.col != ms {
                if let mb = blheli(ms), mb.isValid, g[a.col, a.row] != g[ms, a.row] {
                    cv.brushColor = 0xFFEFA6
                }
            }
            cv.fillRect(r)
            cv.textRect(r, r.minX + 2, r.minY + 2, g[a.col, a.row])
        } else if a.col > 0 && a.row == 0 {
            cv.font.style = [.fsBold]
            guard let btn = m.slots[a.col].btn else { return }
            let cap = btn.caption
            let text: String
            if (Int(cap) ?? 0) == 0 {
                cv.font.size = 12
                text = cap
            } else {
                cv.font.size = 10
                text = "ESC#" + cap
            }
            cv.font.color = btn.font.color
            let w = Int(cv.textWidth(text)), h = Int(cv.textHeight(text))
            let x = Int(r.minX) + Int(r.width) / 2 - w / 2
            let y = Int(r.minY) + Int(r.height) / 2 - h / 2
            cv.textRect(r, CGFloat(x), CGFloat(y), text)
        }
    }

    // MARK: - hints (grdMainMouseMove 0x64D1A8)

    @objc func grdMainMouseMove(_ sender: TObject, _ a: TMouseArgs) {
        guard let m = main else { return }
        let g = grdMain!
        let (c, r) = g.mouseToCell(a.x, a.y)
        guard c > 0 else { return }
        var h = ""
        if r == 0 {
            h = m.slots[c].btn?.hint ?? ""
        } else if r > 2, let b = blheli(c), b.isValid {
            let p = g.object(0, r)
            if p > 0, let bp = BLHeliParam(rawValue: p) {
                h = m.fraESCCombos1.hintText(bp, b.context(m.db))    // FUN_005A60D0 → FUN_005A9C70
            }
        }
        if g.hint != h {
            g.hint = h
            if h.isEmpty { Application.shared.cancelHint() } else { Application.shared.activateHint(g) }
        }
    }

    // MARK: - cell editing (only reachable with `editable`)

    /// grdMainSelectCell (0x64D2E0).
    @objc func grdMainSelectCell(_ sender: TObject, _ a: TSelectCellArgs) {
        a.canSelect = false
        guard editable else { return }
        ccbEdit.visible = false
        guard a.col > 0, let b = blheli(a.col), b.isValid else { return }
        if a.row < 5 {
            if a.row == 1 {
                a.canSelect = true
                ccbEdit.visible = false
            }
        } else {
            let rc = grdMain.cellRect(a.col, a.row)
            fillEditCombo(a.col, a.row)                      // FUN_0064D404
            ccbEdit.setBounds(Int(rc.minX) + grdMain.left, Int(rc.minY) + grdMain.top, Int(rc.width) + 1, Int(rc.height) + 1)
            ccbEdit.visible = true
            window?.makeFirstResponder(ccbEdit)
            a.canSelect = true
        }
    }

    /// FUN_0064D404: value list of the cell's parameter, current value selected.
    func fillEditCombo(_ col: Int, _ row: Int) {
        guard let m = main, let b = blheli(col), b.isValid else { return }
        let p = grdMain.object(0, row)
        if p > 0, let bp = BLHeliParam(rawValue: p) {
            let list = b.valueList(bp, m.db)
            ccbEdit.items = list.map(\.text)
            editValues = list.map(\.value)
            ccbEdit.itemIndex = ccbEdit.items.firstIndex(of: grdMain[col, row]) ?? -1
        } else {
            ccbEdit.items = [grdMain[col, row]]
            editValues = [grdMain.object(col, row)]
        }
    }

    /// ccbEditChange (0x64C96C): the chosen text and value go into the current cell.
    @objc func ccbEditChange(_ sender: TObject) {
        let i = ccbEdit.itemIndex
        guard i >= 0, i < ccbEdit.items.count else { return }
        grdMain[grdMain.col, grdMain.row] = ccbEdit.items[i]
        grdMain.setObject(grdMain.col, grdMain.row, i < editValues.count ? editValues[i] : 0)
    }

    /// ccbEditExit (0x64CB68).
    @objc func ccbEditExit(_ sender: TObject) {
        ccbEditChange(sender)
        ccbEdit.visible = false
        window?.makeFirstResponder(grdMain)
        grdMain.needsDisplay = true
    }

    /// ccbEditDrawItem (0x64CA20): the default value of the parameter on a silver background.
    @objc func ccbEditDrawItem(_ sender: TObject, _ a: TDrawItemArgs) {
        let r = a.rect
        guard a.index >= 0, a.index < ccbEdit.items.count else { Draw.fill(r, ccbEdit.nsColor); return }
        var bg = a.selected ? Colors.ns(clHighlight) : ccbEdit.nsColor
        if let m = main, let b = blheli(grdMain.col), b.isValid,
           let p = BLHeliParam(rawValue: grdMain.object(0, grdMain.row)),
           a.index < editValues.count, b.defaultValue(p, m.db) == editValues[a.index] {
            bg = Colors.ns(0xC0C0C0)
        }
        Draw.fill(r, bg)
        TextDraw.draw(ccbEdit.items[a.index], in: r.insetBy(dx: 2, dy: 0), font: ccbEdit.font.nsFont,
                      color: a.selected ? Colors.ns(clHighlightText) : Colors.ns(ccbEdit.font.color), accel: false)
    }
}
