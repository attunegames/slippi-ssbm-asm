/* Smoke test for the m-ex module pipeline.
 *
 * Attached to the main menu scene so it runs on every launch with no
 * navigation: if the line shows up in Dolphin's log, then the module was
 * found, loaded, relocated and called, and its code reached both Melee and
 * the codeset's injected helpers.  That is the whole pipeline in one signal.
 *
 * Exports map to the scene table's three function slots in order --
 * {Think, Load, Leave} -- and a module replaces the slot rather than being
 * chained onto it, so each export calls the original itself.
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
    SceneThink_MainMenu();

    /* Announce from Think rather than Load: by the first frame the scene is
     * fully built, and once per launch keeps the main menu -- which is
     * re-entered constantly -- from burying the log. */
    if (!announced)
    {
        char line[80];
        char *p = line;

        announced = 1;

        /* Reading the scene controller proves the module can reach Melee's
         * globals, not just call into its code. */
        p = put(p, "Peppy: m-ex module loaded (major ");
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
    SceneLoad_MainMenu();
}

void peppy_boot_leave(void)
{
}
