import AppKit
import VCL
import BLHeliCore

/// Read result codes of the original (Self+0x8BC) used by FUN_0065F29C.
enum ReadResult: UInt8 { case unknown = 0, locked = 1, erased = 2, ok = 3, outdated = 4, removed = 5, removedLayout = 6, flashFailed = 7 }

extension TfrmBLHeliSuiteMain {
    var escText: String { "ESC#" + String(escNo) }   // FUN_0066F2F8

    // MARK: - connect / disconnect (actConnectExecute 0x65E35C, FUN_0065E134, FUN_0065E288)

    @objc func actConnectExecute(_ sender: TObject) {
        if intfConnected {
            disconnectWithLog()
            return
        }
        if !connectWithLog() {
            if checkInterfaceMismatch(false) { _ = connectWithLog() }
        }
    }

    @discardableResult
    func connectWithLog() -> Bool {
        TfrmLogForm.addBlue(NL("Connect to Interface/Device:"))
        TfrmLogForm.indent(1)
        var ok: Bool
        if !intfConnected {
            ok = connectInterface(true)
        } else {
            ok = true
            TfrmLogForm.addBlue(NL("Interface connected."))
        }
        if ok && !multiESCCapable && escNo == 1 {
            switch intf {
            case .silC2Toolstick, .silBLBCom, .atmBLBCom: ok = connectESC(true)
            case .silC2_4wif, .silBLB4wif, .atmBLB4wif, .atmSK4wif: ok = connectESC(true)
            default: break
            }
        }
        TfrmLogForm.indent(-1)
        TfrmLogForm.result(ok)
        return ok
    }

    func disconnectWithLog() {
        TfrmLogForm.addBlue(NL("Disconnect Interface/Device:"))
        TfrmLogForm.indent(1)
        var ok = true
        if !intfConnected {
            TfrmLogForm.addBlue(NL("Interface/Device not connected."))
        } else {
            disconnectTarget()
            ok = disconnectInterface()
        }
        TfrmLogForm.indent(-1)
        TfrmLogForm.result(ok)
    }

    /// FUN_00664538: connects the interface if needed.
    @discardableResult
    func connectInterface(_ showErrors: Bool) -> Bool {
        if intfConnected { return true }
        Screen.busy = true
        defer { Screen.busy = false; updateCaption() }
        resetSlots(1, 8)
        switch intf {
        case .silC2Toolstick:
            if cbxUSBDevices.text_.isEmpty {
                setStatus(NL("No (Toolstick) Adapter available or selected.\r\nUnable to connect to ESC."))
                if showErrors { MsgDlg.error(statusText) }
            } else {
                do { try toolstick.connect() } catch { if showErrors { MsgDlg.error(error.localizedDescription) } }
            }
        case .atmISP:
            do { try avrdude.connect() } catch { if showErrors { MsgDlg.error(error.localizedDescription) } }
        case .none:
            break
        default:
            guard let s = serialIntf else { return false }
            setStatus(NL("Connecting..."))
            Application.shared.processMessages()
            do {
                try s.connect(intf)
                savePortSettings()
                setStatus("")
                if intf.isCF { waitForFCInfo(false) }
            } catch {
                s.disconnect()
                let port = PortList.shortName(s.portPath)
                let msg: String
                if let ce = error as? ConnectError {
                    msg = ce.localizedDescription
                } else {
                    msg = DFormat(NL(Res.connectionFailedAt), [intf.caption, port, error.localizedDescription])
                }
                setStatus(msg.components(separatedBy: "\n").first ?? msg)
                if showErrors { MsgDlg.error(msg) }
            }
        }
        if intfConnected && multiESCCapable { updateESCButtonsVisible() }
        return intfConnected
    }

    /// Waits until the flight controller has reported itself (variant / version).
    func waitForFCInfo(_ show: Bool) {
        guard cf.deviceName.isEmpty || cf.deviceName.hasPrefix("?") else { return }
        let info = show ? TfrmInfo.showInfo(NL("Waiting for Flight Controller ..."), cancel: true) : nil
        let end = Date().addingTimeInterval(3)
        while Date() < end && (cf.deviceName.isEmpty || cf.deviceName.hasPrefix("?")) && !(info?.cancelled ?? false) {
            Application.shared.sleep(100)
        }
        info?.hideInfo()
        updateCaption()
    }

    /// FUN_00664A08: disconnects the interface.
    @discardableResult
    func disconnectInterface() -> Bool {
        guard intfConnected else { return true }
        resetSlots(1, 8)
        checkedMultiESC = false
        Screen.busy = true
        switch intf {
        case .silC2Toolstick: toolstick.disconnect()
        case .atmISP: avrdude.disconnect()
        case .none: break
        default: serialIntf?.disconnect()
        }
        Screen.busy = false
        updateCaption()
        return true
    }

    /// FUN_006648D8: releases the target ESC.
    func disconnectTarget() {
        switch intf {
        case .silC2Toolstick: toolstick.device = nil
        case .atmISP: avrdude.device = nil
        case .none: break
        default:
            if let s = serialIntf, let p = s.programmer, s.device != nil, !intf.isCF {
                try? p.resetESC(escNo - 1)
            }
            serialIntf?.device = nil
        }
    }

    /// FUN_0066483C.
    func disconnectAll() {
        disconnectTarget()
        disconnectInterface()
    }

    var programmer: ESCProgrammer? {
        switch intf {
        case .silC2Toolstick: return toolstick.programmer
        case .atmISP: return avrdude.isp
        case .none: return nil
        default: return serialIntf?.programmer
        }
    }

    var targetDevice: DeviceInfo? {
        get {
            switch intf {
            case .silC2Toolstick: return toolstick.device
            case .atmISP: return avrdude.device
            case .none: return nil
            default: return serialIntf?.device
            }
        }
        set {
            switch intf {
            case .silC2Toolstick: toolstick.device = newValue
            case .atmISP: avrdude.device = newValue
            case .none: break
            default: serialIntf?.device = newValue
            }
        }
    }

    /// FUN_00664080: connects the current ESC (escNo).
    @discardableResult
    func connectESC(_ showErrors: Bool) -> Bool {
        guard let p = programmer else { return false }
        Screen.busy = true
        defer { Screen.busy = false }
        Led_Read.isOn = true
        defer { Led_Read.isOn = false }
        do {
            let dev = try p.selectESC(escNo - 1)
            targetDevice = dev
            let slot = slots[escNo]
            slot.found = true
            slot.foundBrand = dev.family == .silabs ? 1 : (dev.family == .atmel ? 2 : (dev.family == .arm ? 3 : 0))
            slot.wrongBrand = slot.foundBrand != 0 && slot.foundBrand != Brand.current
            slot.deviceType = dev.interfaceMode == .siLabsC2 ? 1 : (dev.isISP ? 4 : (dev.interfaceMode == .atmelSK ? 3 : 2))
            slot.signature = String(format: "0x%04X", dev.signature)
            slot.bootVersion = dev.family == .arm ? 0x65 : 0x20
            return !slot.wrongBrand && dev.family != .arm
        } catch {
            targetDevice = nil
            if case ProgrammerError.escNotFound = error {
                slots[escNo].found = false
            } else if error is SerialError {
                connectionLost()
            }
            if showErrors && !multiESCCapable {
                let msg = DFormat(NL(Res.couldNotConnectESC), [escText])
                setStatus(msg)
                MsgDlg.error(msg + "\r\n\r\n" + error.localizedDescription)
            }
            return false
        }
    }

    /// FUN_00664850: "Connection lost."
    func connectionLost() {
        Led_Write.isOn = false
        Led_Read.isOn = false
        setStatus("Connection lost.")
        disconnectInterface()
        updateCaption()
    }

    // MARK: - interface / device mismatch (FUN_00677E4C)

    /// Offers to switch to the interface matching the found device. Returns true if switched.
    func checkInterfaceMismatch(_ silent: Bool) -> Bool {
        guard escConnected, let dev = targetDevice else { return false }
        let found: UInt8 = dev.family == .silabs ? 1 : (dev.family == .atmel ? 2 : 0)
        guard found != 0 && found != Brand.current else { return false }
        var target: IntfType
        switch intf {
        case .silBLBCF: target = .atmBLBCF
        case .atmBLBCF: target = .silBLBCF
        case .silBLBCom: target = .atmBLBCom
        case .atmBLBCom: target = .silBLBCom
        case .silBLB4wif, .silC2_4wif: target = .atmBLB4wif
        default: target = .silBLB4wif
        }
        let expected = Brand.current == 1 ? "SILABS BLHeli Bootloader" : "ATMEL BLHeli Bootloader"
        let foundName = found == 1 ? "SILABS BLHeli Bootloader" : "ATMEL BLHeli Bootloader"
        if !silent {
            let q = NL("Expected ") + expected + NL(" device, but ") + foundName + NL(" device found") + "\r\n\r\n" + NL("Switch to ") + foundName + NL(" mode?")
            if MsgDlg.show(q, .mtConfirmation, [.mbYes, .mbNo]) != mrYes { return false }
        }
        selectInterface(target)
        if intf.isCF && !intfConnected {
            let info = TfrmInfo.showInfo(NL("Waiting for Flight Controller ..."), cancel: false)
            Application.shared.sleep(3000)
            info.hideInfo()
        }
        return true
    }

    // MARK: - Check (actCheckMultiESCExecute 0x65E0EC, FUN_0067A2C4)

    @objc func actCheckMultiESCExecute(_ sender: TObject) {
        checkMultiESC(1, escCount)
        selectESC(masterESC, load: true)
        if workspace.isFlashFailed { _ = readSetup(false) }
    }

    func checkMultiESC(_ first: Int, _ last: Int) {
        Screen.busy = true
        defer { Screen.busy = false }
        TfrmLogForm.addBlue2("Checking Multiple ESC:")
        TfrmLogForm.indent(1)
        if !connectInterface(true) {
            TfrmLogForm.indent(-1)
            return
        }
        guard multiESCCapable else {
            setStatus(NL("Interface does not support Mutiple ESC configuration."))
            MsgDlg.show(statusText, .mtInformation, [.mbOK])
            TfrmLogForm.indent(-1)
            return
        }
        resetSlots(first, 0)
        var foundText = NL("Found Multiple ESC: ")
        var n = first
        while n <= last {
            if n <= escCount {
                TfrmLogForm.addBlue(NL("Check for ESC#") + DFormat("%d", [n]))
                TfrmLogForm.indent(1)
                selectESC(n, load: false)
                if !connectESC(false) && !intfConnected { break }
                if slots[n].found && !slots[n].wrongBrand {
                    if readCurrentSetup() { foundText += DFormat("ESC#%d ;", [n]) }
                }
                updateESCButtons()
                TfrmLogForm.indent(-1)
                if slots[n].found && current.isValid { TfrmLogForm.add(current.shortInfo(), color: 0x8000) }
            } else {
                TfrmLogForm.addBlue(NL("Check for ESC#") + DFormat("%d skipped", [n]))
            }
            n += 1
        }
        if intfConnected { checkedMultiESC = true }
        TfrmLogForm.indent(-1)
        TfrmLogForm.add(selectedCount == 0 ? "0" : String(selectedCount), color: selectedCount == 0 ? 0xFF : 0x8000)
        TfrmLogForm.add("found", color: 0x800000)
        _ = foundText
    }

    /// FUN_006796A0: reads the setup block of the current ESC into blheli[escNo].
    @discardableResult
    func readCurrentSetup() -> Bool {
        guard let p = programmer, let dev = targetDevice else { return false }
        let ops = ESCOperations(programmer: p)
        var ok = false
        do {
            let s = try ops.readSettings(device: dev)
            // data that is erased (0xFF) or a counting pattern is no setup
            ok = s.raw.enumerated().contains { $0.element != 0xFF && Int($0.element) != $0.offset }
            if ok {
                do {
                    try current.load(raw: s.raw, signature: Int(dev.signature))
                    if !current.isFlashFailed {
                        compareWithMaster()
                        if !slots[escNo].modeDiff { slots[escNo].selected = true }
                    }
                } catch {
                    current.clear(isS: false)
                    lastReadError = error.localizedDescription
                    ok = false
                }
            } else {
                current.clear(isS: false)
            }
        } catch {
            current.clear(isS: false)
            if error is SerialError { connectionLost() }
            ok = false
        }
        updateESCButtons()
        return ok
    }

    // MARK: - Read Setup (actReadSetupExecute 0x65E604, FUN_00677AA4, FUN_0065F29C)

    @objc func actReadSetupExecute(_ sender: TObject) {
        if !readSetup(true) {
            if checkInterfaceMismatch(false) { _ = readSetup(true) }
        }
        updateCaption()
    }

    @discardableResult
    func readSetup(_ showMsg: Bool) -> Bool {
        guard connectInterface(true) else { return false }
        if multiESCCapable && !checkedMultiESC { checkMultiESC(1, escCount) }
        TfrmLogForm.addBlue2("Reading Setup for")
        TfrmLogForm.indent(1)
        setStatus("")
        selectESC(masterESC, load: true)
        current.clear(isS: false)
        TfrmLogForm.add(escText, color: 0xFF0000)
        var ok = false
        if connectESC(true) {
            Led_Read.isOn = true
            ok = readCurrentSetup()
            Led_Read.isOn = false
            let res = classifyRead(ok)
            if res != .ok {
                ok = false
                if offerFlash(res) == mrYes { flashWithAssistant() }
            } else {
                current.assign(to: workspace)
            }
        }
        if ok {
            showESCData()
            fraESCCombos1.dataLoaded()
        } else {
            showESCData()
        }
        TfrmLogForm.indent(-1)
        setStatus(NL(escText + (ok ? " setup read successfully" : " setup read failed")))
        slots[escNo].signature = statusText
        if ok && showMsg && actShowSuccessMsg.checked {
            MsgDlg.show(statusText, .mtInformation, [.mbOK])
        }
        return ok
    }

    func classifyRead(_ ok: Bool) -> ReadResult {
        if slots[escNo].locked { return .locked }
        if ok {
            if current.isFlashFailed { return .flashFailed }
            return .ok
        }
        guard let dev = targetDevice else { return .unknown }
        if dev.family == .arm { return .unknown }
        if lastReadError.contains("outdated") { return .outdated }
        if lastReadError.isEmpty || lastReadError.contains("MCU ID") { return .erased }
        return .unknown
    }

    /// FUN_0065F29C: message after a failed read; returns the modal result (mrYes = flash).
    func offerFlash(_ r: ReadResult) -> TModalResult {
        switch r {
        case .unknown:
            if slots[escNo].bootVersion >= 0x65 || targetDevice?.family == .arm {
                return MsgDlg.show(NL(escText + " BLHeli_32 ESC?\\n\\nPlease use BLHeliSuite32 in oder to connect BLHeli_32 ESC!"), .mtWarning, [.mbCancel])
            }
            let m = NL("Unknown or invald " + escText + " type.") + "\r\n\r\n" + NL("Do You want to flash it with BLHeli firmware?")
            return MsgDlg.show(m, .mtWarning, [.mbYes, .mbCancel])
        case .locked:
            if intf.rawValue < 2 || (intf == .atmISP && !avrdude.lockedBits) {
                let m = NL("The Memory of " + escText + " seems to be locked.") + "\r\n\r\n" + NL("(Typical for newly acquired ESCs)") + "\r\n\r\n" + NL("Do You want to Flash it with BLHeli Firmware?")
                return MsgDlg.show(m, .mtConfirmation, [.mbYes, .mbCancel])
            }
            let m = NL("The Memory of " + escText + " seems to be locked.") + "\r\n\r\n" + NL("(Typical for newly acquired ESCs)") + "\r\n\r\n" +
                NL("You cannot flash locked ESC with current bootloader interface.") + "\r\n" + NL("Please use a ISP 6-pin interface type!")
            return MsgDlg.show(m, .mtWarning, [.mbCancel])
        case .erased:
            let tail = Brand.current == 1 ? " seems to be erased before.\\n\\nDo You want to Flash it with BLHeli Firmware?"
                : " seems to be flash with SimonK or other firmware, or was erased before.\\n\\nDo You want to Flash it with BLHeli Firmware?"
            return MsgDlg.show(escText + NL(tail), .mtConfirmation, [.mbYes, .mbCancel])
        case .outdated:
            let m = DFormat(NL("%s: BLHeli %s firmware revision %d.%d is outdated and not supported by %s!\\n\\nDo You want to flash it with a newer BLHeli firmware revision?"),
                            [escText, Brand.name(current.brand), current.value(.mainRevision), current.value(.subRevision), "BLHeliSuite"])
            return MsgDlg.show(m, .mtWarning, [.mbYes, .mbCancel])
        case .flashFailed:
            let m = DFormat(NL("%s: Obviously an attempt to flash this ESC has failed.\\nNow the memory content is most likely corrupted, so do not try to use this ESC.\\n\\nDo you want to try to flash the again with BLHeli, to remedy the failure?"),
                            [escText, current.value(.mainRevision), current.value(.subRevision)])
            return MsgDlg.show(m, .mtWarning, [.mbYes, .mbCancel])
        default:
            return mrNone
        }
    }

    // MARK: - Write Setup (actWriteSetupExecute 0x662B3C, FUN_0067910C)

    @objc func actWriteSetupExecute(_ sender: TObject) {
        if !writeSetup(true) {
            if checkInterfaceMismatch(false) { _ = writeSetup(true) }
        }
    }

    /// FUN_0067910C: writes the setup to all selected ESC. `masterOnlyRules` (dl): the master/merge rules of the
    /// Multiple ESC mode apply (Write Setup button); otherwise every ESC gets the complete setup.
    @discardableResult
    func writeSetup(_ masterOnlyRules: Bool) -> Bool {
        var msgs = ""
        var ok = true
        TfrmLogForm.addNavy2(NL("Write Setup:"))
        TfrmLogForm.indent(1)
        defer {
            TfrmLogForm.indent(-1)
            TfrmLogForm.result(ok)
        }
        clearSlotStatus()
        fraESCCombos1.collect(into: workspace)
        if !multiESCCapable { slots[1].selected = true }
        for n in 1...escSlotCount where slots[n].selected {
            if masterOnlyRules {
                selectESC(n, load: false)
                ok = writeSetupESC(compareName: isMaster, syncDirection: isMaster || actMergeMotorDir.checked,
                                   syncThrottle: isMaster || actMergeThrottle.checked)
            } else {
                selectESC(n, load: true)
                ok = writeSetupESC(compareName: true, syncDirection: true, syncThrottle: true)
            }
            msgs += escText + ": " + statusText + "\r\n\r\n"
        }
        let selected = (1...8).filter { slots[$0].selected }.count
        if selected > 1 {
            updateESCButtons()
            selectESC(masterESC, load: false)
            _ = readSetup(false)
            if ok {
                if actShowSuccessMsg.checked {
                    MsgDlg.show(trim(NL("Multiple ESC Write successfull:") + "\r\n\r\n" + msgs), .mtInformation, [.mbOK])
                }
            } else {
                MsgDlg.error(trim(NL("Multiple ESC Write failed:") + "\r\n\r\n" + msgs))
            }
        } else if selected == 1 {
            if ok {
                if actShowSuccessMsg.checked { MsgDlg.show(trim(msgs), .mtInformation, [.mbOK]) }
            } else {
                MsgDlg.show(trim(msgs), .mtWarning, [.mbOK])
            }
        }
        return false
    }

    func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// FUN_006789C4: writes the workspace (Self+0x78C) to the current ESC.
    @discardableResult
    func writeSetupESC(compareName: Bool, syncDirection: Bool, syncThrottle: Bool) -> Bool {
        setStatusESC(NL("Write Failed."))
        var ok = false
        TfrmLogForm.addBlue2("Writing Setup for " + escText)
        TfrmLogForm.indent(1)
        defer {
            TfrmLogForm.indent(-1)
            if !ok { TfrmLogForm.add("FAILED", color: 0xFF) } else { TfrmLogForm.result(true) }
            setStatusESC(statusText)
        }
        guard connectInterface(true), connectESC(selectedCountIsSingle), escConnected else {
            setStatusESC(statusText + NL(" Unable to Connect."))
            return false
        }
        let chk = checkESC()
        guard chk.ok else {
            setStatusESC(statusText + NL(" Unable to Connect."))
            return false
        }
        var mem: [UInt8]?
        if chk.locked {
            classifyRead(locked: true, mem: &mem)
            if offerFlash(readResult) == mrYes { ok = ((try? flashOne(mem: mem, file: false, blheli: true)) ?? 0) > 0 }
            return ok
        }
        guard let m = readSetupMem() else { return false }
        mem = m
        let tmp = TBLHeli(isS: false)
        guard (try? tmp.load(raw: m)) != nil else {
            if classifyRead(locked: false, mem: &mem) {
                if offerFlash(readResult) == mrYes { ok = ((try? flashOne(mem: mem, file: false, blheli: true)) ?? 0) > 0 }
            }
            return ok
        }
        if tmp.isFlashFailed {
            setStatusESC(NL("Prior atempt to flash the ESC failed\\nWriting settings is prohibited.\\n\\nPlease retry the flash procedure first"))
            return false
        }
        if classifyRead(locked: false, mem: &mem) {
            if offerFlash(readResult) == mrYes { ok = ((try? flashOne(mem: mem, file: false, blheli: true)) ?? 0) > 0 }
            return ok
        }
        if current.sameAs(workspace, compareName: compareName, syncThrottle: syncThrottle, syncDirection: syncDirection, db) {
            if isMaster { fraESCCombos1.dataLoaded() }
            ok = true
            setStatusESC(NL("Nothing to write. ESC already updated."))
            return true
        }
        guard tmp.paste(from: workspace, translate: true, showMsg: false, syncThrottle: syncThrottle, syncDirection: syncDirection, db) else {
            setStatusESC(tmp.errorText)
            return false
        }
        if !compareName { tmp.settings.name = current.name } else { tmp.settings.name = workspace.name }
        if current.sameAs(tmp, compareName: compareName, syncThrottle: syncThrottle, syncDirection: syncDirection, db) {
            ok = true
            setStatusESC(NL("Nothing to write. ESC already matches with the parameters."))
            return true
        }
        Led_Write.isOn = true
        defer { Led_Write.isOn = false }
        while true {
            do {
                let ops = ESCOperations(programmer: programmer!)
                ops.verify = false
                try ops.writeSettings(tmp.settings, device: targetDevice!)
                break
            } catch {
                if error is SerialError { connectionLost(); return false }
                if MsgDlg.show(NL("Write Setup Section Failed!\\nRetry?"), .mtWarning, [.mbRetry, .mbCancel]) != mrRetry { return false }
            }
        }
        guard let back = readSetupMem(), (try? current.load(raw: back)) != nil,
              current.sameAs(tmp, compareName: compareName, syncThrottle: syncThrottle, syncDirection: syncDirection, db) else { return false }
        if isMaster, (try? workspace.load(raw: back)) != nil {
            fraESCCombos1.dataLoaded()
            showESCData()
            Application.shared.processMessages()
        }
        ok = true
        setStatusESC(NL("Write OK."))
        return true
    }

    /// FUN_0066F27C < 2: only one ESC selected.
    var selectedCountIsSingle: Bool { (1...8).filter { slots[$0].selected }.count < 2 }

    // MARK: - Restart ESC (actRestartESCExecute 0x6602F0 / FUN_00678354)

    @objc func actRestartESCExecute(_ sender: TObject) {
        switch intf {
        case .silC2Toolstick:
            disconnectAll()
        case .silC2_4wif, .silBLB4wif, .atmBLB4wif, .atmSK4wif:
            if !multiESCCapable { disconnectTarget() } else { disconnectAll() }
        default:
            disconnectAll()
        }
        updateCaption()
    }

    @objc func actTargetRestartExecute(_ sender: TObject) { actRestartESCExecute(sender) }

    @objc func actTargetKeepResetExecute(_ sender: TObject) {
        TfrmLogForm.addNavy2("Expert: keep reset target")
    }

    // MARK: - Flash (actFlashBLHeliExecute 0x66111C, actFlashOtherExecute 0x661150)

    @objc func actFlashBLHeliExecute(_ sender: TObject) {
        do {
            if try flashStart(file: false, blheli: true) {
                if checkInterfaceMismatch(false) { _ = try flashStart(file: false, blheli: true) }
            }
            updateCaption()
        } catch {}
    }

    @objc func actFlashOtherExecute(_ sender: TObject) {
        do {
            if try flashStart(file: true, blheli: false) {
                if checkInterfaceMismatch(false) { _ = try flashStart(file: true, blheli: false) }
            }
            updateCaption()
        } catch {}
    }

    /// Flash offered after a failed read (FUN_00665B2C with the memory of the read).
    func flashWithAssistant() {
        var mem: [UInt8]? = nil
        _ = try? flashOne(mem: mem, file: false, blheli: true)
        mem = nil
    }

    /// actCheckForUpdateExecute / FUN_0065EADC: the Windows version downloads its own updates; the macOS port
    /// opens the release page of the port instead.
    func checkForUpdate(manual: Bool) {
        if manual, let u = URL(string: "https://github.com/KarolSieradzki/BLHeliSuiteMac/releases") { NSWorkspace.shared.open(u) }
    }
}

/// Resource strings of BLHeliSuite.exe used by the port.
enum Res {
    /// LoadResString(64713) / (64714) – kept with the "\\n" escapes of the original (UnescapeNL'd by NL()).
    static var choosingWrongMCU: String { Resources.string(64713) }
    static var keepCaution: String { Resources.string(64714) }
    static let connectionFailedAt = "Connection to %s at %s failed!\\n\\nError: \"%s\"\\n\\nPlease check usb/serial port settings!"
    static let couldNotConnectESC = "Could not connect to target %s."
}
