import AppKit

/// TAction.
public final class TAction: TComponent {
    public weak var actionList: TActionList?
    private var clients: [WeakRef] = []

    public var caption = "" { didSet { if caption != oldValue { changed() } } }
    public var hint = "" { didSet { if hint != oldValue { changed() } } }
    public var enabled = true { didSet { if enabled != oldValue { changed() } } }
    public var visible = true { didSet { if visible != oldValue { changed() } } }
    public var checked = false {
        didSet {
            if checked != oldValue {
                if checked && groupIndex > 0, let list = actionList {
                    for a in list.actions where a !== self && a.groupIndex == groupIndex { a.checked = false }
                }
                changed()
            }
        }
    }
    public var imageIndex = -1 { didSet { if imageIndex != oldValue { changed() } } }
    public var groupIndex = 0
    public var autoCheck = false
    public var shortCut = 0
    public var onExecute: TNotifyEvent?
    public var onUpdate: TNotifyEvent?

    final class WeakRef { weak var obj: AnyObject?; init(_ o: AnyObject) { obj = o } }

    func addClient(_ c: AnyObject) {
        clients.removeAll { $0.obj == nil || $0.obj === c }
        clients.append(WeakRef(c))
    }

    func removeClient(_ c: AnyObject) { clients.removeAll { $0.obj == nil || $0.obj === c } }

    private func changed() {
        for c in clients {
            if let ctl = c.obj as? TControl { ctl.actionChanged(self) }
            else if let mi = c.obj as? TMenuItem { mi.actionChanged(self) }
        }
    }

    /// Returns true if an OnExecute handler ran.
    @discardableResult
    public func execute() -> Bool {
        guard enabled else { return false }
        if autoCheck { checked.toggle() }
        if let h = onExecute { h(self); return true }
        return false
    }

    /// Update (idle): OnUpdate of the action, else of the list.
    public func update() {
        if let u = onUpdate { u(self) } else { actionList?.onUpdate?(self) }
    }

    public override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "Caption": caption = value.stringValue ?? ""
        case "Hint": hint = value.stringValue ?? ""
        case "Enabled": enabled = value.boolValue ?? true
        case "Visible": visible = value.boolValue ?? true
        case "Checked": checked = value.boolValue ?? false
        case "ImageIndex": imageIndex = value.intValue ?? -1
        case "GroupIndex": groupIndex = value.intValue ?? 0
        case "AutoCheck": autoCheck = value.boolValue ?? false
        case "ShortCut": shortCut = value.intValue ?? 0
        case "Category", "HelpContext", "SecondaryShortCuts.Strings": break
        case "OnExecute": loader.event(value) { [weak self] h in self?.onExecute = h }
        case "OnUpdate": loader.event(value) { [weak self] h in self?.onUpdate = h }
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

/// TActionList.
public final class TActionList: TComponent {
    public var actions: [TAction] = []
    public weak var images: TImageList?
    public var onUpdate: TNotifyEvent?

    public func add(_ a: TAction) {
        a.actionList = self
        actions.append(a)
    }

    public func updateActions() {
        for a in actions { a.update() }
    }

    public override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "Images": loader.fixup(value) { [weak self] (i: TImageList) in self?.images = i }
        case "OnUpdate": loader.event(value) { [weak self] h in self?.onUpdate = h }
        case "OnExecute", "State": break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

/// TTimer (also used for TJvTimer).
public final class TTimer: TComponent {
    public var interval = 1000 { didSet { restart() } }
    public var enabled = true { didSet { restart() } }
    public var onTimer: TNotifyEvent? { didSet { restart() } }
    private var timer: Timer?
    private var isLoading = true

    private func restart() {
        timer?.invalidate()
        timer = nil
        guard !isLoading, enabled, interval > 0, onTimer != nil else { return }
        let t = Timer(timeInterval: Double(interval) / 1000, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.onTimer?(self)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public override func loaded() {
        isLoading = false
        restart()
    }

    public func start() { isLoading = false; restart() }

    public override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "Interval": interval = value.intValue ?? 1000
        case "Enabled": enabled = value.boolValue ?? true
        case "OnTimer": loader.event(value) { [weak self] h in self?.onTimer = h }
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }

    deinit { timer?.invalidate() }
}

/// Components without visual function on macOS (storage, XP manifest, balloon hint settings …).
public final class TDummyComponent: TComponent {
    public var className_ = ""
    public var props: [(String, DFMValue)] = []
    public var onIdle: TNotifyEvent?
    public var onHelp: TNotifyEvent?

    public override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        props.append((name, value))
        switch name {
        case "OnIdle": loader.event(value) { [weak self] h in self?.onIdle = h }
        default: break
        }
        return true
    }
}
