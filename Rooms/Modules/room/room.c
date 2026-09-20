/* The room screen.
 *
 * SKELETON. This is the smallest thing that proves the m-ex pipeline on this
 * branch: the module is found, loaded, relocated, its exports are installed
 * into the scene's Think/Load slots, and it draws. Nothing else yet.
 *
 * Where it is going, so the shape here does not have to be undone later:
 *
 * The room's scene entry is a COPY of the VS splash's (global minor 0x20),
 * not an empty one. That matters: the splash's Load builds two character models
 * in their chosen costumes, which is exactly the picture a room wants.
 *
 * It DOES need a 3D preload - the old notes said it could not be finished from
 * here and that was wrong. A fighter's model is a file, and a scene requests it
 * in its ScenePrep; the room's prep now does, the same way the splash's own
 * does. What made it look impossible was pumping Preload_Update with nothing
 * ever queued, which pumps an empty queue and changes nothing.
 *
 * So this module exports Think and Load and deliberately NOT Leave: m-ex only
 * overwrites a slot a module actually exports, and the copied entry's own
 * Leave is the right one.
 *
 *   Load   fill a match struct we own, call SceneLoad_ClassicModeSplash to
 *          build the characters, then put the room's own text under them
 *   Think  the room's work. Never the splash's own scene think, which is
 *          twelve instructions that do nothing but exit the scene - that is
 *          why the band can sit here indefinitely
 *
 * The band is a function of room state, rebuilt only when that state changes -
 * never per frame. ClassicMode_LoadSplash is callable on its own for exactly
 * that. ⚠️ Whether repeated calls leak is NOT yet known, and this project has
 * been bitten by that before: FN_LoadMatchState allocated and never freed, and
 * calling it per frame killed the room at 36 seconds every time.
 */
#include "rooms.h"

#define LOG_NOTICE 1

ROOMS_DEFINE_EXI_BUF;

static void room_log(const char *msg)
{
    u8 *buf = rooms_exi_buf;
    int i;

    buf[0] = 0xD0;        /* CMD_LOG_MESSAGE */
    buf[1] = 0;
    buf[2] = LOG_NOTICE;
    for (i = 0; i < ROOMS_EXI_BUF_SIZE - 4 && msg[i]; i++)
        buf[3 + i] = (u8)msg[i];
    buf[3 + i] = 0;
    FN_EXITransferBuffer(buf, ROOMS_EXI_BUF_SIZE, CONST_ExiWrite);
}

/* ------------------------------------------------------------------ layout */

/* Canvas space on this camera, measured rather than assumed: canvas (0,0) is
 * near the TOP-LEFT of the picture and +y runs DOWN - not the centre-origin
 * the character select uses. Writing this layout in the CSS's coordinates put
 * every line off the top-left corner the first time.
 *
 * Nothing is placed carefully yet. The band goes across the top once the
 * splash is building under it, and the queue and lobby columns go beneath it;
 * both want measuring against a real screenshot rather than guessing now and
 * moving everything twice. */
static const u32 COL_WHITE = 0xFFFFFFFF;

/* The old room's palette, and the reason there is more than one colour here.
 *
 * ⚠️ A subtext's colour is fixed WHEN IT IS CREATED. There is no way to recolour
 * one by rewriting its text, which is why joining the queue has to be TWO
 * subtexts sitting in the same place - a white one offering it and a green one
 * saying it is done - with whichever does not apply blanked. Swapping the
 * string alone leaves it white, which is the version that shipped. */
static const u32 COL_DONE = 0x33FF2FFF;   /* green: this one is done */
static const u32 COL_WAIT = 0x3CBCFFFF;   /* blue: waiting on you */
static const u32 COL_GRAY = 0x8E9196FF;
static const u32 COL_GOLD = 0xF5C442FF;  /* the highlight */

/* Position is in canvas units running roughly 0..640 across and 0..480 down,
 * with the origin near the TOP-LEFT - not the centre-origin the character
 * select uses.
 *
 * ⚠️ SIZE IS NOT IN THOSE UNITS. It is a scale factor, and the useful range is
 * about 0.45 to 0.55. Reading it as a point size and passing 18 drew a single
 * letter across the whole screen. */
#define ROOM_TEXT_X  40.0f
/* 40 down the picture, plus the 104 the splash is raised by in
 * Online/Menus/Room/RaiseSplash.asm - the room's text rides the same
 * cameras, so without this it goes up off the top of the screen along
 * with everything else. */
#define ROOM_TEXT_Y  144.0f
#define ROOM_TEXT_SZ 0.55f

/* The state line, sitting where NOW LOADING was.
 *
 * Deliberately NOT matching the splash's italic outlined lettering. There is no
 * way to reach that face from here, and a near-miss reads as a failed imitation
 * where an obvious difference reads as on purpose.
 *
 * Placed against a screenshot: NOW LOADING sat around screen row 255, and every
 * canvas Y here carries the 104 the splash is raised by, so 359. */
/* Measured off the screenshot of the last attempt rather than guessed again.
 * Setting X to 470 put the word at screen x 498 and ran it off the right edge
 * at 0.85, so both come down. NOW LOADING sits at about screen row 231, and
 * canvas Y carries the 104 the splash is raised by, so 335 lands on it. */
/* ⚠️ The stats line that used to live here is GONE. "Q0 L1 #0 P255/255 ST255"
 * sat across NOW LOADING, ran off the right-hand edge so the numbers after the
 * first were cut off anyway, and said nothing a player wanted. What the room is
 * doing is now shown by the two columns underneath.
 *
 * What takes its place is the STAGE, sitting INSIDE the picture with the black
 * beneath it acting as the line the text is written on. ⚠️ Not on the boundary
 * itself, which is where it started - straddling the edge put it half in the
 * blue and half over the players' names. */
#define ROOM_STAGE_X   134.0f
#define ROOM_STAGE_Y   317.0f
#define ROOM_STAGE_SZ  0.55f

/* The middle of the SCREEN, in canvas units, and the size of a letter.
 *
 * Both MEASURED, off a screen capture of a running room, rather than assumed -
 * the earlier numbers here were eyeballed and the VS sat 36 pixels right of
 * centre. The room's black render area ran x 2938..3771 on that capture, so the
 * middle of it is 3354; the two names, placed at canvas 60 and 420, put their
 * first letters at 3106 and 3490, which fixes a canvas unit at 1.0667 pixels
 * and lands the middle of the screen on canvas 293.
 *
 * ⚠️ The font is MONOSPACE for letters but its SPACE IS HALF A CELL.
 * "MrBirdMD" advanced 23.86px a letter at size 0.70 - a cell is 32 canvas units
 * times the size - while every letter after the space in "Peach's Castle"
 * landed half a cell early. That is what the old centring kept getting wrong:
 * it counted a space as a whole character, so a two-word stage name was pushed
 * half a cell right for every space in it. */
#define ROOM_CENTRE_X   293.0f
#define ROOM_CELL_UNITS  32.0f

/* The white VS, between the two names. The RED one is the splash's own artwork
 * and stays hidden - this is the small white one that sits between the players
 * on Slippi's versus screen.
 *
 * ⚠️ Sits so the two letters STRADDLE the middle of the screen, which is
 * why this is not ROOM_CENTRE_X itself: half of "VS" is one cell wide. */
#define ROOM_VS_SZ     0.70f
#define ROOM_VS_X      (ROOM_CENTRE_X - ROOM_CELL_UNITS * ROOM_VS_SZ)

/* The room's own name, top left under the title: ROOM QAFK PASS 5143.
 * A private room is masked until somebody holds L or R, so a code is not left
 * sitting on a stream.
 *
 * ⚠️ The mask is full-width multiplication signs, NOT asterisks. An asterisk
 * draws nothing here - the same as the star, the underscore and `>` - so the
 * first version rendered as "ROOM   PASS" with two empty gaps and looked like
 * the code had failed to arrive. */
/* ⚠️ Where the "Rooms" title used to be. The title said nothing a player in a
 * room needed - they know where they are - so it is gone and this has its
 * place, in the dark of the picture above the left fighter's head. */
#define ROOM_CODE_X     40.0f
#define ROOM_CODE_Y     96.0f
#define ROOM_CODE_SZ    0.50f
#define ROOM_HINT_Y    118.0f
#define ROOM_HINT_SZ    0.38f

/* And the two names, on the plate where DK and Zelda were - which is where the
 * Slippi usernames go. Placeholders until a room has players in it. */
/* Same: at Y 413 the names came out at screen row 322 and the plate wants 309,
 * and both were sitting too far right of where DK and Zelda were. */
#define ROOM_NAME_L_X   60.0f
#define ROOM_NAME_R_X  420.0f
/* ⚠️ Up from 400. They were sitting well below the picture with a band of
 * nothing between, and belong just under the fighters' feet. */
#define ROOM_NAME_Y    348.0f
#define ROOM_NAME_SZ   0.70f

/* Their crown counts, left of each name. Gold, like the queue's. */
#define ROOM_ACTIVE_NUM_L_X (ROOM_NAME_L_X - 26.0f)
#define ROOM_ACTIVE_NUM_R_X (ROOM_NAME_R_X - 26.0f)
#define ROOM_ACTIVE_NUM_SZ   0.50f

static void *s_text;
static int   s_stage_line = -1;  /* the stage, under the fighters     */
static int   s_vs_line = -1;     /* the white VS between the names    */
static int   s_code_line = -1;   /* ROOM QAFK PASS 5143               */
static int   s_hint_line = -1;   /* Press R or L to show              */
static int   s_head_queue = -1;
static int   s_head_lobby = -1;
static int   s_lobby_line[ROOMS_STATE_MAX_LOBBY];
static int   s_queue_crown[ROOMS_STATE_MAX_QUEUE];
static int   s_queue_num[ROOMS_STATE_MAX_QUEUE];
static int   s_name_l = -1;
static int   s_name_r = -1;
static int   s_active_num[2] = {-1, -1}; /* their crown counts */
static int   s_queue_line[ROOMS_STATE_MAX_QUEUE];
static int   s_join_sym = -1;    /* blue x, while it is still to do  */
static int   s_join_line = -1;   /* white, offering the queue        */
static int   s_done_sym = -1;    /* green -, once you are in it      */
static int   s_done_line = -1;   /* green, saying so                 */
static int   s_next_sym = -1;    /* blue +, what you can do next     */
static int   s_next_line = -1;   /* gray, offering practice          */
static int   s_spec_sym = -1;   /* Y to spectate                    */
static int   s_spec_line = -1;
static int   s_leaveq_sym = -1;  /* hold Z, out of the queue         */
static int   s_leaveq_line = -1;
static int   s_leaver_sym = -1;  /* hold B, out of the room          */
static int   s_leaver_line = -1;
static int   s_rule_lobby = -1;  /* the line under each heading      */
static int   s_rule_queue = -1;

/* The third column: everything you can do from here, one line each. The symbol
 * sits in its own subtext ahead of the words, which is how the old room did it
 * - a line can then change its symbol without redrawing the sentence.
 *
 * ⚠️ Smaller than the columns beside it, and it has to be. "Press START to Join
 * the Queue" is the longest string on the screen and at 0.45 it ran off the
 * right-hand edge and read "Press START to Join the".
 *
 * Top-aligned with the two headings rather than with the names under them, so
 * the three columns start on the same line. */
#define ROOM_ACT_SYM_X   356.0f
#define ROOM_ACT_X       376.0f
#define ROOM_ACT_Y       ROOM_HEAD_Y
#define ROOM_ACT_STEP     22.0f
#define ROOM_ACT_SZ       0.34f

/* Two columns under the picture: who is waiting, and who is just here.
 *
 *     Queue              Lobby
 *   2♛ Alpha             Charlie
 *     Bravo              Delta
 *
 * Six lines each, because that is what the reply carries; a seventh person is
 * in the room and in the queue, just not on the screen yet.
 *
 * ⚠️ The crown sits in its OWN subtext, ahead of the name, with the count drawn
 * on TOP of it rather than beside it - a number and a symbol side by side eat
 * twice the width and push the names out of line. Same trick the action lines
 * use for their symbols, and for the same reason a subtext's colour is fixed
 * when it is created. */
/* Three columns, left to right: who is here, who is waiting, and what you can
 * do about it.
 *
 *   Lobby            Queue            + Press START to Join the Queue
 *   -----            -----            + Press Y to Spectate
 *   Peppy          2 Alpha            - Hold Z to Leave the Queue
 *   Bravo            Charlie          - Hold B to Leave the Room
 *
 * ⚠️ Down and left of where they first went, which put them on top of the two
 * players' names. */
#define ROOM_COL_Y       424.0f
#define ROOM_COL_STEP     22.0f
#define ROOM_COL_SZ        0.45f

#define ROOM_LOBBY_X      40.0f
#define ROOM_LOBBY_Y     ROOM_COL_Y
#define ROOM_LOBBY_STEP  ROOM_COL_STEP
#define ROOM_LOBBY_SZ    ROOM_COL_SZ

#define ROOM_QUEUE_X     230.0f
#define ROOM_QUEUE_Y     ROOM_COL_Y
#define ROOM_QUEUE_STEP  ROOM_COL_STEP
#define ROOM_QUEUE_SZ    ROOM_COL_SZ

/* The headings, a line above their columns, with a rule under each.
 *
 * ⚠️ The rule is a row of FULL-WIDTH MINUS SIGNS, not underscores. An ASCII
 * underscore draws nothing here - the same way `>` and `*` do - so the first
 * version was invisible and looked like a placement problem. This is the very
 * character SYM_DONE already draws as the green dash beside "In the Queue",
 * which is the only proof that matters: it is on screen today. */
#define ROOM_HEAD_Y      (ROOM_COL_Y - 30.0f)
#define ROOM_HEAD_SZ      0.50f
/* ⚠️ 14 under the column, not 22. At 22 it sat eight units below a heading
 * drawn at size 0.5 - which is inside the letters, not under them. */
#define ROOM_RULE_Y      (ROOM_COL_Y - 12.0f)
#define ROOM_RULE_SZ      0.50f
#define ROOM_RULE        "\x81\x7C\x81\x7C\x81\x7C\x81\x7C"

/* The crown and its number, both at this X, one over the other. */
/* ⚠️ Left of the QUEUE column, which moved to the middle when Lobby took the
 * left. These stayed at 60 and drew a lonely number under "Lobby", a hundred
 * and seventy units from the name it belonged to. */
#define ROOM_CROWN_X     (ROOM_QUEUE_X - 24.0f)
#define ROOM_CROWN_SZ     0.45f
#define ROOM_CROWN_NUM_X (ROOM_QUEUE_X - 18.0f)
#define ROOM_CROWN_NUM_SZ 0.45f

/* ⚠️ This font has no ASCII star or asterisk - they draw nothing, which is why
 * the room's existing symbols are Shift-JIS full-width punctuation. This is the
 * black star, 0x81 0x99, the nearest thing to a crown that is likely to exist.
 * If it comes out blank, the candidates are in room_draw_crowns. */
#define SYM_CROWN "\x81\x99"

static int   s_said_hello;
static int   s_frames;

/* -------------------------------------------------------------- the module */

/* Cameras are GObj class 20 and park their CObj at +0x28 - but only some of
 * them do. Class 20 holds five GObjs here and three carry nothing at +0x28,
 * measured rather than assumed. Counting them is all this is still for. */
#define ROOM_CLASS_CAMERA 20

/* The room does NOT resize the splash, and why is worth keeping.
 *
 * Three rounds went into fitting a 4:3 picture into a band across the top:
 * squashing it with a 640x240 viewport, then shrinking it to 320x240 to keep
 * its proportions, then forcing that on every camera from CObj_SetCurrent
 * because the fighters kept escaping it. All of it solved a problem that was
 * not there.
 *
 * Melee already frames this screen the way a room wants it - the fighters fill
 * the width with their heads near the top, and the bottom third is the black
 * name plate, which against a black background has no visible seam. THAT is the
 * band, and the space underneath for the queue and the lobby is the splash's
 * own lower third. Shrinking it only made a correctly framed picture small and
 * left it floating in the middle of the screen.
 *
 * So the camera is left alone. If a real band is ever wanted, the control point
 * is CObj_SetCurrent and not anything reachable from here: the cameras a GObj
 * owns are not all of them, and the fighters are drawn through one that is not.
 * The commit that added that hook and the one that removed it are the record.
 */

static int s_banded = -1;

/* ------------------------------------------------------- saying what is there
 *
 * There is no printf in here, and the answers on this project have all come out
 * of the log, so it is worth the thirty lines. */
static char *room_put(char *p, const char *s)
{
    while (*s)
        *p++ = *s++;
    return p;
}

static char *room_put_i(char *p, int v)
{
    char tmp[12];
    int n = 0;

    if (v < 0) { *p++ = '-'; v = -v; }
    do { tmp[n++] = (char)('0' + (v % 10)); v /= 10; } while (v);
    while (n)
        *p++ = tmp[--n];
    return p;
}

/* Read the viewport back OUT of each camera, before anything is written to it.
 *
 * The question this exists to settle: the room writes a 320x240 viewport into
 * every camera it can find, every frame, and the fighters still draw at full
 * size down the whole screen. Either the write is not sticking - something
 * resets these between our think and the draw - or it is sticking and the
 * fighters are not drawn through any camera on this list. Those need opposite
 * fixes, and they look identical on screen.
 *
 * Ints, because the log takes a string and 320 is as much precision as this
 * question needs. */
#define ROOM_COBJ_VIEWPORT 0x0C

static void room_report_cams(void)
{
    void **heads = rooms_gobj_heads();
    void *g;
    int idx = 0;

    if (!heads)
        return;

    for (g = heads[ROOM_CLASS_CAMERA]; g; g = *(void **)((char *)g + ROOMS_GOBJ_NEXT))
    {
        void *cobj = *(void **)((char *)g + ROOMS_GOBJ_OBJECT);
        const float *vp;
        char line[96];
        char *p = line;

        if (!cobj)
            continue;
        vp = (const float *)((const char *)cobj + ROOM_COBJ_VIEWPORT);
        p = room_put(p, "[Rooms] cam ");
        p = room_put_i(p, idx++);
        p = room_put(p, " vp ");
        p = room_put_i(p, (int)vp[0]); *p++ = ' ';
        p = room_put_i(p, (int)vp[1]); *p++ = ' ';
        p = room_put_i(p, (int)vp[2]); *p++ = ' ';
        p = room_put_i(p, (int)vp[3]);
        *p = 0;
        room_log(line);
    }
}

static char *room_put_x(char *p, u32 v)
{
    static const char hex[] = "0123456789abcdef";
    int i;

    for (i = 28; i >= 0; i -= 4)
        *p++ = hex[(v >> i) & 0xF];
    return p;
}

/* Recorded rather than kept as code: of the five class-20 GObjs, only two carry
 * anything at +0x28, and both hold whatever viewport is written to them. The
 * fighters are drawn through a camera no GObj owns, which is why the band had
 * to be forced from CObj_SetCurrent. The probe that established that walked
 * each camera GObj's first words looking for something shaped like a CObj -
 * four floats at +0x0C making a screen-sized rectangle the right way round.
 */

/* NOW LOADING is drawn by a JObj on a class 3 GObj - the last candidate left.
 *
 * It is not in the splash's model tree, not a SIS string, and not one of the
 * text canvases: silencing both of those took the DK and Zelda plate with them
 * and left NOW LOADING exactly where it was. What the census leaves is class 3,
 * which nothing has ever touched, holding two generic JObj drawers on links 4
 * and 0 plus a light.
 *
 * Being a JObj is the useful part: the invisible flag works on those, which is
 * why it worked on the backdrop. The flag is a bit in a word - nothing is freed
 * and nothing is structural, so it cannot hang the way destroying links did.
 *
 * ⚠️ 2026-09-18: link 4 alone was NOT it. The census shows three GObjs in this
 * class, and hiding link 4 left NOW LOADING exactly where it was - see the loop.
 */
#define ROOM_CLASS_LOADING 3
#define ROOM_LOADING_LINK  4
#define ROOM_JOBJ_HIDDEN   0x10

static void room_hide_loading(void)
{
    void **heads = rooms_gobj_heads();
    void *g;

    if (!heads)
        return;

    for (g = heads[ROOM_CLASS_LOADING]; g;
         g = *(void **)((char *)g + ROOMS_GOBJ_NEXT))
    {
        u8 link = *(const u8 *)((const char *)g + ROOMS_GOBJ_LINK);
        u32 *flags;
        void *jobj;

        if (link != ROOM_LOADING_LINK)
            continue;
        jobj = *(void **)((char *)g + ROOMS_GOBJ_OBJECT);
        if (!jobj)
            continue;
        flags = (u32 *)((char *)jobj + ROOMS_JOBJ_FLAGS);
        *flags |= ROOM_JOBJ_HIDDEN;
        room_log("[Rooms] hid the class 3 link 4 jobj");
        return;
    }
    room_log("[Rooms] no class 3 link 4 jobj to hide");
}

/* The splash's own text, switched off.
 *
 * NOW LOADING is a TEXT canvas, not a model. It survived the invisible flag, a
 * whole-tree animation sweep and being hunted as a SIS string because none of
 * those touch text - and the census is what finally said so: three GObjs draw
 * through Text_GX with nothing at +0x28.
 *
 * They are class 20, the same class as the cameras, which is the other thing
 * that census settled. An earlier probe reported "2 cameras" out of five class
 * 20 GObjs and I read that as "there are two cameras". Three of them were text.
 *
 * Two belong to the splash - the DK/Zelda plate and NOW LOADING - and both go.
 * The names were placeholders standing where the Slippi usernames belong, so
 * losing them is the direction of travel rather than a casualty.
 *
 * Destroying the GX LINK, not the GObj: it stops drawing and nothing is freed,
 * so the splash's own Leave still has everything it expects on the way out.
 */
#define ROOM_TEXT_GX  ((void *)0x803A84BC)
/* ---------------------------------------------------------- the room state --
 *
 * Asked for by writing one command byte and reading the reply straight back,
 * the same write-then-read the file loader uses. The layout is in rooms.h, and
 * a copy of it lives in Dolphin's EXI_DeviceSlippi.h - change both.
 *
 * ⚠️ 32-byte aligned, because this is a DMA target.
 *
 * Not every frame. A tick lands every couple of seconds, so asking sixty times
 * a second is fifty-nine reads of the same bytes and an EXI transfer each time.
 */
#define ROOM_STATE_EVERY 30   /* frames - twice a second */

static u8 s_state_buf[ROOMS_STATE_SIZE] __attribute__((aligned(32)));
static int s_have_state;

/* What the fighters on the band were built from.
 *
 * RoomScenePrep reads the same three bytes on the way into this scene and
 * orders the models from them, so this is a record of what is actually on
 * screen. Logged once, because the status line runs off the edge of the band -
 * nothing acts on it any more. See the note above room_buttons for why. */
static u8 s_band_char_l = ROOMS_NOT_PICKED;
static u8 s_band_char_r = ROOMS_NOT_PICKED;
static u8 s_band_stage = ROOMS_NOT_PICKED;
static int s_band_known;

static void room_fetch_state(void)
{
    u8 *cmd = rooms_exi_buf;

    cmd[0] = CONST_SlippiCmdRoomState;
    FN_EXITransferBuffer(cmd, 1, CONST_ExiWrite);
    FN_EXITransferBuffer(s_state_buf, ROOMS_STATE_SIZE, CONST_ExiRead);

    if (!s_have_state && (s_state_buf[ROOMS_STATE_FLAGS] & ROOMS_FLAG_VALID))
    {
        /* Once, and worth saying: it is the first proof that anything the room
         * knows has reached the game. */
        s_have_state = 1;
        room_log("[Rooms] room state is coming through");
    }
}

/* One line saying what the room is doing, which is the thing a test needs to
 * see. Numbers rather than prose while this is being proved out: "3 queued,
 * you are 2nd" is a sentence, but "Q3 L0 #2" cannot be misread. */
/* The stage, on the bottom edge of the picture and between the two fighters.
 *
 * ⚠️ A NAME, not the id. The reply carries a number and nothing in Melee will
 * hand back the string for it from here, so the table is ours. Ids are the same
 * space the match block uses - 0x1F is Battlefield.
 *
 * Blank when nothing is being played, so an idle room shows a clean picture
 * rather than the name of a stage nobody is on. */
static const char *room_stage_name(u8 id)
{
    switch (id)
    {
    case 0x02: return "Peach's Castle";
    case 0x03: return "Rainbow Cruise";
    case 0x04: return "Kongo Jungle";
    case 0x05: return "Jungle Japes";
    case 0x06: return "Great Bay";
    case 0x07: return "Temple";
    case 0x08: return "Brinstar";
    case 0x09: return "Brinstar Depths";
    case 0x0A: return "Yoshi's Story";
    case 0x0B: return "Yoshi's Island";
    case 0x0C: return "Fountain of Dreams";
    case 0x0D: return "Green Greens";
    case 0x0E: return "Corneria";
    case 0x0F: return "Venom";
    case 0x10: return "Pokemon Stadium";
    case 0x11: return "Poke Floats";
    case 0x12: return "Mute City";
    case 0x13: return "Big Blue";
    case 0x14: return "Onett";
    case 0x15: return "Fourside";
    case 0x16: return "Icicle Mountain";
    case 0x18: return "Mushroom Kingdom";
    case 0x19: return "Mushroom Kingdom II";
    case 0x1B: return "Flat Zone";
    case 0x1C: return "Dream Land";
    case 0x1D: return "Yoshi's Island 64";
    case 0x1E: return "Kongo Jungle 64";
    case 0x1F: return "Battlefield";
    case 0x20: return "Final Destination";
    default:   return "";
    }
}

/* How many leading spaces put `s` across the middle of the screen, for a line
 * whose subtext was created at `anchor`.
 *
 * ⚠️ A space is HALF a cell - see ROOM_CELL_UNITS - so it is both the unit
 * this counts in and the reason the width has to be added up character by
 * character instead of taken from the length.
 *
 * The anchor is the leftmost this line can start, so a name too wide to centre
 * gets no padding rather than a negative amount of it. */
static int room_centre_pad(const char *s, float anchor, float size)
{
    float cell = ROOM_CELL_UNITS * size;
    float half = cell * 0.5f;
    float width = 0.0f;
    int i, n;

    for (i = 0; s[i]; i++)
        width += (s[i] == ' ') ? half : cell;

    n = (int)((((ROOM_CENTRE_X - width * 0.5f) - anchor) / half) + 0.5f);
    return n < 0 ? 0 : n;
}

/* The stage and the white VS, both of which belong to a match in progress and
 * neither of which should sit over an empty picture. */
static void room_draw_match(void)
{
    const u8 *st = s_state_buf;
    int live = (st[ROOMS_STATE_FLAGS] & ROOMS_FLAG_PLAYING) != 0;
    const char *stage = live ? room_stage_name(st[ROOMS_STATE_STAGE]) : "";

    /* ⚠️ Centred by PADDING, because there is no other way to do it here. A
     * subtext's position is fixed when it is made and nothing in reach moves
     * one afterwards, and there is no centred mode. So the line is anchored far
     * enough left for the longest name there is and shorter ones are pushed
     * right with spaces - but by the WIDTH they actually take, counting a space
     * as the half cell it is, not by their character count. */
    if (s_stage_line >= 0)
    {
        char padded[48];
        char *p = padded;
        /* An idle room writes a genuinely EMPTY line rather than the spaces
         * centring an empty string would ask for. */
        int pad = stage[0] ? room_centre_pad(stage, ROOM_STAGE_X, ROOM_STAGE_SZ) : 0;
        int i;

        for (i = 0; i < pad && i < 24; i++)
            *p++ = ' ';
        p = room_put(p, stage);
        *p = 0;
        Text_UpdateSubtextContents(s_text, s_stage_line, "%s", padded);
    }
    if (s_vs_line >= 0)
        Text_UpdateSubtextContents(s_text, s_vs_line, "%s", live ? "VS" : "");
}

/* ROOM QAFK PASS 5143, top left.
 *
 * ⚠️ A private room hides both until somebody holds R or L. The code and the
 * passcode together are everything needed to walk into a room, and a room
 * screen is exactly the thing that ends up on a stream.
 *
 * A PUBLIC room has no passcode - the schema allows one or the other, never
 * both - so it shows its code plainly and says nothing about a pass. */
static void room_draw_code(void)
{
    const u8 *st = s_state_buf;
    int private_room = (st[ROOMS_STATE_FLAGS] & ROOMS_FLAG_PRIVATE) != 0;
    int show = (rooms_pad_held() & (PAD_TRIGGER_L | PAD_TRIGGER_R)) != 0;
    const char *code = (const char *)st + ROOMS_STATE_CODE;
    const char *pass = (const char *)st + ROOMS_STATE_PASS;
    char line[48];
    char *p = line;

    if (!(st[ROOMS_STATE_FLAGS] & ROOMS_FLAG_VALID) || !code[0])
    {
        /* Blank rather than "no room" - making one takes two network calls
         * before the first tick can answer, and the line fills itself in. */
        line[0] = 0;
        if (s_code_line >= 0)
            Text_UpdateSubtextContents(s_text, s_code_line, "%s", "");
        if (s_hint_line >= 0)
            Text_UpdateSubtextContents(s_text, s_hint_line, "%s", "");
        return;
    }

    p = room_put(p, "ROOM ");
    p = room_put(p, (private_room && !show) ? "\x81\x7E\x81\x7E\x81\x7E\x81\x7E" : code);
    if (pass[0])
    {
        p = room_put(p, "  PASS ");
        p = room_put(p, (private_room && !show) ? "\x81\x7E\x81\x7E\x81\x7E\x81\x7E" : pass);
    }
    *p = 0;

    if (s_code_line >= 0)
        Text_UpdateSubtextContents(s_text, s_code_line, "%s", line);
    if (s_hint_line >= 0)
        Text_UpdateSubtextContents(s_text, s_hint_line, "%s",
                                   private_room && !show ? "Hold L or R to show" : "");
}

/* The two the room is playing, on the plate where the character names were.
 * Blank when nobody is - the reply keeps every slot at a fixed offset and
 * leaves the unused ones empty, so there is nothing to test for here. */
static void room_draw_players(void)
{
    int i;

    if (s_name_l >= 0)
        Text_UpdateSubtextContents(s_text, s_name_l, "%s",
                                   rooms_state_name(s_state_buf, 0));
    if (s_name_r >= 0)
        Text_UpdateSubtextContents(s_text, s_name_r, "%s",
                                   rooms_state_name(s_state_buf, 1));

    /* ⚠️ Their crowns too. These were drawn only down the queue, so a champion
     * was invisible for exactly as long as they were playing - which is when
     * anybody is looking at them. */
    for (i = 0; i < 2; i++)
    {
        u8 crowns = s_state_buf[ROOMS_STATE_CROWNS + i];
        const char *name = rooms_state_name(s_state_buf, i);
        char n[8];
        char *p = n;

        if (s_active_num[i] < 0)
            continue;
        if (name[0] && crowns)
            p = room_put_i(p, crowns);
        *p = 0;
        Text_UpdateSubtextContents(s_text, s_active_num[i], "%s", n);
    }
}

/* One row of a column: the name, and a crown with its count drawn over it.
 *
 * ⚠️ The count sits ON the crown, not beside it. A symbol and a number side by
 * side take twice the width and push every name out of line - and the number is
 * the thing being read, so it goes on top.
 *
 * Nobody with no crowns gets one. A row of empty crowns says "these people have
 * all won nothing", which is noise; an absent one says nothing at all. */
static void room_draw_row(int name_line, int crown_line, int num_line, int slot)
{
    const char *name = rooms_state_name(s_state_buf, slot);
    u8 crowns = s_state_buf[ROOMS_STATE_CROWNS + slot];

    if (name_line >= 0)
        Text_UpdateSubtextContents(s_text, name_line, "%s", name);

    /* ⚠️ The count on its own, in gold. There is no crown: this font has no
     * star, no asterisk and no underscore, and a probe of eight Shift-JIS
     * candidates drew a blank after every one of them. A number in the
     * winner's colour says the same thing and is a glyph that certainly
     * exists, which the symbol never was.
     *
     * crown_line is kept and left empty rather than removed, so putting a
     * symbol back is a one-line change if the font is ever properly mapped. */
    if (crown_line >= 0)
        Text_UpdateSubtextContents(s_text, crown_line, "%s", "");
    if (num_line >= 0)
    {
        char n[8];
        char *p = n;

        if (name[0] && crowns)
            p = room_put_i(p, crowns);
        *p = 0;
        Text_UpdateSubtextContents(s_text, num_line, "%s", n);
    }
}

/* The queue down the left, the lobby to its right.
 *
 * Names 2 upwards are the queue, in the order the room will actually pair them
 * - pd_tick sorts it the same way it picks, on purpose, so this list and the
 * next match cannot disagree - and the six after that are the lobby. */
static void room_draw_queue(void)
{
    int i;

    /* ⚠️ The headings are written HERE, every time, not once when they are
     * made. They used to be set at creation and never again - and
     * room_blank_room clears them, which every client that joins a room passes
     * through: there is always a poll or two before the first tick comes back
     * when the answer is "not in a room yet". So everyone except whoever made
     * the room lost their headings for good, and got them back only if
     * something happened to rebuild the scene. */
    if (s_head_lobby >= 0)
        Text_UpdateSubtextContents(s_text, s_head_lobby, "%s", "Lobby");
    if (s_head_queue >= 0)
        Text_UpdateSubtextContents(s_text, s_head_queue, "%s", "Queue");
    if (s_rule_lobby >= 0)
        Text_UpdateSubtextContents(s_text, s_rule_lobby, "%s", ROOM_RULE);
    if (s_rule_queue >= 0)
        Text_UpdateSubtextContents(s_text, s_rule_queue, "%s", ROOM_RULE);

    /* ⚠️ Said out loud when it changes, because a blank crown column has two
     * very different meanings and they look identical: nobody has won a room
     * yet, or the glyph does not exist in this font. A crown is not one win -
     * it is beating EVERYONE in the room - so "none" is the usual answer. */
    {
        static int said = -1;
        int total = 0;

        for (i = 0; i < ROOMS_STATE_NAMES; i++)
            total += s_state_buf[ROOMS_STATE_CROWNS + i];
        if (total != said)
        {
            char line[64];
            char *p = line;

            said = total;
            p = room_put(p, "[Rooms] crowns in this room: ");
            p = room_put_i(p, total);
            *p = 0;
            room_log(line);
        }
    }

    for (i = 0; i < ROOMS_STATE_MAX_QUEUE; i++)
        room_draw_row(s_queue_line[i], s_queue_crown[i], s_queue_num[i], 2 + i);

    for (i = 0; i < ROOMS_STATE_MAX_LOBBY; i++)
        room_draw_row(s_lobby_line[i], -1, -1,
                      2 + ROOMS_STATE_MAX_QUEUE + i);
}

/* ------------------------------------------------------------------ START --
 *
 * One button, two jobs, the way the old room had it: START puts you in the
 * queue, and once you are in it START is how you go and practise while you
 * wait. It is never how you leave.
 *
 * The two-line shape carries over as well. Not queued, there is one thing to do
 * and it is not done. Queued, that one is done and practising becomes the next
 * thing available - so the screen always has something on it, which a room that
 * opens in the state it is already in would never manage.
 */
#define STR_JOIN     "START to Join the Queue"
#define STR_IN_QUEUE "In the Queue"
#define STR_PRACTICE "Press START to Practice"
/* Takes the practice line's place while a match is on. There are three slots,
 * and while somebody is actually playing, watching is the more useful offer of
 * the two - practice is still there the rest of the time. */
#define STR_WATCH    "Y to Spectate"
#define STR_LEAVE_Q  "Hold Z to Leave the Queue"
#define STR_LEAVE_R  "Hold B to Leave the Room"

/* Shift-JIS, because this font has no ASCII for them: × is what is still to do,
 * − is done, + is what you can do next. */
#define SYM_TODO "\x81\x7E"
#define SYM_DONE "\x81\x7C"
#define SYM_NEXT "\x81\x7B"

/* The waiting symbol alternates the way Slippi's does while it searches: two
 * icons, fifteen frames each, and only while something is still waiting on you.
 * Once you are in the queue that line is done and stops moving. */
#define SPINNER_FRAMES 15

static int s_queued;
static int s_spin_frame;

/* Two lines in the same place, one blanked. That is how the colour changes. */
/* Are we in the queue?
 *
 * ⚠️ Not s_queued, which is local to this module and comes back as zero every
 * time the band is rebuilt and reloads us - the screen went on offering a queue
 * you were already standing in.
 *
 * ⚠️ And not POSITION either, which was the first fix and was also wrong.
 * pd_tick computes it as "how many are ahead of me, plus one", so a lobby
 * member who has pressed nothing gets 1 - the same as whoever is first in the
 * queue. It can never mean "not queued", whatever the field has always claimed.
 *
 * Dolphin sends a flag for it instead, from the queue state it holds itself. */
static int room_is_queued(void)
{
    return (s_state_buf[ROOMS_STATE_FLAGS] & ROOMS_FLAG_QUEUED) != 0;
}

static void room_show_actions(void)
{
    int playing = (s_state_buf[ROOMS_STATE_FLAGS] & ROOMS_FLAG_PLAYING) != 0;
    int queued = room_is_queued();

    /* Row one changes with you: offering the queue, or saying you are in it. */
    if (s_join_sym >= 0)
        Text_UpdateSubtextContents(s_text, s_join_sym, "%s",
                                   queued ? "" : SYM_TODO);
    if (s_join_line >= 0)
        Text_UpdateSubtextContents(s_text, s_join_line, "%s",
                                   queued ? "" : STR_JOIN);
    if (s_done_sym >= 0)
        Text_UpdateSubtextContents(s_text, s_done_sym, "%s",
                                   queued ? SYM_DONE : "");
    if (s_done_line >= 0)
        Text_UpdateSubtextContents(s_text, s_done_line, "%s",
                                   queued ? STR_IN_QUEUE : "");

    /* Row two: practice, which is what START does once you are already in the
     * queue. ⚠️ Its own row - it used to share row one with "In the Queue" and
     * the two drew on top of each other. */
    if (s_next_sym >= 0)
        Text_UpdateSubtextContents(s_text, s_next_sym, "%s",
                                   queued ? SYM_NEXT : "");
    if (s_next_line >= 0)
        Text_UpdateSubtextContents(s_text, s_next_line, "%s",
                                   queued ? STR_PRACTICE : "");

    /* Row three: spectating. ⚠️ Always, not only while a match is on. It is
     * something you can do in this room, and a line that appears and vanishes
     * with the state of somebody else's game reads as a glitch. */
    if (s_spec_sym >= 0)
        Text_UpdateSubtextContents(s_text, s_spec_sym, "%s",
                                   playing ? SYM_NEXT : "");
    if (s_spec_line >= 0)
        Text_UpdateSubtextContents(s_text, s_spec_line, "%s", STR_WATCH);

    /* Rows three and four: the two ways out.
     *
     * ⚠️ No symbol on either. The symbols ahead of the rows above mean
     * something - what is still to do, what is done, what is next - and a mark
     * against "hold B to leave" would be claiming one of those about an action
     * that is simply always available. Grey text and nothing else, the same
     * grey as the two headings, because that is how Slippi writes a hint.
     *
     * Leaving the QUEUE only appears when there is a queue to leave. Leaving
     * the ROOM is always there - it is the way out. */
    if (s_leaver_sym >= 0)
        Text_UpdateSubtextContents(s_text, s_leaver_sym, "%s", "");
    if (s_leaver_line >= 0)
        Text_UpdateSubtextContents(s_text, s_leaver_line, "%s", STR_LEAVE_R);
    if (s_leaveq_sym >= 0)
        Text_UpdateSubtextContents(s_text, s_leaveq_sym, "%s", "");
    if (s_leaveq_line >= 0)
        Text_UpdateSubtextContents(s_text, s_leaveq_line, "%s",
                                   queued ? STR_LEAVE_Q : "");

    s_spin_frame = 0;
}

static void room_spin(void)
{
    /* ⚠️ room_is_queued, not s_queued. The spinner animates the symbol in front
     * of the JOIN offer, and with the local flag cleared by a reload it kept
     * animating over the top of "In the Queue". */
    if (room_is_queued() || s_join_sym < 0)
        return;
    if (s_spin_frame % SPINNER_FRAMES == 0)
        Text_UpdateSubtextContents(s_text, s_join_sym, "%s",
                                   (s_spin_frame / SPINNER_FRAMES) ? SYM_TODO
                                                                   : SYM_NEXT);
    s_spin_frame = (s_spin_frame + 1) % (2 * SPINNER_FRAMES);
}

/* Telling Dolphin is what actually joins the queue - it goes on the next tick,
 * and until it does pd_tick leaves us out of the pairing and lists us in the
 * lobby instead. */
static void room_set_queued(int queued)
{
    u8 *cmd = rooms_exi_buf;

    s_queued = queued;
    cmd[0] = CONST_SlippiCmdRoomSetQueued;
    cmd[1] = (u8)(queued ? 1 : 0);
    FN_EXITransferBuffer(cmd, 2, CONST_ExiWrite);

    room_show_actions();
    room_log(queued ? "[Rooms] joined the queue" : "[Rooms] left the queue");
}

/* Off to practise.
 *
 * Training's CHARACTER SELECT first, not training itself - a match needs a
 * character in it and that is where one comes from. Going straight to the
 * in-game scene means a match of nobodies, which renders nothing.
 *
 * ⚠️ The pending byte is the minor id PLUS ONE. */
static void room_practice(void)
{
    room_log("[Rooms] off to practise");
    SCENE_CTRL.pending_minor = SCENE_NEXT_MINOR(ONLINE_MINOR_TRAIN_CSS);
    Scene_ExitMinor();
}

/* --------------------------------------------------------- off to a match --
 *
 * The room paired us with somebody, so ask Slippi to connect us to them and go
 * to the draft.
 *
 * ⚠️ DIRECT, against the opponent's connect code. The room decides WHO plays
 * WHO - that is the queue, the rotation, the winner staying - and Slippi's own
 * servers make the introduction, exactly as they do for any direct match. This
 * project owns no STUN, no NAT punching and no matchmaking server because of
 * this one call.
 *
 * The code arrives already Shift-JIS: CMD_FIND_OPPONENT hands it to the
 * matchmaking server in that encoding, so Dolphin converts on its side and this
 * copies bytes.
 *
 * Once only. The tick keeps saying "ready" for as long as the pairing stands,
 * and asking Slippi to find the same opponent sixty times would be sixty
 * searches.
 */
#define ROOM_MODE_DIRECT 2

static int s_match_started;
static int s_draft_entered;

static void room_start_match(void)
{
    u8 *cmd = rooms_exi_buf;
    int i;

    s_match_started = 1;

    cmd[0] = CONST_SlippiCmdFindOpponent;
    cmd[1] = ROOM_MODE_DIRECT;
    for (i = 0; i < 18; i++)
        cmd[2 + i] = s_state_buf[ROOMS_STATE_OPPCODE + i];
    FN_EXITransferBuffer(cmd, 20, CONST_ExiWrite);

    room_log("[Rooms] matched - asking Slippi to connect us");

}

/* And into the draft, once Slippi has actually connected the two.
 *
 * ⚠️ Not a moment earlier. The screens past this fork on the same connection
 * state, and anything below CONNECTION_SUCCESS opens them on their "searching"
 * branch - where a character cannot be locked in. Handing over early lands the
 * player on a screen that will not let them start.
 *
 * Setting the pending byte IS the request: the room's own SceneDecide reads it,
 * sees the draft was asked for, and fills in GamePrepData before the scene
 * loads. Slippi only ever reaches that screen between games of a set, so it
 * helps itself to things a room has never set up.
 */
static void room_go_to_draft(void)
{
    s_draft_entered = 1;
    room_log("[Rooms] connected - handing over to the draft");
    SCENE_CTRL.pending_minor = SCENE_NEXT_MINOR(ONLINE_MINOR_GAMESETUP);
    Scene_ExitMinor();
}

/* Y: watch the match the room is playing.
 *
 * No payload. Dolphin already holds the room state and therefore both players'
 * addresses, so the game only has to ask - nothing about where anybody is has
 * to come through here.
 *
 * ⚠️ Only while there IS a match. Asking otherwise would have Dolphin dial
 * whatever it last saw, and between matches that is two people who have
 * finished.
 */
static int s_watching;
static int s_was_playing = -1; /* forces the first decision */
static int s_was_queued = -1;  /* likewise                   */

static void room_watch(void)
{
    u8 *cmd = rooms_exi_buf;

    cmd[0] = CONST_SlippiCmdRoomWatch;
    FN_EXITransferBuffer(cmd, 1, CONST_ExiWrite);
    s_watching = 1;
    room_log("[Rooms] asked to watch");
}

/* Straight to the VS splash, skipping the character select.
 *
 * A watcher has nothing to pick and no way to advance a screen that wants a
 * pick. The splash is the last thing before a match and the thing that starts
 * one, and RoomSceneDecide does the rest - it names the 1P port, which nothing
 * else on this path will, and runs the splash's own init.
 *
 * ⚠️ Only once Dolphin says the watch is CONNECTED. Going early means arriving
 * at a match Dolphin cannot yet describe: it has no characters, no stage and no
 * seed until both players have said what they picked.
 */
static void room_go_to_watch(void)
{
    room_log("[Rooms] watching - handing over to the match");
    SCENE_CTRL.pending_minor = SCENE_NEXT_MINOR(ONLINE_MINOR_SPLASH);
    Scene_ExitMinor();
}

/* The two ways out, both on a HOLD rather than a press.
 *
 * B leaves the room altogether, Z steps back out of the queue. Held, because
 * both are easy to hit by accident on a screen where the only other controls
 * are Start and Y - and losing your place in a queue to a stray B is a worse
 * mistake than having to hold it for a moment.
 *
 * ⚠️ rooms_pad_held, not rooms_pad_pressed. Pressed fires on the frame the
 * button goes down and is gone the next one, so a counter built on it never
 * gets past 1.
 */

/* ⚠️ Declared up here rather than down with the browser's own statics, because
 * room_leave_room needs it and that sits above them. Which screen is showing
 * decides whether there was a room to leave at all. */
static int s_browsing;

#define ROOM_HOLD_FRAMES 60      /* one second at 60fps */

static int s_hold_b;
static int s_hold_z;

static void room_leave_room(void)
{
    u8 *cmd = rooms_exi_buf;

    room_log("[Rooms] leaving the room");

    /* ⚠️ The byte says whether there was a room to leave. Walking off the list
     * of public rooms is not leaving one - you were never in it - and the old
     * build's note records that saying otherwise drops the client out of the
     * room it was already in. */
    cmd[0] = CONST_SlippiCmdRoomLeave;
    cmd[1] = (u8)!s_browsing;
    FN_EXITransferBuffer(cmd, 2, CONST_ExiWrite);

    /* Out to the menu. ⚠️ Both halves, in this order: the pending MINOR is
     * cleared so nothing of ours is next, the major is written through
     * MenuController_WriteToPendingMajor_1to_0xC, and only then does the minor
     * end - Scene_ProcessMajor only looks at the major flag between minors, so
     * ending the minor first lands you back where you started. */
    SCENE_CTRL.pending_minor = 0;
    MenuController_WriteToPendingMajor_1to_0xC(SCENE_MAJOR_MAIN_MENU);
    Scene_ExitMinor();
}

/* Rebuild the band around what the pair actually picked.
 *
 * The models are FILES, ordered in RoomScenePrep before the scene loads, and
 * the draft happens long after that - everyone else is already sitting in the
 * room while two of them choose. So the band is rebuilt by re-entering the room
 * scene, which runs that prep again with the picks in hand.
 *
 * ⚠️ This froze the room once, 2026-09-18: three rebuilds inside five seconds
 * and the third never came back - "room scene load" with no "splash built"
 * after it. Two things have changed since, and the guards below are the third.
 *
 * ⚠️ It was NOT a heap leak, which is what I said at the time and used as the
 * reason to take it out. Measured 2026-09-19: the heap cursor reads the same
 * address on every room entry, so the scene heap is reset in full each time.
 *
 * What actually caused those three was the PICK bug - the draft reported the
 * field it was not choosing as 0, so the band saw 0/0, then 20/0, then 20/5.
 * Picks now come from the resolved match and change once per game.
 *
 * ⚠️ The remaining suspect is the old build's note on this exact approach:
 * "its models are a preload nothing in this scene advances". The two rebuilds
 * that SURVIVED used characters already in memory; the one that hung wanted
 * Bowser, which was not. If a re-entry does not finish loading a new fighter's
 * file, the build waits for it for ever - and that looks precisely like a hang
 * inside SceneLoad_ClassicModeSplash. The log either side of the build is there
 * to tell the two stories apart.
 */
#define ROOM_REBUILD_COOLDOWN 180   /* three seconds, in frames */

static int s_rebuild_cooldown;

static void room_rebuild_band(void)
{
    u8 l = s_state_buf[ROOMS_STATE_HOST_CHAR];
    u8 r = s_state_buf[ROOMS_STATE_GUEST_CHAR];
    u8 st = s_state_buf[ROOMS_STATE_STAGE];

    /* ⚠️ Not in the first second of a scene. A rebuild reloads this module, so
     * everything here starts again from zero - and if the state read on the way
     * in disagreed even briefly with what RoomScenePrep built from, a rebuild
     * could ask for another immediately. Letting the room settle first means a
     * loop cannot start, and a loop here is a room nobody can even leave. */
    if (!s_band_known || s_rebuild_cooldown > 0 || s_frames < 60)
        return;
    /* ⚠️ Only a COMPLETE draft. A half-filled one is a band that would have to
     * be rebuilt again a moment later, and stacking these is what went wrong. */
    if (l == ROOMS_NOT_PICKED || r == ROOMS_NOT_PICKED || st == ROOMS_NOT_PICKED)
        return;
    if (l == s_band_char_l && r == s_band_char_r && st == s_band_stage)
        return;

    {
        char line[80];
        char *p = line;

        p = room_put(p, "[Rooms] band out of date - rebuilding for ");
        p = room_put_i(p, l);
        p = room_put(p, "/");
        p = room_put_i(p, r);
        p = room_put(p, " on ");
        p = room_put_i(p, st);
        *p = 0;
        room_log(line);
    }

    /* ⚠️ Set BEFORE the scene change, not after - there is no after. Melee
     * leaves the scene inside Scene_ExitMinor and this module is reloaded, so
     * anything written past this line never runs. The cooldown survives only
     * because the reload resets it to zero anyway, which is the same thing. */
    s_rebuild_cooldown = ROOM_REBUILD_COOLDOWN;

    SCENE_CTRL.pending_minor = SCENE_NEXT_MINOR(ONLINE_MINOR_ROOM);
    Scene_ExitMinor();
}

static void room_buttons(void)
{
    u32 pressed = rooms_pad_pressed();
    u32 held = rooms_pad_held();

    if (pressed & PAD_START)
    {
        if (!s_queued)
            room_set_queued(1);
        else
            room_practice();
    }

    if ((pressed & PAD_Y) && (s_state_buf[ROOMS_STATE_FLAGS] & ROOMS_FLAG_PLAYING))
        room_watch();

    /* Hold B: out of the room. */
    s_hold_b = (held & PAD_B) ? s_hold_b + 1 : 0;
    if (s_hold_b == ROOM_HOLD_FRAMES)
    {
        s_hold_b = 0;
        room_leave_room();
        return;
    }

    /* Hold Z: out of the queue, staying in the room. Nothing to do if we are
     * not in it. */
    s_hold_z = (held & PAD_Z) ? s_hold_z + 1 : 0;
    if (s_hold_z == ROOM_HOLD_FRAMES)
    {
        s_hold_z = 0;
        if (s_queued)
        {
            room_log("[Rooms] stepping out of the queue");
            room_set_queued(0);
        }
    }
}

/* ----------------------------------------------------------- the browser --
 *
 * Public lands here: the public rooms, one a line.
 *
 *     Singles     HSJK   MrBirdMD          2/8
 *     type        name   host              size
 *
 * One SUBTEXT per row rather than one per column, with the columns made by
 * padding. This font draws at a fixed width, so padding lines up - and a row
 * per line is twelve subtexts instead of forty-eight, which matters because
 * nothing here knows what Melee's limit is.
 *
 * ⚠️ The highlight is a COLOUR, not a caret. This font has no ASCII '>' and a
 * '[' wedges the text draw, both found the hard way on the old room. A
 * subtext's colour is fixed when it is created, so each row is drawn TWICE -
 * white and gold, in the same place - and whichever does not apply is blanked.
 */
#define ROOM_BROWSE_ROWS   6
#define ROOM_BROWSE_X     40.0f
#define ROOM_BROWSE_HEAD_Y 380.0f
#define ROOM_BROWSE_Y     406.0f
#define ROOM_BROWSE_STEP   20.0f
#define ROOM_BROWSE_SZ     0.42f

/* Column widths, in characters. The last one is not padded - nothing follows
 * it, and a trailing run of spaces is just more string to draw. */
#define COL_TYPE  12
#define COL_NAME   7
#define COL_HOST  17

static const char *const ROOM_MODE_NAME[] = {
    "Singles", "Doubles", "Ironmans", "Crew", "Tournament"};

static u8 s_list_buf[ROOMS_LIST_SIZE] __attribute__((aligned(32)));
static int s_browse_row[ROOM_BROWSE_ROWS];
static int s_browse_sel[ROOM_BROWSE_ROWS];
static int s_browse_head = -1;
static int s_browse_note = -1;
static int s_browse_pick;
/* Starts at "browsing", so the first frame always counts as a change: a room
 * entered directly still needs its band switched on and its actions drawn. */
static int s_was_browsing = 1;
/* ...but a room entered to BROWSE starts equal to it and so counted as no
 * change at all, and never had its band switched OFF. The first decision is
 * always acted on, whichever way it goes. */
static int s_screen_known;

static void room_fetch_list(void)
{
    u8 *cmd = rooms_exi_buf;

    cmd[0] = CONST_SlippiCmdRoomListRead;
    FN_EXITransferBuffer(cmd, 1, CONST_ExiWrite);
    FN_EXITransferBuffer(s_list_buf, ROOMS_LIST_SIZE, CONST_ExiRead);
}

/* Pad to a column width, truncating anything that would push the next column
 * along - a long name must not shove the whole row out of line. */
static char *room_put_col(char *p, const char *s, int width)
{
    int i = 0;

    while (s[i] && i < width - 1)
    {
        *p++ = s[i];
        i++;
    }
    while (i < width)
    {
        *p++ = ' ';
        i++;
    }
    return p;
}

static void room_draw_browser(void)
{
    const u8 *b = s_list_buf;
    int fetched = b[ROOMS_LIST_FLAGS] & ROOMS_LIST_FETCHED;
    int count = b[ROOMS_LIST_COUNT];
    int i;

    if (count > ROOM_BROWSE_ROWS)
        count = ROOM_BROWSE_ROWS;
    if (s_browse_pick >= count)
        s_browse_pick = count > 0 ? count - 1 : 0;

    /* ⚠️ These are different things and they want different words. An empty
     * list before the first reply is not "there are none". */
    if (s_browse_note >= 0)
        Text_UpdateSubtextContents(
            s_text, s_browse_note, "%s",
            !fetched ? "Looking for rooms..."
                     : (count == 0 ? "No public rooms right now" : ""));

    for (i = 0; i < ROOM_BROWSE_ROWS; i++)
    {
        char line[80];
        char *p = line;

        if (i < count)
        {
            const u8 *e = rooms_list_entry(b, i);
            u8 mode = e[ROOMS_LIST_MODE];

            p = room_put_col(p, mode < 5 ? ROOM_MODE_NAME[mode] : "Room",
                             COL_TYPE);
            p = room_put_col(p, (const char *)(e + ROOMS_LIST_CODE), COL_NAME);
            p = room_put_col(p, (const char *)(e + ROOMS_LIST_OWNER), COL_HOST);
            p = room_put_i(p, e[ROOMS_LIST_PLAYERS]);
            /* ⚠️ Shift-JIS solidus, not ASCII '/'. This font does not have the
             * ASCII one - the size column drew "1" and then stopped dead, the
             * same way '#' vanished out of the status line. Every symbol that
             * does work here lives in this same 0x81 block. */
            p = room_put(p, "^");
            p = room_put_i(p, e[ROOMS_LIST_CAPACITY]
                                  ? e[ROOMS_LIST_CAPACITY]
                                  : ROOMS_CAPACITY_UNKNOWN);
        }
        *p = 0;

        /* Drawn twice, one blanked. That is the highlight. */
        if (s_browse_row[i] >= 0)
            Text_UpdateSubtextContents(s_text, s_browse_row[i], "%s",
                                       i == s_browse_pick ? "" : line);
        if (s_browse_sel[i] >= 0)
            Text_UpdateSubtextContents(s_text, s_browse_sel[i], "%s",
                                       i == s_browse_pick ? line : "");
    }
}

/* Joining is telling Dolphin the code. The heartbeat starting IS the join -
 * pd_tick inserts the member row on its first call - so there is nothing else
 * to send and nothing to get out of step with. */
static void room_join_pick(void)
{
    const u8 *b = s_list_buf;
    const u8 *e;
    u8 *cmd = rooms_exi_buf;
    int i;

    if (s_browse_pick >= b[ROOMS_LIST_COUNT])
        return;

    e = rooms_list_entry(b, s_browse_pick);
    cmd[0] = CONST_SlippiCmdRoomJoin;
    for (i = 0; i < 4; i++)
        cmd[1 + i] = e[ROOMS_LIST_CODE + i];
    FN_EXITransferBuffer(cmd, 5, CONST_ExiWrite);

    room_log("[Rooms] joining a room from the list");
}

/* The two screens share one text struct, so whichever is not showing has to be
 * emptied - a subtext nobody rewrites keeps drawing whatever it last said, and
 * the browser's rows would sit under the room's queue for ever. */
/* ---------------------------------------------- the band, on and off again --
 *
 * The browser is a different place from a room, so it does not borrow the
 * room's picture: no fighters, no backdrop, no NOW LOADING. Just the list.
 *
 * Hidden by FLAG rather than by destroying anything, because this has to come
 * back the moment somebody joins. GObj_DestroyGXLink is one-way; the JObj
 * hidden bit is a bit, and clearing it puts the picture back exactly as it was.
 *
 * ⚠️ Only GObjs whose draw callback is known to take a JOBJ. Class 15 also
 * holds the fog, whose object at +0x28 is a fog descriptor - writing a hidden
 * flag into that would be scribbling on something else entirely. The callback
 * is the only reliable way to tell them apart, which the GObj census is what
 * established.
 */
/* The splash's own GObj class. Named here because the helper that used to
 * define it became a comment when the camera work came out - and a class
 * number on its own tells the next reader nothing. */
#define ROOM_CLASS_SPLASH 15

#define ROOM_DRAW_COMMON  0x80391070   /* GXLink_Common - the splash tree     */
#define ROOM_DRAW_FIGHTER 0x80080E18   /* FighterGX_OnscreenDraw - the two    */
#define ROOM_DRAW_JOBJ_A  0x8009F54C   /* plain jobj drawers, class 3         */
#define ROOM_DRAW_JOBJ_B  0x801C4640

static int room_draws_jobj(u32 fn)
{
    return fn == ROOM_DRAW_COMMON || fn == ROOM_DRAW_FIGHTER ||
           fn == ROOM_DRAW_JOBJ_A || fn == ROOM_DRAW_JOBJ_B;
}

static void room_show_band(int show)
{
    static const int classes[] = {3, 8, ROOM_CLASS_SPLASH};
    void **heads = rooms_gobj_heads();
    unsigned int c;

    if (!heads)
        return;

    for (c = 0; c < sizeof(classes) / sizeof(classes[0]); c++)
    {
        void *g;

        for (g = heads[classes[c]]; g;
             g = *(void **)((char *)g + ROOMS_GOBJ_NEXT))
        {
            u32 fn = *(const u32 *)((const char *)g + ROOMS_GOBJ_DRAWFN);
            void *jobj = *(void **)((char *)g + ROOMS_GOBJ_OBJECT);
            u32 *flags;

            if (!jobj || !room_draws_jobj(fn))
                continue;
            flags = (u32 *)((char *)jobj + ROOMS_JOBJ_FLAGS);
            if (show)
                *flags &= ~(u32)ROOM_JOBJ_HIDDEN;
            else
                *flags |= (u32)ROOM_JOBJ_HIDDEN;
        }
    }
}

/* The two fighters, on and off, without touching anything else on the band.
 *
 * An idle room should not claim two people are about to play, but it still
 * needs its picture: the camera, the backdrop and the text all come from a
 * splash that was built in full.
 *
 * ⛔ The one-byte version of this does not work. Writing 26 into the character
 * slots makes SceneLoad_ClassicModeSplash build nothing at all - and the camera
 * is part of nothing. The log said "banded 0 cam", classes 20 and 21 were
 * missing entirely, and the room was black: with no camera even the text has
 * nothing to draw through. So the scene is built exactly as it always was and
 * the two models are covered afterwards.
 *
 * Same flag the browser uses to put the whole band away, on the same GObjs -
 * narrowed to the fighters by their draw callback, which is the only reliable
 * way to tell them from the rest of the tree.
 */
static void room_show_fighters(int show)
{
    static const int classes[] = {3, 8, ROOM_CLASS_SPLASH};
    void **heads = rooms_gobj_heads();
    unsigned int c;

    if (!heads)
        return;

    for (c = 0; c < sizeof(classes) / sizeof(classes[0]); c++)
    {
        void *g;

        for (g = heads[classes[c]]; g;
             g = *(void **)((char *)g + ROOMS_GOBJ_NEXT))
        {
            u32 fn = *(const u32 *)((const char *)g + ROOMS_GOBJ_DRAWFN);
            void *jobj = *(void **)((char *)g + ROOMS_GOBJ_OBJECT);

            if (!jobj || fn != ROOM_DRAW_FIGHTER)
                continue;

            /* ⚠️ The WHOLE model, not the root joint. Writing the flag straight
             * into the root hid Bowser's body and left his shell spikes
             * floating in mid air - they hang off child joints, and each joint
             * is tested on its own on the way down. */
            if (show)
                JOBJ_ClearFlagsAll(jobj, ROOM_JOBJ_HIDDEN);
            else
                JOBJ_SetFlagsAll(jobj, ROOM_JOBJ_HIDDEN);
        }
    }
}

static void room_blank_browser(void)
{
    int i;

    if (s_browse_head >= 0)
        Text_UpdateSubtextContents(s_text, s_browse_head, "%s", "");
    if (s_browse_note >= 0)
        Text_UpdateSubtextContents(s_text, s_browse_note, "%s", "");
    for (i = 0; i < ROOM_BROWSE_ROWS; i++)
    {
        if (s_browse_row[i] >= 0)
            Text_UpdateSubtextContents(s_text, s_browse_row[i], "%s", "");
        if (s_browse_sel[i] >= 0)
            Text_UpdateSubtextContents(s_text, s_browse_sel[i], "%s", "");
    }
}

static void room_blank_room(void)
{
    int i;

    /* Everything the room draws and the browser does not. ⚠️ The headings and
     * the crowns as well - a "Queue" with nothing under it over a list of
     * public rooms reads as a broken screen. */
    if (s_stage_line >= 0)
        Text_UpdateSubtextContents(s_text, s_stage_line, "%s", "");
    if (s_vs_line >= 0)
        Text_UpdateSubtextContents(s_text, s_vs_line, "%s", "");
    if (s_code_line >= 0)
        Text_UpdateSubtextContents(s_text, s_code_line, "%s", "");
    if (s_hint_line >= 0)
        Text_UpdateSubtextContents(s_text, s_hint_line, "%s", "");
    if (s_head_queue >= 0)
        Text_UpdateSubtextContents(s_text, s_head_queue, "%s", "");
    if (s_head_lobby >= 0)
        Text_UpdateSubtextContents(s_text, s_head_lobby, "%s", "");
    if (s_rule_lobby >= 0)
        Text_UpdateSubtextContents(s_text, s_rule_lobby, "%s", "");
    if (s_rule_queue >= 0)
        Text_UpdateSubtextContents(s_text, s_rule_queue, "%s", "");
    if (s_name_l >= 0)
        Text_UpdateSubtextContents(s_text, s_name_l, "%s", "");
    if (s_name_r >= 0)
        Text_UpdateSubtextContents(s_text, s_name_r, "%s", "");
    if (s_active_num[0] >= 0)
        Text_UpdateSubtextContents(s_text, s_active_num[0], "%s", "");
    if (s_active_num[1] >= 0)
        Text_UpdateSubtextContents(s_text, s_active_num[1], "%s", "");
    for (i = 0; i < ROOMS_STATE_MAX_QUEUE; i++)
    {
        if (s_queue_line[i] >= 0)
            Text_UpdateSubtextContents(s_text, s_queue_line[i], "%s", "");
        if (s_queue_crown[i] >= 0)
            Text_UpdateSubtextContents(s_text, s_queue_crown[i], "%s", "");
        if (s_queue_num[i] >= 0)
            Text_UpdateSubtextContents(s_text, s_queue_num[i], "%s", "");
    }
    for (i = 0; i < ROOMS_STATE_MAX_LOBBY; i++)
        if (s_lobby_line[i] >= 0)
            Text_UpdateSubtextContents(s_text, s_lobby_line[i], "%s", "");

    /* The action lines belong to the room, not the browser: there is no queue
     * to join until you are in one. */
    if (s_join_sym >= 0)
        Text_UpdateSubtextContents(s_text, s_join_sym, "%s", "");
    if (s_join_line >= 0)
        Text_UpdateSubtextContents(s_text, s_join_line, "%s", "");
    if (s_done_sym >= 0)
        Text_UpdateSubtextContents(s_text, s_done_sym, "%s", "");
    if (s_done_line >= 0)
        Text_UpdateSubtextContents(s_text, s_done_line, "%s", "");
    if (s_next_sym >= 0)
        Text_UpdateSubtextContents(s_text, s_next_sym, "%s", "");
    if (s_next_line >= 0)
        Text_UpdateSubtextContents(s_text, s_next_line, "%s", "");
    /* ⚠️ And the three rows added after this function was written. They were
     * not in it, so "Y to Spectate" and "Hold B to Leave the Room" sat over the
     * list of public rooms - offering to spectate a match in a room the reader
     * is not in, and to leave one they have not joined. */
    if (s_spec_sym >= 0)
        Text_UpdateSubtextContents(s_text, s_spec_sym, "%s", "");
    if (s_spec_line >= 0)
        Text_UpdateSubtextContents(s_text, s_spec_line, "%s", "");
    if (s_leaveq_sym >= 0)
        Text_UpdateSubtextContents(s_text, s_leaveq_sym, "%s", "");
    if (s_leaveq_line >= 0)
        Text_UpdateSubtextContents(s_text, s_leaveq_line, "%s", "");
    if (s_leaver_sym >= 0)
        Text_UpdateSubtextContents(s_text, s_leaver_sym, "%s", "");
    if (s_leaver_line >= 0)
        Text_UpdateSubtextContents(s_text, s_leaver_line, "%s", "");
}

static void room_browse_buttons(void)
{
    u32 pressed = rooms_pad_pressed();
    int count = s_list_buf[ROOMS_LIST_COUNT];

    if (count > ROOM_BROWSE_ROWS)
        count = ROOM_BROWSE_ROWS;

    if ((pressed & (PAD_STICK_UP | PAD_DPAD_LEFT)) && s_browse_pick > 0)
        s_browse_pick--;
    if ((pressed & (PAD_STICK_DOWN | PAD_DPAD_RIGHT)) &&
        s_browse_pick + 1 < count)
        s_browse_pick++;
    if (pressed & PAD_A)
        room_join_pick();

    /* Out the same way a room is left. ⚠️ Not the same thing underneath: the
     * byte room_leave_room sends says we were only looking at the list, so
     * nobody's membership is touched.
     *
     * ⚠️ A PRESS here, not a hold. Holding is for leaving a room, where a
     * mistake costs you your place in a queue - stepping off a list of rooms
     * costs nothing, and B is what anybody will press. Deliberately unlabelled:
     * backing out of a list is not a thing that needs explaining. */
    if (pressed & PAD_B)
        room_leave_room();
}

#define ROOM_MAX_TEXT 8

static void *s_our_text_gobj;

static int room_is_text_gobj(void *g)
{
    return *(void **)((char *)g + ROOMS_GOBJ_DRAWFN) == ROOM_TEXT_GX;
}

/* Anything drawing text that is not ours. Called after our own text exists, so
 * "not ours" is a complete description of the splash's. */
static void room_silence_splash_text(void)
{
    void *hit[ROOM_MAX_TEXT];
    void **heads = rooms_gobj_heads();
    void *g;
    int n = 0;
    int i;

    if (!heads)
        return;

    /* Collected first, destroyed after.
     *
     * ⚠️ GObj_DestroyGXLink relinks the list this loop is walking, so calling it
     * inside the walk means reading a next pointer that has already moved. The
     * first version did exactly that and the room hung on its opening frame. */
    for (g = heads[ROOM_CLASS_CAMERA]; g && n < ROOM_MAX_TEXT;
         g = *(void **)((char *)g + ROOMS_GOBJ_NEXT))
    {
        if (g == s_our_text_gobj || !room_is_text_gobj(g))
            continue;
        hit[n++] = g;
    }

    for (i = 0; i < n; i++)
        GObj_DestroyGXLink(hit[i]);
}

/* Which GObj of the text ones is ours: the one that was not there a moment ago.
 * Called side by side with creating it, so the difference is exactly ours. */
static void room_note_our_text(void *before[], int n_before)
{
    void **heads = rooms_gobj_heads();
    void *g;

    if (!heads)
        return;

    for (g = heads[ROOM_CLASS_CAMERA]; g;
         g = *(void **)((char *)g + ROOMS_GOBJ_NEXT))
    {
        int i, seen = 0;

        if (!room_is_text_gobj(g))
            continue;
        for (i = 0; i < n_before; i++)
            if (before[i] == g)
                seen = 1;
        if (!seen)
        {
            s_our_text_gobj = g;
            return;
        }
    }
}

static int room_snapshot_text(void *out[], int max)
{
    void **heads = rooms_gobj_heads();
    void *g;
    int n = 0;

    if (!heads)
        return 0;
    for (g = heads[ROOM_CLASS_CAMERA]; g && n < max;
         g = *(void **)((char *)g + ROOMS_GOBJ_NEXT))
        if (room_is_text_gobj(g))
            out[n++] = g;
    return n;
}

/* Every GObj, and the function that DRAWS it.
 *
 * NOW LOADING has now survived the invisible flag, a whole-tree animation
 * sweep, and being looked for as a SIS text - so it is not in the splash's
 * model tree and it is not that text. It is drawn by something, though, and
 * every GObj records what: GObj_AddGXLink parks the callback at +0x1C and the
 * render link at +0x03.
 *
 * So instead of hiding things to see what disappears - which is what the last
 * several attempts did, and what cost the fighters their placement - print the
 * callback for every GObj and look the addresses up in the DOL. That names them
 * outright: GXLink_Common, HSD_SetFog and the rest all have symbols.
 *
 * Once, and non-destructive. It changes nothing on screen. */
static void room_report_gobjs(void)
{
    void **heads = rooms_gobj_heads();
    int c;

    if (!heads)
        return;

    for (c = 0; c < 32; c++)
    {
        void *g;
        int n = 0;

        for (g = heads[c]; g && n < 8;
             g = *(void **)((char *)g + ROOMS_GOBJ_NEXT), n++)
        {
            char line[80];
            char *p = line;
            u8 link = *(const u8 *)((const char *)g + ROOMS_GOBJ_LINK);
            u32 fn  = *(const u32 *)((const char *)g + ROOMS_GOBJ_DRAWFN);
            u32 obj = *(const u32 *)((const char *)g + ROOMS_GOBJ_OBJECT);

            p = room_put(p, "[Rooms] c");
            p = room_put_i(p, c);
            p = room_put(p, " l");
            p = room_put_i(p, link);
            p = room_put(p, " draw ");
            p = room_put_x(p, fn);
            p = room_put(p, " obj ");
            p = room_put_x(p, obj);
            *p = 0;
            room_log(line);
        }
    }
}

/* Which GObj classes have anything in them.
 *
 * Two cameras were found and banded and the fighters ignored both. The old room
 * counted FIVE cameras on this same screen, so either this scene is built
 * differently or the walk is missing some - and if the fighters are drawn from
 * a class this does not know about, that shows up here as a populated class
 * nobody has accounted for. Cheap, and printed once. */
static void room_report_classes(void)
{
    void **heads = rooms_gobj_heads();
    char line[112];
    char *p = line;
    int c;

    if (!heads)
        return;

    p = room_put(p, "[Rooms] class:n");
    for (c = 0; c < 32; c++)
    {
        void *g;
        int n = 0;

        for (g = heads[c]; g; g = *(void **)((char *)g + ROOMS_GOBJ_NEXT))
            if (++n > 99)
                break;
        if (!n)
            continue;
        if (p - line > 92)
            break;
        *p++ = ' ';
        p = room_put_i(p, c);
        *p++ = ':';
        p = room_put_i(p, n);
    }
    *p = 0;
    room_log(line);
}

static void room_count_cams(void)
{
    void **heads = rooms_gobj_heads();
    void *g;
    int n = 0;

    if (!heads)
    {
        room_log("[Rooms] no gobj heads - cannot band the camera");
        return;
    }

    for (g = heads[ROOM_CLASS_CAMERA]; g; g = *(void **)((char *)g + ROOMS_GOBJ_NEXT))
    {
        void *cobj = *(void **)((char *)g + ROOMS_GOBJ_OBJECT);

        if (!cobj)
            continue;
        n++;
    }

    /* Counted rather than assumed: "the band did not move" and "there was no
     * camera to move" look identical on screen.
     *
     * Only when the count CHANGES, because this runs every frame now and a log
     * line per frame drowns out everything else - which is where every answer
     * on this project has come from so far. The change IS the interesting
     * event anyway: it is a camera arriving late. */
    if (n == s_banded)
        return;
    s_banded = n;
    {
        char line[48];
        int i = 0;
        const char *pre = "[Rooms] banded ";

        while (pre[i]) { line[i] = pre[i]; i++; }
        line[i++] = (char)('0' + (n % 10));
        line[i++] = ' ';
        line[i++] = 'c'; line[i++] = 'a'; line[i++] = 'm';
        line[i] = 0;
        room_log(line);
    }
}

/* What the splash builds from lives in the minor data, and RoomScenePrep fills
 * it - see the room's entry in main.asm. It is not done here, for two reasons.
 *
 * The first is ordering. A fighter's model is a FILE, read off the disc across
 * frames, and it has to be requested before anything can draw it. ScenePrep is
 * where a scene does that, so the request goes in there and the files are on
 * their way before this load is ever called.
 *
 * The second is that the offsets this used to write were wrong. It set +0x10
 * and +0x11 and called them "character one and two"; they are the first two
 * RIGHT-hand slots, so both fighters were being put on the same side of a
 * screen whose side-counts still said one each. The real layout is written out
 * where it is used, next to the stores that prove it.
 */

void room_load(void *scene)
{
    void *before[ROOM_MAX_TEXT];
    int n_before;

    room_log("[Rooms] room scene load");

    /* Build the splash BEFORE anything of ours exists.
     *
     * This is the whole difference from the old room, which entered a scene
     * that already had a splash in it and then destroyed everything it did not
     * recognise - including the GObj carrying VSSplash_Think, which is the
     * thing that builds the characters. It kept the camera and deleted the
     * renderer, then concluded the models could not be rendered.
     *
     * Building it ourselves gets the camera AND the models, constructed the way
     * Melee does it every match. Our text goes on top afterwards rather than
     * pruning underneath.
     *
     * `scene` is the minor data Melee handed us - the same pointer the splash's
     * own load expects. Calling it with no argument leaves whatever was last in
     * r3, which works by luck on a fresh entry and not at all otherwise. */
    if (scene)
    {
        SceneLoad_ClassicModeSplash(scene);
        room_log("[Rooms] splash built");

        room_count_cams();

        /* Where the heap's cursor sits, once per scene build. ⚠️ This is the
         * open question from the rebuild that froze the room: two builds
         * worked and the third never returned, and "the scene change frees the
         * heap" was an assumption nobody measured. If this address climbs
         * build over build, it does not. */
        {
            char line[64];
            char *p = line;
            void *probe = HSD_MemAlloc(32);

            p = room_put(p, "[Rooms] heap cursor ");
            p = room_put_x(p, (u32)probe);
            *p = 0;
            room_log(line);
            if (probe)
                HSD_Free(probe);
        }
    }
    else
    {
        /* Said plainly. Without the minor data there is no camera, and every
         * later symptom is a consequence of this one line. */
        room_log("[Rooms] no minor data - no camera, the room will be black");
    }

    /* Taken BEFORE ours exists, so the one that appears after is ours. */
    n_before = room_snapshot_text(before, ROOM_MAX_TEXT);

    s_text = Text_CreateStruct(0, 0);
    if (!s_text)
    {
        /* Said plainly rather than left to look like a black screen: without a
         * text struct nothing below can draw, and every later symptom would be
         * a consequence of this one line. */
        room_log("[Rooms] no text struct - the room cannot draw");
        return;
    }

    /* ⚠️ No title. "Rooms" said nothing to somebody already standing in
     * one, and the room's own name wants that place - see room_draw_code. */

    /* Outlined rather than plain: this font has no bold, and an outline is the
     * nearest thing to one that it does have. */
    /* The stage, on the bottom edge of the picture, and the white VS between
     * the two names. Outlined like the splash's own lettering. */
    s_stage_line = FG_CreateSubtext(s_text, &COL_WHITE, ROOMS_SUBTEXT_OUTLINE, 0,
                                    "", ROOM_STAGE_SZ,
                                    ROOM_STAGE_X, ROOM_STAGE_Y);
    s_vs_line = FG_CreateSubtext(s_text, &COL_WHITE, ROOMS_SUBTEXT_OUTLINE, 0,
                                 "", ROOM_VS_SZ, ROOM_VS_X, ROOM_NAME_Y);

    /* ROOM QAFK PASS 5143, and how to reveal it when it is starred out. */
    s_code_line = FG_CreateSubtext(s_text, &COL_WHITE, ROOMS_SUBTEXT_PLAIN, 0,
                                   "", ROOM_CODE_SZ, ROOM_CODE_X, ROOM_CODE_Y);
    s_hint_line = FG_CreateSubtext(s_text, &COL_GRAY, ROOMS_SUBTEXT_PLAIN, 0,
                                   "", ROOM_HINT_SZ, ROOM_CODE_X, ROOM_HINT_Y);

    /* The two column headings. */
    s_head_lobby = FG_CreateSubtext(s_text, &COL_GRAY, ROOMS_SUBTEXT_PLAIN, 0,
                                    "", ROOM_HEAD_SZ,
                                    ROOM_LOBBY_X, ROOM_HEAD_Y);
    s_head_queue = FG_CreateSubtext(s_text, &COL_GRAY, ROOMS_SUBTEXT_PLAIN, 0,
                                    "", ROOM_HEAD_SZ,
                                    ROOM_QUEUE_X, ROOM_HEAD_Y);
    s_name_l = FG_CreateSubtext(s_text, &COL_WHITE, ROOMS_SUBTEXT_PLAIN, 0,
                                "", ROOM_NAME_SZ,
                                ROOM_NAME_L_X, ROOM_NAME_Y);
    s_name_r = FG_CreateSubtext(s_text, &COL_WHITE, ROOMS_SUBTEXT_PLAIN, 0,
                                "", ROOM_NAME_SZ,
                                ROOM_NAME_R_X, ROOM_NAME_Y);

    s_active_num[0] = FG_CreateSubtext(s_text, &COL_GOLD, ROOMS_SUBTEXT_PLAIN, 0,
                                       "", ROOM_ACTIVE_NUM_SZ,
                                       ROOM_ACTIVE_NUM_L_X, ROOM_NAME_Y);
    s_active_num[1] = FG_CreateSubtext(s_text, &COL_GOLD, ROOMS_SUBTEXT_PLAIN, 0,
                                       "", ROOM_ACTIVE_NUM_SZ,
                                       ROOM_ACTIVE_NUM_R_X, ROOM_NAME_Y);

    {
        int i;

        for (i = 0; i < ROOMS_STATE_MAX_QUEUE; i++)
        {
            float y = ROOM_QUEUE_Y + (float)i * ROOM_QUEUE_STEP;

            s_queue_line[i] = FG_CreateSubtext(
                s_text, &COL_WHITE, ROOMS_SUBTEXT_PLAIN, 0, "", ROOM_QUEUE_SZ,
                ROOM_QUEUE_X, y);
            /* ⚠️ The crown FIRST, the number after it, so the number is drawn
             * over the crown rather than under it. Subtexts go down in the
             * order they are made. */
            s_queue_crown[i] = FG_CreateSubtext(
                s_text, &COL_GOLD, ROOMS_SUBTEXT_PLAIN, 0, "", ROOM_CROWN_SZ,
                ROOM_CROWN_X, y);
            s_queue_num[i] = FG_CreateSubtext(
                s_text, &COL_GOLD, ROOMS_SUBTEXT_PLAIN, 0, "",
                ROOM_CROWN_NUM_SZ, ROOM_CROWN_NUM_X, y);
        }

        for (i = 0; i < ROOMS_STATE_MAX_LOBBY; i++)
            s_lobby_line[i] = FG_CreateSubtext(
                s_text, &COL_WHITE, ROOMS_SUBTEXT_PLAIN, 0, "", ROOM_LOBBY_SZ,
                ROOM_LOBBY_X, ROOM_LOBBY_Y + (float)i * ROOM_LOBBY_STEP);
    }

    s_join_sym = FG_CreateSubtext(s_text, &COL_WAIT, ROOMS_SUBTEXT_PLAIN, 0, "",
                                  ROOM_ACT_SZ, ROOM_ACT_SYM_X, ROOM_ACT_Y);
    s_join_line = FG_CreateSubtext(s_text, &COL_WHITE, ROOMS_SUBTEXT_PLAIN, 0, "",
                                   ROOM_ACT_SZ, ROOM_ACT_X, ROOM_ACT_Y);
    /* Same place as the two above, green instead of white. */
    s_done_sym = FG_CreateSubtext(s_text, &COL_DONE, ROOMS_SUBTEXT_PLAIN, 0, "",
                                  ROOM_ACT_SZ, ROOM_ACT_SYM_X, ROOM_ACT_Y);
    s_done_line = FG_CreateSubtext(s_text, &COL_DONE, ROOMS_SUBTEXT_PLAIN, 0, "",
                                   ROOM_ACT_SZ, ROOM_ACT_X, ROOM_ACT_Y);
    s_next_sym = FG_CreateSubtext(s_text, &COL_WAIT, ROOMS_SUBTEXT_PLAIN, 0, "",
                                  ROOM_ACT_SZ, ROOM_ACT_SYM_X,
                                  ROOM_ACT_Y + ROOM_ACT_STEP);
    s_next_line = FG_CreateSubtext(s_text, &COL_GRAY, ROOMS_SUBTEXT_PLAIN, 0, "",
                                   ROOM_ACT_SZ, ROOM_ACT_X,
                                   ROOM_ACT_Y + ROOM_ACT_STEP);

    /* Spectating, row three. */
    s_spec_sym = FG_CreateSubtext(s_text, &COL_WAIT, ROOMS_SUBTEXT_PLAIN, 0, "",
                                  ROOM_ACT_SZ, ROOM_ACT_SYM_X,
                                  ROOM_ACT_Y + 2.0f * ROOM_ACT_STEP);
    s_spec_line = FG_CreateSubtext(s_text, &COL_GRAY, ROOMS_SUBTEXT_PLAIN, 0, "",
                                   ROOM_ACT_SZ, ROOM_ACT_X,
                                   ROOM_ACT_Y + 2.0f * ROOM_ACT_STEP);

    /* The two ways out, rows four and five. */
    s_leaver_sym = FG_CreateSubtext(s_text, &COL_WAIT, ROOMS_SUBTEXT_PLAIN, 0, "",
                                    ROOM_ACT_SZ, ROOM_ACT_SYM_X,
                                    ROOM_ACT_Y + 3.0f * ROOM_ACT_STEP);
    s_leaver_line = FG_CreateSubtext(s_text, &COL_GRAY, ROOMS_SUBTEXT_PLAIN, 0, "",
                                     ROOM_ACT_SZ, ROOM_ACT_X,
                                     ROOM_ACT_Y + 3.0f * ROOM_ACT_STEP);
    s_leaveq_sym = FG_CreateSubtext(s_text, &COL_WAIT, ROOMS_SUBTEXT_PLAIN, 0, "",
                                    ROOM_ACT_SZ, ROOM_ACT_SYM_X,
                                    ROOM_ACT_Y + 4.0f * ROOM_ACT_STEP);
    s_leaveq_line = FG_CreateSubtext(s_text, &COL_GRAY, ROOMS_SUBTEXT_PLAIN, 0, "",
                                     ROOM_ACT_SZ, ROOM_ACT_X,
                                     ROOM_ACT_Y + 4.0f * ROOM_ACT_STEP);

    /* The rules under the two headings. ⚠️ Created AFTER the headings so they
     * draw over nothing - subtexts go down in the order they are made. */
    s_rule_lobby = FG_CreateSubtext(s_text, &COL_GRAY, ROOMS_SUBTEXT_PLAIN, 0,
                                    "", ROOM_RULE_SZ, ROOM_LOBBY_X, ROOM_RULE_Y);
    s_rule_queue = FG_CreateSubtext(s_text, &COL_GRAY, ROOMS_SUBTEXT_PLAIN, 0,
                                    "", ROOM_RULE_SZ, ROOM_QUEUE_X, ROOM_RULE_Y);

    /* Drawn once here rather than waiting for a change: a room you walk into
     * already not-queued would otherwise show two blank lines. */
    room_show_actions();

    {
        int i;

        s_browse_head = FG_CreateSubtext(
            s_text, &COL_GRAY, ROOMS_SUBTEXT_PLAIN, 0,
            "Type        Name   Host             Size", ROOM_BROWSE_SZ,
            ROOM_BROWSE_X, ROOM_BROWSE_HEAD_Y);
        s_browse_note = FG_CreateSubtext(s_text, &COL_GRAY, ROOMS_SUBTEXT_PLAIN,
                                         0, "", ROOM_BROWSE_SZ, ROOM_BROWSE_X,
                                         ROOM_BROWSE_Y);
        for (i = 0; i < ROOM_BROWSE_ROWS; i++)
        {
            float y = ROOM_BROWSE_Y + (float)i * ROOM_BROWSE_STEP;

            s_browse_row[i] = FG_CreateSubtext(s_text, &COL_WHITE,
                                               ROOMS_SUBTEXT_PLAIN, 0, "",
                                               ROOM_BROWSE_SZ, ROOM_BROWSE_X, y);
            /* Same place, gold. Blanking one of the pair is the highlight. */
            s_browse_sel[i] = FG_CreateSubtext(s_text, &COL_GOLD,
                                               ROOMS_SUBTEXT_PLAIN, 0, "",
                                               ROOM_BROWSE_SZ, ROOM_BROWSE_X, y);
        }
    }

    /* Ours is whichever text GObj was not there a moment ago; everything else
     * drawing text belongs to the splash and stops now. */
    room_note_our_text(before, n_before);
    room_silence_splash_text();
    room_hide_loading();

    room_log("[Rooms] room scene built");
}

/* How to find the splash's own GObj again, kept because finding it cost a
 * disassembly and nothing in the tree is done with yet.
 *
 * Class 15 holds three of them. The one carrying VSSplash_Think and the model
 * tree is on render link 0x0b with callback GXLink_Common (0x80391070). The
 * stage display shares that callback on link 0x0c, and the fog shares the link
 * with HSD_SetFog - so neither test alone is enough and both have to match.
 * Its JObj is at +0x28, as usual.
 *
 * Nothing here needs it right now: the sweep runs from the codeset, inside
 * VSSplash_Think, which already has the JObj in hand. Doing it from here would
 * be a frame late, and a frame late is too late - see the note on the sweep.
 */

void room_think(void)
{
    if (s_rebuild_cooldown > 0)
        s_rebuild_cooldown--;

    /* Once, not every frame. A think that logs per frame drowns everything
     * else in the log, which is where every answer in this project has come
     * from so far. */
    if (!s_said_hello)
    {
        s_said_hello = 1;
        room_log("[Rooms] room think is running");
    }

    /* Every frame, and it has to be.
     *
     * The fighters' camera does not exist when this scene loads - their models
     * are still coming off the disc - so a single pass during load was never
     * going to catch it, and they drew at full size straight down the screen,
     * well past the bottom of the band. Re-banding catches whatever has turned
     * up since, on the frame it turns up.
     *
     * Cheap, and deliberately so: it walks a short list and stores floats.
     * That is not FN_LoadMatchState, which allocated on every call and took the
     * room down after thirty-six seconds every time. */
    /* Once a second, and BEFORE the re-band, so what gets printed is whatever
     * survived the last frame rather than what we just wrote. */
    /* ⚠️ Counts on past 90 rather than stopping at it. Written as
     * "s_frames < 90 && ++s_frames == 90" the counter sticks at 90 for ever,
     * and anything else testing it - a "only for the first few seconds" guard,
     * say - never expires. That is what turned a one-off into a call every
     * frame, and the room hung. */
    if (++s_frames == 90)
    {
        room_report_cams();
        room_report_classes();
        room_report_gobjs();
    }

    /* ⚠️ On the FIRST frame as well as every half second after it. Waiting for
     * frame 30 to ask meant half a second of drawing whichever screen the last
     * scene happened to leave behind, which is the room's own look - so Public
     * opened as a room and then became a list.
     *
     * ⚠️ And the answer is ROOMS_FLAG_INROOM, not VALID. Valid means a tick has
     * come BACK, which is another half second, so a room you had just made drew
     * the public list until then. Both flashes, one cause: asking a question
     * whose answer arrives late when there is one available immediately. */
    if (s_frames == 1 || s_frames % ROOM_STATE_EVERY == 0)
    {
        room_fetch_state();
        s_browsing = !(s_state_buf[ROOMS_STATE_FLAGS] & ROOMS_FLAG_INROOM);

        /* The first answer is what the band was built from - RoomScenePrep
         * asked the same question a moment earlier, on the way into this
         * scene. Everything after it is compared against that. */
        if (!s_band_known)
        {
            char line[80];
            char *p = line;

            s_band_char_l = s_state_buf[ROOMS_STATE_HOST_CHAR];
            s_band_char_r = s_state_buf[ROOMS_STATE_GUEST_CHAR];
            s_band_stage = s_state_buf[ROOMS_STATE_STAGE];
            s_band_known = 1;

            /* ⚠️ Logged rather than left to the status line, which runs off the
             * right-hand edge of the band and loses everything after the first
             * number - 255 for "nobody has picked" and a real id look the same
             * once the rest is clipped away. */
            p = room_put(p, "[Rooms] band built from ");
            p = room_put_i(p, s_band_char_l);
            p = room_put(p, "/");
            p = room_put_i(p, s_band_char_r);
            p = room_put(p, " on ");
            p = room_put_i(p, s_band_stage);
            p = room_put(p, "  (255 = nobody has picked)");
            *p = 0;
            room_log(line);
        }

        if (s_browsing)
        {
            room_fetch_list();
            room_draw_browser();
            room_blank_room();
        }
        else
        {
            /* ⚠️ The action lines were blanked on the way into the browser and
             * nothing else rewrites them, so entering a room showed the
             * spinner and nothing beside it - a lone symbol, no words. */
            if (s_was_browsing)
            {
                room_blank_browser();
                room_show_actions();
            }
            /* The offer changes when a match starts or ends, and when you join
             * or leave the queue.
             *
             * ⚠️ The queue half was missing, which is why pressing Start left
             * the screen still offering a queue you had just joined. Both are
             * the ROOM's answer rather than anything this module remembers -
             * see room_show_actions. */
            {
                int playing = (s_state_buf[ROOMS_STATE_FLAGS] & ROOMS_FLAG_PLAYING) != 0;
                int queued = room_is_queued();

                if (playing != s_was_playing || queued != s_was_queued)
                {
                    s_was_playing = playing;
                    s_was_queued = queued;
                    room_show_actions();
                }
            }

            room_draw_match();
            room_draw_code();
            room_draw_players();
            room_draw_queue();

            /* Paired: ask Slippi to connect us. Then WAIT - the draft is only
             * enterable once it actually has. */
            if (!s_match_started &&
                (s_state_buf[ROOMS_STATE_FLAGS] & ROOMS_FLAG_READY))
                room_start_match();

            if (s_match_started && !s_draft_entered &&
                (s_state_buf[ROOMS_STATE_FLAGS] & ROOMS_FLAG_CONNECTED))
                room_go_to_draft();

            /* Asked to watch, and Dolphin now has enough of the match to
             * describe it. */
            if (s_watching && (s_state_buf[ROOMS_STATE_FLAGS] & ROOMS_FLAG_WATCHING))
                room_go_to_watch();
            /* ⚠️ Not while a watch is being handed over - that is a scene
             * change already on its way, and a second one would take the room
             * back instead of the match. */
            else if (!s_watching)
                room_rebuild_band();
        }

        if (s_browsing != s_was_browsing || !s_screen_known)
            room_show_band(!s_browsing);

        /* ⚠️ AFTER room_show_band, which owns the whole band and would put the
         * fighters back with everything else. And every poll rather than on a
         * change, because the models are not there on the frame the scene
         * loads - this catches them when they turn up, the same way the
         * re-band catches the camera.
         *
         * ⚠️ Shown only when what is LOADED is what is being PLAYED. The models
         * are chosen once, by RoomScenePrep, on the way into this scene - so
         * somebody sitting in the room when a match starts has the wrong two
         * fighters loaded, and "the picks are known, show them" put Donkey Kong
         * and Zelda up as though that were the match. An empty band is honest;
         * the wrong fighters are not. Anyone ENTERING now gets the right ones. */
        if (!s_browsing)
        {
            const u8 l = s_state_buf[ROOMS_STATE_HOST_CHAR];
            const u8 r = s_state_buf[ROOMS_STATE_GUEST_CHAR];

            room_show_fighters(l != ROOMS_NOT_PICKED && r != ROOMS_NOT_PICKED &&
                               l == s_band_char_l && r == s_band_char_r);
        }
        s_screen_known = 1;
        s_was_browsing = s_browsing;
    }

    if (s_browsing)
    {
        room_browse_buttons();
    }
    else
    {
        room_buttons();
        room_spin();
    }

}
