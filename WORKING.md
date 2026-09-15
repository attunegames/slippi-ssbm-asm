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
