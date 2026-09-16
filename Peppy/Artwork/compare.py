"""How did Slippi add their menu labels? Diff the ISO's file against the patched one."""
import sys, struct
sys.path.insert(0, r"C:\root\peppy-assets")
from dat import Dat

def texanims(d):
    """Structs whose aobj and imagetbl are both relocated and whose images are
    the 176x30 menu labels."""
    out = []
    for r in sorted(d.relocs):
        ta = r - 0x0C
        if ta < 0 or ta + 0x20 > len(d.data) or (ta + 0x08) not in d.relocs: continue
        n = struct.unpack(">H", d.data[ta+0x14:ta+0x16])[0]
        if not (8 < n < 300): continue
        tbl = d.u32(ta + 0x0C)
        try:
            desc = d.u32(tbl)
            if d.u16(desc+4) == 176 and d.u16(desc+6) == 30:
                out.append((ta, n, tbl, d.u32(ta+0x08)))
        except Exception:
            pass
    return out

for name in ("MnMaAll.orig.usd", "MnMaAll.slippi.usd"):
    d = Dat(name)
    print("=== %s  (data block %d bytes) ===" % (name, len(d.data)))
    for (ta, n, tbl, aobj) in texanims(d):
        fobj = d.u32(aobj + 8)
        blen = d.u32(fobj + 4)
        buf = d.u32(fobj + 0x10)
        raw = d.data[buf:buf+blen]
        print("  texanim @%06X  images=%-3d table=%06X  aobj=%06X endframe=%g"
              % (ta, n, tbl, aobj, struct.unpack(">f", d.data[aobj+4:aobj+8])[0]))
        print("     fobj @%06X len=%-4d datatype=%02X animkind=%02X buffer=%06X"
              % (fobj, blen, d.data[fobj+0x0C], d.data[fobj+0x0D], buf))
        print("     first 32 bytes: %s" % raw[:32].hex())
