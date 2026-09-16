"""Decode GameCube IA4 textures and write PNGs, so the label strip can be read."""
import struct, zlib

def decode_ia4(data, w, h):
    """IA4: one byte per texel, tiles of 8x4. Low nibble intensity, high alpha."""
    px = [[(0, 0)] * w for _ in range(h)]
    i = 0
    for ty in range(0, h, 4):
        for tx in range(0, w, 8):
            for y in range(4):
                for x in range(8):
                    if i >= len(data): return px
                    b = data[i]; i += 1
                    if ty + y < h and tx + x < w:
                        inten = (b & 0x0F) * 17
                        alpha = ((b >> 4) & 0x0F) * 17
                        px[ty + y][tx + x] = (inten, alpha)
    return px

def write_png_ga(path, px):
    h = len(px); w = len(px[0])
    raw = b"".join(b"\0" + b"".join(bytes(p) for p in row) for row in px)
    def chunk(tag, body):
        c = tag + body
        return struct.pack(">I", len(body)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 4, 0, 0, 0))  # 4 = grey+alpha
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    open(path, "wb").write(png)

def write_sheet(path, tiles, cols=1, pad=2):
    """Stack decoded tiles vertically into one image, on a mid grey so both
    dark and light ink read."""
    w = max(len(t[0]) for t in tiles)
    rows = []
    for t in tiles:
        for row in t:
            r = list(row) + [(0, 0)] * (w - len(row))
            rows.append(r)
        for _ in range(pad):
            rows.append([(128, 255)] * w)
    write_png_ga(path, rows)


def decode_i4(data, w, h):
    """I4: 4 bits per texel, intensity only, in 8x8 tiles (32 bytes each).
    Returned as (intensity, alpha) pairs like the IA4 decoder, with alpha
    standing in for intensity so the same rendering helpers work."""
    px = [[(0, 0)] * w for _ in range(h)]
    tw, th = (w + 7) // 8, (h + 7) // 8
    o = 0
    for ty in range(th):
        for tx in range(tw):
            for y in range(8):
                for xb in range(4):
                    b = data[o]; o += 1
                    for k, v in ((0, b >> 4), (1, b & 0xF)):
                        X, Y = tx*8 + xb*2 + k, ty*8 + y
                        if X < w and Y < h:
                            i = v * 17
                            px[Y][X] = (i, i)
    return px
