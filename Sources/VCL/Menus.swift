import AppKit

/// TMenuItem.
public final class TMenuItem: TComponent {
    public var caption = ""
    public var enabled = true
    public var visible = true
    public var checked = false {
        didSet {
            if checked && radioItem && groupIndex > 0, let p = parentItem {
                for s in p.items where s !== self && s.radioItem && s.groupIndex == groupIndex { s.checked = false }
            }
        }
    }
    public var radioItem = false
    public var groupIndex = 0
    public var autoCheck = false
    public var imageIndex = -1
    public var bitmap: NSImage?
    public var hint = ""
    public var shortCut = 0
    public var isDefault = false
    public var items: [TMenuItem] = []
    public weak var parentItem: TMenuItem?
    public weak var menu: TMenu?
    public var onClick: TNotifyEvent?
    public weak var action: TAction? {
        didSet {
            oldValue?.removeClient(self)
            action?.addClient(self)
            if let a = action { actionChanged(a) }
        }
    }

    public var isLine: Bool { caption == "-" }
    public var count: Int { items.count }

    public func add(_ m: TMenuItem) {
        m.parentItem = self
        m.menu = menu
        items.append(m)
    }

    public func clear() { items.removeAll() }

    func actionChanged(_ a: TAction) {
        caption = a.caption
        enabled = a.enabled
        visible = a.visible
        checked = a.checked
        imageIndex = a.imageIndex
        hint = a.hint
    }

    public func click() {
        guard enabled else { return }
        if autoCheck { checked.toggle() }
        if let h = onClick { h(self) } else if let a = action { a.execute() }
    }

    var displayImage: NSImage? {
        if let b = bitmap { return b }
        if imageIndex >= 0 { return (menu?.images ?? action?.actionList?.images)?.image(imageIndex, enabled: enabled) }
        return nil
    }

    public override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "Caption": caption = value.stringValue ?? ""
        case "Enabled": enabled = value.boolValue ?? true
        case "Visible": visible = value.boolValue ?? true
        case "Checked": checked = value.boolValue ?? false
        case "RadioItem": radioItem = value.boolValue ?? false
        case "GroupIndex": groupIndex = value.intValue ?? 0
        case "AutoCheck": autoCheck = value.boolValue ?? false
        case "ImageIndex": imageIndex = value.intValue ?? -1
        case "Hint": hint = value.stringValue ?? ""
        case "ShortCut": shortCut = value.intValue ?? 0
        case "Default": isDefault = value.boolValue ?? false
        case "Bitmap.Data":
            if case .binary(let b) = value, var bmp = DIB.bitmapProperty(b) {
                if !bmp.hasAlpha { bmp = bmp.keyedTransparent() }
                bitmap = bmp.image
            }
        case "Action": loader.fixup(value) { [weak self] (a: TAction) in self?.action = a }
        case "OnClick": loader.event(value) { [weak self] h in self?.onClick = h }
        case "AutoHotkeys", "AutoLineReduction", "Break", "HelpContext", "SubMenuImages": break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

/// TMainMenu / TPopupMenu base.
open class TMenu: TComponent {
    public let items = TMenuItem()
    public weak var images: TImageList?
    public var onPopup: TNotifyEvent?

    public override init() {
        super.init()
        items.menu = self
    }

    public override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "Images": loader.fixup(value) { [weak self] (i: TImageList) in self?.images = i }
        case "OnPopup": loader.event(value) { [weak self] h in self?.onPopup = h }
        case "Style", "OnGetImageIndex", "AutoMerge", "AutoPopup", "AutoHotkeys", "Alignment", "TrackButton",
             "ImageMargin.Left", "ImageMargin.Top", "ImageMargin.Right", "ImageMargin.Bottom", "ImageSize.Height",
             "ImageSize.Width", "OwnerDraw", "HotImages", "DisabledImages", "MenuAnimation":
            break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

public final class TMainMenu: TMenu {}

public final class TPopupMenu: TMenu {
    public weak var popupComponent: AnyObject?

    public func popup(in view: NSView, at p: NSPoint) {
        popupComponent = view
        onPopup?(self)
        guard let w = view.window else { return }
        let sp = w.convertToScreen(view.convert(NSRect(origin: p, size: .zero), to: nil)).origin
        MenuPopupWindow.show(items: items.items.filter(\.visible), at: sp, parentWindow: w, owner: nil)
    }
}

// MARK: - Painting (JVCL msXP painter look)

enum XPMenu {
    static var font: NSFont { TFont.messageFont }
    static let margin: CGFloat = 24
    static let itemHeight: CGFloat = 22
    static let sepHeight: CGFloat = 7
    static let selFill = Colors.hex(0xCCE4F7)
    static let selBorder = Colors.hex(0x0078D7)
    static let imageBack = Colors.hex(0xF0F0F0)
    static let separator = Colors.hex(0xD7D7D7)
    static let border = Colors.hex(0x979797)

    static func shortcutText(_ sc: Int) -> String {
        guard sc != 0 else { return "" }
        var s = ""
        if sc & 0x4000 != 0 { s += "Ctrl+" }
        if sc & 0x2000 != 0 { s += "Shift+" }
        if sc & 0x8000 != 0 { s += "Alt+" }
        let k = sc & 0xFF
        if k >= 0x70 && k <= 0x7B { s += "F\(k - 0x6F)" } else if let u = Unicode.Scalar(k) { s += String(Character(u)) }
        return s
    }
}

final class MenuPopupView: NSView {
    var items: [TMenuItem] = []
    var hot = -1
    weak var popup: MenuPopupWindow?
    override var isFlipped: Bool { true }

    func rowRects() -> [NSRect] {
        var y: CGFloat = 2
        return items.map { it in
            let h = it.isLine ? XPMenu.sepHeight : XPMenu.itemHeight
            defer { y += h }
            return NSRect(x: 2, y: y, width: bounds.width - 4, height: h)
        }
    }

    static func size(for items: [TMenuItem]) -> NSSize {
        let f = XPMenu.font
        var w: CGFloat = 0, sw: CGFloat = 0, h: CGFloat = 4
        for it in items {
            h += it.isLine ? XPMenu.sepHeight : XPMenu.itemHeight
            w = max(w, TextDraw.width(TextDraw.stripAccel(it.caption), f))
            sw = max(sw, TextDraw.width(XPMenu.shortcutText(it.shortCut), f))
        }
        return NSSize(width: (XPMenu.margin + 8 + w + (sw > 0 ? sw + 24 : 0) + 30).rounded(.up), height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        Draw.fill(bounds, .white)
        Draw.fill(NSRect(x: 1, y: 1, width: XPMenu.margin + 1, height: bounds.height - 2), XPMenu.imageBack)
        let f = XPMenu.font
        for (i, (it, r)) in zip(items, rowRects()).enumerated() {
            if it.isLine {
                Draw.hline(XPMenu.margin + 8, r.maxX - 2, r.midY.rounded(.down), XPMenu.separator)
                continue
            }
            let sel = i == hot
            if sel {
                Draw.fill(r, it.enabled ? XPMenu.selFill : Colors.hex(0xE6E6E6))
                Draw.frame(r, it.enabled ? XPMenu.selBorder : Colors.hex(0xCCCCCC))
            }
            let color = it.enabled ? NSColor.black : Colors.hex(0x6D6D6D)
            if it.checked {
                let cb = NSRect(x: r.minX + 1, y: r.minY + 1, width: XPMenu.itemHeight - 2, height: XPMenu.itemHeight - 2)
                Draw.fill(cb, sel ? Colors.hex(0x99CCFF) : XPMenu.selFill)
                Draw.frame(cb, XPMenu.selBorder)
                if it.displayImage == nil {
                    if it.radioItem {
                        let d = NSBezierPath(ovalIn: NSRect(x: cb.midX - 3, y: cb.midY - 3, width: 6, height: 6))
                        color.setFill()
                        d.fill()
                    } else {
                        let p = NSBezierPath()
                        p.move(to: NSPoint(x: cb.minX + 6, y: cb.midY))
                        p.line(to: NSPoint(x: cb.minX + 9, y: cb.midY + 3))
                        p.line(to: NSPoint(x: cb.minX + 14, y: cb.midY - 3.5))
                        color.setStroke()
                        p.lineWidth = 1.5
                        p.stroke()
                    }
                }
            }
            if let img = it.displayImage {
                Draw.image(img, at: NSPoint(x: r.minX + ((XPMenu.margin - img.size.width) / 2).rounded(.down),
                                            y: r.minY + ((r.height - img.size.height) / 2).rounded(.down)), enabled: it.enabled)
            }
            TextDraw.draw(it.caption, in: NSRect(x: r.minX + XPMenu.margin + 8, y: r.minY, width: r.width - XPMenu.margin - 30, height: r.height),
                          font: f, color: color, layout: .center)
            let sc = XPMenu.shortcutText(it.shortCut)
            if !sc.isEmpty {
                TextDraw.draw(sc, in: NSRect(x: r.minX, y: r.minY, width: r.width - 20, height: r.height), font: f, color: color,
                              align: .right, layout: .center, accel: false)
            }
            if !it.items.isEmpty {
                let c = NSPoint(x: r.maxX - 10, y: r.midY)
                let p = NSBezierPath()
                p.move(to: NSPoint(x: c.x - 2, y: c.y - 4)); p.line(to: NSPoint(x: c.x + 2, y: c.y)); p.line(to: NSPoint(x: c.x - 2, y: c.y + 4)); p.close()
                color.setFill()
                p.fill()
            }
        }
        Draw.frame(bounds, XPMenu.border)
    }

    func index(at p: NSPoint) -> Int { rowRects().firstIndex { $0.contains(p) } ?? -1 }

    override func mouseMoved(with event: NSEvent) {
        let i = index(at: convert(event.locationInWindow, from: nil))
        if i != hot {
            hot = i
            needsDisplay = true
            popup?.hotChanged()
        }
    }

    override func mouseUp(with event: NSEvent) {
        let i = index(at: convert(event.locationInWindow, from: nil))
        guard i >= 0 else { return }
        let it = items[i]
        if it.isLine || !it.enabled { return }
        if !it.items.isEmpty { popup?.openSubmenu(i); return }
        MenuPopupWindow.closeAll()
        DispatchQueue.main.async { it.click() }
    }

    override func mouseDown(with event: NSEvent) {}

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
}

final class MenuPopupWindow: NSPanel {
    static var stack: [MenuPopupWindow] = []
    static var monitor: Any?
    static weak var bar: TMenuBar?

    let view = MenuPopupView(frame: .zero)
    var subTimer: Timer?

    init(items: [TMenuItem]) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        hasShadow = true
        view.items = items
        view.popup = self
        contentView = view
    }

    override var canBecomeKey: Bool { true }

    static func show(items: [TMenuItem], at topLeft: NSPoint, parentWindow: NSWindow, owner: TMenuBar?) {
        let visible = items.filter(\.visible)
        guard !visible.isEmpty else { return }
        let w = MenuPopupWindow(items: visible)
        let size = MenuPopupView.size(for: visible)
        var origin = NSPoint(x: topLeft.x, y: topLeft.y - size.height)
        if let s = parentWindow.screen?.visibleFrame {
            if origin.y < s.minY { origin.y = s.minY }
            if origin.x + size.width > s.maxX { origin.x = s.maxX - size.width }
        }
        w.setFrame(NSRect(origin: origin, size: size), display: true)
        parentWindow.addChildWindow(w, ordered: .above)
        w.orderFront(nil)
        stack.append(w)
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { e in
                if e.type == .keyDown { return handleKey(e) ? nil : e }
                if let ew = e.window, stack.contains(where: { $0 === ew }) { return e }
                if let b = bar, e.window === b.window, b.bounds.contains(b.convert(e.locationInWindow, from: nil)) { return e }
                closeAll()
                return nil
            }
        }
    }

    static func handleKey(_ e: NSEvent) -> Bool {
        guard let top = stack.last else { return false }
        let v = top.view
        let selectable = v.items.indices.filter { !v.items[$0].isLine && v.items[$0].visible }
        switch e.keyCode {
        case 53: // esc
            top.closeMenu()
            stack.removeLast()
            if stack.isEmpty { closeAll() }
            return true
        case 125: // down
            if let n = selectable.first(where: { $0 > v.hot }) ?? selectable.first { v.hot = n; v.needsDisplay = true }
            return true
        case 126: // up
            if let n = selectable.last(where: { $0 < v.hot }) ?? selectable.last { v.hot = n; v.needsDisplay = true }
            return true
        case 124: // right
            if v.hot >= 0 && !v.items[v.hot].items.isEmpty { top.openSubmenu(v.hot) } else { bar?.moveSelection(1) }
            return true
        case 123: // left
            if stack.count > 1 { top.closeMenu(); stack.removeLast() } else { bar?.moveSelection(-1) }
            return true
        case 36, 76: // return
            if v.hot >= 0 {
                let it = v.items[v.hot]
                if !it.items.isEmpty { top.openSubmenu(v.hot) } else if it.enabled && !it.isLine { closeAll(); DispatchQueue.main.async { it.click() } }
            }
            return true
        default:
            return true
        }
    }

    func hotChanged() {
        subTimer?.invalidate()
        // close deeper menus
        if let idx = MenuPopupWindow.stack.firstIndex(where: { $0 === self }) {
            while MenuPopupWindow.stack.count > idx + 1 { MenuPopupWindow.stack.removeLast().closeMenu() }
        }
        let h = view.hot
        if h >= 0 && !view.items[h].items.isEmpty && view.items[h].enabled {
            subTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in self?.openSubmenu(h) }
        }
    }

    func openSubmenu(_ i: Int) {
        if let idx = MenuPopupWindow.stack.firstIndex(where: { $0 === self }) {
            while MenuPopupWindow.stack.count > idx + 1 { MenuPopupWindow.stack.removeLast().closeMenu() }
        }
        let r = view.rowRects()[i]
        let topLeft = convertToScreen(view.convert(NSRect(x: r.maxX - 2, y: r.minY - 2, width: 0, height: 0), to: nil)).origin
        guard let pw = parent else { return }
        MenuPopupWindow.show(items: view.items[i].items, at: NSPoint(x: topLeft.x, y: topLeft.y), parentWindow: pw, owner: nil)
    }

    func closeMenu() {
        subTimer?.invalidate()
        parent?.removeChildWindow(self)
        orderOut(nil)
    }

    static func closeAll() {
        for w in stack { w.closeMenu() }
        stack.removeAll()
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        bar?.menuClosed()
        bar = nil
    }
}

/// In-window Windows menu bar showing the items of a TMainMenu.
public final class TMenuBar: NSView {
    public weak var mainMenu: TMainMenu?
    var hot = -1
    var open = -1
    public static let height: CGFloat = 20
    public override var isFlipped: Bool { true }

    func itemRects() -> [(TMenuItem, NSRect)] {
        guard let m = mainMenu else { return [] }
        var x: CGFloat = 0
        let f = XPMenu.font
        return m.items.items.filter(\.visible).map { it in
            let w = (TextDraw.width(TextDraw.stripAccel(it.caption), f) + 14).rounded(.up)
            defer { x += w }
            return (it, NSRect(x: x, y: 0, width: w, height: TMenuBar.height - 1))
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        Draw.fill(bounds, Colors.ns(clBtnFace))
        let f = XPMenu.font
        for (i, (it, r)) in itemRects().enumerated() {
            if i == open {
                Draw.fill(r, Colors.hex(0xFCFCFC))
                Draw.frame(r, XPMenu.border)
            } else if i == hot && it.enabled {
                Draw.fill(r, XPMenu.selFill)
                Draw.frame(r, XPMenu.selBorder)
            }
            TextDraw.draw(it.caption, in: r, font: f, color: it.enabled ? .black : Colors.hex(0x6D6D6D), align: .center, layout: .center)
        }
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    public override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = itemRects().firstIndex { $0.1.contains(p) } ?? -1
        if i != hot {
            hot = i
            needsDisplay = true
            if open >= 0 && i >= 0 && i != open { openItem(i) }
        }
    }

    public override func mouseExited(with event: NSEvent) {
        hot = -1
        needsDisplay = true
    }

    public override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = itemRects().firstIndex(where: { $0.1.contains(p) }) else { return }
        if open == i { MenuPopupWindow.closeAll(); return }
        let it = itemRects()[i].0
        if it.items.isEmpty {
            if it.enabled { it.click() }
            return
        }
        openItem(i)
    }

    func openItem(_ i: Int) {
        let rects = itemRects()
        guard i >= 0 && i < rects.count, let w = window else { return }
        let (it, r) = rects[i]
        for s in MenuPopupWindow.stack { s.closeMenu() }
        MenuPopupWindow.stack.removeAll()
        open = i
        needsDisplay = true
        guard !it.items.isEmpty, it.enabled else { return }
        MenuPopupWindow.bar = self
        let topLeft = w.convertToScreen(convert(NSRect(x: r.minX, y: r.maxY, width: 0, height: 0), to: nil)).origin
        MenuPopupWindow.show(items: it.items, at: topLeft, parentWindow: w, owner: self)
        MenuPopupWindow.bar = self
    }

    func moveSelection(_ d: Int) {
        let n = itemRects().count
        guard n > 0 else { return }
        openItem((open + d + n) % n)
    }

    func menuClosed() {
        open = -1
        needsDisplay = true
    }
}
