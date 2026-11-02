import AppKit
import VCL
import BLHeliCore

/// Frame TfraMotorControl (VMT 0x648500): one motor slider with gauge (index 9 = master).
@objc(TfraMotorControl) final class TfraMotorControl: TFrame {
    @objc var lblHead: TLabel!
    @objc var gauMotor: TGauge!
    @objc var LblValue: TLabel!
    @objc var trkMotor: TTrackBar!

    var index = 0                 // +0x290
    var minValue = 0, maxValue = 2000, range = 2000   // +0x278 / +0x27C / +0x280
    var value = -1                // +0x294
    var available = false         // +0x298
    var updating = false          // +0x291
    /// OnChange (+0x288): (frame, index, value).
    var onMotorChange: ((TfraMotorControl, Int, Int) -> Void)?
}

extension TfraMotorControl {
    /// FUN_00648718
    func setup(_ i: Int, min: Int, max: Int) {
        index = i
        if i == 9 {
            lblHead.caption = "M"
            lblHead.hint = NL("Master controlls all Motors at once")
            gauMotor.visible = false
            lblHead.top = LblValue.top
            LblValue.visible = false
        } else {
            lblHead.caption = String(i)
            lblHead.hint = DFormat(NL("Controlls Motor #%s"), [lblHead.caption])
            gauMotor.visible = true
            LblValue.visible = true
        }
        minValue = min
        maxValue = max
        range = max - min
        trkMotor.max = range
        gauMotor.maxValue = max
        gauMotor.minValue = min
    }

    /// FUN_006488F0: motor present.
    func setAvailable(_ a: Bool) {
        available = a
        gauMotor.backColor = a ? 0xFFFFFF : 0xC0C0C0
        trkMotor.visible = a || index == 9
    }

    /// FUN_00648968
    func setValue(_ v: Int) {
        guard v != value else { return }
        var pos: Int
        if v == 0 || v < minValue {
            value = 0
            enabled = false
            pos = range
        } else {
            value = v
            pos = range - (v - minValue)
        }
        if pos != trkMotor.position {
            updating = true
            trkMotor.setPositionSilently(pos)
            updating = false
        }
        if gauMotor.progress != value { gauMotor.progress = value }
        if LblValue.caption != String(value) { LblValue.caption = String(value) }
    }

    @objc func trkMotorChange(_ sender: TObject) {
        guard sender === trkMotor, !updating else { return }
        value = range - trkMotor.position + minValue
        if gauMotor.progress != value { gauMotor.progress = value }
        LblValue.caption = String(value)
        if effectiveEnabled { onMotorChange?(self, index, value) }
    }
}

/// Frame TfraCFMotorTest (DFM resource TFRACFMOTORTEST): motors of a Betaflight/Cleanflight FC over MSP.
@objc(TfraCFMotorTest) final class TfraCFMotorTest: TFrame {
    @objc var JvAppEvents1: TDummyComponent!
    @objc var pnlTop: TPanel!
    @objc var grdTop: TGradient!
    @objc var pnlBottom: TPanel!
    @objc var grdBottom: TGradient!
    @objc var lblWarn6: TLabel!
    @objc var lblWarn5: TLabel!
    @objc var lblWarn1: TLabel!
    @objc var lblWarn2: TLabel!
    @objc var lblWarn3: TLabel!
    @objc var lblWarn4: TLabel!
    @objc var btnSpecialTest: TButton!
    @objc var cbxActivate: TCheckBox!
    @objc var btnCalibrateESC: TButton!
    @objc var pnlMotors: TPanel!
    @objc var grdMotors: TGradient!
    @objc var lblCycleTime: TLabel!
    @objc var lblCycleTimeName: TLabel!
    @objc var grdStatus: TGradient!
    @objc var lblStatus: TLabel!

    var motors: [TfraMotorControl?] = Array(repeating: nil, count: 10)   // +0x2BC… (1…8, 9 = master)
    var timer: TTimer?                     // +0x2B8 status poll
    var created = false                    // +0x304
    var active = false                     // +0x2E4 controls activated
    var expert = false
    // TFlightCtrlIntf (+0x2E0) in MSP mode
    var portPath = ""
    var baud = 115200
    var port: SerialPort?
    var msp: MSPClient?
    var motorMin = 1070, motorMax = 2000, motorCommand = 1000
    var motorCount = 0
    var values = [Int](repeating: 0, count: 9)
    var armed = false
    var mode3D = false
    var cycleTime = 0
    var lastValues: [Int] = []             // +0x2EE motor values before activation
    var masterAverage = 0                  // +0x300
    var fcConnected: Bool { msp != nil }
}

extension TfraCFMotorTest {
    /// Constructor part (0x64B5C3): 8 motor sliders + master, status timer.
    func createControls() {
        guard !created else { return }
        created = true
        var left = 1
        for i in 1...9 {
            let m = TfraMotorControl.create()
            m.name = i == 9 ? "MasterControl" : "MotorControl\(i)"
            pnlMotors.insertControl(m)
            m.left = left
            left += m.width + 1
            m.onMotorChange = { [weak self] _, idx, v in self?.motorChanged(idx, v) }
            motors[i] = m
        }
        initControls()
        let t = TTimer()
        t.enabled = false
        t.interval = 100
        t.onTimer = { [weak self] _ in self?.refresh() }
        timer = t
    }

    /// FUN_0064B778
    func prepare(_ cf: SerialIntf) {
        createControls()
        portPath = cf.portPath
        baud = cf.baud
        stopMotors()
    }

    func setExpert(_ on: Bool) { expert = on }

    /// FUN_0064BF4C: limits and values of the sliders.
    func initControls() {
        for i in 1...9 {
            guard let m = motors[i] else { continue }
            m.enabled = false
            if !fcConnected {
                m.visible = true
                m.setup(i, min: 0, max: 2000)
                m.setValue(-1)
                if i != 9 { m.setAvailable(false) }
            } else {
                if i < 9 {
                    m.visible = i <= max(motorCount, 1)
                    m.setAvailable(i <= motorCount)
                }
                m.setup(i, min: motorCommand, max: motorMax)
                m.setValue(i < 9 ? values[i] : masterAverage)
            }
        }
    }

    /// FUN_0064C050: enabled sliders.
    func enableControls() {
        motors[9]?.enabled = !armed
        for i in 1...8 { motors[i]?.enabled = i <= motorCount && !armed }
    }

    // MARK: - FC connection

    func connectFC() -> Bool {
        if msp != nil { return true }
        guard !portPath.isEmpty else { return false }
        let sp = SerialPort(path: portPath)
        do {
            try sp.open(baudRate: baud)
            let c = MSPClient(channel: sp)
            _ = try c.identify()
            let cfg = try c.motorConfig()
            motorMin = cfg.min; motorMax = cfg.max; motorCommand = cfg.command
            mode3D = (try? c.is3D()) ?? false
            let st = try c.status()
            armed = st.armed
            cycleTime = st.cycleTime
            let v = try c.motorValues()
            motorCount = min(8, v.filter { $0 > 0 }.count)
            values = [0] + (0..<8).map { $0 < v.count ? v[$0] : 0 }
            port = sp
            msp = c
            return true
        } catch {
            sp.close()
            return false
        }
    }

    func disconnectFC() {
        port?.close()
        port = nil
        msp = nil
    }

    // MARK: - activate (FUN_0064BA88) / stop (FUN_0064BBE0)

    func activate() {
        active = false
        var ok = false
        if connectFC(), !armed {
            lastValues = values
            averageMaster()
            initControls()
            enableControls()
            ok = true
        }
        active = true
        if !ok {
            btnSpecialTest.enabled = false
            btnCalibrateESC.enabled = false
            stopMotors()
        } else {
            btnSpecialTest.enabled = true
            btnCalibrateESC.enabled = !mode3D
            timer?.enabled = true
        }
    }

    /// FUN_0064BBE0: all motors to their stop value, controls off.
    @discardableResult
    func stopMotors() -> Bool {
        if active, let c = msp {
            try? c.setMotors((1...8).map { _ in motorCommand })
            values = [0] + Array(repeating: motorCommand, count: 8)
        }
        timer?.enabled = false
        active = false
        disconnectFC()
        initControls()
        cbxActivate.checked = false
        lblStatus.caption = NL("FC disconnected")
        lblStatus.font.color = 0x808080
        btnSpecialTest.enabled = false
        btnCalibrateESC.enabled = false
        return true
    }

    /// FUN_0064BA00: master value = average of the present motors.
    func averageMaster() {
        let present = (1...8).filter { $0 <= motorCount }
        masterAverage = present.isEmpty ? 0 : present.map { values[$0] }.reduce(0, +) / present.count
    }

    /// FUN_0064BDF8 / FUN_0064BCB8: slider moved → MSP_SET_MOTOR.
    func motorChanged(_ idx: Int, _ v: Int) {
        guard active, let c = msp, !armed else { return }
        if idx == 9 {
            for i in 1...8 where i <= motorCount { values[i] = v }
        } else {
            values[idx] = v
        }
        do {
            try c.setMotors((1...8).map { $0 <= motorCount ? values[$0] : motorCommand })
            for i in 1...8 where i <= motorCount { motors[i]?.setValue(values[i]) }
        } catch {
            stopMotors()
        }
    }

    /// FUN_0064BE14 (timer): FC state.
    func refresh() {
        guard let c = msp else { stopMotors(); return }
        do {
            let st = try c.status()
            cycleTime = st.cycleTime
            if st.armed != armed {
                armed = st.armed
                enableControls()
            }
        } catch {
            stopMotors()
        }
    }

    @objc func cbxActivateClick(_ sender: TObject) {
        cbxActivate.enabled = false
        if !cbxActivate.checked {
            if active { stopMotors() }
        } else if !active {
            activate()
        }
        cbxActivate.checked = active
        cbxActivate.enabled = true
    }

    /// JvAppEvents1Idle (0x64B7B8): status text, colour and cycle time.
    @objc func JvAppEvents1Idle(_ sender: TObject) {
        guard created else { return }
        if !fcConnected {
            lblStatus.font.color = 0x808080
            return
        }
        let prefix = mode3D ? NL("3D mode - ") : ""
        if armed {
            lblStatus.font.color = 0xFF
            lblStatus.caption = prefix + NL("ARMED - Controls disabled")
        } else if active {
            lblStatus.font.color = 0x0080FF
            lblStatus.caption = prefix + NL("Controls enabled")
        } else {
            lblStatus.font.color = 0
            lblStatus.caption = prefix + NL("Controls disabled")
        }
        lblCycleTime.caption = String(cycleTime)
    }

    // MARK: - calibration (btnCalibrateESCClick 0x64C1A8)

    @objc func btnCalibrateESCClick(_ sender: TObject) {
        guard active, msp != nil else { return }
        let f = TfrmFormCalibrateESCStart(resource: "TFRMFORMCALIBRATEESCSTART", owner: Application.shared.mainForm)
        defer { f.release() }
        f.prepare(min: motorMin, max: motorMax, motors: motorCount)
        guard f.showModal() == mrOk else { return }
        let sel = f.selectedMotors
        guard !sel.isEmpty else { return }
        func set(_ v: Int) {
            for i in sel { values[i] = v }
            try? msp?.setMotors((1...8).map { $0 <= motorCount ? values[$0] : motorCommand })
            for i in sel { motors[i]?.setValue(v) }
        }
        defer { set(motorCommand) }
        guard MsgDlg.show(NL("Power OFF ESCs, Click OK to continue..."), .mtConfirmation, [.mbOK, .mbCancel]) == mrOk else { return }
        set(f.sedCalToMaxPPM.intValue)
        guard MsgDlg.show(NL("Power ON ESCs, Click OK to continue..."), .mtConfirmation, [.mbOK, .mbCancel]) == mrOk else { return }
        let info = TfrmInfo.showInfo(NL("Calibrating Max Trottle..."), cancel: true)
        for _ in 0..<15 where !info.cancelled { Application.shared.sleep(200) }
        if !info.cancelled {
            set(f.sedCalToMinPPM.intValue)
            _ = TfrmInfo.showInfo(NL("Calibrating Min Trottle..."), cancel: true)
            for _ in 0..<15 where !info.cancelled { Application.shared.sleep(200) }
        }
        if !info.cancelled {
            _ = TfrmInfo.showInfo(NL("Calibration done."), cancel: false)
            Application.shared.sleep(1000)
        }
        info.hideInfo()
    }

    // MARK: - special tests (btnSpecialTestClick 0x64C62C)

    @objc func btnSpecialTestClick(_ sender: TObject) {
        guard active else { return }
        timer?.enabled = false
        let saved = values
        let f = TfrmFCEnhTests(resource: "TFRMFCENHTESTS", owner: Application.shared.mainForm)
        f.test = self
        f.showModal()
        f.release()
        values = saved
        timer?.enabled = active
        for i in 1...8 where i <= motorCount { motors[i]?.setValue(values[i]) }
    }
}

/// "Calibrate ESC" – TfrmFormCalibrateESCStart (VMT 0x64AE1C).
@objc(TfrmFormCalibrateESCStart) final class TfrmFormCalibrateESCStart: TForm {
    @objc var pnlBottom: TPanel!
    @objc var btnCancel: TButton!
    @objc var btnOK: TButton!
    @objc var JvPanel1: TPanel!
    @objc var sedCalToMinPPM: TSpinEdit!
    @objc var lblCalToMinimum: TLabel!
    @objc var sedCalToMaxPPM: TSpinEdit!
    @objc var lblCalToMaximum: TLabel!
    @objc var JvPanel2: TPanel!
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

    var boxes: [TCheckBox] { [cbxMotor1, cbxMotor2, cbxMotor3, cbxMotor4, cbxMotor5, cbxMotor6, cbxMotor7, cbxMotor8] }

    func prepare(min: Int, max: Int, motors: Int) {
        sedCalToMinPPM.value = Double(min)
        sedCalToMaxPPM.value = Double(max)
        for (i, b) in boxes.enumerated() {
            b.enabled = i < motors
            b.checked = i < motors
        }
    }

    /// FUN_0064B1C4: motors to calibrate.
    var selectedMotors: [Int] { boxes.enumerated().filter { $0.element.checked && $0.element.enabled }.map { $0.offset + 1 } }
}
