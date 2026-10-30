import Foundation
import Darwin
import IOKit
import IOKit.serial

public enum SerialError: Error, LocalizedError {
    case openFailed(String, Int32)
    case configFailed(String, Int32)
    case writeFailed(Int32)
    case readFailed(Int32)
    case disconnected
    case notOpen

    public var errorDescription: String? {
        switch self {
        case .openFailed(let p, let e): return "Cannot open port \(p): \(String(cString: strerror(e)))"
        case .configFailed(let what, let e): return "Port configuration failed (\(what)): \(String(cString: strerror(e)))"
        case .writeFailed(let e): return "Serial write failed: \(String(cString: strerror(e)))"
        case .readFailed(let e): return "Serial read failed: \(String(cString: strerror(e)))"
        case .disconnected: return "The serial device was disconnected."
        case .notOpen: return "The serial port is not open."
        }
    }
}

/// Byte stream abstraction used by every protocol layer (real serial port, PTY, in-memory test pipe).
public protocol ByteChannel: AnyObject {
    var name: String { get }
    func write(_ bytes: [UInt8]) throws
    /// Returns whatever arrives within `timeout` (possibly empty), at most `maxCount` bytes.
    func read(maxCount: Int, timeout: TimeInterval) throws -> [UInt8]
    func discardInput()
    func setBaudRate(_ baud: Int) throws
    func close()
}

public extension ByteChannel {
    /// Reads exactly `count` bytes or returns what arrived before `timeout` elapsed.
    func readExactly(_ count: Int, timeout: TimeInterval) throws -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(count)
        let deadline = monotonicNow() + timeout
        while out.count < count {
            let left = deadline - monotonicNow()
            if left <= 0 { break }
            out += try read(maxCount: count - out.count, timeout: left)
        }
        return out
    }
}

public struct SerialPortInfo: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let product: String?
    public let vendorID: Int?
    public let productID: Int?
    public let serialNumber: String?

    public var displayName: String {
        if let p = product, !p.isEmpty { return "\(name) – \(p)" }
        return name
    }
}

public final class SerialPort: ByteChannel {
    public let path: String
    public var name: String { (path as NSString).lastPathComponent }
    private var fd: Int32 = -1
    private let ioLock = NSLock()
    public private(set) var baudRate: Int = 0

    public init(path: String) {
        self.path = path
    }

    deinit { close() }

    public var isOpen: Bool { fd >= 0 }

    public func open(baudRate: Int, exclusive: Bool = true) throws {
        if fd >= 0 { close() }
        let f = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        if f < 0 { throw SerialError.openFailed(path, errno) }
        fd = f
        if exclusive { _ = ioctl(fd, TIOCEXCL) }
        var t = termios()
        if tcgetattr(fd, &t) != 0 { let e = errno; close(); throw SerialError.configFailed("tcgetattr", e) }
        cfmakeraw(&t)
        t.c_cflag |= tcflag_t(CLOCAL | CREAD)
        t.c_cflag &= ~tcflag_t(CRTSCTS | PARENB | CSTOPB | CSIZE)
        t.c_cflag |= tcflag_t(CS8)
        t.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY | INPCK | ISTRIP)
        withUnsafeMutableBytes(of: &t.c_cc) { cc in
            cc[Int(VMIN)] = 0
            cc[Int(VTIME)] = 0
        }
        cfsetspeed(&t, speed_t(B9600))
        if tcsetattr(fd, TCSANOW, &t) != 0 { let e = errno; close(); throw SerialError.configFailed("tcsetattr", e) }
        try setBaudRate(baudRate)
        tcflush(fd, TCIOFLUSH)
    }

    public func setBaudRate(_ baud: Int) throws {
        guard fd >= 0 else { throw SerialError.notOpen }
        var t = termios()
        if tcgetattr(fd, &t) != 0 { throw SerialError.configFailed("tcgetattr", errno) }
        let standard: [Int: Int32] = [
            1200: B1200, 2400: B2400, 4800: B4800, 9600: B9600, 19200: B19200,
            38400: B38400, 57600: B57600, 115200: B115200, 230400: B230400,
        ]
        if let s = standard[baud] {
            cfsetspeed(&t, speed_t(s))
            if tcsetattr(fd, TCSANOW, &t) != 0 { throw SerialError.configFailed("baud \(baud)", errno) }
        } else {
            // Non-standard rate (e.g. 250000, 500000): IOSSIOSPEED = _IOW('T', 2, speed_t)
            var speed = speed_t(baud)
            let IOSSIOSPEED: UInt = 0x8008_5402
            if ioctl(fd, IOSSIOSPEED, &speed) != 0 { throw SerialError.configFailed("baud \(baud)", errno) }
        }
        baudRate = baud
    }

    public func setDTR(_ on: Bool) {
        guard fd >= 0 else { return }
        _ = ioctl(fd, on ? TIOCSDTR : TIOCCDTR)
    }

    public func setRTS(_ on: Bool) {
        guard fd >= 0 else { return }
        var bits: Int32 = TIOCM_RTS
        _ = ioctl(fd, on ? TIOCMBIS : TIOCMBIC, &bits)
    }

    public func write(_ bytes: [UInt8]) throws {
        guard fd >= 0 else { throw SerialError.notOpen }
        var offset = 0
        let deadline = monotonicNow() + 5
        while offset < bytes.count {
            let n = bytes.withUnsafeBytes { buf -> Int in
                Darwin.write(fd, buf.baseAddress! + offset, bytes.count - offset)
            }
            if n > 0 {
                offset += n
            } else if n < 0 && (errno == EAGAIN || errno == EINTR) {
                if monotonicNow() > deadline { throw SerialError.writeFailed(EAGAIN) }
                var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                _ = poll(&pfd, 1, 50)
            } else if n < 0 && (errno == ENXIO || errno == EIO || errno == EBADF) {
                throw SerialError.disconnected
            } else if n < 0 {
                throw SerialError.writeFailed(errno)
            }
        }
        tcdrain(fd)
    }

    public func read(maxCount: Int, timeout: TimeInterval) throws -> [UInt8] {
        guard fd >= 0 else { throw SerialError.notOpen }
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let ms = Int32(max(0, min(timeout, 60) * 1000).rounded(.up))
        let r = poll(&pfd, 1, ms)
        if r < 0 {
            if errno == EINTR { return [] }
            throw SerialError.readFailed(errno)
        }
        if r == 0 { return [] }
        if pfd.revents & Int16(POLLIN) != 0 {
            var buf = [UInt8](repeating: 0, count: max(1, maxCount))
            let n = buf.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, maxCount) }
            if n > 0 { return Array(buf.prefix(n)) }
            if n == 0 { throw SerialError.disconnected }
            if errno == EAGAIN || errno == EINTR { return [] }
            if errno == ENXIO || errno == EIO { throw SerialError.disconnected }
            throw SerialError.readFailed(errno)
        }
        if pfd.revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 {
            throw SerialError.disconnected
        }
        return []
    }

    public func discardInput() {
        guard fd >= 0 else { return }
        tcflush(fd, TCIFLUSH)
        // Also drain anything that is already in flight.
        var buf = [UInt8](repeating: 0, count: 512)
        while true {
            let n = buf.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, 512) }
            if n <= 0 { break }
        }
    }

    public func close() {
        if fd >= 0 {
            _ = ioctl(fd, TIOCNXCL)
            Darwin.close(fd)
            fd = -1
        }
    }

    // MARK: - Enumeration

    /// Lists callout devices (/dev/cu.*) with USB metadata from the IORegistry.
    public static func availablePorts() -> [SerialPortInfo] {
        var result: [SerialPortInfo] = []
        guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else { return fallbackPorts() }
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) != KERN_SUCCESS {
            return fallbackPorts()
        }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let path = IORegistryEntryCreateCFProperty(service, kIOCalloutDeviceKey as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String else { continue }
            if path.contains("Bluetooth-Incoming-Port") || path.contains("debug-console") { continue }
            func search(_ key: String) -> Any? {
                IORegistryEntrySearchCFProperty(service, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                                                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
            }
            let product = (search("USB Product Name") as? String) ?? (search("kUSBProductString") as? String)
            let vendor = (search("idVendor") as? NSNumber)?.intValue
            let pid = (search("idProduct") as? NSNumber)?.intValue
            let serial = (search("USB Serial Number") as? String) ?? (search("kUSBSerialNumberString") as? String)
            result.append(SerialPortInfo(path: path, name: (path as NSString).lastPathComponent, product: product,
                                         vendorID: vendor, productID: pid, serialNumber: serial))
        }
        if result.isEmpty { return fallbackPorts() }
        return result.sorted { a, b in
            let au = a.vendorID != nil, bu = b.vendorID != nil
            if au != bu { return au }
            return a.path < b.path
        }
    }

    private static func fallbackPorts() -> [SerialPortInfo] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return names.filter { $0.hasPrefix("cu.") && !$0.contains("Bluetooth-Incoming-Port") && !$0.contains("debug-console") }
            .sorted()
            .map { SerialPortInfo(path: "/dev/" + $0, name: $0, product: nil, vendorID: nil, productID: nil, serialNumber: nil) }
    }
}
