################################################################################
# Address: 0x8022e93c # SceneLoad_MainMenu
################################################################################
# Some events like returning from an Event Match jump to line 8022e930 and
# skip the previous calls, putting this initialization way at the end
# so that it will not be skipped

.include "Common/Common.s"
.include "Online/Online.s"

# Peppy: entering Slippi's replay playback from the menu.
.set ADDR_MajorStruct_DebugMelee, 0x803dada8
.set SCENE_MAJOR_DEBUG_MELEE, 0xE
.set MINOR_PLAYBACK_ENTRY, 0x3
# Slippi's Change Debug Result Screen MinorType to Debug Menu, the half that does
# not survive to the menu. Same address and value as their gecko code.
.set SCENE_MAJOR_MAIN_MENU, 0x1
.set PB_STATE_IDLE, 0
.set PB_STATE_ARMED, 1
.set PB_STATE_HOLDING, 2
.set PB_SCENEPREP_SLOT, 0x801b16a8
.set PB_SCENEPREP_DEBUGMENU, 0x801b09c0
# A peek at whether a replay is queued. Deliberately NOT
# CONST_SlippiCmdCheckForReplay (0x88): that one loads the game and marks it
# played, and the playback scene polls 0x88 itself in a loop - asking it here
# would leave that loop waiting forever on a replay already loaded behind it.
.set CONST_PeppyCmdReplayWaiting, 0xCA
.set MenuController_WriteToPendingMajor_1to_0xC, 0x801A42F8
.set Scene_ExitMinor, 0x801A4B60
.set Scene_GetMajorSceneStruct, 0x801A50AC
.set Scene_MinorIDToMinorSceneFunctionTable, 0x801A4CE0
.set Scene_GetMinorSceneFunctionListStart, 0x801A50A0

b CODE_START

DATA_USER_TEXT_BLRL:
blrl
.float -204 # X Pos of User Display, 0x0
.float -157 # Y Pos of User Display, 0x4
.float 17 # Z Offset, 0x8
.float 0.06 # Scaling, 0xC

DATA_BLRL:
blrl
.set DOFST_IS_FIRST_BOOT, 0
.byte 1
.align 2

CODE_START:
.set REG_FG_USER_DISPLAY, 30
.set REG_DATA_ADDR, 29
.set REG_TXB_ADDR, 28
.set REG_PB_ANSWER, 27
.set REG_PB_DATA, 26
.set REG_PB_MAJOR, 25
.set REG_PB_SCENE, 24

backup

################################################################################
# Section 1: Skip User display init on the main menu
################################################################################
# Intentionally disabled so "User" + logged in name are not shown on title menu.
# Other scenes (like CSS/ranked) initialize their own user display separately.

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

################################################################################
# Section 4: Peppy - the playback handover used to live here
################################################################################
# It cannot work from the main menu. Melee's main menu decides its own next
# major, so the request was overridden every time: the write landed (pending
# 0e, exit flag 1) and the game still came up on major 18. Forcing the byte from
# Dolphin did not help either - the game overwrote it with 18 itself, which says
# the destination is not read from there at all. And Scene_ExitMinor destroys
# the scheduling GObj in the same frame, so nothing survived to say it twice.
#
# It now lives in Online/Menus/CSS/HandleInputsOnCSS.asm, inside the online
# major, where the same pair is already known to work - it is how
# peppy_room_exit_room leaves that major. That is also where the trigger
# belongs: spectating starts because you are queued.


restore

EXIT:
lmw r14, 0x0408 (sp)
