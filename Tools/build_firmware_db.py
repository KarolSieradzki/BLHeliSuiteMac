#!/usr/bin/env python3
"""Builds the firmware database used by BLHeliSuite for Mac.

Reads the resource DLLs shipped with the Windows BLHeliSuite (BLHeliSilabsHex.dll,
BLHeliAtmelHex.dll) and the bootloader hex resources of BLHeliSuite.exe, and writes
a single compressed container (FirmwareDB.bin) that the Mac app loads at runtime.

Container layout (all integers little endian):
    magic       8 bytes  b"BLHFWDB2"
    meta_raw    u32      uncompressed length of the JSON metadata
    meta_len    u32      compressed length of the JSON metadata
    meta        bytes    raw DEFLATE stream of the UTF-8 JSON metadata
    blob_raw    u32      uncompressed length of the image stream
    blob_len    u32      compressed length of the image stream
    blob        bytes    raw DEFLATE stream (zlib wbits=-15)

The decompressed image stream is a concatenation of images. Every image is:
    seg_count u32, then seg_count * (address u32, length u32, bytes)
Firmware entries reference images by [offset, length] into that stream.

Usage: build_firmware_db.py <BLHeliSuite folder> <output FirmwareDB.bin>
"""
import hashlib
import json
import struct
import sys
import zlib
from pathlib import Path


# ---------------------------------------------------------------- PE resources

class PEResources:
    def __init__(self, path):
        self.data = Path(path).read_bytes()
        d = self.data
        e = struct.unpack_from('<I', d, 0x3C)[0]
        nsec = struct.unpack_from('<H', d, e + 6)[0]
        optsz = struct.unpack_from('<H', d, e + 20)[0]
        opt = e + 24
        magic = struct.unpack_from('<H', d, opt)[0]
        ddir = opt + (96 if magic == 0x10B else 112)
        self.rsrc_rva = struct.unpack_from('<I', d, ddir + 2 * 8)[0]
        self.sections = []
        o = opt + optsz
        for _ in range(nsec):
            vsz, va, rsz, rptr = struct.unpack_from('<IIII', d, o + 8)
            self.sections.append((va, vsz, rptr, rsz))
            o += 40
        self.rsrc_off = self.rva2off(self.rsrc_rva)

    def rva2off(self, rva):
        for va, vsz, rptr, rsz in self.sections:
            if va <= rva < va + max(vsz, rsz):
                return rptr + (rva - va)
        raise ValueError('rva %x not mapped' % rva)

    def _name(self, off):
        n = struct.unpack_from('<H', self.data, self.rsrc_off + off)[0]
        raw = self.data[self.rsrc_off + off + 2:self.rsrc_off + off + 2 + 2 * n]
        return raw.decode('utf-16-le')

    def _entries(self, off):
        d = self.data
        base = self.rsrc_off + off
        nnamed, nid = struct.unpack_from('<HH', d, base + 12)
        for i in range(nnamed + nid):
            name, target = struct.unpack_from('<II', d, base + 16 + 8 * i)
            key = self._name(name & 0x7FFFFFFF) if name & 0x80000000 else name
            yield key, target

    def resources(self, rtype):
        """Yields (name, bytes) for every resource of the given type."""
        for tkey, ttarget in self._entries(0):
            if tkey != rtype:
                continue
            for nkey, ntarget in self._entries(ttarget & 0x7FFFFFFF):
                for _lang, ltarget in self._entries(ntarget & 0x7FFFFFFF):
                    rva, size = struct.unpack_from('<II', self.data, self.rsrc_off + ltarget)
                    off = self.rva2off(rva)
                    yield nkey, self.data[off:off + size]
                    break


RT_RCDATA = 10


# ---------------------------------------------------------------- Intel HEX

def parse_hex(text):
    mem = {}
    base = 0
    for line in text.decode('latin-1').splitlines():
        line = line.strip()
        if not line.startswith(':'):
            continue
        rec = bytes.fromhex(line[1:])
        if sum(rec) & 0xFF:
            raise ValueError('bad hex checksum: ' + line)
        n, addr, rtype = rec[0], (rec[1] << 8) | rec[2], rec[3]
        payload = rec[4:4 + n]
        if rtype == 0:
            for i, b in enumerate(payload):
                mem[base + addr + i] = b
        elif rtype == 2:
            base = ((payload[0] << 8) | payload[1]) << 4
        elif rtype == 4:
            base = ((payload[0] << 8) | payload[1]) << 16
        elif rtype == 1:
            break
    return mem


def encode_image(mem):
    segs = []
    addrs = sorted(mem)
    start = prev = None
    for a in addrs:
        if start is None:
            start = prev = a
        elif a == prev + 1:
            prev = a
        else:
            segs.append((start, prev))
            start = prev = a
    if start is not None:
        segs.append((start, prev))
    out = bytearray(struct.pack('<I', len(segs)))
    for s, e in segs:
        out += struct.pack('<II', s, e - s + 1)
        out += bytes(mem[a] for a in range(s, e + 1))
    return bytes(out)


# ---------------------------------------------------------------- lists

def parse_hex_list(blob):
    p = 0

    def i32():
        nonlocal p
        v = struct.unpack_from('<i', blob, p)[0]
        p += 4
        return v

    def u8():
        nonlocal p
        v = blob[p]
        p += 1
        return v

    def lstr():
        n = i32()
        nonlocal p
        s = blob[p:p + n].decode('latin-1')
        p += n
        return s

    count = i32()
    rows = []
    for _ in range(count):
        res, layout, mcu = i32(), i32(), i32()
        family, is_s = u8(), u8()
        mode, rev = i32(), i32()
        layout_rev, def_startup_power, def_startup_method, def_spoolup = u8(), u8(), u8(), u8()
        revs, name, extra = lstr(), lstr(), lstr()
        rows.append(dict(res=res, layout=layout, mcu=mcu, family=family, isS=is_s, mode=mode,
                         rev=rev, layoutRev=layout_rev, defStartupPower=def_startup_power,
                         defStartupMethod=def_startup_method, defSpoolup=def_spoolup,
                         revStr=revs, name=name, extra=extra))
    assert p == len(blob), 'hex list not fully consumed'
    return rows


def parse_layouts(blob):
    p = 4
    count = struct.unpack_from('<i', blob, 0)[0]

    def sstr():
        nonlocal p
        n = blob[p]
        s = blob[p + 1:p + 1 + n].decode('latin-1')
        p += 1 + n
        return s

    out = []
    for _ in range(count):
        name = sstr()
        cells, damped, bec = blob[p], blob[p + 1], blob[p + 2]
        p += 3
        desc = sstr()
        mhz, bootl = blob[p], blob[p + 1]
        p += 2
        pin1 = sstr()
        pin2 = sstr()
        lf, hf, ef = blob[p], blob[p + 1], blob[p + 2]
        p += 3
        out.append(dict(name=name, cells=cells, damped=damped, becHV=bec, desc=desc, mhz=mhz,
                        bootloader=bool(bootl), inPin=pin1, inPin2=pin2, lfuse=lf, hfuse=hf,
                        efuse=ef, leds=0))
    assert p == len(blob), 'layout list not fully consumed'
    return out


def blheli_s_layouts():
    """Generated exactly like TBLHeli (FUN_0059bb54): letters A..Z, H(48MHz)/L(24MHz),
    dead times 00..30 step 5 then 40..90 step 10."""
    out = []
    for letter in (chr(c) for c in range(0x41, 0x5B)):
        for mhz in (48, 24):
            hl = 'H' if mhz == 48 else 'L'
            dt = 0
            while dt < 0x5B:
                name = '%s_%s_%02d' % (letter, hl, dt)
                leds = 0
                if letter == 'M':
                    leds = 1
                elif letter in ('E', 'J', 'U'):
                    leds = 3
                elif letter == 'Q':
                    leds = 2
                out.append(dict(name=name, cells=6, damped=0x10, becHV=0,
                                desc='%s-%s-%02d' % (letter, hl, dt), mhz=mhz, bootloader=False,
                                inPin='', inPin2='', lfuse=0, hfuse=0, efuse=0, leds=leds))
                dt = dt + 5 if dt < 0x1E else dt + 10
    return out


# ---------------------------------------------------------------- main

def main():
    suite = Path(sys.argv[1])
    out_path = Path(sys.argv[2])
    stream = bytearray()
    image_index = {}

    def add_image(mem):
        img = encode_image(mem)
        h = hashlib.sha1(img).hexdigest()
        if h not in image_index:
            image_index[h] = (len(stream), len(img))
            stream.extend(img)
        return list(image_index[h])

    families = {}

    # SiLabs
    pe = PEResources(suite / 'BLHeliSilabsHex.dll')
    res = {name: data for name, data in pe.resources(RT_RCDATA)}
    layouts = parse_layouts(res['ESCLAYOUTSSIL'])
    assert len(layouts) == 98
    layouts += blheli_s_layouts()
    rows = parse_hex_list(res['BLHELISILABSHEXRESLIST'])
    for r in rows:
        assert layouts[r['layout']]['name'] == r['name'], r
        r['image'] = add_image(parse_hex(res['BLHELI_F330_%d' % r['res']]))
    families['silabs'] = dict(layouts=layouts, firmware=rows)

    # Atmel
    pe = PEResources(suite / 'BLHeliAtmelHex.dll')
    res = {name: data for name, data in pe.resources(RT_RCDATA)}
    layouts = parse_layouts(res['ESCLAYOUTSATM'])
    rows = parse_hex_list(res['BLHELIATMELHEXRESLIST'])
    for r in rows:
        assert layouts[r['layout']]['name'] == r['name'], r
        r['image'] = add_image(parse_hex(res['BLHELI_AVR_HEX_%d' % r['res']]))
        r['eeprom'] = add_image(parse_hex(res['BLHELI_AVR_EEP_%d' % r['res']]))
    families['atmel'] = dict(layouts=layouts, firmware=rows)

    # Atmel bootloaders embedded in BLHeliSuite.exe (BLHELI_* and SKBOOT_*)
    pe = PEResources(suite / 'BLHeliSuite.exe')
    boot = []
    for name, data in pe.resources(RT_RCDATA):
        if isinstance(name, str) and (name.startswith('BLHELI_M') or name.startswith('SKBOOT_M')):
            boot.append(dict(name=name, image=add_image(parse_hex(data))))
    boot.sort(key=lambda b: b['name'])

    meta = dict(version=2, source='BLHeliSuite 16.7.14.9.0.2', families=families,
                bootloaders=boot)
    meta_json = json.dumps(meta, separators=(',', ':')).encode()

    def deflate(raw):
        comp = zlib.compressobj(9, zlib.DEFLATED, -15, 9)
        return comp.compress(raw) + comp.flush()

    meta_z = deflate(meta_json)
    blob = deflate(bytes(stream))
    with open(out_path, 'wb') as f:
        f.write(b'BLHFWDB2')
        f.write(struct.pack('<II', len(meta_json), len(meta_z)))
        f.write(meta_z)
        f.write(struct.pack('<II', len(stream), len(blob)))
        f.write(blob)
    print('silabs firmware:', len(families['silabs']['firmware']),
          'layouts:', len(families['silabs']['layouts']))
    print('atmel firmware:', len(families['atmel']['firmware']),
          'layouts:', len(families['atmel']['layouts']))
    print('bootloaders:', len(boot))
    print('unique images:', len(image_index), 'stream bytes:', len(stream),
          'compressed:', len(blob), 'meta:', len(meta_json))


if __name__ == '__main__':
    main()
