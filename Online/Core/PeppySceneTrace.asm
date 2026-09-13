################################################################################
# Address: 0x801a4034
################################################################################

# Diagnosis only.
#
# This is the top of Melee's minor-scene change, where it reads the minor it is
# being asked for and goes looking for a descriptor. When it finds none it does
# not stop - it carries on with a null descriptor and calls a function pointer
# read out of address 8, which is the "Unknown instruction at PC = 010000fc"
# crash.
#
# A catch-all entry in the table does not help, because the lookup gives up
# before it scans at all when the id is 0xFF or above. So the question is what
# id is being asked for, and this says it.
#
# r31 is the scene controller at 0x80479d30; byte 3 is the minor being changed
# to, byte 0 the major.

.include "Common/Common.s"

backup
logf LOG_LEVEL_NOTICE, "Peppy: scene change - major %d", "lbz r5, 0x0(r31)"
logf LOG_LEVEL_NOTICE, "Peppy: scene change - minor %d", "lbz r5, 0x3(r31)"
logf LOG_LEVEL_NOTICE, "Peppy: scene change - pending %d", "lbz r5, 0x5(r31)"
restore

# Original
lbz r4, 0x3(r31)
