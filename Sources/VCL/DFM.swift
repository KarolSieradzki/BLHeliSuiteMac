import Foundation

// Reader for Delphi binary form resources ("TPF0" streams, Classes.TReader format).
// The forms of the original BLHeliSuite.exe are loaded unchanged from Resources/Forms.

public indirect enum DFMValue: CustomStringConvertible {
    case null
    case int(Int)
    case double(Double)
    case string(String)
    case ident(String)
    case bool(Bool)
    case binary([UInt8])
    case set([String])
    case list([DFMValue])
    case collection([DFMCollectionItem])

    public var intValue: Int? {
        switch self {
        case .int(let v): return v
        case .double(let d): return Int(d)
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .int(let v): return Double(v)
        case .double(let d): return d
        default: return nil
        }
    }

    public var stringValue: String? {
        switch self {
        case .string(let s), .ident(let s): return s
        default: return nil
        }
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .ident(let s): return s == "True" ? true : (s == "False" ? false : nil)
        default: return nil
        }
    }

    public var description: String {
        switch self {
        case .null: return "nil"
        case .int(let v): return "\(v)"
        case .double(let d): return "\(d)"
        case .string(let s): return "'\(s)'"
        case .ident(let s): return s
        case .bool(let b): return b ? "True" : "False"
        case .binary(let b): return "{\(b.count) bytes}"
        case .set(let s): return "[\(s.joined(separator: ", "))]"
        case .list(let l): return "(\(l.map(\.description).joined(separator: " ")))"
        case .collection(let c): return "<\(c.count) items>"
        }
    }
}

public struct DFMCollectionItem {
    public var index: Int?
    public var props: [(String, DFMValue)]

    public subscript(_ name: String) -> DFMValue? { props.first { $0.0 == name }?.1 }
}

public final class DFMObject {
    public enum Kind { case object, inherited, inline }

    public let kind: Kind
    public let className: String
    public let name: String
    public var props: [(String, DFMValue)]
    public var children: [DFMObject]
    public let childPos: Int?

    init(kind: Kind, className: String, name: String, props: [(String, DFMValue)], children: [DFMObject], childPos: Int?) {
        self.kind = kind
        self.className = className
        self.name = name
        self.props = props
        self.children = children
        self.childPos = childPos
    }

    public subscript(_ name: String) -> DFMValue? { props.first { $0.0 == name }?.1 }

    public func find(_ name: String) -> DFMObject? {
        if self.name == name { return self }
        for c in children { if let f = c.find(name) { return f } }
        return nil
    }
}

public enum DFMError: Error {
    case badSignature
    case truncated
    case badValue(UInt8, Int)
}

public enum DFMReader {
    public static func parse(_ data: [UInt8]) throws -> DFMObject {
        var r = Cursor(b: data)
        guard data.count > 4, Array(data[0..<4]) == Array("TPF0".utf8) else { throw DFMError.badSignature }
        r.p = 4
        return try r.object()
    }

    public static func parse(contentsOf url: URL) throws -> DFMObject {
        try parse([UInt8](try Data(contentsOf: url)))
    }

    struct Cursor {
        let b: [UInt8]
        var p = 0

        mutating func u8() throws -> UInt8 {
            guard p < b.count else { throw DFMError.truncated }
            defer { p += 1 }
            return b[p]
        }

        func peek() throws -> UInt8 {
            guard p < b.count else { throw DFMError.truncated }
            return b[p]
        }

        mutating func raw(_ n: Int) throws -> [UInt8] {
            guard n >= 0, p + n <= b.count else { throw DFMError.truncated }
            defer { p += n }
            return Array(b[p..<(p + n)])
        }

        mutating func le<T: FixedWidthInteger>(_: T.Type) throws -> T {
            let bytes = try raw(MemoryLayout<T>.size)
            var v: T = 0
            for (i, x) in bytes.enumerated() { v |= T(truncatingIfNeeded: x) << (8 * i) }
            return v
        }

        mutating func shortString() throws -> String {
            let n = Int(try u8())
            return Ansi.decode(try raw(n))
        }

        mutating func value() throws -> DFMValue {
            let t = try u8()
            switch t {
            case 0: return .null
            case 1:
                var items: [DFMValue] = []
                while try peek() != 0 { items.append(try value()) }
                p += 1
                return .list(items)
            case 2: return .int(Int(Int8(bitPattern: try u8())))
            case 3: return .int(Int(try le(Int16.self)))
            case 4: return .int(Int(try le(Int32.self)))
            case 5:
                let bytes = try raw(10)
                var mant: UInt64 = 0
                for i in 0..<8 { mant |= UInt64(bytes[i]) << (8 * UInt64(i)) }
                let se = UInt16(bytes[8]) | UInt16(bytes[9]) << 8
                let sign: Double = se & 0x8000 != 0 ? -1 : 1
                let exp = Int(se & 0x7FFF)
                if exp == 0 && mant == 0 { return .double(0) }
                return .double(sign * Double(mant) / pow(2.0, 63) * pow(2.0, Double(exp - 16383)))
            case 6: return .string(try shortString())
            case 7: return .ident(try shortString())
            case 8: return .bool(false)
            case 9: return .bool(true)
            case 10:
                let n = Int(try le(UInt32.self))
                return .binary(try raw(n))
            case 11:
                var items: [String] = []
                while true {
                    let s = try shortString()
                    if s.isEmpty { break }
                    items.append(s)
                }
                return .set(items)
            case 12:
                let n = Int(try le(UInt32.self))
                return .string(Ansi.decode(try raw(n)))
            case 13: return .null
            case 14:
                var items: [DFMCollectionItem] = []
                while try peek() != 0 {
                    var idx: Int?
                    if [2, 3, 4].contains(try peek()) { idx = try value().intValue }
                    guard try u8() == 1 else { throw DFMError.badValue(t, p) }
                    var props: [(String, DFMValue)] = []
                    while try peek() != 0 { props.append(try property()) }
                    p += 1
                    items.append(DFMCollectionItem(index: idx, props: props))
                }
                p += 1
                return .collection(items)
            case 15:
                let bits = try le(UInt32.self)
                return .double(Double(Float(bitPattern: bits)))
            case 16: return .double(Double(try le(Int64.self)) / 10000)
            case 17, 21:
                let bits = try le(UInt64.self)
                return .double(Double(bitPattern: bits))
            case 18:
                let n = Int(try le(UInt32.self))
                let bytes = try raw(2 * n)
                var units: [UInt16] = []
                for i in 0..<n { units.append(UInt16(bytes[2 * i]) | UInt16(bytes[2 * i + 1]) << 8) }
                return .string(String(decoding: units, as: UTF16.self))
            case 19: return .int(Int(try le(Int64.self)))
            case 20:
                let n = Int(try le(UInt32.self))
                return .string(String(decoding: try raw(n), as: UTF8.self))
            default:
                throw DFMError.badValue(t, p - 1)
            }
        }

        mutating func property() throws -> (String, DFMValue) {
            let name = try shortString()
            return (name, try value())
        }

        mutating func object() throws -> DFMObject {
            var kind = DFMObject.Kind.object
            var pos: Int?
            if try peek() & 0xF0 == 0xF0 {
                let flags = try u8() & 0x0F
                if flags & 1 != 0 { kind = .inherited }
                if flags & 4 != 0 { kind = .inline }
                if flags & 2 != 0 { pos = try value().intValue }
            }
            let cls = try shortString()
            let name = try shortString()
            var props: [(String, DFMValue)] = []
            while try peek() != 0 { props.append(try property()) }
            p += 1
            var children: [DFMObject] = []
            while try peek() != 0 { children.append(try object()) }
            p += 1
            return DFMObject(kind: kind, className: cls, name: name, props: props, children: children, childPos: pos)
        }
    }
}

/// Windows-1252 ("ANSI") text, as used by Delphi 2007 strings and forms.
public enum Ansi {
    private static let high: [UInt16] = [
        0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F,
        0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178,
    ]

    public static func decode(_ bytes: [UInt8]) -> String {
        var s = String.UnicodeScalarView()
        for b in bytes {
            let v: UInt32 = (b >= 0x80 && b < 0xA0) ? UInt32(high[Int(b) - 0x80]) : UInt32(b)
            if let u = Unicode.Scalar(v) { s.append(u) }
        }
        return String(s)
    }

    public static func encode(_ s: String) -> [UInt8] {
        var out: [UInt8] = []
        for u in s.unicodeScalars {
            if u.value < 0x80 || (u.value >= 0xA0 && u.value < 0x100) { out.append(UInt8(u.value)) }
            else if let i = high.firstIndex(of: UInt16(truncatingIfNeeded: u.value)), u.value < 0x10000 { out.append(UInt8(0x80 + i)) }
            else { out.append(UInt8(ascii: "?")) }
        }
        return out
    }
}
