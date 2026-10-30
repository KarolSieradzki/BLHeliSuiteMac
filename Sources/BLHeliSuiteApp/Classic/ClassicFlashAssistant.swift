import SwiftUI
import BLHeliCore

/// "Flash Assistant" dialog in the look of TfrmFlashAssistant (576 px wide).
struct ClassicFlashAssistant: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var ignoreMCU = false
    @State private var search = ""
    @State private var layoutIndex: Int?
    @State private var mode: ESCMode = .multi
    @State private var entryRes: Int?
    @State private var keepSettings = true
    @State private var initialized = false
    @State private var confirmFlash = false

    var masterSlot: ESCSlot? {
        guard let m = model.masterIndex, m < model.slots.count else { return nil }
        return model.slots[m]
    }
    var device: DeviceInfo? { masterSlot?.device }
    var current: BLHeliSettings? {
        guard let s = masterSlot?.settings, (try? s.validate()) != nil else { return nil }
        return s
    }

    var candidates: [FirmwareEntry] {
        guard let db = model.database, let d = device else { return [] }
        return FirmwareSelection.candidates(db, device: d, ignoreMCU: ignoreMCU)
    }

    var allLayouts: [(index: Int, layout: ESCLayout)] {
        guard let db = model.database, let d = device else { return [] }
        return FirmwareSelection.layouts(db, family: d.family, entries: candidates)
    }

    var listed: [(index: Int, layout: ESCLayout)] {
        let q = search.trimmingCharacters(in: .whitespaces).uppercased()
        if q.isEmpty { return allLayouts }
        return allLayouts.filter { $0.layout.name.uppercased().contains(q) || $0.layout.desc.uppercased().contains(q) }
    }

    var modes: [ESCMode] {
        guard let li = layoutIndex else { return [] }
        let ms = Set(candidates.filter { $0.layout == li }.map(\.escMode))
        return ESCMode.allCases.filter { ms.contains($0) }
    }

    var entries: [FirmwareEntry] {
        guard let li = layoutIndex else { return [] }
        return candidates.filter { $0.layout == li && $0.escMode == mode }.sorted { $0.rev > $1.rev }
    }

    var selectedEntry: FirmwareEntry? { entries.first { $0.res == entryRes } }

    var targets: String { model.active.sorted().map { "#\($0 + 1)" }.joined(separator: ", ") }

    var body: some View {
        Abs(width: 576, height: 400) {
            Rectangle().fill(Win.face).at(0, 0, 576, 71)
            Text(device.map { "ESC\(targets): \($0.description)" } ?? "ESC: not detected – run \"Check\" first")
                .font(Win.tahoma(13, bold: true))
                .lineLimit(1)
                .at(4, 3, 418, 17)
            WinCheckBox(title: "Ignore inappropriate MCU", isOn: $ignoreMCU)
                .help("Shows all firmware files of the MCU family and allows to flash even if the file doesn't appear appropriate for the detected MCU.")
                .at(426, 3, 148, 15)
            Text("Current:").font(Win.tahoma(13)).at(5, 23, 52, 16)
            Text(current.map { model.database?.layout(family: $0.family, index: model.database?.layoutIndex(family: $0.family, name: $0.layoutName) ?? -1)?.displayName ?? $0.layoutName } ?? "UNKNOWN")
                .font(Win.tahoma(13, bold: true)).foregroundColor(Win.blue).lineLimit(1).at(58, 23, 172, 16)
            Text(current?.mode.displayName ?? "")
                .font(Win.tahoma(13, bold: true)).lineLimit(1).at(234, 23, 140, 16)
            Text("Firmware Rev.:").font(Win.tahoma(13)).at(377, 23, 92, 16)
            Text(current.map { "\($0.isBLHeliS ? "BLHeli_S" : "BLHeli") \($0.revisionString)" } ?? "X.X")
                .font(Win.tahoma(13, bold: true)).foregroundColor(Win.blue).lineLimit(1).at(471, 23, 104, 16)
            Text("Flash to:").font(Win.tahoma(13)).at(4, 44, 56, 16)
            WinCombo(items: allLayouts.map { ($0.index, $0.layout.displayName) },
                     selection: Binding(get: { layoutIndex ?? -1 }, set: { layoutIndex = $0 }), placeholder: "select ESC")
                .disabled(allLayouts.isEmpty)
                .at(61, 42, 168, 21)
            WinCombo(items: modes.map { ($0, $0.displayName) }, selection: $mode)
                .disabled(modes.isEmpty)
                .at(234, 42, 125, 21)
            WinCombo(items: entries.map { ($0.res, "\($0.firmwareName) \($0.revStr)") },
                     selection: Binding(get: { entryRes ?? -1 }, set: { entryRes = $0 }), placeholder: "-")
                .disabled(entries.isEmpty)
                .at(375, 42, 196, 21)
            list.at(0, 71, 576, 231)
            info.at(0, 302, 576, 53)
            Rectangle().fill(Win.shadow).at(0, 355, 576, 1)
            WinButton(title: "OK", glyph: "ok", isDefault: true) { confirmFlash = true }
                .disabled(selectedEntry == nil || model.busy)
                .at(23, 365, 87, 25)
            WinButton(title: "Cancel", glyph: "cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .at(130, 365, 91, 25)
            WinButton(title: "Ignore the list, pick a file...", glyph: "ignore") {
                dismiss()
                DispatchQueue.main.async { model.flashOther() }
            }
            .at(239, 365, 188, 25)
            Text("Find:").at(436, 371, 28, 13)
            WinEdit(text: $search).at(466, 367, 104, 21)
        }
        .background(Win.face)
        .environment(\.font, Win.tahoma(11))
        .preferredColorScheme(.light)
        .onAppear(perform: preselect)
        .onChange(of: layoutIndex) { _ in
            let ms = modes
            if !ms.contains(mode) {
                if let cm = current?.mode, ms.contains(cm) { mode = cm } else if let m = ms.last { mode = m }
            }
            entryRes = entries.first?.res
        }
        .onChange(of: mode) { _ in entryRes = entries.first?.res }
        .onChange(of: ignoreMCU) { _ in
            if let li = layoutIndex, !allLayouts.contains(where: { $0.index == li }) { layoutIndex = allLayouts.first?.index }
        }
        .confirmationDialog("Flash BLHeli", isPresented: $confirmFlash, titleVisibility: .visible) {
            Button("Yes, flash", role: .destructive) {
                if let e = selectedEntry {
                    dismiss()
                    model.flash(entry: e, keepSettings: keepSettings)
                }
            }
            Button("No", role: .cancel) {}
        } message: {
            if let e = selectedEntry, let db = model.database {
                Text("Do you want to flash ESC \(targets) with\n\(db.layout(family: e.mcuFamily, index: e.layout)?.displayName ?? e.name) – \(e.firmwareName) \(e.revStr) \(e.modeName)?")
            }
        }
    }

    /// lbBuildInHexFiles: owner-drawn list box, clCream, blue bold Tahoma.
    var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(listed, id: \.index) { item in
                        let sel = item.index == layoutIndex
                        HStack(spacing: 8) {
                            Text(item.layout.displayName)
                                .font(Win.tahoma(13, bold: true))
                                .foregroundColor(sel ? .white : Win.blue)
                            if item.layout.desc != "" && item.layout.desc != item.layout.name {
                                Text(item.layout.name)
                                    .font(Win.tahoma(11))
                                    .foregroundColor(sel ? .white : Win.grayText)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 4)
                        .frame(height: 19)
                        .background(sel ? Win.selection : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { layoutIndex = item.index }
                        .id(item.index)
                    }
                }
            }
            .background(Win.cream)
            .overlay(Rectangle().strokeBorder(Win.editBorder, lineWidth: 1))
            .overlay {
                if device == nil {
                    Text("No ESC detected – connect and click \"Check\" first.")
                        .font(Win.tahoma(13, bold: true)).foregroundColor(Win.red)
                }
            }
            .onChange(of: layoutIndex) { li in if let li { withAnimation(nil) { proxy.scrollTo(li, anchor: .center) } } }
            .onAppear { if let li = layoutIndex { proxy.scrollTo(li, anchor: .center) } }
        }
    }

    var info: some View {
        Abs(width: 576, height: 53) {
            WinCheckBox(title: "Keep current settings", isOn: $keepSettings).disabled(current == nil).at(8, 4, 150, 16)
            WinCheckBox(title: "Verify flash", isOn: $model.verifyFlash).at(165, 4, 100, 16)
            if device?.isISP == true {
                WinCheckBox(title: "Include BLHeli bootloader", isOn: $model.ispWriteBootloader).at(270, 4, 160, 16)
                WinCheckBox(title: "Write fuses", isOn: $model.ispWriteFuses).at(436, 4, 120, 16)
            }
            Text(infoText.text)
                .foregroundColor(infoText.warning ? Win.rgb(0xC04000) : Win.grayText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .at(8, 23, 560, 28)
        }
    }

    var infoText: (text: String, warning: Bool) {
        guard let e = selectedEntry, let db = model.database, let d = device else {
            return ("Choosing the wrong MCU or ESC layout may cause severe damage and/or injuries! Always check carefully that you are flashing the exact matching file to your ESC.", false)
        }
        let plan = FirmwareSelection.makePlan(db, entry: e, current: keepSettings ? current : nil)
        var w = FirmwareSelection.check(plan: plan.plan, entry: e, device: d, current: current, db: db)
        if let pw = plan.warning { w.insert(pw, at: 0) }
        if !w.isEmpty { return (w.joined(separator: "  "), true) }
        return ("\(e.firmwareName) \(e.revStr) – \(e.modeName) – \(db.layout(family: e.mcuFamily, index: e.layout)?.displayName ?? e.name)  (EEprom layout rev \(e.layoutRev))", false)
    }

    func preselect() {
        guard !initialized, let db = model.database, let d = device else { return }
        initialized = true
        if let pref = FirmwareSelection.preferred(db, device: d, settings: current) {
            layoutIndex = pref.layout
            mode = pref.escMode
            entryRes = pref.res
            DispatchQueue.main.async { entryRes = pref.res }
        } else if let first = allLayouts.first {
            layoutIndex = first.index
        }
    }
}
