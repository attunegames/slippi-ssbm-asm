import sys
sys.path.insert(0, r"C:\root\peppy-assets")
from dat import Dat
from tex import decode_ia4, write_sheet
d = Dat("MnMaAll.roomslist.usd")
tbl = d.u32(0x0C843C + 0x0C)
def px(i):
    desc = d.u32(tbl + 4*i); p = d.u32(desc)
    return decode_ia4(d.data[p:p+176*32], 176, 30)
lo, hi, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
rows = []
for i in range(lo, hi):
    desc = d.u32(tbl + 4*i)
    if d.u16(desc+4) != 176: rows.append([[(0,0)]*176 for _ in range(30)])
    else: rows.append(px(i))
write_sheet(out, rows)
print("%s = images %d..%d" % (out, lo, hi-1))
