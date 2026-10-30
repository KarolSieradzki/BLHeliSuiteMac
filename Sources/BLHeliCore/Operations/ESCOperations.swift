import Foundation

public enum FlashError: Error, LocalizedError {
    case imageTooLarge(Int, Int)
    case emptyImage
    case mcuMismatch(String)
    case verifyFailed(String, Int)
    case pageZeroNotEmpty
    case bootloaderCannotRead

    public var errorDescription: String? {
        switch self {
        case .imageTooLarge(let a, let b): return "File size exceeds available flash space: \(a) vs. \(b)"
        case .emptyImage: return "The firmware file does not contain any flash data."
        case .mcuMismatch(let s): return s
        case .verifyFailed(let what, let a): return String(format: "%@ verify failed at address 0x%04X.", what, a)
        case .pageZeroNotEmpty: return "Flash page0 empty verify failed."
        case .bootloaderCannotRead: return "This version of BLHeli Atmel bootloader cannot read flash from target ESC."
        }
    }
}

/// Everything needed to (re)flash one ESC.
public struct FlashPlan {
    public var flash: MemoryImage
    /// Atmel EEPROM file content (.eep), nil for SiLabs.
    public var eeprom: MemoryImage?
    /// Final settings block (translated user settings) or nil to use the defaults of the file.
    public var settings: BLHeliSettings?
    public var title: String
    /// C2 only: keep a bootloader found on the chip when the file has none.
    public var keepExistingBootloader = true
    /// ISP only: bootloader merged into the flash image and fuses written with the flash.
    public var ispBootloader: MemoryImage?
    public var ispFuses: AVRFuses?

    public init(flash: MemoryImage, eeprom: MemoryImage? = nil, settings: BLHeliSettings? = nil, title: String) {
        self.flash = flash
        self.eeprom = eeprom
        self.settings = settings
        self.title = title
    }

    /// Default settings stored in the firmware file (SiLabs flash 0x1A00 / Atmel EEPROM 0).
    public var defaultSettings: BLHeliSettings? {
        if let e = eeprom, e.contains(range: 0..<BLHeliSettings.size) {
            return BLHeliSettings(raw: e.read(0, BLHeliSettings.size))
        }
        if flash.contains(range: BLHeliSettings.silabsAddress..<(BLHeliSettings.silabsAddress + BLHeliSettings.size)) {
            return BLHeliSettings(raw: flash.read(BLHeliSettings.silabsAddress, BLHeliSettings.size))
        }
        return nil
    }
}

public struct AVRFuses: Equatable, Sendable {
    public var low: UInt8
    public var high: UInt8
    public var ext: UInt8?

    public init(low: UInt8, high: UInt8, ext: UInt8?) {
        self.low = low
        self.high = high
        self.ext = ext
    }
}

public struct OperationProgress {
    public var message: String
    public var fraction: Double
}

/// Read/write setup and the flash procedures of TUniSerialInterface (FUN_005de5b8 for SiLabs
/// bootloader, FUN_005db934 for C2, FUN_005db468 for Atmel bootloaders).
public final class ESCOperations {
    public let programmer: ESCProgrammer
    public var verify = true
    public var onProgress: ((OperationProgress) -> Void)?

    public init(programmer: ESCProgrammer) {
        self.programmer = programmer
    }

    private func report(_ m: String, _ f: Double) {
        onProgress?(OperationProgress(message: m, fraction: max(0, min(1, f))))
    }

    // MARK: Setup

    public func readSettings(device: DeviceInfo) throws -> BLHeliSettings {
        let raw: [UInt8]
        switch device.family {
        case .silabs:
            raw = try programmer.readFlash(address: BLHeliSettings.silabsAddress, count: BLHeliSettings.size, progress: nil)
        case .atmel:
            raw = try programmer.readEEPROM(address: 0, count: BLHeliSettings.size)
        default:
            throw ProgrammerError.notSupported("\(device.description) is not a BLHeli SiLabs/Atmel ESC (BLHeli_32/AM32 need a different tool).")
        }
        var s = BLHeliSettings(raw: raw)
        s.normalizeOldHeader()
        return s
    }

    public func writeSettings(_ s: BLHeliSettings, device: DeviceInfo) throws {
        switch device.family {
        case .silabs:
            try programmer.erasePage(address: BLHeliSettings.silabsAddress)
            try programmer.writeFlash(address: BLHeliSettings.silabsAddress, data: s.raw, progress: nil)
        case .atmel:
            try programmer.writeEEPROM(address: 0, data: s.raw, progress: nil)
        default:
            throw ProgrammerError.notSupported("Unsupported device family.")
        }
        if verify && device.canReadFlash {
            let back = try readSettings(device: device)
            if back.raw != s.raw {
                let idx = zip(back.raw, s.raw).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? 0
                throw FlashError.verifyFailed("Setup", idx)
            }
        }
    }

    // MARK: Flash

    public func flash(_ plan: FlashPlan, device: DeviceInfo, currentSettings: BLHeliSettings?) throws {
        guard !plan.flash.isEmpty else { throw FlashError.emptyImage }
        if device.isISP, let isp = programmer as? ISPProgrammer {
            try flashISP(plan, device: device, isp: isp)
            return
        }
        switch device.interfaceMode {
        case .siLabsBLB: try flashSiLabsBootloader(plan, device: device, currentSettings: currentSettings)
        case .siLabsC2: try flashSiLabsC2(plan, device: device)
        case .atmelBLB, .atmelSK: try flashAtmel(plan, device: device, currentSettings: currentSettings)
        case .armBLB: throw ProgrammerError.notSupported("ARM ESCs (BLHeli_32) are not supported.")
        }
    }

    /// Flash image limited to `size` bytes with the merged settings block.
    func buildSiLabsImage(_ plan: FlashPlan, size: Int) throws -> [UInt8] {
        var image = plan.flash
        if let s = plan.settings { image.write(s.raw, at: BLHeliSettings.silabsAddress) }
        if let hi = image.highestAddress, hi >= size {
            // Bootloader data (0x1C00…) is part of BLHeli_S hex files and cannot be written
            // over the bootloader – anything else beyond the user flash is an error.
            let beyond = image.bytes.keys.filter { $0 >= size && $0 < 0x1C00 }
            if !beyond.isEmpty { throw FlashError.imageTooLarge(hi + 1, size) }
        }
        return image.read(0, size)
    }

    /// The exact 0x1C00 bytes the bootloader flash procedure writes for `plan`.
    public func siLabsBootloaderImage(for plan: FlashPlan) throws -> [UInt8] {
        try buildSiLabsImage(plan, size: 0x1C00)
    }

    private func flashSiLabsBootloader(_ plan: FlashPlan, device: DeviceInfo, currentSettings: BLHeliSettings?) throws {
        let ps = device.pageSize
        let image = try buildSiLabsImage(plan, size: 0x1C00)
        let eepAddr = BLHeliSettings.silabsAddress
        let ljmpBootloader: [UInt8] = [0x02, 0x1C, 0x00]
        let totalSteps = Double(0x1C00 * (verify ? 2 : 1) + 13 * 64)
        var done = 0.0
        func step(_ msg: String, _ n: Int) { done += Double(n); report(msg, done / totalSteps) }

        // 1. Mark the setup as "flash failed" so an interrupted flash is recognisable.
        if let cur = currentSettings, (try? cur.validate()) != nil,
           !((1470...1479).contains(cur.revision) || (1630...1639).contains(cur.revision)) {
            var marked = cur
            marked.name = "**FLASH*FAILED**"
            try programmer.erasePage(address: eepAddr)
            try programmer.writeFlash(address: eepAddr, data: marked.raw, progress: nil)
        }
        try programmer.checkCancel()
        // 2. If page 0 was left empty by an earlier attempt, put a jump to the bootloader in.
        let first = try programmer.readFlash(address: 0, count: 3, progress: nil)
        if first == [0xFF, 0xFF, 0xFF] {
            try programmer.writeFlash(address: 0, data: ljmpBootloader, progress: nil)
        }
        // 3. Page 1 gets the LJMP so the ESC always reaches the bootloader while page 0 is blank.
        step("Erasing flash…", 64)
        try programmer.erasePage(address: ps)
        try programmer.writeFlash(address: ps, data: ljmpBootloader, progress: nil)
        try programmer.erasePage(address: 0)
        let p0 = try programmer.readFlash(address: 0, count: ps, progress: nil)
        if p0.contains(where: { $0 != 0xFF }) { Log.warning("Flash page0 empty verify failed.") }
        // 4. Erase the application pages 2 … 12.
        let appEnd = eepAddr
        var page = 2
        while page * ps < appEnd {
            try programmer.checkCancel()
            try programmer.erasePage(address: page * ps)
            step("Erasing flash…", 64)
            page += 1
        }
        // 5. Write pages 2…, then page 0, then page 1, then the setup page.
        let body = Array(image[(2 * ps)..<appEnd])
        try programmer.writeFlash(address: 2 * ps, data: body) { d, _ in self.report("Writing flash…", (done + Double(d)) / totalSteps) }
        done += Double(body.count)
        try programmer.writeFlash(address: 0, data: Array(image[0..<ps]), progress: nil)
        step("Writing flash…", ps)
        try programmer.erasePage(address: ps)
        try programmer.writeFlash(address: ps, data: Array(image[ps..<(2 * ps)]), progress: nil)
        step("Writing flash…", ps)
        try programmer.erasePage(address: eepAddr)
        try programmer.writeFlash(address: eepAddr, data: Array(image[eepAddr..<(eepAddr + ps)]), progress: nil)
        step("Writing flash…", ps)
        // 6. Verify.
        if verify {
            let back = try programmer.readFlash(address: 0, count: image.count) { d, _ in
                self.report("Verifying flash…", (done + Double(d)) / totalSteps)
            }
            if let i = zip(back, image).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset {
                throw FlashError.verifyFailed("Flash", i)
            }
        }
        report("Flash finished", 1)
    }

    private func flashSiLabsC2(_ plan: FlashPlan, device: DeviceInfo) throws {
        var full = plan.flash
        if let s = plan.settings { full.write(s.raw, at: BLHeliSettings.silabsAddress) }
        let flashSize = device.flashSize
        // Keep the lock byte page untouched for C8051F33x/F31x/F39x (lock byte at end of user flash).
        let limit = flashSize
        if let hi = full.highestAddress, hi >= limit { throw FlashError.imageTooLarge(hi + 1, limit) }
        if plan.keepExistingBootloader && !full.contains(range: 0x1C00..<0x1E00) {
            let boot = try programmer.readFlash(address: 0x1C00, count: 0x200, progress: nil)
            if boot.contains(where: { $0 != 0xFF }) {
                Log.info("Keeping existing bootloader (0x1C00)")
                full.write(boot, at: 0x1C00)
            }
        }
        let end = ((full.highestAddress ?? 0) / 256 + 1) * 256
        let image = full.read(0, min(end, limit))
        report("Erase chip …", 0.02)
        try programmer.eraseChip()
        let total = Double(image.count * (verify ? 2 : 1))
        var offset = 0
        while offset < image.count {
            try programmer.checkCancel()
            let n = min(256, image.count - offset)
            let chunk = Array(image[offset..<(offset + n)])
            if chunk.contains(where: { $0 != 0xFF }) {
                try programmer.writeFlash(address: offset, data: chunk, progress: nil)
            }
            offset += n
            report("Writing flash…", Double(offset) / total)
        }
        if verify {
            let back = try programmer.readFlash(address: 0, count: image.count) { d, _ in
                self.report("Verifying flash…", Double(image.count + d) / total)
            }
            if let i = zip(back, image).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset {
                throw FlashError.verifyFailed("Flash", i)
            }
        }
        report("Flash finished", 1)
    }

    private func flashAtmel(_ plan: FlashPlan, device: DeviceInfo, currentSettings: BLHeliSettings?) throws {
        let ps = device.pageSize
        let userFlash = device.userFlashSize
        if let hi = plan.flash.highestAddress, hi >= userFlash { throw FlashError.imageTooLarge(hi + 1, userFlash) }
        let image = plan.flash.read(0, userFlash)
        var eep = plan.eeprom ?? MemoryImage()
        if let s = plan.settings { eep.write(s.raw, at: 0) }
        let eepEnd = max(BLHeliSettings.size, (eep.highestAddress ?? -1) + 1)
        let eepData = eep.read(0, eepEnd)
        let jumpToBootloader: [UInt8] = device.flashSize == 0x2000 ? [0xDF, 0xCD] : [0x0C, 0x94, 0x00, 0x1E]
        let total = Double(userFlash * (verify && device.canReadFlash ? 2 : 1) + eepData.count)
        var done = 0.0

        if let cur = currentSettings, (try? cur.validate()) != nil {
            try programmer.writeEEPROM(address: BLHeliParam.name.eepromOffset,
                                       data: paddedLatin1("**FLASH*FAILED**", length: 16), progress: nil)
        }
        try programmer.checkCancel()
        report("Writing flash…", 0)
        try programmer.writeFlash(address: ps, data: jumpToBootloader, progress: nil)
        try programmer.erasePage(address: 0)
        let body = Array(image[(2 * ps)..<userFlash])
        try programmer.writeFlash(address: 2 * ps, data: body) { d, _ in self.report("Writing flash…", Double(d) / total) }
        done += Double(body.count)
        try programmer.writeFlash(address: 0, data: Array(image[0..<(2 * ps)]), progress: nil)
        done += Double(2 * ps)
        report("Writing EEPROM…", done / total)
        try programmer.writeEEPROM(address: 0, data: eepData, progress: nil)
        done += Double(eepData.count)
        if verify {
            if device.canReadFlash {
                let back = try programmer.readFlash(address: 0, count: image.count) { d, _ in
                    self.report("Verifying flash…", (done + Double(d)) / total)
                }
                if let i = zip(back, image).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset {
                    throw FlashError.verifyFailed("Flash", i)
                }
            }
            let eback = try programmer.readEEPROM(address: 0, count: eepData.count)
            if let i = zip(eback, eepData).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset {
                throw FlashError.verifyFailed("EEprom", i)
            }
        }
        report("Flash finished", 1)
    }

    private func flashISP(_ plan: FlashPlan, device: DeviceInfo, isp: ISPProgrammer) throws {
        var image = plan.flash
        if let boot = plan.ispBootloader {
            for (a, b) in boot.bytes { image[a] = b }
        }
        if let hi = image.highestAddress, hi >= device.flashSize { throw FlashError.imageTooLarge(hi + 1, device.flashSize) }
        var eep = plan.eeprom ?? MemoryImage()
        if let s = plan.settings { eep.write(s.raw, at: 0) }
        let eepData = eep.isEmpty ? nil : eep.read(0, device.eepromSize)
        report("Flashing over ISP…", 0.1)
        try isp.flashComplete(flash: image, eeprom: eepData, fuses: plan.ispFuses.map { ($0.low, $0.high, $0.ext) },
                              verify: verify) { out in
            if out.contains("Writing") { self.report("Writing…", 0.4) }
            if out.contains("Reading") { self.report("Verifying…", 0.7) }
        }
        report("Flash finished", 1)
    }

    // MARK: Expert tools

    public func dumpFlash(device: DeviceInfo) throws -> [UInt8] {
        let size = device.interfaceMode == .siLabsC2 ? device.flashSize : device.userFlashSize
        return try programmer.readFlash(address: 0, count: size) { d, t in self.report("Reading flash…", Double(d) / Double(t)) }
    }
}
