import AppKit

// MARK: - Basic VCL types

public typealias TColor = Int32

public enum TAlign: String { case alNone, alTop, alBottom, alLeft, alRight, alClient, alCustom }

public struct TAnchors: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let akLeft = TAnchors(rawValue: 1)
    public static let akTop = TAnchors(rawValue: 2)
    public static let akRight = TAnchors(rawValue: 4)
    public static let akBottom = TAnchors(rawValue: 8)
    public static let `default`: TAnchors = [.akLeft, .akTop]
}

public struct TFontStyles: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let fsBold = TFontStyles(rawValue: 1)
    public static let fsItalic = TFontStyles(rawValue: 2)
    public static let fsUnderline = TFontStyles(rawValue: 4)
    public static let fsStrikeOut = TFontStyles(rawValue: 8)
}

public struct TShiftState: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let ssShift = TShiftState(rawValue: 1)
    public static let ssAlt = TShiftState(rawValue: 2)
    public static let ssCtrl = TShiftState(rawValue: 4)
    public static let ssLeft = TShiftState(rawValue: 8)
    public static let ssRight = TShiftState(rawValue: 16)
    public static let ssMiddle = TShiftState(rawValue: 32)
    public static let ssDouble = TShiftState(rawValue: 64)

    public init(_ flags: NSEvent.ModifierFlags) {
        var s: TShiftState = []
        if flags.contains(.shift) { s.insert(.ssShift) }
        if flags.contains(.option) { s.insert(.ssAlt) }
        if flags.contains(.command) || flags.contains(.control) { s.insert(.ssCtrl) }
        self = s
    }
}

public enum TMouseButton: Int { case mbLeft, mbRight, mbMiddle }

public typealias TModalResult = Int
public let mrNone = 0, mrOk = 1, mrCancel = 2, mrAbort = 3, mrRetry = 4, mrIgnore = 5, mrYes = 6, mrNo = 7,
           mrAll = 8, mrNoToAll = 9, mrYesToAll = 10

public enum TTextAlignment { case left, right, center }
public enum TTextLayout { case top, center, bottom }

// MARK: - Colours

public let clBlack: TColor = 0x000000, clMaroon: TColor = 0x000080, clGreen: TColor = 0x008000, clOlive: TColor = 0x008080,
           clNavy: TColor = 0x800000, clPurple: TColor = 0x800080, clTeal: TColor = 0x808000, clGray: TColor = 0x808080,
           clSilver: TColor = 0xC0C0C0, clRed: TColor = 0x0000FF, clLime: TColor = 0x00FF00, clYellow: TColor = 0x00FFFF,
           clBlue: TColor = 0xFF0000, clFuchsia: TColor = 0xFF00FF, clAqua: TColor = 0xFFFF00, clWhite: TColor = 0xFFFFFF,
           clMoneyGreen: TColor = 0xC0DCC0, clSkyBlue: TColor = 0xF0CAA6, clCream: TColor = 0xF0FBFF, clMedGray: TColor = 0xA4A0A0
public let clNone: TColor = 0x1FFFFFFF, clDefault: TColor = 0x20000000

private func sys(_ i: Int32) -> TColor { TColor(bitPattern: 0xFF000000 | UInt32(i)) }
public let clScrollBar = sys(0), clBackground = sys(1), clActiveCaption = sys(2), clInactiveCaption = sys(3),
           clMenu = sys(4), clWindow = sys(5), clWindowFrame = sys(6), clMenuText = sys(7), clWindowText = sys(8),
           clCaptionText = sys(9), clActiveBorder = sys(10), clInactiveBorder = sys(11), clAppWorkSpace = sys(12),
           clHighlight = sys(13), clHighlightText = sys(14), clBtnFace = sys(15), clBtnShadow = sys(16),
           clGrayText = sys(17), clBtnText = sys(18), clInactiveCaptionText = sys(19), clBtnHighlight = sys(20),
           cl3DDkShadow = sys(21), cl3DLight = sys(22), clInfoText = sys(23), clInfoBk = sys(24), clHotLight = sys(26),
           clGradientActiveCaption = sys(27), clGradientInactiveCaption = sys(28), clMenuHighlight = sys(29),
           clMenuBar = sys(30)

public enum Colors {
    /// Windows 10 system colours (GetSysColor) as seen by the original program.
    static let system: [Int32: UInt32] = [
        0: 0xC8C8C8, 1: 0x000000, 2: 0x99B4D1, 3: 0xBFCDDB, 4: 0xF0F0F0, 5: 0xFFFFFF, 6: 0x646464, 7: 0x000000,
        8: 0x000000, 9: 0x000000, 10: 0xB4B4B4, 11: 0xF4F7FC, 12: 0xABABAB, 13: 0x0078D7, 14: 0xFFFFFF,
        15: 0xF0F0F0, 16: 0xA0A0A0, 17: 0x6D6D6D, 18: 0x000000, 19: 0x000000, 20: 0xFFFFFF, 21: 0x696969,
        22: 0xE3E3E3, 23: 0x000000, 24: 0xFFFFE1, 26: 0x0066CC, 27: 0xB9D1EA, 28: 0xD7E4F2, 29: 0x3399FF,
        30: 0xF0F0F0,
    ]

    static let names: [String: TColor] = [
        "clBlack": clBlack, "clMaroon": clMaroon, "clGreen": clGreen, "clOlive": clOlive, "clNavy": clNavy,
        "clPurple": clPurple, "clTeal": clTeal, "clGray": clGray, "clSilver": clSilver, "clRed": clRed,
        "clLime": clLime, "clYellow": clYellow, "clBlue": clBlue, "clFuchsia": clFuchsia, "clAqua": clAqua,
        "clWhite": clWhite, "clMoneyGreen": clMoneyGreen, "clSkyBlue": clSkyBlue, "clCream": clCream,
        "clMedGray": clMedGray, "clNone": clNone, "clDefault": clDefault,
        "clScrollBar": clScrollBar, "clBackground": clBackground, "clActiveCaption": clActiveCaption,
        "clInactiveCaption": clInactiveCaption, "clMenu": clMenu, "clWindow": clWindow, "clWindowFrame": clWindowFrame,
        "clMenuText": clMenuText, "clWindowText": clWindowText, "clCaptionText": clCaptionText,
        "clActiveBorder": clActiveBorder, "clInactiveBorder": clInactiveBorder, "clAppWorkSpace": clAppWorkSpace,
        "clHighlight": clHighlight, "clHighlightText": clHighlightText, "clBtnFace": clBtnFace,
        "clBtnShadow": clBtnShadow, "clGrayText": clGrayText, "clBtnText": clBtnText,
        "clInactiveCaptionText": clInactiveCaptionText, "clBtnHighlight": clBtnHighlight, "cl3DDkShadow": cl3DDkShadow,
        "cl3DLight": cl3DLight, "clInfoText": clInfoText, "clInfoBk": clInfoBk, "clHotLight": clHotLight,
        "clGradientActiveCaption": clGradientActiveCaption, "clGradientInactiveCaption": clGradientInactiveCaption,
        "clMenuHighlight": clMenuHighlight, "clMenuBar": clMenuBar,
    ]

    public static func value(_ v: DFMValue) -> TColor? {
        switch v {
        case .int(let i): return TColor(truncatingIfNeeded: i)
        case .ident(let s): return names[s]
        default: return nil
        }
    }

    /// ColorToRGB: 0x00BBGGRR.
    public static func rgb(_ c: TColor) -> UInt32 {
        let u = UInt32(bitPattern: c)
        if u & 0xFF000000 == 0xFF000000 {
            let v = system[Int32(u & 0xFF)] ?? 0
            return (v >> 16) & 0xFF | (v & 0xFF00) | (v & 0xFF) << 16
        }
        return u & 0xFFFFFF
    }

    public static func ns(_ c: TColor) -> NSColor {
        let v = rgb(c)
        return NSColor(srgbRed: CGFloat(v & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat((v >> 16) & 0xFF) / 255, alpha: 1)
    }

    /// 0xRRGGBB literal.
    public static func hex(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    public static func fromRGB(_ r: Int, _ g: Int, _ b: Int) -> TColor { TColor(r | g << 8 | b << 16) }
}

/// Windows 10 visual style colours used by the themed controls.
public enum Theme {
    public static let face = Colors.hex(0xF0F0F0)
    public static let text = Colors.hex(0x000000)
    public static let disabledText = Colors.hex(0x838383)
    public static let buttonFill = Colors.hex(0xE1E1E1)
    public static let buttonBorder = Colors.hex(0xADADAD)
    public static let hoverFill = Colors.hex(0xE5F1FB)
    public static let hoverBorder = Colors.hex(0x0078D7)
    public static let pressedFill = Colors.hex(0xCCE4F7)
    public static let pressedBorder = Colors.hex(0x005499)
    public static let disabledFill = Colors.hex(0xCCCCCC)
    public static let disabledBorder = Colors.hex(0xBFBFBF)
    public static let editBorder = Colors.hex(0x7A7A7A)
    public static let editHoverBorder = Colors.hex(0x171717)
    public static let comboBorder = Colors.hex(0xACACAC)
    public static let groupBorder = Colors.hex(0xDCDCDC)
    public static let tabBorder = Colors.hex(0xD9D9D9)
    public static let tabHover = Colors.hex(0xD8EAF9)
    public static let tabHoverBorder = Colors.hex(0x7EB4EA)
    public static let selection = Colors.hex(0x0078D7)
    public static let scrollTrack = Colors.hex(0xF0F0F0)
    public static let scrollThumb = Colors.hex(0xCDCDCD)
    public static let scrollThumbHover = Colors.hex(0xA6A6A6)
    public static let scrollThumbPressed = Colors.hex(0x606060)
    public static let scrollArrow = Colors.hex(0x606060)
    public static let scrollArrowHoverBack = Colors.hex(0xDADADA)
    public static let checkBorder = Colors.hex(0x333333)
    public static let gridLine = Colors.hex(0xF0F0F0)
}

// MARK: - Fonts

public final class TFont: NSObject {
    public var name: String = "Tahoma" { didSet { changed() } }
    /// Delphi Font.Height: negative = character height in pixels.
    public var height: Int = -11 { didSet { changed() } }
    public var style: TFontStyles = [] { didSet { changed() } }
    public var color: TColor = clWindowText { didSet { changed() } }
    public var onChange: (() -> Void)?

    public override init() { super.init() }

    public init(name: String, height: Int, style: TFontStyles = [], color: TColor = clWindowText) {
        self.name = name
        self.height = height
        self.style = style
        self.color = color
        super.init()
    }

    public var size: Int {
        get { Int((Double(-height) * 72 / 96).rounded()) }
        set { height = -Int((Double(newValue) * 96 / 72).rounded()) }
    }

    public func assign(_ f: TFont) {
        name = f.name
        height = f.height
        style = f.style
        color = f.color
    }

    public func copy() -> TFont { TFont(name: name, height: height, style: style, color: color) }

    private func changed() {
        cached = nil
        onChange?()
    }

    private var cached: NSFont?

    /// The AppKit font (1 Windows pixel = 1 point).
    public var nsFont: NSFont {
        if let c = cached { return c }
        let f = TFont.make(name: name, height: height, style: style)
        cached = f
        return f
    }

    static func postScriptName(_ name: String, bold: Bool, italic: Bool) -> [String] {
        switch name.lowercased() {
        case "tahoma": return bold ? ["Tahoma-Bold"] : ["Tahoma"]
        case "arial":
            if bold && italic { return ["Arial-BoldItalicMT"] }
            return bold ? ["Arial-BoldMT"] : (italic ? ["Arial-ItalicMT"] : ["ArialMT"])
        case "courier new":
            if bold && italic { return ["CourierNewPS-BoldItalicMT"] }
            return bold ? ["CourierNewPS-BoldMT"] : (italic ? ["CourierNewPS-ItalicMT"] : ["CourierNewPSMT"])
        case "courier": return bold ? ["Courier-Bold"] : ["Courier"]
        case "ms sans serif", "microsoft sans serif": return bold ? ["Tahoma-Bold"] : ["MicrosoftSansSerif"]
        case "verdana": return bold ? ["Verdana-Bold"] : ["Verdana"]
        case "wingdings": return ["Wingdings-Regular"]
        case "terminal": return bold ? ["Menlo-Bold"] : ["Menlo-Regular"]
        case "segoe ui": return []
        default: return [name]
        }
    }

    /// Pixel size used by AppKit for a Delphi font height.
    static func pointSize(_ font: NSFont, height: Int) -> CGFloat {
        if height < 0 { return CGFloat(-height) }
        // positive height = cell height (ascent + descent)
        let cell = font.ascender - font.descender
        return CGFloat(height) * font.pointSize / max(cell, 1)
    }

    public static func make(name: String, height: Int, style: TFontStyles) -> NSFont {
        let bold = style.contains(.fsBold), italic = style.contains(.fsItalic)
        var base: NSFont?
        for ps in postScriptName(name, bold: bold, italic: italic) {
            if let f = NSFont(name: ps, size: 12) { base = f; break }
        }
        let f0 = base ?? (bold ? NSFont.boldSystemFont(ofSize: 12) : NSFont.systemFont(ofSize: 12))
        let size = pointSize(f0, height: height == 0 ? -11 : height)
        var f = NSFont(descriptor: f0.fontDescriptor, size: size) ?? f0
        if italic && !(f.fontDescriptor.symbolicTraits.contains(.italic)) {
            f = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask)
        }
        return f
    }

    public static var defaultFont: TFont { TFont(name: "Tahoma", height: -11) }
    /// Windows 10 message/menu font (Segoe UI 9pt) – the closest macOS font is the system font.
    public static var messageFont: NSFont { NSFont.systemFont(ofSize: 12) }
}

// MARK: - Text

public enum TextDraw {
    /// Removes Windows accelerator markers ("&File" -> "File", "&&" -> "&").
    public static func stripAccel(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var it = s.makeIterator()
        while let c = it.next() {
            if c == "&" {
                if let n = it.next() { out.append(n) }
            } else { out.append(c) }
        }
        return out
    }

    public static func ascent(_ f: NSFont) -> CGFloat { f.ascender.rounded() }
    public static func lineHeight(_ f: NSFont) -> CGFloat { f.ascender.rounded() + (-f.descender).rounded() }

    public static func attributes(_ font: NSFont, _ color: NSColor, underline: Bool = false, strike: Bool = false) -> [NSAttributedString.Key: Any] {
        var a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if underline { a[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if strike { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return a
    }

    public static func width(_ s: String, _ f: NSFont) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: f]).width
    }

    /// Splits text into lines like DrawText with DT_WORDBREAK.
    public static func wrap(_ s: String, _ f: NSFont, width: CGFloat) -> [String] {
        var lines: [String] = []
        for para in s.components(separatedBy: "\n") {
            let p = para.replacingOccurrences(of: "\r", with: "")
            if width <= 0 || TextDraw.width(p, f) <= width { lines.append(p); continue }
            var cur = ""
            for word in p.split(separator: " ", omittingEmptySubsequences: false) {
                let w = String(word)
                let cand = cur.isEmpty ? w : cur + " " + w
                if TextDraw.width(cand, f) <= width || cur.isEmpty {
                    cur = cand
                } else {
                    lines.append(cur)
                    cur = w
                }
            }
            lines.append(cur)
        }
        return lines
    }

    /// Draws text like DrawText (flipped view coordinates). Returns the used height.
    @discardableResult
    public static func draw(_ text: String, in r: NSRect, font: NSFont, color: NSColor,
                            align: TTextAlignment = .left, layout: TTextLayout = .top,
                            wordWrap: Bool = false, singleLine: Bool = false, accel: Bool = true,
                            underline: Bool = false, strike: Bool = false, ellipsis: Bool = false) -> CGFloat {
        let s = accel ? stripAccel(text) : text
        let lh = lineHeight(font)
        var lines = singleLine ? [s.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: " ")]
            : (wordWrap ? wrap(s, font, width: r.width) : s.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n"))
        if lines.isEmpty { lines = [""] }
        let total = lh * CGFloat(lines.count)
        var y: CGFloat
        switch layout {
        case .top: y = r.minY
        case .center: y = r.minY + ((r.height - total) / 2).rounded(.down)
        case .bottom: y = r.maxY - total
        }
        let attrs = attributes(font, color, underline: underline, strike: strike)
        for line in lines {
            var l = line
            if ellipsis && width(l, font) > r.width {
                while !l.isEmpty && width(l + "...", font) > r.width { l.removeLast() }
                l += "..."
            }
            let w = width(l, font)
            var x: CGFloat
            switch align {
            case .left: x = r.minX
            case .center: x = r.minX + ((r.width - w) / 2).rounded(.down)
            case .right: x = r.maxX - w
            }
            // NSString drawing in a flipped view puts the top of the line box at y; align the baseline
            // to y + rounded ascent like GDI.
            let shift = ascent(font) - font.ascender
            (l as NSString).draw(at: NSPoint(x: x, y: y + shift), withAttributes: attrs)
            y += lh
        }
        return total
    }
}

// MARK: - Drawing helpers

public enum Draw {
    public static func fill(_ r: NSRect, _ c: NSColor) {
        c.setFill()
        r.fill()
    }

    /// 1 px frame inside r.
    public static func frame(_ r: NSRect, _ c: NSColor) {
        c.setFill()
        NSRect(x: r.minX, y: r.minY, width: r.width, height: 1).fill()
        NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1).fill()
        NSRect(x: r.minX, y: r.minY, width: 1, height: r.height).fill()
        NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height).fill()
    }

    public static func hline(_ x0: CGFloat, _ x1: CGFloat, _ y: CGFloat, _ c: NSColor) {
        c.setFill()
        NSRect(x: x0, y: y, width: x1 - x0, height: 1).fill()
    }

    public static func vline(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat, _ c: NSColor) {
        c.setFill()
        NSRect(x: x, y: y0, width: 1, height: y1 - y0).fill()
    }

    /// Frame3D (VCL ExtCtrls): top/left in `tl`, bottom/right in `br`.
    public static func frame3D(_ r: NSRect, _ tl: NSColor, _ br: NSColor) {
        hline(r.minX, r.maxX - 1, r.minY, tl)
        vline(r.minX, r.minY, r.maxY - 1, tl)
        hline(r.minX, r.maxX, r.maxY - 1, br)
        vline(r.maxX - 1, r.minY, r.maxY, br)
    }

    public static func roundRect(_ r: NSRect, radius: CGFloat, fill: NSColor?, stroke: NSColor?) {
        let p = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        if let f = fill { f.setFill(); p.fill() }
        if let s = stroke { s.setStroke(); p.lineWidth = 1; p.stroke() }
    }

    /// Small chevron used by combo boxes and scroll bars.
    public static func chevron(center c: NSPoint, size: CGFloat, direction: Int, color: NSColor, width: CGFloat = 1) {
        // direction: 0 down, 1 up, 2 left, 3 right
        let p = NSBezierPath()
        let h = size / 2
        switch direction {
        case 0: p.move(to: NSPoint(x: c.x - h, y: c.y - h / 2)); p.line(to: NSPoint(x: c.x, y: c.y + h / 2)); p.line(to: NSPoint(x: c.x + h, y: c.y - h / 2))
        case 1: p.move(to: NSPoint(x: c.x - h, y: c.y + h / 2)); p.line(to: NSPoint(x: c.x, y: c.y - h / 2)); p.line(to: NSPoint(x: c.x + h, y: c.y + h / 2))
        case 2: p.move(to: NSPoint(x: c.x + h / 2, y: c.y - h)); p.line(to: NSPoint(x: c.x - h / 2, y: c.y)); p.line(to: NSPoint(x: c.x + h / 2, y: c.y + h))
        default: p.move(to: NSPoint(x: c.x - h / 2, y: c.y - h)); p.line(to: NSPoint(x: c.x + h / 2, y: c.y)); p.line(to: NSPoint(x: c.x - h / 2, y: c.y + h))
        }
        color.setStroke()
        p.lineWidth = width
        p.stroke()
    }

    public static func image(_ img: NSImage, at p: NSPoint, enabled: Bool = true) {
        let r = NSRect(origin: p, size: img.size)
        NSGraphicsContext.current?.imageInterpolation = .none
        img.draw(in: r, from: .zero, operation: .sourceOver, fraction: enabled ? 1 : 0.35, respectFlipped: true, hints: nil)
    }
}
