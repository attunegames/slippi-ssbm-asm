"""Attach an m-ex code module to a minor scene in MxScn.dat.

The scene table is Melee's global minor-scene list, extended by m-ex with a
per-scene code file:

    u8 minorId; u8 pad[3];  void *think; void *load; void *leave;
    char *codeFile;                                       /* 0x14 bytes */

Slippi attaches SlippiCSS.dat to scene 0x08 (the CSS) this way.  We append the
new filename to the end of the data block rather than growing the table, so
every existing offset -- relocations, roots, the other two filename pointers --
stays exactly where it was.

    python mxscn.py MxScn.dat 0x01 PeppyBoot.dat -o MxScn.dat
"""
import argparse, struct, sys

TABLE = 0x22A0          # minors table, data-relative
STRIDE = 0x14
FILE_FIELD = 0x10


class Scn:
    def __init__(self, path):
        d = self.raw = open(path, "rb").read()
        (self.filesize, self.datasize, self.nreloc,
         self.nroot, self.nref) = struct.unpack(">IIIII", d[:20])
        self.head = d[20:0x20]
        o = 0x20
        self.data = bytearray(d[o:o + self.datasize]); o += self.datasize
        self.relocs = [struct.unpack(">I", d[o + 4*i:o + 4*i + 4])[0]
                       for i in range(self.nreloc)]
        o += 4 * self.nreloc
        n = self.nroot + self.nref
        self.roots = [struct.unpack(">II", d[o + 8*i:o + 8*i + 8])
                      for i in range(n)]
        o += 8 * n
        self.strings = d[o:self.filesize]

    def u32(self, off):
        return struct.unpack(">I", self.data[off:off + 4])[0]

    def entries(self):
        for i in range((len(self.data) - TABLE) // STRIDE):
            off = TABLE + STRIDE * i
            ident = self.data[off]
            think, load, leave, f = (self.u32(off + 4), self.u32(off + 8),
                                     self.u32(off + 0xC), self.u32(off + 0x10))
            # The table ends where the filename strings begin.
            if not all(v == 0 or 0x80000000 <= v < 0x80500000
                       for v in (think, load, leave)):
                return
            yield i, off, ident, f

    def find(self, minor_id):
        for i, off, ident, f in self.entries():
            if ident == minor_id:
                return off, f
        raise KeyError(f"no scene with minor id {minor_id:#04x}")

    def cstr(self, off):
        return self.data[off:self.data.index(b"\0", off)].decode()

    def add(self, minor_id, filename=None, think=0, load=0, leave=0):
        """Append a brand-new scene to the table.

        Melee never enters an id it does not know, so a scene invented here is
        ours alone -- which is how Slippi's GameSetup (id 0x50) works.  The
        table is immediately followed by the filename strings, so growing it
        pushes those along and every pointer at them has to move with it."""
        for _, _, ident, _ in self.entries():
            if ident == minor_id:
                raise ValueError(f"scene {minor_id:#04x} already exists")
        # Insert BEFORE the table's last entry, which is where Slippi put its own
        # GameSetup scene rather than appending past it.
        offs = [off for _, off, _, _ in self.entries()]
        if not offs:
            raise ValueError("no entries found")
        end = offs[-1]

        # Everything at or past the insertion point slides up by one entry.
        self.data[end:end] = bytes(STRIDE)
        for i, r in enumerate(self.relocs):
            if r >= end:
                self.relocs[i] = r + STRIDE
        for r in self.relocs:
            v = self.u32(r)
            if v >= end:
                struct.pack_into(">I", self.data, r, v + STRIDE)

        self.data[end] = minor_id
        for k, fn in ((0x04, think), (0x08, load), (0x0C, leave)):
            struct.pack_into(">I", self.data, end + k, fn)

        # A scene with no code file of its own.  Copying one of Melee's this way
        # is how you get that scene WITHOUT whatever module is attached to it.
        if filename is None:
            return end, None

        while len(self.data) % 4:
            self.data.append(0)
        name_off = len(self.data)
        self.data += filename.encode() + bytes(1)
        while len(self.data) % 4:
            self.data.append(0)
        struct.pack_into(">I", self.data, end + FILE_FIELD, name_off)
        self.relocs.append(end + FILE_FIELD)
        self.relocs.sort()
        return end, name_off

    def attach(self, minor_id, filename):
        off, existing = self.find(minor_id)
        if existing:
            raise ValueError(
                f"scene {minor_id:#04x} already loads {self.cstr(existing)!r}; "
                f"attaching a second module to one scene is not something m-ex "
                f"supports")
        # Append the name past everything the file already points at.
        while len(self.data) % 4:
            self.data.append(0)
        name_off = len(self.data)
        self.data += filename.encode() + b"\0"
        while len(self.data) % 4:
            self.data.append(0)
        struct.pack_into(">I", self.data, off + FILE_FIELD, name_off)
        field = off + FILE_FIELD
        if field not in self.relocs:
            self.relocs.append(field)
            self.relocs.sort()
        return name_off

    def write(self, path):
        out = bytearray()
        out += struct.pack(">IIIII", 0, len(self.data), len(self.relocs),
                           self.nroot, self.nref)
        out += self.head
        out += self.data
        for r in self.relocs:
            out += struct.pack(">I", r)
        for o, s in self.roots:
            out += struct.pack(">II", o, s)
        out += self.strings
        struct.pack_into(">I", out, 0, len(out))
        open(path, "wb").write(bytes(out))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scn")
    ap.add_argument("minor", nargs="?")
    ap.add_argument("module", nargs="?")
    ap.add_argument("-o", "--out")
    ap.add_argument("-l", "--list", action="store_true")
    ap.add_argument("--add", action="store_true",
                    help="create the scene instead of attaching to an existing one")
    a = ap.parse_args()

    scn = Scn(a.scn)
    if a.list or not a.minor:
        for i, off, ident, f in scn.entries():
            print(f"  {ident:#04x} @{off:#06x}  {scn.cstr(f) if f else ''}")
        return
    minor = int(a.minor, 0)
    if a.add:
        off, name_off = scn.add(minor, a.module)
        print(f"scene {minor:#04x} created at {off:#06x} -> {a.module} "
              f"(string at {name_off:#x})")
    else:
        off = scn.attach(minor, a.module)
        print(f"scene {minor:#04x} -> {a.module} (string at {off:#x})")
    scn.write(a.out or a.scn)


if __name__ == "__main__":
    main()
