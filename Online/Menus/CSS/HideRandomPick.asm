################################################################################
# Address: 0x8025FBE8 # the random picker storing the rolled fighter's ICON
################################################################################
# Picking random keeps the question mark until the match starts.
#
# The character select draws its portrait from a different field than the one
# the match uses, which is what makes this cheap:
#
#   +0x70   of the selections block  = the CHARACTER, sent to the opponent
#   +0x3C2  of the port's icon block = the ICON, which is what is DRAWN
#
# Melee's random picker at 0x8025fb50 writes both - the rolled fighter into
# +0x70, and that fighter's icon into +0x3C2 - which is why the pick is visible
# the moment it is made. Keeping the random token's own icon in +0x3C2 leaves
# the question mark on screen while the real character sails on untouched
# underneath: matchmaking, the match itself and the splash all read +0x70 and
# never look at this.
#
# ⚠️ 0x19 is the random token's icon index, read out of the ISO rather than
# assumed, and confirmed twice over:
#
#   0x8025fb70  li r3, 0x19    the picker rolls 0..24, so 25 icons are fighters
#   0x80260ad0  cmpwi r4, 0x19 and its CALLER only invokes random when the
#               bne ...        selected icon IS 25
#
# So 0..24 are the fighters and 25 is the question mark.
#
# ⚠️ Stored EXPLICITLY rather than skipping the store. Simply not writing would
# leave whatever happened to be in the field, which is only the random token if
# nothing else ever writes it - and that is an assumption this does not need to
# make. Writing 0x19 is true whatever came before.
#
# ⚠️ Rooms only, and only on the online character select. Melee's random picker
# is shared with every offline mode, where hiding the pick would be a bug.

.include "Common/Common.s"
.include "Online/Online.s"

.set ICON_RANDOM_TOKEN, 0x19

backup

getMinorMajor r3
cmpwi r3, SCENE_ONLINE_CSS
bne HIDE_RANDOM_SHOW_IT

lbz r3, OFST_R13_ONLINE_MODE(r13)
cmpwi r3, ONLINE_MODE_ROOMS
bne HIDE_RANDOM_SHOW_IT

restore
li r0, ICON_RANDOM_TOKEN
stb r0, 0x3c2(r28)          # the question mark stays up
b HIDE_RANDOM_DONE

HIDE_RANDOM_SHOW_IT:
restore
stb r31, 0x3c2(r28)         # the replaced instruction: the rolled fighter

HIDE_RANDOM_DONE:
