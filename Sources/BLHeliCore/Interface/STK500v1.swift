import Foundation

public enum STK500Error: Error, LocalizedError {
    case noSync
    case unexpectedAnswer(String)
    case signatureMismatch(expected: UInt32, found: UInt32)
    case verifyFailed(Int)

    public var errorDescription: String? {
        switch self {
        case .noSync:
            return "The Arduino bootloader does not answer.\nCheck the board type (bootloader baud rate) and the serial port, then try again (press reset on the board if needed)."
        case .unexpectedAnswer(let s): return "Unexpected answer from the Arduino bootloader (\(s))."
        case .signatureMismatch(let e, let f):
            return String(format: "The board has another MCU than expected (expected signature 0x%06X, found 0x%06X). Please check the board selection.", e, f)
        case .verifyFailed(let a): return String(format: "Verify failed at address 0x%04X.", a)
        }
    }
}

/// STK500 v1 protocol as spoken by the Arduino bootloaders (optiboot / ATmegaBOOT) – used to
/// flash the 4-way interface firmware onto an Arduino without avrdude.
public final class STK500v1 {
    static let inSync: UInt8 = 0x14, ok: UInt8 = 0x10, eop: UInt8 = 0x20

    public let port: SerialPort

    public init(port: SerialPort) { self.port = port }

    /// Auto-reset via DTR/RTS (like avrdude's arduino programmer).
    public func resetBoard() {
        port.setDTR(false); port.setRTS(false)
        sleepSeconds(0.25)
        port.setDTR(true); port.setRTS(true)
        sleepSeconds(0.05)
        port.discardInput()
    }

    func command(_ bytes: [UInt8], answer: Int = 0, timeout: TimeInterval = 1.0) throws -> [UInt8] {
        try port.write(bytes + [STK500v1.eop])
        let r = try port.readExactly(answer + 2, timeout: timeout)
        guard r.count == answer + 2, r.first == STK500v1.inSync, r.last == STK500v1.ok else {
            throw STK500Error.unexpectedAnswer(r.hexString)
        }
        return Array(r.dropFirst().dropLast())
    }

    public func sync() throws {
        for attempt in 0..<12 {
            port.discardInput()
            try port.write([0x30, STK500v1.eop])
            let r = try port.readExactly(2, timeout: 0.25)
            if r == [STK500v1.inSync, STK500v1.ok] {
                // drain possible duplicate answers of earlier attempts
                sleepSeconds(0.05)
                port.discardInput()
                return
            }
            if attempt == 5 { resetBoard() }
        }
        throw STK500Error.noSync
    }

    public func readSignature() throws -> UInt32 {
        let s = try command([0x75], answer: 3)
        return UInt32(s[0]) << 16 | UInt32(s[1]) << 8 | UInt32(s[2])
    }

    public func enterProgramming() throws { _ = try command([0x50]) }
    public func leaveProgramming() throws { _ = try command([0x51]) }

    func loadAddress(byteAddress: Int) throws {
        let w = byteAddress / 2
        _ = try command([0x55, UInt8(w & 0xFF), UInt8((w >> 8) & 0xFF)])
    }

    func programPage(_ data: [UInt8]) throws {
        _ = try command([0x64, UInt8(data.count >> 8), UInt8(data.count & 0xFF), 0x46] + data, timeout: 2.0)
    }

    func readPage(_ n: Int) throws -> [UInt8] {
        try command([0x74, UInt8(n >> 8), UInt8(n & 0xFF), 0x46], answer: n, timeout: 2.0)
    }

    /// Complete flash of an Arduino board. `expectedSignature` guards against a wrong board choice.
    public func flash(_ image: MemoryImage, pageSize: Int, expectedSignature: UInt32?, verify: Bool = true,
                      progress: ProgressHandler? = nil) throws {
        resetBoard()
        try sync()
        let sig = try readSignature()
        Log.info(String(format: "Arduino bootloader: signature 0x%06X", sig))
        if let e = expectedSignature, e != sig {
            // ATmega328 vs 328P and 168 vs 168P share the firmware
            let compatible: Set<UInt32> = [0x1E950F, 0x1E9514, 0x1E9406, 0x1E940B]
            if !(compatible.contains(e) && compatible.contains(sig) && (e >> 8) == (sig >> 8)) {
                throw STK500Error.signatureMismatch(expected: e, found: sig)
            }
        }
        try enterProgramming()
        guard let hi = image.highestAddress else { return }
        let end = (hi / pageSize + 1) * pageSize
        let total = verify ? 2 * end : end
        var addr = 0
        while addr < end {
            let page = image.read(addr, pageSize)
            if page.contains(where: { $0 != 0xFF }) {
                try loadAddress(byteAddress: addr)
                try programPage(page)
            }
            addr += pageSize
            progress?(addr, total)
        }
        if verify {
            addr = 0
            while addr < end {
                let expected = image.read(addr, pageSize)
                if expected.contains(where: { $0 != 0xFF }) {
                    try loadAddress(byteAddress: addr)
                    let got = try readPage(pageSize)
                    if let i = zip(got, expected).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset {
                        throw STK500Error.verifyFailed(addr + i)
                    }
                }
                addr += pageSize
                progress?(end + addr, total)
            }
        }
        try leaveProgramming()
    }
}
