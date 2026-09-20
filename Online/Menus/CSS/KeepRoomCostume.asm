################################################################################
# Address: 0x8025FE84 # where both branches of the costume decision meet
################################################################################
# Keep the costume the player last used, instead of losing it every game.
#
# ⚠️ FOUND IN THE DOL, not guessed. Two pieces of Melee's own code decide a
# costume between them, and the bug needs both of them read.
#
# SceneLoad_CSS already does the right thing. At 0x80266550 it takes the costume
# straight out of the match block - the very byte Dolphin fills in - and puts it
# on the cursor:
#
#     lbz  r0, 0x73(r3)      # the costume Dolphin remembered
#     stb  r0, 0x3c1(r28)    # ...onto the cursor
#
# Then the character gets applied, in the function this code sits in, and four
# instructions before us it does this:
#
#     lbz  r0, 0x3c2(r28)    # the fighter the cursor is ALREADY on
#     cmpw r4, r0            # against the one that just arrived
#     beq  0x8025fe84        # same fighter - keep the costume
#     li   r0, 0
#     stb  r0, 0x3c1(r3)     # different fighter - THROW THE COSTUME AWAY
#
# So the costume is set up correctly and then thrown away a moment later,
# because the cursor starts the scene on a default fighter and the one that
# arrives is whatever was played last. The character survives - it is applied
# from the block right here - and only the costume is lost. Which is the report,
# exactly: same fighter as last game, wrong colour.
#
# ⚠️ AT THE MERGE POINT, not at the store. An earlier version of this replaced
# the `stb` above, which only covers the branch where the FIGHTER CHANGED. That
# is the branch that matters least: the reported case is the same fighter twice
# in a row, which takes the `beq` and never reaches that store at all. Both paths
# arrive here.
#
# ⚠️ Only when the cursor has no costume yet. Nothing else would tell this code
# apart from the player having chosen black Falcon on purpose, and this function
# can run more than once in a screen - it is called from six places, on button
# presses and on selections arriving. Filling in a blank is safe; overwriting a
# choice is not. The one case it gets wrong is a player deliberately picking
# costume 0 when their last one was not, and only if the function runs again.
#
# ⚠️ Rooms only. Melee's own behaviour, and Slippi's, are untouched.
#
# Registers: r30 is the CSS struct base and r6 the port times 0x24, both set
# well above and not touched since. r5 and r7 are live - 0x8025fe90 adds them -
# so neither may be used here. r3, r4 and r0 are all written again before
# anything reads them, and the `li r0, 5` this replaces is re-issued at the end
# because the next instruction loads CTR from it.

.include "Common/Common.s"
.include "Online/Online.s"

lbz r0, OFST_R13_ONLINE_MODE(r13)
cmpwi r0, ONLINE_MODE_ROOMS
bne KEEP_ROOM_COSTUME_DONE

add r3, r30, r6                     # this port's cursor
lbz r0, 0x3C1(r3)
cmpwi r0, 0
bne KEEP_ROOM_COSTUME_DONE          # already wearing something - leave it

lwz r4, -0x49f0(r13)                # the match block
add r4, r4, r6
lbz r0, 0x73(r4)                    # ...and the costume Dolphin remembered
stb r0, 0x3C1(r3)

KEEP_ROOM_COSTUME_DONE:
li r0, 5
