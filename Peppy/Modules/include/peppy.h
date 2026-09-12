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
    u8 major;
    u8 pending_major;
    u8 previous_major;
    u8 minor;
    u8 pending_minor;
    u8 previous_minor;
} SceneController;

#define SCENE_CTRL (*(volatile SceneController *)0x80479D30)

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
void SceneLoad_ClassicModeSplash(void);

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

/* ------------------------------------------------------------------- EXI */

#define CONST_ExiWrite 1

void FN_EXITransferBuffer(void *buf, int len, int mode);
/* Returns the match state read buffer: the block Dolphin fills and Melee reads,
 * which is where the room's roster arrives. */
void *FN_LoadMatchState(int unused);

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
