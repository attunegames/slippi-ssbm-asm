################################################################################
# Address: 0x80263258 # CSS_LoadButtonInputs runs once per frame
################################################################################

.include "Common/Common.s"
.include "Online/Online.s"

.set REG_ZERO, 28
.set REG_INPUTS, 27
.set REG_MSRB_ADDR, 26
.set REG_TXB_ADDR, 25
.set REG_CSSDT_ADDR, 24
.set REG_PB_ANSWER, 23

# Peppy: handing over to Slippi's replay playback.
.set CONST_PeppyCmdReplayWaiting, 0xCA
.set SCENE_MAJOR_DEBUG_MELEE, 0xE
.set MINOR_PLAYBACK_ENTRY, 0x3
.set PB_SCENEPREP_SLOT, 0x801b16a8
.set PB_SCENEPREP_DEBUGMENU, 0x801b09c0
.set MenuController_WriteToPendingMajor_1to_0xC, 0x801A42F8
.set Scene_ExitMinor, 0x801A4B60

.set DISCONNECT_HOLD_DELAY, 0x30 # 3 seconds

# Deal with replaced codeline
beq+ START
branch r12, 0x80263334

START:
backup

# Ensure that this is an online CSS
getMinorMajor r3
cmpwi r3, SCENE_ONLINE_CSS
bne EXIT # If not online CSS, continue as normal

################################################################################
# Init
################################################################################
mr REG_INPUTS, r7
loadwz REG_CSSDT_ADDR, CSSDT_BUF_ADDR
lwz REG_MSRB_ADDR, CSSDT_MSRB_ADDR(REG_CSSDT_ADDR) # Load where buf is stored
li REG_ZERO, 0 # set to zero just in case :)

################################################################################
# Peppy: hand over to Slippi's replay playback if a replay is queued
################################################################################
# This used to live at the end of SceneLoad_MainMenu and could never work there.
# Melee's main menu decides its own next major, so the handover was overridden
# every time - the write landed (pending-major 0e, exit flag 1) and the game
# still came up on major 18. Worse, Scene_ExitMinor destroys the scheduling GObj
# in the same frame, so nothing survived to say it again.
#
# Here we are inside the online major, which is Peppy's own. The pair below is
# the same one peppy_room_exit_room uses to leave that major for the menu, and
# that is a feature known to work. This is also where the trigger belongs: you
# start spectating because you are queued, not because you passed a menu.
#
# CONST_PeppyCmdReplayWaiting is a peek - deliberately not 0x88, which loads the
# game and marks it played, leaving SceneThink_Playback's own poll waiting
# forever on a replay already loaded behind it.
li r3, 1
branchl r12, HSD_MemAlloc
mr REG_TXB_ADDR, r3

li r3, CONST_PeppyCmdReplayWaiting
stb r3, 0(REG_TXB_ADDR)

mr r3, REG_TXB_ADDR
li r4, 1
li r5, CONST_ExiWrite
branchl r12, FN_EXITransferBuffer

mr r3, REG_TXB_ADDR
li r4, 1
li r5, CONST_ExiRead
branchl r12, FN_EXITransferBuffer

# Keep the answer somewhere HSD_Free cannot reach - it is a call, so it lands on
# the condition register.
lbz REG_PB_ANSWER, 0(REG_TXB_ADDR)
mr r3, REG_TXB_ADDR
branchl r12, HSD_Free

cmpwi REG_PB_ANSWER, 1
bne PEPPY_NO_REPLAY_ON_CSS

logf LOG_LEVEL_WARN, "[Peppy] replay queued - leaving the online major for playback"

# Slippi's ScenePrep patch does not survive to here: 0x801b16a8 is in Melee's
# scene-code region, which is reloaded as scenes come and go, so their gecko
# write is long gone. Same address, same value, applied late enough to last.
load r3, PB_SCENEPREP_SLOT
load r4, PB_SCENEPREP_DEBUGMENU
stw r4, 0(r3)
load r3, PB_SCENEPREP_SLOT
li r4, 4
branchl r12, TRK_flush_cache

# Ask for the playback ENTRY minor, not zero.
#
# Zero landed us straight on minor 1, which is playback IN-GAME: FetchGameFrame
# started asking Dolphin for frames of a replay nobody had loaded yet, and every
# read came back "DMARead: Empty". Minor 3 is the entry screen, where
# SceneThink_Playback polls for the replay, loads it, and only then starts the
# match. Slippi's boot callback is what normally selects it; this asks directly.
#
# pending_minor is one-based - zero means "carry on as normal" - so minor 3 is 4.
load r4, 0x80479D30
li r3, MINOR_PLAYBACK_ENTRY + 1
stb r3, 0x5(r4)

li r3, SCENE_MAJOR_DEBUG_MELEE
branchl r12, MenuController_WriteToPendingMajor_1to_0xC
branchl r12, Scene_ExitMinor

b EXIT

PEPPY_NO_REPLAY_ON_CSS:

################################################################################
# Play sound on lock-in state 1 -> 0 transition
################################################################################
lbz r3, CSSDT_PREV_LOCK_IN_STATE(REG_CSSDT_ADDR)
lbz r4, MSRB_IS_LOCAL_PLAYER_READY(REG_MSRB_ADDR)
stb r4, CSSDT_PREV_LOCK_IN_STATE(REG_CSSDT_ADDR) # Change previous value
cmpwi r3, 1
bne LOCK_IN_RESET_CHECK_END
cmpwi r4, 0
bne LOCK_IN_RESET_CHECK_END

# If we get here, we transitioned from locked-in to not locked-in, play the sound
b PLAY_BACK_SOUND_ON_RESET
LOCK_IN_RESET_CHECK_END:

################################################################################
# Handle connection state sounds
################################################################################
lbz r3, CSSDT_PREV_CONNECTED_STATE(REG_CSSDT_ADDR)
lbz r4, MSRB_CONNECTION_STATE(REG_MSRB_ADDR)
stb r4, CSSDT_PREV_CONNECTED_STATE(REG_CSSDT_ADDR) # Change previous value

################################################################################
# Play "error" sound on connection state transition ANY -> ERROR
################################################################################
cmpwi r3, MM_STATE_ERROR_ENCOUNTERED
beq ERR_STATE_CHECK_END
cmpwi r4, MM_STATE_ERROR_ENCOUNTERED
bne ERR_STATE_CHECK_END

b PLAY_ERROR_SOUND_ON_ERROR
ERR_STATE_CHECK_END:

################################################################################
# Play "back" sound on connection state transition CONNECTED -> ANY
################################################################################
# Check to see if connection was cleared
cmpwi r3, MM_STATE_CONNECTION_SUCCESS
bne CONN_RESET_CHECK_END
cmpwi r4, MM_STATE_CONNECTION_SUCCESS
beq CONN_RESET_CHECK_END # If still success, no sound

b PLAY_BACK_SOUND_ON_RESET
CONN_RESET_CHECK_END:
b SOUND_PLAY_END

PLAY_BACK_SOUND_ON_RESET:
# Play "back" sound
li	r3, 0
b PLAY_SOUND

PLAY_ERROR_SOUND_ON_ERROR:
# Play "error" sound
li	r3, 3

PLAY_SOUND:
branchl r12, SFX_Menu_CommonSound

SOUND_PLAY_END:

################################################################################
# Fork logic based on current connection state
################################################################################
lbz r3, MSRB_CONNECTION_STATE(REG_MSRB_ADDR)
cmpwi r3, MM_STATE_IDLE
ble HANDLE_IDLE
cmpwi r3, MM_STATE_OPPONENT_CONNECTING
ble HANDLE_FINDING
cmpwi r3, MM_STATE_CONNECTION_SUCCESS
beq HANDLE_CONNECTED
cmpwi r3, MM_STATE_ERROR_ENCOUNTERED
beq HANDLE_ERROR

b SKIP_START_MATCH

################################################################################
# Case 1: Handle idle case
################################################################################
HANDLE_IDLE:

# Prevent CSS Actions if chat window is opened
lbz r3, CSSDT_CHAT_WINDOW_OPENED(REG_CSSDT_ADDR)
cmpwi r3, 0
bne SKIP_START_MATCH # skip input if chat window is opened

# When idle, pressing start will start finding match
# Check if start was pressed
rlwinm.	r0, REG_INPUTS, 0, 19, 19
beq SKIP_START_MATCH # Exit if start was not pressed

# Sometimes when returning to the CSS, previously held buttons will stay held,
# including start. This prevents the start input from locking people in
# immediately... Doesn't feel like this should be necessary, and if it is,
# this doesn't feel like the right place for this logic
loadGlobalFrame r3
cmpwi r3, 0
beq SKIP_START_MATCH # Don't search on very first frame

# Initialize ISWINNER (first match)
li  r3, ISWINNER_NULL
stb r3, OFST_R13_ISWINNER (r13)
# Init CHOSESTAGE bool
li r3,  0
stb r3, OFST_R13_CHOSESTAGE (r13)

# Check if character has been selected, if not, do nothing
lbz r3, -0x49A9(r13)
cmpwi r3, 0
beq SKIP_START_MATCH

# Check which mode we are playing. direct mode should launch text entry
lbz r3, OFST_R13_ONLINE_MODE(r13)
cmpwi r3, ONLINE_MODE_RANKED
beq HANDLE_IDLE_UNRANKED
cmpwi r3, ONLINE_MODE_UNRANKED
beq HANDLE_IDLE_UNRANKED
cmpwi r3, ONLINE_MODE_ROOMS
beq HANDLE_IDLE_UNRANKED
cmpwi r3, ONLINE_MODE_PARTY
beq HANDLE_IDLE_UNRANKED
cmpwi r3, ONLINE_MODE_DIRECT
beq HANDLE_IDLE_DIRECT
cmpwi r3, ONLINE_MODE_TEAMS
beq HANDLE_IDLE_DIRECT
b 0x0

HANDLE_IDLE_UNRANKED:
li  r3, SB_RAND     # stages in unranked are always random
bl FN_LOCK_IN_AND_SEARCH # lock in and trigger matchmaking
b SKIP_START_MATCH

HANDLE_IDLE_DIRECT:
bl FN_LOAD_CODE_ENTRY # load text code entry
b SKIP_START_MATCH

################################################################################
# Case 2: Handle case where search is underway
################################################################################
HANDLE_FINDING:

# Handle cancel
rlwinm.	r0, REG_INPUTS, 0, 0x10
bnel FN_RESET_CONNECTIONS

b SKIP_START_MATCH

################################################################################
# Case 3: Handle case where we have an opponent
################################################################################
HANDLE_CONNECTED:

# Handle disconnect when input is hold for X seconds
lbz r3, -0x49B0(r13) # player index in control of CSS
branchl r12, Inputs_GetPlayerHeldInputs
rlwinm. r0, r4, 0, 0x10
beq RESET_HOLD_TIMER # if button is no longer pressed, reset hold timer

# increase time holding Z
lbz r3, CSSDT_Z_BUTTON_HOLD_TIMER(REG_CSSDT_ADDR)
addi r3, r3, 1
stb r3, CSSDT_Z_BUTTON_HOLD_TIMER(REG_CSSDT_ADDR)

# skip disconnect if hold time is less than delay
cmpwi r3, DISCONNECT_HOLD_DELAY
ble SKIP_DISCONNECT

# reset disconnect hold timer when disconnecting
stb REG_ZERO, CSSDT_Z_BUTTON_HOLD_TIMER(REG_CSSDT_ADDR)
bl FN_RESET_CONNECTIONS
b SKIP_START_MATCH
RESET_HOLD_TIMER:
stb REG_ZERO, CSSDT_Z_BUTTON_HOLD_TIMER(REG_CSSDT_ADDR)
SKIP_DISCONNECT:

# Handle case where we are not yet locked-in
lbz r3, MSRB_IS_LOCAL_PLAYER_READY(REG_MSRB_ADDR)
cmpwi r3, 0
bne CHECK_SHOULD_START_MATCH

# Check if start is pressed to see whether we should lock in
rlwinm.	r0, REG_INPUTS, 0, 19, 19
bne HANDLE_CONNECTED_ADVANCE

# Check if direct mode && loser && already chose stage
lbz r3, OFST_R13_ONLINE_MODE(r13)
cmpwi r3, ONLINE_MODE_DIRECT
beq HANDLE_CONNECTED_CHECK_LOSER_FOR_STAGE
cmpwi r3, ONLINE_MODE_TEAMS
bne CHECK_SHOULD_START_MATCH
HANDLE_CONNECTED_CHECK_LOSER_FOR_STAGE:
lbz r3, OFST_R13_ISWINNER (r13)
cmpwi r3,ISWINNER_LOST              # Check if this is the loser
bne CHECK_SHOULD_START_MATCH
lbz r3, OFST_R13_CHOSESTAGE (r13)
cmpwi r3,1                          # Check if loser picked stage already
bne CHECK_SHOULD_START_MATCH
b HANDLE_CONNECTED_ADVANCE

HANDLE_CONNECTED_ADVANCE:
# Check if character has been selected, if not, do nothing
lbz r3, -0x49A9(r13)
cmpwi r3, 0
beq CHECK_SHOULD_START_MATCH

# Sometimes when returning to the CSS, previously held buttons will stay held,
# including start. This prevents the start input from locking people in
# immediately... Doesn't feel like this should be necessary, and if it is,
# this doesn't feel like the right place for this logic
loadGlobalFrame r3
cmpwi r3, 0
beq CHECK_SHOULD_START_MATCH # Don't lock-in on the very first frame

# Check which mode we are playing.
lbz r3, OFST_R13_ONLINE_MODE(r13)
cmpwi r3, ONLINE_MODE_UNRANKED
beq HANDLE_CONNECTED_UNRANKED
cmpwi r3, ONLINE_MODE_ROOMS
beq HANDLE_CONNECTED_UNRANKED
cmpwi r3, ONLINE_MODE_PARTY
beq HANDLE_CONNECTED_UNRANKED
cmpwi r3, ONLINE_MODE_DIRECT
beq HANDLE_CONNECTED_DIRECT
cmpwi r3, ONLINE_MODE_TEAMS
beq HANDLE_CONNECTED_DIRECT
b 0x0                           # stall if neither

# Branch to this mode's behavior
HANDLE_CONNECTED_UNRANKED:
li  r3, SB_RAND       # stages always random for unranked
bl FN_TX_LOCK_IN
b CHECK_SHOULD_START_MATCH
HANDLE_CONNECTED_DIRECT:
# Loser picks the stage
lbz r3, OFST_R13_ISWINNER (r13)
cmpwi r3,ISWINNER_LOST
beq HANDLE_CONNECTED_DIRECT_ISLOSER
# Winner is unselected
cmpwi r3,ISWINNER_WON
beq HANDLE_CONNECTED_DIRECT_ISWINNER
b 0x0

HANDLE_CONNECTED_DIRECT_ISWINNER:
li  r3, SB_NOTSEL       # lock in, use opponents stage
bl FN_TX_LOCK_IN
b CHECK_SHOULD_START_MATCH

HANDLE_CONNECTED_DIRECT_ISLOSER:
# Check if loser picked stage already
lbz r3, OFST_R13_CHOSESTAGE (r13)
cmpwi r3,0
beq HANDLE_CONNECTED_DIRECT_LOADSSS
HANDLE_CONNECTED_DIRECT_SENDSTAGE:
# Send selected stage
lwz	r3, -0x77C0 (r13)
addi	r3, r3, 1424 + 0x8   # adding 0x8 to skip past some scene state stuff
lhz r3, 0x1E (r3)
bl FN_TX_LOCK_IN
b CHECK_SHOULD_START_MATCH
HANDLE_CONNECTED_DIRECT_LOADSSS:
# Set teams on/off bit. This is required by the "disable fod during doubles" gecko code
lbz r4, OFST_R13_ONLINE_MODE(r13)
cmpwi r4, ONLINE_MODE_TEAMS
li r3, 0
bne SET_TEAMS_BOOL
li r3, 1
SET_TEAMS_BOOL:
lwz	r4, -0x49F0(r13)
stb r3, 0x18(r4)
# Request scene change
li  r3,1
stb	r3, -0x49AA (r13)
# Set lock in callback function
bl FN_TX_LOCK_IN_BLRL
mflr r3
stw r3, OFST_R13_CALLBACK(r13)
b SKIP_START_MATCH

# Check to see if both players are ready and start match if they are
CHECK_SHOULD_START_MATCH:

lbz r3, MSRB_IS_LOCAL_PLAYER_READY(REG_MSRB_ADDR)
lbz r4, MSRB_IS_REMOTE_PLAYER_READY(REG_MSRB_ADDR)
and. r3, r3, r4
beq SKIP_START_MATCH # If not both players are ready, skip

# Once both players are ready, start the game
restore
branch r12, 0x80263264

################################################################################
# Case 4: Handle case where we have not locked-in
################################################################################
HANDLE_ERROR:

# Handle cancel
rlwinm.	r0, REG_INPUTS, 0, 0x10
bnel FN_RESET_CONNECTIONS

b SKIP_START_MATCH

################################################################################
# Function: Start find match
################################################################################
FN_TX_FIND_MATCH:
backup

# When the player starts looking for a match is a good time to reset the game index
loadwz r3, 0x803dad40 # Load minor scene data array ptr
lwz r12, 0x88(r3) # Load game prep minor scene data
li r3, 0
sth r3, GPDO_CUR_GAME(r12)
stb r3, GPDO_TIEBREAK_GAME_NUM(r12)

# Prepare buffer for EXI transfer
li r3, FMTB_SIZE
branchl r12, HSD_MemAlloc
mr REG_TXB_ADDR, r3

# Write tx data
li r3, CONST_SlippiCmdFindOpponent
stb r3, FMTB_CMD(REG_TXB_ADDR)

# Write online mode
lbz r3, OFST_R13_ONLINE_MODE(r13)
stb r3, FMTB_ONLINE_MODE(REG_TXB_ADDR)

# Write opp connect code, only matters for direct mode
addi r7, REG_TXB_ADDR, FMTB_OPP_CONNECT_CODE
load r6, 0x804a0740
li r4, 0
li r5, 0

WRITE_OPP_CODE_LOOP_START:
lhzx r3, r6, r4
sthx r3, r7, r5
addi r4, r4, 3
addi r5, r5, 2
cmpwi r5, 18
blt WRITE_OPP_CODE_LOOP_START

# Start finding opponent
mr r3, REG_TXB_ADDR
li r4, FMTB_SIZE
li r5, CONST_ExiWrite
branchl r12, FN_EXITransferBuffer

mr r3, REG_TXB_ADDR
branchl r12, HSD_Free

restore
blr

################################################################################
# Function: Lock in character selection
# r3 = stage behavior.
#     -2 = random stage
#     -1 = unselected (use opponents stage)
#      0+ = specify stage ID.
################################################################################
FN_TX_LOCK_IN_BLRL:
blrl
FN_TX_LOCK_IN:
.set  REG_SB, 31    # stage behavior
backup

# Backup stage behavior
mr  REG_SB,r3

# Prepare buffer for EXI transfer
li r3, PSTB_SIZE
branchl r12, HSD_MemAlloc
mr REG_TXB_ADDR, r3

# Write tx data
li r3, CONST_SlippiCmdSetMatchSelections
stb r3, PSTB_CMD(REG_TXB_ADDR)

# Fetch selected character information
lwz r4, -0x49f0(r13) # base address where css selections are stored
lbz r3, -0x5108(r13) # player index
mulli r3, r3, 0x24
add r4, r4, r3

lbz r3, 0x70(r4) # load char id
stb r3, PSTB_CHAR_ID(REG_TXB_ADDR)
lbz r3, 0x73(r4) # load char color
stb r3, PSTB_CHAR_COLOR(REG_TXB_ADDR)
li r3, 1 # merge character
stb r3, PSTB_CHAR_OPT(REG_TXB_ADDR)

# Send a blank team ID if this isn't teams mode.
lbz r3, OFST_R13_ONLINE_MODE(r13)
cmpwi r3, ONLINE_MODE_TEAMS
beq SEND_TEAM_ID
li r3, 0
stb r3, PSTB_TEAM_ID(REG_TXB_ADDR)
b SKIP_SEND_TEAM_ID

SEND_TEAM_ID:
# Calc/Set Team ID
loadwz r3, CSSDT_BUF_ADDR
lbz r3, CSSDT_TEAM_IDX(r3)
subi r3, r3, 1
stb r3, PSTB_TEAM_ID(REG_TXB_ADDR)

SKIP_SEND_TEAM_ID:
# Handle stage
cmpwi REG_SB, -2
beq FN_TX_LOCK_IN_STAGE_RAND
cmpwi REG_SB, -1
beq FN_TX_LOCK_IN_STAGE_UNSET
cmpwi REG_SB, 0
bge FN_TX_LOCK_IN_STAGE_PICK

FN_TX_LOCK_IN_STAGE_RAND:
li  r3,0
li  r4,3
b FN_TX_LOCK_IN_STAGE_SEND

FN_TX_LOCK_IN_STAGE_UNSET:
li  r3,0
li  r4,0
b FN_TX_LOCK_IN_STAGE_SEND

FN_TX_LOCK_IN_STAGE_PICK:
mr  r3,REG_SB
li  r4,1
b FN_TX_LOCK_IN_STAGE_SEND

FN_TX_LOCK_IN_STAGE_SEND:
sth r3, PSTB_STAGE_ID(REG_TXB_ADDR)
stb r4, PSTB_STAGE_OPT(REG_TXB_ADDR)

# Write the alt stage mode
computeBranchTargetAddress r3, INJ_FREEZE_STADIUM
addi r3, r3, 0x8
lbz r3, 0(r3)
stb r3, PSTB_ALT_STAGE_MODE(REG_TXB_ADDR)
# mr r5, r3
# logf LOG_LEVEL_WARN, "TXB: Alt Stage Mode: %x"

# Write the online mode we are in
lbz r3, OFST_R13_ONLINE_MODE(r13)
stb r3, PSTB_ONLINE_MODE(REG_TXB_ADDR)

# Indicate to Dolphin we want to lock-in
mr r3, REG_TXB_ADDR
li r4, PSTB_SIZE
li r5, CONST_ExiWrite
branchl r12, FN_EXITransferBuffer

mr r3, REG_TXB_ADDR
branchl r12, HSD_Free

restore
blr

################################################################################
# Function: Simple function to lock in and search
# r3 = stage behavior.
#     -2 = random stage
#     -1 = unselected (use opponents stage)
#      0+ = specify stage ID.
################################################################################
FN_LOCK_IN_AND_SEARCH_BLRL:
blrl
FN_LOCK_IN_AND_SEARCH:
backup

lbz r20, CSSDT_TEAM_IDX(REG_CSSDT_ADDR)
# logf LOG_LEVEL_NOTICE, "TEAM INDEX AFTER %d", "mr r5, 20"

bl FN_TX_LOCK_IN # Lock in character selection
bl FN_TX_FIND_MATCH # Trigger matchmaking

restore
blr

################################################################################
# Function: Load code entry
################################################################################
FN_LOAD_CODE_ENTRY:
backup

# Indicate we want name entry to operate in connect code mode
li r3, 1
stb r3, OFST_R13_NAME_ENTRY_MODE(r13)

# Prepare callback address on successful name entry
bl FN_LOCK_IN_AND_SEARCH_BLRL
mflr r3
stw r3, OFST_R13_CALLBACK(r13)

# Set the player index controlling name entry
lbz r0, -0x49b0(r13)
stb r0, -0x49a7(r13)

# Start process to load name entry
li r0, 4
stb r0, -0x49aa(r13)

restore
blr

################################################################################
# Function: Reset connections and clear lock-in state
################################################################################
FN_RESET_CONNECTIONS:
backup

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
blr


################################################################################
# Skip starting match
################################################################################
SKIP_START_MATCH:
restore
branch r12, 0x80263334

EXIT:
restore
