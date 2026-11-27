# AGENTS.md — operating rules for this repository

Applies to every coding agent working in `/home/john/Projects/TAT-2`, whatever
the harness (OpenCode, Claude Code, Codex). Read this file before editing,
regenerating data, capturing screenshots or claiming a gate is green.

**What this repo is:** a private-use, asset-faithful port of the shipped UE5.5
game *Thick As Thieves* to Godot 4.7.2. The game loads the real extracted assets;
`extracted/`, `game/assets/ue/` and `game/data/generated/` are git-ignored and
must never be committed or redistributed. Only original code, tools and the
TAT-2 expansion content belong in git.

## Read before you touch

| If you are about to… | Read first |
|---|---|
| Change rendering, loader, materials or lighting | [`docs/FIDELITY_GAPS.md`](docs/FIDELITY_GAPS.md), the latest [`docs/reports/`](docs/reports/) wave |
| Regenerate or extend extracted data | [`docs/HANDOFF_NEXT_AGENT.md`](docs/HANDOFF_NEXT_AGENT.md) §5 (pipeline gotchas) |
| Change gameplay, UI or mission flow | handoff §1 (state), the owning `game/tests/` suites |
| Add or fix tests / E2E assertions | `game/tests/e2e/run_e2e_tests.gd` header, tier files |
| Take a screenshot or compare with UE | `build/qa/` harness sources, handoff §2 |
| Ship a wave | this file §“Definition of done”, then update the docs |

## Non-negotiable rules

1. **Never commit extracted content.** `extracted/`, `game/assets/ue/`,
   `game/data/generated/`, `build/` artifacts and
   `game/.godot/` are private/derived. `build/qa/` **script sources** are tracked
   on purpose; PNG/log artifacts are not.
2. **Never edit `game/` while a Godot process is running.** Scripts load lazily;
   a mid-run edit produces meaningless results. Edit between runs only.
3. **Do not weaken, skip or delete a test to go green.** Fix the game, or record
   the defect with evidence and an owner in `docs/FIDELITY_GAPS.md`. Changing an
   expectation is allowed only when the assertion itself was wrong (e.g. the
   intentional `MI_LightBeam_SM` shader exception in T2-04-C).
4. **Serialize GPU work.** Headless is the default. For Vulkan captures run one
   Godot at a time under Xvfb; never poll or run parallel GPU jobs.
5. **Generated data is produced, not hand-edited.** Fix the producer
   (`tools/parse_*.py`) then `make normalize`. Regenerated files are gitignored;
   commit the producer and the code that consumes it.
6. **Keep the authored lens.** World FOV is 54.54 vertical (UE 85 horizontal at
   16:9). The only permitted migration is the one-time legacy saved `fov: 75` →
   54.54; never clamp explicit user values.
7. **Respect runtime contracts.** Groups and flags other code depends on:
   `blocking_volume` (invisible designer blockers must stay solid but unclimbable),
   `swinging_doors`, `loot`, `xray_target`, `prep_skyline`, `GameState.free_play` /
   `free_play_pending`, `MissionPrepUI.open_prep(..., free_play)`. The W7 run
   clock and loot economy add more: `GameState.phase` / `phase_changed`
   (`main` → `endgame` → `resolved`), `escape_markers`,
   `GameState.loot_run_id`, `last_payout`, and the `bank_payout(match_id)`
   idempotency key. Do not rename or repurpose any of them without updating every
   consumer and test.
8. **Native engine binary first.** Use `tools/godot` (falls back to Flatpak).
   `godot` is not on `$PATH`.
9. **One coherent commit per change**, with gate evidence in the message or the
   wave report. Push `main` when the tree is clean and gates are green.
10. **Never fabricate a measurement.** Captures, ROIs and timings must come from a
    real run; say “not verified” otherwise.

## Commands and gates

```bash
make run         # native 4.7.2 client, F3 overlay
make test        # tests/run_tests.gd — 324 checks, suites numbered to 121
make runtime-smoke # real free-play boot: exit 124 only, ERROR:/push_error scan, allowlist
make audit       # fail-closed content + producer/output baseline gate
make gate-ratchet # floors + committed docs/reports/logs evidence agree
build/qa/test_perf_guard.sh  # perf-wrapper contract, no GPU, no launch
build/qa/run_final_gates.sh  # current full set (45 gates) -> docs/reports/logs/final/; no outer flock
build/qa/run_p0b_gates.sh    # historical P1 set (40 gates + cream RED) -> docs/reports/logs/p1/full/
build/qa/run_p0a_gates.sh    # historical P0a 28-gate set -> docs/reports/logs/p0a/

tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"
tools/godot --headless --path game --script res://tests/test_m2_player.gd
tools/godot --headless --path game --script res://probe_leak.gd
tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd
tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=1
tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=s2
```

If a headless run reports missing textures (`T1-01-C`, `moon_visible=0.0`), the
import cache is incomplete — run `tools/godot --headless --path game --import`
first.

| Gate | Passing value (45-gate set measured_on `912a481`, logs in `docs/reports/logs/final/` — raise, never lower) |
|---|---|
| compile | 217 checked, 0 broken |
| `run_tests.gd` | `SUMMARY: fails=0` (324 PASS; suites numbered to 121, 119 cream + 121 audio registered) |
| `test_m2_player.gd` | `M2_SUMMARY: fails=0` (12 PASS) |
| P1 route probes (S12/S21/S24/S25–26/S13–20) | `P1_SAFE PASS checks=86` / `P1_DOORS checks=47 fails=0` / `P1_BEAMS PASS checks=7` / `P1_WARD PASS checks=44` / `P1_STREET PASS checks=31 hard_limits=2` |
| door walk / viewmodel / Niagara probes | `DOORWALK PASS` / `VIEWMODEL_TRUTH PASS` / `NIAGARA_PROBE PASS` (3695 authored / 1048 active / 16 systems in this probe's map scope; the payload-wide census is 3308 active / 36 systems) |
| guard selection (P0a) | `GUARD_CHECK PASS` Guildhall `lounge_marker=C_20` `buckets=4/4` and Old Manor `--order=3` (no Hauntstable) |
| beam geometry (P0a) | `BEAM_GEOMETRY_SUMMARY: fails=0` — 330 cards, `max_axis_err_deg=0.000006`, `clamped=0` |
| GC / turret / civilian (P0a/W10) | `GC_PROBE PASS` (44) / `GC_TRIGGER PASS` (21) / `TURRET_PROBE PASS` (229 actors, 1145 parts, 0 hidden) / `W10A2_CIV_SUMMARY: fails=0 passed=23` |
| collision (W10-P2 truth) | `COL_MAPS PASS maps=3 min_coverage=0.869 dropped=0 planar_skipped=2 coverage_ppm=868852` — authored element coverage 0.910/0.912/0.869, `no_record=0`, no invented fallback |
| lock inventory | `applied=154 containers=144 door_nodes=10 state=APPLIED` |
| E2E | `fails=0 passed=300 total=300` (T1=117 T2=110 T3=25 T4=14 S2=12 A2=22; a2 runs inside `all`) |
| E2E tier a2 | `SUMMARY: fails=0 passed=22 total=22` |
| E2E tier p2 | `P2_SUMMARY: expected_fail=0 expected_delta=0 fixed=0 unexpected_fail=0` (14/14; both pants checks are hard) |
| parity-only (P0b) | `PARITY_ONLY_SUMMARY: fails=0 passed=60 rules=11 restoration=11 expansion=0` |
| cream suite 119 (W10-P2) | `CREAM_PROOF: GREEN passes=5 expected_fail=0`, exit 0 (the old RED proof is retired) |
| audio control suite 121 (W10-P3) | `AUDIO_CONTROL_SUMMARY: fails=0 checks=71` (switch=14/23, state=4/8, rtpc=16/50, 142 curves) |
| P5 UI probe (W10-P5) | `P5_UI PASS checks=44` (headless; no visual score) |
| Den spawn (W10) | `DEN_SPAWN PASS checks=9 fails=0` (`source=authored`, 2434 meshes) |
| port capture harness (P0b) | dry-run `poses=6` manifest valid; `P0B_SELFTEST PASS checks=21 fails=0`; `P0B_KF27_REF … met=7/7` |
| route runner self-test (Phase 0a) | `P0B_ROUTE_SELFTEST PASS checks=62 fails=0`; `bash -n` on `p0b_route.sh` and `p0b_live_capture.sh` |
| `make texture-cap-check` | OK — 796 capped, 1 alpha-critical kept, 0 offenders (target set 1567 after the accepted `texture_refs 1523→1522` drop) |
| `make audit` | exit 0, tracked baseline matches, disk-backed coverage (12660/12703), 0 unexpected, exact-case 0 unexpected, 13/13 content groups |
| `make string-audit` | `UI_STRINGS total=311 routed=311 authored=199 routed_authored=199 invented=112` (ceiling 112; one documented `Thieves' Den` port copy at `contract_table_ui.gd:362`) |
| perf guard | `PERF_GUARD_TEST PASS checks=78 fails=0` |
| `make gate-ratchet` | PASS (`measured_on=5135f53`; floors raised, never lowered) |

The 2026-11-24 W7 wave (five lanes, cherry-picked) re-ran the **complete** set
serially on `6760dd0` — compile, `run_tests`, M2, the three probes, `probe_leak`
(`TAT2_NO_DEN_PROBE=1`), E2E 278/278, `test_perf_guard.sh` (78/78), `make audit`
and `make texture-cap-check` — after regenerating and re-stamping the audit
baseline. Evidence: [`docs/reports/logs/w7-merged/`](docs/reports/logs/w7-merged/)
and [`docs/reports/w7-integration.md`](docs/reports/w7-integration.md). E2E moved
264 → 278 (W7H guard-sprint pair + W7S 12-case loot tier); `run_tests` moved
263 → 278 (S2 suites 89/90, W7E suite, W7H tests).

The 2026-11-25 **W9 wave** (four phases, 34 commits) consumed the new producers:
collision is authored `AggGeom` (98.9 % of meshes), progression is the authored table,
locks are authored-only (154 runtime: 144 container placements + 10 door nodes; 363 is
the raw record join), UI routing is 100 % of authored rows, and the
StateTree runtime runs in shadow with a measured ceiling of **0/21 trees fully
evaluable** at W9 (B2.1 later raised it to one structural tree at `5135f53`;
parity coverage is still zero). See
[`docs/reports/w9-remediation-20261125.md`](docs/reports/w9-remediation-20261125.md).
It also added `make runtime-smoke`.

The 2026-11-25 R8 wave merged twelve remediation teams (40 commits, see
[`docs/reports/r8-remediation-20261125.md`](docs/reports/r8-remediation-20261125.md)):
`run_tests` 278 → **301** (suites to **97**), compile 120 → 152 scripts, and every
producer/output gate re-stamped. The upstream audit that motivated it is in
[`docs/reports/re-audit-20261124.md`](docs/reports/re-audit-20261124.md) and the
recorded-run scorecard in
[`docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md`](docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md).

The 2026-11-26 **P0a wave** restored two proven parity defects and repaired the
gate evidence. Guard selection now uses the authored `spawn_bucket` /
`spawn_layers` metadata (`PARITY_APPROX`; Guildhall Contract 2 selects the Lounge
`C_20` `StandardGuards_Bouncers` marker, never Hauntstable; the 4/6/8 count stays
a labelled `PORT_DECISION`). Beams apply the authored device column-2 axis and
length instead of column 0: 330/330 cards, `max_axis_err_deg=0.000006`,
`clamped=0` (134 Guildhall + 196 Old Manor; the removed 200 ceiling would clip
5/196 and the old 40 m clamp 322/330). The complete set — 28 gates including the
guard Guildhall/Old Manor probes, beam geometry, GC/turret/civilian, leak, full
E2E, runtime smoke with **no outer flock**, audit, texture cap, perf guard and
ratchet — now runs from the tracked `build/qa/run_p0a_gates.sh`, which stops on
the first unexpected non-zero exit. Evidence:
[`docs/reports/p0a-20261126.md`](docs/reports/p0a-20261126.md) and
[`docs/reports/logs/p0a/`](docs/reports/logs/p0a/) (measured on `84912ee`).

The 2026-11-26 **P0b wave** built the parity instruments and measured them at the
merged HEAD. The acceptance harness added suites **117/118/120** (suite **119** is
the standalone cream RED proof and is deliberately unregistered) and the E2E tier
`a2` (one real Contract 02 Novice load; now inside `all`), so `run_tests` is
**322** and E2E is **300/300** (T1=117 T2=110 T3=25 T4=14 S2=12 A2=22). Tier
`p2` records authored-data parity as **12/12 with one expected FAIL** (civilian
pants albedo: `parse_materials` puts the authored `Pants_D` in the `opacity`
slot); the beam material was promoted to an authored-parameter match in
P1-BEAMS (`372bf74`), so the current summary is
`expected_fail=1 expected_delta=0`. The gate is `unexpected_fail=0`, so a data
wave must promote `fixed`. Parity-only
governance is proven by `test_parity_only.gd` (**60/60**; 11 content-override
rules, all `parity_restoration`, 0 unclassified) and `TAT2_PARITY_ONLY=1` excludes
expansion content while keeping every shipped marker/guard/GC/loot record. The
port capture harness (six-pose manifest, Master-bus audio tap with a headless
fallback, ROI/KF27 scorer) is built and self-tested. The first real port capture
ran on 2026-11-26 (`docs/reports/logs/p0b/20261126T210338Z_...`); the frames
confirm the visible cream bars are the `SM_LightBeam` cards (axis fixed,
full-tube material still P4), and exposure is split (gate too dark, foyer too
bright). The live reference and 120-row baseline are not scored.
The complete set — 35 gates plus the cream expected failure — runs from
`build/qa/run_p0b_gates.sh` with logs in
[`docs/reports/logs/p0b/full/`](docs/reports/logs/p0b/full/) (measured on
`dfa8c7e`); report:
[`docs/reports/p0b-20261126.md`](docs/reports/p0b-20261126.md).

The 2026-11-26 **P1 wave** restored the route content for S12–S26 in five lanes
(safe room / portal / lantern, blue double doors / prompts, security beams /
foyer, ward / lockdown / alarm, street / car / gate / MACLEOD). The merged tip
`3998761` was red at `A2-WHITE`: the new safe-room portal outline carried only a
`material_override`, which the audit's surface sampler reads as glTF-default
white. `78884fe` binds the same shader on the QuadMesh surface and is the tree
measured by one serial `build/qa/run_p0b_gates.sh` run — **40 gates** plus the
cream expected failure, logs in
[`docs/reports/logs/p1/full/`](docs/reports/logs/p1/full/). `compile` is
**213/0**, `run_tests` **322**, E2E **300/300**, p2
`expected_fail=1 expected_delta=0`, and the five new probes are
**86 / 47 / 7 / 44 / 31** checks (safe / doors / beams / ward / street). Rows
now scoreable (subject present and probe-measured; not yet visually scored):
V6-01, G1-05, V1-04, V1-05, V3-01, V3-03, UI2-05, V4-05, V4-06, V4-07,
V6-03, V6-04, G5-03, G5-04, V1-07, UI5-06, G1-04, AU5-01. HARD_LIMITs are
recorded, not faked: the `BARRON'S DEMOLITION` banner (no asset), the KF15 drum
placement (no record), the exact cyan ceiling node (hidden BP/Niagara overlay),
and the authored circular-lockpick widget art. The port capture and the
live-reference 120-row score remain **pending** (no GPU run in P1). Report:
[`docs/reports/p1-integration-20261126.md`](docs/reports/p1-integration-20261126.md).

The 2026-11-27 **W10 FINAL wave** merged the P2/P3/P5 + data lanes and measured
them at `5135f53` in one serial `build/qa/run_final_gates.sh` run — **44 gates**
(no expected failure; Phase 0a adds the route self-test for **45**), logs in
[`docs/reports/logs/final/`](docs/reports/logs/final/), report
[`docs/reports/final-20261127.md`](docs/reports/final-20261127.md). `compile` is
**217/0**, `run_tests` **324/0** (suites **119** cream + **121** audio
registered), M2 **12/0**, E2E **300/300** (T1=117 T2=110 T3=25 T4=14 S2=12
A2=22), p2 **14/14** with `expected_fail=0 expected_delta=0 fixed=0
unexpected_fail=0`, parity-only **60/60**, cream **GREEN** `passes=5`, audio
control **71/0**, P5 UI **44**, Den spawn **9**, and the P1 probes stay
**86/47/7/44/31**. Collision is re-based to the authored **element** coverage
(`COL_MAPS PASS min_coverage=0.869 dropped=0 planar_skipped=2
coverage_ppm=868852`; Guildhall 0.910, Old Manor 0.912, FTUE 0.869, runtime
`no_record=0`) — the old `976321` counted invented render-trimesh fallbacks, so
this is a deliberate truth correction, not a regression. The texture cap moved
797 → 796 with the already-accepted `texture_refs 1523 → 1522` target-set drop
(`offenders=0` unchanged). P2-ST B2.1 reads payload-v2 node parameters
(566/566 keys) and measures one structurally covered tree
(`ST_Subtree_IntruderNoLongerSuspicious`, `fully_parity_covered_trees=0`), but
`TAT2_STATETREE` stays `off` and the FSM still drives — **no cutover**. P2-NAV
proved the cooked Guildhall Detour tiles (2,958 tiles / 14,930 polys) and a
Godot consumer (**16/0**, 3-waypoint doorway, sync 975 ms, total 1,172 ms);
the **P1 Detour consumer is the next navmesh lane**, still no runtime region.
The P3 audio control plane is **partial** (14/23 switches, 4/8 states, 16/50
RTPCs; state property rows, music decision trees and `FS_Layers` deferred). P5
UI is **headless-verified, not visually scored** (44 checks; Light Gem
`PORT_APPROX` because the 21-slice array is absent), with one documented
`Thieves' Den` port copy (string-audit ceiling 112). The live-reference / 120-row
baseline and a GPU capture remain **pending**.

The 2026-11-27 **Phase 0b** run re-measured the **45-gate** set at `912a481`
(clean route2 + the Phase 0a route self-test) — **45/45 exit 0**, every count
identical to the `5135f53` table, logs in `docs/reports/logs/final/`, report
[`docs/reports/final-20261127-phase0b.md`](docs/reports/final-20261127-phase0b.md).
The clean route2 capture is `docs/reports/logs/p0b-route/route2-clean/`
(`status=captured`, `git.dirty=false`, 13/14/0, 17 frames, 18 PNGs at 1920×1080,
exit 0). The ratchet is re-stamped `measured_on=912a481` and pins
`p0b_route_self_test.checks=62`. The run replaced the logs in place; the
`5135f53` logs remain in git history at that commit. Still a **staged** capture
(`route_claim=none`), not a played route.

**Fresh worktree trap (P0b).** A copied `game/.godot` does not know a new global
`class_name`; scripts that use it fail with `Identifier "X" not declared` and
`test_parity_only.gd` reports `GameState autoload missing`. Run
`tools/godot --headless --path game --import` once after checking out a merged
tree in a worktree. It writes only gitignored `.godot/` state and local `.uid`
sidecars; no tracked file changes.

If `.godot/imported` lacks the `.s3tc.ctex` variants, `T1-01-C` fails with
`moon_visible=0.0`. Run `tools/godot --headless --path game --import` first; it
repairs the cache and changes no tracked file.

The perf matrix is **not run** (thermal gate waived, but no parallel Godot and
the host idles near 80 °C); the editor core opened but its ≤2.5 GB VRAM
threshold is unproven because `nvidia-smi memory.used` is device-wide.

Anything below these numbers is a regression. Do not re-baseline silently; find
the cause or record it.

## Architecture in one screen

```
game/src/core/        level_loader (UE→Godot world), game_data, game_state,
                      save_system (save v8 + payout outbox), audio_manager,
                      shaders (tat_*.gdshader)
game/src/player/      thief_character (movement, mantle, wall climb, zipwire,
                      step-up/step-down)
game/src/ai/          guard_ai, civilian_npc, hearing_data
game/src/stealth/     light_probe, noise_bus, surface_resolver (ray → authored surface)
game/src/interact/    swinging_door, loot, loot_inventory (12-slot bag),
                      loot_stash, clues, escape_gate, street_car,
                      toggleable_lantern
game/src/missions/    mission_controller (spawns, Den/Guildhall fills, sign,
                      free play, two-phase run clock), safe_room_dressing
game/src/devices/     device_layer, security_beam, ward_zone, vine_lock,
                      alarm_eye
game/src/ui/          main_menu, contract_table, mission_prep, hud, wardrobe,
                      ledger, tool_preview, settings, status_icon
game/data/expansion/  tracked TAT-2 content (briefing overrides, graybox rules,
                      prep_skyline backdrop)
game/tests/           run_tests.gd, test_m2_player.gd, probe_*.gd,
                      e2e tiers 1-4 + s2
tools/                tat-extract (.NET), parse_*.py producers, manifest_audit,
                      check_gate_ratchet
build/qa/             tracked capture/probe/export-stamp scripts; PNG output ignored
```

## Known traps

- **Stair meshes are exempt from the convex element cap.** `authored_collision.gd`
  reduces a convex set above `MAX_CONVEX_ELEMENTS_PER_MESH = 16` to one coalesced
  trimesh of element AABBs, but a stair flight's hulls *are* the walkable surface:
  the 36-hull `SM_OldManor_Tower_Stairs_4x850` moved -0.02 m over 280 frames when
  coalesced. `resolve()` keeps every element for a path containing `stair` (the
  instance-cost cap still applies). `test_stair_walk.gd` pins the per-element count,
  so "one hull of many" cannot come back.
- **A coplanar authored convex element is not solid.** `authored_collision.gd` skips a
  convex element whose baked point AABB is flatter than `PLANAR_EPS_M = 1e-4 m`
  (`planar_convex_skipped`, one `COL_PLANAR` line per path). The 160
  `SM_SlowWardZone_Quad` billboards and 2 `FXSHAPES_1_*` quads are this class (the third
  coplanar convex element is the ward quad itself); the ward zone's
  real body is the device layer's (`ward_zone.gd`, `zone_size_m`). Do **not** extend
  the skip to boxes: the `2 cm` `MIN_HALF_EXTENT_M` clamp is measured as legitimate
  (27 clamp-hit box elements on 18 placed meshes, 295 placed instances excluding the
  20 `/Engine/BasicShapes/Plane` instances, 235 of them glass).
- **The StateTree trace file is budgeted like the ring.** `trace.gd` stops the NDJSON
  sink at `MAX_FILE_ROWS = 8192` (the ring cap) or 16 MiB, keeps counting in
  `file_dropped`, and prints one `STATETREE_TRACE capped` line. `dropped` still means
  ring drops only; do not "fix" a capped run by raising the budget without saying why.
- **A screen that consumes ESC must stamp the frame.** `FocusNav.mark_escape_consumed()`
  is the shared form of the lockpick `_pause_consumed_frame` guard: the HUD polls the
  `pause` action in `_process`, and `set_input_as_handled()` does not clear it. Any new
  screen that closes on ESC must stamp, or the pause menu opens behind it (suite 112).
- **One rack-up, one consumer.** The HUD owns at most one `PostMatchUI`
  (`_post_match_ui`, replaced on every open) and connects both `closed` and
  `continue_requested`. A screen that hides instead of freeing is only safe because the
  HUD is the owner; do not add a second opener.
- **The prison door is pickable as authored.** `CanBeLockpicked` absent resolves to
  `true` (delta dump; a same-class FTUE door writes `false` explicitly), so
  `StaticMeshActor_528` must stay pickable — see `build/qa/w10/re-1-locks.md` and
  `check_lock_cdo.py`. Its authored `MaxLockLevel` is **4** but the producer emits
  instance deltas only, so the port locks at 1: a producer chain resolution +
  regeneration is the open item, not a consumer flip.

- **`game/assets/ue/Raw` is read-only.** Write the physical path under
  `extracted/assets/…`; the hidden `TAT/` subtree must keep its `.gdignore` or
  duplicate UIDs return.
- **Texture cap is not reproducible from extraction.** Rerun
  `make desktop-texture-cap` after a clean extract and after `make normalize`.
- **`parse_materials.py` must read `BasePropertyOverrides`** (two-sided, blend,
  unlit) and prefer a child MI's own `_D` companion over the parent master's
  painterly `T_PaintStrokesD`. Regressing either silently breaks gates, doors and
  floors.
- **A2-WHITE samples surface materials, not `material_override`.** A port-built
  `MeshInstance3D` with only an instance override reads as glTF-default white in
  the acceptance audit. Bind the material on the mesh surface
  (`surface_set_material`) as well; `SafeRoomPortalOutline` at `3998761` is the
  measured example (fixed in `78884fe`).
- **A HUD SubViewport must set `own_world_3d = true`.** `status_icon.gd` (P1-W)
  created its jaw-trap SubViewport without it, so its `DirectionalLight3D` lit
  the gameplay `World3D` (yaw180 mean 39 → 84). Every other UI SubViewport sets
  it. Headless probes skip the icon; only the Xvfb Vulkan capture caught it.
  Fixed in `fafb78f`.
- **`MI_LightBeam_SM` is a deliberate exception** to the HDR neon path: it uses
  additive `tat_beam.gdshader`. T2-04-C guards the exception plus three
  `StandardMaterial3D` negative controls.
- **Cream / invented white is closed; do not reintroduce a white fallback.**
  `_apply_ue_emissive()` requires an authored `EmissiveColor` or emissive map; a
  strength-only material gets no emission and increments `tat_invented_white`
  (`invented_white_count()`), while an authored colour still emits. Suite **119**
  is a normal green gate (`CREAM_PROOF: GREEN passes=5`). The cream bars in the
  old captures are the `SM_LightBeam` cards (a P4 beam-material item), not the
  moon planes.
- **WorldGrid substitution is scoped** to door/gate/fence meshes. WorldGrid is
  still intentional for spheres/emitters; never hide it globally.
- **Loot/civilian spawns are grounded by mesh AABB + floor ray** (0.03 m
  clearance). Do not reintroduce a blanket vertical offset.
- **Free play must not bank progression.** `_on_extracted()` skips both
  `record_contract_complete` and `add_currency`; a normal deploy clears
  `free_play`/`free_play_pending`.
- **Guildhall POI graybox floors** (1,637 `GB_Floor_2x2`) are a deferred content
  project, not a loader defect. Do not “fix” them by nudging the loader.
- **Den probe leak:** 7 texture RIDs warn at exit; `TAT2_NO_DEN_PROBE=1` is the
  clean path. Not a script error.
- **Collision is authored `AggGeom`, behind a flag.** `TAT2_COLLISION=authored|aabb`
  (default `authored`). The producer's `half_extent` is the *full* extent (a 2× trap), the
  capsule axis is Z, and convex bakes must carry instance scale — getting any of those wrong
  produced 95,293 Jolt scale errors. `probe_collision_authored.gd` gates on authored
  **element** coverage, not the render-trimesh fallback: `COL_MAPS PASS
  min_coverage=0.869 coverage_ppm=868852 dropped=0` (Guildhall 0.910, Old Manor
  0.912, FTUE 0.869, runtime `no_record=0`). The older `coverage=0.989` /
  `976321` counted invented fallback collision and must not come back; the probe
  still prints it for continuity but `element_coverage=` is the gate.
  `test_roof_collision.gd` runs both modes; do not restore the old one-hull heuristic.
- **The StateTree runtime is node-aware but shadow-only; no cutover.** B2.1 reads
  payload `/2` per-node `parameters`/`bound` (497/566 nodes author data, 676
  bindings, 139 templates), keys nodes by `(tree,node_index)` (566/566 keys, 0
  duplicates) and separates structural coverage from data parity:
  **`fully_covered_trees=1`** (`ST_Subtree_IntruderNoLongerSuspicious`) and
  **`fully_parity_covered_trees=0`** of 21. Task instances 326 (139 covered / 56
  blind) and condition instances 233 (35 / 20) are the measured ceiling.
  `TAT2_STATETREE` stays `off` by default; `patrol` is not enabled and warns that
  it runs shadow. The FSM still drives. A cutover needs the remaining authored
  task/condition parameters (the producer contract in
  `build/qa/w9/p4-t01-contract.md`), never invented values. Suite 110 is **191
  checks**; suite 111 keeps shadow side-effect free.
- **The light budget is per-room fair, not a global energy cut.** `plan_light_selection()`
  water-fills the same 160 slots per 16 m room bubble (one light per bubble before any
  second, densest-first, deterministic) instead of ranking all 914 deduped Guildhall lights
  by authored energy and cutting at 25.0 lm — the old rule left 94 of 189 bubbles unlit and
  killed every candle and sub-20-lumen practical. Do not reintroduce a global rank; the
  protected set is the 6 KF16 gate lights, the contract-2 safe-room spot, and the 6 hero
  shadows. Candle *lights* are still 0/135 by design (they are 0.35–1.5 m sconce glows and a
  slot costs a room its practical); candle *geometry* is emissive.
- **Roughness bake is full-resolution and process-cached.** The L8
  `low + g*(high-low)` bake is keyed by ORM+range in a process-global cache and
  released only when the last live loader leaves the tree. Do not add a
  half-res path; `TAT2_ROUGH_BAKE=off` is a documented diagnostic fallback
  (`roughness=high`, no texture), never the default.
- **The QA export is stamped, not trusted.** `make linux-build` writes
  `build/tat2-linux-x86_64.stamp.json`; the perf wrapper fails closed on a
  missing, stale or hash-mismatched stamp, and a dirty build is not
  publishable. `scenes/review/**` is excluded from the export. Do not hand-edit
  or delete the stamp; rebuild.
- **`export_presets.cfg` must not contain `#` comments.** Godot's `ConfigFile`
  parser does not treat `#` as a comment: it merges the comment and the next
  key into one malformed key, so `exclude_filter` silently disappears and the
  export includes `scenes/review/**` with no error. Use `;` or keep the
  rationale in the report. Prove it with
  `ConfigFile.has_section_key("preset.0", "exclude_filter")` (must be true).
- **Editor opens rewrite `project.godot`.** A visible editor run reorders the
  file and drops the project's comments/settings. Never commit that rewrite;
  `git checkout -- game/project.godot` after an editor check.
- **Sonar does not see GDScript.** Its gate is new-code Reliability A +
  Security A + duplication <= 3 %; coverage and maintainability are not gate
  conditions. The GDScript floors live in `tools/gate_ratchet.json` and are
  checked against the committed logs in `docs/reports/logs/`.
- **Loot capacity: 12 authored slots, authored cost 1 per item.** 12 slots
  (`BP_TATPlayerState.InventorySlotMaxCapacity`) and the authored slot cost is
  **1/1/1** — `ETATLootType` has no `QuestLoot`, and `parse_loot.py` drops
  `lootType`. `minor 1 / major 3` is a **port decision**, not authored data:
  keep it, but label it as such wherever it is described. `kept_on_escape = 1.0`,
  `kept_on_capture = 0.0`, stashed value is always kept — there is **no**
  authored kept/lost fraction, so do not invent one.
  `DifficultyToLootMultiplier` (authored 1/2/3) is **not stored anywhere** and
  `DIFFICULTY_MULTIPLIER_APPLIED` **does not exist in the tree**; the multiplier
  only reaches the port through T01's `DefaultGame.ini` producer. Do not cite
  the old "stored but not applied" wording.
- **The run clock has two phases.** `main` ends when the objectives complete and
  the escape doors are summoned; only the active phase ticks, main expiry is
  `TIME EXPIRED`, endgame expiry is `MAGIC DOOR COLLAPSED`, and **an endgame
  timeout still banks the stashed haul** (carried is lost, no reward). A
  dormant escape gate must never extract. The main window is the **mission**
  row (LootTheRoom 3300 s), not the 7200 s map row.
- **Every failure path owes a payout.** Escape, capture, main timeout and door
  collapse must each call `build_payout` + `bank_payout`, guarded by
  `_payout_applied`, or a run silently loses (or double-banks) currency.
- **`prep_skyline` is TAT-2 expansion content, not shipped art.** It is built
  from shipped `Skybox/` meshes and labelled `expansion: true` in the JSON, in
  the runtime constant and in the report. Never describe its silhouette as
  authored Kilcairn content.
- **The step-down query capsule is off by default** (`STEP_DOWN_QUERY_SHRINK_M =
  0.0`). D1 (0.40 m ray, ≤0.30 m accept) + D5 (landing coalescing) are the
  shipped path; the D2 shrink is a measured experiment (1–2 air frames,
  0.001 m shove-back). Do not enable it without re-measuring the shove-back.
- **Maps with authored placeholders** (`Mission.Example.*` fallbacks, Niagara
  placement notices, fog clamp, deferred navmesh) log expected warnings; do not
  “clean up” the logs by suppressing the messages.

## Parallel waves

Long waves may be split across subagents in separate git worktrees. Symlink
`game/assets`, `game/data/generated` and `extracted` into the worktree, copy
`game/.godot` for imports, never edit the main checkout from a worker, and
cherry-pick the worker commit onto `main` after its gates pass. Resolve conflicts
by taking both intents (e.g. the `blocking_volume` tag comment), then rerun the
full gate set on the merged tree — not just the worker's suite.

**The symlinked data tree is read-only for workers.** `game/data` is a single
shared directory, so a worker that runs `make normalize`, any `tools/parse_*.py`
or `make audit-refresh-stamps` writes into the main checkout and rewrites the
audit baseline for every other lane mid-run. In W7 that happened and produced a
phantom `make audit` failure in four lanes. Only the integrator regenerates
generated data, and only at the merged HEAD; a worker that needs new producer
output must ask for it. If a lane genuinely must regenerate, give it a private
copy of `game/data` instead of the symlink.

## Definition of done for any wave

```bash
git status --short                      # clean, or only intentional new files
make audit                              # exit 0 (now incl. string-audit + check-greps)
tools/godot … check_scripts_compile.gd  # 0 broken
make test                               # fails=0
tools/godot … test_m2_player.gd         # fails=0
tools/godot … probe_leak.gd             # expected result or documented warning
tools/godot … probe_collision_authored.gd  # COL_MAPS PASS, element coverage >= 0.868, no_record=0, dropped=0
tools/godot … probe_lock_inventory.gd   # applied == 144 containers + 10 door nodes, never 0
tools/godot … run_e2e_tests.gd          # 300/300, no new failures
tools/godot … test_parity_only.gd       # PARITY_ONLY_SUMMARY: fails=0 (needs TAT2_PARITY_ONLY proof)
tools/godot … test_w10a2_cream.gd       # CREAM_PROOF: GREEN passes=5, exit 0 (suite 119)
tools/godot … test_audio_control.gd     # AUDIO_CONTROL_SUMMARY: fails=0 checks=71
tools/godot … probe_p5_ui.gd            # P5_UI PASS checks=44
tools/godot … probe_den_spawn.gd        # DEN_SPAWN PASS checks=9 fails=0
tools/godot … probe_p1_safe.gd          # P1_SAFE PASS checks=86 fails=0
tools/godot … probe_p1_doors.gd         # P1_DOORS checks=47 fails=0
tools/godot … probe_p1_beams.gd         # P1_BEAMS PASS checks=7 fails=0
tools/godot … probe_p1_ward.gd          # P1_WARD PASS checks=44
tools/godot … probe_p1_street.gd        # P1_STREET PASS checks=31 hard_limits=2
build/qa/runtime_smoke.sh 90            # exit 124 only, 0 unexpected ERROR:, mission_ready
build/qa/test_runtime_smoke_scan.sh     # 29/29, no engine needed
build/qa/test_perf_guard.sh             # 78/78, no GPU
build/qa/run_final_gates.sh             # all of the above serially (45 gates, no expected failure)
make gate-ratchet                       # floors + committed logs agree
git push origin main
```

When a Linux export is part of the wave, add `make linux-build` +
`make linux-stamp-verify` and record the `EXPORT_STAMP`/`PERF_PCK` lines.

Then update, in the same wave:

- `docs/FIDELITY_GAPS.md` — what changed and what remains;
- a `docs/reports/<wave>.md` with measured evidence;
- `docs/HANDOFF_NEXT_AGENT.md` — HEAD, gates, open work;
- `README.md` only when user-facing commands/status change.
