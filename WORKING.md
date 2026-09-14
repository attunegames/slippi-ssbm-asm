# Known-good states

Peppy is two repositories that only work as a matched pair - the codeset
(`slippi-ssbm-asm`) and the fork (`peppy-dolphin`). A commit from one is
meaningless without the one from the other, so every entry here records both.

**Add an entry the moment a feature is CONFIRMED working by a human**, not when
it compiles and not when it looks right in a log. Tag both repositories at the
same time:

    git tag works/<feature> <sha> && git push origin works/<feature>

To get a known-good state back, build both tagged commits and put them in their
own folder under `Desktop\` - never over the live test installs. CI artifacts
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
