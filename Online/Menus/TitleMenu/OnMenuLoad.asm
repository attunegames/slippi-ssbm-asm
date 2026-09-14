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
# A peek at whether a replay is queued. Deliberately NOT
# CONST_SlippiCmdCheckForReplay (0x88): that one loads the game and marks it
# played, and the playback scene polls 0x88 itself in a loop - asking it here
# would leave that loop waiting forever on a replay already loaded behind it.
.set CONST_PeppyCmdReplayWaiting, 0xCA
.set MenuController_WriteToPendingMajor_1to_0xC, 0x801A42F8
.set Scene_ExitMinor, 0x801A4B60

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
# Section 4: Peppy - jump into Slippi's replay playback if one is waiting
################################################################################
# Slippi enters playback by hijacking boot (Playback/Core/Scene/Boot). That code
# is built but left disabled, because it takes the whole build with it: a build
# that boots into playback can never reach Peppy. We open the same door from the
# menu instead, so one build does both.
#
# The check cannot happen here. This runs inside the scene's LOAD, and ending a
# major only takes effect once a minor's Think has finished - at load there is no
# minor running to end, so the request is simply lost and the menu carries on.
# That is exactly what the first attempt did. So load schedules a per-frame
# function instead, the same way SceneThink_Playback schedules its own, and the
# work happens in the think where it can actually take.

#Create GObj
li r3, 13
li r4, 14
li r5, 0
branchl r12, GObj_Create

#Schedule our think
bl PEPPY_PLAYBACK_THINK
mflr r4
li r5, 0
branchl r12, GObj_AddProc

b PEPPY_PLAYBACK_SCHEDULED


################################################################################
# Runs once a frame while the menu is up.
################################################################################
PEPPY_PLAYBACK_THINK:
blrl

backup

# Ask Dolphin whether a replay is queued. CONST_PeppyCmdReplayWaiting is a peek:
# deliberately NOT CONST_SlippiCmdCheckForReplay (0x88), which loads the game and
# marks it played. SceneThink_Playback polls 0x88 itself in a loop, so asking it
# here would strand that loop waiting forever on a replay already loaded.
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
# the condition register, and testing after it tests the wrong thing.
lbz REG_PB_ANSWER, 0(REG_TXB_ADDR)
mr r3, REG_TXB_ADDR
branchl r12, HSD_Free

cmpwi REG_PB_ANSWER, 1
bne PEPPY_PLAYBACK_THINK_EXIT

logf LOG_LEVEL_WARN, "[Peppy] Replay is ready - leaving the menu for the playback major"

# The playback scene lives in the DebugMelee major, and Slippi's boot code points
# that major's load at the right minor on the way in. We are not using that code,
# so we register the same callback ourselves. Everything it runs afterwards is
# Slippi's, untouched.
bl PEPPY_PB_MAJOR_LOAD
mflr r3
load r4, ADDR_MajorStruct_DebugMelee
stw r3, 0x4(r4)

# Ending the major: name the one to go to next AND flag this one, then end the
# minor. Scene_ProcessMajor only looks at the flag between minors, so without the
# second half the menu sits there having already been told to leave.
li r3, SCENE_MAJOR_DEBUG_MELEE
branchl r12, MenuController_WriteToPendingMajor_1to_0xC
branchl r12, Scene_ExitMinor

PEPPY_PLAYBACK_THINK_EXIT:
restore
blr


PEPPY_PB_MAJOR_LOAD:
blrl
# Runs as the DebugMelee major loads. The playback scene is its result-screen
# minor - Playback/Core/Scene/Change Debug Result Screen MinorType to Debug Menu
# is what makes that minor the playback one.
  li r3, MINOR_PLAYBACK_ENTRY
  load r4, 0x80479D30
  stb r3, 0x3(r4)
  blr

PEPPY_PLAYBACK_SCHEDULED:

restore

EXIT:
lmw r14, 0x0408 (sp)
