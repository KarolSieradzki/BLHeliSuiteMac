import Foundation

/// Atmel ISP access through avrdude (interface "X: ATMEL ISP Interface (AVRDude)").
/// Every memory access is a complete avrdude run, so data is cached per connection.
public final class ISPProgrammer: ESCProgrammer {
    public let avrdude: AVRDude
    public let programmerType: AVRDudeProgrammerType
    public let port: String?
    public let baud: Int?
    public var cancelRequested = false
    public private(set) var isConnected = true
    public private(set) var device: DeviceInfo?
    private var part = "m8"
    private var flashCache: [UInt8]?
    private var eepromCache: [UInt8]?
    private let tmp: URL

    public var interfaceName: String { "AVRDude \(programmerType.description)" }
    public var escCount: Int { 1 }

    public init(avrdude: AVRDude, programmer: AVRDudeProgrammerType, port: String?, baud: Int?) {
        self.avrdude = avrdude
        self.programmerType = programmer
        self.port = port
        self.baud = baud
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("blheli-isp-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: tmp) }

    static func partName(_ sig: UInt32) -> String? {
        switch sig {
        case 0x1E9307: return "m8"
        case 0x1E930A: return "m88"
        case 0x1E930F: return "m88p"
        case 0x1E9406: return "m168"
        case 0x1E940B: return "m168p"
        case 0x1E950F: return "m328p"
        case 0x1E9514: return "m328"
        case 0x1E920A: return "m48p"
        default: return nil
        }
    }

    private var base: [String] { AVRDude.baseArgs(programmer: programmerType, part: part, port: port, baud: baud) }

    public func selectESC(_ index: Int) throws -> DeviceInfo {
        // Probe with ATmega8 and let avrdude report the real signature (-F accepts a mismatch).
        part = "m8"
        let r = try avrdude.run(base + ["-F", "-q"])
        guard let range = r.output.range(of: "signature = 0x") else {
            throw AVRDudeError.failed(String(r.output.suffix(800)))
        }
        let hex = r.output[range.upperBound...].prefix(6)
        guard let sig = UInt32(hex, radix: 16), sig != 0, sig != 0xFFFFFF else {
            throw AVRDudeError.failed("No target found (signature \(hex)). Check ISP wiring and ESC power.")
        }
        guard let mcu = MCUTable.byAVRSignature(sig), let p = ISPProgrammer.partName(sig) else {
            throw AVRDudeError.unknownSignature(String(format: "0x%06X", sig))
        }
        part = p
        flashCache = nil
        eepromCache = nil
        let dev = DeviceInfo(interfaceMode: .atmelBLB, mcu: mcu, signature: mcu.bootSignature, bootInfo: 0x7A, raw: [], isISP: true)
        device = dev
        Log.info("ISP target: \(mcu.name)")
        return dev
    }

    private func readMemory(_ mem: String) throws -> [UInt8] {
        let f = tmp.appendingPathComponent("\(mem)-read.hex")
        try? FileManager.default.removeItem(at: f)
        let r = try avrdude.run(base + ["-U", "\(mem):r:\(f.path):i"])
        if r.status != 0 { throw AVRDudeError.failed(String(r.output.suffix(800))) }
        let img = try MemoryImage.loadIntelHex(url: f)
        let size = mem == "flash" ? (device?.flashSize ?? 0x2000) : (device?.eepromSize ?? 0x200)
        return img.read(0, size)
    }

    public func readFlash(address: Int, count: Int, progress: ProgressHandler?) throws -> [UInt8] {
        if flashCache == nil { flashCache = try readMemory("flash") }
        progress?(count, count)
        return Array(flashCache![address..<min(flashCache!.count, address + count)])
    }

    public func readEEPROM(address: Int, count: Int) throws -> [UInt8] {
        if eepromCache == nil { eepromCache = try readMemory("eeprom") }
        return Array(eepromCache![address..<min(eepromCache!.count, address + count)])
    }

    public func writeEEPROM(address: Int, data: [UInt8], progress: ProgressHandler?) throws {
        var e = try readEEPROM(address: 0, count: device?.eepromSize ?? 0x200)
        e.replaceSubrange(address..<(address + data.count), with: data)
        let f = tmp.appendingPathComponent("eeprom-write.hex")
        try MemoryImage(contiguous: e).intelHex().write(to: f, atomically: true, encoding: .ascii)
        let r = try avrdude.run(base + ["-U", "eeprom:w:\(f.path):i"])
        if r.status != 0 { throw AVRDudeError.failed(String(r.output.suffix(800))) }
        eepromCache = e
        progress?(data.count, data.count)
    }

    public func writeFlash(address: Int, data: [UInt8], progress: ProgressHandler?) throws {
        throw ProgrammerError.notSupported("Use the complete ISP flash for the ISP interface.")
    }

    public func erasePage(address: Int) throws {
        throw ProgrammerError.notSupported("Page erase is not available over ISP – use Erase chip.")
    }

    public func eraseChip() throws {
        let r = try avrdude.run(base + ["-e"])
        if r.status != 0 { throw AVRDudeError.failed(String(r.output.suffix(800))) }
        flashCache = nil
        eepromCache = nil
    }

    /// Complete ISP flash: chip erase + flash + EEPROM (+ fuses), verified by avrdude.
    public func flashComplete(flash: MemoryImage, eeprom: [UInt8]?, fuses: (low: UInt8, high: UInt8, ext: UInt8?)?,
                              verify: Bool, onOutput: ((String) -> Void)? = nil) throws {
        let ff = tmp.appendingPathComponent("flash-write.hex")
        try flash.intelHex().write(to: ff, atomically: true, encoding: .ascii)
        var args = base
        if !verify { args.append("-V") }
        args += ["-U", "flash:w:\(ff.path):i"]
        if let e = eeprom {
            let ef = tmp.appendingPathComponent("eeprom-write.hex")
            try MemoryImage(contiguous: e).intelHex().write(to: ef, atomically: true, encoding: .ascii)
            args += ["-U", "eeprom:w:\(ef.path):i"]
        }
        if let f = fuses {
            args += ["-U", String(format: "lfuse:w:0x%02X:m", f.low), "-U", String(format: "hfuse:w:0x%02X:m", f.high)]
            if let x = f.ext, part != "m8" { args += ["-U", String(format: "efuse:w:0x%02X:m", x)] }
        }
        let r = try avrdude.run(args, onOutput: onOutput)
        if r.status != 0 { throw AVRDudeError.failed(String(r.output.suffix(1200))) }
        flashCache = nil
        eepromCache = nil
    }

    public func resetESC(_ index: Int) throws {}
    public func keepAlive() throws {}
    public func disconnect() { isConnected = false }
}
