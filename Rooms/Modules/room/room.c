/* The room screen.
 *
 * SKELETON. This is the smallest thing that proves the m-ex pipeline on this
 * branch: the module is found, loaded, relocated, its exports are installed
 * into the scene's Think/Load slots, and it draws. Nothing else yet.
 *
 * Where it is going, so the shape here does not have to be undone later:
 *
 * The room's scene entry is a COPY of the VS splash's (global minor 0x20),
 * not an empty one. That matters. The splash's Load builds two character
 * models in their chosen costumes, and it is the only renderer in the game
 * that does so without a 3D preload the room cannot finish - three attempts
 * at borrowing it the other way are recorded in the old notes, all dead.
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
#define ROOM_TEXT_Y  40.0f
#define ROOM_TEXT_SZ 0.55f

static void *s_text;
static int   s_line = -1;
static int   s_said_hello;

/* -------------------------------------------------------------- the module */

/* Pull the splash up into a band across the top.
 *
 * The splash fills the screen because it is normally the whole screen. Here it
 * is the top of a room, with the queue and lobby underneath - so its camera
 * gets a viewport rather than its objects getting moved. One call per camera
 * instead of repositioning everything the builder made, and the framing stays
 * correct because the camera still sees the same scene.
 *
 * Cameras are GObj class 20 and park their CObj at +0x28. There is more than
 * one - the old room counted five - so every one of them is banded, or the ones
 * left alone keep drawing full-screen over the top.
 */
#define ROOM_CLASS_CAMERA 20
#define BAND_LEFT    0.0f
#define BAND_RIGHT 640.0f
#define BAND_TOP     0.0f
#define BAND_BOTTOM 240.0f

static void room_band_to_top(void)
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
        CObj_SetViewport(cobj, BAND_LEFT, BAND_RIGHT, BAND_TOP, BAND_BOTTOM);
        CObj_SetScissor(cobj, (int)BAND_LEFT, (int)BAND_RIGHT,
                        (int)BAND_TOP, (int)BAND_BOTTOM);
        n++;
    }

    /* Counted rather than assumed: "the band did not move" and "there was no
     * camera to move" look identical on screen. */
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

/* Where SceneLoad_ClassicModeSplash reads what to build, measured off its own
 * disassembly rather than assumed:
 *
 *     +0x10   character one, external id
 *     +0x11   character two
 *
 * If EITHER is 0x1a - 26, "nobody" - it sets the done flag and builds nothing,
 * which is most of the time in a room and would look exactly like a failure.
 * So a real pair goes in before the call. */
#define SPLASH_CHAR_1 0x10
#define SPLASH_CHAR_2 0x11
#define SPLASH_NOBODY 0x1a

/* Hardcoded on purpose, and temporary: this is the first test of whether the
 * splash will build inside the room's scene at all. Fox and Marth because they
 * are unmistakable on screen - two characters here means it worked, and no
 * amount of log reading proves that as well as looking. The real pair comes
 * from the room's state once there is a room tick to carry it. */
#define PROBE_CHAR_1 0x02
#define PROBE_CHAR_2 0x09

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
        u8 *d = (u8 *)scene;

        d[SPLASH_CHAR_1] = PROBE_CHAR_1;
        d[SPLASH_CHAR_2] = PROBE_CHAR_2;
        SceneLoad_ClassicModeSplash(scene);
        room_log("[Rooms] splash built");
        room_band_to_top();
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

    if (s_line >= 0)
        Text_UpdateSubtextContents(s_text, s_line, "%s", "Rooms");
}
