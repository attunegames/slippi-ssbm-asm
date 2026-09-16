"""Build MnMaAll.usd with Peppy's extra menu labels.

Nothing is removed: all 64 stock images stay byte for byte and every existing
keyframe still shows the picture it always showed. The new labels take low image
slots and the stock images shift up, with every keyframe value rewritten to
match - the list will not render an image whose slot is too high.

Each menu's row artwork is a 20-frame block, and options step by two inside it.
New labels go in the padding at the end of a block whose menu does not use it,
the same way Slippi fitted their own six into the hold at frame 142 - so the
block still ends where it did and nothing downstream moves.
"""
import sys, struct
sys.path.insert(0, r"C:\root\peppy-assets")
exec(open(r"C:\root\peppy-assets\build_labels.py").read().split("WORDS = [")[0])

SRC = r"C:\root\peppy-assets\MnMaAll.rooms.usd"
TBL, TEXANIM, FOBJ = 0x209D18, 0x0C843C, 0x209C18

# base frame -> the rows of that menu, in order
GROUPS = [
    (166, ["Singles", "Doubles", "Ironmans", "Crew Battles", "Tournaments"]),  # Stadium's padding
    (126, ["Create", "Join", "Public"]),                                  # block 120's padding
    (186, ["Private", "Public"]),                                         # block 180's padding
]

out_path = sys.argv[1] if len(sys.argv) > 1 else "MnMaAll.roomslist.usd"

# one image per distinct word, shared where a word repeats across menus
words = []
for _, ws in GROUPS:
    for t in ws:
        if t not in words: words.append(t)
slot = {t: i for i, t in enumerate(words)}
shift = len(words)

d = Dat(SRC)
images = [encode_ia4(word(t)) for t in words]

data = bytearray(d.data)
def align(n):
    while len(data) % n: data.append(0)
img_offs = []
for im in images:
    align(32); img_offs.append(len(data)); data += im
desc_offs = []
for off in img_offs:
    align(4); desc_offs.append(len(data))
    data += struct.pack(">IHHIIff", off, W, H, 2, 0, 0.0, 0.0)
align(4); new_tbl = len(data)
old_n = d.u16(TEXANIM + 0x14)
for off in desc_offs: data += struct.pack(">I", off)
for i in range(old_n): data += struct.pack(">I", d.u32(TBL + 4*i))
new_n = old_n + shift

raw = d.data[d.u32(FOBJ+0x10):d.u32(FOBJ+0x10)+d.u32(FOBJ+4)]
def rd(b, i):
    v = 0
    while True:
        x = b[i]; i += 1; v = (v << 7) | (x & 0x7F)
        if not (x & 0x80): return v, i
def wr(v):
    if v < 0x80: return bytes([v])
    o = bytearray()
    while v >= 0x80: o.insert(0, v & 0x7F); v >>= 7
    o.insert(0, v)
    for i in range(len(o)-1): o[i] |= 0x80
    return bytes(o)
i, t, keys = 2, 0, []
while i < len(raw) - 1:
    v = raw[i]; i += 1
    dur, i = rd(raw, i); keys.append((t, v, dur)); t += dur
tail = raw[i:]

# every frame we are going to occupy
insert = {}
for base, ws in GROUPS:
    for k, t in enumerate(ws):
        insert[base + 2*k] = slot[t]

starts = {k[0] for k in keys}
for f in insert:
    assert f not in starts, "frame %d already carries a keyframe" % f

buf = bytearray(raw[:2])
def emit(val, dur):
    if dur > 0: buf.extend(bytes([val]) + wr(dur))
for (tt, val, dur) in keys:
    pts = sorted(f for f in insert if tt <= f < tt + dur)
    if not pts:
        # written directly, not through emit: the track's terminator is a
        # zero-duration key and emit drops those
        buf.extend(bytes([val + shift]) + wr(dur))
        continue
    cur = tt
    for f in pts:
        emit(val + shift, f - cur)
        emit(insert[f], 2)
        cur = f + 2
    emit(val + shift, tt + dur - cur)
buf += tail
align(4); new_buf = len(data); data += buf

data[TEXANIM+0x0C:TEXANIM+0x10] = struct.pack(">I", new_tbl)
data[TEXANIM+0x14:TEXANIM+0x16] = struct.pack(">H", new_n)
data[FOBJ+0x10:FOBJ+0x14] = struct.pack(">I", new_buf)
data[FOBJ+0x04:FOBJ+0x08] = struct.pack(">I", len(buf))

# the relocation table keeps its original order; new entries go on the end
relocs = list(d.reloc_order)
seen = set(relocs)
for off in desc_offs + [new_tbl + 4*k for k in range(new_n)]:
    if off not in seen: relocs.append(off); seen.add(off)

out = bytearray()
out += struct.pack(">5I", 0, len(data), len(relocs), d.root_count, d.ref_count)
out += d.raw[0x14:0x20] + data
for r in relocs: out += struct.pack(">I", r)
for off, nm in d.roots: out += struct.pack(">II", off, nm)
out += d.strings
out[0:4] = struct.pack(">I", len(out))
open(out_path, "wb").write(bytes(out))

print("%s  %d bytes, %d images" % (out_path, len(out), new_n))
for base, ws in GROUPS:
    print("   base %3d: %s" % (base, ", ".join("%d=%s" % (base+2*k, t) for k, t in enumerate(ws))))
