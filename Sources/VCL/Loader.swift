import AppKit

/// Instantiates a component tree from a DFM (like Delphi's TReader) and binds published
/// fields (@objc properties) and event handlers (@objc methods) of the root by name.
public final class DFMLoader {
    public let root: TControl
    /// Object whose methods receive the events (the form for inline frame overrides).
    var eventTarget: NSObject
    var fixups: [() -> Void] = []
    var loadedList: [VCLComponent] = []
    public static var verbose = ProcessInfo.processInfo.environment["VCL_VERBOSE"] != nil

    public static var frameClasses: [String: TFrame.Type] = [:]

    public init(root: TControl, eventTarget: NSObject? = nil) {
        self.root = root
        self.eventTarget = eventTarget ?? root
    }

    static let visual: [String: TControl.Type] = [
        "TLabel": TLabel.self, "TJvLabel": TLabel.self, "TJvStaticText": TStaticText.self, "TStaticText": TStaticText.self,
        "TPanel": TPanel.self, "TJvPanel": TPanel.self, "TJvCaptionPanel": TCaptionPanel.self, "TJvItemsPanel": TItemsPanel.self,
        "TGroupBox": TGroupBox.self, "TJvGroupBox": TGroupBox.self, "TRadioGroup": TRadioGroup.self, "TJvRadioGroup": TRadioGroup.self,
        "TBevel": TBevel.self, "TImage": TImage.self,
        "TButton": TButton.self, "TBitBtn": TButton.self, "TJvBitBtn": TButton.self, "TJvImgBtn": TButton.self,
        "TSpeedButton": TSpeedButton.self, "TJvSpeedButton": TSpeedButton.self,
        "TCheckBox": TCheckBox.self, "TJvCheckBox": TCheckBox.self, "TRadioButton": TRadioButton.self, "TJvRadioButton": TRadioButton.self,
        "TEdit": TEdit.self, "TJvEdit": TEdit.self, "TMaskEdit": TEdit.self,
        "TSpinEdit": TSpinEdit.self, "TJvSpinEdit": TSpinEdit.self,
        "TComboBox": TComboBox.self, "TJvComboBox": TComboBox.self, "TComComboBox": TComboBox.self,
        "TJvColorComboBox": TComboBox.self, "TJvFullColorSpaceCombo": TComboBox.self, "TJvFullColorAxisCombo": TComboBox.self,
        "TListBox": TListBox.self, "TJvListBox": TListBox.self,
        "TMemo": TMemo.self, "TRichEdit": TMemo.self, "TJvRichEdit": TMemo.self, "TJvMemo": TMemo.self,
        "TScrollBar": TScrollBar.self, "TJvScrollBar": TScrollBar.self,
        "TTrackBar": TTrackBar.self, "TJvTrackBar": TTrackBar.self, "TJvFullColorTrackBar": TTrackBar.self,
        "TPageControl": TPageControl.self, "TJvPageControl": TPageControl.self, "TTabSheet": TTabSheet.self,
        "TStatusBar": TStatusBar.self, "TJvStatusBar": TStatusBar.self, "TTreeView": TTreeView.self,
        "TStringGrid": TDrawGrid.self, "TJvStringGrid": TDrawGrid.self, "TDrawGrid": TDrawGrid.self,
        "TLed": TLed.self, "TGauge": TGauge.self, "TJvGradient": TGradient.self, "TJvSwitch": TSwitch.self,
        "TJvFullColorCircle": TPanel.self, "TJvFullColorPanel": TPanel.self, "TJvFullColorGroup": TPanel.self,
    ]

    func makeComponent(_ obj: DFMObject) -> AnyObject {
        if let f = DFMLoader.frameClasses[obj.className] { return f.init() }
        if let v = DFMLoader.visual[obj.className] {
            let c = v.init(frame: .zero)
            if let l = c as? TLabel { l.isJv = obj.className.hasPrefix("TJv") }
            if let p = c as? TPanel, obj.className == "TJvPanel" { p.bevelOuter = .bvRaised }
            return c
        }
        switch obj.className {
        case "TAction", "TJvAction": return TAction()
        case "TActionList", "TJvActionList": return TActionList()
        case "TImageList", "TJvImageList": return TImageList()
        case "TMainMenu", "TJvMainMenu": return TMainMenu()
        case "TPopupMenu", "TJvPopupMenu": return TPopupMenu()
        case "TMenuItem": return TMenuItem()
        case "TTimer", "TJvTimer": return TTimer()
        default:
            let d = TDummyComponent()
            d.className_ = obj.className
            return d
        }
    }

    // MARK: loading

    /// Loads a root (form or frame) DFM into `root`.
    public func loadRoot(_ dfm: DFMObject) {
        apply(dfm, to: root)
        for c in dfm.children { loadChild(c, parent: root) }
        finish()
    }

    func finish() {
        for f in fixups { f() }
        fixups.removeAll()
        // parent font/color inheritance top-down
        inherit(root)
        for c in loadedList { c.loaded() }
        root.loaded()
        loadedList.removeAll()
        root.realign()
    }

    func inherit(_ v: TControl) {
        for c in v.controls {
            c.inheritFromParent()
            inherit(c)
        }
    }

    func apply(_ obj: DFMObject, to comp: VCLComponent) {
        for (name, value) in obj.props {
            if name == "Bitmap", let il = comp as? TImageList, case .binary(let b) = value { il.load(b); continue }
            if name.hasPrefix("HotTrackFont.") || name.hasPrefix("Font.Charset") { continue }
            if !comp.setDFMProperty(name, value, self), DFMLoader.verbose {
                print("VCL: \(obj.className).\(name) not handled (\(value))")
            }
        }
    }

    func register(_ name: String, _ obj: AnyObject) {
        guard !name.isEmpty else { return }
        if let f = root as? TForm { f.components[name] = obj }
        if let fr = root as? TFrame { fr.components[name] = obj }
        let target: NSObject = root
        if target.responds(to: NSSelectorFromString(name)) {
            target.setValue(obj, forKey: name)
        } else if DFMLoader.verbose {
            print("VCL: no outlet \(type(of: root)).\(name)")
        }
    }

    func loadChild(_ obj: DFMObject, parent: AnyObject) {
        // inline / inherited override of an existing frame child
        if obj.kind != .object, let existing = findExisting(obj.name, in: parent) {
            let sub = DFMLoader(root: root, eventTarget: eventTarget)
            sub.apply(obj, to: existing as! VCLComponent)
            fixups += sub.fixups
            for c in obj.children { loadChild(c, parent: existing) }
            return
        }
        let comp = makeComponent(obj)
        guard let vc = comp as? VCLComponent else { return }
        vc.name = obj.name
        if let frame = comp as? TFrame {
            // load the frame's own DFM first, then the overrides of the parent DFM
            frame.root = root
            frame.loadOwnForm()
            if let p = parent as? TControl { p.insertControl(frame) }
            let sub = DFMLoader(root: frame, eventTarget: root)
            sub.apply(obj, to: frame)
            for c in obj.children { sub.loadChild(c, parent: frame) }
            sub.finishOverrides()
            fixups += sub.fixups.map { f in f }
            register(obj.name, frame)
            return
        }
        if let c = comp as? TControl {
            c.root = root
            apply(obj, to: c)
            if let p = parent as? TControl {
                if let pc = p as? TPageControl, let ts = c as? TTabSheet {
                    ts.pageControl = pc
                    pc.pages.append(ts)
                    pc.addSubview(ts)
                    ts.isHidden = true
                } else {
                    p.addSubview(c)
                }
            }
        } else if let comp = comp as? TComponent {
            comp.owner = root
            apply(obj, to: comp)
            if let a = comp as? TAction, let l = parent as? TActionList { l.add(a) }
            if let m = comp as? TMenuItem {
                if let menu = parent as? TMenu { menu.items.add(m); m.menu = menu }
                else if let pi = parent as? TMenuItem { pi.add(m); m.menu = pi.menu }
            }
            if let l = comp as? TActionList, let f = root as? TForm { f.actionLists.append(l) }
            if let d = comp as? TDummyComponent, d.className_ == "TJvAppEvents", let f = root as? TForm { f.appEvents.append(d) }
            if let d = comp as? TDummyComponent, d.className_ == "TJvAppEvents", let fr = root as? TFrame { fr.appEvents.append(d) }
        }
        register(obj.name, comp)
        loadedList.append(vc)
        for c in obj.children { loadChild(c, parent: comp) }
    }

    func finishOverrides() {
        for f in fixups { f() }
        fixups.removeAll()
        for c in loadedList { c.loaded() }
        loadedList.removeAll()
    }

    func findExisting(_ name: String, in parent: AnyObject) -> AnyObject? {
        if let fr = parent as? TFrame, let c = fr.components[name] { return c }
        if let v = parent as? NSView {
            for s in v.subviews {
                if let c = s as? TControl {
                    if c.name == name { return c }
                    if let f = findExisting(name, in: c) { return f }
                }
            }
        }
        if let fr = root as? TFrame, let c = fr.components[name] { return c }
        return nil
    }

    // MARK: references

    func lookup(_ name: String) -> AnyObject? {
        let parts = name.split(separator: ".").map(String.init)
        let key = parts.last ?? name
        if let f = root as? TForm, let c = f.components[key] { return c }
        if let fr = root as? TFrame, let c = fr.components[key] { return c }
        if let et = eventTarget as? TForm, let c = et.components[key] { return c }
        if let et = eventTarget as? TFrame, let c = et.components[key] { return c }
        if let rf = root.root as? TForm, let c = rf.components[key] { return c }
        for wf in Application.shared.forms { if let c = wf.form?.components[key] { return c } }
        return nil
    }

    public func fixup<T>(_ v: DFMValue, _ set: @escaping (T) -> Void) {
        guard let name = v.stringValue else { return }
        fixups.append { [unowned self] in
            if let o = self.lookup(name) as? T { set(o) }
            else if DFMLoader.verbose { print("VCL: unresolved reference \(name)") }
        }
    }

    // MARK: events

    func selector(_ name: String, args: Int) -> Selector? {
        let candidates = args == 1 ? ["\(name):", "\(name)WithSender:"] : ["\(name)::", "\(name):args:", "\(name):_:"]
        for c in candidates where eventTarget.responds(to: NSSelectorFromString(c)) { return NSSelectorFromString(c) }
        if DFMLoader.verbose { print("VCL: handler \(type(of: eventTarget)).\(name) not implemented") }
        return nil
    }

    public func event(_ v: DFMValue, _ set: (@escaping TNotifyEvent) -> Void) {
        guard let n = v.stringValue, let sel = selector(n, args: 1) else { return }
        let t = eventTarget
        set { [weak t] s in _ = t?.perform(sel, with: s) }
    }

    func invoke2(_ n: String) -> ((TObject, NSObject) -> Void)? {
        guard let sel = selector(n, args: 2) else { return nil }
        let t = eventTarget
        return { [weak t] s, a in _ = t?.perform(sel, with: s, with: a) }
    }

    public func mouseEvent(_ v: DFMValue, _ set: (@escaping TMouseEvent) -> Void) {
        guard let n = v.stringValue, let f = invoke2(n) else { return }
        set { s, b, sh, x, y in f(s, TMouseArgs(b, sh, x, y)) }
    }

    public func mouseMoveEvent(_ v: DFMValue, _ set: (@escaping TMouseMoveEvent) -> Void) {
        guard let n = v.stringValue, let f = invoke2(n) else { return }
        set { s, sh, x, y in f(s, TMouseArgs(.mbLeft, sh, x, y)) }
    }

    public func keyPressEvent(_ v: DFMValue, _ set: (@escaping TKeyPressEvent) -> Void) {
        guard let n = v.stringValue, let f = invoke2(n) else { return }
        set { s, key in
            let a = TKeyArgs(key: key)
            f(s, a)
            key = a.key
        }
    }

    public func keyEvent(_ v: DFMValue, _ set: (@escaping TKeyEvent) -> Void) {
        guard let n = v.stringValue, let f = invoke2(n) else { return }
        set { s, key, sh in
            let a = TKeyArgs(key: "\0", keyCode: key, shift: sh)
            f(s, a)
            key = a.keyCode
        }
    }

    public func contextPopupEvent(_ v: DFMValue, _ set: (@escaping (TObject, NSPoint, inout Bool) -> Void) -> Void) {
        guard let n = v.stringValue, let f = invoke2(n) else { return }
        set { s, _, handled in
            let a = TBoolArgs(handled)
            f(s, a)
            handled = a.value
        }
    }

    public func boolEvent(_ v: DFMValue, _ set: (@escaping (TObject, inout Bool) -> Void) -> Void) {
        guard let n = v.stringValue, let f = invoke2(n) else { return }
        set { s, b in
            let a = TBoolArgs(b)
            f(s, a)
            b = a.value
        }
    }

    public func closeEvent(_ v: DFMValue, _ set: (@escaping (TObject, TCloseArgs) -> Void) -> Void) {
        guard let n = v.stringValue, let f = invoke2(n) else { return }
        set { s, a in f(s, a) }
    }

    public func closeQueryEvent(_ v: DFMValue, _ set: (@escaping (TObject, TBoolArgs) -> Void) -> Void) {
        guard let n = v.stringValue, let f = invoke2(n) else { return }
        set { s, a in f(s, a) }
    }

    public func drawCellEvent(_ v: DFMValue, _ set: (@escaping (TObject, TDrawCellArgs) -> Void) -> Void) {
        guard let n = v.stringValue, let f = invoke2(n) else { return }
        set { s, a in f(s, a) }
    }

    public func selectCellEvent(_ v: DFMValue, _ set: (@escaping (TObject, TSelectCellArgs) -> Void) -> Void) {
        guard let n = v.stringValue, let f = invoke2(n) else { return }
        set { s, a in f(s, a) }
    }

    public func drawItemEvent(_ v: DFMValue, _ set: (@escaping (TComboBox, Int, NSRect, Bool) -> Void) -> Void) {
        guard let n = v.stringValue, let f = invoke2(n) else { return }
        set { s, i, r, sel in f(s, TDrawItemArgs(i, r, sel)) }
    }

    public func listDrawItemEvent(_ v: DFMValue, _ set: (@escaping (TListBox, Int, NSRect, Bool) -> Void) -> Void) {
        guard let n = v.stringValue, let f = invoke2(n) else { return }
        set { s, i, r, sel in f(s, TDrawItemArgs(i, r, sel)) }
    }
}

public final class TDrawItemArgs: NSObject {
    public let index: Int
    public let rect: NSRect
    public let selected: Bool
    public init(_ i: Int, _ r: NSRect, _ s: Bool) { index = i; rect = r; selected = s }
}

extension TFrame {
    /// Creates a frame at run time (TFrame.Create(Owner) + its DFM), e.g. the motor sliders of the Motors page.
    public static func create(resource: String? = nil) -> Self {
        let f = Self.init()
        f.loadOwnForm(resource)
        return f
    }

    /// Loads the frame's own DFM resource (TFRAESCCOMBOS …) with the frame as root.
    func loadOwnForm(_ resource: String? = nil) {
        guard let dfm = Resources.form(resource ?? type(of: self).resourceName) else { return }
        let l = DFMLoader(root: self)
        l.apply(dfm, to: self)
        for c in dfm.children { l.loadChild(c, parent: self) }
        for f in l.fixups { f() }
        l.fixups.removeAll()
        l.inherit(self)
        for c in l.loadedList { c.loaded() }
        l.loadedList.removeAll()
    }
}
