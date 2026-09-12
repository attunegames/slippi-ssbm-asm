"""Pack a linked PowerPC ELF into an m-ex code module (HAL DAT, root `mnFunction`).

Format reverse-engineered from Slippi's SlippiCSS.dat; see NOTES-mex-modules.md.

    powerpc-eabi-gcc -c -O2 -mcpu=750 -meabi -mhard-float ... *.c
    powerpc-eabi-ld -T module.ld --emit-relocs -o module.elf *.o
    python mexpack.py module.elf PeppyCSS.dat

The linker script places .text at 0 and supplies Melee's absolute symbols, so
references to the game bake in as constants and carry no relocation -- exactly
how Slippi's module addresses 0x8026688c.
"""
import struct, sys

# ELF PPC relocation types the m-ex loader implements.  Everything else is a
# hard error: silently dropping a relocation produces a module that loads and
# then jumps into the weeds.
R_PPC_ADDR32    = 1
R_PPC_ADDR16_LO = 4
R_PPC_ADDR16_HA = 6
R_PPC_REL24     = 10
SUPPORTED = {R_PPC_ADDR32, R_PPC_ADDR16_LO, R_PPC_ADDR16_HA, R_PPC_REL24}

# Targets at or above this are addresses in the game, passed through
# untouched; anything below is an offset the loader adds the base to.
GAME_BASE = 0x80000000

SHT_RELA, SHT_NOBITS, SHT_SYMTAB = 4, 8, 2
SHF_ALLOC = 0x2


class Elf:
    def __init__(self, path):
        d = self.data = open(path, "rb").read()
        if d[:4] != b"\x7fELF" or d[4] != 1 or d[5] != 2:
            raise ValueError("not a 32-bit big-endian ELF")
        (self.shoff, self.shentsize, self.shnum,
         self.shstrndx) = struct.unpack(">I10xHHH", d[0x20:0x34])
        self.sections = [self._sec(i) for i in range(self.shnum)]
        strtab = self.sections[self.shstrndx]
        for s in self.sections:
            e = d.index(b"\0", strtab["off"] + s["name"])
            s["sname"] = d[strtab["off"] + s["name"]:e].decode()

    def _sec(self, i):
        o = self.shoff + i * self.shentsize
        f = struct.unpack(">10I", self.data[o:o + 40])
        return dict(name=f[0], type=f[1], flags=f[2], addr=f[3], off=f[4],
                    size=f[5], link=f[6], info=f[7], align=f[8], entsize=f[9])

    def by_name(self, n):
        return next((s for s in self.sections if s["sname"] == n), None)

    def symbols(self):
        sym = next(s for s in self.sections if s["type"] == SHT_SYMTAB)
        strt = self.sections[sym["link"]]
        out = []
        for i in range(sym["size"] // 16):
            o = sym["off"] + i * 16
            nm, val, sz, info, other, shndx = struct.unpack(
                ">IIIBBH", self.data[o:o + 16])
            e = self.data.index(b"\0", strt["off"] + nm)
            out.append(dict(name=self.data[strt["off"] + nm:e].decode(),
                            value=val, shndx=shndx))
        return out


def build(elf_path, out_path, exports):
    """exports: list of (id, symbol_name) -- the scene functions m-ex calls."""
    elf = Elf(elf_path)

    # --- flatten the allocatable sections into one image ------------------
    alloc = [s for s in elf.sections
             if (s["flags"] & SHF_ALLOC) and s["size"]]
    alloc.sort(key=lambda s: s["addr"])
    if not alloc:
        raise ValueError("no allocatable sections")
    base = alloc[0]["addr"]
    end = max(s["addr"] + s["size"] for s in alloc)
    image = bytearray(end - base)
    for s in alloc:
        if s["type"] != SHT_NOBITS:          # .bss contributes zeroes only
            o = s["addr"] - base
            image[o:o + s["size"]] = elf.data[s["off"]:s["off"] + s["size"]]

    # --- collect relocations ---------------------------------------------
    syms = elf.symbols()
    relocs = []
    for rs in elf.sections:
        if rs["type"] != SHT_RELA:
            continue
        target = elf.sections[rs["info"]]
        if not (target["flags"] & SHF_ALLOC):
            continue
        for i in range(rs["size"] // 12):
            o = rs["off"] + i * 12
            off, info, addend = struct.unpack(">IIi", elf.data[o:o + 12])
            rtype, symidx = info & 0xFF, info >> 8
            value = syms[symidx]["value"] + addend
            if rtype not in SUPPORTED:
                raise ValueError(
                    f"{rs['sname']}+{off:#x}: relocation type {rtype} against "
                    f"{syms[symidx]['name']!r} is not supported by the loader")
            if base <= value < end:
                # Module-internal.  A relative branch inside one contiguous
                # image is already correct wherever the module lands, so the
                # linker's value stands and the loader must not touch it --
                # which is why neither of Slippi's modules has a single
                # internal REL24.
                if rtype == R_PPC_REL24:
                    continue
                target = value - base
            elif value >= GAME_BASE:
                # A call into Melee.  The loader recognises the high target and
                # uses it verbatim instead of adding the load address, so the
                # REL24 displacement comes out right at whatever base we land.
                target = value
            else:
                raise ValueError(
                    f"{rs['sname']}+{off:#x}: {syms[symidx]['name']!r} resolves "
                    f"to {value:#x}, neither inside the module nor in the game")
            relocs.append((rtype, off - base, target))
    relocs.sort(key=lambda r: r[1])

    # --- lay the module out the way Slippi's do -----------------------
    # relocation table, code, mnFunction, export table.  Matching their order
    # is not cosmetic: in SlippiCSS.dat the header is followed by 36 more
    # bytes of data block, so mnFunction is 0x20 wide with three spare words
    # after the five documented fields.  A packer that stops at 0x14 leaves
    # the loader writing its scratch straight past the end of the data block
    # and into the DAT relocation table.
    FN_SIZE = 0x20

    data = bytearray()

    def align(n):
        while len(data) % n:
            data.append(0)

    reloc_off = len(data)
    for rtype, off, tgt in relocs:
        data += struct.pack(">II", (rtype << 24) | off, tgt)

    align(32)                      # code is cache-flushed; keep it on a line
    code_off = len(data)
    data += image

    align(4)
    fn_off = len(data)
    export_off = fn_off + FN_SIZE
    data += struct.pack(">IIIII", code_off, reloc_off, len(relocs),
                        export_off, len(exports))
    data += bytes(FN_SIZE - 20)

    name_to_off = {s["name"]: s["value"] - base for s in syms}
    assert len(data) == export_off
    for eid, sym in exports:
        if sym not in name_to_off:
            raise ValueError(f"export {eid}: no symbol {sym!r} in {elf_path}")
        data += struct.pack(">II", eid, name_to_off[sym])
    align(4)

    # code / relocs / exports are the three pointers the loader fixes up, in
    # the order Slippi's files list them.
    dat_relocs = [fn_off + 0x0C, fn_off + 0x00, fn_off + 0x04]

    # --- wrap in a HAL DAT with the single `mnFunction` root --------------
    ds = len(data)
    out = bytearray()
    out += struct.pack(">IIIII", 0, ds, len(dat_relocs), 1, 0)
    out += b"\0" * 12                       # rest of the 0x20 header
    out += data
    for r in dat_relocs:
        out += struct.pack(">I", r)
    out += struct.pack(">II", fn_off, 0)    # root: mnFunction
    out += b"mnFunction\0"
    while len(out) % 4:
        out.append(0)
    struct.pack_into(">I", out, 0, len(out))
    open(out_path, "wb").write(out)
    return dict(image=len(image), relocs=len(relocs),
                exports=len(exports), total=len(out))


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("usage: mexpack.py module.elf out.dat [id=symbol ...]")
    ex = [(int(a.split("=")[0]), a.split("=")[1]) for a in sys.argv[3:]]
    print(build(sys.argv[1], sys.argv[2], ex or [(0, "_start")]))
