"""Just enough PowerPC to read what a function does."""
import struct

def dis(w, pc):
    op = w >> 26
    rd, ra, rb = (w >> 21) & 31, (w >> 16) & 31, (w >> 11) & 31
    simm = w & 0xFFFF
    if simm >= 0x8000: simm -= 0x10000
    if w == 0x4E800020: return "blr"
    if w == 0x4E800421: return "bctrl"
    if w == 0x7C0802A6: return "mflr r0"
    if w == 0x7C0803A6: return "mtlr r0"
    if op == 14: return ("li r%d, %d" % (rd, simm)) if ra == 0 else "addi r%d, r%d, %d" % (rd, ra, simm)
    if op == 15: return "lis r%d, 0x%04X" % (rd, w & 0xFFFF)
    if op == 24: return "ori r%d, r%d, 0x%04X" % (ra, rd, w & 0xFFFF)
    if op == 32: return "lwz r%d, %d(r%d)" % (rd, simm, ra)
    if op == 34: return "lbz r%d, %d(r%d)" % (rd, simm, ra)
    if op == 36: return "stw r%d, %d(r%d)" % (rd, simm, ra)
    if op == 37: return "stwu r%d, %d(r%d)" % (rd, simm, ra)
    if op == 38: return "stb r%d, %d(r%d)" % (rd, simm, ra)
    if op == 11: return "cmpwi r%d, %d" % (ra, simm)
    if op == 18:
        t = w & 0x03FFFFFC
        if t >= 0x02000000: t -= 0x04000000
        return "%s 0x%X" % ("bl" if w & 1 else "b", (0 if w & 2 else pc) + t)
    if op == 16:
        t = w & 0xFFFC
        if t >= 0x8000: t -= 0x10000
        bo, bi = rd, ra
        name = {12: "bt", 4: "bf"}.get(bo & 0x1E, "bc")
        cond = {0: "lt", 1: "gt", 2: "eq"}.get(bi & 3, "?")
        if (bo & 0x1E) == 12: name = "b" + cond
        elif (bo & 0x1E) == 4: name = "bn" + cond
        return "%s 0x%X" % (name, pc + t)
    if op == 31:
        x = (w >> 1) & 0x3FF
        if x == 444: return "mr r%d, r%d" % (ra, rd) if rd == rb else "or r%d, r%d, r%d" % (ra, rd, rb)
        if x == 467: return "mtctr r%d" % rd if ((w >> 11) & 0x3FF) == 0x120 else "mtspr"
        if x == 339: return "mfspr r%d" % rd
        return "op31/%d r%d, r%d, r%d" % (x, rd, ra, rb)
    return ".long 0x%08X" % w

def dump(data, start, n, base=0):
    out = []
    for i in range(n):
        off = start + i*4
        if off + 4 > len(data): break
        w = struct.unpack(">I", data[off:off+4])[0]
        out.append("  %06X  %08X  %s" % (off, w, dis(w, base + off)))
    return "\n".join(out)
