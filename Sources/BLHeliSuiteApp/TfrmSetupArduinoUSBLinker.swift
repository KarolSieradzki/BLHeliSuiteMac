import AppKit
import VCL
import BLHeliCore

/// Frame TfraSetupArduinoUSBLinker (VMT 0x62FF38): pin, bit time and baud rate of the ArduinoUSBLinker sketch.
@objc(TfraSetupArduinoUSBLinker) final class TfraSetupArduinoUSBLinker: TFrame {
    @objc var lblTitle: TLabel!
    @objc var lblPort: TLabel!
    @objc var cbbPort: TComboBox!
    @objc var sedPin: TSpinEdit!
    @objc var lblPin: TLabel!
    @objc var btnReadSettings: TButton!
    @objc var btnWriteSettings: TButton!
    @objc var cbxSaveToEEprom: TCheckBox!
    @objc var cbbBaudrates: TComboBox!
    @objc var lblBaudRate: TLabel!
    @objc var sedBitTime: TSpinEdit!
    @objc var lblBitTime: TLabel!
    @objc var btnDefault: TButton!

    let aul = ArduinoUSBLinker()    // +0x29C
}

extension TfraSetupArduinoUSBLinker {
    func setup(portPath: String) {
        aul.portPath = portPath
        aul.log = { s in if TfrmLogForm.isShown { TfrmLogForm.add(s) } }
        lblTitle.caption = NL("ArduinoUSBLinker Settings")
        btnReadSettings.caption = NL("Read")
        btnWriteSettings.caption = NL("Write")
        btnDefault.caption = NL("Default")
        cbxSaveToEEprom.caption = NL("Save to EEprom")
        cbxSaveToEEprom.hint = NL("On Write: Save settings to EEprom and make them power-on defaults")
        lblBitTime.caption = NL("Bit Time")
        lblPort.caption = NL("Port")
        lblPin.caption = NL("Pin")
        lblBaudRate.caption = NL("Baud rate")
        cbbBaudrates.items = ArduinoUSBLinker.searchBauds.sorted().map(String.init)
    }

    /// FUN_0063062C: connects and shows the settings of the sketch.
    @discardableResult
    func readSettings() -> Bool {
        cbbPort.text_ = ""
        sedPin.value = 0
        sedBitTime.value = 0
        cbbBaudrates.text_ = ""
        Screen.busy = true
        defer { Screen.busy = false }
        guard aul.connect() else { return false }
        defer { aul.close() }
        cbbPort.items = aul.ports.map { String($0.letter) }
        let letters = aul.ports
        if let l = aul.portLetter, let i = letters.firstIndex(where: { $0.letter == l }) {
            let next = i + 1 < letters.count ? letters[i + 1].first : letters[i].first + 8
            sedPin.maxValue = Double(next - letters[i].first - 1)
            cbbPort.text_ = String(l)
        }
        sedPin.value = Double(aul.pinInPort)
        cbbBaudrates.text_ = String(aul.baud)
        sedBitTime.value = Double(aul.bitTime)
        return true
    }

    @objc func btnReadSettingsClick(_ sender: TObject) {
        if readSettings() {
            MsgDlg.show(NL("Settings successfully read."), .mtInformation, [.mbOK])
        } else {
            MsgDlg.error(NL("Failed to read settings."))
        }
    }

    @objc func btnWriteSettingsClick(_ sender: TObject) {
        guard let l = cbbPort.text_.first, sedPin.intValue >= 0 else { return }
        Screen.busy = true
        defer { Screen.busy = false }
        var ok = aul.connect()
        if ok {
            do {
                let pin = aul.pinNumber(port: l, sedPin.intValue) ?? aul.pin
                try aul.writeSettings(pin: pin, bitTime: sedBitTime.intValue, baud: Int(cbbBaudrates.text_) ?? aul.baud,
                                      save: cbxSaveToEEprom.checked)
            } catch {
                ok = false
            }
            aul.close()
        }
        if ok {
            MsgDlg.show(NL("Settings successfully written."), .mtInformation, [.mbOK])
        } else {
            MsgDlg.error(NL("Failed to write settings."))
        }
    }

    @objc func btnDefaultClick(_ sender: TObject) {
        sedPin.value = 2
        sedBitTime.value = 136
        cbbPort.text_ = "D"
        cbbBaudrates.text_ = "19200"
    }

    @objc func cbbPortChange(_ sender: TObject) {
        guard let l = cbbPort.text_.first, let i = aul.ports.firstIndex(where: { $0.letter == l }) else { return }
        let next = i + 1 < aul.ports.count ? aul.ports[i + 1].first : aul.ports[i].first + 8
        sedPin.maxValue = Double(next - aul.ports[i].first - 1)
    }

    /// Changed values in red.
    @objc func sedPinChange(_ sender: TObject) {
        guard let s = sender as? TSpinEdit else { return }
        let original = s === sedPin ? aul.pinInPort : aul.bitTime
        s.font.color = s.intValue == original ? clWindowText : clRed
        s.needsDisplay = true
    }
}

/// "Setup ArduinoUSBLinker" – TfrmSetupArduinoUSBLinker (VMT 0x630C98).
@objc(TfrmSetupArduinoUSBLinker) final class TfrmSetupArduinoUSBLinker: TForm {
    @objc var fraSetupArduinoUSBLinker1: TfraSetupArduinoUSBLinker!
    var timActivate: TTimer?

    static func execute(portPaths: [String], port: String) {
        guard !port.isEmpty else { MsgDlg.error(NL("Please select a valid COM port first")); return }
        let f = TfrmSetupArduinoUSBLinker(resource: "TFRMSETUPARDUINOUSBLINKER", owner: Application.shared.mainForm)
        f.caption = NL("Setup ArduinoUSBLinker")
        f.fraSetupArduinoUSBLinker1.setup(portPath: port)
        f.showModal()
        f.release()
    }

    /// FormShow (0x630E98): reads the settings 100 ms after the window is shown.
    @objc func FormShow(_ sender: TObject) {
        let t = TTimer()
        t.interval = 100
        t.onTimer = { [weak self, weak t] _ in
            t?.enabled = false
            self?.fraSetupArduinoUSBLinker1.readSettings()
        }
        timActivate = t
    }

    @objc func FormClose(_ sender: TObject, _ a: TCloseArgs) {
        timActivate?.enabled = false
        fraSetupArduinoUSBLinker1.aul.close()
    }
}
