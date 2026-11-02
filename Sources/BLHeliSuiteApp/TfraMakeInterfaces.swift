import AppKit
import VCL
import BLHeliCore

/// Frame TfraMakeInterfaces (DFM resource TFRAMAKEINTERFACES).
@objc(TfraMakeInterfaces) final class TfraMakeInterfaces: TFrame {
    @objc var btnFlashATMEGA8: TButton!
    @objc var btnFlashRBBXBox: TButton!
    @objc var btnFlashT160ABox: TButton!
    @objc var btnFlashTAQXBox: TButton!
    @objc var btnFlashTDLXBox: TButton!
    @objc var btnFlashTTTBox: TButton!
    @objc var btnMakeArduino4way_if: TButton!
    @objc var btnMakeArduinoBLBootloader: TButton!
    @objc var btnMakeArduinoISP: TButton!
    @objc var btnMakeArduinoUno4884Shield: TButton!
    @objc var btnMakeArduinoUnoLCD1602: TButton!
    @objc var btnMakeArduinoUSBLinker: TButton!
    @objc var btnSetupArduinoUSBLinker: TButton!
    @objc var cbxComPorts: TComboBox!
    @objc var cbxInitialISPFlash: TCheckBox!
    @objc var ccbArduinoBoards: TComboBox!
    @objc var ccbxArduinoBaudrates: TComboBox!
    @objc var ccbxRBBXFlashBaudrate: TComboBox!
    @objc var CompInfo: TDummyComponent!
    @objc var grbArduinoBoards: TGroupBox!
    @objc var grbArduinoBoxes: TGroupBox!
    @objc var grbAtmegaBoxes: TGroupBox!
    @objc var imgArduinoNano: TImage!
    @objc var imgArduinoUno: TImage!
    @objc var imgArduinoUnoLCD1602: TImage!
    @objc var imgRBBX: TImage!
    @objc var imgrduinoUno4884Shield: TImage!
    @objc var imgT160ABox: TImage!
    @objc var imgTAQX: TImage!
    @objc var imgTDLX: TImage!
    @objc var imgTTTBox: TImage!
    @objc var lbl_1: TStaticText!
    @objc var lbl_21: TStaticText!
    @objc var lbl_22: TStaticText!
    @objc var lbl_23: TStaticText!
    @objc var lbl_31: TStaticText!
    @objc var lbl_32: TStaticText!
    @objc var lbl_33: TStaticText!
    @objc var lbl_4: TStaticText!
    @objc var lbl_B1: TStaticText!
    @objc var lbl_B2: TStaticText!
    @objc var lbl_B3: TStaticText!
    @objc var lbl_C: TStaticText!
    @objc var lbl_D1: TStaticText!
    @objc var lbl_D2: TStaticText!
    @objc var lbl_D3: TStaticText!
    @objc var lbl_X: TStaticText!
    @objc var lblArduinoBaud: TLabel!
    @objc var lblArduinoBoards: TLabel!
    @objc var lblAtmegaInterfaceFlashBaudrate: TLabel!
    @objc var lblSerialPort: TLabel!
    @objc var pnlIndicatorArduino1Wire: TPanel!
    @objc var pnlIndicatorArduino4Way: TPanel!
    @objc var pnlIndicatorArduinoBoxes: TPanel!
    @objc var pnlIndicatorArduinoISP: TPanel!
    @objc var pnlIndicatorArduinoUSBLinker: TPanel!
    @objc var pnlIndicatorAtmegaBoxes: TPanel!
    @objc var pnlInterfaceBoxes: TPanel!
    @objc var pnlMain: TPanel!
    @objc var pntlBottom: TPanel!

    // private fields of the original frame
    var portPath = ""                   // +0x368 COM port
    var portPaths: [String] = []        // objects of cbxComPorts.Items
    var folder: URL?                    // +0x35C
    var interfaceOption: UInt8 = 0      // +0x36C chosen interface option (prefix index)
    var interfaceOptions: UInt16 = 0    // +0x36D options found for the last firmware mask
    var statusText = ""                 // +0x378
    let loader = ArduinoLoader()        // +0x358 / +0x370 TAVRDude
    let mainRef = WeakRef()
    final class WeakRef { weak var obj: AnyObject? }

    var main: TfrmBLHeliSuiteMain? { mainRef.obj as? TfrmBLHeliSuiteMain }
}

extension TfraMakeInterfaces {
    /// TfraMakeInterfaces.Create (0x633EC4): captions and hints.
    func attach(_ m: TfrmBLHeliSuiteMain) {
        mainRef.obj = m
        cbxInitialISPFlash.hint = NL("Initial Flash (including Bootloader) over ISP")
        cbxInitialISPFlash.caption = NL("Initial ISP Flash w. Bootloader")
        for i in [imgRBBX, imgTDLX, imgTAQX, imgTTTBox, imgT160ABox] { i?.hint = NL("Click to google product information.") }
        grbAtmegaBoxes.caption = NL("Make Standalone Atmega Boxes")
        grbArduinoBoxes.caption = NL("Make Standalone Arduino Boxes")
        grbArduinoBoards.caption = NL("Make Arduino Interface Boards")
        for p in [pnlIndicatorArduinoBoxes, pnlIndicatorArduino1Wire, pnlIndicatorArduino4Way, pnlIndicatorArduinoISP,
                  pnlIndicatorArduinoUSBLinker, pnlIndicatorAtmegaBoxes] {
            p?.hint = NL("Selectable interface options")
        }
        loader.output = { s in
            guard TfrmLogForm.isShown else { return }
            for l in s.split(whereSeparator: \.isNewline) where !l.trimmingCharacters(in: .whitespaces).isEmpty { TfrmLogForm.add(String(l)) }
        }
    }

    /// FUN_0063454C + FUN_00634A84: fills the lists when the page is shown and selects `port`.
    func prepare(port: String) {
        guard let m = main else { return }
        interfaceOption = 0
        interfaceOptions = 0
        // port list of the main form (cbxComPorts.Items.Assign)
        portPaths = m.ports.paths
        cbxComPorts.items = m.ports.names
        ccbxRBBXFlashBaudrate.items = BaudLists.normal.map(String.init)
        ccbxRBBXFlashBaudrate.itemIndex = ccbxRBBXFlashBaudrate.items.firstIndex(of: "38400") ?? -1
        ccbxRBBXFlashBaudrate.hint = DFormat(NL("The default connection baud rate for the bootloader of the interface is %d.\\nIt should not be changed, unless otherwise noted."), [38400])
        cbxComPorts.hint = NL("Select the appropriate COM port for the interface.")
        ccbArduinoBoards.items = ArduinoBoard.all.map(\.name)
        ccbArduinoBoards.itemIndex = ccbArduinoBoards.items.firstIndex(of: "Nano w/ ATmega328") ?? -1
        ccbxArduinoBaudrates.items = ["115200", "57600", "19200"]
        ccbxArduinoBaudrates.itemIndex = 1
        setOptionHints()
        // FUN_00634A84
        if let i = portPaths.firstIndex(of: port) {
            cbxComPorts.itemIndex = i
        } else {
            cbxComPorts.itemIndex = portPaths.isEmpty ? -1 : 0
        }
        cbxComPortsCloseUp(self)
    }

    /// FUN_00634E44: hints of the interface letters ("Interface option selectable: [A] SILABS …").
    func setOptionHints() {
        let letters = Array("ABCDE123456X")
        func h(_ i: Int) -> String {
            DFormat(NL("Interface option selectable: \"%s\""), ["[" + String(letters[i]) + "] " + IntfType.captions[i]])
        }
        lbl_1.hint = h(5)
        lbl_21.hint = h(6); lbl_22.hint = lbl_21.hint; lbl_23.hint = lbl_21.hint
        lbl_31.hint = h(7); lbl_32.hint = lbl_31.hint; lbl_33.hint = lbl_31.hint
        lbl_4.hint = h(8)
        lbl_B1.hint = h(1); lbl_B2.hint = lbl_B1.hint; lbl_B3.hint = lbl_B1.hint
        lbl_C.hint = h(2)
        lbl_D1.hint = h(3); lbl_D2.hint = lbl_D1.hint; lbl_D3.hint = lbl_D1.hint
        lbl_X.hint = h(11)
    }

    /// FUN_00634220: selected board.
    var board: ArduinoBoard? {
        let i = ccbArduinoBoards.itemIndex
        return i >= 0 && i < ArduinoBoard.all.count ? ArduinoBoard.all[i] : nil
    }

    var portName: String { PortList.shortName(portPath) }

    /// FUN_00634B14: hints that depend on the board.
    func setBoardHints() {
        guard let b = board else { return }
        let name = ccbArduinoBoards.text_
        ccbxArduinoBaudrates.hint = DFormat(NL("Default baud rate for \"Arduino %s\" board is: %d"), [name, b.baud])
        func flashHint(_ firmware: String, _ use: String) -> String {
            DFormat(NL("Flash \"Arduino %s\" \\nwith "), [name]) + NL(firmware) + ".\n\n" + NL(use)
        }
        btnMakeArduinoISP.hint = flashHint("ArduinoISP sketch", "Use to flash Atmel ESC initially over\\n- 6-Pin ISP connection.")
        btnMakeArduino4way_if.hint = flashHint("BLHeliSuite 4way-interface firmware",
                                               "Use to connect ESC over either:\\n- SiLabs C2 interface\\n- Atmel/SiLabs BLHeli bootloader\\n- Atmel SimonK bootloader")
        btnMakeArduinoBLBootloader.hint = flashHint("USB/UART 1-Wire bridge firmware", "Use to connect ESC over:\\n- Atmel/SiLabs BLHeli bootloader")
        btnMakeArduinoUSBLinker.hint = flashHint("ArduinoUSBLinker sketch", "Use to connect ESC over:\\n- Atmel SimonK bootloader")
    }

    /// FUN_00554A50: "Please select a valid COM port first" + Abort.
    func checkPort() -> Bool {
        if portPath.isEmpty {
            MsgDlg.error(NL("Please select a valid COM port first"))
            return false
        }
        return true
    }

    func log(_ s: String) { if TfrmLogForm.isShown { TfrmLogForm.add(s, color: 0x800000) } }

    // MARK: - avrdude steps (TAVRDude)

    /// FUN_00622948: avrdude available (the "arduino" programmer is built in).
    func avrdudeAvailable() -> Bool {
        if loader.isNative || AVRDude() != nil { return true }
        MsgDlg.error(AVRDudeError.notInstalled.localizedDescription)
        return false
    }

    /// FUN_006223E0: "AVRDude Connect:" – reads the device signature.
    func avrdudeConnect() -> Bool {
        log(NL("AVRDude Connect:"))
        TfrmLogForm.indent(1)
        var ok = true
        do {
            try loader.connect()
        } catch {
            ok = false
            MsgDlg.error(DFormat(NL("Avrdude FAILED!\\n\\n\"%s\""), [(error as? LocalizedError)?.errorDescription ?? "\(error)"]))
        }
        TfrmLogForm.indent(-1)
        if TfrmLogForm.isShown {
            TfrmLogForm.result(ok)
            if ok { TfrmLogForm.add(": " + loader.foundPart, color: 0xFF00FF) }
        }
        return ok
    }

    /// FUN_00624B88: writes the hex file (avrdude -D -U flash:w:file:i).
    func avrdudeFlash(_ hex: URL) -> Bool {
        do {
            try loader.flash(hex) { _, _ in Application.shared.processMessages() }
            return true
        } catch {
            MsgDlg.error(DFormat(NL("Avrdude FAILED!\\n\\n\"%s\""), [(error as? LocalizedError)?.errorDescription ?? "\(error)"]))
            return false
        }
    }

    /// Runs `body` like the original: panel disabled, "Flashing with AVRDude:" in the log.
    func flashing(_ panel: TPanel, _ body: () -> Bool) -> Bool {
        panel.enabled = false
        Screen.busy = true
        if TfrmLogForm.isShown {
            log(NL("Flashing with AVRDude:"))
            TfrmLogForm.indent(1)
        }
        Application.shared.processMessages()
        let ok = body()
        if TfrmLogForm.isShown {
            TfrmLogForm.indent(-1)
            TfrmLogForm.result(ok)
        }
        Screen.busy = false
        panel.enabled = true
        return ok
    }

    // MARK: - Arduino 4way-if / LCD shields (FUN_00632048)

    func makeArduino(_ kind: Int) {
        guard checkPort() else { return }
        guard let root = ArduinoBoard.interfacesFolder() else {
            MsgDlg.error(DFormat(NL("No firmware file found for \"%s\""), ["Interfaces"]))
            return
        }
        folder = root
        var name: String, mhzPart = "", caption: String
        var part = ""
        switch kind {
        case 1, 2:
            loader.part = "m328p"
            loader.programmer = "arduino"
            loader.baud = 115200
            name = kind == 1 ? "Arduino_Uno_LCD1602" : "Arduino_Uno_LCD4884"
            caption = NL("Arduino UNO " + "with" + (kind == 1 ? " LCD 1602 Shield" : " LCD 4884 Shield"))
        default:
            guard let b = board else { MsgDlg.error(NL("Internal Error")); return }
            loader.part = b.part
            loader.programmer = b.programmer
            loader.baud = Int(ccbxArduinoBaudrates.text_) ?? b.baud
            part = b.part
            name = InterfaceFirmwareFiles.fourWayName(b)
            mhzPart = "*_\(b.mhz)_"
            caption = "Arduino " + ccbArduinoBoards.text_
        }
        var mask = name + mhzPart + "*.hex"
        if interfaceOption == 0 {
            interfaceOptions = InterfaceFirmwareFiles.options(name: name, mask: mask, in: root)
        }
        if interfaceOptions != 0 {
            interfaceOption = TfrmInterfaceOptions.execute(interfaceOptions)
            if interfaceOption == 0 { return }
        }
        if interfaceOption == 0 {
            if part == "atmega32u4" {
                MsgDlg.show(DFormat(NL("Boards with: %s are not supported yet."), [part]), .mtWarning, [.mbOK])
            } else {
                MsgDlg.show(DFormat(NL("No firmware file found for \"%s\""), [mask]), .mtWarning, [.mbOK])
            }
            return
        }
        mask = InterfaceFirmwareFiles.prefixes[Int(interfaceOption)] + mask
        guard avrdudeAvailable() else { return }
        var file = InterfaceFirmwareFiles.unique(mask, in: root)
        if file == nil {
            let start = InterfaceFirmwareFiles.find(mask, in: root).first?.deletingLastPathComponent() ?? root
            file = OpenDialog.execute(title: DFormat(NL("Choose firmware file for %s"), [caption]),
                                      filter: DFormat(NL(" \"%s\" files"), [mask]) + "|" + mask, initialDir: start)
        }
        guard let hex = file, FileManager.default.fileExists(atPath: hex.path) else {
            statusText = NL("Arduino flash by Avrdude FAILED!")
            return
        }
        loader.port = portPath
        let q = DFormat(NL("Do you want to flash your\\n\\n\"%s\" at %s with:\\n\\n%s?"), [caption, portName, hex.lastPathComponent])
        guard MsgDlg.show(q, .mtConfirmation, [.mbYes, .mbNo]) == mrYes else { return }
        statusText = NL("Wait for Avrdude to complete....")
        let ok = flashing(pnlInterfaceBoxes) { avrdudeAvailable() && avrdudeConnect() && avrdudeFlash(hex) }
        if ok {
            statusText = NL("Arduino flashed sucsessfully by Avrdude.")
            MsgDlg.show(DFormat(statusText + "\n\n\"%s\"", [loader.resultText]), .mtInformation, [.mbOK])
        } else {
            statusText = NL("Arduino flash by Avrdude FAILED!")
        }
    }

    // MARK: - 1-wire, ArduinoUSBLinker, ArduinoISP (btnMakeArduinoBLBootloaderClick 0x6338D8 …)

    /// Common part of the three sketch buttons: file check, question, connect, MCU check and flash.
    func makeSketch(subfolder: String, prefix: String, question: String) -> ArduinoBoard? {
        guard checkPort(), let b = board else { return nil }
        loader.programmer = b.programmer
        loader.baud = Int(ccbxArduinoBaudrates.text_) ?? b.baud
        loader.part = b.part
        loader.port = portPath
        let dir = ArduinoBoard.interfacesFolder()?.appendingPathComponent(subfolder)
        let file = dir?.appendingPathComponent(prefix + b.tag + ".hex")
        guard let hex = file, FileManager.default.fileExists(atPath: hex.path) else {
            if b.part == "atmega32u4" {
                MsgDlg.show(DFormat(NL("Boards with: %s are not supported yet."), [b.part]), .mtWarning, [.mbOK])
            } else if subfolder == "Arduino1Wire" {
                MsgDlg.error(DFormat(NL("Board is not supported yet - or missing File\\n%s"), [file?.path ?? prefix + b.tag + ".hex"]))
            } else {
                MsgDlg.error(DFormat(NL("File not found:\\n%s"), [file?.path ?? prefix + b.tag + ".hex"]))
            }
            return nil
        }
        let q = DFormat(NL("Flash \"Arduino %s\" \\nat %s"), [b.name, portName]) + NL(question)
        guard MsgDlg.show(q, .mtConfirmation, [.mbYes, .mbNo]) == mrYes else { return nil }
        var flashed = false
        _ = flashing(pnlMain) {
            guard avrdudeAvailable(), avrdudeConnect() else { return false }
            guard ArduinoLoader.signature(ofPart: b.part) == loader.foundSignature else {
                MsgDlg.error(DFormat(NL("\"Arduino %s\" should have a %s MCU on board.\\nAVRDude found instead: %s. Please check the settings!"),
                                     [b.name, ArduinoLoader.mcuName(ofPart: b.part), loader.foundPart]))
                return false
            }
            flashed = avrdudeFlash(hex)
            return flashed
        }
        guard flashed else { return nil }
        MsgDlg.show(DFormat(NL("Arduino flashed sucsessfully by Avrdude.") + "\n\n\"%s\"", [loader.resultText]), .mtInformation, [.mbOK])
        return b
    }

    @objc func btnMakeArduinoBLBootloaderClick(_ sender: TObject) {
        guard makeSketch(subfolder: "Arduino1Wire", prefix: "Arduino1Wire_", question: " for BLHeli Bootloader Interface usage?") != nil else { return }
        MsgDlg.show(NL("Please select \"SILABS or ATMEL BLHeli Bootloader (USB/Com)\" Interface."), .mtInformation, [.mbOK])
    }

    @objc func btnMakeArduinoUSBLinkerClick(_ sender: TObject) {
        guard let b = makeSketch(subfolder: "ArduinoUSBLinker", prefix: "ArduinoUSBLinker_", question: " for SK Bootloader usage?") else { return }
        MsgDlg.show(DFormat(NL("Please select \"ATMEL SK Bootloader (ArduinoUSBLinker)\" Interface\\nand set connection speed between %d and %d baud."), [9600, 115200]),
                    .mtInformation, [.mbOK])
        guard b.name.uppercased().contains("NANO") else { return }
        guard MsgDlg.show(DFormat(NL("Do you want to setup the Nano \"ArduinoUSBLinker\"\\nfor using Servo plug connected to %s|-|GND ?"), ["D3"]),
                          .mtConfirmation, [.mbYes, .mbNo]) == mrYes else { return }
        setupNanoUSBLinkerPinD3()
    }

    @objc func btnMakeArduinoISPClick(_ sender: TObject) {
        guard makeSketch(subfolder: "ArduinoISP", prefix: "ArduinoISP4m5_", question: " for ISP Interface usage?") != nil else { return }
        MsgDlg.show(DFormat(NL("Please select \"ATMEL ISP Interface\" with \"ArduinoISP\" as programmer\\nand set connection speed to %d baud."),
                            [loader.baud == 19200 ? 9600 : 19200]), .mtInformation, [.mbOK])
    }

    @objc func btnMakeArduino4way_ifClick(_ sender: TObject) { makeArduino(0) }
    @objc func btnMakeArduinoUnoLCD1602Click(_ sender: TObject) { makeArduino(1) }
    @objc func btnMakeArduinoUno4884ShieldClick(_ sender: TObject) { makeArduino(2) }

    // MARK: - standalone boxes (FUN_0063590C)

    @objc func btnFlashATMEGA8Click(_ sender: TObject) { flashBox(.atmega8) }
    @objc func btnFlashRBBXBoxClick(_ sender: TObject) { flashBox(.rbbx) }
    @objc func btnFlashTAQXBoxClick(_ sender: TObject) { flashBox(.taqx) }
    @objc func btnFlashTTTBoxClick(_ sender: TObject) { flashBox(.ttt) }

    @objc func btnFlashTDLXBoxClick(_ sender: TObject) {
        guard checkPort() else { return }
        let r = MsgDlg.show(NL("Flash Turnigy Delux Box...\\n\\nSelect Keyboard layout:\\nYES = New Layout (Left|Up|Down|Right)\\nNO  = Old Layout (Left|Up|Right|Down)"),
                            .mtConfirmation, [.mbYes, .mbNo, .mbCancel])
        if r == mrYes { flashBox(.tdlxNew) } else if r == mrNo { flashBox(.tdlxOld) }
    }

    @objc func btnSetupArduinoUSBLinkerClick(_ sender: TObject) {
        TfrmSetupArduinoUSBLinker.execute(portPaths: portPaths, port: portPath)
    }

    // MARK: - lists

    @objc func cbxComPortsCloseUp(_ sender: TObject) {
        let i = cbxComPorts.itemIndex
        guard i >= 0, i < portPaths.count else { return }
        portPath = portPaths[i]
        cbxComPorts.itemIndex = i
    }

    /// FUN_005D617C: refreshes the list of serial ports.
    @objc func cbxComPortsDropDown(_ sender: TObject) {
        guard let m = main else { return }
        m.ports.refresh()
        portPaths = m.ports.paths
        cbxComPorts.items = m.ports.names
        cbxComPorts.itemIndex = portPaths.firstIndex(of: portPath) ?? -1
    }

    @objc func cbxInitialISPFlashClick(_ sender: TObject) {
        ccbxRBBXFlashBaudrate.visible = !cbxInitialISPFlash.checked
        lblAtmegaInterfaceFlashBaudrate.visible = !cbxInitialISPFlash.checked
    }

    @objc func ccbArduinoBoardsChange(_ sender: TObject) {
        if let b = board, let i = ccbxArduinoBaudrates.items.firstIndex(of: String(b.baud)) {
            ccbxArduinoBaudrates.itemIndex = i
        }
        setBoardHints()
    }

    // empty in BLHeliSuite as well (0x633EBC, 0x633EC0, 0x63434C)
    @objc func ccbArduinoBoardsCloseUp(_ sender: TObject) { /* empty in BLHeliSuite (0x633EBC) */ }
    @objc func ccbArduinoBoardsDropDown(_ sender: TObject) { /* empty in BLHeliSuite (0x633EC0) */ }
    @objc func imgArduinoNanoClick(_ sender: TObject) { /* empty in BLHeliSuite (0x63434C) */ }

    // MARK: - pictures

    @objc func imgRBBXClick(_ sender: TObject) { main?.shellOpen("https://www.google.com/search?q=Robbe+LCD+ROXXY+PROGRAMMER+V2") }
    @objc func imgT160ABoxClick(_ sender: TObject) {
        main?.shellOpen("https://www.google.com/search?q=Turnigy+160A+1:8th+Scale+Sensorless+ESC+Programming+Box")
    }
    @objc func imgTAQXClick(_ sender: TObject) { main?.shellOpen("https://www.google.com/search?q=Turnigy+AquaStar+Water+Cooled+ESC+Program+Box") }
    @objc func imgTDLXClick(_ sender: TObject) {
        main?.shellOpen("https://www.google.com/search?q=Turnigy+dlux+Programming+Box+w/Data+Logging+Feature")
    }
    @objc func imgTTTBoxClick(_ sender: TObject) {
        main?.shellOpen("https://www.google.com/search?q=Turnigy+TrackStar+Turbo+and+Waterproof+ESC+Programming+Box")
    }
}
