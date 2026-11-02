import AppKit
import VCL
import BLHeliCore

// "Make Standalone Atmega/Arduino Boxes": update of the BLHeliSuite boxes through their bootloader
// (FUN_00635A9C) or initial flash over ISP (FUN_00636820).

extension TfraMakeInterfaces {
    /// Box kinds (index of the tables at 0x68FE88 / 0x68FE6C).
    enum BoxKind: Int { case atmega8 = 0, rbbx, tdlxOld, tdlxNew, taqx, ttt }

    static let boxNames = ["ATMEGA8", "RBBX", "TDLX", "TDLX", "TAQX", "TDLX"]
    static let boxFilePrefixes = ["ATMEGA8", "RBBX", "TDLX_LURD_", "TDLX", "TAQX", "TDLX"]

    /// FUN_0063590C
    func flashBox(_ k: BoxKind) {
        if cbxInitialISPFlash.checked {
            if selectISPParams() { flashBoxISP(k) }
        } else {
            flashBoxBootloader(k)
        }
    }

    /// FUN_0063425C: MCU part of the file mask.
    func boxMcuMask(_ k: BoxKind, _ sig: UInt32) -> String {
        switch sig {
        case 0x1E9307: return k == .atmega8 ? "*.hex" : "m8*.hex"
        case 0x1E930A, 0x1E930F: return "m88P*.hex"
        case 0x1E9406, 0x1E940B: return "m168P*.hex"
        case 0x1E950F, 0x1E9514: return "m328P*.hex"
        default: return ""
        }
    }

    func boxFolder(_ k: BoxKind) -> URL? {
        guard let root = ArduinoBoard.interfacesFolder() else { return nil }
        if k == .atmega8 { return root.appendingPathComponent("ATMega4w-if") }
        return root.appendingPathComponent("ModBoxes4w-if").appendingPathComponent(TfraMakeInterfaces.boxNames[k.rawValue])
    }

    /// Interface option of the box firmware (dialog like for the Arduino boards).
    func chooseBoxOption(_ k: BoxKind, mask: String, folder: URL) -> Bool {
        interfaceOption = 0
        interfaceOptions = 0
        if k == .atmega8 {
            interfaceOption = 1
            return true
        }
        interfaceOptions = InterfaceFirmwareFiles.options(name: TfraMakeInterfaces.boxFilePrefixes[k.rawValue], mask: mask, in: folder)
        if interfaceOptions != 0 {
            interfaceOption = TfrmInterfaceOptions.execute(interfaceOptions)
            if interfaceOption == 0 { return false }
        }
        if interfaceOption == 0 {
            MsgDlg.show(DFormat(NL("No firmware file found for \"%s\""), [TfraMakeInterfaces.boxFilePrefixes[k.rawValue]]), .mtWarning, [.mbOK])
            return false
        }
        return true
    }

    /// FUN_00635958 + file dialog. Without a matching file (ATmega8 box) every hex file can be chosen.
    func chooseFile(_ mask: String, in folder: URL, title: String) -> URL? {
        if let f = InterfaceFirmwareFiles.unique(mask, in: folder) { return f }
        let matches = InterfaceFirmwareFiles.find(mask, in: folder)
        let filter = matches.isEmpty ? "Hex (*.hex)|*.hex" : DFormat(NL(" \"%s\" files"), [mask]) + "|" + mask
        return OpenDialog.execute(title: title, filter: filter, initialDir: matches.first?.deletingLastPathComponent() ?? folder)
    }

    // MARK: - update over the box bootloader (FUN_00635A9C)

    func flashBoxBootloader(_ k: BoxKind) {
        statusText = ""
        guard checkPort() else { return }
        let name = TfraMakeInterfaces.boxNames[k.rawValue]
        let prefix = TfraMakeInterfaces.boxFilePrefixes[k.rawValue]
        let baud = Int(ccbxRBBXFlashBaudrate.text_) ?? 38400
        let sp = SerialPort(path: portPath)
        do {
            try sp.open(baudRate: baud)
        } catch {
            MsgDlg.error(DFormat(NL("Connection to BLHeliSuite-Box/Device at %s failed!\\n\\nError: \"%s\"\\n\\nPlease check usb/serial port- und power-connections to the Box/Device!"),
                                 [portName, error.localizedDescription]))
            return
        }
        defer { sp.close() }
        let boot = BLHeliBootloader(channel: sp, oneWire: k != .atmega8)
        boot.timeout = 0.5
        if TfrmLogForm.isShown { boot.log = { TfrmLogForm.add($0) } }
        // "Please connect and power up the BLHeliSuite-Box" while waiting for the bootloader
        let info = TfrmInfo.showInfo(NL("Please connect and power up the BLHeliSuite-Box"), cancel: true)
        var connected = false
        var lastError = ""
        for _ in 0..<40 where !info.cancelled {
            do {
                try boot.connect(bootSign: "BOOT", attempts: 1)
                connected = true
                break
            } catch {
                lastError = error.localizedDescription
                Application.shared.processMessages()
            }
        }
        info.hideInfo()
        guard connected else {
            if !info.cancelled {
                if lastError.isEmpty {
                    MsgDlg.error(NL("Connection to BLHeliSuite-Box/Device failed!\\nPlease check usb/serial port- und power-connections to the Box/Device!"))
                } else {
                    MsgDlg.error(DFormat(NL("Connection to BLHeliSuite-Box/Device at %s failed!\\n\\nError: \"%s\"\\n\\nPlease check usb/serial port- und power-connections to the Box/Device!"),
                                         [portName, lastError]))
                }
            }
            return
        }
        defer { boot.run() }
        let sig = 0x1E0000 | UInt32(boot.signature)
        let found = String(boot.bootMessage.filter { $0.isLetter || $0.isNumber })
        var mask = ""
        if boot.bootMessage.lowercased().contains(name.lowercased()) {
            let m = boxMcuMask(k, sig)
            if !m.isEmpty { mask = prefix + m }
        }
        guard !mask.isEmpty else {
            MsgDlg.show(DFormat(NL("Wrong Box type: found \"%s\" does not match \"%s\"\\n"), [found, name]), .mtWarning, [.mbOK])
            return
        }
        guard let folder = boxFolder(k), chooseBoxOption(k, mask: mask, folder: folder) else { return }
        mask = InterfaceFirmwareFiles.prefixes[Int(interfaceOption)] + mask
        guard let hex = chooseFile(mask, in: folder, title: DFormat(NL("Choose firmware file for %s"), [name]) + " BLHeliSuite-Box"),
              FileManager.default.fileExists(atPath: hex.path) else { return }
        let eep = hex.deletingPathExtension().appendingPathExtension("eep")
        let withEEprom = k != .atmega8
        if withEEprom && !FileManager.default.fileExists(atPath: eep.path) {
            MsgDlg.error(DFormat(NL("Cannot locate corresponding EEPROM file: %s"), [eep.path]))
            return
        }
        let q = withEEprom
            ? DFormat(NL("Do you want to update your %s BLHeliSuite-Box with:\\n\\n%s\\nand\\n%s ?\\n"), [prefix, hex.lastPathComponent, eep.lastPathComponent])
            : DFormat(NL("Do you want to update your %s with:\\n\\n%s ?\\n"), [prefix, hex.lastPathComponent])
        guard let image = try? MemoryImage.loadIntelHex(url: hex) else {
            MsgDlg.error(DFormat(NL("Failed to update %s BLHeliSuite-Box with:\\n\\n%s\\n"), [prefix, hex.lastPathComponent]))
            return
        }
        let mcu = MCUTable.byAVRSignature(sig)
        let pageSize = mcu?.pageSize ?? 64
        let flashSize = mcu?.flashSize ?? 0x2000
        let available = flashSize - boot.bootPages * pageSize
        let size = (image.highestAddress ?? -1) + 1
        if size > available {
            MsgDlg.error(DFormat(NL("Failed to update %s BLHeliSuite-Box with:\\n\\n%s\\n") + NL("\\nFile size exeeds avaliable flash space: %d vs. %d"),
                                 [prefix, hex.lastPathComponent, size, available]))
            return
        }
        guard MsgDlg.show(q, .mtConfirmation, [.mbOK, .mbCancel]) == mrOk else { return }
        statusText = NL("Wait for Flash write to complete....")
        Screen.busy = true
        let progress = TfrmInfo.showInfo(statusText, cancel: false)
        var ok = true
        do {
            // erase the application area, then write and verify the non-empty chunks
            var a = 0
            while a < available {
                try boot.erasePage(address: a)
                a += pageSize
                progress.setProgress(a, 3 * available)
            }
            a = 0
            while a < size {
                let chunk = image.read(a, min(256, available - a))
                if chunk.contains(where: { $0 != 0xFF }) {
                    try boot.writeFlash(address: a, data: chunk)
                    try boot.verifyFlash(address: a, data: chunk)
                }
                a += chunk.count
                progress.setProgress(available + 2 * a, 3 * available)
            }
        } catch {
            ok = false
            progress.hideInfo()
            Screen.busy = false
            MsgDlg.error(DFormat(NL("Failed to update %s BLHeliSuite-Box with:\\n\\n%s\\n"), [prefix, hex.lastPathComponent]) + "\n" + error.localizedDescription)
        }
        if ok && withEEprom {
            statusText = NL("Wait for EEProm write to comlete....")
            do {
                let e = try MemoryImage.loadIntelHex(url: eep)
                let n = (e.highestAddress ?? -1) + 1
                var a = 0
                while a < n {
                    let chunk = e.read(a, min(64, n - a))
                    try boot.writeEEprom(address: a, data: chunk)
                    a += chunk.count
                }
            } catch {
                ok = false
                progress.hideInfo()
                Screen.busy = false
                MsgDlg.error(DFormat(NL("Failed to update %s with:\\n\\n%s\\n"), [prefix, eep.lastPathComponent]) + "\n" + error.localizedDescription)
            }
        }
        if ok {
            progress.hideInfo()
            Screen.busy = false
            statusText = NL("Arduino flashed sucsessfully by Avrdude.")
            if TfrmLogForm.isShown { TfrmLogForm.result(true) }
        }
    }

    // MARK: - initial flash over ISP (FUN_00631EC0 + FUN_00636820)

    /// FUN_00631EC0: "Select ISP Parameters".
    func selectISPParams() -> Bool {
        guard let m = main else { return false }
        let f = TfrmAvrISPSelectParams(resource: "TFRMAVRISPSELECTPARAMS", owner: m)
        defer { f.release() }
        let fr = f.fraSelectIspParams1!
        fr.fill(ports: m.ports)
        fr.setProgrammer(m.avrdude.programmer)
        fr.setPort(m.avrdude.port)
        fr.setBaud(m.avrdude.baud)
        guard f.execute() else { return false }
        m.avrdude.programmer = fr.programmerID
        if let p = AVRDudeIntf.programmers.first(where: { $0.id == fr.programmerID }) { m.avrdude.portType = p.portType }
        m.avrdude.port = fr.portPath
        m.avrdude.baud = fr.baud
        return true
    }

    /// AVRootloader fuses: BOOTRST programmed, 256 words boot section.
    func bootloaderFuses(_ sig: UInt32, _ f: AVRFuses) -> AVRFuses {
        var r = f
        switch sig {
        case 0x1E9307: r.high = (f.high & 0xF8) | 0x04                       // ATmega8: BOOTSZ=10, BOOTRST=0
        case 0x1E930A, 0x1E930F, 0x1E9406, 0x1E940B: r.ext = ((f.ext ?? 0xFF) & 0xF8) | 0x04   // m88/m168: efuse
        case 0x1E950F, 0x1E9514: r.high = (f.high & 0xF8) | 0x06           // m328P: BOOTSZ=11
        default: break
        }
        return r
    }

    func flashBoxISP(_ k: BoxKind) {
        guard let m = main else { return }
        let name = TfraMakeInterfaces.boxNames[k.rawValue]
        let prefix = TfraMakeInterfaces.boxFilePrefixes[k.rawValue]
        guard let a = AVRDude() else { MsgDlg.error(AVRDudeError.notInstalled.localizedDescription); return }
        let t = AVRDudeProgrammerType.common.first { $0.name == m.avrdude.programmer }
            ?? AVRDudeProgrammerType(name: m.avrdude.programmer, description: m.avrdude.programmer, type: m.avrdude.programmer,
                                     serial: m.avrdude.portType == 2, baud: m.avrdude.baud)
        let isp = ISPProgrammer(avrdude: a, programmer: t, port: m.avrdude.portType == 2 ? m.avrdude.port : nil,
                                baud: m.avrdude.portType == 2 ? m.avrdude.baud : nil)
        Screen.busy = true
        let dev: DeviceInfo
        let fuses: AVRFuses
        do {
            dev = try isp.selectESC(0)
            fuses = try isp.readFuses()
        } catch {
            Screen.busy = false
            MsgDlg.error(DFormat(NL("Avrdude FAILED!\\n\\n\"%s\""), [error.localizedDescription]))
            return
        }
        Screen.busy = false
        let sig = dev.mcu?.signature ?? 0
        let mcuMask = boxMcuMask(k, sig)
        guard !mcuMask.isEmpty, let folder = boxFolder(k) else { MsgDlg.error(NL("Can not find Bootloader config.")); return }
        var mask = prefix + mcuMask
        guard chooseBoxOption(k, mask: mask, folder: folder) else { return }
        let bootFolder = folder.appendingPathComponent("Bootloader")
        guard let bootHex = chooseFile(name + mcuMask, in: bootFolder,
                                       title: DFormat(NL("Choose %s bootloader file for %s BLHeliSuite-Box"), [dev.mcu?.name ?? "", name])) else { return }
        mask = InterfaceFirmwareFiles.prefixes[Int(interfaceOption)] + mask
        guard let hex = chooseFile(mask, in: folder, title: DFormat(NL("Choose %s firmware file for %s BLHeliSuite-Box"), [dev.mcu?.name ?? "", name])) else { return }
        let eep = hex.deletingPathExtension().appendingPathExtension("eep")
        let withEEprom = k != .atmega8
        if withEEprom && !FileManager.default.fileExists(atPath: eep.path) {
            MsgDlg.error(DFormat(NL("Cannot locate corresponding EEPROM file: %s"), [eep.path]))
            return
        }
        var image: MemoryImage
        do {
            image = try MemoryImage.loadIntelHex(url: hex)
            let b = try MemoryImage.loadIntelHex(url: bootHex)
            for (addr, v) in b.bytes {
                if let old = image.bytes[addr], old != 0xFF, old != v { throw ProgrammerError.notSupported(String(format: "0x%04X", addr)) }
                image.write([v], at: addr)
            }
        } catch {
            MsgDlg.error(NL("Error while merging bootloader into flash memory") + DFormat(": %s", [error.localizedDescription]))
            return
        }
        let eeprom = withEEprom ? (try? MemoryImage.loadIntelHex(url: eep)).map { $0.read(0, ($0.highestAddress ?? -1) + 1) } : nil
        let boxTitle: String
        switch k {
        case .rbbx: boxTitle = "Robbe Programmer V2"
        case .tdlxOld, .tdlxNew: boxTitle = "Turnigy Dlux Programming Box"
        case .taqx: boxTitle = "Turnigy Aquastar Program Box"
        case .ttt: boxTitle = "Turnigy Trackstar Turbo Program Box"
        case .atmega8: boxTitle = "ATMEGA8"
        }
        let files = NL("Bootloader: ") + bootHex.lastPathComponent + " + " + hex.lastPathComponent + (withEEprom ? " + " + eep.lastPathComponent : "")
        guard MsgDlg.show(DFormat(NL("Do you want to flash your\\n\\n\"%s\" at %s with:\\n\\n%s?"), [boxTitle, isp.port ?? "USB", files]),
                          .mtConfirmation, [.mbYes, .mbNo]) == mrYes else { return }
        let f = bootloaderFuses(sig, fuses)
        let ok = flashing(pnlInterfaceBoxes) {
            do {
                try isp.flashComplete(flash: image, eeprom: eeprom, fuses: (f.low, f.high, f.ext), verify: true) { s in
                    if TfrmLogForm.isShown { for l in s.split(whereSeparator: \.isNewline) { TfrmLogForm.add(String(l)) } }
                }
                return true
            } catch {
                MsgDlg.error(DFormat(NL("Avrdude FAILED!\\n\\n\"%s\""), [error.localizedDescription]))
                return false
            }
        }
        if ok { MsgDlg.show(DFormat(NL("Avrdude successfully.[%s]"), [boxTitle]), .mtInformation, [.mbOK]) }
    }

    // MARK: - ArduinoUSBLinker on Nano D3 (btnMakeArduinoUSBLinkerClick, 0x632FA4)

    func setupNanoUSBLinkerPinD3() {
        let aul = ArduinoUSBLinker()
        aul.portPath = portPath
        aul.baud = 19200
        if TfrmLogForm.isShown { aul.log = { TfrmLogForm.add($0) } }
        Screen.busy = true
        var ok = aul.connect()
        if ok, let pin = aul.pinNumber(port: "D", 3) {
            ok = (try? aul.writeSettings(pin: pin, bitTime: aul.bitTime, baud: aul.baud, save: true)) != nil
        } else {
            ok = false
        }
        aul.close()
        Screen.busy = false
        if ok {
            MsgDlg.show(NL("Settings written to \"ArduinoUSBLinker\" successfully."), .mtInformation, [.mbOK])
        } else {
            MsgDlg.error(NL("Failed to write settings to \"ArduinoUSBLinker\"."))
        }
    }
}
