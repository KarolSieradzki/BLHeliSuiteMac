import Foundation
import Darwin

/// A pseudo terminal pair. The master side is used by the simulator, the slave path is
/// opened like any serial port by the programmer (this is how the protocol stack is tested
/// end-to-end without hardware).
public final class PseudoTerminal: ByteChannel {
    public private(set) var masterFD: Int32
    public let slavePath: String
    private var slaveFD: Int32
    public var name: String { "pty-master" }

    public init() throws {
        var m: Int32 = -1, s: Int32 = -1
        var nameBuf = [CChar](repeating: 0, count: 256)
        if openpty(&m, &s, &nameBuf, nil, nil) != 0 {
            throw SerialError.openFailed("openpty", errno)
        }
        var t = termios()
        tcgetattr(s, &t)
        cfmakeraw(&t)
        tcsetattr(s, TCSANOW, &t)
        masterFD = m
        slaveFD = s
        slavePath = String(cString: nameBuf)
        let flags = fcntl(m, F_GETFL)
        _ = fcntl(m, F_SETFL, flags | O_NONBLOCK)
    }

    deinit { close() }

    /// Keeps the slave open by us until the client opened it (prevents EIO on the master).
    public func releaseSlaveHold() {
        if slaveFD >= 0 { Darwin.close(slaveFD); slaveFD = -1 }
    }

    public func write(_ bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let n = bytes.withUnsafeBytes { Darwin.write(masterFD, $0.baseAddress! + offset, bytes.count - offset) }
            if n > 0 { offset += n; continue }
            if n < 0 && (errno == EAGAIN || errno == EINTR) {
                var pfd = pollfd(fd: masterFD, events: Int16(POLLOUT), revents: 0)
                _ = poll(&pfd, 1, 20)
                continue
            }
            throw SerialError.writeFailed(errno)
        }
    }

    public func read(maxCount: Int, timeout: TimeInterval) throws -> [UInt8] {
        var pfd = pollfd(fd: masterFD, events: Int16(POLLIN), revents: 0)
        let r = poll(&pfd, 1, Int32(max(0, timeout * 1000).rounded(.up)))
        if r <= 0 { return [] }
        if pfd.revents & Int16(POLLIN) != 0 {
            var buf = [UInt8](repeating: 0, count: max(1, maxCount))
            let n = buf.withUnsafeMutableBytes { Darwin.read(masterFD, $0.baseAddress!, maxCount) }
            if n > 0 { return Array(buf.prefix(n)) }
            if n < 0 && (errno == EAGAIN || errno == EINTR) { return [] }
            if n < 0 && errno == EIO { usleep(2000); return [] } // slave not open (yet / anymore)
            return []
        }
        if pfd.revents & Int16(POLLHUP) != 0 { usleep(2000) }
        return []
    }

    public func discardInput() {
        var buf = [UInt8](repeating: 0, count: 512)
        while buf.withUnsafeMutableBytes({ Darwin.read(masterFD, $0.baseAddress!, 512) }) > 0 {}
    }

    public func setBaudRate(_ baud: Int) throws {}

    public func close() {
        releaseSlaveHold()
        if masterFD >= 0 { Darwin.close(masterFD); masterFD = -1 }
    }
}
