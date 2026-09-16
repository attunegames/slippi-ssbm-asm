"""Disassemble Melee, straight out of the ISO.

Most of the dead ends on this branch came from guessing at what a Melee function
does and then spending a build-and-run cycle finding out. The game's code is
sitting in the ISO the rig already has, so it can just be read.

    python melee_dis.py 0x80368458            # a function, until its blr
    python melee_dis.py 0x80368458 -n 40      # a fixed number of instructions
    python melee_dis.py 0x80432078 --words 16 # raw words, for data

The ISO is Nintendo's and is not in this repo. Point at your own with --iso or
$MELEE_ISO; there is one on each test rig next to Slippi Dolphin.exe.
"""
import argparse, os, struct, sys

DEFAULT_ISO = os.environ.get("MELEE_ISO", "")


class Dol:
    """The executable, addressed the way the game sees it."""

    def __init__(self, iso):
        f = open(iso, "rb")
        f.seek(0x420)
        base = struct.unpack(">I", f.read(4))[0]
        f.seek(base)
        hdr = f.read(0x100)
        offs = struct.unpack(">18I", hdr[0x00:0x48])
        addrs = struct.unpack(">18I", hdr[0x48:0x90])
        sizes = struct.unpack(">18I", hdr[0x90:0xD8])
        self.secs = [(addrs[i], sizes[i], base + offs[i])
                     for i in range(18) if sizes[i]]
        self.f = f

    def read(self, addr, n):
        for a, size, off in self.secs:
            if a <= addr < a + size:
                n = min(n, a + size - addr)
                self.f.seek(off + (addr - a))
                return self.f.read(n)
        raise SystemExit("0x%08x is not in any DOL section - .bss, or not code"
                         % addr)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("addr")
    ap.add_argument("-n", "--count", type=int, default=0,
                    help="instructions; default is until the function returns")
    ap.add_argument("--words", type=int, default=0, help="dump raw words instead")
    ap.add_argument("--iso", default=DEFAULT_ISO)
    args = ap.parse_args()

    if not args.iso or not os.path.exists(args.iso):
        raise SystemExit("need an ISO: --iso, or set MELEE_ISO")

    addr = int(args.addr, 0)
    dol = Dol(args.iso)

    if args.words:
        data = dol.read(addr, args.words * 4)
        for i in range(0, len(data), 4):
            print("%08x  %08x" % (addr + i, struct.unpack(">I", data[i:i + 4])[0]))
        return

    # Until the blr, because the question is almost always "what does this whole
    # function do" and counting instructions first means running it twice.
    limit = args.count or 400
    data = dol.read(addr, limit * 4)

    from capstone import Cs, CS_ARCH_PPC, CS_MODE_32, CS_MODE_BIG_ENDIAN
    md = Cs(CS_ARCH_PPC, CS_MODE_32 | CS_MODE_BIG_ENDIAN)
    for ins in md.disasm(data, addr):
        print("%08x  %08x  %-8s %s" % (
            ins.address,
            struct.unpack(">I", data[ins.address - addr:ins.address - addr + 4])[0],
            ins.mnemonic, ins.op_str))
        if not args.count and ins.mnemonic == "blr":
            break


if __name__ == "__main__":
    main()
