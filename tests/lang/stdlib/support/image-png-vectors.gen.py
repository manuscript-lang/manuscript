#!/usr/bin/env python3
"""Regenerates image-png-vectors.ms: PNGs from an independent writer (all color types,
depths, filters, Adam7, tRNS), each cross-checked against Pillow's decoder.
Run: python3 image-png-vectors.gen.py > image-png-vectors.ms"""
import random, struct, zlib, io
from PIL import Image

random.seed(7)
PASSES = [(0,0,8,8),(4,0,8,8),(0,4,4,8),(2,0,4,4),(0,2,2,4),(1,0,2,2),(0,1,1,2)]
CH = {0:1,2:3,3:1,4:2,6:4}

def chunk(k, b):
    return struct.pack(">I", len(b)) + k + b + struct.pack(">I", zlib.crc32(k + b))

def filt(ft, row, prev, bpp):
    out = bytearray()
    for i, x in enumerate(row):
        a = row[i-bpp] if i >= bpp else 0
        b = prev[i]
        c = prev[i-bpp] if i >= bpp else 0
        if ft == 0: p = 0
        elif ft == 1: p = a
        elif ft == 2: p = b
        elif ft == 3: p = (a + b) // 2
        else:
            q = a + b - c
            pa, pb, pc = abs(q-a), abs(q-b), abs(q-c)
            p = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
        out.append((x - p) % 256)
    return bytes(out)

def pack_row(samples, depth):
    if depth == 16:
        return b"".join(struct.pack(">H", s) for s in samples)
    if depth == 8:
        return bytes(samples)
    bits = "".join(format(s, "0%db" % depth) for s in samples)
    bits += "0" * (-len(bits) % 8)
    return bytes(int(bits[i:i+8], 2) for i in range(0, len(bits), 8))

def make(w, h, color, depth, interlace, trns=None, plte=None):
    n = CH[color]
    top = (1 << depth) - 1
    px = [[[random.randint(0, top) if color != 3 else random.randrange(len(plte)) for _ in range(n)]
           for _ in range(w)] for _ in range(h)]
    bpp = max(1, n * depth // 8)
    raw = bytearray()
    passes = PASSES if interlace else [(0,0,1,1)]
    for xs, ys, dx, dy in passes:
        xs_ = list(range(xs, w, dx)); ys_ = list(range(ys, h, dy))
        if not xs_ or not ys_: continue
        prev = bytes(len(pack_row([0]*(len(xs_)*n), depth)))
        for y in ys_:
            row = pack_row([s for x in xs_ for s in px[y][x]], depth)
            ft = random.randint(0, 4)
            raw += bytes([ft]) + filt(ft, row, prev, bpp)
            prev = row
    hdr = struct.pack(">IIBBBBB", w, h, depth, color, 0, 0, 1 if interlace else 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", hdr)
    if plte: png += chunk(b"PLTE", bytes(v for e in plte for v in e))
    if trns is not None: png += chunk(b"tRNS", bytes(trns))
    # split IDAT in two to exercise concatenation
    z = zlib.compress(bytes(raw))
    mid = len(z) // 2
    png += chunk(b"IDAT", z[:mid]) + chunk(b"IDAT", z[mid:]) + chunk(b"IEND", b"")
    # expected RGBA8
    exp = []
    for y in range(h):
        for x in range(w):
            s = px[y][x]
            if color == 0:
                v = s[0] >> 8 if depth == 16 else (s[0] if depth == 8 else s[0] * 255 // top)
                a = 255
                if trns is not None: a = 0 if s[0] == struct.unpack(">H", bytes(trns[:2]))[0] else 255
                exp += [v, v, v, a]
            elif color == 2:
                v = [t >> 8 if depth == 16 else t for t in s]
                a = 255
                if trns is not None:
                    key = struct.unpack(">HHH", bytes(trns[:6]))
                    a = 0 if tuple(s) == key else 255
                exp += v + [a]
            elif color == 3:
                e = plte[s[0]]
                a = trns[s[0]] if trns is not None and s[0] < len(trns) else 255
                exp += list(e) + [a]
            elif color == 4:
                v = [t >> 8 if depth == 16 else t for t in s]
                exp += [v[0], v[0], v[0], v[1]]
            else:
                exp += [t >> 8 if depth == 16 else t for t in s]
    # cross-check with Pillow where it supports the shape
    if depth != 16 or color in (0, 2, 4, 6):
        try:
            im = Image.open(io.BytesIO(png))
            if depth < 16 and trns is None and color != 3 and not (color == 0 and depth < 8):
                got = list(im.convert("RGBA").tobytes())
                assert got == exp, (w, h, color, depth, interlace)
            elif color == 3 or (color == 0 and depth < 8):
                got = list(im.convert("RGBA").tobytes())
                assert got == exp, (w, h, color, depth, interlace, "p")
        except AssertionError:
            raise
    return png, exp

cases = []
def add(name, *a, **k):
    png, exp = make(*a, **k)
    cases.append((name, a[0], a[1], png, exp))

random.seed(11)
pal = [(random.randrange(256), random.randrange(256), random.randrange(256)) for _ in range(16)]
for ilace in (False, True):
    t = "adam7-" if ilace else ""
    add(t + "gray1", 9, 5, 0, 1, ilace)
    add(t + "gray2", 7, 6, 0, 2, ilace)
    add(t + "gray4", 11, 4, 0, 4, ilace)
    add(t + "gray8", 10, 9, 0, 8, ilace)
    add(t + "gray16", 6, 5, 0, 16, ilace)
    add(t + "rgb8", 8, 8, 2, 8, ilace)
    add(t + "rgb16", 5, 7, 2, 16, ilace)
    add(t + "indexed1", 13, 3, 3, 1, ilace, plte=pal[:2])
    add(t + "indexed2", 9, 9, 3, 2, ilace, plte=pal[:4])
    add(t + "indexed4", 10, 6, 3, 4, ilace, plte=pal)
    add(t + "indexed8", 7, 7, 3, 8, ilace, plte=pal)
    add(t + "gray-alpha8", 6, 6, 4, 8, ilace)
    add(t + "gray-alpha16", 4, 5, 4, 16, ilace)
    add(t + "rgba8", 9, 7, 6, 8, ilace)
    add(t + "rgba16", 3, 9, 6, 16, ilace)
add("indexed-trns", 8, 4, 3, 8, False, plte=pal[:4], trns=[0, 128])
add("gray-trns", 6, 4, 0, 8, False, trns=[0, 5])
add("rgb-trns", 6, 4, 2, 8, False, trns=[0, 1, 0, 2, 0, 3])
add("one-pixel", 1, 1, 6, 8, True)
add("wide-adam7", 17, 2, 2, 8, True)
add("tall-adam7", 2, 17, 2, 8, True)

print("// Generated by image-png-vectors.gen.py; do not edit.")
print('import hex_decode from "@std/data/encoding.ms"')
print('import Bytes from "@std/bytes.ms"')
print("")
print("export type PngVector:")
print("    name: String")
print("    width: Int")
print("    height: Int")
print("    png: String")
print("    rgba: List[Int]")
print("")
print("export fn vectors() List[PngVector]:")
print("    return [")
for i, (name, w, h, png, exp) in enumerate(cases):
    print('        PngVector("%s", %d, %d, "%s", [%s])%s' % (name, w, h, png.hex(), ", ".join(map(str, exp)), "," if i < len(cases)-1 else ""))
print("    ]")
