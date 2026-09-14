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

/* Melee's training mode, which the room runs underneath itself. */
void MajorSetup_TrainingMode(void);
void MajorLoad_TrainingMode(void);
void SceneLoad_TrainingModeInGame(void *minor_data);
void SceneThink_TrainingModeInGame(void);

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
#define ROW_STEP        28.0f

/* The furniture lives in the bottom half now, so everything moves up and the
 * divider sits along its top edge with the two players' names on it. */
#define Y_DIVIDER       26.0f
#define Y_ROOM          66.0f    /* which room this is */
#define Y_HEADING      100.0f
#define Y_FIRST_NAME   132.0f
#define Y_ACTIONS      340.0f
#define ROW_ACTION      30.0f    /* gap between status lines */
#define X_SYMBOL        22.0f    /* line sits this far right of its symbol */
#define SIZE_SPINNER    0.45f    /* Slippi draws its symbols a little larger */
#define SPINNER_FRAMES    15     /* frames per icon, as Slippi spins it */

#define X_COUNT         74.0f    /* the number, just right of its heading */

#define X_P1           110.0f
#define X_VS           300.0f
#define X_P2           430.0f
#define X_BACK         560.0f    /* right end of the divider row */

/* No line primitive is available and the full-width block glyph draws nothing
 * here, so the divider is a run of hyphens - which are plain ASCII and do. */
#define DIVIDER "--------------------------------------------------------"

#define SIZE_TITLE      0.55f
#define SIZE_HEADING    0.40f
#define SIZE_NAME       0.32f
#define SIZE_ACTION     0.38f

#define BROWSE_ROWS  8           /* matches MSRB_ROOMLIST_SLOTS */
#define X_CURSOR        26.0f    /* the marker, left of the row */

#define QUEUE_ROWS   6
#define LOBBY_ROWS   6

static const u8 COL_WHITE[4] = {0xFF, 0xFF, 0xFF, 0xFF};
static const u8 COL_GRAY[4]  = {0x8E, 0x91, 0x96, 0xFF};
static const u8 COL_GOLD[4]  = {0xF5, 0xC4, 0x42, 0xFF};
/* Slippi's own two status colours, same values: green once a thing is done,
 * blue while it is still waiting on you. */
static const u8 COL_DONE[4]  = {0x33, 0xFF, 0x2F, 0xFF};
static const u8 COL_WAIT[4]  = {0x3C, 0xBC, 0xFF, 0xFF};

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

/* The room list this room came from, in the order the menu shows them. 0xFF is
 * a room that did not come from the menus at all - joined by code from
 * peppy.json, say - and has no list to name. */
static const char *const MODE_NAMES[] = {
    "SINGLES", "DOUBLES", "IRON MAN", "CREW BATTLES", "TOURNAMENTS"
};
#define MODE_COUNT ((int)(sizeof(MODE_NAMES) / sizeof(MODE_NAMES[0])))

/* The status block, built the way Slippi's character select builds its own:
 * a symbol in its own subtext, the line beside it, a colour per state.
 *
 * The symbols are Shift-JIS full-width punctuation, because this font has no
 * ASCII plus or asterisk - both draw nothing. The same three Slippi uses.
 */
#define SYM_TODO      "\x81\x7E"   /* multiplication sign - not done yet */
#define SYM_DONE      "\x81\x7C"   /* minus sign - done */
#define SYM_NEXT      "\x81\x7B"   /* plus sign - what you can do next */

#define STR_JOIN      "Press START to Join the Queue"
#define STR_IN_QUEUE  "In the Queue"
#define STR_PRACTICE  "Press START to Practice"
#define STR_SPECTATE  "Press Z to Spectate"

/* The refresh runs every frame and is written top-down; these two are the
 * ways out of the scene and read better next to each other, further down. */
static void peppy_room_go_to_draft(const char *why);
static void peppy_room_go_to_splash(const char *why);
static void peppy_room_check_paired(void *msrb);
static void peppy_room_train(void);
static void peppy_room_move_pick(void);
static void peppy_room_exit_room(void);
/* Joining from the list turns the browser back into a room without leaving the
 * scene, so it needs both builders before either is defined. */
static void *peppy_room_new_text(void);
static void peppy_room_build(void);
static void peppy_room_set_queued(int queued);
static void peppy_room_start_searching(void);

static void *s_text;
/* The match state buffer, made once and kept.
 *
 * FN_LoadMatchState takes the buffer to fill and allocates a new one when it is
 * handed zero - and never gives it back. Every call in Slippi's own code passes
 * zero, and every one of them is a scene setting itself up, once. This screen
 * reads the roster every frame, two and three times a frame, and passing zero
 * there is thirteen hundred bytes a go: about five megabytes a minute, until
 * the heap has nothing left and the game stops where it stands. The picture
 * freezes, the emulated CPU carries on, and nothing in the log says why.
 *
 * That is the whole of the "the room dies about half a minute in" bug, and it
 * was there long before anything was highlighted. */
static void *s_msrb;

/* Dressing the backdrop.
 *
 * The room borrows the Classic Mode Splash for its camera, and that scene is
 * also the versus splash - two characters in front of a stage. It has been
 * drawing an empty one this whole time because nothing filled in who is
 * playing. Everything it needs is one block, the same one SplashSceneInit
 * copies from Dolphin before a real match:
 *
 *     +0x0E              stage, halfword
 *     +0x60 + n*0x24     character
 *     +0x61 + n*0x24     slot type - 0 a human is here, 3 nobody is
 *     +0x63 + n*0x24     costume
 *
 * The difference is where the values come from. The two in the match agree
 * them over netplay and nobody else is in that conversation, so for everybody
 * else they arrive by the room tick instead - see MSRB_DRAFT.
 */
#define VS_DATA_R13_OFS  (-0x77C0)
#define VS_DATA_SKIP     (1424 + 8)
#define MATCH_STAGE      0x0E
#define MATCH_P_BASE     0x60
#define MATCH_P_STRIDE   0x24
#define MATCH_P_CHAR     0x00
#define MATCH_P_SLOT     0x01
#define MATCH_P_COLOR    0x03
#define MATCH_SLOT_HUMAN 0
#define MATCH_SLOT_EMPTY 3

static u8 *peppy_vs_data(void)
{
    char *r13 = (char *)peppy_sda();
    u8 *blk = *(u8 **)(r13 + VS_DATA_R13_OFS);

    return blk ? blk + VS_DATA_SKIP : 0;
}

static int peppy_room_dress_splash(void *msrb)
{
    const u8 *d = (const u8 *)msrb + MSRB_DRAFT;
    u8 *vs = peppy_vs_data();
    int i;

    if (!vs)
        return 0;
    /* The stage is settled before either character is, and it is most of the
     * picture - so it is worth drawing on its own rather than leaving the band
     * black through the whole character phase. Nothing at all is still nothing
     * to draw. */
    if (d[0] == MSRB_DRAFT_NONE && d[1] == MSRB_DRAFT_NONE && d[3] == MSRB_DRAFT_NONE)
        return 0;

    if (d[0] != MSRB_DRAFT_NONE)
        *(u16 *)(vs + MATCH_STAGE) = (u16)d[0];

    for (i = 0; i < 2; i++)
    {
        u8 *port = vs + MATCH_P_BASE + i * MATCH_P_STRIDE;
        u8 chr = d[1 + i * 2];

        if (chr == MSRB_DRAFT_NONE)
        {
            port[MATCH_P_SLOT] = MATCH_SLOT_EMPTY;
            continue;
        }
        port[MATCH_P_CHAR] = chr;
        port[MATCH_P_COLOR] = d[2 + i * 2];
        port[MATCH_P_SLOT] = MATCH_SLOT_HUMAN;
    }
    for (i = 2; i < 4; i++)
        vs[MATCH_P_BASE + i * MATCH_P_STRIDE + MATCH_P_SLOT] = MATCH_SLOT_EMPTY;
    return 1;
}

static void *peppy_room_msrb(void)
{
    s_msrb = FN_LoadMatchState(s_msrb);
    return s_msrb;
}
/* The screen has two shapes: a room, and the list of public rooms you pick one
 * from. Same scene, same text object - only what gets built and what the pad
 * does differ, because a browser that was its own scene would be a second
 * module and a second MxScn entry for one column of text. */
static int s_browsing;
/* Whether the borrowed splash was given a match to draw. */
static int s_dressed;
/* The six draft bytes the backdrop was last built from. */
static u8 s_dressed_from[6];
/* The scene this load was handed, kept so the backdrop can be built again. */
static void *s_scene;
static int s_browse_rows[BROWSE_ROWS];
static int s_browse_hi[BROWSE_ROWS];
static int s_browse_cursor;
static int s_browse_hint;
static int s_room_line;
static int s_room_wait;
static int s_queue_head;
static int s_lobby_head;
static int s_queue_line = -1;
static int s_line2 = -1;
/* Three symbols in the same two places rather than one that changes colour: a
 * subtext's colour is fixed when it is made, so the one that should show gets
 * the character and the others get nothing. */
static int s_spin_wait = -1;    /* blue, alternates - "still waiting on you" */
static int s_spin_done = -1;    /* green, steady - "that one is done" */
static int s_next_sym = -1;     /* blue, steady - "and this is available" */
static int s_spin_frame;
static int s_p1_line = -1;
static int s_p2_line = -1;
static int s_state_line = -1;
static int s_queue_rows[QUEUE_ROWS];
static int s_lobby_rows[LOBBY_ROWS];
/* Every highlightable line is drawn twice, in two colours, at the same place -
 * the lit one carries the text and the dim one carries nothing, or the other
 * way round. A subtext's colour is fixed when it is made, so a line cannot
 * change colour; and a marker character is no good either, because this font is
 * Shift-JIS and has no ASCII '>' - it takes the width and draws nothing, which
 * is what an invisible cursor looked like. Worse, '[' is something the
 * formatter tries to read, and "[BACK]" wedged the text draw outright: the
 * emulated CPU went on running and the picture never moved again. */
static int s_queue_hi[QUEUE_ROWS];
static int s_lobby_hi[LOBBY_ROWS];
static int s_queued;
/* Which name is highlighted, and in which column. The lobby is where a friends
 * list would start, so the cursor has to be able to reach both. */
#define PICK_QUEUE 0
#define PICK_LOBBY 1
#define PICK_BACK  2        /* the corner, reachable by going up off the top */
static int s_pick_col;
static int s_pick_row;
static int s_back_line = -1;   /* grey, shown when BACK is not the pick */
static int s_back_hi = -1;     /* gold, shown when it is */

/* One line, two colours. The text goes to the lit copy or the dim one and the
 * other is emptied, which is how a line appears to change colour. */
static void peppy_room_two_tone(int dim, int lit, const char *str, int highlighted)
{
    if (dim >= 0)
        Text_UpdateSubtextContents(s_text, dim, "%s", highlighted ? "" : str);
    if (lit >= 0)
        Text_UpdateSubtextContents(s_text, lit, "%s", highlighted ? str : "");
}

/* The two names on the line.  Empty when nobody is matched, which is the state
 * the room sits in most of the time. */
void peppy_room_set_players(const char *p1, const char *p2)
{
    if (!s_text)
        return;
    if (s_p1_line >= 0)
        Text_UpdateSubtextContents(s_text, s_p1_line, "%s", p1 ? p1 : "");
    if (s_p2_line >= 0)
        Text_UpdateSubtextContents(s_text, s_p2_line, "%s", p2 ? p2 : "");
}

/* Choosing, or playing. */
static void peppy_room_draft_state(void *msrb)
{
    const u8 *d = (const u8 *)msrb + MSRB_DRAFT;

    if (s_state_line < 0)
        return;
    if (d[1] == MSRB_DRAFT_NONE && d[3] == MSRB_DRAFT_NONE && !d[5])
        Text_UpdateSubtextContents(s_text, s_state_line, "%s", "");
    else
        Text_UpdateSubtextContents(s_text, s_state_line, "%s",
                                   d[5] ? "PLAYING" : "CHOOSING");
}

/* Called when the queue state changes; the roster will drive this once it is
 * wired up. */
/* Joining the queue, which only ever happens in one direction.
 *
 * There is deliberately no way to leave it from here. You leave by leaving the
 * room, or by not being there when your turn comes - which is the same thing
 * from everyone else's side, and means a queue position cannot be lost to a
 * misread button. */
static void peppy_room_set_queued(int queued)
{
    int changed;

    if (!s_text || s_queue_line < 0)
        return;
    changed = (queued != s_queued);
    s_queued = queued;

    /* Drawn every time, not only on a change - the lines are created empty and
     * a room that opens in the state it is already in would never fill them.
     *
     * Not queued: one thing to do, and it is not done yet. Queued: that one is
     * done, and practising becomes the next thing available. */
    Text_UpdateSubtextContents(s_text, s_queue_line,
                               queued ? STR_IN_QUEUE : STR_JOIN);
    if (s_spin_done >= 0)
        Text_UpdateSubtextContents(s_text, s_spin_done, queued ? SYM_DONE : "");
    if (s_spin_wait >= 0 && queued)
        Text_UpdateSubtextContents(s_text, s_spin_wait, "");
    if (s_next_sym >= 0)
        Text_UpdateSubtextContents(s_text, s_next_sym, queued ? SYM_NEXT : "");
    if (s_line2 >= 0)
        Text_UpdateSubtextContents(s_text, s_line2, queued ? STR_PRACTICE : "");
    s_spin_frame = 0;

    /* Dolphin only needs telling when it actually changes. */
    if (!changed)
        return;

    /* Dolphin is what talks to the room, so tell it: until this says otherwise
     * the client is present and watching, and pd_tick leaves it out of the
     * pairing and lists it in the lobby instead of the queue. */
    peppy_exi_buf[0] = PEPPY_CMD_SET_QUEUED;
    peppy_exi_buf[1] = (u8)(queued ? 1 : 0);
    FN_EXITransferBuffer(peppy_exi_buf, 2, CONST_ExiWrite);
}

/* The room borrows the splash's camera, and the splash's artwork comes with it.
 * The census says our text is alone in class 0 and the cameras are class 20, so
 * everything else on the scene belongs to the splash and can go - which leaves
 * a camera, a render pass, and the room's own text on a clean background.
 *
 * Take the next pointer before destroying, or the walk follows a freed object. */
#define PEPPY_CLASS_TEXT    0
#define PEPPY_CLASS_CAMERA  20

/* Is this one of the character select's hands?
 *
 * Kept by pointer rather than by class, because the hand shares its class with
 * the rest of that scene's models - keeping the class would keep the character
 * grid with it. */
static int peppy_room_is_cursor(void *g)
{
    void **objs = (void **)CSS_CURSOR_OBJS;
    int i;

    for (i = 0; i < CSS_CURSOR_PORTS; i++)
        if (objs[i] == g)
            return 1;
    return 0;
}

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

            if (!peppy_room_is_cursor(g))
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
/* The spectator split: the match in the top half, the room's furniture below.
 *
 * Text follows the camera, so the two halves have to be different cameras, and
 * a camera GObj's 64-bit link mask at +0x20/+0x24 says which links it draws.
 *
 * Finding the text's own link took a wrong turn worth recording: Text_CreateStruct
 * returns the text STRUCT, not its GObj, so reading a link out of it gave a
 * byte of the wrong object - which is why the camera whose mask matched was
 * the wrong one and the furniture stayed at the top.  The GObj is the one
 * whose render callback is Text_DrawEachFrame, and that is unambiguous.
 *
 * Players are not split at all: they keep Melee's screens full size.
 */
static void *peppy_find_text_gobj(void)
{
    void **heads = peppy_gobj_heads();
    int c;

    for (c = 0; c < 64; c++)
    {
        void *g = heads[c];

        while (g)
        {
            if (*(void **)((char *)g + PEPPY_GOBJ_DRAWFN) == TEXT_DRAW_EACH_FRAME)
                return g;
            g = *(void **)((char *)g + PEPPY_GOBJ_NEXT);
        }
    }
    return 0;
}

static void peppy_room_viewport(void *gobj, int top_half)
{
    void *cobj = *(void **)((char *)gobj + PEPPY_GOBJ_OBJECT);
    float half = (float)PEPPY_SCREEN_H / 2.0f;

    if (!cobj)
        return;

    if (top_half)
    {
        CObj_SetViewport(cobj, 0.0f, (float)PEPPY_SCREEN_W, 0.0f, half);
        CObj_SetScissor(cobj, 0, PEPPY_SCREEN_W, 0, PEPPY_SCREEN_H / 2);
    }
    else
    {
        CObj_SetViewport(cobj, 0.0f, (float)PEPPY_SCREEN_W, half,
                         (float)PEPPY_SCREEN_H);
        CObj_SetScissor(cobj, 0, PEPPY_SCREEN_W, PEPPY_SCREEN_H / 2,
                        PEPPY_SCREEN_H);
    }
}

/* Squeeze the game's cameras into the top half and put the room's text in the
 * bottom half, by render link: whichever camera draws the text is the one that
 * gets the lower viewport.
 *
 * Proven and then switched off, because it was solving the problem from the
 * wrong end. The drawing has the match in the top half and the queue below it,
 * and a match is not something this scene can render - the picks and the game
 * are Melee's own scenes, and a spectator has to be *in* them for the replayed
 * inputs to drive anything. So the split belongs on those scenes, drawing the
 * room over them, not here drawing a match that was never going to arrive.
 * Until then the room has the screen to itself and Z hands it over.
 *
 * Left standing because the hard part - finding the text's GObj, reading its
 * render link, matching it to a camera - is what that will need. */
static void peppy_room_split(void)
{
    char line[100];
    char *p = line;
    void **heads = peppy_gobj_heads();
    void *text_gobj = peppy_find_text_gobj();
    void *g;
    u8 link;
    u32 text_bit;
    int i = 0;

    if (!text_gobj)
    {
        peppy_log("Peppy: split skipped, no text gobj");
        return;
    }

    link = *(u8 *)((char *)text_gobj + PEPPY_GOBJ_LINK);
    text_bit = 1u << (link & 31);

    p = put(p, "Peppy: textlink=");
    p = put_u8(p, link);

    for (g = heads[PEPPY_CLASS_CAMERA]; g;
         g = *(void **)((char *)g + PEPPY_GOBJ_NEXT))
    {
        u32 links = *(u32 *)((char *)g + PEPPY_GOBJ_LINKS0);
        int bottom = (links & text_bit) != 0;

        peppy_room_viewport(g, bottom ? 0 : 1);
        *p++ = ' ';
        p = put_u8(p, (u8)i++);
        *p++ = '=';
        p = put(p, bottom ? "bottom" : "top");
    }
    *p = 0;
    peppy_log(line);
}

/* The roster arrives in the match state buffer as eight fixed 16-byte slots:
 * slot 0 and 1 are the two who are matched - the names that belong on the line
 * - and 2 onwards are the queue in order.  The names are not promised to be
 * terminated when they fill the slot, so copy rather than point.
 *
 * LOBBY stays empty for now: the backend sends "active" and "queue" and has no
 * notion yet of somebody who is in the room but not queued. */
/* Are we in the queue already?
 *
 * A scene module is loaded fresh every time its scene is entered, so it cannot
 * remember - and assuming "no" is wrong the moment you come back from training
 * or from watching a match, both of which you reached without ever leaving the
 * queue. Slippi already puts the local player's name in the match state buffer,
 * so the honest answer is to look for ourselves in the queue the room is about
 * to draw.
 *
 * Roster slots are MSRB_ROSTER_STRIDE wide and the name is truncated to fit, so
 * the comparison runs to the shorter of the two.
 */
static int peppy_room_is_me(const char *entry, const char *me)
{
    int i;

    if (!*entry)
        return 0;
    for (i = 0; i < MSRB_ROSTER_STRIDE && entry[i] && me[i]; i++)
        if (entry[i] != me[i])
            break;
    /* Matched to the end of the stored name. */
    return i && (i == MSRB_ROSTER_STRIDE || !entry[i]);
}

static int peppy_room_self_queued(void *msrb)
{
    const char *me = (const char *)msrb + MSRB_LOCAL_NAME;
    const char *roster = (const char *)msrb + MSRB_ROSTER;
    int slot;

    if (!*me)
        return 0;

    for (slot = 0; slot < MSRB_ROSTER_QUEUE; slot++)
        if (peppy_room_is_me(roster + (MSRB_ROSTER_ACTIVE + slot) * MSRB_ROSTER_STRIDE, me))
            return 1;
    return 0;
}

/* Are WE one of the two the room has just introduced?
 *
 * The first MSRB_ROSTER_ACTIVE slots are the pair; everything after is the
 * queue. A spectator is in neither, and a third person joining the queue while
 * two others are being matched is in the queue - so neither of them has any
 * business on the draft screen. */
static int peppy_room_self_playing(void *msrb)
{
    const char *me = (const char *)msrb + MSRB_LOCAL_NAME;
    const char *roster = (const char *)msrb + MSRB_ROSTER;
    int slot;

    if (!*me)
        return 0;

    for (slot = 0; slot < MSRB_ROSTER_ACTIVE; slot++)
        if (peppy_room_is_me(roster + slot * MSRB_ROSTER_STRIDE, me))
            return 1;
    return 0;
}

static void peppy_room_name(char *out, const char *slot)
{
    int i;

    for (i = 0; i < MSRB_ROSTER_STRIDE && slot[i]; i++)
        out[i] = slot[i];
    out[i] = 0;
}

/* Empty columns could mean the read is wrong or the room genuinely has nobody
 * queued.  Report the first slots once so the two are not confused. */
static int s_roster_reported;

static void peppy_room_report_roster(void *msrb)
{
    char line[110];
    char *p = line;
    const char *roster = (const char *)msrb + MSRB_ROSTER;
    int slot;

    p = put(p, "Peppy: msrb=");
    p = put_hex(p, (u32)msrb);
    p = put(p, " mode=");
    p = put_u8(p, *(u8 *)((char *)msrb + MSRB_ROOM_MODE));
    for (slot = 0; slot < 4 && p < line + 80; slot++)
    {
        char name[MSRB_ROSTER_STRIDE + 1];

        peppy_room_name(name, roster + slot * MSRB_ROSTER_STRIDE);
        *p++ = ' ';
        p = put_u8(p, (u8)slot);
        *p++ = '=';
        *p++ = '"';
        p = put(p, name);
        *p++ = '"';
    }
    *p = 0;
    peppy_log(line);
}

/* The room's own name line: which list it came from, its code, and the
 * passcode if it has one.
 *
 * Written once. It cannot change while the scene is up - you are in one room
 * until you leave - and a Text_UpdateSubtextContents every frame for a string
 * that never moves is sixty pointless rebuilds a second.
 */
/* The number beside a heading. Spelled out here and handed over as a string:
 * Melee's text formatter is not printf and the one %d I tried drew nothing. */
static void peppy_room_count(int line, int n)
{
    char buf[8];
    char *p = buf;

    if (line < 0)
        return;
    p = put_u8(p, (u8)n);
    *p = 0;
    Text_UpdateSubtextContents(s_text, line, "%s", buf);
}

static void peppy_room_show_code(void *msrb)
{
    char line[48];
    char *p = line;
    const char *code = (const char *)msrb + MSRB_ROOM_CODE;
    const char *pass = (const char *)msrb + MSRB_ROOM_PASS;
    u8 mode = *(u8 *)((char *)msrb + MSRB_ROOM_MODE);

    if (s_room_line < 0)
        return;

    /* A room that could not be made leaves this empty, and the screen would
     * otherwise sit there looking like a room with nobody in it. Say which it
     * is, and say how to get out - B only leaves the queue, and there is no
     * queue to leave here. Up from an empty column reaches BACK. */
    if (!code[0])
    {
        if (++s_room_wait > 180)
        {
            Text_UpdateSubtextContents(s_text, s_room_line, "%s",
                                       "NO ROOM - press UP then A to leave");
            s_room_line = -1;
        }
        return;
    }

    if (mode < MODE_COUNT)
    {
        p = put(p, MODE_NAMES[mode]);
        p = put(p, "   ");
    }
    p = put(p, "ROOM ");
    p = put(p, code);
    if (pass[0])
    {
        p = put(p, "   KEY ");
        p = put(p, pass);
    }
    *p = 0;

    Text_UpdateSubtextContents(s_text, s_room_line, "%s", line);
    s_room_line = -1;
}

static void peppy_room_refresh(void)
{
    char name[MSRB_ROSTER_STRIDE + 1];
    char row[MSRB_ROSTER_STRIDE + 8];
    const char *roster;
    void *msrb;
    int i, queue, lobby;

    if (!s_text)
        return;
    msrb = peppy_room_msrb();
    if (!msrb)
        return;
    roster = (const char *)msrb + MSRB_ROSTER;

    if (!s_roster_reported)
    {
        s_roster_reported = 1;
        peppy_room_report_roster(msrb);
    }

    peppy_room_two_tone(s_back_line, s_back_hi, "BACK", s_pick_col == PICK_BACK);

    peppy_room_draft_state(msrb);
    if (s_p1_line >= 0)
    {
        peppy_room_name(name, roster + 0 * MSRB_ROSTER_STRIDE);
        Text_UpdateSubtextContents(s_text, s_p1_line, "%s", name);
    }
    if (s_p2_line >= 0)
    {
        peppy_room_name(name, roster + 1 * MSRB_ROSTER_STRIDE);
        Text_UpdateSubtextContents(s_text, s_p2_line, "%s", name);
    }

    lobby = 0;
    for (i = 0; i < LOBBY_ROWS; i++)
    {
        peppy_room_name(name, roster + (MSRB_ROSTER_ACTIVE + MSRB_ROSTER_QUEUE
                                        + i) * MSRB_ROSTER_STRIDE);
        if (name[0])
            lobby++;
        {
            char *p = row;

            if (name[0])
                p = put(p, name);
            *p = 0;
            peppy_room_two_tone(s_lobby_rows[i], s_lobby_hi[i], row,
                                name[0] && s_pick_col == PICK_LOBBY
                                && s_pick_row == i);
        }
    }

    queue = 0;
    for (i = 0; i < QUEUE_ROWS; i++)
    {
        char *p = row;

        peppy_room_name(name, roster + (MSRB_ROSTER_ACTIVE + i) * MSRB_ROSTER_STRIDE);
        if (name[0])
        {
            queue++;
            p = put_u8(p, (u8)(i + 1));
            *p++ = '.';
            *p++ = ' ';
            p = put(p, name);
        }
        *p = 0;
        peppy_room_two_tone(s_queue_rows[i], s_queue_hi[i], row,
                            name[0] && s_pick_col == PICK_QUEUE
                            && s_pick_row == i);
    }

    /* An empty column and a column that is not working look identical, so say
     * which one it is. The count in the heading does the same job for a full
     * one, and it is how you tell at a glance that the room is live. */
    peppy_room_count(s_queue_head, queue);
    peppy_room_count(s_lobby_head, lobby);
    if (!queue && s_queue_rows[0] >= 0)
        Text_UpdateSubtextContents(s_text, s_queue_rows[0], "nobody waiting");
    if (!lobby && s_lobby_rows[0] >= 0)
        Text_UpdateSubtextContents(s_text, s_lobby_rows[0], "nobody here");

    peppy_room_show_code(msrb);
    peppy_room_check_paired(msrb);
}

/* ------------------------------------------------------------- the browser */

/* The public room list.
 *
 * Deliberately the same furniture as the room: the divider, the heading line,
 * a column of rows and a line of what the buttons do. Somebody who has seen
 * one has seen the other.
 */
static void peppy_room_build_browser(void *text)
{
    int i;

    FG_CreateSubtext(text, COL_GRAY, PEPPY_SUBTEXT_PLAIN, 0,
                     DIVIDER, SIZE_NAME, 30.0f, Y_DIVIDER + 14.0f);
    FG_CreateSubtext(text, COL_GOLD, PEPPY_SUBTEXT_PLAIN, 0,
                     "PUBLIC ROOMS", SIZE_HEADING, COL_LEFT, Y_DIVIDER);
    FG_CreateSubtext(text, COL_GRAY, PEPPY_SUBTEXT_PLAIN, 0,
                     "ROOM   HOST", SIZE_NAME, COL_LEFT, Y_ROOM);

    for (i = 0; i < BROWSE_ROWS; i++)
    {
        s_browse_rows[i] = FG_CreateSubtext(text, COL_WHITE, PEPPY_SUBTEXT_PLAIN,
                                            0, "", SIZE_NAME, COL_LEFT,
                                            Y_HEADING + ROW_STEP * i);
        s_browse_hi[i] = FG_CreateSubtext(text, COL_GOLD, PEPPY_SUBTEXT_PLAIN,
                                          0, "", SIZE_NAME, COL_LEFT,
                                          Y_HEADING + ROW_STEP * i);
    }

    s_browse_hint = FG_CreateSubtext(text, COL_WHITE, PEPPY_SUBTEXT_PLAIN, 0,
                                     "", SIZE_ACTION, COL_LEFT, Y_ACTIONS);
    FG_CreateSubtext(text, COL_GRAY, PEPPY_SUBTEXT_PLAIN, 0,
                     "Up and Down to choose, B to go back", SIZE_ACTION,
                     COL_LEFT, Y_ACTIONS + 30.0f);
}

/* One row: a marker for the row the cursor is on, the code, the host and how
 * many people are in there. */
static void peppy_room_browse_row(const char *entry, int selected, int line,
                                  int lit)
{
    char row[48];
    char *p = row;
    const char *code = entry + MSRB_ROOMLIST_CODE;
    const char *owner = entry + MSRB_ROOMLIST_OWNER;
    u8 players = *(const u8 *)(entry + MSRB_ROOMLIST_PLAYERS);
    int i;

    if (!code[0])
    {
        peppy_room_two_tone(line, lit, "", 0);
        return;
    }

    p = put(p, code);
    p = put(p, "   ");
    for (i = 0; i < MSRB_ROOMLIST_STRIDE - MSRB_ROOMLIST_OWNER && owner[i]; i++)
        *p++ = owner[i];
    p = put(p, "   ");
    p = put_u8(p, players);
    *p = 0;
    peppy_room_two_tone(line, lit, row, selected);
}

static void peppy_room_browse_refresh(void *msrb)
{
    const char *list = (const char *)msrb + MSRB_ROOMLIST;
    u8 count = *(u8 *)((char *)msrb + MSRB_ROOMLIST_COUNT);
    int i;

    if (count > BROWSE_ROWS)
        count = BROWSE_ROWS;
    if (s_browse_cursor >= count)
        s_browse_cursor = count ? count - 1 : 0;

    for (i = 0; i < BROWSE_ROWS; i++)
        peppy_room_browse_row(list + i * MSRB_ROOMLIST_STRIDE,
                              i == s_browse_cursor, s_browse_rows[i],
                              s_browse_hi[i]);

    if (s_browse_hint >= 0)
        Text_UpdateSubtextContents(s_text, s_browse_hint, "%s",
                                   count ? "Press A to Join"
                                         : "No public rooms open right now");
}

/* Joining moves the cursor off this screen entirely: Dolphin is told which room
 * it is, and then the scene is asked for again so it comes back up as a room.
 * Rebuilding the text in place would work too and would be more code for the
 * same picture. */
static void peppy_room_browse_join(void *msrb)
{
    const char *entry = (const char *)msrb + MSRB_ROOMLIST
                        + s_browse_cursor * MSRB_ROOMLIST_STRIDE;
    const char *code = entry + MSRB_ROOMLIST_CODE;
    int i;

    if (!code[0])
        return;

    peppy_exi_buf[0] = PEPPY_CMD_JOIN_ROOM;
    peppy_exi_buf[1] = *(u8 *)((char *)msrb + MSRB_ROOM_MODE);
    for (i = 0; i < 4; i++)
        peppy_exi_buf[2 + i] = (u8)code[i];
    FN_EXITransferBuffer(peppy_exi_buf, 6, CONST_ExiWrite);

    peppy_log("Peppy: joining a public room");

    /* Rebuilt here rather than by asking for the scene again. Leaving a minor
     * scene to re-enter the same one left a black screen - whatever the engine
     * does with that, it is not "run Load again" - and the room is a text
     * object, so throwing that one away and making another is the whole job. */
    {
        void *gobj = peppy_find_text_gobj();

        if (gobj)
            GObj_Destroy(gobj);
    }
    s_text = peppy_room_new_text();
    if (!s_text)
    {
        peppy_log("Peppy: joined, but could not build the room");
        return;
    }
    s_browsing = 0;
    peppy_room_build();
    peppy_room_set_queued(0);
    peppy_room_start_searching();
    peppy_log("Peppy: room scene built");
}

static void peppy_room_browse_buttons(void *msrb)
{
    u32 pressed = peppy_pad_pressed();
    u8 count = *(u8 *)((char *)msrb + MSRB_ROOMLIST_COUNT);

    if (count > BROWSE_ROWS)
        count = BROWSE_ROWS;

    if ((pressed & PAD_STICK_UP) && s_browse_cursor > 0)
        s_browse_cursor--;
    if ((pressed & PAD_STICK_DOWN) && s_browse_cursor + 1 < count)
        s_browse_cursor++;
    if (pressed & PAD_A)
        peppy_room_browse_join(msrb);
    /* Out the same way BACK leaves a room. It used to hand the screen to the
     * character select, which is not a place anybody asked to be: with no match
     * to pick for, that screen advances itself and you land on a versus splash
     * with two characters you did not choose. */
    if (pressed & PAD_B)
        peppy_room_exit_room();
}

/* The text object both shapes of this screen are drawn into. Made before either
 * of them, because which one gets built depends on what the match state buffer
 * says and that is no reason to set the canvas up twice. */
static void *peppy_room_new_text(void)
{
    void *text = Text_CreateStruct(0, 0);

    if (!text)
        return 0;

    *(u8 *)((char *)text + TEXT_OFS_KERN)  = 1;   /* close kerning */
    *(u8 *)((char *)text + TEXT_OFS_ALIGN) = 0;   /* align left   */
    *(float *)((char *)text + TEXT_OFS_Z)      = TEXT_Z;
    *(float *)((char *)text + TEXT_OFS_SCALEX) = TEXT_CANVAS;
    *(float *)((char *)text + TEXT_OFS_SCALEY) = TEXT_CANVAS;
    return text;
}

static void peppy_room_build(void)
{
    void *text = s_text;
    int i;

    if (!text)
        return;

    /* The line, and the two players sitting on it: whoever is picking a stage
     * or a character right now, and then whoever is playing. */
    FG_CreateSubtext(text, COL_GRAY, PEPPY_SUBTEXT_PLAIN, 0,
                     DIVIDER, SIZE_NAME, 30.0f, Y_DIVIDER + 14.0f);
    s_p1_line = FG_CreateSubtext(text, COL_WHITE, PEPPY_SUBTEXT_PLAIN, 0,
                                 "", SIZE_HEADING, X_P1, Y_DIVIDER);
    FG_CreateSubtext(text, COL_GOLD, PEPPY_SUBTEXT_PLAIN, 0,
                     "VS", SIZE_HEADING, X_VS, Y_DIVIDER);
    s_p2_line = FG_CreateSubtext(text, COL_WHITE, PEPPY_SUBTEXT_PLAIN, 0,
                                 "", SIZE_HEADING, X_P2, Y_DIVIDER);
    /* Under the VS, because the two states look identical otherwise: a pair
     * still choosing and a pair mid-game both draw two characters on a stage. */
    s_state_line = FG_CreateSubtext(text, COL_WAIT, PEPPY_SUBTEXT_PLAIN, 0,
                                    "", SIZE_ACTION, X_VS - 28.0f,
                                    Y_DIVIDER + 26.0f);

    /* Which room you are actually in. It was nowhere on the screen, which is
     * fine right up until somebody wants to tell a friend the code. */
    s_room_line = FG_CreateSubtext(text, COL_GOLD, PEPPY_SUBTEXT_PLAIN, 0,
                                   "", SIZE_NAME, COL_LEFT, Y_ROOM);

    FG_CreateSubtext(text, COL_WHITE, PEPPY_SUBTEXT_PLAIN, 0,
                     "QUEUE", SIZE_HEADING, COL_LEFT, Y_HEADING);
    FG_CreateSubtext(text, COL_WHITE, PEPPY_SUBTEXT_PLAIN, 0,
                     "LOBBY", SIZE_HEADING, COL_RIGHT, Y_HEADING);

    /* The count sits beside the heading as its own line rather than inside it.
     * Two goes at "QUEUE (0)" both drew a bare QUEUE and stopped at the
     * bracket: this text is drawn by Melee's own formatter, not printf, and it
     * does not take everything ASCII has. Digits on their own it does. */
    s_queue_head = FG_CreateSubtext(text, COL_GOLD, PEPPY_SUBTEXT_PLAIN, 0,
                                    "", SIZE_HEADING, COL_LEFT + X_COUNT,
                                    Y_HEADING);
    s_lobby_head = FG_CreateSubtext(text, COL_GOLD, PEPPY_SUBTEXT_PLAIN, 0,
                                    "", SIZE_HEADING, COL_RIGHT + X_COUNT,
                                    Y_HEADING);

    for (i = 0; i < QUEUE_ROWS; i++)
    {
        s_queue_rows[i] = FG_CreateSubtext(text, COL_WHITE, PEPPY_SUBTEXT_PLAIN,
                                           0, "", SIZE_NAME, COL_LEFT,
                                           Y_FIRST_NAME + ROW_STEP * i);
        s_queue_hi[i] = FG_CreateSubtext(text, COL_GOLD, PEPPY_SUBTEXT_PLAIN,
                                         0, "", SIZE_NAME, COL_LEFT,
                                         Y_FIRST_NAME + ROW_STEP * i);
    }
    for (i = 0; i < LOBBY_ROWS; i++)
    {
        s_lobby_rows[i] = FG_CreateSubtext(text, COL_GRAY, PEPPY_SUBTEXT_PLAIN,
                                           0, "", SIZE_NAME, COL_RIGHT,
                                           Y_FIRST_NAME + ROW_STEP * i);
        s_lobby_hi[i] = FG_CreateSubtext(text, COL_GOLD, PEPPY_SUBTEXT_PLAIN,
                                         0, "", SIZE_NAME, COL_RIGHT,
                                         Y_FIRST_NAME + ROW_STEP * i);
    }

    /* Start is the only thing that changes: once you are in the queue it stops
     * offering to put you there and offers practice instead, which is where
     * waiting happens. Training is not a button of its own. */
    s_queue_line = FG_CreateSubtext(text, COL_WHITE, PEPPY_SUBTEXT_PLAIN, 0,
                                    "", SIZE_ACTION,
                                    COL_LEFT + X_SYMBOL, Y_ACTIONS);
    s_spin_wait = FG_CreateSubtext(text, COL_WAIT, PEPPY_SUBTEXT_PLAIN, 0,
                                   "", SIZE_SPINNER, COL_LEFT, Y_ACTIONS);
    s_spin_done = FG_CreateSubtext(text, COL_DONE, PEPPY_SUBTEXT_PLAIN, 0,
                                   "", SIZE_SPINNER, COL_LEFT, Y_ACTIONS);
    s_next_sym = FG_CreateSubtext(text, COL_WAIT, PEPPY_SUBTEXT_PLAIN, 0,
                                  "", SIZE_SPINNER, COL_LEFT,
                                  Y_ACTIONS + ROW_ACTION);
    s_line2 = FG_CreateSubtext(text, COL_GRAY, PEPPY_SUBTEXT_PLAIN, 0,
                               "", SIZE_ACTION, COL_LEFT + X_SYMBOL,
                               Y_ACTIONS + ROW_ACTION);
    FG_CreateSubtext(text, COL_GRAY, PEPPY_SUBTEXT_PLAIN, 0,
                     STR_SPECTATE, SIZE_ACTION, COL_LEFT + X_SYMBOL,
                     Y_ACTIONS + 2.0f * ROW_ACTION);

    /* The same corner the character select keeps its own BACK in. Twice over,
     * grey and gold, so that highlighting it is a change of colour - see
     * peppy_room_two_tone for why it cannot be anything else. */
    s_back_line = FG_CreateSubtext(text, COL_GRAY, PEPPY_SUBTEXT_PLAIN, 0,
                                   "BACK", SIZE_HEADING, X_BACK, Y_DIVIDER);
    s_back_hi = FG_CreateSubtext(text, COL_GOLD, PEPPY_SUBTEXT_PLAIN, 0,
                                 "", SIZE_HEADING, X_BACK, Y_DIVIDER);
}

/* ----------------------------------------------------------------- exports */

/* Watching the match.
 *
 * Dolphin has already joined the broadcast by the time the flag is set - the
 * room tick starts that on its own for anyone who is not playing - so this is
 * only about the screen. The watcher goes to the online character select and
 * the replayed inputs drive it from there exactly as they drive a player's,
 * which is how a spectator sees the picks and then the game.
 *
 * The flag rather than the roster decides it: two names in the active slots
 * mean a pair has been introduced, not that there is anything on screen yet.
 */
/* Into a game with nothing to pick - which is what watching is.
 *
 * The splash is minor 4 of this major. Its init has to run first, and that
 * lives in the codeset, so PeppyRoomSceneDecide makes the call when it sees
 * this minor asked for. */
static void peppy_room_go_to_splash(const char *why)
{
    peppy_log(why);
    SCENE_CTRL.pending_minor = SCENE_NEXT_MINOR(ONLINE_MINOR_SPLASH);
    Scene_ExitMinor();
}

/* Matched players go to the draft - stage, then characters - and never see the
 * character select. */
static void peppy_room_go_to_draft(const char *why)
{
    peppy_log(why);
    SCENE_CTRL.pending_minor = SCENE_NEXT_MINOR(ONLINE_MINOR_GAMESETUP);
    Scene_ExitMinor();
}

/* Ask Dolphin to start looking.
 *
 * This is the character select's own first act, and nothing had taken it over
 * for a room - so Dolphin never started its matchmaking thread, never ticked
 * the room, and the queue and lobby columns sat empty for reasons that looked
 * like a backend problem and were not.
 *
 * Searching is not the same as being in the queue: the tick says "present
 * only" until Start is pressed, so this just opens the line.
 */
static void peppy_room_start_searching(void)
{
    int i;

    peppy_exi_buf[0] = PEPPY_CMD_FIND_OPPONENT;
    peppy_exi_buf[1] = ONLINE_MODE_ROOMS;
    for (i = 2; i < PEPPY_FIND_OPPONENT_SIZE; i++)
        peppy_exi_buf[i] = 0;   /* opponent code, Direct mode only */
    FN_EXITransferBuffer(peppy_exi_buf, PEPPY_FIND_OPPONENT_SIZE, CONST_ExiWrite);
}

static void peppy_room_spectate(void)
{
    void *msrb = peppy_room_msrb();

    if (!msrb || !(*(u8 *)((char *)msrb + MSRB_ROOM_FLAGS)
                   & MSRB_ROOM_FLAG_WATCHABLE))
    {
        peppy_log("Peppy: Z - nothing to watch yet");
        return;
    }

    /* Straight into the game, past every screen where something gets chosen.
     *
     * A watcher has nothing to choose and no way to advance a screen that
     * expects a choice. The draft does not run on pad inputs - it runs on the
     * step results the two players relay to each other, which a watcher never
     * receives - so one sent there sits on "select a stage to ban" until the
     * match it is meant to be watching has finished. The character select was
     * the same in its own way.
     *
     * There is nothing to wait for either: WATCHABLE already means Dolphin has
     * both players' selections AND a timeline of frames, which only happens
     * once the game is live. The match block is filled in from the stream, and
     * the splash's init is what copies it into the scene - so that is the
     * screen a watcher wants, and the codeset's room Decide makes that call. */
    peppy_room_go_to_splash("Peppy: watching the match");
}

/* Paired up: the room's job is done and the character select takes over.
 *
 * The handoff waits for CONNECTION_SUCCESS and not a moment earlier. The
 * character select forks on the same byte, and anything below that lands it in
 * its "searching" branch, where it will not let you lock a character in - you
 * would arrive at a character select that refuses to start. At
 * CONNECTION_SUCCESS it opens on the branch that takes a pick and a Start,
 * which is the screen the player is expecting.
 */
static void peppy_room_check_paired(void *msrb)
{
    u8 state = *(u8 *)((char *)msrb + MSRB_CONNECTION_STATE);

    if (state != MM_STATE_CONNECTION_SUCCESS)
        return;

    /* And it has to be OUR match. The connection state says a connection is up,
     * not whose - a spectator watching somebody else's game has one too, and so
     * does a third person who walks into the queue while two others are being
     * introduced. Both of them were being sent to the draft to pick a stage for
     * a game they are not in. */
    if (!peppy_room_self_playing(msrb))
        return;

    peppy_room_go_to_draft("Peppy: matched - handing over to the draft");
}

/* ⚠️ What the draft needs, and does not bring with it.
 *
 * Slippi only ever reaches that screen from the VS scene's decide, between
 * games of a set, so it helps itself to things the character select has already
 * put out - the archive above being the one that crashed us. If another turns
 * up, the way to find it is in peppy-assets/gamesetup: Dolphin's MMU panic logs
 * the link register and every GPR, and gsdis2.py turns the register that held
 * the bad pointer into an offset inside GameSetup.dat.
 *
 * GPDO_CUR_GAME is 2 because this is the BETWEEN-games screen and game one has
 * nothing to counterpick from. A room's first game is a fresh pairing, so there
 * is no previous result to show - that is a thing to fill in, not a thing to
 * avoid the screen over.
 */

/* Off to practise.
 *
 * Training is minor 7 of this same major - Melee's own training scene, copied
 * in MxScn.dat so the real one is left alone - and going there is the ordinary
 * minor change that already carries a matched player to the character select.
 * Your place in the queue is not touched: the room goes on ticking from
 * Dolphin's side, and the training scene watches for its turn.
 */
static void peppy_room_train(void)
{
    peppy_log("Peppy: off to practise");
    /* Training's character select first - a match needs a character in it, and
     * that is where one comes from. */
    SCENE_CTRL.pending_minor = SCENE_NEXT_MINOR(ONLINE_MINOR_TRAIN_CSS);
    Scene_ExitMinor();
}

/* Leaving the room for real.
 *
 * Out of the online MAJOR altogether, back to the menu the room was entered
 * from - which is what "back" means to anyone who has just walked in through
 * three menus.
 *
 * This is the pair Melee's own character select uses, and reading the scene
 * machinery is what finally explained why eight earlier attempts at it froze.
 * Scene_ProcessMajor is a loop: run the current minor, then look at byte 0xC of
 * the scene controller, and only then leave. Scene_ProcessMinor always returns
 * after one minor - it does not load the next one itself. So the flag alone
 * does nothing while the minor's Think is still running, and the picture sits
 * there in a scene that has already been told to go. The minor has to end too.
 *
 * The heap being exhausted did not help those attempts either. See
 * peppy_room_msrb.
 */
static void peppy_room_exit_room(void)
{
    peppy_log(s_browsing ? "Peppy: leaving the room list"
                         : "Peppy: leaving the room");

    /* Whether there was a room to leave. Walking off the list of public rooms
     * is not leaving one - you were never in it - and saying otherwise drops
     * the launcher out of the room peppy.json started it in. */
    peppy_exi_buf[0] = PEPPY_CMD_LEAVE_ROOM;
    peppy_exi_buf[1] = (u8)!s_browsing;
    FN_EXITransferBuffer(peppy_exi_buf, 2, CONST_ExiWrite);

    /* Nothing of ours is next - the menu's own major load decides where it
     * lands. Slippi's return-from-online handler puts the cursor back on Rooms,
     * and Peppy's addition to it opens the Rooms list rather than the mode list,
     * so you come out on the screen you went in through. */
    SCENE_CTRL.pending_minor = 0;
    MenuController_WriteToPendingMajor_1to_0xC(SCENE_MAJOR_MAIN_MENU);
    Scene_ExitMinor();
}

/* Leaving the room.
 *
 * The request is raised here and spent in the scene's Decide, over in the
 * codeset - a Decide is where every other transition in Slippi's online scene
 * is made. The sentinel rides in the scene controller's own next-minor byte,
 * so there is no new state to keep in step between the two sides.
 *
 * It gets you to the character select, which is one screen from the menu and
 * has Melee's own BACK on it. Ending the online MAJOR outright is unsolved:
 * seven ways tried, from the Think and from the Decide, and every one of them
 * freezes the picture with the scene already left -
 *
 *   Event_StoreSceneNumber(1)                  minor exits, byte 5 still held
 *                                              our own minor, hang
 *   ... with pending_minor 0                   character select, major
 *                                              unchanged
 *   ... with pending_minor 40 (ExitSceneID)    hangs before Leave even runs
 *   ... with pending_minor 0xFF                hang
 *   ... 0xFF again, from the Decide, with the
 *       next major already named               hang
 *   Scene_SetNextMajor(1) + Scene_ExitMajor    byte 1 does change to 1, hang
 *   Event_StoreSceneNumber((40 << 8) | 1)      character select again
 *   from a GObj proc of its own                GObj_Create(0, 1, 128) never
 *                                              came back at all
 *
 * The menu's own Event_StoreSceneNumber(8) works, so the call is fine. What is
 * missing is whatever tells the engine the minor chain is over - zero means
 * minor zero, not "none", and nothing else tried means "none" either.
 */
static void peppy_room_back(void)
{
    if (s_queued)
        peppy_room_set_queued(0);
    peppy_log("Peppy: left the queue");

    /* And stays here.
     *
     * Leaving the ROOM is unsolved - leaving the online major has never worked
     * from a scene of ours, and every stand-in destination is wrong in its own
     * way. Asking for a sentinel minor left the game with no scene at all once
     * the table gained a catch-all; the character select advances itself to a
     * versus splash while the match state still looks live.
     *
     * So B does the part that is real - it takes you out of the queue - and
     * does not pretend to do the part that is not. */
}

/* The room's buttons.
 *
 * START joins the queue, and once you are in it goes off to practise.
 *
 * B leaves the QUEUE and stays in the room. BACK - the corner, highlighted with
 * the stick and taken with A - leaves the ROOM, and takes the queue with it.
 * Two different things, so two different buttons.
 *
 * Z watches the match, when there is one.
 */
/* Move the highlight.
 *
 * Up and down within a column, left and right between them. It stops at the
 * ends rather than wrapping, and it does not walk past the last real name -
 * a cursor sitting on an empty row has nothing to act on.
 */
static void peppy_room_count_names(void *msrb, int *queue, int *lobby)
{
    const char *roster = (const char *)msrb + MSRB_ROSTER;
    int i;

    *queue = *lobby = 0;
    for (i = 0; i < QUEUE_ROWS; i++)
        if (roster[(MSRB_ROSTER_ACTIVE + i) * MSRB_ROSTER_STRIDE])
            (*queue)++;
    for (i = 0; i < LOBBY_ROWS; i++)
        if (roster[(MSRB_ROSTER_ACTIVE + MSRB_ROSTER_QUEUE + i) * MSRB_ROSTER_STRIDE])
            (*lobby)++;
}

static void peppy_room_move_pick(void)
{
    u32 pressed = peppy_pad_pressed();
    void *msrb = peppy_room_msrb();
    int queue, lobby, limit;

    if (!msrb)
        return;
    peppy_room_count_names(msrb, &queue, &lobby);

    if (pressed & (PAD_STICK_LEFT | PAD_DPAD_LEFT))
        s_pick_col = PICK_QUEUE;
    if (pressed & (PAD_STICK_RIGHT | PAD_DPAD_RIGHT))
        s_pick_col = PICK_LOBBY;

    if (s_pick_col == PICK_BACK)
    {
        /* Down comes back to the names; sideways stays put, since BACK is the
         * only thing up there. */
        if (pressed & PAD_STICK_DOWN)
        {
            s_pick_col = PICK_QUEUE;
            s_pick_row = 0;
        }
        return;
    }

    limit = (s_pick_col == PICK_QUEUE) ? queue : lobby;
    if (pressed & PAD_STICK_UP)
    {
        if (s_pick_row > 0)
            s_pick_row--;
        else
            s_pick_col = PICK_BACK;     /* up off the top of the list */
    }
    if ((pressed & PAD_STICK_DOWN) && s_pick_row + 1 < limit)
        s_pick_row++;
    if (s_pick_row >= limit)
        s_pick_row = limit > 0 ? limit - 1 : 0;
}

static void peppy_room_buttons(void)
{
    u32 pressed = peppy_pad_pressed();

    peppy_room_move_pick();

    /* Start joins the queue, and once you are in it Start is how you go and
     * practise while you wait. It is never how you leave. */
    if (pressed & PAD_START)
    {
        if (!s_queued)
            peppy_room_set_queued(1);
        else
            peppy_room_train();
    }
    if ((pressed & PAD_A) && s_pick_col == PICK_BACK)
        peppy_room_exit_room();
    if (pressed & PAD_Z)
        peppy_room_spectate();
    if (pressed & PAD_B)
        peppy_room_back();
}

/* The waiting symbol alternates, the way Slippi's does while it searches: two
 * icons, fifteen frames each. Only while there is something still waiting on
 * you - once you are in the queue that line is done and stops moving. */
static void peppy_room_spin(void)
{
    if (s_queued || s_spin_wait < 0)
        return;
    if (s_spin_frame % SPINNER_FRAMES == 0)
        Text_UpdateSubtextContents(s_text, s_spin_wait,
                                   (s_spin_frame / SPINNER_FRAMES) ? SYM_TODO
                                                                   : SYM_NEXT);
    s_spin_frame = (s_spin_frame + 1) % (2 * SPINNER_FRAMES);
}

/* Build the backdrop again, because what goes in it has changed.
 *
 * Dressing happens at scene load, and somebody sitting in the room while two
 * others get matched loads it long before there is anything to show - so left
 * at that, the only people who ever saw the top half would be those who walked
 * in after the picking was done. Which is nobody.
 *
 * The splash's load is safe to call twice: it is why the room borrows that one
 * and not the character select, whose load fetches portraits across frames. */
static void peppy_room_redress(void *msrb)
{
    const u8 *d = (const u8 *)msrb + MSRB_DRAFT;
    int i, changed = 0;

    if (s_browsing || !s_scene)
        return;
    for (i = 0; i < 6; i++)
        if (s_dressed_from[i] != d[i])
            changed = 1;
    if (!changed)
        return;
    for (i = 0; i < 6; i++)
        s_dressed_from[i] = d[i];

    {
        static const char hex[] = "0123456789abcdef";
        char line[48];
        char *o = put(line, "Peppy: draft ");

        /* Two digits a byte, not put_hex's eight - six of those overflow the
         * line, which the compiler was good enough to say so. */
        for (i = 0; i < 6; i++)
        {
            *o++ = hex[(d[i] >> 4) & 0xF];
            *o++ = hex[d[i] & 0xF];
            *o++ = ' ';
        }
        *o = 0;
        peppy_log(line);
    }

    if (!peppy_room_dress_splash(msrb))
        return;

    /* The bare backdrop first, or the old one stays behind the new one. */
    peppy_room_clear_borrowed_scene();
    SceneLoad_ClassicModeSplash(s_scene);
    peppy_room_split();
    s_dressed = 1;
}

void peppy_room_think(void)
{
    /* The roster changes while people come and go, so it is read every frame
     * rather than once at load. */
    if (s_browsing)
    {
        void *msrb = peppy_room_msrb();

        if (msrb)
        {
            peppy_room_browse_refresh(msrb);
            peppy_room_browse_buttons(msrb);
        }
        return;
    }

    peppy_room_spin();
    {
        void *msrb = peppy_room_msrb();

        if (msrb)
            peppy_room_redress(msrb);
    }
    /* The borrowed splash asks for its character models and then waits, and the
     * waiting is a preload that something has to pump. Preload_Update is that
     * pump on its own - the splash's THINK does this and then advances the
     * scene, which is the half that threw the room out. */
    if (s_dressed)
        Preload_Update();

    /* ⚠️ Do NOT call SceneThink_ClassicModeSplash here to finish the preload.
     *
     * It does advance it - and then advances the SCENE, because that is the
     * other half of what a splash think is for. The room threw itself into the
     * game-prep scene, which for anybody who is not one of the two playing is a
     * DISCONNECTED box and no way back. Tried once, on purpose, and that is
     * exactly what happened.
     *
     * So the borrowed splash stays on NOW LOADING for ever: its character models
     * preload across frames and nothing here can finish them. Full-body
     * characters in the top half need something other than borrowing this
     * scene - the portraits the draft uses are frame-addressed and preload
     * nothing, which is the next thing to try. */
    peppy_room_refresh();
    peppy_room_buttons();
}

/* Melee's match: what stage, which characters, how many stocks. 0x8046b6a0 is
 * the struct the whole game reads it from - Slippi's own code calls it "some
 * static match state struct" in half a dozen places. */
#define MATCH_STRUCT 0x8046b6a0

/* Training's in-game minor data, read out of major 0x1c minor 2. */
#define TRAIN_MINOR_DATA 0x8048e4c0

/* Battlefield. Training's stage select is what should be choosing this. */
#define TRAIN_STAGE     0x1F
/* What training's own in-game prep stores as the match think. */
#define TRAIN_THINK_FN  0x801B1F6C

void ScenePrep_TrainingMode_InGame(void *minor_data);
/* Where this scene's minor data actually lives. The prep writes through this
 * rather than through its own argument, so the load has to be handed the same
 * thing or it starts a different match from the one that was just prepared. */
void *GetMinorSceneData1(void *scene);

/* Where the character select keeps its picks: a pointer in the short data
 * area, plus 0xd10. Training's own in-game prep reads exactly this. */
__attribute__((unused)) static u32 peppy_css_data(void)
{
    return *(u32 *)((char *)peppy_sda() - 0x77c0) + 0xd10;
}

__attribute__((unused)) static void peppy_dump_at(u32 base, int rows)
{
    char line[128];
    int row;

    for (row = 0; row < rows; row++)
    {
        char *o = line;
        int k;

        for (k = 0; "Peppy: d "[k]; k++)
            *o++ = "Peppy: d "[k];
        o = put_hex(o, base + row * 0x20);
        *o++ = ':';
        for (k = 0; k < 0x20; k += 4)
        {
            *o++ = ' ';
            o = put_hex(o, *(u32 *)(base + row * 0x20 + k));
        }
        *o = 0;
        peppy_log(line);
    }
}

__attribute__((unused)) static void peppy_dump_match_struct(void)
{
    char line[128];
    int row;

    for (row = 0; row < 8; row++)
    {
        char *o = line;
        int k;

        for (k = 0; "Peppy: m "[k]; k++)
            *o++ = "Peppy: m "[k];
        o = put_hex(o, row * 0x20);
        *o++ = ':';
        for (k = 0; k < 0x20; k += 4)
        {
            *o++ = ' ';
            o = put_hex(o, *(u32 *)(MATCH_STRUCT + row * 0x20 + k));
        }
        *o = 0;
        peppy_log(line);
    }
}

/* Melee hands a scene its own descriptor, and everything about starting a match
 * hangs off it: GetMinorSceneData1 is nothing but *(scene + 0x10), and
 * StartMelee reads the stage out of it. Throwing that argument away is what
 * made every attempt at training walk off into a stage that does not exist. */
void peppy_room_load(void *scene)
{
    s_scene = scene;
    /* A fresh buffer for a fresh entry. One per visit to the room, which is
     * what Slippi's own scenes cost too - the ruinous version was one per
     * frame. See peppy_room_msrb. */
    s_msrb = 0;

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
    {
        void *msrb0 = peppy_room_msrb();

        s_browsing = msrb0 && (*(u8 *)((char *)msrb0 + MSRB_ROOM_FLAGS)
                               & MSRB_ROOM_FLAG_BROWSING);
        /* Before the load, because the load is what builds from it. And the
         * signature with it, so the first Think does not immediately decide
         * everything has changed and build it all a second time. */
        s_dressed = !s_browsing && msrb0 && peppy_room_dress_splash(msrb0);
        if (msrb0)
        {
            int i;

            for (i = 0; i < 6; i++)
                s_dressed_from[i] = *((const u8 *)msrb0 + MSRB_DRAFT + i);
        }
    }

    /* The room is a menu and wants a menu's backdrop.
     *
     * It is handed the scene, because a scene load reads its minor data out of
     * that argument. Called bare - as this was - it read whatever r3 happened
     * to hold, which the match-state call just above had already overwritten.
     * Entering the room from the menu got away with it; coming back from
     * training did not, and the room drew nothing at all. */
    /* The room borrows the splash for its camera.
     *
     * ⚠️ Borrowing the CHARACTER SELECT instead - to get its hand, which is a
     * GObj that load creates and Melee's cursor think moves from the stick -
     * does NOT work from here. That load never returns: it fetches character
     * portraits, and those loads are spread across frames that only the scene
     * machinery runs. The splash works inline precisely because it loads
     * nothing. Getting the hand means the room's scene being built on the
     * character select by the machinery, not calling its load ourselves.
     *
     * Tried twice: with that scene's own minor data, and with the scene pointer
     * this load is handed. Same both times, so it is not the argument. */
    SceneLoad_ClassicModeSplash(scene);
    /* The sweep is what kept the borrowed scene's own artwork off the screen -
     * the 1-P Mode furniture that has no business in a room. But once the block
     * above is filled in, the things it would sweep away ARE the two characters
     * and the stage they are playing on, which is the whole point. So it only
     * runs when there is nothing to show. */
    if (!s_dressed)
        peppy_room_clear_borrowed_scene();

    s_text = 0;
    s_queue_line = -1;
    s_line2 = -1;
    s_spin_wait = -1;
    s_spin_done = -1;
    s_next_sym = -1;
    s_spin_frame = 0;
    s_room_line = -1;
    s_room_wait = 0;
    s_queue_head = -1;
    s_lobby_head = -1;
    s_p1_line = -1;
    s_p2_line = -1;
    s_state_line = -1;
    s_queued = 0;
    s_pick_col = PICK_QUEUE;
    s_pick_row = 0;
    s_back_line = -1;
    s_back_hi = -1;
    s_roster_reported = 0;
    s_browse_cursor = 0;
    s_browse_hint = -1;
    {
        int i;

        for (i = 0; i < QUEUE_ROWS; i++)
            s_queue_rows[i] = s_queue_hi[i] = -1;
        for (i = 0; i < LOBBY_ROWS; i++)
            s_lobby_rows[i] = s_lobby_hi[i] = -1;
        for (i = 0; i < BROWSE_ROWS; i++)
            s_browse_rows[i] = s_browse_hi[i] = -1;
    }

    s_text = peppy_room_new_text();
    if (!s_text)
    {
        peppy_log("Peppy: room scene FAILED to make a text struct");
        return;
    }

    if (s_browsing)
    {
        /* No room yet, so nothing to search for and nothing to queue for. */
        peppy_room_build_browser(s_text);
        peppy_log("Peppy: room list built");
        return;
    }

    {
        /* A text object draws itself, but only into a camera's render pass. The
         * room has never owned one - it borrows whatever the splash scene's load
         * leaves behind - so if that borrow ever fails the screen is simply
         * black at 60fps. Count what is actually there. */
        void **heads = peppy_gobj_heads();
        char line[64];
        char *o = line;
        int k, cams = 0, texts = 0;
        void *g;

        for (g = heads[PEPPY_CLASS_CAMERA]; g; g = *(void **)((char *)g + PEPPY_GOBJ_NEXT))
            cams++;
        for (g = heads[PEPPY_CLASS_TEXT]; g; g = *(void **)((char *)g + PEPPY_GOBJ_NEXT))
            texts++;
        for (k = 0; "Peppy: cams "[k]; k++)
            *o++ = "Peppy: cams "[k];
        o = put_hex(o, (u32)cams);
        *o++ = ' ';
        o = put_hex(o, (u32)texts);
        *o = 0;
        peppy_log(line);
    }

    peppy_room_build();
    /* Say it rather than assume it - and ask the roster rather than assuming
     * "not queued", because coming back from training or from spectating you
     * never left. */
    {
        void *msrb = peppy_room_msrb();

        peppy_room_set_queued(msrb ? peppy_room_self_queued(msrb) : 0);
    }
    peppy_room_start_searching();
    /* Split only when there is something in the other half. With nothing to
     * show, the room is better off with the whole screen than with half of it
     * and a blank band. */
    if (s_dressed)
        peppy_room_split();
    peppy_log("Peppy: room scene built");
}

void peppy_room_leave(void)
{
    peppy_log("Peppy: room scene leaving");
}
