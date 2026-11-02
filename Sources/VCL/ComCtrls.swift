import AppKit

// MARK: - TPageControl / TJvPageControl + TTabSheet

open class TTabSheet: TControl {
    public weak var pageControl: TPageControl?
    public var tabVisible = true { didSet { pageControl?.needsDisplay = true; pageControl?.layoutPages() } }
    public var imageIndex = -1
    public var pageIndex: Int { pageControl?.pages.firstIndex(where: { $0 === self }) ?? -1 }

    public required init(frame: NSRect) {
        super.init(frame: frame)
        color = clWindow
    }

    public required init?(coder: NSCoder) { fatalError() }

    open override func captionChanged() { pageControl?.needsDisplay = true }

    open override func draw(_ dirtyRect: NSRect) { Draw.fill(bounds, Colors.ns(clWindow)) }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "TabVisible": tabVisible = value.boolValue ?? true
        case "ImageIndex": imageIndex = value.intValue ?? -1
        case "PageIndex", "Highlighted": break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

open class TPageControl: TControl {
    public var pages: [TTabSheet] = []
    public var tabHeight = 0
    public var tabWidth = 0
    public var hotTrack = false
    public weak var activePage: TTabSheet? {
        didSet {
            for p in pages { p.isHidden = p !== activePage }
            needsDisplay = true
        }
    }
    public var onChanging: ((TObject, inout Bool) -> Void)?
    var pendingActivePage: String?
    private var hotTab = -1

    public required init(frame: NSRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { fatalError() }

    open override var wantsHover: Bool { true }

    public var activePageIndex: Int {
        get { activePage.flatMap { p in pages.firstIndex { $0 === p } } ?? -1 }
        set { activePage = (newValue >= 0 && newValue < pages.count) ? pages[newValue] : nil }
    }

    public var pageCount: Int { pages.count }

    var headerHeight: CGFloat { CGFloat(tabHeight > 0 ? tabHeight + 4 : Int(TextDraw.lineHeight(font.nsFont)) + 8) }

    func tabRects() -> [(TTabSheet, NSRect)] {
        var out: [(TTabSheet, NSRect)] = []
        var x: CGFloat = 2
        let f = font.nsFont
        for p in pages where p.tabVisible {
            let w = tabWidth > 0 ? CGFloat(tabWidth) : (TextDraw.width(TextDraw.stripAccel(p.caption), f) + 12).rounded(.up)
            out.append((p, NSRect(x: x, y: 2, width: w, height: headerHeight - 2)))
            x += w
        }
        return out
    }

    open override var alignRect: NSRect {
        NSRect(x: 1, y: headerHeight + 1, width: max(0, bounds.width - 2), height: max(0, bounds.height - headerHeight - 2))
    }

    func layoutPages() {
        let r = alignRect
        for p in pages { p.frame = r; p.resized() }
    }

    open override func resized() {
        super.resized()
        layoutPages()
    }

    open override func realign() { layoutPages() }

    open override func draw(_ dirtyRect: NSRect) {
        Draw.fill(bounds, Colors.ns(parentControl?.color ?? clBtnFace))
        let body = NSRect(x: 0, y: headerHeight, width: bounds.width, height: bounds.height - headerHeight)
        Draw.fill(body, Colors.ns(clWindow))
        Draw.frame(body, Theme.tabBorder)
        let f = font.nsFont
        for (i, (p, r0)) in tabRects().enumerated() {
            let sel = p === activePage
            var r = r0
            if sel { r = NSRect(x: r0.minX - 2, y: 0, width: r0.width + 4, height: headerHeight + 1) }
            let hover = i == hotTab && !sel
            Draw.fill(r, sel ? Colors.ns(clWindow) : (hover ? Theme.tabHover : Theme.face))
            let bc = hover ? Theme.tabHoverBorder : Theme.tabBorder
            Draw.hline(r.minX, r.maxX, r.minY, bc)
            Draw.vline(r.minX, r.minY, r.maxY, bc)
            Draw.vline(r.maxX - 1, r.minY, r.maxY, bc)
            if sel { Draw.fill(NSRect(x: r.minX + 1, y: headerHeight - 1, width: r.width - 2, height: 2), Colors.ns(clWindow)) }
            TextDraw.draw(p.caption, in: NSRect(x: r.minX, y: r.minY + (sel ? 1 : 0), width: r.width, height: r.height - (sel ? 2 : 0)),
                          font: f, color: Colors.ns(font.color), align: .center, layout: .center)
        }
    }

    open override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let p = convert(event.locationInWindow, from: nil)
        let i = tabRects().firstIndex { $0.1.contains(p) } ?? -1
        if i != hotTab { hotTab = i; needsDisplay = true }
    }

    open override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hotTab = -1
        needsDisplay = true
    }

    open override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard effectiveEnabled, let (page, _) = tabRects().first(where: { $0.1.contains(p) }), page !== activePage else { return }
        selectPage(page)
    }

    /// User driven page change (OnChanging / OnChange).
    public func selectPage(_ page: TTabSheet) {
        var allow = true
        onChanging?(self, &allow)
        guard allow else { return }
        activePage = page
        onChange?(self)
    }

    open override func loaded() {
        if let n = pendingActivePage, let p = pages.first(where: { $0.name == n }) { activePage = p }
        else if activePage == nil { activePage = pages.first }
        layoutPages()
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "ActivePage": pendingActivePage = value.stringValue
        case "TabHeight": tabHeight = value.intValue ?? 0
        case "TabWidth": tabWidth = value.intValue ?? 0
        case "HotTrack": hotTrack = value.boolValue ?? false
        case "OnChanging": loader.boolEvent(value) { [weak self] h in self?.onChanging = h }
        case "ClientBorderWidth", "HintSource", "Images", "MultiLine", "Style", "TabPosition", "TabIndex", "ReduceMemoryUse",
             "DrawTabShadow", "HandleGlobalTab", "ParentColor":
            break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

// MARK: - TStatusBar / TJvStatusBar

open class TStatusBar: TControl {
    public struct Panel { public var text = ""; public var width = 50; public var alignment: TTextAlignment = .left }
    public var panels: [Panel] = [] { didSet { needsDisplay = true } }
    public var simplePanel = false
    public var simpleText = "" { didSet { needsDisplay = true } }

    public required init(frame: NSRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { fatalError() }

    public func setPanelText(_ i: Int, _ s: String) {
        while panels.count <= i { panels.append(Panel()) }
        panels[i].text = s
    }

    open override func draw(_ dirtyRect: NSRect) {
        Draw.fill(bounds, Theme.face)
        let f = font.nsFont
        // the Windows status bar draws its texts on a single line (DT_SINGLELINE): CR/LF do not break the line
        func oneLine(_ t: String) -> String {
            t.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        }
        if simplePanel || panels.isEmpty {
            TextDraw.draw(oneLine(simpleText), in: NSRect(x: 4, y: 0, width: bounds.width - 20, height: bounds.height), font: f,
                          color: Colors.ns(font.color), layout: .center, accel: false)
        } else {
            var x: CGFloat = 0
            for (i, p) in panels.enumerated() {
                let w = (i == panels.count - 1) ? bounds.width - x - 14 : CGFloat(p.width)
                TextDraw.draw(oneLine(p.text), in: NSRect(x: x + 3, y: 0, width: max(0, w - 6), height: bounds.height), font: f,
                              color: Colors.ns(font.color), align: p.alignment, layout: .center, singleLine: true, accel: false, ellipsis: false)
                x += w
                if i < panels.count - 1 { Draw.vline(x - 1, 3, bounds.height - 2, Colors.hex(0xD7D7D7)) }
            }
        }
        // size grip
        let c = Colors.hex(0xB9B9B9)
        for i in 0..<3 {
            for j in 0..<(3 - i) {
                Draw.fill(NSRect(x: bounds.width - 4 - CGFloat(j) * 4, y: bounds.height - 4 - CGFloat(i) * 4, width: 2, height: 2), c)
            }
        }
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "Panels":
            if case .collection(let items) = value {
                panels = items.map { it in
                    var p = Panel()
                    p.width = it["Width"]?.intValue ?? 50
                    p.text = it["Text"]?.stringValue ?? ""
                    if let a = it["Alignment"] { p.alignment = parseAlignment(a) }
                    return p
                }
            }
        case "SimplePanel": simplePanel = value.boolValue ?? false
        case "SimpleText": simpleText = value.stringValue ?? ""
        case "AutoHint", "SizeGrip", "UseSystemFont": break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

// MARK: - TTreeView (used by the log window)

open class TTreeNode: NSObject {
    public var text: String
    public var color: TColor
    public var bold = false
    public var imageIndex = -1
    public var children: [TTreeNode] = []
    public weak var parentNode: TTreeNode?
    public var expanded = true
    public var data: AnyObject?

    public init(_ text: String, color: TColor = clWindowText) {
        self.text = text
        self.color = color
    }

    public var level: Int { var l = 0; var p = parentNode; while p != nil { l += 1; p = p?.parentNode }; return l }
}

open class TTreeView: TControl {
    public let scroll = NSScrollView(frame: .zero)
    let content = TreeContent(frame: .zero)
    public var roots: [TTreeNode] = []
    public weak var images: TImageList?
    public var indent = 19
    public weak var selected: TTreeNode? { didSet { content.needsDisplay = true } }
    public var autoScroll = true

    final class TreeContent: NSView {
        weak var tree: TTreeView?
        override var isFlipped: Bool { true }
        var rows: [TTreeNode] = []

        override func draw(_ dirtyRect: NSRect) {
            guard let t = tree else { return }
            Draw.fill(dirtyRect, Colors.ns(t.color))
            let f = t.font.nsFont
            let bf = TFont.make(name: t.font.name, height: t.font.height, style: [.fsBold])
            let rh = t.rowHeight
            let first = max(0, Int(dirtyRect.minY / rh)), last = min(rows.count, Int(dirtyRect.maxY / rh) + 1)
            guard first < last else { return }
            for i in first..<last {
                let n = rows[i]
                let y = CGFloat(i) * rh
                var x = CGFloat(n.level * t.indent) + 2
                if !n.children.isEmpty {
                    Draw.chevron(center: NSPoint(x: x + 6, y: y + rh / 2), size: 6, direction: n.expanded ? 0 : 3, color: Colors.hex(0x404040))
                }
                x += 14
                if let img = t.images?.image(n.imageIndex) { Draw.image(img, at: NSPoint(x: x, y: y + (rh - img.size.height) / 2)); x += img.size.width + 3 }
                let sel = n === t.selected
                let font = n.bold ? bf : f
                let w = TextDraw.width(n.text, font) + 4
                if sel { Draw.fill(NSRect(x: x - 2, y: y, width: w, height: rh), Colors.hex(0xCCE8FF)) }
                TextDraw.draw(n.text, in: NSRect(x: x, y: y, width: max(w, bounds.width - x), height: rh), font: font,
                              color: Colors.ns(n.color), layout: .center, accel: false)
            }
        }

        override func mouseDown(with event: NSEvent) {
            guard let t = tree else { return }
            let p = convert(event.locationInWindow, from: nil)
            let i = Int(p.y / t.rowHeight)
            guard i >= 0 && i < rows.count else { return }
            let n = rows[i]
            let x = CGFloat(n.level * t.indent) + 2
            if !n.children.isEmpty && p.x < x + 14 { n.expanded.toggle(); t.reload(); return }
            t.selected = n
            if event.clickCount == 2 && !n.children.isEmpty { n.expanded.toggle(); t.reload() }
        }

        override func rightMouseDown(with event: NSEvent) {
            tree?.rightMouseDown(with: event)
        }
    }

    public required init(frame: NSRect) {
        super.init(frame: frame)
        color = clWindow
        parentColor = false
        content.tree = self
        scroll.documentView = content
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        addSubview(scroll)
    }

    public required init?(coder: NSCoder) { fatalError() }

    var rowHeight: CGFloat { max(17, TextDraw.lineHeight(font.nsFont) + 4) }

    public func addChild(_ parent: TTreeNode?, _ text: String, color: TColor = clWindowText) -> TTreeNode {
        let n = TTreeNode(text, color: color)
        if let p = parent { n.parentNode = p; p.children.append(n) } else { roots.append(n) }
        return n
    }

    public func clear() {
        roots = []
        selected = nil
        reload()
    }

    public var nodeCount: Int {
        func c(_ ns: [TTreeNode]) -> Int { ns.reduce(0) { $0 + 1 + c($1.children) } }
        return c(roots)
    }

    public func reload() {
        var rows: [TTreeNode] = []
        func walk(_ ns: [TTreeNode]) { for n in ns { rows.append(n); if n.expanded { walk(n.children) } } }
        walk(roots)
        content.rows = rows
        let f = font.nsFont
        let w = rows.map { CGFloat($0.level * indent) + 40 + TextDraw.width($0.text, f) }.max() ?? 0
        content.frame = NSRect(x: 0, y: 0, width: max(scroll.contentSize.width, w), height: max(scroll.contentSize.height, CGFloat(rows.count) * rowHeight))
        content.needsDisplay = true
        if autoScroll, let last = rows.last { _ = last; content.scroll(NSPoint(x: 0, y: max(0, content.frame.height - scroll.contentSize.height))) }
    }

    open override func resized() {
        super.resized()
        scroll.frame = bounds.insetBy(dx: 1, dy: 1)
        reload()
    }

    open override func draw(_ dirtyRect: NSRect) {
        Draw.fill(bounds, nsColor)
        Draw.frame(bounds, Colors.hex(0x828790))
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "Images": loader.fixup(value) { [weak self] (i: TImageList) in self?.images = i }
        case "Indent": indent = value.intValue ?? 19
        case "HotTrack", "ReadOnly", "OnAdvancedCustomDrawItem", "OnChanging", "OnDeletion", "ShowRoot", "ShowLines",
             "ShowButtons", "RowSelect", "HideSelection", "AutoExpand", "BorderStyle", "Items.NodeData":
            break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}
