import Foundation
import BLHeliCore

// Virtual flight controller / 4-way box with simulated ESCs on a pseudo terminal.
// Connect the GUI (or blheli-cli) to the printed /dev/ttys… path.

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    if let i = args.firstIndex(of: name), i + 1 < args.count { let v = args[i + 1]; args.removeSubrange(i...(i + 1)); return v }
    return nil
}
func flag(_ name: String) -> Bool {
    if let i = args.firstIndex(of: name) { args.remove(at: i); return true }
    return false
}

if flag("--help") {
    print("""
    blheli-sim [--escs N] [--layout A_H_30] [--rev 16.6] [--atmel] [--box] [--multi-box] [--blank] [--trace]
      default: Betaflight FC with 4 BLHeli_S ESCs (EFM8BB21, layout A_H_30, rev 16.6)
      --atmel   ATmega8 ESCs with BLHeli Atmel (layout AFRO_12A, rev 14.9)
      --box     Arduino 4w-if box instead of a flight controller (supports C2 mode)
      --blank   ESCs with an erased application (bootloader only)
    """)
    exit(0)
}

Log.shared.echoToStderr = true
if flag("--trace") { Log.shared.protocolTrace = true; Log.shared.minimumEchoLevel = .debug }
let count = option("--escs").flatMap(Int.init) ?? 4
let atmel = flag("--atmel")
let box = flag("--box")
let multiBox = flag("--multi-box")
let blank = flag("--blank")
let layoutName = option("--layout") ?? (atmel ? "AFRO_12A" : "A_H_30")
let rev = option("--rev") ?? (atmel ? "14.9" : "16.6")

do {
    let db = try FirmwareDatabase.shared()
    let family: MCUFamily = atmel ? .atmel : .silabs
    guard let li = db.layoutIndex(family: family, name: layoutName) else {
        print("Unknown layout \(layoutName)"); exit(1)
    }
    guard let entry = db.entries(family: family, layout: li).first(where: { $0.revStr == rev && ($0.mode == 2 || atmel) }) ??
            db.entries(family: family, layout: li).last else {
        print("No firmware for \(layoutName) \(rev)"); exit(1)
    }
    let mcu: MCUInfo
    if atmel {
        mcu = MCUTable.byAVRSignature(UInt32(entry.mcu))!
    } else {
        mcu = MCUTable.all.first { $0.family == .silabs && Int($0.c2DeviceID) == entry.mcu && $0.name.hasPrefix(entry.mcu == 0x32 ? "EFM8BB2" : (entry.mcu == 0x30 ? "EFM8BB1" : "C8051")) }
            ?? MCUTable.byBootSignature(0xE8B2)!
    }
    var escs: [SimulatedESC] = []
    for _ in 0..<count {
        let e = SimulatedESC(mcu: mcu)
        var img = db.flashImage(entry)
        if blank {
            // keep only the bootloader part of BLHeli_S images
            img.remove(range: 0..<0x1C00)
        }
        e.program(flash: img, eeprom: blank ? nil : db.eepromImage(entry))
        escs.append(e)
    }
    let pty = try PseudoTerminal()
    let personality: SimulatedFlightController.Personality = (box || multiBox) ? .arduinoBox(multi: multiBox) : .betaflight
    let sim = SimulatedFlightController(channel: pty, personality: personality, escs: escs)
    sim.latency = 0.002
    sim.start()
    print("Simulator ready: \(box || multiBox ? "Arduino 4w-if" : "Betaflight FC") with \(count) × \(mcu.name) running \(entry.firmwareName) \(entry.revStr) \(layoutName) \(entry.modeName)")
    print("Serial port: \(pty.slavePath)")
    fflush(stdout)
    signal(SIGINT) { _ in exit(0) }
    while true { sleep(1) }
} catch {
    print("ERROR: \(error)")
    exit(1)
}
