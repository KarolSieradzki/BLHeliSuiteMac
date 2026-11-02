import Foundation

/// Arduino board table of BLHeliSuite (0x68FB44: name, file tag, avrdude part, MHz, bootloader baud, programmer).
public struct ArduinoBoard: Hashable, Sendable {
    public let name: String
    public let tag: String
    public let part: String
    public let mhz: Int
    public let baud: Int
    public let programmer: String

    public static let all: [ArduinoBoard] = [
        ArduinoBoard(name: "Uno w/ ATmega328", tag: "Uno", part: "m328p", mhz: 16, baud: 115200, programmer: "arduino"),
        ArduinoBoard(name: "Duemilanove w/ ATmega328", tag: "Due_328", part: "m328p", mhz: 16, baud: 57600, programmer: "arduino"),
        ArduinoBoard(name: "Diecimila or Duemilanove w/ ATmega168", tag: "Dieci_Due_168", part: "m168", mhz: 16, baud: 19200, programmer: "arduino"),
        ArduinoBoard(name: "Nano w/ ATmega328", tag: "Nano_328", part: "m328p", mhz: 16, baud: 57600, programmer: "arduino"),
        ArduinoBoard(name: "Nano w/ ATmega168", tag: "Nano_168", part: "m168", mhz: 16, baud: 19200, programmer: "arduino"),
        ArduinoBoard(name: "Mega 2560 or Mega ADK w/ ATmega2560", tag: "Mega_2560_ADK", part: "m2560", mhz: 16, baud: 115200, programmer: "wiring"),
        ArduinoBoard(name: "Mega (ATmega1280)", tag: "Mega_1280", part: "m1280", mhz: 16, baud: 57600, programmer: "arduino"),
        ArduinoBoard(name: "Leonardo w/ ATmega32u4", tag: "Leonardo", part: "atmega32u4", mhz: 16, baud: 57600, programmer: "avr109"),
        ArduinoBoard(name: "Esplora w/ ATmega32u4", tag: "Esplora", part: "atmega32u4", mhz: 16, baud: 57600, programmer: "avr109"),
        ArduinoBoard(name: "Micro w/ ATmega32u4", tag: "Micro", part: "atmega32u4", mhz: 16, baud: 57600, programmer: "avr109"),
        ArduinoBoard(name: "Mini w/ ATmega328", tag: "Mini_328", part: "m328p", mhz: 16, baud: 115200, programmer: "arduino"),
        ArduinoBoard(name: "Mini w/ ATmega168", tag: "Mini_168", part: "m168", mhz: 16, baud: 19200, programmer: "arduino"),
        ArduinoBoard(name: "Ethernet w/ ATmega328", tag: "Ethernet", part: "m328p", mhz: 16, baud: 115200, programmer: "arduino"),
        ArduinoBoard(name: "Fio w/ ATmega328", tag: "Fio", part: "m328p", mhz: 8, baud: 57600, programmer: "arduino"),
        ArduinoBoard(name: "BT w/ ATmega328", tag: "BT_328", part: "m328p", mhz: 16, baud: 19200, programmer: "arduino"),
        ArduinoBoard(name: "BT w/ ATmega168", tag: "BT_168", part: "m168", mhz: 16, baud: 19200, programmer: "arduino"),
        ArduinoBoard(name: "LilyPad USB w/ ATmega32u4", tag: "LilyPad_USB", part: "atmega32u4", mhz: 8, baud: 57600, programmer: "avr109"),
        ArduinoBoard(name: "LilyPad w/ ATmega328", tag: "LilyPad_328", part: "m328p", mhz: 8, baud: 57600, programmer: "arduino"),
        ArduinoBoard(name: "LilyPad w/ ATmega168", tag: "LilyPad_168", part: "m168", mhz: 8, baud: 19200, programmer: "arduino"),
        ArduinoBoard(name: "Pro or Pro Mini (5V, 16 MHz) w/ ATmega328", tag: "ProMini_328_16", part: "m328p", mhz: 16, baud: 57600, programmer: "arduino"),
        ArduinoBoard(name: "Pro or Pro Mini (5V, 16 MHz) w/ ATmega168", tag: "ProMini_168_16", part: "m168", mhz: 16, baud: 19200, programmer: "arduino"),
        ArduinoBoard(name: "Pro or Pro Mini (3.3V, 8 MHz) w/ ATmega328", tag: "ProMini_328_8", part: "m328p", mhz: 8, baud: 57600, programmer: "arduino"),
        ArduinoBoard(name: "Pro or Pro Mini (3.3V, 8 MHz) w/ ATmega168", tag: "ProMini_168_8", part: "m168", mhz: 8, baud: 19200, programmer: "arduino"),
        ArduinoBoard(name: "NG or older w/ ATmega168", tag: "NG_168", part: "m168", mhz: 16, baud: 19200, programmer: "arduino"),
        ArduinoBoard(name: "NG or older w/ ATmega8", tag: "NG-m8", part: "m8", mhz: 16, baud: 19200, programmer: "arduino"),
        ArduinoBoard(name: "Robot Control w/ ATmega32u4", tag: "RobotControl", part: "atmega32u4", mhz: 16, baud: 57600, programmer: "avr109"),
        ArduinoBoard(name: "Robot Motor w/ ATmega32u4", tag: "RobotMotor", part: "atmega32u4", mhz: 16, baud: 57600, programmer: "avr109"),
    ]

    /// Folder with the interface firmware files (bundled "Interfaces" or the original BLHeliSuite folder).
    public static func interfacesFolder() -> URL? {
        var candidates: [URL] = []
        if let r = Bundle.main.resourceURL { candidates.append(r.appendingPathComponent("Interfaces")) }
        if let env = ProcessInfo.processInfo.environment["BLHELISUITE_WINDOWS"] {
            candidates.append(URL(fileURLWithPath: env).appendingPathComponent("Interfaces"))
        }
        var d = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<7 {
            candidates.append(d.appendingPathComponent("Resources/Interfaces"))
            candidates.append(d.appendingPathComponent("BLHeliSuite/Interfaces"))
            d = d.deletingLastPathComponent()
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

/// Firmware files of "Make interfaces" – the file search of TfraMakeInterfaces (TJvSearchFiles in
/// FUN_00634858 / FUN_00635958): case-insensitive wildcard masks, searched below the Interfaces folder.
public enum InterfaceFirmwareFiles {
    /// Interface option prefixes of the 4way-if file names (table at 0x68E7E8).
    public static let prefixes = ["-", "B_", "D_", "Ds_", "2_", "2s_", "3_", "3s_", "4w", "4ws"]

    /// Option captions (FUN_005C28D0).
    public static func optionName(_ i: Int) -> String {
        switch i {
        case 1: return "[B] SILABS C2 (4way-if)"
        case 2: return "[D] SILABS BLHeli Bootloader (4way-if)"
        case 3: return "[D] SILABS BLHeli Bootloader (4way-if) - SERVO direct"
        case 4: return "[2] ATMEL BLHeli Bootloader (4way-if)"
        case 5: return "[2] ATMEL BLHeli Bootloader (4way-if) - SERVO direct"
        case 6: return "[3] ATMEL SK Bootloader (4way-if)"
        case 7: return "[3] ATMEL SK Bootloader (4way-if) - SERVO direct"
        case 8: return "[B D 2 3] SILABS and ATMEL switchable (for C2,  BLHeli or SK Bootloader)"
        case 9: return "[D 2 3] SILABS and ATMEL switchable - SERVO direct (for BLHeli or SK Bootloader)"
        default: return ""
        }
    }

    /// Wildcard match (`*` and `?`), ignoring case like the Windows file system.
    public static func matches(_ name: String, _ mask: String) -> Bool {
        let n = Array(name.lowercased()), m = Array(mask.lowercased())
        var memo = [Int: Bool]()
        func go(_ i: Int, _ j: Int) -> Bool {
            let key = i * (m.count + 1) + j
            if let v = memo[key] { return v }
            let r: Bool
            if j == m.count { r = i == n.count }
            else if m[j] == "*" { r = go(i, j + 1) || (i < n.count && go(i + 1, j)) }
            else { r = i < n.count && (m[j] == "?" || m[j] == n[i]) && go(i + 1, j + 1) }
            memo[key] = r
            return r
        }
        return go(0, 0)
    }

    /// All files below `folder` whose name matches `mask`, sorted by path.
    public static func find(_ mask: String, in folder: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var out: [URL] = []
        for case let u as URL in e where matches(u.lastPathComponent, mask) {
            if (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { out.append(u) }
        }
        return out.sorted { $0.path < $1.path }
    }

    /// FUN_00634858: interface options (bit i = prefixes[i]) of the files "*<mask>" whose name starts
    /// with "<prefix><name>".
    public static func options(name: String, mask: String, in folder: URL) -> UInt16 {
        var set: UInt16 = 0
        for f in find("*" + mask, in: folder) {
            let fn = f.lastPathComponent.lowercased()
            for i in stride(from: 9, through: 0, by: -1) where fn.hasPrefix((prefixes[i] + name).lowercased()) {
                set |= 1 << i
            }
        }
        return set
    }

    /// FUN_00635958: the file matching `mask` if it is the only one.
    public static func unique(_ mask: String, in folder: URL) -> URL? {
        let f = find(mask, in: folder)
        return f.count == 1 ? f[0] : nil
    }

    /// Base name of the 4way-if firmware of a board (FUN_00632048, kind 0): "Arduino_Nano", "Arduino_m328p".
    public static func fourWayName(_ b: ArduinoBoard) -> String {
        if b.tag.lowercased() == "nano_328" { return "Arduino_Nano" }
        return "Arduino_" + b.part.replacingOccurrences(of: "ATMEGA", with: "m", options: .caseInsensitive)
    }

    /// File mask of the 4way-if firmware of a board: "<name>*_<MHz>_*.hex".
    public static func fourWayMask(_ b: ArduinoBoard) -> String { fourWayName(b) + "*_\(b.mhz)_" + "*.hex" }
}
