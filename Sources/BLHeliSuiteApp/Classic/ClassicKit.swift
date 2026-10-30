import SwiftUI
import AppKit

// Windows look-alike controls for the classic BLHeliSuite UI. Sizes are Windows pixels
// (96 dpi) = macOS points, positions come from the original Delphi forms (DFM).

enum Win {
    static func rgb(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static let face = rgb(0xF0F0F0)          // clBtnFace
    static let window = Color.white          // clWindow
    static let text = Color.black            // clWindowText
    static let disabledText = rgb(0x838383)
    static let grayText = rgb(0x808080)      // clGray
    static let silver = rgb(0xC0C0C0)        // clSilver
    static let shadow = rgb(0xA0A0A0)        // clBtnShadow
    static let darkShadow = rgb(0x696969)
    static let buttonFill = rgb(0xE1E1E1)
    static let buttonBorder = rgb(0xADADAD)
    static let hoverFill = rgb(0xE5F1FB)
    static let hoverBorder = rgb(0x0078D7)
    static let pressedFill = rgb(0xCCE4F7)
    static let pressedBorder = rgb(0x005499)
    static let disabledFill = rgb(0xCCCCCC)
    static let disabledBorder = rgb(0xBFBFBF)
    static let editBorder = rgb(0x7A7A7A)
    static let comboBorder = rgb(0xACACAC)
    static let groupBorder = rgb(0xDCDCDC)
    static let tabBorder = rgb(0xD9D9D9)
    static let tabHover = rgb(0xD8EAF9)
    static let tabHoverBorder = rgb(0x7EB4EA)
    static let selection = rgb(0x0078D7)
    static let infoBk = rgb(0xFFFFE1)        // clInfoBk
    static let cream = rgb(0xFFFBF0)         // clCream
    static let skyBlue = rgb(0xA6CAF0)       // clSkyBlue
    static let navy = rgb(0x000080)
    static let blue = rgb(0x0000FF)
    static let green = rgb(0x008000)
    static let lime = rgb(0x00FF00)
    static let red = rgb(0xFF0000)
    static let orange = rgb(0xFF8000)
    static let purple = rgb(0x800080)
    static let maroon = rgb(0x7E1245)        // SiLabs brand colour (4526718)
    static let atmelBlue = rgb(0x1F5FA8)
    static let badgeYellow = rgb(0xFFFF80)   // 8454143
    static let badgeBlue = rgb(0xD3E5F8)     // 16311507
    static let valueFill = rgb(0xB0D8FF)     // value label background (screenshots)
    static let ledFill = rgb(0x808080)
    static let menuHover = rgb(0xE5F3FF)
    static let menuHoverBorder = rgb(0xCCE8FF)
    static let menuOpen = rgb(0xCCE8FF)
    static let menuOpenBorder = rgb(0x99D1FF)

    static func tahoma(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "Tahoma-Bold" : "Tahoma", size: size)
    }
    static func courierNew(_ size: CGFloat) -> Font { .custom("CourierNewPS-BoldMT", size: size) }
    static func courier(_ size: CGFloat) -> Font { .custom("Courier-Bold", size: size) }
    static func arial(_ size: CGFloat) -> Font { .custom("Arial-BoldMT", size: size) }
    static let nsMenuFont = NSFont(name: "Tahoma", size: 11) ?? NSFont.menuFont(ofSize: 11)
}

// MARK: - Images extracted from BLHeliSuite.exe

@MainActor
enum ClassicImage {
    private static var cache: [String: NSImage] = [:]

    static func named(_ name: String) -> NSImage? {
        if let c = cache[name] { return c }
        guard let s = ClassicAssets.png[name], let d = Data(base64Encoded: s), let img = NSImage(data: d) else { return nil }
        cache[name] = img
        return img
    }
}

/// Pixel exact image (no smoothing – keeps the 16×16 glyphs crisp on Retina screens).
struct Glyph: View {
    let name: String
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        if let img = ClassicImage.named(name) {
            Image(nsImage: img)
                .interpolation(.none)
                .saturation(enabled ? 1 : 0)
                .opacity(enabled ? 1 : 0.4)
        }
    }
}

// MARK: - Absolute (Delphi style) layout

struct Abs: Layout {
    var width: CGFloat
    var height: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for s in subviews {
            let r = s[AbsRect.self]
            s.place(at: CGPoint(x: bounds.minX + r.minX, y: bounds.minY + r.minY), anchor: .topLeading,
                    proposal: ProposedViewSize(width: r.width, height: r.height))
        }
    }
}

private struct AbsRect: LayoutValueKey {
    static let defaultValue = CGRect.zero
}

extension View {
    /// Places the view inside an `Abs` container (Left, Top, Width, Height like in the DFM).
    func at(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> some View {
        frame(width: w, height: h, alignment: .topLeading)
            .layoutValue(key: AbsRect.self, value: CGRect(x: x, y: y, width: w, height: h))
    }
}

// MARK: - Bevels

/// TPanel style bevel line (raised: light top/left, dark bottom/right).
struct Bevel: View {
    var raised = true
    var inset: CGFloat = 0

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, i = inset + 0.5
            Path { p in
                p.move(to: CGPoint(x: i, y: h - i))
                p.addLine(to: CGPoint(x: i, y: i))
                p.addLine(to: CGPoint(x: w - i, y: i))
            }
            .stroke(raised ? Color.white : Win.shadow, lineWidth: 1)
            Path { p in
                p.move(to: CGPoint(x: w - i, y: i))
                p.addLine(to: CGPoint(x: w - i, y: h - i))
                p.addLine(to: CGPoint(x: i, y: h - i))
            }
            .stroke(raised ? Win.shadow : Color.white, lineWidth: 1)
        }
    }
}

// MARK: - Buttons

struct WinButtonStyle: ButtonStyle {
    var isDefault = false

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, isDefault: isDefault)
    }

    struct StyledBody: View {
        let configuration: ButtonStyleConfiguration
        let isDefault: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .foregroundColor(enabled ? Win.text : Win.disabledText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Rectangle().fill(!enabled ? Win.disabledFill : pressed ? Win.pressedFill : hover ? Win.hoverFill : Win.buttonFill))
                .overlay(Rectangle().strokeBorder(!enabled ? Win.disabledBorder : pressed ? Win.pressedBorder
                                                  : (hover || isDefault) ? Win.hoverBorder : Win.buttonBorder,
                                                  lineWidth: isDefault && enabled && !hover ? 2 : 1))
                .contentShape(Rectangle())
                .onHover { hover = $0 }
        }
    }
}

/// TBitBtn: optional 16×16 glyph left of the caption.
struct WinButton: View {
    let title: String
    var glyph: String? = nil
    var font: Font = Win.tahoma(11)
    var textColor: Color? = nil
    var isDefault = false
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let g = glyph { Glyph(name: g).frame(width: 16, height: 16) }
                Text(title)
                    .font(font)
                    .foregroundColor(enabled ? (textColor ?? Win.text) : Win.disabledText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 3)
        }
        .buttonStyle(WinButtonStyle(isDefault: isDefault))
    }
}

/// Flat TSpeedButton with a glyph (Undo / Default buttons of the parameter boxes).
struct WinFlatGlyphButton: View {
    let glyph: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Glyph(name: glyph)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Rectangle().fill(hover && enabled ? Win.hoverFill : Color.clear))
                .overlay(Rectangle().strokeBorder(hover && enabled ? Win.hoverBorder : Color.clear, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Check box

struct CheckMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.38, y: r.maxY - r.height * 0.08))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.1))
        return p
    }
}

struct WinCheckBox: View {
    let title: String
    @Binding var isOn: Bool
    var font: Font = Win.tahoma(11)
    var textColor: Color = Win.text
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Rectangle().fill(enabled ? Color.white : Win.face)
                Rectangle().strokeBorder(enabled ? (hover ? Win.hoverBorder : Win.rgb(0x333333)) : Win.disabledBorder, lineWidth: 1)
                if isOn {
                    CheckMark()
                        .stroke(enabled ? Win.rgb(0x333333) : Win.disabledText, style: StrokeStyle(lineWidth: 1.6, lineCap: .square))
                        .frame(width: 8, height: 7)
                }
            }
            .frame(width: 13, height: 13)
            Text(title)
                .font(font)
                .foregroundColor(enabled ? textColor : Win.disabledText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { if enabled { isOn.toggle() } }
        .onHover { hover = $0 }
    }
}

/// Radio button (TRadioGroup item).
struct WinRadio: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle().fill(Color.white)
                Circle().strokeBorder(enabled ? Win.rgb(0x333333) : Win.disabledBorder, lineWidth: 1)
                if selected { Circle().fill(enabled ? Win.rgb(0x333333) : Win.disabledText).frame(width: 5, height: 5) }
            }
            .frame(width: 13, height: 13)
            Text(title).font(Win.tahoma(11)).foregroundColor(enabled ? Win.text : Win.disabledText)
        }
        .contentShape(Rectangle())
        .onTapGesture { if enabled { action() } }
    }
}

// MARK: - Native popup menus (combo boxes, menu bar)

final class MenuAction: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire(_ sender: Any?) { handler() }
}

enum MenuEntry {
    case item(String, image: NSImage? = nil, checked: Bool = false, enabled: Bool = true, action: () -> Void)
    case separator
    case submenu(String, image: NSImage? = nil, enabled: Bool = true, [MenuEntry])
}

@MainActor
func buildMenu(_ entries: [MenuEntry]) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.font = Win.nsMenuFont
    for e in entries {
        switch e {
        case .separator:
            menu.addItem(.separator())
        case let .item(title, image, checked, enabled, action):
            let a = MenuAction(action)
            let it = NSMenuItem(title: title, action: #selector(MenuAction.fire(_:)), keyEquivalent: "")
            it.target = a
            it.representedObject = a
            it.image = image
            it.state = checked ? .on : .off
            it.isEnabled = enabled
            menu.addItem(it)
        case let .submenu(title, image, enabled, children):
            let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            it.image = image
            it.isEnabled = enabled
            it.submenu = buildMenu(children)
            menu.addItem(it)
        }
    }
    return menu
}

/// Holds the AppKit view behind a SwiftUI control so a menu can pop up right below it.
final class MenuAnchor {
    weak var view: NSView?

    /// GUI test hook (`--uitest`): receives the menu instead of showing it.
    @MainActor static var interceptor: ((NSMenu, NSView) -> Void)?

    @MainActor
    func popUp(_ menu: NSMenu, minWidth: CGFloat? = nil) {
        guard let v = view else { return }
        if let w = minWidth { menu.minimumWidth = w }
        if let hook = Self.interceptor { hook(menu, v); return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: v.isFlipped ? v.bounds.height + 1 : -1), in: v)
    }
}

struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor
    /// Identifier of the AppKit view (lets the GUI test find e.g. the menu bar items).
    var name: String? = nil

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        anchor.view = v
        v.identifier = name.map { NSUserInterfaceItemIdentifier($0) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
        nsView.identifier = name.map { NSUserInterfaceItemIdentifier($0) }
    }
}

/// Catches right clicks only; everything else passes through to the SwiftUI view below.
struct RightClickCatcher: NSViewRepresentable {
    let action: () -> Void

    final class CatcherView: NSView {
        var action: (() -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let e = NSApp.currentEvent, e.type == .rightMouseDown || e.type == .rightMouseUp else { return nil }
            return super.hitTest(point)
        }
        override func rightMouseDown(with event: NSEvent) { action?() }
    }

    func makeNSView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.action = action
        return v
    }
    func updateNSView(_ v: CatcherView, context: Context) { v.action = action }
}

struct Chevron: Shape {
    var down = true
    func path(in r: CGRect) -> Path {
        var p = Path()
        if down {
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        } else {
            p.move(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX, y: r.midY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        }
        return p
    }
}

/// TComboBox (csDropDownList): shows the selected item, a click opens the list.
struct WinCombo<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T
    var placeholder = ""
    var font: Font = Win.tahoma(11)
    var textColor: Color = Win.text
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false
    @State private var anchor = MenuAnchor()

    var label: String { items.first { $0.0 == selection }?.1 ?? placeholder }

    var body: some View {
        GeometryReader { g in
            HStack(spacing: 0) {
                Text(label)
                    .font(font)
                    .foregroundColor(enabled ? textColor : Win.disabledText)
                    .lineLimit(1)
                    .padding(.leading, 4)
                Spacer(minLength: 2)
                Chevron()
                    .stroke(enabled ? Win.rgb(0x404040) : Win.disabledBorder, lineWidth: 1.1)
                    .frame(width: 7, height: 4)
                    .padding(.trailing, 6)
            }
            .frame(width: g.size.width, height: g.size.height)
            .background(enabled ? Color.white : Win.face)
            .overlay(Rectangle().strokeBorder(enabled ? (hover ? Win.hoverBorder : Win.comboBorder) : Win.disabledBorder, lineWidth: 1))
            .background(MenuAnchorView(anchor: anchor))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture {
                guard enabled else { return }
                let entries: [MenuEntry] = items.map { it in
                    .item(it.1, checked: it.0 == selection) { selection = it.0 }
                }
                anchor.popUp(buildMenu(entries), minWidth: g.size.width)
            }
        }
    }
}

// MARK: - Edit

struct WinEdit: View {
    @Binding var text: String
    var font: Font = Win.tahoma(11)
    var color: Color = Win.text
    var maxLength: Int? = nil
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        TextField("", text: Binding(get: { text }, set: { v in text = maxLength.map { String(v.prefix($0)) } ?? v }))
            .textFieldStyle(.plain)
            .font(font)
            .foregroundColor(enabled ? color : Win.disabledText)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(enabled ? Color.white : Win.face)
            .overlay(Rectangle().strokeBorder(enabled ? Win.editBorder : Win.disabledBorder, lineWidth: 1))
    }
}

// MARK: - Group box

struct WinGroupBox<Content: View>: View {
    let title: String
    let width: CGFloat
    let height: CGFloat
    var font: Font = Win.tahoma(12, bold: true)
    var titleColor: Color = Win.text
    var background: Color = .white
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Win.groupBorder, lineWidth: 1)
                .frame(width: width, height: height - 7)
                .offset(y: 7)
            if !title.isEmpty {
                Text(title)
                    .font(font)
                    .foregroundColor(titleColor)
                    .lineLimit(1)
                    .padding(.horizontal, 2)
                    .background(background)
                    .frame(maxWidth: width - 12, alignment: .leading)
                    .offset(x: 6, y: -1)
            }
            Abs(width: width, height: height) { content() }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }
}

// MARK: - Scroll bar / track bar

/// Horizontal TScrollBar (PageSize 0): arrow buttons, track and a small thumb.
struct WinHScrollBar: View {
    let value: Int
    let range: ClosedRange<Int>
    let onChange: (Int) -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var dragStart: CGFloat?
    @State private var dragValue = 0
    @State private var pressed = false

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let btn = min(h + 2, 17)
            let thumbW: CGFloat = 17
            let track = max(1, w - 2 * btn - thumbW)
            let span = max(1, range.upperBound - range.lowerBound)
            let pos = CGFloat(min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / CGFloat(span)
            let tx = btn + track * pos
            let arrow = enabled ? Win.rgb(0x606060) : Win.rgb(0xBFBFBF)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Win.face)
                Chevron(down: false).stroke(arrow, lineWidth: 1.4)
                    .frame(width: 4, height: 7)
                    .position(x: btn / 2, y: h / 2)
                Chevron(down: false).stroke(arrow, lineWidth: 1.4)
                    .frame(width: 4, height: 7)
                    .scaleEffect(x: -1, y: 1)
                    .position(x: w - btn / 2, y: h / 2)
                if enabled && range.upperBound > range.lowerBound {
                    Rectangle().fill(dragStart != nil ? Win.rgb(0xA6A6A6) : Win.rgb(0xCDCDCD))
                        .frame(width: thumbW, height: h - 2)
                        .offset(x: tx, y: 1)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { d in
                    guard enabled else { return }
                    if let start = dragStart {
                        let nv = dragValue + Int(((d.location.x - start) / track * CGFloat(span)).rounded())
                        let cv = min(max(nv, range.lowerBound), range.upperBound)
                        if cv != value { onChange(cv) }
                        return
                    }
                    guard !pressed else { return }
                    pressed = true
                    let x = d.startLocation.x
                    if x < btn { step(-1) }
                    else if x > w - btn { step(1) }
                    else if x >= tx && x <= tx + thumbW { dragStart = x; dragValue = value }
                    else { step(x < tx ? -1 : 1) }
                }
                .onEnded { _ in
                    dragStart = nil
                    pressed = false
                })
        }
    }

    func step(_ d: Int) {
        let v = min(max(value + d, range.lowerBound), range.upperBound)
        if v != value { onChange(v) }
    }
}

/// Vertical TTrackBar (top = maximum).
struct WinVTrackBar: View {
    let value: Double
    let range: ClosedRange<Double>
    var tick: Double = 100
    let onChange: (Double) -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        GeometryReader { g in
            let h = g.size.height, w = g.size.width
            let top: CGFloat = 8, len = max(1, h - 16)
            let frac = (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / (range.upperBound - range.lowerBound)
            let y = top + len * CGFloat(1 - frac)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Win.rgb(0xE7EAEA))
                    .overlay(Rectangle().strokeBorder(Win.rgb(0xD6D6D6), lineWidth: 1))
                    .frame(width: 4, height: len)
                    .offset(x: w / 2 - 2, y: top)
                ForEach(Array(stride(from: range.lowerBound, through: range.upperBound, by: tick)), id: \.self) { t in
                    Rectangle().fill(Win.rgb(0xC4C4C4))
                        .frame(width: 4, height: 1)
                        .offset(x: w / 2 + 12, y: top + len * CGFloat(1 - (t - range.lowerBound) / (range.upperBound - range.lowerBound)))
                }
                Rectangle().fill(enabled ? Win.rgb(0x007AD9) : Win.rgb(0xCCCCCC))
                    .frame(width: 21, height: 11)
                    .offset(x: w / 2 - 10.5, y: y - 5.5)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { d in
                guard enabled else { return }
                let f = 1 - min(max((d.location.y - top) / len, 0), 1)
                onChange(range.lowerBound + Double(f) * (range.upperBound - range.lowerBound))
            })
        }
    }
}

// MARK: - Page control

struct WinTab<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
}

struct WinTabBar<ID: Hashable>: View {
    let tabs: [WinTab<ID>]
    @Binding var selection: ID

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(tabs) { t in
                TabHeader(title: t.title, selected: t.id == selection) { selection = t.id }
            }
        }
    }

    struct TabHeader: View {
        let title: String
        let selected: Bool
        let action: () -> Void
        @State private var hover = false

        var body: some View {
            Text(title)
                .font(Win.tahoma(13))
                .foregroundColor(Win.text)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .frame(height: selected ? 22 : 20)
                .background(selected ? Color.white : hover ? Win.tabHover : Win.face)
                .overlay(TabOutline().stroke(hover && !selected ? Win.tabHoverBorder : Win.tabBorder, lineWidth: 1))
                .padding(.horizontal, selected ? -2 : 0)
                .zIndex(selected ? 1 : 0)
                .contentShape(Rectangle())
                .onHover { hover = $0 }
                .onTapGesture(perform: action)
        }
    }

    /// Left, top and right edge (the bottom edge merges with the page).
    struct TabOutline: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.minX + 0.5, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + 0.5, y: r.minY + 0.5))
            p.addLine(to: CGPoint(x: r.maxX - 0.5, y: r.minY + 0.5))
            p.addLine(to: CGPoint(x: r.maxX - 0.5, y: r.maxY))
            return p
        }
    }
}

// MARK: - Main menu inside the window (TJvMainMenu, XP style)

struct WinMenuBarItem: View {
    let title: String
    var enabled = true
    var entries: (() -> [MenuEntry])? = nil
    var action: (() -> Void)? = nil
    @State private var hover = false
    @State private var anchor = MenuAnchor()

    var body: some View {
        Text(title)
            .font(Win.tahoma(11))
            .foregroundColor(enabled ? Win.text : Win.disabledText)
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(hover && enabled ? Win.menuHover : Color.clear)
            .overlay(Rectangle().strokeBorder(hover && enabled ? Win.menuHoverBorder : Color.clear, lineWidth: 1))
            .background(MenuAnchorView(anchor: anchor, name: "menu:" + title))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture {
                guard enabled else { return }
                if let e = entries { anchor.popUp(buildMenu(e())) } else { action?() }
            }
    }
}

// MARK: - Misc

/// TLed (LEDRndRect).
struct WinLed: View {
    let on: Bool
    let colorOn: Color
    var colorOff: Color = Win.rgb(0xE4E3DE)

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(on ? colorOn : colorOff)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Win.shadow, lineWidth: 1))
    }
}

/// Interface letter badge (TJvStaticText " B " / " 2 " of the Make interfaces page and the menu).
struct InterfaceBadge: View {
    let letter: String
    var silabs: Bool { letter.first.map { $0.isLetter && $0 != "X" } ?? false }

    var body: some View {
        Text(letter)
            .font(Win.tahoma(13, bold: true))
            .foregroundColor(silabs ? Win.maroon : Win.blue)
            .frame(width: 20, height: 19)
            .background(silabs ? Win.badgeYellow : Win.badgeBlue)
    }
}

extension NSImage {
    /// Menu image for an interface badge.
    @MainActor
    static func badge(_ letter: String) -> NSImage {
        let silabs = letter.first.map { $0.isLetter && $0 != "X" } ?? false
        let img = NSImage(size: NSSize(width: 16, height: 16))
        img.lockFocus()
        (silabs ? NSColor(red: 1, green: 1, blue: 0.5, alpha: 1) : NSColor(red: 0.83, green: 0.9, blue: 0.97, alpha: 1)).setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        NSColor(white: 0.55, alpha: 1).setStroke()
        NSBezierPath(rect: NSRect(x: 0.5, y: 0.5, width: 15, height: 15)).stroke()
        let font = NSFont(name: "Tahoma-Bold", size: 12) ?? .boldSystemFont(ofSize: 12)
        let color = silabs ? NSColor(red: 0.494, green: 0.071, blue: 0.271, alpha: 1) : NSColor.blue
        let s = NSAttributedString(string: letter, attributes: [.font: font, .foregroundColor: color])
        let sz = s.size()
        s.draw(at: NSPoint(x: (16 - sz.width) / 2, y: (16 - sz.height) / 2 + 0.5))
        img.unlockFocus()
        return img
    }
}
