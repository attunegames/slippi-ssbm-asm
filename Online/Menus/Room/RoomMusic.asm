################################################################################
# Address: 0x80186DD4 # the VS splash picking its song, one instruction before
#                     # it calls BGM_Play
################################################################################
# Play what the menus are playing, not the VS splash's track.
#
# The room borrows the VS splash's scene for its camera and its picture, and the
# splash starts its own music on the way in - a hardcoded song 0x2d. So a room
# full of people waiting for a game sat under the versus splash's track, while
# the two drafting next door heard the menu's.
#
# ⚠️ FOUND BY READING THE DOL rather than by guessing at an address, which is
# what the note on SilenceSplashVoice says to do and why. The chain, from the
# bottom up:
#
#   0x8038e8ec  fileLoad_HPS(...)      Slippi's own music hook lives INSIDE this
#   0x80023ed4  a wrapper that clamps its arguments
#   0x80023f28  BGM_Play(id)           the general one, 47 callers
#   0x8015ecb0  lwz r3, -0x77c0(r13)   the menus' CURRENT song...
#               lbz r3, 0x1851(r3)     ...one byte
#   0x8015ecbc  its setter, which picks between 0x34 and 0x36 with HSD_Randi
#
# The character select does exactly `bl 0x8015ecb0` then `bl 0x80023f28`, at
# 0x8026681c. This asks the same question rather than hardcoding a song id,
# because the menus have TWO tracks and which one is playing was decided at
# random when they started - hardcoding either would be right half the time.
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

backup

getMinorMajor r3
cmpwi r3, SCENE_ONLINE_ROOM
bne ROOM_MUSIC_LEAVE_SPLASH_ALONE

restore
branchl r12, 0x8015ecb0     # whatever the menus are currently playing
b ROOM_MUSIC_DONE

ROOM_MUSIC_LEAVE_SPLASH_ALONE:
restore
li r3, 0x2d                 # the replaced instruction: the splash's own song

ROOM_MUSIC_DONE:
