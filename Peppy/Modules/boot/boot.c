/* Smoke test for the m-ex module pipeline, stage 1: pass-through only.
 *
 * Three exports that do nothing but jump to the scene functions they replace.
 * At -O2 each compiles to a single tail-call branch, so no register is
 * touched and the scene behaves exactly as it does with no module attached.
 *
 * The point is to separate two failures that look identical from outside: a
 * module the loader cannot handle, and a module whose own code is wrong. If
 * the main menu comes up normally with this attached, then finding, loading,
 * relocating and calling all work, and anything that breaks afterwards is
 * ours. If it still hangs, the format is wrong and no amount of care in the
 * C will help.
 *
 * Exports map to the scene table's three function slots in order --
 * {Think, Load, Leave}.
 */
#include "peppy.h"

void peppy_boot_think(void)
{
    SceneThink_MainMenu();
}

void peppy_boot_load(void)
{
    SceneLoad_MainMenu();
}

void peppy_boot_leave(void)
{
    /* The main menu's Leave slot is null in the scene table: nothing to
     * chain to, and nothing to do. */
}
