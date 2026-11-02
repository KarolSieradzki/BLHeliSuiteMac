import AppKit
import VCL
import BLHeliCore

/// "Just one last question ..." – port of TfrmConfirmFlash (unit at 0x62C550).
@objc(TfrmConfirmFlash) final class TfrmConfirmFlash: TForm {
    @objc var pnlBottomMain: TPanel!
    @objc var pnlBottomLeft: TPanel!
    @objc var lblFlashTo2: TLabel!
    @objc var lblFlashTo: TLabel!
    @objc var lblInfo: TLabel!
    @objc var pnlTextInfo: TPanel!
    @objc var lbSevereWarning: TLabel!
    @objc var lblWarning: TLabel!
    @objc var lblWarningTitle: TLabel!
    @objc var pnlFuses: TPanel!
    @objc var lbl_lfuse: TLabel!
    @objc var lb_hfuse: TLabel!
    @objc var lbl_efuse: TLabel!
    @objc var sbtn_undo_all: TSpeedButton!
    @objc var edt_lfuse: TEdit!
    @objc var edt_hfuse: TEdit!
    @objc var edt_efuse: TEdit!
    @objc var cbxLockBootloader: TCheckBox!
    @objc var btnEditFuses: TButton!
    @objc var pnlBootloader: TPanel!
    @objc var rdg_BootloaderPins: TRadioGroup!
    @objc var rdg_Bootloader: TRadioGroup!
    @objc var pnlMCU: TPanel!
    @objc var lblBrand: TLabel!
    @objc var lblMCU: TLabel!
    @objc var lblCopyright: TLabel!
    @objc var pnlBottomButtons: TPanel!
    @objc var btnYes: TButton!
    @objc var btnNo: TButton!
    @objc var bntSveScreenshot: TButton!
    @objc var actLockBootloaderEnabled: TAction!

    var severeText = ""      // +0x3F4
    var infoText = ""        // +0x400
    var warningText = ""     // +0x404
    var flashToText = ""     // +0x408
    var flashTo2Text = ""    // +0x40C
    var brand: UInt8 = 0     // +0x41C
    var plan: FlashPlan?
    var fuses: AVRFuses?
    /// +0x420 signature of the target (SetDeviceSign, FUN_0062EC98).
    var deviceSignature = 0
    /// Lock byte of the shown fuse model (+0x3E8 → +0x11); BLB11 programmed = "Lock Bootloader".
    var lockByte: UInt8 = 0xFF
    /// +0x415: 0 keep, 1 none, 2 BLHeli, 3 SimonK bootloader (result codes 5/4/2/3 of Execute).
    var bootloaderChoice = 0

    /// FUN_0062EEF8: shows the dialog. 0 = No; 1 = Yes; Atmel ISP: 2…5 = bootloader choice.
    func execute() -> Int {
        layoutDialog()
        guard showModal() == mrYes else { return 0 }
        var r = 1
        if pnlBootloader.visible {
            switch rdg_Bootloader.itemIndex {
            case 0: r = 5
            case 1: r = 4
            case 2: r = 2
            default: r = 3
            }
            bootloaderChoice = r
        }
        if pnlFuses.visible {
            fuses = AVRFuses(low: UInt8(edt_lfuse.textValue, radix: 16) ?? 0xFF, high: UInt8(edt_hfuse.textValue, radix: 16) ?? 0xFF,
                             ext: edt_efuse.visible ? UInt8(edt_efuse.textValue, radix: 16) : nil)
        }
        return r
    }

    /// FUN_0062D658: texts and size of the dialog.
    func layoutDialog() {
        lblCopyright.caption = "©"
        rdg_Bootloader.items = []
        if brand == 2 {
            lblBrand.caption = "Atmel"
            lblBrand.font.color = 0xFF0000
            let isp = plan?.ispFuses != nil || plan?.ispBootloader != nil
            pnlBootloader.visible = isp
            if pnlBootloader.visible {
                rdg_Bootloader.items = [NL("Keep Existing Bootloader [") + "0" + " bytes]"]
                if plan?.ispBootloader != nil {
                    rdg_Bootloader.items.append(NL("Install BLHeli Bootloader [") + "512" + " bytes]")
                    rdg_Bootloader.itemIndex = rdg_Bootloader.items.count - 1
                }
                if rdg_Bootloader.itemIndex == -1 { rdg_Bootloader.itemIndex = 0 }
            }
            pnlFuses.visible = plan?.ispFuses != nil
            if pnlFuses.visible, let f = plan?.ispFuses {
                edt_efuse.visible = f.ext != nil
                lbl_efuse.visible = f.ext != nil
                cbxLockBootloader.visible = pnlBootloader.visible
                showLockBootloader()
                cbxLockBootloader.enabled = pnlBootloader.visible
                edt_lfuse.textValue = String(format: "%02X", f.low)
                edt_hfuse.textValue = String(format: "%02X", f.high)
                edt_efuse.textValue = String(format: "%02X", f.ext ?? 0xFF)
            }
        } else {
            lblBrand.caption = "SiLabs"
            lblBrand.font.color = 0x45127E
            pnlBootloader.visible = false
            pnlFuses.visible = false
        }
        lblInfo.caption = "\r\n" + infoText + "\r\n"
        lblFlashTo.caption = flashToText
        if flashTo2Text.isEmpty {
            lblFlashTo2.height = 0
            lblFlashTo2.visible = false
        } else {
            lblFlashTo2.caption = "\r\n" + flashTo2Text + "\r\n"
            lblFlashTo2.visible = true
        }
        if severeText.isEmpty {
            lbSevereWarning.visible = false
        } else {
            lbSevereWarning.caption = "\r\n" + severeText + "\r\n"
            lblWarningTitle.visible = true
            lblWarningTitle.color = 0xFF
            lbSevereWarning.autoSize = true
            lbSevereWarning.align = .alTop
            lbSevereWarning.adjustBounds()
        }
        if warningText.isEmpty {
            lblWarning.visible = false
        } else {
            if !lblWarningTitle.visible {
                lblWarningTitle.visible = true
                lblWarningTitle.color = 0xB3FFFF
            }
            lblWarning.caption = "\r\n" + warningText + "\r\n"
            lblWarning.autoSize = true
            lblWarning.align = .alTop
            lblWarning.adjustBounds()
        }
        pnlTextInfo.visible = lblWarning.visible || lbSevereWarning.visible
        var h = 0
        if lbSevereWarning.visible { h += lbSevereWarning.height }
        if lblWarning.visible { h += lblWarning.height }
        if lblWarningTitle.visible { h += lblWarningTitle.height }
        if pnlBootloader.visible { h += pnlBootloader.height }
        if pnlFuses.visible { h += pnlFuses.height }
        lblInfo.adjustBounds()
        lblFlashTo2.adjustBounds()
        lblFlashTo2.align = .alBottom
        lblFlashTo.align = .alBottom
        lblInfo.align = .alBottom
        pnlTextInfo.align = .alClient
        h += pnlBottomButtons.height + lblInfo.height + lblFlashTo.height + (lblFlashTo2.visible ? lblFlashTo2.height : 0)
        clientHeight = h
        lblBrand.left = pnlMCU.clientWidth / 2 - lblBrand.width / 2
        lblCopyright.left = lblBrand.left + lblBrand.width
        lblMCU.left = lblBrand.left + lblBrand.width / 2 - lblMCU.width / 2
        btnNo.isDefault = false
    }

    @objc func btnYesClick(_ sender: TObject) { modalResult = mrYes }
    @objc func bntSveScreenshotClick(_ sender: TObject) {
        let text = [lblWarningTitle.visible ? lblWarningTitle.caption : "", lbSevereWarning.visible ? lbSevereWarning.caption : "",
                    lblWarning.visible ? lblWarning.caption : "", lblInfo.caption, lblFlashTo.caption, lblFlashTo2.caption]
            .filter { !$0.isEmpty }.joined(separator: "\r\n")
        saveScreenshot(of: self, name: "BLHeliSuiteConfirmFlashDlg", text: text)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    /// edtfuseKeyPress (0x62D36C): at most two hex digits; with the second digit the fuse byte is taken over.
    @objc func edtfuseKeyPress(_ sender: TObject, _ a: TKeyArgs) {
        guard let e = sender as? TEdit, [edt_lfuse, edt_hfuse, edt_efuse].contains(where: { $0 === e }) else { return }
        let c = a.key
        guard c == "\u{8}" || c == "\r" || c.isHexDigit else { a.key = "\0"; return }
        guard c.isHexDigit else { return }
        let t = e.textValue
        if t.count == 1 {
            e.textValue = t + String(c)
            a.key = "\0"
        } else if t.count == 2 {
            a.key = "\0"
        }
        guard e.textValue.count == 2, UInt8(e.textValue, radix: 16) != nil else { return }
        showFuses(shownFuses)
    }
    /// Fuses shown in the dialog.
    var shownFuses: AVRFuses {
        AVRFuses(low: UInt8(edt_lfuse.textValue, radix: 16) ?? 0xFF, high: UInt8(edt_hfuse.textValue, radix: 16) ?? 0xFF,
                 ext: edt_efuse.visible ? UInt8(edt_efuse.textValue, radix: 16) : nil)
    }

    func showFuses(_ f: AVRFuses) {
        edt_lfuse.textValue = String(format: "%02X", f.low)
        edt_hfuse.textValue = String(format: "%02X", f.high)
        edt_efuse.textValue = String(format: "%02X", f.ext ?? 0xFF)
    }

    /// FUN_0062CB88: BOOTRST / boot size follow the bootloader choice
    /// (ATmega8: hfuse, ATmega48/88/168: efuse; 256 words BLHeli bootloader).
    @objc func rdg_BootloaderClick(_ sender: TObject) {
        guard pnlFuses.visible, let orig = plan?.ispFuses else { return }
        var f = shownFuses
        let install = rdg_Bootloader.itemIndex == rdg_Bootloader.items.count - 1 && plan?.ispBootloader != nil
        if f.ext == nil {
            f.high = install ? (f.high & 0xF8) | 0x04 : (f.high & 0xF8) | (orig.high & 0x07)
        } else if let e = f.ext {
            f.ext = install ? (e & 0xF8) | 0x04 : (e & 0xF8) | ((orig.ext ?? 0xFF) & 0x07)
        }
        showFuses(f)
    }
    @objc func sbtn_undo_allClick(_ sender: TObject) {
        if let f = plan?.ispFuses {
            edt_lfuse.textValue = String(format: "%02X", f.low)
            edt_hfuse.textValue = String(format: "%02X", f.high)
            edt_efuse.textValue = String(format: "%02X", f.ext ?? 0xFF)
        }
    }
    /// btnEditFusesClick (0x62F03C → FUN_0062C250): fuse editor (device fixed, no critical features) for the shown fuses.
    @objc func btnEditFusesClick(_ sender: TObject) {
        let f = shownFuses
        let v = UInt32(f.low) | UInt32(f.high) << 8 | UInt32(f.ext ?? 0xFF) << 16 | UInt32(lockByte) << 24
        let sig = deviceSignature != 0 ? deviceSignature : (f.ext == nil ? 0x1E9307 : 0x1E9406)
        if let n = TfrmFuseEditor.edit(signature: sig, chip: v, fuses: v, deviceChangeable: false, critical: false) {
            showFuses(AVRFuses(low: UInt8(n & 0xFF), high: UInt8((n >> 8) & 0xFF), ext: f.ext == nil ? nil : UInt8((n >> 16) & 0xFF)))
            lockByte = UInt8(n >> 24)
            showLockBootloader()
        }
        layoutDialog()
    }

    /// FUN_0062CA58: "Lock Bootloader" shows BLB11 of the shown fuses.
    func showLockBootloader() {
        guard pnlBootloader.visible else { return }
        cbxLockBootloader.setChecked(lockByte & 0x10 == 0)
    }

    /// actLockBootloaderEnabledExecute (0x62EFAC): BLB11 := not cbxLockBootloader.Checked.
    @objc func actLockBootloaderEnabledExecute(_ sender: TObject) {
        if cbxLockBootloader.checked { lockByte &= ~0x10 } else { lockByte |= 0x10 }
    }
    /// AppEventsIdle (0x62EFE4): "undo" only when the fuses were changed.
    @objc func AppEventsIdle(_ sender: TObject) {
        guard pnlFuses.visible, let orig = plan?.ispFuses else { return }
        sbtn_undo_all.enabled = shownFuses != orig
    }
}
