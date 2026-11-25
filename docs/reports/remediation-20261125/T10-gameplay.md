# T10-GAMEPLAY — remediation report

Team: **T10-GAMEPLAY** (missions / loot / devices / doors / clock).
Worktree: `/home/john/Projects/TAT-2-rem-T10-gameplay`, branch `rem/T10-gameplay`,
base **`38e7b03`**, commit **`ae47adb`** (one coherent commit; this report file is
deliberately untracked — `build/qa/*` is ignored, the integrator reads it here).
Local commits only; **no push, no merge, no rebase**.
Inputs: `REMEDIATION_PLAN.md`, `ADJUDICATIONS.md` (binding), C4, RE-K, RE-J, L4.

Ownership actually exercised (all inside the T10 grant):

| file | use |
|---|---|
| `game/src/missions/mission_controller.gd` | objective spawn side, endgame summoner, run clock resolution, door spawn locks — **not** co-op/payout/reset/phase/extraction (T02-STATE untouched) |
| `game/src/interact/**` | `escape_gate`, `loot_item`, `loot_inventory`, `loot_container`, `swinging_door`, `lockable_door` |
| `game/src/stealth/**` | read only (`noise_bus` unchanged) |
| `game/src/devices/pressure_plate.gd`, `security_turret.gd` | **unassigned in the programme table**; the brief assigns RE-K-11/12 to T10, so these two files are claimed here. No other team owns them. |
| `game/src/player/thief_character.gd` | input/locomotion sections only (`_try_interact` + hold state, speed/climb multipliers). T04 owns the animation/montage sections; none touched. |
| `game/tests/**` | suite 91 (new), suite 53 comments, W7E S5.1/S5.11, E2E T2-15-A |

Binding constraints honoured: the `[0/1]` counter, the 1200 s endgame for
LootTheRoom (KF13) and the 3300 s free-play main window are **unchanged**; the
visible checker, `[0/1]`, endgame-1200, 1/1/1 and the granite floor are not
argued with anywhere below.

---

## C4-14 — the `objectives` group has no producer (P1). FIXED

- **severity:** P1
- **S1 investigate:** `hud.gd:2775-2777` (compass PoI) and `hud.gd:3157-3160`
  (TAB map) read `get_nodes_in_group("objectives")`; `grep -rn
  'add_to_group("objectives")' game/` returned **no hits**, so both loops always
  iterated an empty set. `game/src/interact/loot_item.gd:128-137` joined only
  `interactables`, `loot`, `xray_target`, `thief_vision_highlight`.
- **S2 research:** the marker must be the contract objective actor itself. The
  spawned quest item is the only world node that represents the objective
  (`mission_controller._spawn_quest_loot_at` builds it from
  `DT_LootInfo_Quest` + `BP_QuestSpawner_Item_C`); the HUD positions a gold PoI
  from any visible `Node3D` in the group. `objectives` is also the group the
  pickup must leave, so `loot_inventory.PICKUP_GROUPS` is its lifecycle home.
- **S3 confirm (red):** with the fix reverted, suite 91 on `38e7b03`+
  reverted sources:
  `FAIL: 91 T10 gameplay remediation: ["91.1a a contract quest item does not join the objectives group", ...]`
  (`/tmp/opencode/t10-red-suite91.log`, `SUMMARY: fails=1`).
- **S4 fix:** `loot_item._ready()` joins `objectives` when `is_quest_item` and
  not a personal-chain item; `loot_inventory.PICKUP_GROUPS` gains `"objectives"`,
  so the marker leaves the compass/map the frame the item is taken (the actor
  still lingers for the authored 1 s beat).
- **S5 test:** suite 91 `91.1a-91.1e` (`game/tests/test_t10_gameplay.gd`):
  quest item in group; ordinary major **not**; taken item gone from the group;
  lingering pickup out of `loot`. Registered as `run_tests.gd` suite 91.
- **S6 confirm:** `PASS: 91 T10 gameplay (...)` and `SUMMARY: fails=0`;
  compile 121/0; E2E full green (see gate table).
- **verdict:** FIXED

## C4-03 / RE-K-23 — one-shot 240 s portals inside a 1200 s endgame (P1). FIXED

- **severity:** P1
- **S1 investigate:** `escape_gate.activate()` refused when `expired`
  (`escape_gate.gd:97-99`) and `expire()` was a one-way latch (`:114-126`);
  `_start_endgame` activated every marker exactly once
  (`mission_controller.gd:4310-4321`) and `_start_endgame` is idempotent, so
  from endgame t=240 s to t=1200 s `is_available()` was false for every door
  and there was **no** re-arm path (`grep -n "activate(" game/src` → only the
  one summon site).
- **S2 research:** `BP_EscapePoint._escapeOpenDuration = 240`,
  `_canBeUsedMultipleTimes = true` (`interactables.json escape`, a 1:1 parse).
  The endgame window is 1200 s for LootTheRoom (KF13, adjudication F1b C-2 —
  unchanged). The two numbers are both authored, so the 240 s must be an open
  **cycle**, not the endgame lifetime; the terminal state is the endgame window
  closing (`MAGIC DOOR COLLAPSED`).
- **S3 confirm (red):** reverted tree, `test_w7e_endgame.gd`:
  `FAIL: S5.1c ...`, and S5.11c aborts with
  `SCRIPT ERROR: Invalid call. Nonexistent 'int' constructor` because
  `rearm_count`/`collapse()` do not exist
  (`/tmp/opencode/t10-red-w7e.log`). Behaviourally: at endgame t=240 s every
  marker `expire()`s and `activate()` refuses forever.
- **S4 fix:** `escape_gate` gains `collapse()` (terminal) and a re-armable
  `expire()`; `activate()` clears `expired` and counts `rearm_count`, refuses
  only when `collapsed`; `is_available()` also requires `not collapsed`.
  `mission_controller._rearm_escape_gates()` runs in the endgame tick (after the
  elapsed bump, before nothing else) and re-activates every closed marker while
  the window is live, keeping `GameState.escape_markers[*].expired` in sync (so
  `active_escape_count()` agrees). `_on_door_collapsed()` now calls
  `collapse()` (fallback `expire()` for old nodes).
- **S5 test:** W7E `S5.11a-e`: summon; 240 s cycle closes; live endgame re-arms
  (`rearm_count == 1`); extraction at endgame t=1001 s still fires; collapse is
  terminal (`activate()` → false, `is_available()` → false, no extraction).
  The existing dormant-rule checks `S5.6a` (never-activated door cannot extract)
  and `S5.6c` (main phase cannot extract) are untouched and still pass, and
  `S5.7a-c` still assert the authored 240 s single-cycle expiry.
- **S6 confirm:** `W7E_SUMMARY: fails=0`; log line
  `TAT-2 endgame: re-armed 1/1 escape markers (authored 240 s open cycle, endgame remaining_s=1199.0)`.
- **verdict:** FIXED

## C4-07 — the bag is enforced but invisible; refusal rides the clue toast (P1). FIXED (producer half) / T05 widget pending

- **severity:** P1
- **S1 investigate:** `GameState.carried_loot_changed(used, max, value)` was
  emitted by `notify_carried_loot_changed()` and subscribed by **nobody**
  (`grep -rn "carried_loot_changed" game/src` → `game_state.gd`,
  `loot_inventory.gd:224`, `loot_stash.gd:131` only). The refusal path
  `show_inventory_full → hud.show_toast → show_clue_toast("NOTICE", …)`
  (`loot_inventory.gd:187-192`, `hud.gd:1928-1929`).
- **S2 research:** capacity is enforced at 12 slots (`BP_TATPlayerState`), and
  `ST_Interactables.ErrorInventoryFull` is the authored refusal line. There is
  no authored capacity widget, so the contract (not the widget) is the fix here;
  `hud.gd` is T05's file.
- **S3 confirm (red):** reverted tree, suite 91:
  `91.2b the accepted pickup published no used/max capacity state ([])`,
  `91.2d the refusal did not use the dedicated capacity channel (clue toasts=["INVENTORY FULL"])`,
  `91.2e the capacity refusal still rode the CLUE toast`.
- **S4 fix (consumer, mine):** `loot_inventory` adds `capacity_snapshot()`,
  `broadcast_capacity(actor)` and calls it on every accepted pickup and every
  refusal; refusals prefer `hud.show_inventory_full_toast(text)` and fall back
  to the legacy toast only when the HUD has no dedicated channel. **T05
  contract (defined, not implemented here — hud.gd is T05's):**
  - `hud.show_loot_capacity(used_slots: int, max_slots: int, full: bool)` —
    called on every pickup/refusal; draw `used/max` beside the `(£)` counter.
  - `hud.show_inventory_full_toast(text: String)` — dedicated refusal cue;
    while absent the refusal still uses `show_toast`.
- **S5 test:** suite 91 `91.2a-g` with a `MockHud` that records both channels:
  one accepted pickup publishes 1/12; a refused 13th slot cost calls only
  `show_inventory_full_toast`; no clue toast; the full state is published;
  `capacity_snapshot()` == the enforced state.
- **S6 confirm:** `PASS: 91 ...` / `SUMMARY: fails=0`.
- **verdict:** FIXED (capacity signal + contract); the widget itself is
  **T05-OWNED**. No `BLOCKED-ON` because the brief only requires the contract.

## C4-04 / RE-K-07 / RE-K-17 / C4-05 — invented lock levels + doubled title (P1). FIXED

- **severity:** P1
- **S1 investigate:** `mission_controller._spawn_swinging_doors:3973-3988`
  locked doors from `3 + (count % 2)` and `count % 12 == 5` after a
  leaf-mesh **filename** token search (`prison|vault|cell|security|safe`);
  `loot_container.configure:186-193` used `2 + index % 2` / `1 + index % 3`.
  `swinging_door.gd:431`, `loot_container._container_label()`,
  `lockable_door.gd:273` all passed a label that already contained `(Lv n)`
  while `hud.start_lockpick_minigame` appends `" — LV %d"`.
- **S2 research (data):** loaded Guildhall `swinging_doors` records carry
  `name/actor/class/pos/basis/leaves/source` and **0** of them author
  `locked`/`lock_level` (suite 91.3a re-proves 0 on disk). `BP_SwingingDoor`
  authors only `_lockConfig.MaxLockLevel 4` (= `interactables.json
  doors.max_lock_level`, the clamp). Container BPs author `MaxLockLevel 3` (a
  cap) and `BP_SmallSafe_MajorLoot` serialises `_locked = false`; the level
  records author no lock. The authored expansion `Locks.Doors` scene variant
  (`dd["scene_locked"]`) is the only lock source.
- **S3 confirm (red):** reverted tree, suite 91:
  `91.3b the invented lock heuristics still fire (spawned=6 locked=5, want 6/0)`,
  `91.3d the container lockpick title still embeds its own level ('Display Safe (Lv 2)')`,
  `91.3e a major container was locked without an authored lock`,
  plus `91.4c BP_SmallSafe_MajorLoot_C was locked without authored data`.
- **S4 fix:** delete both index/name formulas. Doors lock only from
  `scene_locked` (level 3 — the authored variant records carry no level; 3 is
  inside the authored 4 cap and is labelled as the port default) or an authored
  `locked`/`lock_level` record (still handled by `swinging_door.configure`).
  Containers lock only from an authored `locked`/`lock_level` record. Caller
  labels are now `"Door Lock"` / `"Display Safe"` / `"Locked Chest"` /
  `"Safe Lock"` so the HUD suffix yields `DOOR LOCK — LV 3` once.
  Door spawn log now reports `locked=N`.
- **S5 test:** 91.3a (data: 0 authored locks), 91.3b (a synthetic `vault`
  leaf at count 5 stays unlocked), 91.3c (an authored `locked/lock_level 2`
  record is honoured), 91.3d (no level in the label), 91.3e. Suite 53g keeps
  the lockpick path covered by setting an authored level-3 lock explicitly;
  its stale `count%12` comments are corrected (no assertion changed).
- **S6 confirm:** `PASS: 91 ...`; suite 53 `PASS: 53 doors traversal` still
  green; E2E T2-15-C (0/99 clamp) still green.
- **verdict:** FIXED

## RE-K-06 — 16 authored container markers dropped by a 5-class allowlist (P1). PARTIAL — consumer FIXED, producer/loader BLOCKED

- **severity:** P1
- **S1 investigate:** `game/src/core/level_loader.gd:326-332`
  `LOOT_CONTAINER_CLASSES` (5 classes) gates `_parse_sublevel_file`; the marker
  never reaches `stats["loot_containers"]`, so `mission_controller
  ._spawn_loot_containers` never sees it. `tools/parse_containers.py:31-37`
  hard-codes the same 5, so `containers.json.classes` has 5 entries.
- **S2 research (counted on the loaded sublevel set of
  `_map_id_to_sublevels("guildhall", 2)`; script in Open risks):**

  | class | markers | allowlist | authored bucket(s) |
  |---|---:|---|---|
  | `BP_ChestTrunk_MajorLoot_C` | 48 | kept | Major (+Minor slot) |
  | `BP_DisplayCaseA_MajorLoot_C` | 31 | kept | Major |
  | `BP_LootStashInteractable_Secret_ThinWall_C` | 24 | kept | stash |
  | `BP_Storefront_DisplayCaseB_MinorLoot_C` | 2 | kept | Minor |
  | `BP_Storefront_DisplayCaseD_MinorLoot_C` | 2 | kept | Minor |
  | **spawned total** | **107** | | |
  | `BP_SmallSafe_MajorLoot_C` | 8 | **dropped** | Major + Minor |
  | `BP_Manor_Bookcase_Cabinet_MinorLoot_C` | 8 | **dropped** | Minor |
  | `BP_Manor_Bookcase_Cabinet_MajorLoot_C` | 2 | **dropped** | Major + Minor |
  | `BP_UtilityBoxA_MinorLoot_C` | 1 | **dropped** | Minor |
  | **dropped total** | **19** | | |

  All four dropped classes carry `TATContainerSpawnerComponent` and an authored
  `DA_SpawnBucket_*` (verified in `extracted/json/...`). 16 of the 19 are the two
  classes the brief names; the other 3 are the remaining authored container BPs
  present in the loaded sublevels. `counts`: before = **107 spawned / 19
  dropped**; after producer+loader land = **126 spawnable**.
- **S3 confirm (red):** reverted tree, suite 91:
  `91.4c BP_SmallSafe_MajorLoot_C was locked without authored data` (the marker
  the loader never emits cannot be opened, and the class resolved only through
  the old name fallback into an invented lock).
- **S4 fix (consumer half only):** `loot_container.configure()` now resolves an
  authored `*_MajorLoot_C` / `*_MinorLoot_C` class that is missing from
  `containers.json` to its authored per-tier bucket, logs one warning per class
  naming the producer gap, and never invents a lock or a slot offset (loot
  spawns at the marker). The 5 shipped rows are still read first.
- **S5 test:** 91.4a-c for the four dropped classes (tier + stash + unlocked)
  and 91.4d (the shipped 5 rows still load).
- **S6 confirm:** consumer green. Spawning is **not** verified because the two
  upstream halves are out of my file grant:
  - **BLOCKED-ON T01** — `tools/parse_containers.py CLASSES` must emit
    `BP_SmallSafe_MajorLoot`, `BP_Manor_Bookcase_Cabinet_{Major,Minor}Loot`,
    `BP_UtilityBoxA_MinorLoot` (kind/bucket/slot entries from
    `TATContainerSpawnerComponent`), then the integrator regenerates
    `containers.json` (`make normalize`; only the integrator may).
  - **BLOCKED-ON T07/T09** — `level_loader.gd LOOT_CONTAINER_CLASSES` (in
    `_parse_sublevel_file`, a placement function) must include those four
    classes. One-line change, not mine to make.
- **verdict:** PARTIAL — consumer FIXED, producer **BLOCKED-ON T01**, loader
  **BLOCKED-ON T07/T09**

## RE-K-04 — large-carry relics have no movement penalty (P1). FIXED

- **severity:** P1
- **S1 investigate:** `is_large_carry` is plumbed (`loot_item.gd:17`,
  `loot_inventory.gd:215`, `loot_container.gd:380`, `mission_controller.gd:3869`)
  and read by **nothing** for behaviour; `grep -rn "MovementMaxSpeedMultiplier"`
  had no hits and `thief_character.gd:1298` applied only `speed_multiplier`.
- **S2 research:** `GE_CarryingLargeCarryLoot` sets
  `MovementMaxSpeedMultiplier` ×0.6 (Multiplicitive) and
  `GE_CarryingLargeCarryLoot_Climbing` ×0.3 on the 8 `IsLargeCarry` rows
  (RE-K-04). `DA_LootInfo`/`loot_settings.json` do not carry the multipliers yet
  (the GE assets are not parsed).
- **S3 confirm (red):** `grep -rn "carry_speed_multiplier\|carry_climb_multiplier" game/src/ | wc -l` → **0**
  on `38e7b03`; suite 91.5b/c fail on the reverted tree.
- **S4 fix:** `loot_inventory` constants `LARGE_CARRY_WALK_MULTIPLIER 0.6` /
  `LARGE_CARRY_CLIMB_MULTIPLIER 0.3` with `loot_settings.json` override keys
  (`large_carry_walk_multiplier` / `large_carry_climb_multiplier`) so a future
  T01 producer pass is drop-in; `carries_large_carry()`,
  `carry_speed_multiplier()`, `carry_climb_multiplier()`.
  `thief_character` multiplies the authoritative walk/crouch/sprint speed and
  the authored `WALL_CLIMB_SPEED` (2.5 m/s) by those, and `effective_speed()`
  (the QA seam) now includes the carry term.
- **S5 test:** 91.5a-f: empty bag 1.0; one large-carry entry → 0.6 / 0.3;
  `effective_speed(100)` = 60; non-large major → 1.0.
- **S6 confirm:** `PASS: 91 ...`; `make test` fails=0; M2 physics suite green.
- **verdict:** FIXED

## RE-K-05 — authored steal times (up to 4 s) unused, instant pickups (P1). FIXED

- **severity:** P1
- **S1 investigate:** `grep -rn "steal_time\|TimeTakenToSteal" game/src/` → **0**
  hits; `loot_item.interact()` carried immediately. `interactables.json` already
  has `steal_time_s` per row (minor 0.01-0.3, major 1.0/3.0/4.0, quest 1.0/3.0).
- **S2 research:** authored `DT_LootInfo_* TimeTakenToSteal`; the shipped
  interaction is a hold. The port's own renderer (`hud.gd`) already draws an
  `interact_hold_progress` arc for the 0.45 s takedown hold, so the authored
  duration is the only missing input.
- **S3 confirm (red):** the grep above (0 readers); 91.6d on the reverted tree
  has no `get_interact_hold_seconds`.
- **S4 fix:** `loot_item.authored_steal_time_s(tier, tag, label)` resolves a
  row by `loot_tag` (quest) or authored display name (bucket actors) and
  `get_interact_hold_seconds()` exposes it. `thief_character` gates the primary
  interact on it: press arms the same two-clock hold as the secondary action,
  release completes the interact only when the authored seconds elapsed **and**
  the target is still inside the 1.75 m authored reach; the reticle arc uses the
  authored duration instead of the fixed 0.45 s. `interact()` itself stays the
  instant apply, so scripted/QA callers keep the synchronous contract (suites 89
  and the E2E loot tier are unchanged).
- **S5 test:** 91.6a-e (Golden Throne 4.0 s, Cat Statue 1.0 s, Vistara Files
  quest row > 0, `get_interact_hold_seconds` = 4.0, unknown row = 0.0).
- **S6 confirm:** `PASS: 91 ...`; E2E s2 loot 12/12 unchanged.
- **verdict:** FIXED

## RE-K-11 — turrets never alarm; authored reset unused (P2). FIXED

- **severity:** P2
- **S1 investigate:** `security_turret.gd` used fire interval, swivel and
  projectile only; `grep -n "alarm\|reset_seconds"` → none. `alarm_delay_seconds_by_difficulty`
  (2.0/1.0/0.25) and `reset_seconds` (10.0) were extracted and unused.
- **S2 research:** `family_defaults.turret.alarm_delay_seconds_by_difficulty`,
  `_difficultyToSwivelSettingsMap[*].Value.SecondsUntilAlarmTriggers`,
  `reset_seconds 10.0` (`devices_runtime.json`). No turret-specific hearing row
  exists; the authored security-alarm stimulus is
  `AI.Stim.Hearing.SecurityDevice.Alarm.Triggered` (25 m Heavy) — used as the
  alarm, labelled as an inference.
- **S3 confirm (red):** grep above (no alarm code); no `turret_alarmed` signal
  on the base tree.
- **S4 fix:** `alarm_delay_s` from the authored difficulty list; detection
  accumulates `_alarm_hold` and raises the alarm once
  (`NoiseBus.emit_noise(..., ALARM_STIM_TAG)` + `turret_alarmed`);
  `reset_seconds` without a target resets the alarm streak. Firing cadence is
  unchanged.
- **S5 test:** no dedicated headless case (the turret needs a physics world and
  a player body); covered by `make test` (suite 52/device suites) staying green
  and by the alarm being a pure function of `alarm_delay_s` +
  `alarm_delay_seconds_by_difficulty`. **Not verified:** a live alarm run.
- **verdict:** FIXED (code); live behaviour **not verified**

## RE-K-12 — jaw traps are silent (P2). FIXED

- **severity:** P2
- **S1 investigate:** `pressure_plate.gd` fired damage + the action graph and
  never emitted a stimulus (`grep -rn "NoiseBus\|JawTrap" game/src/devices` →
  only `alarm_eye.gd`, `noise_alarm.gd`).
- **S2 research:** `family_defaults.pressure_plate.hearing_stim` =
  `AI.Stim.Hearing.Tool.JawTrapTrigger`, Heavy, 1000 cm, inner 50 / outer 150.
  `HearingData.resolve_port_tag` accepts an authored stim tag directly
  (`hearing_data.gd:314-323`), so no T11 file change is needed.
- **S3 confirm (red):** the grep (no emission).
- **S4 fix:** the plate parses `hearing_stim` and emits it through `NoiseBus`
  on `_fire()` (base loudness = the authored 10 m, the resolved authored row
  supplies the real ranges/severity for listeners).
- **S5 test:** `make test` device suites green; the emission is a one-line path
  with the authored tag (no headless assertion added — the plate needs a player
  body on the plate). **Not verified:** a live guard investigation.
- **verdict:** FIXED (code); live behaviour **not verified**

## C4-06 — authored 200 cm lockpick cancel has no reader; T2-15-A greps `"2.0"` (P2). FIXED

- **severity:** P2
- **S1 investigate:** `grep -rn "distance_before_cancel" game/` → only
  `e2e_tier2_boundaries.gd:863`; `hud._tick_lockpick` only advanced the cursor,
  and the pass condition was `hud_txt.find("2.0") >= 0` on a 3.4 k-line file
  (72 literal `2.0` occurrences in `hud.gd` — the check could never fail).
- **S2 research:** `interactables.json lockpick.distance_before_cancel = 200.0`
  cm (`GA_Lockpick`).
- **S3 confirm (red):** `grep -rn "distance_before_cancel" game/src/ | wc -l`
  → **0** on `38e7b03`; the old T2-15-A passed with no feature.
- **S4 fix:** `lockable_door.lockpick_cancel_distance_m()` (authored cm → m,
  fallback 200). `swinging_door` and `loot_container` gained
  `check_lockpick_distance()` and drive it from `_process` (containers enable
  processing only while a pick is live); past the radius the session ends as a
  failure through the HUD's completion callback (`cancel_lockpick()` when T05
  adds it, else the existing `_finish_lockpick(false)`), with the authored
  sparks + jam noise. The lockpick panel title duplication is fixed at the
  callers (see C4-05).
- **S5 test:** 91.7a-c (2.0 m resolves; 0.5 m does **not** cancel; 3.0 m cancels
  and clears the flag for both owners). E2E **T2-15-A rewritten behaviourally**:
  it builds the real `swinging_door` and `loot_container`, places a probe actor
  at 0.5 m then 3.0 m, and asserts the toggle — no source grep.
- **S6 confirm:** `PASS: [T2-15-A] Lockpick cancel distance 2.0 m (200.0 cm)
  cancels beyond the authored radius [near=true far=true]`; E2E tier2 110/110.
- **verdict:** FIXED

## C4-13 / F1b C-4 — slot-cost provenance (P3). DOCUMENTED, major=3 kept

- **severity:** P3
- **S1/S2:** the authored row cost is 1/1/1 (`SlotSizeOverride 1`,
  `UseSlotSizeOverride=false`); `DefaultGame.ini DefaultLootSlotSize` is 1/1/3
  but unread by every producer and unproven at any call site (RE-K-02). The
  adjudication keeps `major = 3` as a port decision.
- **S4 fix:** none in behaviour. `loot_inventory.gd` header now states the
  authored 1/1/1, that `major = 3` is the port decision, that `quest = 1` matches
  the authored row, and that `DefaultLootSlotSize` is not the provenance.
- **S5/S6:** suite 89's provenance checks still pass (`make test` fails=0).
- **verdict:** DOCUMENTED (code unchanged; doc correction below)

## RE-J-13 — contract timers positional, 5 of 16 contracts wrong (P2). FIXED

- **severity:** P2
- **S1 investigate:** `mission_prep_ui.gd:1171`
  `_selected_mission_idx = matching[abs(contract_order) % matching.size()]`
  publishes a default mission id; `_setup_mission_objectives` trusted it and
  `_apply_run_clock` preferred that mission row. For the 5 contracts whose
  `order % 3` lands on the Cleanout row (2, 5, 8, 11, 14) the deploy ran the
  side-mission window and endgame (3300/1200/1200 Guildhall, 4500/1800/1500
  OldManor) instead of the authored contract row.
- **S2 research:** `contracts.json mission_durations` is the parsed canonical
  per-map contract row (`tools/parse_contracts.py MISSIONS`:
  `Mission.Guildhall.VaultHeist`, `Mission.OldManor.Vault`, 7200/2700/1800), and
  `docs/reports/contract-flow.md §3` states the LootTheRoom rows are
  side-mission variants "intentionally NOT used" for contracts. A Cleanout row
  authors a loot-value objective; a contract deploy's objective is a single/set
  item, so the two are mutually exclusive by data shape.
- **S3 confirm (red):** reverted tree, W7E:
  `FAIL: S5.1c main=3300.0 endgame=1200.0 (want 7200 mission_row + 300)`.
- **S4 fix:** `_resolve_deploy_mission_row/_id` in `mission_controller`: a
  contract deploy (`not free_play`) whose selected row authors a `loot_amount`
  objective (the `mission_loot_goals` key or a plan node of that kind — the
  Guildhall-only generated key is not enough, OldManor's Cleanout row authors
  three such nodes) is replaced by the authored per-map contract row, for both
  the objective/title resolution and the run clock. Free play keeps the player's
  pick, so the 3300 s Cleanout window and the KF13 1200 s endgame are untouched.
- **S5 test:** W7E `S5.1c` (Guildhall contract → 7200 + 300) and `S5.1d`
  (OldManor contract → 7200 + 480); `S5.1a` now states `free_play = true`
  because it is the free-play row test (assertion unchanged: 3300 + KF13 1200).
  `S5.2c` likewise sets free play (it is the KF13 override test).
- **S6 confirm:** `W7E_SUMMARY: fails=0`; live log
  `TAT-2 mission row: contract deploy replaces side-mission row 'Mission.Guildhall.LootTheRoom' with the authored per-map contract row 'Mission.Guildhall.VaultHeist'`.
- **verdict:** FIXED (runtime half). The prep UI's positional **default** is
  still in T05's `mission_prep_ui.gd`; the runtime no longer trusts it for a
  contract, but a player-facing default that matches the authored row would be
  better (see Doc corrections).

---

## Team summary

| verdict | count | findings |
|---|---:|---|
| FIXED | 10 rows / 11 ids | C4-14, C4-03, C4-07 (signal+contract), C4-04 + C4-05 (one change), RE-K-04, RE-K-05, RE-K-11, RE-K-12, C4-06, RE-J-13 |
| DOCUMENTED | 1 | C4-13 (major=3 kept) |
| PARTIAL | 1 | RE-K-06 (consumer fixed; producer BLOCKED-ON T01, loader BLOCKED-ON T07/T09) |
| NOT REPRODUCED | 0 | — |
| DEFERRED | 0 | — |

### Gate table (this worktree, `rem/T10-gameplay`, base `38e7b03` + T10 commits)

| gate | command | result |
|---|---|---|
| compile | `tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"` | **121 checked, 0 broken** (was 120; +1 new test script) |
| unit suite | `… --script res://tests/run_tests.gd` | **SUMMARY: fails=0** (suites 1-91; suite 91 new) |
| W7E endgame | `… --script res://tests/test_w7e_endgame.gd` | **W7E_SUMMARY: fails=0** (+S5.1c, S5.1d, S5.11a-e) |
| M2 player | `… --script res://tests/test_m2_player.gd` | **M2_SUMMARY: fails=0** |
| E2E tier 2 | `… --script res://tests/e2e/run_e2e_tests.gd -- --tier=2` | **110/110**, T2-15-A behavioural PASS |
| E2E tier 1 | `… -- --tier=1` | **117/117** |
| E2E s2 | `… -- --tier=s2` | **12/12** |
| E2E full | `… --script res://tests/e2e/run_e2e_tests.gd` | **fails=0 passed=278 total=278** (W7 floor preserved; log `/tmp/opencode/t10-e2e-full.log`) |
| perf guard | `build/qa/test_perf_guard.sh` | **78/78** |
| gate ratchet | `make gate-ratchet` | **PASS** |
| audit | `make audit` | **all content groups OK; fails only on `tool version drift: vgmstream … -> missing`** (the decoder binary is not on this host's PATH; unrelated to T10, not worked around) |

No producer was run and no generated data was written: `extracted/`,
`game/assets` and `game/data/generated` stayed the read-only symlinks, and
`make normalize` / `--refresh-stamps` were not invoked (REMEDIATION_PLAN §1.3).
The only tracked-file change outside `game/src` + `game/tests` is none.

Red proofs are in `/tmp/opencode/t10-red-suite91.log`,
`/tmp/opencode/t10-red-w7e.log`; greens in `/tmp/opencode/t10-green*-*.log`,
`/tmp/opencode/t10-e2e-*.log`. These are transient `/tmp` paths (not committed);
the commands reproduce them.

## Doc corrections (integrator applies; teams must not edit these files)

1. **`docs/reports/w7e-endgame.md` S5.7** (“240 s per gate”) now reads as a
   *cycle*: the BP_EscapePoint 240 s open lifetime closes one cycle and the
   endgame summoner re-arms it while the 1200 s window is live; `collapse()` at
   the window end is terminal. The “1200 s window vs 240 s door” contradiction
   recorded in C4-03 is closed.
2. **`docs/FIDELITY_GAPS.md`** — add/label:
   - locks are **authored only** (no `count % 12`, no leaf-mesh filename token,
     no container spawn index). A scene-variant `Locks.Doors` lock uses level 3
     (port default inside the authored 4 cap). The killer consequence to state:
     **every major container is now unlocked unless a level/scene record authors
     it**, so the lockpick minigame is reachable through scene-variant locked
     doors (suite 53g) rather than chests.
   - large-carry movement penalty is now applied (×0.6 walk / ×0.3 climb,
     `GE_CarryingLargeCarryLoot[_Climbing]`), with the multipliers as
     `loot_settings.json`-overridable constants until T01 parses the GEs.
   - authored steal time is consumed (hold-to-steal up to 4 s; the player-side
     hold, the 1.75 m release reach and the reticle arc are the port surface).
   - authored lockpick cancel radius (200 cm) is enforced by the door/container
     owners, not the HUD.
   - turret alarm + 10 s reset and the plate JawTrapTrigger stimulus are wired;
     the turret alarm uses the authored security-alarm stim (no turret-specific
     hearing row exists) — an inference.
3. **`AGENTS.md` §Known traps “Loot capacity is authored, retention is
   binary”** — the exact sentence F1b C-4 already flags: keep 12 authored, say
   the **authored row cost is 1/1/1**, that **major = 3 is a port decision**
   (`loot_settings.json port_decisions.major_slot_cost`), that `quest 1` follows
   the authored row, and that `DefaultLootSlotSize` (1/1/3) is unread by any
   producer and unproven at any call site.
4. **`docs/reports/contract-flow.md` §3** is now true in code for contract
   deploys (the W7E clock change had contradicted it). Add one line: the
   resolver keys on “row authors a `loot_amount` objective”, and free play is
   the only mode that may run a Cleanout row.
5. **`docs/HANDOFF_NEXT_AGENT.md`** — open items below (producer/loader
   container halves, prep default, T05 capacity widget).
6. **`docs/reports/interactables-implementation.md`** — the lockpick dialog
   title is `DOOR LOCK — LV n` (one level, HUD-appended); the callers no longer
   embed it.
7. `README.md`: no user-facing command changed; no edit.

## Open risks

1. **RE-K-06 is only half fixed.** The consumer now resolves the four dropped
   authored container classes, but the 19 markers still do not spawn until
   **T01** emits their `containers.json` rows and **T07/T09** add them to
   `level_loader.LOOT_CONTAINER_CLASSES`. Do not read “container classes fixed”
   as “19 more chests in the map”.
2. **No container requires a pick any more.** That is what the data says
   (`_locked=false`, no level locks) and it deletes the invented difficulty, but
   it is a real gameplay change: a vault room is now a walk-in unless a scene
   variant locks the door. Playtest before accepting.
3. **The re-arm makes the magic door continuously available in the endgame.**
   The 240 s authored cycle is honoured only at the cycle boundary (a re-arm
   happens on the expiring tick, no dead gap). If the shipped design intends the
   portal to be *intermittent* (a 240 s window that can lapse), this is a
   divergence — but the adjudicated 1200 s window requires an exit, and a lapse
   was the C4-03 defect.
4. **The turret alarm tag is an inference.** No turret-specific hearing row is
   authored; `SecurityDevice.Alarm.Triggered` (25 m Heavy) is the security-device
   row. A live run with a guard near a firing turret is the verification.
5. **Steal hold is player-side.** `loot_item.interact()` stays instant so
   scripted callers (suite 89, E2E loot) do not break; only the
   `thief_character` input path charges the authored seconds. A HUD progress bar
   is not added (T05); the reticle arc reuses `interact_hold_progress`.
6. **My own suite-91 helper had a false-green shape and is fixed.**
   `await fn()` on a function that hits a runtime error returns `null`; a typed
   `Array[String]` assigned from it became empty and read as PASS. `run_tests.gd`
   now fails closed when the suite returns no list. Worth copying to any other
   `_run_suiteNN` helper that assigns `await` results into typed arrays.
7. **Two test expectations changed, both because the fixture, not the property,
   was wrong** (recorded here as required by REMEDIATION_PLAN §1.5):
   - W7E `S5.1a`/`S5.2c` now set `free_play = true` — they test the LootTheRoom
     free-play row (3300 + KF13 1200); a *contract* deploy on that row is the
     finding being fixed.
   - Suite 53's comments no longer claim a `count%12==5` auto-lock; the locked
     door in 53g is set explicitly at an authored level 3. No assertion changed.
8. **`make audit` is blocked on this host** by the missing `vgmstream` CLI
   (stamp gate), not by T10 content: every `content *` group and `engine-dep`
   line is OK. The integrator's host has the decoder.
9. Devices: `MaxAge 5.0` (turret target age) remains unimplemented — RE-K-11
   names it, the brief does not, and the alarm/reset half was the P2. Recorded
   as residual.
10. `_is_side_mission_row()` calls `GameData.get_mission_plan()` once per deploy
    (no caching concern measured); the mission-row log line makes the
    substitution visible in every run log.
11. **`--qa-mission=<cleanout>` without `--qa-free-play` now runs the contract
    row.** The QA autostart publishes the id on a contract deploy, so a capture
    or probe that asks for `Mission.Guildhall.LootTheRoom` with a contract order
    gets VaultHeist timing; add `--qa-free-play` to capture the Cleanout. No
    tracked capture script does this today (all cleanout captures use
    `begin_free_play`); recorded so the next lane does not mis-read a capture.
12. **Merge hotspots** (for the integrator, in pick order):
    - `mission_controller.gd` — the `_process` endgame branch gained the one
      `_rearm_escape_gates()` call. T02-STATE may also edit `_process`; keep both
      intents (phase tick + re-arm) if it conflicts.
    - `thief_character.gd` — the speed assignment in `_physics_process`
      (~line 1298) and the hold tick (~line 1430). T04-ANIM owns the
      animation/montage sections; if its hunks touch these blocks, keep the
      carry multiplier on the speed assignment and `_hold_required_sec` as the
      hold-tick denominator.
    - no `hud.gd`, `game_state.gd`, `save_system.gd` or `level_loader.gd` edits,
      so T05/T02/T07/T08/T09 cannot textually conflict with this commit.
