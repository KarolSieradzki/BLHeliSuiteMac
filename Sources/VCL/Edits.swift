import AppKit

// MARK: - Text field used inside TEdit / editable combos

final class VCLTextField: NSTextField {
    weak var owner: TControl?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok, let o = owner { o.needsDisplay = true; o.onEnter?(o) }
        return ok
    }
}

/// Field editor that forwards typed characters to OnKeyPress (VCL semantics: Key := #0 swallows it).
final class VCLFieldEditor: NSTextView {
    weak var vclOwner: TControl?

    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard let owner = vclOwner, let handler = owner.onKeyPress else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        let s = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        var out = ""
        for ch in s {
            var c = ch
            handler(owner, &c)
            if c != "\0" { out.append(c) }
        }
        if !out.isEmpty { super.insertText(out, replacementRange: replacementRange) }
    }

    override func deleteBackward(_ sender: Any?) {
        if let owner = vclOwner, let handler = owner.onKeyPress {
            var c: Character = "\u{8}"
            handler(owner, &c)
            if c == "\0" { return }
        }
        super.deleteBackward(sender)
    }

    override func insertNewline(_ sender: Any?) {
        if let owner = vclOwner, let handler = owner.onKeyPress {
            var c: Character = "\r"
            handler(owner, &c)
        }
        // Enter: default button of the form
        if let f = window?.delegate as? TForm, f.pressDefaultButton() { return }
        window?.makeFirstResponder(window?.contentView)
    }

    override func cancelOperation(_ sender: Any?) {
        if let f = window?.delegate as? TForm, f.pressCancelButton() { return }
        super.cancelOperation(sender)
    }
}

// MARK: - TEdit / TJvEdit

open class TEdit: TControl, NSTextFieldDelegate {
    let field = VCLTextField(frame: .zero)
    public var readOnly = false { didSet { field.isEditable = !readOnly } }
    public var maxLength = 0
    public var charCaseUpper = false
    public var borderStyleNone = false
    public var autoSelect = true

    public required init(frame: NSRect) {
        super.init(frame: frame)
        color = clWindow
        parentColor = false
        field.owner = self
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = self
        field.lineBreakMode = .byClipping
        addSubview(field)
    }

    public required init?(coder: NSCoder) { fatalError() }

    public var textValue: String {
        get { field.stringValue }
        set {
            if field.stringValue != newValue {
                field.stringValue = newValue
                if !loadingEdit { onChange?(self) }
            }
        }
    }

    var loadingEdit = true

    open override func captionChanged() { textValue = caption }

    open override func fontChanged() {
        super.fontChanged()
        layoutField()
    }

    open override func colorChanged() {
        super.colorChanged()
        layoutField()
    }

    func layoutField() {
        let f = font.nsFont
        field.font = f
        field.textColor = effectiveEnabled ? Colors.ns(font.color) : Theme.disabledText
        let h = TextDraw.lineHeight(f) + 2
        let inset: CGFloat = borderStyleNone ? 0 : 2
        field.frame = NSRect(x: inset + 1, y: ((bounds.height - h) / 2).rounded(), width: max(0, bounds.width - 2 * inset - 2), height: h)
    }

    open override func resized() {
        super.resized()
        layoutField()
    }

    open override func enabledChanged() {
        super.enabledChanged()
        field.isEnabled = enabled
        layoutField()
    }

    open override func draw(_ dirtyRect: NSRect) {
        let en = effectiveEnabled
        Draw.fill(bounds, en ? nsColor : Theme.face)
        if !borderStyleNone {
            let focused = window?.firstResponder === field.currentEditor()
            Draw.frame(bounds, !en ? Colors.hex(0xCCCCCC) : focused ? Theme.hoverBorder : (mouseInside ? Theme.editHoverBorder : Theme.editBorder))
        }
    }

    open override var wantsHover: Bool { true }

    public func controlTextDidChange(_ obj: Notification) {
        var s = field.stringValue
        if charCaseUpper && s != s.uppercased() { s = s.uppercased(); field.stringValue = s }
        if maxLength > 0 && s.count > maxLength { field.stringValue = String(s.prefix(maxLength)) }
        onChange?(self)
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        needsDisplay = true
        onExit?(self)
    }

    public func setFocus() { window?.makeFirstResponder(field) }

    public func selectAll() { field.selectText(nil) }

    open override func loaded() {
        loadingEdit = false
        layoutField()
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "Text": field.stringValue = value.stringValue ?? ""
        case "ReadOnly": readOnly = value.boolValue ?? false
        case "MaxLength": maxLength = value.intValue ?? 0
        case "CharCase": charCaseUpper = value.stringValue == "ecUpperCase"
        case "BorderStyle": borderStyleNone = value.stringValue == "bsNone"
        case "AutoSelect": autoSelect = value.boolValue ?? true
        case "AutoSize", "BevelInner", "BevelKind", "BevelOuter", "Flat", "ParentFlat", "EmptyValue", "AutoHint",
             "PasswordChar", "ImeName", "HideSelection", "NumbersOnly", "OEMConvert", "ThemedPassword":
            break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

// MARK: - TSpinEdit / TJvSpinEdit

open class TSpinEdit: TEdit {
    public var minValue: Double = 0
    public var maxValue: Double = 0
    public var increment: Double = 1
    public var decimal = 0
    public var showButton = true { didSet { if showButton != oldValue { layoutField(); needsDisplay = true } } }
    private var repeatTimer: Timer?
    private var pressedButton = 0

    public var value: Double {
        get { Double(textValue.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        set {
            var v = newValue
            if maxValue > minValue || (maxValue != 0 || minValue != 0) { v = min(max(v, minValue), maxValue == 0 && minValue == 0 ? v : maxValue) }
            textValue = decimal > 0 ? String(format: "%.\(decimal)f", v) : String(Int(v.rounded()))
        }
    }

    public var intValue: Int {
        get { Int(value.rounded()) }
        set { value = Double(newValue) }
    }

    override func layoutField() {
        super.layoutField()
        if showButton { field.frame.size.width = max(0, bounds.width - 21) }
    }

    open override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showButton else { return }
        let en = effectiveEnabled
        let bw: CGFloat = 17
        let x = bounds.width - bw - 1
        let h = (bounds.height - 2) / 2
        let up = NSRect(x: x, y: 1, width: bw, height: h.rounded(.down))
        let dn = NSRect(x: x, y: 1 + h.rounded(.down), width: bw, height: bounds.height - 2 - h.rounded(.down))
        for (i, r) in [up, dn].enumerated() {
            let pressed = pressedButton == i + 1
            Draw.fill(r, pressed ? Theme.pressedFill : Theme.buttonFill)
            Draw.frame(r, pressed ? Theme.pressedBorder : Theme.buttonBorder)
            Draw.chevron(center: NSPoint(x: r.midX, y: r.midY), size: 6, direction: i == 0 ? 1 : 0,
                         color: en ? Theme.scrollArrow : Theme.disabledBorder)
        }
    }

    open override func mouseDown(with event: NSEvent) {
        guard showButton, effectiveEnabled else { return super.mouseDown(with: event) }
        let p = convert(event.locationInWindow, from: nil)
        guard p.x >= bounds.width - 18 else { return super.mouseDown(with: event) }
        pressedButton = p.y < bounds.height / 2 ? 1 : 2
        step()
        needsDisplay = true
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in self?.step() }
        }
    }

    open override func mouseUp(with event: NSEvent) {
        repeatTimer?.invalidate()
        repeatTimer = nil
        pressedButton = 0
        needsDisplay = true
        super.mouseUp(with: event)
    }

    func step() {
        if pressedButton == 1 { value = value + increment } else if pressedButton == 2 { value = value - increment }
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "MinValue": minValue = value.doubleValue ?? 0
        case "MaxValue": maxValue = value.doubleValue ?? 0
        case "Increment": increment = value.doubleValue ?? 1
        case "Decimal": decimal = value.intValue ?? 0
        case "ShowButton": showButton = value.boolValue ?? true
        case "Value":
            let v = value.doubleValue ?? 0
            field.stringValue = decimal > 0 ? String(format: "%.\(decimal)f", v) : String(Int(v.rounded()))
        case "ValueType", "ButtonKind", "CheckMinValue", "CheckMaxValue", "Thousands": break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }

    open override func loaded() {
        super.loaded()
        if field.stringValue.isEmpty { field.stringValue = decimal > 0 ? String(format: "%.\(decimal)f", 0.0) : "0" }
    }
}

// MARK: - Drop-down list window (shared by combo boxes)

final class DropDownList: NSPanel {
    final class ListView: NSView {
        var items: [String] = []
        var font: NSFont = TFont.defaultFont.nsFont
        var itemHeight: CGFloat = 13
        var hot = -1
        var top = 0
        var visibleCount = 8
        var onPick: ((Int) -> Void)?
        var drawItem: ((Int, NSRect, Bool) -> Void)?
        override var isFlipped: Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            Draw.fill(bounds, .white)
            let scroll = items.count > visibleCount
            let w = bounds.width - 2 - (scroll ? 17 : 0)
            for i in top..<min(items.count, top + visibleCount) {
                let r = NSRect(x: 1, y: 1 + CGFloat(i - top) * itemHeight, width: w, height: itemHeight)
                if let d = drawItem {
                    d(i, r, i == hot)
                } else {
                    if i == hot { Draw.fill(r, Theme.selection) }
                    TextDraw.draw(items[i], in: r.insetBy(dx: 2, dy: 0), font: font, color: i == hot ? .white : .black,
                                  layout: .center, accel: false)
                }
            }
            if scroll {
                let sb = NSRect(x: bounds.width - 18, y: 1, width: 17, height: bounds.height - 2)
                Draw.fill(sb, Theme.scrollTrack)
                let frac = CGFloat(visibleCount) / CGFloat(items.count)
                let th = max(17, (sb.height - 34) * frac)
                let pos = CGFloat(top) / CGFloat(max(1, items.count - visibleCount))
                let tr = NSRect(x: sb.minX + 2, y: sb.minY + 17 + (sb.height - 34 - th) * pos, width: 13, height: th)
                Draw.fill(tr, Theme.scrollThumb)
                Draw.chevron(center: NSPoint(x: sb.midX, y: sb.minY + 8), size: 7, direction: 1, color: Theme.scrollArrow)
                Draw.chevron(center: NSPoint(x: sb.midX, y: sb.maxY - 8), size: 7, direction: 0, color: Theme.scrollArrow)
            }
            Draw.frame(bounds, Colors.hex(0x646464))
        }

        func index(at p: NSPoint) -> Int {
            let i = top + Int((p.y - 1) / itemHeight)
            return (i >= 0 && i < items.count) ? i : -1
        }

        override func mouseMoved(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            if items.count > visibleCount && p.x > bounds.width - 18 { return }
            let i = index(at: p)
            if i != hot && i >= 0 { hot = i; needsDisplay = true }
        }

        override func mouseDown(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            if items.count > visibleCount && p.x > bounds.width - 18 {
                if p.y < 18 { scroll(-1) } else if p.y > bounds.height - 18 { scroll(1) }
                else { scroll(p.y < bounds.height / 2 ? -visibleCount : visibleCount) }
                return
            }
            let i = index(at: p)
            if i >= 0 { onPick?(i) }
        }

        override func scrollWheel(with event: NSEvent) {
            if event.scrollingDeltaY > 0 { scroll(-1) } else if event.scrollingDeltaY < 0 { scroll(1) }
        }

        func scroll(_ d: Int) {
            top = max(0, min(items.count - visibleCount, top + d))
            needsDisplay = true
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach { removeTrackingArea($0) }
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        }
    }

    let list = ListView(frame: .zero)
    var monitor: Any?
    var onClose: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        hasShadow = true
        contentView = list
    }

    func show(below control: NSView, items: [String], selected: Int, font: NSFont, itemHeight: CGFloat, count: Int, width: CGFloat,
              drawItem: ((Int, NSRect, Bool) -> Void)?, pick: @escaping (Int) -> Void) {
        guard let w = control.window else { return }
        list.items = items
        list.font = font
        list.itemHeight = itemHeight
        list.visibleCount = max(1, min(count, items.count))
        list.hot = selected
        list.top = max(0, min(selected - list.visibleCount + 1, items.count - list.visibleCount))
        if selected < list.visibleCount { list.top = 0 }
        list.drawItem = drawItem
        let h = CGFloat(list.visibleCount) * itemHeight + 2
        let r = control.convert(control.bounds, to: nil)
        let screenR = w.convertToScreen(r)
        var frame = NSRect(x: screenR.minX, y: screenR.minY - h, width: width, height: h)
        if let s = w.screen, frame.minY < s.visibleFrame.minY { frame.origin.y = screenR.maxY }
        setFrame(frame, display: true)
        list.onPick = { [weak self] i in
            self?.close()
            pick(i)
        }
        w.addChildWindow(self, ordered: .above)
        makeKeyAndOrderFront(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] e in
            guard let self else { return e }
            if e.type == .keyDown {
                switch e.keyCode {
                case 53: self.close(); return nil
                case 36, 76: let i = self.list.hot; self.close(); if i >= 0 { pick(i) }; return nil
                case 125: self.list.hot = min(self.list.items.count - 1, self.list.hot + 1); if self.list.hot >= self.list.top + self.list.visibleCount { self.list.scroll(1) }; self.list.needsDisplay = true; return nil
                case 126: self.list.hot = max(0, self.list.hot - 1); if self.list.hot < self.list.top { self.list.scroll(-1) }; self.list.needsDisplay = true; return nil
                default: return e
                }
            }
            if e.window !== self { self.close(); return nil }
            return e
        }
    }

    override func close() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        parent?.removeChildWindow(self)
        orderOut(nil)
        onClose?()
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - TComboBox / TJvComboBox / TComComboBox

open class TComboBox: TEdit {
    public var items: [String] = []
    public var itemIndex: Int = -1 {
        didSet {
            if itemIndex >= 0 && itemIndex < items.count { field.stringValue = items[itemIndex] }
            else if itemIndex < 0 && isDropDownList { field.stringValue = "" }
            needsDisplay = true
        }
    }
    public var isDropDownList = false { didSet { updateStyle() } }
    public var ownerDraw = false
    public var dropDownCount = 8
    public var itemHeight = 0
    public var onDropDown: TNotifyEvent?
    public var onCloseUp: TNotifyEvent?
    public var onSelect: TNotifyEvent?
    public var onDrawItem: ((TComboBox, Int, NSRect, Bool) -> Void)?
    public var droppedDown = false
    let dropList = DropDownList()

    public required init(frame: NSRect) {
        super.init(frame: frame)
        dropList.onClose = { [weak self] in
            guard let self else { return }
            self.droppedDown = false
            self.needsDisplay = true
        }
    }

    public required init?(coder: NSCoder) { fatalError() }

    func updateStyle() {
        field.isEditable = !isDropDownList && !readOnly
        field.isSelectable = !isDropDownList
        layoutField()
    }

    override func layoutField() {
        super.layoutField()
        field.frame.size.width = max(0, bounds.width - 21)
        if isDropDownList { field.frame.origin.x = 4 }
    }

    public var textValueCombo: String { isDropDownList ? (itemIndex >= 0 && itemIndex < items.count ? items[itemIndex] : "") : field.stringValue }

    open override func draw(_ dirtyRect: NSRect) {
        let en = effectiveEnabled
        if isDropDownList {
            ButtonFace.draw(bounds, enabled: en, hover: mouseInside && en, pressed: droppedDown, isDefault: false)
            if ownerDraw, let d = onDrawItem, itemIndex >= 0 {
                d(self, itemIndex, NSRect(x: 3, y: 3, width: bounds.width - 24, height: bounds.height - 6), false)
            }
        } else {
            Draw.fill(bounds, en ? nsColor : Theme.face)
            Draw.frame(bounds, !en ? Colors.hex(0xCCCCCC) : (mouseInside || droppedDown) ? Theme.hoverBorder : Theme.comboBorder)
            if mouseInside && en {
                let br = NSRect(x: bounds.width - 18, y: 1, width: 17, height: bounds.height - 2)
                Draw.fill(br, droppedDown ? Theme.pressedFill : Theme.hoverFill)
                Draw.vline(br.minX, br.minY, br.maxY, Theme.hoverBorder)
            }
        }
        Draw.chevron(center: NSPoint(x: bounds.width - 9.5, y: bounds.height / 2), size: 7, direction: 0,
                     color: en ? Colors.hex(0x404040) : Theme.disabledBorder, width: 1)
    }

    open override func mouseDown(with event: NSEvent) {
        guard effectiveEnabled else { return }
        let p = convert(event.locationInWindow, from: nil)
        if !isDropDownList && p.x < bounds.width - 18 {
            window?.makeFirstResponder(field)
            return
        }
        dropDown()
    }

    public func dropDown() {
        if droppedDown { dropList.close(); return }
        onDropDown?(self)
        guard !items.isEmpty else { onCloseUp?(self); return }
        droppedDown = true
        needsDisplay = true
        let f = font.nsFont
        let ih = CGFloat(itemHeight > 0 ? itemHeight : Int(TextDraw.lineHeight(f)) + (ownerDraw ? 3 : 0))
        var draw: ((Int, NSRect, Bool) -> Void)?
        if ownerDraw, let d = onDrawItem { draw = { [weak self] i, r, sel in if let s = self { d(s, i, r, sel) } } }
        let current = isDropDownList ? itemIndex : (items.firstIndex(of: field.stringValue) ?? itemIndex)
        dropList.show(below: self, items: items, selected: current, font: f, itemHeight: ih, count: dropDownCount,
                      width: frame.width, drawItem: draw) { [weak self] i in
            guard let self else { return }
            let changed = i != self.itemIndex || (!self.isDropDownList && self.field.stringValue != self.items[i])
            self.itemIndex = i
            if changed { self.onChange?(self) }
            self.onSelect?(self)
            self.onCloseUp?(self)
        }
    }

    public func clear() {
        items = []
        itemIndex = -1
        field.stringValue = ""
    }

    public var text_: String {
        get { isDropDownList ? textValueCombo : field.stringValue }
        set {
            field.stringValue = newValue
            if let i = items.firstIndex(of: newValue) { itemIndex = i } else if isDropDownList { itemIndex = -1 }
        }
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "Items.Strings": if case .list(let l) = value { items = l.compactMap(\.stringValue) }
        case "ItemIndex": itemIndex = value.intValue ?? -1
        case "Style":
            let s = value.stringValue ?? ""
            isDropDownList = s == "csDropDownList" || s == "csOwnerDrawFixed" || s == "csOwnerDrawVariable"
            ownerDraw = s.hasPrefix("csOwnerDraw")
        case "DropDownCount": dropDownCount = value.intValue ?? 8
        case "ItemHeight": itemHeight = value.intValue ?? 0
        case "OnDropDown": loader.event(value) { [weak self] h in self?.onDropDown = h }
        case "OnCloseUp": loader.event(value) { [weak self] h in self?.onCloseUp = h }
        case "OnSelect": loader.event(value) { [weak self] h in self?.onSelect = h }
        case "OnDrawItem": loader.drawItemEvent(value) { [weak self] h in self?.onDrawItem = h }
        case "AutoComplete", "AutoDropDown", "AutoCloseUp", "Sorted", "ComProperty", "DroppedDownWidth", "Options",
             "ColorDialogText", "NewColorText", "ReadOnly", "MeasureStyle", "ListSettings.OutfilteredValueFont.Charset":
            break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

// MARK: - TListBox

open class TListBox: TControl {
    public var items: [String] = [] { didSet { if itemIndex >= items.count { itemIndex = items.count - 1 }; updateScroll(); needsDisplay = true } }
    public var itemIndex = -1 { didSet { needsDisplay = true; ensureVisible() } }
    public var itemHeight = 13
    public var ownerDraw = false
    public var topIndex = 0 { didSet { needsDisplay = true } }
    public var onDrawItem: ((TListBox, Int, NSRect, Bool) -> Void)?
    public var columns = 0

    public required init(frame: NSRect) {
        super.init(frame: frame)
        color = clWindow
        parentColor = false
    }

    public required init?(coder: NSCoder) { fatalError() }

    var ih: CGFloat { CGFloat(itemHeight > 0 ? itemHeight : Int(TextDraw.lineHeight(font.nsFont))) }
    var visibleRows: Int { max(1, Int((bounds.height - 2) / ih)) }
    var hasScroll: Bool { items.count > visibleRows }

    func updateScroll() { topIndex = max(0, min(topIndex, items.count - visibleRows)) }

    func ensureVisible() {
        guard itemIndex >= 0 else { return }
        if itemIndex < topIndex { topIndex = itemIndex }
        if itemIndex >= topIndex + visibleRows { topIndex = itemIndex - visibleRows + 1 }
    }

    open override func draw(_ dirtyRect: NSRect) {
        Draw.fill(bounds, nsColor)
        let w = bounds.width - 2 - (hasScroll ? 17 : 0)
        for i in topIndex..<min(items.count, topIndex + visibleRows + 1) {
            let r = NSRect(x: 1, y: 1 + CGFloat(i - topIndex) * ih, width: w, height: ih)
            let sel = i == itemIndex
            if ownerDraw, let d = onDrawItem {
                d(self, i, r, sel)
            } else {
                if sel { Draw.fill(r, Theme.selection) }
                TextDraw.draw(items[i], in: r.insetBy(dx: 2, dy: 0), font: font.nsFont, color: sel ? .white : Colors.ns(font.color),
                              layout: .center, accel: false)
            }
        }
        if hasScroll {
            let sb = NSRect(x: bounds.width - 18, y: 1, width: 17, height: bounds.height - 2)
            Draw.fill(sb, Theme.scrollTrack)
            let frac = CGFloat(visibleRows) / CGFloat(items.count)
            let th = max(17, (sb.height - 34) * frac)
            let pos = CGFloat(topIndex) / CGFloat(max(1, items.count - visibleRows))
            Draw.fill(NSRect(x: sb.minX + 2, y: sb.minY + 17 + (sb.height - 34 - th) * pos, width: 13, height: th), Theme.scrollThumb)
            Draw.chevron(center: NSPoint(x: sb.midX, y: sb.minY + 8), size: 7, direction: 1, color: Theme.scrollArrow)
            Draw.chevron(center: NSPoint(x: sb.midX, y: sb.maxY - 8), size: 7, direction: 0, color: Theme.scrollArrow)
        }
        Draw.frame(bounds, Colors.hex(0x828790))
    }

    public func itemAt(_ p: NSPoint) -> Int {
        let i = topIndex + Int((p.y - 1) / ih)
        return (i >= 0 && i < items.count) ? i : -1
    }

    open override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if hasScroll && p.x > bounds.width - 18 {
            if p.y < 18 { topIndex = max(0, topIndex - 1) }
            else if p.y > bounds.height - 18 { topIndex = min(items.count - visibleRows, topIndex + 1) }
            else { topIndex = max(0, min(items.count - visibleRows, topIndex + (p.y < bounds.height / 2 ? -visibleRows : visibleRows))) }
            return
        }
        let i = itemAt(p)
        if i >= 0 && i != itemIndex { itemIndex = i; onClick?(self) }
        super.mouseDown(with: event)
    }

    open override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = itemAt(p)
        if i >= 0 { itemIndex = i }
        super.rightMouseDown(with: event)
    }

    open override func scrollWheel(with event: NSEvent) {
        let d = event.scrollingDeltaY > 0 ? -1 : (event.scrollingDeltaY < 0 ? 1 : 0)
        topIndex = max(0, min(max(0, items.count - visibleRows), topIndex + d))
    }

    open override var acceptsFirstResponder: Bool { true }

    open override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125: if itemIndex < items.count - 1 { itemIndex += 1; onClick?(self) }
        case 126: if itemIndex > 0 { itemIndex -= 1; onClick?(self) }
        case 36, 76: onDblClick?(self)
        default: super.keyDown(with: event)
        }
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "Items.Strings": if case .list(let l) = value { items = l.compactMap(\.stringValue) }
        case "ItemHeight": itemHeight = value.intValue ?? 13
        case "Style": ownerDraw = (value.stringValue ?? "").hasPrefix("lbOwnerDraw")
        case "Columns": columns = value.intValue ?? 0
        case "OnDrawItem": loader.listDrawItemEvent(value) { [weak self] h in self?.onDrawItem = h }
        case "ExtendedSelect", "MultiSelect", "Sorted", "IntegralHeight", "BorderStyle": break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

// MARK: - TMemo / TRichEdit / TJvRichEdit

open class TMemo: TControl {
    public let scroll = NSScrollView(frame: .zero)
    public let textView = NSTextView(frame: .zero)
    public var readOnly = false { didSet { textView.isEditable = !readOnly } }
    public var borderNone = false
    public var wordWrap = true

    public required init(frame: NSRect) {
        super.init(frame: frame)
        color = clWindow
        parentColor = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = textView
        textView.isRichText = true
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 0, height: 1)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        addSubview(scroll)
    }

    public required init?(coder: NSCoder) { fatalError() }

    open override func resized() {
        super.resized()
        let inset: CGFloat = borderNone ? 0 : 1
        scroll.frame = bounds.insetBy(dx: inset, dy: inset)
        textView.frame.size.width = scroll.contentSize.width
    }

    open override func fontChanged() {
        super.fontChanged()
        textView.font = font.nsFont
        textView.textColor = Colors.ns(font.color)
    }

    open override func colorChanged() {
        super.colorChanged()
        textView.backgroundColor = nsColor
    }

    public var lines: [String] {
        get { textView.string.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n") }
        set { textView.string = newValue.joined(separator: "\n") }
    }

    public func clearText() { textView.string = "" }

    public func addLine(_ s: String, color: TColor? = nil, style: TFontStyles = []) {
        let storage = textView.textStorage!
        let prefix = storage.length > 0 ? "\n" : ""
        let f = style.contains(.fsBold) ? TFont.make(name: font.name, height: font.height, style: [.fsBold]) : font.nsFont
        storage.append(NSAttributedString(string: prefix + s, attributes: [.font: f, .foregroundColor: Colors.ns(color ?? font.color)]))
    }

    open override func draw(_ dirtyRect: NSRect) {
        Draw.fill(bounds, nsColor)
        if !borderNone { Draw.frame(bounds, Colors.hex(0x828790)) }
    }

    open override func loaded() {
        textView.font = font.nsFont
        textView.textColor = Colors.ns(font.color)
        textView.backgroundColor = nsColor
        resized()
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "Lines.Strings": if case .list(let l) = value { textView.string = l.compactMap(\.stringValue).joined(separator: "\n") }
        case "ReadOnly": readOnly = value.boolValue ?? false
        case "BorderStyle": borderNone = value.stringValue == "bsNone"
        case "ScrollBars":
            let s = value.stringValue ?? ""
            scroll.hasVerticalScroller = s == "ssVertical" || s == "ssBoth"
            scroll.hasHorizontalScroller = s == "ssHorizontal" || s == "ssBoth"
        case "WordWrap": wordWrap = value.boolValue ?? true
        case "Alignment", "BevelInner", "BevelOuter", "BevelKind", "Flat", "ParentFlat", "AdvancedTypography",
             "AllowInPlace", "AutoAdvancedTypography", "StreamFormat", "StreamMode", "PlainText", "HideSelection",
             "HideScrollBars", "WantReturns", "WantTabs", "SelText", "AutoURLDetect":
            break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}
