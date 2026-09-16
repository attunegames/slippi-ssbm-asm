################################################################################
# Address: 801a501c
################################################################################

# Injection is right before game engine loops
.include "Common/Common.s"
.include "Playback/Playback.s"
.include "Common/FastForward/FunctionMacros.s"

# Info provided by tauKhan, relevant for fast forwarding
# 801a4db0: transfer input queue count to r27
# 801a4de4: engine loop start
# 801a501c: Engine loop check against the initial queue count, loop end
# 801a5024: screen render start

# Only in the playback match, and asked through the constant.
#
# This used to test major 0xe and minor 0x1 as raw numbers. Watching moved under
# the online major and those numbers went stale, so the test never passed and
# the catch-up silently stopped: the replay still played, perfectly, just always
# behind the live game and never closing the gap.
#
# Both halves in one compare, the way every other playback guard does it, so the
# next time that scene moves this follows on its own.
  lis r4, 0x8048 # load address to offset from for scene controller
  lwz r3, -0x62D0(r4)
  rlwinm r3, r3, 8, 0xFFFF
  cmpwi r3, SCENE_PLAYBACK_IN_GAME
  bne- PreviousCodeLine

# ensure game is not paused
  li  r3,1
  branchl r12,CheckIfGameEnginePaused
  cmpwi r3,0x2
  beq PreviousCodeLine

# check status for fast forward
  lwz r3,playbackDataBuffer(r13) # directory address
  lwz r3,PDB_EXI_BUF_ADDR(r3) # EXI buf address
  lbz r3,(BufferStatus_Start)+(BufferStatus_Status)(r3)
  cmpwi r3, CONST_FrameFetchResult_FastForward
  beq FastForward # If we are not terminating, skip

# execute normal code line
PreviousCodeLine:
# unmute  music and SFX
  li  r3,1
  li  r4,2
  branchl r12,Audio_AdjustMusicSFXVolume
  cmpw r26, r27
  b Exit

FastForward:
# black screen
  #li  r3,1
  #branchl r12,VISetBlack
# mute music and SFX
  lwz r3,playbackDataBuffer(r13) # directory address
  lwz r3,PDB_EXI_BUF_ADDR(r3) # EXI buf address
  lbz r3,(RBStatus_Start)+(RBStatus_Status)(r3)
  cmpwi r3, 1
  beq SkipMute # If we are rb, skip mute

  li  r3,0
  li  r4,0
  branchl r12,Audio_AdjustMusicSFXVolume

SkipMute:
  bl FN_ExecCameraTasks_PLAYBACK

# do a stupid cmp operation so that the blt at 801a5020 will branch
  cmpwi r3, 0xFF
  b Exit

# Functions section
FunctionBody_ExecCameraTasks _PLAYBACK # Adds FN_ExecCameraTasks_PLAYBACK

Exit:
