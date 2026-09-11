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

# Take Melee's own formatting and put our words behind it.
#
# Writing the whole string ourselves does not work: it comes out ~45% taller
# than the other descriptions and overflows the box, and it cannot ask to be
# smaller - SCALE is consumed but inert here (probed with a value of 2, nothing
# moved) and FIT fits horizontally only, so it condenses the letters instead.
# Whatever sets the size lives in the opcodes Melee puts at the front of its own
# strings, so rather than guess at them, they are copied verbatim.
#
# Opcodes are below 0x20 and characters are 0x20 and up, so the prefix ends at
# the first character - but opcode parameters can be any value, so each one's
# length comes from the table below.
bl PEPPY_ROOMS_DESC_DATA
mflr r3
lwz r4, 0x5C(r31) # Melee's string for this row, already loaded
addi r5, r3, PRD_BUFFER
mr r6, r5
li r10, 32 # cap the prefix, so a surprise cannot run off the buffer

PEPPY_DESC_PREFIX:
cmpwi r10, 0
beq PEPPY_DESC_WORDS
lbz r7, 0x0(r4)
cmpwi r7, 0x20
bge PEPPY_DESC_WORDS # first character - the formatting is behind us
cmpwi r7, 0x0
beq PEPPY_DESC_WORDS # end of string - nothing to inherit
stb r7, 0x0(r5)
addi r4, r4, 1
addi r5, r5, 1
subi r10, r10, 1

addi r8, r3, PRD_PARAMLEN
lbzx r9, r8, r7
cmpwi r9, 0
beq PEPPY_DESC_PREFIX

PEPPY_DESC_PARAMS:
lbz r7, 0x0(r4)
stb r7, 0x0(r5)
addi r4, r4, 1
addi r5, r5, 1
subi r9, r9, 1
subi r10, r10, 1
cmpwi r9, 0
bne PEPPY_DESC_PARAMS
b PEPPY_DESC_PREFIX

PEPPY_DESC_WORDS:
addi r4, r3, PRD_WORDS
PEPPY_DESC_WORDS_LOOP:
lbz r7, 0x0(r4)
stb r7, 0x0(r5)
addi r4, r4, 1
addi r5, r5, 1
cmpwi r7, 0x0
bne PEPPY_DESC_WORDS_LOOP

stw r6, 0x5C(r31)
b EXIT

PEPPY_ROOMS_DESC_DATA:
blrl
# Built at runtime: their formatting, then our words
.set PRD_BUFFER, 0
.space 96, 0
# Parameter bytes per opcode, 0x00 to 0x1A. From Dolphin's SlippiPremadeText.h:
# 0x05 s, 0x06 ss, 0x07 OFFSET ss, 0x0A SCALING bbbb, 0x0C COLOR bbb,
# 0x0E SET_TEXTBOX ss. Everything else takes none.
.set PRD_PARAMLEN, PRD_BUFFER+96
.byte 0, 0, 0, 0, 0, 2, 4, 4, 0, 0, 4, 0, 3, 0, 4, 0
.byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
# "Public & Private Rooms" - characters only, the formatting is inherited
.set PRD_WORDS, PRD_PARAMLEN+27
.byte 0x20, 0x19, 0x20, 0x38, 0x20, 0x25, 0x20, 0x2F, 0x20, 0x2C, 0x20, 0x26
.byte 0x1A, 0x21, 0x05, 0x1A, 0x20, 0x19, 0x20, 0x35, 0x20, 0x2C, 0x20, 0x39
.byte 0x20, 0x24, 0x20, 0x37, 0x20, 0x28, 0x1A, 0x20, 0x1B, 0x20, 0x32, 0x20
.byte 0x32, 0x20, 0x30, 0x20, 0x36, 0x00
.align 2

EXIT:
restore
# stw	r0, 0x005C (r31) # original line before this one
li	r3, 0 # original line
stb r3, OFST_R13_USE_PREMADE_TEXT(r13) # clear out r13 offset
