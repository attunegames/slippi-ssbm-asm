"""Pull a file out of the Melee ISO by name.

melee_dis.py reads main.dol straight out of the ISO; this does the same for
everything else on the disc, so a menu's art can be looked at without anyone
having to keep an unpacked copy around.

    python iso_extract.py --list Mn            # every file whose name has "Mn"
    python iso_extract.py MnSlMap.usd out.usd

GCM layout: the FST offset is at 0x424 and its size at 0x428. The FST is a flat
array of 12-byte entries - a flag byte, a 3-byte name offset into the string
table that follows, then two words whose meaning depends on the flag - with
entry 0's length giving the number of entries.
"""
import argparse, os, struct, sys

DEFAULT_ISO = os.environ.get("MELEE_ISO", "")


def entries(f):
    f.seek(0x424)
    fst_off, fst_size = struct.unpack(">2I", f.read(8))
    f.seek(fst_off)
    fst = f.read(fst_size)
    count = struct.unpack(">I", fst[8:12])[0]
    strings = count * 12
    for i in range(count):
        flag, n0, n1, n2, a, b = struct.unpack(">6B", fst[i*12:i*12+6]) if False else (
            fst[i*12], fst[i*12+1], fst[i*12+2], fst[i*12+3], 0, 0)
        name_off = (n0 << 16) | (n1 << 8) | n2
        off, size = struct.unpack(">2I", fst[i*12+4:i*12+12])
        if flag:                       # a directory, not a file
            continue
        end = fst.index(b"\0", strings + name_off)
        yield fst[strings + name_off:end].decode("ascii", "replace"), off, size


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name", nargs="?")
    ap.add_argument("out", nargs="?")
    ap.add_argument("--list", dest="pat", default=None)
    ap.add_argument("--iso", default=DEFAULT_ISO)
    args = ap.parse_args()
    if not args.iso or not os.path.exists(args.iso):
        raise SystemExit("need an ISO: --iso, or set MELEE_ISO")
    f = open(args.iso, "rb")

    if args.pat is not None:
        n = 0
        for name, off, size in entries(f):
            if args.pat.lower() in name.lower():
                print("%-24s %8d bytes" % (name, size)); n += 1
        print("-- %d" % n, file=sys.stderr)
        return

    for name, off, size in entries(f):
        if name == args.name:
            f.seek(off)
            open(args.out, "wb").write(f.read(size))
            print("wrote %s, %d bytes" % (args.out, size))
            return
    raise SystemExit("%s is not on the disc" % args.name)


main()
