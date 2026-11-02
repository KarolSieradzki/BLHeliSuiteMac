import AppKit

/// Minimal TCanvas for owner drawing (draws into the current graphics context of a flipped view).
public final class TCanvas: NSObject {
    public var brushColor: TColor = clWindow
    public var brushClear = false
    public var penColor: TColor = clBlack
    public var penWidth = 1
    public let font = TFont()
    var pen = NSPoint.zero

    public func fillRect(_ r: NSRect) {
        guard !brushClear else { return }
        Draw.fill(r, Colors.ns(brushColor))
    }

    public func frameRect(_ r: NSRect) { Draw.frame(r, Colors.ns(brushColor)) }

    public func rectangle(_ r: NSRect) {
        fillRect(r.insetBy(dx: 1, dy: 1))
        Draw.frame(r, Colors.ns(penColor))
    }

    public func moveTo(_ x: CGFloat, _ y: CGFloat) { pen = NSPoint(x: x, y: y) }

    public func lineTo(_ x: CGFloat, _ y: CGFloat) {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: pen.x + 0.5, y: pen.y + 0.5))
        p.line(to: NSPoint(x: x + 0.5, y: y + 0.5))
        Colors.ns(penColor).setStroke()
        p.lineWidth = CGFloat(penWidth)
        p.stroke()
        pen = NSPoint(x: x, y: y)
    }

    public func textOut(_ x: CGFloat, _ y: CGFloat, _ s: String) {
        let f = font.nsFont
        let w = TextDraw.width(s, f)
        if !brushClear { Draw.fill(NSRect(x: x, y: y, width: w, height: TextDraw.lineHeight(f)), Colors.ns(brushColor)) }
        TextDraw.draw(s, in: NSRect(x: x, y: y, width: w + 2, height: TextDraw.lineHeight(f)), font: f,
                      color: Colors.ns(font.color), accel: false)
    }

    public func textRect(_ r: NSRect, _ x: CGFloat, _ y: CGFloat, _ s: String) {
        if !brushClear { Draw.fill(r, Colors.ns(brushColor)) }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath.clip(r)
        TextDraw.draw(s, in: NSRect(x: x, y: y, width: max(0, r.maxX - x) + 200, height: r.maxY - y), font: font.nsFont,
                      color: Colors.ns(font.color), accel: false)
        NSGraphicsContext.restoreGraphicsState()
    }

    public func textWidth(_ s: String) -> CGFloat { TextDraw.width(s, font.nsFont) }
    public func textHeight(_ s: String) -> CGFloat { TextDraw.lineHeight(font.nsFont) }

    public func draw(_ x: CGFloat, _ y: CGFloat, _ img: NSImage) { Draw.image(img, at: NSPoint(x: x, y: y)) }
}

public struct TGridDrawState: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let gdSelected = TGridDrawState(rawValue: 1)
    public static let gdFocused = TGridDrawState(rawValue: 2)
    public static let gdFixed = TGridDrawState(rawValue: 4)
}

public final class TDrawCellArgs: NSObject {
    public let col: Int, row: Int
    public let rect: NSRect
    public let state: TGridDrawState
    public init(_ c: Int, _ r: Int, _ rect: NSRect, _ s: TGridDrawState) { col = c; row = r; self.rect = rect; state = s }
}

public final class TSelectCellArgs: NSObject {
    public let col: Int, row: Int
    public var canSelect = true
    public init(_ c: Int, _ r: Int) { col = c; row = r }
}

// MARK: - TDrawGrid / TStringGrid / TJvStringGrid

open class TDrawGrid: TControl {
    public var colCount = 5 { didSet { resizeCells(); updateScrollBars() } }
    public var rowCount = 5 { didSet { resizeCells(); updateScrollBars() } }
    public var fixedCols = 1
    public var fixedRows = 1
    public var defaultColWidth = 64
    public var defaultRowHeight = 24
    public var colWidths: [Int: Int] = [:]
    public var rowHeights: [Int: Int] = [:]
    public var gridLineWidth = 1
    public var options: Set<String> = ["goFixedVertLine", "goFixedHorzLine", "goVertLine", "goHorzLine", "goRangeSelect"]
    public var defaultDrawing = true
    public var fixedColor: TColor = clBtnFace
    public let fixedFont = TFont()
    public var col = 1, row = 1
    public var topRow = 1 { didSet { needsDisplay = true } }
    public var leftCol = 1 { didSet { needsDisplay = true } }
    public var cells: [[String]] = []
    /// TStringGrid.Objects – BLHeliSuite stores small integers (parameter index / value) there.
    public var objects: [[Int]] = []
    public var alignment: TTextAlignment = .left
    public var scrollBarsKind = "ssBoth"
    public var borderSingle = true
    public let canvas = TCanvas()
    public var onDrawCell: ((TObject, TDrawCellArgs) -> Void)?
    public var onSelectCell: ((TObject, TSelectCellArgs) -> Void)?
    let vbar = TScrollBar(frame: .zero)
    let hbar = TScrollBar(frame: .zero)

    public required init(frame: NSRect) {
        super.init(frame: frame)
        color = clWindow
        parentColor = false
        vbar.vertical = true
        vbar.loadingSB = false
        hbar.loadingSB = false
        vbar.onChange = { [weak self] s in guard let self else { return }; self.topRow = self.fixedRows + self.vbar.position }
        hbar.onChange = { [weak self] s in guard let self else { return }; self.leftCol = self.fixedCols + self.hbar.position }
        addSubview(vbar)
        addSubview(hbar)
        resizeCells()
    }

    public required init?(coder: NSCoder) { fatalError() }

    func resizeCells() {
        while cells.count < colCount { cells.append([]) }
        if cells.count > colCount { cells.removeLast(cells.count - colCount) }
        for c in 0..<cells.count {
            while cells[c].count < rowCount { cells[c].append("") }
            if cells[c].count > rowCount { cells[c].removeLast(cells[c].count - rowCount) }
        }
        while objects.count < colCount { objects.append([]) }
        if objects.count > colCount { objects.removeLast(objects.count - colCount) }
        for c in 0..<objects.count {
            while objects[c].count < rowCount { objects[c].append(0) }
            if objects[c].count > rowCount { objects[c].removeLast(objects[c].count - rowCount) }
        }
        needsDisplay = true
    }

    /// Objects[c, r].
    public func object(_ c: Int, _ r: Int) -> Int { (c < objects.count && r < objects[c].count) ? objects[c][r] : 0 }

    public func setObject(_ c: Int, _ r: Int, _ v: Int) {
        if c >= colCount || r >= rowCount { return }
        if c >= objects.count || r >= objects[c].count { resizeCells() }
        objects[c][r] = v
    }

    /// Cols[c].IndexOf(s) (TStrings.IndexOf: case insensitive).
    public func indexInCol(_ c: Int, _ s: String) -> Int {
        guard c < cells.count else { return -1 }
        return cells[c].firstIndex { $0.caseInsensitiveCompare(s) == .orderedSame } ?? -1
    }

    /// TJvStringGrid.Clear: empties all cells (strings and objects).
    public func clear() {
        cells = cells.map { $0.map { _ in "" } }
        objects = objects.map { $0.map { _ in 0 } }
        needsDisplay = true
    }

    /// TJvStringGrid.AutoSizeCol(Index, MinWidth): column as wide as its longest text (+8), at least MinWidth.
    public func autoSizeCol(_ index: Int, _ minWidth: Int) {
        var w = minWidth < 0 ? defaultColWidth : minWidth
        for r in 0..<rowCount {
            let f = (index < fixedCols || r < fixedRows) ? fixedFont : font
            w = max(w, Int(TextDraw.width(self[index, r], f.nsFont).rounded(.up)) + 8)
        }
        setColWidth(index, w)
    }

    public subscript(_ c: Int, _ r: Int) -> String {
        get { (c < cells.count && r < cells[c].count) ? cells[c][r] : "" }
        set {
            if c >= cells.count || r >= rowCount { return }
            if r >= cells[c].count { resizeCells() }
            cells[c][r] = newValue
            needsDisplay = true
        }
    }

    public func colWidth(_ c: Int) -> Int { colWidths[c] ?? defaultColWidth }
    public func rowHeight(_ r: Int) -> Int { rowHeights[r] ?? defaultRowHeight }
    public func setColWidth(_ c: Int, _ w: Int) { colWidths[c] = w; updateScrollBars(); needsDisplay = true }
    public func setRowHeight(_ r: Int, _ h: Int) { rowHeights[r] = h; updateScrollBars(); needsDisplay = true }

    var lw: CGFloat { CGFloat(gridLineWidth) }
    var inner: NSRect {
        var r = bounds.insetBy(dx: borderSingle ? 1 : 0, dy: borderSingle ? 1 : 0)
        if !vbar.isHidden { r.size.width -= 17 }
        if !hbar.isHidden { r.size.height -= 17 }
        return r
    }

    func updateScrollBars() {
        let showV = (scrollBarsKind == "ssBoth" || scrollBarsKind == "ssVertical") && totalHeight() > bounds.height - 2
        let showH = (scrollBarsKind == "ssBoth" || scrollBarsKind == "ssHorizontal") && totalWidth() > bounds.width - 2
        vbar.isHidden = !showV
        hbar.isHidden = !showH
        let b: CGFloat = borderSingle ? 1 : 0
        vbar.frame = NSRect(x: bounds.width - 17 - b, y: b, width: 17, height: bounds.height - 2 * b - (showH ? 17 : 0))
        hbar.frame = NSRect(x: b, y: bounds.height - 17 - b, width: bounds.width - 2 * b - (showV ? 17 : 0), height: 17)
        let visRows = visibleScrollRows()
        vbar.setParams(position: max(0, topRow - fixedRows), min: 0, max: max(0, rowCount - fixedRows - visRows))
        vbar.largeChange = max(1, visRows)
        hbar.setParams(position: max(0, leftCol - fixedCols), min: 0, max: max(0, colCount - fixedCols - 1))
    }

    func totalHeight() -> CGFloat { (0..<rowCount).reduce(0) { $0 + CGFloat(rowHeight($1)) + lw } }
    func totalWidth() -> CGFloat { (0..<colCount).reduce(0) { $0 + CGFloat(colWidth($1)) + lw } }

    func visibleScrollRows() -> Int {
        var h = inner.height
        for r in 0..<min(fixedRows, rowCount) { h -= CGFloat(rowHeight(r)) + lw }
        var n = 0
        var r = topRow
        while r < rowCount && h >= CGFloat(rowHeight(r)) { h -= CGFloat(rowHeight(r)) + lw; n += 1; r += 1 }
        return max(1, n)
    }

    /// Column/row order as drawn (fixed first, then scrolled).
    func visibleCols() -> [Int] { Array(0..<min(fixedCols, colCount)) + Array(max(leftCol, fixedCols)..<max(max(leftCol, fixedCols), colCount)) }
    func visibleRowsList() -> [Int] { Array(0..<min(fixedRows, rowCount)) + Array(max(topRow, fixedRows)..<max(max(topRow, fixedRows), rowCount)) }

    public func cellRect(_ c: Int, _ r: Int) -> NSRect {
        var x = inner.minX, y = inner.minY
        for cc in visibleCols() { if cc == c { break }; x += CGFloat(colWidth(cc)) + lw }
        for rr in visibleRowsList() { if rr == r { break }; y += CGFloat(rowHeight(rr)) + lw }
        return NSRect(x: x, y: y, width: CGFloat(colWidth(c)), height: CGFloat(rowHeight(r)))
    }

    public func mouseToCell(_ x: Int, _ y: Int) -> (Int, Int) {
        var cx = inner.minX, col = -1
        for c in visibleCols() {
            let w = CGFloat(colWidth(c)) + lw
            if CGFloat(x) >= cx && CGFloat(x) < cx + w { col = c; break }
            cx += w
        }
        var cy = inner.minY, row = -1
        for r in visibleRowsList() {
            let h = CGFloat(rowHeight(r)) + lw
            if CGFloat(y) >= cy && CGFloat(y) < cy + h { row = r; break }
            cy += h
        }
        return (col, row)
    }

    open override func resized() {
        super.resized()
        updateScrollBars()
    }

    open override func draw(_ dirtyRect: NSRect) {
        Draw.fill(bounds, nsColor)
        let area = inner
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath.clip(area)
        var y = area.minY
        for r in visibleRowsList() {
            if y > area.maxY { break }
            var x = area.minX
            let rh = CGFloat(rowHeight(r))
            for c in visibleCols() {
                if x > area.maxX { break }
                let cw = CGFloat(colWidth(c))
                let rect = NSRect(x: x, y: y, width: cw, height: rh)
                let fixed = c < fixedCols || r < fixedRows
                var st: TGridDrawState = []
                if fixed { st.insert(.gdFixed) }
                let rowSel = options.contains("goRowSelect")
                // TCustomGrid.DrawCells: the current cell is gdSelected, gdFocused only while the grid has the focus;
                // a selected cell is highlighted unless it is the focused one (goDrawFocusSelected / goRowSelect: always)
                if !fixed && (r == row && (c == col || rowSel)) { st.insert(.gdSelected); if c == col && isFocused { st.insert(.gdFocused) } }
                let highlight = st.contains(.gdSelected) && (!st.contains(.gdFocused) || options.contains("goDrawFocusSelected") || rowSel)
                if defaultDrawing {
                    if fixed {
                        Draw.fill(rect, Colors.ns(fixedColor))
                    } else if highlight {
                        Draw.fill(rect, Colors.ns(clHighlight))
                    } else {
                        Draw.fill(rect, nsColor)
                    }
                    let tf = fixed ? fixedFont : font
                    let selText = highlight && !fixed
                    // TJvStringGrid applies Alignment only without an OnDrawCell handler; otherwise TStringGrid
                    // draws the text left aligned at (Left + 2, Top + 2).
                    TextDraw.draw(self[c, r], in: rect.insetBy(dx: 2, dy: 2), font: tf.nsFont,
                                  color: selText ? Colors.ns(clHighlightText) : Colors.ns(tf.color),
                                  align: onDrawCell == nil ? alignment : .left, accel: false)
                }
                canvas.font.assign(fixed ? fixedFont : font)
                canvas.brushColor = fixed ? fixedColor : color
                if highlight && !fixed && defaultDrawing {
                    canvas.brushColor = clHighlight
                    canvas.font.color = clHighlightText
                }
                canvas.brushClear = false
                onDrawCell?(self, TDrawCellArgs(c, r, rect, st))
                if st.contains(.gdFocused) && !rowSel && defaultDrawing { drawFocusRect(rect) }
                // grid lines
                let vl = fixed ? options.contains("goFixedVertLine") : options.contains("goVertLine")
                let hl = fixed ? options.contains("goFixedHorzLine") : options.contains("goHorzLine")
                if lw > 0 {
                    let lc = fixed ? Colors.hex(0xA0A0A0) : Colors.hex(0xF0F0F0)
                    if vl { Draw.fill(NSRect(x: rect.maxX, y: rect.minY, width: lw, height: rh + lw), lc) }
                    if hl { Draw.fill(NSRect(x: rect.minX, y: rect.maxY, width: cw + lw, height: lw), lc) }
                }
                x += cw + lw
            }
            y += rh + lw
        }
        NSGraphicsContext.restoreGraphicsState()
        if borderSingle { Draw.frame(bounds, Colors.hex(0x828790)) }
    }

    /// The grid has the keyboard focus (TWinControl.Focused).
    public var isFocused: Bool { window?.firstResponder === self && window?.isKeyWindow == true }
    open override var acceptsFirstResponder: Bool { true }
    open override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    open override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    /// DrawFocusRect: dotted rectangle.
    func drawFocusRect(_ r: NSRect) {
        let p = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5))
        p.lineWidth = 1
        p.setLineDash([1, 1], count: 2, phase: 0)
        NSColor.black.setStroke()
        p.stroke()
    }

    public func selectCell(_ c: Int, _ r: Int) -> Bool {
        let a = TSelectCellArgs(c, r)
        onSelectCell?(self, a)
        if a.canSelect { col = c; row = r; needsDisplay = true }
        return a.canSelect
    }

    open override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        window?.makeFirstResponder(self)
        let (x, y) = localPoint(event)
        let (c, r) = mouseToCell(x, y)
        if c >= fixedCols && r >= fixedRows { _ = selectCell(c, r) }
    }

    open override func scrollWheel(with event: NSEvent) {
        guard !vbar.isHidden else { return }
        if event.scrollingDeltaY > 0.5 { vbar.setPos(vbar.position - 1) } else if event.scrollingDeltaY < -0.5 { vbar.setPos(vbar.position + 1) }
    }

    open override func loaded() {
        resizeCells()
        updateScrollBars()
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "ColCount": colCount = value.intValue ?? 5
        case "RowCount": rowCount = value.intValue ?? 5
        case "FixedCols": fixedCols = value.intValue ?? 1; col = fixedCols; leftCol = fixedCols
        case "FixedRows": fixedRows = value.intValue ?? 1; row = fixedRows; topRow = fixedRows
        case "DefaultColWidth": defaultColWidth = value.intValue ?? 64
        case "DefaultRowHeight": defaultRowHeight = value.intValue ?? 24
        case "GridLineWidth": gridLineWidth = value.intValue ?? 1
        case "DefaultDrawing": defaultDrawing = value.boolValue ?? true
        case "FixedColor": fixedColor = Colors.value(value) ?? clBtnFace
        case "Options": if case .set(let s) = value { options = Set(s) }
        case "ScrollBars": scrollBarsKind = value.stringValue ?? "ssBoth"
        case "BorderStyle": borderSingle = value.stringValue != "bsNone"
        case "Alignment": alignment = parseAlignment(value)
        case "ColWidths":
            if case .list(let l) = value { for (i, v) in l.enumerated() { colWidths[i] = v.intValue ?? defaultColWidth } }
        case "RowHeights":
            if case .list(let l) = value { for (i, v) in l.enumerated() { rowHeights[i] = v.intValue ?? defaultRowHeight } }
        case "FixedFont.Name": fixedFont.name = value.stringValue ?? "Tahoma"
        case "FixedFont.Height": fixedFont.height = value.intValue ?? -11
        case "FixedFont.Color": fixedFont.color = Colors.value(value) ?? clWindowText
        case "FixedFont.Style":
            if case .set(let s) = value { fixedFont.style = s.contains("fsBold") ? [.fsBold] : [] }
        case "OnDrawCell": loader.drawCellEvent(value) { [weak self] h in self?.onDrawCell = h }
        case "OnSelectCell": loader.selectCellEvent(value) { [weak self] h in self?.onSelectCell = h }
        case "FixedFont.Charset", "BevelInner", "BevelOuter", "Ctl3D", "ParentCtl3D", "DrawingStyle", "Editable",
             "AutoSizeRows", "FixedRowFontSettings.Font.Charset":
            break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

public typealias TStringGrid = TDrawGrid
