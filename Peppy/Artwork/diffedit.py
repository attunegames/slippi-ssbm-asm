"""Slippi added 6 keys to this track. What does their edit look like?"""
import sys, struct
sys.path.insert(0, r"C:\root\peppy-assets")
from dat import Dat

def track(name, fobj):
    d = Dat(name)
    raw = d.data[d.u32(fobj+0x10):d.u32(fobj+0x10)+d.u32(fobj+4)]
    i, t, keys = 2, 0, []
    while i < len(raw)-1:
        v = raw[i]; i += 1; n = 0
        while True:
            x = raw[i]; i += 1; n = (n<<7)|(x&0x7F)
            if not (x & 0x80): break
        keys.append((t, v, n)); t += n
    return raw, keys

ro, ko = track("MnMaAll.orig.usd",   0x0BFDC4)
rs, ks = track("MnMaAll.slippi.usd", 0x209C18)
ko = [(t, v//4, n) for (t, v, n) in ko]      # vanilla stores byte offsets

vo = {t: v for (t, v, _) in ko}
vs = {t: v for (t, v, _) in ks}
frames = sorted(set(vo) | set(vs))
print("frame   vanilla  slippi")
for f in frames:
    a, b = vo.get(f), vs.get(f)
    if a == b and f < 130: continue
    tag = "" if a == b else ("  <- ADDED" if a is None else
          "  <- REMOVED" if b is None else "  <- CHANGED")
    print("  %5d   %-7s  %-6s%s" % (f, a if a is not None else "-",
                                    b if b is not None else "-", tag))
print("\nvanilla %d keys, slippi %d keys" % (len(ko), len(ks)))
print("vanilla images 58, slippi images 64  (+6)")
print("\nbytes, vanilla: %s" % ro.hex())
print("\nbytes, slippi : %s" % rs.hex())
