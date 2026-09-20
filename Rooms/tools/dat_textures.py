"""Decode the textures out of a Melee DAT to PNG, so they can be looked at.

Finding a picture inside a file nobody has source for is otherwise a guessing
game: the descriptors say 64x64 and a format number, and nothing says whether
that is the thing you actually want. Decoding it and opening it does.

    python dat_textures.py MnSlMap.usd out/            # every distinct image
    python dat_textures.py --sheet MnSlMap.usd out/    # one contact sheet

GameCube textures are TILED - I4/CMPR in 8x8, I8/IA4 in 8x4, the 16-bit ones in
4x4 - which is why a raw dump of one looks like noise.
"""
import argparse, collections, os, struct, zlib

TILE = {0: (8, 8, 4), 1: (8, 4, 8), 2: (8, 4, 8), 3: (4, 4, 16),
        4: (4, 4, 16), 5: (4, 4, 16), 6: (4, 4, 32),
        8: (8, 8, 4), 9: (8, 4, 8), 14: (8, 8, 4)}

# C4/C8 are indexes into a palette the TObj holds, NOT the image descriptor -
# which is why a scan of descriptors alone cannot decode them. The TObj keeps
# the two next to each other, image at +0x4C and palette at +0x50, so finding
# the descriptor's address in the file finds the palette four bytes later.
PALETTED = (8, 9)


def px_i4(v):   c = v * 17; return (c, c, c, 255)
def px_i8(v):   return (v, v, v, 255)
def px_ia4(v):  c = (v & 0xF) * 17; return (c, c, c, (v >> 4) * 17)
def px_ia8(v):  a = v >> 8; c = v & 0xFF; return (c, c, c, a)
def px_565(v):
    return (((v >> 11) & 31) * 255 // 31, ((v >> 5) & 63) * 255 // 63,
            (v & 31) * 255 // 31, 255)
def px_5a3(v):
    if v & 0x8000:
        return (((v >> 10) & 31) * 255 // 31, ((v >> 5) & 31) * 255 // 31,
                (v & 31) * 255 // 31, 255)
    return (((v >> 8) & 15) * 17, ((v >> 4) & 15) * 17, (v & 15) * 17,
            ((v >> 12) & 7) * 255 // 7)


def fmt_bpp(f):
    return TILE[f][2] if f in TILE else 8


def valid_tlut(blob, t):
    """A real TLUT record: a pointer, a format of 0..2, and a sane count."""
    if t + 0x10 > len(blob):
        return False
    ptr, fmt = struct.unpack_from(">2I", blob, t)
    n = struct.unpack_from(">H", blob, t + 0xC)[0]
    return 0 < ptr < len(blob) and fmt <= 2 and 0 < n <= 0x4000


def valid_tlut_at(blob, off):
    """Palette data sitting inline - nothing to check but that it is there."""
    return off + 512 <= len(blob)


def palette(blob, tlut):
    """The TLUT's colours: pointer at +0, format at +4, count at +0xC."""
    if not tlut:
        return None
    p = struct.unpack_from(">I", blob, tlut)[0]
    fmt = struct.unpack_from(">I", blob, tlut + 4)[0]
    n = struct.unpack_from(">H", blob, tlut + 0xC)[0] or 256
    conv = {0: px_ia8, 1: px_565, 2: px_5a3}.get(fmt, px_5a3)
    return [conv(struct.unpack_from(">H", blob, p + i * 2)[0]) for i in range(n)]


def decode(blob, off, w, h, fmt, pal=None):
    """-> list of rows of (r,g,b,a); None for a format not handled here."""
    if fmt not in TILE:
        return None
    if fmt in PALETTED and not pal:
        return None
    out = [[(0, 0, 0, 0)] * w for _ in range(h)]
    tw, th, bpp = TILE[fmt]
    p = off
    if fmt == 14:                                   # CMPR, DXT1 in 8x8 tiles
        for ty in range(0, h, 8):
            for tx in range(0, w, 8):
                for sy in (0, 4):
                    for sx in (0, 4):
                        c0, c1 = struct.unpack_from(">2H", blob, p)
                        bits = struct.unpack_from(">I", blob, p + 4)[0]
                        p += 8
                        cols = [px_565(c0), px_565(c1)]
                        if c0 > c1:
                            cols.append(tuple((2 * cols[0][i] + cols[1][i]) // 3 for i in range(3)) + (255,))
                            cols.append(tuple((cols[0][i] + 2 * cols[1][i]) // 3 for i in range(3)) + (255,))
                        else:
                            cols.append(tuple((cols[0][i] + cols[1][i]) // 2 for i in range(3)) + (255,))
                            cols.append((0, 0, 0, 0))
                        for yy in range(4):
                            for xx in range(4):
                                idx = (bits >> (30 - 2 * (yy * 4 + xx))) & 3
                                y, x = ty + sy + yy, tx + sx + xx
                                if y < h and x < w:
                                    out[y][x] = cols[idx]
        return out
    for ty in range(0, h, th):
        for tx in range(0, w, tw):
            for yy in range(th):
                xx = 0
                while xx < tw:
                    y, x = ty + yy, tx + xx
                    if bpp == 4:
                        byte = blob[p]; p += 1
                        for half in (byte >> 4, byte & 0xF):
                            if y < h and x < w:
                                out[y][x] = pal[half] if fmt == 8 else px_i4(half)
                            x += 1; xx += 1
                        continue
                    if bpp == 8:
                        v = blob[p]; p += 1
                        if fmt == 9:
                            pix = pal[v] if v < len(pal) else (0, 0, 0, 0)
                        else:
                            pix = px_i8(v) if fmt == 1 else px_ia4(v)
                    else:
                        v = struct.unpack_from(">H", blob, p)[0]; p += 2
                        pix = {3: px_ia8, 4: px_565, 5: px_5a3}[fmt](v)
                    if y < h and x < w:
                        out[y][x] = pix
                    xx += 1
    return out


def png(path, rows):
    h = len(rows); w = len(rows[0])
    raw = b"".join(b"\0" + bytes(v for px in r for v in px) for r in rows)
    def chunk(t, data):
        c = t + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))
    open(path, "wb").write(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">2I5B", w, h, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dat"); ap.add_argument("out")
    ap.add_argument("--sheet", action="store_true", help="one contact sheet")
    ap.add_argument("--only", default="", help="only WxH, e.g. 64x64")
    args = ap.parse_args()

    b = open(args.dat, "rb").read()
    dsize, nreloc = struct.unpack(">2I", b[4:12])
    d = b[0x20:0x20 + dsize]
    # Every pointer in a DAT is listed in the relocation table, so the TObj that
    # owns an image descriptor can be found exactly instead of by scanning for
    # the descriptor's address - which finds byte patterns inside image data
    # and hands back whatever sits four bytes later as a palette. That is what
    # made the first sheet come out as confetti.
    reloc = struct.unpack(">%dI" % nreloc, b[0x20 + dsize:0x20 + dsize + nreloc * 4]) if nreloc else ()
    owner = {}
    for r in reloc:
        if r + 8 <= dsize:
            owner.setdefault(struct.unpack_from(">I", d, r)[0], r)
    found = {}
    for o in range(0, dsize - 24, 4):
        p, w, h, f = (struct.unpack_from(">I", d, o)[0],
                      struct.unpack_from(">H", d, o + 4)[0],
                      struct.unpack_from(">H", d, o + 6)[0],
                      struct.unpack_from(">I", d, o + 8)[0])
        # ⚠️ NOT a power-of-two whitelist. Melee's stage icons are 64x56, and a
        # whitelist of powers of two skipped every one of them.
        if 0 < p < dsize and 8 <= w <= 640 and 8 <= h <= 640                 and w % 4 == 0 and h % 4 == 0 and f in TILE:
            if args.only and args.only != "%dx%d" % (w, h):
                continue
            # ⚠️ Only a descriptor something actually POINTS AT. A linear scan
            # also matches four bytes of image data that happen to look like
            # {ptr, w, h, fmt}, and those fakes carry no palette - which is how
            # real icons came out as confetti while a few decoded perfectly.
            if o not in owner:
                continue
            found.setdefault(p, (w, h, f, o))

    os.makedirs(args.out, exist_ok=True)
    imgs = []
    for p, (w, h, f, desc) in sorted(found.items()):
        pal = None
        if f in PALETTED:
            # The TObj that owns this descriptor, found through the RELOCATION
            # TABLE rather than by searching the file for the descriptor's
            # address. Searching finds the same four bytes inside image data
            # first and takes whatever follows them as a palette, which is what
            # turned the first contact sheet into confetti.
            at = owner.get(desc)
            if at is not None:
                t = struct.unpack_from(">I", d, at + 4)[0]
                if 0 < t < dsize and valid_tlut(d, t):
                    pal = palette(d, t)
            if pal is None:
                # ⚠️ Most of these descriptors are NOT inside a TObj - they sit
                # in an array of their own, so the word after the reference is
                # the NEXT descriptor and reading it as a palette is what made
                # the sheet confetti. Melee lays a paletted image out with its
                # palette immediately after the pixels, so that is the fallback.
                after = p + w * h * (4 if fmt_bpp(f) == 4 else 8) // 8
                if after + 512 <= dsize and valid_tlut_at(d, after):
                    pal = [px_565(struct.unpack_from(">H", d, after + i * 2)[0])
                           for i in range(256)]
        rows = decode(d, p, w, h, f, pal)
        if rows:
            imgs.append((p, w, h, f, rows))
    print("decoded %d image(s)" % len(imgs))

    if args.sheet and imgs:
        cols = 8
        cw = max(i[1] for i in imgs); ch = max(i[2] for i in imgs)
        rowsn = (len(imgs) + cols - 1) // cols
        sheet = [[(24, 24, 32, 255)] * (cols * cw) for _ in range(rowsn * ch)]
        for n, (p, w, h, f, rows) in enumerate(imgs):
            oy = (n // cols) * ch; ox = (n % cols) * cw
            for y in range(h):
                for x in range(w):
                    sheet[oy + y][ox + x] = rows[y][x]
        png(os.path.join(args.out, "sheet.png"), sheet)
        for n, (p, w, h, f, _) in enumerate(imgs):
            print("  [%2d] 0x%06x %dx%d fmt%d" % (n, p, w, h, f))
        print("sheet: %s" % os.path.join(args.out, "sheet.png"))
        return
    for p, w, h, f, rows in imgs:
        png(os.path.join(args.out, "%06x_%dx%d_f%d.png" % (p, w, h, f)), rows)


main()
