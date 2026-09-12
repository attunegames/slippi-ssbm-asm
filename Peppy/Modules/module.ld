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

SECTIONS
{
    . = 0;

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
