################################################################################
# Address: 0x8022e93c # SceneLoad_MainMenu
################################################################################
# Some events like returning from an Event Match jump to line 8022e930 and
# skip the previous calls, putting this initialization way at the end
# so that it will not be skipped

.include "Common/Common.s"
.include "Online/Online.s"

b CODE_START

DATA_USER_TEXT_BLRL:
blrl
.float -204 # X Pos of User Display, 0x0
.float -157 # Y Pos of User Display, 0x4
.float 17 # Z Offset, 0x8
.float 0.06 # Scaling, 0xC

DATA_PEPPY_LABEL_BLRL:
blrl
.set PL_ZERO, 0
.float 0
.set PL_MARK, PL_ZERO+4
.float 100
.set PL_Z, PL_MARK+4
.float 17
.set PL_SCALE, PL_Z+4
.float 0.06
.set PL_SIZE, PL_SCALE+4
.float 0.5
.set PL_STR_O, PL_SIZE+4
.string "O"
.set PL_STR_X, PL_STR_O+2
.string "X"
.set PL_STR_Y, PL_STR_X+2
.string "Y"
.align 2

DATA_BLRL:
blrl
.set DOFST_IS_FIRST_BOOT, 0
.byte 1
.align 2

CODE_START:
.set REG_FG_USER_DISPLAY, 30
.set REG_DATA_ADDR, 29
.set REG_TXB_ADDR, 28

backup

################################################################################
# Section 1: Skip User display init on the main menu
################################################################################
# Intentionally disabled so "User" + logged in name are not shown on title menu.
# Other scenes (like CSS/ranked) initialize their own user display separately.

################################################################################
# Section 1b: Peppy - calibration marks for the Rooms label
################################################################################
# The online menu's row labels are pre-rendered images and there are only eight
# of them, so the ninth row borrows the eighth and reads "Update". Nothing
# overrides a single row, so the only way to name it is to draw over it with
# Slippi's own text machinery - the same machinery that puts the user name on
# these menus.
#
# Where to draw is the open question: the row's position lives in Melee's menu
# layout, not in any code here. So this build puts three marks at known canvas
# coordinates - O at (0,0), X at (100,0), Y at (0,100) - which makes the mapping
# from canvas units to screen pixels measurable instead of guessed.
#
# This runs at scene load rather than scene prep: prep is before Melee has
# allocated its menu text memory, and creating a text struct there writes
# through a garbage pointer.
.set REG_PEPPY_DATA, 27
.set REG_PEPPY_TEXT, 26
.set REG_PEPPY_SUBTEXT, 25
.set REG_PEPPY_LR, 24

bl DATA_PEPPY_LABEL_BLRL
mflr REG_PEPPY_DATA

li r3, 0
li r4, 0
branchl r12, Text_CreateStruct
mr REG_PEPPY_TEXT, r3

# Close kerning, left aligned - same as the user display uses
li r4, 0x1
stb r4, 0x49(REG_PEPPY_TEXT)
li r4, 0x0
stb r4, 0x4A(REG_PEPPY_TEXT)

lfs f1, PL_Z(REG_PEPPY_DATA)
stfs f1, 0x8(REG_PEPPY_TEXT)
lfs f1, PL_SCALE(REG_PEPPY_DATA)
stfs f1, 0x24(REG_PEPPY_TEXT)
stfs f1, 0x28(REG_PEPPY_TEXT)

# Origin mark
lfs f1, PL_ZERO(REG_PEPPY_DATA)
lfs f2, PL_ZERO(REG_PEPPY_DATA)
mr r3, REG_PEPPY_TEXT
addi r4, REG_PEPPY_DATA, PL_STR_O
branchl r12, Text_InitializeSubtext
mr REG_PEPPY_SUBTEXT, r3
bl FN_PEPPY_SET_SIZE

# One hundred units along X
lfs f1, PL_MARK(REG_PEPPY_DATA)
lfs f2, PL_ZERO(REG_PEPPY_DATA)
mr r3, REG_PEPPY_TEXT
addi r4, REG_PEPPY_DATA, PL_STR_X
branchl r12, Text_InitializeSubtext
mr REG_PEPPY_SUBTEXT, r3
bl FN_PEPPY_SET_SIZE

# One hundred units along Y
lfs f1, PL_ZERO(REG_PEPPY_DATA)
lfs f2, PL_MARK(REG_PEPPY_DATA)
mr r3, REG_PEPPY_TEXT
addi r4, REG_PEPPY_DATA, PL_STR_Y
branchl r12, Text_InitializeSubtext
mr REG_PEPPY_SUBTEXT, r3
bl FN_PEPPY_SET_SIZE

b PEPPY_LABEL_DONE

FN_PEPPY_SET_SIZE:
# Link register kept in a register rather than on the stack - these injections
# run inside someone else's frame.
mflr REG_PEPPY_LR
lfs f1, PL_SIZE(REG_PEPPY_DATA)
fmr f2, f1
mr r3, REG_PEPPY_TEXT
mr r4, REG_PEPPY_SUBTEXT
branchl r12, Text_UpdateSubtextSize
mtlr REG_PEPPY_LR
blr

PEPPY_LABEL_DONE:

################################################################################
# Section 2: Play MELEE on first boot
################################################################################
bl DATA_BLRL
mflr REG_DATA_ADDR
lbz r3, DOFST_IS_FIRST_BOOT(REG_DATA_ADDR)
cmpwi r3, 0
beq SKIP_MELEE_ANOUNCER

#reset pending ssms
branchl r12,0x80026f2c

#request ssm load (nr_names)
li r3, 2
li r5, 0
li r6, 0x8
branchl r12, 0x8002702c

#load pending ssm's
branchl r12, 0x80027168

#wait for all pending ssms to finish loading
branchl r12, 0x80027648

# Play MELEE sfx
li r3, 30005
li r4, 127
li r5, 64
branchl r12, 0x800237a8 # SFX_PlaySoundAtFullVolume

li r3, 0
stb r3, DOFST_IS_FIRST_BOOT(REG_DATA_ADDR)
SKIP_MELEE_ANOUNCER:

################################################################################
# Section 3: Reset any connections if there were any
################################################################################
# Prepare buffer for EXI transfer
li r3, 1
branchl r12, HSD_MemAlloc
mr REG_TXB_ADDR, r3

# Write tx data
li r3, CONST_SlippiCmdCleanupConnections
stb r3, 0(REG_TXB_ADDR)

# Reset connections
mr r3, REG_TXB_ADDR
li r4, 1
li r5, CONST_ExiWrite
branchl r12, FN_EXITransferBuffer

mr r3, REG_TXB_ADDR
branchl r12, HSD_Free

restore

EXIT:
lmw r14, 0x0408 (sp)
