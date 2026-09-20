"""Find who reaches a thing, straight out of the ISO.

melee_dis.py answers "what does this function do". This answers the question
that keeps coming first: "who calls it", and "who else touches this struct" -
both of which used to be guessed at, and guessing costs a build.

    python melee_xref.py 0x80167858             # every bl/b to a function
    python melee_xref.py 0x804735a8 --data      # every lis/addi that builds
                                                # an address, incl. r13/r2 rels

--data matters because Melee builds most struct pointers as a lis/addi or
lis/ori pair a few instructions apart, so a plain word search finds nothing.

The ISO is Nintendo's and is not in this repo. Point at your own with --iso or
$MELEE_ISO; there is one on each test rig next to Slippi Dolphin.exe.
"""
import argparse, os, struct, sys

DEFAULT_ISO = os.environ.get("MELEE_ISO", "")


class Dol:
    def __init__(self, iso):
        f = open(iso, "rb")
        f.seek(0x420)
        base = struct.unpack(">I", f.read(4))[0]
        f.seek(base)
        hdr = f.read(0x100)
        offs = struct.unpack(">18I", hdr[0x00:0x48])
        addrs = struct.unpack(">18I", hdr[0x48:0x90])
        sizes = struct.unpack(">18I", hdr[0x90:0xD8])
        self.secs = []
        for i in range(18):
            if not sizes[i]:
                continue
            f.seek(base + offs[i])
            self.secs.append((addrs[i], f.read(sizes[i])))


def branches(dol, target):
    """bl/b/bla, by the offset they encode rather than by any symbol."""
    for base, blob in dol.secs:
        for off in range(0, len(blob) - 3, 4):
            w = struct.unpack_from(">I", blob, off)[0]
            if (w >> 26) != 18:
                continue
            d = w & 0x03FFFFFC
            if d & 0x02000000:
                d -= 0x04000000
            pc = base + off
            dest = d if (w & 2) else pc + d
            if dest == target:
                yield pc, "bl" if (w & 1) else "b"


def constants(dol, target):
    """lis paired with a later addi/ori/load that lands on the address.

    The pair is not always adjacent - the compiler fills the gap - so the high
    half is remembered per register and matched against anything that completes
    it within a short window.
    """
    hi = target >> 16
    for base, blob in dol.secs:
        held = {}                      # reg -> (value<<16, pc)
        for off in range(0, len(blob) - 3, 4):
            w = struct.unpack_from(">I", blob, off)[0]
            pc = base + off
            op, d, a, imm = w >> 26, (w >> 21) & 31, (w >> 16) & 31, w & 0xFFFF
            if op == 15 and a == 0:                    # lis
                held[d] = (imm << 16, pc)
                continue
            if a in held and op in (14, 24, 32, 34, 36, 38, 40, 44):
                hival, at = held[a]
                if pc - at > 0x40:
                    continue
                low = imm - 0x10000 if imm & 0x8000 else imm
                # ori keeps its immediate unsigned; the rest are signed
                if op == 24:
                    low = imm
                if hival + low == target:
                    yield at, pc, d, a
            if op in (14, 15, 24) and d in held and d != a:
                held.pop(d, None)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("addr")
    ap.add_argument("--data", action="store_true",
                    help="look for address construction, not branches")
    ap.add_argument("--iso", default=DEFAULT_ISO)
    args = ap.parse_args()
    if not args.iso or not os.path.exists(args.iso):
        raise SystemExit("need an ISO: --iso, or set MELEE_ISO")

    target = int(args.addr, 0)
    dol = Dol(args.iso)
    n = 0
    if args.data:
        for at, pc, d, a in constants(dol, target):
            print("0x%08x  lis r%-2d ... 0x%08x  completes it into r%d" % (at, a, pc, d))
            n += 1
    else:
        for pc, kind in branches(dol, target):
            print("0x%08x  %s  0x%08x" % (pc, kind, target))
            n += 1
    print("-- %d" % n, file=sys.stderr)


main()
