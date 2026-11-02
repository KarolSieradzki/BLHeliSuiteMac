import AppKit

/// Decoded Windows bitmap (top-down RGBA).
public struct RGBABitmap {
    public var width: Int
    public var height: Int
    public var pixels: [UInt8]
    public var hasAlpha: Bool

    public func pixel(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let i = (y * width + x) * 4
        return (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
    }

    public func crop(_ x0: Int, _ y0: Int, _ w: Int, _ h: Int) -> RGBABitmap {
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h where y0 + y < height {
            for x in 0..<w where x0 + x < width {
                let s = ((y0 + y) * width + x0 + x) * 4, d = (y * w + x) * 4
                out[d] = pixels[s]; out[d + 1] = pixels[s + 1]; out[d + 2] = pixels[s + 2]; out[d + 3] = pixels[s + 3]
            }
        }
        return RGBABitmap(width: w, height: h, pixels: out, hasAlpha: hasAlpha)
    }

    /// VCL convention: the bottom-left pixel colour is transparent.
    public func keyedTransparent(_ key: (UInt8, UInt8, UInt8)? = nil) -> RGBABitmap {
        var b = self
        let k = key ?? { let p = pixel(0, height - 1); return (p.0, p.1, p.2) }()
        for i in stride(from: 0, to: b.pixels.count, by: 4) {
            let match = b.pixels[i] == k.0 && b.pixels[i + 1] == k.1 && b.pixels[i + 2] == k.2
            b.pixels[i + 3] = match ? 0 : 255
        }
        b.hasAlpha = true
        return b
    }

    public func opaque() -> RGBABitmap {
        var b = self
        for i in stride(from: 3, to: b.pixels.count, by: 4) { b.pixels[i] = 255 }
        return b
    }

    public var image: NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: width * 4, bitsPerPixel: 32)!
        let dst = rep.bitmapData!
        // premultiply
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = Int(pixels[i + 3])
            dst[i] = UInt8(Int(pixels[i]) * a / 255)
            dst[i + 1] = UInt8(Int(pixels[i + 1]) * a / 255)
            dst[i + 2] = UInt8(Int(pixels[i + 2]) * a / 255)
            dst[i + 3] = UInt8(a)
        }
        let img = NSImage(size: NSSize(width: width, height: height))
        img.addRepresentation(rep)
        return img
    }

    /// Grayed glyph as drawn by VCL for disabled buttons (single glyph images).
    public var disabledImage: NSImage {
        var b = self
        for i in stride(from: 0, to: b.pixels.count, by: 4) where b.pixels[i + 3] > 0 {
            let l = (Int(b.pixels[i]) * 30 + Int(b.pixels[i + 1]) * 59 + Int(b.pixels[i + 2]) * 11) / 100
            let v = UInt8(min(255, 160 + l / 3))
            b.pixels[i] = v; b.pixels[i + 1] = v; b.pixels[i + 2] = v
        }
        return b.image
    }
}

public enum DIB {
    static func u16(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
    static func u32(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 }
    static func i32(_ b: [UInt8], _ o: Int) -> Int { Int(Int32(truncatingIfNeeded: u32(b, o))) }

    /// Decodes a BMP ("BM" file header) or a bare DIB (BITMAPINFOHEADER) at `off`.
    public static func decode(_ b: [UInt8], at off: Int, fileHeader: Bool = true) -> RGBABitmap? {
        var hdr = off
        var pix: Int?
        if fileHeader {
            guard off + 14 < b.count, b[off] == 0x42, b[off + 1] == 0x4D else { return nil }
            pix = off + u32(b, off + 10)
            hdr = off + 14
        }
        guard hdr + 40 <= b.count else { return nil }
        let hs = u32(b, hdr)
        let w = i32(b, hdr + 4)
        var h = i32(b, hdr + 8)
        let bpp = u16(b, hdr + 14)
        let comp = u32(b, hdr + 16)
        let clrUsed = hs >= 36 ? u32(b, hdr + 32) : 0
        let flip = h > 0
        h = abs(h)
        guard w > 0, h > 0, w < 8192, h < 8192 else { return nil }
        var pal: [(UInt8, UInt8, UInt8)] = []
        if bpp <= 8 {
            let n = clrUsed > 0 ? clrUsed : (1 << bpp)
            for i in 0..<n {
                let p = hdr + hs + 4 * i
                guard p + 3 <= b.count else { break }
                pal.append((b[p + 2], b[p + 1], b[p]))
            }
            if pix == nil { pix = hdr + hs + 4 * n }
        } else if pix == nil {
            pix = hdr + hs + (comp == 3 ? 12 : 0)
        }
        guard let p0 = pix else { return nil }
        let rowStride = ((w * bpp + 31) / 32) * 4
        var px = [UInt8](repeating: 0, count: w * h * 4)
        var alpha = false
        for y in 0..<h {
            let row = p0 + (flip ? h - 1 - y : y) * rowStride
            guard row + rowStride <= b.count + 3 else { break }
            for x in 0..<w {
                var r: UInt8 = 0, g: UInt8 = 0, bl: UInt8 = 0, a: UInt8 = 255
                switch bpp {
                case 32:
                    let o = row + 4 * x
                    guard o + 3 < b.count else { continue }
                    bl = b[o]; g = b[o + 1]; r = b[o + 2]; a = b[o + 3]
                    if a != 0 { alpha = true }
                case 24:
                    let o = row + 3 * x
                    guard o + 2 < b.count else { continue }
                    bl = b[o]; g = b[o + 1]; r = b[o + 2]
                case 16:
                    let o = row + 2 * x
                    guard o + 1 < b.count else { continue }
                    let v = u16(b, o)
                    r = UInt8(((v >> 10) & 31) * 255 / 31); g = UInt8(((v >> 5) & 31) * 255 / 31); bl = UInt8((v & 31) * 255 / 31)
                default:
                    let bit = x * bpp
                    let o = row + bit / 8
                    guard o < b.count else { continue }
                    let v = (Int(b[o]) >> (8 - bpp - bit % 8)) & ((1 << bpp) - 1)
                    if v < pal.count { (r, g, bl) = pal[v] }
                }
                let d = (y * w + x) * 4
                px[d] = r; px[d + 1] = g; px[d + 2] = bl; px[d + 3] = a
            }
        }
        if bpp == 32 && !alpha {
            for i in stride(from: 3, to: px.count, by: 4) { px[i] = 255 }
        }
        return RGBABitmap(width: w, height: h, pixels: px, hasAlpha: alpha)
    }

    /// TBitmap property data (Glyph.Data, Bitmap.Data): u32 size + BMP file.
    public static func bitmapProperty(_ b: [UInt8]) -> RGBABitmap? {
        guard b.count > 18 else { return nil }
        if b[0] == 0x42 && b[1] == 0x4D { return decode(b, at: 0) }
        return decode(b, at: 4)
    }

    /// TPicture data (Picture.Data): class name (short string) + graphic data.
    public static func pictureProperty(_ b: [UInt8]) -> (cls: String, bitmap: RGBABitmap?, data: [UInt8]) {
        guard !b.isEmpty else { return ("", nil, []) }
        let n = Int(b[0])
        let cls = String(decoding: b[1..<min(b.count, 1 + n)], as: UTF8.self)
        let rest = Array(b[min(b.count, 1 + n)...])
        if cls == "TBitmap" { return (cls, bitmapProperty(rest), rest) }
        if cls == "TIcon" { return (cls, nil, rest) }
        // TJPEGImage / TPngObject: u32 size + data
        let data = rest.count > 4 ? Array(rest[4...]) : rest
        return (cls, nil, data)
    }

    /// comctl32 ImageList stream ("IL" header + image BMP + optional mask BMP) -> tiles.
    public static func imageList(_ b: [UInt8]) -> [RGBABitmap] {
        guard b.count > 28, b[0] == 0x49, b[1] == 0x4C else { return [] }
        let count = u16(b, 4)
        let cx = u16(b, 10), cy = u16(b, 12)
        let flags = u16(b, 18)
        guard let img = decode(b, at: 28) else { return [] }
        let size = u32(b, 30)
        var mask: RGBABitmap?
        if flags & 1 != 0, 28 + size + 2 < b.count, b[28 + size] == 0x42, b[28 + size + 1] == 0x4D {
            mask = decode(b, at: 28 + size)
        }
        guard cx > 0, cy > 0 else { return [] }
        let cols = max(1, img.width / cx)
        var tiles: [RGBABitmap] = []
        for i in 0..<count {
            let x0 = (i % cols) * cx, y0 = (i / cols) * cy
            var t = img.crop(x0, y0, cx, cy)
            if !img.hasAlpha {
                if let m = mask {
                    let mt = m.crop(x0, y0, cx, cy)
                    for j in stride(from: 0, to: t.pixels.count, by: 4) { t.pixels[j + 3] = mt.pixels[j] > 127 ? 0 : 255 }
                    t.hasAlpha = true
                } else {
                    t = t.keyedTransparent()
                }
            }
            tiles.append(t)
        }
        return tiles
    }
}

/// TImageList.
public final class TImageList: TComponent {
    public var width = 16
    public var height = 16
    public var images: [NSImage] = []
    public var disabled: [NSImage] = []
    var bitmaps: [RGBABitmap] = []

    public var count: Int { images.count }

    public func load(_ data: [UInt8]) {
        bitmaps = DIB.imageList(data)
        images = bitmaps.map(\.image)
        disabled = bitmaps.map(\.disabledImage)
        if let f = bitmaps.first { width = f.width; height = f.height }
    }

    public func image(_ i: Int, enabled: Bool = true) -> NSImage? {
        guard i >= 0, i < images.count else { return nil }
        return enabled ? images[i] : disabled[i]
    }
}

/// Button glyph (TBitBtn / TSpeedButton Glyph with NumGlyphs).
public struct TGlyph {
    public var normal: NSImage
    public var disabled: NSImage
    public var size: NSSize

    public init?(data: [UInt8], numGlyphs: Int) {
        guard var bmp = DIB.bitmapProperty(data) else { return nil }
        if !bmp.hasAlpha { bmp = bmp.keyedTransparent() }
        let n = max(1, numGlyphs)
        let gw = bmp.width / n
        let first = bmp.crop(0, 0, gw, bmp.height)
        normal = first.image
        if n >= 2 {
            disabled = bmp.crop(gw, 0, gw, bmp.height).image
        } else {
            disabled = first.disabledImage
        }
        size = NSSize(width: gw, height: bmp.height)
    }

    public init(image: NSImage) {
        normal = image
        disabled = image
        size = image.size
    }
}
