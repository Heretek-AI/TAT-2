# Phase 3 played-route attempt — first-class Cleanout, continuous driver (BLOCKED, partial)

**Status:** **blocked** (documented partial). `route_claim=none`. **11 of 27 beats
captured** by one continuous input driver — 6 `driven`, 5 `driven_partial` — with
3 measured blockers, 4 measured-unreachable NPC beats and 9 not attempted.
**Row tokens emitted: 0.** Headless only (no Xvfb, no Vulkan, no screenshot);
one Godot at a time under the shared flock. Measured on **`1f3a50d`**
(`900f8eb` + this lane's driver/scorer commit) with `git.dirty=false`; the
manifest excludes the driver's own evidence paths from the source-dirty signal.

**Why this is not a played route.** `route_claim="played"` requires all 27 beats
fully driven; this run stops at 11 captured. The driver never teleports, never
`instantiate()`s a mission scene, and never calls a state hook to fake a
transition — the two scene changes are the game's own `change_scene_to_file`
(main-menu PLAY) and `reload_current_scene` (prep READY). A staged capture and a
short driver segment are not relabelled.

---

## 1. Acceptance evidence

### 1.1 First-class Cleanout (criterion 1) — PASS

Booted from the real startscreen: `main_menu.tscn` → PLAY (real `ui_accept`) →
Den (contract 1) → map table `[F]` → `[C]` (the table's own Cleanout key) →
prep `[F] READY` (6 s countdown) → the game's deploy closure reloads
`mission.tscn` on contract 2 with the Cleanout staged.

| Field | Measured |
|---|---|
| `GameState.active_mission_id` | `Mission.Guildhall.LootTheRoom` |
| `free_play` / `cleanout_run` | `false` / `true` |
| `GameState.run_time_limit` | `3300.0` s |
| mission row | `_active_mission_row.id = Mission.Guildhall.LootTheRoom`, title **Cleanout Heist** |
| run-clock source | `main_source=mission_row` (`GameData.get_mission_duration` = 3300 s = the run limit) |
| engine line | `TAT-2 run clock: map=guildhall mission=Mission.Guildhall.LootTheRoom main_s=3300.0 main_source=mission_row endgame_s=1200.0 endgame_source=project_settings` |
| prep screen | `Cleanout Heist`; `Time Limit: 55 minutes`; `Contract Inactive` |
| HUD clock | `54:50` = the live MM:SS countdown of 3290.6 s remaining (55:00 at the first main frame; the deploy spent ~9 s loading) |
| spawn | authored `TATSafeRoomPlayerStart_0` at XZ `(127.2747, -5.3296)` |

The wrapper fails closed on the engine line (`ROUTE_DRIVER_CLOCK PASS
main_source=mission_row main_s=3300`).

### 1.2 Beat status (27 rows, one process)

| Beat | Status | Evidence |
|---|---|---|
| S01 | `driven` | real `main_menu.tscn` startscreen built with 5 authored buttons + focus ring; marked at boot (the official beat is an idle startscreen — no input exists to give) |
| S02 | `driven` | the Den deploy's own loading overlay (`_bar` sampled at 50 %) |
| S03 | `driven_partial` | authored Den spawn `(5.6692, 42.1592, 270.6863)`; the official attic pan is not driven |
| S04 | `driven_partial` | walked 9.94 m to `DenWardrobeArea`, `[F]` opened the real `wardrobe_ui.gd`; KF03 cap / KF04 slot-3 states not cycled |
| S05 | `driven` | walked to the authored telescope `(-4.9202, 270.7337)`, `[F] PONDER` (ponder cam current), held forward drift `0.0093 m`, `[F] EXIT` restored the player camera |
| S06 | **blocked** | walked to `DenLedgerArea`, stopped at **1.9348 m** 3D vs the authored 1.75 m reach (desk stand-off) |
| S07 | `driven_partial` | `[F]` at the decoration pedestal (`faberge_egg`→`emerald`) **and** the gramophone (`is_gramophone_playing false→true`); boot-trail decals and the trunk cycle not driven |
| S08 | `driven_partial` | `[F]` opened the map table, table's `[C]` selected the first-class Cleanout; 3D table-token framing not adjudicated |
| S09 | `driven` | prep `[F] READY` started the authored 6 s countdown and deployed |
| S10 | `driven` | Guildhall deploy loading overlay (progress 33 %) |
| S11 | `driven` | briefing letter opened over the safe room; closed with the real polled pause/ESC action; body carries the 55-minute copy |
| S12 | **blocked** | lantern out of reach — see §2.1 |
| S13 | **blocked** | local safe-room area only — see §2.2 |
| S14–S18, S21, S24–S26 | `not_attempted` | state dependencies (zipwire/courtyard/terrace/beams/stairs); reasons in the manifest |
| S19, S20, S22, S23 | `unreachable` | 4 guards + 3 civilians measured **85.4–150.7 m** from the route anchor (`probe_route_npcs.gd`) |
| S27 | `driven_partial` | real pause action paused the tree; **wrong context** — the safe room after S12, not the official upper-foyer S26 |

Counts: `beats=27 driven=6 driven_partial=5 blocked=3 unreachable=4
not_attempted=9 failed=0 captured=11 mark_calls=11 checks=17 fails=0`.
`config=0`, `transform_writes=0`, `continuity.single_session=true`,
`scene_changes=2`.

### 1.3 Continuity

- One process, one driver, **one mission boot chain**: `PLAY` →
  `change_scene_to_file(main_menu → mission.tscn)` (contract 1, Den), then prep
  READY → `reload_current_scene()` (contract 2, Guildhall Cleanout). Both are the
  game's own closures (menu `_launch`, `contract_table_ui`'s `deploy_requested`
  handler); the driver never instantiates a mission scene.
- No teleport: the only placement is each scene's authored spawn; every leg is
  `Input.action_press("move_forward")` + the documented
  `player.add_look_pixel_delta` look hook; keys go through
  `Input.parse_input_event` (Input singleton state + viewport `_input` /
  `_unhandled_input` / GUI focus), and the polled pause key is
  `Input.action_press/release`.
- Deterministic: seed `1025051536`, `rng_state` recorded; repeated runs produced
  the same counts and positions to 0.0001 m.
- **Recorded incident (not a defect of this lane):** the wardrobe/ledger UIs
  close on ESC **without** stamping `FocusNav.mark_escape_consumed()`, so the
  HUD's polled pause also fires and pauses the tree on the same event (the
  documented AGENTS.md trap). The driver records `escape_woke_pause=true` and
  taps pause again to resume by input. Two occurrences: S04 and S06.

---

## 2. Measured blockers

### 2.1 S12 — safe-room spawn falls to a lower collision level; the lantern is 3.6 m away

The authored `TATSafeRoomPlayerStart_0` is at y **26.4694**, but the body has no
floor at the dressing level and settles on a lower collider:

```
TAT-2 player spawn: source=authored pos=(127.2747, 26.4694, -5.3296)
SAFE_FLOOR_DIAG player=(127.2747, 23.30033, -5.3296)
SAFE_FLOOR_DIAG floor_under_player=(127.2747, 23.1585, -5.3296) collider=LevelCollision_3_-1_0
SAFE_FLOOR_DIAG lantern=(126.89, 26.6, -2.285) interact_point=(126.89, 26.89, -2.285)
SAFE_FLOOR_DIAG player_to_lantern_3d=4.5061 to_point=4.7226
SAFE_FLOOR_DIAG floor_under_lantern=(126.89, 25.0, -2.285)
SAFE_FLOOR_DIAG dressing_anchor=(126.29, 25.0, -2.28)
```

- The safe-room dressing (`safe_room_dressing.gd`) is built at `WALL_ANCHOR.y =
  25.0`, the authored floor of the room; the lantern is **1.6 m above it**
  (y 26.6), correct for the blueprint.
- The player instead stands at y **23.1585** — **1.84 m below** the dressing
  floor, 3.64 m (3D) from the lantern and 3.92 m from its interact point. The
  authored reach is **1.75 m**, so no walking approach can toggle it. The
  straight-line approach stops after 1.72 m of travel at the ledge; the driver
  aborts the wall-climb (`vertical_climb_abort`) rather than let the body mantle
  out of the room.
- A floor-height grid (10×10 rays) shows the room floor at 23.11–23.16, 1.1–1.5 m
  ledges at 24.1–24.6, and the dressing floor at 25.0 for `z ≥ 0` — i.e. the
  spawn hole is in the room floor, not a path up to the dressing ledge.
- This also explains why the staged route2-clean S12 frame could show the lantern
  lit: the staged runner called `SafeRoomLanternStation.set_lit(true)` with the
  camera at the authored eye, not a walking body.

**This is a content/collision defect, not a driver gap.** The fix is a floor
collision at the authored spawn (or a corrected spawn/landscape mask); the
driver must not teleport the body upward.

### 2.2 S13 — street/alley not reachable from the safe room by the driver's route knowledge

Eight compass probes (150 physics frames each, climb-abort on) and a 60 m
follow leg:

```
moved_m (net after returning to the start) = 0.42
best single probe = 5.81 m (deg 270)
max probe displacement = 5.81 m
distance_to_kf16_car_m  = 128.669
distance_to_kf15_alley_m = 153.373
```

The body can move ~6 m inside the safe-room complex (y stays 23.1–24.3) but
never approaches the KF15 alley or KF16 car. The authored route's door/catwalk
chain is not in the driver's waypoint knowledge; adding it (or driving the
mission's own doors) is the next step. No teleport, no staged substitute.

### 2.3 S06 — ledger Area3D is on the desk, 0.89 m above the floor

`DenLedgerArea` sits at `(-2.0558, 41.0028, 267.3667)`; the player's feet are at
`40.1179`. The authored interaction test is a **3D** distance to the area node
(≤ 1.75 m), so the horizontal budget is only `sqrt(1.75² − 0.885²) = 1.51 m`.
The desk stand-off stops the walk at **1.9348 m 3D** = 1.71 m horizontal,
**0.18 m outside** the reach. The table's own points sit above their surfaces
(0.35 m for the map table), but the ledger's authored `interaction_point` is
+0.7 m while the *distance test* still uses the node origin. This is a measured
0.18 m shortfall, not an input failure: the same walk reached the wardrobe
(1.24 m) and the map table (1.66 m).

### 2.4 NPC beats — unreachable, measured

`probe_route_npcs.gd` at this HEAD: 4 guards + 3 civilians, nearest **85.4 m**,
max 150.7 m. S19/S20/S22/S23 keep `unreachable` status in the manifest and in
the scorer's `npc_measurement`.

---

## 3. 120-row coverage (no tokens)

`python3 build/qa/p0b_route_stats.py --manifest
docs/reports/logs/p0b-route-driver/cleanout_route/manifest.json`:

```
P0B_ROUTE_STATS rows=120 beats=27 rows_with_beats=120 tokens_emitted=0 route_claim=none
P0B_ROUTE_STATS npc_measurement guards=4 civilians=3 nearest_m=85.4 unreachable=S19,S20,S22,S23
P0B_ROUTE_STATS coverage driven=26 partial=19 blocked=23 unreachable=19 not_attempted=33 absent=0 rows_covered=45
P0B_ROUTE_STATS coverage_by_pillar visual=18/37 audio=10/31 hud_ui=11/27 gameplay=6/25
P0B_ROUTE_STATS token_policy route_claim is not 'played' ... no row token may be emitted
```

- **45/120** rows have at least one bound beat captured (26 fully, 19 partially);
  **35** excluding audio. 23 rows inherit a measured blocker, 19 the NPC
  unreachable reason, 33 are not attempted.
- **0 tokens emitted.** The scorer's gate requires `route_claim=played`, and even
  then refuses to invent tokens without per-row machine scores. No `PASS` /
  `DELTA` / `MISSING` / `HARD_LIMIT` / `N/A-route` token changed.
- **Audio:** headless uses the Dummy driver, so `audio.enabled=false`; every AU
  row's coverage is frame-coverage only (`capture_note` per row) and is never an
  audio measurement.
- Coverage is *beat presence*, not a row verdict: e.g. `V7-02` is "covered" by
  S05's presence, but its cut timing is not measurable from a still run.

---

## 4. What changed (files)

| File | Change |
|---|---|
| `build/qa/route_driver.gd` | new `cleanout_route` segment: menu PLAY → Den (S02/S03) → wardrobe (S04) → telescope (S05) → ledger attempt (S06) → props (S07) → map table + `[C]` Cleanout (S08) → prep READY (S09) → Guildhall loading (S10) → letter (S11) → lantern attempt (S12) → street attempt (S13) → pause (S27). Schema `tat2.route_driver/2` adds `blockers[]`, `scene_changes[]`, `continuity`, `level` (mission row/clock/spawn) and `prep` (copy). `den_telescope` kept. `route_claim` is computed: `played` only if all 27 are `driven`; otherwise `none`. |
| `build/qa/route_driver.sh` | `--segment=` (default `den_telescope`); tees `driver.log`; fails closed (`exit 3`) when the Cleanout run's log lacks `TAT-2 run clock: map=guildhall ... main_source=mission_row`. |
| `build/qa/p0b_route_stats.py` | schema `tat2.route_row_map/2`: per-row `capture_status` from the driver's 27 beats, `row_coverage` tally, `rows_covered`, non-audio count, `audio_capture`; 22 self-test checks (was 15). Tokens still gated on a played run + machine scores. |
| `docs/reports/logs/p0b-route-driver/cleanout_route/{manifest.json,driver.log}` | this run's evidence (tracked). |
| `docs/reports/logs/p0b-route-driver/den_telescope/{manifest.json,driver.log}` | re-run regression of the Phase 3C segment (`checks=12 fails=0`, S03 partial + S05 driven). |

No `game/` source was changed.

---

## 5. Reproduce

```bash
# one Godot at a time; the wrapper owns /tmp/opencode/tat2-godot.lock
build/qa/route_driver.sh --segment=cleanout_route --tag=cleanout_route
# -> ROUTE_DRIVER_DONE status=blocked_partial ... driven=6 partial=5 blocked=3
#    unreachable=4 not_attempted=9 captured=11 fails=0 route_claim=none
# -> ROUTE_DRIVER_CLOCK PASS main_source=mission_row main_s=3300

build/qa/route_driver.sh --segment=den_telescope --tag=den_telescope   # regression

python3 build/qa/p0b_route_stats.py --self-test                        # 22/22
python3 build/qa/p0b_route_stats.py \
  --manifest docs/reports/logs/p0b-route-driver/cleanout_route/manifest.json
```

---

## 6. What the next lane owes

1. Fix the safe-room spawn floor (`TATSafeRoomPlayerStart_0` y 26.4694 vs the
   collider at 23.1585; dressing floor 25.0) or record it as an accepted port
   decision. Until then S12 and S13 cannot be played, and no played claim is
   possible.
2. `S06`: resolve the 0.18 m ledger stand-off (move the Area3D's interaction
   test to its authored point, or the node itself) and re-run.
3. Drive S13–S26: the mission's own doors/catwalk waypoints (the driver currently
   knows only the safe room), the zipwire/crank chain, and the foyer beams.
   S19/S20/S22/S23 require an NPC actually in reach, not a moved one.
4. Only when a run is 27/27 `driven` may `route_claim=played` be set; then supply
   explicit per-row machine scores to the scorer so it can emit tokens.
5. The wardrobe/ledger ESC-does-not-stamp trap (S04/S06) is still open in
   `game/`; the driver works around it by input.
