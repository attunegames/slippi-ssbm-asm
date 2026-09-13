#ifndef PEPPY_H
#define PEPPY_H

/* Shared declarations for Peppy's m-ex code modules.
 *
 * Nothing here is defined by us -- every symbol resolves through
 * melee_symbols.ld (Melee's own functions, lifted from m-ex's MxDb.dat) or
 * slippi_symbols.ld (the codeset's injected helpers).  See
 * peppy-assets/NOTES-mex-modules.md for the module format itself.
 */

typedef unsigned char  u8;
typedef unsigned short u16;
typedef unsigned int   u32;
typedef signed char    s8;
typedef short          s16;
typedef int            s32;

/* Structure offsets lifted straight from the codeset rather than copied by
 * hand - see gen_slippi_consts.py. */
#include "slippi_consts.h"

/* Melee keeps its small-data base in r13 and a lot of engine globals hang off
 * it, so a module that wants one reads the register rather than guessing where
 * the base landed. */
static inline void *peppy_sda(void)
{
    void *r13;
    __asm__ volatile("mr %0, 13" : "=r"(r13));
    return r13;
}


/* ---------------------------------------------------------------- scenes */

/* The scene controller Melee keeps at a fixed address.  A scene is named
 * (minor << 8) | major everywhere in the codeset, which is this struct's
 * byte 3 and byte 0 -- see the getMinorMajor macro in Common/Common.s. */
typedef struct SceneController {
    u8 major;           /* +0x0 */
    u8 pending_major;   /* +0x1 */
    u8 unknown2;        /* +0x2 */
    u8 minor;           /* +0x3 */
    u8 unknown4;        /* +0x4 */
    /* +0x5. Every scene change in the codeset writes HERE - the stage select
     * setting 5 for the splash, the character select setting 6 for game prep.
     * A first guess put this at +0x4 and the writes went nowhere: the screen
     * stayed put and the log showed +0x5 still holding what the major's Load
     * had written on the way in. */
    u8 pending_minor;   /* +0x5 */
} SceneController;

#define SCENE_CTRL (*(volatile SceneController *)0x80479D30)

/* pending_minor is one-based: zero means "carry on as normal" and anything else
 * is the minor scene id plus one. Every store in the codeset reads that way -
 * the stage select sets 5 to reach the splash (id 4), the character select sets
 * 6 to reach game prep (id 5). Getting this off by one lands on the neighbour,
 * which is a whole different screen.
 *
 * These are minor ids within the online major, from the table in
 * Online/Slippi Online Scene/main.asm - not the global MxScn ids above. */
#define ONLINE_MINOR_CSS        0
#define ONLINE_MINOR_ROOM       6
#define ONLINE_MINOR_GAMESETUP 5
#define ONLINE_MINOR_TRAIN      7
#define ONLINE_MINOR_TRAIN_CSS  8
#define ONLINE_MINOR_TRAIN_SSS  9

/* Melee's major scene table: one 0x14-byte entry per major, with the pointer to
 * that major's minor list at +0x10. */
/* The next minor scene, as Melee's menus ask for it: a raw minor id in the
 * short data area, which is how Slippi's stage select asks for the match it is
 * about to start. Not the same thing as the scene controller's own pending byte
 * at 0x80479d35, which wants the id plus one. */
#define SDA_NEXT_MINOR      (-0x49F1)

#define MAJOR_SCENE_TABLE   0x803daca4
#define MAJOR_SCENE_STRIDE  0x14
#define SCENE_NEXT_MINOR(id)    ((u8)((id) + 1))


#define MAJOR_ONLINE        0x08

#define MINOR_MAIN_MENU     0x01
#define MINOR_CSS           0x08    /* SlippiCSS.dat hooks this one */
#define MINOR_SSS           0x09
#define MINOR_PEPPY_ROOM    0x51    /* ours; Slippi's added scene is 0x50 */

/* Melee's scene functions, as named by m-ex's symbol database. */
void SceneThink_CSS(void);
void SceneLoad_CSS(void);
void SceneLeave_CSS(void);
void SceneThink_MainMenu(void);
void SceneLoad_MainMenu(void);
void Scene_ExitMinor(void);
/* Ends the MAJOR scene. Event_StoreSceneNumber only names the next one and
 * flags the minor - on its own the engine went to the current major's first
 * minor instead, which from a room is the character select. */
void Scene_ExitMajor(void);
/* Names the major to go to next. Event_StoreSceneNumber was supposed to do
 * this and the controller never changed, so this is the one that says it. */
void Scene_SetNextMajor(int major);

/* Sets the major scene to go to next and flags the current one to end. The
 * minor is not its business - the new major's Load picks that. */
void Event_StoreSceneNumber(int major);

/* Melee's own menu, which is where backing out of a room lands. Slippi's
 * FN_OnReturnFromOnline already puts the cursor back on Rooms from here. */
#define SCENE_MAJOR_MAIN_MENU 1

/* A scene needs a camera and a render pass before anything draws, and that is
 * the scene Load's job.  Ours is our own, so until it builds its own camera it
 * borrows the simplest one in the game: Melee's unused "Coming Soon" screen,
 * which is a camera, a render pass and almost nothing else. */
void SceneLoad_ComingSoon(void);
void SceneLeave_ComingSoon(void);

/* Coming Soon gives a camera and a render pass -- its artwork draws -- but our
 * text still does not, so the text object is on a GXLink that camera does not
 * cover.  The debug menu is the one scene in the game that is nothing but menu
 * text, so its camera has to cover the link menu text uses. */
void SceneLoad_DebugMenu(void);

/* The one base with proof behind it: Slippi's VS splash injects at 0x80186ec4,
 * inside this function, and creates a text struct and subtexts there that do
 * render.  Coming Soon has no text of its own and never brings up whatever
 * menu text needs, which is why ours drew nothing on it at any position or
 * scale. */
/* A scene load takes the scene's minor data - the same pointer Melee hands our
 * own load. Calling it with no argument leaves whatever was last in r3, which
 * works by luck on a fresh entry and not at all after something else has run. */
void SceneLoad_ClassicModeSplash(void *scene);

/* Melee's character select, and its hand.
 *
 * The hand is a GObj the character select's load creates, driven every frame by
 * CSS_CursorThink reading the stick. Its pointer per port lives in
 * CSS_CursorObjPointers, which is how the room can keep it while throwing the
 * rest of that scene away. */
void CSS_LoadFunction(void *scene);
#define CSS_CURSOR_OBJS     0x804A0BC0
#define CSS_CURSOR_PORTS    4
/* The character select's own minor data, read out of the online major's table.
 * A scene load reads its data from the argument, so the room can hand it this
 * while its own descriptor still names the splash's. */
#define CSS_MINOR_DATA      0x80497758

/* Better base than the splash: the main menu is the blue grid Peppy's own
 * menus already sit on, it is a real scene so text renders, it carries none of
 * the splash's stage and item loading, and Melee ships a function for taking
 * its widgets away - which leaves the background and nothing else. */
void MainMenu_HideAllElements(void);

/* A GObj is registered on a render link with a draw callback and a priority -
 * this is how Text_AllocateTextObject puts the text object on link 0 in the
 * first place.  Poking the link byte afterwards does nothing, because the
 * object is already threaded onto link 0's list; it has to be taken off and
 * put back on. */
/* Melee threads every GObj onto a per-class list: the heads live in an array
 * hung off r13, indexed by the object's class byte at +0x02, chained through
 * +0x0C.  GObj_Create writes the class from its third argument, so the splash's
 * GObj_Create(11, 3, 0) artwork is class 3. */
#define PEPPY_GOBJ_HEADS   (-15992)
#define PEPPY_GOBJ_CLASS   0x02
#define PEPPY_GOBJ_NEXT    0x0C

static inline void **peppy_gobj_heads(void)
{
    return *(void ***)((char *)peppy_sda() + PEPPY_GOBJ_HEADS);
}

/* A camera's viewport is four floats at cobj+0x0C and its scissor four
 * halfwords at cobj+0x1C; Melee renders 640x480, so the top half is
 * (0, 640, 0, 240).  GObj_AddObject parks the object on its GObj at +0x28, so
 * a camera GObj (class 20) hands over its CObj. */
void CObj_SetViewport(void *cobj, float left, float right, float top, float bottom);
void CObj_SetScissor(void *cobj, int left, int right, int top, int bottom);

/* A camera GObj carries a 64-bit render-link mask at +0x20/+0x24 -
 * CObj_RenderGXLinks walks exactly the links whose bits are set - so which
 * camera draws what is editable, and the split needs no new camera. */
#define PEPPY_GOBJ_LINKS32 0x20   /* links 32..63 */
#define PEPPY_GOBJ_LINKS0  0x24   /* links 0..31  */
#define PEPPY_GOBJ_DRAWFN  0x1C   /* GObj_AddGXLink stores the callback here */
#define PEPPY_GOBJ_LINK    0x03   /* ...and the render link here */
#define PEPPY_GOBJ_OBJECT  0x28
#define PEPPY_SCREEN_W     640
#define PEPPY_SCREEN_H     480

void GObj_Destroy(void *gobj);
void GObj_DestroyGXLink(void *gobj);
void GObj_AddGXLink(void *gobj, void *callback, int link, int priority);

#define TEXT_DRAW_EACH_FRAME ((void *)0x803A84BC)
void SceneThink_ClassicModeSplash(void);

/* -------------------------------------------------------------------- pad */

/* Melee's pad array: four ports, 0x44 apart.  Held buttons sit at +0x00 and
 * the newly-pressed word at +0x08, which is the one a menu wants. */
#define PEPPY_PAD_MASTER   0x804c1fac
#define PEPPY_PAD_STRIDE   0x44
#define PEPPY_PAD_PORTS    4
#define PEPPY_PAD_PRESSED  0x08

#define PAD_START  0x1000
#define PAD_B      0x0200
#define PAD_Z      0x0010
#define PAD_A      0x0100

/* Melee puts the control stick's direction into the same word as the buttons,
 * so a menu can read a flick without touching the analog values at all.
 * Measured by dumping a pad struct while the test script held each direction:
 * up came out 0x00010000 and down 0x00020000. Left and right were not measured
 * and are not guessed at here. */
#define PAD_STICK_UP   0x00010000
#define PAD_STICK_DOWN 0x00020000
#define PAD_STICK_LEFT  0x00040000
#define PAD_STICK_RIGHT 0x00080000
/* The d-pad, which nothing in the room uses, taken as well - so sideways still
 * works if the stick's left and right do not sit where up and down suggest. */
#define PAD_DPAD_LEFT   0x0001
#define PAD_DPAD_RIGHT  0x0002

/* Any port: a room is watched by whoever is sitting there, not by a fixed
 * controller slot. */
static inline u32 peppy_pad_pressed(void)
{
    const char *pad = (const char *)PEPPY_PAD_MASTER;
    u32 all = 0;
    int i;

    for (i = 0; i < PEPPY_PAD_PORTS; i++)
        all |= *(u32 *)(pad + i * PEPPY_PAD_STRIDE + PEPPY_PAD_PRESSED);
    return all;
}

/* ------------------------------------------------------------------- EXI */

#define CONST_ExiWrite 1

void FN_EXITransferBuffer(void *buf, int len, int mode);
/* Fills and returns the match state read buffer: the block Dolphin fills and
 * Melee reads, which is where the room's roster arrives.
 *
 * The argument is the buffer to fill. Hand it zero and it allocates one -
 * MSRB-sized, off the heap, never given back - so anything that asks more than
 * once must keep what it was given and hand it back in. Slippi's own callers
 * all pass zero because they all ask once, on the way into a scene. */
void *FN_LoadMatchState(void *buf);

/* Slippi's logf macro transfers out of a scratch buffer hung off r13 at
 * OFST_R13_SB_ADDR, but every caller of that macro is online code -- there is
 * no promise the pointer is live in a menu scene, and writing 128 bytes
 * through a null one takes the game down before it draws a frame.  A module
 * owns its own memory, so use that instead.
 *
 * 32-byte aligned because the transfer is a DMA and a cache line is 32 bytes;
 * a buffer sharing a line with something else can have that neighbour written
 * back over it. */
#define PEPPY_EXI_BUF_SIZE 128

/* Tells Dolphin whether this client wants a game. Being in a room is not the
 * same as being in the queue, so nothing pairs until this says so. */
#define PEPPY_CMD_SET_QUEUED 0xC6
/* Let go of the room itself, as opposed to just the queue. */
#define PEPPY_CMD_LEAVE_ROOM 0xC9
/* Start fetching the public rooms of one mode. The menu sends this on its way
 * in; the room sends it again when somebody backs out, because the list thread
 * stops the moment a room is joined. Payload is the mode. */
#define PEPPY_CMD_LIST_ROOMS 0xC7

/* Slippi's "start looking for an opponent". It is what starts the matchmaking
 * thread, and therefore what starts the room ticking - without it Dolphin
 * never asks the room anything and every column stays empty. The character
 * select has always sent this; a room has to send it for itself.
 *
 * Payload is the online mode and eighteen shift-JIS bytes of opponent code,
 * which only Direct mode reads. */
/* Joining a room somebody else made: the mode, then the four characters of its
 * code. Melee does not terminate it - the length is the terminator. */
#define PEPPY_CMD_JOIN_ROOM 0xC8

#define PEPPY_CMD_FIND_OPPONENT 0xB4
#define PEPPY_FIND_OPPONENT_SIZE 20

extern u8 peppy_exi_buf[PEPPY_EXI_BUF_SIZE];

#define PEPPY_DEFINE_EXI_BUF     u8 peppy_exi_buf[PEPPY_EXI_BUF_SIZE] __attribute__((aligned(32)))


/* ------------------------------------------------------------------ text */

/* Melee's menu text: a struct holds a list of subtexts, each with its own
 * colour, size and canvas position.  FG_CreateSubtext is one of the codeset's
 * injected helpers.
 *
 * Its signature looks odd until you remember that PPC EABI fills the GPRs and
 * the FPRs independently, in argument order: text/colour/mode/outline/string
 * land in r3-r7 and size/x/y in f1-f3, which is exactly what the assembly
 * version sets up by hand. */
void *Text_CreateStruct(int a, int b);

/* Rewrites one subtext in place, by the index FG_CreateSubtext handed back.
 * Printf-style, so a plain string with no % in it can be passed directly. */
void Text_UpdateSubtextContents(void *text, int index, const char *fmt, ...);

int FG_CreateSubtext(void *text, const void *color, int mode,
                     const void *outline_color, const char *str,
                     float size, float x, float y);

#define PEPPY_SUBTEXT_PLAIN 0    /* 1 = outlined, 2 = premade text */

/* Peppy's own CSS code builds the text struct in CSS_LoadFunction and parks it
 * in the CSS data table, so a module that runs after SceneLoad_CSS can just
 * borrow it rather than making a second one. */
#define CSSDT_BUF_ADDR        0x80005614
#define CSSDT_TEXT_STRUCT_OFS 0x08

static inline void *peppy_css_text(void)
{
    void *cssdt = *(void **)CSSDT_BUF_ADDR;
    if (!cssdt)
        return 0;
    return *(void **)((char *)cssdt + CSSDT_TEXT_STRUCT_OFS);
}

/* Canvas coordinates, the same space the drawn room row uses:
 *     screen_x = 961 + 1.886 * canvas_x
 *     screen_y = 594 + 1.886 * canvas_y                                    */

#endif /* PEPPY_H */
