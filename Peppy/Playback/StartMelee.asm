################################################################################
# Address: 0x8016e748 # StartMelee, before the standard Slippi stuff runs
################################################################################
#
# PEPPY MERGE - generated file, do not hand-edit.
# Regenerate with: python Peppy/Playback/merge-startmelee.py
#
# Upstream Slippi ships two different codes at this same address, one in each
# codeset:
#
#   netplay.json   Online/Superseded/InitOnlinePlay.asm           (allocates the ODB)
#   playback.json  Playback/Core/StartMelee/RestoreGameInfo.asm   (allocates the PDB)
#
# Peppy builds one codeset that can do both, so exactly one code may live here.
# Both originals gate on their own scene and those scenes are mutually
# exclusive - SCENE_ONLINE_IN_GAME (0x0208) and SCENE_PLAYBACK_IN_GAME (0x010E) -
# so this file runs the replaced instruction once, then dispatches to whichever
# body matches the scene we are actually in.
#
# Both bodies are copied VERBATIM. The only lines removed from each are the ones
# this wrapper now owns: the replaced `branchl`, the `backup`, the online scene
# check, and the trailing `restore`. Nothing inside either body changed.
#
# Verified before merging:
#   - no label is defined in both files
#   - no .set name is defined in both files
#   - the 13 symbols Online.s and Playback.s both define evaluate the same
#     (ROLLBACK_MAX_FRAME_COUNT and SOUND_STORAGE_FRAME_COUNT are both 7)
#   - playbackDataBuffer (-0x5040) and frameIndex (-0x49ac) do not overlap any
#     r13 slot used by Online/ or Peppy/
#
################################################################################

.include "Common/Common.s"
.include "Online/Online.s"
.include "Playback/Playback.s"
.include "Playback/Core/RestoreInitialRNG.s"

################################################################################
# Register names - from Online/Superseded/InitOnlinePlay.asm
################################################################################
.set REG_GAME_INFO_START, 31 # from parent

.set REG_ODB_ADDRESS, 27
.set REG_RXB_ADDRESS, 26
.set REG_SSRB_ADDR, 25
.set REG_MSRB_ADDR, 24
.set REG_PLAYER_IDX, 23

################################################################################
# Register names - from Playback/Core/StartMelee/RestoreGameInfo.asm
################################################################################
.set BufferPointer,30
.set REG_GeckoBuffer,29
.set REG_DirectoryBuffer,28

################################################################################
# Replaced codeline, call function. Runs once, for either path.
################################################################################
branchl r12, 0x802254B8

backup

################################################################################
# Dispatch on the scene we are in
################################################################################
getMinorMajor r3
cmpwi r3, SCENE_ONLINE_IN_GAME
beq PEPPY_PATH_ONLINE
cmpwi r3, SCENE_PLAYBACK_IN_GAME
beq PEPPY_PATH_PLAYBACK
b PEPPY_END


################################################################################
################################################################################
##  PLAYBACK PATH - verbatim from Playback/Core/StartMelee/RestoreGameInfo.asm
################################################################################
################################################################################
PEPPY_PATH_PLAYBACK:

# allocate memory for directory buffer
  li r3, PDB_SIZE
  branchl r12, HSD_MemAlloc
  mr REG_DirectoryBuffer, r3
  stw REG_DirectoryBuffer, playbackDataBuffer(r13) # Store directory buffer location
  li r4, PDB_SIZE
  branchl r12, Zero_AreaLength

# allocate memory for the gameframe buffer used here and in ReceiveGameFrame
  li  r3,EXIBufferLength
  branchl r12, HSD_MemAlloc
  mr  BufferPointer,r3
  stw BufferPointer,PDB_EXI_BUF_ADDR(REG_DirectoryBuffer)

# allocate memory for the Secondary Buffer used in RestoreStockSteal
  li  r3,64
  branchl r12, HSD_MemAlloc
  stw r3,PDB_SECONDARY_EXI_BUF_ADDR(REG_DirectoryBuffer)

# get the game info data
REQUEST_DATA:
# request game information from slippi
  li r3,CMD_GET_GAME_INFO        # store game info request ID
  stb r3,0x0(BufferPointer)

# write memory locations to preserve when doing mem savestates
  addi r3, REG_DirectoryBuffer, PDB_SFXDB_START
  stw r3, 0x1(BufferPointer)
  li r3, SFXDB_SIZE + 4 # include the latest frame which follows SFXDB
  stw r3, 0x5(BufferPointer)
  li r3, 0
  stw r3, 0x9(BufferPointer)

# Transfer buffer over DMA
  mr r3,BufferPointer   #Buffer Pointer
  li  r4,0xD            #Buffer Length
  li  r5,CONST_ExiWrite
  branchl r12,FN_EXITransferBuffer
RECEIVE_DATA:
# Transfer buffer over DMA
  mr  r3,BufferPointer
  li  r4,GameInfoLength     #Buffer Length
  li  r5,CONST_ExiRead
  branchl r12,FN_EXITransferBuffer
# Check if successful
  lbz r3,0x0(BufferPointer)
  cmpwi r3, 1
  beq READ_DATA
# Wait a frame before trying again
  branchl r12, VIWaitForRetrace
  b REQUEST_DATA

READ_DATA:
  lwz r3,InfoRNGSeed(BufferPointer)
  lis r4, 0x804D
  stw r3, 0x5F90(r4) #store random seed

#------------- GAME INFO BLOCK -------------
# this iterates through the static game info block that is used to pull data
# from to initialize the game. it reads the whole thing from slippi and writes
# it back to memory. (0x138 bytes long)
  mr  r3,r31                        #Match setup struct
  addi r4,BufferPointer,MatchStruct #Match info from slippi
  li  r5,0x138                      #Match struct length
  branchl r12, memcpy

# nullify function pointers
# Dolphin v2.1.0 had an issue where it put something in the game start callback
# which would pause the game. By clearing these, we avoid that issue with 2.1.0
  addi r3, r31, 0x40
  li r4, 0x1C
  branchl r12, Zero_AreaLength

#------------- OTHER INFO -------------
# write UCF toggle bytes
# This stuff is handled with dynamic gecko codes now but this has to stay
# here for backward compatibility with old replays from before we got rid
# of the toggles
# As of 3/31/2021 this is no longer strictly necessary for new replays but
# it has to stay here to play back legacy replays, those still use the toggle-based
# UCF handlers
  subi r23,rtoc,DashbackOptions #Prepare game memory dashback toggle address
  subi r20,rtoc,ShieldDropOptions #Prepare game memory shield drop toggle address
  addi r21,BufferPointer,UCFToggles  #Get UCF toggles in buffer
  li  r22,0                          #Init loop
UCF_LOOP:
  mulli r4,r22,0x8          #each player's ucf toggle is 8 bytes long (thanks FM)
  lwzx  r3,r4,r21           #get dashback toggle from
  stbx  r3,r22,r23          #store to dashback
  addi  r4,r4,0x4
  lwzx  r3,r4,r21
  stbx  r3,r22,r20
  addi  r22,r22,1
  cmpwi r22,4
  blt UCF_LOOP

#------------- RESTORE NAMETAGS ------------
# Loop through players 1-4 and restore their nametag data
# r31 contains the match struct fed into StartMelee. We'll
# be using this to restore each player's nametag slot

# Offsets
.set PlayerInfoStart,96       #player data starts in match struct
.set PlayerInfoLength,36      #length of each player's data
.set PlayerStatus,0x1         #offset of players in-game status
.set Nametag,0xA              #offset of the nametag ID in the player's data
# Constants
.set CharactersToCopy, 8 *2
# Registers
.set REG_LoopCount,20
.set REG_PlayerInfoStart,21
.set REG_CurrentPlayerData,22
.set REG_NametagID,23

# Init loop
  li  REG_LoopCount,0                               #init loop count
  addi REG_PlayerInfoStart,r31,PlayerInfoStart     #player data start in match struct
RESTORE_GAME_INFO_NAMETAG_LOOP:
# Get players data
  mulli REG_CurrentPlayerData,REG_LoopCount,PlayerInfoLength
  add REG_CurrentPlayerData,REG_CurrentPlayerData,REG_PlayerInfoStart
# Check if player is in game && human
  lbz r3,PlayerStatus(REG_CurrentPlayerData)
  cmpwi r3,0x0
  bne RESTORE_GAME_INFO_NAMETAG_NO_TAG
# Check if player has a nametag
  lbz r3,Nametag(REG_CurrentPlayerData)
  cmpwi r3,0x78
  beq RESTORE_GAME_INFO_NAMETAG_NO_TAG
RESTORE_GAME_INFO_NAMETAG_HAS_TAG:
# Save nametag ID
  mr REG_NametagID,r3
# Set nametag as active
  branchl r12, Nametag_SetNameAsInUse
# Get nametag text pointer
  mr  r3,REG_NametagID
  branchl r12, Nametag_GetNametagBlock
  addi r3,r3,0x198
# Get players nametag
  addi r4,BufferPointer,NametagData       #Start of nametag data
  mulli r5,REG_LoopCount,CharactersToCopy #This players nametag data
  add r4,r4,r5
# Check if nametag data is empty (old replays have no data here)
  lbz r5,0x(r4)
  cmpwi r5,0x0
  bne RESTORE_GAME_INFO_NAMETAG_COPY
# Nametag was not backed up, give player a null nametag ID
  li  r3,0x78
  stb r3,Nametag(REG_CurrentPlayerData)
  b RESTORE_GAME_INFO_NAMETAG_INC_LOOP
RESTORE_GAME_INFO_NAMETAG_COPY:
# Copy backed up nametag to it
  li  r5,CharactersToCopy
  branchl r12, memcpy
  b RESTORE_GAME_INFO_NAMETAG_INC_LOOP
RESTORE_GAME_INFO_NAMETAG_NO_TAG:
RESTORE_GAME_INFO_NAMETAG_INC_LOOP:
# Increment Loop
  addi REG_LoopCount,REG_LoopCount,1
  cmpwi REG_LoopCount,4
  blt RESTORE_GAME_INFO_NAMETAG_LOOP

# TODO: I dont think any of the following three toggles are necessary anymore
# TODO: since we use dynamic gecko codes now. I'm don't even think the toggles
# TODO: are referenced anywhere.

#Restore PALToggle byte
  lbz r3,PALBool(BufferPointer)
  stb r3,PALToggle(rtoc)

#Restore PSPreloadToggle byte
  lbz r3,PSPreloadBool(BufferPointer)
  stb r3,PSPreloadToggle(rtoc)

#Restore FrozenPS byte
  lbz r3,FrozenPSBool(BufferPointer)
  stb r3,FSToggle(rtoc)

# Get bool for whether resync logic should be used
  lbz r3,ShouldResyncBool(BufferPointer)
  stb r3,PDB_SHOULD_RESYNC(REG_DirectoryBuffer)

# Get player display names
  addi r3, REG_DirectoryBuffer, PDB_DISPLAY_NAMES # destination
  addi r4, BufferPointer, DisplayNameData         # source
  li r5, DisplayNameData_Length                   # length
  branchl r12, memcpy

#--------------- Apply Dynamic Gecko Codes ---------------------
# Step 1: Grab size of gecko code list and create a buffer to store them
  # TODO: Make sure that returned size includes the termination sequence (8 bytes)
  lwz r3, GeckoListSize(BufferPointer)
  branchl r12, HSD_MemAlloc
  mr REG_GeckoBuffer, r3
  stw REG_GeckoBuffer, PDB_DYNAMIC_GECKO_ADDR(REG_DirectoryBuffer)

  # Overwrite the gecko heap location for simultaneous recording + playback
  load r4, GeckoHeapPtr
  subi r3, REG_GeckoBuffer, 0x8 # Recording expects d0c0de d0c0de but we dont have that here
  stw r3, 0(r4)

# Step 2: Ask dolphin for the code list
  li r3, CMD_GET_GECKO_CODES
  stb r3, 0(REG_GeckoBuffer)

  # Request codes
  mr r3, REG_GeckoBuffer
  li r4, 1
  li r5, CONST_ExiWrite
  branchl r12, FN_EXITransferBuffer

# Step 3: Copy code list into our buffer
  mr r3, REG_GeckoBuffer
  lwz r4, GeckoListSize(BufferPointer)
  li r5, CONST_ExiRead
  branchl r12, FN_EXITransferBuffer

# Step 4: Run through code list once to figure out how much space we need
# to allocate for restoration data
  # initialize the backup size to zero
  li r4, 4 # Start with size 4 to fit null pointer to terminate restore
  stw r4, PDB_RESTORE_BUF_SIZE(REG_DirectoryBuffer)

  mr r3, REG_GeckoBuffer # Gecko code list start
  bl Callback_CalculateSize
  mflr r4 # Callback function to calculate size. Will update PDB_RESTORE_BUF_SIZE
  branchl r12, FN_ProcessGecko

# Step 5: Use size returned to allocate a buffer to store the recovery data
  lwz r3, PDB_RESTORE_BUF_SIZE(REG_DirectoryBuffer)
  branchl r12, HSD_MemAlloc
  stw r3, PDB_RESTORE_BUF_ADDR(REG_DirectoryBuffer)
  stw r3, PDB_RESTORE_BUF_WRITE_POS(REG_DirectoryBuffer) # Init pos to start

# Step 6: Iterate through codes again, this time using a callback that will
# apply all of the changes and store the replacements in the restore buffer
  mr r3, REG_GeckoBuffer # Gecko code list start
  bl Callback_ProcessGeckoCode # Callback function to process codes
  mflr r4
  branchl r12, FN_ProcessGecko

  b GECKO_CLEANUP

Callback_CalculateSize:
blrl
  # r5 is input to this function, it contains the size of the replaced data
  cmpwi r5, 0 # If size is 0, either we don't support this codetype or theres nothing to replace
  beq Callback_CalculateSize_End

  lwz r6, playbackDataBuffer(r13)
  lwz r3, PDB_RESTORE_BUF_SIZE(r6)
  addi r3, r3, 8 # For each new code, we need a target address and length
  add r3, r3, r5 # Add size of the replacement to the total length
  stw r3, PDB_RESTORE_BUF_SIZE(r6)

Callback_CalculateSize_End:
  blr

Callback_ProcessGeckoCode:
blrl

.set REG_CodeAddress, 30
.set REG_TargetDataPtr, 29
.set REG_SourceDataPtr, 28
.set REG_ReplaceSize, 27

.set REG_DirectoryBuffer2, 26
.set REG_RestoreBufPos, 25

  # r5 is input to this function, it contains the size of the replaced data
  cmpwi r5, 0 # If size is 0, either we don't support this codetype or theres nothing to replace
  beq Callback_ProcessGeckoCode_End

  backup # TODO: Consider being more efficient about backup and restore?

  mr REG_CodeAddress, r4
  mr REG_ReplaceSize, r5

  lwz r5, 0(REG_CodeAddress)
  rlwinm r5, r5, 0, 0x01FFFFFF
  oris REG_TargetDataPtr, r5, 0x8000 # Injection Address

  lwz REG_DirectoryBuffer2, playbackDataBuffer(r13)
  lwz REG_RestoreBufPos, PDB_RESTORE_BUF_WRITE_POS(REG_DirectoryBuffer2)

  # r3 contains the codetype, do a switch statement on it to prepare for memcpys
  cmpwi r3, 0x04
  beq HANDLE_04

  cmpwi r3, 0x06
  beq HANDLE_06

  cmpwi r3, 0xC2
  beq HANDLE_C2

  # TODO: Assert? It should not be possible to get here. Obviously we could skip
  # TODO: one of the above compares but I'd rather do an assert or something
  # TODO: here to make sure that we haven't made a code error

HANDLE_04:
  addi REG_SourceDataPtr, REG_CodeAddress, 4
  b BACKUP_REPLACED

HANDLE_06:
  addi REG_SourceDataPtr, REG_CodeAddress, 8
  b BACKUP_REPLACED

HANDLE_C2:
  # C2 Step 1: Copy the branch instruction that will overwrite data to buffer.
  # This is done in this way to allow us to back up the data before overwriting it
  addi r4, REG_CodeAddress, 0x8
  sub r3, r4, REG_TargetDataPtr
  rlwinm r3, r3, 0, 6, 29
  oris r3, r3, 0x4800
  stw r3, PDB_RESTORE_C2_BRANCH(REG_DirectoryBuffer2)
  addi REG_SourceDataPtr, REG_DirectoryBuffer2, PDB_RESTORE_C2_BRANCH

  # C2 Step 2: Replace branch instruction in gecko code to return to correct loc
  lwz r3, 0x4(REG_CodeAddress)
  mulli r3, r3, 0x8
  add r4, r3, REG_CodeAddress            # get branch back site
  addi r3, REG_TargetDataPtr, 0x4        # get branch back destination
  sub r3, r3, r4
  rlwinm r3, r3, 0, 6, 29                # extract bits for offset
  oris r3, r3, 0x4800                    # Create branch instruction from it
  subi r3, r3, 0x4                       # subtract 4 i guess
  stw r3, 0x4(r4)                        # place branch instruction

BACKUP_REPLACED:

  # Step 1: Back up the data about to be replaced
  stw REG_TargetDataPtr, 0(REG_RestoreBufPos)
  stw REG_ReplaceSize, 4(REG_RestoreBufPos)

  addi r3, REG_RestoreBufPos, 8 # destination
  mr r4, REG_TargetDataPtr # source
  mr r5, REG_ReplaceSize
  branchl r12, memcpy

  # Increment RestoreBufPos
  addi REG_RestoreBufPos, REG_RestoreBufPos, 8
  add REG_RestoreBufPos, REG_RestoreBufPos, REG_ReplaceSize
  stw REG_RestoreBufPos, PDB_RESTORE_BUF_WRITE_POS(REG_DirectoryBuffer2)

  # Step 2: Replace data
  mr r3, REG_TargetDataPtr # destination
  mr r4, REG_SourceDataPtr # source
  mr r5, REG_ReplaceSize
  branchl r12, memcpy

  mr r3, REG_TargetDataPtr
  mr r4, REG_ReplaceSize
  branchl r12, TRK_flush_cache

  restore

Callback_ProcessGeckoCode_End:
  blr

GECKO_CLEANUP:
  # Cleanup Step 1: Write null ptr to the end of cleanup
  li r3, 0
  lwz r4, PDB_RESTORE_BUF_WRITE_POS(REG_DirectoryBuffer)
  stw r3, 0(r4)

  # Cleanup Step 2: Flush instruction cache for entire gecko code region
  mr r3, REG_GeckoBuffer
  lwz r4, GeckoListSize(BufferPointer)
  branchl r12, TRK_flush_cache

# run macro to create the RestoreInitialRNG process
  Macro_RestoreInitialRNG

Injection_Exit:
b PEPPY_END


################################################################################
################################################################################
##  ONLINE PATH - verbatim from Online/Superseded/InitOnlinePlay.asm
################################################################################
################################################################################
PEPPY_PATH_ONLINE:

################################################################################
# Initialize Online Data Buffers
################################################################################

li r3, ODB_SIZE
branchl r12, HSD_MemAlloc
mr REG_ODB_ADDRESS, r3
li r4, ODB_SIZE
branchl r12, Zero_AreaLength

stw REG_ODB_ADDRESS, OFST_R13_ODB_ADDR(r13)

# We use game prep minor scene data as a convenient place to store game index such that it persists
# between games even when not in ranked
loadwz r3, 0x803dad40 # Load minor scene data array ptr
lwz r12, 0x88(r3) # Load game prep minor scene data

# If not in ranked mode, let's increment the game index before the game start. Ranked mode manages
# this in its scene logic
lbz r3, OFST_R13_ONLINE_MODE(r13)
cmpwi r3, ONLINE_MODE_RANKED
beq SKIP_GAME_INDEX_INCR
lhz r3, GPDO_CUR_GAME(r12)
addi r3, r3, 1
sth r3, GPDO_CUR_GAME(r12)
SKIP_GAME_INDEX_INCR:

# Indicate that the first frame is frame 1
li r3, 1
stw r3, ODB_FRAME(REG_ODB_ADDRESS)

# Store location to game complete handler
bl FN_HandleGameCompleted
mflr r3
stw r3, ODB_FN_HANDLE_GAME_OVER_ADDR(REG_ODB_ADDRESS)

# Create buffers for EXI data transfer. These buffers are split up because
# EXI buffers must be 32-byte aligned to work
li r3, TXB_SIZE
branchl r12, HSD_MemAlloc
stw r3, ODB_TXB_ADDR(REG_ODB_ADDRESS)

li r3, RXB_SIZE
branchl r12, HSD_MemAlloc
stw r3, ODB_RXB_ADDR(REG_ODB_ADDRESS)
mr REG_RXB_ADDRESS, r3
li r4, RXB_SIZE
branchl r12, Zero_AreaLength # For frame num, may not be necessary

# Prepare buffer for requesting savestate actions from Dolphin
li r3, SSRB_SIZE
branchl r12, HSD_MemAlloc
mr REG_SSRB_ADDR, r3
stw REG_SSRB_ADDR, ODB_SAVESTATE_SSRB_ADDR(REG_ODB_ADDRESS)

# Prepare buffer for ASM side savestates
li r3, SSCB_SIZE
branchl r12, HSD_MemAlloc
stw r3, ODB_SAVESTATE_SSCB_ADDR(REG_ODB_ADDRESS)
li r4, SSCB_SIZE
branchl r12, Zero_AreaLength

li r4, 0
stb r4, SSCB_WRITE_INDEX(r3)

li r4, ROLLBACK_MAX_FRAME_COUNT
stb r4, SSCB_SSDB_COUNT(r3)

# Write the locations that will be preserved through a savestate
stw REG_ODB_ADDRESS, SSRB_ODB_ADDR(REG_SSRB_ADDR)
li r3, ODB_SIZE
stw r3, SSRB_ODB_SIZE(REG_SSRB_ADDR)
stw REG_RXB_ADDRESS, SSRB_RXB_ADDR(REG_SSRB_ADDR)
li r3, RXB_SIZE
stw r3, SSRB_RXB_SIZE(REG_SSRB_ADDR)
lwz r3, ODB_SAVESTATE_SSCB_ADDR(REG_ODB_ADDRESS)
stw r3, SSRB_SSCB_ADDR(REG_SSRB_ADDR)
li r3, SSCB_SIZE
stw r3, SSRB_SSCB_SIZE(REG_SSRB_ADDR)
li r3, 0 # Write terminator
stw r3, SSRB_TERMINATOR(REG_SSRB_ADDR)

################################################################################
# Prepare match characters, ports, and RNG
################################################################################
# Get match state info
li r3, 0
branchl r12, FN_LoadMatchState
mr REG_MSRB_ADDR, r3

# Write port used for local player during the game so we can remap inputs on the
# results screen. Currently only party mode uses results screen
fetchOnlineStaticDataPtr r12

# Prepare player indices
lbz r3, -0x5108(r13) # Grab the 1p port in use
stb r3, ODB_INPUT_SOURCE_INDEX(REG_ODB_ADDRESS)
lbz r3, MSRB_LOCAL_PLAYER_INDEX(REG_MSRB_ADDR)
stb r3, ODB_LOCAL_PLAYER_INDEX(REG_ODB_ADDRESS)
stb r3, OSD_LOCAL_PLAYER_INDEX(r12)
lbz r3, MSRB_REMOTE_PLAYER_INDEX(REG_MSRB_ADDR)
stb r3, ODB_ONLINE_PLAYER_INDEX(REG_ODB_ADDRESS)

# Copy over RNG Offset
lwz r3, MSRB_RNG_OFFSET(REG_MSRB_ADDR)
stw r3, ODB_RNG_OFFSET(REG_ODB_ADDRESS)

# Write RNG offset to seed such that the start seed matches. Without this I
# noticed some desyncs on FD
lis r4, 0x804D
stw r3, 0x5F90(r4) # overwrite seed

# Copy match struct
mr r3, REG_GAME_INFO_START
addi r4, REG_MSRB_ADDR, MSRB_GAME_INFO_BLOCK
li r5, MATCH_STRUCT_LEN
branchl r12, memcpy

computeBranchTargetAddress r4, INJ_FREEZE_STADIUM
lbz r3, MSRB_ALT_STAGE_MODE(REG_MSRB_ADDR)
stb r3, 0x8(r4) # Store selection in the gecko code space
# logf LOG_LEVEL_ERROR, "alt stage mode: %d"

lbz r3, OFST_R13_ONLINE_MODE(r13)
cmpwi r3, ONLINE_MODE_RANKED
bne SKIP_TIEBREAK_OVERWRITE

# For ranked, in the case of a tiebreak, overwrite stock count and timer
loadwz r5, 0x803dad40 # Load minor scene data array ptr
lwz r5, 0x88(r5) # Load game prep minor scene data
lbz r3, GPDO_TIEBREAK_GAME_NUM(r5) # Load is_tiebreak
cmpwi r3, 0
beq HANDLE_RANKED_MATCH_START # If not a tiebreak, handle ranked match start
lbz r3, GPDO_LAST_GAME_END_MODE(r5)
cmpwi r3, 0x7
beq SKIP_TIEBREAK_OVERWRITE # If last game ended with exit, desync recovery values will be used (set by dolphin)

li r3, 180
stw r3, 0x10(REG_GAME_INFO_START)

li r3, 1
stb r3, 0x62(REG_GAME_INFO_START)
stb r3, 0x62 + 0x24(REG_GAME_INFO_START)
stb r3, 0x62 + 0x24 * 2(REG_GAME_INFO_START)
stb r3, 0x62 + 0x24 * 3(REG_GAME_INFO_START)

b SKIP_TIEBREAK_OVERWRITE # Done handling tiebreak

HANDLE_RANKED_MATCH_START:
# This is a ranked match that is not a tiebreak, report to the server that the game is starting
lwz r3, OFST_R13_SB_ADDR(r13) # Use the scene buffer, should be available to use
li r4, CONST_SlippiCmdReportMatchStatus
stb r4, 0(r3) # Store command byte
lhz r4, GPDO_CUR_GAME(r5) # r5 still contains game prep minor scene data from above
addi r4, r4, 19 # Add 19 to the game num because 20 is the offset for game_start_1
stb r4, 1(r3) # Store message index
li r4, 2 # Buffer length
li r5, CONST_ExiWrite
branchl r12, FN_EXITransferBuffer

SKIP_TIEBREAK_OVERWRITE:

# Test code to force the timer to 15 seconds
# li r3, 15
# stw r3, 0x10(REG_GAME_INFO_START)

# For teams, overwrite the colors in the game info block with the proper color for the given team ID
lbz r3, OFST_R13_ONLINE_MODE(r13)
cmpwi r3, ONLINE_MODE_TEAMS
bne SKIP_CHAR_COLOR_OVERWRITE

li REG_PLAYER_IDX, 0

CHAR_COLOR_OVERWRITE_LOOP_START:
# Load the team ID + 1 for team index and character ID to pass to function to get costume ID
mulli r5, REG_PLAYER_IDX, 0x24
addi r3, r5, 0x69
lbzx r3, REG_GAME_INFO_START, r3 # Loads team ID
addi r3, r3, 1
addi r4, r5, 0x60
lbzx r4, REG_GAME_INFO_START, r4 # Loads character ID
branchl r12, FN_GetTeamCostumeIndex # Loads costume ID into r3

# Write costume ID 
mulli r4, REG_PLAYER_IDX, 0x24
addi r4, r4, 0x63
stbx r3, REG_GAME_INFO_START, r4

# Increment port
addi REG_PLAYER_IDX, REG_PLAYER_IDX, 1
cmpwi REG_PLAYER_IDX, 4
blt CHAR_COLOR_OVERWRITE_LOOP_START

SKIP_CHAR_COLOR_OVERWRITE:

################################################################################
# Set up number of delay frames
################################################################################
lbz r3, MSRB_DELAY_FRAMES(REG_MSRB_ADDR)
cmpwi r3, MIN_DELAY_FRAMES
blt DELAY_FRAMES_MIN_LIMIT
cmpwi r3, MAX_DELAY_FRAMES
bgt DELAY_FRAMES_MAX_LIMIT
b SET_DELAY_FRAMES

DELAY_FRAMES_MIN_LIMIT:
li r3, MIN_DELAY_FRAMES
b SET_DELAY_FRAMES

DELAY_FRAMES_MAX_LIMIT:
li r3, MAX_DELAY_FRAMES

SET_DELAY_FRAMES:
stb r3, ODB_DELAY_FRAMES(REG_ODB_ADDRESS)

################################################################################
# Clear A inputs to prevent transformation
################################################################################
# This is kind of jank but it will prevent Slippi from trying to flip the
# character in the recording game info block. It will also prevent a
# sheik -> zelda or zelda -> sheik transformation. This does every port because
# otherwise it might be possible for someone to play online with two controllers
# plugged in to start the opponent as the wrong character
li r5, 0

LOOP_CLEAR_INPUTS_START:
load r3, 0x804c20bc
mulli	r4, r5, 68
add r3, r3, r4
li r4, 0
stw r4, 0x0(r3)

addi r5, r5, 1
cmpwi r5, 4
blt LOOP_CLEAR_INPUTS_START

################################################################################
# Initialize RNG Function for Online Games
################################################################################

# Create GObj
li r3, 4 # GObj Type (4 is the player type, this should ensure it runs before any player animations)
li r4, 7 # On-Pause Function (dont run on pause)
li r5, 0 # some type of priority
branchl r12, GObj_Create

#Create Proc
bl FN_SyncRNG
mflr r4 # Function
li r5, 0 # Priority
branchl	r12, GObj_AddProc

b GECKO_EXIT

################################################################################
# Routine: SyncRNG
# ------------------------------------------------------------------------------
# Description: Syncs RNG when playing online
################################################################################

FN_SyncRNG:
blrl

loadGlobalFrame r3
rlwinm r4, r3, 16, 0xFFFFFFFF # Rotate left 16 bits for better RNG differences?

# Add RNG offset such that games are not always the same. Without this, for
# example, Pokemon would always go to the same transformation
lwz r3, OFST_R13_ODB_ADDR(r13) # ODB address
lwz r3, ODB_RNG_OFFSET(r3)
add r4, r4, r3

lis r3, 0x804D
stw r4, 0x5F90(r3) # overwrite random seed

blr

################################################################################
# Routine: HandleGameCompleted
# ------------------------------------------------------------------------------
# Description: Function called when game is confirmed over (no more rollbacks)
################################################################################
FN_HandleGameCompleted:
blrl

.set REG_IDX, 31
.set REG_RGB_ADDR, 30
.set REG_RGPB_ADDR, 29
.set REG_ODB_ADDRESS, 28
.set REG_GPD_ADDR, 27
.set REG_GAME_END_STRUCT_ADDR, 26

backup

lwz REG_ODB_ADDRESS, OFST_R13_ODB_ADDR(r13) # data buffer address

loadwz r5, 0x803dad40 # Load minor scene data array ptr
lwz REG_GPD_ADDR, 0x88(r5) # Load game prep minor scene data

load REG_GAME_END_STRUCT_ADDR, 0x80479da4

################################################################################
# Initialize the MatchEndData early. Normally his happens on scene transition
# around 0x8016ea1c but we need it earlier (now) to determine the result of
# the match
################################################################################
mr r3, REG_GAME_END_STRUCT_ADDR # dest
load r4, 0x8046b8ec # source
li r5, 8824 # size
branchl r12, memcpy

load r4, 0x8046b6a0
mr r3, REG_GAME_END_STRUCT_ADDR
lbz r0, 0x24D0(r4)
stb r0, 0x6(r3)
lbz r0, 0x0008(r4)
stb r0, 0x4(r3)
branchl r12, 0x80166378 # CreateMatchEndData (struct @ 80479da4)

################################################################################
# Report game results
################################################################################
# Prepare buffer for EXI transfer
li r3, RGB_SIZE
branchl r12, HSD_MemAlloc
mr REG_RGB_ADDR, r3

# We can just use the receive buffer to send request command
li r3, CONST_SlippiCmdReportMatch
stb r3, RGB_COMMAND(REG_RGB_ADDR)

lbz r3, OFST_R13_ONLINE_MODE(r13)
stb r3, RGB_ONLINE_MODE(REG_RGB_ADDR)

branchl r12, 0x801a4ba8 # MenuController_LoadTimer1
stw r3, RGB_FRAME_LENGTH(REG_RGB_ADDR) # Store frame length

lhz r3, GPDO_CUR_GAME(REG_GPD_ADDR)
stw r3, RGB_GAME_INDEX(REG_RGB_ADDR)

lbz r3, GPDO_TIEBREAK_GAME_NUM(REG_GPD_ADDR)
stw r3, RGB_TIEBREAKER_INDEX(REG_RGB_ADDR)

lwz r3, GPDO_FN_COMPUTE_RANKED_WINNER(REG_GPD_ADDR)
mtctr r3
bctrl
stb r3, RGB_WINNER_IDX(REG_RGB_ADDR)

# Change winner idx to -3 if disconnect detected, -2 if desync detected
lbz r3, ODB_IS_DISCONNECT_STATE_DISPLAYED(REG_ODB_ADDRESS)
cmpwi r3, 0
li r4, -3
bne OVERWRITE_WINNER_IDX
lbz r3, ODB_IS_DESYNC_STATE_DISPLAYED(REG_ODB_ADDRESS)
cmpwi r3, 0
li r4, -2
bne OVERWRITE_WINNER_IDX
b SKIP_OVERWRITE_WINNER_IDX
OVERWRITE_WINNER_IDX:
stb r4, RGB_WINNER_IDX(REG_RGB_ADDR)
SKIP_OVERWRITE_WINNER_IDX:

# Output the game end method and lras initiator
load r4, 0x8046b6a0
lbz r3, 0x8(r4)
stb r3, RGB_GAME_END_METHOD(REG_RGB_ADDR)
cmpwi r3, 0x7
bne NO_LRAS
lbz r3, 0x1(r4)
b STORE_LRAS_INITIATOR
NO_LRAS:
li r3, -1
STORE_LRAS_INITIATOR:
stb r3, RGB_LRAS_INITIATOR(REG_RGB_ADDR)

# Write synced timer for desync recovery
lwz r4, ODB_DESYNC_RECOVERY_TIMER(REG_ODB_ADDRESS)
stw r4, RGB_SYNCED_TIMER(REG_RGB_ADDR)

PLAYER_LOOP_INIT:
li REG_IDX, 0
addi REG_RGPB_ADDR, REG_RGB_ADDR, RGB_P1_RGPB

PLAYER_LOOP:
mr r3, REG_IDX
branchl r12, PlayerBlock_LoadStaticBlock

# Store isActive
lwz r4, 0x8(r3)
stb r4, RGPB_SLOT_TYPE(REG_RGPB_ADDR)

# Store stocks remaining
lbz r4, 0x8E(r3)
stb r4, RGPB_STOCKS_REMAINING(REG_RGPB_ADDR)

# Store damage done
lwz r4, 0xC6C+188(r3)
stw r4, RGPB_DAMAGE_DONE(REG_RGPB_ADDR)

# Write synced stocks and percents for desync recovery
mulli r5, REG_IDX, DFRE_SIZE
addi r4, r5, ODB_DESYNC_RECOVERY_FIGHTER_ARR + DFRE_STOCKS_REMAINING
lbzx r4, REG_ODB_ADDRESS, r4
stb r4, RGPB_SYNCED_STOCKS(REG_RGPB_ADDR)
addi r4, r5, ODB_DESYNC_RECOVERY_FIGHTER_ARR + DFRE_PERCENT
lhzx r4, REG_ODB_ADDRESS, r4
sth r4, RGPB_SYNCED_DAMAGE(REG_RGPB_ADDR)

PLAYER_LOOP_INC:
addi REG_IDX, REG_IDX, 1
addi REG_RGPB_ADDR, REG_RGPB_ADDR, RGPB_SIZE

PLAYER_LOOP_CHECK:
cmpwi REG_IDX, 4
blt PLAYER_LOOP

# Copy over game info
addi r3, REG_RGB_ADDR, RGB_GAME_INFO_BLOCK # Destination
load r4, 0x80480530 # Game info block source
li r5, MATCH_STRUCT_LEN
branchl r12, memcpy

# Execute match reporting
mr r3, REG_RGB_ADDR
li r4, RGB_SIZE
li r5, CONST_ExiWrite
branchl r12, FN_EXITransferBuffer

REPORT_GAME_EXIT:

restore

blr


GECKO_EXIT:
b PEPPY_END


################################################################################
# Single exit for both paths
################################################################################
PEPPY_END:
restore
