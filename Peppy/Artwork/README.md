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

## ⚠️ We ship the whole file, and Slippi ships a patch

Slippi distributes `MnMaAll.usd.diff` - 186KB of VCDIFF - and
`SlippiGameFileLoader` applies it to the copy in the user's own ISO. We put a
whole 2.2MB `MnMaAll.usd` in `Sys/GameFiles/`, which the loader prefers over the
`.diff`, so every build carries Melee's menu archive inside it.

That wants fixing before any of this is distributed: it is ~12x larger than it
needs to be, and it is the reason Slippi chose diffs in the first place.

`vcdiff.py` here only DECODES - it was written to read Slippi's patches and
learn the format. Producing our own needs an encoder, or open-vcdiff / xdelta3
driven from the build.

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
