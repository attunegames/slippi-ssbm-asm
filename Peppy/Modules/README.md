# Peppy m-ex code modules

Melee runs Peppy's UI code as **m-ex modules**: relocatable PowerPC compiled
from C, shipped as HAL DAT files in `Sys/GameFiles/GALE01/`, loaded when a
scene is entered.  Slippi already does this - `SlippiCSS.dat` is the rank and
chat overlay on the character select, and `GameSetup.dat` is a whole scene they
invented.  We add to that rather than touching either.

The format, and how it was worked out, is written up in
`peppy-assets/NOTES-mex-modules.md`.  The short version:

* `MxScn.dat` holds Melee's global minor-scene table, extended by m-ex with a
  per-scene code file.  `mxscn.py` attaches a module to a scene.
* A module is a DAT whose single root, `mnFunction`, points at the code, a
  relocation table, and an export table.
* Exports map to the scene's three function slots in order: **0 = Think,
  1 = Load, 2 = Leave**.  A module *replaces* the slot, so an export that wants
  the original behaviour has to call the original itself.
* Relocation targets below `0x80000000` are module-internal and get the load
  address added; targets at or above it are addresses in the game and are used
  verbatim.  That is the whole trick, and getting it backwards produces a
  module that loads and then branches nowhere.

## Layout

    Makefile                  build all modules
    module.ld                 one contiguous image linked at zero
    melee_symbols.ld          6444 Melee functions, extracted from m-ex's MxDb.dat
    slippi_symbols.ld         the codeset's injected helpers, from Common.s/Online.s
    mexpack.py                linked ELF -> module DAT
    mxscn.py                  attach a module to a scene in MxScn.dat
    include/peppy.h           scene controller, EXI helpers
    boot/                     pipeline smoke test

## Regenerating the symbol scripts

    python gen_slippi_symbols.py ../../Common/Common.s ../../Online/Online.s slippi_symbols.ld
    python ../../../peppy-assets/mxdb.py <path to>/MxDb.dat melee_symbols.ld

## Building

CI does it on every push and uploads the `.dat` files as the `mex-modules`
artifact.  Locally it needs the same container as the codeset:

    docker run --rm -v $PWD:/work -w /work/Peppy/Modules \
        nikhilnarayana/devkitpro-slippi:latest make
