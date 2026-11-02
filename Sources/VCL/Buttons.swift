import AppKit

public enum TButtonLayout: String { case blGlyphLeft, blGlyphRight, blGlyphTop, blGlyphBottom }

/// Themed (Windows 10) push button background.
enum ButtonFace {
    static func draw(_ r: NSRect, enabled: Bool, hover: Bool, pressed: Bool, isDefault: Bool, focused: Bool = false) {
        let fill: NSColor, border: NSColor
        if !enabled { fill = Theme.disabledFill; border = Theme.disabledBorder }
        else if pressed { fill = Theme.pressedFill; border = Theme.pressedBorder }
        else if hover { fill = Theme.hoverFill; border = Theme.hoverBorder }
        else { fill = Theme.buttonFill; border = (isDefault || focused) ? Theme.hoverBorder : Theme.buttonBorder }
        Draw.fill(r, fill)
        Draw.frame(r, border)
        if enabled && (isDefault || focused) && !hover && !pressed {
            Draw.frame(r.insetBy(dx: 1, dy: 1), Theme.hoverBorder)
        }
    }
}

// MARK: - TButton / TBitBtn / TJvBitBtn

open class TButton: TControl {
    public var modalResult: TModalResult = mrNone
    public var isDefault = false
    public var isCancel = false
    public var glyph: TGlyph?
    public var layoutGlyph: TButtonLayout = .blGlyphLeft
    public var spacing = 4
    public var margin = -1
    public var numGlyphs = 1
    var pendingGlyph: [UInt8]?
    var kind = "bkCustom"
    public var wordWrap = false

    public required init(frame: NSRect) {
        super.init(frame: frame)
        color = clBtnFace
    }

    public required init?(coder: NSCoder) { fatalError() }

    open override var wantsHover: Bool { true }
    open override var clickOnMouseUp: Bool { true }

    open override func click() {
        if let f = root as? TForm ?? (window?.delegate as? TForm), modalResult != mrNone {
            super.click()
            f.modalResult = modalResult
            return
        }
        super.click()
    }

    open override func actionChanged(_ a: TAction) {
        super.actionChanged(a)
    }

    open override func draw(_ dirtyRect: NSRect) {
        let en = effectiveEnabled
        ButtonFace.draw(bounds, enabled: en, hover: mouseInside && en, pressed: mouseIsDown && mouseInside && en,
                        isDefault: isDefault)
        drawContent(in: bounds, enabled: en)
    }

    func drawContent(in r: NSRect, enabled en: Bool) {
        let f = font.nsFont
        let text = TextDraw.stripAccel(caption)
        let tw = text.isEmpty ? 0 : TextDraw.width(text, f).rounded(.up)
        let th = TextDraw.lineHeight(f)
        let color = en ? Colors.ns(font.color) : Theme.disabledText
        let off: CGFloat = (mouseIsDown && mouseInside && en) ? 0 : 0
        if let g = glyph {
            let gs = g.size
            let sp: CGFloat = text.isEmpty ? 0 : CGFloat(spacing)
            switch layoutGlyph {
            case .blGlyphLeft, .blGlyphRight:
                let total = gs.width + sp + tw
                var x = margin >= 0 ? r.minX + CGFloat(margin) : r.minX + ((r.width - total) / 2).rounded(.down)
                let gy = r.minY + ((r.height - gs.height) / 2).rounded(.down)
                if layoutGlyph == .blGlyphLeft {
                    Draw.image(en ? g.normal : g.disabled, at: NSPoint(x: x + off, y: gy + off))
                    x += gs.width + sp
                    TextDraw.draw(text, in: NSRect(x: x + off, y: r.minY + ((r.height - th) / 2).rounded(.down) + off, width: tw + 2, height: th),
                                  font: f, color: color, accel: false)
                } else {
                    TextDraw.draw(text, in: NSRect(x: x + off, y: r.minY + ((r.height - th) / 2).rounded(.down) + off, width: tw + 2, height: th),
                                  font: f, color: color, accel: false)
                    Draw.image(en ? g.normal : g.disabled, at: NSPoint(x: x + tw + sp + off, y: gy + off))
                }
            case .blGlyphTop, .blGlyphBottom:
                let total = gs.height + sp + (text.isEmpty ? 0 : th)
                var y = r.minY + ((r.height - total) / 2).rounded(.down)
                let gx = r.minX + ((r.width - gs.width) / 2).rounded(.down)
                if layoutGlyph == .blGlyphTop {
                    Draw.image(en ? g.normal : g.disabled, at: NSPoint(x: gx, y: y))
                    y += gs.height + sp
                    TextDraw.draw(text, in: NSRect(x: r.minX, y: y, width: r.width, height: th), font: f, color: color, align: .center, accel: false)
                } else {
                    TextDraw.draw(text, in: NSRect(x: r.minX, y: y, width: r.width, height: th), font: f, color: color, align: .center, accel: false)
                    Draw.image(en ? g.normal : g.disabled, at: NSPoint(x: gx, y: y + th + sp))
                }
            }
        } else {
            TextDraw.draw(caption, in: r.insetBy(dx: 2, dy: 0), font: f, color: color, align: .center, layout: .center,
                          wordWrap: wordWrap)
        }
    }

    open override func loaded() {
        if let g = pendingGlyph { glyph = TGlyph(data: g, numGlyphs: numGlyphs); pendingGlyph = nil }
        if glyph == nil, kind != "bkCustom" { applyKind() }
    }

    func applyKind() {
        let map: [String: (String, String, TModalResult)] = [
            "bkOK": ("BBOK", "OK", mrOk), "bkCancel": ("BBCANCEL", "Cancel", mrCancel),
            "bkYes": ("BBYES", "&Yes", mrYes), "bkNo": ("BBNO", "&No", mrNo), "bkIgnore": ("BBIGNORE", "&Ignore", mrIgnore),
            "bkRetry": ("BBRETRY", "&Retry", mrRetry), "bkAbort": ("BBABORT", "Abort", mrAbort),
            "bkClose": ("BBCLOSE", "&Close", mrNone), "bkHelp": ("BBHELP", "&Help", mrNone), "bkAll": ("BBALL", "&All", mrAll),
        ]
        guard let (res, cap, mr) = map[kind] else { return }
        if let img = Resources.bitmapGlyph(res) { glyph = img }
        if caption.isEmpty { caption = cap }
        if modalResult == mrNone { modalResult = mr }
        if kind == "bkOK" || kind == "bkYes" { isDefault = true }
        if kind == "bkCancel" || kind == "bkNo" { isCancel = true }
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "ModalResult":
            switch value {
            case .int(let i): modalResult = i
            case .ident(let s):
                let m = ["mrNone": 0, "mrOk": 1, "mrCancel": 2, "mrAbort": 3, "mrRetry": 4, "mrIgnore": 5, "mrYes": 6,
                         "mrNo": 7, "mrAll": 8, "mrNoToAll": 9, "mrYesToAll": 10]
                modalResult = m[s] ?? 0
            default: break
            }
        case "Default": isDefault = value.boolValue ?? false
        case "Cancel": isCancel = value.boolValue ?? false
        case "Glyph.Data": if case .binary(let b) = value { pendingGlyph = b }
        case "NumGlyphs": numGlyphs = value.intValue ?? 1
        case "Layout": layoutGlyph = TButtonLayout(rawValue: value.stringValue ?? "") ?? .blGlyphLeft
        case "Spacing": spacing = value.intValue ?? 4
        case "Margin": margin = value.intValue ?? -1
        case "Kind": kind = value.stringValue ?? "bkCustom"
        case "WordWrap": wordWrap = value.boolValue ?? false
        case "Style", "HotTrackGlyph.Data", "DropDownMenu", "ForceSameSize", "Flat", "IsFocused": break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

public typealias TBitBtn = TButton

// MARK: - TSpeedButton / TJvSpeedButton

open class TSpeedButton: TButton {
    public var flat = false
    public var groupIndex = 0
    public var allowAllUp = false
    public var down = false {
        didSet {
            if down != oldValue {
                needsDisplay = true
                if down && groupIndex > 0, let p = superview {
                    for case let b as TSpeedButton in p.subviews where b !== self && b.groupIndex == groupIndex { b.down = false }
                }
            }
        }
    }

    open override func click() {
        if groupIndex > 0 {
            if down && allowAllUp { down = false } else if !down { down = true }
        }
        super.click()
    }

    open override func actionChanged(_ a: TAction) {
        super.actionChanged(a)
        if groupIndex > 0 { down = a.checked }
    }

    open override func draw(_ dirtyRect: NSRect) {
        let en = effectiveEnabled
        let pressed = (mouseIsDown && mouseInside && en) || down
        if flat {
            if pressed {
                Draw.fill(bounds, Theme.pressedFill)
                Draw.frame(bounds, Theme.pressedBorder)
            } else if mouseInside && en {
                Draw.fill(bounds, Theme.hoverFill)
                Draw.frame(bounds, Theme.hoverBorder)
            } else if !transparent && color != clBtnFace {
                Draw.fill(bounds, nsColor)
            }
        } else {
            ButtonFace.draw(bounds, enabled: en, hover: mouseInside && en, pressed: pressed, isDefault: false)
        }
        drawContent(in: bounds, enabled: en)
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "Flat": flat = value.boolValue ?? false
        case "GroupIndex": groupIndex = value.intValue ?? 0
        case "AllowAllUp": allowAllUp = value.boolValue ?? false
        case "Down": down = value.boolValue ?? false
        case "MarkDropDown", "HintColor", "DropDownMenu": break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

// MARK: - TCheckBox / TJvCheckBox

open class TCheckBox: TControl {
    public var checked = false {
        didSet {
            if checked != oldValue {
                needsDisplay = true
                if !loading && !suppressClick { onClick?(self) }
            }
        }
    }
    public var alignmentLeftText = false
    public var wordWrap = false
    public var autoSize = false
    var loading = true
    /// Programmatic changes in VCL also fire OnClick; ClicksDisabled suppresses it.
    public var suppressClick = false

    public required init(frame: NSRect) {
        super.init(frame: frame)
        color = clBtnFace
    }

    public required init?(coder: NSCoder) { fatalError() }

    open override var wantsHover: Bool { true }
    open override var clickOnMouseUp: Bool { true }

    open override func click() {
        if let a = action, onClick == nil {
            a.execute()
            return
        }
        checked.toggle()
    }

    /// Sets Checked without firing OnClick.
    public func setChecked(_ v: Bool) {
        suppressClick = true
        checked = v
        suppressClick = false
    }

    open override func actionChanged(_ a: TAction) {
        super.actionChanged(a)
        setChecked(a.checked)
    }

    open override func loaded() { loading = false }

    open override func draw(_ dirtyRect: NSRect) {
        paintBackground()
        let en = effectiveEnabled
        let box: CGFloat = 13
        let by = ((bounds.height - box) / 2).rounded(.down)
        let bx: CGFloat = alignmentLeftText ? bounds.width - box : 0
        let br = NSRect(x: bx, y: by, width: box, height: box)
        Draw.fill(br, en ? (mouseIsDown && mouseInside ? Colors.hex(0xCCE4F7) : .white) : Colors.hex(0xF0F0F0))
        Draw.frame(br, en ? ((mouseInside || mouseIsDown) ? Theme.hoverBorder : Theme.checkBorder) : Colors.hex(0xCCCCCC))
        if checked {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: bx + 3, y: by + 6.5))
            p.line(to: NSPoint(x: bx + 5.5, y: by + 9))
            p.line(to: NSPoint(x: bx + 10, y: by + 3.5))
            (en ? Theme.checkBorder : Colors.hex(0xCCCCCC)).setStroke()
            p.lineWidth = 1.6
            p.stroke()
        }
        let tx: CGFloat = alignmentLeftText ? 0 : box + 4
        let tr = NSRect(x: tx, y: 0, width: bounds.width - box - 4, height: bounds.height)
        TextDraw.draw(caption, in: tr, font: font.nsFont, color: en ? Colors.ns(font.color) : Theme.disabledText,
                      align: alignmentLeftText ? .right : .left, layout: .center, wordWrap: wordWrap)
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "Checked": checked = value.boolValue ?? false
        case "State": checked = value.stringValue == "cbChecked"
        case "Alignment": alignmentLeftText = value.stringValue == "taLeftJustify"
        case "WordWrap": wordWrap = value.boolValue ?? false
        case "AutoSize": autoSize = value.boolValue ?? false
        case "LinkedControls", "AllowGrayed", "LeftText", "HotTrack": break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

// MARK: - TRadioButton

open class TRadioButton: TCheckBox {
    open override func click() {
        if !checked { checked = true }
        if let p = superview {
            for case let r as TRadioButton in p.subviews where r !== self { r.setChecked(false) }
        }
    }

    open override func draw(_ dirtyRect: NSRect) {
        paintBackground()
        let en = effectiveEnabled
        let d: CGFloat = 13
        let y = ((bounds.height - d) / 2).rounded(.down)
        let c = NSBezierPath(ovalIn: NSRect(x: 0.5, y: y + 0.5, width: d - 1, height: d - 1))
        NSColor.white.setFill()
        c.fill()
        (en ? ((mouseInside || mouseIsDown) ? Theme.hoverBorder : Theme.checkBorder) : Colors.hex(0xCCCCCC)).setStroke()
        c.lineWidth = 1
        c.stroke()
        if checked {
            let dot = NSBezierPath(ovalIn: NSRect(x: 3.5, y: y + 3.5, width: 6, height: 6))
            (en ? Theme.checkBorder : Colors.hex(0xCCCCCC)).setFill()
            dot.fill()
        }
        TextDraw.draw(caption, in: NSRect(x: d + 4, y: 0, width: bounds.width - d - 4, height: bounds.height), font: font.nsFont,
                      color: en ? Colors.ns(font.color) : Theme.disabledText, layout: .center, wordWrap: wordWrap)
    }
}

// MARK: - TRadioGroup / TJvRadioGroup

open class TRadioGroup: TGroupBox {
    public var items: [String] = [] { didSet { rebuild() } }
    public var columns = 1 { didSet { rebuild() } }
    public var itemIndex: Int = -1 {
        didSet {
            if itemIndex != oldValue {
                for (i, b) in buttons.enumerated() { b.setChecked(i == itemIndex) }
                if !loadingRG && !suppressClick { onClick?(self) }
            }
        }
    }
    var buttons: [TRadioButton] = []
    var loadingRG = true
    var suppressClick = false

    public func setItemIndex(_ i: Int) {
        suppressClick = true
        itemIndex = i
        suppressClick = false
    }

    func rebuild() {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = []
        guard !items.isEmpty else { return }
        let r = NSRect(x: 8, y: captionHeight, width: bounds.width - 16, height: bounds.height - captionHeight - 4)
        let cols = max(1, columns)
        let rows = (items.count + cols - 1) / cols
        let colW = r.width / CGFloat(cols)
        let rowH = r.height / CGFloat(max(1, rows))
        for (i, s) in items.enumerated() {
            let col = i / rows, row = i % rows
            let b = TRadioButton(frame: NSRect(x: r.minX + CGFloat(col) * colW, y: r.minY + (CGFloat(row) * rowH).rounded(),
                                               width: colW, height: max(17, rowH.rounded())))
            b.caption = s
            b.font.assign(font)
            b.color = color
            b.loading = false
            b.root = root
            b.onClick = { [weak self, weak b] _ in
                guard let self, let b, let idx = self.buttons.firstIndex(where: { $0 === b }) else { return }
                if b.checked { self.itemIndex = idx }
            }
            b.setChecked(i == itemIndex)
            b.enabled = enabled
            addSubview(b)
            buttons.append(b)
        }
    }

    open override func resized() {
        super.resized()
        if !loadingRG { rebuild() }
    }

    open override func enabledChanged() {
        super.enabledChanged()
        for b in buttons { b.enabled = enabled }
    }

    open override func loaded() {
        loadingRG = false
        rebuild()
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "Items.Strings": if case .list(let l) = value { items = l.compactMap(\.stringValue) }
        case "Columns": columns = value.intValue ?? 1
        case "ItemIndex": itemIndex = value.intValue ?? -1
        case "CaptionVisible": captionVisible = value.boolValue ?? true
        case "ReadOnly", "EdgeInner", "EdgeOuter": break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}
