import Foundation
import VCL
import BLHeliCore

/// Serial ports (macOS /dev/cu.* devices take the place of the Windows COM port numbers).
final class PortList {
    private(set) var ports: [SerialPortInfo] = []

    var paths: [String] { ports.map(\.path) }
    var names: [String] { ports.map { PortList.shortName($0.path) } }

    func refresh() {
        ports = SerialPort.availablePorts()
        // Extra ports (e.g. the pseudo terminal of blheli-sim): BLHELI_EXTRA_PORTS=/dev/ttys003:/dev/ttys004
        for p in (ProcessInfo.processInfo.environment["BLHELI_EXTRA_PORTS"] ?? "").split(separator: ":") where !paths.contains(String(p)) {
            ports.append(SerialPortInfo(path: String(p), name: (String(p) as NSString).lastPathComponent, product: nil,
                                        vendorID: nil, productID: nil, serialNumber: nil))
        }
    }

    func index(of path: String) -> Int? { ports.firstIndex { $0.path == path } }

    /// First USB serial device (FC, Arduino, USB-UART adapter).
    var preferredPath: String? { ports.first { $0.vendorID != nil }?.path ?? ports.first?.path }

    static func shortName(_ path: String) -> String {
        var n = (path as NSString).lastPathComponent
        if n.hasPrefix("cu.") { n.removeFirst(3) }
        return n
    }

    init() { refresh() }
}

/// Interface object for the serial based programming paths
/// (TUniSerialInterface, TBLBInterface, TFlightCtrlIntf, TArduinoUSBLinker, TStk500v2Interface).
final class SerialIntf {
    let section: String
    let defaultBaud: Int
    var portPath = ""
    var baud: Int
    var programmer: ESCProgrammer?
    var device: DeviceInfo?
    var deviceName = ""
    var escCount = 0
    var isFourWayBox = false
    var lastError = ""
    /// Brand reported by the interface (1 SiLabs, 2 Atmel) – used for the "Switch to … mode?" question.
    var reportedBrand: UInt8 = 0
    var reportedMode: FourWayInterfaceMode?

    init(section: String, defaultBaud: Int) {
        self.section = section
        self.defaultBaud = defaultBaud
        baud = defaultBaud
    }

    var connected: Bool { programmer?.isConnected ?? false }
    var targetConnected: Bool { connected && device != nil }

    func connect(_ type: IntfType) throws {
        guard !portPath.isEmpty else { throw ProgrammerError.notSupported("No serial port selected.") }
        let p: ESCProgrammer
        switch type {
        case .silBLBCF, .atmBLBCF:
            let f = try ProgrammerFactory.openSerial(type == .silBLBCF ? .silabsBLBFlightController : .atmelFlightController,
                                                    portPath: portPath, baud: baud)
            if case .flightController(let fc) = f.kind { deviceName = "\(fc.variant) \(fc.version)" }
            isFourWayBox = false
            p = f
        case .silC2_4wif, .silBLB4wif, .atmBLB4wif, .atmSK4wif:
            let t: InterfaceType = [.silC2_4wif: .silabsC2FourWay, .silBLB4wif: .silabsBLBFourWay,
                                    .atmBLB4wif: .atmelBLBFourWay, .atmSK4wif: .atmelSKFourWay][type]!
            let f = try ProgrammerFactory.openSerial(t, portPath: portPath, baud: baud, arduinoResetDelay: 2.0)
            deviceName = f.boxName
            isFourWayBox = true
            p = f
        case .silBLBCom, .atmBLBCom:
            // TBLBInterface: USB-UART bridge on the signal wire, BLHeli bootloader spoken by the PC
            p = try BLHeliBootloaderProgrammer.open(portPath: portPath, baud: baud, family: type == .silBLBCom ? .silabs : .atmel)
            deviceName = "USB/Com"
            isFourWayBox = false
        case .atmSKAULinker:
            // TArduinoUSBLinker: find the sketch (baud search), then STK500 v2 through it
            let aul = ArduinoUSBLinker()
            aul.portPath = portPath
            aul.baud = baud
            guard aul.connect() else {
                throw ProgrammerError.notSupported(DFormat(NL("Unable to connect to ArduinoUSBLinker at %s"), [PortList.shortName(portPath)]))
            }
            aul.close()
            if aul.baud != baud { baud = aul.baud }
            let sp = SerialPort(path: portPath)
            try sp.open(baudRate: aul.baud)
            p = SimonKProgrammer(port: sp, linkerName: "ArduinoUSBLinker")
            deviceName = String(format: "ArduinoUSBLinker P%d", aul.pin)
            isFourWayBox = false
        case .atmSKTGYLinker:
            // TStk500v2Interface: Afro/Turnigy USB linker, fixed 9600 baud
            let sp = SerialPort(path: portPath)
            try sp.open(baudRate: baud)
            p = SimonKProgrammer(port: sp, linkerName: "Afro/Turnigy USB Linker")
            deviceName = "USB Linker"
            isFourWayBox = false
        default:
            throw ProgrammerError.notSupported("\(type.caption) is not available in this version.")
        }
        programmer = p
        escCount = p.escCount
        device = nil
    }

    func disconnect() {
        programmer?.disconnect()
        programmer = nil
        device = nil
        escCount = 0
        deviceName = ""
    }
}

/// SiLabs ToolStick / USB Debug Adapter (TSiLabsSiUtils, SiUtil.dll replacement).
final class ToolstickIntf {
    var programmer: ToolstickProgrammer?
    var device: DeviceInfo?
    var serial = ""
    var connected: Bool { programmer?.isConnected ?? false }
    var targetConnected: Bool { connected && device != nil }
    var deviceName: String { serial.isEmpty ? "ToolStick" : serial }

    static func adapters() -> [String] { ToolstickHID.list().map { $0.serial.isEmpty ? $0.product : $0.serial } }

    func connect() throws {
        let p = try ToolstickProgrammer.open(serial: serial.isEmpty ? nil : serial)
        programmer = p
    }

    func disconnect() {
        programmer?.disconnect()
        programmer = nil
        device = nil
    }
}

/// AVRDude ISP interface (TAVRDude).
final class AVRDudeIntf {
    struct Programmer { let id: String; let desc: String; let portType: Int }   // portType: 1 LPT, 2 COM, 3 USB

    /// Programmer list of AVRDudeProg.ini (BLHeliSuite\Interfaces\AVRDude).
    static let programmers: [Programmer] = [
        Programmer(id: "usbasp", desc: "USBasp, http://www.fischl.de/usbasp/", portType: 3),
        Programmer(id: "arduino", desc: "Arduino", portType: 2),
        Programmer(id: "avrisp", desc: "Atmel AVR ISP / ArduinoISP", portType: 2),
        Programmer(id: "stk500v1", desc: "Atmel STK500 Version 1.x firmware", portType: 2),
        Programmer(id: "stk500v2", desc: "Atmel STK500 Version 2.x firmware", portType: 2),
        Programmer(id: "avrispmkII", desc: "Atmel AVR ISP mkII", portType: 3),
        Programmer(id: "usbtiny", desc: "USBtiny simple USB programmer", portType: 3),
        Programmer(id: "dragon_isp", desc: "Atmel AVR Dragon in ISP mode", portType: 3),
        Programmer(id: "jtag2isp", desc: "Atmel JTAG ICE mkII in ISP mode", portType: 3),
        Programmer(id: "buspirate", desc: "The Bus Pirate", portType: 2),
    ]

    static var programmerNames: [String] { programmers.map { "\($0.id) [\($0.desc)]" } }

    var programmer = "usbasp"
    var portType = 3
    var port = ""
    var baud = 19200
    var isp: ISPProgrammer?
    /// Lock bits of the target read via ISP (memory locked).
    var lockedBits = false
    var device: DeviceInfo?
    var connected: Bool { isp != nil }
    /// TAVRDude+0x38: programming through a bootloader (Arduino) – fuses cannot be accessed.
    var bootloaderMode: Bool { programmer == "arduino" }
    var targetConnected: Bool { device != nil }

    func connect() throws {
        guard let a = AVRDude() else { throw AVRDudeError.notInstalled }
        let t = AVRDudeProgrammerType.common.first { $0.name == programmer }
            ?? AVRDudeProgrammerType(name: programmer, description: programmer, type: programmer, serial: portType == 2, baud: baud)
        isp = ISPProgrammer(avrdude: a, programmer: t, port: portType == 2 ? port : nil, baud: portType == 2 ? baud : nil)
    }

    func disconnect() {
        isp?.disconnect()
        isp = nil
        device = nil
    }
}
