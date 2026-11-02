import AppKit
import VCL
import BLHeliCore

/// ESC setup page – port of TfraESCCombos.
@objc(TfraESCCombos) final class TfraESCCombos: TfraESCCombosOutlets {
    /// Controls of one parameter (Self+0x648 + p*0x18).
    final class ParamCtl {
        var grb: TGroupBox?
        var lbl: TLabel?
        var led: TLabel?
        var scb: TControl?     // TScrollBar or TTrackBar
        var undo: TSpeedButton?
        var def: TSpeedButton?
    }

    weak var main: TfrmBLHeliSuiteMain?
    var params: [Int: ParamCtl] = [:]
    var escNo = 1          // Self+0x640
    var updating = false   // Self+0xA98
    var designSimple = false

    var bl: TBLHeli { main?.workspace ?? TBLHeli() }
    var original: TBLHeli { main?.blheli[escNo] ?? TBLHeli() }
    var db: FirmwareDatabase? { main?.db }

    static let lefts = [4, 195, 385, 575]
    static let tops = [10, 68, 126, 184, 242, 300, 358, 416]

    // MARK: - setup (FUN_00650E00 / FUN_0065000C)

    func attach(_ m: TfrmBLHeliSuiteMain) {
        main = m
        cbxPositionRunTime.visible = false   // TfraESCCombos.Create (0x64FE3C)
        for case let g as TGroupBox in pnlSetupMain.subviews {
            let name = g.name.lowercased()
            g.onMouseEnter = nil
            guard name.hasPrefix("grb_eep_") else { continue }
            let eep = String(g.name.dropFirst(4))
            guard let p = BLHeliParam.allCases.first(where: { $0.eepName.lowercased() == eep.lowercased() }), p != .name else { continue }
            let c = ParamCtl()
            c.grb = g
            g.tag = p.rawValue
            for case let k as TControl in g.subviews {
                k.tag = p.rawValue
                let kn = k.name.lowercased()
                if kn.hasPrefix("scb_") {
                    c.scb = k
                    if let sb = k as? TScrollBar { sb.onChange = { [weak self] s in self?.paramChanged(s as! TControl) } }
                    if let tb = k as? TTrackBar { tb.onChange = { [weak self] s in self?.paramChanged(s as! TControl) } }
                } else if kn.hasPrefix("led_") {
                    c.led = k as? TLabel
                } else if kn.hasPrefix("lbl_") {
                    c.lbl = k as? TLabel
                    c.lbl?.roundedFrame = 2
                } else if kn.hasPrefix("sbtnundo") {
                    c.undo = k as? TSpeedButton
                    c.undo?.hint = NL("Undo changes")
                    c.undo?.showHint = true
                    c.undo?.onClick = { [weak self] s in self?.undoClick(s as! TControl) }
                } else if kn.hasPrefix("sbtndefault") {
                    c.def = k as? TSpeedButton
                    c.def?.hint = NL("Restore factory default value")
                    c.def?.showHint = true
                    c.def?.onClick = { [weak self] s in self?.defaultClick(s as! TControl) }
                }
            }
            params[p.rawValue] = c
        }
        grb_Eep_Name.tag = 0x2D
        edt_Eep_Name.tag = 0x2D
        edt_Eep_Name.onChange = { [weak self] s in self?.paramChanged(s as! TControl) }
        grb_Misc.tag = 0x10
        cbx_Eep_Enable_TX_Setup.tag = 0x10
        cbx_Eep_Gov_Rearm_Start.tag = 0x11
        sbtnUNDO_Misc.onClick = { [weak self] s in self?.undoClick(s as! TControl) }
        sbtnUNDO_Misc.hint = NL("Undo changes")
        sbtnDEFAULT_Misc.onClick = { [weak self] s in self?.defaultClick(s as! TControl) }
        sbtnDEFAULT_Misc.hint = NL("Restore factory default value")
        sbtnUNDO_Eep_Name.tag = 0x2D
        sbtnUNDO_Eep_Name.onClick = { [weak self] s in self?.undoClick(s as! TControl) }
        sbtnDEFAULT_Eep_Name.tag = 0x2D
        sbtnDEFAULT_Eep_Name.onClick = { [weak self] s in self?.defaultClick(s as! TControl) }
        for l in [lee_Eep_Pgm_LED_Control_1, lee_Eep_Pgm_LED_Control_2, lee_Eep_Pgm_LED_Control_3, lee_Eep_Pgm_LED_Control_4] {
            l?.onClick = { [weak self] s in self?.ledClicked(s as! TControl) }
        }
        for l in [lbe_Eep_Pgm_LED_Control_1, lbe_Eep_Pgm_LED_Control_2, lbe_Eep_Pgm_LED_Control_3, lbe_Eep_Pgm_LED_Control_4] {
            l?.onClick = { [weak self] s in self?.ledClicked(s as! TControl) }
        }
        loadMotorSetups()
    }

    /// OnChange of the name edit (attach() also routes it to paramChanged).
    @objc func edt_Eep_NameChange(_ sender: TObject) { paramChanged(edt_Eep_Name) }
    @objc func cbx_Eep_Enable_TX_SetupClick(_ sender: TObject) { paramChanged(cbx_Eep_Enable_TX_Setup) }
    @objc func cbx_Eep_Gov_Rearm_StartClick(_ sender: TObject) { paramChanged(cbx_Eep_Gov_Rearm_Start) }
    @objc func cbxMotorSetupsChange(_ sender: TObject) { applyMotorSetup() }
    @objc func sedLipo_sChange(_ sender: TObject) { updateGovernorTarget() }
    @objc func sedMainGearTeethChange(_ sender: TObject) { updateGovernorTarget() }
    @objc func sedMotorCompChange(_ sender: TObject) { updateGovernorTarget() }
    @objc func sedMotorKVChange(_ sender: TObject) { updateGovernorTarget() }
    @objc func sedMotorPoleChange(_ sender: TObject) { updateGovernorTarget() }
    @objc func sedPinionTeethChange(_ sender: TObject) { updateGovernorTarget() }

    // MARK: - show (FUN_0065249C / FUN_00654718)

    func show(escNo n: Int) {
        escNo = n == 0 ? 1 : n
        updateAll()
    }

    func updateAll() {
        guard Brand.current != 0, !updating else { return }
        updating = true
        layoutParams()                 // FUN_00652568
        for raw in 4...0x28 where raw != 0x29 { showValue(raw) }
        updateGovernorTarget()         // FUN_00653C44
        showLED()                      // FUN_00654220
        edt_Eep_Name.textValue = bl.name   // FUN_00654334
        adjustSize()                   // FUN_00654908
        updateValidity()               // FUN_00654988
        updateUndoDefault()            // FUN_00654C98
        updating = false
        main?.adjustFormSize()
    }

    func exists(_ raw: Int) -> Bool {
        guard let p = BLHeliParam(rawValue: raw) else { return false }
        guard bl.isValid else { return false }
        let ctx = bl.context(db)
        if !BLHeliParamLogic.exists(p, ctx) { return false }
        if p == .becVoltageHigh { return (ctx.layout?.becHV ?? 0) != 0 }
        if p == .ledControl { return (ctx.layout?.leds ?? 0) != 0 }
        return true
    }

    /// FUN_00652568: positions, captions, ranges and hints of all parameter boxes.
    func layoutParams() {
        let L = TfraESCCombos.lefts, T = TfraESCCombos.tops
        func put(_ g: TControl?, _ col: Int, _ row: Int) { g?.left = L[col]; g?.top = T[row] }
        let ctx = bl.context(db)
        grb_ESC_Description.caption = ctx.layout?.displayName ?? (bl.isValid ? bl.layoutName : "unknown ESC")
        if !bl.isS {
            put(grb_Eep_Name, 0, 0)
            put(grb_Eep_Pgm_Low_Voltage_Lim, 0, 1)
            put(grb_Eep_Pgm_Gov_Mode, 0, 2)
            put(grb_Eep_Pgm_Gov_P_Gain, 0, 3)
            put(grb_Eep_Pgm_Gov_I_Gain, 0, 4)
            put(grb_Eep_Pgm_Gov_Range, 0, 5)
            put(grb_Eep_Pgm_Gov_Setup_Target, 0, 6)
            put(grb_Eep_Pgm_Motor_Idle, 0, 1)
            put(grb_Eep_Pgm_Motor_Gain, 0, bl.mode == 2 ? 5 : 2)
            put(grb_ESC_Description, 1, 0)
            put(grb_Eep_Pgm_Startup_Pwr, 1, 1)
            put(grb_Eep_Pgm_Temp_Prot_Enable, 1, 2)
            put(grb_Eep_Pgm_Main_Spoolup_Time, 1, 3)
            put(grb_Eep_Pgm_Enable_Power_Prot, 1, 4)
            put(grb_Eep_Pgm_Brake_On_Stop, 1, 5)
            put(grb_MotorGearSetup, 1, 6)
            put(grb_Eep_Pgm_Startup_Accel, 1, 3)
            put(grb_Eep_Pgm_Pwm_Dither, 1, 3)
            put(grb_Eep_Pgm_Startup_Method, 1, 4)
            put(grb_Eep_Pgm_Throttle_Rate, 1, 5)
            put(grb_Misc, 2, 0)
            put(grb_Eep_Pgm_Direction, 2, 1)
            put(grb_Eep_Pgm_Demag_Comp, 2, 2)
            put(grb_Eep_Pgm_Pwm_Freq, 2, 3)
            put(grb_Eep_Pgm_Enable_Pwm_Input, 2, 4)
            put(grb_Eep_Pgm_Comm_Timing, 2, 5)
            put(grb_Eep_Pgm_Volt_Comp, 2, 2)
            put(grb_Eep_Pgm_Damping_Force, 2, 4)
            put(grb_Eep_Pgm_Ppm_Center_Throttle, 2, 6)
            put(grb_Eep_Pgm_Input_Pol, 3, 1)
            put(grb_Eep_Pgm_LED_Control, 3, 1)
            put(grb_Eep_Pgm_Beep_Strength, 3, 2)
            put(grb_Eep_Pgm_Beacon_Strength, 3, 3)
            put(grb_Eep_Pgm_Beacon_Delay, 3, 4)
            put(grb_Eep_Pgm_Ppm_Min_Throttle, 3, 5)
            put(grb_Eep_Pgm_Ppm_Max_Throttle, 3, 6)
            put(grb_Eep_Pgm_BEC_Voltage_High, 3, 0)
            if bl.revision < 0x528 {
                let lr = bl.value(.layoutRevision)
                if Brand.current == 1 {
                    if bl.mode == 0 && lr > 0x11 {
                        if lr < 0x13 {
                            put(grb_Eep_Pgm_Gov_Setup_Target, 0, 7)
                            put(grb_MotorGearSetup, 1, 7)
                            put(grb_Eep_Pgm_Main_Spoolup_Time, 1, 6)
                            put(grb_Eep_Pgm_Temp_Prot_Enable, 2, 6)
                        } else {
                            grb_Eep_Pgm_Comm_Timing.top = T[4]
                        }
                    } else {
                        grb_Eep_Pgm_Temp_Prot_Enable.top = T[6]
                    }
                } else if lr < 0x13 {
                    grb_Eep_Pgm_Temp_Prot_Enable.top = T[4]
                }
            }
        } else {
            put(grb_Eep_Name, 0, 0)
            put(grb_Eep_Pgm_Startup_Pwr, 0, 1)
            put(grb_Eep_Pgm_Temp_Prot_Enable, 0, 2)
            put(grb_Eep_Pgm_Enable_Power_Prot, 0, 3)
            put(grb_Eep_Pgm_Motor_Idle, 0, 1)
            put(grb_Eep_Pgm_Low_Voltage_Lim, 0, 1)
            put(grb_Eep_Pgm_Gov_Mode, 0, 1)
            put(grb_Eep_Pgm_Motor_Gain, 0, 2)
            put(grb_Eep_Pgm_Gov_P_Gain, 0, 2)
            put(grb_Eep_Pgm_Gov_I_Gain, 0, 3)
            put(grb_Eep_Pgm_Gov_Range, 0, 4)
            put(grb_Eep_Pgm_Gov_Setup_Target, 0, 6)
            put(grb_ESC_Description, 1, 0)
            put(grb_Eep_Pgm_Direction, 1, 1)
            put(grb_Eep_Pgm_Demag_Comp, 1, 2)
            put(grb_Eep_Pgm_Comm_Timing, 1, 3)
            put(grb_Eep_Pgm_Startup_Accel, 1, 3)
            put(grb_Eep_Pgm_Main_Spoolup_Time, 1, 3)
            put(grb_Eep_Pgm_Pwm_Dither, 1, 3)
            put(grb_Eep_Pgm_Startup_Method, 1, 4)
            put(grb_Eep_Pgm_Throttle_Rate, 1, 5)
            put(grb_MotorGearSetup, 1, 6)
            put(grb_Misc, 2, 0)
            put(grb_Eep_Pgm_Ppm_Min_Throttle, 2, 1)
            put(grb_Eep_Pgm_Ppm_Max_Throttle, 2, 2)
            put(grb_Eep_Pgm_Ppm_Center_Throttle, 2, 3)
            put(grb_Eep_Pgm_Brake_On_Stop, 2, 4)
            put(grb_Eep_Pgm_Volt_Comp, 2, 2)
            put(grb_Eep_Pgm_Pwm_Freq, 2, 3)
            put(grb_Eep_Pgm_Damping_Force, 2, 4)
            put(grb_Eep_Pgm_Enable_Pwm_Input, 2, 4)
            put(grb_Eep_Pgm_LED_Control, 3, 0)
            put(grb_Eep_Pgm_Input_Pol, 3, 1)
            put(grb_Eep_Pgm_Beep_Strength, 3, 1)
            put(grb_Eep_Pgm_Beacon_Strength, 3, 2)
            put(grb_Eep_Pgm_Beacon_Delay, 3, 3)
            put(grb_Eep_Pgm_BEC_Voltage_High, 3, 0)
        }
        if !bl.isValid {
            lblESCMode.caption = "???"
            lblFirmwareRevision.caption = "xx.x"
            lblESCMode.font.color = 0x808080
            grb_ESC_Description.hint = NL("Setup data still invalid.\\nPlease Read a valid ESC Setup")
            grb_ESC_Description.font.color = 0x808080
            lblFirmwareRevision.font.color = 0x808080
        } else {
            lblFirmwareRevision.caption = bl.revisionString
            grb_ESC_Description.font.color = 0xFF0000
            lblRevision_header.caption = bl.isS ? "BLHeli_S Revision:" : "BLHeli Revision:"
            if Brand.current == 1 {
                lblFirmwareRevision.font.color = bl.isS ? 0xFF00FF : 0x45127E
            } else if Brand.current == 2 {
                lblFirmwareRevision.font.color = 0xFF0000
            }
            var usage = ""
            switch bl.mode {
            case 0: lblESCMode.caption = "Main"; usage = NL("to be used for Heli Main motors"); lblESCMode.font.color = 0x808000
            case 1: lblESCMode.caption = "Tail"; usage = NL("to be used for Heli Tail motors"); lblESCMode.font.color = 0xFF
            case 2: lblESCMode.caption = "Multicopter"; usage = NL("to be used for Multicopter motors"); lblESCMode.font.color = 0xFF0000
            default: break
            }
            let rev = bl.revision
            let damped = ctx.supportsDampedLight
            var dampText = ""
            if rev < 500 { dampText = NL(damped ? "- supports \"Damped\" mode" : "- no \"Damped\" mode support in this rev.") }
            if rev < 0x4B0 {
                if rev >= 500 { dampText = NL(damped ? "- supports fully \"Damped\" mode" : "- supports only \"Damped Light\" mode in this rev.") }
            } else {
                dampText = NL(damped ? "- supports \"Damped Light\" mode" : "- no \"Damped Light\" mode support in this rev.")
            }
            let fw = bl.isS ? "BLHeli_S" : "BLHeli"
            var bec = ""
            if let b = ctx.layout?.becHV, b != 0 { bec = NL("- supports switchable BEC voltage [Steps: ") + "\(b)" + "]" }
            let special = NL("Special ESC hardware info:") + "\r\n" + dampText + "\r\n" + bec
            let slot = main?.slots[escNo]
            let dev = (slot.map { Int($0.deviceType) < deviceTypeNames.count ? deviceTypeNames[Int($0.deviceType)] : "" }) ?? ""
            let body = DFormat(NL("\\n\\n       %s\\n\\n       with %s rev: %s\\n       (Eep_Layout_Rev %d)\\n       %s %s\\n\\n%s\\n\\n%s\\n\\n"),
                               [ctx.layout?.displayName ?? bl.layoutName, fw, bl.revisionString, bl.value(.layoutRevision), dev, slot?.signature ?? "", usage, special])
            grb_ESC_Description.hint = NL("Valid ESC Setup loaded for ESC:") + body
        }
        lblMotors.left = lblESCMode.left + lblESCMode.width + 5
        for (raw, c) in params {
            guard let g = c.grb else { continue }
            let vis = exists(raw)
            g.visible = vis
            guard vis, let p = BLHeliParam(rawValue: raw) else { continue }
            g.caption = p.displayName(ctx)
            let r = BLHeliParamLogic.range(p, ctx)
            if let sb = c.scb as? TScrollBar { sb.setParams(position: sb.position, min: r.lowerBound, max: r.upperBound) }
            if let tb = c.scb as? TTrackBar { tb.min = r.lowerBound; tb.max = r.upperBound; tb.needsDisplay = true }
            g.hint = hintText(p, ctx)
        }
        cbx_Eep_Enable_TX_Setup.visible = exists(0x10)
        if cbx_Eep_Enable_TX_Setup.visible { cbx_Eep_Enable_TX_Setup.hint = hintText(.enableTxProgramming, ctx) }
        cbx_Eep_Gov_Rearm_Start.visible = exists(0x11)
        if cbx_Eep_Gov_Rearm_Start.visible { cbx_Eep_Gov_Rearm_Start.hint = hintText(.rearmAtStart, ctx) }
        grb_Misc.visible = cbx_Eep_Enable_TX_Setup.visible || cbx_Eep_Gov_Rearm_Start.visible || !bl.isValid
        grb_Eep_Name.caption = DFormat("ESC# %d - Name", [escNo])
        grb_Eep_Name.hint = DFormat(NL("ESC# %d - Name:\\nName of the individual ESC.\\nMay help to avoid confusion."), [escNo])
        grb_Eep_Name.enabled = !bl.isFlashFailed
        updateMotorGearSetup()       // FUN_00654354
        if exists(0x29) {
            let n = Int(ctx.layout?.leds ?? 0)
            let lees = [lee_Eep_Pgm_LED_Control_1, lee_Eep_Pgm_LED_Control_2, lee_Eep_Pgm_LED_Control_3, lee_Eep_Pgm_LED_Control_4]
            let lbes = [lbe_Eep_Pgm_LED_Control_1, lbe_Eep_Pgm_LED_Control_2, lbe_Eep_Pgm_LED_Control_3, lbe_Eep_Pgm_LED_Control_4]
            for i in 0..<4 { lees[i]?.visible = i < n; lbes[i]?.visible = i < n }
            lbl_Eep_Pgm_LED_Control.width = n * ((lbe_Eep_Pgm_LED_Control_1?.width ?? 24) + 4) + 3
        }
        lblBrand.visible = Brand.current != 0
        lblCopyright.visible = Brand.current != 0
        if Brand.current == 1 {
            lblBrand.caption = "SiLabs"
            lblBrand.font.color = 4526718
            lblCopyright.font.color = 4526718
        } else if Brand.current == 2 {
            lblBrand.caption = "Atmel"
            lblBrand.font.color = 0xA85F1F
            lblCopyright.font.color = 0xA85F1F
        }
    }

    /// FUN_005A9C70: parameter hint.
    func hintText(_ p: BLHeliParam, _ ctx: ParamContext) -> String {
        guard BLHeliParamLogic.exists(p, ctx) else { return "" }
        let r = BLHeliParamLogic.range(p, ctx)
        let def = BLHeliParamLogic.defaultValue(p, ctx) ?? r.lowerBound
        func lab(_ v: Int) -> String { BLHeliParamLogic.label(p, value: v, ctx) }
        func list() -> String {
            var s = ""
            for v in r { s += "\n" + String(v).padding(toLength: 2, withPad: " ", startingAt: 0) + " = " + lab(v) }
            return s + "\n\nDefault = " + lab(def)
        }
        func numeric() -> String {
            let d = lab(def) == String(def) ? String(def) : "\(def) = \(lab(def))"
            return DFormat(NL("\\nValue Range %d..%d\\nDefault: %s"), [r.lowerBound, r.upperBound, d])
        }
        var body = ""
        switch p.rawValue {
        case 4...10, 12, 13, 0x13...0x19, 0x24...0x28: body = list()
        case 11:
            body = list()
            if !ctx.supportsDampedLight {
                body += "\n" + (ctx.layoutRevision < 0x12 && ctx.layoutRevision > 10 ? "ESC hardware does not support full Damped mode" : "ESC hardware does not support Damped mode")
            }
        case 0x10:
            body = list() + "\n" + NL("Remove checkmark here if programming by transmitter is not needed\\nto prevent the ESC from entering programming mode unintentionally.\\n(Remark: unchecking will also disable ESC throttle calibration mode)")
        case 0x11:
            body = list() + "\n" + NL("Set checkmark to activate motor re-arming procedure after every stop of the motor.\\n(Remark: may be useful for MAIN ESCs if Governor Mode = ARM)")
        case 0x12:
            body = numeric() + "\n" + NL("Set and/or lookup the resulting head speed in Governormode here.")
        case 0x1A:
            body = DFormat(NL("%s\\n%s (us)\\nDifference between MIN and MAX must not fall below %d (us)"), [numeric(), ">= 1000", (ctx.isBLHeliS ? 0x23 : 0x82) * 4])
        case 0x1B:
            body = DFormat(NL("%s\\n%s (us)\\nDifference between MIN and MAX must not fall below %d (us)"), [numeric(), "<= 2020", (ctx.isBLHeliS ? 0x23 : 0x82) * 4])
        case 0x1C:
            body = numeric() + "\n\n" + NL("Determines the volume of the ESC startup beep tones.")
        case 0x1D:
            body = numeric()
            if ctx.isBLHeliS { body += "\n\n" + NL("Determines the volume of the ESC beacon and\\nDShot initiated signal tones.") }
        case 0x1E...0x21:
            body = r.lowerBound == r.upperBound ? "\n" + "ESC hardware does not support this feature" : list()
        case 0x22, 0x23: body = numeric()
        case 0x29:
            if r.lowerBound == r.upperBound { body = "\n" + "ESC hardware does not support this feature" } else {
                body = numeric() + DFormat(NL("\\n%d = All Off\\n%d = All ON"), [0, r.upperBound])
                for i in 1...max(1, Int(ctx.layout?.leds ?? 0)) { body += DFormat(NL("\\nLED%d = Bits %d,%d"), [i, (i - 1) * 2, (i - 1) * 2 + 1]) }
            }
        default: break
        }
        if !body.isEmpty { body = ":" + body }
        return p.displayName(ctx) + body
    }

    /// FUN_00653AC0: value of one parameter into scroll bar, LED and value label.
    func showValue(_ raw: Int) {
        guard exists(raw), let p = BLHeliParam(rawValue: raw) else { return }
        let v = bl.value(p)
        if let c = params[raw] {
            if let sb = c.scb as? TScrollBar { sb.setPositionSilently(v) }
            if let tb = c.scb as? TTrackBar { tb.setPositionSilently(v) }
            c.led?.caption = String(v)
            c.lbl?.caption = bl.valueText(p, v, db)
        }
        if raw == 0x10 { cbx_Eep_Enable_TX_Setup.setChecked(v == 1) }
        if raw == 0x11 { cbx_Eep_Gov_Rearm_Start.setChecked(v == 1) }
    }

    /// FUN_00654220: LED control.
    func showLED() {
        guard exists(0x29) else { return }
        let v = bl.value(.ledControl)
        let n = Int(bl.context(db).layout?.leds ?? 0)
        let lees = [lee_Eep_Pgm_LED_Control_1, lee_Eep_Pgm_LED_Control_2, lee_Eep_Pgm_LED_Control_3, lee_Eep_Pgm_LED_Control_4]
        let lbes = [lbe_Eep_Pgm_LED_Control_1, lbe_Eep_Pgm_LED_Control_2, lbe_Eep_Pgm_LED_Control_3, lbe_Eep_Pgm_LED_Control_4]
        var mask = 3
        for i in 0..<min(n, 4) {
            lees[i]?.isOn = (v & mask) == mask
            lbes[i]?.caption = (lees[i]?.isOn ?? false) ? "On" : "Off"
            mask <<= 2
        }
        led_Eep_Pgm_LED_Control.caption = String(v)
    }

    func ledClicked(_ s: TControl) {
        guard !updating, exists(0x29) else { return }
        let lees: [TControl?] = [lee_Eep_Pgm_LED_Control_1, lee_Eep_Pgm_LED_Control_2, lee_Eep_Pgm_LED_Control_3, lee_Eep_Pgm_LED_Control_4]
        let lbes: [TControl?] = [lbe_Eep_Pgm_LED_Control_1, lbe_Eep_Pgm_LED_Control_2, lbe_Eep_Pgm_LED_Control_3, lbe_Eep_Pgm_LED_Control_4]
        guard let i = lees.firstIndex(where: { $0 === s }) ?? lbes.firstIndex(where: { $0 === s }) else { return }
        let bits = 3 << (2 * i)
        var v = bl.value(.ledControl)
        if v & bits == bits { v &= ~bits } else { v |= bits }
        bl.setValue(.ledControl, v)
        updating = true
        showLED()
        updateUndoDefault()
        updating = false
    }

    /// FUN_00654908: frame size from the visible boxes.
    func adjustSize() {
        var maxTop = 0, maxLeft = 0
        for (raw, c) in params where exists(raw) {
            if let g = c.grb { maxTop = max(maxTop, g.top); maxLeft = max(maxLeft, g.left) }
        }
        for g in [grb_Eep_Name, grb_ESC_Description, grb_Misc] as [TControl?] {
            if let g, g.visible { maxTop = max(maxTop, g.top); maxLeft = max(maxLeft, g.left) }
        }
        if grb_MotorGearSetup.visible { maxTop = max(maxTop, grb_MotorGearSetup.top) }
        maxLeft = max(maxLeft, TfraESCCombos.lefts[3])
        setBounds(left, top, maxLeft + 0xC3, maxTop + 0x44)
        pnlSetupMain.setBounds(0, 0, width, height)
    }

    /// FUN_00654988: LED / value label colours depending on the validity of the value.
    func updateValidity() {
        for raw in 0..<0x2E {
            if raw == 0x10 {
                let ok = isValidValue(raw)
                cbx_Eep_Enable_TX_Setup.enabled = ok
                grb_Misc.hint = ok ? "" : NL("Programming by TX is ignored when Motor Direction is set to Bidirectional.")
                continue
            }
            if raw == 0x11 { cbx_Eep_Gov_Rearm_Start.enabled = isValidValue(raw); continue }
            guard exists(raw), let c = params[raw] else { continue }
            if !isValidValue(raw) {
                c.led?.frameColor = 0xC0C0C0
                c.led?.color = 0xC0C0C0
                c.led?.font.color = 0x808080
                c.lbl?.frameColor = clNone
                c.lbl?.color = c.grb?.color ?? clBtnFace
                if let sb = c.scb { sb.hint = "" }
            } else {
                c.led?.frameColor = 0x808080
                c.led?.color = 0x808080
                c.led?.font.color = 0xFF00
                c.lbl?.frameColor = 0x808080
                if Brand.current == 1 { c.lbl?.color = bl.isS ? ValueColors.silabsS : ValueColors.silabs }
                else if Brand.current == 2 { c.lbl?.color = ValueColors.avr }
            }
        }
    }

    /// FUN_005A6414.
    func isValidValue(_ raw: Int) -> Bool {
        guard let p = BLHeliParam(rawValue: raw), bl.isValid else { return false }
        let ctx = bl.context(db)
        if raw == 0x10 && BLHeliParamLogic.exists(.direction, ctx) && bl.value(.direction) >= 3 { return false }
        return BLHeliParamLogic.isValid(p, value: bl.value(p), ctx)
    }

    /// FUN_00654C98: enable state of the Undo / Default buttons.
    func updateUndoDefault() {
        let orig = original
        let nameChanged = bl.name != orig.name
        sbtnDEFAULT_Eep_Name.enabled = !bl.name.isEmpty
        sbtnUNDO_Eep_Name.enabled = nameChanged
        let ctx = bl.context(db)
        func changed(_ p: BLHeliParam) -> Bool { exists(p.rawValue) && isValidValue(p.rawValue) && bl.value(p) != orig.value(p) }
        func notDefault(_ p: BLHeliParam) -> Bool {
            exists(p.rawValue) && isValidValue(p.rawValue) && BLHeliParamLogic.defaultValue(p, ctx) != bl.value(p)
        }
        sbtnUNDO_Misc.enabled = changed(.enableTxProgramming) || changed(.rearmAtStart)
        sbtnDEFAULT_Misc.enabled = notDefault(.enableTxProgramming) || notDefault(.rearmAtStart)
        for (raw, c) in params {
            guard let p = BLHeliParam(rawValue: raw), exists(raw) else { continue }
            c.undo?.enabled = orig.isValid && bl.value(p) != orig.value(p)
            c.def?.enabled = BLHeliParamLogic.defaultValue(p, ctx).map { $0 != bl.value(p) } ?? false
        }
    }

    // MARK: - changes (FUN_006515E0)

    /// FUN_00651BD4: PPM Min/Max of the setup must form a valid pair, otherwise both are set to their defaults
    /// and the change is not applied.
    func checkPPMRange() -> Bool {
        let gap = bl.isS ? 0x23 : 0x82
        let mn = bl.value(.ppmMinThrottle), mx = bl.value(.ppmMaxThrottle)
        guard mx <= mn || mx < gap || mn > 0xFF - gap else { return true }
        MsgDlg.show(NL("Invalid PPM Min/Max Throttle parameter value combination was found\\nParameters will be set to default."),
                    .mtWarning, [.mbOK])
        if let d = bl.defaultValue(.ppmMinThrottle, db) { bl.setValue(.ppmMinThrottle, d) }
        if let d = bl.defaultValue(.ppmMaxThrottle, db) { bl.setValue(.ppmMaxThrottle, d) }
        showValue(0x1A)
        showValue(0x1B)
        return false
    }

    func paramChanged(_ s: TControl) {
        guard Brand.current != 0, !updating else { return }
        updating = true
        defer { updating = false }
        let raw = s.tag
        guard raw != 0 else { return }
        var v = 0
        if let sb = s as? TScrollBar { v = sb.position } else if let tb = s as? TTrackBar { v = tb.position }
        else if let cb = s as? TCheckBox { v = cb.checked ? 1 : 0 }
        let ctx = bl.context(db)
        let gap = bl.isS ? 0x23 : 0x82
        switch raw {
        case 0x1A:
            guard checkPPMRange() else { return }
            if let mx = (params[0x1B]?.scb as? TScrollBar)?.position, mx - v < gap, v <= mx { v = mx - gap }
        case 0x1B:
            guard checkPPMRange() else { return }
            if let mn = (params[0x1A]?.scb as? TScrollBar)?.position, v - mn < gap { v = mn + gap }
        case 0x22:
            if let mn = (params[0x1A]?.scb as? TScrollBar)?.position, v - mn < 1 { v = mn + 1 }
            if let mx = (params[0x1B]?.scb as? TScrollBar)?.position, mx - v < 1 { v = mx - 1 }
        case 0x2D:
            bl.settings.name = edt_Eep_Name.textValue
            updateUndoDefault()
            main?.updateCopyPaste()
            return
        default: break
        }
        guard let p = BLHeliParam(rawValue: raw) else { return }
        let r = BLHeliParamLogic.range(p, ctx)
        v = min(max(v, r.lowerBound), r.upperBound)
        bl.setValue(p, v)
        showValue(raw)
        switch raw {
        case 6, 0xB, 0xC, 0x19, 0x1E: updateValidity()
        case 0x12: updateGovernorTarget()
        case 0x18: showValue(0x18); updateGovernorTarget()
        case 0x1A, 0x1B: showValue(0x1A); showValue(0x1B); showValue(0x22)
        default: break
        }
        if raw == 0xC { layoutParamsKeepValues() }
        updateUndoDefault()
        main?.updateCopyPaste()
    }

    func layoutParamsKeepValues() {
        updateValidity()
    }

    func undoClick(_ s: TControl) {
        let raw = s.tag
        let orig = original
        if raw == 0x2D {
            bl.settings.name = orig.name
        } else if raw == 0x10 {
            bl.setValue(.enableTxProgramming, orig.value(.enableTxProgramming))
            bl.setValue(.rearmAtStart, orig.value(.rearmAtStart))
        } else if let p = BLHeliParam(rawValue: raw) {
            bl.setValue(p, orig.value(p))
        }
        updateAll()
        main?.updateCopyPaste()
    }

    func defaultClick(_ s: TControl) {
        let raw = s.tag
        let ctx = bl.context(db)
        if raw == 0x2D {
            bl.settings.name = ""
        } else if raw == 0x10 {
            for p in [BLHeliParam.enableTxProgramming, .rearmAtStart] { if let d = BLHeliParamLogic.defaultValue(p, ctx) { bl.setValue(p, d) } }
        } else if let p = BLHeliParam(rawValue: raw), let d = BLHeliParamLogic.defaultValue(p, ctx) {
            bl.setValue(p, d)
        }
        updateAll()
        main?.updateCopyPaste()
    }

    // MARK: - main motor governor (FUN_00653C44, FUN_00654354, FUN_00651D20/FUN_00651FEC)

    var motorSetups: [String] = []

    func loadMotorSetups() {
        guard let f = AppFolders.find("Settings")?.appendingPathComponent("MotorGovSetup.txt") else { return }
        let ini = TIniFile(url: f)
        motorSetups = ini.sectionNames()
        cbxMotorSetups.items = motorSetups
    }

    func updateMotorGearSetup() {
        let show = exists(0x12) && bl.mode == 0
        grb_MotorGearSetup.visible = show
        if show { grb_MotorGearSetup.caption = "Motor / Gear Setup" }
    }

    func applyMotorSetup() {
        guard let f = AppFolders.find("Settings")?.appendingPathComponent("MotorGovSetup.txt") else { return }
        let ini = TIniFile(url: f)
        let s = cbxMotorSetups.text_
        sedLipo_s.intValue = ini.readInteger(s, "LipoCells", 2)
        sedMotorKV.intValue = ini.readInteger(s, "KV", 1000)
        sedMotorPole.intValue = ini.readInteger(s, "Pole", 2)
        sedPinionTeeth.intValue = ini.readInteger(s, "Teeth", 10)
        sedMainGearTeeth.intValue = ini.readInteger(s, "MainGearTeeth", 100)
        sedMotorComp.intValue = ini.readInteger(s, "KVCompensation", 81)
        updateGovernorTarget()
    }

    func updateGovernorTarget() {
        guard exists(0x12) else { return }
        let v = bl.value(.govSetupTarget)
        let cells = Double(max(1, sedLipo_s.intValue)), kv = Double(sedMotorKV.intValue)
        let comp = Double(sedMotorComp.intValue) / 100
        let pinion = Double(max(1, sedPinionTeeth.intValue)), gear = Double(max(1, sedMainGearTeeth.intValue))
        let maxRPM = cells * 3.7 * kv * comp
        let percent = Int((Double(v) * 100 / 255).rounded())
        let motor = Int((maxRPM * Double(v) / 255).rounded())
        lblMotorPercentage1.caption = DFormat("%d%%", [percent])
        lbl_Eep_Pgm_Gov_Setup_Target.caption = DFormat("Motor: %d RPM = %d%%", [motor, percent]) +
            (gear > 0 ? "" : "")
        _ = pinion
    }

    func dataLoaded() {
        if bl.isValid && bl.mode == 0, cbxMotorSetups.text_.isEmpty, let f = motorSetups.first { cbxMotorSetups.text_ = f; applyMotorSetup() }
    }

    // MARK: - design simple (FUN_006512C8)

    func setDesignSimple(_ simple: Bool) {
        designSimple = simple
        for case let g as TGroupBox in pnlSetupMain.subviews {
            for case let k as TControl in g.subviews {
                let n = k.name
                if n.hasPrefix("led_") {
                    k.visible = !simple
                } else if n.hasPrefix("lbl_") && k !== lbl_Eep_Pgm_Gov_Setup_Target {
                    k.setBounds(simple ? 3 : 0x27, 0x10, simple ? 0x97 : 0x73, 0xF)
                } else if n.hasPrefix("scb_") && !(k is TTrackBar) {
                    k.setBounds(simple ? 3 : 0x28, 0x22, simple ? 0x98 : 0x73, 0xF)
                } else if n.hasPrefix("trb_") || (n.hasPrefix("scb_") && k is TTrackBar) {
                    k.setBounds(simple ? 3 : 0x28, 0x1D, simple ? 0x98 : 0x73, 0x17)
                }
            }
        }
        if !pnlSetupMain.isHidden { updateAll() }
    }

    // MARK: - paste (FUN_005A65C8)

    func pasteSetup(from src: TBLHeli, syncThrottle: Bool, syncDirection: Bool) -> Bool {
        guard src.isValid, bl.isValid, src.mode == bl.mode else { return false }
        let ctx = bl.context(db)
        for raw in 4..<42 {
            guard let p = BLHeliParam(rawValue: raw), BLHeliParamLogic.exists(p, ctx) else { continue }
            if p == .direction && !syncDirection { continue }
            if (p == .ppmMinThrottle || p == .ppmMaxThrottle || p == .ppmCenterThrottle) && !syncThrottle { continue }
            let v = src.value(p)
            if BLHeliParamLogic.isValid(p, value: v, ctx) { bl.setValue(p, v) }
        }
        return true
    }

    /// The workspace is edited in place; nothing to collect.
    func collect(into t: TBLHeli) {}
}

// MARK: - motor / gear setup spin edits and governor target track bar

extension TfraESCCombos {
    /// grb_MotorGearSetupEnter (0x64FF18) – OnEnter of the spin edits in "Motor / Gear Setup":
    /// the focused spin edit shows its buttons and gets 5 pixels wider.
    @objc func grb_MotorGearSetupEnter(_ sender: TObject) {
        guard let e = sender as? TSpinEdit, !e.showButton else { return }
        e.showButton = true
        e.width = e.width + 5
    }

    /// grb_MotorGearSetupExit (0x64FF5C)
    @objc func grb_MotorGearSetupExit(_ sender: TObject) {
        guard let e = sender as? TSpinEdit, e.showButton else { return }
        e.showButton = false
        e.width = e.width - 5
    }

    /// No hint while the governor target track bar is dragged (0x651240 / 0x651254).
    @objc func scb_Eep_Pgm_Gov_Setup_TargetMouseDown(_ sender: TObject, _ a: TMouseArgs) {
        grb_Eep_Pgm_Gov_Setup_Target.showHint = false
    }

    @objc func scb_Eep_Pgm_Gov_Setup_TargetMouseUp(_ sender: TObject, _ a: TMouseArgs) {
        grb_Eep_Pgm_Gov_Setup_Target.showHint = true
    }
}
