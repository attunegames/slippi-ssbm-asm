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

/* ------------------------------------------------------------------- EXI */

#define CONST_ExiWrite 1

void FN_EXITransferBuffer(void *buf, int len, int mode);
void FN_LoadMatchState(void);

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
