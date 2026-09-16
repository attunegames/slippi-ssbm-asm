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

static void *s_text;
static int   s_line = -1;
static int   s_said_hello;
static int   s_frames;
static int   s_probes;

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

/* Find every camera, rather than the ones that happen to keep their CObj where
 * this expected it.
 *
 * Class 20 holds FIVE GObjs and only two of them have anything at +0x28, which
 * is where GObj_AddObject is supposed to park the object. Those two are banded,
 * hold their viewport perfectly, and the fighters ignore them - so the fighters
 * belong to one of the other three, and the assumption to question is the
 * offset, not the banding.
 *
 * So: for each camera GObj, walk its first few words, and for any that could be
 * a RAM pointer, look at what it points at and ask whether it looks like a
 * CObj. A CObj carries its viewport at +0x0C, and a viewport is four floats
 * describing a rectangle that is the right way round and screen-sized. That is
 * a specific enough shape to recognise without knowing the struct.
 *
 * Self-validating on purpose. If this prints nothing, the guess was wrong and
 * nothing has been broken to find that out. */
#define ROOM_GOBJ_SCAN_END 0x50

static int room_ptr_ok(u32 v)
{
    return v >= 0x80000000u && v < 0x81800000u && (v & 3u) == 0u;
}

static int room_looks_like_viewport(const float *vp)
{
    return vp[1] - vp[0] >= 16.0f && vp[3] - vp[2] >= 16.0f
        && vp[0] > -1000.0f && vp[2] > -1000.0f
        && vp[1] < 2000.0f && vp[3] < 2000.0f;
}

static void room_probe_cams(void)
{
    void **heads = rooms_gobj_heads();
    void *g;
    int idx = 0;

    if (!heads)
        return;

    for (g = heads[ROOM_CLASS_CAMERA]; g; g = *(void **)((char *)g + ROOMS_GOBJ_NEXT))
    {
        char line[120];
        char *p = line;
        int off;

        p = room_put(p, "[Rooms] g");
        p = room_put_i(p, idx++);
        p = room_put(p, " at ");
        p = room_put_x(p, (u32)g);

        for (off = 0x10; off < ROOM_GOBJ_SCAN_END; off += 4)
        {
            u32 v = *(const u32 *)((const char *)g + off);
            const float *vp;

            if (!room_ptr_ok(v))
                continue;
            vp = (const float *)(u32)(v + ROOM_COBJ_VIEWPORT);
            if (!room_looks_like_viewport(vp))
                continue;
            if (p - line > 84)
                break;
            *p++ = ' '; *p++ = '+';
            p = room_put_x(p, (u32)off);
            *p++ = ' ';
            p = room_put_i(p, (int)vp[0]); *p++ = ',';
            p = room_put_i(p, (int)vp[1]); *p++ = ',';
            p = room_put_i(p, (int)vp[2]); *p++ = ',';
            p = room_put_i(p, (int)vp[3]);
        }
        *p = 0;
        room_log(line);
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
    }
    else
    {
        /* Said plainly. Without the minor data there is no camera, and every
         * later symptom is a consequence of this one line. */
        room_log("[Rooms] no minor data - no camera, the room will be black");
    }

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

    room_log("[Rooms] room scene built");
}

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
    if (++s_frames >= 60)
    {
        s_frames = 0;
        room_report_cams();
        room_report_classes();
        /* Three times and then quiet: it is five lines a go and the answer
         * does not change once the fighters are in. */
        if (s_probes < 3)
        {
            s_probes++;
            room_probe_cams();
        }
    }

    if (s_line >= 0)
        Text_UpdateSubtextContents(s_text, s_line, "%s", "Rooms");
}
