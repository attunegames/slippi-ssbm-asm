# Known-good states

Peppy is two repositories that only work as a matched pair - the codeset
(`slippi-ssbm-asm`) and the fork (`peppy-dolphin`). A commit from one is
meaningless without the one from the other, so every entry here records both.

**Add an entry the moment a feature is CONFIRMED working by a human**, not when
it compiles and not when it looks right in a log. Tag both repositories at the
same time:

    git tag works/<feature> <sha> && git push origin works/<feature>

To get a known-good state back, build both tagged commits and put them in their
own folder under `Desktop\` - never over the live test installs.

**The spectate rebuild (from 2026-09-14):**

* `Desktop\peppy-spectate-good` - the confirmed-working Sept 10 build.
  ⛔ NEVER deploy over this. It is the only thing we can measure against.
* `Desktop\peppy-spectate-good - Copy` - where rebuilt versions go.
* Source stays in `C:
oot\slippi-ssbm-asm` and `C:
oot\peppy-dolphin`,
  branched from `works/spectate`.

The plan, in four steps, testing spectate after each - the draft is last on
purpose, because it is what moved players off the character select and the
watcher's entry depended on that:

  1. the room scene
  2. the menus
  3. the queue overlay
  4. the draft CI artifacts
survive for months, so check for an existing build of that SHA before starting
a new one:

    gh run list --limit 60 --json databaseId,headSha,conclusion \
      --repo attunegames/peppy-dolphin -q '.[]|select(.headSha|startswith("<sha>"))'

---

## spectate - 2026-09-10

| repo             | commit      | what it is                                        |
|------------------|-------------|---------------------------------------------------|
| peppy-dolphin    | `24d4176e8` | fix: ration the advance signal rather than refusing it |
| slippi-ssbm-asm  | `419813c`   | fix: stop telling queued players to press a button that does nothing |

Tagged `works/spectate`. Confirmed by building both into
`Desktop\peppy-spectate-good\` and watching a live match catch up and settle.

**The mechanism, because it was rewritten twice and broken both times.** A
watcher catching up needs TWO things together, in `shouldAdvanceOnlineFrame`:

    PeppyCatchUpSpeed(behind > 10);                  // throttle off, may exceed 60fps
    return behind > 10 && (frame % 2) == 0;          // RESP_ADVANCE, every other frame

* Rationing is not optional. Returning it every poll makes the frame counter
  race ahead of a simulation that never runs.
* `RESP_CATCHUP` (5) is NOT a substitute. Only `ForceEngineOnRollback` reads it
  and it declines whenever the engine loop count is already zero.
* Do not "tidy" the throttle call away. It looks unreachable whenever a
  `frameResult = 5` branch sits in front of it - that branch is the bug, not
  the proof.

⚠️ At this commit the room scene does not exist yet; it was written the
following night. That build's flow is Rooms -> character select.

---

## spectate on the CURRENT build - still broken, 2026-09-13

Fixed and verified tonight:

* **pacing** - catches up and settles. Log shows `9 behind` holding steady at
  60fps. Two halves, both needed: `PeppyCatchUpSpeed(behind > 10)` and
  `RESP_ADVANCE` rationed to `(frame % 2) == 0`.

NOT fixed:

* **divergence** - right clock, wrong damage. The watcher simulates a different
  match.

What has been ruled out, by diffing against `works/spectate`:

* Dolphin's watch path - timeline struct, pad lookup, `PeppyWatchPad`,
  `PeppyWatchSetFrame`, the skip test, remote pad supply, the RNG offset. All
  unchanged in substance.
* `ForceEngineOnRollback` - the only in-game codeset change, and inert now that
  nothing sends `RESP_CATCHUP`.
* The character-select entry. TRIED and it does not start at all: on the 10th
  the players were on that screen and THEIR inputs drove the watcher's copy of
  it into the match. They draft now, so nothing drives it.

Last thing tried, unverified: the input source port. `InitOnlinePlay` reads the
1P port from `-0x5108(r13)`, written by `CSS_StoreSinglePlayerPortNumber` from
the character select's A press. A watcher never presses A, so on the splash
path it holds whatever was there; the watched inputs go to port 0. Now forced
to 0 in `PeppyRoomSceneDecide`.

⚠️ Two harness runs in a row proved nothing and looked fine:
  * both characters idle - two still characters match trivially
  * Charlie joined the queue early and became a PLAYER, not a watcher
A test that cannot fail is not evidence. The harness now makes them fight and
delays Charlie's Start past the first pairing.

---

## spectate on the LIVE build - WORKING, 2026-09-15

| repo             | commit       | branch                | what it is                                      |
|------------------|--------------|-----------------------|-------------------------------------------------|
| peppy-dolphin    | `a1210d048`  | `peppy-with-spectate` | fix: a second conflict block in the same header went unresolved |
| slippi-ssbm-asm  | `154fe2f`    | `peppy-with-spectate` | feat: bring the replay-based spectate into the live build |

Tagged `works/spectate-live-build` (the tag sits on the commit that added this
entry; the code is `154fe2f` / `a1210d048` unchanged). Successful CI builds of
both, so a restore needs no 20-minute rebuild:

    gh run download 34917871528 --repo attunegames/slippi-ssbm-asm   # codeset + mex-modules
    gh run download 34918649322 --repo attunegames/peppy-dolphin     # exe + dll

Confirmed by a human: Alpha and Bravo
played a matchmade game from a room, Charlie pressed Z and watched it live.
**First game worked and the spectate of that game worked.**

This is the merge of the replay-based spectate (proved on `peppy-rebuild`,
tagged `works/spectate-live-catchup`) into the live `peppy` line, so everything
else is still there: training mode, the room with its queue and lobby, the
draft, the menus.

### What replaced what

The bespoke pad-relay is gone. `peppy_room_spectate()` in `Peppy/Modules/room/room.c`
no longer calls `peppy_room_go_to_splash()`; it hands over to **Slippi's own
replay playback**, running in the same window:

    if (!peppy_room_stream_ready()) { peppy_log("Peppy: nothing to watch yet..."); return; }
    SCENE_CTRL.pending_minor = 0;
    MenuController_WriteToPendingMajor_1to_0xC(SCENE_MAJOR_DEBUG_MELEE);
    Scene_ExitMinor();

A live spectate is just a replay of a `.slp` that has not finished being
written - `mode: "mirror"` with `isRealTimeMode: true`. `SlippiSpectateClient`
(new, in `SlippiSpectate.cpp`) connects to the broadcaster's ENet spectate
server, base64-decodes the event payloads into a growing `.slp`, and points the
comm file at it. Melee drives the playback itself over EXI; Slippi's own
hard/soft fast-forward catches the watcher up, which is the ~1s freeze before
live gameplay appears.

### Traps, all of them paid for

* **A new EXI command MUST be registered in `payloadSizes`.** `CMD_PEPPY_REPLAY_WAITING`
  (0xCA) was not, so the dispatcher logged `Invalid command byte` and returned,
  and the game read back 0 with no other symptom. It is a non-consuming peek -
  `CMD_IS_FILE_READY` (0x88) both loads AND marks played, so it cannot be used
  to ask "is there anything to watch".
* **Playback hooks need scene guards they never needed upstream.** `FetchGameFrame`
  and `RestoreGameFrame` fire in EVERY scene once the playback codes are in a
  netplay build. Unguarded, they ran during real online matches and broke
  matchmaking. Both now test the scene and exit unless it is
  `SCENE_PLAYBACK_IN_GAME` (0x010E). One whole day went to this.
  ⚠️ Use `r12` as the base register, not `r0` - `r0` means literal zero there.
* **The handover must come from inside Peppy's own major.** From a scene Load
  there is no minor to end and the request is silently dropped; from the main
  menu the destination major gets overwritten (always landed on 0x18); from a
  GObj think that `Scene_ExitMinor` destroys in the same frame nothing survives
  to re-assert it.
* **Do not re-apply Slippi's ScenePrep patch** (`0x801b09c0` -> `0x801b16a8`).
  It overwrites a live function's first instruction and crashes when minor 3's
  prep runs.
* **`room.c` compiles into `PeppyRoom.dat`, not the ini.** Shipping only
  `GALE01r2.ini` leaves the new trigger inert with nothing in the log to say so.
  Deploy the `mex-modules` artifact too.
* **HSD heaps reset between scenes** - a cached `HSD_MemAlloc` pointer is
  dangling after a scene change (`Unknown Pointer 0x03414c40`). Use
  `OFST_R13_SB_ADDR` (-0x503C), which is what `logf` uses.
* `StartMelee.asm` merges the online and playback bodies behind a scene test at
  `0x8016e748`; generated by `Peppy/Playback/merge-startmelee.py`, not hand-edited.

### Deployed at

`Desktop\peppy-lan-test\{Alpha,Bravo,Charlie}` - exe, dll, `GALE01r2.ini` and
all three `.dat` modules. Previous files kept beside them as `.pre-spectate`.
Spectate ports set per-instance so three on one machine do not collide on bind:
Alpha 51441, Bravo 51442, Charlie 51443.

### Known gaps at this tag

* **No NAT traversal on the spectate port** AT THIS TAG. LAN and loopback only.
  A NAT hole belongs to ONE socket, and the stream does not travel on the
  netplay socket - so the mapping the game already has does nothing for the
  spectate server's own socket, and the watcher's connection reaches the
  broadcaster's router as an unsolicited packet it is built to drop.

  Addressed AFTER this tag in peppy-dolphin `78e47cb4f`, ⚠️ **UNTESTED off-LAN**:
  the watcher STUNs its own client socket and publishes `p_watch_external`, the
  broadcaster knocks at it once a second from the SPECTATE server's socket
  rather than from netplay, and both `lan` and `external` are dialled in turn
  instead of taking `lan` whenever it is present (which sent a watcher on
  another network to the broadcaster's `192.168.x.x`). Both halves of the punch
  already existed for the old pad-relay watcher; only the socket was wrong.
  Symmetric NAT will still fail, the same limitation netplay has. The backend
  needs no migration - `migrate-peppy-dolphin-18` already takes
  `p_watch_external` and returns the punch list.
* ~~The watch target's port is assumed to be the default 51441~~ - FIXED after
  this tag in `666cd3442`, ⚠️ UNTESTED. The watcher used to take the
  broadcaster's NETPLAY address, drop the port and assume 51441. Wrong twice:
  the port is configurable and must differ when several clients share a machine
  (so watching Bravo dialled Alpha, and it only ever looked right because the
  watched player happened to hold the default), and across the internet what
  matters is the port the NAT mapped, not the one that was bound. The
  broadcaster now STUNs its own spectate socket - once, right after
  `enet_host_create`, BEFORE the service loop starts reading it - and publishes
  `host:port`. **Needs `migrate-peppy-dolphin-19.sql` run by hand.** Without it
  the room returns no address and spectating does not start; nothing else is
  affected.

**⛔ The LAN path is GONE as of `516337f81`** - this build is for people playing
each other over the internet, and the shortcut was not free: a watcher on
another network dialled the broadcaster's `192.168.x.x`, waited out the whole
connect timeout, and only then tried the address that works. Nothing publishes
`p_lan`, the watch target is the external address, and a pairing always takes
the opponent's external address.

⚠️ **This changes how to test on one machine.** Alpha, Bravo and Charlie now
reach each other by hairpinning out to the router and back instead of going
straight over the LAN. Most routers do that; if this one does not, same-machine
testing stops working and the symptom is a connection that simply never
establishes. That is a property of the network, not a regression - check it
before chasing it in the code.
* Four playback polish files are out of the build, in `Playback/Core/Extras/`:
  `RestoreStockSteal`, `RestoreLRAStart`, `CleanDynamicGeckos`,
  `PreventDressRemoval`. They need scene guards before they go back.

See `PLAYBACK.md` for the full recipe.

---

## The room loop - IN PROGRESS, 2026-09-15

The loop this is being built to:

  1. press Start to queue into the room
  2. two get matched, into the draft
  3. they play
  4. the game ends and both are put back into the ROOM
  5. the room matches the next two, from the front of the queue

and for a spectator: ask to watch, watch, and on the match ending go back to the
room. ⛔ Not auto-queueing anyone yet. Get everybody into the room reliably
first; pressing Start for them is a later, smaller job, and doing it early is
what caused the worst bug below.

### Two pieces that are each fine alone and deadlock together

⚠️ **Read this before touching either.**

* **The auto-requeue** - finishing a game put the player straight back into
  matchmaking. Written when the room had no screen and the character select was
  where a Rooms player waited.
* **The character-select bounce** - in Rooms, that screen sends you to the room.
  Added when the room got a screen.

With both, the character select is up for about 300ms, matchmaking restarts
inside that window, Melee starts a match from a result it still had lying
around, and the bounce never gets a turn. The signature is unmistakable:

  * the SAME match id reported every ~4.4 seconds
  * scene going minor 02 -> 00 -> 04 -> 02, and minor 06 never once
  * DISCONNECTED on screen over a match replaying forever

`rebuild` has the requeue and NOT the bounce, which is why it behaves: you land
on the character select already queued. That is also why "it worked on rebuild"
is misleading - rebuild has no room module at all (`Peppy/Modules` does not
exist on that branch), so there was nothing to return to and no rotation to get
wrong. What was proven there is entering spectate and catching up to live.

Resolved by dropping the requeue, not the bounce.

### MSRB_ROOM_FLAG_WATCHABLE means "there is a match worth watching"

It does NOT mean "I am watching it". The two were the same while only a queued
watcher ever had the flag set. Once the spectate stream started for everybody in
the room - so somebody in the lobby could press Z - the two PLAYERS had it too,
and the character select's "except a watcher" case kept them there. Any new test
of this flag needs to say which of the two it means.

### The queue has to be a queue

Pairing picked its two in `joined_at` order - when you walked into the room,
which never changes - so the first two to arrive were matched, finished, and
matched again while a third waited all night. Invisible while a finished pair
kept playing each other anyway. `migrate-peppy-dolphin-20.sql` orders by
`searching_at` instead, and the queue list and the position counter with it, or
the screen shows one order and the room plays another.

### Still open: a spectator's return crashes

The transition works - `major 0e` -> `major 08 minor 06` fires the moment the
broadcaster finishes. What fails is the module. Melee asks Dolphin for
PeppyRoom.dat and is answered:

  Getting file size for: PeppyRoom.dat -> 19900

and then never asks for the contents - no `Writing file contents`, which the
working path has. So the region keeps what was in it and the scene machinery
runs off the end into zeros: `Unknown instruction 00000000 at PC = 80bf5460`,
the same address every time, with `File_Load` and `File_WaitForFileToLoad` in
the trace.

Between those two requests is one branch, on the length read back from the EXI
buffer. `TransferFile.asm` now logs `Peppy: replacing a file, %d bytes` on the
replacement side; the line appears for other files, so its absence for
PeppyRoom.dat says the branch went the other way and the file quietly fell back
to the disc, where it does not exist.

---

## Watching as a MINOR of the online major - TRIED AND REVERTED, 2026-09-15

⛔ Reverted. The code is on the tag `experiment/playback-as-minor`; the branch
went back to the commit before it. Read this before trying it again - the idea
is sound and most of the groundwork is done, but it is not free.

**What it fixed:** the crash inside the room's load. Staying in the major means
the heaps are not reset, so the splash artwork is still resident and that load
has nothing to fetch.

**What it cost:** the catch-up stopped, silently. `FastForward.asm` tested major
`0xe` and minor `0x1` as raw numbers rather than through SCENE_PLAYBACK_IN_GAME,
so the test simply never passed again - the replay still played, still accurate,
just permanently a couple of seconds behind with no way to close the gap. Any
future attempt must grep case-insensitively for raw scene numbers; "cmpwi r3,
0xE" does not match "cmpwi r3, 0xe".

**What it did not fix:** the room still did not draw on the way back, and in a
worse form. As a major the room's load RUNS and dies somewhere nameable. As a
minor it is never called at all, from any predecessor, and four attempts did not
find out why - the character select route (dies in SlippiCSS.dat, "Invalid read
from 0x31000204", a float read as a pointer, because that module expects an
online match and a returning watcher has none), the heap count, a decide of its
own on the match scene, and this major's prep instead of DebugMelee's.

Reverted because it traded a diagnosis for a mystery.

### Worth keeping from it

* The numbers, read out of DebugMelee's table rather than guessed:

      minor 1  common 2  heaps 2  prep 801b13b8  data 80480530 / 80479d98
      minor 3  common 7  heaps 2  prep 801b16a8  data 8047c020 / 0

* **Playback's match is common minor 2 - the same scene an online match is.**
  One think serves both, which is exactly why the playback codes need a scene
  guard at all.
* The waiting screen cannot be left from: its think is a LOOP that renders and
  waits for retrace itself, so ending a minor inside it does not set the next
  scene up.
* Training does NOT return to the room directly either - it asks for the
  character select and lets that screen send it on. Nothing has ever entered the
  room from a sibling minor.

## ⛔ THE SPECTATOR'S RETURN - measured, not solved (2026-09-15)

**The one fact that matters, and it is measured rather than inferred:**

    working entry:  prep -> room scene load -> room scene built -> room think is running
    the return:     prep -> replacing a file, 20396 bytes -> (nothing)

Coming back from a watch, PeppyRoom.dat transfers IN FULL and then **neither its
load nor its think runs**. Both are bound by m-ex out of that module, so the file
arriving and the module being attached to the scene are separate steps and only
the first one happens. The room has no code at all: a black screen, and a crash
for anything that calls a pointer that was never rebound.

That is why the crash lands inside module space on an address holding data -
nothing of ours was ever put there.

### What this ELIMINATES - do not re-try these

The scene arrives at `major 08 minor 06` correctly on every single attempt. It
is not the transition. Specifically ruled out, each by a test:

* which predecessor you come from - the character select, the match, the waiting
  screen; all reach the room, none bind the module
* the pending-minor convention (one-based 7 vs plain 6)
* `Event_StoreSceneNumber` - it is what the MENU uses, and it does not travel:
  called from the playback screen it moves the MINOR, landing on major 0e minor
  08 and never leaving that major
* moving playback under the online major - see the section above; also cost the
  catch-up
* the persistent-heap count
* freeing the playback think's EXI buffer on the way out (it does leak, and
  fixing that changed nothing here)
* loading the room's backdrop from the scene prep - ⛔ this BREAKS room creation
  outright, a prep cannot call another scene's load

### Every destination arrives broken - it is the EXIT, not the destination

    the room            module transferred in full, never bound - black screen
    character select    dies inside SlippiCSS.dat (float read as a pointer)
    the main menu       reaches it, Charlie still queued, invalid instruction ~2s later
    playback as a minor same, from every predecessor

Four destinations, four different failures, and an evening spent asking which
destination was wrong. What they share is that they were all entered FROM the
playback major. Whatever that scene leaves behind is what breaks the next one.

Things that sounded like the answer and were not, each tested:

* the overclock. The catch-up IS one - `setHardFFW` sets `m_OCEnable` and
  `m_OCFactor = 4.0`, and only `setHardFFW(false)` puts it back, so a watch that
  ends mid-catch-up hands the next scene a four-times CPU. That is a REAL bug and
  the fix is kept. It is not this one: clearing it changed nothing.
* Dolphin still serving the watched match's block after Melee had gone. Also
  real, also fixed, also not it - the "Watch block slot 0/1" lines stopped and the
  crash stayed.
* ⛔ `SlippiSpectateClient::Stop()` from the EXI handler. Do NOT do this: it joins
  the client thread and closes the replay file from the emulation thread, and
  Dolphin dies silently mid-session. Flags only on that path.

### Where to look next

What m-ex does between transferring the file and attaching think/load/leave to
the scene. That step is the one that does not happen, and nothing in the codeset
we own is between those two points - it is in the m-ex runtime.

⚠️ Do not accept "the scene reached minor 06" as evidence that the entry worked.
Reaching a scene and having it set up are different things, and reading the
scene log as proof of both is what cost an entire evening.


## ⛔ The replay-based spectate is OUT of the live build - 2026-09-16

Removed on the advice of Fizzi, who wrote Slippi:

> "I don't think trying to merge the replay based broadcast system with in-game
> stuff is a good idea. Probably will add a lot of complexity and be fairly jank.
> It'd probably be better if they functioned the same as the players in the game
> but don't send inputs and operated on delay based netcode effectively"

> "I recommend you scrap the broadcast idea. If the spectators are the one
> desyncing, you should just make it so they never need to fast forward by
> effectively setting the amount of rollback frame to zero."

Two days of evidence agree. Every bug after the merge was a SEAM bug, not a
spectating bug - the watching itself always worked. The playback major's think
is a blocking loop, both majors share the persistent heaps and the preload
cache, and the return is where the room module fails to rebind.

**Restore point: `git tag pre-unmerge/replay-spectate`** (both remotes). That
state spectates correctly and cannot get back out.

### What the unmerge was

Smaller than it looks, because the merge had MOVED the original rather than
rewritten it:

* `Online/Superseded/InitOnlinePlay.asm` -> `Online/Core/InitOnlinePlay.asm`.
  `Online/Core` is built recursively, so the online body owns `0x8016e748`
  again exactly as before.
* Dropped both Playback sections from `netplay.json` and
  `$Required: Slippi Playback` from each regional ini. That takes
  `Peppy/Playback/StartMelee.asm` - the 917-line merged dispatch - out with
  them, since it was the only `Peppy/` entry in the build.
* Nothing else referenced playback in built code: only comments and an unused
  `.set SCENE_PLAYBACK_IN_GAME`.

Codeset went 175887 -> 163618 bytes; `grep "Slippi Playback"` on the built ini
returns nothing.

### Most of Fizzi's architecture is still in the tree

It was built, then abandoned for the replay approach. The caller is gone; the
rest compiles and is wired together:

| piece | state |
|---|---|
| `PeppyWatchRemotePad` in `prepareOpponentInputs` | **live** - feeds Melee by Slippi's own input path |
| `s_timeline` - frame store, waits for complete frames | intact |
| `PeppyWatch(endpoint)` - receives pads over ENet | intact, **never called** |
| broadcaster side - `PeppyForward` relays every pad packet to `m_spectators` | **live** |
| `NP_MSG_PEPPY_WATCH` - attaches a watcher and sends the backlog reliably | **live** |

⛔ An earlier note here said the send side was gone. It is not - it is named
`PeppyForward`/`PeppyRecord` in `SlippiNetplay.cpp`, called on BOTH the send
path (830-831) and the receive path (1238-1239), so every pad a player sends or
receives is already relayed to attached watchers.

**The only missing link is the CALLER.** Nothing invokes `PeppyWatch(endpoint)`.
The Z handler calls `SlippiSpectateClient::Watch(host, sport)` - the replay path
- at SlippiMatchmaking.cpp:1896. Pointing that at `PeppyWatch` instead is the
switch.

Delay-based is already how the watcher runs: `PeppyWatchLatestFrame()` returns
`s_timeline.CompleteHigh()`, the highest CONTIGUOUSLY complete frame, and
`PeppyWatchRemotePad` clamps to `min(that, frame)`. Melee is never told it may
simulate past a frame whose inputs are all known - no speculation, no rollback,
no catch-up. That IS what Fizzi asked for.

⚠️ The wire format is fixed-size and zero-padded
(`tx.resize(SLIPPI_PAD_FULL_SIZE * ROLLBACK_MAX_FRAMES, 0)`), so the ASM side
always gets the same block however many real frames are in it. That makes a
watcher window of 1 safe - but it is belt-and-braces, because the latestFrame
clamp already prevents speculation.

⚠️ `ROLLBACK_MAX_FRAMES` is a `#define 7` used in buffer sizing AND in the
watcher's own pad loop:

    tx.resize(SLIPPI_PAD_FULL_SIZE * ROLLBACK_MAX_FRAMES, 0);
    for (s32 f = latest; f > latest - ROLLBACK_MAX_FRAMES && ...; f--)

A literal 0 emits NO pads and sizes the buffer to nothing. The translation of
"set rollback to zero" here is **1** - one frame, no speculation.

⚠️ `s_timeline.Expect(s_selections.Count())` already refuses to simulate a frame
until every player's pads have arrived - which is delay-based behaviour, added
to fix the exact desync Fizzi is describing. Part of the suggestion may already
be in. Worth asking before changing it.

### Why this should work where the merge did not

A spectator that behaves like a player inherits the room -> match -> room path,
which is PROVEN: Alpha and Bravo play, the match ends, both land back in the
room and the queue rotates. No second major, no module to rebind, no shared
heap, and no 2-second lag, because nothing is replaying a file being written.

## ⛔ CORRECTION: the module does NOT arrive on a spectator's return

This overturns "Every destination arrives broken - it is the EXIT, not the
destination" and "the file arrives fine, so it is m-ex's root lookup". Both were
built on the `dest %08x` line in `TransferFile.asm`, which reports **r27 - where
Melee MEANT to put the file** - and is logged several calls before the DMA that
would write it. Identical `dest` on both paths therefore proved nothing.

Measured from Dolphin instead (`PeppyDumpRoomArchive`, reading emulated RAM):

    working entry  31:30:458  prep -> replacing a file 20396 -> dest 80bf0a20
                   31:30:459  room scene load                     <- binds
                   31:30:505  DAT at 80bf0a20 filesize 20396 nroots 1   ✅
                   31:30:658  room think is running

    the return     32:47:790  scene 0e/03  DAT at 80bf0a20 filesize 1250368
                   32:47:801  prep -> replacing a file 20396 -> dest 80bf0a20
                   32:47:891  scene 08/06  DAT at 80bf0a20 filesize 1250368   ❌
                                                            (no room scene load)

The header at the destination is **byte-identical before and after the transfer**
- still the playback scene's leftovers. The module never lands. m-ex then reads a
DAT with `nroots 0`, `File_GetSymbol` walks nothing, returns 0, and binds nothing.

### The crash puts an address on it

Hitting spectate from the draft: `IntCPU: Unknown instruction 00000000 at
PC = 80bf59e0`, reached through

    zz_001668c_ [800166b4]   File_WaitForFileToLoad   <- TransferFile hooks 800166b8
    zz_0016be0_ [80016c30]   File_Load
    zz_01a4014_ [801a40c4]   the m-ex binder

`0x80bf59e0` is `80bf0a20 + 0x4FC0` - the buffer plus its aligned size. So a
bound export points just past the module and the game runs into zeros. The
silent return, the black screen in the draft and the join-a-room crash are very
likely one bug, not three.

⚠️ `TransferFile.asm` writes the length to the parent's out-param
(`stw REG_FileLength, 0(r28)`) BEFORE requesting the contents. If the contents
exchange does not complete, the parent still believes it has a 20396-byte file
and hands the garbage buffer to `Archive_InitOnLoad`. An older note in that file
had already seen this once: *"Dolphin answers the length request ... and is then
never asked for the contents."*

## The queue rotated the same two players forever - FIXED, migration 22

Three-player test: Alpha and Bravo played, Charlie was queued and waiting, Bravo
lost, and the room put Alpha and Bravo straight back into the draft.

`pd_result` has always ended with the loser going to the back:

    update pd_members set joined_at = now() where player = v_loser;

Migration 20 changed the ordering to `searching_at` and 21 to
`coalesce(queued_at, now()) asc, joined_at asc`, which left `joined_at` as
nothing but a tiebreaker. `queued_at` is written once and deliberately kept
across ticks - that is what 21 is FOR - so the two who just played still carry
the timestamps from the first time they pressed Start, which beat anyone who
queued while they were playing. The same two are picked again, forever.

Migration 22 moves the loser (and a crowned winner) on `queued_at` as well.

⚠️ **A fix to the queue's ordering has to be applied to `pd_result` too.** They
are two halves of one mechanism and they live in different migrations.
### ⛔ Two ways a debug probe took the Rooms row off the online menu

Both cost a deploy and a test cycle. Neither was about "the m-ex region" as
such, which was the wrong lesson drawn the first time.

**1. The m-ex binder's addresses are fictional.** The binder is a gecko C2 at
`0x801a40c8`. Only that address is real - the 43-line body lives in the
codehandler's own block. Disassembling it based at `0x801a40c8` is a reading
convenience. A C2 injected at `0x801a4118` to watch the `beq` therefore did not
hook the binder at all; it hooked whatever real game code sits at
`0x801a4118`, which is menu code. ⛔ The binder cannot be hooked with a C2.
Hook the game functions it calls instead - they are ordinary code:

    0x80016be0   File_Load          (loads the module file)
    0x80380358   File_GetSymbol     (the "mnFunction" root lookup)

**2. `logf` clobbers CR1 and the volatile FPRs.** `backupall` covers r3-r31 and
nothing else, and `logf` does `crset 6` on its way into sprintf. A probe was put
at `0x80016af0` believing it to be `Archive_InitPostLoad`. Disassembly says it
is not: it is a **varargs** archive symbol lookup, whose prologue reads `cr1` to
decide whether to spill `f1`-`f8`, then walks `va_arg` calling `File_GetSymbol`.
A `logf` immediately in front of it flipped that decision for every archive
symbol lookup in the game, so menu artwork lost its symbols.

    ⛔ Never place a logf immediately before a varargs prologue.
    If CR must survive, save it by hand: `mfcr r20` ... `mtcr r20`
    inside a `backup`/`restore` pair (r20-r31 are the ones backup covers).

**3. Verify an injection address by disassembling it.** `0x80016af0` was reached
by reasoning from `Archive_InitDat = 0x80016a54` in the symbol map.
`Archive_InitDat` ends with `blr` at `0x80016aec`, so `0x80016af0` is simply the
next function - a different one entirely. `scratchpad/ppcdis.py <addr>` prints it.


**4. `File_GetSymbol` itself cannot be hooked either.** A third probe, on
`0x80380358`, with CR saved by hand and the log filtered to the `"mnFu"` name so
it fired a handful of times - still took the Rooms row off the menu. The filter
and the CR were not the problem.

⛔ **Stop probing this bug from the codeset.** Every hook that answers it has to
sit on the path the whole game uses to resolve archive symbols, and that path
will not tolerate a `backup`/`restore` pair on every call. Three attempts, three
broken menus, three test cycles.

✅ **Read it from Dolphin instead.** `PeppySceneWatch()` already polls emulated
RAM from its own thread and logs on change; it injects nothing into the game and
cannot break a menu. `Memory::Read_U32` works on any address. The archive struct
is findable without knowing the heap layout, because `Archive_InitOnLoad` stores
its data base at `+0x20` - so the struct describing our module is the one with
`0x80bf0a20` at that offset.

**Restoring is instant, and does not need a rebuild.** Keep the known-good
`GALE01r2.ini` on disk (`scratchpad/_verify/pre/`, md5 `cdcbc7ae...`) and copy it
over the three installs. That turns a broken menu into a 5-second fix instead of
a build-and-deploy cycle.

**Reverting is verifiable, so verify it.** The reverted codeset built to an
`GALE01r2.ini` byte-identical to the last build before the probe
(`cdcbc7ae...`), which is proof the menu is back, not a hope.

## What the major version still gets wrong

Spectating works: the replay plays, accurate, a couple of seconds behind. Room
creation and a real match both survive the change. What is still broken is the
room's own screen on the way back - it arrives black.

### The move

A watcher used to leave for the DebugMelee major and come back. Leaving reset
the heaps, and the room's load then called `SceneLoad_ClassicModeSplash`, which
reaches `Load_TyDatai_usd` - a disc read, and a disc read only makes progress on
frames the scene machinery runs, which are not running during a load. So it died
where it stood: `room scene load` logged, `room scene built` never. Black room,
or a crash into the part of the module that had not run.

⚠️ That trap is general: **never call another scene's load inline if it might
have to fetch anything.** The same file already recorded it for the character
select's portraits; the splash was believed exempt because "it loads nothing",
which is true only while the data is still resident.

So watching is a minor of the ONLINE major now, the way training already was.
The numbers were read out of DebugMelee's own table rather than guessed - a
one-shot dump from `peppy_room_load`, since they are in RAM and not in
MxScn.dat:

    minor 1  common 2  heaps 2  prep 801b13b8  data 80480530 / 80479d98
    minor 3  common 7  heaps 2  prep 801b16a8  data 8047c020 / 0

**Common 2 is the same scene an online match is.** One think serves both, which
is exactly why the playback codes need a scene guard at all. They went in as
minors 10 (the match) and 11 (the waiting screen), BEFORE the `0xFE` catch-all,
because the lookup walks upwards and would never reach them after it.

`SCENE_PLAYBACK_IN_GAME` moved `0x010E` -> `0x0A08`. Almost every guard is
written against that name in `Common.s`, so one edit moves them all; the two
that are not - `SceneThink_Playback`'s own check and the room's handover - must
move in the same commit. Splitting them is how a playback hook ends up firing
during a real match.

### Then: the room must only PEEK at the replay

`0xCA` asks whether a replay is waiting. `0x88` asks and CONSUMES it. The room
did both, because changing major loses a pending minor so the replay had to be
loaded before leaving. It does not change major any more, so the waiting screen
arrives intact and loads the replay itself - and the room taking it first left a
spectator on "Waiting for game" forever, unable even to close Dolphin, because
that screen's think is a loop with no exit but a replay.

### ⛔ STILL OPEN: the room does not draw when re-entered from the waiting screen

    25:39  room scene load / room scene built     from the CSS (minor 00) - fine
    26:39  room scene prep                        from the waiting screen (minor 0b)
    26:39  Writing file contents: PeppyRoom.dat -> 20200
    26:39  scene: major 08 minor 06 prev-minor 0b
           ... and no "room scene load" at all

The module IS fully transferred both times. The difference is which loader did
it: the working path logs `Peppy: replacing a file, 20200 bytes` from
`TransferFile.asm`, and the return does not, though Dolphin still writes the
contents. So something other than that injection served it, and whatever binds
the module's think/load/leave did not happen.

Next thing to find: which path serves the file on that transition, and why it
leaves the scene's functions unbound. `GetFileSize.asm` (0x800163fc) and
`TransferFile.asm` (0x800166b8) are the two known injections; there may be a
third route through `File_Load` (0x80016BE0).

### Also true after this session

* ⛔ Coming Soon does NOT work as the room's camera, even with the text's own
  GXLink added to the camera it provides: "lit 1 camera(s) for textlink 0" and a
  black room on a plain entry. Under the splash the text lands on link 14, so
  that scene puts it somewhere else entirely. Do not retry the link.
* Bravo's `SIDevice0` is 6, left over from driving Dolphin by script. It should
  be 12. A GameCube adapter can only be claimed by one instance at a time, so
  two installs set to 12 will fight over it.
