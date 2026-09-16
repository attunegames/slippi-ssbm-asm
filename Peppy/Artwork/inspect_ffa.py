import sys
sys.path.insert(0, r"C:\root\peppy-assets")
from dat import Dat
from tex import decode_ia4, write_sheet

d = Dat("MnMaAll.roomslist.usd")
tbl = d.u32(0x0C843C + 0x0C)
def px(i):
    desc = d.u32(tbl + 4*i); p = d.u32(desc)
    return decode_ia4(d.data[p:p+176*32], 176, 30)

def zoom(img, s):
    return [[img[y//s][x//s] for x in range(len(img[0])*s)] for y in range(len(img)*s)]

# FFA is slot 2; its sources are label 47 (F) and label 32 (A), which shifted +5
write_sheet("ffa_check.png", [zoom(px(2), 5), zoom(px(47+5), 5), zoom(px(32+5), 5)])
print("composed FFA, then the label F is cut from, then the label A is cut from")

def cores(p, t=140):
    col = [any(p[y][x][0] > t and p[y][x][1] > 100 for y in range(len(p))) for x in range(len(p[0]))]
    r, s = [], None
    for x, on in enumerate(col + [False]):
        if on and s is None: s = x
        elif not on and s is not None:
            if x - s >= 2: r.append((s, x))
            s = None
    return r
for i, tag in ((2, "FFA"), (52, "F source"), (37, "A source")):
    c = cores(px(i))
    print("%-10s %2d cores, widths %s, gaps %s"
          % (tag, len(c), [b-a for a, b in c], [c[k+1][0]-c[k][1] for k in range(len(c)-1)]))
