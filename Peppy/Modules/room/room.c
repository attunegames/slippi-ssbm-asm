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
#define X_BACK         520.0f    /* top right, where the CSS keeps its BACK */

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

/* Kept through the diagnostics coming and going: the roster needs them the
 * moment real names go into the columns. */
__attribute__((unused)) static char *put(char *p, const char *str)
{
    while (*str)
        *p++ = *str++;
    return p;
}

__attribute__((unused)) static char *put_u8(char *p, u8 v)
{
    if (v >= 100)
        *p++ = (char)('0' + v / 100);
    if (v >= 10)
        *p++ = (char)('0' + (v / 10) % 10);
    *p++ = (char)('0' + v % 10);
    return p;
}

__attribute__((unused)) static char *put_hex(char *p, u32 v)
{
    static const char digits[] = "0123456789abcdef";
    int i;

    for (i = 28; i >= 0; i -= 4)
        *p++ = digits[(v >> i) & 0xF];
    return p;
}

#define STR_JOIN      "Press START to Join the Queue"
#define STR_PRACTICE  "Press START to Practice"

static void *s_text;
static int s_queue_line = -1;
static int s_queued;

/* Called when the queue state changes; the roster will drive this once it is
 * wired up. */
void peppy_room_set_queued(int queued)
{
    if (!s_text || s_queue_line < 0 || queued == s_queued)
        return;
    s_queued = queued;
    Text_UpdateSubtextContents(s_text, s_queue_line,
                               queued ? STR_PRACTICE : STR_JOIN);
}

/* The room borrows the splash's camera, and the splash's artwork comes with it.
 * The census says our text is alone in class 0 and the cameras are class 20, so
 * everything else on the scene belongs to the splash and can go - which leaves
 * a camera, a render pass, and the room's own text on a clean background.
 *
 * Take the next pointer before destroying, or the walk follows a freed object. */
#define PEPPY_CLASS_TEXT    0
#define PEPPY_CLASS_CAMERA  20

static void peppy_room_clear_borrowed_scene(void)
{
    void **heads = peppy_gobj_heads();
    int c;

    for (c = 0; c < 64; c++)
    {
        void *g;

        if (c == PEPPY_CLASS_TEXT || c == PEPPY_CLASS_CAMERA)
            continue;

        g = heads[c];
        while (g)
        {
            void *next = *(void **)((char *)g + PEPPY_GOBJ_NEXT);

            GObj_Destroy(g);
            g = next;
        }
    }
}

/* The spectator split: the match in the top half, the room's furniture below.
 *
 * The text follows the camera - squeezing every camera took the whole room with
 * it - so the two halves have to be different cameras.  No new camera is
 * needed: CObj_RenderGXLinks walks a 64-bit mask at gobj+0x20, and on this
 * scene the cameras came out as
 *
 *     cam0 nothing   cam1 link 14   cam2 links 0 and 11
 *
 * with our text on link 0.  So the rule is general and needs no hard-coded
 * indices: whichever camera draws the text link gets the bottom half, and
 * every other camera gets the top.
 *
 * Players are not split at all - they get Melee's screens full size, untouched.
 */
/* Which camera actually draws the text?
 *
 * Its link is 0 and only one camera's mask has bit 0, yet giving that camera
 * the bottom half left the text at the top - while squeezing every camera did
 * move it.  So the mask is not telling the whole story.  Give each camera a
 * different third of the screen: wherever the text lands names its camera,
 * with no inference involved.
 */
static void peppy_room_thirds(void)
{
    void **heads = peppy_gobj_heads();
    void *g = heads[PEPPY_CLASS_CAMERA];
    int i = 0;

    while (g)
    {
        void *cobj = *(void **)((char *)g + PEPPY_GOBJ_OBJECT);
        float top = (float)(PEPPY_SCREEN_H / 3 * i);
        float bot = (float)(PEPPY_SCREEN_H / 3 * (i + 1));

        if (cobj && i < 3)
        {
            CObj_SetViewport(cobj, 0.0f, (float)PEPPY_SCREEN_W, top, bot);
            CObj_SetScissor(cobj, 0, PEPPY_SCREEN_W, (int)top, (int)bot);
        }
        i++;
        g = *(void **)((char *)g + PEPPY_GOBJ_NEXT);
    }
}

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

    for (i = 0; i < QUEUE_ROWS; i++)
        FG_CreateSubtext(text, COL_WHITE, PEPPY_SUBTEXT_PLAIN, 0,
                         i == 0 ? "1. Alpha" : "",
                         SIZE_NAME, COL_LEFT, Y_FIRST_NAME + ROW_STEP * i);
    for (i = 0; i < LOBBY_ROWS; i++)
        FG_CreateSubtext(text, COL_GRAY, PEPPY_SUBTEXT_PLAIN, 0, "",
                         SIZE_NAME, COL_RIGHT, Y_FIRST_NAME + ROW_STEP * i);

    /* Start is the only thing that changes: once you are in the queue it stops
     * offering to put you there and offers practice instead, which is where
     * waiting happens. Training is not a button of its own. */
    s_queue_line = FG_CreateSubtext(text, COL_WHITE, PEPPY_SUBTEXT_PLAIN, 0,
                                    STR_JOIN, SIZE_ACTION, COL_LEFT, Y_ACTIONS);
    FG_CreateSubtext(text, COL_GRAY, PEPPY_SUBTEXT_PLAIN, 0,
                     "Press Z to Spectate", SIZE_ACTION, COL_LEFT,
                     Y_ACTIONS + ROW_STEP);

    /* The character select's own BACK is part of that scene's artwork and does
     * not exist here, so this is the label in the same corner. B leaves the
     * room, and leaves the queue with it. */
    FG_CreateSubtext(text, COL_GRAY, PEPPY_SUBTEXT_PLAIN, 0,
                     "BACK", SIZE_HEADING, X_BACK, Y_TITLE);
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
    SceneLoad_ClassicModeSplash();

    peppy_room_clear_borrowed_scene();

    s_text = 0;
    s_queue_line = -1;
    s_queued = 0;
    peppy_room_build();
    peppy_room_thirds();
    peppy_log(s_text ? "Peppy: room scene built"
                     : "Peppy: room scene FAILED to make a text struct");
}

void peppy_room_leave(void)
{
}
