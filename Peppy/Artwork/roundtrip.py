"""Write Slippi's file back out through my builder's reconstruction, changing
nothing. If it is not byte-identical, the writer is broken independently of any
keyframe logic - and that would explain every failed build."""
import sys, struct
sys.path.insert(0, r"C:\root\peppy-assets")
from dat import Dat

src = r"C:\root\peppy-assets\MnMaAll.slippi.usd"
d = Dat(src)
data = bytearray(d.data)
relocs = set(d.relocs)

out = bytearray()
out += struct.pack(">5I", 0, len(data), len(relocs), d.root_count, d.ref_count)
out += d.raw[0x14:0x20] + data
for r in sorted(relocs): out += struct.pack(">I", r)
for off, nm in d.roots: out += struct.pack(">II", off, nm)
out += d.strings
out[0:4] = struct.pack(">I", len(out))

orig = d.raw
print("input  %d bytes" % len(orig))
print("output %d bytes" % len(out))
if bytes(out) == orig:
    print("IDENTICAL - the writer is faithful")
else:
    print("DIFFERS")
    for i in range(min(len(out), len(orig))):
        if out[i] != orig[i]:
            print("  first difference at 0x%06X: wrote %02X, original %02X" % (i, out[i], orig[i]))
            print("  (data block is 0x20..0x%06X, reloc table starts 0x%06X)"
                  % (0x20+d.data_size, 0x20+d.data_size))
            break
    n = sum(1 for a, b in zip(out, orig) if a != b)
    print("  %d differing bytes, length delta %d" % (n, len(out)-len(orig)))
    # where do the differences live?
    dstart, rstart = 0x20, 0x20 + d.data_size
    rend = rstart + 4*d.reloc_count
    send = rend + 8*(d.root_count + d.ref_count)
    zones = {"header":0, "data":0, "relocs":0, "roots":0, "strings":0}
    for i in range(min(len(out), len(orig))):
        if out[i] == orig[i]: continue
        zones["header" if i < 0x20 else "data" if i < rstart else
              "relocs" if i < rend else "roots" if i < send else "strings"] += 1
    print("  by zone:", zones)
