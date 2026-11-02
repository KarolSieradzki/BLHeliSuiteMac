import AppKit
import VCL
import BLHeliCore

// MARK: - TAVRFuses (fuse model of one AVR device, VMT 0x61983C)

final class TAVRFuses {
    /// +0x04 signature, +0x0C device kind (1 ATmega8, 2 ATmega48(P), 3 ATmega88(P), 4 ATmega168(P), 5 ATmega328(P),
    /// 6 ATmega640, 7 ATmega1280/1281, 8 ATmega2560/2561), +0x0D extended fuse present.
    private(set) var signature = 0
    private(set) var kind: UInt8 = 0
    private(set) var hasExt = false
    /// +0x0E…+0x11: low, high, extended fuse, lock byte.
    var bytes: [UInt8] = [0, 0, 0, 0]

    /// The four bytes as one LongWord (+0x0E).
    var value: UInt32 {
        get { UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24 }
        set { bytes = [UInt8(newValue & 0xFF), UInt8((newValue >> 8) & 0xFF), UInt8((newValue >> 16) & 0xFF), UInt8(newValue >> 24)] }
    }

    struct FuseError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// FUN_0061ED64: device name of the AVR device table.
    var deviceName: String { AVRFusesData.allDeviceNames[signature] ?? "Unknown" }

    /// FUN_0061EA20: copy of another model.
    func assign(_ o: TAVRFuses) throws {
        try setDevice(o.signature)
        value = o.value
    }

    /// FUN_0061F640: selects the device and loads its factory default fuses.
    func setDevice(_ sig: Int) throws {
        guard sig != signature else { return }
        signature = 0; kind = 0; hasExt = false; value = 0      // FUN_0061EA40
        let k: UInt8
        switch sig {
        case 0x1E9307: k = 1
        case 0x1E9205, 0x1E920A: k = 2
        case 0x1E930A, 0x1E930F: k = 3
        case 0x1E9406, 0x1E940B: k = 4
        case 0x1E9514, 0x1E950F: k = 5
        case 0x1E9608: k = 6
        case 0x1E9703, 0x1E9704: k = 7
        case 0x1E9801, 0x1E9802: k = 8
        default:
            throw FuseError(message: "Unsupported Device: " + (AVRFusesData.allDeviceNames[sig] ?? "Unknown") + "[0x" +
                            String(format: "%06X", sig) + "]")
        }
        signature = sig
        kind = k
        hasExt = k >= 2 && k <= 8
        loadDefaults()
    }

    /// FUN_0061EF60: factory default fuses, lock bits unprogrammed (FUN_0061F0C4).
    @discardableResult
    func loadDefaults() -> Bool {
        value = 0
        bytes[3] = 0xFF
        let d: (UInt8, UInt8, UInt8)?
        switch signature {
        case 0x1E9307: d = (0xE1, 0xD9, 0x00)
        case 0x1E9205, 0x1E920A: d = (0x62, 0xDF, 0xFF)
        case 0x1E930A, 0x1E930F, 0x1E9406, 0x1E940B: d = (0x62, 0xDF, 0xF9)
        case 0x1E9514, 0x1E950F: d = (0x62, 0xD9, 0xFF)
        case 0x1E9608, 0x1E9703, 0x1E9704, 0x1E9801, 0x1E9802: d = (0x42, 0x99, 0xFF)
        default: d = nil
        }
        if let d { bytes[0] = d.0; bytes[1] = d.1; bytes[2] = d.2 }
        return Int(bytes[0]) + Int(bytes[1]) + Int(bytes[2]) != 0
    }

    /// Bit name of the device kind (table 0x68ED10): byte 0 low, 1 high, 2 extended, 3 lock.
    func name(_ byte: Int, _ bit: Int) -> String? { AVRFusesData.bitNames[Int(kind)][byte][bit] }

    private func location(_ n: String) -> (Int, Int)? {
        for b in 0..<4 { for i in 0..<8 where name(b, i) == n { return (b, i) } }
        return nil
    }

    /// FUN_0061EC68: the device has a bit of this name.
    func has(_ n: String) -> Bool { location(n) != nil }

    /// FUN_0061EA74: value of a bit (true = 1 = unprogrammed).
    func bit(_ n: String) throws -> Bool {
        guard let (b, i) = location(n) else { throw FuseError(message: "Requested Bit \"" + n + "\" not found!") }
        return (bytes[b] >> UInt8(i)) & 1 == 1
    }

    /// FUN_0061EB6C (FUN_0061EB64): sets a bit by name.
    @discardableResult
    func setBit(_ n: String, _ v: Bool) -> Bool {
        guard let (b, i) = location(n) else { return false }
        if v { bytes[b] |= 1 << UInt8(i) } else { bytes[b] &= ~(1 << UInt8(i)) }
        return true
    }

    /// FUN_0061F0CC: brown-out level (0.1 V; 0 = disabled, 0xFF = invalid setting).
    var bodLevel: Int {
        if kind == 1 { return ((try? bit("BODLEVEL")) ?? true) ? 0x1B : 0x28 }
        guard kind >= 2 && kind <= 8 else { return 0xFF }
        let v = (((try? bit("BODLEVEL2")) ?? true) ? 4 : 0) | (((try? bit("BODLEVEL1")) ?? true) ? 2 : 0) |
            (((try? bit("BODLEVEL0")) ?? true) ? 1 : 0)
        switch v {
        case 4: return 0x2B
        case 5: return 0x1B
        case 6: return 0x12
        case 7: return 0
        default: return 0xFF
        }
    }

    /// FUN_0061F1E0: sets the brown-out level.
    func setBodLevel(_ v: Int) {
        if kind == 1 {
            if v == 0x1B { setBit("BODLEVEL", true) } else if v == 0x28 { setBit("BODLEVEL", false) }
        } else if kind >= 2 && kind <= 8 {
            let bits: [Int: (Bool, Bool, Bool)] = [0: (true, true, true), 0x12: (true, true, false),
                                                    0x1B: (true, false, true), 0x2B: (true, false, false)]
            if let (b2, b1, b0) = bits[v] {
                setBit("BODLEVEL2", b2); setBit("BODLEVEL1", b1); setBit("BODLEVEL0", b0)
            }
        }
    }

    /// FUN_0061ECEC: boot flash size in bytes.
    var bootSize: Int {
        switch kind {
        case 1: return 0x800 >> ((Int(bytes[1]) & 6) >> 1)
        case 3, 4: return 0x800 >> ((Int(bytes[2]) & 6) >> 1)
        case 5: return 0x1000 >> ((Int(bytes[1]) & 6) >> 1)
        case 6, 7, 8: return 0x2000 >> ((Int(bytes[1]) & 6) >> 1)
        default: return 0
        }
    }

    /// FUN_0061F434: sets BOOTSZ for a boot flash size in bytes.
    func setBootSize(_ size: Int) throws {
        let byte: Int, top: Int
        switch kind {
        case 1: byte = 1; top = 0x800
        case 3, 4: byte = 2; top = 0x800
        case 5: byte = 1; top = 0x1000
        case 6, 7, 8: byte = 1; top = 0x2000
        default: byte = -1; top = 0
        }
        guard byte >= 0, [top >> 3, top >> 2, top >> 1, top].contains(size) else {
            throw FuseError(message: "Bootloader size cannot be set (" + String(size) + " bytes) for " + deviceName)
        }
        var shift = 0
        while shift < 4 && (size << shift) != top { shift += 1 }
        bytes[byte] = (bytes[byte] & 0xF9) | UInt8(shift * 2)
    }

    /// FUN_0061EE34: meaning of CKOPT for the selected clock source (ATmega8; jump tables at 0x61EE67 / 0x61EEC0).
    var clockOption: Int {
        let c = Int(bytes[0] & 0x0F)
        if kind == 1 {
            switch c {
            case 0: return 7
            case 1...4: return 6
            case 5...8: return 4
            case 9: return 3
            default: return 1
            }
        } else if kind >= 2 && kind <= 8 {
            switch c {
            case 0: return 7
            case 2: return 6
            case 3: return 5
            case 4, 5: return 3
            case 6, 7: return 2
            case 8...15: return 1
            default: return 0
            }
        }
        return 0
    }
}

// MARK: - TfraAVRFuses (frame TFRAAVRFUSES, unit 0x6288A4)

@objc(TfraAVRFuses) final class TfraAVRFuses: TFrame {
    @objc var cpnlDevice: TCaptionPanel!
    @objc var cbxAVRDevice: TComboBox!
    @objc var lblDeviceSign: TLabel!
    @objc var cpnlFuseBitChecks: TCaptionPanel!
    @objc var cpnlLowFuseBits: TCaptionPanel!
    @objc var ipnlLowFuseBits: TItemsPanel!
    @objc var ipnlHighFuseBits: TItemsPanel!
    @objc var cpnlExtFuseBits: TCaptionPanel!
    @objc var ipnlExtFuseBits: TItemsPanel!
    @objc var ipnlLockBits: TItemsPanel!
    @objc var cpnlFeatures: TCaptionPanel!
    @objc var edtLowFuse: TEdit!
    @objc var edtHighFuse: TEdit!
    @objc var edtExtFuse: TEdit!
    @objc var edtLockbyte: TEdit!
    @objc var lblHexSignLow: TLabel!
    @objc var lblHexSignHigh: TLabel!
    @objc var lblHexSignExt: TLabel!
    @objc var lblHexSignLock: TLabel!
    @objc var pnlFeaturesClock: TPanel!
    @objc var pnlFeaturesMid: TPanel!
    @objc var pnlFeaturesCritical: TPanel!
    @objc var pnlFeaturesBootloader: TPanel!
    @objc var pnlButtons: TPanel!
    @objc var cpnlFeaturesLockBits: TCaptionPanel!
    @objc var pnlLockBits: TPanel!
    @objc var ccbCKSEL_SUT: TComboBox!
    @objc var ccbBodlevel: TComboBox!
    @objc var ccbBOOTSZ: TComboBox!
    @objc var ccbLB: TComboBox!
    @objc var ccbBLB0: TComboBox!
    @objc var ccbBLB1: TComboBox!
    @objc var cbxCKOPT: TCheckBox!
    @objc var btnOK: TButton!
    @objc var btnWrite: TButton!
    @objc var btnRead: TButton!
    @objc var actLoadFusesDefault: TAction!
    @objc var actUndoFusesChanges: TAction!
    @objc var actLoadFusesCurrent: TAction!
    @objc var actCriticalFeaturesEnabled: TAction!
    @objc var actCKOUT: TAction!
    @objc var actCKOPT: TAction!

    /// +0x498 fuse model.
    let fuses = TAVRFuses()
    /// +0x49C device change in progress, +0x49D device can be changed.
    var changingDevice = false
    var deviceChangeable = true
    /// +0x49E fuses to undo to, +0x4A2 fuses of the chip, +0x4A6 factory defaults.
    var undoValue: UInt32 = 0
    var chipValue: UInt32 = 0
    var defaultValue: UInt32 = 0
    /// +0x4AA critical features enabled, +0x4AC result (1 OK, 2 Cancel).
    var criticalEnabled = false
    var result = 2
    /// +0x4B0 AVRDude interface (nil: edit only).
    var avrdude: AVRDudeIntf?
    /// Items.Objects of the combo boxes.
    var ckselValues: [Int] = []
    var bodValues: [Int] = []
    var bootValues: [Int] = []
    var lbValues: [Int] = []
    var blb0Values: [Int] = []
    var blb1Values: [Int] = []

    static let bytePrefixes = ["LF", "HF", "EF", "LB"]

    /// Check boxes of the fuse bits (Self+0x418 + byte * 0x20 + bit * 4).
    func bitBox(_ byte: Int, _ bit: Int) -> TCheckBox? { component("cbx" + TfraAVRFuses.bytePrefixes[byte] + String(bit)) }

    private var created = false

    override func loaded() {
        super.loaded()
        createFrame()
    }

    /// TfraAVRFuses.Create (FUN_00629FE0).
    func createFrame() {
        guard !created else { return }
        created = true
        for b in 0..<4 {
            for i in 0..<8 {
                // OnKeyPress / OnKeyDown / OnKeyUp / OnMouseUp of all bit check boxes
                bitBox(b, i)?.onClick = { [weak self] _ in self?.bitsChanged() }
            }
        }
        result = 2
        criticalEnabled = false
    }

    // MARK: setup

    /// FUN_0062B744: the device list can be used.
    func setDeviceChangeable(_ b: Bool) {
        deviceChangeable = b
        cbxAVRDevice.enabled = b
    }

    /// FUN_0062A4F8: device, fuses of the chip and fuses to edit.
    func setup(signature: Int, chip: UInt32, fuses value: UInt32) throws {
        result = 2
        try selectDevice(signature)
        chipValue = chip
        undoValue = value
        fuses.value = undoValue
        if avrdude == nil {
            btnOK.visible = true
            btnWrite.visible = false
            btnRead.visible = false
            actLoadFusesCurrent.visible = undoValue != chipValue
        } else {
            btnOK.visible = false
            btnWrite.visible = true
            btnRead.visible = true
            actLoadFusesCurrent.visible = false
        }
        refresh()
    }

    /// FUN_0062B5B0: new device – lists, captions and factory defaults.
    func selectDevice(_ sig: Int) throws {
        try fuses.setDevice(sig)
        defaultValue = fuses.value
        undoValue = fuses.value
        chipValue = fuses.value
        lblDeviceSign.caption = "0x" + String(format: "%06X", fuses.signature)
        fillCKSEL()          // FUN_0062A948
        fillBodLevel()       // FUN_0062A67C
        fillBootSize()       // FUN_0062A720
        fillLockBits()       // FUN_0062AB10
        showBitNames()       // FUN_0062AD68
        if cbxAVRDevice.visible { cbxAVRDevice.text_ = fuses.deviceName }
        actCKOUT.caption = (6...8).contains(fuses.kind) ? NL("Clock output at PE7 pin") : NL("Clock output at PB0 pin")
        refresh()
    }

    static func bits(_ v: Int, _ from: Int, _ to: Int) -> String {   // FUN_005550E0: highest bit first
        var s = ""
        for b in from...to { s = ((v >> b) & 1 == 1 ? "1" : "0") + s }
        return s
    }

    /// FUN_0062A948: clock source list.
    func fillCKSEL() {
        let table: [(String, Int)]
        switch fuses.kind {
        case 1: table = AVRFusesData.ckselM8
        case 2...5: table = AVRFusesData.ckselM48
        case 6...8: table = AVRFusesData.ckselM640
        default: table = []
        }
        ccbCKSEL_SUT.items = table.map { $0.0 + " [CKSEL=" + TfraAVRFuses.bits($0.1, 0, 3) + " SUT=" + TfraAVRFuses.bits($0.1, 4, 5) + "]" }
        ckselValues = table.map(\.1)
    }

    /// FUN_0062A67C: brown-out list.
    func fillBodLevel() {
        let table = fuses.kind == 1 ? AVRFusesData.bodM8 : ((2...8).contains(fuses.kind) ? AVRFusesData.bodOthers : [])
        ccbBodlevel.items = table.map(\.0)
        bodValues = table.map(\.1)
    }

    /// FUN_0062A720: boot flash size list (ATmega48: none).
    func fillBootSize() {
        if fuses.kind == 2 {
            ccbBOOTSZ.height = 0
            ccbBOOTSZ.items = []
            bootValues = []
            return
        }
        ccbBOOTSZ.height = 0x18
        let table = (AVRFusesData.bootSizes[fuses.kind] ?? []).filter { $0.1 > 0 }
        ccbBOOTSZ.items = table.map { $0.0 + " [BOOTSZ=" + TfraAVRFuses.bits($0.2, 0, 1) + "]" }
        bootValues = table.map(\.1)
    }

    /// FUN_0062AB10: lock bit lists (boot lock bits only on devices with a boot section).
    func fillLockBits() {
        ccbLB.items = AVRFusesData.lb.map { $0.0 + " [LB=" + TfraAVRFuses.bits($0.1, 0, 1) + "]" }
        lbValues = AVRFusesData.lb.map(\.1)
        if fuses.kind == 1 || (3...8).contains(fuses.kind) {
            ccbBLB0.items = AVRFusesData.blb0.map { $0.0 + " [BLB0=" + TfraAVRFuses.bits($0.1, 0, 1) + "]" }
            blb0Values = AVRFusesData.blb0.map(\.1)
            ccbBLB1.items = AVRFusesData.blb1.map { $0.0 + " [BLB1=" + TfraAVRFuses.bits($0.1, 0, 1) + "]" }
            blb1Values = AVRFusesData.blb1.map(\.1)
            ccbBLB0.height = 0x18
            ccbBLB1.height = 0x18
        } else {
            ccbBLB0.items = []; blb0Values = []
            ccbBLB1.items = []; blb1Values = []
            ccbBLB0.height = 0
            ccbBLB1.height = 0
        }
    }

    /// FUN_0062AD68: captions of the bit check boxes ("unused" bits disabled, critical bits red).
    func showBitNames() {
        for b in 0..<4 {
            for i in 0..<8 {
                guard let c = bitBox(b, i) else { continue }
                if let n = fuses.name(b, i) {
                    c.caption = n
                    c.enabled = true
                    c.font.color = clWindowText
                    if AVRFusesData.criticalNames.contains(n) {
                        c.enabled = criticalEnabled
                        c.font.color = clRed
                    }
                } else {
                    c.enabled = false
                    c.caption = "unused"
                }
            }
        }
    }

    // MARK: display (FUN_0062BBB4)

    func refresh() {
        showHex()            // FUN_0062BCE4
        showBits()           // FUN_0062BF44
        showFeatures()       // FUN_0062BDC8
        showLockBits()       // FUN_0062BBDC
        layoutFrame()        // FUN_00629898
    }

    func showHex() {
        edtLowFuse.text = String(format: "%02X", fuses.bytes[0])
        edtHighFuse.text = String(format: "%02X", fuses.bytes[1])
        edtExtFuse.text = String(format: "%02X", fuses.bytes[2])
        edtLockbyte.text = String(format: "%02X", fuses.bytes[3])
    }

    /// Check box checked = bit programmed (0).
    func showBits() {
        for b in 0..<4 {
            for i in 0..<8 {
                guard let c = bitBox(b, i) else { continue }
                c.setChecked((fuses.bytes[b] >> UInt8(i)) & 1 == 0)
                c.hint = c.checked ? "programmed (0)" : "unprogrammed (1)"
            }
        }
    }

    /// ItemIndex := Items.IndexOfObject(v); an unknown setting shows an empty yellow box.
    func select(_ c: TComboBox, _ values: [Int], _ v: Int) {
        c.itemIndex = values.firstIndex(of: v) ?? -1
        c.color = c.itemIndex < 0 ? clYellow : clWindow
    }

    func showFeatures() {
        // FUN_0062B830: clock source and the meaning of CKOPT
        select(ccbCKSEL_SUT, ckselValues, Int(fuses.bytes[0] & 0x3F))
        cbxCKOPT.parentColor = true
        if fuses.has("CKOPT") {
            if ccbCKSEL_SUT.itemIndex < 0 {
                actCKOPT.caption = "Clock selection invalid: No option available."
            } else {
                var s = "Clock option: "
                switch fuses.clockOption {
                case 0: s += "No option available."
                case 1: s += "full rail-to-rail swing oscillator"
                case 3: s += "enable internal 36pf capacitors on XTAL1 and XTAL2"
                case 4: s += "enable an internal 36pF capacitor between XTAL1 and GND"
                case 5, 6:
                    s += "No option for calibrated internal RC Oscillator"
                    if cbxCKOPT.checked { cbxCKOPT.color = clYellow }
                case 7: s += "enable an internal 36pF capacitor between XTAL1 and GND, and XTAL2 and GND"
                default: break
                }
                actCKOPT.caption = s
            }
        }
        select(ccbBodlevel, bodValues, fuses.bodLevel)             // FUN_0062B75C
        if !bootValues.isEmpty { select(ccbBOOTSZ, bootValues, fuses.bootSize) } // FUN_0062B7FC
        // feature check boxes: "cbx" + bit name, only for bits of this device
        for case let p as TPanel in cpnlFeatures.subviews {
            for case let c as TCheckBox in p.subviews where c.name.hasPrefix("cbx") {
                let n = String(c.name.dropFirst(3))
                if fuses.has(n) {
                    c.height = 0x11
                    c.setChecked(!((try? fuses.bit(n)) ?? true))
                } else {
                    c.height = 0
                }
            }
        }
    }

    /// FUN_0062BBDC: lock bit lists from the lock byte.
    func showLockBits() {
        let l = Int(fuses.bytes[3])
        select(ccbLB, lbValues, l & 3)
        if !blb0Values.isEmpty { select(ccbBLB0, blb0Values, (l >> 2) & 3) }
        if !blb1Values.isEmpty { select(ccbBLB1, blb1Values, (l >> 4) & 3) }
    }

    /// FUN_00629898: bit panels only with critical features; frame and window height.
    func layoutFrame() {
        cpnlExtFuseBits.visible = fuses.hasExt
        let h = criticalEnabled ? 0x99 : 1
        cpnlFuseBitChecks.caption = criticalEnabled ? "Fuse Bits" : "Fuses"
        for p in [ipnlLowFuseBits, ipnlHighFuseBits, ipnlExtFuseBits, ipnlLockBits] { p?.height = h }
        edtLowFuse.top = lblHexSignLow.top + 4
        edtHighFuse.top = lblHexSignHigh.top + 4
        edtExtFuse.top = lblHexSignExt.top + 4
        edtLockbyte.top = lblHexSignLock.top + 4
        cpnlFuseBitChecks.height = ipnlLowFuseBits.height + cpnlLowFuseBits.captionHeight + lblHexSignLow.height + 8
        let fh = pnlFeaturesCritical.height + pnlFeaturesBootloader.height + pnlFeaturesClock.height + pnlFeaturesMid.height + 2
        if fh != cpnlFeatures.height { cpnlFeatures.height = fh }
        cpnlFeaturesLockBits.height = pnlLockBits.height + 2
        let maxH = pnlButtons.height + cpnlFeatures.height + cpnlDevice.height + cpnlFeaturesLockBits.height + cpnlFuseBitChecks.height + 0x12
        if let f = window?.delegate as? TForm, f.clientHeight != maxH {
            height = maxH
            f.setClientSize(f.clientWidth, maxH)
        }
    }

    /// FUN_0062C01C: fuse bytes from the bit check boxes.
    func bitsChanged() {
        for b in 0..<4 {
            var v = fuses.bytes[b]
            for i in 0..<8 {
                guard let c = bitBox(b, i) else { continue }
                if c.checked { v &= ~(1 << UInt8(i)) } else { v |= 1 << UInt8(i) }
            }
            fuses.bytes[b] = v
        }
        refresh()
    }

    /// FUN_0062B554: critical features (RSTDISBL, SPIEN, DWEN …) can be changed.
    func setCriticalEnabled(_ b: Bool) {
        criticalEnabled = b
        for case let c as TControl in pnlFeaturesCritical.subviews { c.enabled = b }
        showBitNames()
        if window?.isVisible == true { layoutFrame() }
    }

    /// FUN_0062C07C: the edited fuses.
    var editedValue: UInt32 { fuses.value }

    // MARK: actions

    @objc func aclMainUpdate(_ sender: TObject) {
        actLoadFusesDefault.enabled = fuses.value != defaultValue
        actUndoFusesChanges.enabled = fuses.value != undoValue
        actLoadFusesCurrent.enabled = fuses.value != chipValue
        actCriticalFeaturesEnabled.checked = criticalEnabled
    }

    func feature(_ box: String, _ bit: String) {
        guard let c: TCheckBox = component(box) else { return }
        fuses.setBit(bit, !c.checked)
        refresh()
    }

    @objc func actBODENExecute(_ sender: TObject) { feature("cbxBODEN", "BODEN") }
    @objc func actBOOTRSTExecute(_ sender: TObject) { feature("cbxBOOTRST", "BOOTRST") }
    @objc func actCKDIV8Execute(_ sender: TObject) { feature("cbxCKDIV8", "CKDIV8") }
    @objc func actCKOPTExecute(_ sender: TObject) { feature("cbxCKOPT", "CKOPT") }
    @objc func actCKOUTExecute(_ sender: TObject) { feature("cbxCKOUT", "CKOUT") }
    @objc func actDWENExecute(_ sender: TObject) { feature("cbxDWEN", "DWEN") }
    @objc func actEESAVEExecute(_ sender: TObject) { feature("cbxEESAVE", "EESAVE") }
    @objc func actRSTDISBLExecute(_ sender: TObject) { feature("cbxRSTDISBL", "RSTDISBL") }
    @objc func actSELFPRGENExecute(_ sender: TObject) { feature("cbxSELFPRGEN", "SELFPRGEN") }
    @objc func actSPIENExecute(_ sender: TObject) { feature("cbxSPIEN", "SPIEN") }
    @objc func actWDTONExecute(_ sender: TObject) { feature("cbxWDTON", "WDTON") }
    @objc func actCriticalFeaturesEnabledExecute(_ sender: TObject) { setCriticalEnabled(!criticalEnabled) }

    @objc func actLoadFusesDefaultExecute(_ sender: TObject) { fuses.loadDefaults(); refresh() }
    @objc func actLoadFusesCurrentExecute(_ sender: TObject) { fuses.value = chipValue; refresh() }
    @objc func actUndoFusesChangesExecute(_ sender: TObject) { fuses.value = undoValue; refresh() }

    /// cbxAVRDeviceChange (0x629B0C): another device from the list – factory defaults of that device.
    @objc func cbxAVRDeviceChange(_ sender: TObject) {
        guard !changingDevice else { return }
        changingDevice = true
        defer { changingDevice = false }
        if let sig = AVRFusesData.signatureByName[cbxAVRDevice.text_] {
            do { try selectDevice(sig) } catch { MsgDlg.error(error.localizedDescription) }
        }
    }

    @objc func cbxFuseBitsMouseUp(_ sender: TObject, _ a: TMouseArgs) { bitsChanged() }
    @objc func cbxFuseBitsKeyPress(_ sender: TObject, _ a: TKeyArgs) { /* empty in BLHeliSuite (0x629BCC) */ }
    @objc func cbxFuseBitsKeyUp(_ sender: TObject, _ a: TKeyArgs) { bitsChanged() }

    /// cbxFuseBitsKeyDown (0x629BD0): space toggles the bit.
    @objc func cbxFuseBitsKeyDown(_ sender: TObject, _ a: TKeyArgs) {
        guard a.keyCode == 0x31 || a.key == " ", let c = sender as? TCheckBox else { return }
        c.setChecked(!c.checked)
        a.keyCode = 0
        bitsChanged()
    }

    func lockChanged(_ c: TComboBox, _ values: [Int], _ b1: String, _ b2: String) {
        guard c.itemIndex >= 0, c.itemIndex < values.count else { return }
        let v = values[c.itemIndex]
        fuses.setBit(b1, v & 1 != 0)
        fuses.setBit(b2, v & 2 != 0)
        refresh()
    }

    @objc func ccbLBChange(_ sender: TObject) { lockChanged(ccbLB, lbValues, "LB1", "LB2") }
    @objc func ccbBLB0Change(_ sender: TObject) { lockChanged(ccbBLB0, blb0Values, "BLB01", "BLB02") }
    @objc func ccbBLB1Change(_ sender: TObject) { lockChanged(ccbBLB1, blb1Values, "BLB11", "BLB12") }

    @objc func ccbBodlevelChange(_ sender: TObject) {
        guard ccbBodlevel.itemIndex >= 0, ccbBodlevel.itemIndex < bodValues.count else { return }
        fuses.setBodLevel(bodValues[ccbBodlevel.itemIndex])
        refresh()
    }

    @objc func ccbBOOTSZChange(_ sender: TObject) {
        guard ccbBOOTSZ.itemIndex >= 0, ccbBOOTSZ.itemIndex < bootValues.count else { return }
        do { try fuses.setBootSize(bootValues[ccbBOOTSZ.itemIndex]) } catch { MsgDlg.error(error.localizedDescription) }
        refresh()
    }

    /// ccbCKSEL_SUTChange (0x629E8C): bits 0…5 of the low fuse.
    @objc func ccbCKSEL_SUTChange(_ sender: TObject) {
        guard ccbCKSEL_SUT.itemIndex >= 0, ccbCKSEL_SUT.itemIndex < ckselValues.count else { return }
        fuses.bytes[0] = (fuses.bytes[0] & 0xC0) | UInt8(ckselValues[ccbCKSEL_SUT.itemIndex] & 0x3F)
        refresh()
    }

    /// Yellow while no valid entry is selected, normal while the list is open.
    func closeUp(_ c: TComboBox) { c.color = c.text_.isEmpty ? clYellow : clWindow }
    @objc func ccbBodlevelCloseUp(_ sender: TObject) { closeUp(ccbBodlevel) }
    @objc func ccbCKSEL_SUTCloseUp(_ sender: TObject) { closeUp(ccbCKSEL_SUT) }
    @objc func ccbLBCloseUp(_ sender: TObject) { closeUp(ccbLB) }
    @objc func ccbBodlevelDropDown(_ sender: TObject) { ccbBodlevel.color = clWindow }
    @objc func ccbCKSEL_SUTDropDown(_ sender: TObject) { ccbCKSEL_SUT.color = clWindow }
    @objc func ccbLBDropDown(_ sender: TObject) { ccbLB.color = clWindow }

    /// edtFuseKeyPress (0x62A294): hex digits only (with critical features); two digits update the fuse byte.
    @objc func edtFuseKeyPress(_ sender: TObject, _ a: TKeyArgs) {
        guard let e = sender as? TEdit, [edtLowFuse, edtHighFuse, edtExtFuse, edtLockbyte].contains(where: { $0 === e }) else { return }
        let k = a.key
        defer { a.key = "\0" }
        guard criticalEnabled, k == "\u{8}" || k == "\r" || k.isHexDigit else { return }
        guard k.isHexDigit else { return }
        var t = e.text
        if t.count < 2 { t = String(k).uppercased() + t } else if t.count == 2 { t = String(k).uppercased() }
        t = t.uppercased()
        e.text = t
        guard t.count == 2, let v = UInt8(t, radix: 16) else { return }
        if e === edtLowFuse { fuses.bytes[0] = v }
        else if e === edtHighFuse { fuses.bytes[1] = v }
        else if e === edtExtFuse { fuses.bytes[2] = v }
        else { fuses.bytes[3] = v }
        refresh()
    }

    /// edtFuseContextPopup (0x62A4E0): context menu only with critical features.
    @objc func edtFuseContextPopup(_ sender: TObject, _ a: TBoolArgs) { a.value = !criticalEnabled }

    @objc func FrameResize(_ sender: TObject) { /* empty in BLHeliSuite (0x62C018) */ }

    @objc func btnOKClick(_ sender: TObject) {
        result = 1
        (window?.delegate as? TForm)?.close()
    }

    @objc func btnCancelClick(_ sender: TObject) {
        result = 2
        (window?.delegate as? TForm)?.close()
    }

    @objc func bntSaveScreenshotClick(_ sender: TObject) {
        if let f = window?.delegate as? TForm { saveScreenshot(of: f, name: "BLHeliSuiteFuseEditor") }
    }

    /// Connects avrdude and reads the fuses of the chip (TAVRDude 0x622948 / 0x6223E0 / 0x623DA4).
    func readChip() -> UInt32? {
        guard let a = avrdude else { return nil }
        Screen.busy = true
        defer { Screen.busy = false }
        do {
            if !a.connected { try a.connect() }
            guard let isp = a.isp else { return nil }
            if a.device == nil { a.device = try isp.selectESC(0) }
            return try isp.readFuseBytes()
        } catch {
            MsgDlg.error(error.localizedDescription)
            return nil
        }
    }

    /// btnReadClick (0x62AF30).
    @objc func btnReadClick(_ sender: TObject) {
        guard avrdude != nil else { return }
        guard let v = readChip() else { MsgDlg.error(NL("Failed to read Fuses.")); return }
        if avrdude?.bootloaderMode == true {
            MsgDlg.error(NL("Cannot read fuses in bootloader mode."))
            return
        }
        chipValue = v
        fuses.value = v
        refresh()
        MsgDlg.show(NL("Fuses successfully read."), .mtInformation, [.mbOK])
    }

    /// btnWriteClick (0x62B090).
    @objc func btnWriteClick(_ sender: TObject) {
        guard let a = avrdude, let chip = readChip() else { return }
        if a.bootloaderMode {
            MsgDlg.error(NL("Cannot read fuses in bootloader mode."))
            return
        }
        if chip == fuses.value {
            MsgDlg.show(NL("Nothing to write. Fuses are already up to date."), .mtInformation, [.mbOK])
            return
        }
        // a programmed (0) lock bit can only be cleared by a chip erase
        let oldLock = UInt8(chip >> 24), newLock = fuses.bytes[3]
        for i in 0..<8 where (oldLock >> UInt8(i)) & 1 == 0 && (newLock >> UInt8(i)) & 1 == 1 {
            MsgDlg.error(NL("Lock bits cannot be disabled (unprogrammed) this way.\\nThis can only be done by a complete erase of the chip..."))
            return
        }
        guard MsgDlg.show(NL("Write shown Fuse values to the chip?"), .mtConfirmation, [.mbYes, .mbNo]) == mrYes else { return }
        Screen.busy = true
        var ok = false
        do {
            try a.isp?.writeFuseBytes(fuses.value, ext: fuses.hasExt)
            if let back = try a.isp?.readFuseBytes(), back == fuses.value {
                chipValue = back
                fuses.value = back
                ok = true
            }
        } catch {}
        Screen.busy = false
        refresh()
        if ok {
            MsgDlg.show(NL("Fuses successfully written."), .mtInformation, [.mbOK])
        } else {
            MsgDlg.error(NL("Failed to write Fuses."))
        }
    }
}

// MARK: - TfrmFuseEditor (form TFRMFUSEEDITOR, 0x62C0E8)

@objc(TfrmFuseEditor) final class TfrmFuseEditor: TForm {
    /// Self+0x360: the TfraAVRFuses frame created at run time.
    var fraAVRFuses: TfraAVRFuses!

    /// TfrmFuseEditor.Create (FUN_0062C448): the frame is created at run time.
    static func create() -> TfrmFuseEditor {
        let f = TfrmFuseEditor(resource: "TFRMFUSEEDITOR", owner: Application.shared.mainForm)
        let fr = TfraAVRFuses.create()
        fr.createFrame()
        f.insertControl(fr)
        // action list of the frame (aclMain → aclMainUpdate) is updated in idle time like the form's own lists
        for case let l as TActionList in fr.components.values { f.actionLists.append(l) }
        fr.align = .alClient
        f.fraAVRFuses = fr
        return f
    }

    /// FUN_0062C250: edit fuses without a chip connection (Confirm Flash). Returns the new fuses on OK.
    static func edit(signature: Int, chip: UInt32, fuses: UInt32, deviceChangeable: Bool, critical: Bool) -> UInt32? {
        let f = create()
        defer { f.release() }
        f.fraAVRFuses.setDeviceChangeable(deviceChangeable)
        f.fraAVRFuses.setCriticalEnabled(critical)
        do { try f.fraAVRFuses.setup(signature: signature, chip: chip, fuses: fuses) } catch {
            MsgDlg.error(error.localizedDescription)
            return nil
        }
        return f.showModal() == mrOk ? f.fraAVRFuses.editedValue : nil
    }

    /// FUN_0062C320: fuse editor with avrdude (Expert tools → Edit fuses).
    @discardableResult
    static func execute(avrdude: AVRDudeIntf, signature: Int, chip: UInt32, deviceChangeable: Bool, critical: Bool) -> Bool {
        let f = create()
        defer { f.release() }
        f.fraAVRFuses.setDeviceChangeable(deviceChangeable)
        f.fraAVRFuses.setCriticalEnabled(critical)
        f.fraAVRFuses.avrdude = avrdude
        do { try f.fraAVRFuses.setup(signature: signature, chip: chip, fuses: chip) } catch {
            MsgDlg.error(error.localizedDescription)
            return false
        }
        return f.showModal() == mrOk
    }

    @objc func FormShow(_ sender: TObject) { fraAVRFuses?.layoutFrame() }

    /// FormClose (0x62C4D8): the result of the frame (OK / Cancel) is the modal result.
    @objc func FormClose(_ sender: TObject, _ a: TCloseArgs) {
        if let fr = fraAVRFuses { modalResult = fr.result == 1 ? mrOk : mrCancel }
    }
}
