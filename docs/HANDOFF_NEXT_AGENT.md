# Handoff — Thick As Thieves Godot 4.7.2 port (next session)

**Repo:** `/home/john/Projects/TAT-2`
**Code/data tip:** `84912ee` (P0a: guard bucket/layer selection + authored beam
axis + audit re-stamp). This handoff and the P0a evidence are the commit on top
of that tip.
**Working tree:** clean apart from private/derived data and the tracked
`docs/reports/logs/p0a/` evidence.
**Godot:** `4.7.2.stable` via native `tools/godot` (`godot` is **not** on `$PATH`).
**Renderer:** Forward+ · Jolt 60 Hz · 1280×720 reference · Linux x86_64.
**Steam reference:** `/home/john/.steam/steam/steamapps/common/Thick As Thieves/`.
**Single-Godot lock:** `/tmp/opencode/tat2-godot.lock` (never wrap
`build/qa/runtime_smoke.sh` in an outer `flock`; it takes the lock itself).

## 1. State in one paragraph

P0a restored two proven parity defects and repaired the evidence set. Guard
selection now uses the authored `spawn_bucket`/`spawn_layers` metadata
(`PARITY_APPROX`, 4/6/8 still `PORT_DECISION`) and Guildhall Contract 2 puts the
Lounge guard on the authored `C_20` marker, not the Hauntstable `C_16`. All 330
`SM_LightBeam` cards now use the authored device column-2 axis and length
(`PARITY_RESTORATION`; material still P4). The complete gate set runs from the
tracked `build/qa/run_p0a_gates.sh` in one serial run with committed logs. The
next work is **P0b — a live capture and the honest 120-row baseline**; the
remaining known look defects (cream slabs, mirrored winding, landscape visibility,
sky/IBL, EV bias) and behaviour (StateTree cutover, Niagara activation) come
after it.

## 2. Gates at this HEAD (all measured, logs in `docs/reports/logs/p0a/`)

Run: `build/qa/run_p0a_gates.sh` on `84912eef76d4cbd0a65258aa6c715ed4e6a7a2c3`
(Godot `4.7.2.stable.official.ed1daf0bf`). Every gate exited 0; the runner stops
on the first unexpected non-zero exit.

| Gate | Value |
|---|---|
| compile | **196 checked, 0 broken** |
| `run_tests.gd` | **319 PASS, fails=0** (suites to 116) |
| `test_m2_player.gd` | **12 PASS, fails=0** |
| guard, Guildhall Contract 2 | `GUARD_CHECK PASS ... guards=4 buckets=4/4 lounge=1 lounge_marker=C_20 selection=parity_approx_layer_bucket` |
| guard, Old Manor `--order=3` | `GUARD_CHECK PASS ... guards=4 buckets=4/4 lounge=0` (Novice-labelled) |
| beams | `BEAM_GEOMETRY_SUMMARY: fails=0` — `cards=330 max_axis_err_deg=0.000006 clamped=0` |
| GC / turret / civilian | `GC_PROBE PASS` (44) · `GC_TRIGGER PASS` (21) · `TURRET_PROBE PASS` (229 actors, 1,145 parts, 0 hidden) · `W10A2_CIV_SUMMARY: fails=0 passed=22` |
| probes | doorwalk · viewmodel truth · Niagara · blackjack · geometry (7/7) |
| collision | `COL_MAPS PASS maps=3 min_coverage=0.976 dropped=0 coverage_ppm=976321` |
| lock inventory | `applied=154 containers=144 door_nodes=10 state=APPLIED` |
| `probe_leak` | clean (`TAT2_NO_DEN_PROBE=1`, `res://probe_leak.gd`) |
| E2E | **278/278**, `fails=0 passed=278 total=278` (tier 1: 117; includes `--tier=s2`) |
| `make runtime-smoke` | **PASS** (`RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 mission_ready=1`) |
| `make audit` | PASS — 12,660/12,703, 0 unexpected |
| texture cap | 797 capped / 1 alpha-critical kept / 0 offenders |
| perf guard | 78/78 |
| `make gate-ratchet` | PASS (P0a floors; raise, never lower) |

**Caveat:** no Vulkan capture since the lighting work. P0a is headless; it makes
no new pixel claim. The W9 interior numbers were measured on a frame with a
light-card slab covering half the screen and are **not** a valid interior
baseline.

## 3. Closed by P0a (previously the top defects)

- **Guards on the floor above** — `_ground_position` now rejects hits above the
  marker (2 m skip/back-fill); selection is layer/bucket-first. Guildhall
  Contract 2 has a ground-floor Lounge guard at `C_20`, all guards within 2 m of
  their own marker and ≤0.5 m off its floor ray (`marker_floor_within_0.5m=4/4`).
- **Beams 90° wrong** — `beam_card_transform()` scales the authored column 2 with
  the authored length; 330/330 cards, `clamped=0`.
- **Turrets invisible / civilian untextured and blind** — 229 turret actors now
  emit 1,145 parts (0 hidden); the civilian body/head is dressed and sight casts
  from the head (22/22).
- **W10-A2 deadlocked evidence batch** — the tracked runner keeps every Godot
  call under one lock, runs `runtime_smoke.sh` without an outer flock, uses the
  correct leak path, and covers audit/texture/perf/ratchet.

## 4. Open work (measured/recorded, not hidden)

| Defect / item | Evidence | Next step |
|---|---|---|
| **63 cream slabs** from `1m_Plane_Reverse` + `MI_EmisLight_Moonlight` | no albedo/opacity/emissive vector; loader invents white emissive | treat light cards as additive/skipped; never default white |
| **3,288 mirrored instances, winding unverified** | 1,601 floors/roofs; `MESH_RECON ... mirrored=` | one `CULL_DISABLED` capture, then compensate |
| **Landscape visibility may be inverted** | `tat_landscape.gdshader` discards `vis > 0.5`; UE convention is 1 = visible | one reference sample; do not "fix" blind |
| **Sky contributes no light** | `sky_contribution=0`, `IBL available=false` | cubemap export + consumer (W10-C) |
| **Authored −4.00 EV bias not applied** | emissives hot against a zero floor | apply the AEM curve (W10-C) |
| **Guard count** | 4/6/8 is a labelled `PORT_DECISION`; selection is `PARITY_APPROX` | live Contract 02 capture before any parity claim |
| **Beam material** | additive `tat_beam.gdshader` | P4 authored centre-line/fade |
| **GC hold-smash** | temporary `PORT_DECISION`; 95 broken layers / 79 leaves measured | authored damage path before Parity Complete |
| **Prison-door lock level** | authored `MaxLockLevel` 4, port locks at 1 (producer emits instance deltas) | producer chain resolution + regeneration on the integrator |
| **StateTree** | payload v2 emits parameters (497/566 nodes, 676 bindings, 139 templates) but the runtime still flattens nodes to names; shadow `0/21` fully evaluable | consume v2 in `tree_model`/`coverage`; never invent parameters |
| **No Vulkan capture / perf matrix** | headless only; thermal gate waived | P0b capture; no parallel Godot |

## 5. Wave plan for the next session

**P0b — capture + the 120-row baseline (do this first).** Live Vulkan Forward+
captures under Xvfb, the 120-row scorecard from
`docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md`, and an honest
per-row PASS/PARTIAL/FAIL with recorded evidence. Do not re-grade on frame
`215507`.

**W10-B — behaviour.** StateTree payload-v2 consumer (parameters/bindings →
interpreter) then navmesh/EQS; Niagara activation bridge. Audio direction if B
finishes early.

**W10-C — look.** AEM scalars/temporal model, cubemap/IBL, then the table above
(cream slabs, mirrored winding, landscape visibility).

## 6. How to run everything

```bash
build/qa/run_p0a_gates.sh    # all 28 P0a gates -> docs/reports/logs/p0a/ (no outer flock)
make run                     # native client
make test                    # run_tests (319)
tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"  # 196
tools/godot --headless --path game --script res://tests/test_m2_player.gd
tools/godot --headless --path game --script res://tests/probe_guard_positions.gd
tools/godot --headless --path game --script res://tests/probe_guard_positions.gd -- --map=old_manor --order=3
tools/godot --headless --path game --script res://tests/test_beam_geometry.gd
tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd          # 278
make runtime-smoke           # exit 124 only, ERROR: scan
make audit && make gate-ratchet
TAT2_GUARD_DIAG=1 tools/godot --headless --path game -- --qa-free-play   # guard spawn diagnostics
```

## 7. Invariants and hazards

- **Single Godot at a time.** Use `flock /tmp/opencode/tat2-godot.lock` for every
  invocation; never wrap `runtime_smoke.sh` (it takes the lock itself) and never
  run two GPUs/captures in parallel. Never edit `game/` while a run is live.
- **Generated data is produced, not edited.** `game/data/generated/` and `extracted/`
  are read-only; regenerate only at merged HEAD (`make normalize`, `make anims`), then
  `make audit-refresh-stamps REASON=…`.
- **Workers do not push.** Treat any worker push as a contract violation and
  verify `origin/main` after each merge.
- **Do not weaken a test.** Changing an expectation needs evidence the assertion
  was wrong. The ratchet floors in `tools/gate_ratchet.json` are
  minimums; raise them only from a committed log and never lower one.
- **Collision is authored `AggGeom`** (`TAT2_COLLISION=authored|aabb`); planar
  convexes are skipped; stairs are exempt from the hull cap. Do not "fix" a
  floating surface by moving the loader's grounding offsets — check the ray first.
- **Guard selection is `PARITY_APPROX`.** Bucket/layer selection is authored;
  the 4/6/8 count is a `PORT_DECISION`. Keep the `spawn_marker`, `grounded_spawn`,
  `spawn_bucket` and `spawn_layers` metas and the
  `selection=parity_approx_layer_bucket` diagnostic.
- **Beam axis is the device column 2.** `beam_card_transform()` must keep the
  0.102 m authored mesh length in the calculation, apply the authored length
  without a ceiling, and keep `BEAM_AXIS ... clamped=0`. The `MESH_RECON`
  `mirrored=` count is the winding follow-up, not a beam bug.
- **The StateTree runs in shadow** (`TAT2_STATETREE=off|shadow`): the FSM still
  drives. Payload v2 has the parameters/bindings; the runtime still flattens
  nodes to names, so `0/21` trees are fully evaluable. Do not invent parameters.
- **GC smash is a labelled port decision.** 336 hidden components / 264 actors,
  95 hidden Guildhall_Loot layers, 79 intact leaves. Tap keeps the lockpick path;
  the deliberate held-secondary break is temporary until the authored damage path.

## 8. Where the evidence lives

- `docs/reports/p0a-20261126.md` — the P0a measured table and exact lines.
- `docs/reports/logs/p0a/` — the 28 gate logs + the integrator's `normalize.log`.
- `docs/reports/logs/w10/` — the preceding W10-A run (historical).
- `docs/reports/r8-remediation-20261125.md`, `w9-remediation-20261125.md`.
- `build/qa/w10/` — W10-A report/audits and the guard investigation.
- `docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md` — 120-row scorecard.

## 9. Definition of done for the next run

```bash
git status --short                    # clean, or only intentional evidence
build/qa/run_p0a_gates.sh             # 28 gates, stops on first failure
make gate-ratchet                     # PASS against the committed p0a logs
git push origin main
```

When a gate value moves, update `tools/gate_ratchet.json`, the report it names
(`docs/reports/p0a-20261126.md` or its successor) and this file in the same
wave. Never fabricate a capture, ROI or timing: say "not verified" instead.
