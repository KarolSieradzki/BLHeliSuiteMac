import AppKit
import VCL
import BLHeliCore

/// "Select Interface Options" – port of TfrmInterfaceOptions (VMT 0x625B18, FUN_00625D20).
@objc(TfrmInterfaceOptions) final class TfrmInterfaceOptions: TForm {
    @objc var pnlMain: TPanel!
    @objc var pnlRadioBtn: TPanel!
    @objc var pnlButtons: TPanel!
    @objc var btnOK: TButton!
    @objc var btnCancel: TButton!

    /// FUN_00625D20: one radio button per available option (bit i of `options` = InterfaceFirmwareFiles.prefixes[i]).
    /// Returns the chosen option or 0 when cancelled.
    static func execute(_ options: UInt16) -> UInt8 {
        let f = TfrmInterfaceOptions(resource: "TFRMINTERFACEOPTIONS", owner: Application.shared.mainForm)
        defer { f.release() }
        var radios: [TRadioButton] = []
        let h = 21
        for i in 0...9 where options & (1 << i) != 0 {
            let r = TRadioButton(frame: NSRect(x: 0, y: radios.count * h, width: f.pnlRadioBtn.width, height: h))
            r.name = "rdb" + InterfaceFirmwareFiles.prefixes[i]
            r.caption = InterfaceFirmwareFiles.optionName(i)
            r.tag = i
            r.align = .alTop
            f.pnlRadioBtn.insertControl(r)
            radios.append(r)
        }
        let grow = radios.count * h + 8 - f.pnlRadioBtn.height
        f.pnlRadioBtn.height = radios.count * h + 8
        f.setClientSize(f.clientWidth, f.clientHeight + grow)
        f.pnlRadioBtn.realign()
        if radios.count == 1 {
            radios[0].checked = true
        } else {
            radios.first { $0.tag == 8 }?.checked = true
        }
        while true {
            guard f.showModal() == mrOk else { return 0 }
            if let r = radios.first(where: { $0.checked }) { return UInt8(r.tag) }
            MsgDlg.show(NL("Please select an option"), .mtInformation, [.mbOK])
        }
    }
}
