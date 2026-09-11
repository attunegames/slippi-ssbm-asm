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
################################################################################
# Peppy: blank the description line for rows that are ours
################################################################################
# Not substituted - BLANKED, and drawn separately instead.
#
# Substituting a string here worked but only from the second time a line was
# built. The first one after a menu is built comes out letter-spaced: the
# letters are the right size and spread apart, which is justification, not
# scaling - Melee reserves a width from the original string and spreads ours
# across it, and ours are much shorter than the lines they replace. It is never
# rebuilt, so it stays wrong until the cursor moves and comes back. Neither
# dropping FIT nor padding with spaces touched it.
#
# So Melee draws nothing for these rows and the line is drawn with our own text,
# where nothing depends on the frame it was born on. See FN_PeppyDescription.
lis r3, 0x804A
addi r3, r3, 0x4F0
lbz r0, 0x0(r3)
cmpwi r0, 0x8
bne EXIT

# Which list is on screen? Five rows is the Rooms list, nine the mode list -
# the same menu redrawn, so the row count is what tells them apart.
load r4, 0x803eb750
lbz r4, 0xC(r4)
cmpwi r4, 5
beq PEPPY_BLANK_IT

lhz r0, 0x2(r3)
cmpwi r0, OPTION_ROOMS_IDX
bne EXIT
cmpwi REG_PREMADE_TEXT_ID, 0x064C
bne EXIT

PEPPY_BLANK_IT:
bl PEPPY_ROOMS_DESC_DATA
mflr r3
addi r3, r3, PRD_EMPTY
stw r3, 0x5C(r31)
b EXIT

PEPPY_ROOMS_DESC_DATA:
blrl
.set PRD_EMPTY, 0
.byte 0x00
.align 2

EXIT:
restore
# stw	r0, 0x005C (r31) # original line before this one
li	r3, 0 # original line
stb r3, OFST_R13_USE_PREMADE_TEXT(r13) # clear out r13 offset
