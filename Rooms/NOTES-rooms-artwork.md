# Rooms menu artwork and levels

All of the Rooms menu runs on real menu artwork - images in `MnMaAll.usd`, the
same as every other row Melee and Slippi draw. No ISO is modified: Slippi's
game-file loader serves `Sys/GameFiles/GALE01/` and prefers a whole file over
its `.diff`.

Shipping file: `MnMaAll.roomslist.usd`, md5 `2e00db0d`. Build with
`python mklabels.py <out.usd>`; the menus and their frames are in `GROUPS`.

## How row artwork works

The labels are frames of one texture animation (texanim `0x0C843C`, aobj
`0x0C7D74`, first FObj of its chain at `0x209C18`). **Each menu owns a 20-frame
block** - 0, 20, 40 ... 140 is the online menu's, 160 Stadium's, 240 the last -
and options step by **two** inside their block, so the frame is
`base + 2*option`. `base` is the second field of the submenu option table.
The first field points at the *preview panel* animation, three floats per
option, not the labels.

Measured, not assumed: label every frame and read them off the screen. The mode
list samples 140, 142, 144, 146, 148 and 156 - Rooms is option 8, because the
hidden log-in/log-out options still count.

## How to add labels - read Slippi's own patch

`MnMaAll.orig.usd` is the ISO's copy, `MnMaAll.slippi.usd` is after their patch.
Diffing the two shows exactly how they added Ranked, Unranked, Direct, Teams,
Party, Log-in, Log-out and Update:

- They **rewrote the whole track's encoding**. Vanilla stores byte offsets into
  the image table - header `a1 07`, animkind `0x82`, values stepping by 4 (max
  228 = 57x4 for 58 images). Slippi's stores plain indices - header `81 08`,
  animkind `0x80`, values 0..63. Keep their form.
- They **fitted the new keys into padding inside a menu's own block**. The key
  at 142 held for 18 frames; they shortened it to 2 and inserted six keys
  summing to 16, so the block still ended on 160 and nothing downstream moved.
- They appended the images and a new image table at the end of the data block
  and repointed the texanim.

**Do not put labels out in the tail padding** (frame 246, or the free block at
260). The rows only partially render there; never diagnosed, and no need to,
because block padding works.

Stream format: 2-byte header, then `(image index, duration varint)` pairs, then
a terminator. The varint is big-endian. **The terminator is a zero-duration
key** - a writer that skips zero durations silently drops it and the track ends
in the wrong place.

## Guarantees the builder checks

All 64 stock images kept byte for byte, every pre-existing keyframe still showing
the identical picture, the track still ending on 15097, and the relocation table
preserved in its original order with new entries appended (`dat.py` keeps
`reloc_order`). A writer that cannot round-trip Slippi's file byte for byte
cannot tell you what your own edit changed; re-run that round-trip after any
change to the builder.

## The labels

Composed from glyphs cut out of Melee's own menu labels. Baseline-corrected,
because a few source labels sit a pixel off, and cuts clamped so a neighbouring
letter's stem can never ride along.

**One core gap of 2 for every row.** The stock font tracks to fit - short labels
run gaps of 6-7 and long ones 1-5 - but copying that left Singles and Doubles
visibly looser than Crew Battles and Tournaments, and the long words cannot
loosen to meet them because they are already at the plate's width limit. So the
long words set the spacing and the short ones match it. Crew Battles sits at 1,
the widest that fits it; everything else is 2.

**Check a source label's length before cutting a glyph.** Cap height is constant
across every label, so letters look the same size, but Melee *condenses* long
labels horizontally - "Fixed-Camera Mode" runs about 0.64x the width of
"All-Star". Mixing weight classes inside one word is invisible in a long word
and glaring in a three-letter one.

Three glyphs do not exist anywhere in the set and are built rather than cut:

- **`w`** - no lowercase w. Crew's is two `v`s sharing a stroke.
- **`J`** - no capital J. A J is the right half of a U, so the U from "Unranked"
  keeps its right stem and bottom hook, the left stem is cut down to a tail
  about a third of the height, and the tail is capped with the U's own stem-top
  outline so the cut end is finished.
- **`I`** - the only capital I is in "Invisible Melee", one of the condensed
  labels, but it is safe to cut directly: a capital I here is a bare 4px stem
  with no arms and no serifs, the same width as the l and the i, so there is
  nothing for the condensing to distort. Contrast the F below.
- **`F`** - the only capital F is in "Fixed-Camera Mode", the most condensed
  label, which put a 9px-wide light F beside a 19px-wide heavy A. Derived from
  the E in "Erase Data" instead: everything below the middle arm's underside is
  replaced with the stem's own cross-section taken from an open row of the
  counter, and the E's baseline cap is kept, clipped to the stem. 13 wide, a
  natural F:A ratio.

## Menu levels

All four levels are menu 8 redrawn in place, not separate menus:

| level | rows | artwork base | block borrowed from |
|---|---|---|---|
| 0 | Ranked ... Rooms | 140 | the online menu's own |
| 1 | Singles, Doubles, IronMan, Crew Battles, Tournaments | 166 | Stadium's padding |
| 2 | Create / Join / Public | 126 | block 120's padding |
| 3 | Private / Public | 186 | block 180's padding |

`PLD_LEVEL` is the depth and `PLD_SEL` holds the option picked at each level, one
byte each. B unwinds a level and puts the cursor back on the row that opened the
one being left; the deeper levels read the same record to know which mode the
room is for. `FN_RoomsGoToLevel` is the only way levels change, and
`FN_RoomsLevelTables` maps a level to its option and description tables.

Descriptions: level 0's Rooms line goes through the premade-text hook because it
needs an ampersand, which the drawn-text path has no glyph for. Every level below
draws its own, from a per-level list in `PDD_LEVELS`. The hook blanks any row
count that is not 9, so new levels need nothing added there.

**Not built yet:** Join (wants a room code), Public (wants a list of rooms),
Private (wants a passcode). They refuse rather than pretending. Create then
Public is where a room would be made; Singles is the only mode with anywhere to
go, so it still does what it did.

**For the public room browser:** the strip carries nine 8x4 stub images that
render as an empty plate. Point a row's artwork frame at one of those and draw
the room name with the text API, and there is no artwork underneath to cover -
which is what made the old drawn labels look sloppy.

## The menu header ("1-P Mode | Online Play") - investigated, parked

- 168x28, format **I4** (4bpp intensity, 8x8 tiles, 2688 bytes), not IA4.
  `tex.decode_i4` reads it. Texanim `0x05E438`, 21 images, table `0x209BAC`.
  The first breadcrumb segment is a separate 5-image texanim, table `0x05E214`.
- "Online Play" is index 2; Slippi put it there, vanilla has "Stadium".
- **The index is the option's position on the parent menu, not the menu id** -
  Online Play is 1-P Mode's option 2. Menu 8's header is fixed the moment you
  enter it, so a header that changes per level needs a runtime swap.
- That needs the RAM address of the loaded file. `Archive_GetSymbol`
  (`0x80380358`, used in `Stadium/StadiumFileLoad.asm`) resolves a named root,
  and `MenMainPanel_Top_matanim_joint` at `0x05E710` is a fixed offset from both
  the header texanim and its table - so one symbol yields everything. Missing
  piece is the archive pointer for the menu file; the name strings are
  referenced inline by code, and `"MnMaAll"` at `0x804D4B78` is a bare string,
  not a file-table entry. Finding it means disassembling the menu load path.
