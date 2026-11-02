import AppKit

// MARK: - TScrollBar / TJvScrollBar (Windows 10 look)

open class TScrollBar: TControl {
    public var min = 0 { didSet { clamp() } }
    public var max = 100 { didSet { clamp() } }
    public var position = 0 {
        didSet {
            if position != oldValue {
                needsDisplay = true
                if !loadingSB { onChange?(self) }
            }
        }
    }
    public var pageSize = 0 { didSet { needsDisplay = true } }
    public var smallChange = 1
    public var largeChange = 1
    public var vertical = false
    public var onScroll: ((TObject, Int) -> Void)?
    var loadingSB = true

    private enum Part { case none, arrowLow, arrowHigh, trackLow, trackHigh, thumb }
    private var pressed: Part = .none
    private var hoverPart: Part = .none
    private var repeatTimer: Timer?
    private var dragOffset: CGFloat = 0

    public required init(frame: NSRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { fatalError() }

    open override var wantsHover: Bool { true }

    func clamp() {
        let hi = Swift.max(min, max - Swift.max(pageSize - 1, 0))
        if position < min { position = min }
        if position > hi { position = hi }
        needsDisplay = true
    }

    /// Sets the position without firing OnChange.
    public func setPositionSilently(_ p: Int) {
        let saved = loadingSB
        loadingSB = true
        position = p
        loadingSB = saved
    }

    public func setParams(position p: Int, min mn: Int, max mx: Int) {
        let saved = loadingSB
        loadingSB = true
        min = mn
        max = mx
        loadingSB = saved
        position = Swift.min(Swift.max(p, mn), mx)
    }

    var length: CGFloat { vertical ? bounds.height : bounds.width }
    var thickness: CGFloat { vertical ? bounds.width : bounds.height }
    var arrow: CGFloat { Swift.min(thickness, length / 2).rounded(.down) }
    var trackLength: CGFloat { length - 2 * arrow }

    var thumbLength: CGFloat {
        let range = CGFloat(max - min + 1)
        var t: CGFloat
        if pageSize > 0 && range > 0 { t = trackLength * CGFloat(pageSize) / range } else { t = thickness }
        return Swift.max(Swift.min(t.rounded(), trackLength), Swift.min(8, trackLength))
    }

    var thumbStart: CGFloat {
        let hi = Swift.max(min, max - Swift.max(pageSize - 1, 0))
        let span = CGFloat(hi - min)
        let free = trackLength - thumbLength
        let frac = span > 0 ? CGFloat(position - min) / span : 0
        return arrow + (free * frac).rounded()
    }

    func rect(along a: CGFloat, _ len: CGFloat) -> NSRect {
        vertical ? NSRect(x: 0, y: a, width: bounds.width, height: len) : NSRect(x: a, y: 0, width: len, height: bounds.height)
    }

    private func part(at p: NSPoint) -> Part {
        let v = vertical ? p.y : p.x
        if v < arrow { return .arrowLow }
        if v >= length - arrow { return .arrowHigh }
        let ts = thumbStart
        if v < ts { return .trackLow }
        if v >= ts + thumbLength { return .trackHigh }
        return .thumb
    }

    open override func draw(_ dirtyRect: NSRect) {
        let en = effectiveEnabled && max > min
        Draw.fill(bounds, Theme.scrollTrack)
        // arrows
        for (pt, a, dir) in [(Part.arrowLow, CGFloat(0), vertical ? 1 : 2), (Part.arrowHigh, length - arrow, vertical ? 0 : 3)] {
            let r = rect(along: a, arrow)
            var c = en ? Theme.scrollArrow : Colors.hex(0xBFBFBF)
            if en && pressed == pt && hoverPart == pt { Draw.fill(r, Theme.scrollThumbPressed); c = .white }
            else if en && hoverPart == pt { Draw.fill(r, Theme.scrollArrowHoverBack); c = .black }
            let ctr = NSPoint(x: r.midX, y: r.midY)
            drawArrow(ctr, dir: dir, color: c)
        }
        if en {
            let t = rect(along: thumbStart, thumbLength)
            let inset: CGFloat = 1
            let tr = vertical ? t.insetBy(dx: inset, dy: 0) : t.insetBy(dx: 0, dy: inset)
            let col = pressed == .thumb ? Theme.scrollThumbPressed : (mouseInside ? Theme.scrollThumbHover : Theme.scrollThumb)
            Draw.fill(tr, col)
        }
    }

    func drawArrow(_ c: NSPoint, dir: Int, color: NSColor) {
        // filled small triangle like Windows 10 scroll bar glyphs
        let p = NSBezierPath()
        let s: CGFloat = Swift.min(4, (thickness / 4).rounded())
        switch dir {
        case 0: p.move(to: NSPoint(x: c.x - s, y: c.y - s / 2)); p.line(to: NSPoint(x: c.x + s, y: c.y - s / 2)); p.line(to: NSPoint(x: c.x, y: c.y + s / 2 + 0.5))
        case 1: p.move(to: NSPoint(x: c.x - s, y: c.y + s / 2)); p.line(to: NSPoint(x: c.x + s, y: c.y + s / 2)); p.line(to: NSPoint(x: c.x, y: c.y - s / 2 - 0.5))
        case 2: p.move(to: NSPoint(x: c.x + s / 2, y: c.y - s)); p.line(to: NSPoint(x: c.x + s / 2, y: c.y + s)); p.line(to: NSPoint(x: c.x - s / 2 - 0.5, y: c.y))
        default: p.move(to: NSPoint(x: c.x - s / 2, y: c.y - s)); p.line(to: NSPoint(x: c.x - s / 2, y: c.y + s)); p.line(to: NSPoint(x: c.x + s / 2 + 0.5, y: c.y))
        }
        p.close()
        color.setFill()
        p.fill()
    }

    private func stepFor(_ p: Part) {
        switch p {
        case .arrowLow: setPos(position - smallChange)
        case .arrowHigh: setPos(position + smallChange)
        case .trackLow: setPos(position - largeChange)
        case .trackHigh: setPos(position + largeChange)
        default: break
        }
    }

    func setPos(_ v: Int) {
        let hi = Swift.max(min, max - Swift.max(pageSize - 1, 0))
        let nv = Swift.min(Swift.max(v, min), hi)
        onScroll?(self, nv)
        position = nv
    }

    open override func mouseDown(with event: NSEvent) {
        guard effectiveEnabled, max > min else { return }
        Application.shared.cancelHint()
        let p = convert(event.locationInWindow, from: nil)
        pressed = part(at: p)
        hoverPart = pressed
        mouseIsDown = true
        if pressed == .thumb {
            dragOffset = (vertical ? p.y : p.x) - thumbStart
        } else {
            stepFor(pressed)
            let pt = pressed
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                    guard let self, self.hoverPart == pt else { return }
                    if pt == .trackLow || pt == .trackHigh {
                        let now = self.part(at: self.lastPoint)
                        if now != pt { return }
                    }
                    self.stepFor(pt)
                }
            }
        }
        lastPoint = p
        needsDisplay = true
        onMouseDown?(self, .mbLeft, TShiftState(event.modifierFlags), Int(p.x), Int(p.y))
    }

    private var lastPoint = NSPoint.zero

    open override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        lastPoint = p
        if pressed == .thumb {
            let free = trackLength - thumbLength
            let hi = Swift.max(min, max - Swift.max(pageSize - 1, 0))
            let a = (vertical ? p.y : p.x) - dragOffset - arrow
            let frac = free > 0 ? Swift.min(Swift.max(a / free, 0), 1) : 0
            setPos(min + Int((frac * CGFloat(hi - min)).rounded()))
        } else {
            let h = part(at: p)
            hoverPart = bounds.contains(p) && (h == pressed) ? pressed : .none
            needsDisplay = true
        }
    }

    open override func mouseUp(with event: NSEvent) {
        repeatTimer?.invalidate()
        repeatTimer = nil
        let wasPressed = pressed != .none
        pressed = .none
        mouseIsDown = false
        hoverPart = .none
        needsDisplay = true
        if wasPressed {
            let p = convert(event.locationInWindow, from: nil)
            onMouseUp?(self, .mbLeft, TShiftState(event.modifierFlags), Int(p.x), Int(p.y))
        }
    }

    open override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let p = convert(event.locationInWindow, from: nil)
        let h = part(at: p)
        let newHover: Part = (h == .arrowLow || h == .arrowHigh) ? h : .none
        if newHover != hoverPart { hoverPart = newHover; needsDisplay = true }
    }

    open override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hoverPart = .none
        needsDisplay = true
    }

    open override func scrollWheel(with event: NSEvent) {
        guard effectiveEnabled else { return }
        let d = vertical ? event.scrollingDeltaY : (abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? -event.scrollingDeltaX : event.scrollingDeltaY)
        if d > 0.5 { setPos(position - smallChange) } else if d < -0.5 { setPos(position + smallChange) }
    }

    open override func loaded() { loadingSB = false }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "Min": min = value.intValue ?? 0
        case "Max": max = value.intValue ?? 100
        case "Position": position = value.intValue ?? 0
        case "PageSize": pageSize = value.intValue ?? 0
        case "SmallChange": smallChange = value.intValue ?? 1
        case "LargeChange": largeChange = value.intValue ?? 1
        case "Kind": vertical = value.stringValue == "sbVertical"
        case "OnScroll": loader.event(value) { [weak self] h in self?.onScroll = { s, _ in h(s) } }
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}

// MARK: - TTrackBar / TJvTrackBar

open class TTrackBar: TControl {
    public var min = 0
    public var max = 10
    public var position = 0 {
        didSet {
            if position != oldValue {
                needsDisplay = true
                if !loadingTB { onChange?(self) }
            }
        }
    }
    public var frequency = 1
    public var pageSize = 2
    public var vertical = false
    public var tickMarks = "tmBottomRight"
    public var thumbLength = 20
    public var selStart = 0, selEnd = 0
    var loadingTB = true
    private var dragging = false

    public required init(frame: NSRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { fatalError() }

    open override var wantsHover: Bool { true }

    public func setPositionSilently(_ p: Int) {
        let s = loadingTB
        loadingTB = true
        position = p
        loadingTB = s
    }

    var channelInset: CGFloat { 13 }
    var usable: CGFloat { (vertical ? bounds.height : bounds.width) - 2 * channelInset }

    func coord(_ v: Int) -> CGFloat {
        let span = CGFloat(Swift.max(1, max - min))
        return channelInset + usable * CGFloat(v - min) / span
    }

    open override func draw(_ dirtyRect: NSRect) {
        paintBackground()
        let en = effectiveEnabled
        let tl = CGFloat(Swift.min(thumbLength, Int(vertical ? bounds.width : bounds.height) - 4))
        if vertical {
            let cx = (bounds.width / 2).rounded(.down)
            let ch = NSRect(x: cx - 2, y: channelInset - 4, width: 4, height: usable + 8)
            Draw.fill(ch, Colors.hex(0xE7EAEA))
            Draw.frame(ch, Colors.hex(0xD6D6D6))
            if tickMarks != "tmNone" && frequency > 0 {
                var v = min
                while v <= max {
                    Draw.hline(cx + tl / 2 + 2, cx + tl / 2 + 5, coord(v).rounded(), Colors.hex(0xC4C4C4))
                    v += frequency
                }
            }
            let ty = coord(position)
            let thumb = NSRect(x: cx - tl / 2, y: ty - 5, width: tl, height: 11)
            Draw.fill(thumb, en ? (dragging ? Colors.hex(0xCCCCCC) : (mouseInside ? Colors.hex(0x171717) : Colors.hex(0x007AD9))) : Colors.hex(0xCCCCCC))
        } else {
            let cy = (bounds.height / 2).rounded(.down) - (tickMarks == "tmBottomRight" ? 2 : 0)
            let ch = NSRect(x: channelInset - 4, y: cy - 2, width: usable + 8, height: 4)
            Draw.fill(ch, Colors.hex(0xE7EAEA))
            Draw.frame(ch, Colors.hex(0xD6D6D6))
            if tickMarks != "tmNone" && frequency > 0 {
                var v = min
                while v <= max {
                    let x = coord(v).rounded()
                    if tickMarks == "tmBottomRight" || tickMarks == "tmBoth" { Draw.vline(x, cy + tl / 2 + 2, cy + tl / 2 + 5, Colors.hex(0xC4C4C4)) }
                    if tickMarks == "tmTopLeft" || tickMarks == "tmBoth" { Draw.vline(x, cy - tl / 2 - 5, cy - tl / 2 - 2, Colors.hex(0xC4C4C4)) }
                    v += frequency
                }
            }
            let tx = coord(position)
            let thumb = NSRect(x: tx - 5, y: cy - tl / 2, width: 11, height: tl)
            Draw.fill(thumb, en ? (dragging ? Colors.hex(0xCCCCCC) : (mouseInside ? Colors.hex(0x171717) : Colors.hex(0x007AD9))) : Colors.hex(0xCCCCCC))
        }
    }

    func value(at p: NSPoint) -> Int {
        let a = (vertical ? p.y : p.x) - channelInset
        let frac = usable > 0 ? Swift.min(Swift.max(a / usable, 0), 1) : 0
        return min + Int((frac * CGFloat(max - min)).rounded())
    }

    open override func mouseDown(with event: NSEvent) {
        guard effectiveEnabled else { return }
        Application.shared.cancelHint()
        let p = convert(event.locationInWindow, from: nil)
        let tc = coord(position)
        let a = vertical ? p.y : p.x
        if abs(a - tc) <= 6 {
            dragging = true
        } else {
            position = Swift.min(Swift.max(position + (a < tc ? -pageSize : pageSize), min), max)
        }
        needsDisplay = true
        onMouseDown?(self, .mbLeft, TShiftState(event.modifierFlags), Int(p.x), Int(p.y))
    }

    open override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        position = value(at: convert(event.locationInWindow, from: nil))
    }

    open override func mouseUp(with event: NSEvent) {
        dragging = false
        needsDisplay = true
        let p = convert(event.locationInWindow, from: nil)
        onMouseUp?(self, .mbLeft, TShiftState(event.modifierFlags), Int(p.x), Int(p.y))
    }

    open override func scrollWheel(with event: NSEvent) {
        guard effectiveEnabled else { return }
        if event.scrollingDeltaY > 0.5 { position = Swift.max(min, position - 1) } else if event.scrollingDeltaY < -0.5 { position = Swift.min(max, position + 1) }
    }

    open override func loaded() { loadingTB = false }

    open override func setDFMProperty(_ name: String, _ value: DFMValue, _ loader: DFMLoader) -> Bool {
        switch name {
        case "Min": min = value.intValue ?? 0
        case "Max": max = value.intValue ?? 10
        case "Position": position = value.intValue ?? 0
        case "Frequency": frequency = value.intValue ?? 1
        case "PageSize": pageSize = value.intValue ?? 2
        case "Orientation": vertical = value.stringValue == "trVertical"
        case "TickMarks": tickMarks = value.stringValue ?? "tmBottomRight"
        case "TickStyle": if value.stringValue == "tsNone" { tickMarks = "tmNone" }
        case "ThumbLength": thumbLength = value.intValue ?? 20
        case "SelStart": selStart = value.intValue ?? 0
        case "SelEnd": selEnd = value.intValue ?? 0
        case "ShowSelRange", "PositionToolTip", "ShowRange", "ToolTipSide", "ToolTips", "SliderVisible": break
        default: return super.setDFMProperty(name, value, loader)
        }
        return true
    }
}
