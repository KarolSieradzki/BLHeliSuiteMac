import SwiftUI
import BLHeliCore

/// "Motors" tab – motor test through the flight controller (MSP_SET_MOTOR).
struct MotorsView: View {
    @EnvironmentObject var model: AppModel
    @State private var propsRemoved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("REMOVE ALL PROPELLERS before testing motors!", systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.red)
            Text("The motor test uses the flight controller (MSP). An open 4-way session is closed automatically. The FC must be disarmed.")
                .foregroundStyle(.secondary)
            HStack {
                if model.motorSessionOpen {
                    Text(model.motorInfo).font(.callout)
                    Button("Close") { model.motorClose() }
                } else {
                    Button("Connect to flight controller") { model.motorOpen() }
                        .disabled(model.busy || model.portPath.isEmpty)
                }
            }
            if model.motorSessionOpen {
                Toggle("Propellers are removed – activate motor test", isOn: $propsRemoved)
                    .onChange(of: propsRemoved) { on in if on { model.motorStart() } else { model.motorStop() } }
                GroupBox("Master") {
                    HStack {
                        Slider(value: Binding(
                            get: { model.motorValues.prefix(model.motorCountFC).max() ?? model.motorMinCommand },
                            set: { v in for i in 0..<model.motorCountFC { model.motorValues[i] = v } }),
                               in: model.motorMinCommand...2000, step: 5)
                        Text(verbatim: String(Int(model.motorValues.prefix(model.motorCountFC).max() ?? 0))).frame(width: 50)
                    }
                    .disabled(!propsRemoved)
                }
                GroupBox("Motors") {
                    HStack(alignment: .bottom, spacing: 22) {
                        ForEach(0..<model.motorCountFC, id: \.self) { i in
                            VStack {
                                Text(verbatim: String(Int(model.motorValues[i]))).font(.caption.monospacedDigit())
                                Slider(value: $model.motorValues[i], in: model.motorMinCommand...2000, step: 5)
                                    .rotationEffect(.degrees(-90))
                                    .frame(width: 160, height: 30)
                                    .frame(width: 40, height: 170)
                                Text("Motor \(i + 1)").font(.caption)
                            }
                        }
                    }
                    .disabled(!propsRemoved)
                    .padding(8)
                }
                Button("STOP all motors") {
                    propsRemoved = false
                    model.motorStop()
                }
                .keyboardShortcut(.space, modifiers: [])
                .controlSize(.large)
                .tint(.red)
            }
            Spacer()
        }
        .padding(16)
        .onDisappear { propsRemoved = false; model.motorStop() }
    }
}

/// "Make interfaces" tab – flash an Arduino with the interface firmware shipped with BLHeliSuite.
struct MakeInterfacesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Turn an Arduino into a BLHeli programming interface").font(.title3.weight(.semibold))
                GroupBox {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            Text("Arduino board:")
                            Picker("", selection: $model.arduinoBoard) {
                                ForEach(ArduinoBoard.all) { b in Text(b.name).tag(b) }
                            }
                            .labelsHidden()
                            .frame(width: 380)
                        }
                        GridRow {
                            Text("Firmware:")
                            Picker("", selection: $model.arduinoFirmware) {
                                ForEach(ArduinoBoard.InterfaceFirmware.allCases) { k in Text(k.rawValue).tag(k) }
                            }
                            .labelsHidden()
                            .frame(width: 380)
                        }
                        GridRow {
                            Text("Port:")
                            HStack {
                                Picker("", selection: $model.portPath) {
                                    ForEach(model.ports) { p in Text(p.displayName).tag(p.path) }
                                    if !model.portPath.isEmpty && !model.ports.contains(where: { $0.path == model.portPath }) {
                                        Text(model.portPath).tag(model.portPath)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 330)
                                Button { model.refreshPorts() } label: { Image(systemName: "arrow.clockwise") }
                            }
                        }
                        GridRow {
                            Text("File:")
                            Text(fileName).font(.system(.body, design: .monospaced)).foregroundStyle(fileName.hasPrefix("–") ? .red : .primary)
                        }
                        GridRow {
                            Text("")
                            Text(model.arduinoBoard.nativeFlashSupported
                                 ? "Flashed directly through the Arduino bootloader (" + String(model.arduinoBoard.baud) + " baud)."
                                 : "This board needs avrdude (brew install avrdude).")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                }
                Button {
                    model.makeInterface()
                } label: { Label("Flash Arduino", systemImage: "bolt.fill") }
                .controlSize(.large)
                .disabled(model.busy || fileName.hasPrefix("–"))
                GroupBox("Wiring (4way-interface)") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bootloader / servo wire (BLHeli, BLHeli_S): ESC signal → SIG pin, ESC ground → GND.")
                        Text("Multi ESC (MULTI firmware): ESC #1…#8 → D3, D4, D5, D6, D7, D8, D9, D10 (Nano) or D11, D10, D9, D8, A2…A5 (Uno/others).")
                        Text("Single ESC (PB3PB4): signal → D11.  SiLabs C2: C2CK → D11 (ESC #1), C2D → D12, GND → GND.")
                        Text("Arduino Mega: ESC #1 → D51, #2 → D49, #3 → D48 … (C2D → D50).")
                        Text("After flashing, select the \"(4way-if)\" interface in BLHeliSuite (38400 baud).")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
    }

    var fileName: String {
        guard let folder = ArduinoBoard.interfacesFolder() else { return "– interface firmware folder not found" }
        return model.arduinoBoard.firmwareURL(model.arduinoFirmware, in: folder)?.lastPathComponent ?? "– not available for this board"
    }
}

/// Bottom-left box for the SiLabs Toolstick (USB HID, C2).
struct ToolstickBox: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GroupBox {
            HStack(spacing: 10) {
                Text("Toolstick:")
                Text(ToolstickProgrammer.devicesDescription())
                    .foregroundStyle(.secondary)
                    .frame(width: 280, alignment: .leading)
                    .lineLimit(1)
                Button(model.connected ? "Disconnect" : "Connect") { model.toggleConnection() }
                    .disabled(model.busy)
            }
        }
    }
}

/// Bottom-left box for the Atmel ISP interface (avrdude).
struct ISPBox: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GroupBox {
            HStack(spacing: 8) {
                Picker("ISP Prog:", selection: $model.ispProgrammer) {
                    ForEach(AVRDudeProgrammerType.common) { p in Text(p.description).tag(p) }
                }
                .frame(width: 280)
                .disabled(model.connected || model.busy)
                if model.ispProgrammer.serial {
                    Picker("Port:", selection: $model.portPath) {
                        ForEach(model.ports) { p in Text(p.name).tag(p.path) }
                    }
                    .frame(width: 200)
                    .disabled(model.connected || model.busy)
                }
                Button(model.connected ? "Disconnect" : "Connect") { model.toggleConnection() }
                    .disabled(model.busy)
                if AVRDude(path: model.avrdudePath) == nil {
                    Text("avrdude missing – brew install avrdude").font(.caption).foregroundStyle(.red)
                }
            }
        }
    }
}
