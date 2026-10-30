import Foundation

/// Behavioural model of an ESC as seen through the BLHeli bootloader (or C2).
/// Flash writes behave like real NOR flash (bits can only be cleared) so a flash
/// procedure that forgets an erase is caught by the self tests.
public final class SimulatedESC {
    public let mcu: MCUInfo
    public var flash: [UInt8]
    public var eeprom: [UInt8]
    public var responding = true
    /// Last char of the "471x" boot message.
    public var bootVersion: UInt8 = 0x63
    public var bootloaderStart: Int
    public private(set) var writeCount = 0
    public private(set) var eraseCount = 0
    /// Simulated power loss: after this many flash writes all further commands fail.
    public var failAfterWrites: Int?

    public init(mcu: MCUInfo) {
        self.mcu = mcu
        flash = [UInt8](repeating: 0xFF, count: mcu.flashSize)
        eeprom = [UInt8](repeating: 0xFF, count: max(mcu.eepromSize, 1))
        bootloaderStart = mcu.family == .silabs ? 0x1C00 : mcu.flashSize - 0x200
    }

    public var family: MCUFamily { mcu.family }

    /// Loads a firmware image (and Atmel EEPROM) like a factory programmed ESC.
    public func program(flash image: MemoryImage, eeprom eep: MemoryImage? = nil) {
        for (a, b) in image.bytes where a < flash.count { flash[a] = b }
        if let e = eep { for (a, b) in e.bytes where a < eeprom.count { eeprom[a] = b } }
    }

    func checkPower() -> Bool {
        if let f = failAfterWrites, writeCount >= f { return false }
        return responding
    }

    // MARK: bootloader semantics

    func blRead(_ addr: Int, _ n: Int) -> [UInt8]? {
        guard checkPower(), addr >= 0, addr + n <= flash.count else { return nil }
        return Array(flash[addr..<(addr + n)])
    }

    func blWrite(_ addr: Int, _ data: [UInt8]) -> Bool {
        guard checkPower(), addr >= 0, addr + data.count <= flash.count else { return false }
        // The bootloader protects itself.
        if addr + data.count > bootloaderStart { return false }
        writeCount += 1
        switch family {
        case .silabs:
            for (i, b) in data.enumerated() { flash[addr + i] &= b }
        default:
            // AVR bootloader: each touched page is erased, then programmed.
            let ps = mcu.pageSize
            var page = (addr / ps) * ps
            while page < addr + data.count {
                for i in page..<(page + ps) { flash[i] = 0xFF }
                page += ps
            }
            for (i, b) in data.enumerated() { flash[addr + i] = b }
        }
        return true
    }

    func blErasePage(_ page: Int) -> Bool {
        guard checkPower() else { return false }
        let ps = mcu.pageSize
        let a = page * ps
        guard a + ps <= bootloaderStart else { return false }
        eraseCount += 1
        for i in a..<(a + ps) { flash[i] = 0xFF }
        return true
    }

    func eepromRead(_ addr: Int, _ n: Int) -> [UInt8]? {
        guard checkPower(), addr + n <= eeprom.count else { return nil }
        return Array(eeprom[addr..<(addr + n)])
    }

    func eepromWrite(_ addr: Int, _ data: [UInt8]) -> Bool {
        guard checkPower(), addr + data.count <= eeprom.count else { return false }
        for (i, b) in data.enumerated() { eeprom[addr + i] = b }
        return true
    }

    // MARK: C2 semantics (whole flash accessible, no bootloader protection)

    func c2Write(_ addr: Int, _ data: [UInt8]) -> Bool {
        guard checkPower(), addr + data.count <= flash.count else { return false }
        writeCount += 1
        for (i, b) in data.enumerated() { flash[addr + i] &= b }
        return true
    }

    func c2ErasePage(_ page: Int) -> Bool {
        let ps = mcu.pageSize
        guard checkPower(), (page + 1) * ps <= flash.count else { return false }
        for i in (page * ps)..<((page + 1) * ps) { flash[i] = 0xFF }
        return true
    }

    func c2EraseAll() -> Bool {
        guard checkPower() else { return false }
        for i in 0..<flash.count { flash[i] = 0xFF }
        return true
    }

    public var settings: BLHeliSettings {
        if family == .silabs {
            return BLHeliSettings(raw: Array(flash[0x1A00..<0x1A70]))
        }
        return BLHeliSettings(raw: Array(eeprom[0..<0x70]))
    }
}
