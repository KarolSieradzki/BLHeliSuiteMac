import Foundation
import AppKit
import BLHeliCore

// MARK: - ISP (AVRDude) and Toolstick connections

extension AppModel {
    func connectISP(then next: (() -> Void)?) {
        guard let dude = AVRDude(path: avrdudePath) else {
            alert = AlertItem(title: "ATMEL ISP", message: AVRDudeError.notInstalled.localizedDescription)
            return
        }
        let prog = ispProgrammer
        let port = prog.serial ? portPath : nil
        let b = prog.serial ? baud : nil
        run("Connecting ISP…", { [weak self] _ in
            let isp = ISPProgrammer(avrdude: dude, programmer: prog, port: port, baud: b)
            let dev = try isp.selectESC(0)
            self?.programmer = isp
            DispatchQueue.main.async {
                guard let self else { return }
                self.connected = true
                self.connectionInfo = "\(isp.interfaceName) – \(dev.mcu?.name ?? "?")"
                self.slots = [ESCSlot(index: 0, state: .unchecked, device: dev, settings: nil)]
                self.active = [0]
            }
        }, done: { [weak self] in
            guard let self, self.connected else { return }
            self.check(then: next)
        })
    }

    func connectToolstick(then next: (() -> Void)?) {
        let serial = toolstickSerial.isEmpty ? nil : toolstickSerial
        run("Connecting Toolstick…", { [weak self] _ in
            let ts = try ToolstickProgrammer.open(serial: serial)
            self?.programmer = ts
            DispatchQueue.main.async {
                guard let self else { return }
                self.connected = true
                self.connectionInfo = ts.interfaceName
                self.slots = [ESCSlot(index: 0)]
                self.active = [0]
            }
        }, done: { [weak self] in
            guard let self, self.connected else { return }
            self.check(then: next)
        })
    }
}

// MARK: - Expert tools

extension AppModel {
    func expertRead(start: Int, length: Int, eeprom: Bool) {
        guard connected, let m = masterIndex, length > 0 else { return }
        run("Reading memory…", { [weak self] p in
            guard let p else { return }
            _ = try p.selectESC(m)
            let data = eeprom ? try p.readEEPROM(address: start, count: length)
                              : try p.readFlash(address: start, count: length, progress: nil)
            let dump = AppModel.hexDump(data, base: start)
            DispatchQueue.main.async { self?.expertDump = dump }
        })
    }

    func expertWrite(start: Int, bytes: [UInt8], eeprom: Bool) {
        guard connected, let m = masterIndex, !bytes.isEmpty else { return }
        confirm = ConfirmItem(title: "Write memory", message: String(format: "Write %d byte(s) to %@ address 0x%04X of ESC #%d?", bytes.count, eeprom ? "EEprom" : "flash", start, m + 1), destructive: true) { [weak self] in
            self?.run("Writing memory…", { p in
                guard let p else { return }
                _ = try p.selectESC(m)
                if eeprom { try p.writeEEPROM(address: start, data: bytes, progress: nil) }
                else { try p.writeFlash(address: start, data: bytes, progress: nil) }
                Log.success("Wrote \(bytes.count) bytes")
            })
        }
    }

    func expertErasePage(_ requested: Int) {
        guard connected, let m = masterIndex else { return }
        // always a whole page: round down to the page start of the selected MCU
        let pageSize = (m < slots.count ? slots[m].device?.pageSize : nil) ?? 0
        let address = pageSize > 0 ? requested - requested % pageSize : requested
        confirm = ConfirmItem(title: "Erase page", message: String(format: "Erase the flash page at 0x%04X of ESC #%d?", address, m + 1), destructive: true) { [weak self] in
            self?.run("Erasing page…", { p in
                guard let p else { return }
                _ = try p.selectESC(m)
                try p.erasePage(address: address)
                Log.success(String(format: "Page 0x%04X erased", address))
            })
        }
    }

    /// Address / length input: "0x1A00", "$1A00", "1A00h", "1A00" (contains hex letters) or decimal "6656".
    nonisolated static func parseNumber(_ s: String) -> Int? {
        var t = s.trimmingCharacters(in: .whitespaces).lowercased()
        var hex = false
        if t.hasPrefix("0x") { t.removeFirst(2); hex = true }
        else if t.hasPrefix("$") { t.removeFirst(); hex = true }
        else if t.hasSuffix("h") { t.removeLast(); hex = true }
        else if t.contains(where: { "abcdef".contains($0) }) { hex = true }
        guard !t.isEmpty, let v = Int(t, radix: hex ? 16 : 10), v >= 0 else { return nil }
        return v
    }

    /// Hex bytes "01 02 FF" / "0x01,0x02" – nil if any token is not a byte (never writes a partial list).
    nonisolated static func parseBytes(_ s: String) -> [UInt8]? {
        var out: [UInt8] = []
        for token in s.split(whereSeparator: { $0 == " " || $0 == "," || $0 == ";" }) {
            var t = token.lowercased()
            if t.hasPrefix("0x") { t.removeFirst(2) } else if t.hasPrefix("$") { t.removeFirst() }
            guard let b = UInt8(t, radix: 16) else { return nil }
            out.append(b)
        }
        return out.isEmpty ? nil : out
    }

    func expertRead(start: String, length: String, eeprom: Bool) {
        guard let a = Self.parseNumber(start), let n = Self.parseNumber(length), n > 0 else {
            alert = AlertItem(title: "Read memory", message: "Invalid start address or length.\nExamples: 0x1A00, 1A00h, 112")
            return
        }
        expertRead(start: a, length: n, eeprom: eeprom)
    }

    func expertWrite(start: String, bytes: String, eeprom: Bool) {
        guard let a = Self.parseNumber(start) else {
            alert = AlertItem(title: "Write memory", message: "Invalid start address.\nExamples: 0x1A60, 1A60h")
            return
        }
        guard let b = Self.parseBytes(bytes) else {
            alert = AlertItem(title: "Write memory", message: "Invalid hex bytes – use e.g. \"01 02 FF\".")
            return
        }
        expertWrite(start: a, bytes: b, eeprom: eeprom)
    }

    func expertErasePage(_ text: String) {
        guard let a = Self.parseNumber(text) else {
            alert = AlertItem(title: "Erase page", message: "Invalid page address.\nExample: 0x1A00")
            return
        }
        expertErasePage(a)
    }

    func showHexFile() {
        let panel = NSOpenPanel()
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let img = try MemoryImage.loadIntelHex(url: url)
            var text = "\(url.lastPathComponent): \(img.count) bytes\n"
            for seg in img.segments { text += AppModel.hexDump(seg.data, base: seg.start) + "\n" }
            if let s = (img.contains(range: 0x1A00..<0x1A70) ? BLHeliSettings(raw: img.read(0x1A00, 0x70)) : nil), (try? s.validate()) != nil {
                text = "BLHeli setup: \(s.summary(database: database))\n" + text
            }
            expertDump = text
            selectedTab = .expert
        } catch { alert = AlertItem(title: "Show HEX file", message: error.localizedDescription) }
    }

    nonisolated static func hexDump(_ data: [UInt8], base: Int) -> String {
        var lines: [String] = []
        var i = 0
        while i < data.count {
            let chunk = data[i..<min(i + 16, data.count)]
            let hex = chunk.map { String(format: "%02X", $0) }.joined(separator: " ")
            let ascii = String(chunk.map { (0x20...0x7E).contains($0) ? Character(UnicodeScalar($0)) : "." })
            lines.append(String(format: "%04X  ", base + i) + hex.padding(toLength: 48, withPad: " ", startingAt: 0) + "  " + ascii)
            i += 16
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Motors (MSP motor test, TfraCFMotorTest)

extension AppModel {
    func motorOpen() {
        guard interfaceType.isFlightController else { return }
        if connected { disconnect() }
        let path = portPath
        let b = baud
        worker.async { [weak self] in
            guard let self else { return }
            do {
                let port = SerialPort(path: path)
                try port.open(baudRate: b)
                let msp = MSPClient(channel: port)
                var info: FlightControllerInfo
                do { info = try msp.identify() } catch {
                    // leave a pending 4-way session first
                    try? port.write(FourWayClient.frame(FourWayCommand.interfaceExit.rawValue, address: 0, params: [0]))
                    sleepSeconds(0.6)
                    port.discardInput()
                    info = try msp.identify()
                }
                let cfg = (try? msp.motorConfig()) ?? (min: 1070, max: 2000, command: 1000)
                let motors = (try? msp.motorValues()) ?? []
                let armed = (try? msp.isArmed()) ?? false
                self.mspPort = port
                self.mspClient = msp
                let count = max(1, motors.filter { $0 > 0 }.count)
                DispatchQueue.main.async {
                    self.motorSessionOpen = true
                    self.motorInfo = info.description + (armed ? " – ARMED!" : "")
                    self.motorCountFC = min(8, count)
                    self.motorMinCommand = Double(cfg.command)
                    self.motorValues = Array(repeating: Double(cfg.command), count: 8)
                    Log.info("Motor test: \(info.description), \(count) motors, mincommand \(cfg.command)")
                }
            } catch {
                DispatchQueue.main.async {
                    self.alert = AlertItem(title: "Motors", message: (error as? LocalizedError)?.errorDescription ?? "\(error)")
                }
            }
        }
    }

    func motorClose() {
        motorStop()
        worker.async { [weak self] in
            self?.mspPort?.close()
            self?.mspPort = nil
            self?.mspClient = nil
        }
        motorSessionOpen = false
        motorInfo = ""
    }

    func motorStart() {
        guard motorSessionOpen else { return }
        motorRunning = true
        motorTimer?.invalidate()
        motorTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.motorSend() }
        }
    }

    func motorStop() {
        motorTimer?.invalidate()
        motorTimer = nil
        motorRunning = false
        motorValues = Array(repeating: motorMinCommand, count: 8)
        let values = motorValues.map { Int($0) }
        worker.async { [weak self] in try? self?.mspClient?.setMotors(values) }
    }

    func motorSend() {
        guard motorRunning else { return }
        let values = (0..<8).map { $0 < motorCountFC ? Int(motorValues[$0]) : Int(motorMinCommand) }
        worker.async { [weak self] in
            do { try self?.mspClient?.setMotors(values) } catch {
                DispatchQueue.main.async { self?.motorStop(); self?.alert = AlertItem(title: "Motors", message: error.localizedDescription) }
            }
        }
    }
}

// MARK: - Make interfaces (flash Arduino with 4-way / 1-wire / ISP firmware)

extension AppModel {
    func makeInterface() {
        guard let folder = ArduinoBoard.interfacesFolder() else {
            alert = AlertItem(title: "Make Interfaces", message: "Interface firmware folder not found.")
            return
        }
        let board = arduinoBoard
        let kind = arduinoFirmware
        guard let hex = board.firmwareURL(kind, in: folder) else {
            alert = AlertItem(title: "Make Interfaces", message: "There is no \"\(kind.rawValue)\" firmware for \(board.name).")
            return
        }
        guard !portPath.isEmpty else { alert = AlertItem(title: "Make Interfaces", message: "Select the serial port of the Arduino first."); return }
        if connected { disconnect() }
        if motorSessionOpen { motorClose() }
        let port = portPath
        let dudePath = avrdudePath
        confirm = ConfirmItem(title: "Make Interface", message: "Do you want to flash your\n\n\"\(board.name)\" at \((port as NSString).lastPathComponent) with:\n\n\(hex.lastPathComponent)?", destructive: false) { [weak self] in
            self?.run("Flashing Arduino…", { _ in
                let image = try MemoryImage.loadIntelHex(url: hex)
                if board.nativeFlashSupported {
                    let sp = SerialPort(path: port)
                    var lastError: Error?
                    // try the board's bootloader baud first, then the other common one
                    for b in [board.baud] + [115200, 57600].filter({ $0 != board.baud }) {
                        do {
                            try sp.open(baudRate: b)
                            defer { sp.close() }
                            let stk = STK500v1(port: sp)
                            try stk.flash(image, pageSize: board.pageSize, expectedSignature: board.avrSignature, verify: true) { d, t in
                                self?.setProgress(Double(d) / Double(t), d * 2 > t ? "Verifying…" : "Writing…")
                            }
                            lastError = nil
                            break
                        } catch let e as STK500Error {
                            lastError = e
                            if case .noSync = e { continue } else { break }
                        }
                    }
                    if let e = lastError { throw e }
                } else {
                    guard let dude = AVRDude(path: dudePath) else { throw AVRDudeError.notInstalled }
                    try dude.flashArduino(board: board, port: port, hex: hex)
                }
                Log.success("Arduino flashed successfully with \(hex.lastPathComponent)")
                DispatchQueue.main.async {
                    self?.alert = AlertItem(title: "Make Interface", message: "Arduino flashed successfully.\n\nSelect the matching interface (e.g. \"SILABS BLHeli Bootloader (4way-if)\") and connect.")
                }
            })
        }
    }
}
