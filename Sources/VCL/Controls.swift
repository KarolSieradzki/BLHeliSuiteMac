import AppKit

public typealias TObject = NSObject
public typealias TNotifyEvent = (TObject) -> Void
public typealias TMouseEvent = (TObject, TMouseButton, TShiftState, Int, Int) -> Void
public typealias TMouseMoveEvent = (TObject, TShiftState, Int, Int) -> Void
public typealias TKeyPressEvent = (TObject, inout Character) -> Void
public typealias TKeyEvent = (TObject, inout UInt16, TShiftState) -> Void

/// Common part of visual and non-visual components.
public protocol VCLComponent: AnyObject {
    var name: String { get set }
    var tag: Int { get set }
    /// Applies one DFM property; returns false if unknown.
    func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool
    /// Called after all properties and children of the component were read.
    func loaded()
}

/// Non-visual component (TAction, TImageList, TTimer, menus …).
open class TComponent: NSObject, VCLComponent {
    public var name = ""
    public var tag = 0
    public weak var owner: AnyObject?

    public override init() { super.init() }

    open func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "Tag": tag = value.intValue ?? 0
        case "Left", "Top": break
        default: return false
        }
        return true
    }

    open func loaded() {}
}

/// Event argument objects used to forward multi-parameter events to @objc handlers.
public final class TMouseArgs: NSObject {
    public let button: TMouseButton
    public let shift: TShiftState
    public let x: Int, y: Int
    public init(_ b: TMouseButton, _ s: TShiftState, _ x: Int, _ y: Int) { button = b; shift = s; self.x = x; self.y = y }
}

public final class TKeyArgs: NSObject {
    public var key: Character
    public var keyCode: UInt16
    public let shift: TShiftState
    public init(key: Character, keyCode: UInt16 = 0, shift: TShiftState = []) { self.key = key; self.keyCode = keyCode; self.shift = shift }
}

public final class TBoolArgs: NSObject {
    public var value: Bool
    public init(_ v: Bool) { value = v }
}

/// Base of all visual VCL controls.
open class TControl: NSView, VCLComponent {
    public var name = ""
    private var vclTag = 0
    open override var tag: Int {
        get { vclTag }
        set { vclTag = newValue }
    }
    /// Root (form or frame) this control was loaded into.
    public weak var root: TControl?

    open override var isFlipped: Bool { true }

    public required override init(frame: NSRect) {
        super.init(frame: frame)
        font.onChange = { [weak self] in self?.fontChanged() }
        wantsLayer = false
    }

    public required init?(coder: NSCoder) { fatalError() }

    // MARK: geometry

    public var left: Int {
        get { Int(frame.minX.rounded()) }
        set { setBounds(newValue, top, width, height) }
    }
    public var top: Int {
        get { Int(frame.minY.rounded()) }
        set { setBounds(left, newValue, width, height) }
    }
    public var width: Int {
        get { Int(frame.width.rounded()) }
        set { setBounds(left, top, newValue, height) }
    }
    public var height: Int {
        get { Int(frame.height.rounded()) }
        set { setBounds(left, top, width, newValue) }
    }
    open var clientWidth: Int {
        get { width }
        set { width = newValue }
    }
    open var clientHeight: Int {
        get { height }
        set { height = newValue }
    }

    public var boundsRect: NSRect { frame }

    open func setBounds(_ l: Int, _ t: Int, _ w: Int, _ h: Int) {
        let r = NSRect(x: l, y: t, width: max(0, w), height: max(0, h))
        if r == frame { return }
        let sizeChanged = r.size != frame.size
        frame = r
        if sizeChanged { resized() }
        if align != .alNone { parentControl?.realign() }
    }

    /// Called after the size changed (OnResize).
    open func resized() {
        realign()
        needsDisplay = true
        onResize?(self)
    }

    public var align: TAlign = .alNone { didSet { parentControl?.realign() } }
    public var anchors: TAnchors = .default
    public var alignWithMargins = false
    public var margins = NSEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
    /// Distances to the right/bottom edge at load time (for akRight/akBottom anchors).
    var anchorRight: CGFloat = 0, anchorBottom: CGFloat = 0
    var anchorsInitialized = false

    public var parentControl: TControl? { superview as? TControl }
    public var controls: [TControl] { subviews.compactMap { $0 as? TControl } }
    public var controlCount: Int { controls.count }

    public func insertControl(_ c: TControl) {
        addSubview(c)
        c.inheritFromParent()
    }

    /// Client area used for aligned children.
    open var alignRect: NSRect { bounds }

    open func realign() {
        var r = alignRect
        let kids = controls.filter { !$0.isHidden && $0.align != .alNone && $0.align != .alCustom }
        if kids.isEmpty { return }
        func m(_ c: TControl) -> NSEdgeInsets { c.alignWithMargins ? c.margins : NSEdgeInsets() }
        for c in kids.filter({ $0.align == .alTop }).sorted(by: { $0.frame.minY < $1.frame.minY }) {
            let e = m(c)
            c.frame = NSRect(x: r.minX + e.left, y: r.minY + e.top, width: r.width - e.left - e.right, height: c.frame.height)
            c.resized()
            r.origin.y += c.frame.height + e.top + e.bottom
            r.size.height -= c.frame.height + e.top + e.bottom
        }
        for c in kids.filter({ $0.align == .alBottom }).sorted(by: { $0.frame.maxY > $1.frame.maxY }) {
            let e = m(c)
            c.frame = NSRect(x: r.minX + e.left, y: r.maxY - c.frame.height - e.bottom, width: r.width - e.left - e.right, height: c.frame.height)
            c.resized()
            r.size.height -= c.frame.height + e.top + e.bottom
        }
        for c in kids.filter({ $0.align == .alLeft }).sorted(by: { $0.frame.minX < $1.frame.minX }) {
            let e = m(c)
            c.frame = NSRect(x: r.minX + e.left, y: r.minY + e.top, width: c.frame.width, height: r.height - e.top - e.bottom)
            c.resized()
            r.origin.x += c.frame.width + e.left + e.right
            r.size.width -= c.frame.width + e.left + e.right
        }
        for c in kids.filter({ $0.align == .alRight }).sorted(by: { $0.frame.maxX > $1.frame.maxX }) {
            let e = m(c)
            c.frame = NSRect(x: r.maxX - c.frame.width - e.right, y: r.minY + e.top, width: c.frame.width, height: r.height - e.top - e.bottom)
            c.resized()
            r.size.width -= c.frame.width + e.left + e.right
        }
        for c in kids.filter({ $0.align == .alClient }) {
            let e = m(c)
            c.frame = NSRect(x: r.minX + e.left, y: r.minY + e.top, width: max(0, r.width - e.left - e.right), height: max(0, r.height - e.top - e.bottom))
            c.resized()
        }
    }

    open override func resizeSubviews(withOldSize oldSize: NSSize) {
        for c in controls where c.align == .alNone {
            if !c.anchorsInitialized { continue }
            var f = c.frame
            let a = c.anchors
            if a.contains(.akRight) {
                let newRight = bounds.width - c.anchorRight
                if a.contains(.akLeft) { f.size.width = max(0, newRight - f.minX) } else { f.origin.x = newRight - f.width }
            }
            if a.contains(.akBottom) {
                let newBottom = bounds.height - c.anchorBottom
                if a.contains(.akTop) { f.size.height = max(0, newBottom - f.minY) } else { f.origin.y = newBottom - f.height }
            }
            if f != c.frame {
                let sz = f.size != c.frame.size
                c.frame = f
                if sz { c.resized() }
            }
        }
    }

    func captureAnchors() {
        guard let p = parentControl else { return }
        anchorRight = p.bounds.width - frame.maxX
        anchorBottom = p.bounds.height - frame.maxY
        anchorsInitialized = true
        for c in controls { c.captureAnchors() }
    }

    // MARK: appearance

    public var caption: String = "" {
        didSet { if caption != oldValue { captionChanged() } }
    }
    public var text: String {
        get { caption }
        set { caption = newValue }
    }

    open func captionChanged() { needsDisplay = true }

    public var color: TColor = clBtnFace {
        didSet { if color != oldValue { colorChanged() } }
    }
    public var parentColor = true
    public let font = TFont()
    public var parentFont = true
    public var transparent = false

    open func colorChanged() {
        needsDisplay = true
        for c in controls where c.parentColor { c.color = color }
    }

    open func fontChanged() {
        needsDisplay = true
        for c in controls where c.parentFont { c.font.assign(font) }
    }

    /// ParentFont / ParentColor resolution after the control got its parent.
    func inheritFromParent() {
        guard let p = parentControl else { return }
        if parentFont { font.assign(p.font) }
        if parentColor { color = p.color }
        if parentShowHint { showHint = p.showHint }
    }

    public var visible: Bool {
        get { !isHidden }
        set {
            if isHidden == !newValue { return }
            isHidden = !newValue
            if align != .alNone { parentControl?.realign() }
            visibleChanged()
        }
    }

    open func visibleChanged() {}

    public var enabled = true {
        didSet { if enabled != oldValue { enabledChanged() } }
    }

    open func enabledChanged() {
        needsDisplay = true
        if propagateEnable { for c in controls { c.enabled = enabled } }
    }

    /// TJvGroupBox.PropagateEnable.
    public var propagateEnable = false

    /// True if this control and all its parents are enabled (input allowed).
    public var effectiveEnabled: Bool {
        var v: NSView? = self
        while let c = v as? TControl {
            if !c.enabled { return false }
            v = c.superview
        }
        return true
    }

    public var hint = ""
    public var showHint = false
    public var parentShowHint = true
    public var cursorKind: NSCursor?

    public var popupMenu: TPopupMenu?

    // MARK: action link

    public weak var action: TAction? {
        didSet {
            oldValue?.removeClient(self)
            action?.addClient(self)
            if let a = action { actionChanged(a) }
        }
    }

    /// Update from the linked action (caption, enabled, visible, hint, checked, image).
    open func actionChanged(_ a: TAction) {
        caption = a.caption
        enabled = a.enabled
        visible = a.visible
        if !a.hint.isEmpty || hint.isEmpty { hint = a.hint }
    }

    // MARK: events

    public var onClick: TNotifyEvent?
    public var onDblClick: TNotifyEvent?
    public var onMouseDown: TMouseEvent?
    public var onMouseUp: TMouseEvent?
    public var onMouseMove: TMouseMoveEvent?
    public var onMouseEnter: TNotifyEvent?
    public var onMouseLeave: TNotifyEvent?
    public var onResize: TNotifyEvent?
    public var onEnter: TNotifyEvent?
    public var onExit: TNotifyEvent?
    public var onKeyPress: TKeyPressEvent?
    public var onKeyDown: TKeyEvent?
    public var onKeyUp: TKeyEvent?
    public var onChange: TNotifyEvent?
    public var onContextPopup: ((TObject, NSPoint, inout Bool) -> Void)?

    /// Default click: execute the linked action or OnClick.
    open func click() {
        if let a = action, onClick == nil {
            a.execute()
        } else {
            onClick?(self)
        }
    }

    // MARK: mouse handling

    public var mouseInside = false
    public var mouseIsDown = false
    private var tracking: NSTrackingArea?

    open override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    open override func mouseEntered(with event: NSEvent) {
        mouseInside = true
        if wantsHover { needsDisplay = true }
        onMouseEnter?(self)
        Application.shared.hintMouseEntered(self)
    }

    open override func mouseExited(with event: NSEvent) {
        mouseInside = false
        if wantsHover { needsDisplay = true }
        onMouseLeave?(self)
        Application.shared.hintMouseExited(self)
    }

    /// Repaint on hover (themed buttons etc.).
    open var wantsHover: Bool { false }

    func localPoint(_ e: NSEvent) -> (Int, Int) {
        let p = convert(e.locationInWindow, from: nil)
        return (Int(p.x.rounded(.down)), Int(p.y.rounded(.down)))
    }

    open override func mouseMoved(with event: NSEvent) {
        let (x, y) = localPoint(event)
        onMouseMove?(self, TShiftState(event.modifierFlags), x, y)
        Application.shared.hintMouseMoved(self)
    }

    open override func mouseDragged(with event: NSEvent) {
        let (x, y) = localPoint(event)
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside != mouseInside { mouseInside = inside; if wantsHover { needsDisplay = true } }
        onMouseMove?(self, TShiftState(event.modifierFlags).union(.ssLeft), x, y)
    }

    open override func mouseDown(with event: NSEvent) {
        Application.shared.cancelHint()
        guard effectiveEnabled else { return }
        mouseIsDown = true
        if wantsHover { needsDisplay = true }
        let (x, y) = localPoint(event)
        var s = TShiftState(event.modifierFlags).union(.ssLeft)
        if event.clickCount > 1 { s.insert(.ssDouble) }
        onMouseDown?(self, .mbLeft, s, x, y)
        if event.clickCount == 2 { onDblClick?(self) }
        if acceptsFirstResponder { window?.makeFirstResponder(self) }
    }

    open override func mouseUp(with event: NSEvent) {
        guard mouseIsDown else { return }
        mouseIsDown = false
        if wantsHover { needsDisplay = true }
        let (x, y) = localPoint(event)
        onMouseUp?(self, .mbLeft, TShiftState(event.modifierFlags), x, y)
        if clickOnMouseUp && bounds.contains(NSPoint(x: x, y: y)) && effectiveEnabled { click() }
    }

    /// Generates a click on mouse up inside (buttons, labels with OnClick, images …).
    open var clickOnMouseUp: Bool { onClick != nil }

    open override func rightMouseDown(with event: NSEvent) {
        Application.shared.cancelHint()
        let (x, y) = localPoint(event)
        if effectiveEnabled { onMouseDown?(self, .mbRight, TShiftState(event.modifierFlags).union(.ssRight), x, y) }
        var handled = false
        onContextPopup?(self, NSPoint(x: x, y: y), &handled)
        if !handled, let pm = popupMenu ?? inheritedPopupMenu {
            pm.popup(in: self, at: NSPoint(x: x, y: y))
        }
    }

    open override func rightMouseUp(with event: NSEvent) {
        let (x, y) = localPoint(event)
        if effectiveEnabled { onMouseUp?(self, .mbRight, TShiftState(event.modifierFlags), x, y) }
    }

    var inheritedPopupMenu: TPopupMenu? {
        var v = superview
        while let c = v as? TControl {
            if let p = c.popupMenu { return p }
            v = c.superview
        }
        return nil
    }

    open override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: painting helpers

    public var nsColor: NSColor { Colors.ns(color) }
    public var textColor: NSColor { effectiveEnabled || !grayWhenDisabled ? Colors.ns(font.color) : Colors.ns(clGrayText) }
    open var grayWhenDisabled: Bool { true }

    open func paintBackground() {
        if !transparent { Draw.fill(bounds, nsColor) }
    }

    // MARK: DFM

    open func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "Left": frame.origin.x = CGFloat(value.intValue ?? 0)
        case "Top": frame.origin.y = CGFloat(value.intValue ?? 0)
        case "Width": frame.size.width = CGFloat(value.intValue ?? 0)
        case "Height": frame.size.height = CGFloat(value.intValue ?? 0)
        case "ClientWidth": frame.size.width = CGFloat(value.intValue ?? 0)
        case "ClientHeight": frame.size.height = CGFloat(value.intValue ?? 0)
        case "Tag": tag = value.intValue ?? 0
        case "Caption", "Text": caption = value.stringValue ?? ""
        case "Color":
            if let c = Colors.value(value) { color = c }
            parentColor = false
        case "ParentColor": parentColor = value.boolValue ?? true
        case "ParentFont": parentFont = value.boolValue ?? true
        case "Font.Name": font.name = value.stringValue ?? "Tahoma"; parentFont = false
        case "Font.Height": font.height = value.intValue ?? -11; parentFont = false
        case "Font.Size": font.size = value.intValue ?? 8; parentFont = false
        case "Font.Color": font.color = Colors.value(value) ?? clWindowText; parentFont = false
        case "Font.Style":
            var s: TFontStyles = []
            if case .set(let items) = value {
                for i in items {
                    switch i {
                    case "fsBold": s.insert(.fsBold)
                    case "fsItalic": s.insert(.fsItalic)
                    case "fsUnderline": s.insert(.fsUnderline)
                    case "fsStrikeOut": s.insert(.fsStrikeOut)
                    default: break
                    }
                }
            }
            font.style = s
            parentFont = false
        case "Font.Charset", "Font.Pitch", "Ctl3D", "ParentCtl3D", "TabOrder", "TabStop", "HelpContext",
             "ExplicitLeft", "ExplicitTop", "ExplicitWidth", "ExplicitHeight", "DesignSize", "BiDiMode",
             "ParentBiDiMode", "ParentBackground", "DoubleBuffered", "ParentDoubleBuffered", "DragKind", "DragMode",
             "HotTrackFont.Charset", "HotTrackFont.Color", "HotTrackFont.Height", "HotTrackFont.Name",
             "HotTrackFont.Style", "HotTrackFontOptions", "HintColor", "Constraints.MinHeight", "Constraints.MinWidth",
             "Constraints.MaxHeight", "Constraints.MaxWidth", "UseDockManager", "AutoHint", "Cursor":
            break
        case "Visible": isHidden = !(value.boolValue ?? true)
        case "Enabled": enabled = value.boolValue ?? true
        case "Hint": hint = value.stringValue ?? ""
        case "ShowHint": showHint = value.boolValue ?? false; parentShowHint = false
        case "ParentShowHint": parentShowHint = value.boolValue ?? true
        case "Transparent": transparent = value.boolValue ?? false
        case "Align": align = TAlign(rawValue: value.stringValue ?? "alNone") ?? .alNone
        case "AlignWithMargins": alignWithMargins = value.boolValue ?? false
        case "Margins.Left": margins.left = CGFloat(value.intValue ?? 3)
        case "Margins.Top": margins.top = CGFloat(value.intValue ?? 3)
        case "Margins.Right": margins.right = CGFloat(value.intValue ?? 3)
        case "Margins.Bottom": margins.bottom = CGFloat(value.intValue ?? 3)
        case "Anchors":
            var a: TAnchors = []
            if case .set(let items) = value {
                for i in items {
                    switch i {
                    case "akLeft": a.insert(.akLeft)
                    case "akTop": a.insert(.akTop)
                    case "akRight": a.insert(.akRight)
                    case "akBottom": a.insert(.akBottom)
                    default: break
                    }
                }
            }
            anchors = a
        case "Action": loader.fixup(value) { [weak self] (a: TAction) in self?.action = a }
        case "PopupMenu": loader.fixup(value) { [weak self] (p: TPopupMenu) in self?.popupMenu = p }
        case "OnClick": loader.event(value) { [weak self] h in self?.onClick = h }
        case "OnDblClick": loader.event(value) { [weak self] h in self?.onDblClick = h }
        case "OnChange": loader.event(value) { [weak self] h in self?.onChange = h }
        case "OnResize": loader.event(value) { [weak self] h in self?.onResize = h }
        case "OnEnter": loader.event(value) { [weak self] h in self?.onEnter = h }
        case "OnExit": loader.event(value) { [weak self] h in self?.onExit = h }
        case "OnMouseDown": loader.mouseEvent(value) { [weak self] h in self?.onMouseDown = h }
        case "OnMouseUp": loader.mouseEvent(value) { [weak self] h in self?.onMouseUp = h }
        case "OnMouseMove": loader.mouseMoveEvent(value) { [weak self] h in self?.onMouseMove = h }
        case "OnKeyPress": loader.keyPressEvent(value) { [weak self] h in self?.onKeyPress = h }
        case "OnKeyDown": loader.keyEvent(value) { [weak self] h in self?.onKeyDown = h }
        case "OnKeyUp": loader.keyEvent(value) { [weak self] h in self?.onKeyUp = h }
        case "OnContextPopup": loader.contextPopupEvent(value) { [weak self] h in self?.onContextPopup = h }
        default: return false
        }
        return true
    }

    open func loaded() {}

    open override var description: String { "\(type(of: self))(\(name))" }
}

/// TFrame: a reusable container loaded from its own DFM resource.
open class TFrame: TControl {
    open class var resourceName: String { String(describing: self).uppercased() }
    public var components: [String: AnyObject] = [:]
    public var appEvents: [TDummyComponent] = []

    public required init() {
        super.init(frame: .zero)
        color = clBtnFace
    }

    public required init(frame: NSRect) {
        super.init(frame: frame)
        color = clBtnFace
    }

    public required init?(coder: NSCoder) { fatalError() }

    public func component<T>(_ name: String) -> T? { components[name] as? T }

    open override func draw(_ dirtyRect: NSRect) { paintBackground() }
}
