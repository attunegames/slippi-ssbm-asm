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
# Two ranges and two mechanisms, and the difference between them is the whole
# reason the emblem survived two attempts.
#
# The invisible flag alone is not enough here. The loop below this one drops
# ANIMATIONS instead, and its comment says why: the letters animate in and are
# never drawn otherwise. The emblem is the same kind of thing - it sweeps on -
# and the tree is handed to JOBJ_AnimAll every frame four instructions above
# this hook, so an animation that drives visibility simply puts back whatever
# the flag said. Dropping the animation is what actually sticks.
#
# So: drop animations across the whole tree, which cannot touch anything static
# because there is no animation on it to drop - that is what keeps the backdrop,
# which is why the flag is NOT used down at 0 to 8 where hiding it by flag
# blanked the sky. The flag is kept from 14 up, for anything that is drawn
# without animating.
#
# The range is past the end on purpose; a child that is not there costs a call
# that returns nothing.
#
# WARNING: the out slot is zeroed before every call. JOBJ_GetChild is a VARARGS
# function - that trailing -1 is a terminator, not an argument - and it does not
# promise to write the slot when it finds nothing. The loop below gets away
# without this because 9 to 13 are known to exist; reading a stale stack slot
# and storing through it would be a store to whatever was there last.
.set ROOM_ANIM_END, 48
.set ROOM_FLAG_FIRST, 14
getMinorMajor r12
cmpwi r12, SCENE_ONLINE_ROOM
bne SKIP_ROOM_EXTRA
li REG_IDX, 0
ROOM_LOOP_START:
li r3, 0
stw r3, SPO_CHILD_JOBJ(sp)
mr r3, REG_JOBJ_ADDR
addi r4, sp, SPO_CHILD_JOBJ
mr r5, REG_IDX
li r6, -1
branchl r12, JObj_GetJObjChild

lwz r4, SPO_CHILD_JOBJ(sp)
cmpwi r4, 0
beq ROOM_LOOP_NEXT

# Static things keep their place; animated ones never arrive.
mr r3, r4
branchl r12, JObj_RemoveAnimAll

# ...and above the stage lettering, hide it outright as well.
cmpwi REG_IDX, ROOM_FLAG_FIRST
blt ROOM_LOOP_NEXT
lwz r4, SPO_CHILD_JOBJ(sp)
lwz r3, 0x14(r4) # Get current flags
ori r3, r3, 0x10 # Set invisible flag
stw r3, 0x14(r4)

ROOM_LOOP_NEXT:
addi REG_IDX, REG_IDX, 1
cmpwi REG_IDX, ROOM_ANIM_END
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
