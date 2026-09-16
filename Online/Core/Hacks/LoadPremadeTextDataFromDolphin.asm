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
beq ROOMS_DESCRIPTION # the game doing its thing - but it may be our row

# Load Premade text id from dolphin
mr r3, REG_PREMADE_TEXT_ID
mr r4, REG_PREMADE_TEXT_PARAM_1
branchl r12, FN_LoadPremadeText
mr REG_STRING_FORMAT_ADDR, r3
stw REG_STRING_FORMAT_ADDR, 0x5C(r31)
b EXIT

################################################################################
# Rooms: the Rooms row's description
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
ROOMS_DESCRIPTION:
################################################################################
# Rooms: the description line
################################################################################
# Two different treatments, for a reason.
#
# The Rooms LIST draws its own line (FN_RoomsDescription), because substituting
# one here only renders correctly from the second time it is built: Melee
# reserves a width from the original string and justifies ours across it, and
# those lines are much shorter than the ones they replace. So they are blanked.
#
# The Rooms ROW on the mode list still goes through here, because it needs an
# ampersand and the drawn-text path has no glyph for one - probed with & + and @
# and all three came out blank. That line is close enough in length to the one
# it replaces (22 against 26) that the justification never shows.
lis r3, 0x804A
addi r3, r3, 0x4F0
lbz r0, 0x0(r3)
cmpwi r0, 0x8
bne EXIT

# Nine rows is the mode list; every level Rooms adds below it has fewer. The
# same menu is redrawn for all of them, so the row count is what tells them
# apart, and anything that is not the mode list draws its own description.
load r4, 0x803eb750
lbz r4, 0xC(r4)
cmpwi r4, 9
bne ROOMS_BLANK_IT

lhz r0, 0x2(r3)
cmpwi r0, OPTION_ROOMS_IDX
bne EXIT
cmpwi REG_PREMADE_TEXT_ID, 0x064C
bne EXIT

# Melee's own formatting, then our words. Opcodes are below 0x20 and characters
# are 0x20 and up, so the prefix ends at the first character - but opcode
# parameters can be any value, so each one's length comes from the table below.
# FIT is dropped: it scales against a box that is still animating when the line
# is first built.
bl ROOMS_DESC_DATA
mflr r3
lwz r4, 0x5C(r31)
addi r5, r3, PRD_BUFFER
mr r6, r5
li r10, 32

ROOMS_DESC_PREFIX:
cmpwi r10, 0
beq ROOMS_DESC_WORDS
lbz r7, 0x0(r4)
cmpwi r7, 0x20
bge ROOMS_DESC_WORDS
cmpwi r7, 0x0
beq ROOMS_DESC_WORDS
cmpwi r7, 0x18
beq ROOMS_DESC_DROP_FIT
stb r7, 0x0(r5)
addi r5, r5, 1

ROOMS_DESC_DROP_FIT:
addi r4, r4, 1
subi r10, r10, 1
addi r8, r3, PRD_PARAMLEN
lbzx r9, r8, r7
cmpwi r9, 0
beq ROOMS_DESC_PREFIX

ROOMS_DESC_PARAMS:
lbz r7, 0x0(r4)
stb r7, 0x0(r5)
addi r4, r4, 1
addi r5, r5, 1
subi r9, r9, 1
subi r10, r10, 1
cmpwi r9, 0
bne ROOMS_DESC_PARAMS
b ROOMS_DESC_PREFIX

ROOMS_DESC_WORDS:
addi r4, r3, PRD_WORDS

ROOMS_DESC_WORDS_LOOP:
lbz r7, 0x0(r4)
stb r7, 0x0(r5)
addi r4, r4, 1
addi r5, r5, 1
cmpwi r7, 0x0
bne ROOMS_DESC_WORDS_LOOP

stw r6, 0x5C(r31)
b EXIT

ROOMS_BLANK_IT:
bl ROOMS_DESC_DATA
mflr r3
addi r3, r3, PRD_EMPTY
stw r3, 0x5C(r31)
b EXIT

ROOMS_DESC_DATA:
blrl
.set PRD_BUFFER, 0
.space 96, 0
# Parameter bytes per opcode, 0x00 to 0x1A, from Dolphin's SlippiPremadeText.h
.set PRD_PARAMLEN, PRD_BUFFER+96
.byte 0, 0, 0, 0, 0, 2, 4, 4, 0, 0, 4, 0, 3, 0, 4, 0
.byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
# "Public & Private Rooms" - characters only, the formatting is inherited. The
# ampersand is index 261, which is why it needs the two-byte form.
.set PRD_WORDS, PRD_PARAMLEN+27
.byte 0x20, 0x19, 0x20, 0x38, 0x20, 0x25, 0x20, 0x2F, 0x20, 0x2C, 0x20, 0x26
.byte 0x1A, 0x21, 0x05, 0x1A, 0x20, 0x19, 0x20, 0x35, 0x20, 0x2C, 0x20, 0x39
.byte 0x20, 0x24, 0x20, 0x37, 0x20, 0x28, 0x1A, 0x20, 0x1B, 0x20, 0x32, 0x20
.byte 0x32, 0x20, 0x30, 0x20, 0x36, 0x00
.set PRD_EMPTY, PRD_WORDS+42
.byte 0x00
.align 2

EXIT:
restore
# stw	r0, 0x005C (r31) # original line before this one
li	r3, 0 # original line
stb r3, OFST_R13_USE_PREMADE_TEXT(r13) # clear out r13 offset
