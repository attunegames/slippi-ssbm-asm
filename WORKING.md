# What is known to work

Two repositories that only work as a matched pair. A tag on one means
nothing without the tag on the other, so every entry names both.

| What | asm | dolphin | when |
|---|---|---|---|
| Room hands two players to the draft over Slippi DIRECT, and a game is played | `works/rooms-draft-over-direct` (`fbdf5d6`) | `works/rooms-draft-over-direct` (`3973015e8`) | 2026-09-17 |

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
