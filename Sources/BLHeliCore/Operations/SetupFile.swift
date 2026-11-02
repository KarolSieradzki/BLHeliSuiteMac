import Foundation

/// Simple INI setup file ("[Setup]" section with Eep_* = value), similar to BLHeliSuite's *.ini.
public enum SetupFile {
    public static func write(_ s: BLHeliSettings, to url: URL) throws {
        try (lines(s, section: "Setup").joined(separator: "\r\n") + "\r\n").write(to: url, atomically: true, encoding: .isoLatin1)
    }

    /// Multiple ESC file: one section per ESC ("[ESC#1]" …).
    public static func write(multiple list: [(Int, BLHeliSettings)], to url: URL) throws {
        var out: [String] = []
        for (n, s) in list { out += lines(s, section: "ESC#\(n)") + [""] }
        try (out.joined(separator: "\r\n") + "\r\n").write(to: url, atomically: true, encoding: .isoLatin1)
    }

    /// Section names of a setup file.
    public static func sections(url: URL) throws -> [String] {
        let text = try String(contentsOf: url, encoding: .isoLatin1)
        return text.split(whereSeparator: { $0.isNewline }).compactMap {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("[") && t.hasSuffix("]") ? String(t.dropFirst().dropLast()) : nil
        }
    }

    static func lines(_ s: BLHeliSettings, section: String) -> [String] {
        var lines = ["[\(section)]",
                     "Eep_ESC_Layout=\(s.rawLayoutString)",
                     "Eep_ESC_MCU=\(s.mcuString)",
                     "Eep_Name=\(s.name)",
                     "Eep_FW_Main_Revision=\(s.mainRevision)",
                     "Eep_FW_Sub_Revision=\(s.subRevision)",
                     "Eep_Layout_Revision=\(s.layoutRevision)"]
        for p in BLHeliParam.editable { lines.append("\(p.eepName)=\(s.value(p))") }
        return lines
    }

    /// Applies all valid values of the file to `s`; returns the number of values applied.
    @discardableResult
    public static func apply(url: URL, to s: inout BLHeliSettings, database: FirmwareDatabase?, section: String? = nil) throws -> Int {
        let text = try String(contentsOf: url, encoding: .isoLatin1)
        let ctx = s.context(database: database)
        var n = 0
        var current: String?
        for line in text.split(whereSeparator: { $0.isNewline }) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[") && t.hasSuffix("]") { current = String(t.dropFirst().dropLast()); continue }
            if let sec = section, current != sec { continue }
            let kv = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2, let v = Int(kv[1]) else { continue }
            if let p = BLHeliParam.editable.first(where: { $0.eepName == kv[0] }), BLHeliParamLogic.isValid(p, value: v, ctx) {
                s.setValue(p, v)
                n += 1
            }
        }
        return n
    }
}
