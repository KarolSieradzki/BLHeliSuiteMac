import Foundation

public extension Array where Element == UInt8 {
    /// "2F 30 00 00" style dump, used by the protocol log.
    var hexString: String { map { String(format: "%02X", $0) }.joined(separator: " ") }

    /// Bytes interpreted as a Latin-1 string with trailing spaces and NULs removed.
    var latin1Trimmed: String {
        let mapped = self.map { $0 == 0 ? UInt8(0x20) : $0 }
        return (String(bytes: mapped, encoding: .isoLatin1) ?? "").trimmingCharacters(in: .whitespaces)
    }
}

public extension ArraySlice where Element == UInt8 {
    var hexString: String { Array(self).hexString }
}

public func hex2(_ v: UInt8) -> String { String(format: "%02X", v) }
public func hex4(_ v: Int) -> String { String(format: "%04X", v) }

/// Latin-1 string padded with spaces (or truncated) to `length` bytes, as stored in BLHeli EEPROM.
public func paddedLatin1(_ s: String, length: Int, pad: UInt8 = 0x20) -> [UInt8] {
    var out = Array(s.data(using: .isoLatin1, allowLossyConversion: true) ?? Data())
    if out.count > length { out = Array(out.prefix(length)) }
    while out.count < length { out.append(pad) }
    return out
}

public enum Checksum {
    /// XMODEM CRC16 (poly 0x1021, init 0), used by the 4-way interface protocol.
    public static func crc16XModem<S: Sequence>(_ data: S, initial: UInt16 = 0) -> UInt16 where S.Element == UInt8 {
        var crc = initial
        for b in data {
            crc ^= UInt16(b) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : (crc << 1)
            }
        }
        return crc
    }

    /// CRC16 used by the BLHeli 1-wire bootloader (reflected, poly 0xA001, init 0).
    public static func crc16BLHeli<S: Sequence>(_ data: S, initial: UInt16 = 0) -> UInt16 where S.Element == UInt8 {
        var crc = initial
        for byte in data {
            var b = byte
            for _ in 0..<8 {
                if ((crc & 1) ^ UInt16(b & 1)) != 0 {
                    crc = (crc >> 1) ^ 0xA001
                } else {
                    crc >>= 1
                }
                b >>= 1
            }
        }
        return crc
    }

    public static func xor<S: Sequence>(_ data: S) -> UInt8 where S.Element == UInt8 {
        data.reduce(0, ^)
    }
}

/// Monotonic clock in seconds.
@inline(__always) public func monotonicNow() -> TimeInterval {
    TimeInterval(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
}

public func sleepSeconds(_ s: TimeInterval) {
    if s > 0 { usleep(useconds_t(min(s, 4000) * 1_000_000)) }
}
