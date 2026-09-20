"""List the public symbols in a Melee DAT/USD file.

A DAT carries its own directory: a header, a relocation table, then a list of
public roots with a string table after them. That directory is the only way to
find out what is actually inside a file nobody has source for - which on this
branch is most of them, including the ones the draft draws its stage icons from.

    python dat_symbols.py "..../GameSetup.dat"
    python dat_symbols.py --grep Stage "..../MnSlMap.usd"

Header (big endian):
    0x00 file size   0x04 data block size   0x08 reloc count
    0x0C public root count   0x10 extern reference count
The data block starts at 0x20; relocs follow it, then roots (8 bytes each:
data offset, string offset), then the string table.
"""
import argparse, struct, sys


def symbols(path):
    b = open(path, "rb").read()
    if len(b) < 0x20:
        raise SystemExit("%s is too small to be a DAT" % path)
    _fsize, dsize, nreloc, nroot, nextref = struct.unpack(">5I", b[0:0x14])
    roots = 0x20 + dsize + nreloc * 4
    strings = roots + (nroot + nextref) * 8
    if strings > len(b):
        raise SystemExit("%s: header does not describe this file - not a DAT?" % path)

    def name(off):
        end = b.index(b"\0", strings + off)
        return b[strings + off:end].decode("ascii", "replace")

    out = []
    for i in range(nroot + nextref):
        doff, soff = struct.unpack(">2I", b[roots + i * 8: roots + i * 8 + 8])
        out.append((doff, name(soff), i >= nroot))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--grep", default="", help="only symbols containing this")
    args = ap.parse_args()
    got = symbols(args.path)
    shown = 0
    for doff, nm, is_ext in got:
        if args.grep and args.grep.lower() not in nm.lower():
            continue
        print("%-8s 0x%06x  %s" % ("extern" if is_ext else "root", doff, nm))
        shown += 1
    print("-- %d of %d" % (shown, len(got)), file=sys.stderr)


main()
