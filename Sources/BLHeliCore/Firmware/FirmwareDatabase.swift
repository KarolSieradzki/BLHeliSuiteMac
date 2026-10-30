import Foundation
import Compression

/// ESC layout record (TBLHeli 0x409-byte layout entry / ESC.cfg line).
public struct ESCLayout: Codable, Equatable, Hashable, Sendable {
    public let name: String
    public let cells: UInt8
    /// "Fully damped enabled since Eep_Layout_Revision X" (255 = never).
    public let damped: UInt8
    public let becHV: UInt8
    public let desc: String
    public let mhz: UInt8
    public let bootloader: Bool
    public let inPin: String
    public let inPin2: String
    public let lfuse: UInt8
    public let hfuse: UInt8
    public let efuse: UInt8
    public let leds: UInt8

    public var displayName: String { desc.isEmpty ? name : desc }
}

/// One built-in firmware file (a record of BLHeliSilabsHexResList / BLHeliAtmelHexResList).
public struct FirmwareEntry: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String { "\(family)-\(res)" }
    public let res: Int
    public let layout: Int
    public let mcu: Int
    public let family: Int
    public let isS: Int
    public let mode: Int
    public let rev: Int
    public let layoutRev: UInt8
    public let defStartupPower: UInt8
    public let defStartupMethod: UInt8
    public let defSpoolup: UInt8
    public let revStr: String
    public let name: String
    public let extra: String
    public let image: [Int]
    public let eeprom: [Int]?

    public var mcuFamily: MCUFamily { MCUFamily(rawValue: family) ?? .unknown }
    public var isBLHeliS: Bool { isS != 0 }
    public var escMode: ESCMode { ESCMode(rawValue: mode) ?? .invalid }
    public var modeName: String { escMode.displayName }
    public var firmwareName: String { isBLHeliS ? "BLHeli_S" : "BLHeli" }
}

public struct FirmwareFamily: Codable, Sendable {
    public let layouts: [ESCLayout]
    public let firmware: [FirmwareEntry]
}

public struct BootloaderEntry: Codable, Sendable {
    public let name: String
    public let image: [Int]
}

public enum FirmwareDatabaseError: Error, LocalizedError {
    case notFound
    case corrupt(String)

    public var errorDescription: String? {
        switch self {
        case .notFound: return "FirmwareDB.bin was not found next to the application."
        case .corrupt(let s): return "Firmware database is corrupt: \(s)"
        }
    }
}

public final class FirmwareDatabase: @unchecked Sendable {
    public let silabs: FirmwareFamily
    public let atmel: FirmwareFamily
    public let bootloaders: [BootloaderEntry]
    public let source: String
    private let stream: [UInt8]

    private struct Meta: Codable {
        let version: Int
        let source: String
        let families: [String: FirmwareFamily]
        let bootloaders: [BootloaderEntry]
    }

    private static var cached: FirmwareDatabase?
    private static let cacheLock = NSLock()

    /// Lazily loaded shared database (throws if FirmwareDB.bin cannot be found or decoded).
    public static func shared() throws -> FirmwareDatabase {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let c = cached { return c }
        guard let url = locate() else { throw FirmwareDatabaseError.notFound }
        let db = try FirmwareDatabase(url: url)
        cached = db
        return db
    }

    public static func locate() -> URL? {
        var candidates: [URL] = []
        if let env = ProcessInfo.processInfo.environment["BLHELI_FIRMWARE_DB"] {
            candidates.append(URL(fileURLWithPath: env))
        }
        if let r = Bundle.main.resourceURL { candidates.append(r.appendingPathComponent("FirmwareDB.bin")) }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        var dir = exe.deletingLastPathComponent()
        for _ in 0..<6 {
            candidates.append(dir.appendingPathComponent("FirmwareDB.bin"))
            candidates.append(dir.appendingPathComponent("Resources/FirmwareDB.bin"))
            dir = dir.deletingLastPathComponent()
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public init(url: URL) throws {
        let data = [UInt8](try Data(contentsOf: url))
        guard data.count > 24, Array(data[0..<8]) == Array("BLHFWDB2".utf8) else {
            throw FirmwareDatabaseError.corrupt("bad magic")
        }
        var p = 8
        func u32() throws -> Int {
            guard p + 4 <= data.count else { throw FirmwareDatabaseError.corrupt("truncated") }
            let v = Int(data[p]) | Int(data[p + 1]) << 8 | Int(data[p + 2]) << 16 | Int(data[p + 3]) << 24
            p += 4
            return v
        }
        let metaRaw = try u32(), metaLen = try u32()
        guard p + metaLen <= data.count else { throw FirmwareDatabaseError.corrupt("truncated meta") }
        let metaBytes = try FirmwareDatabase.inflate(Array(data[p..<(p + metaLen)]), expected: metaRaw)
        p += metaLen
        let blobRaw = try u32(), blobLen = try u32()
        guard p + blobLen <= data.count else { throw FirmwareDatabaseError.corrupt("truncated images") }
        stream = try FirmwareDatabase.inflate(Array(data[p..<(p + blobLen)]), expected: blobRaw)
        let meta = try JSONDecoder().decode(Meta.self, from: Data(metaBytes))
        guard let s = meta.families["silabs"], let a = meta.families["atmel"] else {
            throw FirmwareDatabaseError.corrupt("families")
        }
        silabs = s
        atmel = a
        bootloaders = meta.bootloaders
        source = meta.source
    }

    static func inflate(_ src: [UInt8], expected: Int) throws -> [UInt8] {
        var out = [UInt8](repeating: 0, count: expected + 16)
        let n = src.withUnsafeBufferPointer { s in
            out.withUnsafeMutableBufferPointer { d in
                compression_decode_buffer(d.baseAddress!, d.count, s.baseAddress!, s.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n == expected else { throw FirmwareDatabaseError.corrupt("inflate \(n) != \(expected)") }
        out.removeLast(out.count - n)
        return out
    }

    public func family(_ f: MCUFamily) -> FirmwareFamily? {
        switch f {
        case .silabs: return silabs
        case .atmel: return atmel
        default: return nil
        }
    }

    public func layout(family f: MCUFamily, index: Int) -> ESCLayout? {
        guard let fam = family(f), index >= 0, index < fam.layouts.count else { return nil }
        return fam.layouts[index]
    }

    /// Case-insensitive layout lookup (FUN_0059baa0). Returns the index or nil.
    public func layoutIndex(family f: MCUFamily, name: String) -> Int? {
        guard let fam = family(f) else { return nil }
        let key = name.uppercased()
        guard !key.isEmpty else { return nil }
        let idx = fam.layouts.firstIndex { $0.name.uppercased() == key }
        return (idx ?? 0) > 0 ? idx : nil
    }

    func decodeImage(_ ref: [Int]) -> MemoryImage {
        guard ref.count == 2 else { return MemoryImage() }
        var p = ref[0]
        let end = ref[0] + ref[1]
        func u32() -> Int {
            let v = Int(stream[p]) | Int(stream[p + 1]) << 8 | Int(stream[p + 2]) << 16 | Int(stream[p + 3]) << 24
            p += 4
            return v
        }
        var img = MemoryImage()
        let segs = u32()
        for _ in 0..<segs where p < end {
            let addr = u32(), len = u32()
            img.write(Array(stream[p..<(p + len)]), at: addr)
            p += len
        }
        return img
    }

    public func flashImage(_ e: FirmwareEntry) -> MemoryImage { decodeImage(e.image) }

    public func eepromImage(_ e: FirmwareEntry) -> MemoryImage? { e.eeprom.map { decodeImage($0) } }

    public func bootloaderImage(named name: String) -> MemoryImage? {
        bootloaders.first { $0.name == name }.map { decodeImage($0.image) }
    }

    /// All firmware entries that fit an MCU (database code) – optionally restricted.
    public func entries(family f: MCUFamily, mcuCode: Int? = nil, layout: Int? = nil, mode: ESCMode? = nil,
                        blheliS: Bool? = nil) -> [FirmwareEntry] {
        guard let fam = family(f) else { return [] }
        return fam.firmware.filter { e in
            (mcuCode == nil || e.mcu == mcuCode!) &&
            (layout == nil || e.layout == layout!) &&
            (mode == nil || e.mode == mode!.rawValue) &&
            (blheliS == nil || (e.isS != 0) == blheliS!)
        }
    }

    /// Built-in file that produced `settings` (same layout, mode, type and revision) – gives the
    /// per-file defaults (startup power/method, spoolup time).
    public func matchingEntry(for settings: BLHeliSettings) -> FirmwareEntry? {
        let fam = settings.family
        guard let li = layoutIndex(family: fam, name: settings.layoutName) else { return nil }
        return entries(family: fam, layout: li, mode: settings.mode, blheliS: settings.isBLHeliS)
            .first { $0.revStr == settings.revisionString }
    }

    public func entry(family f: MCUFamily, res: Int) -> FirmwareEntry? {
        family(f)?.firmware.first { $0.res == res }
    }
}
