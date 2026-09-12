/* m-ex code module: one contiguous image linked at zero.
 *
 * Everything lands in a single span so the packer can tell a module-internal
 * relocation target (a small offset) from a call into the game (0x8xxxxxxx).
 * Melee owns r13, so nothing may be small-data addressed -- the Makefile
 * passes -msdata=none -G0 to guarantee it, and the empty .sdata/.sbss outputs
 * below turn a mistake into a link error rather than a runtime one.
 */
OUTPUT_FORMAT("elf32-powerpc")
OUTPUT_ARCH(powerpc)

/* Link base.  A module gets relocated to wherever the loader puts it, so this
 * address is never where the code actually runs -- but a bl to Melee has to
 * ENCODE at link time, and REL24 only reaches +/-32MB.  Linking at zero puts
 * the whole game out of range ("relocation truncated to fit"); linking at the
 * game's own base puts every call within 4MB.  The loader recomputes each of
 * those displacements from the absolute target at load time, so the value the
 * linker writes is thrown away either way.
 *
 * It also gives the packer its test for what to relocate: an address inside
 * [BASE, BASE + image) is ours and becomes an offset, anything else is the
 * game's and is stored absolute. */
BASE = 0x80000000;

SECTIONS
{
    . = BASE;

    .text : ALIGN(4) {
        *(.init)
        *(.text .text.*)
    }

    .rodata : ALIGN(4) {
        *(.rodata .rodata.*)
    }

    .data : ALIGN(4) {
        *(.data .data.*)
    }

    .bss : ALIGN(4) {
        *(.bss .bss.*)
        *(COMMON)
    }

    /* Anything small-data addressed would be reached off r13 at runtime,
     * which in Melee points at the game's own globals.  Collect those
     * sections so they exist, then refuse to link if anything landed there. */
    .sdata  : { *(.sdata .sdata.*) }
    .sbss   : { *(.sbss .sbss.*) }
    .sdata2 : { *(.sdata2 .sdata2.*) }

    ASSERT(SIZEOF(.sdata)  == 0, "module uses .sdata -- rebuild with -msdata=none -G0")
    ASSERT(SIZEOF(.sbss)   == 0, "module uses .sbss -- rebuild with -msdata=none -G0")
    ASSERT(SIZEOF(.sdata2) == 0, "module uses .sdata2 -- rebuild with -msdata=none -G0")

    /DISCARD/ : {
        *(.comment)
        *(.note .note.*)
        *(.eh_frame .eh_frame_hdr)
        *(.gnu.attributes)
    }
}
