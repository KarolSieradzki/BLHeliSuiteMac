import Foundation

/// Minimal optiboot (STK500 v1) model on a byte channel, for tests of the Arduino flasher.
public final class SimulatedArduinoBootloader {
    public var flash: [UInt8]
    public let signature: [UInt8]
    let channel: ByteChannel
    private var address = 0
    private var running = false
    private var buffer: [UInt8] = []

    public init(channel: ByteChannel, flashSize: Int = 0x8000, signature: [UInt8] = [0x1E, 0x95, 0x0F]) {
        self.channel = channel
        self.flash = [UInt8](repeating: 0xFF, count: flashSize)
        self.signature = signature
    }

    public func start() {
        running = true
        Thread { [weak self] in
            while let self, self.running {
                guard let c = try? self.channel.read(maxCount: 512, timeout: 0.05), !c.isEmpty else { continue }
                self.buffer += c
                self.process()
            }
        }.start()
    }

    public func stop() { running = false }

    private func ok(_ data: [UInt8] = []) { try? channel.write([0x14] + data + [0x10]) }

    private func process() {
        while let cmd = buffer.first {
            let need: Int
            switch cmd {
            case 0x30, 0x50, 0x51, 0x75: need = 2
            case 0x41: need = 3
            case 0x55: need = 4
            case 0x42: need = 22
            case 0x45: need = 7
            case 0x64, 0x74:
                guard buffer.count >= 4 else { return }
                let n = Int(buffer[1]) << 8 | Int(buffer[2])
                need = cmd == 0x64 ? 5 + n : 5
            default: buffer.removeFirst(); continue
            }
            guard buffer.count >= need else { return }
            let f = Array(buffer.prefix(need))
            buffer.removeFirst(need)
            guard f.last == 0x20 else { continue }
            switch cmd {
            case 0x30, 0x42, 0x45, 0x50, 0x51: ok()
            case 0x41: ok([0x03])
            case 0x75: ok(signature)
            case 0x55: address = (Int(f[1]) | Int(f[2]) << 8) * 2; ok()
            case 0x64:
                let n = Int(f[1]) << 8 | Int(f[2])
                for i in 0..<n where address + i < flash.count { flash[address + i] = f[4 + i] }
                ok()
            case 0x74:
                let n = Int(f[1]) << 8 | Int(f[2])
                ok(Array(flash[address..<min(flash.count, address + n)]))
            default: break
            }
        }
    }
}
