################################################################################
# Address: 0x801b1040 # ScenePrep_MainMenu
################################################################################

.include "Common/Common.s"
.include "Online/Online.s"

# general registers
.set REG_FG_USER_DISPLAY, 21
.set REG_DLG_BUFFER_SIZE, REG_FG_USER_DISPLAY+1
.set REG_DLG_BUFFER_ADDRESS, REG_DLG_BUFFER_SIZE+1

.set REG_DLG_GOBJ, REG_DLG_BUFFER_ADDRESS+1
.set REG_DLG_JOBJ, REG_DLG_GOBJ+1

# Registers used on Dialog think function, start at REG_DLG_JOBJ
.set REG_DLG_USER_DATA_ADDR, REG_DLG_JOBJ+1
.set REG_DLG_SELECTED_OPTION, REG_DLG_USER_DATA_ADDR+1 # 0: NO, 1: YES
.set REG_DLG_MENU_GOBJ_ADDR, REG_DLG_SELECTED_OPTION+1
.set REG_DLG_TEXT_STRUCT_ADDR, REG_DLG_MENU_GOBJ_ADDR+1
.set REG_TEXT_PROPERTIES, REG_DLG_TEXT_STRUCT_ADDR+1

.set REG_JOBJ_DESC_ADDR, REG_DLG_USER_DATA_ADDR
.set REG_JOBJ_DESC_ANIM_JOINT_ADDR, REG_JOBJ_DESC_ADDR+1
.set REG_JOBJ_DESC_MAT_JOINT_ADDR, REG_JOBJ_DESC_ANIM_JOINT_ADDR+1
.set REG_JOBJ_DESC_SHAPE_JOINT_ADDR, REG_JOBJ_DESC_MAT_JOINT_ADDR+1

# float registers
.set REG_F_0, 31
.set REG_F_1, 30

# Dialog Constants
.set DLG_JOBJ_OFFSET, 0x28 # offset from GOBJ to HSD Object (Jobj we assigned)
.set DLG_USER_DATA_OFFSET, 0x2C # offset from GOBJ to entity data
.set DLG_OPTION_YES, 0x1
.set DLG_OPTION_NO, 0x0

# PAD Constants for dialog when using Inputs_GetPlayerHeldInputs on the dialog
.set PAD_LEFT, 0x40 # on r4 is 00040000
.set PAD_RIGHT, 0x80 # on r4 is 00080000
.set PAD_A, 0x01 # on r4 is 00000100
.set PAD_B, 0x02 # on r4 is 00000200

# Dialog Static Memory JOBJ Descriptors Locations/Pointers
.set JOBJ_DESC_DLG, 0x803efa0c # archive memory address of dialog jobj
.set JOBJ_DESC_DLG_ANIM_JOINT, 0x803efa24 # archive memory address of dialog anim joint
.set JOBJ_DESC_DLG_MAT_JOINT, 0x803efa40 # archive memory address of dialog mat joint
.set JOBJ_DESC_DLG_SHAPE_JOINT, 0x803efa60 # archive memory address of dialog shape joint
.set JOBJ_CHILD_OFFSET, BKP_FREE_SPACE_OFFSET # Pointer to store Child JOBJ on the SP

# Offset from submenu gobj where we are storing dialog user data buffer when
# open
.set MENU_DLG_USER_DATA_OFFSET, 0x8

# Dialog Buffer Data Table
.set DLG_DT_SELECTED_OPTION, 0 # u8
.set DLG_DT_SUBMENU_GOBJ_ADDR, DLG_DT_SELECTED_OPTION+1 # u32
.set DLG_DT_TEXT_STRUCT_ADDR, DLG_DT_SUBMENU_GOBJ_ADDR+4 # u32
.set DLG_DT_SIZE, DLG_DT_TEXT_STRUCT_ADDR + 4

backup

################################################################################
# Section 0: Peppy - forget last visit's Rooms label
################################################################################
# The label's text object dies with the scene, so the stored pointer is stale
# every time the main menu is loaded afresh. Clearing it here is what makes the
# lazy creation in the submenu think safe.
bl PEPPY_LABEL_DATA
mflr r3
li r4, 0
stw r4, PLD_TEXT_PTR(r3)
stw r4, PLD_LEVEL(r3)

bl PEPPY_ROWS_DATA
mflr r3
li r5, 0
PEPPY_SCENE_PREP_CLEAR_ROWS:
mulli r6, r5, 4
addi r7, r3, PRW_STRUCTS
stwx r4, r7, r6
addi r5, r5, 1
cmpwi r5, PRW_ROW_COUNT
blt PEPPY_SCENE_PREP_CLEAR_ROWS

################################################################################
# Section 1: Overwrite handler function pointer for going back to menu from
# major 0x8
################################################################################
bl FN_OnReturnFromOnline
mflr r3
load r4, 0x803dd908
stw r3, 0(r4)

################################################################################
# Section 2: Prepare the online submenu
################################################################################
load r3, 0x803eb750 # Start of online submenu entry (0x14 long)

# Write the ptr to think function
bl FN_OnlineSubmenuThink
mflr r4
stw r4, 0x10(r3)

# Write other submenu data
bl Data_OnlineSubmenuOptions
mflr r4
li r5, 0x10
branchl r12, memcpy

load r3, 0x803eb750 # Start of online submenu entry (0x14 long)
bl Data_OnlineSubmenuDescriptions
mflr r4
stw r4, 0x8(r3) # Overwrite description text locations

load r3, 0x803eb66c # Start or 1P mode submenu entry
li r4, 0x644
sth r4, 0x4(r3) # Set 3rd option description text (online submenu)

################################################################################
# Section 3: Store function for switching to online submenu
################################################################################
bl FN_SwitchToOnlineMenu_blrl
mflr r3
stw r3, OFST_R13_SWITCH_TO_ONLINE_SUBMENU(r13)

################################################################################
# Section 4: Prepare user display buffers and data for finding first unlocked
# when returning from online menu or any other menu. Also prepares it for the
# actual user display
################################################################################
# Get static function table
branchl r12, FG_UserDisplay
mflr REG_FG_USER_DISPLAY # This will be restored by parent function

# Init app state buffers
addi r12, REG_FG_USER_DISPLAY, 0x14 # FN_InitBuffers
mtctr r12
bctrl

# Fetch app state, used to determine which options are hidden
addi r12, REG_FG_USER_DISPLAY, 0xC # FN_FetchSlippiAppState
mtctr r12
bctrl

restore
b EXIT

################################################################################
# Routine: OnReturnFromOnline
# ------------------------------------------------------------------------------
# Description: Writes the proper menu and selection when returning from online
# mode
################################################################################
.set REG_FG_USER_DISPLAY, 30 # This will be reset by parent function

FN_OnReturnFromOnline:
blrl

# Get static function table
branchl r12, FG_UserDisplay
mflr REG_FG_USER_DISPLAY # This will be restored by parent function

# Set the submenu to go to
li r0, 8 # Go to submenu 0x8 (Online Play)
stb r0, 0(r31)

# Get the selected index we want.
#
# The option index is the mode number for Ranked through Party, because those
# numbers coincide. Rooms is mode 5 but sits last in the list, so it needs
# translating - done inline rather than in a helper, because a helper's compare
# would clobber the condition register this code branches on.
li r3, 0x8
lbz r4, OFST_R13_ONLINE_MODE(r13)
cmpwi r4, ONLINE_MODE_ROOMS
bne FN_OnReturnFromOnline_CHECK_UNLOCKED
li r4, OPTION_ROOMS_IDX

FN_OnReturnFromOnline_CHECK_UNLOCKED:
branchl r12, 0x80229938 # MainMenu_CheckIfOptionIsUnlocked
cmpwi r3, 0
beq FN_OnReturnFromOnline_GET_FIRST_UNLOCKED

# Unlocked - select it
lbz r3, OFST_R13_ONLINE_MODE(r13)
cmpwi r3, ONLINE_MODE_ROOMS
bne FN_OnReturnFromOnline_SET_SELECTED_INDEX
li r3, OPTION_ROOMS_IDX
b FN_OnReturnFromOnline_SET_SELECTED_INDEX

FN_OnReturnFromOnline_GET_FIRST_UNLOCKED:
addi r12, REG_FG_USER_DISPLAY, 0x10 # FN_GetFirstUnlocked
mtctr r12
bctrl

FN_OnReturnFromOnline_SET_SELECTED_INDEX:
stb r3, 0x1(r31)

# Go to end of function
branch r12, 0x801b136c

################################################################################
# Routine: SwitchToOnlineMenu
# ------------------------------------------------------------------------------
# Description: Triggers a switch to the online submenu
################################################################################
FN_SwitchToOnlineMenu_blrl:
blrl
FN_SwitchToOnlineMenu:
backup

# Most of the code in this function is stolen from game logic so it's a bit
# weird... r27 is returned as r3 so it can mimic a direct function call
load r31, 0x804a04f0
load r30, 0x803eae68

li	r0, 5
sth	r0, -0x4AD8 (r13)

# Fetch first unlocked option
branchl r12, FG_UserDisplay
mflr r3
addi r12, r3, 0x10 # FN_GetFirstUnlocked
mtctr r12
bctrl
mr r0, r3 # Option to select

# Continue
li	r4, 8 # Go to online menu
lbz	r5, 0 (r31)
li	r3, 1
stb	r5, 0x0001 (r31)
stb	r4, 0 (r31)
sth	r0, 2 (r31)
branchl r12, 0x8022B3A0
branchl r12, 0x80390CD4
lwz	r3, -0x3E84 (r13)
branchl r12, 0x80390228
lwz	r27, 0x08F8 (r30) # Load think function
cmplwi	r27, 0
beq- SKIP_TO_END_OF_PARENT
li	r3, 0
li	r4, 1
li	r5, 128
branchl r12, GObj_Create
addi	r4, r27, 0
li	r5, 0
branchl r12, GObj_AddProc
lwz	r4, -0x3E64 (r13)
lbz	r0, 0x000D (r3)
rlwimi	r0, r4, 4, 26, 27
stb	r0, 0x000D (r3)

# Force menu to change (normally changing to the same menu would not clear old menu)
li r3, 1
stb r3, OFST_R13_FORCE_MENU_CLEAR(r13)

# Return this such that we can mimic a direct execution
mr r3, r27

restore
blr

################################################################################
# Routine: PeppyRoomsLabels
# ------------------------------------------------------------------------------
# Names the five rows of the Rooms list, the same way the Rooms row itself is
# named: the artwork word is buried under a copy of itself in the plate's
# colour, then ours is drawn on top.
#
# One text struct per row rather than one for all five - that keeps each row's
# subtext count at eight, which is where the single-row version is already known
# to work, instead of asking one struct to hold forty.
################################################################################
.set REG_PRL_DATA, 31
.set REG_PRL_ROW, 30
.set REG_PRL_TEXT, 29
.set REG_PRL_I, 28
.set REG_PRL_COVER, 27
.set REG_PRL_SELECTED, 26
.set REG_PRL_PLATE, 25
.set REG_PRL_WORD, 24
.set REG_PRL_TMP, 23

FN_PeppyRoomsLabels:
backup

bl PEPPY_ROWS_DATA
mflr REG_PRL_DATA

# Only while the Rooms list is the thing on screen
bl PEPPY_LABEL_DATA
mflr r3
lwz r0, PLD_LEVEL(r3)
cmpwi r0, 1
bne FN_PeppyRoomsLabels_TEARDOWN
lis r3, 0x804A
addi r3, r3, 0x4F0
lbz r0, 0x0(r3)
cmpwi r0, 0x8
bne FN_PeppyRoomsLabels_TEARDOWN

lwz r0, PRW_STRUCTS(REG_PRL_DATA)
cmpwi r0, 0
bne FN_PeppyRoomsLabels_PAINT

################################################################################
# Build them
################################################################################
li REG_PRL_I, 0

FN_PeppyRoomsLabels_BUILD:
mulli r3, REG_PRL_I, 16
addi REG_PRL_ROW, REG_PRL_DATA, PRW_ROWS
add REG_PRL_ROW, REG_PRL_ROW, r3

li r3, 0
li r4, 0
branchl r12, Text_CreateStruct
mr REG_PRL_TEXT, r3

mulli r4, REG_PRL_I, 4
addi r5, REG_PRL_DATA, PRW_STRUCTS
stwx REG_PRL_TEXT, r5, r4

# Close kerning, centred - the row words are centred on their plate
li r4, 0x1
stb r4, 0x49(REG_PRL_TEXT)
stb r4, 0x4A(REG_PRL_TEXT)

lfs f1, PRW_Z(REG_PRL_DATA)
stfs f1, 0x8(REG_PRL_TEXT)
lfs f1, PRW_SCALE(REG_PRL_DATA)
stfs f1, 0x24(REG_PRL_TEXT)
stfs f1, 0x28(REG_PRL_TEXT)

# The cover, seven offset copies of the word underneath
li REG_PRL_COVER, 0

FN_PeppyRoomsLabels_COVER:
mulli r3, REG_PRL_COVER, 8
addi r4, REG_PRL_DATA, PRW_COVERS
add r4, r4, r3
lfs f1, 0x0(REG_PRL_ROW)
lfs f2, 0x4(REG_PRL_ROW)
lfs f3, 0x0(r4)
lfs f4, 0x4(r4)
fadds f1, f1, f3
fadds f2, f2, f4
mr r3, REG_PRL_TEXT
lwz r4, 0xC(REG_PRL_ROW)
add r4, REG_PRL_DATA, r4
branchl r12, Text_InitializeSubtext
mr REG_PRL_TMP, r3
lfs f1, PRW_SIZE(REG_PRL_DATA)
fmr f2, f1
mr r3, REG_PRL_TEXT
mr r4, REG_PRL_TMP
branchl r12, Text_UpdateSubtextSize
addi REG_PRL_COVER, REG_PRL_COVER, 1
cmpwi REG_PRL_COVER, PRW_COVER_COUNT
blt FN_PeppyRoomsLabels_COVER

# And the word itself, on top
lfs f1, 0x0(REG_PRL_ROW)
lfs f2, 0x4(REG_PRL_ROW)
mr r3, REG_PRL_TEXT
lwz r4, 0x8(REG_PRL_ROW)
add r4, REG_PRL_DATA, r4
branchl r12, Text_InitializeSubtext
mr REG_PRL_TMP, r3
lfs f1, PRW_SIZE(REG_PRL_DATA)
fmr f2, f1
mr r3, REG_PRL_TEXT
mr r4, REG_PRL_TMP
branchl r12, Text_UpdateSubtextSize

addi REG_PRL_I, REG_PRL_I, 1
cmpwi REG_PRL_I, PRW_ROW_COUNT
blt FN_PeppyRoomsLabels_BUILD

################################################################################
# Colour them, every frame, so each row follows its own selected state
################################################################################
FN_PeppyRoomsLabels_PAINT:
lis r3, 0x804A
addi r3, r3, 0x4F0
lhz REG_PRL_SELECTED, 0x2(r3)

li REG_PRL_I, 0

FN_PeppyRoomsLabels_PAINT_ROW:
mulli r4, REG_PRL_I, 4
addi r5, REG_PRL_DATA, PRW_STRUCTS
lwzx REG_PRL_TEXT, r5, r4
cmpwi REG_PRL_TEXT, 0
beq FN_PeppyRoomsLabels_PAINT_NEXT

cmpw REG_PRL_I, REG_PRL_SELECTED
beq FN_PeppyRoomsLabels_PAINT_PICKED
addi REG_PRL_PLATE, REG_PRL_DATA, PRW_COL_PLATE_IDLE
addi REG_PRL_WORD, REG_PRL_DATA, PRW_COL_WORD_IDLE
b FN_PeppyRoomsLabels_PAINT_DO

FN_PeppyRoomsLabels_PAINT_PICKED:
addi REG_PRL_PLATE, REG_PRL_DATA, PRW_COL_PLATE_PICKED
addi REG_PRL_WORD, REG_PRL_DATA, PRW_COL_WORD_PICKED

FN_PeppyRoomsLabels_PAINT_DO:
li REG_PRL_COVER, 0

FN_PeppyRoomsLabels_PAINT_COVER:
mr r3, REG_PRL_TEXT
mr r4, REG_PRL_COVER
mr r5, REG_PRL_PLATE
branchl r12, Text_ChangeTextColor
addi REG_PRL_COVER, REG_PRL_COVER, 1
cmpwi REG_PRL_COVER, PRW_COVER_COUNT
blt FN_PeppyRoomsLabels_PAINT_COVER

mr r3, REG_PRL_TEXT
li r4, PRW_COVER_COUNT
mr r5, REG_PRL_WORD
branchl r12, Text_ChangeTextColor

FN_PeppyRoomsLabels_PAINT_NEXT:
addi REG_PRL_I, REG_PRL_I, 1
cmpwi REG_PRL_I, PRW_ROW_COUNT
blt FN_PeppyRoomsLabels_PAINT_ROW
b FN_PeppyRoomsLabels_EXIT

################################################################################
# Take them down
################################################################################
FN_PeppyRoomsLabels_TEARDOWN:
li REG_PRL_I, 0

FN_PeppyRoomsLabels_TEARDOWN_ROW:
mulli r4, REG_PRL_I, 4
addi r5, REG_PRL_DATA, PRW_STRUCTS
lwzx r3, r5, r4
cmpwi r3, 0
beq FN_PeppyRoomsLabels_TEARDOWN_NEXT
branchl r12, Text_RemoveText
li r3, 0
mulli r4, REG_PRL_I, 4
addi r5, REG_PRL_DATA, PRW_STRUCTS
stwx r3, r5, r4

FN_PeppyRoomsLabels_TEARDOWN_NEXT:
addi REG_PRL_I, REG_PRL_I, 1
cmpwi REG_PRL_I, PRW_ROW_COUNT
blt FN_PeppyRoomsLabels_TEARDOWN_ROW

FN_PeppyRoomsLabels_EXIT:
restore
blr

################################################################################
# Routine: PeppyEnterSubmenu
# ------------------------------------------------------------------------------
# Installs an option table and rebuilds the online submenu in place. This is how
# the Rooms list can be a second level without a second menu: Melee is told to
# switch to the menu it is already on, which normally does nothing - Slippi's
# AllowSwapToSameSubmenu patch plus the force-clear flag is what makes it redraw.
#
# The sequence after the table swap is the one the B press handler uses to go
# back to the 1-P menu, pointed at menu 8 instead.
#
# r3 - option table to install, 0x10 bytes
# r4 - description table for it
# r5 - option to select
# r6 - transition kind: 1 going deeper, 3 coming back
################################################################################
.set REG_PES_SELECTED, 27
.set REG_PES_TRANSITION, 26
.set REG_PES_MENU, 25

FN_PeppyEnterSubmenu:
backup

mr REG_PES_SELECTED, r5
mr REG_PES_TRANSITION, r6
mr REG_PES_MENU, r4

mr r4, r3
load r3, 0x803eb750
li r5, 0x10
branchl r12, memcpy

load r3, 0x803eb750
stw REG_PES_MENU, 0x8(r3) # Overwrite description text locations

# Without this, switching to the menu we are already on does nothing
li r3, 1
stb r3, OFST_R13_FORCE_MENU_CLEAR(r13)

load r29, 0x804a04f0
li r0, 5
sth r0, -0x4AD8 (r13)
lbz r4, 0x0 (r29)
stb r4, 0x0001 (r29) # Previous menu
li r0, 8
stb r0, 0x0 (r29) # Still the online submenu
sth REG_PES_SELECTED, 0x0002 (r29)

mr r3, REG_PES_TRANSITION
branchl r12, 0x8022B3A0
branchl r12, 0x80390CD4
lwz r3, -0x3E84 (r13)
branchl r12, 0x80390228

load r3, 0x803eb760 # Think function for menu 8, which is ours
lwz r28, 0x0(r3)
cmplwi r28, 0
beq FN_PeppyEnterSubmenu_EXIT

li r3, 0
li r4, 1
li r5, 128
branchl r12, 0x803901F0 # GObj_Create
addi r4, r28, 0
li r5, 0
branchl r12, 0x8038FD54 # GObj_AddProc
lwz r4, -0x3E64 (r13)
lbz r0, 0x000D (r3)
rlwimi r0, r4, 4, 26, 27
stb r0, 0x000D (r3)

FN_PeppyEnterSubmenu_EXIT:
restore
blr

################################################################################
# Routine: OnlineSubmenuThink
# ------------------------------------------------------------------------------
# Description: Think function for online submenu
################################################################################
.set REG_FG_USER_DISPLAY, 27
.set REG_SM_GOBJ, 19

FN_OnlineSubmenuThink:
blrl

.set NUM_FREG, 0
.set NUM_GPREG, 18
backup BKP_DEFAULT_FREE_SPACE_SIZE, NUM_FREG, NUM_GPREG

################################################################################
# Check if confirm dialog is open or not, and prevent input if it is
################################################################################
mr REG_SM_GOBJ, r3

lwz r3, MENU_DLG_USER_DATA_OFFSET(REG_SM_GOBJ)
cmpwi r3, 0
bne FN_OnlineSubmenuThink_INPUT_HANDLERS_END

################################################################################
# Most of the below is ported code from function 8022cc28 (Menus_RegularMatch)
################################################################################
lis r3, 0x804A
addi r29, r3, 0x4F0
li r3, 4
branchl r12, 0x80229624 # MainMenu_GetAllControllerInstantButtons
stw r3, 0xC(r29)
li	r30, 0
stw	r30, 0x0008 (r29)
rlwinm.	r0, r3, 0, 27, 27
beq- FN_OnlineSubmenuThink_A_PRESS_HANDLER_END

################################################################################
# A Press Handler
################################################################################
FN_OnlineSubmenuThink_A_PRESS_HANDLER:
# The following is copied and I think its primary goal is to update which
# controller is considered to be the "active player"
li	r0, 5
sth	r0, -0x4AD8 (r13)
li	r31, 1
addi	r28, r30, 0
stb	r31, 0x0011 (r29)
FN_OnlineSubmenuThink_A_PRESS_CHECK_PORT_INPUTS:
rlwinm	r3, r28, 0, 24, 31
branchl r12, Inputs_GetPlayerInstantInputs 
and	r0, r3, r31
and	r4, r4, r30
xor	r3, r4, r30
xor	r0, r0, r30
or.	r0, r3, r0
beq- FN_OnlineSubmenuThink_A_PRESS_CHECK_NEXT_PORT
rlwinm	r3, r28, 0, 24, 31
b	FN_OnlineSubmenuThink_A_PRESS_UPDATE_PLAYER_PORT
FN_OnlineSubmenuThink_A_PRESS_CHECK_NEXT_PORT:
addi	r28, r28, 1
cmpwi	r28, 4
blt+ FN_OnlineSubmenuThink_A_PRESS_CHECK_PORT_INPUTS
li	r3, 0
FN_OnlineSubmenuThink_A_PRESS_UPDATE_PLAYER_PORT:
branchl r12, 0x801677E8 # CSS_StoreSinglePlayerPortNumber

lhz r0, 0x0002 (r29) # Load selected option index

# Peppy: on the Rooms list these indices mean Singles, Doubles and so on
bl PEPPY_LABEL_DATA
mflr r3
lwz r3, PLD_LEVEL(r3)
cmpwi r3, 1
beq FN_OnlineSubmenuThink_ROOMS_DISPATCH

cmpwi r0, OPTION_RANKED_IDX # Check if Ranked
beq FN_OnlineSubmenuThink_HANDLE_RANKED
cmpwi r0, OPTION_UNRANKED_IDX # Check if Unranked
beq FN_OnlineSubmenuThink_HANDLE_UNRANKED
cmpwi r0, OPTION_DIRECT_IDX # Check if Direct
beq FN_OnlineSubmenuThink_HANDLE_DIRECT
cmpwi r0, OPTION_TEAMS_IDX # Check if teams
beq FN_OnlineSubmenuThink_HANDLE_TEAMS
cmpwi r0, OPTION_PARTY_IDX # Check if party
beq FN_OnlineSubmenuThink_HANDLE_PARTY
cmpwi r0, OPTION_LOGIN_IDX # Check if Log-in
beq FN_OnlineSubmenuThink_HANDLE_LOGIN
cmpwi r0, OPTION_LOGOUT_IDX # Check if Log-out
beq FN_OnlineSubmenuThink_HANDLE_LOGOUT
cmpwi r0, OPTION_UPDATE_IDX # Check if update
beq FN_OnlineSubmenuThink_HANDLE_UPDATE
cmpwi r0, OPTION_ROOMS_IDX # Check if Peppy rooms
beq FN_OnlineSubmenuThink_HANDLE_ROOMS
b FN_OnlineSubmenuThink_INPUT_HANDLERS_END

################################################################################
# Option Selected Handlers
################################################################################
FN_OnlineSubmenuThink_HANDLE_RANKED:
li r3, ONLINE_MODE_RANKED
b FN_OnlineSubmenuThink_GO_TO_CSS

FN_OnlineSubmenuThink_HANDLE_UNRANKED:
li r3, ONLINE_MODE_UNRANKED
b FN_OnlineSubmenuThink_GO_TO_CSS

FN_OnlineSubmenuThink_HANDLE_DIRECT:
li r3, ONLINE_MODE_DIRECT
b FN_OnlineSubmenuThink_GO_TO_CSS

FN_OnlineSubmenuThink_HANDLE_TEAMS:
li r3, ONLINE_MODE_TEAMS
b FN_OnlineSubmenuThink_GO_TO_CSS

# Peppy: Rooms opens its own list rather than starting a match.
FN_OnlineSubmenuThink_HANDLE_ROOMS:
li r3, 1
branchl r12, SFX_Menu_CommonSound

bl PEPPY_LABEL_DATA
mflr r3
li r4, 1
stw r4, PLD_LEVEL(r3)

bl Data_RoomsSubmenuOptions
mflr r3
bl Data_RoomsSubmenuDescriptions
mflr r4
li r5, 0
li r6, 1
bl FN_PeppyEnterSubmenu
b FN_OnlineSubmenuThink_INPUT_HANDLERS_END

################################################################################
# The Rooms list
################################################################################
# Singles is the mode that exists today - it is what Rooms did before this list
# was in front of it. The other four are named but have nothing to start yet, so
# they say no rather than pretending.
.set ROOMS_OPT_SINGLES, 0

FN_OnlineSubmenuThink_ROOMS_DISPATCH:
cmpwi r0, ROOMS_OPT_SINGLES
beq FN_OnlineSubmenuThink_HANDLE_SINGLES

li r3, 0xbc
li r4, 127
li r5, 64
branchl r12, 0x800237a8 # SFX_PlaySoundAtFullVolume
b FN_OnlineSubmenuThink_INPUT_HANDLERS_END

FN_OnlineSubmenuThink_HANDLE_SINGLES:
li r3, ONLINE_MODE_ROOMS
b FN_OnlineSubmenuThink_GO_TO_CSS

FN_OnlineSubmenuThink_HANDLE_PARTY:
li r3, ONLINE_MODE_PARTY
b FN_OnlineSubmenuThink_GO_TO_CSS

FN_OnlineSubmenuThink_HANDLE_LOGIN:
li	r3, 1
branchl r12, SFX_Menu_CommonSound

li r4, CONST_SlippiCmdOpenLogIn
b FN_OnlineSubmenuThink_TRIGGER_EXI_MSG

FN_OnlineSubmenuThink_HANDLE_LOGOUT: # crash at 80370c28

# Play Warning sfx
li r3, 0xbc
li r4, 127
li r5, 64
branchl r12, 0x800237a8 # SFX_PlaySoundAtFullVolume

bl FN_CREATE_DIALOG
b FN_OnlineSubmenuThink_INPUT_HANDLERS_END

FN_OnlineSubmenuThink_HANDLE_UPDATE:
li	r3, 1
branchl r12, SFX_Menu_CommonSound

li r4, CONST_SlippiCmdUpdateApp
b FN_OnlineSubmenuThink_TRIGGER_EXI_MSG

FN_OnlineSubmenuThink_GO_TO_CSS:
# Set the selected mode
stb r3, OFST_R13_ONLINE_MODE(r13)

# Play success sound
li	r3, 1
branchl r12, SFX_Menu_CommonSound

# Go to online mode CSS
li r3, 0x8
branchl r12, Event_StoreSceneNumber
b FN_OnlineSubmenuThink_INPUT_HANDLERS_END

FN_OnlineSubmenuThink_TRIGGER_EXI_MSG:
# Use the scene buffer cause it's not being used for anything
lwz r3, OFST_R13_SB_ADDR(r13)
stb r4, 0(r3) # Store command byte
li r4, 1
li r5, CONST_ExiWrite
branchl r12, FN_EXITransferBuffer

b FN_OnlineSubmenuThink_INPUT_HANDLERS_END

FN_OnlineSubmenuThink_A_PRESS_HANDLER_END:

rlwinm.	r0, r3, 0, 26, 26
beq- FN_OnlineSubmenuThink_B_PRESS_HANDLER_END

################################################################################
# B Press Handler
################################################################################
FN_OnlineSubmenuThink_B_PRESS_HANLER:
# Peppy: on the Rooms list, B goes back to the mode list rather than out of
# online play, and puts the cursor back on the row that opened it.
bl PEPPY_LABEL_DATA
mflr r3
lwz r0, PLD_LEVEL(r3)
cmpwi r0, 1
bne FN_OnlineSubmenuThink_B_LEAVE_ONLINE

li r4, 0
stw r4, PLD_LEVEL(r3)
li r3, 0
branchl r12, SFX_Menu_CommonSound

bl Data_OnlineSubmenuOptions
mflr r3
bl Data_OnlineSubmenuDescriptions
mflr r4
li r5, OPTION_ROOMS_IDX
li r6, 3
bl FN_PeppyEnterSubmenu
b FN_OnlineSubmenuThink_INPUT_HANDLERS_END

FN_OnlineSubmenuThink_B_LEAVE_ONLINE:
li	r3, 0
branchl r12, SFX_Menu_CommonSound
stb	r30, 0x0011 (r29)
li	r3, 5
li	r0, 1
sth	r3, -0x4AD8 (r13)
li	r3, 3
lbz	r4, 0 (r29)
stb	r4, 0x0001 (r29)
stb	r0, 0 (r29)
li r0, 2
sth	r0, 0x0002 (r29)
branchl r12, 0x8022B3A0
branchl r12, 0x80390CD4
lwz	r3, -0x3E84 (r13)
branchl r12, 0x80390228
lis	r3, 0x803F
subi	r3, r3, 18768
lwz	r28, 0x0024 (r3)
cmplwi	r28, 0
beq-	 FN_OnlineSubmenuThink_INPUT_HANDLERS_END
li	r3, 0
li	r4, 1
li	r5, 128
branchl r12, 0x803901F0
addi	r4, r28, 0
li	r5, 0
branchl r12, 0x8038FD54
lwz	r4, -0x3E64 (r13)
lbz	r0, 0x000D (r3)
rlwimi	r0, r4, 4, 26, 27
stb	r0, 0x000D (r3)
b	FN_OnlineSubmenuThink_INPUT_HANDLERS_END

FN_OnlineSubmenuThink_B_PRESS_HANDLER_END:

rlwinm.	r0, r3, 0, 31, 31
beq- FN_OnlineSubmenuThink_STICK_UP_HANDLER_END
################################################################################
# Stick Up Handler
################################################################################
FN_OnlineSubmenuThink_STICK_UP_HANDLER:
li r3, 2
branchl r12, SFX_Menu_CommonSound
# Wrap on the count the menu is actually drawing - the Rooms list is shorter
# than the mode list, so this can no longer be a constant
load r31, 0x803eb750
lbz r31, 0xC(r31)
subi r31, r31, 1
addi r28, r29, 2
FN_OnlineSubmenuThink_STICK_UP_INDEX_ADJUST_START:
lhz r3, 0(r28) # Load current index
cmplwi r3, 0
beq- FN_OnlineSubmenuThink_WRAP_TO_BOTTOM
subi r0, r3, 1
sth r0, 0(r28)
b FN_OnlineSubmenuThink_STICK_UP_INDEX_ADJUST_COMPLETE
FN_OnlineSubmenuThink_WRAP_TO_BOTTOM:
sth r31, 0(r28)
FN_OnlineSubmenuThink_STICK_UP_INDEX_ADJUST_COMPLETE:
li r3, 0x8
lhz r4, 0(r28)
branchl r12, 0x80229938 # MainMenu_CheckIfOptionIsUnlocked
cmpwi r3, 0
beq FN_OnlineSubmenuThink_STICK_UP_INDEX_ADJUST_START
b	FN_OnlineSubmenuThink_INPUT_HANDLERS_END

FN_OnlineSubmenuThink_STICK_UP_HANDLER_END:

rlwinm.	r0, r3, 0, 30, 30
beq- FN_OnlineSubmenuThink_STICK_DOWN_HANDLER_END
################################################################################
# Stick Down Handler
################################################################################
FN_OnlineSubmenuThink_STICK_DOWN_HANDLER:
li r3, 2
branchl r12, SFX_Menu_CommonSound
# Play MELEE sfx
load r31, 0x803eb750
lbz r31, 0xC(r31)
subi r31, r31, 1
addi r28, r29, 2
FN_OnlineSubmenuThink_STICK_DOWN_INDEX_ADJUST_START:
lhz r3, 0(r28) # Load current index
cmplw r3, r31 # Check if at bottom
beq- FN_OnlineSubmenuThink_WRAP_TO_TOP
addi r0, r3, 1
sth r0, 0(r28)
b FN_OnlineSubmenuThink_STICK_DOWN_INDEX_ADJUST_COMPLETE
FN_OnlineSubmenuThink_WRAP_TO_TOP:
sth r30, 0(r28)
FN_OnlineSubmenuThink_STICK_DOWN_INDEX_ADJUST_COMPLETE:
li r3, 0x8
lhz r4, 0(r28)
branchl r12, 0x80229938 # MainMenu_CheckIfOptionIsUnlocked
cmpwi r3, 0
beq FN_OnlineSubmenuThink_STICK_DOWN_INDEX_ADJUST_START
b	FN_OnlineSubmenuThink_INPUT_HANDLERS_END

FN_OnlineSubmenuThink_STICK_DOWN_HANDLER_END:
FN_OnlineSubmenuThink_INPUT_HANDLERS_END:

################################################################################
# Skip title menu User text updates. This hides the "User" label and username
# on main menu while preserving user display behavior in other scenes.
################################################################################

################################################################################
# Peppy: name the Rooms row
################################################################################
# The row labels are pre-rendered images and there are only eight of them, so
# the ninth row borrows the eighth and reads "Update". Nothing overrides a
# single row, so the name is drawn over it with Slippi's own text machinery.
#
# It lives here, in the submenu's own think, for three reasons: the scene is
# fully loaded by now (creating a text struct at scene prep writes through a
# garbage pointer), this runs every frame so the colours can follow the row's
# selected state, and this same frame is the one in which a B press has already
# written the menu we are leaving to - which is when the label is taken down,
# so it cannot bleed onto the 1-P menu's rows.
.set REG_PL_DATA, 22
.set REG_PL_TEXT, 23
.set REG_PL_WORD_COLOR, 24
.set REG_PL_MASK_COLOR, 21

bl PEPPY_LABEL_DATA
mflr REG_PL_DATA
lwz REG_PL_TEXT, PLD_TEXT_PTR(REG_PL_DATA)

# Still on the online submenu?
lis r3, 0x804A
addi r3, r3, 0x4F0
lbz r0, 0x0(r3)
cmpwi r0, 0x8
bne FN_OnlineSubmenuThink_LABEL_TEARDOWN

# The Rooms list has its own rows; this label names the one on the mode list
lwz r0, PLD_LEVEL(REG_PL_DATA)
cmpwi r0, 0
bne FN_OnlineSubmenuThink_LABEL_TEARDOWN

# And is the row actually drawn? It is hidden when signed out or mid-update,
# and a name with no row under it would just float over the menu.
li r3, 0x8
li r4, OPTION_ROOMS_IDX
branchl r12, 0x80229938 # MainMenu_CheckIfOptionIsUnlocked
cmpwi r3, 0
bne FN_OnlineSubmenuThink_LABEL_ON_MENU

FN_OnlineSubmenuThink_LABEL_TEARDOWN:
cmpwi REG_PL_TEXT, 0
beq FN_OnlineSubmenuThink_LABELS_DONE
mr r3, REG_PL_TEXT
branchl r12, Text_RemoveText
li r3, 0
stw r3, PLD_TEXT_PTR(REG_PL_DATA)
b FN_OnlineSubmenuThink_LABELS_DONE

FN_OnlineSubmenuThink_LABEL_ON_MENU:
cmpwi REG_PL_TEXT, 0
bne FN_OnlineSubmenuThink_LABEL_COLOR

li r3, 0
li r4, 0
branchl r12, Text_CreateStruct
mr REG_PL_TEXT, r3
stw REG_PL_TEXT, PLD_TEXT_PTR(REG_PL_DATA)

# Close kerning, centred - the row words are centred on their plate
li r4, 0x1
stb r4, 0x49(REG_PL_TEXT)
stb r4, 0x4A(REG_PL_TEXT)

lfs f1, PLD_Z(REG_PL_DATA)
stfs f1, 0x8(REG_PL_TEXT)
lfs f1, PLD_SCALE(REG_PL_DATA)
stfs f1, 0x24(REG_PL_TEXT)
stfs f1, 0x28(REG_PL_TEXT)

# Subtexts 0..4 are the cover, then the word goes on top of them
.set REG_PL_OFS, 25
.set REG_PL_COUNT, 26

addi REG_PL_OFS, REG_PL_DATA, PLD_MASK_OFS
li REG_PL_COUNT, 0

FN_OnlineSubmenuThink_LABEL_MASK_LOOP:
lfs f1, 0x0(REG_PL_OFS)
lfs f2, 0x4(REG_PL_OFS)
mr r3, REG_PL_TEXT
addi r4, REG_PL_DATA, PLD_MASK_STR
branchl r12, Text_InitializeSubtext
mr REG_PL_WORD_COLOR, r3 # borrowed as scratch for the subtext index
lfs f1, PLD_SIZE(REG_PL_DATA)
fmr f2, f1
mr r3, REG_PL_TEXT
mr r4, REG_PL_WORD_COLOR
branchl r12, Text_UpdateSubtextSize
addi REG_PL_OFS, REG_PL_OFS, 8
addi REG_PL_COUNT, REG_PL_COUNT, 1
cmpwi REG_PL_COUNT, PLD_MASK_COUNT
blt FN_OnlineSubmenuThink_LABEL_MASK_LOOP

# The patch over the p's stem
lfs f1, PLD_PATCH_X(REG_PL_DATA)
lfs f2, PLD_PATCH_Y(REG_PL_DATA)
mr r3, REG_PL_TEXT
addi r4, REG_PL_DATA, PLD_PATCH_STR
branchl r12, Text_InitializeSubtext
mr REG_PL_WORD_COLOR, r3
lfs f1, PLD_PATCH_W(REG_PL_DATA)
lfs f2, PLD_SIZE(REG_PL_DATA)
mr r3, REG_PL_TEXT
mr r4, REG_PL_WORD_COLOR
branchl r12, Text_UpdateSubtextSize

# And the word itself, on top of the cover
lfs f1, PLD_X(REG_PL_DATA)
lfs f2, PLD_Y(REG_PL_DATA)
mr r3, REG_PL_TEXT
addi r4, REG_PL_DATA, PLD_STR
branchl r12, Text_InitializeSubtext
mr REG_PL_WORD_COLOR, r3
lfs f1, PLD_SIZE(REG_PL_DATA)
fmr f2, f1
mr r3, REG_PL_TEXT
mr r4, REG_PL_WORD_COLOR
branchl r12, Text_UpdateSubtextSize

FN_OnlineSubmenuThink_LABEL_COLOR:
# Follow the row: orange on a dark plate normally, black on yellow when it is
# the selected row - the same inversion every other row does.
lis r3, 0x804A
addi r3, r3, 0x4F0
lhz r0, 0x2(r3)
cmpwi r0, OPTION_ROOMS_IDX
beq FN_OnlineSubmenuThink_LABEL_SELECTED

addi r5, REG_PL_DATA, PLD_COL_PLATE_IDLE
addi REG_PL_WORD_COLOR, REG_PL_DATA, PLD_COL_WORD_IDLE
b FN_OnlineSubmenuThink_LABEL_PAINT

FN_OnlineSubmenuThink_LABEL_SELECTED:
addi r5, REG_PL_DATA, PLD_COL_PLATE_PICKED
addi REG_PL_WORD_COLOR, REG_PL_DATA, PLD_COL_WORD_PICKED

FN_OnlineSubmenuThink_LABEL_PAINT:
# Colour pointers live in saved registers - a call is free to trample the
# volatile ones.
mr REG_PL_MASK_COLOR, r5
li REG_PL_COUNT, 0

FN_OnlineSubmenuThink_LABEL_PAINT_LOOP:
mr r3, REG_PL_TEXT
mr r4, REG_PL_COUNT
mr r5, REG_PL_MASK_COLOR
branchl r12, Text_ChangeTextColor
addi REG_PL_COUNT, REG_PL_COUNT, 1
cmpwi REG_PL_COUNT, PLD_COVER_COUNT
blt FN_OnlineSubmenuThink_LABEL_PAINT_LOOP

mr r3, REG_PL_TEXT
li r4, PLD_COVER_COUNT
mr r5, REG_PL_WORD_COLOR
branchl r12, Text_ChangeTextColor

FN_OnlineSubmenuThink_LABELS_DONE:
bl FN_PeppyRoomsLabels

FN_OnlineSubmenuThink_EXIT:
restore BKP_DEFAULT_FREE_SPACE_SIZE, NUM_FREG, NUM_GPREG

################################################################################
# Data: OnlineSubmenuOptions
# ------------------------------------------------------------------------------
# Description: These are the new submenu table values for menu
# 0x8 (Originally Smash Dojo). The ptr to the think function comes at the
# end and will be written separately
################################################################################
Data_OnlineSubmenuOptions:
blrl

.long 0x803eb57c # Ptr to preview animation frame values (stolen from reg match)
.float 140 # Frame index pointing at the option text images
.long 0x803eb684 # Ptr to description text. Will be overwritten
.byte 0x09 # Number of options
.align 2

PEPPY_LABEL_DATA:
blrl
# Measured off the screen, not guessed. Three calibration marks drawn at known
# canvas coordinates put the mapping at
#     screen_x = 961 + 2.30 * canvas_x      screen_y = 583 + 2.52 * canvas_y
# on a 1920x1080 render; the row's word is centred at (673, 774) and stands
# 49px tall. Note a glyph draws ABOVE its anchor by about 78 * size pixels.
.set PLD_TEXT_PTR, 0
.long 0
# 0 = the mode list, 1 = the Rooms list. The Rooms list is not a second menu -
# it is this one, redrawn with a different option table.
.set PLD_LEVEL, PLD_TEXT_PTR+4
.long 0
.set PLD_X, PLD_LEVEL+4
.float -124.55
.set PLD_Y, PLD_X+4
.float 85.06
.set PLD_SIZE, PLD_Y+4
.float 0.80
# The mask is the borrowed word itself, drawn in the plate's colour at the same
# size and place. The row artwork and Slippi's text use the same font, so it
# covers the ghost glyph for glyph - which nothing generic can do: a larger copy
# of "Rooms" leaves it showing between the letters, stretching that copy opens
# the gaps further, and a single stretched period (the one solid glyph in the
# font) kills the whole text object.
#
# Seven copies dilate the cover: the centre, straight up and down, and the four
# diagonals. The artwork's letters sit a couple of pixels higher than the font
# draws them and carry an outline outside the glyph, so the cover has to reach
# further up (6px) than down (4px) and out to 6px either side. Diagonals alone
# leave a gap directly above each stem - which is exactly where the last specks
# of "Update" were showing. The plate under here is flat (#00000A to #070712),
# so none of this can be seen.
.set PLD_MASK_OFS, PLD_SIZE+4
.float -124.55
.float 85.06
.float -124.55
.float 82.68
.float -124.55
.float 86.65
.float -127.16
.float 82.68
.float -121.94
.float 82.68
.float -127.16
.float 86.65
.float -121.94
.float 86.65
.set PLD_MASK_COUNT, 7
# One spot the cover cannot reach: the artwork draws "Update" with a FULL-HEIGHT
# stem on the p, and the runtime font's p is an ordinary lowercase, so its stem
# starts at x-height and there is simply no ink up there to dilate. The two
# fonts agree on every other glyph. Patched with a single stretched l, wide
# enough to bury the stem (screen x 604-617) and starting just below the plate's
# top edge, which begins at y 767 - going higher would paint on the border.
.set PLD_PATCH_X, PLD_MASK_OFS+56
.float -151.72
.set PLD_PATCH_Y, PLD_PATCH_X+4
.float 83.07
.set PLD_PATCH_W, PLD_PATCH_Y+4
.float 1.70
.set PLD_COVER_COUNT, PLD_MASK_COUNT+1
.set PLD_Z, PLD_PATCH_W+4
.float 17
.set PLD_SCALE, PLD_Z+4
.float 0.06
# Sampled from the menu itself
.set PLD_COL_WORD_IDLE, PLD_SCALE+4
.long 0xCA9732FF
.set PLD_COL_PLATE_IDLE, PLD_COL_WORD_IDLE+4
.long 0x04040EFF
.set PLD_COL_WORD_PICKED, PLD_COL_PLATE_IDLE+4
.long 0x000000FF
.set PLD_COL_PLATE_PICKED, PLD_COL_WORD_PICKED+4
.long 0xFFCB00FF
.set PLD_STR, PLD_COL_PLATE_PICKED+4
.string "Rooms"
.set PLD_MASK_STR, PLD_STR+6
.string "Update"
.set PLD_PATCH_STR, PLD_MASK_STR+7
.string "l"
.align 2

################################################################################
# Data: the Rooms list's rows
################################################################################
# Positions measured off the screen, same mapping the Rooms label uses:
#   screen_x = 959.5 + 2.30 * canvas_x    cap top = 559.7 + 2.52 * canvas_y
# The five rows sit at screen centres 807, 700, 611, 678, 634 with cap tops 309,
# 413, 528, 635 and 746 - the fan layout means they are not in a straight line.
#
# Size is smaller than the mode list's rows because "Crew Battles" has to fit the
# plate: our font runs wider per character than the artwork does, and at the
# mode list's size that word would be half again wider than the row it sits on.
PEPPY_ROWS_DATA:
blrl
PRW_BASE:
.set PRW_STRUCTS, . - PRW_BASE
.long 0
.long 0
.long 0
.long 0
.long 0
.set PRW_SIZE, . - PRW_BASE
.float 0.58
.set PRW_Z, . - PRW_BASE
.float 17
.set PRW_SCALE, . - PRW_BASE
.float 0.06
# Sampled from the menu itself
.set PRW_COL_WORD_IDLE, . - PRW_BASE
.long 0xCA9732FF
.set PRW_COL_PLATE_IDLE, . - PRW_BASE
.long 0x04040EFF
.set PRW_COL_WORD_PICKED, . - PRW_BASE
.long 0x000000FF
.set PRW_COL_PLATE_PICKED, . - PRW_BASE
.long 0xFFCB00FF
# Seven offsets that dilate the cover: centre, straight up and down, and the
# four diagonals. Same shape that buried "Update" on the Rooms row.
.set PRW_COVERS, . - PRW_BASE
.float 0.00
.float 0.00
.float 0.00
.float -2.38
.float 0.00
.float 1.59
.float -2.61
.float -2.38
.float 2.61
.float -2.38
.float -2.61
.float 1.59
.float 2.61
.float 1.59
.set PRW_COVER_COUNT, 7
# Our words, and the artwork word each one has to bury
.set PRW_S_SINGLES, . - PRW_BASE
.string "Singles"
.set PRW_S_DOUBLES, . - PRW_BASE
.string "Doubles"
.set PRW_S_FFA, . - PRW_BASE
.string "FFA"
.set PRW_S_CREW, . - PRW_BASE
.string "Crew Battles"
.set PRW_S_TOURNEY, . - PRW_BASE
.string "Tournaments"
.set PRW_S_RANKED, . - PRW_BASE
.string "Ranked"
.set PRW_S_UNRANKED, . - PRW_BASE
.string "Unranked"
.set PRW_S_DIRECT, . - PRW_BASE
.string "Direct"
.set PRW_S_TEAMS, . - PRW_BASE
.string "Teams"
.set PRW_S_PARTY, . - PRW_BASE
.string "Party"
.align 2
# x, y, our word, the word underneath
.set PRW_ROWS, . - PRW_BASE
.set PRW_ROW_COUNT, 5
.float -66.29
.float -99.47
.long PRW_S_SINGLES
.long PRW_S_RANKED
.float -112.59
.float -58.20
.long PRW_S_DOUBLES
.long PRW_S_UNRANKED
.float -151.29
.float -12.56
.long PRW_S_FFA
.long PRW_S_DIRECT
.float -122.37
.float 29.90
.long PRW_S_CREW
.long PRW_S_TEAMS
.float -141.29
.float 73.94
.long PRW_S_TOURNEY
.long PRW_S_PARTY

################################################################################
# Data: RoomsSubmenuOptions
# ------------------------------------------------------------------------------
# Description: The second level, shown after picking Rooms. Same artwork base as
# the mode list on purpose - the row labels are pre-rendered images and covering
# one means drawing its own word over it, so reusing a base whose words are
# already known (Ranked, Unranked, Direct, Teams, Party) beats discovering five
# new ones.
################################################################################
Data_RoomsSubmenuOptions:
blrl

.long 0x803eb57c # Ptr to preview animation frame values
.float 140 # Frame index pointing at the option text images
.long 0x803eb684 # Ptr to description text. Will be overwritten
.byte 0x05 # Singles, Doubles, FFA, Crew Battles, Tournaments
.align 2

Data_RoomsSubmenuDescriptions:
blrl
.short 0x0645 # Singles
.short 0x0646 # Doubles
.short 0x0647 # FFA
.short 0x064B # Crew Battles
.short 0x064C # Tournaments
.align 2

Data_OnlineSubmenuDescriptions:
blrl
.short 0x0645 # Ranked
.short 0x0646 # Unranked
.short 0x0647 # Direct
.short 0x064B # Teams
.short 0x064C # Party
.short 0x0648 # Log-in
.short 0x0649 # Log-out
.short 0x064A # Update
.short 0x064C # Rooms - borrowing Party's description as a placeholder
.align 2

FN_CREATE_DIALOG:
backup BKP_DEFAULT_FREE_SPACE_SIZE, 2

# load jobjects in memory
lwz r3, archiveDataBuffer(r13)
load r4, JOBJ_DESC_DLG
branchl r12, HSD_ArchiveGetPublicAddress # 0x80380358
mr REG_JOBJ_DESC_ADDR, r3

lwz r3, archiveDataBuffer(r13)
load r4, JOBJ_DESC_DLG_ANIM_JOINT
branchl r12, HSD_ArchiveGetPublicAddress # 0x80380358
mr REG_JOBJ_DESC_ANIM_JOINT_ADDR, r3

lwz r3, archiveDataBuffer(r13)
load r4, JOBJ_DESC_DLG_MAT_JOINT
branchl r12, HSD_ArchiveGetPublicAddress # 0x80380358
mr REG_JOBJ_DESC_MAT_JOINT_ADDR, r3

lwz r3, archiveDataBuffer(r13)
load r4, JOBJ_DESC_DLG_SHAPE_JOINT
branchl r12, HSD_ArchiveGetPublicAddress # 0x80380358
mr REG_JOBJ_DESC_SHAPE_JOINT_ADDR, r3


# INIT PROPERTIES
bl TEXT_PROPERTIES
mflr REG_TEXT_PROPERTIES

lfs REG_F_0, TPO_FLOAT_0(REG_TEXT_PROPERTIES)
lfs REG_F_1, TPO_FLOAT_1(REG_TEXT_PROPERTIES)

# Create User Data:
# We will be adding a very small buffer to be able to track the selected option
# Get Memory Buffer for Chat Window Data Table
li REG_DLG_BUFFER_SIZE, REG_DLG_BUFFER_SIZE # buffer size

mr r3, REG_DLG_BUFFER_SIZE # Buffer Size
branchl r12, HSD_MemAlloc
mr REG_DLG_BUFFER_ADDRESS, r3 # save result address into REG_DLG_BUFFER_ADDRESS

# Zero out CSS data table
mr r4, REG_DLG_BUFFER_SIZE # buffer size
branchl r12, Zero_AreaLength

# 0: means no is selected, 1: yes is selected
li r3, DLG_OPTION_NO # Initial Selected Option
stb r3, DLG_DT_SELECTED_OPTION(REG_DLG_BUFFER_ADDRESS)

# save submenu gobj
mr r3, REG_SM_GOBJ
stw r3, DLG_DT_SUBMENU_GOBJ_ADDR(REG_DLG_BUFFER_ADDRESS)

# Save Pointer to User data To keep track of it
stw REG_DLG_BUFFER_ADDRESS, MENU_DLG_USER_DATA_OFFSET(REG_SM_GOBJ)


# Create GObj
li r3, 6 # GObj Type (6 is menu type?)
li r4, 7 # On-Pause Function (dont run on pause)
li r5, 0x80 # some type of priority
branchl r12, GObj_Create
mr REG_DLG_GOBJ, r3 # 0x803901f0 store result

# Create JOBJ
mr r3, REG_JOBJ_DESC_ADDR
branchl r12, JObj_LoadJoint # 0x80370E44 # (this func only uses r3)
mr REG_DLG_JOBJ, r3 # store result

# Add JOBJ to GObj
mr r3,REG_DLG_GOBJ
li	r4, 3
mr r5,REG_DLG_JOBJ
branchl r12, GObj_AddToObj # 0x80390A70


# Hide Interrogation Mark
mr r3,REG_DLG_JOBJ # jobj
addi r4, sp, JOBJ_CHILD_OFFSET # pointer where to store return value
li r5, 10 # index
li r6, -1
branchl r12, JObj_GetJObjChild

# Set invisible flag on JObj
lwz r3, JOBJ_CHILD_OFFSET(sp) # get return obj
li r4, 0x10
branchl r12, JObj_SetFlagsAll # 0x80371D9c

# Hide Progress Bar
mr r3,REG_DLG_JOBJ # jobj
addi r4, sp, JOBJ_CHILD_OFFSET # pointer where to store return value
li r5, 11 # index
li r6, -1
branchl r12, JObj_GetJObjChild

# Set invisible flag on JObj
lwz r3, JOBJ_CHILD_OFFSET(sp) # get return obj
li r4, 0x10
branchl r12, JObj_SetFlagsAll # 0x80371D9c
# Hide Progress Bar!


# Add Animations to JObj
mr r3, REG_DLG_JOBJ
mr r4, REG_JOBJ_DESC_ANIM_JOINT_ADDR
mr r5, REG_JOBJ_DESC_MAT_JOINT_ADDR
mr r6, REG_JOBJ_DESC_SHAPE_JOINT_ADDR
branchl r12, JObj_AddAnimAll #, 0x8036FB5C # (jobj,an_joint,mat_joint,sh_joint)

mr r3, REG_DLG_JOBJ
fmr f1, REG_F_0
branchl r12, JObj_ReqAnimAll# (jobj, frames)

# Configure "Yes" Button
mr r3,REG_DLG_JOBJ # jobj
addi r4, sp, JOBJ_CHILD_OFFSET # pointer where to store return value
li r5, 6 # index
li r6, -1
branchl r12, JObj_GetJObjChild

# Move to the Left
lwz r3, JOBJ_CHILD_OFFSET(sp) # jobj child
load r4, 0xC0600000
stw r4, 0x38(r3)
# Configure "Yes" Button!


# Configure "No" Button
mr r3,REG_DLG_JOBJ # jobj
addi r4, sp, JOBJ_CHILD_OFFSET # pointer where to store return value
li r5, 7 # index
li r6, -1
branchl r12, JObj_GetJObjChild

# Move to the Right
lwz r3, JOBJ_CHILD_OFFSET(sp) # jobj child
load r4, 0x405c0000
stw r4, 0x38(r3)
# Configure "No" Button!

# AddGXLink
mr r3, REG_DLG_GOBJ
load r4, 0x80391070 # GX Callback func to use
li r5, 6 # Assigns the gx_link index
li r6, 0x80 # sets the priority
branchl r12, GObj_SetupGXLink # 0x8039069c

# Add User Data to GOBJ ( Our buffer )
mr r3, REG_DLG_GOBJ
li r4, 4 # user data kind
load r5, HSD_Free # destructor
mr r6, REG_DLG_BUFFER_ADDRESS # memory pointer of allocated buffer above
branchl r12, GObj_AddUserData # 0x80390b68;

#Create Proc
mr r3, REG_DLG_GOBJ
bl FN_LogoutDialogThink
mflr r4 # Function
li r5, 15 # Priority
branchl	r12, GObj_AddProc

restore BKP_DEFAULT_FREE_SPACE_SIZE, 2
blr


################################################################################
# Routine: FN_LogoutDialogThink
# ------------------------------------------------------------------------------
# Description: Handles Confirm Dialog when pressing logout
################################################################################
FN_LogoutDialogThink: #801978fc
blrl
backup BKP_DEFAULT_FREE_SPACE_SIZE, 2

# INIT PROPERTIES
bl TEXT_PROPERTIES
mflr REG_TEXT_PROPERTIES

lfs REG_F_0, TPO_FLOAT_0(REG_TEXT_PROPERTIES) # load 0.0
lfs REG_F_1, TPO_FLOAT_1(REG_TEXT_PROPERTIES) # load 1.0

mr REG_DLG_GOBJ, r3
lwz REG_DLG_JOBJ, DLG_JOBJ_OFFSET(REG_DLG_GOBJ) # Get Jobj
lwz REG_DLG_USER_DATA_ADDR, DLG_USER_DATA_OFFSET(REG_DLG_GOBJ) # get address of data buffer

lbz REG_DLG_SELECTED_OPTION, DLG_DT_SELECTED_OPTION(REG_DLG_USER_DATA_ADDR) # Get selected option from bufffer
lwz REG_DLG_MENU_GOBJ_ADDR, DLG_DT_SUBMENU_GOBJ_ADDR(REG_DLG_USER_DATA_ADDR) # get address of submenu's gboj
lwz REG_DLG_TEXT_STRUCT_ADDR, DLG_DT_TEXT_STRUCT_ADDR(REG_DLG_USER_DATA_ADDR) # get address of text struct

# Always Animate the dialog
mr r3, REG_DLG_JOBJ
branchl r12, JObj_AnimAll

# Only Initialize Text if needed
cmpwi REG_DLG_TEXT_STRUCT_ADDR, 0
bne FN_LogoutDialogThink_ConfigureUI

FN_LogoutDialogThink_InitText:

li r3, 0x13F #  Text ID
li r4, 0 # Use Slippi ID = false
li r5, 2 # use premade text fn
li r6, 1 # gx_link?
lfs f1, TPO_DLG_LABEL_X_POS(REG_TEXT_PROPERTIES)
lfs f2, TPO_DLG_LABEL_Y_POS(REG_TEXT_PROPERTIES)
lfs f3, TPO_DLG_LABEL_Z_POS(REG_TEXT_PROPERTIES)
lfs f4, TPO_DLG_LABEL_CANVAS_SCALE(REG_TEXT_PROPERTIES)
branchl r12, FG_CreateSubtext
stw r3, DLG_DT_TEXT_STRUCT_ADDR(REG_DLG_USER_DATA_ADDR) # Save Text Struct Address

# exit to next frame when dialog is first initialized
b FN_LogoutDialogThink_Exit

FN_LogoutDialogThink_ConfigureUI:

# Configure "No" Button
mr r3,REG_DLG_JOBJ # jobj
addi r4, sp, JOBJ_CHILD_OFFSET # pointer where to store return value
li r5, 7 # index
li r6, -1
branchl r12, JObj_GetJObjChild

# Set Animation Frame (frame 0 is turned off, frame 1+ is on)
fmr f1, REG_F_0 # Turn off
cmpwi REG_DLG_SELECTED_OPTION, DLG_OPTION_NO
bne FN_LogoutDialogThink_ConfigureUI_Animate_No
fmr f1, REG_F_1 # Turn on

FN_LogoutDialogThink_ConfigureUI_Animate_No:
lwz r3, JOBJ_CHILD_OFFSET(sp) # jobj child
branchl r12, JObj_ReqAnimAll# (jobj, frames)

lwz r3, JOBJ_CHILD_OFFSET(sp) # jobj child
branchl r12, JObj_AnimAll
# Configure "No" Button!

# Configure "Yes" Button
mr r3,REG_DLG_JOBJ # jobj
addi r4, sp, JOBJ_CHILD_OFFSET # pointer where to store return value
li r5, 6 # index
li r6, -1
branchl r12, JObj_GetJObjChild

# Set Animation Frame (frame 0 is turned off, frame 1+ is on)
fmr f1, REG_F_0 # Turn off
cmpwi REG_DLG_SELECTED_OPTION, DLG_OPTION_YES
bne FN_LogoutDialogThink_ConfigureUI_Animate_Yes
fmr f1, REG_F_1 # Turn on

FN_LogoutDialogThink_ConfigureUI_Animate_Yes: # 801979b4
lwz r3, JOBJ_CHILD_OFFSET(sp) # jobj child
branchl r12, JObj_ReqAnimAll# (jobj, frames)

lwz r3, JOBJ_CHILD_OFFSET(sp) # jobj child
branchl r12, JObj_AnimAll
# Configure "Yes" Button!

FN_LogoutDialogThink_CheckInputs:
# Check input and switch option if left or right
li r14, 0
FN_LogoutDialogThink_CheckInputs_AfterPort:
mr r3, r14
branchl r12, Inputs_GetPlayerInstantInputs 

# Exit function if no input # 0x8019796c
cmpwi r3, PAD_LEFT
beq FN_LogoutDialogThink_SwitchOption
cmpwi r3, PAD_RIGHT
beq FN_LogoutDialogThink_SwitchOption
cmpwi r3, PAD_A
beq FN_LogoutDialogThink_DoLogout
cmpwi r3, PAD_B
beq FN_LogoutDialogThink_CloseDialog

addi r14, r14, 1
cmpwi r14, 4 # check all 4 ports
blt FN_LogoutDialogThink_CheckInputs_AfterPort
b FN_LogoutDialogThink_Exit


FN_LogoutDialogThink_SwitchOption:
li	r3, 2
branchl r12, SFX_Menu_CommonSound

xori r3, REG_DLG_SELECTED_OPTION, 0x1 # alternate selected option
stb r3, DLG_DT_SELECTED_OPTION(REG_DLG_USER_DATA_ADDR) # Store to proper user data offset

b FN_LogoutDialogThink_Exit

FN_LogoutDialogThink_DoLogout:
# only logout if selected option is YES
cmpwi REG_DLG_SELECTED_OPTION, DLG_OPTION_YES
bne FN_LogoutDialogThink_CloseDialog


li r4, CONST_SlippiCmdLogOut
# Use the scene buffer cause it's not being used for anything
lwz r3, OFST_R13_SB_ADDR(r13)
stb r4, 0(r3) # Store command byte
li r4, 1
li r5, CONST_ExiWrite
branchl r12, FN_EXITransferBuffer

b FN_LogoutDialogThink_CloseDialog

FN_LogoutDialogThink_CloseDialog:
li	r3, 0
branchl r12, SFX_Menu_CommonSound

# destroy gobj
mr r3, REG_DLG_GOBJ
branchl r12, GObj_Destroy

# Delete Text
mr r3, REG_DLG_TEXT_STRUCT_ADDR
branchl r12, Text_RemoveText

# Clear Pointer to this gobj's User data to restore input on submenu
load r3, 00000000
stw r3, MENU_DLG_USER_DATA_OFFSET(REG_DLG_MENU_GOBJ_ADDR)

b FN_LogoutDialogThink_Exit

FN_LogoutDialogThink_Exit:


restore BKP_DEFAULT_FREE_SPACE_SIZE, 2
blr

################################################################################
# Properties
################################################################################
TEXT_PROPERTIES:
blrl
# Label properties
.set TPO_DLG_LABEL_X_POS, 0
.float -5.5
.set TPO_DLG_LABEL_Y_POS, TPO_DLG_LABEL_X_POS+4
.float -2.8
.set TPO_DLG_LABEL_Z_POS,  TPO_DLG_LABEL_Y_POS+4
.float 23
.set TPO_DLG_LABEL_CANVAS_SCALE, TPO_DLG_LABEL_Z_POS+4
.float 0.045

.set TPO_FLOAT_0, TPO_DLG_LABEL_CANVAS_SCALE+4
.float 0.0
.set TPO_FLOAT_1, TPO_FLOAT_0+4
.float 1.0

.align 2

EXIT:
lis r3, 0x804A
