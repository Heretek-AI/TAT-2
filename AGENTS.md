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
make test        # tests/run_tests.gd — 319 checks, suites numbered to 116
make runtime-smoke # real free-play boot: exit 124 only, ERROR:/push_error scan, allowlist
make audit       # fail-closed content + producer/output baseline gate
make gate-ratchet # floors + committed docs/reports/logs evidence agree
build/qa/test_perf_guard.sh  # perf-wrapper contract, no GPU, no launch

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

| Gate | Passing value (W10-A tip, logs in `docs/reports/logs/w10/` — raise, never lower) |
|---|---|
| compile | 189 checked, 0 broken |
| `run_tests.gd` | `SUMMARY: fails=0` (319 PASS; suites numbered to 116) |
| `test_m2_player.gd` | `M2_SUMMARY: fails=0` (12 PASS) |
| door walk / viewmodel / Niagara probes | `DOORWALK PASS` / `VIEWMODEL_TRUTH PASS` / `NIAGARA_PROBE PASS` (3695 authored / 3308 active / 36 systems) |
| E2E | `fails=0 passed=278 total=278` (tier 1: 117; includes `--tier=s2`) |
| `make texture-cap-check` | OK — 797 capped, 1 alpha-critical kept, 0 offenders |
| `make audit` | exit 0, tracked baseline matches, disk-backed coverage (12660/12703), 0 unexpected, exact-case 0 unexpected, 13/13 content groups |

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
evaluable**. See [`docs/reports/w9-remediation-20261125.md`](docs/reports/w9-remediation-20261125.md).
It also added `make runtime-smoke`.

The 2026-11-25 R8 wave merged twelve remediation teams (40 commits, see
[`docs/reports/r8-remediation-20261125.md`](docs/reports/r8-remediation-20261125.md)):
`run_tests` 278 → **301** (suites to **97**), compile 120 → 152 scripts, and every
producer/output gate re-stamped. The upstream audit that motivated it is in
[`docs/reports/re-audit-20261124.md`](docs/reports/re-audit-20261124.md) and the
recorded-run scorecard in
[`docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md`](docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md).

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
                      loot_stash, clues, escape_gate
game/src/missions/    mission_controller (spawns, Den/Guildhall fills, sign,
                      free play, two-phase run clock)
game/src/ui/          main_menu, contract_table, mission_prep, hud, wardrobe,
                      ledger, tool_preview, settings
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
- **`MI_LightBeam_SM` is a deliberate exception** to the HDR neon path: it uses
  additive `tat_beam.gdshader`. T2-04-C guards the exception plus three
  `StandardMaterial3D` negative controls.
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
  produced 95,293 Jolt scale errors. `probe_collision_authored.gd` is the coverage gate
  (`coverage=0.989`, `dropped=0`). `test_roof_collision.gd` runs both modes; do not restore
  the old one-hull heuristic.
- **The StateTree dump is a property dump; the trees are not fully evaluable.** 18/77 task
  classes and 6/36 condition classes are mapped, and **0 of 21 trees** can be evaluated
  end-to-end because the payload drops every node parameter (`EAlertnessLevel`,
  `DelayTask.duration`, `Move To` target, `Bool Compare` operands). The runtime therefore
  runs in **shadow** (`TAT2_STATETREE=off|shadow`, default off) and reports; the FSM still
  drives. A cutover needs the producer contract in
  `build/qa/w9/p4-t01-contract.md`. Do not "finish" a cutover by inventing parameters.
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
tools/godot … probe_collision_authored.gd  # COL_MAPS PASS, per-map coverage >= 0.95, dropped=0
tools/godot … probe_lock_inventory.gd   # applied == 144 containers + 10 door nodes, never 0
tools/godot … run_e2e_tests.gd          # 278/278, no new failures
build/qa/runtime_smoke.sh 90            # exit 124 only, 0 unexpected ERROR:, mission_ready
build/qa/test_runtime_smoke_scan.sh     # 29/29, no engine needed
build/qa/test_perf_guard.sh             # 78/78, no GPU
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
