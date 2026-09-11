################################################################################
# Address: 0x803a63a8 # Address in Text_CopyPremadeTextDataToStruct right after
# encoded string is stored in in r0
################################################################################
# Usage:
# OFST_R13_USE_PREMADE_TEXT must be > 0 to use this patch
################################################################################
# Inputs:
# r6 is the actual slippi text id of the text we want to read
################################################################################

.include "Common/Common.s"
.include "Online/Online.s"

.set REG_STRING_FORMAT_ADDR, 30
.set REG_PREMADE_TEXT_ID, REG_STRING_FORMAT_ADDR-1
.set REG_PREMADE_TEXT_PARAM_1, REG_PREMADE_TEXT_ID-1

backup
mr REG_PREMADE_TEXT_ID, r4
mr REG_PREMADE_TEXT_PARAM_1, r6

# So, what we are going to do here is request a READ from the EXI device which
# will return the encoded string requested with an ID and then store that into
# the text data struct
lbz r3, OFST_R13_USE_PREMADE_TEXT(r13)
cmpwi r3, 0
beq PEPPY_ROOMS_DESCRIPTION # the game doing its thing - but it may be our row

# Load Premade text id from dolphin
mr r3, REG_PREMADE_TEXT_ID
mr r4, REG_PREMADE_TEXT_PARAM_1
branchl r12, FN_LoadPremadeText
mr REG_STRING_FORMAT_ADDR, r3
stw REG_STRING_FORMAT_ADDR, 0x5C(r31)
b EXIT

################################################################################
# Peppy: the Rooms row's description
################################################################################
# Descriptions are premade strings in Melee's .dat, indexed by id, and there is
# no id for a row Melee has never heard of - so the Rooms row borrows Party's
# and reads "Play FFA games with items.".
#
# This is the function that loads those strings, and Slippi already hooks it to
# serve text from Dolphin, so the string can simply be swapped here. Ours is
# encoded into Melee's own text format (opcodes and character map are in
# Dolphin's SlippiPremadeText.h) and lives in this codeset, which means no
# Dolphin build and no new text id.
#
# Narrow on purpose: this function draws every premade string in the game, so it
# only swaps when the online submenu is up, the Rooms row is the selected one,
# and the id being asked for is the one that row carries.
PEPPY_ROOMS_DESCRIPTION:
lis r3, 0x804A
addi r3, r3, 0x4F0
lbz r0, 0x0(r3)
cmpwi r0, 0x8
bne EXIT
lhz r0, 0x2(r3)
cmpwi r0, OPTION_ROOMS_IDX
bne EXIT
cmpwi REG_PREMADE_TEXT_ID, 0x064C
bne EXIT

bl PEPPY_ROOMS_DESC_DATA
mflr r3
stw r3, 0x5C(r31)
b EXIT

PEPPY_ROOMS_DESC_DATA:
blrl
# "Public & Private Rooms".
#   SCALE   - the string renders far larger than Melee's own descriptions
#             otherwise. FIT was tried and clamps to the box width, which
#             overrides SCALE entirely - so it is SCALE alone that sets the size.
#   CENTER, KERN - the other descriptions are centred and tightly spaced
.byte 0x0A, 0x00, 0x46, 0x00, 0x46, 0x10, 0x16, 0x20, 0x19, 0x20, 0x38, 0x20, 0x25, 0x20, 0x2F, 0x20, 0x2C
.byte 0x20, 0x26, 0x1A, 0x21, 0x05, 0x1A, 0x20, 0x19, 0x20, 0x35, 0x20, 0x2C
.byte 0x20, 0x39, 0x20, 0x24, 0x20, 0x37, 0x20, 0x28, 0x1A, 0x20, 0x1B, 0x20
.byte 0x32, 0x20, 0x32, 0x20, 0x30, 0x20, 0x36, 0x00
.align 2

EXIT:
restore
# stw	r0, 0x005C (r31) # original line before this one
li	r3, 0 # original line
stb r3, OFST_R13_USE_PREMADE_TEXT(r13) # clear out r13 offset
