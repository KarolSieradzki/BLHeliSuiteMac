import SwiftUI
import BLHeliCore

/// "Expert Tools" tab: raw memory access of the selected ESC (TfraExpertTools).
struct ExpertToolsView: View {
    @EnvironmentObject var model: AppModel
    @State private var readStart = "0x1A00"
    @State private var readLength = "112"
    @State private var memType = 0   // 0 flash, 1 eeprom
    @State private var writeStart = "0x1A60"
    @State private var writeBytes = "FF"
    @State private var erasePage = "0x1A00"

    var device: DeviceInfo? {
        guard let m = model.masterIndex, m < model.slots.count else { return nil }
        return model.slots[m].device
    }

    var canEraseChip: Bool { device.map { $0.interfaceMode == .siLabsC2 || $0.isISP } ?? false }

    /// Default addresses point at the setup block: SiLabs flash 0x1A00, Atmel EEPROM 0.
    func applyDefaults() {
        guard let d = device else { return }
        if d.family == .atmel {
            memType = 1
            readStart = "0x0000"; writeStart = "0x0060"; erasePage = ""
        } else {
            memType = 0
            readStart = "0x1A00"; writeStart = "0x1A60"; erasePage = "0x1A00"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Expert tools work on the master ESC (\(model.masterIndex.map { "#\($0 + 1)" } ?? "none")). Wrong writes can make the ESC unusable!")
                    .foregroundStyle(.orange)
                GroupBox("Memory access") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Memory:", selection: $memType) {
                            Text("Flash").tag(0)
                            Text("EEprom (Atmel)").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 280)
                        HStack {
                            TextField("Start", text: $readStart).frame(width: 90)
                            TextField("Length", text: $readLength).frame(width: 70)
                            Button("Read") { model.expertRead(start: readStart, length: readLength, eeprom: memType == 1) }
                                .disabled(!model.connected || model.busy)
                        }
                        HStack {
                            TextField("Start", text: $writeStart).frame(width: 90)
                            TextField("Hex bytes (e.g. 01 02 FF)", text: $writeBytes).frame(width: 260)
                            Button("Write") {
                                model.expertWrite(start: writeStart, bytes: writeBytes, eeprom: memType == 1)
                            }
                            .disabled(!model.connected || model.busy)
                        }
                        HStack {
                            TextField("Page address", text: $erasePage).frame(width: 90)
                            Button("Erase page") { model.expertErasePage(erasePage) }
                                .disabled(!model.connected || model.busy || erasePage.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        if !model.expertDump.isEmpty {
                            ScrollView(.horizontal) {
                                Text(model.expertDump)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(6)
                            }
                            .frame(maxHeight: 260)
                            .background(Color(nsColor: .textBackgroundColor))
                        }
                    }
                    .padding(6)
                }
                GroupBox("Special commands") {
                    HStack {
                        Button("Read complete flash to HEX file…") { model.dumpFlash() }
                        Button("Restart ESC") { model.restartESC() }
                        Button("Erase chip (C2/ISP)") { model.eraseChip() }
                            .disabled(!canEraseChip)
                    }
                    .disabled(!model.connected || model.busy)
                    .padding(6)
                }
                GroupBox("Hex files") {
                    HStack {
                        Button("Show HEX file…") { model.showHexFile() }
                    }
                    .padding(6)
                }
            }
            .padding(12)
        }
        .onAppear { applyDefaults() }
        .onChange(of: device?.family) { _ in applyDefaults() }
    }
}
