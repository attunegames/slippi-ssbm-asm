"""Build Peppy's MxScn.dat: Melee's scene table plus the scenes we added.

Run against the stock file pulled out of the ISO. That file is Melee's and does
not live in this repo, so this script is the recipe rather than the result:

    python make_mxscn.py MxScn.orig.dat -o MxScn.dat

Scene ids above 0x50 are ones Melee never enters by itself, so they are ours to
invent - the same way Slippi's GameSetup took 0x50.
"""
import argparse
from mxscn import Scn

# Training in-game, read out of the stock table: Melee's own scene 0x04. Copied
# rather than hooked, so real training mode keeps its own functions and only
# the room's version goes through our module.
# Training's own in-game scene. VS mode's was used while the scene refused to
# load at all, but that was the scene pointer being thrown away rather than
# anything about training - and VS's scene is a VS match with a CPU in it: no
# training HUD, no training pause menu, no CPU behaviour settings.
TRAIN_THINK = 0x8016D32C   # SceneThink_TrainingModeInGame
TRAIN_LOAD  = 0x8016EC28   # SceneLoad_TrainingModeInGame
TRAIN_LEAVE = 0x8016E9C8   # SceneLeave_InGame, shared with VS

# Melee's character select, read out of the stock table as scene 0x08. Slippi
# attaches SlippiCSS.dat to that scene, so entering it anywhere loads Slippi's
# online character select - rank, chat, match state and all - which has no
# business running over a training session and crashes when it tries. A copy
# with no code file is the same screen without the module.
CSS_THINK = 0x802669F4
CSS_LOAD  = 0x8026688C
CSS_LEAVE = 0x80266D70

SCENES = [
    # id,   file,               think,       load,       leave
    (0x51, "PeppyRoom.dat",     0,           0,          0),
    # No module: Melee's own training scene, called by the scene machinery with
    # the arguments it expects. A module here would replace those functions and
    # has to hand the scene pointer back through, which is one more thing to get
    # wrong while the basic case is still unproven.
    (0x52, None,                TRAIN_THINK, TRAIN_LOAD, TRAIN_LEAVE),
    (0x53, None,                CSS_THINK,   CSS_LOAD,   CSS_LEAVE),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("-o", "--out", required=True)
    args = ap.parse_args()

    scn = Scn(args.src)
    have = {ident for _, _, ident, _ in scn.entries()}
    for ident, name, think, load, leave in SCENES:
        if ident in have:
            print(f"{ident:#04x} already there, leaving it alone")
            continue
        scn.add(ident, name, think, load, leave)
        print(f"{ident:#04x} -> {name or 'no module'}")
    scn.write(args.out)


if __name__ == "__main__":
    main()
