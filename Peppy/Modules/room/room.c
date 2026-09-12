/* Peppy's room screen.
 *
 * Its own scene (global minor 0x51, minor 6 of the online major), so none of
 * Slippi's screens are touched: the character select keeps SlippiCSS.dat and
 * its rank and chat overlay, and only shows up later, once two people are
 * matched, doing its normal job.
 *
 * Scene 0x51 has no Melee functions behind it -- the whole screen is this
 * module.  Text only for now; the layout is the part worth getting right
 * first, and artwork can be built up over it later without moving any of it.
 */
#include "peppy.h"

#define LOG_NOTICE 1

PEPPY_DEFINE_EXI_BUF;

static void peppy_log(const char *msg)
{
    u8 *buf = peppy_exi_buf;
    int i;

    buf[0] = 0xD0;        /* CMD_LOG_MESSAGE */
    buf[1] = 0;
    buf[2] = LOG_NOTICE;
    for (i = 0; i < PEPPY_EXI_BUF_SIZE - 4 && msg[i]; i++)
        buf[3 + i] = (u8)msg[i];
    buf[3 + i] = 0;
    FN_EXITransferBuffer(buf, PEPPY_EXI_BUF_SIZE, CONST_ExiWrite);
}

/* ------------------------------------------------------------------ layout */

/* Canvas space, the same one the CSS text uses:
 *     screen_x = 961 + 1.886 * canvas_x   ->  x spans about -509 .. 509
 *     screen_y = 594 + 1.886 * canvas_y   ->  y spans about -315 .. 258     */
#define COL_LEFT     (-430.0f)   /* queue column */
#define COL_RIGHT      (40.0f)   /* lobby column */
#define ROW_STEP       (26.0f)

#define Y_TITLE      (-250.0f)
#define Y_HEADING    (-180.0f)
#define Y_FIRST_NAME (-140.0f)
#define Y_ACTIONS      (120.0f)

#define SIZE_TITLE      0.70f
#define SIZE_HEADING    0.50f
#define SIZE_NAME       0.45f
#define SIZE_ACTION     0.50f

#define QUEUE_ROWS   6
#define LOBBY_ROWS   6

static const u8 COL_WHITE[4] = {0xFF, 0xFF, 0xFF, 0xFF};
static const u8 COL_GRAY[4]  = {0x8E, 0x91, 0x96, 0xFF};
static const u8 COL_GOLD[4]  = {0xF5, 0xC4, 0x42, 0xFF};

/* Text struct fields Melee expects set before anything is drawn, taken from
 * the values Slippi's own CSS text uses. */
#define TEXT_Z          0.0f
#define TEXT_CANVAS     0.1f
#define TEXT_OFS_Z      0x08
#define TEXT_OFS_SCALEX 0x24
#define TEXT_OFS_SCALEY 0x28
#define TEXT_OFS_KERN   0x49
#define TEXT_OFS_ALIGN  0x4A

static void *s_text;

static void peppy_room_build(void)
{
    void *text = Text_CreateStruct(0, 0);

    if (!text)
        return;
    s_text = text;

    *(u8 *)((char *)text + TEXT_OFS_KERN)  = 1;
    *(u8 *)((char *)text + TEXT_OFS_ALIGN) = 0;
    *(float *)((char *)text + TEXT_OFS_Z)      = TEXT_Z;
    *(float *)((char *)text + TEXT_OFS_SCALEX) = TEXT_CANVAS;
    *(float *)((char *)text + TEXT_OFS_SCALEY) = TEXT_CANVAS;

    /* Probe, not layout. The room laid out at canvas (-430, -250) drew
     * nothing, but those numbers were measured off the CHARACTER SELECT's
     * camera, and canvas coordinates are camera-relative -- on this scene's
     * camera the same numbers could put every line off screen. Markers at
     * known positions and sizes say which it is: if any of them appear, the
     * text renders fine and only the mapping is wrong. */
    FG_CreateSubtext(text, COL_WHITE, PEPPY_SUBTEXT_PLAIN, 0,
                     "CENTRE", 1.0f, 0.0f, 0.0f);
    FG_CreateSubtext(text, COL_GOLD, PEPPY_SUBTEXT_PLAIN, 0,
                     "LEFT", 1.0f, -200.0f, 0.0f);
    FG_CreateSubtext(text, COL_GOLD, PEPPY_SUBTEXT_PLAIN, 0,
                     "RIGHT", 1.0f, 200.0f, 0.0f);
    FG_CreateSubtext(text, COL_GRAY, PEPPY_SUBTEXT_PLAIN, 0,
                     "UP", 1.0f, 0.0f, -200.0f);
    FG_CreateSubtext(text, COL_GRAY, PEPPY_SUBTEXT_PLAIN, 0,
                     "DOWN", 1.0f, 0.0f, 200.0f);
    /* And one at the scale the CSS text uses, in case 1.0 is enormous here. */
    FG_CreateSubtext(text, COL_WHITE, PEPPY_SUBTEXT_PLAIN, 0,
                     "small centre", 0.05f, 0.0f, 30.0f);
}

/* ----------------------------------------------------------------- exports */

void peppy_room_think(void)
{
}

void peppy_room_load(void)
{
    /* A text object registers its own draw callback but still needs a camera
     * and a render pass to be drawn into, and nothing sets those up for a
     * scene invented from nothing -- which is why the first build of this ran
     * at 60fps and showed a black screen.
     *
     * Coming Soon supplied a camera and its own artwork drew, but our text did
     * not, so the text sits on a GXLink that camera does not cover.  The debug
     * menu is the one scene that is nothing but menu text, so its camera
     * covers the link menu text uses. */
    SceneLoad_ComingSoon();

    s_text = 0;
    peppy_room_build();
    peppy_log(s_text ? "Peppy: room scene built"
                     : "Peppy: room scene FAILED to make a text struct");
}

void peppy_room_leave(void)
{
    SceneLeave_ComingSoon();
}
