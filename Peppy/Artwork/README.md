# Rooms menu artwork

Everything that makes the Rooms menu's row labels. `NOTES-rooms-artwork.md` is
the real document - how Melee stores row labels, how Slippi added their own, and
what the builder guarantees. Read that first.

    python mklabels.py <out.usd>

The words are in `GROUPS` at the top of `mklabels.py`. Change one, re-run, and
the whole file is rebuilt. The labels are composed from glyphs cut out of
Melee's own menu labels, so a word can only use letters that exist somewhere in
the set - there is no lowercase `w` anywhere, for instance, and Crew's is built
from two `v`s sharing a stroke.

## No game data is committed here

The `.usd` files this reads and writes are Melee's own menu archive, and they
are deliberately absent:

    MnMaAll.orig.usd       the ISO's copy
    MnMaAll.slippi.usd     after Slippi's patch
    MnMaAll.roomslist.usd  the built file we currently ship

They live in `C:\root\peppy-assets\` on the build machine. Anyone rebuilding
this needs their own copy extracted from their own ISO.

## Ship a patch, the way Slippi does

    python mklabels.py MnMaAll.roomslist.usd
    python vcdiff_encode.py MnMaAll.orig.usd MnMaAll.roomslist.usd MnMaAll.usd.diff

Put the `.diff` in `Sys/GameFiles/GALE01/` and do NOT leave a whole
`MnMaAll.usd` beside it - the loader prefers a whole file over its patch, so one
left there wins and the patch is ignored.

    ours     199826 bytes
    Slippi   186319 bytes
    whole   2244266 bytes

This is why Slippi ships patches: `SlippiGameFileLoader` applies them to the
copy in the user's own ISO, so no Melee data is redistributed. Shipping the
whole file carries the menu archive with it and is ~11x larger.

Ours comes out slightly bigger than Slippi's because it carries their edits as
well as ours - it is a patch against the untouched ISO copy, so it replaces
theirs rather than stacking on it - and because the encoder here is far simpler
than open-vcdiff.

Both halves are checked rather than assumed. `vcdiff.py` is proven against
Slippi's own patch: decoding `MnMaAll.usd.diff` over `MnMaAll.orig.usd`
reproduces `MnMaAll.slippi.usd` byte for byte. `vcdiff_encode.py` decodes every
delta it writes and refuses to save one that does not come back identical, so a
broken patch cannot reach a build.

## The other scripts

`dat.py` reads and writes the HAL DAT container and preserves relocation order.
`tex.py` encodes IA4 images. `tracks.py` handles the texture-animation keyframe
stream, whose terminator is a zero-duration key - a writer that skips zero
durations silently drops it and the track ends in the wrong place.
`roundtrip.py` checks the writer can reproduce Slippi's own file; run it after
any change to the builder, because a writer that cannot round-trip theirs cannot
tell you what your own edit changed.

It currently reports 12 differing bytes, all in the relocation table, with no
length change. That predates the Ironmans edit and the shipping artwork was
built with it, but it has never been explained and should be.
