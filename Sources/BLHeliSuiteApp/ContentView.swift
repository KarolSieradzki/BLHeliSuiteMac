import SwiftUI
import BLHeliCore

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar()
            Divider()
            TabBar()
            Group {
                switch model.selectedTab {
                case .setup: ESCSetupView()
                case .overview: ESCOverviewView()
                case .motors: MotorsView()
                case .interfaces: MakeInterfacesView()
                case .expert: ExpertToolsView()
                case .log: LogView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            BottomPanel()
        }
    }
}

struct HeaderBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("BLHeliSuite").font(.system(size: 20, weight: .bold))
                Text("for Mac – 16.7.14.9.0.2").font(.caption).foregroundStyle(.secondary)
            }
            Divider().frame(height: 34)
            Picker("Interface:", selection: $model.interfaceType) {
                Section("SiLabs") {
                    ForEach([InterfaceType.silabsBLBFlightController, .silabsBLBFourWay, .silabsC2FourWay, .silabsC2Toolstick]) { t in
                        Text(t.title).tag(t)
                    }
                }
                Section("Atmel") {
                    ForEach([InterfaceType.atmelFlightController, .atmelBLBFourWay, .atmelSKFourWay, .atmelISP]) { t in
                        Text(t.title).tag(t)
                    }
                }
            }
            .frame(maxWidth: 470)
            .disabled(model.busy)
            Spacer()
            if model.connected {
                Label(model.connectionInfo, systemImage: "bolt.horizontal.circle.fill")
                    .foregroundStyle(.green)
                    .lineLimit(1)
            } else {
                Label("Not connected", systemImage: "bolt.horizontal.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct BottomPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                ConnectionBox()
                if model.slots.count > 1 {
                    MultipleESCBox()
                } else if model.connected {
                    SingleESCBox()
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                ActionButtons()
                Spacer(minLength: 12)
                if model.busy {
                    ProgressView(value: model.progress)
                        .frame(width: 220)
                    Button("Cancel") { model.cancel() }
                        .controlSize(.small)
                }
                VStack(alignment: .trailing, spacing: 2) {
                    Text(model.status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if model.workspaceModified {
                        Label("Settings changed – not written yet", systemImage: "pencil.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
    }
}

struct TabBar: View {
    @EnvironmentObject var model: AppModel

    var tabs: [(MainTab, String)] {
        var t: [(MainTab, String)] = [(.setup, model.setupTabTitle), (.overview, "ESC Overview")]
        if model.interfaceType.isFlightController { t.append((.motors, "Motors")) }
        t.append((.interfaces, "Make Interfaces"))
        if model.expertMode { t.append((.expert, "Expert Tools")) }
        t.append((.log, "Log"))
        return t
    }

    var body: some View {
        HStack {
            Picker("", selection: $model.selectedTab) {
                ForEach(tabs, id: \.0) { t in Text(t.1).tag(t.0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .onChange(of: model.interfaceType) { _ in
            if !tabs.contains(where: { $0.0 == model.selectedTab }) { model.selectedTab = .setup }
        }
    }
}

struct ConnectionBox: View {
    @EnvironmentObject var model: AppModel
    static let bauds = [9600, 19200, 38400, 57600, 115200, 230400, 250000, 500000]

    var body: some View {
        if model.interfaceType == .silabsC2Toolstick {
            ToolstickBox()
        } else if model.interfaceType == .atmelISP {
            ISPBox()
        } else {
            GroupBox {
                HStack(spacing: 8) {
                    Picker("Port:", selection: $model.portPath) {
                        if model.ports.isEmpty { Text("no serial port").tag("") }
                        ForEach(model.ports) { p in
                            Text(p.displayName).tag(p.path)
                        }
                        if !model.portPath.isEmpty && !model.ports.contains(where: { $0.path == model.portPath }) {
                            Text(model.portPath).tag(model.portPath)
                        }
                    }
                    .frame(width: 290)
                    .disabled(model.connected || model.busy)
                    Button {
                        model.refreshPorts()
                    } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh the list of serial ports")
                    .disabled(model.connected || model.busy)
                    Picker("Baud:", selection: $model.baud) {
                        ForEach(Self.bauds, id: \.self) { Text(verbatim: String($0)).tag($0) }
                    }
                    .frame(width: 130)
                    .disabled(model.connected || model.busy)
                    Button(model.connected ? "Disconnect" : "Connect") { model.toggleConnection() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.busy)
                        .frame(minWidth: 90)
                }
            }
        }
    }
}

struct SingleESCBox: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        GroupBox {
            HStack {
                Text("Single ESC").font(.callout)
                Button("Check") { model.check() }.disabled(model.busy)
            }
        }
    }
}

struct MultipleESCBox: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GroupBox {
            HStack(spacing: 4) {
                Text(model.active.count > 1 ? "Multiple ESC" : (model.masterIndex.map { "Single ESC #\($0 + 1)" } ?? "ESC"))
                    .font(.callout)
                    .frame(width: 92, alignment: .leading)
                ForEach(model.slots) { slot in
                    ESCSlotButton(slot: slot)
                }
                Button("Check") { model.check() }
                    .disabled(model.busy)
                    .padding(.leading, 4)
                if model.active.count == 1 && model.workspace != nil {
                    Button("Copy") { model.copySettings() }
                        .help("Copy the current settings into the clipboard")
                    if model.clipboard != nil && model.clipboard != model.workspace {
                        Button("Paste") { model.pasteSettings() }
                    }
                }
            }
        }
    }
}

struct ESCSlotButton: View {
    @EnvironmentObject var model: AppModel
    let slot: ESCSlot

    var color: Color {
        let isActive = model.active.contains(slot.index)
        switch slot.state {
        case .notFound: return .gray.opacity(0.25)
        case .unchecked: return isActive ? .gray : .gray.opacity(0.3)
        case .ok:
            if !isActive { return .gray.opacity(0.35) }
            if slot.index == model.masterIndex { return .green }
            if model.inSync(slot) { return model.directionDiffers(slot) ? .orange : .green.opacity(0.75) }
            return .gray
        case .layoutDiffers: return isActive ? .purple : .purple.opacity(0.35)
        case .failedFlash, .unknownFirmware, .wrongBrand, .modeDiffers, .unsupported:
            return isActive ? .red : .red.opacity(0.4)
        }
    }

    var body: some View {
        Button {
            if NSEvent.modifierFlags.contains(.option) { model.selectSingle(slot.index) } else { model.toggleActive(slot.index) }
        } label: {
            ZStack(alignment: .topTrailing) {
                Text(slot.title)
                    .font(.system(size: 13, weight: slot.index == model.masterIndex ? .heavy : .semibold, design: .rounded))
                    .frame(width: 28, height: 24)
                    .background(RoundedRectangle(cornerRadius: 5).fill(color))
                    .foregroundStyle(.white)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(model.active.contains(slot.index) ? Color.primary.opacity(0.6) : .clear, lineWidth: 1))
                if let b = slot.state.badge {
                    Text(b).font(.system(size: 9, weight: .bold))
                        .padding(2)
                        .background(Circle().fill(Color.yellow))
                        .foregroundStyle(.black)
                        .offset(x: 5, y: -5)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.busy || slot.state == .notFound)
        .help(helpText)
        .contextMenu {
            Button("Select only ESC #\(slot.index + 1)") { model.selectSingle(slot.index) }
            Button(model.active.contains(slot.index) ? "Deactivate" : "Activate") { model.toggleActive(slot.index) }
        }
    }

    var helpText: String {
        var s = "ESC #\(slot.index + 1)"
        if let d = slot.device { s += "\n\(d.description)" }
        if let st = slot.settings, (try? st.validate()) != nil { s += "\n\(st.summary(database: model.database))" }
        switch slot.state {
        case .unknownFirmware: s += "\nu: unknown firmware or erased ESC"
        case .failedFlash: s += "\nf: a former flash attempt failed"
        case .wrongBrand: s += "\nb: wrong firmware brand for the selected interface"
        case .modeDiffers: s += "\nm: ESC mode differs from the master"
        case .layoutDiffers: s += "\nEEprom layout differs from the master"
        case .notFound: s += "\nnot found"
        default: break
        }
        s += "\n\nClick: (de)activate · ⌥-click / right click: single ESC"
        return s
    }
}

struct ActionButtons: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.readSetup()
            } label: { Label("Read Setup", systemImage: "arrow.down.doc") }
            .disabled(model.busy || !model.interfaceType.usesSerialPort && !model.connected)
            Button {
                model.writeSetup()
            } label: { Label("Write Setup", systemImage: "arrow.up.doc") }
            .disabled(model.busy || !model.connected || model.workspace == nil)
            Button {
                model.flashBLHeli()
            } label: { Label("Flash BLHeli", systemImage: "bolt.fill") }
            .disabled(model.busy)
            Button {
                model.flashOther()
            } label: { Label("Flash Other", systemImage: "doc.badge.gearshape") }
            .disabled(model.busy)
        }
        .controlSize(.large)
    }
}
