################################################################################
# Address: 0x80186DD4 # the VS splash picking its song, one instruction before
#                     # it calls BGM_Play
################################################################################
# The room picks its music at random from a small pool.
#
# The room borrows the VS splash's scene for its camera and its picture, and the
# splash starts its own music on the way in - a hardcoded song 0x2d. So a room
# full of people waiting for a game sat under the versus splash's track.
#
# ⚠️ EVERY NUMBER HERE WAS READ OUT OF THE ISO, and the two that matter were
# then confirmed BY EAR. The chain, from the bottom up:
#
#   0x8038e8ec  fileLoad_HPS(...)     Slippi's own music hook lives INSIDE this,
#                                     so Slippi forwards whatever Melee loads
#                                     and never chooses - nothing to build there
#   0x80023ed4  a wrapper that clamps its arguments
#   0x80023f28  BGM_Play(id)          the general one, 47 callers
#
# BGM_Play range-checks the id against 0x62 and indexes a filename table.
# ⚠️ That table is in BSS, so the DOL holds nothing at it - reading it there
# gives character filenames and garbage, which is what the first attempt
# produced. The NAMES are DOL constants though, 99 of them in order from
# 0x803bbddc, and the index into that list IS the song id. Proven against ids
# the game's own code already gave us: 0x2d -> intro_es.hps, which is what this
# very splash plays, and 0x34/0x36 -> menu01/menu3, exactly the two Melee's own
# menu song setter at 0x8015ecbc picks between with HSD_Randi.
#
# ⚠️ Picking at random is Melee's own idea, not an invention - that setter is
# the pattern this copies.
#
# ⚠️ THIS REROLLS ON EVERY ENTRY TO THE ROOM SCENE, which includes coming back
# from a match. So the track changes between games rather than once per room.
# That is a consequence of where the hook sits, not a decision - the scene is
# re-entered and this code runs again with nothing remembered in between.
#
# ⚠️ Gated on the SCENE, not on ONLINE_MODE_ROOMS. The mode is set for the whole
# of a rooms session, and that includes the REAL VS splash immediately before a
# match - which genuinely wants its own song.
#
# ⚠️ The work happens AFTER `restore`, because restore puts r3 back and the
# instruction being replaced is `li r3, 0x2d` - the song id has to be in r3 on
# the way out. r4 is used as a scratch and is safe: the instruction after the
# BGM_Play call below is this function's epilogue, so r4 is dead there.

.include "Common/Common.s"
.include "Online/Online.s"

.set SPLASH_SONG_INTRO, 0x2d    # intro_es.hps - the replaced instruction's own

b ROOM_MUSIC_CODE

# The pool. Add ids here and the count below; nothing else needs touching.
#
# ⚠️ howto_S (0x25), not howto (0x24). Both are "How to Play" and 0x24 has the
# DEMO MIXED IN - Mario and Bowser can be heard fighting over the music - and it
# does not loop, being a one-shot cut to the length of the demo. Both of those
# complaints had the one cause. Settled by decoding each to WAV and listening.
#
# ⚠️ EVERY ONE OF THESE WAS PICKED BY EAR, and that is not fussiness. All-Star
# is 1p_qk.hps - nothing in that name says All-Star, and no amount of reading
# would have found it. Melee's sound test numbers its own way too: All-Star is
# #60 there and id 0x00 here. Decode the clip and listen; do not reason from
# the filename.
ROOM_MUSIC_TABLE:
blrl
.byte 0x25      # howto_s.hps  - How to Play, clean
.byte 0x53      # target.hps   - Target Test
.byte 0x00      # 1p_qk.hps    - All-Star
.align 2

.set ROOM_SONG_COUNT, 3

ROOM_MUSIC_CODE:
backup

getMinorMajor r3
cmpwi r3, SCENE_ONLINE_ROOM
bne ROOM_MUSIC_LEAVE_SPLASH_ALONE

restore
li r3, ROOM_SONG_COUNT
branchl r12, HSD_Randi      # 0 .. count-1
bl ROOM_MUSIC_TABLE         # blrl leaves the table's address in LR
mflr r4
lbzx r3, r4, r3
b ROOM_MUSIC_DONE

ROOM_MUSIC_LEAVE_SPLASH_ALONE:
restore
li r3, SPLASH_SONG_INTRO

ROOM_MUSIC_DONE:
