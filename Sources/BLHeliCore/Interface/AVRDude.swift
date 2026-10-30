import Foundation

public enum AVRDudeError: Error, LocalizedError {
    case notInstalled
    case failed(String)
    case unknownSignature(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "AVRDude was not found.\nInstall it with Homebrew:  brew install avrdude\n(or set its path in the ISP options)."
        case .failed(let s): return "Avrdude FAILED!\n\n\(s)"
        case .unknownSignature(let s): return "Avrdude successfully. But unknown MCU: \"\(s)\""
        }
    }
}

/// One entry of AVRDudeProg.ini (programmer choices offered for the ISP interface).
public struct AVRDudeProgrammerType: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let type: String
    public let serial: Bool
    public let baud: Int

    public static let common: [AVRDudeProgrammerType] = [
        AVRDudeProgrammerType(name: "usbasp", description: "USBasp (USB)", type: "usbasp", serial: false, baud: 0),
        AVRDudeProgrammerType(name: "usbasp-clone", description: "USBasp clone (USB)", type: "usbasp-clone", serial: false, baud: 0),
        AVRDudeProgrammerType(name: "ArduinoISP", description: "Arduino as ISP (serial)", type: "stk500v1", serial: true, baud: 19200),
        AVRDudeProgrammerType(name: "avrisp2", description: "Atmel AVR ISP mkII (USB)", type: "avrisp2", serial: false, baud: 0),
        AVRDudeProgrammerType(name: "usbtiny", description: "USBtiny (USB)", type: "usbtiny", serial: false, baud: 0),
        AVRDudeProgrammerType(name: "stk500v2", description: "STK500v2 / mySmartUSB (serial)", type: "stk500v2", serial: true, baud: 115200),
        AVRDudeProgrammerType(name: "avrisp", description: "Atmel AVR ISP (serial)", type: "stk500v1", serial: true, baud: 19200),
    ]
}

/// Thin wrapper around an installed avrdude binary (the Windows version ships avrdude.exe).
public final class AVRDude {
    public let executable: URL

    public init?(path: String? = nil) {
        let fm = FileManager.default
        var candidates: [String] = []
        if let p = path, !p.isEmpty { candidates.append(p) }
        if let r = Bundle.main.resourceURL { candidates.append(r.appendingPathComponent("avrdude/avrdude").path) }
        candidates += ["/opt/homebrew/bin/avrdude", "/usr/local/bin/avrdude", "/opt/local/bin/avrdude"]
        if let env = ProcessInfo.processInfo.environment["PATH"] {
            candidates += env.split(separator: ":").map { "\($0)/avrdude" }
        }
        guard let found = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) else { return nil }
        executable = URL(fileURLWithPath: found)
    }

    public struct Result {
        public let status: Int32
        public let output: String
    }

    @discardableResult
    public func run(_ arguments: [String], onOutput: ((String) -> Void)? = nil) throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        Log.info("Running AVRDude [\(arguments.joined(separator: " "))]")
        var collected = Data()
        let lock = NSLock()
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            lock.lock(); collected.append(d); lock.unlock()
            if let s = String(data: d, encoding: .utf8) { onOutput?(s) }
        }
        try process.run()
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        let rest = pipe.fileHandleForReading.readDataToEndOfFile()
        lock.lock(); collected.append(rest); lock.unlock()
        let out = String(data: collected, encoding: .utf8) ?? ""
        for line in out.split(whereSeparator: \.isNewline) where line.contains("rror") || line.contains("signature") {
            Log.debug("avrdude: \(line)")
        }
        return Result(status: process.terminationStatus, output: out)
    }

    /// Common connection arguments.
    public static func baseArgs(programmer: AVRDudeProgrammerType, part: String, port: String?, baud: Int?) -> [String] {
        var a = ["-c", programmer.type, "-p", part]
        if programmer.serial, let p = port { a += ["-P", p] }
        if let b = baud ?? (programmer.baud > 0 ? programmer.baud : nil), programmer.serial { a += ["-b", "\(b)"] }
        return a
    }

    /// Flashes an Arduino board through its serial bootloader (wiring / avr109 boards).
    public func flashArduino(board: ArduinoBoard, port: String, hex: URL) throws {
        let r = try run(["-c", board.programmer, "-p", board.part, "-P", port, "-b", "\(board.baud)", "-D", "-U", "flash:w:\(hex.path):i"])
        if r.status != 0 { throw AVRDudeError.failed(r.output.suffix(800).description) }
    }

    /// Reads the device signature ("Device signature = 0x1e9307").
    public func readSignature(_ base: [String]) throws -> UInt32 {
        let r = try run(base + ["-q"])
        if let range = r.output.range(of: "signature = 0x") {
            let hex = r.output[range.upperBound...].prefix(6)
            if let v = UInt32(hex, radix: 16) { return v }
        }
        if r.status != 0 { throw AVRDudeError.failed(r.output.suffix(800).description) }
        throw AVRDudeError.unknownSignature(r.output.suffix(200).description)
    }
}
