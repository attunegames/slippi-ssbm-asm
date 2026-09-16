"""Extract Melee's symbol map from m-ex's MxDb.dat (root `mexDebug`).

Entries are {void* start; void* end; char* name} -- the name pointer is null
for the ~14k ranges m-ex has no name for.  Emits a linker script so module C
code can call Melee by name instead of by address.
"""
import struct, re, sys

def load(path):
    d = open(path, "rb").read()
    fs, ds, nr, nroot, nref = struct.unpack(">IIIII", d[:20])
    D = d[0x20:0x20 + ds]
    roff = 0x20 + ds; rootoff = roff + nr * 4
    stroff = rootoff + 8 * (nroot + nref)
    root = None
    for i in range(nroot + nref):
        o, s = struct.unpack(">II", d[rootoff + 8*i:rootoff + 8*i + 8])
        if d[stroff + s:d.index(b"\0", stroff + s)] == b"mexDebug":
            root = o
    u32 = lambda o: struct.unpack(">I", D[o:o+4])[0]
    count, table = u32(root), u32(root + 4)
    syms = []
    for i in range(count):
        o = table + 12 * i
        start, end, name = u32(o), u32(o + 4), u32(o + 8)
        if name and name < len(D):
            e = D.index(b"\0", name)
            syms.append((start, end, D[name:e].decode("ascii", "replace")))
    return count, syms

# m-ex's names carry a signature: "Foo(r3=Bar,r4=Baz)".  Keep the identifier.
CLEAN = re.compile(r"[^A-Za-z0-9_]")

def ident(name):
    return CLEAN.sub("_", name.split("(")[0].strip()).strip("_")

if __name__ == "__main__":
    count, syms = load(sys.argv[1])
    print(f"{count} ranges, {len(syms)} named", file=sys.stderr)
    seen, out = {}, []
    for start, end, name in sorted(syms):
        n = ident(name)
        if not n or n[0].isdigit():
            continue
        if n in seen:
            if seen[n] != start:
                continue          # same name, different address: ambiguous
        seen[n] = start
        out.append((n, start))
    if len(sys.argv) > 2:
        with open(sys.argv[2], "w") as f:
            f.write("/* Generated from MxDb.dat by mxdb.py -- do not edit. */\n")
            for n, a in sorted(out, key=lambda x: x[1]):
                f.write(f"PROVIDE({n} = 0x{a:08X});\n")
    print(f"{len(out)} unique linker symbols", file=sys.stderr)
    for n, a in sorted(out, key=lambda x: x[1])[:12]:
        print(f"  {a:08X}  {n}")
