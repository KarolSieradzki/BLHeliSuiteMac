import Foundation

/// An ESC with BLHeli bootloader on a USB-UART 1-wire bridge: every byte is echoed, the bootloader
/// answers boot init ("BLHeli"/"BOOT" + CRC) and the commands of the BLHeli bootloader protocol.
public final class SimulatedBLHeliBootloaderLine {
    public let channel: ByteChannel
    public let esc: SimulatedESC
    public let echo: Bool
    public var bootSign: String
    public var bootMessage: [UInt8] = Array("471".utf8)
    private var running = false
    private var buf: [UInt8] = []
    private var connected = false
    private var address = 0
    private var buffer: [UInt8] = []
    private var expectData = 0
    private let queue = DispatchQueue(label: "sim.blheli.bootloader")

    public init(channel: ByteChannel, esc: SimulatedESC, echo: Bool = true, bootSign: String = "BLHeli") {
        self.channel = channel
        self.esc = esc
        self.echo = echo
        self.bootSign = bootSign
    }

    public func start() {
        running = true
        queue.async { [weak self] in
            while let s = self, s.running {
                guard let d = try? s.channel.read(maxCount: 512, timeout: 0.05), !d.isEmpty else { continue }
                if s.echo { try? s.channel.write(d) }
                s.buf += d
                s.process()
            }
        }
    }

    public func stop() { running = false }

    func reply(_ b: [UInt8]) { try? channel.write(b) }

    func crcOK(_ f: [UInt8]) -> Bool {
        guard f.count >= 3 else { return false }
        let c = Checksum.crc16BLHeli(f.dropLast(2))
        return f[f.count - 2] == UInt8(c & 0xFF) && f[f.count - 1] == UInt8(c >> 8)
    }

    private func process() {
        while true {
            if !connected {
                let sign = Array(bootSign.utf8)
                let c = Checksum.crc16BLHeli(sign)
                let pattern = sign + [UInt8(c & 0xFF), UInt8(c >> 8)]
                guard let r = find(pattern) else {
                    if buf.count > 64 { buf.removeFirst(buf.count - 64) }
                    return
                }
                buf.removeFirst(r + pattern.count)
                guard esc.responding else { continue }
                connected = true
                let sig = esc.mcu.bootSignature
                reply(bootMessage + [esc.bootVersion, UInt8(sig >> 8), UInt8(sig & 0xFF), 0x06, UInt8((esc.mcu.flashSize - esc.bootloaderStart) / max(esc.mcu.pageSize, 1)), 0x30])
                continue
            }
            if expectData > 0 {
                guard buf.count >= expectData + 2 else { return }
                let f = Array(buf[0..<(expectData + 2)])
                buf.removeFirst(expectData + 2)
                if crcOK(f) { buffer = Array(f.dropLast(2)); reply([0x30]) } else { reply([0xC2]) }
                expectData = 0
                continue
            }
            guard let cmd = buf.first else { return }
            let len = cmd >= 0xFE ? 6 : 4
            guard buf.count >= len else { return }
            let f = Array(buf[0..<len])
            buf.removeFirst(len)
            guard crcOK(f) else { reply([0xC2]); continue }
            handle(f)
        }
    }

    private func find(_ p: [UInt8]) -> Int? {
        guard buf.count >= p.count else { return nil }
        for i in 0...(buf.count - p.count) where Array(buf[i..<(i + p.count)]) == p { return i }
        return nil
    }

    private func dataAnswer(_ d: [UInt8]?) {
        guard let d else { reply([0xC5]); return }
        let c = Checksum.crc16BLHeli(d)
        reply(d + [UInt8(c & 0xFF), UInt8(c >> 8), 0x30])
    }

    private func handle(_ f: [UInt8]) {
        let n = f[1] == 0 ? 256 : Int(f[1])
        switch f[0] {
        case 0xFF:
            address = Int(f[2]) << 8 | Int(f[3])
            reply([0x30])
        case 0xFE:
            let count = Int(f[2]) << 8 | Int(f[3])
            expectData = count == 0 ? 256 : count
        case 0x00:
            connected = false
        case 0x01:
            reply([esc.blWrite(address, buffer) ? 0x30 : 0xC5])
        case 0x02:
            reply([esc.blErasePage(address / esc.mcu.pageSize) ? 0x30 : 0xC5])
        case 0x03:
            if esc.family == .silabs {
                dataAnswer(esc.blRead(address, n))
            } else {
                reply([esc.blRead(address, buffer.count) == buffer ? 0x30 : 0xC0])
            }
        case 0x04:
            dataAnswer(esc.eepromRead(address, n))
        case 0x05:
            reply([esc.eepromWrite(address, buffer) ? 0x30 : 0xC5])
        case 0x07:
            dataAnswer(esc.blRead(address, n))
        default:
            reply([0xC1])
        }
    }
}

/// SimonK bootloader behind an ArduinoUSBLinker / Afro USB linker (STK500 v2 framing, no echo).
/// With `aulSketch` the line also answers the "$M<…" settings commands of the ArduinoUSBLinker sketch.
public final class SimulatedSimonKBootloader {
    public let channel: ByteChannel
    public let esc: SimulatedESC
    public var aulSketch: Bool
    public var aulPin = 18, aulBitTime = 136, aulBaud = 19200
    private var running = false
    private var buf: [UInt8] = []
    private var address = 0
    private let queue = DispatchQueue(label: "sim.simonk")

    public init(channel: ByteChannel, esc: SimulatedESC, aulSketch: Bool = false) {
        self.channel = channel
        self.esc = esc
        self.aulSketch = aulSketch
    }

    public func start() {
        running = true
        queue.async { [weak self] in
            while let s = self, s.running {
                guard let d = try? s.channel.read(maxCount: 512, timeout: 0.05), !d.isEmpty else { continue }
                s.buf += d
                s.process()
            }
        }
    }

    public func stop() { running = false }

    private func process() {
        while !buf.isEmpty {
            if aulSketch, buf.starts(with: Array("$M<".utf8)) {
                // the sketch collects the whole message until the serial timeout
                Thread.sleep(forTimeInterval: 0.02)
                if let more = try? channel.read(maxCount: 64, timeout: 0.01) { buf += more }
                let text = String(decoding: buf, as: UTF8.self)
                buf.removeAll()
                let arg = Int(text.dropFirst(4)) ?? 0
                var prefix = ""
                switch text.dropFirst(3).first {
                case "P": aulPin = arg
                case "B": aulBitTime = arg
                case "R": aulBaud = max(9600, arg)
                case "W": prefix = "saved:"
                default: break
                }
                try? channel.write(Array("\(prefix)P\(aulPin):B\(aulBitTime):R\(aulBaud):PINS:B0:C8:D16:\n".utf8))
                return
            }
            guard let s = buf.firstIndex(of: 0x1B) else { buf.removeAll(); return }
            if s > 0 { buf.removeFirst(s) }
            guard buf.count >= 5 else { return }
            let n = Int(buf[2]) << 8 | Int(buf[3])
            guard buf.count >= 6 + n else { return }
            let frame = Array(buf[0..<(6 + n)])
            buf.removeFirst(6 + n)
            guard frame[4] == 0x0E, frame.dropLast().reduce(0, ^) == frame.last! else { continue }
            let body = Array(frame[5..<(5 + n)])
            var answer: [UInt8]
            switch body[0] {
            case 0x01: answer = [0x01, 0x00, 8] + Array("AVRISP_2".utf8)
            case 0x10, 0x11: answer = [body[0], 0x00]
            case 0x1B:
                let sig = esc.mcu.signature
                let i = Int(body[4])
                answer = [0x1B, 0x00, UInt8((sig >> (16 - 8 * UInt32(i))) & 0xFF), 0x00]
            case 0x06:
                address = Int(body[1]) << 24 | Int(body[2]) << 16 | Int(body[3]) << 8 | Int(body[4])
                answer = [0x06, 0x00]
            case 0x13:
                let cnt = Int(body[1]) << 8 | Int(body[2])
                let ok = esc.blWrite(address * 2, Array(body[10..<(10 + cnt)]))
                address += cnt / 2
                answer = [0x13, ok ? 0x00 : 0xC0]
            case 0x14:
                let cnt = Int(body[1]) << 8 | Int(body[2])
                if let d = esc.blRead(address * 2, cnt) { answer = [0x14, 0x00] + d + [0x00]; address += cnt / 2 } else { answer = [0x14, 0xC0] }
            case 0x15:
                let cnt = Int(body[1]) << 8 | Int(body[2])
                answer = [0x15, esc.eepromWrite(address, Array(body[10..<(10 + cnt)])) ? 0x00 : 0xC0]
                address += cnt
            case 0x16:
                let cnt = Int(body[1]) << 8 | Int(body[2])
                if let d = esc.eepromRead(address, cnt) { answer = [0x16, 0x00] + d + [0x00]; address += cnt } else { answer = [0x16, 0xC0] }
            default:
                answer = [body[0], 0xC9]
            }
            var out: [UInt8] = [0x1B, frame[1], UInt8(answer.count >> 8), UInt8(answer.count & 0xFF), 0x0E] + answer
            out.append(out.reduce(0, ^))
            try? channel.write(out)
        }
    }
}
