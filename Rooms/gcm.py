"""Pull a file out of a GameCube disc image.

The format is simple: a header at 0x400 points at the FST, which is a flat
array of 12-byte entries plus a string table. Directories carry their end
index, files their offset and length.
"""
import struct, sys

def read_fst(iso):
    with open(iso, "rb") as f:
        f.seek(0x424); fst_off = struct.unpack(">I", f.read(4))[0]
        f.seek(0x428); fst_size = struct.unpack(">I", f.read(4))[0]
        f.seek(fst_off); fst = f.read(fst_size)
    count = struct.unpack(">I", fst[8:12])[0]
    strings = fst[count * 12:]
    out = {}
    for i in range(count):
        e = fst[i*12:(i+1)*12]
        is_dir = e[0] == 1
        name_off = int.from_bytes(e[1:4], "big")
        a, b = struct.unpack(">II", e[4:12])
        end = strings.find(b"\0", name_off)
        name = strings[name_off:end].decode("ascii", "replace")
        if not is_dir:
            out[name] = (a, b)
    return out

if __name__ == "__main__":
    iso, want = sys.argv[1], sys.argv[2]
    files = read_fst(iso)
    if want == "--list":
        for n in sorted(files):
            print("%-20s %8d bytes @ 0x%X" % (n, files[n][1], files[n][0]))
    else:
        off, size = files[want]
        with open(iso, "rb") as f:
            f.seek(off); data = f.read(size)
        open(sys.argv[3], "wb").write(data)
        print("%s  %d bytes from 0x%X" % (sys.argv[3], size, off))
