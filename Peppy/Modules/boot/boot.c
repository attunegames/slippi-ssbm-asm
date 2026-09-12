/* Smoke test for the m-ex module pipeline.
 *
 * Hooks the CSS (minor scene 0x08), not the main menu.  A module attached to
 * the main menu takes the game down before it draws a frame -- the same
 * MxScn.dat edit pointed at a scene that is never entered boots fine at 60fps,
 * and a 12-byte pass-through fails there exactly like a full one, so it is the
 * timing of that scene rather than the table or the module.  Nothing in Slippi
 * hangs a module off the main menu either: theirs go on the CSS and on a scene
 * they invented.
 *
 * Exports map to the scene table's three function slots in order --
 * {Think, Load, Leave} -- and the loader *replaces* those slots rather than
 * chaining onto them, so each export calls the original itself.
 *
 * If the line shows up in Dolphin's log then the module was found, loaded,
 * relocated and called, its code reached both Melee and the codeset's injected
 * helpers, and it can read Melee's globals.  That is the whole pipeline in one
 * signal.
 */
#include "peppy.h"

#define LOG_NOTICE 1

PEPPY_DEFINE_EXI_BUF;

/* Matches the logf macro in Common/Common.s: the device reads a fixed buffer
 * and treats everything from byte 3 on as the message. */
static void peppy_log(const char *msg)
{
    u8 *buf = peppy_exi_buf;
    int i;

    buf[0] = 0xD0;        /* CMD_LOG_MESSAGE */
    buf[1] = 0;           /* do not append a timestamp */
    buf[2] = LOG_NOTICE;

    for (i = 0; i < PEPPY_EXI_BUF_SIZE - 4 && msg[i]; i++)
        buf[3 + i] = (u8)msg[i];
    buf[3 + i] = 0;

    FN_EXITransferBuffer(buf, PEPPY_EXI_BUF_SIZE, CONST_ExiWrite);
}

static char *put(char *p, const char *s)
{
    while (*s)
        *p++ = *s++;
    return p;
}

static char *put_u8(char *p, u8 v)
{
    if (v >= 100)
        *p++ = (char)('0' + v / 100);
    if (v >= 10)
        *p++ = (char)('0' + (v / 10) % 10);
    *p++ = (char)('0' + v % 10);
    return p;
}

static int announced;

void peppy_boot_think(void)
{
    SceneThink_CSS();

    /* Announce from Think rather than Load: by the first frame the scene is
     * fully built.  Once per launch, so re-entering the CSS between matches
     * does not bury the log. */
    if (!announced)
    {
        char line[96];
        char *p = line;

        announced = 1;

        /* Reading the scene controller proves the module can reach Melee's
         * globals, not just call into its code. */
        p = put(p, "Peppy: m-ex module running on the CSS (major ");
        p = put_u8(p, SCENE_CTRL.major);
        p = put(p, ", minor ");
        p = put_u8(p, SCENE_CTRL.minor);
        p = put(p, ") -- pipeline OK");
        *p = 0;

        peppy_log(line);
    }
}

void peppy_boot_load(void)
{
    SceneLoad_CSS();
}

void peppy_boot_leave(void)
{
    SceneLeave_CSS();
}
