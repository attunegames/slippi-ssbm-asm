################################################################################
# Address: 0x80184adc # VS Splash think function
################################################################################

.include "Common/Common.s"
.include "Online/Online.s"

.set REG_IDX, 31
.set REG_JOBJ_ADDR, 27 # Set by parent function

# Stack Pointer Offsets
.set SPO_CHILD_JOBJ, 0x80 # float

# Ensure that this is an online VS
getMinorMajor r12
cmpwi r12, SCENE_ONLINE_VS
beq HIDE_IT
# The room draws this same screen as a band across its top, and wants it just
# as bare - so the hack that strips it for online VS runs there too.
cmpwi r12, SCENE_ONLINE_ROOM
bne EXIT # If neither, execute normal code
HIDE_IT:

backup

# The room wants the band bare: backdrop and two fighters, nothing else. The VS
# emblem and NOW LOADING sit ABOVE the stage lettering in this tree, not below
# it - hiding 0 to 8 cost the backdrop and left both of them untouched, and
# disassembling the think settled where they really are. It only ever reaches
# for children 0x12 and 0x13, which are the loading digits, so everything the
# room still wants gone is from 14 up.
#
# The flag rather than the animations: dropping an anim works for the letters
# because they animate IN and are never drawn otherwise, but something already
# on screen and sitting still stays on screen. The emblem is one of those.
#
# Null-checked, unlike the loop below: 9 to 13 are known to be there and the
# top of this range is a guess at where the children run out.
# The room hides the small vs plate lettering the same way the stage letters go.
#
# It does NOT sweep animations across the tree any more. That did remove the red
# emblem - the mechanism is right, an animation driving visibility just puts the
# invisible flag back - but JObj_RemoveAnimAll is RECURSIVE, and the indices
# here are positions in the whole tree rather than direct children. Clearing one
# early index cleared an ancestor of the joints the fighters hang from, and they
# drifted out to the edges of the screen, zoomed and half off it. Skipping 4 and
# 5, the joints themselves, changed nothing at all - which is the proof that
# what was cleared was above them.
#
# Getting that right needs the tree's actual shape, not another range.
.set ROOM_HIDE_FIRST, 14
.set ROOM_HIDE_END, 27
getMinorMajor r12
cmpwi r12, SCENE_ONLINE_ROOM
bne SKIP_ROOM_EXTRA
li REG_IDX, ROOM_HIDE_FIRST
ROOM_LOOP_START:
li r3, 0
stw r3, SPO_CHILD_JOBJ(sp)
mr r3, REG_JOBJ_ADDR
addi r4, sp, SPO_CHILD_JOBJ
mr r5, REG_IDX
li r6, -1
branchl r12, JObj_GetJObjChild

# The out slot is zeroed above every call: JOBJ_GetChild is VARARGS - the -1 is
# a terminator, not an argument - and it does not promise to write the slot when
# it finds nothing. The loop below gets away without it because 9 to 13 are
# known to be there.
lwz r4, SPO_CHILD_JOBJ(sp)
cmpwi r4, 0
beq ROOM_LOOP_NEXT
lwz r3, 0x14(r4) # Get current flags
ori r3, r3, 0x10 # Set invisible flag
stw r3, 0x14(r4)
ROOM_LOOP_NEXT:
addi REG_IDX, REG_IDX, 1
cmpwi REG_IDX, ROOM_HIDE_END
blt ROOM_LOOP_START
SKIP_ROOM_EXTRA:

li REG_IDX, 9

# Loop through 27 JOBJs and set them to invisible
LOOP_START:
# Get child JObj
mr r3, REG_JOBJ_ADDR
addi r4, sp, SPO_CHILD_JOBJ
mr r5, REG_IDX
li r6, -1
branchl r12, JObj_GetJObjChild

# Remove animations for the JObjs. By doing this they will never show
lwz r3, SPO_CHILD_JOBJ(sp)
branchl r12, JObj_RemoveAnimAll

addi REG_IDX, REG_IDX, 1
cmpwi REG_IDX, 14
blt LOOP_START

# Restore
restore

EXIT:
# Run replaced code lines
addi r29, r30, 56
