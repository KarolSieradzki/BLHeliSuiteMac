import SwiftUI
import BLHeliCore

/// "SiLabs / Atmel ESC Setup" page (TfraESCCombos). Every parameter is a 185×56 group box at the
/// position of the original form; parameters that exclude each other share a position.
struct ClassicSetupPage: View {
    @EnvironmentObject var model: AppModel

    struct Slot {
        let param: BLHeliParam
        let x: CGFloat
        let y: CGFloat
        /// 3-digit raw values use the small LED (34×19, Courier New 19).
        var small = false
    }

    static let slots: [Slot] = [
        Slot(param: .becVoltageHigh, x: 575, y: 10),
        Slot(param: .motorIdle, x: 4, y: 68), Slot(param: .lowVoltageLimit, x: 5, y: 68),
        Slot(param: .startupPower, x: 195, y: 68), Slot(param: .direction, x: 385, y: 68),
        Slot(param: .inputPolarity, x: 575, y: 68),
        Slot(param: .motorGain, x: 4, y: 126), Slot(param: .govMode, x: 4, y: 126),
        Slot(param: .temperatureProtection, x: 195, y: 126), Slot(param: .startupRpm, x: 197, y: 126),
        Slot(param: .voltageCompensation, x: 385, y: 126), Slot(param: .demagCompensation, x: 385, y: 126),
        Slot(param: .beepStrength, x: 575, y: 126, small: true),
        Slot(param: .govPGain, x: 4, y: 184),
        Slot(param: .startupAccel, x: 195, y: 184), Slot(param: .spoolupTime, x: 195, y: 184),
        Slot(param: .pwmDither, x: 195, y: 184),
        Slot(param: .pwmFrequency, x: 385, y: 184), Slot(param: .beaconStrength, x: 575, y: 184, small: true),
        Slot(param: .govIGain, x: 4, y: 242),
        Slot(param: .startupMethod, x: 195, y: 242), Slot(param: .lowRpmPowerProtection, x: 195, y: 242),
        Slot(param: .dampingForce, x: 385, y: 242), Slot(param: .pwmInput, x: 385, y: 242),
        Slot(param: .beaconDelay, x: 575, y: 242),
        Slot(param: .govRange, x: 4, y: 300),
        Slot(param: .throttleRate, x: 195, y: 300), Slot(param: .brakeOnStop, x: 195, y: 300),
        Slot(param: .commutationTiming, x: 385, y: 300), Slot(param: .ppmMinThrottle, x: 575, y: 300, small: true),
        Slot(param: .govSetupTarget, x: 4, y: 358, small: true),
        Slot(param: .ppmCenterThrottle, x: 385, y: 358, small: true), Slot(param: .ppmMaxThrottle, x: 575, y: 358, small: true),
    ]

    static let columns: [CGFloat] = [4, 195, 385, 575]
    static let rows: [CGFloat] = [68, 126, 184, 242, 300, 358]

    /// Visible parameter boxes; if two existing parameters claim the same place the second one
    /// moves to the next free cell, so nothing is ever hidden or overlapping.
    static func placed(_ ctx: ParamContext) -> [Slot] {
        var used = Set<String>()
        func key(_ x: CGFloat, _ y: CGFloat) -> String { "\(Int(x / 100))-\(Int(y))" }
        var out: [Slot] = []
        var pending: [Slot] = []
        let showLED = BLHeliParamLogic.exists(.ledControl, ctx) && (ctx.layout?.leds ?? 0) > 0
        for s in slots where BLHeliParamLogic.exists(s.param, ctx) {
            if s.param == .becVoltageHigh && showLED { pending.append(s); continue }
            if used.insert(key(s.x, s.y)).inserted { out.append(s) } else { pending.append(s) }
        }
        if showLED { used.insert(key(575, 10)) }
        for s in pending {
            for y in rows {
                if let x = columns.first(where: { !used.contains(key($0, y)) }) {
                    used.insert(key(x, y))
                    out.append(Slot(param: s.param, x: x, y: y, small: s.small))
                    break
                }
            }
        }
        return out
    }

    var body: some View {
        let ctx = model.workspaceContext
        Abs(width: 770, height: 438) {
            ClassicNameBox().at(4, 10, 185, 56)
            ClassicDescriptionBox().at(195, 10, 185, 56)
            if let ctx {
                if BLHeliParamLogic.exists(.enableTxProgramming, ctx) || BLHeliParamLogic.exists(.rearmAtStart, ctx) {
                    ClassicMiscBox(ctx: ctx).at(385, 10, 185, 56)
                }
                if BLHeliParamLogic.exists(.ledControl, ctx) && (ctx.layout?.leds ?? 0) > 0 {
                    ClassicLEDBox(ctx: ctx).at(575, 10, 185, 56)
                } else if !BLHeliParamLogic.exists(.becVoltageHigh, ctx) {
                    brand.at(575, 10, 185, 56)
                }
                ForEach(Self.placed(ctx), id: \.param) { s in
                    ClassicParamBox(param: s.param, ctx: ctx, small: s.small).at(s.x, s.y, 185, 56)
                }
            } else {
                brand.at(575, 10, 185, 56)
                ClassicSetupHint().at(195, 110, 380, 200)
            }
        }
        .disabled(model.busy)
    }

    var brand: some View {
        let silabs = model.family == .silabs
        return Abs(width: 185, height: 56) {
            Text(silabs ? "SiLabs" : "Atmel")
                .font(Win.tahoma(32, bold: true))
                .foregroundColor(silabs ? Win.maroon : Win.atmelBlue)
                .frame(width: 145, height: 39)
                .at(19, 6, 145, 39)
            Text("©")
                .font(Win.tahoma(13, bold: true))
                .foregroundColor(silabs ? Win.maroon : Win.atmelBlue)
                .at(160, 6, 14, 16)
        }
    }
}

/// Parameter group box: value label, LED with the raw value, scroll bar, Undo and Default.
struct ClassicParamBox: View {
    @EnvironmentObject var model: AppModel
    let param: BLHeliParam
    let ctx: ParamContext
    var small = false

    var value: Int { model.workspace?.value(param) ?? 0 }
    var originalValue: Int? { model.original?.value(param) }
    var range: ClosedRange<Int> { BLHeliParamLogic.range(param, ctx) }
    var adjustable: Bool { range.lowerBound != range.upperBound }
    var valid: Bool { BLHeliParamLogic.isValid(param, value: value, ctx) }
    var defaultValue: Int? { BLHeliParamLogic.defaultValue(param, ctx) }
    var allowed: [Int] { BLHeliParamLogic.allowedValues(param, ctx) }

    var scrollRange: ClosedRange<Int> { param.isNumeric ? range : 0...max(0, allowed.count - 1) }
    var scrollValue: Int { param.isNumeric ? value : (allowed.firstIndex(of: value) ?? 0) }

    var body: some View {
        WinGroupBox(title: param.displayName(ctx), width: 185, height: 56) {
            Text(valid ? BLHeliParamLogic.label(param, value: value, ctx) : "Invalid (\(value))")
                .font(Win.tahoma(12, bold: true))
                .foregroundColor(!adjustable ? Win.grayText : valid ? Win.text : Win.red)
                .lineLimit(1)
                .frame(width: 115, height: 15)
                .background(RoundedRectangle(cornerRadius: 4).fill(adjustable ? Win.valueFill : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(adjustable ? Win.grayText : Color.clear, lineWidth: 1))
                .at(39, 16, 115, 15)
            ClassicLED(value: value, small: small, active: adjustable)
                .at(3, small ? 31 : 21, 34, small ? 19 : 29)
            WinFlatGlyphButton(glyph: "undo") { model.undo(param) }
                .disabled(originalValue == nil || originalValue == value)
                .help(originalValue.map { "Undo – value read from the ESC: " + BLHeliParamLogic.label(param, value: $0, ctx) } ?? "Undo")
                .at(160, 8, 23, 22)
            WinFlatGlyphButton(glyph: "default") { model.setDefault(param) }
                .disabled(defaultValue == nil || defaultValue == value)
                .help(defaultValue.map { "Default: " + BLHeliParamLogic.label(param, value: $0, ctx) } ?? "No default value")
                .at(160, 32, 23, 22)
            WinHScrollBar(value: scrollValue, range: scrollRange) { pos in
                if param.isNumeric { model.setValue(param, pos) } else if pos < allowed.count { model.setValue(param, allowed[pos]) }
            }
            .disabled(!adjustable)
            .at(40, 34, 115, 15)
        }
        .help("\(param.displayName(ctx))  (\(param.eepName))\nValue \(value)  –  range \(range.lowerBound)…\(range.upperBound)")
    }
}

/// Raw value display (TJvLabel "led_…": Courier New, lime on gray, rounded).
struct ClassicLED: View {
    let value: Int
    var small = false
    var active = true

    var body: some View {
        Text(verbatim: String(value))
            .font(Win.courierNew(small ? 19 : 28))
            .foregroundColor(active ? Win.lime : Win.rgb(0xA8A8A8))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.trailing, 1)
            .frame(width: 34, height: small ? 19 : 29, alignment: .trailing)
            .background(RoundedRectangle(cornerRadius: 3).fill(active ? Win.ledFill : Win.rgb(0xE6E6E6)))
    }
}

struct ClassicNameBox: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let n = (model.masterIndex ?? 0) + 1
        let name = model.workspace?.name ?? ""
        let orig = model.original?.name
        WinGroupBox(title: "ESC# \(n) - Name", width: 185, height: 56) {
            WinEdit(text: Binding(get: { model.workspace?.name ?? "" }, set: { model.workspace?.name = $0 }),
                    font: Win.courier(15), color: Win.blue, maxLength: 16)
                .disabled(model.workspace == nil)
                .at(4, 32, 152, 21)
            WinFlatGlyphButton(glyph: "undo") { if let o = orig { model.workspace?.name = o } }
                .disabled(orig == nil || orig == name)
                .help("Undo")
                .at(160, 8, 23, 22)
            WinFlatGlyphButton(glyph: "default") { model.workspace?.name = "" }
                .disabled(model.workspace == nil || name.isEmpty)
                .help("Default: empty")
                .at(160, 32, 23, 22)
        }
        .help("ESC# \(n) - Name:\nName of the individual ESC.\nMay help to avoid confusion.")
    }
}

struct ClassicDescriptionBox: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let ws = model.workspace
        let ctx = model.workspaceContext
        let title = ws.map { ctx?.layout?.displayName ?? $0.layoutName } ?? "unknown ESC"
        let mode: String = {
            switch ws?.mode {
            case .main?: return "MAIN"
            case .tail?: return "TAIL"
            case .multi?: return "Multicopter"
            default: return "???"
            }
        }()
        WinGroupBox(title: title, width: 185, height: 56, titleColor: ws == nil ? Win.grayText : Win.text) {
            Text("for").font(Win.tahoma(15)).at(8, 15, 24, 18)
            Text(mode).font(Win.tahoma(15, bold: true)).foregroundColor(ws == nil ? Win.grayText : Win.text).at(34, 15, 100, 18)
            Text("Motors").font(Win.tahoma(15)).at(136, 15, 49, 18)
            Text(ws?.isBLHeliS == true ? "BLHeli_S Revision:" : "BLHeli Revision:").font(Win.tahoma(15)).at(8, 33, 128, 18)
            Text(ws?.revisionString ?? "xx.x")
                .font(Win.tahoma(15, bold: true))
                .foregroundColor(ws == nil ? Win.grayText : Win.blue)
                .at(136, 33, 48, 18)
        }
        .help(ws.map { "\($0.summary(database: model.database))\nESC layout: \($0.rawLayoutString)\nMCU: \($0.mcuString)\nEEprom layout rev. \($0.layoutRevision)" } ?? "Setup data still invalid.\nPlease Read a valid ESC Setup")
    }
}

struct ClassicMiscBox: View {
    @EnvironmentObject var model: AppModel
    let ctx: ParamContext

    func binding(_ p: BLHeliParam) -> Binding<Bool> {
        Binding(get: { (model.workspace?.value(p) ?? 0) != 0 }, set: { model.setValue(p, $0 ? 1 : 0) })
    }

    var changed: Bool {
        [BLHeliParam.rearmAtStart, .enableTxProgramming].contains { model.workspace?.value($0) != model.original?.value($0) }
    }

    var atDefaults: Bool {
        [BLHeliParam.rearmAtStart, .enableTxProgramming].allSatisfy { p in
            guard BLHeliParamLogic.exists(p, ctx), let d = BLHeliParamLogic.defaultValue(p, ctx) else { return true }
            return model.workspace?.value(p) == d
        }
    }

    var body: some View {
        WinGroupBox(title: "Misc", width: 185, height: 56) {
            if BLHeliParamLogic.exists(.rearmAtStart, ctx) {
                WinCheckBox(title: "Rearming every Start", isOn: binding(.rearmAtStart), font: Win.tahoma(12, bold: true))
                    .at(3, 13, 152, 17)
            }
            if BLHeliParamLogic.exists(.enableTxProgramming, ctx) {
                WinCheckBox(title: "Programming by TX", isOn: binding(.enableTxProgramming), font: Win.tahoma(12, bold: true))
                    .help("Programming by TX is ignored when Motor Direction is set to Bidirectional.")
                    .at(3, 32, 141, 17)
            }
            WinFlatGlyphButton(glyph: "undo") {
                model.undo(.rearmAtStart)
                model.undo(.enableTxProgramming)
            }
            .disabled(!changed)
            .at(160, 8, 23, 22)
            WinFlatGlyphButton(glyph: "default") {
                model.setDefault(.rearmAtStart)
                model.setDefault(.enableTxProgramming)
            }
            .disabled(model.workspace == nil || atDefaults)
            .at(160, 32, 23, 22)
        }
    }
}

/// BLHeli_S LED control: one switchable LED per layout LED.
struct ClassicLEDBox: View {
    @EnvironmentObject var model: AppModel
    let ctx: ParamContext
    static let colors: [Color] = [Win.rgb(0x0791F8), Win.rgb(0x1FE05E), Win.rgb(0xD12E2E), Win.rgb(0xFFFF00)]

    var value: Int { model.workspace?.value(.ledControl) ?? 0 }

    var body: some View {
        let leds = min(4, Int(ctx.layout?.leds ?? 0))
        let orig = model.original?.value(.ledControl)
        let def = BLHeliParamLogic.defaultValue(.ledControl, ctx)
        WinGroupBox(title: BLHeliParam.ledControl.displayName(ctx), width: 185, height: 56) {
            ForEach(0..<leds, id: \.self) { k in
                let on = (value >> (2 * k)) & 3 == 3
                Text(on ? "ON" : "OFF").font(Win.tahoma(11)).frame(width: 24, height: 16).at(44 + 28 * CGFloat(k), 16, 24, 16)
                WinLed(on: on, colorOn: Self.colors[k], colorOff: Win.grayText)
                    .contentShape(Rectangle())
                    .onTapGesture { model.setValue(.ledControl, on ? value & ~(3 << (2 * k)) : value | (3 << (2 * k))) }
                    .help("LED \(k + 1) – click to switch")
                    .at(43 + 28 * CGFloat(k), 35, 24, 12)
            }
            ClassicLED(value: value, small: true).at(3, 32, 34, 19)
            WinFlatGlyphButton(glyph: "undo") { model.undo(.ledControl) }
                .disabled(orig == nil || orig == value)
                .at(160, 8, 23, 22)
            WinFlatGlyphButton(glyph: "default") { model.setDefault(.ledControl) }
                .disabled(def == nil || def == value)
                .at(160, 32, 23, 22)
        }
    }
}

/// Shown in the setup page while no valid ESC setup is loaded.
struct ClassicSetupHint: View {
    @EnvironmentObject var model: AppModel

    var text: String {
        if let e = model.databaseError { return e }
        if !model.connected {
            let step2: String
            switch model.interfaceType {
            case .atmelISP:
                step2 = "2. Connect the ISP programmer (USBasp, Arduino as ISP…) to the ESC"
                    + (AVRDude(path: model.avrdudePath) == nil ? " and install avrdude (brew install avrdude)." : ".")
            case .silabsC2Toolstick:
                step2 = "2. Plug in the SiLabs ToolStick / USB Debug Adapter and connect it to the ESC (C2)."
            default:
                step2 = "2. Select the port below."
            }
            return "Interface/Device not connected.\n\n1. Select the interface in the menu \"Select ATMEL / SILABS Interface\".\n\(step2)\n3. Power up the ESC (connect a battery) and click \"Connect\" or \"Read Setup\"."
        }
        guard let m = model.masterIndex, m < model.slots.count else { return "No ESC selected." }
        switch model.slots[m].state {
        case .unknownFirmware: return "ESC#\(m + 1) seems to be erased or flashed with SimonK or other firmware.\n\nUse \"Flash BLHeli\" to flash it with BLHeli firmware."
        case .failedFlash: return "ESC#\(m + 1): Obviously an attempt to flash this ESC has failed.\n\nUse \"Flash BLHeli\" to flash it again."
        case .wrongBrand: return "ESC#\(m + 1): the firmware brand does not match the selected interface.\n\nSelect the matching ATMEL / SILABS interface."
        case .unsupported: return "ESC#\(m + 1) uses an ARM MCU (BLHeli_32 / AM32) – not supported by BLHeliSuite."
        case .notFound: return "ESC#\(m + 1) not found."
        default: return "Click \"Read Setup\" to read the ESC setup."
        }
    }

    var body: some View {
        Text(text)
            .font(Win.tahoma(13))
            .foregroundColor(model.databaseError != nil ? Win.red : Win.grayText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
