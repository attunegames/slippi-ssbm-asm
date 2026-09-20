# On the rigs right now, and not yet confirmed

This file is the opposite of `WORKING.md`. That one records what has been
proven; this one records what is sitting on the three test rigs waiting for
somebody to press the buttons. It is rewritten each time, not appended to -
once something here is confirmed it moves to `WORKING.md` and leaves.

## The build

Deployed to `Desktop/rooms-lan-test/{Alpha,Bravo,Charlie}` on 2026-09-20.

| | commit | tag |
|---|---|---|
| asm | `ce3bd16` | `test/random-stages` (adds this file on top, no code) |
| dolphin | `68c3aa4a2` | `test/random-stages` |

    Alpha    exe 28dc2c8a  codeset 4c8fca78  module 080d6a91
    Bravo    exe 28dc2c8a  codeset 4c8fca78  module 080d6a91
    Charlie  exe 28dc2c8a  codeset 4c8fca78  module 080d6a91

⚠️ Those three hashes are the first eight of the md5 of `Slippi Dolphin.exe`,
`Sys/GameSettings/GALE01r2.ini` and `Sys/GameFiles/GALE01/SlippiRoom.dat`. All
three rigs must match each other. A mismatched pair is the single easiest way
to spend an evening testing a build nobody made.

## What to test

### 1. A second draft in the same room drives its stages

The one that matters. Game one already worked - the cursor swept along the
stage row by itself, banned, confirmed, and the pick did the same. Game TWO
did not, and the reason was `draft_last_local_step`: it means "my step has
landed, stop driving" and it was only ever set, never cleared. So a client
that had drafted once believed its step was already done forever.

⚠️ The tell, and the thing worth watching for again: one side banned by hand
while the other still picked by itself. That asymmetry is a per-client memory,
not a protocol disagreement - the fresh client had no stale step to believe.

Play at least three matches in a row so the rotation brings a third person in.
Every draft after the first is new ground.

### 2. Pressing X is acknowledged

The room's sixth action line. The owner sees `X for Stage Draft` or
`X for Random Stages`; everybody else is told what the room does.

* One press should change the line to `Turning on Random Stages` (or
  `Turning the Stage Draft on`) with a blue symbol blinking beside it, ON THE
  FRAME the button goes down.
* Further presses do nothing until it settles. That is deliberate - a second
  press used to send a second request that undid the first.
* It gives up after five seconds. Anyone who is not the owner should see the
  line come back unchanged, because the server never answers a request it
  refuses.

### 3. The ban order in game two

The drive code and the room's own `ROOM_STATE_BAN_FIRST` byte use the identical
rule - the PAIRING's host bans first - so they cannot disagree with each other.
⚠️ But the rule itself is only proven for game one. If the automatic ban happens
on the wrong side in a later game, that is a different bug from the one above,
and which side did it is the useful half of the report.

### 4. Turning the draft back on still gives a normal draft

The safety net. All of the driving is gated on the room setting, so if the
automatic play misbehaves, pressing X gives a working room immediately.

## If it broke something

Both repos carry `test/random-stages` at exactly what is deployed. The last
pair confirmed on hardware is `works/rooms-leave` (asm `ea900c7`, dolphin
`52dc15214`) - ⚠️ that is BEFORE the live band, the announcer fix and
everything about stages, so it is a long way back. Rewinding one repo without
the other is worse than not rewinding at all.

## Known bad, and not part of this test

* **A character's COLOUR is not kept between games.** The character is. The fix
  that exists injects into the character select, and a room goes room -> draft
  -> game and never visits it, so that fix has never run.
* `lanForTesting` is still in the build and must come out before any beta.
* Spectating has never been tried over the real internet.
