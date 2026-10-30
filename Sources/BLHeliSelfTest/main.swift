import Foundation
import BLHeliCore

// Self test runner (XCTest is not available with the Command Line Tools only).

var failures = 0
var checks = 0
var currentTest = ""

func expect(_ cond: @autoclosure () -> Bool, _ msg: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
    checks += 1
    if !cond() {
        failures += 1
        print("  ✗ [\(currentTest)] \(msg())  (\(file):\(line))")
    }
}

func test(_ name: String, _ body: () throws -> Void) {
    currentTest = name
    let before = failures
    let t0 = Date()
    do { try body() } catch {
        failures += 1
        print("  ✗ [\(name)] threw \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
    }
    let dt = Date().timeIntervalSince(t0)
    print(String(format: "%@ %@ (%.2fs)", failures == before ? "✓" : "✗", name, dt))
}

let filter = CommandLine.arguments.dropFirst().first
func enabled(_ name: String) -> Bool { filter == nil || name.lowercased().contains(filter!.lowercased()) }

let db = try FirmwareDatabase.shared()

// MARK: - Unit tests

if enabled("crc") { test("crc") {
    // examples from "BLHeliSuite 4w-if protocol.pdf"
    expect(Checksum.crc16XModem([0x2F, 0x30, 0x00, 0x00, 0x01, 0x00]) == 0xCFD4, "TestAlive CRC")
    expect(Checksum.crc16XModem([0x2F, 0x31, 0x00, 0x00, 0x01, 0x00]) == 0x6585, "GetVersion CRC")
    expect(Checksum.crc16XModem([0x2F, 0x38, 0x00, 0x00, 0x01, 0x00]) == 0xCDF9, "EraseAll CRC")
    expect(Checksum.crc16XModem([0x2E, 0x30, 0x00, 0x00, 0x01, 0x00, 0x00]) == 0x44C2, "TestAlive answer CRC")
    expect(FourWayClient.frame(0x34, address: 0, params: [0]) == [0x2F, 0x34, 0, 0, 1, 0, 0x46, 0xD2], "Exit frame")
    // BLHeli bootloader init "BLHeli" + CRC F4 7D
    expect(Checksum.crc16BLHeli(Array("BLHeli".utf8)) == 0x7DF4, "BLHeli boot init CRC")
} }

if enabled("hex") { test("intel hex") {
    var img = MemoryImage()
    img.write([0x02, 0x1C, 0x00], at: 0)
    img.write(Array(0..<40).map { UInt8($0) }, at: 0x1A00)
    img.write([0xAA], at: 0x12345)
    let text = img.intelHex()
    let back = try MemoryImage.parseIntelHex(text)
    expect(back == img, "roundtrip")
    expect(back.read(0x1A05, 3) == [5, 6, 7], "read")
    expect(back.read(0x1A50, 2) == [0xFF, 0xFF], "fill")
    let bad = ":03000000020D06E9\n"
    expect((try? MemoryImage.parseIntelHex(bad)) == nil, "bad checksum rejected")
} }

if enabled("database") { test("firmware database") {
    expect(db.silabs.firmware.count == 6933, "6933 SiLabs files")
    expect(db.atmel.firmware.count == 1948, "1948 Atmel files")
    expect(db.silabs.layouts.count == 774, "SiLabs layouts incl. generated BLHeli_S")
    expect(db.layoutIndex(family: .silabs, name: "a_h_30") == 104, "A_H_30 index")
    expect(db.layout(family: .silabs, index: 104)?.desc == "A-H-30", "A_H_30 description")
    expect(db.layout(family: .silabs, index: db.layoutIndex(family: .silabs, name: "Q_H_15")!)?.leds == 2, "Q has 2 LEDs")
    let e = db.entries(family: .silabs, mcuCode: 0x32).first { $0.name == "A_H_30" && $0.revStr == "16.7" }!
    let img = db.flashImage(e)
    let s = BLHeliSettings(raw: img.read(0x1A00, 0x70))
    expect(s.revisionString == "16.7" && s.layoutName == "A_H_30" && s.isBLHeliS && s.mode == .multi, "BLHeli_S defaults \(s.summary(database: db))")
    expect(img.contains(range: 0x1C00..<0x1C10), "BLHeli_S file contains bootloader")
    expect(db.bootloaders.count == 48, "48 Atmel bootloaders")
} }

if enabled("settings") { test("settings of every built-in file") {
    var bad = 0, outOfRange = 0, defaultMismatch = [String: Int]()
    for fam in [MCUFamily.silabs, .atmel] {
        for e in db.family(fam)!.firmware {
            let plan = FirmwareSelection.makePlan(db, entry: e, current: nil).plan
            guard let s = plan.defaultSettings else { bad += 1; continue }
            do { try s.validate() } catch { bad += 1; if bad < 5 { print("    invalid \(e.name) \(e.revStr): \(error)") }; continue }
            expect(s.mode.rawValue == e.mode, "mode of \(e.name) \(e.revStr)")
            expect(s.isBLHeliS == e.isBLHeliS, "S flag of \(e.name)")
            expect(Int(s.layoutRevision) == Int(e.layoutRev), "layout rev of \(e.name) \(e.revStr)")
            expect(db.layoutIndex(family: fam, name: s.layoutName) == e.layout, "layout name \(s.layoutName) vs \(e.name)")
            let ctx = s.context(database: db, firmware: e)
            for p in BLHeliParam.editable where BLHeliParamLogic.exists(p, ctx) {
                let v = s.value(p)
                if !BLHeliParamLogic.isValid(p, value: v, ctx) {
                    outOfRange += 1
                    if outOfRange < 8 { print("    \(e.name) \(e.revStr) \(e.modeName): \(p.plainName)=\(v) outside \(BLHeliParamLogic.range(p, ctx))") }
                }
                if let d = BLHeliParamLogic.defaultValue(p, ctx), d != v { defaultMismatch[p.plainName, default: 0] += 1 }
            }
        }
    }
    expect(bad == 0, "\(bad) files with invalid setup")
    expect(outOfRange == 0, "\(outOfRange) values out of range")
    if !defaultMismatch.isEmpty {
        print("    info: defaults differing from file content: " + defaultMismatch.sorted { $0.value > $1.value }.prefix(8).map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
    }
} }

if enabled("translate") { test("settings translation") {
    // BLHeli_S 16.5 -> 16.7, user changed direction, timing, beep
    let li = db.layoutIndex(family: .silabs, name: "A_H_30")!
    let e165 = db.entries(family: .silabs, layout: li).first { $0.revStr == "16.5" }!
    let e167 = db.entries(family: .silabs, layout: li).first { $0.revStr == "16.7" }!
    var old = FirmwareSelection.makePlan(db, entry: e165, current: nil).plan.defaultSettings!
    old.setValue(.direction, 2)
    old.setValue(.commutationTiming, 5)
    old.setValue(.beepStrength, 120)
    old.setValue(.ppmMinThrottle, 30)
    old.name = "FrontLeft"
    let r = FirmwareSelection.makePlan(db, entry: e167, current: old)
    expect(r.warning == nil, "no warning")
    let n = r.plan.settings!
    expect(n.revisionString == "16.7", "new revision")
    expect(n.value(.direction) == 2 && n.value(.commutationTiming) == 5 && n.value(.beepStrength) == 120, "values kept")
    expect(n.value(.ppmMinThrottle) == 30, "throttle kept")
    expect(n.name == "FrontLeft", "name kept")
    // BLHeli_S 16.0 (temp on/off) -> 16.7 (temp levels)
    if let e160 = db.entries(family: .silabs, layout: li).first(where: { $0.revStr == "16.0" }) {
        var o = FirmwareSelection.makePlan(db, entry: e160, current: nil).plan.defaultSettings!
        o.setValue(.temperatureProtection, 1)
        let t = FirmwareSelection.makePlan(db, entry: e167, current: o).plan.settings!
        expect(t.value(.temperatureProtection) == 7, "temp on -> 140°C")
        o.setValue(.temperatureProtection, 0)
        let t2 = FirmwareSelection.makePlan(db, entry: e167, current: o).plan.settings!
        expect(t2.value(.temperatureProtection) == 0, "temp off stays off")
    }
    // MULTI -> MAIN refused
    let atm = db.entries(family: .atmel, layout: db.layoutIndex(family: .atmel, name: "AFRO_12A")!)
    let multi = atm.first { $0.mode == 2 && $0.revStr == "14.9" }!
    let main = atm.first { $0.mode == 0 && $0.revStr == "14.9" }!
    let m = FirmwareSelection.makePlan(db, entry: main, current: FirmwareSelection.makePlan(db, entry: multi, current: nil).plan.defaultSettings)
    expect(m.warning != nil, "mode change is reported")
    // every translated result must be valid for the new firmware (all BLHeli SiLabs MULTI A->B pairs of one layout)
    let lt = db.layoutIndex(family: .silabs, name: "XP12A")!
    let entries = db.entries(family: .silabs, layout: lt, mode: .multi)
    var invalid = 0
    for a in entries { for b in entries {
        let sa = FirmwareSelection.makePlan(db, entry: a, current: nil).plan.defaultSettings!
        let tr = FirmwareSelection.makePlan(db, entry: b, current: sa)
        guard let s = tr.plan.settings else { continue }
        let ctx = s.context(database: db, firmware: b)
        for p in BLHeliParam.editable where BLHeliParamLogic.exists(p, ctx) && !BLHeliParamLogic.isValid(p, value: s.value(p), ctx) {
            invalid += 1
            if invalid < 6 { print("    \(a.revStr)->\(b.revStr): \(p.plainName)=\(s.value(p))") }
        }
    } }
    expect(invalid == 0, "\(invalid) invalid values after translation between \(entries.count) revisions")
} }

// MARK: - End to end with the simulator

final class Rig {
    let pty: PseudoTerminal
    let sim: SimulatedFlightController
    let programmer: FourWayProgrammer
    let ops: ESCOperations

    init(personality: SimulatedFlightController.Personality, escs: [SimulatedESC], type: InterfaceType) throws {
        pty = try PseudoTerminal()
        sim = SimulatedFlightController(channel: pty, personality: personality, escs: escs)
        sim.start()
        programmer = try ProgrammerFactory.openSerial(type, portPath: pty.slavePath, baud: type.defaultBaud, arduinoResetDelay: 0)
        pty.releaseSlaveHold()
        ops = ESCOperations(programmer: programmer)
    }

    func close() {
        programmer.disconnect()
        sim.stop()
        pty.close()
    }
}

func blheliS(_ layout: String, _ rev: String, mcuCode: Int = 0x32) -> FirmwareEntry {
    db.entries(family: .silabs, mcuCode: mcuCode).first { $0.name == layout && $0.revStr == rev }!
}

func makeSiLabsESC(_ e: FirmwareEntry) -> SimulatedESC {
    let mcu = e.mcu == 0x32 ? MCUTable.byBootSignature(0xE8B2)! : (e.mcu == 0x30 ? MCUTable.byBootSignature(0xE8B1)! : MCUTable.byBootSignature(0xF330)!)
    let esc = SimulatedESC(mcu: mcu)
    var img = db.flashImage(e)
    if !img.contains(range: 0x1C00..<0x1C10), let boot = db.entries(family: .silabs, mcuCode: 0x32).first.map({ db.flashImage($0) }) {
        // old BLHeli files have no bootloader – give the simulated ESC one
        for a in 0x1C00..<0x1E00 { if let b = boot[a] { img[a] = b } }
    }
    esc.program(flash: img)
    return esc
}

if enabled("e2e-read") { test("FC passthrough: identify and read 4 ESCs") {
    let e = blheliS("A_H_30", "16.6")
    let rig = try Rig(personality: .betaflight, escs: (0..<4).map { _ in makeSiLabsESC(e) }, type: .silabsBLBFlightController)
    defer { rig.close() }
    expect(rig.programmer.escCount == 4, "4 channels")
    for i in 0..<4 {
        let dev = try rig.programmer.selectESC(i)
        expect(dev.mcu?.name == "EFM8BB21F16G", "MCU \(dev.description)")
        let s = try rig.ops.readSettings(device: dev)
        try s.validate()
        expect(s.layoutName == "A_H_30" && s.revisionString == "16.6", "settings \(s.summary(database: db))")
    }
} }

if enabled("e2e-write") { test("FC passthrough: write setup") {
    let e = blheliS("A_H_30", "16.6")
    let esc = makeSiLabsESC(e)
    let rig = try Rig(personality: .betaflight, escs: [esc, makeSiLabsESC(e)], type: .silabsBLBFlightController)
    defer { rig.close() }
    let dev = try rig.programmer.selectESC(1)
    var s = try rig.ops.readSettings(device: dev)
    s.setValue(.direction, 3)
    s.setValue(.beaconStrength, 200)
    s.name = "Rear Right"
    try rig.ops.writeSettings(s, device: dev)
    let back = rig.sim.escs[1].settings
    expect(back.value(.direction) == 3 && back.value(.beaconStrength) == 200 && back.name == "Rear Right", "written")
    expect(rig.sim.escs[0].settings.value(.direction) == 1, "ESC #1 untouched")
} }

if enabled("e2e-flash") { test("FC passthrough: flash BLHeli_S 16.7 over 16.6 keeping settings") {
    let e166 = blheliS("A_H_30", "16.6"), e167 = blheliS("A_H_30", "16.7")
    let esc = makeSiLabsESC(e166)
    let rig = try Rig(personality: .betaflight, escs: [esc], type: .silabsBLBFlightController)
    defer { rig.close() }
    let dev = try rig.programmer.selectESC(0)
    var s = try rig.ops.readSettings(device: dev)
    s.setValue(.direction, 2)
    try rig.ops.writeSettings(s, device: dev)
    let cur = try rig.ops.readSettings(device: dev)
    let bootBefore = Array(esc.flash[0x1C00..<0x2000])
    let plan = FirmwareSelection.makePlan(db, entry: e167, current: cur).plan
    try rig.ops.flash(plan, device: dev, currentSettings: cur)
    let expected = try rig.ops.siLabsBootloaderImage(for: plan)
    expect(Array(esc.flash[0..<0x1C00]) == expected, "flash content")
    expect(Array(esc.flash[0x1C00..<0x2000]) == bootBefore, "bootloader untouched")
    let after = try rig.ops.readSettings(device: dev)
    expect(after.revisionString == "16.7" && after.value(.direction) == 2, "rev 16.7, direction kept")
    expect(!after.flashFailedMarker, "no failure marker")
} }

if enabled("e2e-interrupt") { test("interrupted flash is recoverable") {
    let e166 = blheliS("A_H_30", "16.6"), e167 = blheliS("A_H_30", "16.7")
    let esc = makeSiLabsESC(e166)
    let rig = try Rig(personality: .betaflight, escs: [esc], type: .silabsBLBFlightController)
    defer { rig.close() }
    let dev = try rig.programmer.selectESC(0)
    let cur = try rig.ops.readSettings(device: dev)
    esc.failAfterWrites = esc.writeCount + 10
    let plan = FirmwareSelection.makePlan(db, entry: e167, current: cur).plan
    var failed = false
    do { try rig.ops.flash(plan, device: dev, currentSettings: cur) } catch { failed = true }
    expect(failed, "flash failed as simulated")
    // power cycle
    esc.failAfterWrites = nil
    // page 0 must jump to the bootloader or be empty with LJMP on page 1
    let p0 = Array(esc.flash[0..<3]), p1 = Array(esc.flash[0x200..<0x203])
    expect(p0 == [0x02, 0x1C, 0x00] || (esc.flash[0..<0x200].allSatisfy { $0 == 0xFF } && p1 == [0x02, 0x1C, 0x00]), "reset vector leads to bootloader")
    let dev2 = try rig.programmer.selectESC(0)
    let broken = try rig.ops.readSettings(device: dev2)
    expect(broken.flashFailedMarker || broken.revisionString == "16.6", "failure visible (\(broken.name))")
    try rig.ops.flash(plan, device: dev2, currentSettings: broken)
    let ok = try rig.ops.readSettings(device: dev2)
    expect(ok.revisionString == "16.7", "recovered")
} }

if enabled("e2e-atmel") { test("Atmel via FC: flash 14.9 over 14.8") {
    let li = db.layoutIndex(family: .atmel, name: "AFRO_12A")!
    let all = db.entries(family: .atmel, layout: li, mode: .multi)
    let e148 = all.first { $0.revStr == "14.8" }!, e149 = all.first { $0.revStr == "14.9" }!
    let esc = SimulatedESC(mcu: MCUTable.byAVRSignature(0x1E9307)!)
    esc.program(flash: db.flashImage(e148), eeprom: db.eepromImage(e148))
    if let boot = db.bootloaderImage(named: "BLHELI_M8_16_PB0") { esc.program(flash: boot) }
    let rig = try Rig(personality: .betaflight, escs: [esc], type: .atmelFlightController)
    defer { rig.close() }
    let dev = try rig.programmer.selectESC(0)
    expect(dev.family == .atmel && dev.mcu?.name == "ATmega8", "ATmega8 detected: \(dev.description)")
    var cur = try rig.ops.readSettings(device: dev)
    try cur.validate()
    cur.setValue(.direction, 2)
    try rig.ops.writeSettings(cur, device: dev)
    let plan = FirmwareSelection.makePlan(db, entry: e149, current: cur).plan
    try rig.ops.flash(plan, device: dev, currentSettings: cur)
    let after = try rig.ops.readSettings(device: dev)
    expect(after.revisionString == "14.9" && after.value(.direction) == 2, "14.9 + direction kept: \(after.summary(database: db))")
    let expected = db.flashImage(e149).read(0, 0x2000 - 0x200)
    expect(Array(esc.flash[0..<(0x2000 - 0x200)]) == expected, "flash content")
} }

if enabled("e2e-c2") { test("Arduino 4w-if in C2 mode: full flash of an empty chip") {
    let e = blheliS("A_L_15", "16.7", mcuCode: 0x30)
    let esc = SimulatedESC(mcu: MCUTable.byBootSignature(0xE8B1)!)  // completely erased
    let rig = try Rig(personality: .arduinoBox(multi: false), escs: [esc], type: .silabsC2FourWay)
    defer { rig.close() }
    let dev = try rig.programmer.selectESC(0)
    expect(dev.interfaceMode == .siLabsC2 && dev.mcu?.c2DeviceID == 0x30, "C2 device \(dev.description)")
    let s = try rig.ops.readSettings(device: dev)
    expect((try? s.validate()) == nil, "blank ESC has no setup")
    let plan = FirmwareSelection.makePlan(db, entry: e, current: s).plan
    try rig.ops.flash(plan, device: dev, currentSettings: s)
    let img = db.flashImage(e)
    var same = true
    for (a, b) in img.bytes where esc.flash[a] != b { same = false; break }
    expect(same, "image incl. bootloader written")
    let after = try rig.ops.readSettings(device: dev)
    expect(after.layoutName == "A_L_15" && after.revisionString == "16.7", "settings \(after.summary(database: db))")
} }

if enabled("e2e-box") { test("Arduino 4w-if bootloader mode: read + flash old BLHeli SiLabs") {
    let li = db.layoutIndex(family: .silabs, name: "XP12A")!
    let entries = db.entries(family: .silabs, layout: li, mode: .multi)
    let older = entries.first { $0.revStr == "14.6" }!, newest = entries.max { $0.rev < $1.rev }!
    let esc = makeSiLabsESC(older)
    let rig = try Rig(personality: .arduinoBox(multi: true), escs: [esc], type: .silabsBLBFourWay)
    defer { rig.close() }
    expect(rig.programmer.escCount == 8, "multi box has 8 channels")
    let dev = try rig.programmer.selectESC(0)
    let cur = try rig.ops.readSettings(device: dev)
    expect(cur.revisionString == "14.6", "14.6 found")
    let pref = FirmwareSelection.preferred(db, device: dev, settings: cur)
    expect(pref?.res == newest.res, "preferred = newest XP12A MULTI (\(pref?.revStr ?? "nil"))")
    let plan = FirmwareSelection.makePlan(db, entry: newest, current: cur).plan
    try rig.ops.flash(plan, device: dev, currentSettings: cur)
    let after = try rig.ops.readSettings(device: dev)
    expect(after.revisionString == newest.revStr, "flashed \(after.revisionString)")
    expect((try? rig.programmer.selectESC(3)) == nil, "missing ESC reported")
} }

if enabled("e2e-toolstick") { test("Toolstick C2: flash an erased EFM8BB21 incl. bootloader") {
    let e = blheliS("D_H_15", "16.7")
    let esc = SimulatedESC(mcu: MCUTable.byBootSignature(0xE8B2)!)
    for i in 0..<esc.flash.count { esc.flash[i] = UInt8(truncatingIfNeeded: i * 7) }  // garbage, needs erase
    let ts = ToolstickProgrammer(transport: SimulatedToolstick(esc: esc))
    try ts.initAdapter()
    let dev = try ts.selectESC(0)
    expect(dev.interfaceMode == .siLabsC2 && dev.mcu?.c2DeviceID == 0x32, "EFM8BB2 via C2: \(dev.description)")
    let ops = ESCOperations(programmer: ts)
    let plan = FirmwareSelection.makePlan(db, entry: e, current: nil).plan
    try ops.flash(plan, device: dev, currentSettings: nil)
    var same = true
    for (a, b) in db.flashImage(e).bytes where esc.flash[a] != b { same = false; break }
    expect(same, "image written")
    expect(esc.flash[0x3000] == 0xFF, "rest erased")
    let s = try ops.readSettings(device: dev)
    expect(s.layoutName == "D_H_15" && s.revisionString == "16.7", "setup \(s.summary(database: db))")
    var w = s
    w.setValue(.direction, 2)
    try ops.writeSettings(w, device: dev)
    expect(esc.settings.value(.direction) == 2, "setup written via C2")
} }

if enabled("arduino") { test("Make interface: flash 4way-if firmware into an Arduino Nano (STK500v1)") {
    guard let folder = ArduinoBoard.interfacesFolder() else { expect(false, "Interfaces folder"); return }
    let nano = ArduinoBoard.all.first { $0.tag == "Nano_328" }!
    let hex = nano.firmwareURL(.fourWayMulti, in: folder)
    expect(hex?.lastPathComponent == "4wArduino_Nano__16_MULTIv20005.hex", "firmware file \(hex?.lastPathComponent ?? "nil")")
    for b in ArduinoBoard.all where b.nativeFlashSupported {
        for k in ArduinoBoard.InterfaceFirmware.allCases where b.firmwarePath(k) != nil && b.part != "m8" && b.part != "m1280" {
            if k == .fourWayPD3PD2 && b.tag != "Nano_328" { continue }
            if k == .blheliBootloader && !["Uno", "Nano_328", "Nano_168", "Nano_328_new"].contains(b.tag) { continue }
            expect(b.firmwareURL(k, in: folder) != nil, "\(b.tag) \(k.rawValue) file exists (\(b.firmwarePath(k) ?? ""))")
        }
    }
    guard let url = hex else { return }
    let image = try MemoryImage.loadIntelHex(url: url)
    let pty = try PseudoTerminal()
    let boot = SimulatedArduinoBootloader(channel: pty)
    boot.start()
    defer { boot.stop(); pty.close() }
    let port = SerialPort(path: pty.slavePath)
    try port.open(baudRate: 57600)
    pty.releaseSlaveHold()
    defer { port.close() }
    try STK500v1(port: port).flash(image, pageSize: 128, expectedSignature: 0x1E950F, verify: true)
    var same = true
    for (a, b) in image.bytes where boot.flash[a] != b { same = false; break }
    expect(same, "Arduino flash content")
} }

if enabled("e2e-armed") { test("FC armed: passthrough refused") {
    let pty = try PseudoTerminal()
    let sim = SimulatedFlightController(channel: pty, personality: .betaflight, escs: [makeSiLabsESC(blheliS("A_H_30", "16.6"))])
    sim.armed = true
    sim.start()
    defer { sim.stop(); pty.close() }
    var refused = false
    do {
        let p = try ProgrammerFactory.openSerial(.silabsBLBFlightController, portPath: pty.slavePath, baud: 115200)
        p.disconnect()
    } catch ConnectError.armed { refused = true }
    expect(refused, "armed FC refused")
} }

print("")
print(failures == 0 ? "ALL \(checks) CHECKS PASSED" : "\(failures) of \(checks) CHECKS FAILED")
exit(failures == 0 ? 0 : 1)
