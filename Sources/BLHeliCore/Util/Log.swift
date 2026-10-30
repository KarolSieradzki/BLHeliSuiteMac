import Foundation

public enum LogLevel: Int, Comparable, Sendable {
    case debug = 0, info, success, warning, error

    public static func < (a: LogLevel, b: LogLevel) -> Bool { a.rawValue < b.rawValue }
}

public struct LogEntry: Identifiable, Sendable {
    public let id: Int
    public let date: Date
    public let level: LogLevel
    public let message: String
}

/// Thread-safe log sink. The UI subscribes with `addHandler`; the CLI echoes to stderr.
public final class Log: @unchecked Sendable {
    public static let shared = Log()

    private let lock = NSLock()
    private var handlers: [UUID: (LogEntry) -> Void] = [:]
    private var counter = 0
    public var echoToStderr = false
    public var minimumEchoLevel: LogLevel = .info
    /// When false, `debug` messages (protocol traffic) are dropped early.
    public var protocolTrace = false

    @discardableResult
    public func addHandler(_ h: @escaping (LogEntry) -> Void) -> UUID {
        let id = UUID()
        lock.lock(); handlers[id] = h; lock.unlock()
        return id
    }

    public func removeHandler(_ id: UUID) {
        lock.lock(); handlers[id] = nil; lock.unlock()
    }

    public func write(_ level: LogLevel, _ message: String) {
        if level == .debug && !protocolTrace { return }
        lock.lock()
        counter += 1
        let entry = LogEntry(id: counter, date: Date(), level: level, message: message)
        let hs = Array(handlers.values)
        lock.unlock()
        if echoToStderr && level >= minimumEchoLevel {
            FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
        }
        for h in hs { h(entry) }
    }

    public static func debug(_ m: @autoclosure () -> String) {
        if shared.protocolTrace { shared.write(.debug, m()) }
    }
    public static func info(_ m: String) { shared.write(.info, m) }
    public static func success(_ m: String) { shared.write(.success, m) }
    public static func warning(_ m: String) { shared.write(.warning, m) }
    public static func error(_ m: String) { shared.write(.error, m) }
}
