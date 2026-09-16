"""Add five menu labels to MnMaAll.usd - purely additive.

New images, new image-table entries and new keyframes are appended; not one
existing frame, image or menu changes meaning. The five new labels live on
frames that were previously dead padding inside a 14853-frame hold.
"""
import sys, struct
sys.path.insert(0, r"C:\root\peppy-assets")
from dat import Dat
from compose import encode_ia4, W, H

SRC = r"C:\root\peppy-assets\MnMaAll.rooms.usd"   # already carries the Rooms label
OUT = r"C:\root\peppy-assets\MnMaAll.list.usd"
TBL, TEXANIM, FOBJ = 0x209D18, 0x0C843C, 0x209C18

d = Dat(SRC)

def label_px(i):
    desc = d.u32(TBL + 4*i); ptr = d.u32(desc)
    w, h = d.u16(desc+4), d.u16(desc+6)
    from tex import decode_ia4
    return decode_ia4(d.data[ptr:ptr+w*32], w, h)

def cores(px, thresh=140):
    col = [any(px[y][x][0] > thresh and px[y][x][1] > 100 for y in range(len(px)))
           for x in range(len(px[0]))]
    runs, start = [], None
    for x, on in enumerate(col + [False]):
        if on and start is None: start = x
        elif not on and start is not None:
            if x - start >= 2: runs.append((start, x))
            start = None
    return runs

_cache = {}
_base = {}
def glyph(idx, n, margin=4):
    if idx not in _cache: _cache[idx] = (label_px(idx), None)
    px = _cache[idx][0]
    c = cores(px); a, b = c[n]
    left  = (c[n-1][1] + a)//2 if n > 0 else max(0, a-margin)
    right = (b + c[n+1][0])//2 if n < len(c)-1 else min(W, b+margin)
    return [row[left:right] for row in px]

# character -> (source label, which glyph in it)
LIB = {
 'S': (25,0), 'n': (33,2), 'a': (33,1), 'e': (33,4), 'd': (33,5), 'R': (33,0),
 'i': (30,5), 'l': (30,1), 's': (30,3), 'C': (30,0), 'c': (30,6),
 'D': (58,0), 'r': (58,2), 't': (58,5),
 'o': (41,7), 'm': (41,2), 'M': (41,6),
 'u': (31,6), 'v': (31,2),
 'g': (35,3), 'T': (35,0),
 'b': (46,6), 'E': (24,0), 'U': (34,0), 'I': (46,0), 'A': (32,0), 'B': (54,0), 'P': (63,0),
}

BASELINE = 24          # where nearly every stock label sits its letters

def label_baseline(idx):
    """A few source labels sit a pixel high or low; find each one's own baseline
    so glyphs from different labels line up instead of wobbling."""
    if idx in _base: return _base[idx]
    px = _cache[idx][0] if idx in _cache else label_px(idx)
    bots = {}
    for (a, b) in cores(px):
        ys = [y for y in range(H) for x in range(a, b)
              if px[y][x][0] > 140 and px[y][x][1] > 100]
        if ys: bots[max(ys)] = bots.get(max(ys), 0) + 1
    _base[idx] = max(bots, key=bots.get) if bots else BASELINE
    return _base[idx]

def cut(idx, n, bleed=3):
    """One glyph, with its outline, plus where its white core sits inside the cut."""
    if idx not in _cache: _cache[idx] = (label_px(idx), None)
    px = _cache[idx][0]
    c = cores(px); a, b = c[n]
    left  = max(0, a - bleed)
    right = min(W, b + bleed)
    if n > 0:          left  = max(left,  c[n-1][1] + 1)
    if n < len(c) - 1: right = min(right, c[n+1][0] - 1)
    img = [row[left:right] for row in px]
    dy = BASELINE - label_baseline(idx)
    if dy:
        blank = [(0, 0)] * len(img[0])
        img = ([blank] * dy + img)[:H] if dy > 0 else (img[-dy:] + [blank] * -dy)
    return img, a - left, b - left          # image, core start, core end

def compose_f():
    """Melee has exactly one capital F, in "Fixed-Camera Mode" - its most
    condensed label - so cutting it puts a narrow, light F beside a wide, heavy
    A. Derive one from the E in "Erase Data" instead, which is the same weight
    as the A: an F is an E with the bottom arm taken off.

    The arm is not simply erased. Everything below the middle arm's underside is
    replaced with the stem's own cross-section, taken from an open row of the
    counter, so the stem keeps its outline down both sides and the arm's top
    outline goes with it; the baseline rows keep the E's own cap, clipped to the
    stem, so the bottom corner stays intact."""
    img, cs, ce = cut(*LIB['E'])
    w = len(img[0])

    def core(y):
        return sum(1 for x in range(w) if img[y][x][0] > 140 and img[y][x][1] > 100)
    rows = [y for y in range(H) if core(y) > 0]
    stem = min(core(y) for y in rows)

    # the arms, as bands of rows wider than the bare stem
    bands = []
    for y in (y for y in rows if core(y) > stem * 1.5):
        if bands and y == bands[-1][-1] + 1: bands[-1].append(y)
        else: bands.append([y])

    # a row showing the stem alone, and the stem's own width - measured as the
    # first unbroken run of ink, not the row's full extent, since the letter
    # next door in the source label bleeds into the right-hand edge
    def ink(y): return sum(1 for x in range(w) if img[y][x][1])
    gap = min((y for y in rows if y > bands[0][-1] and core(y) <= stem), key=ink)
    x0 = next(x for x in range(w) if img[gap][x][1])
    x1 = x0
    while x1 + 1 < w and img[gap][x1 + 1][1]: x1 += 1

    # start where the counter first opens up below the middle arm, so the arm
    # keeps its underside outline and the bottom arm loses its top one
    def open_row(y):
        return x1 + 1 >= w or not img[y][x1 + 1][1]
    start = next(y for y in range(bands[-2][-1] + 1, H) if open_row(y))

    out = [list(r) for r in img]
    for y in range(start, H):
        src = img[gap] if core(y) > 0 else img[y]
        out[y] = [src[x] if x0 <= x <= x1 else (0, 0) for x in range(w)]

    # Measure the core off the glyph we just built rather than inheriting the
    # E's - dropping the bottom arm makes the F a pixel narrower, and layout
    # spaces by the core, so the inherited figure opens a gap next to it.
    ink = [x for x in range(w) for y in range(H)
           if out[y][x][0] > 140 and out[y][x][1] > 100]
    return out, min(ink), max(ink) + 1


def compose_j():
    """No capital J exists in these labels either. A J is a U whose left stem has
    been cut down to a tail: keep the right stem full height, keep the bottom
    third of the left one so the hook still curves the way the U's does, and cap
    the tail with the U's own stem-top outline so the cut end is finished."""
    img, cs, ce = cut(*LIB['U'])
    w = len(img[0])

    def runs(y, core):
        out, st = [], None
        for x in range(w + 1):
            lit = x < w and ((img[y][x][0] > 140 and img[y][x][1] > 100)
                             if core else img[y][x][1])
            if lit and st is None: st = x
            elif not lit and st is not None:
                out.append((st, x)); st = None
        return out

    two = [y for y in range(H) if len(runs(y, True)) >= 2]
    top, bot = two[0], two[-1]
    tail_top = bot - (bot - top) // 3
    keep = runs(top, False)[-1][0]          # where the right stem's ink starts

    out = []
    for y in range(H):
        if y >= tail_top:
            out.append(list(img[y]))
        else:
            out.append([img[y][x] if x >= keep else (0, 0) for x in range(w)])

    # the U's own stem-top is outline with no core - reuse it to cap the tail
    cap = [y for y in range(top) if runs(y, False) and not runs(y, True)][-3:]
    for k, src in enumerate(cap):
        ty = tail_top - len(cap) + k
        if ty < 0: continue
        for x in range(keep):
            if img[src][x][1]: out[ty][x] = img[src][x]

    ink = [x for x in range(w) for y in range(H)
           if out[y][x][0] > 140 and out[y][x][1] > 100]
    return out, min(ink), max(ink) + 1


def compose_w():
    """No lowercase w exists in these labels - build one from two v's sharing a stroke."""
    v, cs, ce = cut(*LIB['v'])
    vw, cw = len(v[0]), ce - cs
    shift = cw - max(2, cw // 3)             # second v starts inside the first's last stroke
    out = [[(0,0)]*(vw + shift) for _ in range(H)]
    for src_x0 in (0, shift):
        for y in range(H):
            for x in range(vw):
                tx = src_x0 + x
                if v[y][x][1] and v[y][x][0] >= out[y][tx][0]: out[y][tx] = v[y][x]
    return out, cs, ce + shift

def word(text, gap=4, space=10):
    """Lay out by CORE spacing, letting outlines overlap - which is what Melee does.
    Cores are composited last-wins-by-intensity so a neighbour's outline never cuts
    into a letter."""
    parts = []
    for ch in text:
        if ch == ' ':   parts.append(None)
        elif ch == 'w': parts.append(compose_w())
        elif ch == 'F': parts.append(compose_f())
        elif ch == 'J': parts.append(compose_j())
        else:           parts.append(cut(*LIB[ch]))

    def layout(g, sp):
        xs, pen, first = [], 0, True
        for p in parts:
            if p is None: pen += sp; continue
            img, cs, ce = p
            xs.append((p, pen - cs if first else pen - cs))
            pen = (pen if first else pen) + 0
            first = False
            # advance the pen to just past this glyph's core
            pen = xs[-1][1] + ce + g
        if not xs: return xs, 0
        lastimg, lastcs, lastce = xs[-1][0]
        ink = (xs[-1][1] + lastce) - (xs[0][1] + xs[0][0][1])
        return xs, ink

    # One gap for every row, so the five labels read as a set. Letting short
    # words spread out to fill the plate - which is what the stock font does -
    # left Singles and Doubles visibly looser than Crew Battles and Tournaments,
    # and the long words cannot loosen to meet them because they are already at
    # the width limit. So the long words set the spacing and the short ones
    # match it; 2 is inside the 1-5 range the stock labels measure.
    best = None
    for g in range(2, 0, -1):
        sp = max(9, g + 6)
        xs, ink = layout(g, sp)
        if ink <= W - 10: best = (xs, ink); break
    xs, ink = best if best else layout(1, 5)

    # centre on the CORES, the way every stock label is centred
    lead = xs[0][1] + xs[0][0][1]
    off = (W - ink)//2 - lead
    out = [[(0,0)]*W for _ in range(H)]
    for (p, x0) in xs:
        img = p[0]; pw = len(img[0])
        for y in range(H):
            for i in range(pw):
                tx = x0 + off + i
                if 0 <= tx < W and img[y][i][1] and img[y][i][0] >= out[y][tx][0]:
                    out[y][tx] = img[y][i]
    return out

WORDS = ["Singles", "Doubles", "FFA", "Crew Battles", "Tournaments"]
images = [encode_ia4(word(t)) for t in WORDS]
print("composed:", ", ".join(WORDS))

# ---- append everything ------------------------------------------------------
data = bytearray(d.data)
def align(n):
    while len(data) % n: data.append(0)

img_offs = []
for im in images:
    align(32); img_offs.append(len(data)); data += im

desc_offs = []
for off in img_offs:
    align(4); desc_offs.append(len(data))
    data += struct.pack(">IHHIIff", off, W, H, 2, 0, 0.0, 0.0)   # format 2 = IA4

align(4); new_tbl = len(data)
old_n = d.u16(TEXANIM + 0x14)
for i in range(old_n): data += struct.pack(">I", d.u32(TBL + 4*i))
for off in desc_offs: data += struct.pack(">I", off)
new_n = old_n + len(desc_offs)

# ---- keyframes: split the long tail hold and slot the new frames inside ------
raw = d.data[d.u32(FOBJ+0x10):d.u32(FOBJ+0x10)+d.u32(FOBJ+4)]
def rd_varint(b, i):
    v = 0
    while True:
        x = b[i]; i += 1
        v = (v << 7) | (x & 0x7F)
        if not (x & 0x80): return v, i
def wr_varint(v):
    if v < 0x80: return bytes([v])
    return bytes([0x80 | (v >> 7), v & 0x7F])

i, t = 2, 0
keys = []
while i < len(raw) - 1:
    val = raw[i]; i += 1
    dur, i = rd_varint(raw, i)
    keys.append([t, val, dur]); t += dur
tail = raw[i:]                      # the final terminator pair

longest = max(keys, key=lambda k: k[2])
base_frame = longest[0] + 2
print("longest hold: image %d at frame %d for %d frames -> new labels at %d"
      % (longest[1], longest[0], longest[2], base_frame))

buf = bytearray(raw[:2])
for (tt, val, dur) in keys:
    if tt == longest[0] and dur == longest[2]:
        buf += bytes([val]) + wr_varint(2)
        for k in range(len(images)):
            buf += bytes([old_n + k]) + wr_varint(2)
        buf += bytes([val]) + wr_varint(dur - 2 - 2*len(images))
    else:
        buf += bytes([val]) + wr_varint(dur)
buf += tail
align(4); new_buf = len(data); data += buf

# ---- point the animation at the new table and buffer ------------------------
data[TEXANIM+0x0C:TEXANIM+0x10] = struct.pack(">I", new_tbl)
data[TEXANIM+0x14:TEXANIM+0x16] = struct.pack(">H", new_n)
data[FOBJ+0x10:FOBJ+0x14] = struct.pack(">I", new_buf)
data[FOBJ+0x04:FOBJ+0x08] = struct.pack(">I", len(buf))

# ---- relocations: every new pointer field has to be listed -------------------
relocs = set(d.relocs)
for k in range(new_n): relocs.add(new_tbl + 4*k)
for off in desc_offs: relocs.add(off)

out = bytearray()
out += struct.pack(">5I", 0, len(data), len(relocs), d.root_count, d.ref_count)
out += d.raw[0x14:0x20]
out += data
for r in sorted(relocs): out += struct.pack(">I", r)
for off, name in d.roots: out += struct.pack(">II", off, name)
out += d.strings
out[0:4] = struct.pack(">I", len(out))
open(OUT, "wb").write(bytes(out))
print("wrote %s  %d bytes (was %d), %d relocs (was %d), table %d entries"
      % (OUT, len(out), len(d.raw), len(relocs), d.reloc_count, new_n))
print("SET THE ROOMS LIST BASE TO %d" % base_frame)
