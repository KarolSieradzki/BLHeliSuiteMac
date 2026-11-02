import Foundation

/// Settings protocol of the ArduinoUSBLinker sketch (BLHeliSuite TArduinoUSBLinker, VMT 0x61FA3C):
/// "$M<Pn" signal pin, "$M<Bn" bit time, "$M<Rn" serial baud rate, "$M<W" store in EEPROM.
/// Every command answers with the status line "P18:B136:R19200:PINS:B0:C8:D16:".
public final class ArduinoUSBLinker {
    public var portPath = ""
    /// Serial baud rate of the sketch (the port is opened with it).
    public var baud = 19200
    public private(set) var isOpen = false
    /// Settings read from the sketch.
    public private(set) var pin = -1          // absolute pin number (+0x50)
    public private(set) var bitTime = -1      // +0x54
    public private(set) var linkerBaud = -1   // +0x58
    /// Port letters and their first pin numbers ("PINS:B0:C8:D16:").
    public private(set) var ports: [(letter: Character, first: Int)] = []
    public private(set) var statusLine = ""
    public var log: ((String) -> Void)?
    private var port: SerialPort?

    /// Baud rates tried by Connect when the sketch does not answer (FUN_0061FB1C).
    public static let searchBauds = [9600, 19200, 14400, 38400, 57600, 115200, 56000, 128000, 256000, 921600]

    public init() {}

    public var portLetter: Character? { pinPort(pin)?.letter }
    public var pinInPort: Int { pinPort(pin).map { pin - $0.first } ?? -1 }

    func pinPort(_ p: Int) -> (letter: Character, first: Int)? {
        guard p >= 0 else { return nil }
        return ports.last { $0.first <= p }
    }

    /// Number of the pin `n` of port `letter` (e.g. D3 → 19).
    public func pinNumber(port letter: Character, _ n: Int) -> Int? {
        ports.first { $0.letter == letter }.map { $0.first + n }
    }

    func open(_ b: Int) throws {
        close()
        let sp = SerialPort(path: portPath)
        try sp.open(baudRate: b)
        port = sp
        isOpen = true
    }

    public func close() {
        port?.close()
        port = nil
        isOpen = false
    }

    /// Sends `cmd` and reads the status line (FUN_0062018C: 200 ms for the first byte, 500 ms after each byte).
    @discardableResult
    public func command(_ cmd: String) throws -> Bool {
        guard let p = port else { throw SerialError.notOpen }
        p.discardInput()
        log?("Write: " + cmd)
        try p.write(Array(cmd.utf8))
        var line: [UInt8] = []
        var deadline = monotonicNow() + 0.2
        while monotonicNow() < deadline {
            let b = try p.read(maxCount: 1, timeout: 0.02)
            guard let c = b.first else { continue }
            if c == 0x0A { break }
            if c != 0x0D { line.append(c) }
            deadline = monotonicNow() + 0.5
        }
        statusLine = String(decoding: line, as: UTF8.self)
        log?("Read: " + statusLine)
        return parse(statusLine)
    }

    /// FUN_0062077C / FUN_00620310: "[saved:]P<pin>:B<bittime>:R<baud>:PINS:B0:C8:D16:".
    func parse(_ s: String) -> Bool {
        var t = s
        if t.hasPrefix("saved:") { t.removeFirst(6) }
        let parts = t.split(separator: ":").map(String.init)
        guard let pi = parts.firstIndex(where: { $0 == "PINS" }) else { return false }
        var p = -1, b = -1, r = -1
        for x in parts[..<pi] {
            guard let c = x.first, let v = Int(x.dropFirst()) else { continue }
            switch c {
            case "P": p = v
            case "B": b = v
            case "R": r = v
            default: break
            }
        }
        var list: [(Character, Int)] = []
        for x in parts[(pi + 1)...] {
            if let c = x.first, let v = Int(x.dropFirst()) { list.append((c, v)) }
        }
        guard p >= 0, !list.isEmpty else { return false }
        pin = p; bitTime = b; linkerBaud = r
        ports = list
        return true
    }

    /// Connect (FUN_0061FB1C): the configured baud first (2 s wait for the Arduino reset on failure),
    /// then the list of other baud rates.
    public func connect() -> Bool {
        let first = baud
        for (i, b) in ([first] + ArduinoUSBLinker.searchBauds.filter { $0 != first }).enumerated() {
            log?(String(format: "AUL Connect @%@|%d", (portPath as NSString).lastPathComponent, b))
            if (try? open(b)) == nil { continue }
            if (try? command("$M<")) == true { baud = b; return true }
            if i == 0 {
                log?("AUL Failed first try: Waiting ms 2000")
                Thread.sleep(forTimeInterval: 2.0)
                if (try? command("$M<")) == true { baud = b; return true }
            }
            close()
        }
        baud = first
        return false
    }

    /// FUN_00620D1C: writes the changed settings and optionally saves them in the EEPROM.
    public func writeSettings(pin newPin: Int, bitTime newBitTime: Int, baud newBaud: Int, save: Bool) throws {
        if newPin != pin { log?("Write Pin"); try command("$M<P\(newPin)") } else { log?("Skip Write Pin") }
        if newBitTime != bitTime { log?("Write BitTime"); try command("$M<B\(newBitTime)") } else { log?("Skip Write BitTime") }
        if newBaud != linkerBaud {
            log?("Write Baud")
            try command("$M<R\(newBaud)")
            // the sketch switches its serial port after the answer
            Thread.sleep(forTimeInterval: 0.1)
            try open(newBaud)
            baud = newBaud
            _ = try command("$M<")
        } else {
            log?("Skip Write Baud")
        }
        if save {
            log?("Save to EEProm")
            try command("$M<W")
        }
    }
}
