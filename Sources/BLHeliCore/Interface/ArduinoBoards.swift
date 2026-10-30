import Foundation

/// Arduino board table of BLHeliSuite (0x68FB44: name, file tag, avrdude part, MHz, baud, programmer).
public struct ArduinoBoard: Identifiable, Hashable, Sendable {
    public var id: String { tag }
    public let name: String
    public let tag: String
    public let part: String
    public let mhz: Int
    public let baud: Int
    public let programmer: String

    public var avrSignature: UInt32? {
        switch part {
        case "m328p": return 0x1E950F
        case "m168": return 0x1E9406
        case "m8": return 0x1E9307
        case "m2560": return 0x1E9801
        case "m1280": return 0x1E9703
        case "atmega32u4": return 0x1E9587
        default: return nil
        }
    }

    public var pageSize: Int {
        switch part {
        case "m8": return 64
        case "m2560", "m1280": return 256
        default: return 128
        }
    }

    /// Boards that can be flashed natively (STK500v1 "arduino" bootloader).
    public var nativeFlashSupported: Bool { programmer == "arduino" }

    public static let all: [ArduinoBoard] = [
        ArduinoBoard(name: "Uno w/ ATmega328", tag: "Uno", part: "m328p", mhz: 16, baud: 115200, programmer: "arduino"),
        ArduinoBoard(name: "Duemilanove w/ ATmega328", tag: "Due_328", part: "m328p", mhz: 16, baud: 57600, programmer: "arduino"),
        ArduinoBoard(name: "Diecimila or Duemilanove w/ ATmega168", tag: "Dieci_Due_168", part: "m168", mhz: 16, baud: 19200, programmer: "arduino"),
        ArduinoBoard(name: "Nano w/ ATmega328", tag: "Nano_328", part: "m328p", mhz: 16, baud: 57600, programmer: "arduino"),
        ArduinoBoard(name: "Nano w/ ATmega328 (new bootloader)", tag: "Nano_328_new", part: "m328p", mhz: 16, baud: 115200, programmer: "arduino"),
        ArduinoBoard(name: "Nano w/ ATmega168", tag: "Nano_168", part: "m168", mhz: 16, baud: 19200, programmer: "arduino"),
        ArduinoBoard(name: "Mega 2560 or Mega ADK w/ ATmega2560", tag: "Mega_2560_ADK", part: "m2560", mhz: 16, baud: 115200, programmer: "wiring"),
        ArduinoBoard(name: "Mega (ATmega1280)", tag: "Mega_1280", part: "m1280", mhz: 16, baud: 57600, programmer: "arduino"),
        ArduinoBoard(name: "Leonardo w/ ATmega32u4", tag: "Leonardo", part: "atmega32u4", mhz: 16, baud: 57600, programmer: "avr109"),
        ArduinoBoard(name: "Micro w/ ATmega32u4", tag: "Micro", part: "atmega32u4", mhz: 16, baud: 57600, programmer: "avr109"),
        ArduinoBoard(name: "Mini w/ ATmega328", tag: "Mini_328", part: "m328p", mhz: 16, baud: 115200, programmer: "arduino"),
        ArduinoBoard(name: "Mini w/ ATmega168", tag: "Mini_168", part: "m168", mhz: 16, baud: 19200, programmer: "arduino"),
        ArduinoBoard(name: "Ethernet w/ ATmega328", tag: "Ethernet", part: "m328p", mhz: 16, baud: 115200, programmer: "arduino"),
        ArduinoBoard(name: "Fio w/ ATmega328", tag: "Fio", part: "m328p", mhz: 8, baud: 57600, programmer: "arduino"),
        ArduinoBoard(name: "BT w/ ATmega328", tag: "BT_328", part: "m328p", mhz: 16, baud: 19200, programmer: "arduino"),
        ArduinoBoard(name: "BT w/ ATmega168", tag: "BT_168", part: "m168", mhz: 16, baud: 19200, programmer: "arduino"),
        ArduinoBoard(name: "LilyPad w/ ATmega328", tag: "LilyPad_328", part: "m328p", mhz: 8, baud: 57600, programmer: "arduino"),
        ArduinoBoard(name: "LilyPad w/ ATmega168", tag: "LilyPad_168", part: "m168", mhz: 8, baud: 19200, programmer: "arduino"),
        ArduinoBoard(name: "Pro or Pro Mini (5V, 16 MHz) w/ ATmega328", tag: "ProMini_328_16", part: "m328p", mhz: 16, baud: 57600, programmer: "arduino"),
        ArduinoBoard(name: "Pro or Pro Mini (5V, 16 MHz) w/ ATmega168", tag: "ProMini_168_16", part: "m168", mhz: 16, baud: 19200, programmer: "arduino"),
        ArduinoBoard(name: "Pro or Pro Mini (3.3V, 8 MHz) w/ ATmega328", tag: "ProMini_328_8", part: "m328p", mhz: 8, baud: 57600, programmer: "arduino"),
        ArduinoBoard(name: "Pro or Pro Mini (3.3V, 8 MHz) w/ ATmega168", tag: "ProMini_168_8", part: "m168", mhz: 8, baud: 19200, programmer: "arduino"),
        ArduinoBoard(name: "NG or older w/ ATmega168", tag: "NG_168", part: "m168", mhz: 16, baud: 19200, programmer: "arduino"),
        ArduinoBoard(name: "NG or older w/ ATmega8", tag: "NG-m8", part: "m8", mhz: 16, baud: 19200, programmer: "arduino"),
    ]

    /// Firmware kinds offered in "Make interfaces".
    public enum InterfaceFirmware: String, CaseIterable, Identifiable, Sendable {
        case fourWayMulti = "4way-interface (Multi ESC, D3…D10)"
        case fourWaySingle = "4way-interface (single ESC, D11/D12)"
        case fourWayPD3PD2 = "4way-interface (single ESC, D3/D2 – Nano)"
        case blheliBootloader = "BLHeli bootloader 1-wire interface"
        case usbLinker = "ArduinoUSBLinker (SimonK bootloader)"
        case arduinoISP = "ArduinoISP programmer"

        public var id: String { rawValue }
    }

    /// Relative path below the Interfaces folder of the hex file for this board.
    public func firmwarePath(_ kind: InterfaceFirmware) -> String? {
        let t = tag == "Nano_328_new" ? "Nano_328" : tag
        switch kind {
        case .fourWayMulti, .fourWaySingle, .fourWayPD3PD2:
            let pins: String
            switch kind {
            case .fourWayMulti: pins = "MULTI"
            case .fourWaySingle: pins = part == "m2560" ? "PB2PB3" : "PB3PB4"
            default: pins = "PD3PD2"
            }
            let prefix: String
            switch (part, mhz, t) {
            case (_, _, "Nano_328"): prefix = "4wArduino_Nano__16"
            case ("m328p", 16, _): prefix = "4wArduino_m328P_16"
            case ("m328p", 8, _): prefix = "4wArduino_m328P__8"
            case ("m168", 16, _): prefix = "4wArduino_m168__16"
            case ("m168", 8, _): prefix = "4wArduino_m168___8"
            case ("m2560", _, _): prefix = "4wArduino_m2560_16"
            case ("m1280", _, _): prefix = "4wArduino_m1280_16"
            default: return nil
            }
            if kind == .fourWayPD3PD2 && t != "Nano_328" { return nil }
            return "Arduino4w-if/\(prefix)_\(pins)v20005.hex"
        case .blheliBootloader:
            return "Arduino1Wire/Arduino1Wire_\(t).hex"
        case .usbLinker:
            return "ArduinoUSBLinker/ArduinoUSBLinker_\(t.replacingOccurrences(of: "-", with: "_")).hex"
        case .arduinoISP:
            return "ArduinoISP/ArduinoISP4m5_\(t.replacingOccurrences(of: "-", with: "_")).hex"
        }
    }

    /// Resolves the firmware file inside `folder` (BLHeliSuite uses a few irregular names).
    public func firmwareURL(_ kind: InterfaceFirmware, in folder: URL) -> URL? {
        guard let rel = firmwarePath(kind) else { return nil }
        let url = folder.appendingPathComponent(rel)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        // "ArduinoUSBLinker._Nano_168.hex" style names
        let alt = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent.replacingOccurrences(of: "_", with: "._", options: [], range: url.lastPathComponent.range(of: "_")))
        if FileManager.default.fileExists(atPath: alt.path) { return alt }
        return nil
    }

    /// Folder with the interface firmware files (bundled "Interfaces" or the original BLHeliSuite folder).
    public static func interfacesFolder() -> URL? {
        var candidates: [URL] = []
        if let r = Bundle.main.resourceURL { candidates.append(r.appendingPathComponent("Interfaces")) }
        var d = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            candidates.append(d.appendingPathComponent("Resources/Interfaces"))
            candidates.append(d.appendingPathComponent("BLHeliSuite/Interfaces"))
            d = d.deletingLastPathComponent()
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
