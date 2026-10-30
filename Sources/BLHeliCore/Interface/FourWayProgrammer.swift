import Foundation

public enum ConnectError: Error, LocalizedError {
    case flightControllerNotResponding
    case armed
    case motorsRunning
    case passthroughFailed(String)
    case interfaceNotResponding
    case outdatedInterface(String)

    public var errorDescription: String? {
        switch self {
        case .flightControllerNotResponding:
            return "Connection to Flightcontroller failed!\nPlease check usb/serial port and power connections."
        case .armed:
            return "Initialization of flight controller denied!\nPlease check all motors are disarmed!"
        case .motorsRunning:
            return "Initialization of flight controller denied!\nPlease check all motors are stopped!"
        case .passthroughFailed(let fc):
            return "Initialization of serial 1wire passthrough or 4way interface failed!\n\nPlease check \(fc) revision for support of the 4way interface!"
        case .interfaceNotResponding:
            return "Connection to 4-way Interface failed!\n\nPlease check usb/serial port and power connections to the interface!"
        case .outdatedInterface(let s):
            return s
        }
    }
}

/// ESC access through the 4-way interface protocol – used for Betaflight/Cleanflight/INAV
/// passthrough (MSP_SET_4WAY_IF) and for the Arduino / ATmega 4w-if boxes.
public final class FourWayProgrammer: ESCProgrammer {
    public enum Kind: Sendable {
        case flightController(FlightControllerInfo)
        case box
    }

    public let channel: ByteChannel
    public let client: FourWayClient
    public let kind: Kind
    public private(set) var escCount: Int
    public private(set) var protocolVersion: UInt8 = 0
    public private(set) var boxName: String = ""
    public private(set) var boxVersion: UInt16 = 0
    public private(set) var currentDevice: DeviceInfo?
    public private(set) var currentESC: Int = 0
    public private(set) var isConnected = true
    public var cancelRequested = false

    public var interfaceName: String {
        switch kind {
        case .flightController(let fc): return "\(fc.variant) \(fc.version) – 4-way \(boxName)"
        case .box: return "\(boxName) v\(boxVersion >> 8).\(boxVersion & 0xFF)"
        }
    }

    init(channel: ByteChannel, kind: Kind, escCount: Int) {
        self.channel = channel
        self.client = FourWayClient(channel: channel)
        self.kind = kind
        self.escCount = escCount
    }

    // MARK: Session setup

    /// Betaflight / Cleanflight / INAV: identify via MSP, check motors, switch to 4-way.
    public static func connectFlightController(channel: ByteChannel, family: MCUFamily, checkArmed: Bool = true) throws -> FourWayProgrammer {
        let msp = MSPClient(channel: channel)
        channel.discardInput()
        var info: FlightControllerInfo
        do {
            info = try msp.identify()
        } catch {
            // The FC might still be in 4-way mode from an interrupted session ("MSP 4Way deactivate").
            Log.info("FC does not answer MSP – trying to leave a pending 4-way session…")
            try? channel.write(FourWayClient.frame(FourWayCommand.interfaceExit.rawValue, address: 0, params: [0]))
            sleepSeconds(0.6)
            channel.discardInput()
            do { info = try msp.identify() } catch { throw ConnectError.flightControllerNotResponding }
        }
        Log.info("Connected to \(info.description)")
        if checkArmed {
            if (try? msp.isArmed()) == true { throw ConnectError.armed }
            if let motors = try? msp.motorValues(), let cfg = try? msp.motorConfig() {
                info.motorValues = motors
                let running = motors.contains { $0 > max(cfg.command, 1000) + 20 }
                if running { throw ConnectError.motorsRunning }
            }
        }
        let count: Int
        do { count = try msp.enter4Way() } catch { throw ConnectError.passthroughFailed(info.variant) }
        info.motorCount = count
        Log.info("4-way interface activated, \(count) ESC channel(s)")
        sleepSeconds(0.05)
        channel.discardInput()
        let p = FourWayProgrammer(channel: channel, kind: .flightController(info), escCount: max(count, 1))
        try p.readInterfaceInfo()
        let mode: FourWayInterfaceMode = family == .atmel ? .atmelBLB : .siLabsBLB
        try? p.client.setMode(mode)
        return p
    }

    /// Arduino / ATmega 4w-if box. `mode` selects C2 or bootloader access (cmd_InterfaceSetMode).
    public static func connectBox(channel: ByteChannel, mode: FourWayInterfaceMode, resetDelay: TimeInterval = 2.0) throws -> FourWayProgrammer {
        if resetDelay > 0 {
            Log.info(String(format: "Waiting %.1f s for the interface to start…", resetDelay))
            sleepSeconds(resetDelay)
        }
        channel.discardInput()
        // "send_InterfaceListen": some 0xFF bytes put a box from menu into listen state.
        try channel.write([0xFF, 0xFF, 0xFF, 0xFF])
        sleepSeconds(0.1)
        channel.discardInput()
        let p = FourWayProgrammer(channel: channel, kind: .box, escCount: 1)
        var ok = false
        for _ in 0..<3 {
            if (try? p.client.testAlive()) != nil { ok = true; break }
            sleepSeconds(0.3)
        }
        if !ok {
            // Older interfaces do not answer TestAlive before the version query.
            if (try? p.client.protocolVersion()) == nil { throw ConnectError.interfaceNotResponding }
        }
        try p.readInterfaceInfo()
        if p.boxName.hasPrefix("m") { p.escCount = 8 }
        if p.protocolVersion >= 106 || p.protocolVersion >= 6 && p.protocolVersion < 100 {
            do {
                try p.client.setMode(mode)
            } catch let e as FourWayError where e.ack == FourWayAck.invalidParam.rawValue {
                throw ConnectError.outdatedInterface("Cannot set interface to \"\(mode)\" mode!\nCurrent interface is not switchable.")
            }
        }
        return p
    }

    func readInterfaceInfo() throws {
        protocolVersion = try client.protocolVersion()
        boxName = (try? client.interfaceName()) ?? ""
        boxVersion = (try? client.interfaceVersion()) ?? 0
        Log.info("4-way interface \"\(boxName)\" version \(boxVersion >> 8).\(boxVersion & 0xFF), protocol \(protocolVersion)")
    }

    // MARK: ESCProgrammer

    public func selectESC(_ index: Int) throws -> DeviceInfo {
        guard index >= 0 && index < max(escCount, 1) else { throw ProgrammerError.escNotFound(index) }
        let params: [UInt8]
        do {
            params = try client.initFlash(esc: index)
        } catch let e as FourWayError {
            if case .nack(_, let a) = e, a == FourWayAck.invalidChannel.rawValue {
                throw ProgrammerError.escNotFound(index)
            }
            if case .nack = e { throw ProgrammerError.escNotFound(index) }
            throw e
        }
        let dev = DeviceInfo.fromInitFlash(params)
        currentDevice = dev
        currentESC = index
        Log.info("ESC #\(index + 1): \(dev.description)")
        return dev
    }

    private var maxChunk: Int { 256 }

    public func readFlash(address: Int, count: Int, progress: ProgressHandler?) throws -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(count)
        var addr = address
        while out.count < count {
            try checkCancel()
            let n = min(maxChunk, count - out.count)
            out += try client.read(address: addr, count: n)
            addr += n
            progress?(out.count, count)
        }
        return out
    }

    public func writeFlash(address: Int, data: [UInt8], progress: ProgressHandler?) throws {
        var offset = 0
        while offset < data.count {
            try checkCancel()
            let n = min(maxChunk, data.count - offset)
            try client.write(address: address + offset, data: Array(data[offset..<(offset + n)]))
            offset += n
            progress?(offset, data.count)
        }
    }

    public func erasePage(address: Int) throws {
        guard let dev = currentDevice else { throw ProgrammerError.escNotFound(currentESC) }
        switch dev.interfaceMode {
        case .siLabsBLB, .siLabsC2:
            try client.pageErase(page: address / dev.pageSize)
        default:
            // Atmel bootloaders erase on write – BLHeliSuite writes an empty page.
            try writeFlash(address: address, data: [UInt8](repeating: 0xFF, count: dev.pageSize), progress: nil)
        }
    }

    public func eraseChip() throws {
        guard let dev = currentDevice else { throw ProgrammerError.escNotFound(currentESC) }
        if dev.interfaceMode == .siLabsC2 {
            try client.eraseAll()
        } else {
            throw ProgrammerError.notSupported("Erase chip is only available in C2 mode.")
        }
    }

    public func readEEPROM(address: Int, count: Int) throws -> [UInt8] {
        var out: [UInt8] = []
        var addr = address
        while out.count < count {
            try checkCancel()
            let n = min(maxChunk, count - out.count)
            out += try client.readEEPROM(address: addr, count: n)
            addr += n
        }
        return out
    }

    public func writeEEPROM(address: Int, data: [UInt8], progress: ProgressHandler?) throws {
        var offset = 0
        while offset < data.count {
            try checkCancel()
            let n = min(maxChunk, data.count - offset)
            try client.writeEEPROM(address: address + offset, data: Array(data[offset..<(offset + n)]))
            offset += n
            progress?(offset, data.count)
        }
    }

    public func resetESC(_ index: Int) throws {
        try client.deviceReset(esc: index)
    }

    public func keepAlive() throws {
        try client.testAlive()
    }

    public func disconnect() {
        guard isConnected else { return }
        isConnected = false
        // cmd_InterfaceExit: the FC resets the ESCs and returns to MSP, boxes return to their menu.
        _ = try? client.send(.interfaceExit, timeout: 1.0)
        channel.close()
    }
}
