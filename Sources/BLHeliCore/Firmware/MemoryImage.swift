import Foundation

public enum HexFileError: Error, LocalizedError {
    case badRecord(line: Int, reason: String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .badRecord(let l, let r): return "Invalid Intel HEX record in line \(l): \(r)"
        case .unsupported(let s): return s
        }
    }
}

/// Sparse memory content (flash or EEPROM) as loaded from Intel HEX or read from a device.
public struct MemoryImage: Equatable, Sendable {
    public private(set) var bytes: [Int: UInt8] = [:]

    public init() {}

    public init(segments: [(Int, [UInt8])]) {
        for (addr, data) in segments { write(data, at: addr) }
    }

    public init(contiguous data: [UInt8], at base: Int = 0) {
        write(data, at: base)
    }

    public var isEmpty: Bool { bytes.isEmpty }
    public var count: Int { bytes.count }
    public var lowestAddress: Int? { bytes.keys.min() }
    public var highestAddress: Int? { bytes.keys.max() }

    public subscript(address: Int) -> UInt8? {
        get { bytes[address] }
        set { bytes[address] = newValue }
    }

    public mutating func write(_ data: [UInt8], at address: Int) {
        for (i, b) in data.enumerated() { bytes[address + i] = b }
    }

    public mutating func remove(range: Range<Int>) {
        for a in range { bytes[a] = nil }
    }

    public func contains(range: Range<Int>) -> Bool {
        range.contains { bytes[$0] != nil }
    }

    /// Returns `length` bytes starting at `address`, filling gaps with `fill`.
    public func read(_ address: Int, _ length: Int, fill: UInt8 = 0xFF) -> [UInt8] {
        (0..<max(0, length)).map { bytes[address + $0] ?? fill }
    }

    /// Contiguous segments ordered by address.
    public var segments: [(start: Int, data: [UInt8])] {
        var out: [(Int, [UInt8])] = []
        var cur: [UInt8] = []
        var start = -1
        var prev = -2
        for a in bytes.keys.sorted() {
            if a != prev + 1 {
                if !cur.isEmpty { out.append((start, cur)) }
                cur = []
                start = a
            }
            cur.append(bytes[a]!)
            prev = a
        }
        if !cur.isEmpty { out.append((start, cur)) }
        return out.map { (start: $0.0, data: $0.1) }
    }

    // MARK: Intel HEX

    public static func parseIntelHex(_ text: String) throws -> MemoryImage {
        var image = MemoryImage()
        var base = 0
        var lineNo = 0
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            lineNo += 1
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard line.hasPrefix(":") else { continue }
            let hex = line.dropFirst()
            guard hex.count >= 10, hex.count % 2 == 0 else {
                throw HexFileError.badRecord(line: lineNo, reason: "length")
            }
            var rec: [UInt8] = []
            rec.reserveCapacity(hex.count / 2)
            var idx = hex.startIndex
            while idx < hex.endIndex {
                let next = hex.index(idx, offsetBy: 2)
                guard let b = UInt8(hex[idx..<next], radix: 16) else {
                    throw HexFileError.badRecord(line: lineNo, reason: "not hexadecimal")
                }
                rec.append(b)
                idx = next
            }
            let n = Int(rec[0])
            guard rec.count == n + 5 else { throw HexFileError.badRecord(line: lineNo, reason: "byte count") }
            guard rec.reduce(0, { $0 &+ $1 }) == 0 else { throw HexFileError.badRecord(line: lineNo, reason: "checksum") }
            let addr = Int(rec[1]) << 8 | Int(rec[2])
            let payload = Array(rec[4..<(4 + n)])
            switch rec[3] {
            case 0x00: image.write(payload, at: base + addr)
            case 0x01: return image
            case 0x02: base = (Int(payload[0]) << 8 | Int(payload[1])) << 4
            case 0x04: base = (Int(payload[0]) << 8 | Int(payload[1])) << 16
            case 0x03, 0x05: break
            default: throw HexFileError.badRecord(line: lineNo, reason: "record type \(rec[3])")
            }
        }
        return image
    }

    public static func loadIntelHex(url: URL) throws -> MemoryImage {
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        return try parseIntelHex(text)
    }

    public func intelHex(recordSize: Int = 16) -> String {
        var lines: [String] = []
        var currentUpper = -1
        func record(_ type: UInt8, _ addr: Int, _ payload: [UInt8]) {
            var rec: [UInt8] = [UInt8(payload.count), UInt8((addr >> 8) & 0xFF), UInt8(addr & 0xFF), type] + payload
            let sum = rec.reduce(0, { $0 &+ $1 })
            rec.append(0 &- sum)
            lines.append(":" + rec.map { String(format: "%02X", $0) }.joined())
        }
        for seg in segments {
            var offset = 0
            while offset < seg.data.count {
                let addr = seg.start + offset
                let upper = addr >> 16
                if upper != currentUpper {
                    if upper != 0 || currentUpper != -1 {
                        record(0x04, 0, [UInt8((upper >> 8) & 0xFF), UInt8(upper & 0xFF)])
                    }
                    currentUpper = upper
                }
                let lineEnd = min(seg.data.count, offset + recordSize, offset + (0x10000 - (addr & 0xFFFF)))
                record(0x00, addr & 0xFFFF, Array(seg.data[offset..<lineEnd]))
                offset = lineEnd
            }
        }
        lines.append(":00000001FF")
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}
