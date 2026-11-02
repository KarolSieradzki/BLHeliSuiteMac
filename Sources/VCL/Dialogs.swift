import AppKit
import UniformTypeIdentifiers

/// Dialogs.TMsgDlgType
public enum TMsgDlgType: Int { case mtWarning = 0, mtError, mtInformation, mtConfirmation, mtCustom }

/// Dialogs.TMsgDlgBtn
public enum TMsgDlgBtn: Int, CaseIterable {
    case mbYes = 0, mbNo, mbOK, mbCancel, mbAbort, mbRetry, mbIgnore, mbAll, mbNoToAll, mbYesToAll, mbHelp

    var caption: String {
        ["&Yes", "&No", "OK", "Cancel", "&Abort", "&Retry", "&Ignore", "&All", "N&o to All", "Yes to &All", "&Help"][rawValue]
    }

    var modalResult: TModalResult { [mrYes, mrNo, mrOk, mrCancel, mrAbort, mrRetry, mrIgnore, mrAll, mrNoToAll, mrYesToAll, mrNone][rawValue] }
}

public struct TMsgDlgButtons: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let mbYes = TMsgDlgButtons(rawValue: 1 << 0)
    public static let mbNo = TMsgDlgButtons(rawValue: 1 << 1)
    public static let mbOK = TMsgDlgButtons(rawValue: 1 << 2)
    public static let mbCancel = TMsgDlgButtons(rawValue: 1 << 3)
    public static let mbAbort = TMsgDlgButtons(rawValue: 1 << 4)
    public static let mbRetry = TMsgDlgButtons(rawValue: 1 << 5)
    public static let mbIgnore = TMsgDlgButtons(rawValue: 1 << 6)
    public static let mbAll = TMsgDlgButtons(rawValue: 1 << 7)
    public static let mbNoToAll = TMsgDlgButtons(rawValue: 1 << 8)
    public static let mbYesToAll = TMsgDlgButtons(rawValue: 1 << 9)
    public static let mbHelp = TMsgDlgButtons(rawValue: 1 << 10)
}

/// Windows system icons (IDI_WARNING, IDI_ERROR, IDI_ASTERISK, IDI_QUESTION) drawn in Windows 10 style.
public enum SystemIcon {
    public static func image(_ t: TMsgDlgType) -> NSImage? {
        guard t != .mtCustom else { return nil }
        let img = NSImage(size: NSSize(width: 32, height: 32), flipped: true) { _ in
            switch t {
            case .mtWarning:
                let p = NSBezierPath()
                p.move(to: NSPoint(x: 16, y: 2))
                p.line(to: NSPoint(x: 31, y: 29))
                p.line(to: NSPoint(x: 1, y: 29))
                p.close()
                p.lineJoinStyle = .round
                Colors.hex(0xFFD000).setFill()
                p.fill()
                Colors.hex(0xC79A00).setStroke()
                p.lineWidth = 1
                p.stroke()
                NSColor.black.setFill()
                NSBezierPath(roundedRect: NSRect(x: 14.5, y: 10, width: 3, height: 11), xRadius: 1, yRadius: 1).fill()
                NSBezierPath(ovalIn: NSRect(x: 14.3, y: 23, width: 3.4, height: 3.4)).fill()
            case .mtError:
                let c = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 30, height: 30))
                Colors.hex(0xE81123).setFill()
                c.fill()
                let x = NSBezierPath()
                x.move(to: NSPoint(x: 11, y: 11)); x.line(to: NSPoint(x: 21, y: 21))
                x.move(to: NSPoint(x: 21, y: 11)); x.line(to: NSPoint(x: 11, y: 21))
                NSColor.white.setStroke()
                x.lineWidth = 2.6
                x.lineCapStyle = .round
                x.stroke()
            case .mtInformation, .mtConfirmation:
                let c = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 30, height: 30))
                Colors.hex(0x1C6FD1).setFill()
                c.fill()
                let s = t == .mtInformation ? "i" : "?"
                let f = NSFont.boldSystemFont(ofSize: t == .mtInformation ? 20 : 19)
                let a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: NSColor.white]
                let sz = (s as NSString).size(withAttributes: a)
                (s as NSString).draw(at: NSPoint(x: 16 - sz.width / 2, y: 16 - sz.height / 2), withAttributes: a)
            default: break
            }
            return true
        }
        return img
    }
}

/// Dialogs.CreateMessageDialog (Delphi 2007) – classic message box layout with Screen.MessageFont.
public final class TMessageForm: TForm {
    public var extraSetup: ((TMessageForm) -> Void)?

    public static func create(_ msg: String, _ type: TMsgDlgType, _ buttons: TMsgDlgButtons, title: String? = nil) -> TMessageForm {
        let f = TMessageForm(frame: .zero)
        f.borderStyle = "bsDialog"
        f.position = "poScreenCenter"
        f.font.name = "Segoe UI"
        f.font.height = -12
        let mf = TFont.messageFont
        // DialogUnits: average char size (GetAveCharSize) of the message font
        let avg = TextDraw.width("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz", mf) / 52
        let du = (x: Int(avg), y: Int(TextDraw.lineHeight(mf)))
        func mul(_ v: Int, _ d: Int, _ q: Int) -> Int { Int((Double(v * d) / Double(q)).rounded()) }
        let horzMargin = mul(8, du.x, 4), vertMargin = mul(8, du.y, 8)
        let horzSpacing = mul(10, du.x, 4), vertSpacing = mul(10, du.y, 8)
        var buttonWidth = mul(50, du.x, 4)
        let all = TMsgDlgBtn.allCases.filter { buttons.contains(TMsgDlgButtons(rawValue: 1 << $0.rawValue)) }
        for b in all {
            let w = Int(TextDraw.width(TextDraw.stripAccel(b.caption), mf).rounded(.up)) + 8
            if w > buttonWidth { buttonWidth = w }
        }
        let buttonHeight = mul(14, du.y, 8)
        let buttonSpacing = mul(4, du.x, 4)
        let maxW = (NSScreen.main?.frame.width ?? 1600) / 2
        let lines = TextDraw.wrap(msg.replacingOccurrences(of: "\r", with: ""), mf, width: maxW)
        let textW = Int((lines.map { TextDraw.width($0, mf) }.max() ?? 0).rounded(.up))
        let textH = Int(TextDraw.lineHeight(mf)) * lines.count
        let icon = SystemIcon.image(type)
        var iconTextWidth = textW, iconTextHeight = textH
        if icon != nil {
            iconTextWidth += 32 + horzSpacing
            if iconTextHeight < 32 { iconTextHeight = 32 }
        }
        let n = all.count
        let groupW = n > 0 ? buttonWidth * n + buttonSpacing * (n - 1) : 0
        let cw = max(iconTextWidth, groupW) + horzMargin * 2
        let ch = iconTextHeight + buttonHeight + vertSpacing + vertMargin * 2
        f.designClientWidth = cw
        f.designClientHeight = ch
        f.frame = NSRect(x: 0, y: 0, width: cw, height: ch)
        f.caption = title ?? (type == .mtCustom ? Application.shared.title : ["Warning", "Error", "Information", "Confirm"][type.rawValue])
        if let icon {
            let im = TImage(frame: NSRect(x: horzMargin, y: vertMargin, width: 32, height: 32))
            im.picture = icon
            im.transparent = true
            im.name = "Image"
            f.addSubview(im)
        }
        let lbl = TLabel(frame: NSRect(x: iconTextWidth - textW + horzMargin, y: vertMargin, width: textW, height: textH))
        lbl.name = "Message"
        lbl.autoSize = false
        lbl.wordWrap = true
        lbl.transparent = true
        lbl.font.name = "Segoe UI"
        lbl.font.height = -12
        lbl.caption = msg.replacingOccurrences(of: "\r", with: "")
        lbl.showAccelChar = false
        lbl.loading = false
        f.addSubview(lbl)
        let def: TMsgDlgBtn = buttons.contains(.mbOK) ? .mbOK : (buttons.contains(.mbYes) ? .mbYes : .mbRetry)
        let cancel: TMsgDlgBtn = buttons.contains(.mbCancel) ? .mbCancel : (buttons.contains(.mbNo) ? .mbNo : .mbOK)
        var x = (cw - groupW) / 2
        for b in all {
            let btn = TButton(frame: NSRect(x: x, y: iconTextHeight + vertMargin + vertSpacing, width: buttonWidth, height: buttonHeight))
            btn.caption = b.caption
            btn.font.name = "Segoe UI"
            btn.font.height = -12
            btn.modalResult = b.modalResult
            btn.isDefault = b == def
            btn.isCancel = b == cancel
            btn.root = f
            btn.name = ["Yes", "No", "OK", "Cancel", "Abort", "Retry", "Ignore", "All", "NoToAll", "YesToAll", "Help"][b.rawValue]
            f.addSubview(btn)
            x += buttonWidth + buttonSpacing
        }
        f.createWindow()
        return f
    }

    public required init(frame: NSRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { fatalError() }

    public override func draw(_ dirtyRect: NSRect) { Draw.fill(bounds, Colors.ns(clBtnFace)) }
}

/// MessageDlg.
@discardableResult
public func MessageDlg(_ msg: String, _ type: TMsgDlgType, _ buttons: TMsgDlgButtons, setup: ((TMessageForm) -> Void)? = nil) -> TModalResult {
    let f = TMessageForm.create(msg, type, buttons)
    setup?(f)
    let r = f.showModal()
    f.release()
    return r
}

public func ShowMessage(_ msg: String) {
    let f = TMessageForm.create(msg, .mtCustom, [.mbOK])
    f.showModal()
    f.release()
}

// MARK: - common dialogs

public enum OpenDialog {
    /// Content types of file extensions in both cases (Windows file names like "…REV14_9.HEX").
    static func contentTypes(_ exts: [String]) -> [UTType] {
        Array(Set(exts.flatMap { [$0.lowercased(), $0.uppercased()] })).compactMap { UTType(filenameExtension: $0) }
    }

    /// filter: Delphi filter string "Text|*.ext;*.ext2|…"
    public static func execute(title: String? = nil, filter: String = "", initialDir: URL? = nil) -> URL? {
        let p = NSOpenPanel()
        p.canChooseDirectories = false
        p.allowsMultipleSelection = false
        if let t = title { p.title = t; p.message = t }
        if let d = initialDir { p.directoryURL = d }
        p.allowsOtherFileTypes = true
        let exts = extensions(filter)
        let masks = filter.components(separatedBy: "|").enumerated().filter { $0.offset % 2 == 1 }
            .flatMap { $0.element.components(separatedBy: ";") }.map { $0.trimmingCharacters(in: .whitespaces) }
        var maskFilter: MaskFilter?
        if masks.contains(where: { m in m != "*.*" && !(m.hasPrefix("*.") && !m.dropFirst(2).contains { "*?".contains($0) }) }) {
            // wildcard masks like "4wArduino_Nano*_16_*.hex": only matching files can be chosen
            maskFilter = MaskFilter(masks)
            p.delegate = maskFilter
        } else if !exts.isEmpty && !exts.contains("*") {
            p.allowedContentTypes = OpenDialog.contentTypes(exts)
        }
        let r = p.runModal() == .OK ? p.url : nil
        p.delegate = nil
        _ = maskFilter
        return r
    }

    /// Enables only the files matching one of the Delphi filter masks.
    final class MaskFilter: NSObject, NSOpenSavePanelDelegate {
        let masks: [String]
        init(_ m: [String]) { masks = m.map { $0.lowercased() } }

        func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { return true }
            let n = url.lastPathComponent.lowercased()
            return masks.contains { MaskFilter.wildcard(n, $0) }
        }

        static func wildcard(_ name: String, _ mask: String) -> Bool {
            let n = Array(name), m = Array(mask)
            var i = 0, j = 0, star = -1, mark = 0
            while i < n.count {
                if j < m.count && (m[j] == "?" || m[j] == n[i]) { i += 1; j += 1 }
                else if j < m.count && m[j] == "*" { star = j; mark = i; j += 1 }
                else if star >= 0 { j = star + 1; mark += 1; i = mark }
                else { return false }
            }
            while j < m.count && m[j] == "*" { j += 1 }
            return j == m.count
        }
    }

    static func extensions(_ filter: String) -> [String] {
        let parts = filter.components(separatedBy: "|")
        var out: [String] = []
        for (i, p) in parts.enumerated() where i % 2 == 1 {
            for m in p.components(separatedBy: ";") {
                let e = m.trimmingCharacters(in: .whitespaces)
                if e == "*.*" { out.append("*") } else if e.hasPrefix("*.") { out.append(String(e.dropFirst(2))) }
            }
        }
        return out
    }
}

public enum SaveDialog {
    public static func execute(title: String? = nil, fileName: String = "", filter: String = "", initialDir: URL? = nil) -> URL? {
        let p = NSSavePanel()
        if let t = title { p.title = t; p.message = t }
        p.nameFieldStringValue = fileName
        if let d = initialDir { p.directoryURL = d }
        let exts = OpenDialog.extensions(filter).filter { $0 != "*" }
        if !exts.isEmpty {
            p.allowedContentTypes = OpenDialog.contentTypes(exts)
            p.allowsOtherFileTypes = true
        }
        return p.runModal() == .OK ? p.url : nil
    }
}

public enum ColorDialog {
    /// TColorDialog.Execute – returns the chosen colour or nil.
    public static func execute(_ c: TColor) -> TColor? {
        let panel = NSColorPanel.shared
        panel.color = Colors.ns(c)
        panel.showsAlpha = false
        final class Observer: NSObject, NSWindowDelegate {
            func windowWillClose(_ notification: Notification) { NSApp.stopModal() }
        }
        let obs = Observer()
        let oldDelegate = panel.delegate
        panel.delegate = obs
        NSApp.runModal(for: panel)
        panel.delegate = oldDelegate
        guard let rgb = panel.color.usingColorSpace(.sRGB) else { return nil }
        let r = Int((rgb.redComponent * 255).rounded()), g = Int((rgb.greenComponent * 255).rounded()), b = Int((rgb.blueComponent * 255).rounded())
        return Colors.fromRGB(r, g, b)
    }
}
