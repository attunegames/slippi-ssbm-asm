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
.set Scene_GetMajorSceneStruct, 0x801A50AC

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
# that boots into playback can never reach Peppy. We open the same door here, so
# one build does both.
#
# Split in two on purpose.
#
# The ASK happens here, in the scene's load. One EXI transfer, once.
#
# The HANDOVER cannot happen here: ending a major only takes effect once a
# minor's Think has finished, and at load there is no minor running to end, so
# the request is dropped and the menu carries on. That was the first attempt.
#
# The second attempt moved the whole thing into a per-frame function, which did
# leave the menu - and then died in EXIDma with a bad DMA pointer, because the
# function kept running as the scene tore down, allocating a buffer and starting
# a transfer each frame against a heap that was going away. So the think does no
# EXI at all now: it reads a byte this code already fetched, and it fires once.

bl PEPPY_PB_DATA
mflr REG_PB_DATA

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
bne PEPPY_PLAYBACK_SCHEDULED

logf LOG_LEVEL_WARN, "[Peppy] A replay is queued - scheduling the handover"

# Arm the think and schedule it.
li r3, 1
stb r3, PB_DOFST_PENDING(REG_PB_DATA)

li r3, 13
li r4, 14
li r5, 0
branchl r12, GObj_Create

bl PEPPY_PLAYBACK_THINK
mflr r4
li r5, 0
branchl r12, GObj_AddProc

b PEPPY_PLAYBACK_SCHEDULED


################################################################################
# Runs once a frame while the menu is up. No EXI, no allocation - just the
# handover, once.
################################################################################
PEPPY_PLAYBACK_THINK:
blrl

backup

bl PEPPY_PB_DATA
mflr REG_PB_DATA
lbz r3, PB_DOFST_PENDING(REG_PB_DATA)
cmpwi r3, 1
bne PEPPY_PLAYBACK_THINK_EXIT

# Once. The scene is about to go away and this function will keep being called
# until it does.
li r3, 0
stb r3, PB_DOFST_PENDING(REG_PB_DATA)

logf LOG_LEVEL_WARN, "[Peppy] Leaving the menu for the playback major"

# The playback scene lives in the DebugMelee major, and Slippi's boot code points
# that major's load at the right minor on the way in. We are not using that code,
# so we register the same callback ourselves. Everything it runs afterwards is
# Slippi's, untouched.
# Ask the game where that major's struct is rather than hardcoding it. Slippi's
# boot code uses a fixed 0x803dada8, which is right in the playback build - but
# that build has no m-ex in it, and ours does, and m-ex rearranges Melee's scene
# tables. Writing a function pointer at a stale address is exactly the shape of
# the crash this hit: an immediate, deterministic bad pointer.
li r3, SCENE_MAJOR_DEBUG_MELEE
branchl r12, Scene_GetMajorSceneStruct
mr REG_PB_MAJOR, r3

logf LOG_LEVEL_WARN, "[Peppy] DebugMelee major struct at %x (Slippi hardcodes 803dada8)", "mr r5, REG_PB_MAJOR"

bl PEPPY_PB_MAJOR_LOAD
mflr r3
stw r3, 0x4(REG_PB_MAJOR)

# Ending the major: name the one to go to next AND flag this one, then end the
# minor. Scene_ProcessMajor only looks at the flag between minors, so without the
# second half the menu sits there having already been told to leave.
# Clear the pending minor first. room.c's exit_room does this before naming the
# next major and it is the only part of that known-good sequence this was
# missing; a stale pending minor is read by the incoming major's load.
load r4, 0x80479D30
li r3, 0
stb r3, 0x5(r4)

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

PEPPY_PB_DATA:
blrl
.set PB_DOFST_PENDING, 0
.byte 0
.align 2

PEPPY_PLAYBACK_SCHEDULED:

restore

EXIT:
lmw r14, 0x0408 (sp)
