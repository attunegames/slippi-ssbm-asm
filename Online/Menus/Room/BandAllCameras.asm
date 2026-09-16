################################################################################
# Address: 0x80368468 # CObj_SetCurrent, past its prologue
################################################################################
# Put every camera the room draws through into the band.
#
# Banding from the module reaches cameras that a GObj owns, and that is not all
# of them. Class 20 holds five GObjs; only two carry a CObj, both are banded,
# both read their viewport back unchanged every frame - and the fighters ignore
# both and draw at full size down the whole screen. A probe over the first 0x50
# bytes of the other three found no CObj at all. So the fighters are drawn
# through a camera nothing on that list owns, and walking GObjs will never find
# it.
#
# CObj_SetCurrent is the one place it cannot hide. Every camera that draws
# anything is made current first - that is what the function is for - so forcing
# the viewport here catches all of them, owned or not.
#
# Not at 0x80368458, the function's first instruction, although that is where
# the camera arrives. That instruction is "mflr r0", and whether it still reads
# the game's LR after the codehandler has dispatched to us is not something this
# codeset has ever relied on - nothing else in it replaces an mflr. Four
# instructions later r0 has been saved to the stack and is dead, r3 is still the
# camera, and the replaced instruction is a plain register move. Same effect,
# nothing assumed.
#
# ⚠️ "or." sets CR0, and the null check two instructions down branches on it, so
# it has to be the LAST thing this runs. Our own compares write CR0 too.

.include "Common/Common.s"
.include "Online/Online.s"

# A null camera is exactly what the check below us is for; leave it alone.
cmplwi r3, 0
beq EXIT

getMinorMajor r12
cmpwi r12, SCENE_ONLINE_ROOM
bne EXIT

# The viewport, as raw float bits - no FPU and no calls, so LR stays untouched.
# 320x240 centred in the 640: 4:3, so the picture keeps its proportions and the
# whole VS composition fits in the top half of the screen.
lis r0, 0x4320      # 160.0 left
stw r0, 0xC(r3)
lis r0, 0x43F0      # 480.0 right
stw r0, 0x10(r3)
li r0, 0            #   0.0 top
stw r0, 0x14(r3)
lis r0, 0x4370      # 240.0 bottom
stw r0, 0x18(r3)

# The scissor is halfwords in the same order, and stays the full width of the
# band so nothing can spill out underneath it.
li r0, 0
sth r0, 0x1C(r3)    # left
li r0, 640
sth r0, 0x1E(r3)    # right
li r0, 0
sth r0, 0x20(r3)    # top
li r0, 240
sth r0, 0x22(r3)    # bottom

EXIT:
# Run replaced code line
or. r31, r3, r3
