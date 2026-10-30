import Foundation
import BLHeliCore

// Command line front end – handy for scripting and for testing without the GUI.

func usage() -> Never {
    print("""
    blheli-cli – BLHeliSuite for Mac command line

      blheli-cli ports
      blheli-cli db [silabs|atmel] [layout-filter]
      blheli-cli read  --port <dev> [--if fc|box|c2] [--baud N] [--esc N]
      blheli-cli set   --port <dev> [--if ...] [--esc N] <Eep_Name|index>=<value> ...
      blheli-cli flash --port <dev> [--if ...] [--esc N] (--res <db index> | --hex <file> [--eep <file>]) [--no-verify]

    Interfaces: fc = Betaflight/Cleanflight passthrough (default), box = Arduino 4w-if (bootloader),
                c2 = Arduino 4w-if in SiLabs C2 mode, atmel-fc / atmel-box for Atmel ESCs.
    Use --port sim to talk to the built-in simulator (BLHeli_S A_H_30 ESCs).
    """)
    exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }
args.removeFirst()

func option(_ name: String) -> String? {
    if let i = args.firstIndex(of: name), i + 1 < args.count {
        let v = args[i + 1]
        args.removeSubrange(i...(i + 1))
        return v
    }
    return nil
}
func flag(_ name: String) -> Bool {
    if let i = args.firstIndex(of: name) { args.remove(at: i); return true }
    return false
}

Log.shared.echoToStderr = true
if flag("--trace") { Log.shared.protocolTrace = true; Log.shared.minimumEchoLevel = .debug }

func fail(_ e: Error) -> Never {
    FileHandle.standardError.write("ERROR: \((e as? LocalizedError)?.errorDescription ?? "\(e)")\n".data(using: .utf8)!)
    exit(2)
}

func interfaceType(_ s: String?) -> InterfaceType {
    switch s ?? "fc" {
    case "fc": return .silabsBLBFlightController
    case "box": return .silabsBLBFourWay
    case "c2": return .silabsC2FourWay
    case "atmel-fc": return .atmelFlightController
    case "atmel-box": return .atmelBLBFourWay
    case "atmel-sk": return .atmelSKFourWay
    default: usage()
    }
}

var simulator: SimulatedFlightController?

func openProgrammer() -> FourWayProgrammer {
    guard let port = option("--port") else { usage() }
    let type = interfaceType(option("--if"))
    let baud = option("--baud").flatMap(Int.init) ?? type.defaultBaud
    do {
        if port == "sim" {
            let db = try FirmwareDatabase.shared()
            let pty = try PseudoTerminal()
            var escs: [SimulatedESC] = []
            let entry = db.entries(family: .silabs, mcuCode: 0x32).first { $0.name == "A_H_30" && $0.revStr == "16.6" }!
            for _ in 0..<4 {
                let e = SimulatedESC(mcu: MCUTable.byBootSignature(0xE8B2)!)
                e.program(flash: db.flashImage(entry))
                escs.append(e)
            }
            let sim = SimulatedFlightController(channel: pty, personality: .betaflight, escs: escs)
            sim.start()
            simulator = sim
            let p = try ProgrammerFactory.openSerial(type, portPath: pty.slavePath, baud: baud)
            pty.releaseSlaveHold()
            return p
        }
        return try ProgrammerFactory.openSerial(type, portPath: port, baud: baud)
    } catch { fail(error) }
}

do {
    switch command {
    case "ports":
        for p in SerialPort.availablePorts() {
            print("\(p.path)\t\(p.product ?? "")\t\(p.vendorID.map { String(format: "%04X:%04X", $0, p.productID ?? 0) } ?? "")")
        }

    case "db":
        let db = try FirmwareDatabase.shared()
        let fam: MCUFamily = args.first == "atmel" ? .atmel : .silabs
        if !args.isEmpty && (args[0] == "atmel" || args[0] == "silabs") { args.removeFirst() }
        let filter = args.first?.uppercased()
        for e in db.family(fam)!.firmware {
            let l = db.layout(family: fam, index: e.layout)
            if let f = filter, !(l?.name.uppercased().contains(f) ?? false) && !(l?.desc.uppercased().contains(f) ?? false) { continue }
            print(String(format: "%5d  %-16@ %-28@ %@ %@ %@ mcu=0x%X", e.res, e.name, l?.desc ?? "", e.firmwareName, e.revStr, e.modeName, e.mcu))
        }

    case "read":
        let escIndex = option("--esc").flatMap(Int.init).map { $0 - 1 }
        let p = openProgrammer()
        defer { p.disconnect() }
        let db = try? FirmwareDatabase.shared()
        let ops = ESCOperations(programmer: p)
        let range = escIndex.map { [$0] } ?? Array(0..<p.escCount)
        for i in range {
            do {
                let dev = try p.selectESC(i)
                let s = try ops.readSettings(device: dev)
                print("ESC #\(i + 1): \(dev.description) – \(s.summary(database: db))  name=\"\(s.name)\"")
                let ctx = s.context(database: db)
                for param in BLHeliParam.editable where BLHeliParamLogic.exists(param, ctx) {
                    let v = s.value(param)
                    print(String(format: "   %-26@ %3d  %@", param.displayName(ctx), v, BLHeliParamLogic.label(param, value: v, ctx)))
                }
            } catch {
                print("ESC #\(i + 1): \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
            }
        }

    case "set":
        let escIndex = (option("--esc").flatMap(Int.init) ?? 1) - 1
        let p = openProgrammer()
        defer { p.disconnect() }
        let db = try? FirmwareDatabase.shared()
        let ops = ESCOperations(programmer: p)
        let dev = try p.selectESC(escIndex)
        var s = try ops.readSettings(device: dev)
        try s.validate()
        let ctx = s.context(database: db)
        for a in args {
            let kv = a.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2, let v = Int(kv[1]) else { usage() }
            guard let param = BLHeliParam.allCases.first(where: { $0.eepName == kv[0] || String($0.rawValue) == kv[0] || $0.plainName == kv[0] }) else {
                fail(SettingsError.unknownLayout(kv[0]))
            }
            guard BLHeliParamLogic.isValid(param, value: v, ctx) else {
                fail(ProgrammerError.notSupported("Value \(v) is not valid for \(param.plainName) (range \(BLHeliParamLogic.range(param, ctx)))"))
            }
            s.setValue(param, v)
        }
        try ops.writeSettings(s, device: dev)
        print("Setup written to ESC #\(escIndex + 1)")

    case "flash":
        let escIndex = (option("--esc").flatMap(Int.init) ?? 1) - 1
        let res = option("--res").flatMap(Int.init)
        let hex = option("--hex")
        let eep = option("--eep")
        let verify = !flag("--no-verify")
        let p = openProgrammer()
        defer { p.disconnect() }
        let db = try FirmwareDatabase.shared()
        let ops = ESCOperations(programmer: p)
        ops.verify = verify
        var lastPct = -1
        ops.onProgress = { pr in
            let pct = Int(pr.fraction * 100)
            if pct / 10 != lastPct / 10 { lastPct = pct; FileHandle.standardError.write("  \(pr.message) \(pct)%\n".data(using: .utf8)!) }
        }
        let dev = try p.selectESC(escIndex)
        let cur = try? ops.readSettings(device: dev)
        let planResult: (plan: FlashPlan, warning: String?)
        var entry: FirmwareEntry?
        if let r = res {
            guard let e = db.entry(family: dev.family, res: r) else { fail(ProgrammerError.notSupported("No firmware #\(r)")) }
            entry = e
            planResult = FirmwareSelection.makePlan(db, entry: e, current: cur)
        } else if let h = hex {
            planResult = try FirmwareSelection.makePlan(hexURL: URL(fileURLWithPath: h), eepURL: eep.map { URL(fileURLWithPath: $0) }, current: cur, db: db)
        } else if let e = FirmwareSelection.preferred(db, device: dev, settings: cur) {
            entry = e
            planResult = FirmwareSelection.makePlan(db, entry: e, current: cur)
        } else { usage() }
        if let w = planResult.warning { print("Warning: \(w)") }
        for w in FirmwareSelection.check(plan: planResult.plan, entry: entry, device: dev, current: cur, db: db) { print("Warning: \(w)") }
        print("Flashing ESC #\(escIndex + 1) with \(planResult.plan.title)")
        let t0 = Date()
        try ops.flash(planResult.plan, device: dev, currentSettings: cur)
        let after = try ops.readSettings(device: dev)
        print(String(format: "Flashed successfully in %.1f s: %@", Date().timeIntervalSince(t0), after.summary(database: db)))

    default:
        usage()
    }
} catch {
    fail(error)
}
