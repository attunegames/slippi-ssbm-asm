#!/usr/bin/env python3
"""Regenerate Peppy/Playback/StartMelee.asm from the two upstream originals.

Slippi ships two different codes at 0x8016e748, one per codeset. Peppy builds a
single codeset that can do both, so the two bodies get spliced into one file
that dispatches on the scene. Run this from the repo root after either original
changes, then re-check the boundary line numbers below.
"""
import os

PB = "Playback/Core/StartMelee/RestoreGameInfo.asm"
ON = "Online/Superseded/InitOnlinePlay.asm"
OUT = "Peppy/Playback/StartMelee.asm"

# Line numbers (1-indexed, inclusive) of the pieces we keep from each original.
# Everything left out is a line this wrapper now owns: the replaced branchl, the
# backup, the online scene check, and the trailing restore.
PB_SETS, PB_BODY = (15, 17), (28, 402)   # body ends on "Injection_Exit:"
ON_SETS, ON_BODY = (8, 14), (25, 461)    # body ends on "GECKO_EXIT:"


def span(lines, bounds):
    a, b = bounds
    return "\n".join(lines[a - 1:b])


def check(lines, bounds, expect_last, name):
    if lines[bounds[1] - 1].strip() != expect_last:
        raise SystemExit(
            "%s: expected body to end on %r, found %r - the original moved, "
            "fix the line numbers in this script" %
            (name, expect_last, lines[bounds[1] - 1].strip()))


def main():
    pb = open(PB).read().split("\n")
    on = open(ON).read().split("\n")
    check(pb, PB_BODY, "Injection_Exit:", PB)
    check(on, ON_BODY, "GECKO_EXIT:", ON)

    out = HEADER
    out += span(on, ON_SETS) + "\n"
    out += SETS_PB
    out += span(pb, PB_SETS) + "\n"
    out += PROLOGUE
    out += span(pb, PB_BODY) + "\nb PEPPY_END\n"
    out += ONLINE_BANNER
    out += span(on, ON_BODY) + "\nb PEPPY_END\n"
    out += EPILOGUE
    open(OUT, "w").write(out)
    print("wrote %s (%d lines)" % (OUT, out.count("\n") + 1))


HEADER = '''################################################################################
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
'''

SETS_PB = '''
################################################################################
# Register names - from Playback/Core/StartMelee/RestoreGameInfo.asm
################################################################################
'''

PROLOGUE = '''
################################################################################
# Replaced codeline, call function. Runs once, for either path.
################################################################################
branchl r12, 0x802254B8

backup

################################################################################
# Dispatch on the scene we are in
################################################################################
getMinorMajor r3
logf LOG_LEVEL_WARN, "[Peppy] StartMelee: scene=%x (online=0208 playback=010e)", "mr r5, r3"

getMinorMajor r3
cmpwi r3, SCENE_ONLINE_IN_GAME
beq PEPPY_PATH_ONLINE
cmpwi r3, SCENE_PLAYBACK_IN_GAME
beq PEPPY_PATH_PLAYBACK

logf LOG_LEVEL_WARN, "[Peppy] StartMelee: neither path - doing nothing"
b PEPPY_END


################################################################################
################################################################################
##  PLAYBACK PATH - verbatim from Playback/Core/StartMelee/RestoreGameInfo.asm
################################################################################
################################################################################
PEPPY_PATH_PLAYBACK:
logf LOG_LEVEL_WARN, "[Peppy] StartMelee: playback path"
'''

ONLINE_BANNER = '''

################################################################################
################################################################################
##  ONLINE PATH - verbatim from Online/Superseded/InitOnlinePlay.asm
################################################################################
################################################################################
PEPPY_PATH_ONLINE:
logf LOG_LEVEL_WARN, "[Peppy] StartMelee: online path"
'''

EXIT_LOG = """
logf LOG_LEVEL_WARN, "[Peppy] StartMelee: online path finished"
"""

EPILOGUE = '''

################################################################################
# Single exit for both paths
################################################################################
PEPPY_END:
restore
'''

if __name__ == "__main__":
    main()
