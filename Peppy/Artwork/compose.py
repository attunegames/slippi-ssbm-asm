"""Author a menu label by cutting glyphs out of the labels already in the file.

Melee's labels are pre-rendered images, so the only way to match the font
exactly is to reuse it. Every label in this strip shares a baseline and a size,
so glyphs lift cleanly from one word into another.
"""
import sys
sys.path.insert(0, r"C:\root\peppy-assets")
from dat import Dat
from tex import decode_ia4, write_sheet

W, H = 176, 30

def label(d, tbl, i):
    desc = d.u32(tbl + 4*i); ptr = d.u32(desc)
    w, h = d.u16(desc+4), d.u16(desc+6)
    return decode_ia4(d.data[ptr:ptr+w*h], w, h), ptr, w, h

def ink_columns(px, thresh=40):
    return [any(px[y][x][1] > thresh for y in range(len(px))) for x in range(len(px[0]))]

def glyphs(px, min_gap=2):
    """Split a word into glyph column-ranges."""
    col = ink_columns(px)
    out, run = [], None
    gap = 0
    for x, on in enumerate(col + [False]):
        if on:
            if run is None: run = x
            gap = 0
        else:
            if run is not None:
                gap += 1
                if gap >= min_gap:
                    out.append((run, x - gap + 1)); run = None
    return out

def cut(px, a, b):
    return [row[a:b] for row in px]

def compose(parts, gap):
    """Lay glyphs out left to right, centred in the label, baseline preserved."""
    total = sum(len(g[0]) for g in parts) + gap * (len(parts) - 1)
    x0 = (W - total) // 2
    out = [[(0, 0)] * W for _ in range(H)]
    x = x0
    for g in parts:
        gw = len(g[0])
        for y in range(min(H, len(g))):
            for i in range(gw):
                if 0 <= x + i < W:
                    out[y][x + i] = g[y][i]
        x += gw + gap
    return out

def encode_ia4(px):
    w, h = len(px[0]), len(px)
    data = bytearray()
    for ty in range(0, h, 4):
        for tx in range(0, w, 8):
            for y in range(4):
                for x in range(8):
                    if ty+y < h and tx+x < w:
                        inten, alpha = px[ty+y][tx+x]
                    else:
                        inten = alpha = 0
                    data.append(((alpha // 17) << 4) | (inten // 17))
    return bytes(data)
