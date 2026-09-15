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
* The watch target's port is assumed to be the default 51441 - the backend does
  not send a `spectate_port`.

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
