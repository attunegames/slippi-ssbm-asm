################################################################################
# Address: 0x80186DD4 # the VS splash picking its song, one instruction before
#                     # it calls BGM_Play
################################################################################
# The room plays How to Play's music (howto.hps).
#
# The room borrows the VS splash's scene for its camera and its picture, and the
# splash starts its own music on the way in - a hardcoded song 0x2d. So a room
# full of people waiting for a game sat under the versus splash's track.
#
# ⚠️ EVERY NUMBER HERE WAS READ OUT OF THE ISO, not guessed. The chain, from the
# bottom up:
#
#   0x8038e8ec  fileLoad_HPS(...)     Slippi's own music hook lives INSIDE this,
#                                     so Slippi forwards whatever Melee loads
#                                     and never chooses - nothing to build there
#   0x80023ed4  a wrapper that clamps its arguments
#   0x80023f28  BGM_Play(id)          the general one, 47 callers
#
# BGM_Play range-checks the id against 0x62 and then indexes a filename table.
# ⚠️ That table is in BSS, so the DOL holds nothing at it and reading it there
# gives character filenames and garbage - which is exactly what the first
# attempt produced. The NAMES are DOL constants though, 99 of them in order
# starting at 0x803bbddc, and the index into that list IS the song id.
#
# Proven against two ids already known from the game's own code before being
# relied on:
#
#   0x2d -> intro_es.hps   and 0x2d is what this very splash plays
#   0x34 -> menu01.hps  }  and the menu's song setter at 0x8015ecbc picks
#   0x36 -> menu3.hps   }  between exactly 0x34 and 0x36 with HSD_Randi
#
#   0x24 -> howto.hps      which is the one asked for
#
# ⚠️ Gated on the SCENE, not on ONLINE_MODE_ROOMS. The mode is set for the whole
# of a rooms session, and that includes the REAL VS splash immediately before a
# match - which genuinely wants its own song. Only the room screen is borrowing
# this scene, so only the room screen should have its music replaced.
#
# ⚠️ The work happens AFTER `restore`, because restore puts r3 back and the
# instruction being replaced is `li r3, 0x2d` - the song id has to be in r3 on
# the way out. Same shape as SilenceSplashVoice for the same reason.

.include "Common/Common.s"
.include "Online/Online.s"

.set ROOM_SONG_HOWTO, 0x24      # howto.hps
.set SPLASH_SONG_INTRO, 0x2d    # intro_es.hps - the replaced instruction's own

backup

getMinorMajor r3
cmpwi r3, SCENE_ONLINE_ROOM
bne ROOM_MUSIC_LEAVE_SPLASH_ALONE

restore
li r3, ROOM_SONG_HOWTO
b ROOM_MUSIC_DONE

ROOM_MUSIC_LEAVE_SPLASH_ALONE:
restore
li r3, SPLASH_SONG_INTRO

ROOM_MUSIC_DONE:
