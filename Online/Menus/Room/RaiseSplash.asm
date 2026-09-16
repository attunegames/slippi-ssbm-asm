################################################################################
# Address: 0x80368468 # CObj_SetCurrent, past its prologue
################################################################################
# Slide the splash up to the top of the screen. Nothing else.
#
# Melee frames this screen with the fighters in a strip across the middle and
# black above and below, because it is normally the whole screen. A room wants
# that strip at the TOP, with the black below it for the queue and the lobby -
# so the picture is translated, not resized. The size was already right.
#
# The viewport is left, right, top, bottom. Keeping bottom - top at 480 and
# right - left at 640 leaves the projection unchanged and every proportion with
# it; only where it lands moves. Set the top negative and the whole picture
# rides up by that much.
#
# It has to happen HERE rather than in the module. Banding from the module
# reaches cameras that a GObj owns, and those are not all of them: class 20
# holds five GObjs, three carry no CObj at all, and the fighters are drawn
# through a camera none of them own - they sat at full size down the screen
# while everything else moved. CObj_SetCurrent is where every camera that draws
# anything has to pass.
#
# WARNING: ABSOLUTE values, never a subtract. This runs for every camera every
# frame, so "move it up a bit" would move it up a bit again on the next frame,
# and the picture would fly off the top of the screen.
#
# Not at 0x80368458, the function's first instruction, although that is where
# the camera arrives: that one is "mflr r0", nothing else in this codeset
# replaces an mflr, and whether it still reads the game's LR after the
# codehandler has dispatched is untested. Four instructions later r0 is saved
# and dead, r3 is still the camera, and the replaced instruction is a plain
# register move.
#
# WARNING: "or." sets CR0 and the null check two instructions down branches on
# it, so it stays LAST. Our own compares write CR0 too.

.include "Common/Common.s"
.include "Online/Online.s"

# A null camera is what the check below us is for; leave it alone.
cmplwi r3, 0
beq EXIT

getMinorMajor r12
cmpwi r12, SCENE_ONLINE_ROOM
bne EXIT

# Raw float bits - no FPU and no calls, so LR and the FPRs stay untouched.
# The rise is 104: measured off a screenshot as the gap above the sky, and the
# one number here worth tuning. Too big and it cuts the tops of their heads.
lis r0, 0x0000      #    0.0  left
stw r0, 0xC(r3)
lis r0, 0x4420      #  640.0  right
stw r0, 0x10(r3)
lis r0, 0xC2D0      # -104.0  top
stw r0, 0x14(r3)
lis r0, 0x43BC      #  376.0  bottom, so the height is still 480
stw r0, 0x18(r3)

EXIT:
# Run replaced code line
or. r31, r3, r3
