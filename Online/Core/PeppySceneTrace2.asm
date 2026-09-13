################################################################################
# Address: 0x801a4150
################################################################################

# Diagnosis only. See PeppySceneTrace.asm.
#
# The scene change is a loop: prep, load, think, decide, and then it reads the
# pending minor here and goes round again if it is set. The trace at the top of
# the routine only catches the first time through - a second lap re-enters below
# it, which is why the crash never showed up there.
#
# This is that second lap. r31 is the scene controller.

.include "Common/Common.s"

backup
logf LOG_LEVEL_NOTICE, "Peppy: another lap - pending %d", "lbz r5, 0x5(r31)"
restore

# Original
lbz r3, 0x5(r31)
