# What is known to work

Two repositories that only work as a matched pair. A tag on one means
nothing without the tag on the other, so every entry names both.

| What | asm | dolphin | when |
|---|---|---|---|
| Room hands two players to the draft over Slippi DIRECT, and a game is played | `works/rooms-draft-over-direct` (`fbdf5d6`) | `works/rooms-draft-over-direct` (`3973015e8`) | 2026-09-17 |
| The whole room loop: pair, draft, play, report, ROTATE, pair the next two | `works/rooms-queue-rotation` | `works/rooms-queue-rotation` (`65bd21418`) | 2026-09-17 |
| Both room screens open clean - no flash of the wrong one | `works/rooms-screens-clean` (`0f4026a`) | `works/rooms-screens-clean` (`5cfbc74d6`) | 2026-09-17 |
| A third person in the room watches the live match, re-simulated from the players' own inputs | `works/rooms-spectate-live` (`962983e`) | `works/rooms-spectate-live` (`709e8959a`) | 2026-09-18 |

## rooms-draft-over-direct

Two people in a room are paired by our own database, introduced to each
other by Slippi's servers as an ordinary DIRECT match, and land in the
draft. Confirmed by playing a game through to the end.

Three things had to be true at once, and each of the first two failed as a
SILENT TIMEOUT - the matchmaking server accepts the ticket and simply never
sends an assignment, so a wrong code and an unreachable one look identical
from the couch:

- `user.json` belongs in `User\Slippi\`, not `User\Config\`. Without it the
  real login never happens and the invented development identity is used,
  which is a connect code no account owns.
- The identity must not live in `s_config`. `LoadConfig()` fills that from
  `peppy.json`, so a real login could be overwritten by the fallback
  depending on whether the heartbeat signed in before the room screen said
  hello - the same build published a real code on one rig and a made-up one
  on the other.
- The separator on the wire is the FULL-WIDTH hash, `0x81 0x94`, because
  that is what Melee's own connect-code entry produces. `UTF8ToSHIFTJIS`
  leaves an ASCII `#` alone and makes a code that is nearly right, which is
  a different code to the server.

NOT yet true at this tag: both clients abort on returning to the room after
the game. Fixed immediately after in dolphin `d0df1693d`, untested at the
time of writing.

## rooms-queue-rotation

The room concept, end to end, with three people. Confirmed by playing three
games through:

- MrBirdMD beat Peppy. Peppy to the back, MrBirdMD stays.
- MrBirdMD beat Bravo - `"crowned": true, "champion": "MrBirdMD"`. Beating
  everyone in the room earns the crown AND sends you to the back, so the
  people who were waiting get their turn.
- Peppy vs Bravo, paired from the queue without anybody arranging it.

Our database owns rooms, the queue, the rotation and who plays who. Slippi's
own servers make every connection, as an ordinary DIRECT match. Nothing here
runs a matchmaking server, a STUN server or NAT punching.

Ending a game is the part that took the work, and all of it was already
solved on `peppy-with-spectate` and had not been ported:

- `pd_result` must be CALLED or the pairing stays `ready`, and a ready
  pairing is one the room asks Slippi to connect - so both players walking
  back in get sent straight out to replay the same person.
- `slippi_netplay->ForceDisconnect()`, or the next search runs against a
  live connection.
- `handleConnectionCleanup()`, deferred 250ms behind a busy flag, or
  `prepareOnlineMatchState` keeps answering "yes, there is a match" and
  Melee restarts the finished one - overruling the character select's move
  to the room about fifty milliseconds later.

⚠ `ROOM_FLAG_READY` is held down while that cleanup runs. The old
matchmaking and netplay clients are destroyed on a detached thread and hold
their port until they are gone.

⚠ `SlippiMatchmaking::FindMatch` assigned over a still-joinable
`m_matchmakeThread`, which calls `std::terminate()` - an instant abort with
no log line, on both clients at once. Stock Slippi never sees it because it
searches ONCE per session; a room searches once per pairing.

Still open at this tag: a genuine draw reports nothing and leaves the
pairing open (`[Rooms] no result to report`).

## rooms-screens-clean

The room scene wears two faces - a room, and the public list - and it opened
as the wrong one for about half a second either way.

One mistake, three places. Each time it asked a question whose answer comes
over the network when a local answer was available the whole time:

- It only asked every 30th frame, so it first drew whatever the scene was
  built as, which is the room's own look. Now it asks on frame 1.
- It asked `ROOMS_FLAG_VALID`, which means a tick has come BACK. Now it asks
  `ROOMS_FLAG_INROOM`, which Dolphin answers from whether we have a room.
- Making a room is two network calls - sign in, then `pd_room_create` - and
  `Enter()` has no code to store until they finish, so `INROOM` was still
  false on the create path. The intent is now recorded synchronously when the
  create is asked for, and taken back if the room is never made.

Plus: `s_was_browsing` starts at 1 so entering a ROOM counts as a change and
switches the band on. Entering to BROWSE started equal to it, counted as no
change, and never switched the band OFF - so the public list kept the
characters whenever it was the first screen opened.

And the status line said "no room" until the first tick answered, which with
the flash fixed would have been the new wrong thing to show. Blank now.

⚠ This pair must ship together. `ROOMS_FLAG_INROOM` is new on both sides;
the module reads it and Dolphin is what sets it.

## rooms-spectate-live

Someone waiting in the room presses Y and watches the match that is already
being played, as a delay-based peer: it connects to BOTH players, takes
their pads, and re-simulates the game. No `.slp` stream, no replay, and the
online major is never left - so the return bug that killed the replay
version cannot happen here.

⚠️ Confirmed on the TEST RIG, which needs `lanForTesting`. Three clients
behind one router cannot reach each other at their shared public address -
the packets hairpin and are dropped - so the watcher falls back to a LAN
address after three seconds. Every piece of that carries a
`TEST RIGS ONLY - DELETE BEFORE THE FIRST BETA` banner. Spectating between
real players over the internet is UNTESTED at this tag.

Five things had to be true at once, and four of them presented as either
silence or a crash:

- A watcher joining mid-match must be TOLD what is being played.
  `StartSlippiGame` ends with `matchInfo.Reset()` ready for the next game,
  so a player's own selections are zeros by the time a match is on screen.
  The watcher was being handed character 0, colour 0, stage 0, and having
  no idea what it was looking at, never started anything - pressing Y
  simply appeared to do nothing. A snapshot is now kept from just before
  that reset.
- ⚠️ The seed is PLAYER 0's `rngOffset`, always. Both players generate
  their own and the match runs on the decider's, who is player index 0.
  Taking whichever packet landed last is a coin flip, and a wrong seed is
  every random thing in the match happening differently - which reads as a
  divergence and is almost certainly part of what the old
  re-simulation attempt died of. The stage has the same trap: it is the
  first player in port order who chose one.
- ⚠️ `localSelections` and `matchInfo.localPlayerSelections` are different
  things. The first is the EXI device's, the second is what
  `prepareOnlineMatchState` reads. Filling only the first left the second
  claiming player index 0 and seed 0 - so `orderedSelections[2]` was never
  filled and the next statement dereferenced it. That was a hard crash one
  line after the handover logged.
- ⚠️ ENet reports a dial that TIMED OUT through the same event as a player
  leaving. The two unreachable addresses gave up at 30 seconds and ended
  the view every time, no matter how well it was going. Only a peer that
  actually answered can end it now.
- Port 2 must stay empty. A watcher has a remote player count of 2, and
  the normal rule reads that as "there is a third player" and marks port 2
  human - standing a motionless fighter on the very port that was chosen
  for being out of the match.

NOT yet true at this tag: the watcher shows no player names, and the splash
puts both players on the same team. Both are cosmetic - the match itself
plays.
