import Foundation
import IOKit
import IOKit.hid

public enum ToolstickError: Error, LocalizedError {
    case notFound
    case openFailed(Int32)
    case transferFailed(String)
    case unexpectedAnswer(String)

    public var errorDescription: String? {
        switch self {
        case .notFound: return "No SiLabs Toolstick / USB Debug Adapter found (USB 10C4:8253 / 8044)."
        case .openFailed(let r): return String(format: "Cannot connect to the selected ToolStick base adapter (IOHID 0x%08X).\nPlease check that the device is plugged in and not already in use.", r)
        case .transferFailed(let s): return "Toolstick communication failed: \(s)"
        case .unexpectedAnswer(let s): return "Unexpected answer from the Toolstick: \(s)"
        }
    }
}

/// Transport used by ToolstickProgrammer (real HID device or a simulation).
public protocol ToolstickTransport: AnyObject {
    func write(_ data: [UInt8]) throws
    func read(timeout: TimeInterval) throws -> [UInt8]
    func discardInput()
    func setFeature(_ id: UInt8, _ value: UInt8) throws
    func getFeature(_ id: UInt8) throws -> UInt8
    func close()
}

/// Raw HID transport to the SiLabs ToolStick base adapter / USB Debug Adapter (USBHID.dll).
/// Output reports are 64 bytes: [report id = payload length (1…63)] + payload.
public final class ToolstickHID: ToolstickTransport {
    public static let vendorID = 0x10C4
    public static let productIDs = [0x8253, 0x8044, 0x8045]

    let device: IOHIDDevice
    private var inputBuffer = [UInt8](repeating: 0, count: 64)
    private var received: [[UInt8]] = []
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var isOpen = false

    public struct Info: Sendable {
        public let productID: Int
        public let serial: String
        public let product: String
    }

    static func matchingDevices() -> [IOHIDDevice] {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches = productIDs.map { [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: $0] as CFDictionary }
        IOHIDManagerSetDeviceMatchingMultiple(mgr, matches as CFArray)
        guard let set = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> else { return [] }
        return Array(set)
    }

    public static func list() -> [Info] {
        matchingDevices().map { d in
            Info(productID: (IOHIDDeviceGetProperty(d, kIOHIDProductIDKey as CFString) as? Int) ?? 0,
                 serial: (IOHIDDeviceGetProperty(d, kIOHIDSerialNumberKey as CFString) as? String) ?? "",
                 product: (IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String) ?? "ToolStick")
        }
    }

    public init(serial: String? = nil) throws {
        let devs = ToolstickHID.matchingDevices()
        guard let d = devs.first(where: { serial == nil || (IOHIDDeviceGetProperty($0, kIOHIDSerialNumberKey as CFString) as? String) == serial }) else {
            throw ToolstickError.notFound
        }
        device = d
        var r = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if r != kIOReturnSuccess { r = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        guard r == kIOReturnSuccess else { throw ToolstickError.openFailed(r) }
        isOpen = true
        startInputThread()
    }

    deinit { close() }

    private func startInputThread() {
        let ready = DispatchSemaphore(value: 0)
        let t = Thread { [weak self] in
            guard let self else { return }
            self.runLoop = CFRunLoopGetCurrent()
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            self.inputBuffer.withUnsafeMutableBufferPointer { buf in
                IOHIDDeviceRegisterInputReportCallback(self.device, buf.baseAddress!, buf.count, { context, result, _, _, _, report, length in
                    guard let context else { return }
                    let me = Unmanaged<ToolstickHID>.fromOpaque(context).takeUnretainedValue()
                    let data = Array(UnsafeBufferPointer(start: report, count: length))
                    me.lock.lock(); me.received.append(data); me.lock.unlock()
                    me.semaphore.signal()
                }, ctx)
                IOHIDDeviceScheduleWithRunLoop(self.device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
                ready.signal()
                CFRunLoopRun()
            }
        }
        t.name = "ToolstickHID"
        thread = t
        t.start()
        ready.wait()
    }

    /// Sends a byte stream split into ≤63 byte reports (EC3Write).
    public func write(_ data: [UInt8]) throws {
        Log.debug("TS > \(data.prefix(16).hexString)\(data.count > 16 ? " … (\(data.count))" : "")")
        var offset = 0
        repeat {
            let n = min(63, data.count - offset)
            var report = [UInt8](repeating: 0, count: 64)
            report[0] = UInt8(n)
            for i in 0..<n { report[1 + i] = data[offset + i] }
            let r = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), report, report.count)
            guard r == kIOReturnSuccess else { throw ToolstickError.transferFailed(String(format: "write 0x%08X", r)) }
            offset += n
        } while offset < data.count
    }

    /// Returns the payload of the next input report (EC3Read skips the leading length/report-id byte).
    public func read(timeout: TimeInterval) throws -> [UInt8] {
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            throw ToolstickError.transferFailed("timeout")
        }
        lock.lock(); let r = received.removeFirst(); lock.unlock()
        Log.debug("TS < \(r.prefix(16).hexString)")
        return r.count > 1 ? Array(r.dropFirst()) : r
    }

    public func discardInput() {
        lock.lock()
        let n = received.count
        received.removeAll()
        lock.unlock()
        for _ in 0..<n { _ = semaphore.wait(timeout: .now()) }
    }

    /// TXFeatureReport(id, value): 2-byte feature report [id, value].
    public func setFeature(_ id: UInt8, _ value: UInt8) throws {
        let report: [UInt8] = [id, value]
        let r = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(id), report, report.count)
        guard r == kIOReturnSuccess else { throw ToolstickError.transferFailed(String(format: "set feature 0x%02X: 0x%08X", id, r)) }
    }

    /// RXFeatureReport(id): returns the data byte following the report id.
    public func getFeature(_ id: UInt8) throws -> UInt8 {
        var report = [UInt8](repeating: 0, count: 64)
        report[0] = id
        var len = CFIndex(report.count)
        let r = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(id), &report, &len)
        guard r == kIOReturnSuccess else { throw ToolstickError.transferFailed(String(format: "get feature 0x%02X: 0x%08X", id, r)) }
        return len >= 2 ? report[1] : report[0]
    }

    public func close() {
        guard isOpen else { return }
        isOpen = false
        if let rl = runLoop {
            IOHIDDeviceUnscheduleFromRunLoop(device, rl, CFRunLoopMode.defaultMode.rawValue)
            CFRunLoopStop(rl)
            runLoop = nil
        }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }
}

/// SiLabs C2 programming through the ToolStick base adapter / USB Debug Adapter.
/// Protocol taken from SiUtil.dll (C2 mode, adapter type 3 = USB):
///   [0x40,0] + [0x20]          connect target (C2)            → ack 0x0D
///   [0x21]                     disconnect
///   [0x22] / [0x23]            device id + revision / derivative id (2 bytes each)
///   [0x2E,lo,hi,n]             read code (n ≤ 60)             → n bytes + status
///   [0x2F,lo,hi,n,data…]       write code (n ≤ 60)            → ack
///   [0x30,page]                erase flash sector             → ack
///   [0x3C]                     erase device                   → ack (up to 15 s)
/// Feature reports 0x40…0x44 select the adapter mode and report the firmware version.
public final class ToolstickProgrammer: ESCProgrammer {
    public var cancelRequested = false
    public private(set) var isConnected = false
    public private(set) var adapterMode: UInt8 = 0
    public private(set) var firmwareVersion: UInt8 = 0
    public var interfaceName: String { "SiLabs ToolStick (C2) fw \(firmwareVersion)" }
    public var escCount: Int { 1 }
    let hid: ToolstickTransport
    private var device: DeviceInfo?
    private var targetConnected = false
    static let ack: UInt8 = 0x0D
    static let chunk = 0x3C

    public init(transport: ToolstickTransport) {
        self.hid = transport
        isConnected = true
    }

    public static func devicesDescription() -> String {
        let l = ToolstickHID.list()
        if l.isEmpty { return "no Toolstick found" }
        return l.map { "\($0.product) \($0.serial)" }.joined(separator: ", ")
    }

    /// Opens the adapter with the given serial number (nil: the first one found).
    public static func open(serial: String? = nil) throws -> ToolstickProgrammer {
        let hid = try ToolstickHID(serial: serial)
        let p = ToolstickProgrammer(transport: hid)
        try p.initAdapter()
        return p
    }

    /// FUN_100073f0 for ToolStick adapters: mode (0x43) and firmware version (0x41/0x42/0x44).
    public func initAdapter() throws {
        adapterMode = (try? hid.getFeature(0x43)) ?? 0
        try? hid.setFeature(0x41, 0)
        if (try? hid.getFeature(0x42)) == 1 {
            firmwareVersion = (try? hid.getFeature(0x44)) ?? 0
        } else {
            try? hid.setFeature(0x40, 1)
            firmwareVersion = 0
        }
        Log.info("ToolStick adapter mode \(adapterMode), firmware version \(firmwareVersion)")
        if firmwareVersion != 0x12 && firmwareVersion != 0x26 && firmwareVersion != 5 {
            Log.warning("ToolStick firmware version \(firmwareVersion) differs from the version SiUtil.dll expects (18). If programming fails, update the adapter firmware with the SiLabs tools.")
        }
    }

    func command(_ bytes: [UInt8], answer: Int, timeout: TimeInterval = 2.5) throws -> [UInt8] {
        hid.discardInput()
        try hid.write(bytes)
        let r = try hid.read(timeout: timeout)
        guard r.count >= answer else { throw ToolstickError.unexpectedAnswer(r.hexString) }
        return Array(r.prefix(answer))
    }

    func acked(_ bytes: [UInt8], timeout: TimeInterval = 2.5) throws {
        let r = try command(bytes, answer: 1, timeout: timeout)
        guard r[0] == ToolstickProgrammer.ack else {
            throw ToolstickError.unexpectedAnswer(String(format: "command 0x%02X answered 0x%02X", bytes[0], r[0]))
        }
    }

    public func selectESC(_ index: Int) throws -> DeviceInfo {
        if targetConnected { try? acked([0x21]) }
        try acked([0x40, 0x00])
        try acked([0x20])
        targetConnected = true
        let id = try command([0x22], answer: 2)
        let der = try command([0x23], answer: 2)
        let mcu = MCUTable.bySiLabsC2(deviceID: id[0], derivativeID: der[0])
        Log.info(String(format: "C2 device id 0x%02X rev 0x%02X derivative 0x%02X – %@", id[0], id[1], der[0], mcu?.name ?? "unknown"))
        let dev = DeviceInfo(interfaceMode: .siLabsC2, mcu: mcu, signature: UInt16(id[0]) << 8 | UInt16(der[0]), bootInfo: 0x03, raw: id + der)
        device = dev
        return dev
    }

    public func readFlash(address: Int, count: Int, progress: ProgressHandler?) throws -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(count)
        while out.count < count {
            try checkCancel()
            let n = min(ToolstickProgrammer.chunk, count - out.count)
            let a = address + out.count
            let r = try command([0x2E, UInt8(a & 0xFF), UInt8((a >> 8) & 0xFF), UInt8(n)], answer: n + 1)
            if r[n] != ToolstickProgrammer.ack && r[n] != 0 {
                Log.debug(String(format: "C2 read status 0x%02X at 0x%04X", r[n], a))
            }
            out += r.prefix(n)
            progress?(out.count, count)
        }
        return out
    }

    public func writeFlash(address: Int, data: [UInt8], progress: ProgressHandler?) throws {
        var offset = 0
        while offset < data.count {
            try checkCancel()
            let n = min(ToolstickProgrammer.chunk, data.count - offset)
            let a = address + offset
            try acked([0x2F, UInt8(a & 0xFF), UInt8((a >> 8) & 0xFF), UInt8(n)] + Array(data[offset..<(offset + n)]))
            offset += n
            progress?(offset, data.count)
        }
    }

    public func erasePage(address: Int) throws {
        let ps = device?.pageSize ?? 0x200
        try acked([0x30, UInt8(address / ps)], timeout: 5)
    }

    public func eraseChip() throws {
        try acked([0x3C], timeout: 15)
    }

    public func readEEPROM(address: Int, count: Int) throws -> [UInt8] {
        throw ProgrammerError.notSupported("SiLabs MCUs have no EEPROM (setup is stored in flash).")
    }

    public func writeEEPROM(address: Int, data: [UInt8], progress: ProgressHandler?) throws {
        throw ProgrammerError.notSupported("SiLabs MCUs have no EEPROM (setup is stored in flash).")
    }

    public func resetESC(_ index: Int) throws {
        if targetConnected { try? acked([0x21]); targetConnected = false }
    }

    public func keepAlive() throws {}

    public func disconnect() {
        if targetConnected { try? acked([0x21]); targetConnected = false }
        hid.close()
        isConnected = false
    }
}
