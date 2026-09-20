################################################################################
# Address: 0x8025FE80 # the character select zeroing a costume it did not expect
################################################################################
# Keep the costume the player last used, instead of losing it every game.
#
# ⚠️ FOUND IN THE DOL, not guessed. The character select sets its cursor up from
# the character Dolphin hands it, and four instructions earlier it does this:
#
#     lbz  r0, 0x3C2(r28)    # the character the cursor is ALREADY on
#     ...
#     cmpw r4, r0            # against the one that just arrived
#     beq  0x8025FE84        # same fighter - keep the costume
#     li   r0, 0
#     stb  r0, 0x3C1(r3)     # different fighter - THROW THE COSTUME AWAY
#
# Which is exactly the reported bug. Dolphin remembers both halves and writes
# them into the match block, the character survives because the cursor is set
# from it - and the costume is wiped right here, because the fighter changed.
#
# In a room the fighter changes constantly: every pairing is a different
# opponent and the cursor is still sitting on whatever the last game left.
#
# So the costume comes from the match block as well, which is where Dolphin
# already put it: the character is read at +0x70 of the same per-port struct and
# the costume is three bytes after it, at +0x73. Melee's own behaviour is not
# touched anywhere else - only a room takes the other branch.
#
# ⚠️ r6 is the port times 0x24, set four instructions up and not touched since.
# r4 is free: the only path through here falls into 0x8025FE84, which loads it
# again before anything reads it. r0 is free for the same reason - the next
# instruction is `li r0, 5`.

.include "Common/Common.s"
.include "Online/Online.s"

lbz r0, OFST_R13_ONLINE_MODE(r13)
cmpwi r0, ONLINE_MODE_ROOMS
li r0, 0                            # the stock value. `li` leaves cr0 alone.
bne KEEP_ROOM_COSTUME_STORE

lwz r4, -0x49f0(r13)                # the character select's per-port data
add r4, r4, r6
lbz r0, 0x73(r4)                    # ...and the costume Dolphin remembered

KEEP_ROOM_COSTUME_STORE:
stb r0, 0x3C1(r3)
