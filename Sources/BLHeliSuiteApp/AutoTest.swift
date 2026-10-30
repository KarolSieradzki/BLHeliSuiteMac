import AppKit
import SwiftUI
import BLHeliCore

/// GUI self test driven from the command line:
///   BLHeliSuite --autotest <serial port> --out <folder> [--interface E|D|6|2]
/// Connects, checks, edits + writes a setting, flashes the newest matching firmware and stores
/// window snapshots plus a JSON summary. Used with blheli-sim during development.
@MainActor
final class AutoTest {
    static var current: AutoTest?
    let port: String
    let out: URL
    let interface: InterfaceType
    var report: [String: Any] = [:]
    var steps: [String] = []
    /// The user's preferences before the test (taken before `--style` is applied).
    let saved: [String: Any]

    static func fromArguments() -> AutoTest? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--autotest"), i + 1 < a.count else { return nil }
        var out = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("blheli-autotest")
        if let o = a.firstIndex(of: "--out"), o + 1 < a.count { out = URL(fileURLWithPath: a[o + 1]) }
        var itf = InterfaceType.silabsBLBFlightController
        if let o = a.firstIndex(of: "--interface"), o + 1 < a.count, let t = InterfaceType(rawValue: a[o + 1]) { itf = t }
        return AutoTest(port: a[i + 1], out: out, interface: itf)
    }

    init(port: String, out: URL, interface: InterfaceType) {
        self.port = port
        self.out = out
        self.interface = interface
        saved = UITest.preferences()
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    }

    func wait(_ model: AppModel, timeout: TimeInterval = 60) async {
        let t0 = Date()
        try? await Task.sleep(nanoseconds: 300_000_000)
        while model.busy && Date().timeIntervalSince(t0) < timeout {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    func snapshot(_ name: String) {
        for (i, w) in NSApp.windows.enumerated() where w.isVisible && (w.contentView?.bounds.width ?? 0) > 10 {
            if let png = ClassicMenuBar.contentPNG(of: w) {
                try? png.write(to: out.appendingPathComponent(i == 0 ? "\(name).png" : "\(name)-\(i).png"))
            }
        }
        steps.append(name)
    }

    func run(_ model: AppModel) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            model.interfaceType = interface
            model.portPath = port
            model.baud = interface.defaultBaud
            try? await Task.sleep(nanoseconds: 500_000_000)
            snapshot("0-start")
            model.connect()
            await wait(model)
            report["connected"] = model.connected
            report["connection"] = model.connectionInfo
            report["slots"] = model.slots.map { "#\($0.index + 1) \($0.state) \($0.settings?.summary(database: model.database) ?? "-")" }
            snapshot("1-setup")
            model.selectedTab = .overview
            try? await Task.sleep(nanoseconds: 800_000_000)
            snapshot("2-overview")
            model.selectedTab = .setup
            try? await Task.sleep(nanoseconds: 500_000_000)
            // edit + write setup
            if model.workspace != nil {
                model.setValue(.direction, 2)
                model.setValue(.beepStrength, 77)
                snapshot("3-edited")
                model.writeSetup()
                await wait(model)
                report["afterWrite"] = model.slots.map { "#\($0.index + 1) dir=\($0.settings?.value(.direction) ?? -1) beep=\($0.settings?.value(.beepStrength) ?? -1)" }
            }
            // flash assistant UI
            model.showFlashAssistant = true
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            snapshot("4-flash-assistant")
            model.showFlashAssistant = false
            try? await Task.sleep(nanoseconds: 800_000_000)
            // flash newest firmware for the master
            if let db = model.database, let m = model.masterIndex, m < model.slots.count, let dev = model.slots[m].device,
               let e = FirmwareSelection.preferred(db, device: dev, settings: model.slots[m].settings) {
                report["flashEntry"] = "\(e.name) \(e.firmwareName) \(e.revStr) \(e.modeName)"
                model.active = [m]
                model.flash(entry: e, keepSettings: true)
                await wait(model, timeout: 180)
                await wait(model)
                report["afterFlash"] = model.slots.map { "#\($0.index + 1) \($0.state) \($0.settings?.summary(database: model.database) ?? "-") dir=\($0.settings?.value(.direction) ?? -1)" }
                snapshot("5-after-flash")
            }
            model.selectedTab = .log
            try? await Task.sleep(nanoseconds: 800_000_000)
            snapshot("6-log")
            model.selectedTab = .interfaces
            try? await Task.sleep(nanoseconds: 600_000_000)
            snapshot("7-interfaces")
            model.expertMode = true
            model.selectedTab = .expert
            try? await Task.sleep(nanoseconds: 600_000_000)
            snapshot("8-expert")
            model.expertMode = false
            model.selectedTab = .motors
            model.motorOpen()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            report["motors"] = model.motorInfo
            snapshot("9-motors")
            model.motorClose()
            report["errors"] = model.log.filter { $0.level == .error }.map(\.message)
            report["status"] = model.status
            report["steps"] = steps
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: out.appendingPathComponent("report.json"))
            }
            model.disconnect()
            try? await Task.sleep(nanoseconds: 500_000_000)
            UITest.restore(saved)   // the test switched interface, port and look
            NSApp.terminate(nil)
        }
    }
}
