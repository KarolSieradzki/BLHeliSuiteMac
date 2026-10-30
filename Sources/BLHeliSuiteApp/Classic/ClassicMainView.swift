import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BLHeliCore

/// Main window in the look of the original BLHeliSuite (TfrmBLHeliSuiteMain, 778 × 582 client area
/// plus the main menu). Positions are taken from the Delphi form.
struct ClassicMainView: View {
    @EnvironmentObject var model: AppModel
    static let size = CGSize(width: 778, height: 602)

    var body: some View {
        VStack(spacing: 0) {
            ClassicMenuBar()
                .frame(width: 778, height: 20, alignment: .leading)
            Abs(width: 778, height: 582) {
                ZStack {
                    Bevel(raised: true)
                    Bevel(raised: false, inset: 1)
                }
                .at(0, 5, 776, 465)
                ClassicPageControl().at(2, 7, 772, 461)
                ClassicActionButtons().at(0, 470, 778, 42)
                ClassicBottomPanel().at(0, 512, 778, 70)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Win.face)
        .environment(\.font, Win.tahoma(11))
        .preferredColorScheme(.light)
        .navigationTitle("BLHeliSuite 16.7.14.9.0.2")
    }
}

// MARK: - Main menu

struct ClassicMenuBar: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage("uiStyle") private var uiStyle = "classic"

    var body: some View {
        HStack(spacing: 0) {
            WinMenuBarItem(title: "ESC setup", entries: escSetupMenu)
            WinMenuBarItem(title: "ESC tools", entries: escToolsMenu)
            WinMenuBarItem(title: "Select ATMEL / SILABS Interface", enabled: !model.busy, entries: interfaceMenu)
            WinMenuBarItem(title: "Options", entries: optionsMenu)
            WinMenuBarItem(title: "?", entries: helpMenu)
            WinMenuBarItem(title: "BLHeli info", entries: infoMenu)
            WinMenuBarItem(title: "Save Screenshot", action: saveScreenshot)
            Spacer(minLength: 0)
        }
        .padding(.leading, 1)
        .background(Win.face)
    }

    func escSetupMenu() -> [MenuEntry] {
        [.item("Save Setup...", image: ClassicImage.named("save"), enabled: model.workspace != nil) { model.saveSetupToFile() },
         .item("Read Setup from file...", image: ClassicImage.named("open"), enabled: model.workspace != nil) { model.loadSetupFromFile() },
         .separator,
         .item("Read Setup", image: ClassicImage.named("read"), enabled: !model.busy) { model.readSetup() },
         .item("Write Setup", image: ClassicImage.named("write"), enabled: !model.busy && model.connected && model.workspace != nil) { model.writeSetup() },
         .separator,
         .item("Undo all changes", image: ClassicImage.named("undo"), enabled: model.workspaceModified) { model.undoAll() },
         .item("Set all to defaults", image: ClassicImage.named("default"), enabled: model.workspace != nil) { model.allDefaults() }]
    }

    func escToolsMenu() -> [MenuEntry] {
        let dev = model.masterIndex.flatMap { $0 < model.slots.count ? model.slots[$0].device : nil }
        let canErase = dev.map { $0.interfaceMode == .siLabsC2 || $0.isISP } ?? false
        return [.item("Read complete flash to HEX file...", image: ClassicImage.named("verify"), enabled: model.connected && !model.busy) { model.dumpFlash() },
                .item("Restart ESC", image: ClassicImage.named("restart"), enabled: model.connected && !model.busy) { model.restartESC() },
                .item("Erase chip", image: ClassicImage.named("erase"), enabled: canErase && !model.busy) { model.eraseChip() },
                .separator,
                .item("Show hex File...", image: ClassicImage.named("hexdoc")) { model.showHexFile() }]
    }

    /// Original interface list; the ones without a Mac implementation are shown disabled.
    static let interfaces: [(letter: String, title: String, type: InterfaceType?)] = [
        ("A", "SILABS C2 (Toolstick)", .silabsC2Toolstick),
        ("B", "SILABS C2 (4way-if)", .silabsC2FourWay),
        ("C", "SILABS BLHeli Bootloader (USB/Com)", nil),
        ("D", "SILABS BLHeli Bootloader (4way-if)", .silabsBLBFourWay),
        ("E", "SILABS BLHeli Bootloader (Cleanflight)", .silabsBLBFlightController),
        ("-", "", nil),
        ("1", "ATMEL BLHeli Bootloader (USB/Com)", nil),
        ("2", "ATMEL BLHeli Bootloader (4way-if)", .atmelBLBFourWay),
        ("3", "ATMEL SK Bootloader (4way-if)", .atmelSKFourWay),
        ("4", "ATMEL SK Bootloader (ArduinoUSBLinker)", nil),
        ("5", "ATMEL SK Bootloader (Afro/Turnigy USB Linker)", nil),
        ("6", "ATMEL BLHeli Bootloader (Cleanflight)", .atmelFlightController),
        ("-", "", nil),
        ("X", "ATMEL ISP Interface (AVRDude)", .atmelISP),
    ]

    func interfaceMenu() -> [MenuEntry] {
        Self.interfaces.map { i in
            if i.letter == "-" { return .separator }
            guard let t = i.type else {
                return .item(i.title + "   (not available on Mac)", image: .badge(i.letter), enabled: false) {}
            }
            return .item(i.title, image: .badge(i.letter), checked: model.interfaceType == t) { model.interfaceType = t }
        }
    }

    func optionsMenu() -> [MenuEntry] {
        [.item("Enable Log", image: ClassicImage.named("log2")) { openWindow(id: "log") },
         .item("Log Protocol Traffic", checked: model.protocolTrace) { model.protocolTrace.toggle() },
         .separator,
         .item("Verify Flash after Write", checked: model.verifyFlash) { model.verifyFlash.toggle() },
         .item("Arduino Delay", checked: model.arduinoDelay > 0, enabled: !model.interfaceType.isFlightController && model.interfaceType.usesSerialPort) {
             model.arduinoDelay = model.arduinoDelay > 0 ? 0 : 2.0
         },
         .separator,
         .item("Expert Mode", checked: model.expertMode) { model.expertMode.toggle() },
         .separator,
         .item("Sync Motor direction to Multiple ESC", checked: model.syncDirection) { model.syncDirection.toggle() },
         .item("Sync Min/Center/Max Throttle to Multiple ESC", checked: model.syncThrottle) { model.syncThrottle.toggle() },
         .separator,
         .item("Modern macOS look") { uiStyle = "modern" }]
    }

    func helpMenu() -> [MenuEntry] {
        var e: [MenuEntry] = [.item("About...", image: ClassicImage.named("about")) { NSApp.orderFrontStandardAboutPanel(nil) }]
        if let h = manual("BLHeliSuite History.pdf") {
            e.append(.item("Show history  (local pdf)", image: ClassicImage.named("pdf")) { NSWorkspace.shared.open(h) })
        }
        e.append(.separator)
        for (title, file) in [("Show BLHeli programming adapters manual (local pdf)", "BLHeli programming adapters.pdf"),
                              ("Show how to Make an ArduinoISP (local pdf)", "How to Make an ArduinoISP.pdf"),
                              ("Show Building a BLHeli bootloader interface with USB-UART board (local pdf)", "How to Build a BLHeli bootloader interface with USB-UART board.pdf"),
                              ("Show Pinout for 4w-if Interfaces (local pdf)", "BLHeliSuite 4w-if interfaces pinout.pdf"),
                              ("Show info about 4w-if Interface Protocol  (local pdf)", "BLHeliSuite 4w-if protocol.pdf"),
                              ("Show info about BLHeliSuite MultipleESC mode (local pdf)", "BLHeliSuite MultipleESC mode.pdf")] {
            if let u = manual(file) { e.append(.item(title, image: ClassicImage.named("pdf")) { NSWorkspace.shared.open(u) }) }
        }
        return e
    }

    func infoMenu() -> [MenuEntry] {
        let manuals = Manuals.list().map { u -> MenuEntry in
            .item("\"\(u.deletingPathExtension().lastPathComponent)\" (\(u.pathExtension))", image: ClassicImage.named("pdf")) { NSWorkspace.shared.open(u) }
        }
        return [.submenu("Manuals", image: ClassicImage.named("pdf"), enabled: !manuals.isEmpty, manuals),
                .submenu("Source", [.item("BLHeli source files at GitHub", image: ClassicImage.named("web")) {
                    if let u = URL(string: "https://github.com/bitdump/BLHeli") { NSWorkspace.shared.open(u) }
                }])]
    }

    func manual(_ name: String) -> URL? {
        guard let f = Manuals.folder() else { return nil }
        let u = f.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    /// PNG of the window content below the title bar.
    static func contentPNG(of w: NSWindow) -> Data? {
        guard let v = w.contentView else { return nil }
        let r = v.convert(w.contentLayoutRect, from: nil).intersection(v.bounds)
        guard let rep = v.bitmapImageRepForCachingDisplay(in: r) else { return nil }
        v.cacheDisplay(in: r, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    func saveScreenshot() {
        guard let w = NSApp.keyWindow ?? NSApp.mainWindow, let data = Self.contentPNG(of: w) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        panel.nameFieldStringValue = "BLHeliSuite_\(f.string(from: Date())).png"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                model.status = "Screenshot saved: \(url.lastPathComponent)"
            } catch {
                model.alert = AlertItem(title: "Save Screenshot", message: error.localizedDescription)
            }
        }
    }
}

// MARK: - Page control

struct ClassicPageControl: View {
    @EnvironmentObject var model: AppModel

    var tabs: [WinTab<MainTab>] {
        var t = [WinTab(id: MainTab.setup, title: model.setupTabTitle), WinTab(id: MainTab.overview, title: "ESC overview")]
        if model.interfaceType.isFlightController { t.append(WinTab(id: .motors, title: "Motors")) }
        if model.expertMode { t.append(WinTab(id: .expert, title: "Expert tools")) }
        t.append(WinTab(id: .interfaces, title: "Make interfaces"))
        return t
    }

    var current: MainTab {
        if model.selectedTab == .log || tabs.contains(where: { $0.id == model.selectedTab }) { return model.selectedTab }
        return .setup
    }

    var body: some View {
        Abs(width: 772, height: 461) {
            Rectangle().fill(Color.white)
                .overlay(Rectangle().strokeBorder(Win.tabBorder, lineWidth: 1))
                .at(0, 21, 772, 440)
            WinTabBar(tabs: tabs, selection: Binding(get: { current }, set: { model.selectedTab = $0 }))
                .at(2, 0, 768, 22)
            page.clipped().at(1, 22, 770, 438)
        }
    }

    @ViewBuilder var page: some View {
        switch current {
        case .setup: ClassicSetupPage()
        case .overview: ClassicOverviewPage()
        case .motors: ClassicMotorsPage()
        case .expert: ClassicExpertPage()
        case .interfaces: ClassicMakeInterfacesPage()
        case .log: ClassicLogList().padding(6)
        }
    }
}

// MARK: - Bottom buttons (pnlBottomButtons)

struct ClassicActionButtons: View {
    @EnvironmentObject var model: AppModel

    var writing: Bool {
        let s = model.status.lowercased()
        return ["writ", "flash", "eras", "verif"].contains { s.contains($0) }
    }

    var body: some View {
        Abs(width: 778, height: 42) {
            WinLed(on: model.busy && !writing, colorOn: Win.lime).at(8, 10, 20, 10)
            WinLed(on: model.busy && writing, colorOn: Win.red).at(8, 23, 20, 10)
            WinButton(title: "Read Setup", glyph: "read") { model.readSetup() }
                .disabled(model.busy || (!model.interfaceType.usesSerialPort && !model.connected && model.interfaceType != .atmelISP && model.interfaceType != .silabsC2Toolstick))
                .at(34, 9, 98, 25)
            WinButton(title: "Write Setup", glyph: "write") { model.writeSetup() }
                .disabled(model.busy || !model.connected || model.workspace == nil)
                .at(139, 9, 98, 25)
            WinButton(title: "Flash BLHeli", glyph: "flash") { model.flashBLHeli() }
                .disabled(model.busy)
                .at(245, 9, 101, 25)
            WinButton(title: "Flash Other", glyph: "flashOther") { model.flashOther() }
                .disabled(model.busy)
                .at(354, 9, 101, 25)
            WinButton(title: "Restart ESC", glyph: "restart") { model.restartESC() }
                .disabled(model.busy || !model.connected)
                .at(463, 9, 107, 25)
            Rectangle().fill(Win.shadow).at(0, 41, 778, 1)
        }
    }
}

// MARK: - Bottom panel (interface, Multiple ESC, status bar)

struct ClassicBottomPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Abs(width: 778, height: 70) {
            switch model.interfaceType {
            case .silabsC2Toolstick:
                ToolstickPanel().at(1, 1, 180, 43)
                ConnectPanel().at(181, 1, 107, 43)
                multiESC(x: 290)
            case .atmelISP:
                ISPPanel().at(1, 1, 574, 43)
                ConnectPanel().at(575, 1, 107, 43)
            default:
                SerialPanel().at(1, 1, 290, 43)
                ConnectPanel().at(291, 1, 107, 43)
                if model.connected && !model.slots.isEmpty {
                    MultipleESCGroup().at(400, 1, 369, 43)
                } else if !model.interfaceType.isFlightController {
                    WinCheckBox(title: "Arduino Delay", isOn: Binding(get: { model.arduinoDelay > 0 },
                                                                       set: { model.arduinoDelay = $0 ? 2.0 : 0 }))
                        .disabled(model.busy || model.connected)
                        .help("Waits for the Arduino bootloader after opening the port (Arduino resets on connect).")
                        .at(402, 16, 120, 17)
                }
            }
            ClassicStatusBar().at(1, 50, 776, 19)
        }
    }

    @ViewBuilder func multiESC(x: CGFloat) -> some View {
        if model.connected && !model.slots.isEmpty { MultipleESCGroup().at(x, 1, 369, 43) }
    }
}

struct SerialPanel: View {
    @EnvironmentObject var model: AppModel
    static let bauds = [9600, 19200, 38400, 57600, 115200, 230400, 250000, 500000]

    var portItems: [(String, String)] {
        var items = model.ports.map { ($0.path, $0.displayName) }
        if !model.portPath.isEmpty && !items.contains(where: { $0.0 == model.portPath }) {
            items.append((model.portPath, (model.portPath as NSString).lastPathComponent))
        }
        return items
    }

    var body: some View {
        Abs(width: 290, height: 43) {
            Text("Port:").at(3, 18, 26, 13)
            PortCombo().disabled(model.connected || model.busy).at(30, 15, 150, 21)
            Text("Baud:").at(188, 18, 30, 13)
            WinCombo(items: Self.bauds.map { ($0, String($0)) }, selection: $model.baud)
                .disabled(model.connected || model.busy)
                .at(221, 15, 65, 21)
        }
    }
}

/// Serial port combo; refreshes the port list when it is opened (like the original).
struct PortCombo: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.isEnabled) private var enabled
    @State private var anchor = MenuAnchor()
    @State private var hover = false

    var label: String {
        if model.portPath.isEmpty { return model.ports.isEmpty ? "no serial port" : "" }
        return model.ports.first { $0.path == model.portPath }?.displayName ?? (model.portPath as NSString).lastPathComponent
    }

    var body: some View {
        GeometryReader { g in
            HStack(spacing: 0) {
                Text(label)
                    .foregroundColor(enabled ? Win.text : Win.disabledText)
                    .lineLimit(1)
                    .padding(.leading, 4)
                Spacer(minLength: 2)
                Chevron().stroke(enabled ? Win.rgb(0x404040) : Win.disabledBorder, lineWidth: 1.1)
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
                model.refreshPorts()
                var entries: [MenuEntry] = model.ports.map { p in
                    .item(p.displayName, checked: p.path == model.portPath) { model.portPath = p.path }
                }
                if entries.isEmpty { entries = [.item("no serial port found", enabled: false) {}] }
                anchor.popUp(buildMenu(entries), minWidth: g.size.width)
            }
        }
    }
}

struct ToolstickPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        // (serial number, shown name); adapters without a serial number are opened as "first one found"
        let list = ToolstickHID.list().map { ($0.serial, $0.serial.isEmpty ? $0.product : $0.serial) }
        Abs(width: 180, height: 43) {
            Text("Toolstick:").at(6, 18, 47, 13)
            WinCombo(items: list, selection: Binding(get: { list.contains { $0.0 == model.toolstickSerial } ? model.toolstickSerial : (list.first?.0 ?? "") },
                                                     set: { model.toolstickSerial = $0 }),
                     placeholder: "none found")
                .disabled(model.connected || model.busy)
                .at(54, 15, 113, 21)
        }
    }
}

struct ISPPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Abs(width: 574, height: 43) {
            Text("ISP Prog:").at(5, 18, 47, 13)
            WinCombo(items: AVRDudeProgrammerType.common.map { ($0, $0.description) }, selection: $model.ispProgrammer)
                .disabled(model.connected || model.busy)
                .at(53, 15, 280, 21)
            if model.ispProgrammer.serial {
                Text("Port:").at(339, 18, 26, 13)
                PortCombo().disabled(model.connected || model.busy).at(369, 15, 200, 21)
            } else if AVRDude(path: model.avrdudePath) == nil {
                Text("avrdude missing – brew install avrdude")
                    .foregroundColor(Win.red)
                    .at(339, 18, 230, 13)
            }
        }
    }
}

struct ConnectPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Abs(width: 107, height: 43) {
            WinButton(title: model.connected ? "Disconnect" : "Connect", glyph: "connect") { model.toggleConnection() }
                .disabled(model.busy)
                .at(5, 13, 98, 25)
        }
    }
}

/// grb_MultipleESC: ESC #1…#8 buttons, Copy / Paste and Check.
struct MultipleESCGroup: View {
    @EnvironmentObject var model: AppModel
    static let xs: [CGFloat] = [4, 31, 58, 85, 112, 139, 166, 194]

    var title: String {
        guard let m = model.masterIndex else { return "Multiple ESC" }
        return model.active.count > 1 ? "Multiple ESC / Master#\(m + 1)" : "Single ESC#\(m + 1)"
    }

    var single: Bool { model.active.count == 1 && model.workspace != nil }
    var clipboardInSync: Bool {
        guard var c = model.clipboard, let w = model.workspace else { return false }
        c.name = w.name
        return c == w
    }

    var body: some View {
        WinGroupBox(title: title, width: 369, height: 43, background: Win.face) {
            ForEach(model.slots.prefix(8)) { slot in
                ClassicESCButton(slot: slot).at(Self.xs[slot.index], 15, 25, 25)
            }
            if single {
                WinButton(title: "Copy", textColor: clipboardInSync ? Win.green : nil) { model.copySettings() }
                    .help(clipboardText(model.clipboard, header: "Clipboard:"))
                    .at(223, 15, 34, 25)
                if model.clipboard != nil && !clipboardInSync {
                    WinButton(title: "Paste") { model.pasteSettings() }
                        .help(clipboardText(model.clipboard, header: "Paste:"))
                        .at(260, 15, 37, 25)
                }
            }
            WinButton(title: "Check", glyph: "check") { model.check() }
                .disabled(model.busy)
                .at(300, 15, 62, 25)
        }
        .disabled(model.busy)
    }

    func clipboardText(_ s: BLHeliSettings?, header: String) -> String {
        guard let s else { return "Clipboard is empty" }
        return "\(header)\nName:\(s.name)\n\(s.summary(database: model.database))"
    }
}

struct ClassicESCButton: View {
    @EnvironmentObject var model: AppModel
    let slot: ESCSlot
    @State private var hover = false

    var isActive: Bool { model.active.contains(slot.index) }

    var face: (String, Color) {
        let n = "\(slot.index + 1)"
        switch slot.state {
        case .notFound: return isActive ? ("?", Win.blue) : ("", Win.grayText)
        case .unchecked: return (isActive ? n : "..", Win.grayText)
        case .ok:
            if !isActive { return ("..", Win.grayText) }
            if slot.index == model.masterIndex { return (n, Win.blue) }
            if model.inSync(slot) { return (n, model.directionDiffers(slot) ? Win.orange : Win.green) }
            return (n, Win.grayText)
        case .layoutDiffers: return (isActive ? n : "..", isActive ? Win.purple : Win.grayText)
        case .unknownFirmware: return ("u", isActive ? Win.blue : Win.rgb(0xA0A0A0))
        case .failedFlash: return ("f", isActive ? Win.blue : Win.rgb(0xA0A0A0))
        case .wrongBrand: return ("b", isActive ? Win.blue : Win.rgb(0xA0A0A0))
        case .modeDiffers: return ("m", isActive ? Win.blue : Win.rgb(0xA0A0A0))
        case .unsupported: return ("x", isActive ? Win.blue : Win.rgb(0xA0A0A0))
        }
    }

    var body: some View {
        let f = face
        Text(f.0)
            .font(Win.arial(f.0.count > 1 ? 13 : 17))
            .foregroundColor(f.1)
            .frame(width: 25, height: 25)
            .background(Rectangle().fill(hover ? Win.hoverFill : Win.rgb(0xEDEDED)))
            .overlay(Rectangle().strokeBorder(hover ? Win.hoverBorder : Win.buttonBorder, lineWidth: 1))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture {
                guard !model.busy, slot.state != .notFound else { return }
                model.toggleActive(slot.index)
            }
            .overlay(RightClickCatcher { if !model.busy { model.selectSingle(slot.index) } })
            .help(helpText)
    }

    var helpText: String {
        var s = "ESC#\(slot.index + 1): "
        if slot.index == model.masterIndex { s += "[MASTER]" } else if isActive { s += "[SLAVE]" } else { s += "[not active]" }
        if slot.state == .ok, isActive, slot.index != model.masterIndex {
            s += model.inSync(slot) ? "\n\nSetup in Sync with Master" : "\n\nSetup NOT in Sync with Master"
            if model.directionDiffers(slot) { s += "\n    -> Motor Direction: different" }
        }
        if let st = slot.settings, (try? st.validate()) != nil { s += "\n\n\(st.summary(database: model.database))" }
        else if let d = slot.device { s += "\n\n\(d.description)" }
        switch slot.state {
        case .unknownFirmware: s += "\nErased or unknown firmware"
        case .failedFlash: s += "\n**FLASH*FAILED**"
        case .wrongBrand: s += "\nWrong firmware brand for the selected interface"
        case .modeDiffers: s += "\nESC Mode different from Master"
        case .layoutDiffers: s += "\nEEprom Layout different from Master"
        case .notFound: s += "\nnot found"
        default: break
        }
        s += "\n\nLeft click adds ESC#\(slot.index + 1) to Multiple ESC configuration.\nRight click selects ESC#\(slot.index + 1) as a Single target."
        return s
    }
}

struct ClassicStatusBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Abs(width: 776, height: 19) {
            Rectangle().fill(Win.face).at(0, 0, 776, 19)
            Rectangle().fill(Win.rgb(0xD7D7D7)).at(0, 0, 776, 1)
            Text(model.status).lineLimit(1).at(4, 3, model.busy ? 500 : 420, 14)
            if model.busy {
                ZStack(alignment: .leading) {
                    Rectangle().fill(Win.rgb(0xE6E6E6))
                    Rectangle().fill(Win.rgb(0x06B025)).frame(width: max(0, min(1, model.progress)) * 176)
                }
                .overlay(Rectangle().strokeBorder(Win.rgb(0xBCBCBC), lineWidth: 1))
                .at(510, 3, 178, 13)
                WinButton(title: "Cancel") { model.cancel() }.at(696, 1, 74, 17)
            } else if model.workspaceModified {
                Text("Setup changed – not written yet").foregroundColor(Win.orange).lineLimit(1).at(430, 3, 200, 14)
                connection.at(632, 3, 140, 14)
            } else {
                connection.at(430, 3, 342, 14)
            }
        }
    }

    var connection: some View {
        Text(model.connected ? model.connectionInfo : "")
            .foregroundColor(Win.grayText)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
