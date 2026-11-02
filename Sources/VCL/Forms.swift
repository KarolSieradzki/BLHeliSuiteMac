import AppKit

// MARK: - Resources (forms and bitmaps extracted from BLHeliSuite.exe)

public enum Resources {
    public static var folder: URL? = {
        var c: [URL] = []
        if let env = ProcessInfo.processInfo.environment["BLHELI_RESOURCES"] { c.append(URL(fileURLWithPath: env)) }
        if let r = Bundle.main.resourceURL { c.append(r.appendingPathComponent("VCL")) }
        var d = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            c.append(d.appendingPathComponent("Resources/VCL"))
            d = d.deletingLastPathComponent()
        }
        return c.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Forms").path) }
    }()

    public static func data(_ path: String) -> [UInt8]? {
        guard let f = folder, let d = try? Data(contentsOf: f.appendingPathComponent(path)) else { return nil }
        return [UInt8](d)
    }

    /// String table (resourcestring) entries of the exe – Strings.txt "id<TAB>text" with \\ \r \n \t escapes.
    public static let strings: [Int: String] = {
        guard let b = data("Strings.txt"), let t = String(bytes: b, encoding: .utf8) else { return [:] }
        var r: [Int: String] = [:]
        for line in t.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tab = line.firstIndex(of: "\t"), let id = Int(line[..<tab]) else { continue }
            var out = ""
            var esc = false
            for ch in line[line.index(after: tab)...] {
                if esc {
                    switch ch {
                    case "r": out.append("\r")
                    case "n": out.append("\n")
                    case "t": out.append("\t")
                    default: out.append(ch)
                    }
                    esc = false
                } else if ch == "\\" {
                    esc = true
                } else {
                    out.append(ch)
                }
            }
            r[id] = out
        }
        return r
    }()

    /// LoadResString.
    public static func string(_ id: Int) -> String { strings[id] ?? "" }

    public static func form(_ name: String) -> DFMObject? {
        guard let b = data("Forms/\(name.uppercased()).dfm") else { return nil }
        return try? DFMReader.parse(b)
    }

    private static var glyphCache: [String: TGlyph] = [:]

    /// RT_BITMAP resource (BBOK, BBCANCEL …) used as a 2-glyph button image.
    public static func bitmapGlyph(_ name: String) -> TGlyph? {
        if let g = glyphCache[name] { return g }
        guard let b = data("Bitmaps/\(name).bmp"), var bmp = DIB.decode(b, at: 0) else { return nil }
        if !bmp.hasAlpha { bmp = bmp.keyedTransparent() }
        let n = bmp.width >= 2 * bmp.height ? 2 : 1
        let gw = bmp.width / n
        var g = TGlyph(image: bmp.crop(0, 0, gw, bmp.height).image)
        if n == 2 { g.disabled = bmp.crop(gw, 0, gw, bmp.height).image } else { g.disabled = bmp.crop(0, 0, gw, bmp.height).disabledImage }
        glyphCache[name] = g
        return g
    }

    public static func bitmapImage(_ name: String) -> NSImage? {
        guard let b = data("Bitmaps/\(name).bmp"), let bmp = DIB.decode(b, at: 0) else { return nil }
        return bmp.image
    }
}

// MARK: - Form container (window content: menu bar + client area)

public final class FormContainerView: NSView {
    weak var form: TForm?
    var menuBar: TMenuBar?
    public override var isFlipped: Bool { true }

    func layoutChildren() {
        guard let f = form else { return }
        let mh = menuBar == nil ? 0 : TMenuBar.height
        menuBar?.frame = NSRect(x: 0, y: 0, width: bounds.width, height: mh)
        let r = NSRect(x: 0, y: mh, width: bounds.width, height: bounds.height - mh)
        if f.frame != r {
            let sz = f.frame.size != r.size
            f.frame = r
            if sz { f.resized() }
        }
    }

    public override func resizeSubviews(withOldSize oldSize: NSSize) { layoutChildren() }

    public override func draw(_ dirtyRect: NSRect) {
        Draw.fill(bounds, Colors.ns(clBtnFace))
        if menuBar != nil { Draw.hline(0, bounds.width, TMenuBar.height - 1, Colors.hex(0xF0F0F0)) }
    }

    // DragAcceptFiles / WM_DROPFILES
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { form?.onDropFiles == nil ? [] : .copy }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let h = form?.onDropFiles,
              let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                               options: [.urlReadingFileURLsOnly: true]) as? [URL] else { return false }
        DispatchQueue.main.async { h(urls) }   // after the drag session: the handler may show modal dialogs
        return true
    }
}

final class VCLWindow: NSWindow {
    weak var form: TForm?

    override func keyDown(with event: NSEvent) {
        if let f = form {
            if event.keyCode == 53, f.pressCancelButton() { return }
            if event.keyCode == 36 || event.keyCode == 76, f.pressDefaultButton() { return }
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if let f = form, f.pressCancelButton() { return }
        super.cancelOperation(sender)
    }
}

final class VCLPanelWindow: NSPanel {
    weak var form: TForm?
    override func cancelOperation(_ sender: Any?) {
        if let f = form, f.pressCancelButton() { return }
        super.cancelOperation(sender)
    }
}

public enum TCloseAction: Int { case caNone, caHide, caFree, caMinimize }

public final class TCloseArgs: NSObject {
    public var action: TCloseAction
    public init(_ a: TCloseAction) { action = a }
}

// MARK: - TForm

open class TForm: TControl, NSWindowDelegate {
    public var formWindow: NSWindow!
    public let container = FormContainerView(frame: .zero)
    public weak var mainMenu: TMainMenu? { didSet { setupMenuBar() } }
    public var position = "poDesigned"
    public var borderStyle = "bsSizeable"
    public var borderIcons: Set<String> = ["biSystemMenu", "biMinimize", "biMaximize"]
    public var formStyleStayOnTop = false
    public var designLeft = 0, designTop = 0
    public var designClientWidth = 0, designClientHeight = 0
    public var minWidth = 0, minHeight = 0
    public var keyPreview = false
    public var isModal = false
    public var modalResult: TModalResult = mrNone {
        didSet {
            if isModal && modalResult != mrNone {
                if closeQuery() { NSApp.stopModal() } else { modalResult = mrNone }
            }
        }
    }
    public var onCreate: TNotifyEvent?
    public var onShow: TNotifyEvent?
    public var onHide: TNotifyEvent?
    public var onActivate: TNotifyEvent?
    public var onDestroy: TNotifyEvent?
    public var onClose: ((TObject, TCloseArgs) -> Void)?
    public var onCloseQuery: ((TObject, TBoolArgs) -> Void)?
    /// DragAcceptFiles(Handle, True) + WM_DROPFILES: files dropped on the window.
    public var onDropFiles: (([URL]) -> Void)? {
        didSet {
            if onDropFiles == nil { container.unregisterDraggedTypes() } else { container.registerForDraggedTypes([.fileURL]) }
        }
    }
    public var components: [String: AnyObject] = [:]
    public var actionLists: [TActionList] = []
    public var appEvents: [TDummyComponent] = []
    public weak var ownerForm: TForm?
    var shownOnce = false

    public required init(frame: NSRect) {
        super.init(frame: frame)
        color = clBtnFace
        parentFont = false
        container.form = self
        container.addSubview(self)
    }

    public required init?(coder: NSCoder) { fatalError() }

    /// Creates the form from its DFM resource (e.g. "TFRMBLHELISUITEMAIN").
    public init(resource: String, owner: TForm? = nil) {
        super.init(frame: .zero)
        color = clBtnFace
        parentFont = false
        container.form = self
        container.addSubview(self)
        ownerForm = owner
        if let dfm = Resources.form(resource) {
            let l = DFMLoader(root: self)
            l.loadRoot(dfm)
        }
        createWindow()
        Application.shared.forms.append(WeakForm(self))
        onCreate?(self)
    }

    open override var isFlipped: Bool { true }

    public var formCaption: String {
        get { caption }
        set { caption = newValue }
    }

    open override func captionChanged() { formWindow?.title = TextDraw.stripAccel(caption) }

    open override var clientWidth: Int {
        get { Int(bounds.width) }
        set { setClientSize(newValue, clientHeight) }
    }

    open override var clientHeight: Int {
        get { Int(bounds.height) }
        set { setClientSize(clientWidth, newValue) }
    }

    public func setClientSize(_ w: Int, _ h: Int) {
        let mh = mainMenu == nil ? 0 : TMenuBar.height
        if let win = formWindow {
            win.setContentSize(NSSize(width: CGFloat(w), height: CGFloat(h) + mh))
            container.layoutChildren()
        } else {
            frame.size = NSSize(width: w, height: h)
        }
    }

    func setupMenuBar() {
        container.menuBar?.removeFromSuperview()
        container.menuBar = nil
        if let m = mainMenu {
            let b = TMenuBar(frame: .zero)
            b.mainMenu = m
            container.addSubview(b)
            container.menuBar = b
        }
        if formWindow != nil { container.layoutChildren() }
    }

    public func refreshMenuBar() { container.menuBar?.needsDisplay = true }

    func createWindow() {
        let mh = mainMenu == nil ? 0 : TMenuBar.height
        let cw = designClientWidth > 0 ? CGFloat(designClientWidth) : frame.width
        let ch = designClientHeight > 0 ? CGFloat(designClientHeight) : frame.height
        frame = NSRect(x: 0, y: mh, width: cw, height: ch)
        let size = NSSize(width: cw, height: ch + mh)
        var style: NSWindow.StyleMask = [.titled]
        switch borderStyle {
        case "bsNone": style = [.borderless]
        case "bsDialog", "bsToolWindow": style.insert(.closable)
        case "bsSingle":
            if borderIcons.contains("biSystemMenu") { style.insert(.closable) }
            if borderIcons.contains("biMinimize") { style.insert(.miniaturizable) }
        default:
            if borderIcons.contains("biSystemMenu") { style.insert(.closable) }
            if borderIcons.contains("biMinimize") { style.insert(.miniaturizable) }
            style.insert(.resizable)
        }
        let w: NSWindow
        if borderStyle == "bsToolWindow" || borderStyle == "bsSizeToolWin" {
            let p = VCLPanelWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style.union(.utilityWindow), backing: .buffered, defer: false)
            p.form = self
            p.becomesKeyOnlyIfNeeded = false
            p.isFloatingPanel = false
            p.hidesOnDeactivate = false
            w = p
        } else {
            let vw = VCLWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
            vw.form = self
            w = vw
        }
        w.isReleasedWhenClosed = false
        w.contentView = container
        w.title = TextDraw.stripAccel(caption)
        w.delegate = self
        w.backgroundColor = Theme.face
        if formStyleStayOnTop { w.level = .floating }
        if minWidth > 0 || minHeight > 0 { w.contentMinSize = NSSize(width: CGFloat(minWidth), height: CGFloat(minHeight) + mh) }
        formWindow = w
        container.frame = NSRect(origin: .zero, size: size)
        container.layoutChildren()
        captureAnchors()
    }

    func placeWindow() {
        guard let w = formWindow else { return }
        switch position {
        case "poScreenCenter", "poDesktopCenter":
            w.center()
        case "poMainFormCenter", "poOwnerFormCenter":
            if let m = (position == "poOwnerFormCenter" ? ownerForm : nil) ?? Application.shared.mainForm, m !== self, let mw = m.formWindow, mw.isVisible {
                let mf = mw.frame
                w.setFrameOrigin(NSPoint(x: mf.midX - w.frame.width / 2, y: mf.midY - w.frame.height / 2))
            } else { w.center() }
        default:
            if let s = NSScreen.main {
                let vf = s.visibleFrame
                let x = vf.minX + CGFloat(designLeft)
                let y = vf.maxY - CGFloat(designTop) - w.frame.height
                w.setFrameOrigin(NSPoint(x: x, y: max(vf.minY, y)))
            }
        }
    }

    // MARK: show / close

    open func show() {
        if !shownOnce { placeWindow(); shownOnce = true }
        let wasVisible = formWindow.isVisible
        formWindow.makeKeyAndOrderFront(nil)
        if !wasVisible { onShow?(self) }
    }

    public var visibleForm: Bool { formWindow?.isVisible ?? false }

    open func hide() {
        formWindow.orderOut(nil)
        onHide?(self)
    }

    @discardableResult
    open func showModal() -> TModalResult {
        Application.shared.cancelHint()
        modalResult = mrNone
        if !shownOnce { placeWindow(); shownOnce = true }
        isModal = true
        onShow?(self)
        formWindow.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: formWindow)
        isModal = false
        formWindow.orderOut(nil)
        let args = TCloseArgs(.caHide)
        onClose?(self, args)
        return modalResult
    }

    func closeQuery() -> Bool {
        let a = TBoolArgs(true)
        onCloseQuery?(self, a)
        return a.value
    }

    open func close() {
        if isModal { if modalResult == mrNone { modalResult = mrCancel }; return }
        guard closeQuery() else { return }
        let args = TCloseArgs(.caHide)
        onClose?(self, args)
        if args.action != .caNone { formWindow.orderOut(nil) }
        if self === Application.shared.mainForm { Application.shared.terminate() }
    }

    public func release() {
        formWindow?.orderOut(nil)
        Application.shared.forms.removeAll { $0.form === self || $0.form == nil }
        onDestroy?(self)
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        close()
        return false
    }

    public func windowDidBecomeKey(_ notification: Notification) { onActivate?(self) }

    public func windowDidResize(_ notification: Notification) { container.layoutChildren() }

    public func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        guard let tf = client as? VCLTextField, let owner = tf.owner else { return nil }
        let ed = Application.shared.fieldEditor
        ed.vclOwner = owner
        ed.isFieldEditor = true
        return ed
    }

    // MARK: default / cancel buttons

    func allControls(_ v: NSView) -> [TControl] {
        var out: [TControl] = []
        for s in v.subviews {
            if let c = s as? TControl { out.append(c) }
            out += allControls(s)
        }
        return out
    }

    func pressDefaultButton() -> Bool {
        guard let b = allControls(self).compactMap({ $0 as? TButton }).first(where: { $0.isDefault && !$0.isHidden && $0.effectiveEnabled }) else { return false }
        b.click()
        return true
    }

    func pressCancelButton() -> Bool {
        if let b = allControls(self).compactMap({ $0 as? TButton }).first(where: { $0.isCancel && !$0.isHidden && $0.effectiveEnabled }) {
            b.click()
            return true
        }
        if isModal { modalResult = mrCancel; return true }
        return false
    }

    public func component<T>(_ name: String) -> T? { components[name] as? T }

    /// Clicks the visible button whose caption (without '&') matches – used by scripted tests.
    @discardableResult
    public func pressButton(caption: String) -> Bool {
        let want = caption.lowercased()
        if let b = allControls(self).compactMap({ $0 as? TButton })
            .first(where: { $0.caption.replacingOccurrences(of: "&", with: "").lowercased() == want && !$0.isHidden && $0.effectiveEnabled }) {
            b.click()
            return true
        }
        return false
    }

    /// Window snapshot (client area including the menu bar) as PNG data.
    public func screenshotPNG() -> Data? {
        let v = container
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return nil }
        v.cacheDisplay(in: v.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "Left": designLeft = value.intValue ?? 0
        case "Top": designTop = value.intValue ?? 0
        case "Width", "Height": break
        case "ClientWidth": designClientWidth = value.intValue ?? 0; frame.size.width = CGFloat(designClientWidth)
        case "ClientHeight": designClientHeight = value.intValue ?? 0; frame.size.height = CGFloat(designClientHeight)
        case "Position": position = value.stringValue ?? "poDesigned"
        case "BorderStyle": borderStyle = value.stringValue ?? "bsSizeable"
        case "BorderIcons": if case .set(let s) = value { borderIcons = Set(s) }
        case "FormStyle": formStyleStayOnTop = value.stringValue == "fsStayOnTop"
        case "Menu": loader.fixup(value) { [weak self] (m: TMainMenu) in self?.mainMenu = m }
        case "KeyPreview": keyPreview = value.boolValue ?? false
        case "Constraints.MinWidth": minWidth = value.intValue ?? 0
        case "Constraints.MinHeight": minHeight = value.intValue ?? 0
        case "OnCreate": loader.event(value) { [weak self] h in self?.onCreate = h }
        case "OnShow": loader.event(value) { [weak self] h in self?.onShow = h }
        case "OnHide": loader.event(value) { [weak self] h in self?.onHide = h }
        case "OnActivate": loader.event(value) { [weak self] h in self?.onActivate = h }
        case "OnDestroy": loader.event(value) { [weak self] h in self?.onDestroy = h }
        case "OnClose": loader.closeEvent(value) { [weak self] h in self?.onClose = h }
        case "OnCloseQuery": loader.closeQueryEvent(value) { [weak self] h in self?.onCloseQuery = h }
        case "OldCreateOrder", "PixelsPerInch", "TextHeight", "Scaled", "ScreenSnap", "WindowState", "Icon.Data",
             "HorzScrollBar.Visible", "VertScrollBar.Visible", "AutoScroll", "DefaultMonitor", "ActiveControl",
             "SnapBuffer", "AlphaBlend", "AlphaBlendValue", "GlassFrame.Enabled", "Visible", "DesignSize", "PrintScale":
            break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }

    open override func draw(_ dirtyRect: NSRect) { paintBackground() }
}

final class WeakForm { weak var form: TForm?; init(_ f: TForm) { form = f } }

// MARK: - Application

public final class Application: NSObject {
    public static let shared = Application()
    public weak var mainForm: TForm?
    var forms: [WeakForm] = []
    public var title = "BLHeliSuite"
    public var onIdle: [TNotifyEvent] = []
    let fieldEditor = VCLFieldEditor(frame: .zero)
    private var idleObserver: CFRunLoopObserver?
    private var lastIdle = Date.distantPast
    public var hintHidePause: TimeInterval = 10

    /// Application.ProcessMessages – handles pending events and repaints.
    public func processMessages() {
        let mode = RunLoop.current.currentMode ?? .default
        var n = 0
        while n < 200, let e = NSApp.nextEvent(matching: .any, until: Date.distantPast, inMode: mode, dequeue: true) {
            NSApp.sendEvent(e)
            n += 1
        }
        for f in forms { f.form?.formWindow?.displayIfNeeded() }
        for w in NSApp.windows where w.isVisible { w.displayIfNeeded() }
    }

    /// Sleep(ms) that keeps the UI alive.
    public func sleep(_ ms: Int) {
        let end = Date().addingTimeInterval(Double(ms) / 1000)
        while Date() < end {
            processMessages()
            Thread.sleep(forTimeInterval: min(0.005, max(0, end.timeIntervalSinceNow)))
        }
    }

    public func startIdleProcessing() {
        let obs = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { [weak self] _, _ in
            self?.idle()
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), obs, .commonModes)
        idleObserver = obs
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.idle() }
        RunLoop.main.add(t, forMode: .common)
    }

    var inIdle = false

    func idle() {
        guard !inIdle, Date().timeIntervalSince(lastIdle) > 0.1 else { return }
        inIdle = true
        lastIdle = Date()
        for f in forms {
            guard let form = f.form, form.formWindow?.isVisible == true else { continue }
            for l in form.actionLists { l.updateActions() }
            for e in form.appEvents { e.onIdle?(e) }
            // TJvAppEvents of the frames on the form (Motors page, alternate speed test …)
            func frames(_ v: NSView) {
                for s in v.subviews {
                    if let fr = s as? TFrame { for e in fr.appEvents { e.onIdle?(e) } }
                    frames(s)
                }
            }
            if let c = form.formWindow?.contentView { frames(c) }
        }
        for h in onIdle { h(self) }
        inIdle = false
    }

    public func terminate() { NSApp.terminate(nil) }

    // MARK: hints

    private var hintTimer: Timer?
    private var hideTimer: Timer?
    private weak var hintControl: TControl?
    private var hintWindow: BalloonHint?

    func effectiveShowHint(_ c: TControl) -> Bool {
        var v: NSView? = c
        while let x = v as? TControl {
            if !x.parentShowHint { return x.showHint }
            v = x.superview
        }
        return true
    }

    /// Forms.GetHint: the hint of the control, else of the nearest parent with a hint.
    func getHint(_ c: TControl) -> String {
        var v: NSView? = c
        while let x = v {
            if let t = x as? TControl, !t.hint.isEmpty { return t.hint }
            v = x.superview
        }
        return ""
    }

    func hintMouseEntered(_ c: TControl) {
        guard !getHint(c).isEmpty, effectiveShowHint(c) else { return }
        hintControl = c
        hintTimer?.invalidate()
        hintTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in self?.showHint() }
    }

    func hintMouseMoved(_ c: TControl) {
        if hintControl !== c { hintMouseEntered(c) }
    }

    func hintMouseExited(_ c: TControl) {
        if hintControl === c { cancelHint() }
    }

    public func cancelHint() {
        hintTimer?.invalidate()
        hideTimer?.invalidate()
        hintWindow?.orderOut(nil)
        hintControl = nil
    }

    private func showHint() {
        guard let c = hintControl, let w = c.window, w.isVisible, !c.isHiddenOrHasHiddenAncestor else { return }
        let h = getHint(c)
        let text = h.components(separatedBy: "|").first ?? h
        guard !text.isEmpty else { return }
        if hintWindow == nil { hintWindow = BalloonHint() }
        let mouse = NSEvent.mouseLocation
        hintWindow?.show(text: text, at: mouse, parent: w)
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: hintHidePause, repeats: false) { [weak self] _ in self?.hintWindow?.orderOut(nil) }
    }

    /// Hint for a control shown immediately (e.g. after an operation).
    public func activateHint(_ c: TControl) {
        hintControl = c
        showHint()
    }
}

/// Balloon tooltip (TJvBalloonHint with UseBalloonAsApplicationHint).
final class BalloonHint: NSPanel {
    final class V: NSView {
        var text = ""
        var stemUp = true
        var stemX: CGFloat = 16
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            let stem: CGFloat = 12
            let body = stemUp ? NSRect(x: 0.5, y: stem + 0.5, width: bounds.width - 1, height: bounds.height - stem - 1)
                : NSRect(x: 0.5, y: 0.5, width: bounds.width - 1, height: bounds.height - stem - 1)
            let p = NSBezierPath(roundedRect: body, xRadius: 6, yRadius: 6)
            let s = NSBezierPath()
            if stemUp {
                s.move(to: NSPoint(x: stemX, y: body.minY + 1)); s.line(to: NSPoint(x: stemX, y: 0.5)); s.line(to: NSPoint(x: stemX + stem, y: body.minY + 1))
            } else {
                s.move(to: NSPoint(x: stemX, y: body.maxY - 1)); s.line(to: NSPoint(x: stemX, y: bounds.height - 0.5)); s.line(to: NSPoint(x: stemX + stem, y: body.maxY - 1))
            }
            p.append(s)
            NSColor.white.setFill()
            p.fill()
            Colors.hex(0x767676).setStroke()
            p.lineWidth = 1
            p.stroke()
            NSColor.white.setFill()
            NSRect(x: stemX + 1, y: stemUp ? body.minY - 0.5 : body.maxY - 1.5, width: stem - 2, height: 2).fill()
            TextDraw.draw(text, in: body.insetBy(dx: 8, dy: 6), font: TFont.messageFont, color: Colors.hex(0x575757), accel: false)
        }
    }

    let v = V(frame: .zero)

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = true
        contentView = v
    }

    func show(text: String, at mouse: NSPoint, parent: NSWindow) {
        let f = TFont.messageFont
        let lines = text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
        let w = (lines.map { TextDraw.width($0, f) }.max() ?? 0) + 18
        let h = TextDraw.lineHeight(f) * CGFloat(lines.count) + 14 + 12
        v.text = text
        var origin = NSPoint(x: mouse.x - 16, y: mouse.y - 20 - h)
        v.stemUp = true
        if let s = parent.screen?.visibleFrame {
            if origin.y < s.minY { origin.y = mouse.y + 8; v.stemUp = false }
            if origin.x + w > s.maxX { origin.x = s.maxX - w }
        }
        v.stemX = max(8, min(w - 22, mouse.x - origin.x - 1))
        setFrame(NSRect(origin: origin, size: NSSize(width: w.rounded(.up), height: h.rounded(.up))), display: true)
        v.needsDisplay = true
        orderFront(nil)
    }
}

// MARK: - Screen cursor

public enum Screen {
    public static var busy = false {
        didSet { if busy { NSCursor.operationNotAllowed.set() } else { NSCursor.arrow.set() } }
    }
}
