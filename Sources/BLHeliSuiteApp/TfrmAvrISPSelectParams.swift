import AppKit
import VCL
import BLHeliCore

/// Frame TfraSelectIspParams (VMT 0x62F1A4): ISP programmer, port and baud rate.
@objc(TfraSelectIspParams) final class TfraSelectIspParams: TFrame {
    @objc var ccbBaudrate: TComboBox!
    @objc var ccbAVRDudeProgList: TComboBox!
    @objc var lblISPProgrammer: TLabel!
    @objc var lblBaudrate: TLabel!
    @objc var lblPort: TLabel!
    @objc var ccbComPort: TComboBox!
    @objc var ccbParaPort: TComboBox!
    @objc var btnCancel: TButton!
    @objc var btnOK: TButton!

    /// +0x28C index into the programmer table, +0x290 OnResult.
    var programmerIndex = -1
    var portPaths: [String] = []
    var onResult: ((TModalResult) -> Void)?
    var listWidth = 0
}

extension TfraSelectIspParams {
    func fill(ports: PortList) {
        ccbAVRDudeProgList.items = AVRDudeIntf.programmerNames
        ccbBaudrate.items = BaudLists.normal.map(String.init)
        ports.refresh()
        portPaths = ports.paths
        ccbComPort.items = ports.names
        ccbParaPort.items = []
        btnCancel.caption = NL("Cancel")
        btnOK.caption = NL("OK")
    }

    /// FUN_0062FB98: selects the programmer by id.
    func setProgrammer(_ id: String) {
        ccbAVRDudeProgList.itemIndex = AVRDudeIntf.programmers.firstIndex { $0.id == id } ?? -1
        if ccbAVRDudeProgList.itemIndex < 0 { ccbAVRDudeProgList.text_ = "Unknown Programmer" }
        ccbAVRDudeProgListChange(self)
    }

    /// FUN_0062FA58: selects the serial port.
    func setPort(_ path: String) {
        if let i = portPaths.firstIndex(of: path) { ccbComPort.itemIndex = i } else if !path.isEmpty { ccbComPort.text_ = PortList.shortName(path) }
    }

    /// FUN_0062FA00
    func setBaud(_ b: Int) { ccbBaudrate.text_ = String(b) }

    var programmerID: String { programmerIndex >= 0 ? AVRDudeIntf.programmers[programmerIndex].id : "" }
    var portPath: String { let i = ccbComPort.itemIndex; return i >= 0 && i < portPaths.count ? portPaths[i] : "" }
    var baud: Int { Int(ccbBaudrate.text_) ?? 19200 }

    @objc func ccbAVRDudeProgListChange(_ sender: TObject) {
        ccbAVRDudeProgList.hint = ccbAVRDudeProgList.text_
        let i = ccbAVRDudeProgList.itemIndex
        guard i >= 0, i < AVRDudeIntf.programmers.count else { programmerIndex = -1; return }
        programmerIndex = i
        switch AVRDudeIntf.programmers[i].portType {
        case 1:
            ccbBaudrate.visible = false
            lblBaudrate.visible = false
            ccbComPort.visible = false
            lblPort.caption = "Parallel Port"
            ccbParaPort.visible = true
        case 2:
            ccbBaudrate.visible = true
            lblBaudrate.visible = true
            if ccbBaudrate.itemIndex < 0, let j = ccbBaudrate.items.firstIndex(of: "19200") { ccbBaudrate.itemIndex = j }
            ccbComPort.visible = true
            lblPort.caption = "Com Port"
            ccbParaPort.visible = false
        default:
            ccbBaudrate.visible = false
            lblBaudrate.visible = false
            ccbComPort.visible = false
            lblPort.caption = "USB"
            ccbParaPort.visible = false
        }
    }

    @objc func ccbAVRDudeProgListDropDown(_ sender: TObject) {
        if listWidth == 0 { listWidth = ccbAVRDudeProgList.width }
        ccbAVRDudeProgList.width = 600
    }

    @objc func ccbAVRDudeProgListCloseUp(_ sender: TObject) {
        if listWidth > 0 { ccbAVRDudeProgList.width = listWidth }
    }

    @objc func btnCancelClick(_ sender: TObject) { onResult?(mrCancel) }

    @objc func btnOKClick(_ sender: TObject) {
        var ok = true
        if programmerIndex >= 0 {
            switch AVRDudeIntf.programmers[programmerIndex].portType {
            case 1: ok = ccbParaPort.itemIndex >= 0
            case 2: ok = ccbComPort.itemIndex >= 0 && Int(ccbBaudrate.text_) != nil
            default: break
            }
        }
        if ok { onResult?(mrOk) }
    }

    @objc func SaveScreeshot1Click(_ sender: TObject) {
        if let f = window?.delegate as? TForm { saveScreenshot(of: f, name: "ESCSetup") }
    }
}

/// "Select ISP Parameters" – TfrmAvrISPSelectParams (VMT 0x62FC70).
@objc(TfrmAvrISPSelectParams) final class TfrmAvrISPSelectParams: TForm {
    @objc var mmnMain: TMainMenu!
    @objc var mniSaveSvreenshot: TMenuItem!
    @objc var fraSelectIspParams1: TfraSelectIspParams!

    /// FUN_0062FE44: modal, true on OK.
    func execute() -> Bool {
        fraSelectIspParams1.onResult = { [weak self] r in self?.modalResult = r }
        return showModal() == mrOk
    }

    @objc func mniSaveSvreenshotClick(_ sender: TObject) { saveScreenshot(of: self, name: "SelectIspParameters") }
}
