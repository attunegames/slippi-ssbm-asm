# Save points

Two halves. The tag restores the source and the codeset; the rig folder restores
what was actually running, because the artwork cannot live in git.

## works/rooms-menu-reordered - the current one

The Rooms menu, final order, confirmed on hardware:

* Rooms -> Create / Join / Public
* Create alone goes on to Singles / Doubles / Ironmans / Crew Battles /
  Tournaments, then Private / Public
* Join and Public never see a kind list
* row labels read Ironmans, all eleven descriptions correct
* artwork delivered as a 199KB VCDIFF patch, not the whole 2.2MB file

To rewind the source:

    git checkout works/rooms-menu-reordered

`Output/Netplay/*.ini` is committed at every tag, so that checkout gives the
exact codeset that was running - no rebuild needed to get back to a known state.

To rewind the rig:

    Desktop/rooms-lan-test/_known-good/RESTORE.sh

⚠️ That script also DELETES any whole `MnMaAll.usd` it finds. The loader prefers
a whole file over its patch, so one left beside the patch wins and quietly
undoes the restore.

## works/rooms-menu

The same menu before the reorder - kinds first, then Create / Join / Public.
Kept because it is the last state where the original order was known good.

## Why the artwork is not in git

`MnMaAll.usd` and the files it is built from are Melee's own menu archive.
`Peppy/Artwork/` has the builder, the notes and the encoder; the `.usd` files
are gitignored and live in `C:\root\peppy-assets\`. Rebuild with:

    python mklabels.py MnMaAll.roomslist.usd
    python vcdiff_encode.py MnMaAll.orig.usd MnMaAll.roomslist.usd MnMaAll.usd.diff

## What is NOT covered

The Dolphin side. `rooms-lan-test` runs the old Peppy Dolphin, which answers the
room EXI commands and points at the OLD Supabase project. Nothing on this branch
has rebuilt it, so a rewind here does not move it.
