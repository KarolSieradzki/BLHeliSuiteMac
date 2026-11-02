import AppKit
import VCL
import BLHeliCore

/// Flash Assistant – port of TfrmFlashAssistant (FUN_0065572C … FUN_006572B8).
@objc(TfrmFlashAssistant) final class TfrmFlashAssistant: TForm {
    @objc var pnlBottom: TPanel!
    @objc var btnOK: TButton!
    @objc var btnIgnore: TButton!
    @objc var btnCancel: TButton!
    @objc var cbShowFavoritesOnly: TCheckBox!
    @objc var btnScreenShot: TButton!
    @objc var pnlMain: TPanel!
    @objc var lbBuildInHexFiles: TListBox!
    @objc var pnlTop: TPanel!
    @objc var lblLayout: TLabel!
    @objc var lblType: TLabel!
    @objc var lblRev: TLabel!
    @objc var lblRevsionStatic: TLabel!
    @objc var lblESCCurrent: TLabel!
    @objc var lblNewTarget: TLabel!
    @objc var cbbSelectESC: TComboBox!
    @objc var cbbSelectESCMode: TComboBox!
    @objc var cbbSelectBLHeliRevision: TComboBox!
    @objc var pnlTopTop: TPanel!
    @objc var lblCurrentESC: TLabel!
    @objc var cbIgnoreInappropriateMCU: TCheckBox!
    @objc var pmnESCSelectList: TPopupMenu!
    @objc var mniSelectDeselectFavorite: TMenuItem!
    @objc var actlFlashAssistan: TActionList!
    @objc var actIsFavorite: TAction!
    @objc var actShowFavoritesOnly: TAction!
    @objc var actIgnoreInappropriateMCU: TAction!

    var db: FirmwareDatabase!
    var entries: [FirmwareEntry] = []      // resource list of the current brand (0x690F50)
    var listIndex: [Int] = []              // list box line -> entries index (Objects)
    var listKeys: [String] = []            // "MODE layout" keys (Self+0x3EC)
    var favorites: [String] = []           // Self+0x3F0
    var mcu = 0                            // Self+0x40C detected MCU
    var currentLayout = "UNKNOWN"          // Self+0x3E0
    var currentRev = "X.X"                 // Self+0x3DC
    var currentMode = -1                   // Self+0x3D8
    var currentModeText = "UNKNOWN MODE"   // Self+0x3E4
    var allIndex = 1, allBLHeliIndex = 0, allBLHeliSIndex = 0   // Self+0x414/0x41C/0x418
    var selected: FirmwareEntry?
    var escTitle = ""

    static var favoritesFile: URL { AppFolders.userFolder.appendingPathComponent("Favorites.txt") }

    /// FUN_0065572C: returns the chosen entry, nil (cancel) or `pickFile` = true (Ignore the list, pick a file…).
    static func execute(db: FirmwareDatabase, mcu: Int, current: TBLHeli?, escTitle: String, ignoreMCUAllowed: Bool) -> (FirmwareEntry?, Bool) {
        let f = TfrmFlashAssistant(resource: "TFRMFLASHASSISTANT", owner: Application.shared.mainForm)
        f.db = db
        f.mcu = mcu
        f.escTitle = escTitle
        f.prepare(current: current, ignoreAllowed: ignoreMCUAllowed)
        let r = f.showModal()
        let sel = f.selected
        f.release()
        if r == mrOk { return (sel, false) }
        if r == mrIgnore { return (nil, true) }
        return (nil, false)
    }

    @objc func FormCreate(_ sender: TObject) {
        caption = NL("Flash Assistant")
        lbBuildInHexFiles.hint = NL(" LEFT to select a specific firmware.\\nClick RIGTH to select/deselect ESC as Favorite (*)")
        actShowFavoritesOnly.hint = NL("Set checkmark here to only show those ESC in the list,\\nwhich formerly were marked as favorites.")
        actIgnoreInappropriateMCU.hint = NL("Set checkmark here to show all firmware file in the list,\\nand allow flash even if it doesn't appear appropriate for the detected MCU.")
        btnIgnore.modalResult = mrIgnore
        if let t = try? String(contentsOf: TfrmFlashAssistant.favoritesFile, encoding: .utf8) {
            favorites = t.components(separatedBy: .newlines).filter { !$0.isEmpty }
        }
    }

    @objc func FormShow(_ sender: TObject) {}

    func prepare(current: TBLHeli?, ignoreAllowed: Bool) {
        let fam: MCUFamily = Brand.current == 1 ? .silabs : .atmel
        entries = (fam == .silabs ? db.silabs : db.atmel).firmware
        actIgnoreInappropriateMCU.checked = false
        actIgnoreInappropriateMCU.enabled = ignoreAllowed
        if let c = current, c.isValid {
            currentLayout = c.layoutName
            currentRev = c.revisionString
            currentMode = c.mode
            currentModeText = ["MAIN", "TAIL", "MULTI"][min(c.mode, 2)]
        }
        lblCurrentESC.caption = "ESC: " + escTitle
        lblLayout.caption = currentLayout
        lblType.caption = currentModeText
        lblRev.caption = currentRev
        lblLayout.adjustBounds()
        lblType.left = lblLayout.left + lblLayout.width + 12
        fillESCList()
        fillModes()
        fillRevisions()
        fillList()
        updateFavoriteAction()
    }

    var favoritesOnly: Bool { actShowFavoritesOnly.checked && actShowFavoritesOnly.enabled }

    func layoutName(_ e: FirmwareEntry) -> String {
        let fam: MCUFamily = Brand.current == 1 ? .silabs : .atmel
        return db.layout(family: fam, index: e.layout)?.displayName ?? e.name
    }

    func layoutKey(_ e: FirmwareEntry) -> String {
        let fam: MCUFamily = Brand.current == 1 ? .silabs : .atmel
        return db.layout(family: fam, index: e.layout)?.name ?? e.name
    }

    func modeName(_ m: Int) -> String { ["MAIN", "TAIL", "MULTI"][min(max(m, 0), 2)] }

    func mcuMatches(_ e: FirmwareEntry) -> Bool { mcu <= 0 || e.mcu == mcu || actIgnoreInappropriateMCU.checked }

    /// FUN_006568EC.
    func fillESCList() {
        let prev = cbbSelectESC.text_
        var names: [String] = []
        for e in entries {
            let n = layoutName(e)
            if names.contains(n) { continue }
            if !mcuMatches(e) { continue }
            if favoritesOnly && !["MAIN", "TAIL", "MULTI"].contains(where: { favorites.contains($0 + " " + n) }) { continue }
            names.append(n)
        }
        names.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        var head: [String]
        if !favoritesOnly {
            head = Brand.current == 1 ? ["- ALL ESC -", "- ALL BLHeli_S ESC -", "- ALL BLHeli ESC -"] : ["- ALL ESC -"]
        } else {
            head = Brand.current == 1 ? ["- ALL FAVORITE ESC -", "- FAVORITE BLHeli_S ESC -", "- FAVORITE BLHeli ESC -"] : ["- ALL FAVORITE ESC -"]
        }
        allIndex = head.count
        allBLHeliIndex = Brand.current == 1 ? 2 : 0
        allBLHeliSIndex = Brand.current == 1 ? 1 : 0
        cbbSelectESC.items = head + names
        if let i = cbbSelectESC.items.firstIndex(of: prev) { cbbSelectESC.itemIndex = i }
        else if let i = cbbSelectESC.items.firstIndex(of: currentLayoutDisplay) { cbbSelectESC.itemIndex = i }
        else { cbbSelectESC.itemIndex = 0 }
        cbbSelectESC.dropDownCount = cbbSelectESC.items.count
    }

    var currentLayoutDisplay: String {
        let fam: MCUFamily = Brand.current == 1 ? .silabs : .atmel
        if let i = db.layoutIndex(family: fam, name: currentLayout), let l = db.layout(family: fam, index: i) { return l.displayName }
        return currentLayout
    }

    /// FUN_0065651C.
    func fillModes() {
        cbbSelectESCMode.items = ["MAIN, TAIL, MULTI", "MAIN", "TAIL", "MULTI"]
        cbbSelectESCMode.itemIndex = currentMode >= 0 ? currentMode + 1 : 0
    }

    /// FUN_006565CC.
    func fillRevisions() {
        var revs: [String] = []
        for e in entries where escFilter(e) && mcuMatches(e) {
            if !revs.contains(e.revStr) { revs.append(e.revStr) }
        }
        cbbSelectBLHeliRevision.items = ["All BLHeli Revisions", "Latest available BLHeli Revision"] + revs
        cbbSelectBLHeliRevision.itemIndex = 1
    }

    func escFilter(_ e: FirmwareEntry) -> Bool {
        let i = cbbSelectESC.itemIndex
        if i >= allIndex { return layoutName(e) == cbbSelectESC.text_ }
        if Brand.current == 1 {
            if i == allBLHeliSIndex && i != 0 { return e.isBLHeliS }
            if i == allBLHeliIndex && i != 0 { return !e.isBLHeliS }
        }
        return true
    }

    /// FUN_00655F68.
    func fillList() {
        var lines: [String] = []
        listIndex = []
        listKeys = []
        var latest: [String: Int] = [:]
        for (k, e) in entries.enumerated() {
            guard mcuMatches(e), escFilter(e) else { continue }
            let key = modeName(e.mode) + " " + layoutName(e)
            if favoritesOnly && !favorites.contains(key) && cbbSelectESC.itemIndex < allIndex { continue }
            let mi = cbbSelectESCMode.itemIndex
            if mi > 0 && e.mode != mi - 1 { continue }
            let ri = cbbSelectBLHeliRevision.itemIndex
            if ri == 1 {
                if let j = latest[layoutName(e) + "|" + modeName(e.mode)] {
                    if entries[listIndex[j]].rev >= e.rev { continue }
                    var s = key + " [Rev: " + e.revStr + "] "
                    if !e.extra.isEmpty { s += " ~" }
                    lines[j] = s
                    listIndex[j] = k
                    continue
                }
            } else if ri >= 2 && e.revStr != cbbSelectBLHeliRevision.text_ {
                continue
            }
            var s = key + " [Rev: " + e.revStr + "] "
            if !e.extra.isEmpty { s += " ~" }
            latest[layoutName(e) + "|" + modeName(e.mode)] = lines.count
            lines.append(s)
            listIndex.append(k)
            listKeys.append(key)
        }
        lbBuildInHexFiles.items = lines
        lbBuildInHexFiles.itemIndex = lines.count == 1 ? 0 : -1
        updateFavoriteAction()
    }

    func updateFavoriteAction() {
        actShowFavoritesOnly.enabled = currentLayout == "UNKNOWN" || true
        if favoritesOnly && favorites.isEmpty { actShowFavoritesOnly.checked = false }
    }

    @objc func lbBuildInHexFilesDrawItem(_ sender: TObject, _ a: TDrawItemArgs) {
        let lb = lbBuildInHexFiles!
        let r = a.rect
        guard a.index < lb.items.count, a.index < listIndex.count else { Draw.fill(r, lb.nsColor); return }
        let e = entries[listIndex[a.index]]
        var color = Colors.ns(e.isBLHeliS ? 0xFF00FF : lb.font.color)
        if a.selected { Draw.fill(r, Theme.selection); color = .white } else { Draw.fill(r, lb.nsColor) }
        var s = lb.items[a.index]
        if favorites.contains(listKeys[a.index]) { s = "* " + s + " *" }
        TextDraw.draw(s, in: r.insetBy(dx: 2, dy: 0), font: lb.font.nsFont, color: color, layout: .center, accel: false)
    }

    @objc func lbBuildInHexFilesDblClick(_ sender: TObject) { btnOKClick(sender); if selected != nil { modalResult = mrOk } }

    @objc func lbBuildInHexFilesMouseUp(_ sender: TObject, _ a: TMouseArgs) {
        if a.button == .mbRight { actIsFavoriteExecute(sender) }
    }

    @objc func actIsFavoriteExecute(_ sender: TObject) {
        let i = lbBuildInHexFiles.itemIndex
        guard i >= 0 && i < listKeys.count else { return }
        let k = listKeys[i]
        if let j = favorites.firstIndex(of: k) { favorites.remove(at: j) } else { favorites.append(k) }
        try? favorites.joined(separator: "\n").write(to: TfrmFlashAssistant.favoritesFile, atomically: true, encoding: .utf8)
        lbBuildInHexFiles.needsDisplay = true
    }

    @objc func actShowFavoritesOnlyExecute(_ sender: TObject) {
        actShowFavoritesOnly.checked.toggle()
        fillESCList(); fillRevisions(); fillList()
    }

    @objc func actIgnoreInappropriateMCUExecute(_ sender: TObject) {
        actIgnoreInappropriateMCU.checked.toggle()
        fillESCList(); fillRevisions(); fillList()
    }

    @objc func btnOKClick(_ sender: TObject) {
        selected = nil
        if lbBuildInHexFiles.items.count == 1 { lbBuildInHexFiles.itemIndex = 0 }
        let i = lbBuildInHexFiles.itemIndex
        if i >= 0 && i < listIndex.count {
            selected = entries[listIndex[i]]
            modalResult = mrOk
            return
        }
        MsgDlg.show("Please select a Hex File from the List first.", .mtInformation, [.mbOK])
        btnOK.modalResult = mrNone
        modalResult = mrNone
    }

    @objc func btnScreenShotClick(_ sender: TObject) { saveScreenshot(of: self, prefix: "FlashAssistant") }
    @objc func cbbSelectESCCloseUp(_ sender: TObject) { fillRevisions(); fillList() }
    @objc func cbbSelectESCModeChange(_ sender: TObject) { fillList() }
    @objc func cbbSelectESCModeCloseUp(_ sender: TObject) { fillList() }
    @objc func cbbSelectBLHeliRevisionChange(_ sender: TObject) { fillList() }
    @objc func cbbSelectBLHeliRevisionCloseUp(_ sender: TObject) { fillList() }
    @objc func fstrgFlashAssistantAfterRestorePlacement(_ sender: TObject) {}
    @objc func fstrgFlashAssistantAfterSavePlacement(_ sender: TObject) {}

    /// cbbSelectESCDropDown (0x655C04): the list opens at the detected layout.
    @objc func cbbSelectESCDropDown(_ sender: TObject) {
        if let i = cbbSelectESC.items.firstIndex(of: currentLayout) { cbbSelectESC.itemIndex = i }
    }

    /// cbbSelectESCModeDropDown (0x655C58)
    @objc func cbbSelectESCModeDropDown(_ sender: TObject) {
        if currentMode >= 0 { cbbSelectESCMode.itemIndex = currentMode + 1 }
    }

    /// cbbSelectBLHeliRevisionDropDown (0x655C84)
    @objc func cbbSelectBLHeliRevisionDropDown(_ sender: TObject) {
        if let i = cbbSelectBLHeliRevision.items.firstIndex(of: currentRev) { cbbSelectBLHeliRevision.itemIndex = i }
    }
}
