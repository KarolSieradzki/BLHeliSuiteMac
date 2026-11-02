#!/usr/bin/env python3
"""Extracts the resources the macOS port loads at runtime from the original BLHeliSuite.exe:

  Forms/<NAME>.dfm     Delphi form resources (binary TPF0, loaded unchanged by the VCL runtime)
  Bitmaps/<NAME>.bmp   RT_BITMAP resources (button glyphs BBOK, BBCANCEL …)
  RCData/<NAME>        other RCDATA resources (about box text, Atmel bootloader hex images …)
  Strings.txt          string table resources (id <tab> text)

usage: extract_vcl_resources.py ../BLHeliSuite/BLHeliSuite.exe Resources/VCL
"""
import os
import struct
import sys


def u16(b, o): return struct.unpack_from('<H', b, o)[0]
def u32(b, o): return struct.unpack_from('<I', b, o)[0]


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

    out = []

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
                out.append((tuple(path + [key]), data[o:o + size]))

    walk(0, [])
    return out


def main(exe, out):
    data = open(exe, 'rb').read()
    for sub in ('Forms', 'Bitmaps', 'RCData'):
        os.makedirs(os.path.join(out, sub), exist_ok=True)
    counts = {'forms': 0, 'bitmaps': 0, 'rcdata': 0, 'strings': 0}
    strings = []
    for path, payload in pe_resources(data):
        rtype, name = path[0], path[1]
        sname = name if isinstance(name, str) else str(name)
        if rtype == 10:
            if payload[:4] == b'TPF0':
                open(os.path.join(out, 'Forms', sname + '.dfm'), 'wb').write(payload)
                counts['forms'] += 1
            elif sname not in ('PACKAGEINFO', 'DVCLAL', 'ELDATA'):
                open(os.path.join(out, 'RCData', sname), 'wb').write(payload)
                counts['rcdata'] += 1
        elif rtype == 2:
            hs = u32(payload, 0)
            bpp = u16(payload, 14)
            clr = u32(payload, 32) if hs >= 36 else 0
            ncol = clr if clr else ((1 << bpp) if bpp <= 8 else 0)
            off = 14 + hs + 4 * ncol
            hdr = b'BM' + struct.pack('<IHHI', 14 + len(payload), 0, 0, off)
            open(os.path.join(out, 'Bitmaps', sname + '.bmp'), 'wb').write(hdr + payload)
            counts['bitmaps'] += 1
        elif rtype == 6 and isinstance(name, int):
            o = 0
            for i in range(16):
                n = u16(payload, o)
                o += 2
                if n:
                    s = payload[o:o + 2 * n].decode('utf-16-le')
                    strings.append(((name - 1) * 16 + i, s))
                o += 2 * n
    with open(os.path.join(out, 'Strings.txt'), 'w', encoding='utf-8') as f:
        for i, s in strings:
            f.write('%d\t%s\n' % (i, s.replace('\\', '\\\\').replace('\r', '\\r').replace('\n', '\\n').replace('\t', '\\t')))
    counts['strings'] = len(strings)
    print(counts)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
