import SwiftUI
import BLHeliCore

/// "ESC overview" tab (TfraESCTable): all checked ESCs side by side.
struct ESCOverviewView: View {
    @EnvironmentObject var model: AppModel

    static let columns: [BLHeliParam] = [
        .direction, .commutationTiming, .startupPower, .demagCompensation, .ppmMinThrottle, .ppmCenterThrottle,
        .ppmMaxThrottle, .beepStrength, .beaconStrength, .beaconDelay, .temperatureProtection, .lowRpmPowerProtection,
        .brakeOnStop, .pwmFrequency, .lowVoltageLimit, .govMode, .motorGain,
    ]

    var body: some View {
        if model.slots.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "tablecells").font(.system(size: 44)).foregroundStyle(.secondary)
                Text("Connect and run \"Check\" to see all ESCs.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        header("ESC")
                        header("State")
                        header("MCU")
                        header("Layout")
                        header("Firmware")
                        header("Mode")
                        header("Name")
                        ForEach(visibleColumns, id: \.self) { p in header(p.plainName) }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(model.slots) { slot in
                        GridRow {
                            Text("#\(slot.index + 1)").font(.body.weight(.bold))
                                .foregroundStyle(model.active.contains(slot.index) ? Color.primary : Color.secondary)
                            Text(stateText(slot)).foregroundStyle(stateColor(slot))
                            Text(slot.device?.mcu?.name ?? "–")
                            if let s = slot.settings, (try? s.validate()) != nil {
                                let ctx = s.context(database: model.database)
                                Text(ctx.layout?.displayName ?? s.layoutName)
                                Text("\(s.isBLHeliS ? "BLHeli_S" : "BLHeli") \(s.revisionString)")
                                Text(s.mode.displayName)
                                Text(s.name.isEmpty ? "–" : s.name)
                                ForEach(visibleColumns, id: \.self) { p in
                                    if BLHeliParamLogic.exists(p, ctx) {
                                        Text(BLHeliParamLogic.label(p, value: s.value(p), ctx))
                                            .foregroundStyle(differsFromMaster(slot, p) ? Color.orange : Color.primary)
                                    } else {
                                        Text("–").foregroundStyle(.secondary)
                                    }
                                }
                            } else {
                                Text("–"); Text("–"); Text("–"); Text("–")
                                ForEach(visibleColumns, id: \.self) { _ in Text("") }
                            }
                        }
                        .font(.callout)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    var visibleColumns: [BLHeliParam] {
        Self.columns.filter { p in
            model.slots.contains { slot in
                guard let s = slot.settings, (try? s.validate()) != nil else { return false }
                return BLHeliParamLogic.exists(p, s.context(database: model.database))
            }
        }
    }

    func header(_ s: String) -> some View {
        Text(s).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }

    func differsFromMaster(_ slot: ESCSlot, _ p: BLHeliParam) -> Bool {
        guard let m = model.masterIndex, m < model.slots.count, m != slot.index,
              let ms = model.slots[m].settings, let s = slot.settings else { return false }
        return ms[p] != s[p]
    }

    func stateText(_ slot: ESCSlot) -> String {
        switch slot.state {
        case .unchecked: return "unchecked"
        case .notFound: return "not found"
        case .ok: return slot.index == model.masterIndex ? "Master" : (model.inSync(slot) ? "in sync" : "differs")
        case .unknownFirmware: return "no BLHeli"
        case .failedFlash: return "flash failed"
        case .wrongBrand: return "wrong brand"
        case .modeDiffers: return "mode differs"
        case .layoutDiffers: return "EEprom layout differs"
        case .unsupported: return "unsupported"
        }
    }

    func stateColor(_ slot: ESCSlot) -> Color {
        switch slot.state {
        case .ok: return .green
        case .notFound, .unchecked: return .secondary
        case .layoutDiffers: return .purple
        default: return .red
        }
    }
}
