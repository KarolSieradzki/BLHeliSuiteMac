import AppKit
import SwiftUI
import BLHeliCore

/// Mouse driven test of the classic look against blheli-sim (Betaflight FC with 4 ESCs):
///   BLHeliSuite --uitest <serial port> --out <folder>
/// Posts real mouse events into the window (menus, combos, ESC buttons, tabs, parameter boxes,
/// buttons, the flash assistant sheet) at the DFM positions of the classic layout. Menus are
/// captured by `MenuAnchor.interceptor`; one menu is also really opened and closed again.
/// The preferences changed by the test are restored at the end.
@MainActor
final class UITest {
    static var current: UITest?
    let port: String
    let out: URL
    var results: [[String: Any]] = []
    var failures = 0
    var captured: (menu: NSMenu, rect: NSRect)?
    /// The user's preferences before the test (taken before `--style` is applied).
    let saved: [String: Any]
    /// Menu reported by NSMenu.didBeginTrackingNotification (posted on the main thread).
    nonisolated(unsafe) static var trackedMenu: NSMenu?
    static let keys = ["interface", "port", "expert", "syncDirection", "syncThrottle", "arduinoDelay", "uiStyle", "avrdudePath"]

    static func preferences() -> [String: Any] {
        var p: [String: Any] = [:]
        for k in keys { if let v = UserDefaults.standard.object(forKey: k) { p[k] = v } }
        return p
    }

    static func restore(_ p: [String: Any]) {
        for k in keys { if let v = p[k] { UserDefaults.standard.set(v, forKey: k) } else { UserDefaults.standard.removeObject(forKey: k) } }
    }

    static func fromArguments() -> UITest? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--uitest"), i + 1 < a.count else { return nil }
        var out = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("blheli-uitest")
        if let o = a.firstIndex(of: "--out"), o + 1 < a.count { out = URL(fileURLWithPath: a[o + 1]) }
        return UITest(port: a[i + 1], out: out)
    }

    init(port: String, out: URL) {
        self.port = port
        self.out = out
        saved = Self.preferences()
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    }

    // MARK: - Helpers

    func check(_ ok: Bool, _ what: String, _ detail: String = "") {
        results.append(["ok": ok, "check": what, "detail": detail])
        if !ok { failures += 1 }
        print("UITEST \(ok ? "ok  " : "FAIL") \(what)\(detail.isEmpty ? "" : "  [\(detail)]")")
        fflush(stdout)
    }

    var mainWindow: NSWindow? { NSApp.windows.first { $0.title.hasPrefix("BLHeliSuite") } }

    func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }

    func waitIdle(_ model: AppModel, timeout: Double = 60) async {
        await pause(0.3)
        let t0 = Date()
        while model.busy && Date().timeIntervalSince(t0) < timeout { await pause(0.1) }
        await pause(0.4)
    }

    /// Point of the SwiftUI root view (top left origin, below the title bar) → window coordinates.
    func windowPoint(_ p: CGPoint, in w: NSWindow) -> NSPoint {
        let r = w.contentLayoutRect
        return NSPoint(x: r.minX + p.x, y: r.maxY - p.y)
    }

    /// eventNumber of the synthetic mouse events – everything else is kept away from the window.
    nonisolated static let marker = 0x5EED
    var inputFilter: Any?
    var droppedEvents = 0

    /// The real mouse / keyboard of whoever sits at the Mac must not interfere: a real mouse move
    /// between a synthetic down and up cancels a tap, real typing would land in the test window.
    func isolateFromRealInput() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .mouseEntered, .mouseExited, .leftMouseDown, .leftMouseUp,
                                           .rightMouseDown, .rightMouseUp, .leftMouseDragged, .rightMouseDragged,
                                           .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel, .keyDown, .keyUp]
        inputFilter = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in
            switch e.type {
            case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp:
                if e.eventNumber == UITest.marker { return e }
            case .keyDown, .keyUp:
                if e.keyCode == 53 { return e }  // Escape posted by the popup test
            default: break
            }
            self?.droppedEvents += 1
            return nil
        }
    }

    func post(_ type: NSEvent.EventType, at wp: NSPoint, in w: NSWindow) {
        let down = type == .leftMouseDown || type == .rightMouseDown
        guard let e = NSEvent.mouseEvent(with: type, location: wp, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: w.windowNumber, context: nil, eventNumber: Self.marker,
                                         clickCount: 1, pressure: down ? 1 : 0) else { return }
        NSApp.postEvent(e, atStart: false)
    }

    var inactiveClicks = 0

    /// The test runs from a terminal that may take the focus back – a click into an inactive
    /// window only activates it (like on any Mac), so make the app active first.
    func ensureActive(_ w: NSWindow) async {
        for _ in 0..<20 where !(NSApp.isActive && (w.isKeyWindow || w.isSheet || w.attachedSheet != nil)) {
            NSApp.activate(ignoringOtherApps: true)
            (w.sheetParent ?? w).makeKeyAndOrderFront(nil)
            await pause(0.1)
        }
        if !NSApp.isActive { inactiveClicks += 1 }
    }

    func click(windowPoint wp: NSPoint, in w: NSWindow, right: Bool = false) async {
        await ensureActive(w)
        post(right ? .rightMouseDown : .leftMouseDown, at: wp, in: w)
        await pause(0.08)
        post(right ? .rightMouseUp : .leftMouseUp, at: wp, in: w)
        await pause(0.35)
    }

    /// Click at a position of the classic main window (778 × 602, top left origin).
    func click(_ x: CGFloat, _ y: CGFloat, right: Bool = false) async {
        guard let w = mainWindow else { check(false, "main window present"); return }
        await click(windowPoint: windowPoint(CGPoint(x: x, y: y), in: w), in: w, right: right)
    }

    func view(named id: String, in v: NSView?) -> NSView? {
        guard let v else { return nil }
        if v.identifier?.rawValue == id { return v }
        for s in v.subviews { if let f = view(named: id, in: s) { return f } }
        return nil
    }

    func menuBarPoint(_ title: String) -> NSPoint? {
        guard let w = mainWindow, let v = view(named: "menu:" + title, in: w.contentView) else { return nil }
        let r = v.convert(v.bounds, to: nil)
        return NSPoint(x: r.midX, y: r.midY)
    }

    /// Clicks an item of the in-window menu bar and returns the menu it opened.
    func openMenu(_ title: String) async -> NSMenu? {
        guard let w = mainWindow, let p = menuBarPoint(title) else {
            check(false, "menu bar item \"\(title)\" found")
            return nil
        }
        captured = nil
        await click(windowPoint: p, in: w)
        check(captured != nil, "click on menu \"\(title)\" opens it")
        return captured?.menu
    }

    /// Clicks a combo box / button and returns the menu it opened.
    func openPopup(_ what: String, _ x: CGFloat, _ y: CGFloat) async -> NSMenu? {
        captured = nil
        await click(x, y)
        check(captured != nil, "click on \(what) opens its list")
        return captured?.menu
    }

    func titles(_ m: NSMenu?) -> [String] { m?.items.map { $0.isSeparatorItem ? "-" : $0.title } ?? [] }

    func item(_ m: NSMenu?, _ title: String) -> NSMenuItem? { m?.items.first { $0.title == title } }

    @discardableResult
    func choose(_ m: NSMenu?, _ title: String) -> Bool {
        guard let m, let i = m.items.firstIndex(where: { $0.title == title }) else {
            check(false, "menu item \"\(title)\" present", titles(m).joined(separator: " | "))
            return false
        }
        guard m.items[i].isEnabled else {
            check(false, "menu item \"\(title)\" enabled")
            return false
        }
        m.performActionForItem(at: i)
        return true
    }

    /// Centre of a page control tab (WinTabBar: Tahoma 13 + 2 × 7 padding, selected tab −2 px each side).
    func tab(_ title: String, _ model: AppModel) -> CGPoint? {
        var tabs = [(MainTab.setup, model.setupTabTitle), (.overview, "ESC overview")]
        if model.interfaceType.isFlightController { tabs.append((.motors, "Motors")) }
        if model.expertMode { tabs.append((.expert, "Expert tools")) }
        tabs.append((.interfaces, "Make interfaces"))
        let current = tabs.contains { $0.0 == model.selectedTab } ? model.selectedTab : .setup
        let font = NSFont(name: "Tahoma", size: 13) ?? .systemFont(ofSize: 13)
        var x: CGFloat = 4
        for (id, t) in tabs {
            var w = ceil((t as NSString).size(withAttributes: [.font: font]).width) + 14
            if id == current { w -= 4 }
            if t == title { return CGPoint(x: x + w / 2, y: 38) }
            x += w
        }
        check(false, "tab \"\(title)\" present")
        return nil
    }

    var retries: [String] = []

    func clickTab(_ title: String, _ model: AppModel) async {
        let target: MainTab = title == "ESC overview" ? .overview : title == "Motors" ? .motors : title == "Expert tools" ? .expert
            : title == "Make interfaces" ? .interfaces : .setup
        for attempt in 0..<2 {
            await pause(0.2)
            if let p = tab(title, model) { await click(p.x, p.y) }
            if model.selectedTab == target { return }
            if attempt == 0 { retries.append("tab \(title)") }
        }
    }

    func snapshot(_ name: String, window: NSWindow? = nil) {
        guard let w = window ?? mainWindow, let png = ClassicMenuBar.contentPNG(of: w) else { return }
        try? png.write(to: out.appendingPathComponent(name + ".png"))
    }

    // MARK: - Test

    func run(_ model: AppModel) {
        UserDefaults.standard.set("classic", forKey: "uiStyle")
        MenuAnchor.interceptor = { [weak self] menu, view in
            self?.captured = (menu, view.convert(view.bounds, to: nil))
        }
        isolateFromRealInput()
        // hard limit: never leave a hanging test process behind
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: 300)
            print("UITEST FAIL timeout")
            exit(3)
        }
        Task { @MainActor in
            await pause(1.5)
            await steps(model)
            finish(model)
        }
    }

    func steps(_ model: AppModel) async {
        guard let w = mainWindow else { check(false, "main window present"); return }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        await pause(0.5)
        let size = w.contentLayoutRect.size
        check(size == ClassicMainView.size, "classic window content 778 × 602", "\(Int(size.width)) × \(Int(size.height))")
        model.syncDirection = false
        model.syncThrottle = true
        model.expertMode = false
        snapshot("ui-0-start")

        // Expert tools input parsing (addresses, hex bytes)
        let numbers: [(String, Int?)] = [("0x1A00", 0x1A00), ("1A00", 0x1A00), ("1a00h", 0x1A00), ("$1A00", 0x1A00), (" 6656 ", 6656),
                                         ("112", 112), ("0x", nil), ("", nil), ("1G00", nil), ("-5", nil)]
        check(numbers.allSatisfy { AppModel.parseNumber($0.0) == $0.1 }, "address parsing",
              numbers.map { "\($0.0)→\(AppModel.parseNumber($0.0).map(String.init) ?? "nil")" }.joined(separator: " "))
        let bytes: [(String, [UInt8]?)] = [("01 02 FF", [1, 2, 255]), ("0x01,0x02", [1, 2]), ("$a5", [0xA5]),
                                          ("01 GG", nil), ("100", nil), ("", nil)]
        check(bytes.allSatisfy { AppModel.parseBytes($0.0) == $0.1 }, "hex byte parsing (no partial lists)")

        // Interface menu (letters, unsupported entries disabled, check mark)
        if model.interfaceType == .silabsBLBFlightController { model.interfaceType = .atmelBLBFourWay }
        var m = await openMenu("Select ATMEL / SILABS Interface")
        check(titles(m).count == 14, "interface menu: 14 entries", "\(titles(m).count)")
        let disabled = m?.items.filter { !$0.isSeparatorItem && !$0.isEnabled }.map(\.title) ?? []
        check(disabled.count == 4, "interface menu: C, 1, 4, 5 disabled", disabled.joined(separator: "; "))
        check(m?.items.allSatisfy { $0.isSeparatorItem || $0.image != nil } ?? false, "interface menu: every entry has its letter badge")
        choose(m, "SILABS BLHeli Bootloader (4way-if)")
        check(model.interfaceType == .silabsBLBFourWay, "menu selects interface D")
        await pause(0.3)
        m = await openMenu("Select ATMEL / SILABS Interface")
        check(item(m, "SILABS BLHeli Bootloader (4way-if)")?.state == .on, "menu: current interface checked")
        choose(m, "SILABS BLHeli Bootloader (Cleanflight)")
        check(model.interfaceType == .silabsBLBFlightController, "menu selects interface E")
        await pause(0.3)

        // Baud combo: list anchored right below the combo
        m = await openPopup("the Baud combo", 254, 558)
        if let r = captured?.rect {
            let top = 602 - 548.0
            check(abs(r.minX - 222) < 2 && abs(r.maxY - top) < 2 && abs(r.width - 65) < 2,
                  "Baud list positioned at the combo", "\(r)")
        }
        choose(m, "57600")
        check(model.baud == 57600, "Baud combo: 57600 chosen")
        m = await openPopup("the Baud combo", 254, 558)
        check(item(m, "57600")?.state == .on, "Baud combo: current value checked")
        choose(m, "115200")
        check(model.baud == 115200, "Baud combo: 115200 chosen")

        // Port combo (the simulator pty is not a system serial port – set directly afterwards)
        m = await openPopup("the Port combo", 106, 558)
        check(!titles(m).isEmpty, "Port combo: list built", titles(m).joined(separator: " | "))
        model.portPath = port
        await pause(0.3)

        // Connect button → connect + check
        await click(345, 558)
        await waitIdle(model)
        check(model.connected, "Connect button connects", model.connectionInfo)
        check(model.slots.count == 4 && model.slots.allSatisfy { $0.state == .ok }, "Check finds 4 ESCs",
              model.slots.map { "\($0.state)" }.joined(separator: ","))
        check(model.workspace != nil && model.masterIndex == 0, "setup of master ESC#1 loaded")
        snapshot("ui-1-connected")

        // Multiple ESC buttons: left click toggles, right click selects a single ESC
        func esc(_ i: Int) -> CGPoint { CGPoint(x: 400 + MultipleESCGroup.xs[i] + 12.5, y: 560.5) }
        await click(esc(1).x, esc(1).y)
        check(model.active == [0, 2, 3], "left click on ESC#2 deactivates it", "\(model.active.sorted())")
        await click(esc(1).x, esc(1).y)
        check(model.active == [0, 1, 2, 3], "left click on ESC#2 activates it", "\(model.active.sorted())")
        await click(esc(2).x, esc(2).y, right: true)
        check(model.active == [2] && model.masterIndex == 2, "right click on ESC#3 selects it as single ESC", "\(model.active.sorted())")
        check(model.workspace != nil, "single ESC#3 setup shown")
        snapshot("ui-2-single-esc3")
        await click(400 + 223 + 17, 560.5)
        check(model.clipboard != nil, "Copy button stores the setup")
        for i in [0, 1, 3] { await click(esc(i).x, esc(i).y) }
        check(model.active == [0, 1, 2, 3] && model.masterIndex == 0, "all 4 ESCs active again, master ESC#1", "\(model.active.sorted())")

        // Tabs
        await clickTab("ESC overview", model)
        check(model.selectedTab == .overview, "tab \"ESC overview\"")
        snapshot("ui-3-overview")
        await clickTab(model.setupTabTitle, model)
        check(model.selectedTab == .setup, "tab \"\(model.setupTabTitle)\"")

        // Parameter box Beep Strength (575, 126): scroll bar arrows, Undo, Default
        guard model.workspace != nil, let ctx = model.workspaceContext else { check(false, "setup loaded"); return }
        let beep0 = model.workspace?.value(.beepStrength) ?? -1
        func beep() -> Int { model.workspace?.value(.beepStrength) ?? -1 }
        await click(724.5, 216.5)
        check(beep() == beep0 + 1, "scroll bar right arrow: +1", "\(beep0) → \(beep())")
        await click(626.5, 216.5)
        check(beep() == beep0, "scroll bar left arrow: −1", "\(beep())")
        await click(724.5, 216.5)
        await click(724.5, 216.5)
        await click(749.5, 194)
        check(beep() == beep0, "Undo button: value read from the ESC", "\(beep())")
        let def = BLHeliParamLogic.defaultValue(.beepStrength, ctx)
        if def == beep0 { await click(724.5, 216.5) }
        await click(749.5, 218)
        check(beep() == def, "Default button: default value", "\(beep()) / \(def ?? -1)")
        await click(749.5, 194)
        check(beep() == beep0, "Undo after Default", "\(beep())")

        // Misc check box "Programming by TX" (385, 10)
        let tx0 = model.workspace?.value(.enableTxProgramming)
        await click(400, 99.5)
        check(model.workspace?.value(.enableTxProgramming) != tx0, "check box \"Programming by TX\" toggles")
        await click(400, 99.5)
        check(model.workspace?.value(.enableTxProgramming) == tx0, "check box toggles back")

        // Motor direction (385, 68): non numeric parameter, next allowed value
        let dir0 = model.workspace?.value(.direction) ?? 0
        await click(534.5, 158.5)
        let dir1 = model.workspace?.value(.direction) ?? 0
        check(dir1 != dir0, "Motor Direction scroll bar: next value", "\(dir0) → \(dir1)")

        // Name field: click + type
        await click(87, 101.5)
        if let tv = w.firstResponder as? NSTextView {
            tv.selectAll(nil)
            tv.insertText("UITEST", replacementRange: tv.selectedRange())
        }
        await pause(0.3)
        check(model.workspace?.name == "UITEST", "typing into the ESC name field", model.workspace?.name ?? "nil")
        check(model.workspaceModified, "status: setup changed")
        snapshot("ui-4-edited")
        w.makeFirstResponder(nil)

        // Write Setup button
        let slaveDirs = model.slots.dropFirst().map { $0.settings?.value(.direction) ?? -1 }
        await click(188, 511.5)
        await waitIdle(model)
        let s = model.slots.map(\.settings)
        check(s[0]?.name == "UITEST" && s[0]?.value(.direction) == dir1, "Write Setup: master ESC#1 written")
        check(s.dropFirst().allSatisfy { $0?.name != "UITEST" }, "Write Setup: slaves keep their own names")
        check(s.dropFirst().map { $0?.value(.direction) ?? -1 } == slaveDirs, "Write Setup: slaves keep their direction (sync off)")
        check(!model.workspaceModified, "status: setup written")

        // In-window menu "ESC setup"
        m = await openMenu("ESC setup")
        check(item(m, "Undo all changes")?.isEnabled == false && item(m, "Write Setup")?.isEnabled == true,
              "ESC setup menu: enabled states")
        model.setValue(.beepStrength, beep0 == 80 ? 81 : 80)
        choose(m, "Read Setup")
        await waitIdle(model)
        check(model.workspace?.name == "UITEST" && model.workspace?.value(.beepStrength) == beep0,
              "ESC setup menu → Read Setup reads ESC#1 again")

        // Options menu: Expert Mode → Expert tools tab → Read Memory
        m = await openMenu("Options")
        check(item(m, "Expert Mode")?.state == .off, "Options: Expert Mode unchecked")
        choose(m, "Expert Mode")
        check(model.expertMode, "Options → Expert Mode")
        await pause(0.3)
        await clickTab("Expert tools", model)
        check(model.selectedTab == .expert, "tab \"Expert tools\"")
        await click(80, 275.5)
        await waitIdle(model)
        check(model.expertDump.hasPrefix("1A00"), "Read Memory shows the setup page", String(model.expertDump.prefix(60)))
        snapshot("ui-5-expert")
        m = await openMenu("Options")
        choose(m, "Expert Mode")
        check(!model.expertMode, "Options → Expert Mode off")
        await pause(0.3)

        // Make interfaces: Arduino board combo + 4way-interface button
        await clickTab("Make interfaces", model)
        check(model.selectedTab == .interfaces, "tab \"Make interfaces\"")
        let board0 = model.arduinoBoard
        m = await openPopup("the Arduino board combo", 582, 107.5)
        check(titles(m).count == ArduinoBoard.all.count, "board list complete", "\(titles(m).count)")
        if let other = ArduinoBoard.all.first(where: { $0 != board0 }) {
            choose(m, other.name)
            check(model.arduinoBoard == other, "board chosen: \(other.name)")
        }
        model.arduinoBoard = board0
        m = await openPopup("\"Arduino 4way-interface\"", 537, 386.5)
        check(titles(m).count == 3 && (m?.items.contains { $0.isEnabled } ?? false), "4way variants listed", titles(m).joined(separator: " | "))
        snapshot("ui-6-interfaces")

        // Flash BLHeli → classic flash assistant sheet → Cancel
        await clickTab(model.setupTabTitle, model)
        await click(295.5, 511.5)
        await pause(1.5)
        check(model.showFlashAssistant && w.attachedSheet != nil, "Flash BLHeli opens the flash assistant")
        if let sheet = w.attachedSheet {
            snapshot("ui-7-flash-assistant", window: sheet)
            await click(windowPoint: windowPoint(CGPoint(x: 175.5, y: 377.5), in: sheet), in: sheet)
            await pause(1.0)
            check(!model.showFlashAssistant && w.attachedSheet == nil, "Cancel closes the flash assistant")
        }

        // Motors: Connect FC (closes the 4-way session), enable, STOP, then back to the ESCs
        await clickTab("Motors", model)
        check(model.selectedTab == .motors, "tab \"Motors\"")
        await click(73.5, 442.5)
        await pause(2.5)
        check(model.motorSessionOpen && !model.connected, "Connect FC opens the MSP session", model.motorInfo)
        await click(200, 447.5)
        check(model.motorRunning, "motor control enabled by the check box")
        snapshot("ui-8-motors")
        await click(723, 474.5)
        check(!model.motorRunning, "STOP stops the motor test")
        await clickTab(model.setupTabTitle, model)
        await click(83, 511.5)
        await waitIdle(model)
        check(model.connected && !model.motorSessionOpen && model.slots.count == 4, "Read Setup after the motor test reconnects the ESCs",
              model.status)

        // A real popup menu (no hook): opens, is tracked and closes again
        MenuAnchor.interceptor = nil
        UITest.trackedMenu = nil
        let obs = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { n in
            UITest.trackedMenu = n.object as? NSMenu
            let t = Timer(timeInterval: 0.8, repeats: false) { _ in UITest.trackedMenu?.cancelTracking() }
            RunLoop.main.add(t, forMode: .common)
        }
        // fallback if the notification does not come: Escape closes an open menu
        let escape = Timer(timeInterval: 3, repeats: false) { _ in
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: 0, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
                                            isARepeat: false, keyCode: 53) {
                    NSApp.postEvent(e, atStart: false)
                }
            }
        }
        RunLoop.main.add(escape, forMode: .common)
        let t0 = Date()
        if let p = menuBarPoint("Options") { await click(windowPoint: p, in: w) }
        await pause(1.5)
        escape.invalidate()
        NotificationCenter.default.removeObserver(obs)
        check(UITest.trackedMenu?.items.contains { $0.title == "Expert Mode" } ?? false, "real popup of the Options menu opens and closes",
              String(format: "%.1f s", Date().timeIntervalSince(t0)))
        MenuAnchor.interceptor = { [weak self] menu, view in self?.captured = (menu, view.convert(view.bounds, to: nil)) }

        // Disconnect
        await click(345, 558)
        await pause(0.8)
        check(!model.connected, "Disconnect button")
        snapshot("ui-9-disconnected")
    }

    func finish(_ model: AppModel) {
        MenuAnchor.interceptor = nil
        if let f = inputFilter { NSEvent.removeMonitor(f) }
        Self.restore(saved)
        let errors = model.log.filter { $0.level == .error }.map(\.message)
        let report: [String: Any] = ["checks": results, "failures": failures, "errors": errors, "retries": retries,
                                     "inactiveClicks": inactiveClicks, "droppedRealEvents": droppedEvents]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: out.appendingPathComponent("uitest.json"))
        }
        print("UITEST RESULT \(results.count - failures)/\(results.count) passed, \(errors.count) logged errors, \(inactiveClicks) clicks while inactive, retries: \(retries), real input events ignored: \(droppedEvents)")
        fflush(stdout)
        model.disconnect()
        model.motorClose()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
    }
}
