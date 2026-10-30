import Foundation

/// ESC operating mode stored in Eep_Initialized_L/H (FUN_005a59a0).
public enum ESCMode: Int, Codable, Sendable, CaseIterable {
    case main = 0, tail = 1, multi = 2, invalid = 3

    public var displayName: String {
        switch self {
        case .main: return "MAIN"
        case .tail: return "TAIL"
        case .multi: return "MULTI"
        case .invalid: return "INVALID"
        }
    }

    public init(initL: UInt8, initH: UInt8) {
        switch (initL, initH) {
        case (0xA5, 0x5A): self = .main
        case (0x5A, 0xA5): self = .tail
        case (0x55, 0xAA): self = .multi
        default: self = .invalid
        }
    }

    public var signature: (UInt8, UInt8) {
        switch self {
        case .main: return (0xA5, 0x5A)
        case .tail: return (0x5A, 0xA5)
        case .multi, .invalid: return (0x55, 0xAA)
        }
    }
}

/// Parameter index as used by TBLHeli (EEPROM offset + 1, table at 0x68E2A8 / 0x68E418).
public enum BLHeliParam: Int, CaseIterable, Sendable {
    case invalid = 0
    case mainRevision, subRevision, layoutRevision
    case govPGain, govIGain, govMode, lowVoltageLimit, motorGain, motorIdle, startupPower
    case pwmFrequency, direction, inputPolarity, initializedL, initializedH
    case enableTxProgramming, rearmAtStart, govSetupTarget, startupRpm, startupAccel
    case voltageCompensation, commutationTiming, dampingForce, govRange, startupMethod
    case ppmMinThrottle, ppmMaxThrottle, beepStrength, beaconStrength, beaconDelay
    case throttleRate, demagCompensation, becVoltageHigh, ppmCenterThrottle, spoolupTime
    case temperatureProtection, lowRpmPowerProtection, pwmInput, pwmDither, brakeOnStop
    case ledControl, dummy, escLayout, escMCU, name

    /// EEPROM offset (0x68E418 table).
    public var eepromOffset: Int {
        switch self {
        case .invalid, .dummy: return -1
        case .escLayout: return 0x40
        case .escMCU: return 0x50
        case .name: return 0x60
        default: return rawValue - 1
        }
    }

    public var eepName: String { BLHeliParam.eepNames[rawValue] }

    /// Display name used by BLHeliSuite (0x68E360 table + FUN_005ab2f0 overrides).
    public func displayName(_ c: ParamContext) -> String {
        switch self {
        case .govPGain, .govIGain, .govMode:
            let base = BLHeliParam.displayNames[rawValue]
            return c.mode == .multi ? base.replacingOccurrences(of: "Governor", with: "Closed Loop") : base
        case .beaconStrength:
            // FUN_005a6048: "Beacon/Signal Volume" only for BLHeli_S newer than 16.60.
            return (c.isBLHeliS && c.revision > 0x67C) ? BLHeliParam.displayNames[rawValue] : "Beacon Volume"
        default:
            return BLHeliParam.displayNames[rawValue]
        }
    }

    public var plainName: String { BLHeliParam.displayNames[rawValue] }

    static let eepNames: [String] = [
        "Eep_Invalid", "Eep_FW_Main_Revision", "Eep_FW_Sub_Revision", "Eep_Layout_Revision",
        "Eep_Pgm_Gov_P_Gain", "Eep_Pgm_Gov_I_Gain", "Eep_Pgm_Gov_Mode", "Eep_Pgm_Low_Voltage_Lim",
        "Eep_Pgm_Motor_Gain", "Eep_Pgm_Motor_Idle", "Eep_Pgm_Startup_Pwr", "Eep_Pgm_Pwm_Freq",
        "Eep_Pgm_Direction", "Eep_Pgm_Input_Pol", "Eep_Initialized_L", "Eep_Initialized_H",
        "Eep_Enable_TX_Setup", "Eep_Gov_Rearm_Start", "Eep_Pgm_Gov_Setup_Target", "Eep_Pgm_Startup_Rpm",
        "Eep_Pgm_Startup_Accel", "Eep_Pgm_Volt_Comp", "Eep_Pgm_Comm_Timing", "Eep_Pgm_Damping_Force",
        "Eep_Pgm_Gov_Range", "Eep_Pgm_Startup_Method", "Eep_Pgm_Ppm_Min_Throttle", "Eep_Pgm_Ppm_Max_Throttle",
        "Eep_Pgm_Beep_Strength", "Eep_Pgm_Beacon_Strength", "Eep_Pgm_Beacon_Delay", "Eep_Pgm_Throttle_Rate",
        "Eep_Pgm_Demag_Comp", "Eep_Pgm_BEC_Voltage_High", "Eep_Pgm_Ppm_Center_Throttle", "Eep_Pgm_Main_Spoolup_Time",
        "Eep_Pgm_Temp_Prot_Enable", "Eep_Pgm_Enable_Power_Prot", "Eep_Pgm_Enable_Pwm_Input", "Eep_Pgm_Pwm_Dither",
        "Eep_Pgm_Brake_On_Stop", "Eep_Pgm_LED_Control", "Eep_Dummy", "Eep_ESC_Layout", "Eep_ESC_MCU", "Eep_Name",
    ]

    static let displayNames: [String] = [
        "Invalid", "Main Revision", "Sub Revision", "Eeprom Layout Revision",
        "Governor P-Gain", "Governor I-Gain", "Governor Mode", "Low Voltage Limiter",
        "Motor Gain", "Motor Idle", "Startup Power", "PWM Frequency/Damped",
        "Motor Direction", "Input Polarity", "ESC Mode Lo", "ESC Mode Hi",
        "Programming by TX", "Rearming every Start", "Governor Target RPM", "Startup RPM",
        "Startup Acceleration", "Voltage Compensation", "Motor Timing", "Damping Force",
        "Governor Range", "Startup Method", "PPM Min Throttle", "PPM Max Throttle",
        "Startup Beep Volume", "Beacon/Signal Volume", "Beacon Delay", "Throttle Change Rate",
        "Demag Compensation", "BEC Output Voltage", "PPM Center Throttle", "Spoolup Time",
        "Temperature Protection", "Low RPM Power Protect", "Enable PWM Input", "PWM Output Dither",
        "Brake On Stop", "LED Control", "Dummy", "ESC Layout", "ESC MCU", "Name",
    ]

    /// Parameters shown as editable controls in the ESC setup page (in BLHeliSuite order).
    public static let editable: [BLHeliParam] = [
        .govPGain, .govIGain, .govMode, .lowVoltageLimit, .motorGain, .motorIdle, .startupPower,
        .pwmFrequency, .direction, .inputPolarity, .govSetupTarget, .startupRpm, .startupAccel,
        .voltageCompensation, .commutationTiming, .dampingForce, .govRange, .startupMethod,
        .ppmMinThrottle, .ppmCenterThrottle, .ppmMaxThrottle, .beepStrength, .beaconStrength, .beaconDelay,
        .throttleRate, .demagCompensation, .becVoltageHigh, .spoolupTime, .temperatureProtection,
        .lowRpmPowerProtection, .pwmInput, .pwmDither, .brakeOnStop, .ledControl,
        .enableTxProgramming, .rearmAtStart,
    ]

    /// True for parameters that are rendered as a raw numeric value (slider) instead of a list.
    public var isNumeric: Bool {
        switch self {
        case .govSetupTarget, .ppmMinThrottle, .ppmMaxThrottle, .ppmCenterThrottle,
             .beepStrength, .beaconStrength, .spoolupTime:
            return true
        default:
            return false
        }
    }

    public var isBoolean: Bool {
        switch self {
        case .enableTxProgramming, .rearmAtStart: return true
        default: return false
        }
    }
}

/// Everything the parameter logic needs to know about the ESC/firmware the values belong to.
public struct ParamContext: Equatable, Sendable {
    public var layoutRevision: UInt8
    /// main * 100 + sub * 10 (sub < 10) or main * 100 + sub (FUN_005a5734).
    public var revision: Int
    public var isBLHeliS: Bool
    public var family: MCUFamily
    public var mode: ESCMode
    /// Layout record (cells, damped since rev X, BEC, LED count) – may be unknown.
    public var layout: ESCLayout?
    /// Firmware database entry for per-file defaults (startup power/method, spoolup).
    public var firmware: FirmwareEntry?

    public init(layoutRevision: UInt8, revision: Int, isBLHeliS: Bool, family: MCUFamily, mode: ESCMode,
                layout: ESCLayout? = nil, firmware: FirmwareEntry? = nil) {
        self.layoutRevision = layoutRevision
        self.revision = revision
        self.isBLHeliS = isBLHeliS
        self.family = family
        self.mode = mode
        self.layout = layout
        self.firmware = firmware
    }

    var supportsDampedLight: Bool {
        guard let l = layout else { return false }
        return l.damped <= layoutRevision
    }
}

public enum BLHeliParamLogic {
    // MARK: existence – FUN_005aa830

    public static func exists(_ p: BLHeliParam, _ c: ParamContext) -> Bool {
        let lr = c.layoutRevision
        let s = c.isBLHeliS
        let m = c.mode
        switch p {
        case .mainRevision, .subRevision, .layoutRevision: return true
        case .govPGain, .govIGain, .govMode:
            return !s && (m == .main || (lr > 0x0F && m == .multi))
        case .lowVoltageLimit:
            return !s && m != .tail && (m != .multi || lr < 0x14)
        case .motorGain: return !s && (m == .tail || m == .multi)
        case .motorIdle: return !s && m == .tail
        case .startupPower: return true
        case .pwmFrequency: return !s
        case .direction: return true
        case .inputPolarity: return !s
        case .initializedL, .initializedH: return true
        case .enableTxProgramming: return lr > 7
        case .rearmAtStart: return !s && lr > 8 && m == .main
        case .govSetupTarget: return !s && lr > 9 && m == .main
        case .startupRpm, .startupAccel: return !s && lr > 9 && lr < 0x13 && c.family == .silabs
        case .voltageCompensation: return !s && lr > 9 && lr < 0x0E
        case .commutationTiming: return lr > 10
        case .dampingForce: return !s && lr > 10 && lr < 0x13
        case .govRange: return !s && lr > 0x0B && m == .main
        case .startupMethod: return !s && lr > 0x0C && lr < 0x13 && c.family == .silabs
        case .ppmMinThrottle, .ppmMaxThrottle, .beepStrength, .beaconStrength, .beaconDelay: return lr > 0x0C
        case .throttleRate: return !s && lr > 0x0C && lr < 0x13
        case .demagCompensation: return lr > 0x0D
        case .becVoltageHigh: return !s && lr > 0x0F
        case .ppmCenterThrottle: return lr > 0x10 && (m == .tail || m == .multi)
        case .spoolupTime: return !s && lr > 0x11 && m == .main
        case .temperatureProtection: return lr > 0x11
        case .lowRpmPowerProtection: return lr > 0x13
        case .pwmInput: return !s && lr > 0x13
        case .pwmDither: return !s && lr > 0x13 && (m == .tail || m == .multi)
        case .brakeOnStop: return s || lr >= 0x15
        case .ledControl: return s && lr >= 0x20
        case .escLayout, .escMCU, .name: return true
        case .invalid, .dummy: return false
        }
    }

    // MARK: value ranges – FUN_005a8564

    public static func range(_ p: BLHeliParam, _ c: ParamContext) -> ClosedRange<Int> {
        let lr = c.layoutRevision
        let notMain = c.mode != .main
        switch p {
        case .mainRevision: return 2...0x40
        case .subRevision: return 0...9
        case .layoutRevision: return 7...0x40
        case .govPGain, .govIGain:
            if lr < 10 { return 1...5 }
            if c.revision < 400 { return 1...9 }
            return 1...13
        case .govMode: return lr < 10 ? 1...3 : 1...4
        case .lowVoltageLimit:
            if lr < 0x0E { return lr < 10 ? 1...3 : 1...5 }
            return 1...6
        case .motorGain, .motorIdle: return 1...5
        case .startupPower:
            if lr < 0x10 { return lr == 0x0F ? 1...7 : 1...5 }
            return 1...13
        case .pwmFrequency:
            let damped = c.supportsDampedLight
            if lr < 0x12 {
                if lr < 0x0B { return (notMain && damped) ? 1...3 : 1...2 }
                return (notMain && damped) ? 1...4 : 1...3
            }
            return damped ? 1...3 : 1...2
        case .direction:
            if lr < 0x20 { return (lr < 0x11 || !notMain) ? 1...2 : 1...3 }
            return 1...4
        case .inputPolarity: return 1...2
        case .enableTxProgramming, .rearmAtStart: return 0...1
        case .govSetupTarget: return 0...255
        case .startupRpm, .startupAccel: return 1...5
        case .voltageCompensation: return 1...2
        case .commutationTiming: return 1...5
        case .dampingForce: return lr < 0x10 ? 1...5 : 1...6
        case .govRange: return lr < 0x10 ? 1...2 : 1...3
        case .startupMethod: return 1...2
        case .ppmMinThrottle, .ppmMaxThrottle: return 0...255
        case .beepStrength, .beaconStrength: return 1...255
        case .beaconDelay: return 1...5
        case .throttleRate: return 1...13
        case .demagCompensation: return lr < 0x11 ? 1...5 : 1...3
        case .becVoltageHigh: return 0...Int(c.layout?.becHV ?? 0)
        case .ppmCenterThrottle, .spoolupTime: return 0...255
        case .temperatureProtection: return lr < 0x21 ? 0...1 : 0...7
        case .lowRpmPowerProtection, .pwmInput: return 0...1
        case .pwmDither: return 1...5
        case .brakeOnStop: return 0...1
        case .ledControl:
            var mask = 0, bits = 3
            for _ in 0..<Int(c.layout?.leds ?? 0) { mask |= bits; bits <<= 2 }
            return 0...mask
        default: return 0...255
        }
    }

    /// FUN_005aa7a8: parameter exists and the value is inside the allowed range.
    public static func isValid(_ p: BLHeliParam, value: Int, _ c: ParamContext) -> Bool {
        exists(p, c) && range(p, c).contains(value)
    }

    /// Values offered for a parameter. LED control only allows per-LED on/off combinations.
    public static func allowedValues(_ p: BLHeliParam, _ c: ParamContext) -> [Int] {
        let r = range(p, c)
        if p == .ledControl {
            let leds = Int(c.layout?.leds ?? 0)
            var out: [Int] = []
            for combo in 0..<(1 << leds) {
                var v = 0
                for k in 0..<leds where combo & (1 << k) != 0 { v |= 3 << (2 * k) }
                out.append(v)
            }
            return out
        }
        return Array(r)
    }

    // MARK: value labels – FUN_005a9324

    static let gains = ["", "x 0.13", "x 0.17", "x 0.25", "x 0.38", "x 0.50", "x 0.75", "x 1.00", "x 1.50",
                        "x 2.00", "x 3.00", "x 4.00", "x 6.00", "x 8.00"]
    static let govModesMain = ["", "Tx", "Arm", "Setup", "Off"]
    static let govModesMulti = ["", "HiRange", "MidRange", "LoRange", "Off"]
    static let lowVoltage = ["", "Off", "3.0 Volt / cell", "3.1 Volt / cell", "3.2 Volt / cell", "3.3 Volt / cell",
                             "3.4 Volt / cell", "2.7 Volt / cell", "3.0 Volt / cell", "3.3 Volt / cell"]
    static let motorGain = ["", "x 0.75", "x 0.88", "x 1.00", "x 1.12", "x 1.25"]
    static let motorIdle = ["", "Low", "MediumLow", "Medium", "MediumHigh", "High"]
    static let startupPower = ["", "0.031", "0.047", "0.063", "0.094", "0.125", "0.188", "0.25", "0.38",
                               "0.50", "0.75", "1.00", "1.25", "1.50"]
    static let pwmFrequency = ["", "High", "Low", "DampedLight", "Damped"]
    static let direction = ["", "Normal", "Reversed", "Bidirectional", "Bidirectional Rev."]
    static let polarity = ["", "Positive", "Negative"]
    static let offOn = ["Off", "On"]
    static let startupRpm = ["", "0.67", "0.80", "1.00", "1.25", "1.50"]
    static let startupAccel = ["", "0.4", "0.7", "1.0", "1.5", "2.3"]
    static let commTiming = ["", "Low", "MediumLow", "Medium", "MediumHigh", "High"]
    static let damping = ["", "VeryLow", "Low", "MediumLow", "MediumHigh", "High", "Highest"]
    static let govRange = ["", "High", "Middle", "Low"]
    static let startupMethod = ["", "Stepped", "Direct"]
    static let beaconDelayOld = ["", "30 seconds", "1 minute", "2 minutes", "3 minutes", "Infinite"]
    static let beaconDelayNew = ["", "1 minute", "2 minutes", "5 minutes", "10 minutes", "Infinite"]
    static let throttleRate = ["", "2", "3", "4", "6", "8", "12", "16", "24", "32", "48", "64", "128", "255"]
    static let demagOld = ["", "Off", "15/0", "15/7.5", "7.5/7.5", "7.5/15"]
    static let demagNew = ["", "Off", "Low", "High"]
    static let bec = ["Low", "High", "Higher", "Highest"]
    static let tempProt = ["Off", "80°C", "90°C", "100°C", "110°C", "120°C", "130°C", "140°C"]
    static let dither = ["", "Off", "3", "7", "15", "31", "63"]

    private static func pick(_ table: [String], _ i: Int) -> String {
        (i >= 0 && i < table.count && !table[i].isEmpty) ? table[i] : "\(i)"
    }

    public static func label(_ p: BLHeliParam, value: Int, _ c: ParamContext) -> String {
        guard isValid(p, value: value, c) else { return "Invalid (\(value))" }
        let lr = c.layoutRevision
        var v = value
        switch p {
        case .mainRevision, .subRevision, .layoutRevision, .govSetupTarget, .beaconStrength, .spoolupTime:
            return "\(v)"
        case .govPGain, .govIGain:
            if lr < 10 { v += 3 }
            return pick(gains, v)
        case .govMode:
            if c.mode == .main {
                if lr < 10 && v == 3 { v = 4 }
                return pick(govModesMain, v)
            }
            return pick(govModesMulti, v)
        case .lowVoltageLimit:
            if lr < 0x0E { v += (lr < 10) ? 6 : 1 }
            return pick(lowVoltage, v)
        case .motorGain: return pick(motorGain, v)
        case .motorIdle: return pick(motorIdle, v)
        case .startupPower:
            if lr < 0x10 { v += (lr == 0x0F) ? 6 : 8 }
            return pick(startupPower, v)
        case .pwmFrequency:
            if lr < 0x0B && v == 3 { v = 4 }
            return pick(pwmFrequency, v)
        case .direction: return pick(direction, v)
        case .inputPolarity: return pick(polarity, v)
        case .enableTxProgramming, .rearmAtStart, .lowRpmPowerProtection, .pwmInput, .brakeOnStop:
            return pick(offOn, v)
        case .startupRpm: return pick(startupRpm, v)
        case .startupAccel: return pick(startupAccel, v)
        case .voltageCompensation: return pick(offOn, v - 1)
        case .commutationTiming: return pick(commTiming, v)
        case .dampingForce: return pick(damping, v)
        case .govRange:
            if c.revision > 610 && c.revision < 1010 { v = 1 }
            return pick(govRange, v)
        case .startupMethod: return pick(startupMethod, v)
        case .ppmMinThrottle, .ppmMaxThrottle, .ppmCenterThrottle:
            return "\(v * 4 + 1000)"
        case .beepStrength:
            let r = c.revision
            if ((r < 1470 || r > 1609) && r < 1620) || v != 1 { return "\(v)" }
            return "Off"
        case .beaconDelay:
            return pick(c.revision < 1120 ? beaconDelayOld : beaconDelayNew, v)
        case .throttleRate: return pick(throttleRate, v)
        case .demagCompensation: return pick(lr < 0x11 ? demagOld : demagNew, v)
        case .becVoltageHigh: return pick(bec, v)
        case .temperatureProtection: return lr < 0x21 ? pick(offOn, v) : pick(tempProt, v)
        case .pwmDither:
            if lr < 0x15 && v > 1 { v += 1 }
            return pick(dither, v)
        case .ledControl:
            let leds = Int(c.layout?.leds ?? 0)
            if leds == 0 { return "\(v)" }
            var parts: [String] = []
            for k in 0..<leds {
                let mask = 3 << (2 * k)
                parts.append("LED\(k + 1) " + ((v & mask) == mask ? "On" : "Off"))
            }
            return parts.joined(separator: ", ")
        default:
            return "\(v)"
        }
    }

    // MARK: defaults – FUN_005aabf4

    public static func defaultValue(_ p: BLHeliParam, _ c: ParamContext) -> Int? {
        guard exists(p, c) else { return nil }
        let lr = c.layoutRevision
        let rev = c.revision
        let mode = c.mode
        switch p {
        case .mainRevision, .subRevision, .layoutRevision: return nil
        case .govPGain, .govIGain:
            if mode == .multi { return 9 }
            return lr < 10 ? 4 : 7
        case .govMode: return mode == .multi ? 4 : 1
        case .lowVoltageLimit:
            if lr < 0x0E { return lr < 10 ? 2 : 3 }
            return mode != .main ? 1 : 4
        case .motorGain: return 3
        case .motorIdle: return lr < 0x0B ? 3 : 4
        case .startupPower:
            if c.isBLHeliS { return 9 }
            if lr < 0x0F || c.firmware == nil {
                if lr < 0x10 { return lr == 0x0F ? 5 : 3 }
                return 0x0B
            }
            return Int(c.firmware!.defStartupPower)
        case .pwmFrequency:
            let damped = c.supportsDampedLight
            switch mode {
            case .main: return 2
            case .tail:
                if lr < 0x12 {
                    if lr < 0x0B { return damped ? 3 : 1 }
                    return damped ? 4 : 3
                }
                return damped ? 3 : 1
            default:
                if damped { return rev < 1440 ? 1 : 3 }
                return 1
            }
        case .direction, .inputPolarity: return 1
        case .initializedL: return c.isBLHeliS ? 0x55 : 0xA5
        case .initializedH: return c.isBLHeliS ? 0xAA : 0x5A
        case .enableTxProgramming: return 1
        case .rearmAtStart: return lr < 10 ? 1 : 0
        case .govSetupTarget: return 0xB4
        case .startupRpm: return mode == .multi ? 1 : 3
        case .startupAccel: return mode == .main ? 1 : 5
        case .voltageCompensation: return 1
        case .commutationTiming: return 3
        case .dampingForce:
            switch mode {
            case .main: return 1
            case .tail: return rev < 1210 ? 5 : 6
            default: return lr < 0x10 ? 2 : 6
            }
        case .govRange: return 1
        case .startupMethod:
            if lr < 0x0F || c.firmware == nil { return mode == .multi ? 2 : 1 }
            return Int(c.firmware!.defStartupMethod)
        case .ppmMinThrottle: return 0x25
        case .ppmMaxThrottle: return 0xD0
        case .beepStrength:
            switch mode { case .main: return 0x78; case .tail: return 0xFA; default: return 0x28 }
        case .beaconStrength:
            switch mode { case .main: return 200; case .tail: return 0xFA; default: return 0x50 }
        case .beaconDelay: return rev < 920 ? 1 : 4
        case .throttleRate: return 0x0D
        case .demagCompensation: return mode == .multi ? 2 : 1
        case .becVoltageHigh: return 0
        case .ppmCenterThrottle: return 0x7A
        case .spoolupTime:
            guard let f = c.firmware else { return 9 }
            return Int(f.defSpoolup)
        case .temperatureProtection:
            if lr < 0x13 || c.family != .atmel { return lr < 0x21 ? 1 : 7 }
            return 0
        case .lowRpmPowerProtection: return 1
        case .pwmInput: return 0
        case .pwmDither: return 3
        case .brakeOnStop: return 0
        case .ledControl: return 0
        default: return nil
        }
    }
}
