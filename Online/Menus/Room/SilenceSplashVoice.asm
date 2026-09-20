################################################################################
# Address: 0x80186EE0 # SceneLoad_ClassicModeSplash, the announcer call
################################################################################
# Do not shout a character's name every time somebody walks into a room.
#
# The room borrows the VS splash for its camera and its picture, and the splash
# announces the two fighters it has just built - which in a room fires on entry,
# on every rebuild of the band, and for everybody sitting there when two other
# people finish drafting.
#
# ⚠️ The instruction replaced here is the CALL that plays it, read out of the
# DOL rather than guessed. 0x80167858 is handed the two character ids and ends:
#
#     clrlwi r3, r28, 0x18    # the character
#     li     r4, 3
#     bl     0x80014574       # play it
#
# The call after it, 0x80168F88, only loads sound banks - it clears the ssm
# queue and fills it - so leaving that alone keeps everything else this screen
# is allowed to say.
#
# ⚠️ Rooms only. Every other screen that builds this splash is a real match
# about to start, where announcing the fighters is the whole point.
#
# ⚠️ r3 through r6 are ALREADY the arguments when we arrive - the three
# instructions before this one load them - and `backup` saves r20 up, not them.
# So the mode is read into r3 only after r3 has been put somewhere it survives.

.include "Common/Common.s"
.include "Online/Online.s"

backup

mr r30, r3                          # the character id, out of harm's way
lbz r3, OFST_R13_ONLINE_MODE(r13)
cmpwi r3, ONLINE_MODE_ROOMS
mr r3, r30                          # ...and back. Does not touch the compare.
beq SILENCE_SPLASH_VOICE_SKIP

restore
branchl r12, 0x80167858
b SILENCE_SPLASH_VOICE_DONE

SILENCE_SPLASH_VOICE_SKIP:
restore

SILENCE_SPLASH_VOICE_DONE:
