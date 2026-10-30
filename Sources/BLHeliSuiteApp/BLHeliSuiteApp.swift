import SwiftUI
import AppKit
import BLHeliCore

@main
struct BLHeliSuiteMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("BLHeliSuite") {
            RootView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
        .commands { AppCommands(model: model) }
        Window("Logged Messages", id: "log") {
            ClassicLogWindow()
                .environmentObject(model)
        }
        .defaultSize(width: 640, height: 320)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Also behave like a normal app when started from a terminal (swift run).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct AppCommands: Commands {
    @ObservedObject var model: AppModel
    @AppStorage("uiStyle") private var uiStyle = "classic"
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(after: .toolbar) {
            Toggle("Classic BLHeliSuite Look", isOn: Binding(get: { uiStyle != "modern" }, set: { uiStyle = $0 ? "classic" : "modern" }))
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Show Log Window") { openWindow(id: "log") }
                .keyboardShortcut("l", modifiers: [.command, .option])
        }
        CommandMenu("ESC Setup") {
            Button("Read Setup") { model.readSetup() }.keyboardShortcut("r")
            Button("Write Setup") { model.writeSetup() }.keyboardShortcut("w").disabled(!model.connected || model.workspace == nil)
            Divider()
            Button("Save Setup to File…") { model.saveSetupToFile() }.keyboardShortcut("s").disabled(model.workspace == nil)
            Button("Load Setup from File…") { model.loadSetupFromFile() }.keyboardShortcut("o").disabled(model.workspace == nil)
            Divider()
            Button("Flash BLHeli…") { model.flashBLHeli() }.keyboardShortcut("f")
            Button("Flash Other…") { model.flashOther() }
        }
        CommandMenu("Interface") {
            Picker("Select Interface", selection: $model.interfaceType) {
                Section("SiLabs") {
                    ForEach([InterfaceType.silabsBLBFlightController, .silabsBLBFourWay, .silabsC2FourWay, .silabsC2Toolstick]) { t in
                        Text(t.title).tag(t)
                    }
                }
                Section("Atmel") {
                    ForEach([InterfaceType.atmelFlightController, .atmelBLBFourWay, .atmelSKFourWay, .atmelISP]) { t in
                        Text(t.title).tag(t)
                    }
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button(model.connected ? "Disconnect" : "Connect") { model.toggleConnection() }.keyboardShortcut("k")
            Button("Check ESCs") { model.check() }.disabled(!model.connected)
            Button("Refresh Ports") { model.refreshPorts() }
        }
        CommandMenu("Options") {
            Toggle("Expert Mode", isOn: $model.expertMode)
            Toggle("Verify Flash after Write", isOn: $model.verifyFlash)
            Divider()
            Toggle("Sync Motor Direction to Multiple ESC", isOn: $model.syncDirection)
            Toggle("Sync Min/Center/Max Throttle to Multiple ESC", isOn: $model.syncThrottle)
            Divider()
            Toggle("Log Protocol Traffic", isOn: $model.protocolTrace)
        }
        CommandGroup(replacing: .help) {
            ManualsMenu()
        }
    }
}

/// Opens the PDF manuals shipped with BLHeliSuite (bundled in Resources/Manuals).
struct ManualsMenu: View {
    var body: some View {
        let manuals = Manuals.list()
        if manuals.isEmpty {
            Text("Manuals not found")
        } else {
            ForEach(manuals, id: \.self) { url in
                Button(url.deletingPathExtension().lastPathComponent) { NSWorkspace.shared.open(url) }
            }
        }
    }
}

enum Manuals {
    static func folder() -> URL? {
        var candidates: [URL] = []
        if let r = Bundle.main.resourceURL { candidates.append(r.appendingPathComponent("Manuals")) }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        var d = exe
        for _ in 0..<6 {
            candidates.append(d.appendingPathComponent("Resources/Manuals"))
            candidates.append(d.appendingPathComponent("BLHeliSuite/Manuals"))
            d = d.deletingLastPathComponent()
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func list() -> [URL] {
        guard let f = folder(), let items = try? FileManager.default.contentsOfDirectory(at: f, includingPropertiesForKeys: nil) else { return [] }
        return items.filter { ["pdf", "xls"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
