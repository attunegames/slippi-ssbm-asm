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

/* Slippi keeps a scratch buffer for EXI transfers alive across scenes, hung
 * off r13 at OFST_R13_SB_ADDR.  Melee owns r13, so we read it directly rather
 * than assuming where the SDA base landed. */
#define OFST_R13_SB_ADDR (-0x503C)

static inline void *peppy_exi_buffer(void)
{
    void *r13;
    __asm__ volatile("mr %0, 13" : "=r"(r13));
    return *(void **)((char *)r13 + OFST_R13_SB_ADDR);
}

static inline void peppy_exi_send(const u8 *bytes, int len)
{
    u8 *buf = (u8 *)peppy_exi_buffer();
    for (int i = 0; i < len; i++)
        buf[i] = bytes[i];
    FN_EXITransferBuffer(buf, len, CONST_ExiWrite);
}

#endif /* PEPPY_H */
