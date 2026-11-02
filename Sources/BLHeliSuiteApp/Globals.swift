import AppKit
import VCL
import BLHeliCore

// Global state and constant tables of BLHeliSuite (values taken from BLHeliSuite.exe).

/// Interface kinds in the order of the "Select ATMEL / SILABS Interface" menu (Self+0x799 in the original).
enum IntfType: UInt8 {
    case silC2Toolstick = 0, silC2_4wif, silBLBCom, silBLB4wif, silBLBCF
    case atmBLBCom, atmBLB4wif, atmSK4wif, atmSKAULinker, atmSKTGYLinker, atmBLBCF, atmISP
    case none = 12

    /// Interface captions (const table at 0x68CCAC).
    static let captions = [
        "SILABS C2 (Toolstick)", "SILABS C2 (4way-if)", "SILABS BLHeli Bootloader (USB/Com)",
        "SILABS BLHeli Bootloader (4way-if)", "SILABS BLHeli Bootloader (Cleanflight)",
        "ATMEL BLHeli Bootloader (USB/Com)", "ATMEL BLHeli Bootloader (4way-if)", "ATMEL SK Bootloader (4way-if)",
        "ATMEL SK Bootloader (ArduinoUSBLinker)", "ATMEL SK Bootloader (Afro/Turnigy USB Linker)",
        "ATMEL BLHeli/SK Bootloader (Cleanflight)", "ATMEL ISP Interface (AVRDude)",
    ]

    var caption: String { rawValue < 12 ? IntfType.captions[Int(rawValue)] : "" }

    /// 1 = SiLabs, 2 = Atmel (brand flag at 0x68CCE4).
    var brand: UInt8 { rawValue < 5 ? 1 : (rawValue < 12 ? 2 : 0) }

    var isFourWay: Bool { [.silC2_4wif, .silBLB4wif, .atmBLB4wif, .atmSK4wif].contains(self) }
    var isCF: Bool { self == .silBLBCF || self == .atmBLBCF }
    var isBLBCom: Bool { self == .silBLBCom || self == .atmBLBCom }
    var isLinker: Bool { self == .atmSKAULinker || self == .atmSKTGYLinker }
}

enum Brand {
    /// Current brand: 0 none, 1 SiLabs, 2 Atmel (global at 0x68CCE4).
    static var current: UInt8 = 0
    /// Brand names (table at 0x68CD30).
    static let names = ["NONE", "SiLabs", "Atmel", "BLHeli_32"]
    static func name(_ b: UInt8) -> String { Int(b) < names.count ? names[Int(b)] : "" }
}

/// Device kinds found on an ESC channel (table at 0x68CC34).
let deviceTypeNames = ["", "SiLabs C2 interface", "BLHeli Bootloader", "SimonK Bootloader", "Atmel ISP interface"]

/// ESC mode names (table at 0x68D2D8 via 0x690838).
let escModeNames = ["Main", "Tail", "Multi", "INVALID"]

enum ValueColors {
    /// Value label background colours (TColor, set in TfrmBLHeliSuiteMain.Create).
    static var avr: TColor = 0xFFD8B0
    static var silabs: TColor = 0x80FFFF
    static var silabsS: TColor = 0xFF80FF
}

/// Baud rate lists (initialised at 0x5D6F80 from the integer tables at 0x68EA78…).
enum BaudLists {
    static let normal = [9600, 14400, 19200, 38400, 57600, 115200]
    static let cleanflight = [9600, 14400, 19200, 38400, 57600, 115200, 256000, 460800]
    static let short = [9600, 14400, 19200, 38400, 57600]
    static let expert = [9600, 14400, 19200, 28800, 38400, 56000, 57600, 115200, 128000, 230400, 250000, 256000,
                         460800, 500000, 921600, 1000000]
}

/// Format helper with Delphi semantics for the subset used by BLHeliSuite (%s %d %x %u).
func DFormat(_ fmt: String, _ args: [Any]) -> String {
    var out = ""
    var it = fmt.makeIterator()
    var ai = 0
    while let c = it.next() {
        guard c == "%" else { out.append(c); continue }
        var spec = ""
        while let n = it.next() {
            spec.append(n)
            if n.isLetter || n == "%" { break }
        }
        guard let kind = spec.last else { break }
        if kind == "%" { out.append("%"); continue }
        let a: Any = ai < args.count ? args[ai] : ""
        ai += 1
        let width = Int(spec.dropLast().filter { $0.isNumber }) ?? 0
        switch kind {
        case "s": out += "\(a)"
        case "d", "u":
            let v = (a as? Int) ?? Int("\(a)") ?? 0
            var s = String(v)
            if width > 0 && spec.hasPrefix("0") { s = String(repeating: "0", count: max(0, width - s.count)) + s }
            out += s
        case "x", "X":
            let v = (a as? Int) ?? 0
            var s = String(v, radix: 16, uppercase: true)
            if width > 0 { s = String(repeating: "0", count: max(0, width - s.count)) + s }
            out += s
        default: out += "\(a)"
        }
    }
    return out
}

/// Strings with "\n" escapes as stored in BLHeliSuite.exe (UnescapeNL = StringReplace('\n', CRLF)).
func NL(_ s: String) -> String { s.replacingOccurrences(of: "\\n", with: "\n") }

/// Settings file (BLHeliSuite.ini) – same sections and keys as the Windows version.
final class TIniFile {
    let url: URL
    private var sections: [(String, [(String, String)])] = []

    init(url: URL) {
        self.url = url
        load()
    }

    static let shared: TIniFile = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BLHeliSuite", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return TIniFile(url: dir.appendingPathComponent("BLHeliSuite.ini"))
    }()

    func load() {
        sections = []
        guard let text = try? String(contentsOf: url, encoding: .isoLatin1) else { return }
        var cur = -1
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                sections.append((String(line.dropFirst().dropLast()), []))
                cur = sections.count - 1
            } else if cur >= 0, let eq = line.firstIndex(of: "=") {
                sections[cur].1.append((String(line[..<eq]), String(line[line.index(after: eq)...])))
            }
        }
    }

    func save() {
        var s = ""
        for (name, values) in sections {
            s += "[\(name)]\r\n"
            for (k, v) in values { s += "\(k)=\(v)\r\n" }
            s += "\r\n"
        }
        try? s.write(to: url, atomically: true, encoding: .isoLatin1)
    }

    func readString(_ section: String, _ key: String, _ def: String) -> String {
        guard let sec = sections.first(where: { $0.0.caseInsensitiveCompare(section) == .orderedSame }),
              let kv = sec.1.first(where: { $0.0.caseInsensitiveCompare(key) == .orderedSame }) else { return def }
        return kv.1
    }

    func readInteger(_ section: String, _ key: String, _ def: Int) -> Int {
        let s = readString(section, key, "")
        if s.hasPrefix("$") { return Int(s.dropFirst(), radix: 16) ?? def }
        return Int(s) ?? def
    }

    func readBool(_ section: String, _ key: String, _ def: Bool) -> Bool {
        let s = readString(section, key, "").uppercased()
        if ["TRUE", "YES", "Y", "1"].contains(s) { return true }
        if ["FALSE", "NO", "N", "0"].contains(s) { return false }
        return def
    }

    func writeString(_ section: String, _ key: String, _ value: String) {
        if let si = sections.firstIndex(where: { $0.0.caseInsensitiveCompare(section) == .orderedSame }) {
            if let ki = sections[si].1.firstIndex(where: { $0.0.caseInsensitiveCompare(key) == .orderedSame }) {
                sections[si].1[ki].1 = value
            } else {
                sections[si].1.append((key, value))
            }
        } else {
            sections.append((section, [(key, value)]))
        }
        save()
    }

    func writeInteger(_ section: String, _ key: String, _ value: Int) { writeString(section, key, String(value)) }
    func writeBool(_ section: String, _ key: String, _ value: Bool) { writeString(section, key, value ? "TRUE" : "FALSE") }

    func sectionNames() -> [String] { sections.map(\.0) }
    func values(_ section: String) -> [(String, String)] {
        sections.first { $0.0.caseInsensitiveCompare(section) == .orderedSame }?.1 ?? []
    }
    func eraseSection(_ section: String) {
        sections.removeAll { $0.0.caseInsensitiveCompare(section) == .orderedSame }
        save()
    }
}

/// Folder with the files of the original distribution (Manuals, Interfaces, BLHeli_HexFiles …).
enum AppFolders {
    static var resources: URL? { Bundle.main.resourceURL }

    static func find(_ sub: String) -> URL? {
        var c: [URL] = []
        if let r = Bundle.main.resourceURL { c.append(r.appendingPathComponent(sub)) }
        if let env = ProcessInfo.processInfo.environment["BLHELISUITE_WINDOWS"] { c.append(URL(fileURLWithPath: env).appendingPathComponent(sub)) }
        var d = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<7 {
            c.append(d.appendingPathComponent("BLHeliSuite").appendingPathComponent(sub))
            c.append(d.appendingPathComponent("Resources").appendingPathComponent(sub))
            d = d.deletingLastPathComponent()
        }
        return c.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static var manuals: URL? { find("Manuals") }

    /// FUN_00582B3C(0) / FUN_00582BB0(0, …): last folder of the hex file dialogs.
    static var hexFolder: URL? {
        get {
            if let p = UserDefaults.standard.string(forKey: "HexFileFolder"), FileManager.default.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
            return find("BLHeli_HexFiles")
        }
        set { UserDefaults.standard.set(newValue?.path, forKey: "HexFileFolder") }
    }

    /// Writable folder for screenshots, logs and settings files (Windows: next to the exe).
    static var userFolder: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("BLHeliSuite", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
}
