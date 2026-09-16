import sys, struct
sys.path.insert(0, r"C:\root\peppy-assets")
from dat import Dat

def track(name, fobj):
    d = Dat(name)
    blen, buf = d.u32(fobj+4), d.u32(fobj+0x10)
    raw = d.data[buf:buf+blen]
    i, t, keys = 2, 0, []
    while i < len(raw)-1:
        v = raw[i]; i += 1; n = 0
        while True:
            x = raw[i]; i += 1; n = (n<<7)|(x&0x7F)
            if not (x & 0x80): break
        keys.append((t, v, n)); t += n
    return d, raw, keys

do, ro, ko = track("MnMaAll.orig.usd",   0x0BFDC4)
ds, rs, ks = track("MnMaAll.slippi.usd", 0x209C18)

print("vanilla: header %s  %d keys  animkind %02X" % (ro[:2].hex(), len(ko), do.data[0x0BFDC4+0x0D]))
print("slippi : header %s  %d keys  animkind %02X" % (rs[:2].hex(), len(ks), ds.data[0x209C18+0x0D]))
print("\nvanilla values: %s" % [k[1] for k in ko[:14]])
print("slippi  values: %s" % [k[1] for k in ks[:14]])
print("\nvanilla frames: %s" % [k[0] for k in ko[:14]])
print("slippi  frames: %s" % [k[0] for k in ks[:14]])
print("\nvanilla value step: %s" % sorted({ko[i+1][1]-ko[i][1] for i in range(len(ko)-1)})[:6])
print("vanilla max value %d, images %d  ->  value/4 = %d"
      % (max(k[1] for k in ko), 58, max(k[1] for k in ko)//4))
print("slippi  max value %d, images %d" % (max(k[1] for k in ks), 64))
print("\nvanilla track ends %d, slippi track ends %d"
      % (ko[-1][0]+ko[-1][2], ks[-1][0]+ks[-1][2]))
print("vanilla blocks:", sorted({k[0]//20*20 for k in ko}))
print("slippi  blocks:", sorted({k[0]//20*20 for k in ks}))
