/* Practice while you wait.
 *
 * Waiting in a queue is exactly when somebody wants to be in training, so this
 * is Melee's own training mode reached as a MINOR of the online major rather
 * than as a major of its own. That matters: leaving the online major is the
 * one transition that has never worked from a scene of ours, and going around
 * it means training needs nothing that is not already proven.
 *
 * MxScn.dat carries a copy of Melee's training-in-game scene (common minor
 * 0x04) as 0x52 with this module attached, so real training mode keeps its own
 * functions and only this one runs through here. Everything Melee does it
 * still does; this adds one thing, which is watching the room and leaving the
 * moment it is this player's turn.
 */
#include "peppy.h"

#define LOG_NOTICE 1

PEPPY_DEFINE_EXI_BUF;

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

/* Melee's own, which this scene is a copy of. */
void SceneLoad_TrainingModeInGame(void *scene);
void SceneThink_TrainingModeInGame(void *scene);
void SceneLeave_InGame(void);

/* One frame's worth of grace before believing the roster. The match state
 * buffer is Dolphin's, and a training session that starts on the same frame a
 * pairing is torn down would read the last one and bounce straight out. */
static int s_settle;

void peppy_train_load(void *scene)
{
    s_settle = 0;
    /* The scene pointer is the match. Melee hands it to every scene and
     * everything about starting one hangs off it. */
    SceneLoad_TrainingModeInGame(scene);
    peppy_log("Peppy: training");
}

void peppy_train_think(void *scene)
{
    void *msrb;

    SceneThink_TrainingModeInGame(scene);

    if (s_settle < 120)
    {
        s_settle++;
        return;
    }

    /* The room names the pair it has made in the first two roster slots. A name
     * in there means the wait is over - Melee is about to be handed a match,
     * and the character select is where that is answered. */
    msrb = FN_LoadMatchState(0);
    if (!msrb)
        return;
    if (!*(char *)((char *)msrb + MSRB_ROSTER))
        return;

    peppy_log("Peppy: training over - it is your turn");
    SCENE_CTRL.pending_minor = SCENE_NEXT_MINOR(ONLINE_MINOR_CSS);
    Scene_ExitMinor();
}

void peppy_train_leave(void)
{
    SceneLeave_InGame();
}
