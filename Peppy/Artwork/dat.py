"""Enough of the HAL DAT format to find images.

Header is 0x20 bytes: file size, data-block size, relocation count, root count.
After the data block comes a relocation table - a list of offsets INSIDE the
data block that hold pointers - then the root nodes and a string table.

An HSD_ImageDesc is 0x18 bytes: pointer, u16 width, u16 height, u32 format,
u32 mipmap, 2 floats. Finding them is a matter of looking at every relocated
pointer and asking whether what follows looks like one.
"""
import struct, sys, collections

FMT = {0:"I4",1:"I8",2:"IA4",3:"IA8",4:"RGB565",5:"RGB5A3",6:"RGBA8",
       8:"CI4",9:"CI8",10:"CI14X2",14:"CMPR"}

class Dat:
    def __init__(self, path):
        b = open(path, "rb").read()
        self.raw = b
        (self.file_size, self.data_size, self.reloc_count,
         self.root_count, self.ref_count) = struct.unpack(">5I", b[0:20])
        self.data = b[0x20:0x20+self.data_size]
        p = 0x20 + self.data_size
        self.reloc_order = list(struct.unpack(">%dI" % self.reloc_count,
                                              b[p:p+4*self.reloc_count]))
        self.relocs = set(self.reloc_order)
        p += 4 * self.reloc_count
        self.roots = []
        for i in range(self.root_count + self.ref_count):
            off, name_off = struct.unpack(">II", b[p:p+8]); p += 8
            self.roots.append((off, name_off))
        self.strings = b[p:]
    def name(self, off):
        e = self.strings.find(b"\0", off)
        return self.strings[off:e].decode("ascii", "replace")
    def u32(self, off): return struct.unpack(">I", self.data[off:off+4])[0]
    def u16(self, off): return struct.unpack(">H", self.data[off:off+2])[0]

    def images(self):
        """Every plausible ImageDesc, by where it sits in the data block."""
        out = []
        for off in sorted(self.relocs):
            if off + 0x18 > len(self.data): continue
            ptr = self.u32(off)
            w, h = self.u16(off+4), self.u16(off+6)
            fmt = self.u32(off+8)
            if fmt not in FMT: continue
            if not (4 <= w <= 1024 and 4 <= h <= 1024): continue
            if ptr == 0 or ptr >= len(self.data): continue
            out.append((off, ptr, w, h, fmt))
        return out

if __name__ == "__main__":
    d = Dat(sys.argv[1])
    print("file %d  data %d  relocs %d  roots %d" %
          (d.file_size, d.data_size, d.reloc_count, d.root_count))
    print("--- roots ---")
    for off, no in d.roots[:40]:
        print("  0x%06X  %s" % (off, d.name(no)))
    imgs = d.images()
    print("--- %d image descriptors ---" % len(imgs))
    sizes = collections.Counter((w, h, FMT[f]) for _, _, w, h, f in imgs)
    for (w, h, f), n in sizes.most_common(25):
        print("  %4dx%-4d %-7s x%d" % (w, h, f, n))
