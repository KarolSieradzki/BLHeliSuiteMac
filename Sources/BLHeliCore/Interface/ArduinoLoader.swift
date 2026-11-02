import Foundation

/// The part of BLHeliSuite's TAVRDude (class at 0x62180C) used by "Make interfaces": connect to a board
/// (read the device signature, FUN_006223E0) and flash a hex file (FUN_00624B88).
/// Boards with the "arduino" programmer (STK500 v1 bootloader) are handled natively with the selected
/// baud rate – exactly one attempt like avrdude; every other programmer runs an installed avrdude.
public final class ArduinoLoader {
    /// avrdude programmer id (-c), part (-p), port (-P) and baud rate (-b).
    public var programmer = ""
    public var part = "m8"
    public var port = ""
    public var baud = 19200
    public var avrdudePath: String?
    /// Part found by the last connect (TAVRDude+0x1C).
    public private(set) var foundPart = ""
    public private(set) var foundSignature: UInt32 = 0
    /// Result text of the last operation (TAVRDude+0x18), shown in the success message.
    public private(set) var resultText = ""
    /// avrdude-like progress lines for the log window.
    public var output: ((String) -> Void)?

    public init() {}

    public var isNative: Bool { programmer.lowercased() == "arduino" }

    // MARK: part table (FUN_005A1EC8 / FUN_005A2064)

    static let parts: [(part: String, name: String, signature: UInt32, pageSize: Int)] = [
        ("m8", "ATmega8", 0x1E9307, 64), ("m88", "ATmega88", 0x1E930A, 64), ("m88p", "ATmega88P", 0x1E930F, 64),
        ("m168", "ATmega168", 0x1E9406, 128), ("m168p", "ATmega168P", 0x1E940B, 128),
        ("m328", "ATmega328", 0x1E9514, 128), ("m328p", "ATmega328P", 0x1E950F, 128),
        ("m1280", "ATmega1280", 0x1E9703, 256), ("m2560", "ATmega2560", 0x1E9801, 256),
        ("atmega32u4", "ATmega32U4", 0x1E9587, 128), ("m32u4", "ATmega32U4", 0x1E9587, 128),
    ]

    /// FUN_005A2064: device signature of an avrdude part id.
    public static func signature(ofPart p: String) -> UInt32? { parts.first { $0.part == p.lowercased() }?.signature }

    /// FUN_005A1EC8: MCU name of an avrdude part id ("m328p" → "ATmega328P").
    public static func mcuName(ofPart p: String) -> String { parts.first { $0.part == p.lowercased() }?.name ?? p.uppercased() }

    public static func part(ofSignature s: UInt32) -> String? { parts.first { $0.signature == s }?.part }

    static func pageSize(ofPart p: String) -> Int { parts.first { $0.part == p.lowercased() }?.pageSize ?? 128 }

    // MARK: operations

    /// Reads the device signature (avrdude without -U).
    public func connect() throws {
        foundPart = ""
        foundSignature = 0
        resultText = ""
        if isNative {
            try withBootloader { stk in
                let sig = try stk.readSignature()
                try self.found(sig)
            }
        } else {
            let r = try avrdude().run(base(), onOutput: output)
            if let range = r.output.range(of: "signature = 0x"), let v = UInt32(r.output[range.upperBound...].prefix(6), radix: 16) {
                try found(v)
            } else if r.status != 0 {
                throw AVRDudeError.failed(r.output.suffix(800).description)
            }
            resultText = lastLine(r.output)
        }
    }

    /// Writes and verifies `hex` (avrdude -D -U flash:w:<hex>:i).
    public func flash(_ hex: URL, progress: ProgressHandler? = nil) throws {
        resultText = ""
        if isNative {
            let image = try MemoryImage.loadIntelHex(url: hex)
            let expected = ArduinoLoader.signature(ofPart: part)
            try withBootloader { stk in
                let sig = try stk.readSignature()
                try self.found(sig)
                if let e = expected, e != sig {
                    throw AVRDudeError.failed(String(format: "avrdude: Expected signature for %@ is %02X %02X %02X\n         Double check chip, or use -F to override this check.",
                                                     ArduinoLoader.mcuName(ofPart: self.part), e >> 16, (e >> 8) & 0xFF, e & 0xFF))
                }
                let pageSize = ArduinoLoader.pageSize(ofPart: self.part)
                let n = (image.highestAddress ?? -1) + 1
                self.output?("avrdude: reading input file \"\(hex.path)\"\navrdude: writing flash (\(n) bytes):\n")
                try stk.program(image, pageSize: pageSize) { d, t in progress?(d, 2 * t) }
                self.output?("avrdude: \(n) bytes of flash written\navrdude: verifying flash memory against \(hex.path):\n")
                try stk.verify(image, pageSize: pageSize) { d, t in progress?(t + d, 2 * t) }
                self.output?("avrdude: \(n) bytes of flash verified\n")
                self.resultText = "\(n) bytes of flash verified"
            }
        } else {
            let r = try avrdude().run(base() + ["-D", "-U", "flash:w:\(hex.path):i"], onOutput: output)
            if r.status != 0 { throw AVRDudeError.failed(r.output.suffix(800).description) }
            if let range = r.output.range(of: #"\d+ bytes of flash verified"#, options: .regularExpression) {
                resultText = String(r.output[range])
            } else {
                resultText = lastLine(r.output)
            }
        }
    }

    // MARK: helpers

    func found(_ sig: UInt32) throws {
        foundSignature = sig
        foundPart = ArduinoLoader.part(ofSignature: sig).map { ArduinoLoader.mcuName(ofPart: $0) } ?? String(format: "0x%06X", sig)
        output?(String(format: "avrdude: Device signature = 0x%06x\n", sig))
    }

    func withBootloader(_ body: (STK500v1) throws -> Void) throws {
        let sp = SerialPort(path: port)
        try sp.open(baudRate: baud)
        defer { sp.close() }
        let stk = STK500v1(port: sp)
        output?("avrdude: Version 5.11, BLHeliSuite native STK500 v1\n         Using Port: \(port)\n         Using Programmer: arduino\n         Overriding Baud Rate: \(baud)\n")
        stk.resetBoard()
        do {
            try stk.sync()
        } catch STK500Error.noSync {
            throw AVRDudeError.failed("avrdude: stk500_getsync(): not in sync: resp=0x00\n\n\(STK500Error.noSync.localizedDescription)")
        }
        output?("avrdude: AVR device initialized and ready to accept instructions\n")
        try stk.enterProgramming()
        try body(stk)
        try? stk.leaveProgramming()
        output?("avrdude done.  Thank you.\n")
    }

    func avrdude() throws -> AVRDude {
        guard let a = AVRDude(path: avrdudePath) else { throw AVRDudeError.notInstalled }
        return a
    }

    func base() -> [String] { ["-c", programmer, "-p", part, "-P", port, "-b", "\(baud)"] }

    func lastLine(_ s: String) -> String {
        s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty } ?? ""
    }
}
