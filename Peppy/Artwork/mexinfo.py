"""Inspect an m-ex code module and verify its relocations make sense."""
import struct, sys
sys.path.insert(0, ".")
from ppc import dis

def load(path):
    d = open(path, "rb").read()
    fs, ds, nr, nroot, nref = struct.unpack(">IIIII", d[:20])
    D = d[0x20:0x20 + ds]
    roff = 0x20 + ds
    rootoff = roff + nr * 4
    stroff = rootoff + 8 * (nroot + nref)
    roots = []
    for i in range(nroot + nref):
        o, s = struct.unpack(">II", d[rootoff + 8 * i:rootoff + 8 * i + 8])
        roots.append((o, d[stroff + s:d.index(b"\0", stroff + s)].decode()))
    return D, [struct.unpack(">I", d[roff + 4 * i:roff + 4 * i + 4])[0]
               for i in range(nr)], roots

D, datrel, roots = load(sys.argv[1])
u32 = lambda o: struct.unpack(">I", D[o:o + 4])[0]
fn = next(o for o, n in roots if n == "mnFunction")
code, rel, nrel, exp, nexp = struct.unpack(">IIIII", D[fn:fn + 20])
print(f"mnFunction @{fn:#x}: code={code:#x} relocs={rel:#x} n={nrel} "
      f"exports={exp:#x} n={nexp}")
print("dat relocs:", [hex(r) for r in datrel],
      "-> expect", [hex(fn), hex(fn + 4), hex(fn + 0xC)])
print("exports:", [(u32(exp + 8 * i), hex(u32(exp + 8 * i + 4)))
                   for i in range(nexp)])

# Apply the relocations the way the loader would, with a pretend load base.
BASE = 0x81000000
img = bytearray(D[code:])
bad = 0
for i in range(nrel):
    a, tgt = struct.unpack(">II", D[rel + 8 * i:rel + 8 * i + 8])
    t, off = a >> 24, a & 0xFFFFFF
    if off + 4 > len(img):
        print(f"  !! reloc {i} offset {off:#x} past end"); bad += 1; continue
    v = tgt if tgt >= 0x80000000 else BASE + tgt
    if t in (4, 6):
        # ADDR16 relocations address the immediate halfword, i.e. instr+2
        h = ((v >> 16) + (1 if v & 0x8000 else 0)) if t == 6 else v
        struct.pack_into(">H", img, off, h & 0xFFFF)
        continue
    w = struct.unpack(">I", img[off:off + 4])[0]
    if t == 1:      # ADDR32
        w = v
    elif t == 10:   # REL24
        d_ = (v - (BASE + off)) & 0x3FFFFFC
        w = (w & 0xFC000003) | d_
    else:
        print(f"  !! unknown reloc type {t}"); bad += 1; continue
    struct.pack_into(">I", img, off, w)

print(f"\napplied {nrel} relocs at base {BASE:#x}, {bad} problems")
print("\n-- export 1 after relocation --")
e1 = u32(exp + 8 * 1 + 4)
for k in range(14):
    o = e1 + 4 * k
    w = struct.unpack(">I", img[o:o + 4])[0]
    print(f"  {BASE+o:08X}  {w:08X}  {dis(w, BASE + o)}")
