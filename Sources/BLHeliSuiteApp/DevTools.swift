import AppKit
import VCL

/// Development helpers driven by environment variables (screenshots / scripted actions for testing).
///   BLHELI_SCRIPT="interface=E;port=/dev/ttys002;wait=1;snap=/tmp/a.png;action=actReadSetup;wait=2;snap=/tmp/b.png;quit"
enum DevTools {
    static func start(_ m: TfrmBLHeliSuiteMain) {
        guard let script = ProcessInfo.processInfo.environment["BLHELI_SCRIPT"] else { return }
        let steps = script.split(separator: ";").map(String.init)
        // start after the first Application.OnIdle: it selects the interface stored in BLHeliSuite.ini (0x671FD0)
        func begin() {
            if m.firstIdleDone { run(steps, 0, m); return }
            let t = Timer(timeInterval: 0.1, repeats: false) { _ in begin() }
            RunLoop.main.add(t, forMode: .common)
        }
        begin()
    }

    static func run(_ steps: [String], _ i: Int, _ m: TfrmBLHeliSuiteMain) {
        guard i < steps.count else { return }
        let s = steps[i]
        let kv = s.split(separator: "=", maxSplits: 1).map(String.init)
        FileHandle.standardError.write(("[script] " + s + "\n").data(using: .utf8)!)
        // the next step is scheduled first: actions may open modal dialogs (runModal keeps .common timers alive)
        let delay = kv[0] == "wait" ? (Double(kv[1]) ?? 1) : 0.3
        let t = Timer(timeInterval: delay, repeats: false) { _ in run(steps, i + 1, m) }
        RunLoop.main.add(t, forMode: .common)
        switch kv[0] {
        case "interface":
            let map: [String: IntfType] = ["A": .silC2Toolstick, "B": .silC2_4wif, "C": .silBLBCom, "D": .silBLB4wif, "E": .silBLBCF,
                                           "1": .atmBLBCom, "2": .atmBLB4wif, "3": .atmSK4wif, "4": .atmSKAULinker, "5": .atmSKTGYLinker,
                                           "6": .atmBLBCF, "X": .atmISP]
            if let t = map[kv[1]] { m.selectInterface(t) }
        case "port":
            m.serialIntf?.portPath = kv[1]
            m.fillComPorts(true)
            m.updateCaption()
        case "snap":
            snap(kv[1], m)
        case "action":
            if let a: TAction = m.component(kv[1]) { a.execute() }
        case "tab":
            if let t: TTabSheet = m.component(kv[1]) { m.pgcMain.selectPage(t) }
        case "key":
            // press a button of the topmost form by caption, e.g. key=OK
            let w = NSApp.modalWindow ?? NSApp.keyWindow
            if let f = w?.delegate as? TForm { f.pressButton(caption: kv[1]) }
        case "select":
            // select=<component>:<index> in the topmost form (list/combo boxes)
            let a = kv[1].split(separator: ":").map(String.init)
            let f = ((NSApp.modalWindow ?? NSApp.keyWindow)?.delegate as? TForm) ?? m
            let c: TControl? = f.component(a[0]) ?? DevTools.find(a[0], in: f)
            if let lb = c as? TListBox { lb.itemIndex = Int(a[1]) ?? 0 }
            else if let cb = c as? TComboBox { cb.itemIndex = Int(a[1]) ?? 0; cb.onChange?(cb) }
        case "click":
            let f = ((NSApp.modalWindow ?? NSApp.keyWindow)?.delegate as? TForm) ?? m
            if let c: TControl = f.component(kv[1]) ?? DevTools.find(kv[1], in: f) { c.click() }
        case "set":
            // set=<control>:<value> – scroll bar / track bar position, edit text or check box state (topmost form, frames included)
            let a = kv[1].split(separator: ":", maxSplits: 1).map(String.init)
            let f = ((NSApp.modalWindow ?? NSApp.keyWindow)?.delegate as? TForm) ?? m
            guard a.count == 2, let c: TControl = f.component(a[0]) ?? DevTools.find(a[0], in: f) ?? m.component(a[0]) ?? DevTools.find(a[0], in: m) else { break }
            if let sb = c as? TScrollBar { sb.position = Int(a[1]) ?? sb.position }
            else if let tb = c as? TTrackBar { tb.position = Int(a[1]) ?? tb.position }
            else if let cb = c as? TCheckBox { cb.checked = a[1] == "1"; cb.onClick?(cb) }
            else if let e = c as? TEdit { e.textValue = a[1]; e.onChange?(e) }
        case "dump":
            // dump=<file>: texts of all visible forms (dialogs first) and the status bar, appended to <file>
            var out = "---- step \(i)\n"
            for w in NSApp.windows.reversed() where w.isVisible {
                guard let f = w.delegate as? TForm else { continue }
                out += "[\(String(describing: type(of: f))) \"\(f.caption)\"]\n"
                if f === m { out += "status: " + m.statusText.replacingOccurrences(of: "\r\n", with: " | ") + "\n"; continue }
                func walk(_ v: NSView) {
                    if let c = v as? TControl, !c.isHiddenOrHasHiddenAncestor, !(c is TButton), !c.caption.isEmpty, !(c is TForm) {
                        out += "  " + c.caption.replacingOccurrences(of: "\r\n", with: " | ").replacingOccurrences(of: "\n", with: " | ") + "\n"
                    }
                    for x in v.subviews { walk(x) }
                }
                if let cv = w.contentView { walk(cv) }
            }
            if let h = FileHandle(forWritingAtPath: kv[1]) ?? { FileManager.default.createFile(atPath: kv[1], contents: nil); return FileHandle(forWritingAtPath: kv[1]) }() {
                h.seekToEndOfFile(); h.write(out.data(using: .utf8)!); h.closeFile()
            }
        case "fuses":
            // fuses=<signature hex>[:critical] – fuse editor without programmer, factory defaults of the device
            let a = kv[1].split(separator: ":").map(String.init)
            let sig = Int(a[0], radix: 16) ?? 0x1E9307
            let model = TAVRFuses()
            try? model.setDevice(sig)
            if let v = TfrmFuseEditor.edit(signature: sig, chip: model.value, fuses: model.value, deviceChangeable: true,
                                           critical: a.count > 1) {
                FileHandle.standardError.write(String(format: "[script] fuses result 0x%08X\n", v).data(using: .utf8)!)
            }
        case "saveini":
            // saveini=<file>[:escNo] – TBLHeli.SaveToIni of the workspace (escNo 0) or of ESC n, without dialog
            let a = kv[1].split(separator: ":").map(String.init)
            let n = a.count > 1 ? Int(a[1]) ?? 0 : 0
            (n == 0 ? m.workspace : m.blheli[n]).saveToIni(URL(fileURLWithPath: a[0]), escNo: n, m.db)
        case "loadini":
            // loadini=<file> – TBLHeli.LoadFromIni into the workspace (section ESC0), like "Read Setup from ini"
            var found = false
            if m.workspace.loadFromIni(URL(fileURLWithPath: kv[1]), escNo: 0, m.db, found: &found) { m.showESCData() }
            FileHandle.standardError.write("[script] loadini found=\(found)\n".data(using: .utf8)!)
        case "drop":
            // drop=<file> – like dropping the file on the main window (WM_DROPFILES)
            m.onDropFiles?([URL(fileURLWithPath: kv[1])])
        case "quit":
            exit(0)
        default: break
        }
    }

    /// Finds a control by name also inside frames (fraCFMotorTest1.cbxActivate …).
    static func find(_ name: String, in f: TForm) -> TControl? {
        func walk(_ v: NSView) -> TControl? {
            if let c = v as? TControl, c.name == name { return c }
            for s in v.subviews { if let r = walk(s) { return r } }
            return nil
        }
        return f.formWindow.contentView.flatMap(walk)
    }

    /// Saves every visible form: the main form to `path`, other forms to path-<Class>.png.
    static func snap(_ path: String, _ m: TfrmBLHeliSuiteMain) {
        for w in NSApp.windows where w.isVisible {
            guard let f = w.delegate as? TForm else { continue }
            w.displayIfNeeded()
            guard let png = f.screenshotPNG() else { continue }
            let p = w === m.formWindow ? path : path.replacingOccurrences(of: ".png", with: "-\(String(describing: type(of: f))).png")
            try? png.write(to: URL(fileURLWithPath: p))
        }
    }
}
