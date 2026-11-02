import AppKit
import VCL
import BLHeliCore

/// ESC channel record (Self+0x784 + n*0x18 in the original).
final class ESCSlot {
    var btn: TSpeedButton!
    var locked = false          // +0x04 "x"
    var dirDiff = false         // +0x05
    var throttleDiff = false    // +0x06
    var modeDiff = false        // +0x07 "m"
    var inSync = false          // +0x08
    var layoutDiff = false      // +0x09
    var found = false           // +0x0A
    var wrongBrand = false      // +0x0B "b"
    var foundBrand: UInt8 = 0   // +0x0C
    var selected = false        // +0x0D
    var signature = ""          // +0x10
    var deviceType: UInt8 = 0   // +0x14
    var bootVersion: UInt8 = 0x20 // +0x15
    /// +0x10 status text of the last operation (used in the Write/Flash summaries).
    var statusText: String { get { signature } set { signature = newValue } }

    func reset() {
        locked = false; dirDiff = false; throttleDiff = false; modeDiff = false; inSync = false
        layoutDiff = false; found = false; wrongBrand = false; foundBrand = 0; selected = false
        signature = ""; deviceType = 0; bootVersion = 0x20
    }
}

/// Main window – port of TfrmBLHeliSuiteMain (BLHeliSuite 16.7.14.9.0.2).
@objc(TfrmBLHeliSuiteMain) final class TfrmBLHeliSuiteMain: TfrmBLHeliSuiteMainOutlets {
    static let version = "16.7.14.9.0.2"

    // MARK: private fields of the original form
    var intf: IntfType = .none                 // +0x799
    var escNo: Int = 1                         // +0x798 current ESC (1…8)
    var slots: [ESCSlot] = (0...8).map { _ in ESCSlot() }   // index 1…8
    var blheli: [TBLHeli] = (0...8).map { _ in TBLHeli() }  // +0x858 + n*4
    var workspace = TBLHeli()                  // +0x78C setup shown in the ESC setup page
    var clipboard = TBLHeli()                  // +0x788 Copy/Paste
    var expertMode = false                     // +0x87C
    var checkedMultiESC = false                // +0x8D0
    var pageChangeDone = false                 // +0x8D1
    var firstIdleDone = false                  // +0x8B0
    var statusText = ""                        // +0x894
    var autoCheckForUpdates = 24               // +0x774
    var lastTimeCheckedUpdate = 0.0            // +0x898
    var manualPath = ""                        // +0x8CC
    var lastReadError = ""
    var readResult: ReadResult = .unknown      // +0x8BC
    let ini = TIniFile.shared                  // +0x8B4 interface settings
    let db: FirmwareDatabase? = try? FirmwareDatabase.shared()
    let ports = PortList()

    /// Interface objects (one per kind like in the original).
    let fourWay = SerialIntf(section: "AtmSil_4wif", defaultBaud: 38400)          // +0x8C4 TUniSerialInterface
    let blbCom = SerialIntf(section: "AtmelSiLabs_BLB", defaultBaud: 19200)       // +0x784 TBLBInterface
    let cf = SerialIntf(section: "Cleanflight", defaultBaud: 115200)              // +0x794 TFlightCtrlIntf
    let auLinker = SerialIntf(section: "AtmelArduinoUSBLinker", defaultBaud: 19200) // +0x770 TArduinoUSBLinker
    let tgyLinker = SerialIntf(section: "AtmelAfroUSBLinker", defaultBaud: 9600)  // +0x780 TStk500v2Interface
    let toolstick = ToolstickIntf()                                               // +0x790 TSiLabsSiUtils
    let avrdude = AVRDudeIntf()                                                   // +0x778 TAVRDude

    var serialIntf: SerialIntf? {
        switch intf {
        case .silC2_4wif, .silBLB4wif, .atmBLB4wif, .atmSK4wif: return fourWay
        case .silBLBCom, .atmBLBCom: return blbCom
        case .silBLBCF, .atmBLBCF: return cf
        case .atmSKAULinker: return auLinker
        case .atmSKTGYLinker: return tgyLinker
        default: return nil
        }
    }

    var current: TBLHeli { blheli[escNo] }   // FUN_00662CC8

    // MARK: - creation (TfrmBLHeliSuiteMain.Create, virt11 0x6632FC + FormCreate 0x66CB5C)

    override init(resource: String, owner: TForm? = nil) {
        super.init(resource: resource, owner: owner)
    }

    required init(frame: NSRect) { super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }

    @objc func FormCreate(_ sender: TObject) {
        Application.shared.title = "BLHeliSuite " + TfrmBLHeliSuiteMain.version
        formCaption = Application.shared.title
        for i in 1...8 {
            slots[i].btn = component("sbtnESC_\(i)")
        }
        mainMenu?.images = imlInterfaces
        edtGetStartAddress.text = "0x1A00"
        edtGetLength.text = String(0x1C00 - 0x1A00)

        func cap(_ a: TAction!, _ s: String) { a.caption = NL(s) }
        func hint(_ a: TAction!, _ s: String) { a.hint = NL(s) }
        cap(actAtmSaveSetupAsEEpromFile, "Save Setup as EEprom File")
        cap(actBLHeliProgrammingAdaptersManual, "Show BLHeli programming adapters manual (local pdf)")
        cap(actBLHeliRevisionCheckDisabled, "Disable BLHeli Revision check")
        cap(actCheckForUpdate, "Check for BLHeliSuite update")
        cap(actCheckForUpdateEnabled, "Daily check for BLHeliSuite updates")
        cap(actCheckMultiESC, "Check")
        cap(actConnect, "Connect")
        hint(actConnect, "Connect or disconnect Interface/Traget/ESC here")
        cap(actCopyBLHeli, "Copy")
        hint(actCopyBLHeli, "Copy current BLHeli paramter values to clipboard")
        cap(actDesignSimple, "Design simple")
        cap(actDeviceErasePage, "Erase Page")
        hint(actDeviceErasePage, "")
        cap(actDeviceEraseMultiplePages, "Erase Flash Pages")
        hint(actDeviceEraseMultiplePages, "")
        cap(actEditFuses, "Edit ATmega Fuses")
        hint(actEditFuses, "Show Fuse Editor Dialog for ATmega\\nusing AVRDude  ISP interface")
        cap(actEraseChip, "Erase Chip")
        hint(actEraseChip, "")
        cap(actExpertMode, "Expert Mode")
        hint(actExpertMode, "")
        cap(actFlashAnyFile, "Flash any File")
        hint(actFlashAnyFile, "Flash the target with any other Flash or EEprom Hex file")
        cap(actFlashBLHeli, "Flash BLHeli")
        hint(actFlashBLHeli, "Flash current ESC with BLHeli Hex file either choosen from build-in ressources or from file system...")
        cap(actFlashOther, "Flash Other")
        hint(actFlashOther, "Flash the target with BLheli or any other external Hex file")
        cap(actHowtoBuildaBLHeliBootloaderInterface, "Show Building a BLHeli bootloader interface with USB-UART board (local pdf)")
        cap(actIdentifyFlashMemory, "Identify ESC")
        cap(actLinkToAtmSil11pdf, "\"Operation manual for BLHeli SiLabs Rev11.x\" (pdf) ")
        cap(actLinkToAtmSil12pdf, "\"Operation manual for BLHeli SiLabs Rev12.x\" (pdf) ")
        cap(actLinkToAtmSil13pdf, "\"Operation manual for BLHeli SiLabs Rev13.x\" (pdf)")
        cap(actLinkToAtmSil14pdf, "\"Operation manual for BLHeli SiLabs Rev14.x\" (pdf)")
        cap(actLinkToBLHeli_S_16pdf, "\"Operation manual for BLHeli_S Rev16.x\" (pdf)")
        cap(actLinkToBLHeli_S_ESCs_supported, "\"ESCs supported by BLHeli_S\" (pdf)")
        cap(actLinkToBLHeliGitHub, "BLHeli source files at GitHub")
        cap(actLinkToESCs_supported, "\"ESCs supported by BLHeli SiLabs\" (pdf)")
        cap(actLinkToGovernorRpmTable, "\"Governor SiLabs\" (Governor RPM Excel table | .xls)")
        cap(actLinkToHFForum_BLHeli_Setup, "\"BLHeli-Setup - Q&&A / Discussion\" thread at Helifreak")
        cap(actLinkToHFForum_BLHeliForSil, "\"BLHeli for SiLabs ESCs\" Thread at HeliFreak")
        cap(actLinkToMyBLHeliThread, "\"My (DoubleCH) BLHeli thread\" at HeliFreak")
        cap(actLinkToRcgroupsBLheliSuiteThread, "\"BLHeli for Atmel and SiLabs, united by BLHeliSuite\" thread at RC Groups")
        cap(actLinkToSiLabs10pdf, "\"Operation manual for BLHeli SiLabs Rev10.x\" (pdf) ")
        cap(actLinkToSiLabs2pdf, "\"Operation manual for BLHeli SiLabs Rev2.x\" (pdf) ")
        cap(actLinkToSiLabs3pdf, "\"Operation manual for BLHeli SiLabs Rev3.x\" (pdf) ")
        cap(actLinkToSiLabs4pdf, "\"Operation manual for BLHeli SiLabs Rev4.x\" (pdf) ")
        cap(actLinkToSiLabs5pdf, "\"Operation manual for BLHeli SiLabs Rev5.x\" (pdf) ")
        cap(actLinkToSiLabs6pdf, "\"Operation manual for BLHeli SiLabs Rev6.x\" (pdf) ")
        cap(actLinkToSiLabs7pdf, "\"Operation manual for BLHeli SiLabs Rev7.0\" (pdf) ")
        cap(actLinkToSiLabs8pdf, "\"Operation manual for BLHeli SiLabs Rev8.x\" (pdf) ")
        cap(actLinkToSiLabs9pdf, "\"Operation manual for BLHeli SiLabs Rev9.x\" (pdf) ")
        cap(actLinktToBLHeliSuiteBlog, "Blog of latest BLHeliSuite revision ...")
        cap(actLogOn, "Enable log")
        cap(actLogStayOnTop, "Log stay on top")
        cap(actMergeMotorDir, "Sync motor direction to Multiple ESC")
        cap(actMergeThrottle, "Sync Min/Center/Max throttle to Multiple ESC")
        cap(actPasteBLHeli, "Paste")
        hint(actPasteBLHeli, "Paste BLHeli paramter values from clipboard")
        cap(actReadMem, "Read Memory")
        cap(actReadSetup, "Read Setup")
        hint(actReadSetup, "Get/Load Setup values from ESC.")
        cap(actReadSetupFromHexFile, "Read Setup From Hex File")
        cap(actReadSetupFromIniFile, "Read Setup from ini file")
        cap(actReadMultipleESCSetupFromIniFile, "Read MultipleESC Setup from ini file")
        cap(actRestartESC, "Restart ESC")
        hint(actRestartESC, "Starts ESC normal operation w/o dis- and reconnecting Lipo.")
        cap(actSaveSetupToIniFile, "Save Setup to ini file")
        cap(actSaveMultipleESCSetupToIniFile, "Save MultipleESC Setup to ini file")
        cap(actSelectValBackColor, "Select Value Background Colour")
        cap(actShow4wifPinout, "Show Pinout for 4w-if Interfaces (local pdf)")
        cap(actShow4wifProtocol, "Show info about 4w-if Interface Protocol  (local pdf)")
        cap(actShowAbout, "About...")
        cap(actShowBinaryFile, "Show binary File")
        cap(actShowBLHeliSuiteMultipleESCmode, "Show info about BLHeliSuite MultipleESC mode (local pdf)")
        cap(actShowHexFile, "Show hex File")
        hint(actShowHexFile, "Open a firmware hex File and view content in binary form.")
        cap(actShowHistory, "Show BLHeliSuite history(local pdf)")
        cap(actShowMakeArduinoISP, "Show how to make an ArduinoISP (local pdf)")
        cap(actShowSuccessMsg, "Show Success Infos")
        cap(actScreenshot, "Save Screenshot")
        cap(actTargetKeepReset, "Keep Reset Target")
        cap(actTargetRestart, "Restart Target")
        hint(actTargetRestart, "Starts ESC normal operation w/o dis- and reconnecting Lipo.")
        cap(actVerifyFlashMemory, "Verify flash memory")
        cap(actWriteMem, "Write Memory")
        cap(actWriteSetup, "Write Setup")
        hint(actWriteSetup, "Write/save the current setup values to ESC.")
        cbxAVRDudeBaudrates.hint = NL("Choose appropriate baud rate here")
        cbxAVRDudeComPorts.hint = NL("Choose available serial port here")
        cbxAVRDudeParaPorts.hint = NL("Choose available parallel port here")
        cbxAVRDudeProgs.hint = NL("Choose your programmer here")
        cbxComPorts.hint = NL("Choose available serial port here")
        cbxSerialBaudrate.hint = NL("Choose appropriate baud rate here")
        cbxUSBDevices.hint = NL("Choose available Tooltsick here")
        mniBrandAndInterface.caption = NL("Select ATMEL / SILABS Interface")
        mniESCSetup.caption = NL("ESC setup")
        mniESCTools.caption = NL("ESC tools")
        mniOptions.caption = NL("Options")
        mniHelp.caption = "?"
        mniBLHeliManualsLinks.caption = NL("BLHeli info")
        tbsESCSetup.caption = NL("ESC setup")
        tbsESCTable.caption = NL("ESC overview")
        tbsCFMotors.caption = NL("Motors")
        tbsExpertTools.caption = NL("Expert tools")
        tbsMakeInterfaces.caption = NL("Make interfaces")
        grb_MultipleESC.tag = 2000
        let images: [(TAction?, Int)] = [(act_A_Sil_C2_Toolstick_Intf, 10), (act_B_Sil_C2_4wif_Intf, 11), (act_C_Sil_BLB_Com_Intf, 12),
                                         (act_D_Sil_BLB_4wif_Intf, 13), (act_E_Sil_BLB_CF_Intf, 14), (act_1_Atm_BLB_Com_Intf, 1),
                                         (act_2_Atm_BLB_4wif_Intf, 2), (act_3_Atm_SK_4wif_Intf, 3), (act_4_Atm_SK_AULinker_Intf, 4),
                                         (act_5_Atm_SK_TGYLinker_Intf, 5), (act_6_Atm_BLB_CF_Intf, 6), (act_X_Atm_Isp_Intf, 0x12)]
        for (a, i) in images { a?.imageIndex = i }
        let intfActions: [TAction?] = [act_A_Sil_C2_Toolstick_Intf, act_B_Sil_C2_4wif_Intf, act_C_Sil_BLB_Com_Intf, act_D_Sil_BLB_4wif_Intf,
                                       act_E_Sil_BLB_CF_Intf, act_1_Atm_BLB_Com_Intf, act_2_Atm_BLB_4wif_Intf, act_3_Atm_SK_4wif_Intf,
                                       act_4_Atm_SK_AULinker_Intf, act_5_Atm_SK_TGYLinker_Intf, act_6_Atm_BLB_CF_Intf, act_X_Atm_Isp_Intf]
        for (i, a) in intfActions.enumerated() { a?.caption = IntfType.captions[i] }
        grbSpecialCommands.caption = NL("Special commands")
        grbHexFileTools.caption = NL("Hex && bin file tools")
        grbMemAccess.caption = NL("Memory access")
        rgpMemType.caption = NL("Memory type")
        grbWriteMem.caption = NL("Write memory")
        grbReadMem.caption = NL("Read memory")
        lblWriteMemStart.caption = NL("Start")
        lblReadMemStart.caption = NL("Start")
        lblReadMemStop.caption = NL("Stop")
        lblReadMemLength.caption = NL("Length")
        lblWriteMemHexBytesToWrite.caption = NL("Hex bytes to write")
        cbxPersistFlashWriteMem.caption = NL("Persist flash")
        btnConstruction.visible = false
        fraESCCombos1.attach(self)
        fraESCTable1.attach(self)
        fraMakeInterfaces1.attach(self)
        restoreStoredValues()
        resetSlots(1, 8)    // FUN_00678344
    }

    // MARK: - form storage (JvFormStorage, section "frmBLHeliSuiteMain")

    let storageSection = "frmBLHeliSuiteMain"

    func restoreStoredValues() {
        let s = storageSection
        let props: [(TAction?, String)] = [(actShowSuccessMsg, "actShowSuccessMsg"), (actExpertMode, "actExpertMode"),
                                           (actLogStayOnTop, "actLogStayOnTop"), (actLogOn, "actLogOn"), (actDesignSimple, "actDesignSimple"),
                                           (actBLHeliRevisionCheckDisabled, "actBLHeliRevisionCheckDisabled"),
                                           (actMergeMotorDir, "actMergeMotorDir"), (actMergeThrottle, "actMergeThrottle")]
        for (a, n) in props {
            guard let a else { continue }
            a.checked = ini.readBool(s, n + ".Checked", a.checked)
        }
        let i = ini.readInteger(s, "Interface", 0)
        intf = .none
        pendingInterface = IntfType(rawValue: UInt8(max(0, min(12, i)))) ?? .none
        ValueColors.avr = TColor(truncatingIfNeeded: ini.readInteger(s, "AVRBackgroundColor", Int(ValueColors.avr)))
        ValueColors.silabs = TColor(truncatingIfNeeded: ini.readInteger(s, "SiLabsBackgroundColor", Int(ValueColors.silabs)))
        ValueColors.silabsS = TColor(truncatingIfNeeded: ini.readInteger(s, "SiLabsSBackgroundColor", Int(ValueColors.silabsS)))
        avrdude.programmer = ini.readString(s, "AVRDudeProgrammer", "usbasp")
        autoCheckForUpdates = ini.readInteger(s, "AutoCheckForUpdates", autoCheckForUpdates)
        expertMode = actExpertMode.checked
        Globals.revisionCheckDisabled = actBLHeliRevisionCheckDisabled.checked
    }

    var pendingInterface: IntfType = .none

    func saveStoredValues() {
        let s = storageSection
        let props: [(TAction?, String)] = [(actShowSuccessMsg, "actShowSuccessMsg"), (actExpertMode, "actExpertMode"),
                                           (actLogStayOnTop, "actLogStayOnTop"), (actLogOn, "actLogOn"), (actDesignSimple, "actDesignSimple"),
                                           (actBLHeliRevisionCheckDisabled, "actBLHeliRevisionCheckDisabled"),
                                           (actMergeMotorDir, "actMergeMotorDir"), (actMergeThrottle, "actMergeThrottle")]
        for (a, n) in props { if let a { ini.writeBool(s, n + ".Checked", a.checked) } }
        ini.writeInteger(s, "Interface", Int(intf.rawValue))
        ini.writeInteger(s, "AVRBackgroundColor", Int(ValueColors.avr))
        ini.writeInteger(s, "SiLabsBackgroundColor", Int(ValueColors.silabs))
        ini.writeInteger(s, "SiLabsSBackgroundColor", Int(ValueColors.silabsS))
        ini.writeString(s, "AVRDudeProgrammer", avrdude.programmer)
        ini.writeInteger(s, "AutoCheckForUpdates", autoCheckForUpdates)
        if let w = formWindow {
            ini.writeInteger(s, "Left", Int(w.frame.minX))
            ini.writeInteger(s, "Top", Int(w.frame.minY))
        }
    }

    @objc func FormClose(_ sender: TObject, _ args: TCloseArgs) {
        disconnectAll()    // FUN_0066483C
        if pgcMain.activePage === tbsCFMotors { fraCFMotorTest1.stopMotors() }
        saveStoredValues()
    }

    // MARK: - connection state (FUN_00671E60, FUN_00671F04, FUN_00663C6C, FUN_00675438)

    /// Interface connected.
    var intfConnected: Bool {
        switch intf {
        case .silC2Toolstick: return toolstick.connected
        case .atmISP: return avrdude.connected
        case .none: return false
        default: return serialIntf?.connected ?? false
        }
    }

    /// Interface supports the Multiple ESC mode (4way-if or flight controller).
    var multiESCCapable: Bool {
        guard intfConnected else { return false }
        if intf.isFourWay { return fourWay.escCount > 1 || fourWay.isFourWayBox }
        return intf.isCF
    }

    /// Target ESC connected.
    var escConnected: Bool {
        switch intf {
        case .silC2Toolstick: return toolstick.targetConnected
        case .atmISP: return avrdude.targetConnected
        case .none: return false
        default: return serialIntf?.targetConnected ?? false
        }
    }

    /// Number of ESC channels (FUN_00675438).
    var escCount: Int {
        guard multiESCCapable else { return 1 }
        switch intf {
        case .silC2_4wif, .silBLB4wif, .atmBLB4wif, .atmSK4wif: return max(1, fourWay.escCount)
        case .silBLBCF, .atmBLBCF: return max(1, cf.escCount)
        default: return 1
        }
    }

    /// FUN_0066F27C: number of selected ESC.
    var selectedCount: Int { (1...8).filter { slots[$0].selected }.count }
    /// FUN_0066F2D4: first selected ESC or 0.
    var firstSelected: Int { (1...8).first { slots[$0].selected } ?? 0 }
    /// FUN_0066F29C: master ESC.
    var masterESC: Int {
        let f = firstSelected
        if f != 0 { return f }
        return (1...8).first { slots[$0].found } ?? 1
    }

    // MARK: - status bar (FUN_00673108)

    func setStatus(_ s: String) {
        statusText = s
        stbMain.setPanelText(0, s)
        stbMain.display()
    }

    // MARK: - interface selection (InterfaceSelectExecute 0x661858 / FUN_00673234)

    @objc func InterfaceSelectExecute(_ sender: TObject) {
        let list: [(TAction?, IntfType)] = [(act_A_Sil_C2_Toolstick_Intf, .silC2Toolstick), (act_B_Sil_C2_4wif_Intf, .silC2_4wif),
                                            (act_C_Sil_BLB_Com_Intf, .silBLBCom), (act_D_Sil_BLB_4wif_Intf, .silBLB4wif),
                                            (act_E_Sil_BLB_CF_Intf, .silBLBCF), (act_1_Atm_BLB_Com_Intf, .atmBLBCom),
                                            (act_2_Atm_BLB_4wif_Intf, .atmBLB4wif), (act_3_Atm_SK_4wif_Intf, .atmSK4wif),
                                            (act_4_Atm_SK_AULinker_Intf, .atmSKAULinker), (act_5_Atm_SK_TGYLinker_Intf, .atmSKTGYLinker),
                                            (act_6_Atm_BLB_CF_Intf, .atmBLBCF), (act_X_Atm_Isp_Intf, .atmISP)]
        if let (_, t) = list.first(where: { $0.0 === sender }) { selectInterface(t) }
    }

    func selectInterface(_ t: IntfType) {
        if t != intf {
            var disconnect = true
            if intf == .silBLBCF { disconnect = t != .atmBLBCF } else if intf == .atmBLBCF { disconnect = t != .silBLBCF }
            if disconnect {
                disconnectInterface()    // FUN_00664A08
            } else {
                resetSlots(1, 8)
                checkedMultiESC = false
            }
            beginUpdate()
            intf = t
            tbsCFMotors.tabVisible = intf.isCF
            let brand = intf.brand
            if brand != Brand.current {
                Brand.current = brand
                for a in aclMain.actions {
                    let cap = a.caption
                    if brand == 1 {
                        if cap.contains("SILABS") { a.visible = true }
                        if cap.contains("ATMEL") { a.visible = false }
                    } else {
                        if cap.contains("ATMEL") { a.visible = true }
                        if cap.contains("SILABS") { a.visible = false }
                    }
                }
                workspace.clear(isS: false)
                current.clear(isS: false)
                clipboard.clear(isS: false)
                let manuals: [TAction?] = [actLinkToAtmSil11pdf, actLinkToAtmSil12pdf, actLinkToAtmSil13pdf, actLinkToAtmSil14pdf, actLinkToESCs_supported]
                if brand == 1 {
                    tbsESCSetup.caption = "SiLabs ESC Setup"
                    actLinkToBLHeli_S_16pdf.visible = true
                    actLinkToBLHeli_S_ESCs_supported.visible = false
                    actAtmSaveSetupAsEEpromFile.visible = false
                    for a in manuals { a?.caption = (a?.caption ?? "").replacingOccurrences(of: "Atmel", with: "SiLabs") }
                } else if brand == 2 {
                    tbsESCSetup.caption = "Atmel ESC Setup"
                    actLinkToBLHeli_S_16pdf.visible = false
                    actLinkToBLHeli_S_ESCs_supported.visible = false
                    actAtmSaveSetupAsEEpromFile.visible = true
                    for a in manuals { a?.caption = (a?.caption ?? "").replacingOccurrences(of: "SiLabs", with: "Atmel") }
                }
                setStatus("Loading ESC Data...")
                if db != nil {
                    setStatus("ESC Data loaded.")
                } else {
                    setStatus("Loading ESC Data FAILED.")
                    intf = .none
                }
            }
            rgpMemType.items = []
            grbReadMem.visible = true
            actRestartESC.visible = intf.rawValue < 2
            actFlashBLHeli.visible = true
            actDeviceErasePage.enabled = intf.rawValue < 5
            switch intf {
            case .silC2Toolstick:
                rgpMemType.items = ["Flash"]; rgpMemType.setItemIndex(0); actConnect.visible = true
            case .silC2_4wif, .silBLBCom, .silBLB4wif, .silBLBCF:
                rgpMemType.items = ["Flash"]; rgpMemType.setItemIndex(0); actConnect.visible = true
                fillComPorts(false)
            case .atmBLBCom, .atmBLBCF, .atmBLB4wif, .atmSK4wif, .atmSKAULinker, .atmSKTGYLinker:
                rgpMemType.items = ["Flash", "EEprom"]; rgpMemType.setItemIndex(1); actConnect.visible = true
                fillComPorts(false)
            case .atmISP:
                rgpMemType.items = ["Flash", "EEprom"]; rgpMemType.setItemIndex(1); actConnect.visible = false
                cbxAVRDudeProgs.items = AVRDudeIntf.programmerNames
                cbxAVRDudeProgs.itemIndex = 0
                cbxAVRDudeParaPorts.items = []
                cbxAVRDudeComPorts.items = ports.names
                selectAVRDudeProgrammer(avrdude.programmer)
                cbxAVRDudeProgsChange(self)
            case .none:
                actFlashBLHeli.visible = false
                actDeviceErasePage.enabled = false
            }
            fillBaudrates()    // FUN_00674428
            if Brand.current == 1 {
                edtGetStartAddress.text = "0x1A00"
                edtGetLength.text = "112"
                edtGetStopAdress.text = "0x1A6F"
                edtSetStartAddress.text = "0x1DFF"
            } else if Brand.current == 2 {
                edtGetStartAddress.text = "0"
                edtGetLength.text = "0x200"
                edtGetStopAdress.text = "0x1FF"
                edtSetStartAddress.text = "0"
            }
            loadPortSettings()    // FUN_00673F14
            updateCaption()        // FUN_00674A84
            showESCData()          // FUN_006731D8
            pgcMainChange(self)
            endUpdate()
        }
        let acts: [(TAction?, IntfType)] = [(act_A_Sil_C2_Toolstick_Intf, .silC2Toolstick), (act_B_Sil_C2_4wif_Intf, .silC2_4wif),
                                            (act_C_Sil_BLB_Com_Intf, .silBLBCom), (act_D_Sil_BLB_4wif_Intf, .silBLB4wif),
                                            (act_E_Sil_BLB_CF_Intf, .silBLBCF), (act_1_Atm_BLB_Com_Intf, .atmBLBCom),
                                            (act_2_Atm_BLB_4wif_Intf, .atmBLB4wif), (act_3_Atm_SK_4wif_Intf, .atmSK4wif),
                                            (act_4_Atm_SK_AULinker_Intf, .atmSKAULinker), (act_5_Atm_SK_TGYLinker_Intf, .atmSKTGYLinker),
                                            (act_6_Atm_BLB_CF_Intf, .atmBLBCF), (act_X_Atm_Isp_Intf, .atmISP)]
        for (a, t) in acts { a?.checked = intf == t }
        refreshMenuBar()
    }

    var updateDepth = 0
    func beginUpdate() { updateDepth += 1 }
    func endUpdate() { updateDepth = max(0, updateDepth - 1) }

    // MARK: - ports and baud rates

    /// FUN_00676300: fills the port list (macOS device names instead of COM numbers).
    func fillComPorts(_ keepSelection: Bool) {
        ports.refresh()
        cbxComPorts.items = ports.names
        cbxAVRDudeComPorts.items = ports.names
        if let s = serialIntf {
            if let i = ports.index(of: s.portPath) { cbxComPorts.itemIndex = i }
            else if !ports.paths.isEmpty && !keepSelection {
                s.portPath = ports.preferredPath ?? ports.paths[0]
                cbxComPorts.itemIndex = ports.index(of: s.portPath) ?? 0
            }
        }
    }

    /// FUN_00674428.
    func fillBaudrates() {
        var list: [Int] = []
        switch intf {
        case .silC2_4wif, .silBLBCom, .silBLB4wif, .atmBLBCom, .atmBLB4wif, .atmSK4wif, .atmSKAULinker, .atmSKTGYLinker:
            list = expertMode ? BaudLists.expert : BaudLists.normal
        case .silBLBCF, .atmBLBCF:
            list = expertMode ? BaudLists.expert : BaudLists.cleanflight
        case .atmISP:
            cbxAVRDudeBaudrates.items = BaudLists.normal.map(String.init)
            return
        default:
            return
        }
        cbxSerialBaudrate.items = list.map(String.init)
    }

    /// FUN_00673F14: interface settings of BLHeliSuite.ini.
    func loadPortSettings() {
        guard let s = serialIntf else { return }
        s.portPath = ini.readString(s.section, "ComPort", s.portPath)
        if intf != .atmSKTGYLinker && intf != .silBLBCom && intf != .atmBLBCom {
            s.baud = ini.readInteger(s.section, "Baudrate", s.defaultBaud)
        } else if intf == .atmSKTGYLinker {
            s.baud = 9600
        }
        if let i = ports.index(of: s.portPath) { cbxComPorts.itemIndex = i }
    }

    /// FUN_0067414C.
    func savePortSettings() {
        guard let s = serialIntf else { return }
        ini.writeString(s.section, "ComPort", s.portPath)
        if intf.isCF || intf == .atmSKAULinker { ini.writeInteger(s.section, "Baudrate", s.baud) }
    }

    @objc func cbxComPortsDropDown(_ sender: TObject) { fillComPorts(true) }

    @objc func cbxComPortsCloseUp(_ sender: TObject) {
        guard let s = serialIntf, cbxComPorts.itemIndex >= 0, cbxComPorts.itemIndex < ports.paths.count else { return }
        let p = ports.paths[cbxComPorts.itemIndex]
        if p != s.portPath {
            if s.connected { disconnectInterface() }
            s.portPath = p
            savePortSettings()
            updateCaption()
        }
    }

    @objc func cbxSerialBaudrateCloseUp(_ sender: TObject) {
        guard let s = serialIntf, let b = Int(cbxSerialBaudrate.text_) else { return }
        if b != s.baud {
            if s.connected { disconnectInterface() }
            s.baud = b
            savePortSettings()
        }
    }

    @objc func cbxUSBDevicesKeyPress(_ sender: TObject, _ args: TKeyArgs) { args.key = "\0" }

    @objc func cbxAVRDudeProgsChange(_ sender: TObject) {
        let i = cbxAVRDudeProgs.itemIndex
        guard i >= 0, i < AVRDudeIntf.programmers.count else { return }
        let p = AVRDudeIntf.programmers[i]
        avrdude.programmer = p.id
        avrdude.portType = p.portType
        cbxAVRDudeComPorts.visible = p.portType == 2
        cbxAVRDudeParaPorts.visible = p.portType == 1
        lblAVRDudePort.visible = p.portType == 1 || p.portType == 2
        cbxAVRDudeBaudrates.visible = p.portType == 2
        lblAVRDudeBaudrate.visible = p.portType == 2
        updateCaption()
    }

    func selectAVRDudeProgrammer(_ id: String) {
        if let i = AVRDudeIntf.programmers.firstIndex(where: { $0.id == id }) { cbxAVRDudeProgs.itemIndex = i }
    }

    @objc func cbxAVRDudeProgsCloseUp(_ sender: TObject) {
        if avrdudeProgsWidth > 0 { cbxAVRDudeProgs.width = avrdudeProgsWidth }
        cbxAVRDudeProgsChange(sender)
    }
    @objc func cbxAVRDudeProgsKeyPress(_ sender: TObject, _ args: TKeyArgs) { args.key = "\0" }

    @objc func cbxAVRDudeBaudratesChange(_ sender: TObject) {
        if let b = Int(cbxAVRDudeBaudrates.text_) { avrdude.baud = b }
    }

    @objc func cbxAVRDudeComPortsDropDown(_ sender: TObject) {
        ports.refresh()
        cbxAVRDudeComPorts.items = ports.names
    }

    @objc func cbxAVRDudeComPortsCloseUp(_ sender: TObject) {
        let i = cbxAVRDudeComPorts.itemIndex
        if i >= 0 && i < ports.paths.count { avrdude.port = ports.paths[i]; updateCaption() }
    }

    /// cbxAVRDudeParaPortsCloseUp (0x663234): parallel port programmers (no LPT ports on a Mac).
    @objc func cbxAVRDudeParaPortsCloseUp(_ sender: TObject) { updateCaption() }

    // MARK: - caption (FUN_00674A84)

    func updateCaption() {
        let title = Application.shared.title
        let ic = intf.caption
        var c: String
        switch intf {
        case .silC2Toolstick:
            c = intfConnected ? title + " [" + ic + ": " + toolstick.deviceName + "]" : title + " [" + ic + "]"
        case .atmISP:
            c = title + " [" + ic + " \"" + avrdude.programmer + "\" "
            switch avrdude.portType {
            case 1: c += "@LPT1"
            case 2: c += "@" + PortList.shortName(avrdude.port) + "|\(avrdude.baud)"
            case 3: c += "@USB"
            default: break
            }
            c += "]"
        case .none:
            c = title
        default:
            let s = serialIntf!
            let port = s.portPath.isEmpty ? "" : " @" + PortList.shortName(s.portPath)
            if intfConnected && !s.deviceName.isEmpty {
                c = title + " [" + ic + ": " + s.deviceName + port + "]"
            } else {
                c = title + " [" + ic + port + "]"
            }
        }
        formCaption = c
        actConnect.caption = NL(intfConnected ? "Disconnect" : "Connect")
        layoutBottom()      // FUN_00672BB0
        updateESCButtonsVisible()   // FUN_0067629C
        updateESCButtons()  // FUN_00675740
    }

    // MARK: - bottom panels (FUN_00672BB0)

    func layoutBottom() {
        let page = pgcMain.activePage
        let notSetup = page !== tbsESCSetup
        let isTable = page === tbsESCTable
        let isMotors = page === tbsCFMotors
        let isMake = page === tbsMakeInterfaces
        tbsESCTable.tabVisible = multiESCCapable
        pnlBottomButtons.height = notSetup ? 1 : 0x2A
        pnlBottom.height = isMake ? 1 : 0x46
        let h = pnlBottom.height - stbMain.height - 2
        if pnlBottomLeftISP.height != h {
            pnlBottomLeftISP.height = h
            pnlBottomLeftSerial.height = h
            pnlBottomConnect.height = h
            pnlBottomLeftToolstick.height = h
        }
        pnlBottomLeftISP.top = 1
        pnlBottomLeftSerial.top = 1
        pnlBottomConnect.top = 1
        pnlBottomLeftToolstick.top = 1
        grb_MultipleESC.visible = multiESCCapable
        pnlBottomConnect.visible = !(isMake || isMotors)
        switch intf {
        case .silC2Toolstick:
            pnlBottomLeftISP.visible = false
            pnlBottomLeftSerial.visible = false
            pnlBottomLeftToolstick.visible = !isMake
            pnlBottomLeftToolstick.left = 1
            pnlBottomConnect.left = pnlBottomLeftToolstick.left + pnlBottomLeftToolstick.width
        case .silC2_4wif, .silBLB4wif, .atmBLB4wif, .atmSK4wif:
            pnlBottomLeftISP.visible = false
            pnlBottomLeftToolstick.visible = false
            pnlBottomLeftSerial.visible = true
            pnlBottomLeftSerial.left = 1
            pnlBottomConnect.left = pnlBottomLeftSerial.left + pnlBottomLeftSerial.width + 2
            cbxSerialBaudrate.visible = true
            cbxSerialBaudrate.enabled = false
            lblSeriallBaud.visible = true
            if multiESCCapable { grb_MultipleESC.left = pnlBottomConnect.left + pnlBottomConnect.width + 1 }
        case .silBLBCom, .atmBLBCom:
            pnlBottomLeftISP.visible = false
            pnlBottomLeftToolstick.visible = false
            pnlBottomLeftSerial.left = 1
            pnlBottomConnect.left = pnlBottomLeftSerial.left + pnlBottomLeftSerial.width + 2
            pnlBottomLeftSerial.visible = true
            cbxSerialBaudrate.enabled = false
        case .silBLBCF, .atmBLBCF:
            pnlBottomLeftISP.visible = false
            pnlBottomLeftToolstick.visible = false
            pnlBottomLeftSerial.left = 1
            pnlBottomConnect.left = pnlBottomLeftSerial.left + pnlBottomLeftSerial.width + 2
            pnlBottomLeftSerial.visible = true
            cbxSerialBaudrate.enabled = true
            if !multiESCCapable { grb_MultipleESC.visible = false } else {
                grb_MultipleESC.visible = true
                grb_MultipleESC.left = pnlBottomConnect.left + pnlBottomConnect.width + 1
            }
        case .atmSKAULinker, .atmSKTGYLinker:
            pnlBottomLeftISP.visible = false
            pnlBottomLeftToolstick.visible = false
            pnlBottomLeftSerial.left = 1
            pnlBottomConnect.left = pnlBottomLeftSerial.left + pnlBottomLeftSerial.width + 2
            pnlBottomLeftSerial.visible = true
            cbxSerialBaudrate.visible = true
            lblSeriallBaud.visible = true
            cbxSerialBaudrate.enabled = intf == .atmSKAULinker
        case .atmISP:
            pnlBottomConnect.visible = false
            pnlBottomLeftToolstick.visible = false
            pnlBottomLeftSerial.visible = false
            pnlBottomLeftISP.left = 1
            pnlBottomLeftISP.visible = !isMake
        case .none:
            pnlBottomLeftISP.visible = false
            pnlBottomLeftSerial.visible = false
            pnlBottomLeftToolstick.visible = false
        }
        actMergeMotorDir.enabled = multiESCCapable && !(notSetup && !isTable)
        actMergeThrottle.enabled = multiESCCapable && !(notSetup && !isTable)
    }

    // MARK: - window size per page (FUN_006747DC)

    func adjustFormSize() {
        let page = pgcMain.activePage
        var w = pgcMain.width - (page?.width ?? 0)
        var h = pgcMain.height - (page?.height ?? 0)
        if page === tbsESCSetup {
            w += fraESCCombos1.width; h += fraESCCombos1.height
        } else if page === tbsESCTable {
            w += fraESCTable1.width; h += fraESCTable1.height
        } else if page === tbsExpertTools {
            w += pnlExpertTools.width; h += pnlExpertTools.height
        } else if page === tbsCFMotors {
            w += fraCFMotorTest1.width; h += fraCFMotorTest1.height
        } else if page === tbsMakeInterfaces {
            w += fraMakeInterfaces1.width; h += fraMakeInterfaces1.height
        } else {
            w += 0x1A4; h += 0x2F8
        }
        // pgcMain is aligned inside pnlMain; keep the frame size exact
        let pw = w + (pnlMain.width - pgcMain.width)
        let ph = h + (pnlMain.height - pgcMain.height)
        if pnlMain.width != pw || pnlMain.height != ph {
            pnlMain.setBounds(pnlMain.left, pnlMain.top, pw, ph)
        }
        let cw = pnlMain.left + pw
        let ch = pnlMain.top + ph + pnlBottom.height + pnlBottomButtons.height
        if clientWidth != cw || clientHeight != ch {
            setClientSize(cw, ch)
            if let win = formWindow {
                win.contentMinSize = win.contentRect(forFrameRect: win.frame).size
                win.contentMaxSize = win.contentMinSize
            }
        }
    }

    // MARK: - page control (pgcMainChange 0x66F988 / pgcMainChanging 0x66FCC4)

    @objc func pgcMainChanging(_ sender: TObject, _ args: TBoolArgs) {
        if pgcMain.activePage === tbsCFMotors {
            fraCFMotorTest1.stopMotors()
            updateCaption()
        }
    }

    @objc func pgcMainChange(_ sender: TObject) {
        let page = pgcMain.activePage
        let isSetup = page === tbsESCSetup
        let isTable = page === tbsESCTable
        beginUpdate()
        mniESCSetup.enabled = isTable || isSetup
        mniESCTools.enabled = isTable || isSetup
        actDesignSimple.enabled = isSetup
        actSelectValBackColor.enabled = isSetup
        actShowSuccessMsg.enabled = isTable || isSetup
        if page === tbsMakeInterfaces {
            disconnectAll()
            fraMakeInterfaces1.prepare(port: serialIntf?.portPath ?? ports.preferredPath ?? "")
        }
        if page === tbsCFMotors {
            disconnectInterface()
            fraCFMotorTest1.prepare(cf)
        }
        layoutBottom()
        if isSetup || isTable { showESCData() }
        adjustFormSize()
        refreshMenuBar()
        endUpdate()
    }

    /// FUN_006731D8: shows the data of the current ESC (setup page or ESC table).
    func showESCData() {
        if pgcMain.activePage !== tbsESCSetup {
            fraESCTable1.update(self, syncDir: actMergeMotorDir.checked, syncThrottle: actMergeThrottle.checked, count: escCount)
        } else {
            fraESCCombos1.show(escNo: escNo)
        }
        adjustFormSize()
    }

    // MARK: - idle (evtAppIdle 0x671FD0)

    @objc func evtAppIdle(_ sender: TObject) {
        let connectedAny = selectedCount == 1 || (!multiESCCapable && intfConnected)
        var portOK = (escConnected || intf != .silC2Toolstick) ? true : !cbxUSBDevices.text_.isEmpty
        switch intf {
        case .silC2Toolstick:
            portOK = !cbxUSBDevices.text_.isEmpty
        case .atmISP:
            break
        case .none:
            portOK = false
        default:
            if let s = serialIntf {
                if let i = ports.index(of: s.portPath), cbxComPorts.itemIndex != i { cbxComPorts.itemIndex = i }
                if cbxSerialBaudrate.text_ != String(s.baud) { cbxSerialBaudrate.text_ = String(s.baud) }
                lblSeriallBaud.caption = "Baud:"
                portOK = !s.portPath.isEmpty
            }
        }
        actCheckMultiESC.enabled = portOK
        if intf.rawValue < 2 && escConnected && connectedAny {
            actTargetRestart.enabled = true
            actRestartESC.enabled = true
            actTargetKeepReset.enabled = true
        } else {
            actTargetRestart.enabled = false
            actRestartESC.enabled = false
            actTargetKeepReset.enabled = false
        }
        actIdentifyFlashMemory.enabled = true
        tbsExpertTools.tabVisible = expertMode
        actWriteSetup.enabled = portOK && workspace.isValid && !workspace.isFlashFailed && selectedCount > 0
        actReadSetup.enabled = portOK
        actFlashBLHeli.enabled = portOK
        actFlashOther.enabled = portOK
        actEraseChip.enabled = connectedAny && portOK
        actReadMem.enabled = connectedAny && portOK
        actWriteMem.enabled = connectedAny && portOK
        actDeviceErasePage.enabled = portOK && intf.rawValue <= 4 && connectedAny
        actDeviceEraseMultiplePages.enabled = portOK && intf.rawValue <= 4 && connectedAny
        actFlashAnyFile.enabled = connectedAny && portOK
        actAtmSaveSetupAsEEpromFile.enabled = workspace.isValid
        actSaveSetupToIniFile.enabled = workspace.isValid
        actReadMultipleESCSetupFromIniFile.enabled = multiESCCapable
        actSaveMultipleESCSetupToIniFile.enabled = workspace.isValid && multiESCCapable
        actConnect.enabled = portOK
        actEditFuses.enabled = portOK && intf == .atmISP
        actCheckForUpdateEnabled.checked = autoCheckForUpdates > 0
        if !firstIdleDone {
            firstIdleDone = true
            let t = pendingInterface
            intf = .none
            selectInterface(t)
            if let w = formWindow, w.isVisible == false { show() }
        }
    }

    @objc func evtAppHelp(_ sender: TObject) { /* 0x671F6C: HtmlHelp(Application.HelpFile, control.HelpContext) – BLHeliSuite ships no help file */ }

    // MARK: - ESC buttons (FUN_00675740, FUN_0067629C, sbtnESC_MouseDown 0x66F6EC)

    /// FUN_006754D0: clears the ESC channel records first…last.
    func resetSlots(_ first: Int, _ last: Int) {
        for i in 1...8 where (i >= first && i <= last) || i > escCount {
            blheli[i].clear(isS: blheli[i].isS)
            slots[i].btn?.hint = ""
            slots[i].btn?.caption = ""
            slots[i].reset()
        }
        updateESCButtons()
        selectESC(masterESC, load: true)    // FUN_00672B78
    }

    /// FUN_006755C4: compares the setups of the other ESC with the master.
    func compareWithMaster() {
        let m = firstSelected
        for i in 1...8 {
            let s = slots[i]
            s.btn?.hint = ""
            s.btn?.caption = ""
            s.dirDiff = false; s.throttleDiff = false; s.modeDiff = false; s.inSync = false; s.layoutDiff = false
            if m != 0 && i != m && blheli[i].isValid && blheli[m].isValid {
                let a = blheli[i], b = blheli[m]
                s.dirDiff = a.value(.direction) != b.value(.direction)
                s.throttleDiff = !a.sameAs(b, compareName: false, syncThrottle: true, syncDirection: false, db)
                s.modeDiff = a.mode != b.mode
                s.inSync = a.sameAs(b, compareName: false, syncThrottle: actMergeThrottle.checked, syncDirection: actMergeMotorDir.checked, db)
                s.layoutDiff = a.value(.layoutRevision) != b.value(.layoutRevision)
            }
        }
    }

    func updateESCButtonsVisible() {
        guard multiESCCapable else { return }
        let n = escCount
        for i in 1...8 { slots[i].btn?.visible = i <= n }
    }

    func updateESCButtons() {
        guard multiESCCapable else { return }
        compareWithMaster()
        let master = masterESC
        for i in 1...8 {
            let s = slots[i]
            guard let b = s.btn else { continue }
            let bl = blheli[i]
            b.font.style = [.fsBold]
            b.font.height = -17
            if !s.found {
                b.caption = s.selected ? "?" : ""
            } else if s.locked {
                b.caption = "x"
            } else if bl.isFlashFailed {
                b.caption = "f"
            } else if s.wrongBrand {
                b.caption = "b"
            } else if !bl.isValid {
                b.caption = "u"
            } else if s.selected {
                b.caption = "\(i)"
            } else {
                b.caption = s.modeDiff ? "m" : ".."
            }
            var h = DFormat("ESC#%d: ", [i])
            if !s.selected {
                h += NL("deselected\\n\\n")
                b.font.color = 0x808080
            } else if bl.isFlashFailed || s.wrongBrand {
                b.font.color = 0xFF0000
            } else if !bl.isValid {
                b.font.color = 0xFF0000
            } else if i == master {
                h += NL("[MASTER]\\n\\n")
                b.font.color = 0xFF0000
            } else {
                h += NL("[SLAVE]\\n\\n")
                if s.inSync {
                    h += "Setup in Sync with Master"
                    if s.dirDiff {
                        h += NL("\\n     -> Motor Direction: ") + bl.valueText(.direction, bl.value(.direction), db)
                        b.font.color = 0x4080FF
                    } else {
                        b.font.color = 0x8000
                    }
                    if s.throttleDiff { h += NL("\\n     -> Min/Center/Max Throttle diff") }
                } else if s.layoutDiff {
                    h += "EEprom Layout different from Master"
                    b.font.color = 0x9D009D
                } else {
                    h += "Setup NOT in Sync with Master"
                    b.font.color = 0x808080
                }
                h += NL("\\n\\n")
            }
            if !bl.isValid {
                if s.locked {
                    h += " Unknown firmware (Memory is locked)"
                } else if s.wrongBrand {
                    h += DFormat(" Found %s (expected %s)", [Brand.name(s.foundBrand), Brand.name(Brand.current)])
                } else if !s.found {
                    h += " No ESC Found"
                } else if s.bootVersion < 0x65 {
                    h += DFormat(" Found %s: Erased or of unknown firmware", [Brand.name(s.foundBrand)])
                } else {
                    h += " BLHeli_32 ESC? Use BLHeliSuite32!"
                }
            } else {
                if s.modeDiff { h += NL("ESC Mode different from Master\\n\\n") }
                h += bl.shortInfo()
            }
            if s.found {
                h += NL("\\n\\n") + (Int(s.deviceType) < deviceTypeNames.count ? deviceTypeNames[Int(s.deviceType)] : "") + " " + s.signature
            }
            h += DFormat(NL("\\n\\nLeft click adds ESC#%d to Multiple ESC configuration.\\nRight click selects ESC#%d as a Single target."), [i, i])
            b.hint = h
            b.needsDisplay = true
        }
        let sel = selectedCount
        if sel == 1 {
            grb_MultipleESC.caption = DFormat("Single ESC#%d", [master])
        } else if sel < 2 {
            grb_MultipleESC.caption = NL("Multiple ESC")
        } else {
            grb_MultipleESC.caption = DFormat("Multiple ESC / Master#%d", [master])
        }
        if pgcMain.activePage !== tbsESCSetup {
            fraESCTable1.update(self, syncDir: actMergeMotorDir.checked, syncThrottle: actMergeThrottle.checked, count: escCount)
        }
    }

    @objc func sbtnESC_MouseDown(_ sender: TObject, _ args: TMouseArgs) {
        guard let btn = sender as? TSpeedButton, let n = (1...8).first(where: { slots[$0].btn === btn }) else { return }
        let master = masterESC
        if !blheli[master].isValid || blheli[master].isFlashFailed { slots[master].selected = false }
        if args.button == .mbRight {
            for i in 1...8 { slots[i].selected = false }
            slots[n].selected = true
        } else if args.button == .mbLeft {
            if !args.shift.contains(.ssShift) {
                if !slots[n].selected {
                    compareWithMaster()
                    if blheli[n].isValid && !blheli[n].isFlashFailed && !slots[n].modeDiff { slots[n].selected = true }
                } else {
                    slots[n].selected = false
                }
            } else {
                for i in 1...8 { slots[i].selected = false }
                slots[master].selected = true
                if master + 1 <= n {
                    for i in (master + 1)...n where blheli[i].isValid && !blheli[i].isFlashFailed && !slots[i].modeDiff {
                        slots[i].selected = true
                    }
                }
            }
        }
        let m2 = masterESC
        selectESC(m2, load: master != m2)
        updateESCButtons()
    }

    /// FUN_00672B78: makes `n` the current ESC (optionally loading its setup into the workspace).
    func selectESC(_ n: Int, load: Bool) {
        if n != escNo { escNo = n }
        if load {
            current.assign(to: workspace)
            showESCData()
        }
        updateCopyPaste()
    }

    // MARK: - Copy / Paste (FUN_00674508, actCopyBLHeliExecute, actPasteBLHeliExecute)

    func updateCopyPaste() {
        guard multiESCCapable else { return }
        guard selectedCount == 1 else {
            actCopyBLHeli.visible = false
            actPasteBLHeli.visible = false
            return
        }
        if clipboard.isValid && workspace.isValid && !workspace.isFlashFailed && clipboard.mode == workspace.mode
            && !clipboard.sameAs(workspace, compareName: false, syncThrottle: actMergeThrottle.checked, syncDirection: actMergeMotorDir.checked, db) {
            actPasteBLHeli.visible = true
            actPasteBLHeli.hint = NL("Paste:") + "\r\n" + clipboard.dumpText(db)
        } else {
            actPasteBLHeli.visible = false
        }
        if !workspace.isValid {
            actCopyBLHeli.visible = false
        } else {
            actCopyBLHeli.visible = true
            btnCopyBLHeli.font.color = clBtnText
            if !clipboard.isValid {
                actCopyBLHeli.hint = NL("Copy current BLHeli paramter values to clipboard")
            } else {
                let same = clipboard.sameAs(workspace, compareName: false, syncThrottle: actMergeThrottle.checked, syncDirection: actMergeMotorDir.checked, db)
                btnCopyBLHeli.font.color = same ? 0x8000 : clBtnText
                actCopyBLHeli.hint = NL("Clipboard:") + "\r\n" + clipboard.dumpText(db)
            }
        }
    }

    @objc func actCopyBLHeliExecute(_ sender: TObject) {
        clipboard.clear(isS: false)
        workspace.assign(to: clipboard)
        updateCopyPaste()
    }

    @objc func actPasteBLHeliExecute(_ sender: TObject) {
        if !workspace.sameAs(clipboard, compareName: true, syncThrottle: actMergeThrottle.checked, syncDirection: actMergeMotorDir.checked, db) {
            let tmp = clipboard.copy()
            if fraESCCombos1.pasteSetup(from: tmp, syncThrottle: actMergeThrottle.checked, syncDirection: actMergeMotorDir.checked) {
                showESCData()
            }
        }
    }

    // MARK: - options and misc actions

    @objc func actMergeMotorDirExecute(_ sender: TObject) { updateESCButtons(); updateCopyPaste() }
    @objc func actMergeThrottleExecute(_ sender: TObject) { updateESCButtons(); updateCopyPaste() }
    @objc func actDesignSimpleExecute(_ sender: TObject) { fraESCCombos1.setDesignSimple(actDesignSimple.checked) }
    @objc func actShowSuccessMsgExecute(_ sender: TObject) { /* empty in BLHeliSuite (0x661854) – AutoCheck action */ }
    @objc func actBLHeliRevisionCheckDisabledExecute(_ sender: TObject) { Globals.revisionCheckDisabled = actBLHeliRevisionCheckDisabled.checked }
    @objc func actCheckForUpdateEnabledExecute(_ sender: TObject) { autoCheckForUpdates = actCheckForUpdateEnabled.checked ? 0 : 24 }
    @objc func actCheckForUpdateExecute(_ sender: TObject) { checkForUpdate(manual: true) }

    @objc func actExpertModeExecute(_ sender: TObject) {
        expertMode = actExpertMode.checked
        fraCFMotorTest1.setExpert(expertMode)
        fillBaudrates()
    }

    @objc func actLogOnExecute(_ sender: TObject) {
        if !TfrmLogForm.isShown {
            if actLogOn.checked { TfrmLogForm.showLog(stayOnTop: actLogStayOnTop.checked) }
        } else if !actLogOn.checked {
            TfrmLogForm.hideLog()
        }
        actLogStayOnTop.enabled = TfrmLogForm.isShown
    }

    @objc func actLogStayOnTopExecute(_ sender: TObject) {
        if TfrmLogForm.isShown { TfrmLogForm.setStayOnTop(actLogStayOnTop.checked) }
    }

    @objc func actScreenshotExecute(_ sender: TObject) {
        saveScreenshot(of: self, name: "BLHeliSuite" + (pgcMain.activePage?.caption ?? ""))
    }

    @objc func actSelectValBackColorExecute(_ sender: TObject) {
        var target: TColor
        if Brand.current == 1 { target = workspace.isS ? ValueColors.silabsS : ValueColors.silabs }
        else if Brand.current == 2 { target = ValueColors.avr } else { return }
        guard let c = ColorDialog.execute(target) else { return }
        target = c
        if Brand.current == 1 { if workspace.isS { ValueColors.silabsS = c } else { ValueColors.silabs = c } } else { ValueColors.avr = c }
        showESCData()
    }

    @objc func actShowAboutExecute(_ sender: TObject) {
        let f = TAboutBox(resource: "TABOUTBOX", owner: self)
        f.showModal()
        f.release()
    }

    @objc func btnConstructionClick(_ sender: TObject) { /* empty in BLHeliSuite (0x662CE4) */ }
    @objc func btnFlashOtherClick(_ sender: TObject) {}
    @objc func CompInfoDeviceChange(_ sender: TObject) { fillComPorts(true) }
    @objc func mnuMainGetImageIndex(_ sender: TObject) { /* 0x67280C: ImageIndex of the item := its action's ImageIndex – done by VCL TMenuItem */ }
    @objc func FormStorageAfterRestorePlacement(_ sender: TObject) {}
    @objc func FormStorageRestorePlacement(_ sender: TObject) { /* empty in BLHeliSuite (0x66EDB4) */ }
    @objc func FormStorageSavePlacement(_ sender: TObject) { /* empty in BLHeliSuite (0x66EDB8) */ }

    // MARK: - manuals and links

    func manualFile(_ name: String) -> URL? { AppFolders.manuals?.appendingPathComponent(name) }

    /// FUN_00630F2C: ShellExecute(open).
    func shellOpen(_ s: String) {
        if s.hasPrefix("http") { if let u = URL(string: s) { NSWorkspace.shared.open(u) } }
        else { NSWorkspace.shared.open(URL(fileURLWithPath: s)) }
    }

    func openManual(_ file: String, _ url: String?) {
        if let f = manualFile(file), FileManager.default.fileExists(atPath: f.path) { manualPath = f.path }
        else if let u = url { manualPath = u } else { manualPath = manualFile(file)?.path ?? file }
        shellOpen(manualPath)
    }

    func openSiLabsAtmel(_ silabsFile: String, _ atmelFile: String, _ silabsURL: String, _ atmelURL: String) {
        if Brand.current == 1 { openManual(silabsFile, silabsURL) } else { openManual(atmelFile, atmelURL) }
    }

    static let gh = "https://github.com/bitdump/BLHeli/raw/master/"

    @objc func actBLHeliProgrammingAdaptersManualExecute(_ sender: TObject) { openManual("BLHeli programming adapters.pdf", nil) }
    @objc func actShowBLHeliSuiteMultipleESCmodeExecute(_ sender: TObject) { openManual("BLHeliSuite MultipleESC mode.pdf", nil) }
    @objc func actHowtoBuildaBLHeliBootloaderInterfaceExecute(_ sender: TObject) { openManual("How to Build a BLHeli bootloader interface with USB-UART board.pdf", nil) }
    @objc func actShow4wifPinoutExecute(_ sender: TObject) { openManual("BLHeliSuite 4w-if interfaces pinout.pdf", nil) }
    @objc func actShow4wifProtocolExecute(_ sender: TObject) { openManual("BLHeliSuite 4w-if protocol.pdf", nil) }
    @objc func actShowHistoryExecute(_ sender: TObject) { openManual("BLHeliSuite History.pdf", nil) }
    @objc func actShowMakeArduinoISPExecute(_ sender: TObject) { openManual("How to Make an ArduinoISP.pdf", nil) }
    @objc func actLinkToSiLabs2pdfExecute(_ sender: TObject) { openManual("BLHeli programming by TX SiLabs Rev2.x.pdf", Self.gh + "SiLabs/BLHeli%20programming%20by%20TX%20SiLabs%20Rev2.x.pdf") }
    @objc func actLinkToSiLabs3pdfExecute(_ sender: TObject) { openManual("BLHeli programming by TX SiLabs Rev3.x.pdf", Self.gh + "SiLabs/BLHeli%20programming%20by%20TX%20SiLabs%20Rev3.x.pdf") }
    @objc func actLinkToSiLabs4pdfExecute(_ sender: TObject) { openManual("BLHeli programming by TX SiLabs Rev4.x.pdf", Self.gh + "SiLabs/BLHeli%20programming%20by%20TX%20SiLabs%20Rev4.x.pdf") }
    @objc func actLinkToSiLabs5pdfExecute(_ sender: TObject) { openManual("BLHeli programming by TX SiLabs Rev5.x.pdf", Self.gh + "SiLabs/BLHeli%20programming%20by%20TX%20SiLabs%20Rev5.x.pdf") }
    @objc func actLinkToSiLabs6pdfExecute(_ sender: TObject) { openManual("BLHeli programming by TX SiLabs Rev6.x.pdf", Self.gh + "SiLabs/BLHeli%20programming%20by%20TX%20SiLabs%20Rev6.x.pdf") }
    @objc func actLinkToSiLabs7pdfExecute(_ sender: TObject) { openManual("BLHeli programming by TX SiLabs Rev7.0.pdf", "https://github.com/bitdump/BLHeli/blob/master/SiLabs/BLHeli%20programming%20by%20TX%20SiLabs%20Rev7.0.pdf?raw=true") }
    @objc func actLinkToSiLabs8pdfExecute(_ sender: TObject) { openManual("BLHeli programming by TX SiLabs Rev8.x.pdf", Self.gh + "SiLabs/BLHeli%20programming%20by%20TX%20SiLabs%20Rev8.x.pdf") }
    @objc func actLinkToSiLabs9pdfExecute(_ sender: TObject) { openManual("BLHeli programming by TX SiLabs Rev9.x.pdf", Self.gh + "SiLabs/BLHeli%20programming%20by%20TX%20SiLabs%20Rev9.x.pdf") }
    @objc func actLinkToSiLabs10pdfExecute(_ sender: TObject) { openManual("BLHeli programming by TX SiLabs Rev10.x.pdf", Self.gh + "SiLabs/BLHeli%20programming%20by%20TX%20SiLabs%20Rev10.x.pdf") }
    @objc func actLinkToAtmSil11pdfExecute(_ sender: TObject) { openSiLabsAtmel("BLHeli manual SiLabs Rev11.x.pdf", "BLHeli manual Atmel Rev11.x.pdf", Self.gh + "SiLabs/BLHeli%20manual%20SiLabs%20Rev11.x.pdf", Self.gh + "Atmel/BLHeli%20manual%20Atmel%20Rev11.x.pdf") }
    @objc func actLinkToAtmSil12pdfExecute(_ sender: TObject) { openSiLabsAtmel("BLHeli manual SiLabs Rev12.x.pdf", "BLHeli manual Atmel Rev12.x.pdf", Self.gh + "SiLabs/BLHeli%20manual%20SiLabs%20Rev12.x.pdf", Self.gh + "Atmel/BLHeli%20manual%20Atmel%20Rev12.x.pdf") }
    @objc func actLinkToAtmSil13pdfExecute(_ sender: TObject) { openSiLabsAtmel("BLHeli manual SiLabs Rev13.x.pdf", "BLHeli manual Atmel Rev13.x.pdf", Self.gh + "SiLabs/BLHeli%20manual%20SiLabs%20Rev13.x.pdf", Self.gh + "Atmel/BLHeli%20manual%20Atmel%20Rev13.x.pdf") }
    @objc func actLinkToAtmSil14pdfExecute(_ sender: TObject) { openSiLabsAtmel("BLHeli manual SiLabs Rev14.x.pdf", "BLHeli manual Atmel Rev14.x.pdf", Self.gh + "SiLabs/BLHeli%20manual%20SiLabs%20Rev14.x.pdf", Self.gh + "Atmel/BLHeli%20manual%20Atmel%20Rev14.x.pdf") }
    @objc func actLinkToESCs_supportedExecute(_ sender: TObject) { openSiLabsAtmel("BLHeli supported SiLabs ESCs.pdf", "BLHeli supported Atmel ESCs.pdf", Self.gh + "SiLabs/BLHeli%20supported%20SiLabs%20ESCs.pdf", Self.gh + "Atmel/BLHeli%20supported%20Atmel%20ESCs.pdf") }
    @objc func actLinkToBLHeli_S_16pdfExecute(_ sender: TObject) { openManual("BLHeli_S manual SiLabs Rev16.x.pdf", Self.gh + "BLHeli_S%20SiLabs/BLHeli_S%20manual%20SiLabs%20Rev16.x.pdf") }
    @objc func actLinkToBLHeli_S_ESCs_supportedExecute(_ sender: TObject) { openManual("BLHeli supported BLHeli_S ESCs.pdf", Self.gh + "BLHeli_S%20SiLabs/BLHeli%20supported%20BLHeli_S%20ESCs.pdf") }
    @objc func actLinkToGovernorRpmTableExecute(_ sender: TObject) { openManual("Governor SiLabs.xls", Self.gh + "SiLabs/Governor%20SiLabs.xls") }
    @objc func actLinkToBLHeliGitHubExecute(_ sender: TObject) { manualPath = "https://github.com/bitdump/BLHeli"; shellOpen(manualPath) }
    @objc func actLinkToHFForum_BLHeliForSilExecute(_ sender: TObject) { manualPath = "http://www.helifreak.com/showthread.php?t=390517"; shellOpen(manualPath) }
    @objc func actLinkToHFForum_BLHeli_SetupExecute(_ sender: TObject) { manualPath = "http://www.helifreak.com/showthread.php?t=467519"; shellOpen(manualPath) }
    @objc func actLinkToMyBLHeliThreadExecute(_ sender: TObject) { manualPath = "http://www.helifreak.com/showthread.php?t=412147"; shellOpen(manualPath) }
    @objc func actLinkToRcgroupsBLheliSuiteThreadExecute(_ sender: TObject) { manualPath = "http://www.rcgroups.com/forums/showthread.php?t=2136895"; shellOpen(manualPath) }
    @objc func actLinktToBLHeliSuiteBlogExecute(_ sender: TObject) { manualPath = "https://blhelisuite.wordpress.com/"; shellOpen(manualPath) }
}

enum Globals {
    /// "Disable BLHeli Revision check" (global at 0x6910CC).
    static var revisionCheckDisabled = false
}
