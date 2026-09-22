# On the rigs right now, and not yet confirmed

This file is the opposite of `WORKING.md`. That one records what has been
proven; this one records what is sitting on the three test rigs waiting for
somebody to press the buttons. It is rewritten each time, not appended to -
once something here is confirmed it moves to `WORKING.md` and leaves.

## The build

Deployed to `Desktop/rooms-lan-test/{Alpha,Bravo,Charlie}` on 2026-09-22.
Identical to the public **beta 13**.

| | commit | tag |
|---|---|---|
| asm | `ae7e88c87` | `test/six-features` |
| dolphin | `e583d9b2b` | `test/six-features` |

    Alpha    exe 25b10d45  codeset b335eaab  module 0bc1d493
    Bravo    exe 25b10d45  codeset b335eaab  module 0bc1d493
    Charlie  exe 25b10d45  codeset b335eaab  module 0bc1d493

⚠️ Those three hashes are the first eight of the md5 of `Slippi Dolphin.exe`,
`Sys/GameSettings/GALE01r2.ini` and `Sys/GameFiles/GALE01/SlippiRoom.dat`. All
three rigs must match each other. A mismatched pair is the single easiest way
to spend an evening testing a build nobody made.

⚠️ The rigs carry no `Update Peppy.exe` and no `VERSION.txt`, deliberately.
They are kept in step by `deploy.sh` pulling straight from CI, and an updater
pointed at the public release would drag a rig backwards to whatever was last
published the moment the two diverge.

## Do this one first

### 0. The NOW LOADING freeze

⚠️ **The only thing here that is a BUG rather than a feature, and the thing
that stopped a real test night.** On the way back to the room after a match the
game logs `room scene load` and never reaches `splash built`. The same return
takes 49 milliseconds when it works.

**Reproduce it:** one player as **Sheik**, the other as **Young Link**. That
froze both clients at the end of the game. The same two players with the second
on DK, Zelda or several others did not freeze once - only Young Link did.

The diagnostic is in this build and reports what the scene asked for on the way
IN, where a build that never returns can still be read:

    [Rooms] prep read   X/Y stage Z   (255 = not picked)
    [Rooms] prep orders X/Y on Z

⚠️ **If `prep orders` is the last line in the log, those three files are what
it died waiting on.** That is the whole question; nothing else needs doing.

Already ruled out, so do not spend time on them: the band rebuild (never fires
- zero occurrences across five logs), a spectator being attached (present in
one freeze, absent in another), the netplay teardown racing the build (lands at
the same +1170ms in the cases that WORKED), and stage, winner, frame count and
end method (all vary across working and frozen alike).

## The six features, none of them seen working

Every address below was read out of the ISO and checked against the game's own
code. That proves they assemble and that the numbers are right. It proves
nothing about what appears on screen, which is what all six of them are.

### 1. The room plays How to Play's music

Open a room. It should play `howto.hps` - the How to Play tune - and not the VS
splash's track.

Song id `0x24`, confirmed against two ids the game already told us: `0x2d` ->
`intro_es.hps`, which is what the splash itself plays, and `0x34`/`0x36` ->
`menu01`/`menu3`, exactly the two the menu's song setter picks between. Both
land where the game says they should.

⚠️ The REAL VS splash before a match must still play its own song. The hack is
gated on the scene rather than the online mode precisely because the mode
covers both.

### 2. Pressing Y is acknowledged

Press Y with a match on. The spectate row should read `Connecting to the match`
with a symbol that MOVES, on the frame the button goes down - not whenever the
room next happens to redraw.

### 3. Z rerolls your costume

On the character select, press Z. Your colour should change, and change again
on another press, without touching your fighter.

⚠️ **Known limitation, and it is ours.** `KeepRoomCostume.asm` treats costume
`0` as "nothing chosen" and replaces it with the colour it remembered, so a
roll landing on the DEFAULT colour silently does not stick. If Z sometimes
appears to do nothing, that is why - it is not the roll failing. A proper fix
needs a "done once this screen" flag rather than a magic value.

### 4. A random character also gets a random colour

Pick random several times. The colour should vary as well as the fighter.

⚠️ Nothing was built for this. Melee already does it at `0x80260b00`:
`Character_GetMaxCostumeCount`, then `HSD_Randi`, then store. This is a test to
find out whether it works, not a test of new code. The costume-0 limitation
above applies here too.

### 5. A random pick stays a question mark

Pick random. The portrait should stay `?` for BOTH players until the match
starts, and the right fighter should appear at the splash.

The character select draws from `+0x3C2` (the icon) while the match reads
`+0x70` (the fighter), so the pick travels normally underneath. Icon `0x19` is
the random token, confirmed twice: the picker rolls `0..24`, and its caller
only invokes random when the selected icon IS 25.

⚠️ Watch that the match still starts with the RIGHT fighter. If the question
mark survives into the game, the wrong field is being held back.

### 6. Spectating starts at the live frame

Join a match already in progress with Y. The first frame drawn should be the
live one, with no double-speed replay of everything that already happened.

⚠️ **The rigs probably cannot test this.** Three clients on one machine means a
watcher is barely behind at all, so the `behind > 10` condition may never fire
and the screen would look identical either way. This needs somebody joining a
match that has genuinely been running a while.

⚠️ **Watch for the opposite failure.** A long catch-up now shows a STILL FRAME
rather than a fast-forward. That is the intent, but if it reads as a freeze it
needs something on screen saying it is working. Say which it felt like.

## Older, still unconfirmed

* A character keeps its COLOUR between games (`0x8025FE84`).
* Spectating over the real internet. The STUN lookup and the hole punch
  connected once - `caught a watcher up, frames 1 to 3569` - but one success is
  not a proven feature. ⚠️ A LAN test passes whether or not it works, which is
  how the missing half shipped in the first place.
* An unanswered matchmaking search. Beta 9 stopped it taking the whole game
  down with it; the search itself still has no timeout anywhere and leaves you
  queued with nothing happening.

## Known bad, and not part of this test

* `lanForTesting` is still in the source. It defaults to off and `peppy.json`
  is excluded from the zip, so no shipped beta can turn it on - but the code is
  there and the rigs still use it.
* The browse screen cannot report a failure. `Looking for rooms...` shows
  whether there genuinely are none or the request was refused, which turned an
  authentication error into an hour of confusion once already.
* An abandoned room is never reaped. The 15-minute reaper only runs inside
  `pd_tick` for a room somebody is standing in, so a room everybody left keeps
  its stale pairing for ever. Harmless litter, and it self-heals when anyone
  rejoins.
* `Build Check` has been red on every run for weeks - the repo does not commit
  its regenerated `.ini` files, so it always reports dirty. ⚠️ `Staging
  Artifacts` is the check that actually assembles. A permanently red check
  means a genuine assembly error looks exactly like the normal state.
