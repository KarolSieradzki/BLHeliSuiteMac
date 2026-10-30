#!/usr/bin/env python3
"""Extracts the button glyphs, menu icons and pictures of the classic BLHeliSuite look from
BLHeliSuite.exe (PE resources -> Delphi DFM forms / ImageLists / bitmaps) and writes them as
base64 PNG data into Sources/BLHeliSuiteApp/Classic/ClassicAssets.swift.

    python3 Tools/make_classic_assets.py ../BLHeliSuite/BLHeliSuite.exe Sources/BLHeliSuiteApp/Classic/ClassicAssets.swift
"""
import base64
import struct
import sys
import zlib


def u16(b, o): return struct.unpack_from('<H', b, o)[0]
def u32(b, o): return struct.unpack_from('<I', b, o)[0]


# ---------------------------------------------------------------- PE resources

def pe_resources(data):
    pe = u32(data, 0x3C)
    nsec = u16(data, pe + 6)
    optsz = u16(data, pe + 20)
    opt = pe + 24
    ddir = opt + (96 if u16(data, opt) == 0x10B else 112)
    rsrc_rva = u32(data, ddir + 16)
    secs = []
    for i in range(nsec):
        s = opt + optsz + 40 * i
        vs, va, rs, ro = struct.unpack_from('<IIII', data, s + 8)
        secs.append((va, max(vs, rs), ro))

    def off(rva):
        for va, size, raw in secs:
            if va <= rva < va + size:
                return raw + rva - va
        raise ValueError('rva %x' % rva)

    base = off(rsrc_rva)

    def name_of(v):
        if v & 0x80000000:
            o = base + (v & 0x7FFFFFFF)
            return data[o + 2:o + 2 + 2 * u16(data, o)].decode('utf-16-le')
        return v

    out = {}

    def walk(d, path):
        n = u16(data, base + d + 12) + u16(data, base + d + 14)
        for i in range(n):
            e = base + d + 16 + 8 * i
            key, target = name_of(u32(data, e)), u32(data, e + 4)
            if target & 0x80000000:
                walk(target & 0x7FFFFFFF, path + [key])
            else:
                rva, size = struct.unpack_from('<II', data, base + target)
                o = off(rva)
                out.setdefault(tuple(path[:2] + [key])[:2], data[o:o + size])

    walk(0, [])
    return out


# ---------------------------------------------------------------- Delphi DFM

class Reader:
    def __init__(self, b): self.b, self.p = b, 0
    def u8(self): v = self.b[self.p]; self.p += 1; return v
    def i(self, fmt, n): v = struct.unpack_from(fmt, self.b, self.p)[0]; self.p += n; return v
    def raw(self, n): v = self.b[self.p:self.p + n]; self.p += n; return v
    def ss(self): return self.raw(self.u8()).decode('latin-1')


def dfm_value(r):
    t = r.u8()
    if t == 1:
        items = []
        while r.b[r.p] != 0:
            items.append(dfm_value(r))
        r.p += 1
        return items
    if t == 2: return r.i('<b', 1)
    if t == 3: return r.i('<h', 2)
    if t == 4: return r.i('<i', 4)
    if t == 5: r.raw(10); return 0.0
    if t in (6, 7): return r.ss()
    if t in (0, 8, 9, 13): return None
    if t == 10: return bytes(r.raw(r.i('<i', 4)))
    if t == 11:
        items = []
        while True:
            x = r.ss()
            if not x: return items
            items.append(x)
    if t == 12: return r.raw(r.i('<i', 4)).decode('latin-1')
    if t == 14:
        while True:
            nt = r.b[r.p]
            if nt == 0: r.p += 1; return None
            if nt in (2, 3, 4): dfm_value(r)
            r.u8()
            dfm_props(r)
    if t == 15: r.raw(4); return 0.0
    if t in (16, 17, 19, 21): r.raw(8); return 0
    if t == 18: return r.raw(2 * r.i('<i', 4)).decode('utf-16-le')
    if t == 20: return r.raw(r.i('<i', 4)).decode('utf-8')
    raise ValueError('DFM value type %d' % t)


def dfm_props(r):
    d = {}
    while True:
        name = r.ss()
        if not name: return d
        d[name] = dfm_value(r)


def dfm_objects(b):
    """Flat dict: object name -> properties."""
    assert b[:4] == b'TPF0'
    r = Reader(b)
    r.p = 4
    objs = {}

    def obj():
        if r.b[r.p] & 0xF0 == 0xF0:
            flags = r.u8() & 0x0F
            if flags & 2:
                {2: lambda: r.i('<b', 1), 3: lambda: r.i('<h', 2), 4: lambda: r.i('<i', 4)}[r.u8()]()
        r.ss()
        name = r.ss()
        objs[name] = dfm_props(r)
        while r.b[r.p] != 0:
            obj()
        r.p += 1

    obj()
    return objs


# ---------------------------------------------------------------- bitmaps

def decode_dib(b, off, file_header=True):
    """BMP/DIB -> (w, h, rgba list, has_alpha)."""
    if file_header:
        assert b[off:off + 2] == b'BM'
        pix = off + u32(b, off + 10)
        hdr = off + 14
    else:
        hdr = off
        pix = None
    hs, w, h, _, bpp, comp, _, _, _, clr = struct.unpack_from('<IiiHHIIiiI', b, hdr)
    flip = h > 0
    h = abs(h)
    pal = []
    if bpp <= 8:
        n = clr or (1 << bpp)
        pal = [tuple(b[hdr + hs + 4 * i:hdr + hs + 4 * i + 3]) for i in range(n)]
        if pix is None: pix = hdr + hs + 4 * n
    elif pix is None:
        pix = hdr + hs + (12 if comp == 3 else 0)
    stride = ((w * bpp + 31) // 32) * 4
    px = [0] * (w * h * 4)
    alpha = False
    for y in range(h):
        row = pix + (h - 1 - y if flip else y) * stride
        for x in range(w):
            if bpp == 32:
                B, G, R, A = b[row + 4 * x:row + 4 * x + 4]
                alpha = alpha or A != 0
            elif bpp == 24:
                B, G, R = b[row + 3 * x:row + 3 * x + 3]
                A = 255
            else:
                bit = x * bpp
                v = (b[row + bit // 8] >> (8 - bpp - bit % 8)) & ((1 << bpp) - 1)
                B, G, R = pal[v]
                A = 255
            px[(y * w + x) * 4:(y * w + x) * 4 + 4] = [R, G, B, A]
    return w, h, px, alpha


def key_transparent(w, h, px):
    """VCL convention: the bottom-left pixel colour is transparent."""
    k = px[(h - 1) * w * 4:(h - 1) * w * 4 + 3]
    for i in range(0, len(px), 4):
        px[i + 3] = 0 if px[i:i + 3] == k else 255
    return px


def crop(w, px, x0, y0, cw, ch):
    out = []
    for y in range(y0, y0 + ch):
        out += px[(y * w + x0) * 4:(y * w + x0 + cw) * 4]
    return out


def png(w, h, px):
    raw = b''.join(b'\0' + bytes(px[y * w * 4:(y + 1) * w * 4]) for y in range(h))

    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def glyph(blob, num=1):
    """TBitmap glyph (u32 size + BMP); first of `num` glyphs."""
    w, h, px, alpha = decode_dib(blob, 4)
    if not alpha:
        px = key_transparent(w, h, px)
    gw = w // num
    return png(gw, h, crop(w, px, 0, 0, gw, h))


def picture(blob, transparent):
    """TPicture data: class name + u32 size + BMP."""
    n = blob[0]
    assert blob[1:1 + n] == b'TBitmap', blob[1:1 + n]
    w, h, px, _ = decode_dib(blob, 1 + n + 4)
    if transparent:
        px = key_transparent(w, h, px)
    else:
        for i in range(3, len(px), 4): px[i] = 255
    return png(w, h, px)


def imagelist(blob):
    """Windows ImageList stream ('IL' header + image BMP [+ mask BMP]) -> list of PNGs."""
    assert blob[:2] == b'IL'
    _, count, _, _, cx, cy, _, flags = struct.unpack_from('<HHHHHHIH', blob, 2)
    w, h, px, alpha = decode_dib(blob, 28)
    size = u32(blob, 30)
    mask = None
    if flags & 1 and blob[28 + size:30 + size] == b'BM':
        _, _, mask, _ = decode_dib(blob, 28 + size)
    cols = w // cx
    tiles = []
    for i in range(count):
        x0, y0 = (i % cols) * cx, (i // cols) * cy
        t = crop(w, px, x0, y0, cx, cy)
        if not alpha:
            if mask:
                m = crop(w, mask, x0, y0, cx, cy)
                for j in range(0, len(t), 4): t[j + 3] = 0 if m[j] > 127 else 255
            else:
                t = key_transparent(cx, cy, t)
        tiles.append(png(cx, cy, t))
    return tiles


def dib_glyph(dib, num=2):
    w, h, px, _ = decode_dib(dib, 0, file_header=False)
    px = key_transparent(w, h, px)
    gw = w // num
    return png(gw, h, crop(w, px, 0, 0, gw, h))


# ---------------------------------------------------------------- main

def main(exe, out):
    res = pe_resources(open(exe, 'rb').read())

    def form(name): return dfm_objects(res[(10, name)])

    main_form = form('TFRMBLHELISUITEMAIN')
    combos = form('TFRAESCCOMBOS')
    make = form('TFRAMAKEINTERFACES')
    logf = form('TFRMLOGFORM')

    assets = {}
    for key, obj in [('read', 'btnReadSetuo'), ('write', 'btnWriteSetup'), ('flash', 'btnFlashBLHeliHexFile'),
                     ('flashOther', 'btnFlashOther'), ('restart', 'btnStartESC'), ('connect', 'btnConnect'),
                     ('check', 'btnCheckMultiESC'), ('readMem', 'btnReadMem'), ('writeMem', 'btnWriteMem'),
                     ('showHex', 'btnShowHexFile'), ('showBin', 'btnShowBinaryFile'), ('flashAny', 'btnFlashAnyHexFile'),
                     ('fuses', 'btnEditFuses')]:
        assets[key] = glyph(main_form[obj]['Glyph.Data'])
    assets['undo'] = glyph(combos['sbtnUNDO_Misc']['Glyph.Data'])
    assets['default'] = glyph(combos['sbtnDEFAULT_Misc']['Glyph.Data'])

    tiles = imagelist(main_form['imlInterfaces']['Bitmap'])
    for key, i in [('floppy', 24), ('hexdoc', 25), ('erase', 26), ('pdf', 27), ('palette', 28), ('about', 30),
                   ('verify', 31), ('web', 32), ('save', 33), ('open', 34)]:
        assets[key] = tiles[i]
    for i, t in enumerate(imagelist(logf['imlTrvLog']['Bitmap'])):
        assets['log%d' % i] = t

    for name in ('BBOK', 'BBCANCEL', 'BBIGNORE', 'BBYES', 'BBNO'):
        assets[name[2:].lower()] = dib_glyph(res[(2, name)])

    for obj in ('imgRBBX', 'imgTAQX', 'imgTDLX', 'imgTTTBox', 'imgT160ABox', 'imgArduinoUnoLCD1602',
                'imgrduinoUno4884Shield', 'imgArduinoNano', 'imgArduinoUno'):
        assets[obj] = picture(make[obj]['Picture.Data'], make[obj].get('Transparent', False))

    lines = ['// Generated by Tools/make_classic_assets.py from BLHeliSuite.exe – do not edit.',
             '// Button glyphs, menu icons and pictures of the original BLHeliSuite (PNG, base64).',
             '',
             'enum ClassicAssets {',
             '    static let png: [String: String] = [']
    for k in sorted(assets):
        lines.append('        "%s": "%s",' % (k, base64.b64encode(assets[k]).decode()))
    lines += ['    ]', '}', '']
    open(out, 'w').write('\n'.join(lines))
    print('%d images, %d bytes' % (len(assets), sum(len(v) for v in assets.values())))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
