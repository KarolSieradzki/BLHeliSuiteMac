import AppKit
import VCL
import BLHeliCore

// BLHeliSuite for macOS – program start (BLHeliSuite.dpr: Application.CreateForm(TfrmBLHeliSuiteMain…); Application.Run).

final class AppDelegate: NSObject, NSApplicationDelegate {
    var main: TfrmBLHeliSuiteMain?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DFMLoader.frameClasses = [
            "TfraESCCombos": TfraESCCombos.self, "TfraESCTable": TfraESCTable.self,
            "TfraCFMotorTest": TfraCFMotorTest.self, "TfraMakeInterfaces": TfraMakeInterfaces.self,
            "TfraSelectIspParams": TfraSelectIspParams.self, "TfraSetupArduinoUSBLinker": TfraSetupArduinoUSBLinker.self,
            "TfraAlternateSpeedTest": TfraAlternateSpeedTest.self, "TfraMotorControl": TfraMotorControl.self, "TfraAVRFuses": TfraAVRFuses.self,
        ]
        buildMacMenu()
        let m = TfrmBLHeliSuiteMain(resource: "TFRMBLHELISUITEMAIN")
        main = m
        Application.shared.mainForm = m
        Application.shared.startIdleProcessing()
        m.show()
        NSApp.activate(ignoringOtherApps: true)
        DevTools.start(m)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        if let m = main { m.FormClose(m, TCloseArgs(.caFree)) }
    }

    /// macOS application menu (the BLHeliSuite menus are inside the window like on Windows).
    func buildMacMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem()
        bar.addItem(appItem)
        let app = NSMenu()
        app.addItem(withTitle: "About BLHeliSuite", action: #selector(showAbout), keyEquivalent: "").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Hide BLHeliSuite", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit BLHeliSuite", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app
        let editItem = NSMenuItem()
        bar.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        let winItem = NSMenuItem()
        bar.addItem(winItem)
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winItem.submenu = win
        NSApp.mainMenu = bar
        NSApp.windowsMenu = win
    }

    @objc func showAbout() { main?.actShowAboutExecute(self) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
