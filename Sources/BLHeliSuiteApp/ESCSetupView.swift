import SwiftUI
import BLHeliCore

struct ESCSetupView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let ws = model.workspace, let ctx = model.workspaceContext {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ESCInfoHeader(settings: ws, ctx: ctx)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 255, maximum: 380), spacing: 10, alignment: .top)],
                              alignment: .leading, spacing: 10) {
                        ForEach(visibleParams(ctx), id: \.self) { p in
                            ParameterCard(param: p, ctx: ctx)
                        }
                    }
                    HStack {
                        Button {
                            model.undoAll()
                        } label: { Label("Undo all changes", systemImage: "arrow.uturn.backward") }
                        .disabled(!model.workspaceModified)
                        Button {
                            model.allDefaults()
                        } label: { Label("Set all to defaults", systemImage: "star") }
                        Spacer()
                        Text("Changes are stored in the ESC only after \"Write Setup\".")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
                .padding(12)
            }
        } else {
            EmptySetupView()
        }
    }

    func visibleParams(_ ctx: ParamContext) -> [BLHeliParam] {
        BLHeliParam.editable.filter { BLHeliParamLogic.exists($0, ctx) }
    }
}

struct EmptySetupView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "cpu")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            if let err = model.databaseError {
                Text(err).foregroundStyle(.red)
            }
            if !model.connected {
                Text("No ESC connected").font(.title2)
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Select the interface at the top (\(model.interfaceType.title)).")
                    if model.interfaceType.isFlightController {
                        Text("2. Connect the flight controller by USB and power the ESCs (battery!).")
                    } else if model.interfaceType.usesSerialPort {
                        Text("2. Connect the 4-way interface (Arduino) and power the ESC.")
                    } else {
                        Text("2. Plug in the programmer and connect the ESC.")
                    }
                    Text("3. Select the serial port and click Connect or Read Setup.")
                }
                .foregroundStyle(.secondary)
            } else if let m = model.masterIndex, m < model.slots.count {
                let slot = model.slots[m]
                Text("ESC #\(m + 1)").font(.title2)
                if let d = slot.device { Text(d.description).foregroundStyle(.secondary) }
                switch slot.state {
                case .unknownFirmware:
                    Text("This ESC does not contain a valid BLHeli setup (erased, SimonK or other firmware).\nUse \"Flash BLHeli\" to install BLHeli.")
                        .multilineTextAlignment(.center)
                case .failedFlash:
                    Text("A former flash attempt failed on this ESC.\nPlease flash it again with \"Flash BLHeli\".")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.red)
                case .wrongBrand:
                    Text("The ESC firmware brand does not match the selected interface (SiLabs ↔ Atmel).\nSelect the matching interface in the menu at the top.")
                        .multilineTextAlignment(.center)
                case .unsupported:
                    Text("This ESC uses an ARM MCU (BLHeli_32 / AM32) – it is not supported by BLHeliSuite.")
                default:
                    Text("Click \"Read Setup\" to read the ESC settings.")
                }
            } else {
                Text("No ESC selected").font(.title2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct ESCInfoHeader: View {
    @EnvironmentObject var model: AppModel
    let settings: BLHeliSettings
    let ctx: ParamContext

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ctx.layout?.displayName ?? settings.layoutName)
                        .font(.title2.weight(.semibold))
                    Text("\(settings.isBLHeliS ? "BLHeli_S" : "BLHeli") Rev. \(settings.revisionString)  ·  \(settings.mode.displayName)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                    GridRow {
                        Text("ESC layout:").foregroundStyle(.secondary)
                        Text(settings.rawLayoutString).font(.system(.body, design: .monospaced))
                    }
                    GridRow {
                        Text("MCU:").foregroundStyle(.secondary)
                        Text(settings.mcuString).font(.system(.body, design: .monospaced))
                    }
                    GridRow {
                        Text("Device:").foregroundStyle(.secondary)
                        Text(model.workspaceDevice?.description ?? "–")
                    }
                    GridRow {
                        Text("EEprom layout:").foregroundStyle(.secondary)
                        Text("Rev. \(settings.layoutRevision)")
                    }
                }
                .font(.callout)
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("ESC name").font(.caption).foregroundStyle(.secondary)
                    TextField("Name", text: Binding(
                        get: { model.workspace?.name ?? "" },
                        set: { v in
                            let clipped = String(v.prefix(16))
                            model.workspace?.name = clipped
                        }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .font(.system(.body, design: .monospaced))
                    if let l = ctx.layout, l.cells > 0 {
                        Text("Max. \(l.cells) LiPo cells").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(6)
        }
    }
}

struct ParameterCard: View {
    @EnvironmentObject var model: AppModel
    let param: BLHeliParam
    let ctx: ParamContext

    var value: Int { model.workspace?.value(param) ?? 0 }
    var originalValue: Int? { model.original?.value(param) }
    var changed: Bool { originalValue != nil && originalValue != value }
    var range: ClosedRange<Int> { BLHeliParamLogic.range(param, ctx) }
    var valid: Bool { BLHeliParamLogic.isValid(param, value: value, ctx) }
    var defaultValue: Int? { BLHeliParamLogic.defaultValue(param, ctx) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(param.displayName(ctx))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Button {
                    model.undo(param)
                } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.borderless)
                .disabled(!changed)
                .help("Undo")
                Button {
                    model.setDefault(param)
                } label: { Image(systemName: defaultValue == value ? "star.fill" : "star") }
                .buttonStyle(.borderless)
                .disabled(defaultValue == nil || defaultValue == value)
                .help(defaultValue.map { "Default: " + BLHeliParamLogic.label(param, value: $0, ctx) } ?? "No default")
            }
            Text(valid ? BLHeliParamLogic.label(param, value: value, ctx) : "Invalid value (\(value))")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(valid ? Color.primary : Color.red)
            control
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(changed ? Color.orange : Color.secondary.opacity(0.25), lineWidth: changed ? 2 : 1))
        .help(helpText)
    }

    @ViewBuilder var control: some View {
        if range.lowerBound == range.upperBound {
            Text("Not adjustable on this ESC").font(.caption).foregroundStyle(.secondary)
        } else if param.isNumeric {
            HStack {
                Slider(value: Binding(get: { Double(value) }, set: { model.setValue(param, Int($0.rounded())) }),
                       in: Double(range.lowerBound)...Double(range.upperBound))
                Stepper("", value: Binding(get: { value }, set: { model.setValue(param, $0) }), in: range)
                    .labelsHidden()
            }
        } else {
            Picker("", selection: Binding(get: { value }, set: { model.setValue(param, $0) })) {
                if !valid { Text("Invalid (\(value))").tag(value) }
                ForEach(BLHeliParamLogic.allowedValues(param, ctx), id: \.self) { v in
                    Text(BLHeliParamLogic.label(param, value: v, ctx)).tag(v)
                }
            }
            .labelsHidden()
        }
    }

    var helpText: String {
        var s = "\(param.eepName)\nValue \(value) (range \(range.lowerBound)…\(range.upperBound))"
        if let d = defaultValue { s += "\nDefault: \(BLHeliParamLogic.label(param, value: d, ctx))" }
        if let o = originalValue, changed { s += "\nRead from ESC: \(BLHeliParamLogic.label(param, value: o, ctx))" }
        return s
    }
}
