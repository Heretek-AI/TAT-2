# W7E — two-phase timer, 25 escape markers and endgame extraction

Branch: `w7e-endgame` (worker worktree `/tmp/opencode/tat2-w7e-s5`,
`XDG_DATA_HOME=/tmp/opencode/w7e-data`).

Commit: `feat(mission): two-phase timer, 25 escape markers and endgame extraction`.

## 1. What shipped

| Area | Before | W7E |
|---|---|---|
| Run clock | one map-window timer (`Guildhall` 7200 s) | **two phases**: main mission-row window, then endgame door window |
| Endgame | briefing/plan value only (W6U1), no runtime phase | objectives completion starts it; expiry collapses the doors |
| Escape markers | first authored `BP_EscapePoint` only | **all 25** authored markers (Guildhall 14, OldManor 10, FTUE 1) |
| Escape extraction | always available once objectives complete | **endgame phase + summoned, unexpired door** |
| Door lifetime | config value unused | `BP_EscapePoint` 240 s open lifetime, per gate |
| HUD | one `(MM:SS)` main timer | active-phase countdown + endgame door banner |
| Extraction banking | existing `_on_extracted` | untouched; host-once wrapper, free play still banks nothing |

## 2. Clock rules (measured from the shipped data)

`MissionController._apply_run_clock(map_id)` resolves the main window after
`_setup_mission_objectives()` has resolved `GameState.active_mission_id`:

1. If the active mission row exists **and its `map_id` matches the contract
   map**, use `GameData.get_mission_duration(id, difficulty)`
   (`main_source=mission_row`).
2. Otherwise fall back to the map row (`main_source=map_row`), preserving the
   pre-W7E legacy paths.

The endgame window is `GameData.get_mission_endgame_seconds(id)`: the tracked
KF13 override first, the authored quest-graph `EndgameDuration` node second.
`GameData.get_mission_plan()` is untouched, so suite 65 still sees the QG value
480 s.

Measured clock table (Novice):

| mission row | main | source | endgame | source |
|---|---|---|---|---|
| `Mission.Guildhall.LootTheRoom` (free play) | 3300 s (55:00) | mission_row | 1200 s (20:00) | KF13 override |
| `Mission.Guildhall.VaultHeist` / `.Set` | 7200 s | mission_row | 300 s / 480 s | quest_graph |
| `Mission.OldManor.LootTheRoom` | 4500 s | mission_row | 480 s | quest_graph |
| no active mission id (legacy) | 7200 s | map_row | 480 s | fallback |
| `Mission.Tutorial.Single` (FTUE) | 0 s (unlimited) | mission_row | 480 s | quest_graph |

Runtime log lines (real run, contract 2 + `LootTheRoom`):

```text
TAT-2 run clock: map=guildhall mission=Mission.Guildhall.LootTheRoom main_s=3300.0 main_source=mission_row endgame_s=1200.0 endgame_source=KF13
TAT-2 endgame: phase=endgame reason=suite window_s=1200.0 doors=14/14
TAT-2 escape markers: authored=14 spawned=14 grounded=14 connected=14 phase=main
```

## 3. Phase state (`game/src/core/game_state.gd`)

New fields, all reset by `reset_run()`:

- `phase`: `main` | `endgame` | `resolved`;
- `endgame_time_limit`, `endgame_elapsed`;
- `escape_markers` (one record per authored marker: `index`, `authored`,
  `position`, `grounded`, `connected`, `activated`, `expired`, `gate`);
- `extracted_players` (peer ids, host-once).

Helpers: `begin_endgame()`, `resolve_phase()`, `phase_time_limit()`,
`phase_elapsed()`, `phase_time_remaining()`, `total_elapsed()`,
`register_extracted_player()`, `set_escape_markers()`, `active_escape_count()`.
`phase_changed` is emitted for QA/future listeners. `elapsed_sec` still means
the **main** clock and `total_elapsed()` is main + endgame for logs.

## 4. Mission flow (`game/src/missions/mission_controller.gd`)

- `_process` ticks **only the active phase**. The main phase keeps the P1
  `LETTER_GRACE_SEC` hold; the endgame never gets it (starting the endgame
  forces `_letter_grace_sec = 0`).
- Objective completion (`GameState.objective_completed` signal plus a per-frame
  safety poll) calls `_start_endgame()`: phase -> endgame, every spawned door
  `activate()`d, door count logged.
- Main expiry keeps the existing `TIME EXPIRED` failure.
- Endgame expiry is a new `_on_door_collapsed()` failure with
  `timeout_reason = "MAGIC DOOR COLLAPSED"`; all doors `expire()`.
- `_on_extracted` (payout/loot/save) was **not edited**. A new
  `_on_escape_gate_extracted()` wrapper guards it:
  - endgame phase only;
  - expired doors ignored;
  - one extraction per peer (`GameState.extracted_players`);
  - local-only co-op: a client observes but does not bank (host RPC deferred).

## 5. Escape markers and gates

`_spawn_escape()` now loops every authored `BP_EscapePoint` instead of
`ue_escapes[0]`. Each marker is:

1. floor-raycast (`_ground_escape_position(raw, world)` returns
   `{position, grounded}`), keeping the authored position with a warning when
   no floor exists;
2. spawned as its own `EscapeGate` with a unique name and `marker_index`
   metadata;
3. connected to the host-once extraction handler;
4. recorded in `GameState.escape_markers` with its grounded/connected state.

Authored counts from the generated level JSON: Guildhall `Gameplay` 10 +
`P` 4 = **14**, OldManor `Gameplay` **10**, FTUE `Geometry` **1**, total
**25**.

`escape_gate.gd` gains `activated` / `active` / `expired`, `open_elapsed`,
`activate(duration)` / `expire()` / `is_available()` and
`gate_activated` / `gate_expired` signals. A marker is dormant (portal hidden)
during the main window, opens for the endgame and closes after the authored
240 s (`interactables.json` `escape.open_duration_s`). `_on_body_entered`
requires `GameState.state == "playing"`, `GameState.phase == "endgame"`,
objectives complete, and an available door.

Live Guildhall run evidence: 14 gates spawned, 14 grounded, 14 connected,
14 dormant at start; `_start_endgame` summons all 14.

## 6. HUD (`game/src/ui/hud.gd`)

- `phase_countdown_text()`: `55:00` in the main phase, `20:00` in the endgame,
  derived from `GameState` seconds (never a typed minute count).
- Objective strip suffix: `(55:00)` main, `(DOOR 20:00)` endgame.
- `door_warning_text()` + `DoorWarningLabel`: gold
  `THE MAGIC DOOR IS OPEN — 20:00 BEFORE IT COLLAPSES` banner, endgame only,
  hidden on the hub and after resolution.
- Free play keeps its authored inline objective row (`Mission: Steal 4,000 in
  loot value[0/4,000]`, `(£) 0`), so T4-13's HUD assertion is unchanged.
- The briefing paper (`MissionStartLetter`) is untouched.

## 7. Tests and gates

| gate | result |
|---|---|
| `tools/check_scripts_compile.gd` | **111 checked, 0 broken** (110 + the new S5 test) |
| `res://tests/test_w7e_endgame.gd` (S5.1–S5.10) | **W7E_SUMMARY: fails=0** (31 checks) |
| `make test` (`tests/run_tests.gd`) | **SUMMARY: fails=0** (263 PASS; suites to 88; suite 60 PASS) |
| `res://tests/test_m2_player.gd` | **M2_SUMMARY: fails=0** (11 PASS) |
| `res://probe_leak.gd` (`TAT2_NO_DEN_PROBE=1`) | exit 0 |
| `res://tests/probe_door_walk.gd` | `DOORWALK PASS` |
| `res://tests/probe_viewmodel_truth.gd` | `VIEWMODEL_TRUTH PASS` |
| `res://tests/probe_niagara.gd` | `NIAGARA_PROBE PASS` (3695 authored / 3308 active / 36 systems) |
| E2E tier 1 | **fails=0 passed=115 total=115** (T1-18-E now reports `escapes=14`) |
| E2E tier 2 | **fails=0 passed=110 total=110** (T2-18-A..E PASS, unchanged) |
| E2E tier 3 | **fails=0 passed=25 total=25** |
| E2E tier 4 | **fails=0 passed=14 total=14** (T4-13/T4-14 PASS, unchanged) |
| `make audit` | exit 2 — baseline mismatch only, see below; all 13 content groups OK |

S5 coverage (`game/tests/test_w7e_endgame.gd`):

- **S5.1** main clock 3300 from the LootTheRoom mission row; legacy no-mission
  path keeps 7200 map row.
- **S5.2** QG plan endgame stays 480; runtime accessor 1200/KF13; run clock
  applies 1200; VaultHeist 300 quest-graph.
- **S5.3** main -> endgame on objective completion; only the endgame ticks;
  repeated completion is idempotent.
- **S5.4** main expiry -> failed + `TIME EXPIRED`, phase resolved.
- **S5.5** endgame expiry -> failed + `MAGIC DOOR COLLAPSED`; letter grace is
  dropped and the endgame ticks immediately.
- **S5.6** dormant door cannot extract; activated endgame door extracts; the
  main phase cannot extract even from an activated door.
- **S5.7** authored 240 s lifetime: open at 239 s, expired and hidden at 240 s.
- **S5.8** authored counts 14 + 10 + 1 = 25; all 25 spawned / floor-grounded
  (+0.15 m) / connected; live Guildhall run spawns and summons its 14 doors;
  `run_time_limit` is 3300 in the live run.
- **S5.9** free-play extraction writes no contract and banks no currency.
- **S5.10** HUD `55:00` main / `20:00` endgame, door banner visible in the
  endgame, hidden on the hub, ticks to `19:00` at 60 s.

### Intentional existing-test update

`run_tests.gd` suite 60d created an `EscapeGate` and expected a bare
`_on_body_entered` to extract. That assertion encoded the pre-W7E
always-open contract; W7E deliberately makes extraction endgame+activation
gated. The suite now sets `phase = "endgame"` and calls `activate()` before the
body-entry check, then restores `phase = "main"`. The portal mesh/shader/trigger
assertions are unchanged. Evidence: `make test` suite 60 PASS.

E2E T2-18 and T4-13 needed **no** edits; both pass on the W7E tree because the
free-play timer remains 3300 and `_on_time_expired` keeps its existing API.

### Audit note

`make audit` exits 2 in this worktree, exactly as W6U1 documented: the shared
symlinked `game/data/generated` snapshot carries other waves' uncommitted
outputs (`parse_tables`, `parse_gameplay`, `parse_contracts`, `parse_loot`,
`parse_containers` baseline content mismatches) and `vgmstream` is missing from
the container. All content checks pass (levels, contracts 16, tables 144,
materials 1629, devices 4118, animations 995, audio 5018, localization 8,
niagara 3695). W7E changes no producer and no generated file.

## 8. Deferred / residual

- **Co-op replication is still local-only.** The host-once guard works for the
  local transport (one bank per peer id); a client extraction does not yet RPC
  the host to bank the run. That is the same transport boundary W6b documented
  for door events.
- **Den banking policy** is untouched: `_on_extracted` still banks every
  non-free-play extraction at `active_contract_order`. Whether a Den hub run or
  a free-play "Contract Inactive" run should ever bank is a design decision
  outside W7E; free play currently banks nothing by explicit `free_play` guard.
- Marker records hold a `gate` object reference for activation. `reset_run()`
  clears the array; the mission normally owns and frees the gate nodes. A test
  that frees gates without clearing the array would leave freed instances in
  `GameState` until the next reset (S5.8 clears explicitly).
- `GameState.elapsed_sec` remains main-phase time for compatibility (HUD/result
  screens, existing tests). Use `total_elapsed()` for whole-run reporting.
