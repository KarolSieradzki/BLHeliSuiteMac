import Foundation
import SwiftUI
import AppKit
import BLHeliCore

/// State of one ESC channel after "Check" (BLHeliSuite MultipleESC indications).
enum SlotState: Equatable {
    case unchecked
    case notFound
    case ok
    case unknownFirmware   // "u": erased, SimonK or other
    case failedFlash       // "f"
    case wrongBrand        // "b"
    case modeDiffers       // "m"
    case layoutDiffers     // purple: different EEPROM layout revision
    case unsupported       // ARM etc.

    var badge: String? {
        switch self {
        case .unknownFirmware: return "u"
        case .failedFlash: return "f"
        case .wrongBrand: return "b"
        case .modeDiffers: return "m"
        default: return nil
        }
    }
}

struct ESCSlot: Identifiable, Equatable {
    let index: Int
    var state: SlotState = .unchecked
    var device: DeviceInfo?
    var settings: BLHeliSettings?
    var id: Int { index }
    var title: String { "\(index + 1)" }
}

struct AlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct ConfirmItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let destructive: Bool
    let action: () -> Void
}

@MainActor
final class AppModel: ObservableObject {
    // MARK: Preferences
    @Published var interfaceType: InterfaceType {
        didSet {
            guard oldValue != interfaceType else { return }
            UserDefaults.standard.set(interfaceType.rawValue, forKey: "interface")
            if connected { disconnect() }
            baud = interfaceType.defaultBaud
            clearWorkspace()
        }
    }
    @Published var portPath: String { didSet { UserDefaults.standard.set(portPath, forKey: "port") } }
    @Published var baud: Int
    @Published var ports: [SerialPortInfo] = []
    @Published var expertMode = UserDefaults.standard.bool(forKey: "expert") { didSet { UserDefaults.standard.set(expertMode, forKey: "expert") } }
    @Published var verifyFlash = true
    @Published var syncDirection = UserDefaults.standard.bool(forKey: "syncDirection") { didSet { UserDefaults.standard.set(syncDirection, forKey: "syncDirection") } }
    @Published var syncThrottle = (UserDefaults.standard.object(forKey: "syncThrottle") as? Bool) ?? true { didSet { UserDefaults.standard.set(syncThrottle, forKey: "syncThrottle") } }
    @Published var arduinoDelay = (UserDefaults.standard.object(forKey: "arduinoDelay") as? Double) ?? 2.0 { didSet { UserDefaults.standard.set(arduinoDelay, forKey: "arduinoDelay") } }
    @Published var protocolTrace = false { didSet { Log.shared.protocolTrace = protocolTrace } }

    // MARK: Connection
    @Published var connected = false
    @Published var connectionInfo = ""
    @Published var slots: [ESCSlot] = []
    @Published var active: Set<Int> = []

    // MARK: Workspace
    @Published var workspace: BLHeliSettings?
    @Published var original: BLHeliSettings?
    @Published var workspaceDevice: DeviceInfo?
    @Published var clipboard: BLHeliSettings?

    // MARK: Activity
    @Published var busy = false
    @Published var progress: Double = 0
    @Published var status = "Not connected"
    @Published var alert: AlertItem?
    @Published var confirm: ConfirmItem?
    @Published var log: [LogEntry] = []
    @Published var showFlashAssistant = false
    @Published var selectedTab: MainTab = .setup

    // Motors tab (MSP motor test)
    @Published var motorSessionOpen = false
    @Published var motorRunning = false
    @Published var motorValues: [Double] = Array(repeating: 1000, count: 8)
    @Published var motorCountFC = 4
    @Published var motorInfo = ""
    @Published var motorMinCommand = 1000.0
    nonisolated(unsafe) var mspPort: SerialPort?
    nonisolated(unsafe) var mspClient: MSPClient?
    var motorTimer: Timer?

    // Expert tools
    @Published var expertDump = ""

    // Make interfaces
    @Published var arduinoBoard: ArduinoBoard = ArduinoBoard.all.first { $0.tag == "Nano_328" }!
    @Published var arduinoFirmware: ArduinoBoard.InterfaceFirmware = .fourWayMulti

    // ISP (AVRDude)
    @Published var ispProgrammer: AVRDudeProgrammerType = AVRDudeProgrammerType.common[0]
    @Published var avrdudePath = UserDefaults.standard.string(forKey: "avrdudePath") ?? "" { didSet { UserDefaults.standard.set(avrdudePath, forKey: "avrdudePath") } }
    @Published var ispWriteBootloader = true
    @Published var ispWriteFuses = true

    // Toolstick: serial number of the selected adapter ("" = first one found)
    @Published var toolstickSerial = ""

    let database: FirmwareDatabase?
    let databaseError: String?

    let worker = DispatchQueue(label: "blheli.worker", qos: .userInitiated)
    /// Accessed on `worker` only.
    nonisolated(unsafe) var programmer: ESCProgrammer?
    private var keepAliveTimer: Timer?
    private var keepAliveFailures = 0

    init() {
        let it = InterfaceType(rawValue: UserDefaults.standard.string(forKey: "interface") ?? "") ?? .silabsBLBFlightController
        interfaceType = it
        baud = it.defaultBaud
        portPath = UserDefaults.standard.string(forKey: "port") ?? ""
        do {
            database = try FirmwareDatabase.shared()
            databaseError = nil
        } catch {
            database = nil
            databaseError = error.localizedDescription
        }
        Log.shared.addHandler { [weak self] entry in
            DispatchQueue.main.async {
                guard let self else { return }
                self.log.append(entry)
                if self.log.count > 5000 { self.log.removeFirst(self.log.count - 5000) }
            }
        }
        refreshPorts()
        if let e = databaseError { Log.error(e) } else if let db = database {
            Log.info("Firmware database: \(db.silabs.firmware.count) SiLabs + \(db.atmel.firmware.count) Atmel files (\(db.source))")
        }
    }

    var family: MCUFamily { interfaceType.family }
    var setupTabTitle: String { family == .silabs ? "SiLabs ESC Setup" : "Atmel ESC Setup" }

    var masterIndex: Int? { active.sorted().first }

    // MARK: Ports

    func refreshPorts() {
        ports = SerialPort.availablePorts()
        if portPath.isEmpty || !ports.contains(where: { $0.path == portPath }) {
            // Prefer USB serial devices (FC VCP, Arduino, FTDI…)
            portPath = ports.first(where: { $0.vendorID != nil })?.path ?? ports.first?.path ?? portPath
        }
    }

    // MARK: Worker helpers

    func run(_ title: String, _ body: @escaping (ESCProgrammer?) throws -> Void, done: (() -> Void)? = nil) {
        guard !busy else { return }
        busy = true
        progress = 0
        status = title
        stopKeepAlive()
        worker.async { [weak self] in
            guard let self else { return }
            var failure: Error?
            do { try body(self.programmer) } catch { failure = error }
            DispatchQueue.main.async {
                self.busy = false
                if let f = failure {
                    let msg = (f as? LocalizedError)?.errorDescription ?? "\(f)"
                    if case ProgrammerError.cancelled = f {
                        self.status = "Cancelled"
                    } else {
                        self.status = "Failed"
                        Log.error(msg)
                        self.alert = AlertItem(title: title, message: msg)
                    }
                    if f is SerialError { self.markDisconnected() }
                } else if self.status == title {
                    self.status = self.connected ? "Connected" : "Ready"
                }
                done?()
                if self.connected { self.startKeepAlive() }
            }
        }
    }

    nonisolated func setProgress(_ p: Double, _ message: String? = nil) {
        DispatchQueue.main.async {
            self.progress = p
            if let m = message { self.status = m }
        }
    }

    func cancel() {
        worker.async {} // queue barrier
        programmer?.cancelRequested = true
    }

    // MARK: Connect / disconnect

    func toggleConnection() {
        if connected { disconnect() } else { connect() }
    }

    func connect(then next: (() -> Void)? = nil) {
        guard !busy else { return }
        // The motor test keeps the FC port open (exclusive) – close it first.
        if motorSessionOpen { motorClose() }
        if interfaceType == .atmelISP { connectISP(then: next); return }
        if interfaceType == .silabsC2Toolstick { connectToolstick(then: next); return }
        guard !portPath.isEmpty else {
            alert = AlertItem(title: "Connect", message: "Please select a serial port first.")
            return
        }
        let type = interfaceType, path = portPath, baudRate = baud, delay = arduinoDelay
        run("Connecting…", { [weak self] _ in
            let p = try ProgrammerFactory.openSerial(type, portPath: path, baud: baudRate, arduinoResetDelay: delay)
            self?.programmer = p
            let count = p.escCount
            let name = p.interfaceName
            DispatchQueue.main.async {
                guard let self else { return }
                self.connected = true
                self.connectionInfo = name
                self.slots = (0..<count).map { ESCSlot(index: $0) }
                self.active = Set(0..<count)
                self.status = "Connected"
            }
        }, done: { [weak self] in
            guard let self, self.connected else { return }
            self.check(then: next)
        })
    }

    func disconnect() {
        stopKeepAlive()
        worker.async { [weak self] in
            self?.programmer?.disconnect()
            self?.programmer = nil
        }
        connected = false
        connectionInfo = ""
        status = "Disconnected"
        slots = []
        active = []
    }

    func markDisconnected() {
        stopKeepAlive()
        worker.async { [weak self] in
            self?.programmer?.disconnect()
            self?.programmer = nil
        }
        connected = false
        connectionInfo = ""
        status = "Device disconnected or connection lost…"
        slots = []
        active = []
    }

    private func startKeepAlive() {
        stopKeepAlive()
        keepAliveFailures = 0
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.keepAliveTick() }
        }
    }

    private func stopKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }

    private func keepAliveTick() {
        guard connected, !busy else { return }
        worker.async { [weak self] in
            guard let self, let p = self.programmer else { return }
            let ok = (try? p.keepAlive()) != nil
            DispatchQueue.main.async {
                if ok { self.keepAliveFailures = 0; return }
                self.keepAliveFailures += 1
                if self.keepAliveFailures >= 3 {
                    Log.warning("Interface hangs – disconnecting…")
                    self.markDisconnected()
                }
            }
        }
    }

    // MARK: Check (multi ESC)

    func check(then next: (() -> Void)? = nil) {
        guard connected else { connect(then: next); return }
        let fam = family
        let db = database
        let count = slots.count
        run("Checking ESCs…", { [weak self] p in
            guard let p else { return }
            let ops = ESCOperations(programmer: p)
            var results: [ESCSlot] = []
            for i in 0..<count {
                var slot = ESCSlot(index: i)
                do {
                    let dev = try p.selectESC(i)
                    slot.device = dev
                    if dev.family == .arm { slot.state = .unsupported }
                    else if dev.family != fam && dev.family != .unknown { slot.state = .wrongBrand }
                    else {
                        let s = try ops.readSettings(device: dev)
                        slot.settings = s
                        if s.flashFailedMarker { slot.state = .failedFlash }
                        else if (try? s.validate()) == nil { slot.state = .unknownFirmware }
                        else { slot.state = .ok }
                    }
                    Log.info("ESC #\(i + 1): \(dev.description) – \(slot.settings.map { $0.summary(database: db) } ?? "no BLHeli setup")")
                } catch ProgrammerError.escNotFound {
                    slot.state = .notFound
                    Log.info("ESC #\(i + 1): not found")
                }
                results.append(slot)
                self?.setProgress(Double(i + 1) / Double(max(count, 1)))
            }
            // master/slave compatibility
            if let master = results.first(where: { $0.state == .ok })?.settings {
                for k in results.indices where results[k].state == .ok {
                    let s = results[k].settings!
                    if s.mode != master.mode { results[k].state = .modeDiffers }
                    else if s.layoutRevision != master.layoutRevision { results[k].state = .layoutDiffers }
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.slots = results
                let usable = results.filter { $0.state == .ok || $0.state == .layoutDiffers }.map(\.index)
                self.active = Set(usable.isEmpty ? results.filter { $0.state != .notFound }.map(\.index) : usable)
                let found = results.filter { $0.state != .notFound }.count
                self.status = "Found \(found) ESC" + (found == 1 ? "" : "s")
                if found == 0 {
                    self.alert = AlertItem(title: "Check", message: "No ESC found.\nPlease check the ESC power supply (battery connected?) and signal wiring.")
                }
                if let m = self.masterIndex, let s = self.slots[m].settings, self.slots[m].state == .ok {
                    self.loadWorkspace(s, device: self.slots[m].device)
                } else if let m = self.masterIndex {
                    self.workspace = nil
                    self.original = nil
                    self.workspaceDevice = self.slots[m].device
                }
            }
        }, done: next)
    }

    // MARK: Workspace

    func loadWorkspace(_ s: BLHeliSettings, device: DeviceInfo?) {
        workspace = s
        original = s
        workspaceDevice = device
    }

    func clearWorkspace() {
        workspace = nil
        original = nil
        workspaceDevice = nil
    }

    var workspaceContext: ParamContext? {
        guard let w = workspace else { return nil }
        return w.context(database: database, firmware: database?.matchingEntry(for: w))
    }

    var workspaceModified: Bool { workspace != nil && workspace != original }

    func setValue(_ p: BLHeliParam, _ v: Int) {
        workspace?.setValue(p, v)
    }

    func undo(_ p: BLHeliParam) {
        guard let o = original else { return }
        workspace?.setValue(p, o.value(p))
    }

    func setDefault(_ p: BLHeliParam) {
        guard let ctx = workspaceContext, let d = BLHeliParamLogic.defaultValue(p, ctx) else { return }
        workspace?.setValue(p, d)
    }

    func allDefaults() {
        guard let ctx = workspaceContext else { return }
        for p in BLHeliParam.editable { if let d = BLHeliParamLogic.defaultValue(p, ctx) { workspace?.setValue(p, d) } }
    }

    func undoAll() { workspace = original }

    /// Slot is "in sync" with the master (BLHeliSuite green/gray indication).
    func inSync(_ slot: ESCSlot) -> Bool {
        guard let m = workspace, let s = slot.settings, slot.state == .ok else { return false }
        for p in BLHeliParam.editable {
            if p == .direction && !syncDirection { continue }
            if [.ppmMinThrottle, .ppmMaxThrottle, .ppmCenterThrottle].contains(p) && !syncThrottle { continue }
            if m[p] != s[p] { return false }
        }
        return true
    }

    func directionDiffers(_ slot: ESCSlot) -> Bool {
        guard let m = workspace, let s = slot.settings else { return false }
        return m[.direction] != s[.direction]
    }

    func toggleActive(_ i: Int) {
        if active.contains(i) { active.remove(i) } else { active.insert(i) }
        if let m = masterIndex, m < slots.count, let s = slots[m].settings, slots[m].state == .ok {
            if workspace == nil || original?.raw != s.raw { loadWorkspace(s, device: slots[m].device) }
        }
    }

    func selectSingle(_ i: Int) {
        active = [i]
        if i < slots.count, let s = slots[i].settings, slots[i].state == .ok { loadWorkspace(s, device: slots[i].device) }
        else if i < slots.count { workspace = nil; original = nil; workspaceDevice = slots[i].device }
    }

    // MARK: Read / write setup

    func readSetup() {
        guard connected else { connect(); return }
        guard let m = masterIndex else { alert = AlertItem(title: "Read Setup", message: "No ESC selected."); return }
        run("Reading setup…", { [weak self] p in
            guard let p else { return }
            let ops = ESCOperations(programmer: p)
            let dev = try p.selectESC(m)
            let s = try ops.readSettings(device: dev)
            DispatchQueue.main.async {
                guard let self else { return }
                if m < self.slots.count {
                    self.slots[m].device = dev
                    self.slots[m].settings = s
                }
                do {
                    try s.validate()
                    self.loadWorkspace(s, device: dev)
                    if m < self.slots.count { self.slots[m].state = s.flashFailedMarker ? .failedFlash : .ok }
                    Log.success("Read setup of ESC #\(m + 1): \(s.summary(database: self.database))")
                    if s.flashFailedMarker {
                        self.alert = AlertItem(title: "ESC #\(m + 1)", message: "Obviously an attempt to flash this ESC has failed.\nNow the memory content is most likely corrupted, so do not try to use this ESC.\n\nPlease flash it again with BLHeli (Flash BLHeli).")
                    }
                } catch {
                    self.workspace = nil
                    self.original = nil
                    self.workspaceDevice = dev
                    if m < self.slots.count { self.slots[m].state = .unknownFirmware }
                    self.alert = AlertItem(title: "ESC #\(m + 1)", message: ((error as? LocalizedError)?.errorDescription ?? "\(error)") +
                        "\n\nThe ESC seems to be erased or flashed with SimonK or other firmware.\nUse \"Flash BLHeli\" to flash it with BLHeli firmware.")
                }
            }
        })
    }

    func writeSetup() {
        guard connected, let ws = workspace else { return }
        guard let m = masterIndex else { return }
        let targets = active.sorted()
        let syncDir = syncDirection, syncThr = syncThrottle
        let slotsCopy = slots
        let db = database
        run("Writing setup…", { [weak self] p in
            guard let p else { return }
            let ops = ESCOperations(programmer: p)
            ops.verify = true
            var written: [(Int, BLHeliSettings)] = []
            for (n, i) in targets.enumerated() {
                let dev = try p.selectESC(i)
                var target = ws
                if i != m {
                    // Slave: keep its own name, optionally direction and throttle range.
                    let own = i < slotsCopy.count ? slotsCopy[i].settings : nil
                    if let own, (try? own.validate()) != nil {
                        if own.mode != ws.mode {
                            Log.warning("ESC #\(i + 1): ESC mode differs – skipped"); continue
                        }
                        if own.layoutRevision != ws.layoutRevision {
                            // different EEPROM layout: translate the workspace values into the slave's layout
                            if let t = try? SettingsTranslator(copyName: false).translate(from: ws, oldContext: ws.context(database: db), to: own, newContext: own.context(database: db)) {
                                target = t
                            } else { Log.warning("ESC #\(i + 1): parameters cannot be transformed – skipped"); continue }
                        } else {
                            target.raw.replaceSubrange(0x40..<0x60, with: own.raw[0x40..<0x60]) // layout + MCU of the slave
                        }
                        target.name = own.name
                        if !syncDir { target[.direction] = own[.direction] }
                        if !syncThr {
                            for q in [BLHeliParam.ppmMinThrottle, .ppmMaxThrottle, .ppmCenterThrottle] { target[q] = own[q] }
                        }
                    } else {
                        Log.warning("ESC #\(i + 1): no valid BLHeli setup – skipped"); continue
                    }
                }
                try ops.writeSettings(target, device: dev)
                written.append((i, target))
                Log.success("Setup written to ESC #\(i + 1)")
                self?.setProgress(Double(n + 1) / Double(targets.count))
            }
            DispatchQueue.main.async {
                guard let self else { return }
                for (i, s) in written where i < self.slots.count { self.slots[i].settings = s; self.slots[i].state = .ok }
                if let s = written.first(where: { $0.0 == m })?.1 { self.loadWorkspace(s, device: self.workspaceDevice) }
            }
        })
    }

    // MARK: Flash

    func flashBLHeli() {
        guard database != nil else { alert = AlertItem(title: "Flash BLHeli", message: databaseError ?? "No firmware database"); return }
        guard connected else { connect(then: { [weak self] in self?.flashBLHeli() }); return }
        guard masterIndex != nil else { alert = AlertItem(title: "Flash BLHeli", message: "No ESC selected."); return }
        showFlashAssistant = true
    }

    /// Flashes all active ESCs with a built-in file (each ESC keeps its own settings).
    func flash(entry: FirmwareEntry, keepSettings: Bool) {
        guard let db = database else { return }
        let targets = active.sorted()
        let slotsCopy = slots
        let verify = verifyFlash
        let ispBoot = ispWriteBootloader, ispFuses = ispWriteFuses
        run("Flashing…", { [weak self] p in
            guard let p else { return }
            let ops = ESCOperations(programmer: p)
            ops.verify = verify
            for (n, i) in targets.enumerated() {
                ops.onProgress = { pr in self?.setProgress((Double(n) + pr.fraction) / Double(targets.count), "ESC #\(i + 1): \(pr.message)") }
                let dev = try p.selectESC(i)
                let cur = (try? ops.readSettings(device: dev)) ?? (i < slotsCopy.count ? slotsCopy[i].settings : nil)
                var r = FirmwareSelection.makePlan(db, entry: entry, current: keepSettings ? cur : nil,
                                                   translator: SettingsTranslator())
                if dev.isISP {
                    let extras = FirmwareSelection.ispExtras(db, entry: entry)
                    if ispBoot { r.plan.ispBootloader = extras.bootloader; if let n = extras.bootloaderName { Log.info("Adding bootloader \(n)") } }
                    if ispFuses { r.plan.ispFuses = extras.fuses }
                }
                if let w = r.warning { Log.warning("ESC #\(i + 1): \(w)") }
                Log.info("Flashing ESC #\(i + 1) with \(r.plan.title)")
                let t0 = Date()
                try ops.flash(r.plan, device: dev, currentSettings: cur)
                Log.success(String(format: "ESC #%d: Flashed %@ successfully in %.2f s", i + 1, r.plan.title, Date().timeIntervalSince(t0)))
            }
        }, done: { [weak self] in
            guard let self, self.connected else { return }
            self.check()
        })
    }

    func flashOther() {
        guard connected else { connect(then: { [weak self] in self?.flashOther() }); return }
        let panel = NSOpenPanel()
        panel.title = "Flash Other – select a firmware file"
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.message = "Intel HEX file (*.hex). For Atmel the matching *.eep file is used automatically."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        flash(fileURL: url)
    }

    func flash(fileURL url: URL) {
        let eep = url.deletingPathExtension().appendingPathExtension("eep")
        let eepURL = FileManager.default.fileExists(atPath: eep.path) ? eep : nil
        let targets = active.sorted()
        let db = database
        let verify = verifyFlash
        confirm = ConfirmItem(title: "Flash Other",
                              message: "Do you want to flash ESC \(targets.map { "#\($0 + 1)" }.joined(separator: ", ")) with\n\(url.lastPathComponent)\(eepURL != nil ? " + .eep" : "")?\n\nFlashing an ESC with an inappropriate file may cause severe damage!",
                              destructive: true) { [weak self] in
            self?.run("Flashing…", { p in
                guard let p else { return }
                let ops = ESCOperations(programmer: p)
                ops.verify = verify
                for (n, i) in targets.enumerated() {
                    ops.onProgress = { pr in self?.setProgress((Double(n) + pr.fraction) / Double(targets.count), "ESC #\(i + 1): \(pr.message)") }
                    let dev = try p.selectESC(i)
                    let cur = try? ops.readSettings(device: dev)
                    let r = try FirmwareSelection.makePlan(hexURL: url, eepURL: eepURL, current: cur, db: db)
                    if let w = r.warning { Log.warning(w) }
                    try ops.flash(r.plan, device: dev, currentSettings: cur)
                    Log.success("ESC #\(i + 1): Flashed \(url.lastPathComponent)")
                }
            }, done: {
                guard let self, self.connected else { return }
                self.check()
            })
        }
    }

    // MARK: Files

    func saveSetupToFile() {
        guard let ws = workspace else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "BLHeli_\(ws.layoutName)_\(ws.revisionString).ini"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SetupFile.write(ws, to: url)
            Log.success("Setup saved to \(url.path)")
        } catch { alert = AlertItem(title: "Save Setup", message: error.localizedDescription) }
    }

    func loadSetupFromFile() {
        guard var ws = workspace else {
            alert = AlertItem(title: "Read Setup from file", message: "Read the setup of an ESC first – the file values are applied to it.")
            return
        }
        let panel = NSOpenPanel()
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let applied = try SetupFile.apply(url: url, to: &ws, database: database)
            workspace = ws
            Log.info("Loaded \(applied) values from \(url.lastPathComponent) – press Write Setup to store them")
        } catch { alert = AlertItem(title: "Read Setup from file", message: error.localizedDescription) }
    }

    func copySettings() { clipboard = workspace }

    func pasteSettings() {
        guard let c = clipboard, var ws = workspace else { return }
        for p in BLHeliParam.editable {
            if p == .direction && !syncDirection { continue }
            if [.ppmMinThrottle, .ppmMaxThrottle, .ppmCenterThrottle].contains(p) && !syncThrottle { continue }
            if let ctx = workspaceContext, BLHeliParamLogic.isValid(p, value: c.value(p), ctx) { ws[p] = c[p] }
        }
        workspace = ws
    }

    // MARK: Expert tools

    func restartESC() {
        guard connected, let m = masterIndex else { return }
        run("Restarting ESC…", { p in try p?.resetESC(m) })
    }

    func dumpFlash() {
        guard connected, let m = masterIndex else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ESC\(m + 1)_flash.hex"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run("Reading flash…", { [weak self] p in
            guard let p else { return }
            let ops = ESCOperations(programmer: p)
            ops.onProgress = { pr in self?.setProgress(pr.fraction, pr.message) }
            let dev = try p.selectESC(m)
            let data = try ops.dumpFlash(device: dev)
            try MemoryImage(contiguous: data).intelHex().write(to: url, atomically: true, encoding: .ascii)
            Log.success("Flash of ESC #\(m + 1) saved to \(url.path)")
        })
    }

    func eraseChip() {
        guard connected, let m = masterIndex else { return }
        confirm = ConfirmItem(title: "Erase chip", message: "Erase the complete flash memory of ESC #\(m + 1)? The ESC needs a full flash (C2/ISP) afterwards.", destructive: true) { [weak self] in
            self?.run("Erasing…", { p in
                guard let p else { return }
                _ = try p.selectESC(m)
                try p.eraseChip()
                Log.success("ESC #\(m + 1) erased")
            })
        }
    }

    // MARK: Log

    func clearLog() { log.removeAll() }

    func copyLog() {
        let text = log.map { "\($0.date.formatted(date: .omitted, time: .standard)) \($0.message)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

enum MainTab: Hashable {
    case setup, overview, motors, interfaces, expert, log
}
