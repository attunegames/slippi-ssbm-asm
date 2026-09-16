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

/* The band is 640x240 of a 640x480 picture, and there are two different ways to
 * get one from the other. The first try used the wrong one.
 *
 * The VIEWPORT is a mapping, not a window: give it a 240-high rectangle and the
 * whole 480-high picture is squeezed into it, which is why the first band came
 * out squashed rather than cropped. The SCISSOR is the window - it throws away
 * whatever falls outside and touches nothing else.
 *
 * So the viewport keeps its full 480 of height and is slid UP by BAND_SHIFT,
 * and the scissor clips to the top of the screen. The picture is then drawn at
 * its true proportions and we see a 240-high slice of it.
 *
 * BAND_SHIFT is which slice. 0 is the top of the picture, 240 the bottom; 120
 * takes the middle, which is where two fighters stood on the screen this was
 * borrowed from. It is one number and it is meant to be tuned against a
 * screenshot - nothing else depends on it. */
#define BAND_SHIFT 120.0f
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
        CObj_SetViewport(cobj, BAND_LEFT, BAND_RIGHT,
                         -BAND_SHIFT, (float)ROOMS_SCREEN_H - BAND_SHIFT);
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
