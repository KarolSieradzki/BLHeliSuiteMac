import AppKit
import VCL
import BLHeliCore

// MARK: - message dialog with screenshot button (FUN_00554858)

enum MsgDlg {
    /// MessageDlg + the Wingdings "save" button at the bottom left (screenshot and dialog text to file).
    @discardableResult
    static func show(_ msg: String, _ type: TMsgDlgType, _ buttons: TMsgDlgButtons) -> TModalResult {
        Application.shared.cancelHint()
        return MessageDlg(msg, type, buttons) { f in
            let b = TButton(frame: NSRect(x: 0, y: f.clientHeight - 20, width: 20, height: 20))
            b.caption = "<"
            b.font.name = "Wingdings"
            b.font.height = -13
            b.hint = NL("Save screenshot and dialog text to file...")
            b.showHint = true
            b.root = f
            b.onClick = { _ in saveScreenshot(of: f, prefix: "BLHeliSuite_Message", text: msg) }
            f.addSubview(b)
        }
    }

    /// FUN_00554A10: error message.
    static func error(_ msg: String) { show(msg, .mtError, [.mbOK]) }
}

/// FUN_00553FF0: saves a PNG of the form (and the dialog text) into the Screenshots folder.
func saveScreenshot(of f: TForm, prefix: String, text: String? = nil) {
    let df = DateFormatter()
    df.dateFormat = "yyyyMMdd_HHmmss"
    let name = prefix.replacingOccurrences(of: " ", with: "") + "_" + df.string(from: Date())
    guard let url = SaveDialog.execute(title: "Save Screenshot", fileName: name + ".png", filter: "PNG (*.png)|*.png",
                                       initialDir: AppFolders.userFolder.appendingPathComponent("Screenshots")) else { return }
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let png = f.screenshotPNG() { try? png.write(to: url) }
    if let t = text { try? t.write(to: url.deletingPathExtension().appendingPathExtension("txt"), atomically: true, encoding: .utf8) }
}

// MARK: - TfrmInfo (non modal info window, FUN_005DA828)

@objc(TfrmInfo) final class TfrmInfo: TForm {
    @objc var pnlMain: TPanel!
    @objc var gauInfo: TGauge!
    @objc var pnlBottom: TPanel!
    @objc var btnCancel: TButton!
    @objc var Memo: TMemo!
    var cancelled = false
    static weak var current: TfrmInfo?

    static func showInfo(_ text: String, cancel: Bool) -> TfrmInfo {
        let f = current ?? TfrmInfo(resource: "TFRMINFO", owner: Application.shared.mainForm)
        current = f
        f.cancelled = false
        f.caption = Application.shared.title
        f.Memo.lines = text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
        f.btnCancel.visible = cancel
        f.gauInfo.progress = 0
        f.show()
        Application.shared.processMessages()
        return f
    }

    func setProgress(_ p: Int, _ max: Int) {
        gauInfo.maxValue = max
        gauInfo.progress = p
        Application.shared.processMessages()
    }

    func hideInfo() {
        hide()
        release()
        TfrmInfo.current = nil
    }

    @objc func btnCancelClick(_ sender: TObject) { cancelled = true }
    @objc func FormShow(_ sender: TObject) {}
}

// MARK: - TAboutBox

@objc(TAboutBox) final class TAboutBox: TForm {
    @objc var Panel1: TPanel!
    @objc var ProgramIcon: TImage!
    @objc var lblProductName: TLabel!
    @objc var lblVersion: TLabel!
    @objc var lblCopyright: TLabel!
    @objc var redAbout: TMemo!
    @objc var Panel2: TPanel!
    @objc var OKButton: TButton!

    @objc func FormCreate(_ sender: TObject) {
        caption = "About BLHeliSuite"
        lblProductName.caption = "BLHeliSuite"
        lblVersion.caption = TfrmBLHeliSuiteMain.version
        lblCopyright.caption = "Copyright (c) 4712 – macOS port"
        if let img = NSApp.applicationIconImage { ProgramIcon.picture = img; ProgramIcon.stretch = true; ProgramIcon.proportional = true }
        if let rtf = Resources.data("RCData/ABOUTBLHELISUITE"),
           let s = NSAttributedString(rtf: Data(rtf), documentAttributes: nil) {
            redAbout.textView.textStorage?.setAttributedString(s)
        }
        redAbout.readOnly = true
        OKButton.modalResult = mrOk
        OKButton.isDefault = true
    }
}

// MARK: - TfrmLogForm ("Logged Messages")

@objc(TfrmLogForm) final class TfrmLogForm: TForm {
    @objc var trvLog: TTreeView!
    @objc var imlTrvLog: TImageList!
    @objc var aclMain: TActionList!
    @objc var actStayOnTop: TAction!
    @objc var actSuspend: TAction!
    @objc var actLevel1: TAction!
    @objc var actLevel2: TAction!
    @objc var actLevel3: TAction!
    @objc var actLevel4: TAction!
    @objc var actPrint: TAction!
    @objc var actSaveToFile: TAction!
    @objc var actLoadfromFile: TAction!
    @objc var actClear: TAction!
    @objc var actSaveScreenshot: TAction!
    @objc var mniStayOnTop: TMenuItem!
    @objc var mniSuspend: TMenuItem!
    @objc var mni_StayOnTop: TMenuItem!
    @objc var mni_Suspend: TMenuItem!

    static var instance: TfrmLogForm?
    static var enabled: Bool { instance?.visibleForm ?? false }
    static var isShown: Bool { instance?.visibleForm ?? false }
    static var level = 0
    static var stack: [TTreeNode?] = [nil]
    static var lastNode: TTreeNode?
    static var suspended = false

    static func showLog(stayOnTop: Bool) {
        if instance == nil { instance = TfrmLogForm(resource: "TFRMLOGFORM", owner: Application.shared.mainForm) }
        instance?.show()
        setStayOnTop(stayOnTop)
    }

    static func hideLog() { instance?.hide() }

    static func setStayOnTop(_ v: Bool) { instance?.formWindow.level = v ? .floating : .normal }

    /// Log_Add* (0x599E0C / 0x599E28 …): adds a line at the current indentation level.
    static func add(_ text: String, color: TColor = clWindowText) {
        guard let f = instance, isShown, !suspended else { return }
        let parent = stack.last ?? nil
        let n = f.trvLog.addChild(parent ?? nil, text, color: color)
        lastNode = n
        f.trvLog.reload()
    }

    static func addBlue(_ s: String) { add(s, color: 0xFF0000) }
    static func addBlue2(_ s: String) { add(s, color: 0xFF0000) }
    static func addNavy2(_ s: String) { add(s, color: 0x800000) }

    static func indent(_ d: Int) {
        if d > 0 { for _ in 0..<d { stack.append(lastNode) } }
        else { for _ in 0..<(-d) where stack.count > 1 { stack.removeLast() } }
    }

    /// Log_Result (0x599D54): "OK" / "FAILED".
    static func result(_ ok: Bool) { add(ok ? "OK" : "FAILED", color: ok ? 0x8000 : 0xFF) }

    @objc func FormClose(_ sender: TObject, _ a: TCloseArgs) {
        if let m = Application.shared.mainForm as? TfrmBLHeliSuiteMain { m.actLogOn.checked = false; m.actLogStayOnTop.enabled = false }
    }
    /// FormCloseQuery (0x5994C0): the log window can always be closed.
    @objc func FormCloseQuery(_ sender: TObject, _ a: TBoolArgs) { a.value = true }

    /// Empty in BLHeliSuite as well (0x599530).
    @objc func redLogMouseDown(_ sender: TObject, _ a: TMouseArgs) {}

    /// mniLogClick (0x59AAF4) / pmnLogPopUpPopup (0x59B1AC): menu check marks.
    @objc func mniLogClick(_ sender: TObject) {
        mniStayOnTop?.checked = formWindow.level == .floating
        mniSuspend?.checked = TfrmLogForm.suspended
    }

    @objc func pmnLogPopUpPopup(_ sender: TObject) {
        mni_StayOnTop?.checked = formWindow.level == .floating
        mni_Suspend?.checked = TfrmLogForm.suspended
    }

    /// aclMainUpdate (0x598ED4): current log level.
    @objc func aclMainUpdate(_ sender: TObject) {
        actLevel1.checked = TfrmLogForm.level == 1
        actLevel2.checked = TfrmLogForm.level == 2
        actLevel3.checked = TfrmLogForm.level == 3
        actLevel4.checked = TfrmLogForm.level == 4
    }

    /// actPrintExecute (0x598F84 → 0x59A9AC): prints the log.
    @objc func actPrintExecute(_ sender: TObject) {
        var text = ""
        func walk(_ ns: [TTreeNode], _ d: Int) { for n in ns { text += String(repeating: "    ", count: d) + n.text + "\n"; walk(n.children, d + 1) } }
        walk(trvLog.roots, 0)
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 700))
        tv.string = text
        tv.font = NSFont(name: "Courier New", size: 9) ?? NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        let op = NSPrintOperation(view: tv)
        op.jobTitle = "BLHeliSuite Log"
        op.run()
    }

    /// The tree view draws the coloured lines itself (0x59B210); node data needs no release (0x59B458);
    /// selection changes are always allowed.
    @objc func trvLogAdvancedCustomDrawItem(_ sender: TObject) { trvLog.needsDisplay = true }
    @objc func trvLogDeletion(_ sender: TObject) { TfrmLogForm.lastNode = nil }
    @objc func trvLogChanging(_ sender: TObject) { trvLog.needsDisplay = true }

    @objc func actStayOnTopExecute(_ sender: TObject) { actStayOnTop.checked.toggle(); TfrmLogForm.setStayOnTop(actStayOnTop.checked) }
    @objc func actSuspendExecute(_ sender: TObject) { actSuspend.checked.toggle(); TfrmLogForm.suspended = actSuspend.checked }
    @objc func actLevel1Execute(_ sender: TObject) { TfrmLogForm.level = 1 }
    @objc func actLevel2Execute(_ sender: TObject) { TfrmLogForm.level = 2 }
    @objc func actLevel3Execute(_ sender: TObject) { TfrmLogForm.level = 3 }
    @objc func actLevel4Execute(_ sender: TObject) { TfrmLogForm.level = 4 }
    @objc func actClearExecute(_ sender: TObject) { trvLog.clear(); TfrmLogForm.stack = [nil] }
    @objc func actSaveScreenshotExecute(_ sender: TObject) { saveScreenshot(of: self, prefix: "BLHeliSuiteLogWindow") }

    @objc func actSaveToFileExecute(_ sender: TObject) {
        guard let url = SaveDialog.execute(fileName: "BLHeliSuite.log", filter: "Log file (*.log)|*.log") else { return }
        var s = ""
        func walk(_ ns: [TTreeNode], _ d: Int) { for n in ns { s += String(repeating: "  ", count: d) + n.text + "\r\n"; walk(n.children, d + 1) } }
        walk(trvLog.roots, 0)
        try? s.write(to: url, atomically: true, encoding: .utf8)
    }

    @objc func actLoadfromFileExecute(_ sender: TObject) {
        guard let url = OpenDialog.execute(filter: "Log file (*.log)|*.log"), let t = try? String(contentsOf: url, encoding: .utf8) else { return }
        trvLog.clear()
        for l in t.components(separatedBy: .newlines) where !l.isEmpty { _ = trvLog.addChild(nil, l) }
        trvLog.reload()
    }

}
