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

/* Canvas space on this camera, measured off the probe markers rather than
 * assumed: canvas (0,0) lands near the TOP-LEFT of the picture, about screen
 * (300, 3), and +y runs down -- not the centre-origin the character select
 * uses.  That is why the first layout, written in the CSS's coordinates with
 * negative values, put every line off the top-left corner.
 *
 * At a canvas scale of 1.0 a unit is roughly 2 screen pixels, and the game
 * renders 4:3 between screen x 300 and 1620, so usable canvas is about
 * x 40..640, y 40..520.  Glyph height is roughly 80 * size. */
#define COL_LEFT        40.0f    /* queue column */
#define COL_RIGHT      330.0f    /* lobby column */
#define ROW_STEP        22.0f

#define Y_TITLE         40.0f
#define Y_HEADING      105.0f
#define Y_FIRST_NAME   145.0f
#define Y_ACTIONS      310.0f

#define SIZE_TITLE      0.55f
#define SIZE_HEADING    0.40f
#define SIZE_NAME       0.32f
#define SIZE_ACTION     0.38f

#define QUEUE_ROWS   6
#define LOBBY_ROWS   6

static const u8 COL_WHITE[4] = {0xFF, 0xFF, 0xFF, 0xFF};
static const u8 COL_GRAY[4]  = {0x8E, 0x91, 0x96, 0xFF};
static const u8 COL_GOLD[4]  = {0xF5, 0xC4, 0x42, 0xFF};

/* Text struct fields Melee expects set before anything is drawn, taken from
 * the values Slippi's own CSS text uses. */
#define TEXT_Z          0.0f
/* Measured off the probe: at 0.1 this camera gave about 0.2px per canvas
 * unit, against 1.886 on the character select - the markers landed in a corner
 * a few pixels across. Ten times that puts the two in the same ballpark. */
#define TEXT_CANVAS     1.0f
#define TEXT_OFS_Z      0x08
#define TEXT_OFS_SCALEX 0x24
#define TEXT_OFS_SCALEY 0x28
#define TEXT_OFS_KERN   0x49
#define TEXT_OFS_ALIGN  0x4A

static void *s_text;

static void peppy_room_build(void)
{
    void *text = Text_CreateStruct(0, 0);
    int i;

    if (!text)
        return;
    s_text = text;

    *(u8 *)((char *)text + TEXT_OFS_KERN)  = 1;   /* close kerning */
    *(u8 *)((char *)text + TEXT_OFS_ALIGN) = 0;   /* align left   */
    *(float *)((char *)text + TEXT_OFS_Z)      = TEXT_Z;
    *(float *)((char *)text + TEXT_OFS_SCALEX) = TEXT_CANVAS;
    *(float *)((char *)text + TEXT_OFS_SCALEY) = TEXT_CANVAS;

    FG_CreateSubtext(text, COL_GOLD, PEPPY_SUBTEXT_PLAIN, 0,
                     "PEPPY ROOM", SIZE_TITLE, COL_LEFT, Y_TITLE);

    FG_CreateSubtext(text, COL_WHITE, PEPPY_SUBTEXT_PLAIN, 0,
                     "QUEUE", SIZE_HEADING, COL_LEFT, Y_HEADING);
    FG_CreateSubtext(text, COL_WHITE, PEPPY_SUBTEXT_PLAIN, 0,
                     "LOBBY", SIZE_HEADING, COL_RIGHT, Y_HEADING);

    /* Placeholders until the roster is wired in, so the shape of the screen is
     * visible and the per-frame update only ever rewrites contents. */
    for (i = 0; i < QUEUE_ROWS; i++)
        FG_CreateSubtext(text, COL_WHITE, PEPPY_SUBTEXT_PLAIN, 0,
                         i == 0 ? "1. Alpha" : "",
                         SIZE_NAME, COL_LEFT, Y_FIRST_NAME + ROW_STEP * i);
    for (i = 0; i < LOBBY_ROWS; i++)
        FG_CreateSubtext(text, COL_GRAY, PEPPY_SUBTEXT_PLAIN, 0, "",
                         SIZE_NAME, COL_RIGHT, Y_FIRST_NAME + ROW_STEP * i);

    FG_CreateSubtext(text, COL_WHITE, PEPPY_SUBTEXT_PLAIN, 0,
                     "START    Join Queue", SIZE_ACTION, COL_LEFT, Y_ACTIONS);
    FG_CreateSubtext(text, COL_GRAY, PEPPY_SUBTEXT_PLAIN, 0,
                     "X        Spectate", SIZE_ACTION, COL_LEFT,
                     Y_ACTIONS + ROW_STEP);
    FG_CreateSubtext(text, COL_GRAY, PEPPY_SUBTEXT_PLAIN, 0,
                     "Z        Training", SIZE_ACTION, COL_LEFT,
                     Y_ACTIONS + ROW_STEP * 2);
}

/* ----------------------------------------------------------------- exports */

void peppy_room_think(void)
{
    /* Deliberately not SceneThink_ClassicModeSplash: its Load is what sets the
     * scene up, its Think animates the splash toward a match and reads data a
     * room does not have, which is the invalid read a few seconds in. */
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
     * Four bases tried: Coming Soon gives a camera but no text; the debug menu
     * dies on an invalid read; the main menu simply puts you back in the menu.
     * The splash is the one where our text renders, so it stays until the room
     * builds a camera of its own.  Its artwork showing through is cosmetic and
     * the next thing to go. */
    SceneLoad_ComingSoon();

    s_text = 0;
    peppy_room_build();
    /* Coming Soon renders Melee's own artwork but never our text, so either
     * the text object is on a render link that camera does not cover, or the
     * struct never got any glyph data.  Text_CreateStruct ends by reading the
     * struct's id at +0x4F, looking it up in the table at 0x804D1124 and
     * storing the result at +0x5C - a null there says the text has nothing to
     * draw with and the camera was never the problem. */
    {
        char line[96];
        char *p = line;
        u8 id = s_text ? *(u8 *)((char *)s_text + 0x4F) : 0;
        u32 slot = *(u32 *)(0x804D1124 + 4 * (u32)id);
        u32 data = s_text ? *(u32 *)((char *)s_text + 0x5C) : 0;

        p = put(p, "Peppy: text=");
        p = put_hex(p, (u32)s_text);
        p = put(p, " id=");
        p = put_u8(p, id);
        p = put(p, " table=");
        p = put_hex(p, slot);
        p = put(p, " data=");
        p = put_hex(p, data);
        *p = 0;
        peppy_log(line);
    }
}

void peppy_room_leave(void)
{
}
