import SwiftUI
import AppKit
import BLHeliCore

// MARK: - ESC overview (TfraESCTable: string grid on clInfoBk)

struct ClassicOverviewPage: View {
    @EnvironmentObject var model: AppModel

    struct Row {
        let title: String
        let cell: (ESCSlot) -> (String, Color)
    }

    var contexts: [ParamContext] {
        model.slots.compactMap { s -> ParamContext? in
            guard let st = s.settings, (try? st.validate()) != nil else { return nil }
            return st.context(database: model.database)
        }
    }

    var params: [BLHeliParam] {
        let ctxs = contexts
        return BLHeliParam.editable.filter { p in ctxs.contains { BLHeliParamLogic.exists(p, $0) } }
    }

    func valid(_ s: ESCSlot) -> BLHeliSettings? {
        guard let st = s.settings, (try? st.validate()) != nil else { return nil }
        return st
    }

    var rows: [Row] {
        var r: [Row] = [
            Row(title: "State") { s in
                switch s.state {
                case .ok:
                    if s.index == model.masterIndex { return ("Master", Win.blue) }
                    if !model.active.contains(s.index) { return ("not active", Win.grayText) }
                    return model.inSync(s) ? ("Slave / in sync", Win.green) : ("Slave / differs", Win.grayText)
                case .notFound: return ("---", Win.grayText)
                case .unchecked: return ("unchecked", Win.grayText)
                case .unknownFirmware: return ("erased / unknown", Win.red)
                case .failedFlash: return ("FLASH FAILED", Win.red)
                case .wrongBrand: return ("wrong brand", Win.red)
                case .modeDiffers: return ("mode differs", Win.red)
                case .layoutDiffers: return ("EEprom layout differs", Win.purple)
                case .unsupported: return ("not supported", Win.red)
                }
            },
            Row(title: "Name") { s in (valid(s).map { $0.name.isEmpty ? "-" : $0.name } ?? "", Win.blue) },
            Row(title: "ESC") { s in
                guard let st = valid(s) else { return ("", Win.text) }
                return (st.context(database: model.database).layout?.displayName ?? st.layoutName, Win.text)
            },
            Row(title: "MCU") { s in (s.device?.mcu?.name ?? "", Win.text) },
            Row(title: "Firmware") { s in (valid(s).map { "\($0.isBLHeliS ? "BLHeli_S" : "BLHeli") \($0.revisionString)" } ?? "", Win.text) },
            Row(title: "Mode") { s in (valid(s)?.mode.displayName ?? "", Win.text) },
        ]
        let ctxs = contexts
        for p in params {
            let title = ctxs.first { BLHeliParamLogic.exists(p, $0) }.map { p.displayName($0) } ?? p.eepName
            r.append(Row(title: title) { s in
                guard let st = valid(s) else { return ("", Win.text) }
                let ctx = st.context(database: model.database)
                guard BLHeliParamLogic.exists(p, ctx) else { return ("-", Win.grayText) }
                var color = Win.text
                if let m = model.masterIndex, m < model.slots.count, m != s.index, let ms = valid(model.slots[m]), ms[p] != st[p] {
                    color = Win.red
                }
                return (BLHeliParamLogic.label(p, value: st.value(p), ctx), color)
            })
        }
        return r
    }

    var body: some View {
        if model.slots.isEmpty {
            Text("No ESC data.\n\nConnect the interface and click \"Check\".")
                .font(Win.tahoma(13))
                .foregroundColor(Win.grayText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Win.infoBk)
        } else {
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        cell("", header: true, width: 170)
                        ForEach(model.slots) { s in cell("ESC#\(s.index + 1)", header: true, width: 118) }
                    }
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 0) {
                            cell(row.title, header: true, width: 170, alignment: .leading)
                            ForEach(model.slots) { s in
                                let c = row.cell(s)
                                cell(c.0, color: c.1, width: 118)
                            }
                        }
                    }
                }
                .frame(minWidth: 770, minHeight: 438, alignment: .topLeading)
            }
            .background(Win.infoBk)
        }
    }

    func cell(_ text: String, header: Bool = false, color: Color = Win.text, width: CGFloat, alignment: Alignment = .center) -> some View {
        Text(text)
            .font(Win.tahoma(11, bold: header))
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 3)
            .frame(width: width, height: 18, alignment: alignment)
            .background(header ? Win.face : Win.infoBk)
            .overlay(GridLines())
    }

    struct GridLines: View {
        var body: some View {
            GeometryReader { g in
                Path { p in
                    p.move(to: CGPoint(x: g.size.width - 0.5, y: 0))
                    p.addLine(to: CGPoint(x: g.size.width - 0.5, y: g.size.height - 0.5))
                    p.addLine(to: CGPoint(x: 0, y: g.size.height - 0.5))
                }
                .stroke(Win.rgb(0xA0A0A0), lineWidth: 1)
            }
        }
    }
}

// MARK: - Motors (TfraCFMotorTest)

struct ClassicMotorsPage: View {
    @EnvironmentObject var model: AppModel
    @State private var enabled = false

    var body: some View {
        let n = min(8, model.motorCountFC)
        Abs(width: 770, height: 438) {
            LinearGradient(colors: [Win.rgb(0xC9C9C9), Win.grayText], startPoint: .top, endPoint: .bottom).at(0, 0, 770, 35)
            Text("Test Motors").font(Win.tahoma(19)).frame(width: 770, height: 35).at(0, 0, 770, 35)
            LinearGradient(colors: [Win.rgb(0x79B6FF), Win.rgb(0x2D8AFF)], startPoint: .leading, endPoint: .trailing).at(0, 35, 770, 303)
            if model.motorSessionOpen {
                ForEach(0..<n, id: \.self) { i in
                    ClassicMotorControl(title: "\(i + 1)", value: model.motorValues[i], minValue: model.motorMinCommand) { v in
                        model.motorValues[i] = v
                    }
                    .disabled(!enabled)
                    .at(14 + 70 * CGFloat(i), 45, 64, 284)
                }
                ClassicMotorControl(title: "All", value: model.motorValues.prefix(n).max() ?? model.motorMinCommand,
                                    minValue: model.motorMinCommand) { v in
                    for i in 0..<n { model.motorValues[i] = v }
                }
                .disabled(!enabled)
                .at(14 + 70 * CGFloat(n) + 30, 45, 64, 284)
            } else {
                Text("The motor test uses the flight controller (MSP).\nAn open 4-way session is closed automatically.\n\nClick \"Connect FC\" below.")
                    .font(Win.tahoma(13))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(width: 770, height: 303)
                    .at(0, 35, 770, 303)
            }
            LinearGradient(colors: [Win.rgb(0xC9C9C9), Win.grayText], startPoint: .top, endPoint: .bottom).at(0, 338, 770, 75)
            Rectangle().fill(Color.white).at(0, 413, 770, 25)
            WinButton(title: "Calibrate ESCs") {}.disabled(true).at(20, 348, 101, 25)
            WinButton(title: model.motorSessionOpen ? "Disconnect FC" : "Connect FC") {
                if model.motorSessionOpen { enabled = false; model.motorClose() } else { model.motorOpen() }
            }
            .disabled(model.busy || (!model.motorSessionOpen && model.portPath.isEmpty))
            .at(20, 381, 101, 25)
            Text("Motor Test Mode Notice:").font(Win.tahoma(11, bold: true)).at(188, 342, 160, 13)
            HStack(spacing: 3) {
                Text("Moving the sliders will cause the motors to")
                Text("spin up.").font(Win.tahoma(11, bold: true))
            }
            .at(188, 358, 400, 13)
            HStack(spacing: 3) {
                Text("In order to prevent injury")
                Text("remove ALL propellers").font(Win.tahoma(11, bold: true)).foregroundColor(Win.red)
                Text("before using this feature.")
            }
            .at(188, 374, 500, 13)
            WinCheckBox(title: "I understand the risks, propellors are removed - Enable motor control.",
                        isOn: Binding(get: { enabled }, set: { on in
                            enabled = on
                            if on { model.motorStart() } else { model.motorStop() }
                        }),
                        font: Win.tahoma(11, bold: true))
                .disabled(!model.motorSessionOpen)
                .at(188, 390, 417, 17)
            Text(model.motorSessionOpen ? model.motorInfo : "no status")
                .font(Win.tahoma(13, bold: true))
                .foregroundColor(model.motorSessionOpen ? Win.green : Win.grayText)
                .lineLimit(1)
                .at(22, 417, 440, 17)
            WinButton(title: "STOP") { enabled = false; model.motorStop() }
                .disabled(!model.motorSessionOpen)
                .at(680, 415, 80, 21)
        }
        .onDisappear { enabled = false; model.motorStop() }
    }
}

/// TfraMotorControl: number, vertical gauge with value, vertical track bar.
struct ClassicMotorControl: View {
    let title: String
    let value: Double
    let minValue: Double
    let onChange: (Double) -> Void

    var body: some View {
        let frac = max(0, min(1, (value - minValue) / max(1, 2000 - minValue)))
        Abs(width: 64, height: 284) {
            Text(title).font(Win.tahoma(21)).foregroundColor(.white).frame(width: 64, height: 26).at(0, 12, 64, 26)
            ZStack(alignment: .bottom) {
                Rectangle().fill(Color.white)
                Rectangle().fill(Win.rgb(0x0A246A)).frame(height: 85 * frac)
            }
            .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 1))
            .at(10, 47, 43, 87)
            Text(verbatim: String(Int(value)))
                .font(Win.tahoma(13, bold: true))
                .foregroundColor(frac > 0.45 ? .white : .black)
                .frame(width: 43, height: 16)
                .at(10, 80, 43, 16)
            WinVTrackBar(value: value, range: minValue...2000, tick: 100) { v in onChange((v / 5).rounded() * 5) }
                .at(7, 150, 50, 131)
        }
    }
}

// MARK: - Make interfaces (TfraMakeInterfaces)

struct ClassicMakeInterfacesPage: View {
    @EnvironmentObject var model: AppModel
    @State private var anchor4way = MenuAnchor()

    var folder: URL? { ArduinoBoard.interfacesFolder() }

    func available(_ kind: ArduinoBoard.InterfaceFirmware) -> Bool {
        guard let f = folder else { return false }
        return model.arduinoBoard.firmwareURL(kind, in: f) != nil
    }

    func make(_ kind: ArduinoBoard.InterfaceFirmware) {
        model.arduinoFirmware = kind
        model.makeInterface()
    }

    func badges(_ letters: [String]) -> some View {
        HStack(spacing: 4) { ForEach(letters, id: \.self) { InterfaceBadge(letter: $0) } }
    }

    var body: some View {
        Abs(width: 770, height: 438) {
            atmegaBoxes.at(5, 3, 187, 390)
            arduinoBoxes.at(198, 3, 231, 390)
            arduinoBoards.at(435, 3, 330, 390)
            Abs(width: 762, height: 36) {
                Rectangle().strokeBorder(Win.groupBorder, lineWidth: 1).at(0, 0, 762, 36)
                Text("Port:").at(8, 11, 26, 13)
                PortCombo().disabled(model.busy || model.connected).at(37, 7, 349, 21)
                if model.connected {
                    Text("(disconnect the ESC interface first)").foregroundColor(Win.grayText).at(394, 11, 300, 13)
                }
            }
            .at(3, 399, 762, 36)
        }
        .disabled(model.busy)
    }

    var unsupportedHelp: String { "Standalone programming boxes are not supported in the Mac version." }

    struct Box {
        let image: String, title: String
        let x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, bx: CGFloat, by: CGFloat
    }

    /// TImage bounds (Proportional) and buttons of grbAtmegaBoxes.
    static let boxes: [Box] = [
        Box(image: "imgRBBX", title: "RBBX Box", x: 17, y: 101, w: 47, h: 40, bx: 79, by: 110),
        Box(image: "imgTAQX", title: "TAQX Box", x: 16, y: 149, w: 49, h: 54, bx: 79, by: 158),
        Box(image: "imgTDLX", title: "TDLX Box", x: 14, y: 199, w: 59, h: 44, bx: 79, by: 209),
        Box(image: "imgTTTBox", title: "TTT Box", x: 17, y: 249, w: 47, h: 40, bx: 81, by: 255),
        Box(image: "imgT160ABox", title: "T160A Box", x: 16, y: 294, w: 52, h: 37, bx: 81, by: 300),
    ]

    var atmegaBoxes: some View {
        WinGroupBox(title: "Make Standalone Atmega Boxes", width: 187, height: 390, font: Win.tahoma(11)) {
            badges(["B", "D", "2", "3"]).at(5, 17, 97, 19)
            WinCheckBox(title: "Initial ISP Flash w. Bootloader", isOn: .constant(false)).disabled(true).at(8, 42, 170, 24)
            Text("Baud").foregroundColor(Win.disabledText).at(10, 76, 26, 13)
            WinCombo(items: [(38400, "38400")], selection: .constant(38400)).disabled(true).at(42, 72, 107, 21)
            ForEach(Self.boxes, id: \.title) { b in
                picture(b.image, maxW: b.w, maxH: b.h).at(b.x, b.y, b.w, b.h)
                WinButton(title: b.title) {}.disabled(true).help(unsupportedHelp).at(b.bx, b.by, 70, 25)
            }
            WinButton(title: "ATMEGA8") {}.disabled(true).help(unsupportedHelp).at(81, 349, 70, 25)
        }
    }

    var arduinoBoxes: some View {
        WinGroupBox(title: "Make Standalone Arduino Boxes", width: 231, height: 390, font: Win.tahoma(11)) {
            badges(["B", "D", "2", "3"]).at(5, 17, 97, 19)
            picture("imgArduinoUnoLCD1602", maxW: 83, maxH: 57).at(5, 53, 83, 57)
            WinButton(title: "Arduino UNO LCD1602") {}.disabled(true).help(unsupportedHelp).at(94, 69, 123, 25)
            picture("imgrduinoUno4884Shield", maxW: 81, maxH: 56).at(5, 131, 81, 56)
            WinButton(title: "Arduino UNO LCD4884") {}.disabled(true).help(unsupportedHelp).at(94, 145, 123, 25)
        }
    }

    var arduinoBoards: some View {
        WinGroupBox(title: "Make Arduino Interface Boards", width: 330, height: 390, font: Win.tahoma(11)) {
            Text("Arduino Board:").at(10, 26, 100, 13)
            WinCombo(items: ArduinoBoard.all.map { ($0, $0.name) }, selection: $model.arduinoBoard).at(10, 45, 268, 21)
            Text("Baud:").at(10, 69, 30, 13)
            WinCombo(items: [(model.arduinoBoard.baud, String(model.arduinoBoard.baud))], selection: .constant(model.arduinoBoard.baud))
                .disabled(true)
                .at(10, 85, 117, 21)
            WinButton(title: "ArduinoISP Programmer") { make(.arduinoISP) }
                .disabled(!available(.arduinoISP))
                .help("Flash \"\(model.arduinoBoard.name)\" board\nwith ArduinoISP sketch.\nUse to flash Atmel ESC initially using 6-Pin ISP connection.")
                .at(10, 118, 178, 25)
            badges(["X"]).at(220, 119, 27, 19)
            WinButton(title: "Arduino BLHeli Bootloader") { make(.blheliBootloader) }
                .disabled(!available(.blheliBootloader))
                .help("Flash \"\(model.arduinoBoard.name)\" board\nwith the BLHeli bootloader 1-wire interface.")
                .at(10, 151, 178, 25)
            badges(["C", "1"]).at(197, 155, 59, 19)
            WinButton(title: "ArduinoUSBLinker (SK Bootloader)") { make(.usbLinker) }
                .disabled(!available(.usbLinker))
                .at(10, 184, 178, 25)
            badges(["4"]).at(222, 186, 29, 19)
            WinButton(title: "Setup ArduinoUSBLinker") {}.disabled(true).help("Not available in the Mac version.").at(10, 216, 178, 25)
            picture("imgArduinoNano", maxW: 70, maxH: 29).at(19, 286, 70, 29)
            picture("imgArduinoUno", maxW: 73, maxH: 52).at(108, 263, 73, 52)
            WinButton(title: "Arduino 4way-interface") { choose4Way() }
                .disabled(!available(.fourWayMulti) && !available(.fourWaySingle) && !available(.fourWayPD3PD2))
                .background(MenuAnchorView(anchor: anchor4way))
                .help("Flash \"\(model.arduinoBoard.name)\" board\nwith the 4way-interface firmware (choose the ESC pins).")
                .at(10, 322, 178, 25)
            badges(["B", "D", "2", "3"]).at(197, 324, 96, 19)
        }
    }

    func choose4Way() {
        let entries: [MenuEntry] = [ArduinoBoard.InterfaceFirmware.fourWayMulti, .fourWaySingle, .fourWayPD3PD2].map { k in
            let file = folder.flatMap { model.arduinoBoard.firmwareURL(k, in: $0)?.lastPathComponent }
            return .item(k.rawValue + (file.map { "   – \($0)" } ?? ""), enabled: file != nil) { make(k) }
        }
        anchor4way.popUp(buildMenu(entries))
    }

    func picture(_ name: String, maxW: CGFloat, maxH: CGFloat) -> some View {
        Group {
            if let img = ClassicImage.named(name) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: maxW, maxHeight: maxH)
            }
        }
    }
}

// MARK: - Expert tools

struct ClassicExpertPage: View {
    @EnvironmentObject var model: AppModel
    @State private var memType = 0
    @State private var readStart = "0x1A00"
    @State private var readLength = "112"
    @State private var writeStart = "0x1A60"
    @State private var writeBytes = "FF"
    @State private var persist = true

    var device: DeviceInfo? {
        guard let m = model.masterIndex, m < model.slots.count else { return nil }
        return model.slots[m].device
    }

    var canEraseChip: Bool { device.map { $0.interfaceMode == .siLabsC2 || $0.isISP } ?? false }

    var stopAddress: String {
        guard let a = AppModel.parseNumber(readStart), let n = AppModel.parseNumber(readLength), n > 0 else { return "?" }
        return String(format: "0x%04X", a + n - 1)
    }

    func applyDefaults() {
        guard let d = device else { return }
        if d.family == .atmel {
            memType = 1; readStart = "0x0000"; writeStart = "0x0060"
        } else {
            memType = 0; readStart = "0x1A00"; writeStart = "0x1A60"
        }
    }

    var body: some View {
        let ready = model.connected && !model.busy
        Abs(width: 770, height: 438) {
            WinGroupBox(title: "Memory access", width: 227, height: 417, font: Win.tahoma(11)) {
                WinGroupBox(title: "Memory type", width: 211, height: 43, font: Win.tahoma(11)) {
                    WinRadio(title: "Flash", selected: memType == 0) { memType = 0 }.at(12, 18, 80, 16)
                    WinRadio(title: "EEProm", selected: memType == 1) { memType = 1 }.at(110, 18, 80, 16)
                }
                .at(8, 14, 211, 43)
                WinGroupBox(title: "Read memory", width: 211, height: 182, font: Win.tahoma(11)) {
                    Text("Start").at(10, 17, 83, 13)
                    WinEdit(text: $readStart).at(10, 33, 99, 21)
                    Text("Length").at(10, 59, 92, 13)
                    WinEdit(text: $readLength).at(10, 74, 99, 21)
                    Text("Stop").at(10, 99, 81, 13)
                    WinEdit(text: .constant(stopAddress)).disabled(true).at(10, 115, 99, 21)
                    WinButton(title: "Read Memory", glyph: "readMem") {
                        model.expertRead(start: readStart, length: readLength, eeprom: memType == 1)
                    }
                    .disabled(!ready)
                    .at(8, 146, 110, 25)
                }
                .at(8, 61, 211, 182)
                WinGroupBox(title: "Write memory", width: 211, height: 162, font: Win.tahoma(11)) {
                    Text("Start").at(8, 18, 84, 13)
                    WinEdit(text: $writeStart).at(8, 32, 101, 21)
                    Text("Hex bytes to write").at(8, 61, 144, 13)
                    WinEdit(text: $writeBytes, font: .custom("ArialMT", size: 11)).at(8, 77, 195, 22)
                    WinCheckBox(title: "Persist flash", isOn: $persist).disabled(true).at(8, 105, 143, 17)
                    WinButton(title: "Write Memory", glyph: "writeMem") {
                        model.expertWrite(start: writeStart, bytes: writeBytes, eeprom: memType == 1)
                    }
                    .disabled(!ready)
                    .at(3, 125, 104, 25)
                    WinButton(title: "Erase Page", glyph: "erase") { model.expertErasePage(writeStart) }
                        .disabled(!ready || memType == 1)
                        .help("Erases the flash page that contains the write start address")
                        .at(110, 125, 94, 25)
                }
                .at(8, 249, 211, 162)
            }
            .at(6, 7, 227, 417)
            WinGroupBox(title: "Hex & bin file tools", width: 184, height: 179, font: Win.tahoma(11)) {
                WinButton(title: "Show hex File", glyph: "showHex") { model.showHexFile() }.at(12, 25, 150, 25)
                WinButton(title: "Show binary File", glyph: "showBin") {}.disabled(true).help("Not available in the Mac version.").at(12, 62, 150, 25)
                WinButton(title: "Flash any File", glyph: "flashAny") { model.flashOther() }.disabled(model.busy).at(12, 120, 150, 25)
            }
            .at(239, 7, 184, 179)
            WinGroupBox(title: "Special commands", width: 184, height: 232, font: Win.tahoma(11)) {
                WinButton(title: "Edit fuses", glyph: "fuses") {}.disabled(true).help("Fuses are written by the flash assistant (ISP).").at(12, 26, 150, 26)
                WinButton(title: "Keep Reset Target") {}.disabled(true).at(12, 83, 150, 25)
                WinButton(title: "Restart Target") { model.restartESC() }.disabled(!ready).at(12, 117, 150, 25)
                WinButton(title: "Read flash to HEX file", glyph: "verify") { model.dumpFlash() }.disabled(!ready).at(12, 164, 150, 25)
                WinButton(title: "Erase Chip", glyph: "erase") { model.eraseChip() }.disabled(!ready || !canEraseChip).at(12, 195, 150, 25)
            }
            .at(239, 192, 184, 232)
            WinGroupBox(title: "Memory view", width: 333, height: 417, font: Win.tahoma(11)) {
                ScrollView([.vertical, .horizontal]) {
                    Text(model.expertDump.isEmpty ? "(read memory to show its content here)" : model.expertDump)
                        .font(.custom("CourierNewPSMT", size: 11))
                        .foregroundColor(model.expertDump.isEmpty ? Win.grayText : Win.text)
                        .textSelection(.enabled)
                        .padding(4)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Color.white)
                .overlay(Rectangle().strokeBorder(Win.editBorder, lineWidth: 1))
                .at(8, 18, 317, 391)
            }
            .at(429, 7, 333, 417)
        }
        .onAppear(perform: applyDefaults)
        .onChange(of: device?.family) { _ in applyDefaults() }
    }
}

// MARK: - Log ("Logged Messages")

struct ClassicLogList: View {
    @EnvironmentObject var model: AppModel
    var showTraffic = true

    var entries: [LogEntry] { showTraffic ? model.log : model.log.filter { $0.level != .debug } }

    func icon(_ l: LogLevel) -> String {
        switch l {
        case .success: return "log0"
        case .error: return "log1"
        case .info, .debug: return "log2"
        case .warning: return "log3"
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(entries) { e in
                        HStack(alignment: .top, spacing: 4) {
                            Glyph(name: icon(e.level)).frame(width: 16, height: 16)
                            Text(e.date.formatted(date: .omitted, time: .standard) + "  " + e.message)
                                .font(.custom("CourierNewPSMT", size: 12))
                                .foregroundColor(e.level == .error ? Win.red : e.level == .debug ? Win.grayText : Win.text)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .id(e.id)
                    }
                }
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Win.infoBk)
            .overlay(Rectangle().strokeBorder(Win.editBorder, lineWidth: 1))
            .onChange(of: model.log.last?.id) { _ in
                if let last = entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onAppear { if let last = entries.last { proxy.scrollTo(last.id, anchor: .bottom) } }
        }
    }
}

struct ClassicLogWindow: View {
    @EnvironmentObject var model: AppModel
    @State private var showTraffic = true
    @State private var stayOnTop = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                WinMenuBarItem(title: "Log", entries: {
                    [.item("Stay On Top", checked: stayOnTop) { setStayOnTop(!stayOnTop) },
                     .separator,
                     .item("Log Protocol Traffic", checked: model.protocolTrace) { model.protocolTrace.toggle() },
                     .item("Show Protocol Traffic", checked: showTraffic) { showTraffic.toggle() },
                     .separator,
                     .item("Save to File...", image: ClassicImage.named("save")) { saveToFile() },
                     .item("Copy", image: ClassicImage.named("hexdoc")) { model.copyLog() },
                     .separator,
                     .item("Clear", image: ClassicImage.named("erase")) { model.clearLog() }]
                })
                Spacer(minLength: 0)
            }
            .frame(height: 20)
            .background(Win.face)
            ClassicLogList(showTraffic: showTraffic)
        }
        .background(Win.face)
        .frame(minWidth: 420, minHeight: 200)
        .preferredColorScheme(.light)
        .navigationTitle("Logged Messages")
    }

    func setStayOnTop(_ on: Bool) {
        stayOnTop = on
        NSApp.windows.first { $0.title == "Logged Messages" }?.level = on ? .floating : .normal
    }

    func saveToFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "BLHeliSuite.log"
        if panel.runModal() == .OK, let url = panel.url {
            let text = model.log.map { "\($0.date.formatted(date: .numeric, time: .standard)) \($0.message)" }.joined(separator: "\n")
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
