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
#define ROOM_STATE_X   470.0f
#define ROOM_STATE_Y   359.0f
#define ROOM_STATE_SZ  0.85f

/* And the two names, on the plate where DK and Zelda were - which is where the
 * Slippi usernames go. Placeholders until a room has players in it. */
#define ROOM_NAME_L_X  100.0f
#define ROOM_NAME_R_X  430.0f
#define ROOM_NAME_Y    413.0f
#define ROOM_NAME_SZ   0.70f

static void *s_text;
static int   s_state_line = -1;
static int   s_name_l = -1;
static int   s_name_r = -1;
static int   s_line = -1;
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
#define ROOM_TEXT_GX ((void *)0x803A84BC)

static void *s_our_text_gobj;

static int room_is_text_gobj(void *g)
{
    return *(void **)((char *)g + ROOMS_GOBJ_DRAWFN) == ROOM_TEXT_GX;
}

/* Anything drawing text that is not ours. Called after our own text exists, so
 * "not ours" is a complete description of the splash's. */
static void room_silence_splash_text(void)
{
    void **heads = rooms_gobj_heads();
    void *g;

    if (!heads)
        return;

    for (g = heads[ROOM_CLASS_CAMERA]; g;
         g = *(void **)((char *)g + ROOMS_GOBJ_NEXT))
    {
        if (g == s_our_text_gobj || !room_is_text_gobj(g))
            continue;
        GObj_DestroyGXLink(g);
    }
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

#define ROOM_MAX_TEXT 8

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

        /* NOW LOADING, collapsed to nothing. It is a text object, not part of
         * the model tree - which is exactly why hiding JObjs never touched it,
         * through a flag sweep and a whole-tree animation sweep both. */
        {
            void *sis = *(void **)(ROOMS_SPLASH_STATE + ROOMS_SPLASH_SISTEXT);

            if (sis)
            {
                Text_SetScale(sis, 0.0f, 0.0f);
                room_log("[Rooms] now loading scaled away");
            }
            else
            {
                room_log("[Rooms] no sis text - now loading is somewhere else");
            }
        }
        room_count_cams();
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

    s_line = FG_CreateSubtext(s_text, &COL_WHITE, ROOMS_SUBTEXT_PLAIN, 0,
                              "Rooms", ROOM_TEXT_SZ, ROOM_TEXT_X, ROOM_TEXT_Y);

    /* Outlined rather than plain: this font has no bold, and an outline is the
     * nearest thing to one that it does have. */
    s_state_line = FG_CreateSubtext(s_text, &COL_WHITE, ROOMS_SUBTEXT_OUTLINE, 0,
                                    "DRAFTING", ROOM_STATE_SZ,
                                    ROOM_STATE_X, ROOM_STATE_Y);
    s_name_l = FG_CreateSubtext(s_text, &COL_WHITE, ROOMS_SUBTEXT_PLAIN, 0,
                                "Player 1", ROOM_NAME_SZ,
                                ROOM_NAME_L_X, ROOM_NAME_Y);
    s_name_r = FG_CreateSubtext(s_text, &COL_WHITE, ROOMS_SUBTEXT_PLAIN, 0,
                                "Player 2", ROOM_NAME_SZ,
                                ROOM_NAME_R_X, ROOM_NAME_Y);

    /* Ours is whichever text GObj was not there a moment ago; everything else
     * drawing text belongs to the splash and stops now. */
    room_note_our_text(before, n_before);
    room_silence_splash_text();

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
    if (s_frames < 90 && ++s_frames == 90)
    {
        room_report_cams();
        room_report_classes();
        room_report_gobjs();
    }

    /* The splash can bring text up after its load has returned, so keep
     * sweeping for a few seconds rather than trusting one pass. Destroying a
     * link that is already gone finds nothing to match. */
    if (s_frames < 180)
        room_silence_splash_text();

    if (s_line >= 0)
        Text_UpdateSubtextContents(s_text, s_line, "%s", "Rooms");
}
