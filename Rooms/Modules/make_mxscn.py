"""Build Rooms's MxScn.dat: Melee's scene table plus the scenes we added.

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

# The splash's own entry, read out of the stock table as scene 0x20. Its Load
# is the only renderer in the game that builds two characters in their chosen
# costumes without a 3D preload the room cannot finish.
#
# The room does not inherit it through the table, because m-ex overwrites any
# slot a module exports and the room exports Load. It calls SPLASH_LOAD itself,
# with a match struct it owns. Recorded here because the address is the reason
# this scene exists in this shape.
SPLASH_THINK = 0x80186DFC   # SceneThink_ClassicModeSplash - twelve instructions
                            # that do nothing but exit the scene. Never ours.
SPLASH_LOAD  = 0x80186E30   # SceneLoad_ClassicModeSplash

SCENES = [
    # id,   file,              think,       load,       leave
    #
    # The room. Think and Load come from the module; Leave is left at 0
    # deliberately, the same as the splash's own entry, because m-ex only
    # overwrites a slot a module actually exports.
    (0x51, "SlippiRoom.dat",   0,           0,          0),

    # Training, with NO module on it. Melee's own scene functions, called by the
    # scene machinery with the arguments they expect. Putting a module here
    # would replace those functions and then have to hand the scene pointer back
    # through them, which is one more thing to get wrong.
    #
    # A copy rather than a hook on 0x04, so real training mode keeps its own
    # functions untouched and only the room's version comes through here.
    (0x52, None,               TRAIN_THINK, TRAIN_LOAD, TRAIN_LEAVE),

    # The character select, also with no module - and 0x53 rather than 0x08 for
    # a specific reason. 0x08 is where Slippi attaches SlippiCSS.dat, and that
    # module has no business running over a training session: it expects an
    # online match and reads a float as if it were a pointer when there is none.
    (0x53, None,               CSS_THINK,   CSS_LOAD,   CSS_LEAVE),
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
