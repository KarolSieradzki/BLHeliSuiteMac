import AppKit
import VCL
import BLHeliCore

/// Frame TfraAlternateSpeedTest (VMT 0x649000…): ramp up, then alternate the selected motors between two speeds.
@objc(TfraAlternateSpeedTest) final class TfraAlternateSpeedTest: TFrame {
    @objc var pnlAlternateSpeedTest: TPanel!
    @objc var swtTest: TSwitch!
    @objc var grbStartPhase: TGroupBox!
    @objc var lblRampToPPM: TLabel!
    @objc var lblWaitAtRamp: TLabel!
    @objc var lblWaitStart: TLabel!
    @objc var sedRampToPPM: TSpinEdit!
    @objc var sedWaitAtRamp: TSpinEdit!
    @objc var sedWaitStart: TSpinEdit!
    @objc var grbLoopPhase: TGroupBox!
    @objc var lblStep1ToPPM: TLabel!
    @objc var lblStep1SettleTime: TLabel!
    @objc var lblStep2PPM: TLabel!
    @objc var lblStep2SettleTime: TLabel!
    @objc var lblLoopCount: TLabel!
    @objc var sedStep1ToPPM: TSpinEdit!
    @objc var sedStep1SettleTime: TSpinEdit!
    @objc var sedStep2ToPPM: TSpinEdit!
    @objc var sedStep2SettleTime: TSpinEdit!
    @objc var sedLoopCount: TSpinEdit!
    @objc var lblCountDown: TLabel!
    @objc var lblStartDelayLeft: TLabel!
    @objc var grbMotors: TGroupBox!
    @objc var lblMotorNrs: TLabel!
    @objc var cbxMotor1: TCheckBox!
    @objc var cbxMotor2: TCheckBox!
    @objc var cbxMotor3: TCheckBox!
    @objc var cbxMotor4: TCheckBox!
    @objc var cbxMotor5: TCheckBox!
    @objc var cbxMotor6: TCheckBox!
    @objc var cbxMotor7: TCheckBox!
    @objc var cbxMotor8: TCheckBox!
    @objc var aevSpeedTest: TDummyComponent!
    @objc var Button1: TButton!
    @objc var grbSettings: TGroupBox!
    @objc var cbxSettings: TComboBox!
    @objc var btnStoreSettings: TButton!
    @objc var btnRestoreSettings: TButton!
    @objc var btnDeleteSettings: TButton!

    weak var test: TfraCFMotorTest?        // +0x324 FC interface
    var running = false                    // +0x331
    var savedValues: [Int] = []            // +0x332
    var keyMonitor: Any?
}

extension TfraAlternateSpeedTest {
    var boxes: [TCheckBox] { [cbxMotor1, cbxMotor2, cbxMotor3, cbxMotor4, cbxMotor5, cbxMotor6, cbxMotor7, cbxMotor8] }
    var spins: [(String, TSpinEdit)] {
        [("RampToPPM", sedRampToPPM), ("WaitAtRamp", sedWaitAtRamp), ("WaitStart", sedWaitStart), ("Step1ToPPM", sedStep1ToPPM),
         ("Step1SettleTime", sedStep1SettleTime), ("Step2ToPPM", sedStep2ToPPM), ("Step2SettleTime", sedStep2SettleTime), ("LoopCount", sedLoopCount)]
    }

    /// AltSpeedTest.cfg / AltSpeedTest3D.cfg: stored settings.
    var settingsFile: URL {
        AppFolders.userFolder.appendingPathComponent(test?.mode3D == true ? "AltSpeedTest3D.cfg" : "AltSpeedTest.cfg")
    }

    func loadSettings() -> [String: [String: Int]] {
        guard let t = try? String(contentsOf: settingsFile, encoding: .utf8) else { return [:] }
        var out: [String: [String: Int]] = [:]
        var cur = ""
        for l in t.components(separatedBy: .newlines) {
            let s = l.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("[") && s.hasSuffix("]") { cur = String(s.dropFirst().dropLast()); out[cur] = [:]; continue }
            let kv = s.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2, !cur.isEmpty, let v = Int(kv[1]) { out[cur]?[kv[0]] = v }
        }
        return out
    }

    func saveSettings(_ s: [String: [String: Int]]) {
        var t = ""
        for k in s.keys.sorted() {
            t += "[\(k)]\r\n"
            for (n, v) in s[k]!.sorted(by: { $0.key < $1.key }) { t += "\(n)=\(v)\r\n" }
        }
        try? t.write(to: settingsFile, atomically: true, encoding: .utf8)
    }

    /// FUN_0064A18C: called when the form is activated.
    func prepare(_ t: TfraCFMotorTest) {
        test = t
        for (i, b) in boxes.enumerated() {
            b.enabled = i < t.motorCount
            b.checked = i < t.motorCount
        }
        for (_, s) in spins where s !== sedLoopCount && s !== sedWaitAtRamp && s !== sedWaitStart
            && s !== sedStep1SettleTime && s !== sedStep2SettleTime {
            s.minValue = Double(t.motorCommand)
            s.maxValue = Double(t.motorMax)
        }
        cbxSettings.items = loadSettings().keys.sorted()
        lblCountDown.caption = ""
        swtTest.enabled = !t.armed
    }

    var selected: [Int] { boxes.enumerated().filter { $0.element.checked && $0.element.enabled }.map { $0.offset + 1 } }

    /// FUN_0064A4B4 + FUN_0064A42C: selected motors to `v`, false when the FC does not take it.
    func setMotors(_ v: Int) -> Bool {
        guard let t = test, let c = t.msp else { return false }
        for i in selected { t.values[i] = v }
        do {
            try c.setMotors((1...8).map { $0 <= t.motorCount ? t.values[$0] : t.motorCommand })
            return true
        } catch {
            return false
        }
    }

    /// FUN_0064A268: waits `ms`, stops early when the test is switched off.
    func wait(ms: Int) {
        let end = monotonicNow() + Double(ms) / 1000
        while running && monotonicNow() < end { Application.shared.sleep(10) }
    }

    /// FUN_00649D6C: start delay with count down.
    func countDown(ms: Int) {
        let end = monotonicNow() + Double(ms) / 1000
        while running {
            let left = end - monotonicNow()
            let s = String(Int(left) + 1)
            if lblCountDown.caption != s { lblCountDown.caption = s }
            if left <= 0 { break }
            Application.shared.sleep(20)
        }
        if running { lblCountDown.caption = "RUN" }
    }

    /// FUN_0064A508: the test.
    func run() {
        guard let t = test, !t.armed else { swtTest.stateOn = false; return }
        grbSettings.enabled = false
        running = true
        savedValues = t.values
        swtTest.stateOn = true
        grbStartPhase.enabled = false
        grbLoopPhase.enabled = false
        // any key stops the test (aevSpeedTestMessage: WM_KEYDOWN)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if self?.running == true { self?.stop(); return nil }
            return e
        }
        defer { finish() }
        countDown(ms: sedWaitStart.intValue * 1000)
        guard running, setMotors(sedRampToPPM.intValue) else { return }
        wait(ms: sedWaitAtRamp.intValue)
        var n = sedLoopCount.intValue
        while running && n > 0 {
            guard setMotors(sedStep1ToPPM.intValue) else { break }
            wait(ms: sedStep1SettleTime.intValue)
            guard running, setMotors(sedStep2ToPPM.intValue) else { break }
            wait(ms: sedStep2SettleTime.intValue)
            n -= 1
        }
    }

    func finish() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let t = test, let c = t.msp {
            t.values = savedValues.isEmpty ? t.values : savedValues
            try? c.setMotors((1...8).map { $0 <= t.motorCount ? t.values[$0] : t.motorCommand })
        }
        running = false
        swtTest.stateOn = false
        lblCountDown.caption = ""
        grbStartPhase.enabled = true
        grbLoopPhase.enabled = true
        grbSettings.enabled = true
    }

    /// FUN_00649BD4
    func stop() { running = false }

    @objc func swtTestOn(_ sender: TObject) { if !running { run() } }
    @objc func swtTestOff(_ sender: TObject) { stop() }
    @objc func swtTestClick(_ sender: TObject) { /* empty in BLHeliSuite (0x64A4EC); swtTestOn / swtTestOff do the work */ }

    @objc func sedWaitStartChange(_ sender: TObject) {
        lblStartDelayLeft.caption = String(sedWaitStart.intValue)
    }

    @objc func aevSpeedTestMessage(_ sender: TObject) { if running { stop() } }

    @objc func btnStoreSettingsClick(_ sender: TObject) {
        let name = cbxSettings.text_.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var s = loadSettings()
        var v: [String: Int] = [:]
        for (n, e) in spins { v[n] = e.intValue }
        for (i, b) in boxes.enumerated() { v["Motor\(i + 1)"] = b.checked ? 1 : 0 }
        s[name] = v
        saveSettings(s)
        cbxSettings.items = s.keys.sorted()
        cbxSettings.text_ = name
    }

    @objc func btnRestoreSettingsClick(_ sender: TObject) {
        guard let v = loadSettings()[cbxSettings.text_] else { return }
        for (n, e) in spins { if let x = v[n] { e.value = Double(x) } }
        for (i, b) in boxes.enumerated() where b.enabled { if let x = v["Motor\(i + 1)"] { b.checked = x != 0 } }
        sedWaitStartChange(self)
    }

    @objc func btnDeleteSettingsClick(_ sender: TObject) {
        var s = loadSettings()
        s[cbxSettings.text_] = nil
        saveSettings(s)
        cbxSettings.items = s.keys.sorted()
        cbxSettings.text_ = ""
    }

    @objc func cbbSettingsChange(_ sender: TObject) {
        let known = loadSettings()[cbxSettings.text_] != nil
        btnRestoreSettings.enabled = known
        btnDeleteSettings.enabled = known
    }
}

/// "FC enhanced tests" – TfrmFCEnhTests (VMT 0x64AA…).
@objc(TfrmFCEnhTests) final class TfrmFCEnhTests: TForm {
    @objc var fraAlternateSpeedTest1: TfraAlternateSpeedTest!
    weak var test: TfraCFMotorTest?
    var warned = false

    /// FormActivate (0x64AB90): severe warning, then the test frame is prepared.
    @objc func FormActivate(_ sender: TObject) {
        guard !warned else { return }
        warned = true
        let msg = NL("                         Serious warning!\\nThe following test, will cause the motors to spin up fast\\n      and may lead to severe damage and/or injury!!!\\n\\nIt is also still beta state and may contain bugs.\\n                    Use it on your own risk.\\n\\nOnly click \"Yes\", if removed all propellers and agree to\\n\\n                 \"UASGE ON YOUR OWN RISK!\".\\n")
        if MessageDlg(msg, .mtWarning, [.mbOK, .mbCancel]) == mrOk, let t = test {
            fraAlternateSpeedTest1.prepare(t)
        } else {
            DispatchQueue.main.async { [weak self] in self?.modalResult = mrCancel }
        }
    }

    @objc func FormClose(_ sender: TObject, _ a: TCloseArgs) { fraAlternateSpeedTest1.stop() }

    @objc func fraAlternateSpeedTest1Button1Click(_ sender: TObject) { saveScreenshot(of: self, name: "AlternateSpeedTest") }
}
