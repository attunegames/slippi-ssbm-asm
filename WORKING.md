# What is known to work

Two repositories that only work as a matched pair. A tag on one means
nothing without the tag on the other, so every entry names both.

| What | asm | dolphin | when |
|---|---|---|---|
| Room hands two players to the draft over Slippi DIRECT, and a game is played | `works/rooms-draft-over-direct` (`fbdf5d6`) | `works/rooms-draft-over-direct` (`3973015e8`) | 2026-09-17 |
| The whole room loop: pair, draft, play, report, ROTATE, pair the next two | `works/rooms-queue-rotation` | `works/rooms-queue-rotation` (`65bd21418`) | 2026-09-17 |

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
