# On the rigs right now, and not yet confirmed

This file is the opposite of `WORKING.md`. That one records what has been
proven; this one records what is sitting on the three test rigs waiting for
somebody to press the buttons. It is rewritten each time, not appended to -
once something here is confirmed it moves to `WORKING.md` and leaves.

## The build

Deployed to `Desktop/rooms-lan-test/{Alpha,Bravo,Charlie}` on 2026-09-22.
⚠️ **Not a public beta.** Nothing has been released with this in it.

| | commit | tag |
|---|---|---|
| asm | `e3e91b8c` | `test/room-picks` |
| dolphin | `ac0e19fb` | `test/room-picks` |

    Alpha    exe 72c98c9a  codeset c3f8f8fd  module f9a8e187  rust 3e629e40
    Bravo    exe 72c98c9a  codeset c3f8f8fd  module f9a8e187  rust 3e629e40
    Charlie  exe 72c98c9a  codeset c3f8f8fd  module f9a8e187  rust 3e629e40

Those are the first eight of the md5 of `Slippi Dolphin.exe`,
`Sys/GameSettings/GALE01r2.ini`, `Sys/GameFiles/GALE01/SlippiRoom.dat` and
`slippi_rust_extensions.dll`. All three rigs must match each other - a
mismatched pair is the easiest way to spend an evening testing a build nobody
made.

⚠️ `PeppyRoom.dat` sits beside `SlippiRoom.dat` in `Sys/GameFiles/GALE01` and
is **not** the live module. `SlippiRoom.dat` is the one CI builds and the one
to replace.

**To go back:** beta 15 is `exe 25b10d45  codeset 16577794  module 0bc1d493
rust 17f5d78f`. Those four files are the whole of a deploy.

⚠️ There is **no `deploy.sh`**, whatever an earlier version of this file said.
A deploy is `gh run download` from the two Staging runs, then four `cp`s into
each rig, then check the hashes above. Nothing automates it yet.

⚠️ The rigs carry no `Update Peppy.exe` and no `VERSION.txt`, deliberately. An
updater pointed at the public release would drag a rig backwards to whatever
was last published the moment the two diverge.

## Do this one first

### 0. The NOW LOADING freeze

⚠️ **The only thing here that is a BUG rather than a feature, and the thing
that stopped a real test night.** On the way back to the room after a match the
game logs `room scene load` and never reaches `splash built`. The same return
takes 49 milliseconds when it works.

The diagnostic has been in the build since beta 8 and has never yet been
captured. If `prep orders` is the last line in the log when it hangs, the three
files named on that line are what it died loading.

Repro that produced it: Sheik vs Young Link, freeze at the end of the game.

## New: characters are picked in the ROOM

Everything below is new and **none of it has ever run**. The whole path from
"the box opens" to "the match starts" is untested on real hardware.

### 1. The box opens for the winner first

Two players queue. When they are paired, the box opens for **the winner of the
last game** - for a first game, whoever has been in the room longest.

- Their slot says `choosing`; the other stays blank
- A clock counts down from 30 beside the two names
- Everyone else in the room sees the same thing

⚠️ The clock counts down locally and is corrected by every tick. If it jumps
around by two seconds at a time, the local count is not running.

### 2. Picking

Stick left/right moves through the roster, **A** locks in.

- The slot fills with the fighter's name
- The other player's box opens and gets its own 30 seconds
- The queue watches both happen

⚠️ **Start, Y, X and hold-Z are suspended while the box is open.** That is
deliberate. **Hold B is NOT** - it must still leave the room. Check it.

### 3. Z rerolls the colour

**Z** on a fighter picks a different costume for it. The line shows `c2`, `c3`
and so on.

⚠️ Z is hold-to-leave-the-queue everywhere else on this screen. While the box
is open it is the colour instead. Leaving the queue mid-pick is meaningless -
you are already paired.

⚠️ `Character_GetMaxCostumeCount` returns a COUNT. If a fighter ever shows a
colour it does not have, that is the off-by-one.

### 4. The question mark

`?` is the last entry in the roster. Pick it and:

- **Both** slots show `?` - yours too
- Nobody learns the fighter until the VS splash
- The splash shows a real character, and the match plays it

⚠️ **The server rolls it, not the client.** If the two players end up on
different fighters, that is the whole design failing, not a cosmetic bug.

⚠️ A timeout is rolled the same way and is indistinguishable from choosing `?`.
Let a clock run out and check it looks identical.

### 5. Both in, then the match

Once both have chosen:

- The box clears
- The band across the top builds the two fighters
- ⚠️ **No draft screen at all** for a room with random stages
- The match starts on a random stage

⚠️ **This is the first time the stage-draft setting has ever done anything.**
It has been stored, shown and sent to the server since part 7 and nothing read
it. Test **both** settings with X:

- **Random stages** (default) - no draft, straight to the match
- **Stage draft on** - the draft still runs, and ⚠️ you will pick a character
  **twice**, once in the room and once in the draft. That is expected in this
  build. The draft cannot be told to do stages only - see the note in
  `RoomSceneDecide`.

### 6. Your controller works

⚠️ **The most likely thing to be broken, and the least obvious.** A room skips
the character select, and the character select is what normally names the 1P
port. This build writes it from the room state instead.

If it is wrong, the symptom is not a crash: **your controller does nothing**,
or it moves the wrong character.

⚠️ Test it **after watching a match**, specifically. The watcher path borrows
port 2 and puts it back, and that interaction is exactly where this would
break.

## Older, still unconfirmed

- The room's music playlist - ten tracks, rerolled on every entry to the room
  scene, including after a match
- A private room's code stays starred until L or R is held

## Known bad, and not part of this test

- `KeepRoomCostume.asm` treats costume 0 as "unset"
- An unanswered matchmaking ticket still has no timeout
- The browse screen cannot report a failure
- Abandoned rooms are never reaped
- ⚠️ `lanForTesting` is still in the code and must come out before any public
  beta
