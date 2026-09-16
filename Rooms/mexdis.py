"""Disassemble an m-ex module's code with relocations applied."""
import struct, sys
from ppc import dis

BASE = 0x81000000

def relocate(path):
    d = open(path, "rb").read()
    fs, ds, nr, nroot, nref = struct.unpack(">IIIII", d[:20])
    D = d[0x20:0x20 + ds]
    roff = 0x20 + ds; rootoff = roff + nr * 4
    stroff = rootoff + 8 * (nroot + nref)
    fn = None
    for i in range(nroot + nref):
        o, s = struct.unpack(">II", d[rootoff + 8*i:rootoff + 8*i + 8])
        if d[stroff + s:d.index(b"\0", stroff + s)] == b"mnFunction":
            fn = o
    code, rel, nrel, exp, nexp = struct.unpack(">IIIII", D[fn:fn+20])
    img = bytearray(D[code:])
    for i in range(nrel):
        a, tgt = struct.unpack(">II", D[rel + 8*i:rel + 8*i + 8])
        t, off = a >> 24, a & 0xFFFFFF
        v = tgt if tgt >= 0x80000000 else BASE + tgt
        if t in (4, 6):
            h = ((v >> 16) + (1 if v & 0x8000 else 0)) if t == 6 else v
            struct.pack_into(">H", img, off, h & 0xFFFF); continue
        w = struct.unpack(">I", img[off:off+4])[0]
        if t == 1:    w = v
        elif t == 10: w = (w & 0xFC000003) | ((v - (BASE + off)) & 0x3FFFFFC)
        struct.pack_into(">I", img, off, w)
    exports = [(struct.unpack(">I", D[exp+8*i:exp+8*i+4])[0],
                struct.unpack(">I", D[exp+8*i+4:exp+8*i+8])[0])
               for i in range(nexp)]
    return img, exports, D, code

if __name__ == "__main__":
    img, exports, D, code = relocate(sys.argv[1])
    start = int(sys.argv[2], 0); n = int(sys.argv[3]) if len(sys.argv) > 3 else 40
    print("exports:", [(i, hex(o)) for i, o in exports], " image", hex(len(img)))
    for k in range(n):
        o = start + 4*k
        if o + 4 > len(img): break
        w = struct.unpack(">I", img[o:o+4])[0]
        txt = dis(w, BASE + o)
        # annotate strings / data the instruction points at
        print(f"  {o:06X}  {w:08X}  {txt}")
