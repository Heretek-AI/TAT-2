# Phase 3C played-route instruments (input driver, scorer, telescope, NPC precondition)

**Status:** instruments built and headless-verified. This is **not** a played
route: `route_claim` stays `none`, and no staged frame is relabelled played.
No GPU, Vulkan, Xvfb or Steam process was started. Measured on the Phase 3
worktree base `6773977` (headless Godot 4.7.2).

**Delivered**

| Item | File | Headless result |
|---|---|---|
| Continuous input driver (short segment) | `build/qa/route_driver.gd` + `build/qa/route_driver.sh` | `ROUTE_DRIVER_DONE status=partial_driven beats=27 driven=1 partial=1 unreachable=4 not_attempted=21 mark_calls=2 checks=12 fails=0 route_claim=none` |
| 27-beat → 120-row scorer | `build/qa/p0b_route_stats.py` | `P0B_ROUTE_STATS_SELFTEST PASS checks=15 fails=0 rows=120 beats=27`; report emits `tokens_emitted=0` |
| Telescope `[F] EXIT` (L4-13) | `game/src/missions/mission_controller.gd`, `game/tests/probe_den_window.gd` | `DEN_WINDOW PASS checks=44`; real-key `[F] PONDER`/`[F] EXIT`, scope drift `0.0000 m`, exit body inside the Den |
| Route NPC re-measure (C4-08/L4-08) | `game/tests/probe_route_npcs.gd` | `ROUTE_NPC PASS checks=4`; 4 guards + 3 civilians at **85.4–150.7 m** from the authored Contract 2 spawn |

## 1. Driver design (and the claim boundary)

`route_driver.gd` is a `SceneTree` headless driver:

- **Movement** is `Input.action_press("move_forward")` (and a deterministic
  left-strafe nudge after 40 stuck frames). The player's own `_physics_process`
  integrates it.
- **Look** is `player.add_look_pixel_delta(...)`, the documented touch-look
  input hook (`rotate_y(-delta_px.x * mouse_sens)`), stepped toward the
  waypoint yaw. No yaw/position write.
- **Interact** is an `InputEventKey` (`KEY_F`, pressed + released) pushed through
  `SceneTree.root.push_input`, so the player's `_unhandled_input` and the
  mission's `[F] EXIT` handler are exercised as real input.
- **Wait** is `await physics_frame` (fixed 60 Hz), which makes the replay
  bit-identical: two runs of the same seed produced identical evidence
  (`leg_to_telescope` 151 frames / 8.8401 m, `exit_pos` identical to 0.0001 m).
- **No teleport:** the driver never assigns `player.global_position`; the only
  placement is the mission's authored spawn. `transform_writes=0` is recorded
  in the manifest.
- `driver_seed` (`1025051536`, the official clip seed) is recorded, and
  `rng_state` is stored for replay provenance.
- Every captured beat calls the audio tap's `mark_beat()` (`S03`, `S05`) and
  the manifest records `mark_kind="mark_beat"`.

The only implemented segment is `den_telescope`:

1. **S03** — the player spawns at the authored Den spawn; the entry half is
   driven and marked `driven_partial` (the official attic pan is not driven).
2. Walk ~8.8 m west to the authored telescope `Area3D`
   `(-4.9202, floor, 270.7337)`; arrival 1.75 m from the centre (< 1.8 m radius).
3. **S05** — `[F] PONDER`, mark the scope, hold `move_forward` 40 frames
   (drift `0.0000 m`), `[F] EXIT`, assert the player camera is restored, the
   body did not move, and the body is still inside the Den (`x > -6.06`,
   `y < 45.1`). Then walk 4.89 m away to prove the body is not stranded.

The other 25 beats are listed in the manifest with an explicit status:

- `unreachable` — **S19, S20, S22, S23** (NPC scan / terrace patrol /
  pickpocket / takedown): measured nearest NPC **85.4 m**.
- `not_attempted` — the remaining UI and traversal beats with the specific
  missing plan (menu input, S13–S18 zipwire/courtyard chain, S21 blue doors,
  S24–S26 beams/stairs).

Counts: `beats=27 driven=1 driven_partial=1 unreachable=4 not_attempted=21
failed=0`.

## 2. Telescope `[F] EXIT` (L4-13) fix

Before this lane, `toggle_telescope_ponder()` only swapped the camera. The
character kept polling movement input while the scope was up, so a held forward
key walked the body into the framed west opening; `[F] EXIT` then returned the
camera to a body already outside on the Den roof.

Fix in `mission_controller.gd`:

- push an `InputContext` modal `telescope_ponder` with the movement/tool/jump/
  sprint/crouch/interact action set while the scope is active, pop it on exit
  (and in `_exit_tree`, so a quit while scoped cannot leave the gate behind);
- zero the body's horizontal velocity on scope entry, so residual walk/sprint
  momentum cannot carry the body 0.1–0.5 m into the opening before the modal
  deceleration settles.

`probe_den_window.gd` now includes a real-key block (44 checks total):

```
PASS: [den] [F] PONDER (real key) enters the telescope scope
PASS: [den] scope pushes the telescope_ponder gameplay modal
PASS: [den] scope modal blocks gameplay input
PASS: [den] held forward key cannot move the body while the scope is up (max drift 0.000 m)
PASS: [den] [F] EXIT (real key) leaves the telescope scope
PASS: [den] [F] EXIT restores the player camera
PASS: [den] [F] EXIT pops the telescope_ponder modal
PASS: [den] [F] EXIT restores gameplay input
PASS: [den] [F] EXIT never teleports the body (drift 0.000 m)
PASS: [den] [F] EXIT leaves the player inside the Den (pos=(-3.6, 40.11766, 271.4))
```

The existing west-window blocker checks and the pre-fix A/B walk stay in the
same probe. The blocker remains defense-in-depth (the authored
`SM_ThievesDen_Glass` collision already closes the opening on this HEAD).

## 3. NPC precondition re-measure

`probe_route_npcs.gd` boots the same Novice Contract 2 Guildhall spawn and reads
the live population; it moves nothing.

```
ROUTE_NPC guard id=Guard_1 pos=(49.225,45.053,-35.570) dist_anchor=86.5
ROUTE_NPC guard id=Guard_3 pos=(44.201,26.016,-25.066) dist_anchor=85.4
ROUTE_NPC guard id=Guard_ClubLantern_0 pos=(39.599,35.533,-13.880) dist_anchor=89.0
ROUTE_NPC guard id=Guard_ClubLantern_2 pos=(29.671,11.501,-31.444) dist_anchor=101.7
ROUTE_NPC civilian id=... pos=(44.042,26.002,-25.677) dist_anchor=85.7
ROUTE_NPC civilian id=... pos=(7.594,28.001,-43.309) dist_anchor=125.7
ROUTE_NPC civilian id=... pos=(-21.786,11.524,-23.991) dist_anchor=150.7
ROUTE_NPC count_matches guards=4 civilians=3 reported_guards=4 reported_civilians=3
ROUTE_NPC SUMMARY guards=4 civilians=3 nearest_m=85.4 in_range_30m=0 max_m=150.7
ROUTE_NPC PASS checks=4 fails=0 unreachable_beats=S19,S20,S22,S23
```

The old "nearest 48.1 m" is superseded at this HEAD; the count (4 + 3) matches
the report, but **none** are inside a 30 m engagement radius. S19/S20/S22/S23
are therefore `unreachable` in the driver manifest and in the scorer's
`npc_measurement`, not faked.

## 4. 27 → 120 scorer

`build/qa/p0b_route_stats.py` binds every matrix row to its official beat(s)
and validates against the tracked
`docs/reference/clip_1795033698901/row_route_matrix.md`:

- 120 rows, pillars 37/31/27/25, matrix tally YES/PARTIAL/NO = 43/21/56.
- all 27 beats are referenced by at least one row; no unknown beat id.
- every `NO` row carries an explicit no-route reason; every NPC row carries
  the measured 85.4 m reason; UI3-02/UI4-03/G5-01 carry the free-play-substitute
  binding.
- **tree kill:** `emit_tokens()` returns zero tokens unless `route_claim ==
  "played"`. Even a future played claim alone is not enough — this version has
  no per-row machine score input, so it still refuses to invent tokens.
  Current output: `P0B_ROUTE_STATS rows=120 beats=27 rows_with_beats=120
  tokens_emitted=0 route_claim=none`.

## 5. Gates run (this lane)

```
tools/godot --headless --path game --import                  # repaired fresh-worktree cache
tools/godot ... check_scripts_compile.gd                     # 234 checked, 0 broken
tools/godot ... run_tests.gd                                 # SUMMARY: fails=0, 329 PASS
tools/godot ... probe_den_window.gd                           # DEN_WINDOW PASS checks=44
tools/godot ... probe_route_npcs.gd                           # ROUTE_NPC PASS checks=4
build/qa/route_driver.sh --tag=den_telescope --seed=1025051536# exit 0, 12 checks, partial_driven
python3 build/qa/p0b_route_stats.py --self-test               # 15 checks, 0 fails
```

No GPU/Vulkan capture was run. The staged `p0b_route.gd` capture and the
120-row visual score remain separate tasks; a single short input-driven segment
does not make the route played.

**Gate registration (round 2).** `probe_route_npcs` is registered in
`build/qa/run_final_gates.sh` as gate 59 (`$OUT/probe_route_npcs.log`,
`ROUTE_NPC PASS checks=4 fails=0`), with its floor in `tools/gate_ratchet.json`
and evidence in `docs/reports/logs/final/probe_route_npcs.log`; the
`probe_den_window` marker/floor moved from 34 to 44 for the new real-key block.
`gate_manifest.py` reports `orphans=0`, `check_gate_ratchet.py` passes
`runner/binding self-check 59 gates`, and `make gate-ratchet` is PASS.

## 6. What is still owed for a played route

1. Drive S13–S26 (street, zipwire chain, courtyard, portico doors, foyer beams,
   stairs) with the same input driver, on one mission run.
2. Put an NPC in reach (authored patrol position or a real spawned guard) before
   S19/S22/S23 can be driven; do not move one just to pass.
3. Drive the UI beats S01/S02/S04/S06/S07/S08/S09/S10/S11/S27 with menu input
   and the `[F]`/click path (the short driver has no menu plan).
4. Only then set `route_claim=played`, call `mark_beat()` on all 27 captured
   beats, and feed explicit per-row machine scores to the scorer.
