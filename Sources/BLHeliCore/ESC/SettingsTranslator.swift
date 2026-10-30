import Foundation

public enum TranslateError: Error, LocalizedError {
    case modeDiffers
    case blheliSversusBLHeli

    public var errorDescription: String? {
        switch self {
        case .modeDiffers: return "Unable to translate parameters!\nReason: ESC Mode (MAIN-TAIL-MULTI) is different."
        case .blheliSversusBLHeli: return "Unable to translate parameters!\nReason: BLHeliS ESC versus BLHeli ESC."
        }
    }
}

/// Port of TBLHeliTranslator (FUN_0059fdb0 and the per-parameter helpers 0x5a0178…0x5a1414).
/// Carries the user's settings over to the EEPROM defaults of a new firmware revision.
///
/// Note: a few helpers in BLHeliSuite compare revisions against constants written in tenths
/// (0x28 = "4.0", 0x3D/0x65 = "6.1"/"10.1", 0xA3 = "16.3") while the revision value itself is
/// main*100+sub*10. This port evaluates those comparisons in tenths, as obviously intended.
public struct SettingsTranslator {
    public var copyThrottleCalibration = true
    public var copyDirection = true
    public var copyName = true

    public init(copyThrottleCalibration: Bool = true, copyDirection: Bool = true, copyName: Bool = true) {
        self.copyThrottleCalibration = copyThrottleCalibration
        self.copyDirection = copyDirection
        self.copyName = copyName
    }

    public func translate(from old: BLHeliSettings, oldContext: ParamContext,
                          to newDefaults: BLHeliSettings, newContext: ParamContext) throws -> BLHeliSettings {
        guard old.mode == newDefaults.mode else { throw TranslateError.modeDiffers }
        guard old.isBLHeliS == newDefaults.isBLHeliS else { throw TranslateError.blheliSversusBLHeli }
        var t = State(old: old, new: newDefaults, oc: oldContext, nc: newContext)
        t.gain(.govPGain)
        t.gain(.govIGain)
        t.govMode()
        t.lowVoltageLimit()
        if t.oldTail || t.oldMulti { t.copy(.motorGain) }
        if t.oldTail { t.copy(.motorIdle) }
        t.startupPower()
        t.pwmFrequency()
        if copyDirection { t.direction() }
        t.copy(.inputPolarity)
        if t.bothAtLeast(8) { t.copy(.enableTxProgramming) }
        if t.bothAtLeast(9) { t.copy(.rearmAtStart) }
        if t.oldMain && t.bothAtLeast(10) { t.copy(.govSetupTarget) }
        if old.family == .silabs {
            if t.bothIn(10, 0x12) { t.copy(.startupRpm) }
            if t.bothIn(10, 0x12) { t.copy(.startupAccel) }
        }
        if t.bothIn(10, 0x0D) { t.copy(.voltageCompensation) }
        t.generic(.commutationTiming)
        t.generic(.dampingForce)
        t.govRange()
        if old.family == .silabs && t.bothIn(0x0D, 0x12) { t.copy(.startupMethod) }
        if copyThrottleCalibration {
            if t.bothAtLeast(0x0D) { t.copy(.ppmMinThrottle) }
            if t.bothAtLeast(0x0D) { t.copy(.ppmMaxThrottle) }
        }
        t.generic(.beepStrength)
        t.generic(.beaconStrength)
        t.generic(.beaconDelay)
        if t.bothIn(0x0D, 0x12) { t.copy(.throttleRate) }
        t.demag()
        if oldContext.layout?.becHV == newContext.layout?.becHV { t.generic(.becVoltageHigh) }
        if copyThrottleCalibration && t.bothAtLeast(0x11) && (t.oldTail || t.oldMulti) { t.copy(.ppmCenterThrottle) }
        if t.bothAtLeast(0x12) && t.oldMain { t.copy(.spoolupTime) }
        t.temperatureProtection()
        t.generic(.lowRpmPowerProtection)
        t.generic(.pwmInput)
        t.generic(.pwmDither)
        t.generic(.brakeOnStop)
        if (oldContext.layout?.leds ?? 0) == (newContext.layout?.leds ?? 0) { t.generic(.ledControl) }
        if copyName && !old.flashFailedMarker && old.name != newDefaults.name { t.new.name = old.name }
        // Safety net (not in BLHeliSuite): never hand out values the new firmware does not accept,
        // e.g. when downgrading to a revision with a smaller range.
        for p in BLHeliParam.editable where BLHeliParamLogic.exists(p, newContext) {
            if !BLHeliParamLogic.isValid(p, value: t.new.value(p), newContext) {
                t.new[p] = newDefaults[p]
            }
        }
        return t.new
    }

    struct State {
        let old: BLHeliSettings
        var new: BLHeliSettings
        let oc: ParamContext
        let nc: ParamContext
        var oLR: Int { Int(old.layoutRevision) }
        var nLR: Int { Int(new.layoutRevision) }
        /// revisions in tenths ("16.3" = 163)
        var oRev10: Int { old.revision / 10 }
        var nRev10: Int { new.revision / 10 }
        var oldMain: Bool { old.mode == .main }
        var oldTail: Bool { old.mode == .tail }
        var oldMulti: Bool { old.mode == .multi }

        init(old: BLHeliSettings, new: BLHeliSettings, oc: ParamContext, nc: ParamContext) {
            self.old = old; self.new = new; self.oc = oc; self.nc = nc
        }

        func bothAtLeast(_ x: Int) -> Bool { oLR >= x && nLR >= x }
        func bothAtMost(_ x: Int) -> Bool { oLR <= x && nLR <= x }
        func bothIn(_ a: Int, _ b: Int) -> Bool { bothAtLeast(a) && bothAtMost(b) }

        func o(_ p: BLHeliParam) -> UInt8 { old[p] }
        mutating func set(_ p: BLHeliParam, _ v: UInt8) { new[p] = v }
        mutating func copy(_ p: BLHeliParam) { new[p] = old[p] }

        /// FUN_005a00d0: copy when the parameter exists for both revisions.
        mutating func generic(_ p: BLHeliParam) {
            if BLHeliParamLogic.exists(p, nc) && BLHeliParamLogic.exists(p, oc) { copy(p) }
        }

        mutating func map(_ p: BLHeliParam, _ table: [UInt8: UInt8]) {
            if let v = table[o(p)] { set(p, v) }
        }

        // FUN_005a0394
        func convertGain(_ oldV: UInt8, _ newV: UInt8) -> UInt8 {
            let cond = !(bothAtLeast(0x10) && oldMulti)
                && (nRev10 < 0x28 || oRev10 < 0x28)
                && (nLR < 10 || nRev10 > 0x27 || oLR < 10 || oRev10 > 0x27)
                && !bothIn(7, 9)
            guard cond else { return oldV }
            var r = newV
            if oLR < 7 || oLR > 9 {
                if oLR > 9 && oRev10 < 0x28 {
                    if nLR < 7 || nLR > 9 {
                        if nRev10 > 0x27, (1...9).contains(oldV) { r = oldV }
                    } else {
                        let m: [UInt8: UInt8] = [1: 1, 2: 1, 3: 1, 4: 1, 5: 2, 6: 3, 7: 4, 8: 5, 9: 5]
                        if let v = m[oldV] { r = v }
                    }
                }
            } else {
                let m: [UInt8: UInt8] = [1: 4, 2: 5, 3: 6, 4: 7, 5: 8]
                if nLR < 10 || nRev10 > 0x27 {
                    if nRev10 > 0x27, let v = m[oldV] { r = v }
                } else if let v = m[oldV] {
                    r = v
                }
            }
            return r
        }

        // FUN_005a0358 / FUN_005a0230
        mutating func gain(_ p: BLHeliParam) {
            if !oldMain {
                if !bothAtLeast(0x10) { return }
                if !oldMulti { return }
            }
            set(p, convertGain(o(p), new[p]))
        }

        // FUN_005a026c
        mutating func govMode() {
            if bothAtLeast(0x10) && oldMulti { copy(.govMode); return }
            guard oldMain else { return }
            if bothAtLeast(10) || bothIn(7, 9) { copy(.govMode); return }
            if oLR < 7 || oLR > 9 {
                if oLR > 9 && nLR >= 7 && nLR <= 9 { map(.govMode, [1: 1, 2: 2, 3: 1, 4: 3]) }
            } else if nLR > 9 {
                map(.govMode, [1: 1, 2: 2, 3: 4])
            }
        }

        // FUN_005a06bc
        mutating func lowVoltageLimit() {
            guard oldMain || (oldMulti && bothAtMost(0x13)) else { return }
            if bothAtLeast(0x0E) || bothIn(10, 0x0D) || bothIn(7, 9) { copy(.lowVoltageLimit); return }
            let p = BLHeliParam.lowVoltageLimit
            if oLR < 7 || oLR > 9 {
                if oLR < 10 || oLR > 0x0D {
                    if oLR > 0x0D {
                        if nLR < 7 || nLR > 9 {
                            if nLR > 9 && nLR < 0x0E { map(p, [1: 1, 2: 1, 3: 2, 4: 3, 5: 4, 6: 5]) }
                        } else {
                            map(p, [1: 1, 2: 2, 3: 2, 4: 3, 5: 3, 6: 3])
                        }
                    }
                } else {
                    if nLR < 7 || nLR > 9 {
                        if nLR > 0x0D { map(p, [1: 2, 2: 3, 3: 4, 4: 5, 5: 6]) }
                    } else {
                        map(p, [1: 2, 2: 2, 3: 3, 4: 3, 5: 3])
                    }
                }
            } else {
                if nLR < 10 || nLR > 0x0D {
                    if nLR > 0x0D { map(p, [1: 2, 2: 2, 3: 5]) }
                } else {
                    map(p, [1: 1, 2: 1, 3: 4])
                }
            }
        }

        // FUN_005a0ce0
        mutating func startupPower() {
            let p = BLHeliParam.startupPower
            if bothAtLeast(0x10) || bothIn(0x0F, 0x0F) || bothIn(7, 0x0E) { copy(p); return }
            if oLR < 7 || oLR > 0x0E {
                if oLR == 0x0F {
                    if nLR < 10 || nLR > 0x0E {
                        if nLR > 0x0F { map(p, [1: 7, 2: 8, 3: 9, 4: 10, 5: 11, 6: 12, 7: 13]) }
                    } else {
                        map(p, [1: 1, 2: 1, 3: 1, 4: 2, 5: 3, 6: 4, 7: 5])
                    }
                } else if oLR > 0x0F {
                    if nLR < 7 || nLR > 0x0E {
                        if nLR == 0x0F { map(p, [1: 1, 2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 8: 2, 9: 3, 10: 4, 11: 5, 12: 6, 13: 7]) }
                    } else {
                        map(p, [1: 1, 2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 8: 1, 9: 1, 10: 2, 11: 3, 12: 4, 13: 5])
                    }
                }
            } else if nLR == 0x0F {
                map(p, [1: 3, 2: 4, 3: 5, 4: 6, 5: 7])
            } else if nLR > 0x0F {
                map(p, [1: 9, 2: 10, 3: 11, 4: 12, 5: 13])
            }
        }

        // FUN_005a0a7c
        mutating func pwmFrequency() {
            let p = BLHeliParam.pwmFrequency
            let damped = nc.supportsDampedLight
            let newNotMain = new.mode != .main
            let ov = o(p)
            if bothAtLeast(0x12) {
                if ov != 3 || damped { set(p, ov) }
                return
            }
            if bothIn(0x0B, 0x11) {
                if ov == 4 && (!damped || !newNotMain) { set(p, 3) } else { set(p, ov) }
                return
            }
            if bothAtMost(10) {
                if ov != 3 || damped { set(p, ov) }
                return
            }
            if oLR >= 0x12 && nLR >= 0x0B {
                set(p, ov)
            } else if oLR >= 0x12 && nLR <= 10 {
                if ov != 3 || damped { set(p, ov) }
            } else if oLR >= 0x0B && nLR >= 0x12 {
                if ov == 1 { set(p, 1) } else if ov == 2 { set(p, 2) } else if (ov == 3 || ov == 4) && damped { set(p, 3) }
            } else if oLR >= 0x0B && nLR <= 10 {
                if ov == 1 { set(p, 1) } else if ov == 2 { set(p, 2) } else if (ov == 3 || ov == 4) && damped && newNotMain { set(p, 3) }
            } else if oLR < 0x0B && nLR > 10 {
                if ov == 1 { set(p, 1) } else if ov == 2 { set(p, 2) } else if ov == 3 { set(p, damped ? 4 : 3) }
            }
        }

        // FUN_005a135c
        mutating func direction() {
            let p = BLHeliParam.direction
            if bothAtLeast(0x11) || bothAtMost(0x10) { copy(p); return }
            if oLR < 0x11 {
                if nLR > 0x10 { map(p, [1: 1, 2: 2]) }
            } else if nLR < 0x11 {
                map(p, [1: 1, 2: 2, 3: 1])
            }
        }

        // FUN_005a05a8
        mutating func govRange() {
            let p = BLHeliParam.govRange
            var ov = o(p)
            if oRev10 > 0x3D && oRev10 < 0x65 { ov = 1 }
            guard oldMain && bothAtLeast(0x0C) else { return }
            if bothAtLeast(0x11) || bothIn(0x0C, 0x10) { set(p, ov); return }
            if oLR < 0x0C || oLR > 0x10 {
                if oLR > 0x10 && nLR >= 0x0C && nLR <= 0x10 {
                    if nRev10 < 0x3E || nRev10 > 100 {
                        if ov == 1 { set(p, 1) } else if ov == 3 { set(p, 2) }
                    } else {
                        set(p, 1)
                    }
                }
            } else if nLR > 0x10 {
                if ov == 1 { set(p, 1) } else if ov == 2 { set(p, 3) }
            }
        }

        // FUN_005a1274
        mutating func demag() {
            let p = BLHeliParam.demagCompensation
            guard bothAtLeast(0x0E) else { return }
            if bothAtLeast(0x11) || bothAtMost(0x10) { copy(p); return }
            if oLR < 0x11 {
                if nLR > 0x10 { map(p, [1: 1, 2: 2, 3: 2, 4: 3, 5: 3]) }
            } else if nLR < 0x11 {
                map(p, [1: 1, 2: 3, 3: 5])
            }
        }

        // FUN_005a1148 (Off is kept Off – BLHeliSuite wrote the old object here by mistake)
        mutating func temperatureProtection() {
            let p = BLHeliParam.temperatureProtection
            guard bothAtLeast(0x12) else { return }
            let oldMulti = oRev10 >= 163, newMulti = nRev10 >= 163
            if oldMulti == newMulti { copy(p); return }
            if !oldMulti {
                set(p, o(p) == 0 ? 0 : 7)
            } else {
                set(p, o(p) == 0 ? 0 : 1)
            }
        }
    }
}
