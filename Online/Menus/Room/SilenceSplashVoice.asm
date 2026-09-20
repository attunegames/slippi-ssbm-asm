################################################################################
# Address: 0x80184DE8 # the VS splash announcing a fighter by name
################################################################################
# Do not shout a character's name every time somebody walks into a room.
#
# The room borrows the VS splash for its camera and its picture, and the splash
# announces the fighter it has just drawn - which in a room fires on entry, on
# every rebuild of the band, and for everybody sitting there when two other
# people finish drafting. An empty room announced "Zelda", because the empty
# band's right-hand placeholder IS Zelda.
#
# ⚠️ FOUND BY READING THE DOL, after a first attempt hooked the wrong call.
# 0x80168C5C is the announcer: it bounds-checks a character id against 0x1D and
# jumps through a table at 0x803D55A8, one voice clip per fighter. Its caller
# here is the splash's step machine:
#
#     lbz r3, 0xF4(r30)    # r30 is the splash's struct, +0xF4 is the RIGHT
#     bl  0x80168C5C       # fighter - and this is the only name it speaks
#
# ⚠️ The call that was hooked first, 0x80186EE0, is NOT this. It is handed the
# splash template's own first two bytes - a fixed sound id 1 in bank 0x78, the
# same every time whoever is playing - so silencing it took away a sound that
# had nothing to do with a fighter's name and left this one talking.
#
# Only the NAME goes. The steps around this one play the splash's other clips
# and are left alone, so a room still gets everything but the shout.
#
# ⚠️ Rooms only. Every other screen that builds this splash is a real match
# about to start, where announcing the fighters is the whole point.
#
# ⚠️ r3 is ALREADY the argument when we arrive - the instruction before this one
# loads it - and `backup` saves r20 up, not r3. So the mode is read into r3 only
# after r3 has been put somewhere it survives.

.include "Common/Common.s"
.include "Online/Online.s"

backup

mr r30, r3                          # the character id, out of harm's way
lbz r3, OFST_R13_ONLINE_MODE(r13)
cmpwi r3, ONLINE_MODE_ROOMS
mr r3, r30                          # ...and back. Does not touch the compare.
beq SILENCE_SPLASH_VOICE_SKIP

restore
branchl r12, 0x80168C5C
b SILENCE_SPLASH_VOICE_DONE

SILENCE_SPLASH_VOICE_SKIP:
restore

SILENCE_SPLASH_VOICE_DONE:
