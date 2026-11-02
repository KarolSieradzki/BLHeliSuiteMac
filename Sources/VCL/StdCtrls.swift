import AppKit

func parseAlignment(_ v: DFMValue) -> TTextAlignment {
    switch v.stringValue {
    case "taRightJustify": return .right
    case "taCenter": return .center
    default: return .left
    }
}

func parseLayout(_ v: DFMValue) -> TTextLayout {
    switch v.stringValue {
    case "tlCenter": return .center
    case "tlBottom": return .bottom
    default: return .top
    }
}

// MARK: - TLabel / TJvLabel

open class TLabel: TControl {
    public var alignment: TTextAlignment = .left { didSet { needsDisplay = true } }
    public var layout: TTextLayout = .top { didSet { needsDisplay = true } }
    public var autoSize = true
    public var wordWrap = false { didSet { adjustBounds() } }
    public var showAccelChar = true
    /// TJvLabel.RoundedFrame (corner radius) and FrameColor.
    public var roundedFrame = 0 { didSet { needsDisplay = true } }
    public var frameColor: TColor = clNone { didSet { needsDisplay = true } }
    public var focusControl: TControl?
    var isJv = false

    public required init(frame: NSRect) {
        super.init(frame: frame)
        transparent = false
    }

    public required init?(coder: NSCoder) { fatalError() }

    open override var clickOnMouseUp: Bool { onClick != nil }

    open override func captionChanged() {
        adjustBounds()
        needsDisplay = true
    }

    open override func fontChanged() {
        super.fontChanged()
        adjustBounds()
    }

    /// TCustomLabel.AdjustBounds.
    public func adjustBounds() {
        guard autoSize, !loading else { return }
        let f = font.nsFont
        let text = showAccelChar ? TextDraw.stripAccel(caption) : caption
        var w: CGFloat, h: CGFloat
        if wordWrap {
            w = frame.width
            let lines = TextDraw.wrap(text.isEmpty ? " " : text, f, width: w)
            h = TextDraw.lineHeight(f) * CGFloat(lines.count)
        } else {
            let lines = (text.isEmpty ? " " : text).components(separatedBy: "\n")
            w = (lines.map { TextDraw.width($0, f) }.max() ?? 0).rounded(.up)
            h = TextDraw.lineHeight(f) * CGFloat(lines.count)
        }
        var x = frame.minX
        if alignment == .right && !wordWrap { x = frame.maxX - w }
        if alignment == .center && !wordWrap { x = frame.midX - w / 2 }
        let r = NSRect(x: x.rounded(), y: frame.minY, width: w, height: h)
        if r != frame { frame = r; needsDisplay = true }
    }

    var loading = true

    open override func loaded() {
        loading = false
    }

    open override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let hasFrame = roundedFrame > 0 || frameColor != clNone
        if !transparent {
            if roundedFrame > 0 {
                let p = NSBezierPath(roundedRect: r, xRadius: CGFloat(roundedFrame), yRadius: CGFloat(roundedFrame))
                nsColor.setFill()
                p.fill()
            } else {
                Draw.fill(r, nsColor)
            }
        }
        if frameColor != clNone {
            if roundedFrame > 0 {
                Draw.roundRect(r, radius: CGFloat(roundedFrame), fill: nil, stroke: Colors.ns(frameColor))
            } else {
                Draw.frame(r, Colors.ns(frameColor))
            }
        }
        var tr = r
        if hasFrame && isJv { tr = r.insetBy(dx: 1, dy: 0) }
        let color = effectiveEnabled ? Colors.ns(font.color) : Colors.ns(clGrayText)
        TextDraw.draw(caption, in: tr, font: font.nsFont, color: color, align: alignment, layout: layout,
                      wordWrap: wordWrap, accel: showAccelChar,
                      underline: font.style.contains(.fsUnderline), strike: font.style.contains(.fsStrikeOut))
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "Alignment": alignment = parseAlignment(value)
        case "Layout": layout = parseLayout(value)
        case "AutoSize": autoSize = value.boolValue ?? true
        case "WordWrap": wordWrap = value.boolValue ?? false
        case "ShowAccelChar": showAccelChar = value.boolValue ?? true
        case "RoundedFrame": roundedFrame = value.intValue ?? 0
        case "FrameColor": frameColor = Colors.value(value) ?? clNone
        case "FocusControl": loader.fixup(value) { [weak self] (c: TControl) in self?.focusControl = c }
        case "Spacing", "Angle", "ShadowSize", "ShadowColor", "ShadowPos", "HotTrack", "Images", "ImageIndex",
             "Margin", "TextEllipsis", "Provider": break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

// MARK: - TPanel / TJvPanel

public enum TBevelCut: String { case bvNone, bvLowered, bvRaised, bvSpace }

open class TPanel: TControl {
    public var bevelOuter: TBevelCut = .bvRaised { didSet { needsDisplay = true } }
    public var bevelInner: TBevelCut = .bvNone { didSet { needsDisplay = true } }
    public var bevelWidth = 1
    public var borderWidth = 0
    public var borderStyleSingle = false
    public var flatBorder = false
    public var flatBorderColor: TColor = clBtnShadow
    public var alignment: TTextAlignment = .center
    public var verticalLayout: TTextLayout = .center
    public var showCaption = true
    /// AutoSize: the panel takes the height of its vertically stacked children (alTop / alBottom / alNone),
    /// e.g. the feature panels of the fuse editor whose unused check boxes have Height = 0.
    public var autoSize = false
    private var autoSizing = false

    public required init(frame: NSRect) {
        super.init(frame: frame)
        color = clBtnFace
    }

    open override func realign() {
        super.realign()
        guard autoSize, !autoSizing else { return }
        let kids = controls.filter { !$0.isHidden }
        guard !kids.isEmpty, !kids.contains(where: { [.alLeft, .alRight, .alClient].contains($0.align) }) else { return }
        var bottom: CGFloat = 0
        for c in kids { bottom = max(bottom, c.frame.maxY + (c.alignWithMargins ? c.margins.bottom : 0)) }
        let h = Int((bottom + bevelInset).rounded())
        if h != height {
            autoSizing = true
            height = h
            autoSizing = false
        }
    }

    public required init?(coder: NSCoder) { fatalError() }

    var bevelInset: CGFloat {
        var n: CGFloat = CGFloat(borderWidth)
        if flatBorder { return n + 1 }
        if bevelOuter != .bvNone { n += CGFloat(bevelWidth) }
        if bevelInner != .bvNone { n += CGFloat(bevelWidth) }
        if borderStyleSingle { n += 1 }
        return n
    }

    open override var alignRect: NSRect { bounds.insetBy(dx: bevelInset, dy: bevelInset) }

    open override func draw(_ dirtyRect: NSRect) {
        paintBackground()
        var r = bounds
        if borderStyleSingle { Draw.frame(r, Colors.ns(clWindowFrame)); r = r.insetBy(dx: 1, dy: 1) }
        if flatBorder {
            Draw.frame(r, Colors.ns(flatBorderColor))
        } else {
            func bevel(_ cut: TBevelCut) {
                switch cut {
                case .bvRaised: Draw.frame3D(r, Colors.ns(clBtnHighlight), Colors.ns(clBtnShadow))
                case .bvLowered: Draw.frame3D(r, Colors.ns(clBtnShadow), Colors.ns(clBtnHighlight))
                default: break
                }
                if cut != .bvNone { r = r.insetBy(dx: CGFloat(bevelWidth), dy: CGFloat(bevelWidth)) }
            }
            bevel(bevelOuter)
            r = r.insetBy(dx: CGFloat(borderWidth), dy: CGFloat(borderWidth))
            bevel(bevelInner)
        }
        if showCaption && !caption.isEmpty {
            TextDraw.draw(caption, in: r, font: font.nsFont, color: textColor, align: alignment, layout: verticalLayout)
        }
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "BevelOuter": bevelOuter = TBevelCut(rawValue: value.stringValue ?? "") ?? .bvRaised
        case "BevelInner": bevelInner = TBevelCut(rawValue: value.stringValue ?? "") ?? .bvNone
        case "BevelWidth": bevelWidth = value.intValue ?? 1
        case "BorderWidth": borderWidth = value.intValue ?? 0
        case "BorderStyle": borderStyleSingle = value.stringValue == "bsSingle"
        case "FlatBorder": flatBorder = value.boolValue ?? false
        case "FlatBorderColor": flatBorderColor = Colors.value(value) ?? clBtnShadow
        case "Alignment": alignment = parseAlignment(value)
        case "VerticalAlignment": break
        case "ShowCaption": showCaption = value.boolValue ?? true
        case "AutoSize": autoSize = value.boolValue ?? false
        case "BevelEdges", "BevelKind", "FullRepaint", "Locked", "Layout", "MultiLine", "HotTrack",
             "Sizeable", "Movable", "ArrangeSettings.AutoArrange", "Transparent":
            break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

// MARK: - TGroupBox / TJvGroupBox

open class TGroupBox: TControl {
    public var captionVisible = true

    public required init(frame: NSRect) {
        super.init(frame: frame)
        color = clBtnFace
    }

    public required init?(coder: NSCoder) { fatalError() }

    var captionHeight: CGFloat { TextDraw.lineHeight(font.nsFont) }

    open override var alignRect: NSRect {
        var r = bounds
        r.origin.y += captionHeight
        r.size.height -= captionHeight
        return r.insetBy(dx: 2, dy: 2)
    }

    open override func draw(_ dirtyRect: NSRect) {
        paintBackground()
        let f = font.nsFont
        let th = captionHeight
        let lineY = (th / 2).rounded(.down)
        let box = NSRect(x: 0, y: lineY, width: bounds.width, height: bounds.height - lineY)
        Draw.frame(box, Theme.groupBorder)
        let text = TextDraw.stripAccel(caption)
        if captionVisible && !text.isEmpty {
            let w = TextDraw.width(text, f).rounded(.up)
            let cr = NSRect(x: 6, y: 0, width: min(w + 4, bounds.width - 12), height: th)
            Draw.fill(cr, nsColor)
            let color = effectiveEnabled ? Colors.ns(font.color) : Colors.ns(clGrayText)
            TextDraw.draw(text, in: NSRect(x: 8, y: 0, width: cr.width, height: th), font: f, color: color, accel: false)
        }
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "PropagateEnable": propagateEnable = value.boolValue ?? false
        case "CaptionVisible": captionVisible = value.boolValue ?? true
        case "Checkable", "Checked", "OnCheckBoxClick": break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

// MARK: - TBevel

open class TBevel: TControl {
    public var shape = "bsBox"
    public var lowered = true

    public required init(frame: NSRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { fatalError() }

    open override func draw(_ dirtyRect: NSRect) {
        let c1 = Colors.ns(lowered ? clBtnShadow : clBtnHighlight)
        let c2 = Colors.ns(lowered ? clBtnHighlight : clBtnShadow)
        let r = bounds
        switch shape {
        case "bsBox": Draw.frame3D(r, c1, c2)
        case "bsFrame":
            Draw.frame3D(r.insetBy(dx: 0, dy: 0), c1, c2)
            Draw.frame3D(r.insetBy(dx: 1, dy: 1), c2, c1)
        case "bsTopLine": Draw.hline(0, r.width, 0, c1); Draw.hline(0, r.width, 1, c2)
        case "bsBottomLine": Draw.hline(0, r.width, r.height - 2, c1); Draw.hline(0, r.width, r.height - 1, c2)
        case "bsLeftLine": Draw.vline(0, 0, r.height, c1); Draw.vline(1, 0, r.height, c2)
        case "bsRightLine": Draw.vline(r.width - 2, 0, r.height, c1); Draw.vline(r.width - 1, 0, r.height, c2)
        default: break
        }
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "Shape": shape = value.stringValue ?? "bsBox"
        case "Style": lowered = value.stringValue != "bsRaised"
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

// MARK: - TImage

open class TImage: TControl {
    public var picture: NSImage? { didSet { needsDisplay = true } }
    var pictureBitmap: RGBABitmap?
    public var stretch = false
    public var proportional = false
    public var center = false
    public var autoSize = false

    public required init(frame: NSRect) {
        super.init(frame: frame)
        transparent = false
    }

    public required init?(coder: NSCoder) { fatalError() }

    open override var clickOnMouseUp: Bool { onClick != nil }

    open override func draw(_ dirtyRect: NSRect) {
        guard let img = picture else { return }
        NSGraphicsContext.current?.imageInterpolation = (stretch || proportional) ? .high : .none
        var r = NSRect(origin: .zero, size: img.size)
        if stretch || (proportional && (img.size.width > bounds.width || img.size.height > bounds.height)) {
            if proportional {
                let s = min(bounds.width / img.size.width, bounds.height / img.size.height)
                r.size = NSSize(width: (img.size.width * s).rounded(), height: (img.size.height * s).rounded())
                if center { r.origin = NSPoint(x: ((bounds.width - r.width) / 2).rounded(), y: ((bounds.height - r.height) / 2).rounded()) }
            } else {
                r = bounds
            }
        } else if center {
            r.origin = NSPoint(x: ((bounds.width - r.width) / 2).rounded(), y: ((bounds.height - r.height) / 2).rounded())
        }
        img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    /// Loads Picture.Data.
    public func loadPicture(_ data: [UInt8]) {
        let p = DIB.pictureProperty(data)
        if var b = p.bitmap {
            if transparent { b = b.keyedTransparent() } else { b = b.opaque() }
            pictureBitmap = b
            picture = b.image
        } else if !p.data.isEmpty, let img = NSImage(data: Data(p.data)) {
            picture = img
        }
    }

    var pendingPicture: [UInt8]?

    open override func loaded() {
        if let p = pendingPicture { loadPicture(p); pendingPicture = nil }
        if autoSize, let img = picture { frame.size = img.size }
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "Picture.Data": if case .binary(let b) = value { pendingPicture = b }
        case "Stretch": stretch = value.boolValue ?? false
        case "Proportional": proportional = value.boolValue ?? false
        case "Center": center = value.boolValue ?? false
        case "AutoSize": autoSize = value.boolValue ?? false
        case "IsControl", "IncrementalDisplay": break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

// MARK: - TJvStaticText

open class TStaticText: TLabel {
    public var borderStyle = "sbsNone"
    public var textMargins = NSPoint(x: 0, y: 0)

    open override func draw(_ dirtyRect: NSRect) {
        var r = bounds
        if !transparent { Draw.fill(r, nsColor) }
        switch borderStyle {
        case "sbsSingle": Draw.frame(r, Colors.ns(clWindowFrame)); r = r.insetBy(dx: 1, dy: 1)
        case "sbsSunken": Draw.frame3D(r, Colors.ns(clBtnShadow), Colors.ns(clBtnHighlight)); r = r.insetBy(dx: 1, dy: 1)
        default: break
        }
        r = r.insetBy(dx: textMargins.x, dy: textMargins.y)
        TextDraw.draw(caption, in: r, font: font.nsFont, color: textColor, align: alignment, layout: layout, wordWrap: wordWrap)
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "BorderStyle": borderStyle = value.stringValue ?? "sbsNone"
        case "TextMargins.X": textMargins.x = CGFloat(value.intValue ?? 0)
        case "TextMargins.Y": textMargins.y = CGFloat(value.intValue ?? 0)
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }

    public required init(frame: NSRect) {
        super.init(frame: frame)
        autoSize = false
    }

    public required init?(coder: NSCoder) { fatalError() }
}

// MARK: - TLed (BLHeliSuite's own LED component)

open class TLed: TControl {
    public var isOn = false { didSet { if isOn != oldValue { needsDisplay = true } } }
    public var colorOn: TColor = clLime
    public var colorOff: TColor = 14607076
    public var intVal = 0

    public required init(frame: NSRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { fatalError() }

    open override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let p = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)
        Colors.ns(isOn ? colorOn : colorOff).setFill()
        p.fill()
        Colors.ns(clGray).setStroke()
        p.lineWidth = 1
        p.stroke()
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "_On": isOn = value.boolValue ?? false
        case "ColorOn": colorOn = Colors.value(value) ?? clLime
        case "ColorOff": colorOff = Colors.value(value) ?? 14607076
        case "IntVal": intVal = value.intValue ?? 0
        case "Size", "Shape": break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

// MARK: - TGauge

open class TGauge: TControl {
    public var minValue = 0, maxValue = 100
    public var progress = 0 { didSet { if progress != oldValue { needsDisplay = true } } }
    public var foreColor: TColor = clBlack
    public var backColor: TColor = clWhite
    public var showText = true
    public var borderSingle = true
    /// Kind = gkVerticalBar: filled from the bottom.
    public var vertical = false { didSet { needsDisplay = true } }

    public required init(frame: NSRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { fatalError() }

    public var percentDone: Int {
        guard maxValue > minValue else { return 0 }
        return Int((Double(progress - minValue) / Double(maxValue - minValue) * 100).rounded(.down))
    }

    open override func draw(_ dirtyRect: NSRect) {
        var r = bounds
        if borderSingle { Draw.frame(r, Colors.ns(clBlack)); r = r.insetBy(dx: 1, dy: 1) }
        Draw.fill(r, Colors.ns(backColor))
        let frac = maxValue > minValue ? CGFloat(progress - minValue) / CGFloat(maxValue - minValue) : 0
        let fill: NSRect
        if vertical {
            let h = (r.height * max(0, min(1, frac))).rounded()
            fill = NSRect(x: r.minX, y: r.maxY - h, width: r.width, height: h)
        } else {
            fill = NSRect(x: r.minX, y: r.minY, width: (r.width * max(0, min(1, frac))).rounded(), height: r.height)
        }
        Draw.fill(fill, Colors.ns(foreColor))
        if showText {
            let s = "\(percentDone)%"
            let f = font.nsFont
            // text inverted over the bar
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: fill).setClip()
            TextDraw.draw(s, in: r, font: f, color: Colors.ns(backColor), align: .center, layout: .center)
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: vertical ? NSRect(x: r.minX, y: r.minY, width: r.width, height: fill.minY - r.minY)
                                        : NSRect(x: fill.maxX, y: r.minY, width: r.maxX - fill.maxX, height: r.height)).setClip()
            TextDraw.draw(s, in: r, font: f, color: Colors.ns(foreColor), align: .center, layout: .center)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "MinValue": minValue = value.intValue ?? 0
        case "MaxValue": maxValue = value.intValue ?? 100
        case "Progress": progress = value.intValue ?? 0
        case "ForeColor": foreColor = Colors.value(value) ?? clBlack
        case "BackColor": backColor = Colors.value(value) ?? clWhite
        case "ShowText": showText = value.boolValue ?? true
        case "BorderStyle": borderSingle = value.stringValue != "bsNone"
        case "Kind": vertical = value.stringValue == "gkVerticalBar"
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

// MARK: - TJvGradient

open class TGradient: TControl {
    public var startColor: TColor = clBlue
    public var endColor: TColor = clBlack
    public var vertical = false

    public required init(frame: NSRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { fatalError() }

    open override func draw(_ dirtyRect: NSRect) {
        let g = NSGradient(starting: Colors.ns(startColor), ending: Colors.ns(endColor))
        g?.draw(in: bounds, angle: vertical ? 90 : 0)
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "StartColor": startColor = Colors.value(value) ?? clBlue
        case "EndColor": endColor = Colors.value(value) ?? clBlack
        case "Style": vertical = value.stringValue == "grVertical"
        case "Steps": break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

// MARK: - TJvCaptionPanel

open class TCaptionPanel: TPanel {
    public var captionColor: TColor = clActiveCaption
    public let captionFont = TFont(name: "Tahoma", height: -11, style: [.fsBold], color: clWhite)
    public var captionHeight = 0
    public var captionPosition = "dpLeft"

    open override var alignRect: NSRect {
        var r = bounds.insetBy(dx: bevelInset, dy: bevelInset)
        let h = CGFloat(captionHeight > 0 ? captionHeight : Int(TextDraw.lineHeight(captionFont.nsFont)) + 4)
        switch captionPosition {
        case "dpTop": r.origin.y += h; r.size.height -= h
        case "dpLeft": r.origin.x += h; r.size.width -= h
        case "dpRight": r.size.width -= h
        case "dpBottom": r.size.height -= h
        default: break
        }
        return r
    }

    open override func draw(_ dirtyRect: NSRect) {
        let saved = showCaption
        showCaption = false
        super.draw(dirtyRect)
        showCaption = saved
        let inner = bounds.insetBy(dx: bevelInset, dy: bevelInset)
        let h = CGFloat(captionHeight > 0 ? captionHeight : Int(TextDraw.lineHeight(captionFont.nsFont)) + 4)
        var cr = inner
        switch captionPosition {
        case "dpTop": cr.size.height = h
        case "dpLeft": cr.size.width = h
        case "dpRight": cr.origin.x = inner.maxX - h; cr.size.width = h
        case "dpBottom": cr.origin.y = inner.maxY - h; cr.size.height = h
        default: break
        }
        Draw.fill(cr, Colors.ns(captionColor))
        let text = TextDraw.stripAccel(caption)
        if captionPosition == "dpLeft" || captionPosition == "dpRight" {
            NSGraphicsContext.saveGraphicsState()
            let t = NSAffineTransform()
            t.translateX(by: cr.minX, yBy: cr.maxY)
            t.rotate(byDegrees: -90)
            t.concat()
            TextDraw.draw(text, in: NSRect(x: 4, y: 0, width: cr.height - 8, height: cr.width), font: captionFont.nsFont,
                          color: Colors.ns(captionFont.color), layout: .center, accel: false)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            TextDraw.draw(text, in: cr.insetBy(dx: 4, dy: 0), font: captionFont.nsFont, color: Colors.ns(captionFont.color),
                          layout: .center, accel: false)
        }
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "CaptionColor": captionColor = Colors.value(value) ?? clActiveCaption
        case "CaptionFont.Name": captionFont.name = value.stringValue ?? "Tahoma"
        case "CaptionFont.Height": captionFont.height = value.intValue ?? -11
        case "CaptionFont.Color": captionFont.color = Colors.value(value) ?? clWhite
        case "CaptionFont.Style":
            var s: TFontStyles = []
            if case .set(let items) = value { if items.contains("fsBold") { s.insert(.fsBold) }; if items.contains("fsItalic") { s.insert(.fsItalic) } }
            captionFont.style = s
        case "CaptionHeight": captionHeight = value.intValue ?? 0
        case "CaptionPosition": captionPosition = value.stringValue ?? "dpLeft"
        case "CaptionFont.Charset", "Buttons", "FlatButtons", "OutlookLook", "Resizable", "AutoDrag", "Icon.Data",
             "CaptionOffsetSmall", "CaptionOffsetLarge":
            break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

// MARK: - TJvItemsPanel

open class TItemsPanel: TPanel {
    public var items: [String] = [] { didSet { needsDisplay = true } }
    public var itemHeight = 16
    public var hotTrack = false
    public var hotIndex = -1
    public var onItemClick: ((TObject, Int) -> Void)?

    open override var wantsHover: Bool { hotTrack }

    open override func draw(_ dirtyRect: NSRect) {
        let saved = showCaption
        showCaption = false
        super.draw(dirtyRect)
        showCaption = saved
        let inner = alignRect
        for (i, s) in items.enumerated() {
            let r = NSRect(x: inner.minX, y: inner.minY + CGFloat(i * itemHeight), width: inner.width, height: CGFloat(itemHeight))
            if i == hotIndex && hotTrack { Draw.frame3D(r, Colors.ns(clBtnHighlight), Colors.ns(clBtnShadow)) }
            TextDraw.draw(s, in: r.insetBy(dx: 4, dy: 0), font: font.nsFont, color: textColor, align: alignment, layout: .center)
        }
    }

    open override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let (_, y) = localPoint(event)
        let i = (y - Int(alignRect.minY)) / max(1, itemHeight)
        let n = (i >= 0 && i < items.count) ? i : -1
        if n != hotIndex { hotIndex = n; needsDisplay = true }
    }

    open override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hotIndex = -1
    }

    open override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        let (_, y) = localPoint(event)
        let i = (y - Int(alignRect.minY)) / max(1, itemHeight)
        if i >= 0 && i < items.count { onItemClick?(self, i) }
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "Items.Strings": if case .list(let l) = value { items = l.compactMap(\.stringValue) }
        case "ItemHeight": itemHeight = value.intValue ?? 16
        case "HotTrack": hotTrack = value.boolValue ?? false
        case "AutoGrow", "Clickable", "Orientation": break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

// MARK: - TJvSwitch

open class TSwitch: TControl {
    public var stateOn = false { didSet { needsDisplay = true } }
    public var onOn: TNotifyEvent?
    public var onOff: TNotifyEvent?

    public required init(frame: NSRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { fatalError() }

    open override var clickOnMouseUp: Bool { true }

    open override func click() {
        stateOn.toggle()
        if stateOn { onOn?(self) } else { onOff?(self) }
        onClick?(self)
    }

    open override func draw(_ dirtyRect: NSRect) {
        let r = NSRect(x: 0, y: 0, width: min(bounds.width, 40), height: min(bounds.height, 20))
        Draw.roundRect(r, radius: r.height / 2, fill: stateOn ? Theme.selection : Colors.hex(0xFFFFFF), stroke: stateOn ? Theme.selection : Theme.checkBorder)
        let d = r.height - 8
        let x = stateOn ? r.maxX - d - 4 : r.minX + 4
        let knob = NSBezierPath(ovalIn: NSRect(x: x, y: r.minY + 4, width: d, height: d))
        (stateOn ? NSColor.white : Theme.checkBorder).setFill()
        knob.fill()
        if !caption.isEmpty {
            TextDraw.draw(caption, in: NSRect(x: r.maxX + 4, y: 0, width: bounds.width - r.maxX - 4, height: bounds.height),
                          font: font.nsFont, color: textColor, layout: .center)
        }
    }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "StateOn": stateOn = value.boolValue ?? false
        case "OnOn": loader.event(value) { [weak self] h in self?.onOn = h }
        case "OnOff": loader.event(value) { [weak self] h in self?.onOff = h }
        case "Data", "TextPosition", "ToggleKey", "Glyph.Data", "GlyphOff.Data", "GlyphOn.Data": break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}
