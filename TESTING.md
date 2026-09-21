# On the rigs right now, and not yet confirmed

This file is the opposite of `WORKING.md`. That one records what has been
proven; this one records what is sitting on the three test rigs waiting for
somebody to press the buttons. It is rewritten each time, not appended to -
once something here is confirmed it moves to `WORKING.md` and leaves.

## The build

Deployed to `Desktop/rooms-lan-test/{Alpha,Bravo,Charlie}` on 2026-09-21.

| | commit | tag |
|---|---|---|
| asm | `a34497745` | `test/draft-pad-release` |
| dolphin | `6615944f9` | `test/draft-pad-release` |

    Alpha    exe c0a0e4eb  codeset d8d07d75  module d4728b1c
    Bravo    exe c0a0e4eb  codeset d8d07d75  module d4728b1c
    Charlie  exe c0a0e4eb  codeset d8d07d75  module d4728b1c

This is what shipped as **beta 4**. Beta 2 (`exe 181fe684`) and beta 3
(`exe 1fa31340`) are both marked superseded on the release page - they carry
the deadlock in section 0a below and cannot finish a drafted match.

⚠️ Those three hashes are the first eight of the md5 of `Slippi Dolphin.exe`,
`Sys/GameSettings/GALE01r2.ini` and `Sys/GameFiles/GALE01/SlippiRoom.dat`. All
three rigs must match each other. A mismatched pair is the single easiest way
to spend an evening testing a build nobody made.

## What to test

### 0a. The draft gives the pad back

⚠️ **The first thing to try, because beta 2 and beta 3 both fail it.** Random
stages worked and then the player who BANNED FIRST could not move at character
select; their opponent unlocked and waited for somebody who was frozen.

The lock that beta 2 added decided when to release by counting draft steps:

    stage_phase = draft_fetch_step < 2 && draft_last_local_step < 2

A client only FETCHES the steps it is not performing. The client that performs
0 and 2 therefore never fetches 2, so `draft_fetch_step` stops at 1 and
`draft_last_local_step` stops at 0 - both under 2 forever, and the pad is never
returned. The other client fetches 2, unlocks cleanly, and waits for a partner
who cannot move.

It now unlocks from two REMEMBERED facts instead of a count: the step this
client performed, and `draft_opp_step_done`, recorded in
`prepareGamePrepOppStep` where the draft legitimately consumes a result.

⚠️ That second detail is not cosmetic. `GetGamePrepResults(step, res)` POPS
every queue entry it passes over, so asking it each frame whether a step is
done would throw away the opponent's stage pick. Never probe it speculatively.

What to watch: **the player who bans first must get their controller back at
character select.** If they are still frozen, the unlock is reading a fact that
never becomes true rather than one that arrives late - a different bug.

### 0b. The four beta fixes, none of them tried

From the first beta night with real people on real networks.

- Four people in a room must run ONE match, not two. (Server side, already
  live - no build needed.)
- Every player's own controller must work. The zip was shipping Alpha's
  keyboard mapping over it. (Packaging, already live.)
- ⚠️ The stage roulette must TAKE the pad. Both players are locked out of
  the whole stage half now, sticks and triggers included. This writes the pad
  every frame of the draft - if a PADStatus offset is wrong it will be
  obvious and ugly immediately. Try one two-person draft before anything
  else.
- Practice must end itself when your match comes up. Queue with two others,
  press START again to practise, and let their match finish.

### 1. The draft drives the RIGHT side

The drive used to work out who bans first from its own copy of the rule the
room publishes as ROOM_STATE_BAN_FIRST, and the two could disagree. One
client announced `driving draft step 0` and auto-pressed into a screen that
was waiting for its OPPONENT to ban, while the draft sat on the other client
waiting for a human. Fourteen minutes later somebody banned by hand and
nothing lined up again. Two of five games failed that way in one session.

It now asks the draft instead: the draft polls each client about the step it
is NOT performing, so the other one is ours. The log line says what it
concluded and on what evidence:

    [Rooms] driving draft step N, sweep M (draft asked about K)

⚠️ If N and K are ever the SAME number, the inference itself is wrong and
that is a different bug from the one this replaced.

### 2. A second draft in the same room drives its stages

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

### 3. Pressing X is acknowledged

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

### 4. The ban order in game two

The drive code and the room's own `ROOM_STATE_BAN_FIRST` byte use the identical
rule - the PAIRING's host bans first - so they cannot disagree with each other.
⚠️ But the rule itself is only proven for game one. If the automatic ban happens
on the wrong side in a later game, that is a different bug from the one above,
and which side did it is the useful half of the report.

### 5. A character keeps its COLOUR between games

New in this build, and the one thing here with no earlier test behind it.
Play the same fighter twice in a row and the costume should come back with
it - not just the fighter.

Melee already takes the costume out of the match block at scene load, which
is why this always looked like it should work. What was throwing it away is
four instructions after the character is applied: the cursor starts the
screen on a default fighter, the one that arrives is whatever was played
last, they differ, and the costume set correctly a moment earlier is wiped.
The character survives because it is applied from the block. Only the
colour is lost.

⚠️ It only fills in a cursor that has NO costume yet, so it cannot fight a
player who is choosing one. The case it can get wrong is deliberately
picking costume 0 when the last one was not 0 - if that snaps back to the
old colour, this is why.

### 6. A pairing that will not connect does not freeze the room

Hard to trigger on purpose, because it depends on Slippi's own servers.
Seen once: the server took one client's connection and never answered its
create-ticket, while the other client's ticket sat open waiting for an
assignment that could never come. Both rooms waited an HOUR with the two
names up on the band and nothing on screen.

If it happens again the queue's own row should now read
`Connecting - trying again`, up to three times, and then
`Slippi could not connect us`. The log says
`Slippi could not connect us - asking again` each time.

⚠️ This only covers the side that gets an ERROR. The side whose ticket is
accepted and never assigned has no timeout in Slippi at all and can still
wait forever - the retry is meant to rescue it by giving it a partner. If
that does not happen in practice, that side needs its own answer, and
interrupting a live search is not as safe as restarting a failed one.

### 7. The rotation, after a crown

Server-side, already applied to the live database - no build involved.

Beat everyone in the room and the next game should be the OTHER TWO. It was
not: pd_result sent the champion to the back with now() and then the loser to
the back with now(), and now() in PostgreSQL is the TRANSACTION's clock, so
both landed on the same microsecond. Confirmed in the table:

    Bravo    (loser)     queued_at 18:25:52.021941
    MrBirdMD (champion)  queued_at 18:25:52.021941   crowns 1

The champion now goes a second behind.

### 8. A disconnected game does not brick the room

Also server-side. A pairing that reached 'ready' and never finished was never
reaped, and pd_tick will not pair anyone who is already in one - so both
players dropped out of the rotation silently and permanently. Found live:
PX8M had all three players present with two of them locked out.

Now given up on after fifteen minutes. ⚠️ That is the recovery time, so a
room that loses a game will look stuck for a quarter of an hour before it
heals itself. Making a new room is still the faster answer.

### 9. Turning the draft back on still gives a normal draft

The safety net. All of the driving is gated on the room setting, so if the
automatic play misbehaves, pressing X gives a working room immediately.

## If it broke something

Both repos carry `test/random-stages` at exactly what is deployed. The last
pair confirmed on hardware is `works/rooms-leave` (asm `ea900c7`, dolphin
`52dc15214`) - ⚠️ that is BEFORE the live band, the announcer fix and
everything about stages, so it is a long way back. Rewinding one repo without
the other is worse than not rewinding at all.

## Known bad, and not part of this test

* `lanForTesting` is still in the source and must come out. It defaults to
  off and `peppy.json` is excluded from the zip, so no shipped beta can turn
  it on - but the code is still there and the rigs still use it.
* ⚠️ Spectating over the real internet is STILL unproven. The STUN lookup and
  the hole punch shipped in beta 3, and the rigs cannot test either of them:
  on one network there is no NAT to open, so a LAN test passes whether or not
  the code works. That is exactly how the missing half shipped in the first
  place. It needs people on genuinely different connections.
