import SwiftUI
import BLHeliCore

/// "Flash BLHeli" assistant (TfrmFlashAssistant): pick ESC layout, mode and revision from the
/// built-in firmware list.
struct FlashAssistantView: View {
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

    var layouts: [(index: Int, layout: ESCLayout)] {
        guard let db = model.database, let d = device else { return [] }
        let all = FirmwareSelection.layouts(db, family: d.family, entries: candidates)
        let q = search.trimmingCharacters(in: .whitespaces).uppercased()
        if q.isEmpty { return all }
        return all.filter { $0.layout.name.uppercased().contains(q) || $0.layout.desc.uppercased().contains(q) }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Flash BLHeli").font(.title2.weight(.semibold))
            if let d = device {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Target: ESC \(model.active.sorted().map { "#\($0 + 1)" }.joined(separator: ", ")) – \(d.description)")
                    if let c = current {
                        Text("Currently: \(c.summary(database: model.database))").foregroundStyle(.secondary)
                    } else {
                        Text("Currently: no valid BLHeli firmware").foregroundStyle(.orange)
                    }
                }
                .font(.callout)
            } else {
                Text("No ESC detected – run Check first.").foregroundStyle(.red)
            }
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Search ESC (e.g. A_H_30, Littlebee, XP-12A)", text: $search)
                        .textFieldStyle(.roundedBorder)
                    List(layouts, id: \.index, selection: $layoutIndex) { item in
                        HStack {
                            Text(item.layout.displayName)
                            Spacer()
                            Text(item.layout.name).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(item.index)
                    }
                    .frame(minWidth: 330, minHeight: 300)
                    Toggle("Show all firmware files (ignore MCU check)", isOn: $ignoreMCU)
                        .help("Set checkmark here to show all firmware files in the list, and allow flash even if it doesn't appear appropriate for the detected MCU.")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Mode:", selection: $mode) {
                        ForEach(modes, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .disabled(modes.isEmpty)
                    Picker("Revision:", selection: $entryRes) {
                        Text("–").tag(Int?.none)
                        ForEach(entries) { e in
                            Text("\(e.firmwareName) \(e.revStr)").tag(Int?.some(e.res))
                        }
                    }
                    .disabled(entries.isEmpty)
                    Toggle("Keep current settings (translate to the new revision)", isOn: $keepSettings)
                        .disabled(current == nil)
                    Toggle("Verify flash after write", isOn: $model.verifyFlash)
                    if device?.isISP == true {
                        Toggle("Include BLHeli bootloader (initial ISP flash)", isOn: $model.ispWriteBootloader)
                        Toggle("Write fuses of the ESC layout", isOn: $model.ispWriteFuses)
                        if let e = selectedEntry, let db = model.database {
                            let x = FirmwareSelection.ispExtras(db, entry: e)
                            Text("Bootloader: \(x.bootloaderName ?? "none for this ESC")  ·  Fuses: \(x.fuses.map { String(format: "L=0x%02X H=0x%02X", $0.low, $0.high) + ($0.ext.map { String(format: " E=0x%02X", $0) } ?? "") } ?? "–")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let e = selectedEntry, let db = model.database {
                        GroupBox("Selected file") {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(db.layout(family: e.mcuFamily, index: e.layout)?.displayName ?? e.name).font(.headline)
                                Text("\(e.firmwareName) \(e.revStr) – \(e.modeName)")
                                Text("MCU code: 0x\(String(e.mcu, radix: 16, uppercase: true)) · EEprom layout rev \(e.layoutRev)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(warnings(e), id: \.self) { w in
                            Label(w, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                }
                .frame(minWidth: 340)
            }
            Text("Choosing the wrong MCU or ESC layout may cause severe damage and/or injuries! Always check carefully that you are flashing the exact matching file to your ESC. Remove the propellers.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Flash") { confirmFlash = true }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedEntry == nil)
            }
        }
        .padding(18)
        .frame(width: 820, height: 620)
        .onAppear(perform: preselect)
        .onChange(of: layoutIndex) { _ in
            let ms = modes
            if !ms.contains(mode) {
                if let cm = current?.mode, ms.contains(cm) { mode = cm } else if let m = ms.last { mode = m }
            }
            entryRes = entries.first?.res
        }
        .onChange(of: mode) { _ in entryRes = entries.first?.res }
        .confirmationDialog("Flash BLHeli", isPresented: $confirmFlash, titleVisibility: .visible) {
            Button("Flash", role: .destructive) {
                if let e = selectedEntry {
                    dismiss()
                    model.flash(entry: e, keepSettings: keepSettings)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let e = selectedEntry, let db = model.database {
                Text("Do you want to flash ESC \(model.active.sorted().map { "#\($0 + 1)" }.joined(separator: ", ")) with\n\(db.layout(family: e.mcuFamily, index: e.layout)?.displayName ?? e.name) – \(e.firmwareName) \(e.revStr) \(e.modeName)?")
            }
        }
    }

    func warnings(_ e: FirmwareEntry) -> [String] {
        guard let db = model.database, let d = device else { return [] }
        let plan = FirmwareSelection.makePlan(db, entry: e, current: keepSettings ? current : nil)
        var w = FirmwareSelection.check(plan: plan.plan, entry: e, device: d, current: current, db: db)
        if let pw = plan.warning { w.insert(pw, at: 0) }
        return w
    }

    func preselect() {
        guard !initialized, let db = model.database, let d = device else { return }
        initialized = true
        if let pref = FirmwareSelection.preferred(db, device: d, settings: current) {
            layoutIndex = pref.layout
            mode = pref.escMode
            entryRes = pref.res
            DispatchQueue.main.async { entryRes = pref.res }
        } else if let first = layouts.first {
            layoutIndex = first.index
        }
    }
}
