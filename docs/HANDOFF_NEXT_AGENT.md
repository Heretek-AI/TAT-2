# Handoff — Thick As Thieves Godot 4.7.2 port (next session)

**Repo:** `/home/john/Projects/TAT-2`
**Code/data tip:** `dfa8c7e` (P0b: capture instruments + acceptance harness +
parity-only governance + audit re-stamp). This handoff and the P0b evidence are
the commit on top of that tip.
**Working tree:** clean apart from private/derived data, the tracked
`docs/reports/logs/p0b/full/` evidence and local untracked `.uid` sidecars
created by `--import`.
**Godot:** `4.7.2.stable` via native `tools/godot` (`godot` is **not** on `$PATH`).
**Renderer:** Forward+ · Jolt 60 Hz · 1280×720 reference · Linux x86_64.
**Steam reference:** `/home/john/.steam/steam/steamapps/common/Thick As Thieves/`.
**Single-Godot lock:** `/tmp/opencode/tat2-godot.lock` (never wrap
`build/qa/runtime_smoke.sh` or `build/qa/p0b_capture.sh` in an outer `flock`;
they take the lock themselves).

## 1. State in one paragraph

P0b built the parity instruments and measured them at the merged HEAD. The
acceptance harness registers suites 117/118/120 and runs a real Contract 02
Novice load in E2E tier `a2` (inside `all`), so `run_tests` is **322** and E2E is
**300/300**. Tier `p2` records the authored-data parity baseline as 12/12 with
one **expected FAIL** (civilian pants albedo — a producer
`BaseColorOpacity`→albedo defect). The beam material was promoted to an
authored-parameter match in P1-BEAMS (`372bf74`), so the current p2 is
`expected_fail=1 expected_delta=0`. Parity-only governance is proven: every
content-override rule
is classified, and `TAT2_PARITY_ONLY=1` excludes expansion content while keeping
every shipped record. The port capture harness (six poses, audio tap, ROI/KF27
scorer) is built and self-tested; the first six-pose port capture ran at
`5301fc6` (`docs/reports/logs/p0b/20261126T210338Z_...`). The frames confirm the
visible cream bars are the `SM_LightBeam` cards (axis fixed, full-tube material
still P4) and the exposure split (gate too dark, foyer too bright). The live
reference and 120-row baseline are still unscored; the beam material is the
top visual fix, then the live-reference score.

## 2. Gates at this HEAD (all measured, logs in `docs/reports/logs/p0b/full/`)

Run: `build/qa/run_p0b_gates.sh` on
`dfa8c7e7f9a66e24c114ee56e1e9d37ab66dc58d` (Godot
`4.7.2.stable.official.ed1daf0bf`), 18 m 39 s wall. Every gate exited 0 except
the cream proof, which is expected to exit 1; the runner stops on the first
unexpected non-zero exit.

| Gate | Value |
|---|---|
| compile | **202 checked, 0 broken** |
| `run_tests.gd` | **322 PASS, fails=0** (suites 117/118/120; 119 deliberately not registered) |
| `test_m2_player.gd` | **12 PASS, fails=0** |
| guard, Guildhall Contract 2 | `GUARD_CHECK PASS ... guards=4 buckets=4/4 lounge=1 lounge_marker=C_20 selection=parity_approx_layer_bucket` |
| guard, Old Manor `--order=3` | `GUARD_CHECK PASS ... guards=4 buckets=4/4 lounge=0` (Novice-labelled) |
| beams | `BEAM_GEOMETRY_SUMMARY: fails=0` — `cards=330 max_axis_err_deg=0.000006 clamped=0` |
| GC / turret / civilian | `GC_PROBE PASS` (44) · `GC_TRIGGER PASS` (21) · `TURRET_PROBE PASS` (229 actors, 1,145 parts, 0 hidden) · `W10A2_CIV_SUMMARY: fails=0 passed=22` |
| probes | doorwalk · viewmodel truth · Niagara · blackjack · geometry (7/7) |
| collision | `COL_MAPS PASS maps=3 min_coverage=0.976 dropped=0 coverage_ppm=976321` |
| lock inventory | `applied=154 containers=144 door_nodes=10 state=APPLIED` |
| `probe_leak` | clean (`TAT2_NO_DEN_PROBE=1`, `res://probe_leak.gd`) |
| E2E | **300/300**, `fails=0 passed=300 total=300` (T1=117 T2=110 T3=25 T4=14 S2=12 A2=22) |
| E2E tier `a2` | **22/22** standalone |
| E2E tier `p2` | **12/12**, `expected_fail=1 expected_delta=0 fixed=0 unexpected_fail=0` (pants only; beam promoted) |
| parity-only | **60/60**, 11 rules all `parity_restoration`, 0 unclassified |
| cream RED proof | **expected exit 1**, `CREAM_PROOF: RED passes=2 expected_fail=2` |
| capture harness | dry-run `poses=6` manifest valid · self-test **21/21** · KF27 reference **7/7** |
| `make runtime-smoke` | **PASS** (`RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 mission_ready=1`) |
| `make audit` | PASS — 12,660/12,703, 0 unexpected |
| texture cap | 797 capped / 1 alpha-critical kept / 0 offenders |
| perf guard | 78/78 |
| `make gate-ratchet` | PASS (`measured_on=dfa8c7e`; floors raised, never lowered) |

**Caveat:** no live reference capture. The port-side six-pose capture exists and
is measured, but it is not a parity score; the 120-row baseline still needs the
shipped reference. The W9 interior numbers were measured on a frame with a
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
| **Port capture** | six-pose run 2026-11-26 at `5301fc6` (`logs/p0b/20261126T210338Z_...`): gate 23.2/10, foyer 45.8/29, Lounge 28.6/23; audio enabled 85.3 s | live reference + 120-row score; exposure/IBL remains split |
| **120-row baseline unscored** | instruments ready; live reference prepared, nothing launched (`reports/p0b-live-capture.md`) | score the 120 rows on the parity-only build with recorded evidence |
| **Cream / invented white** | the visible cream bars are `SM_LightBeam` cards (axis fixed; full-tube material); cream RED proof `expected_fail=2`; 122 authored moon cards are safe | P4 authored beam centre-line/fade; data wave fixes `_apply_ue_emissive` + registers suite 119 |
| **Civilian pants albedo** | p2 expected FAIL: authored `Pants_D` in the `opacity` slot | producer fix (`BaseColorOpacity` → albedo), then p2 `fixed` → 1 |
| **Cream bars (retired 63 claim)** | all 122 `1m_Plane_Reverse` are hidden and `MI_EmisLight_Moonlight` resolves unshaded black; the visible bars are `SM_LightBeam` | retire the 63/moon attribution; fix the beam material (P4) |
| **3,288 mirrored instances, winding unverified** | 1,601 floors/roofs; `MESH_RECON ... mirrored=` | one `CULL_DISABLED` capture, then compensate |
| **Landscape visibility may be inverted** | `tat_landscape.gdshader` discards `vis > 0.5`; UE convention is 1 = visible | one reference sample; do not "fix" blind |
| **Sky contributes no light** | `sky_contribution=0`, `IBL available=false` | cubemap export + consumer (W10-C) |
| **Authored −4.00 EV bias not applied** | emissives hot against a zero floor | apply the AEM curve (W10-C) |
| **Guard count** | 4/6/8 is a labelled `PORT_DECISION`; selection is `PARITY_APPROX` | live Contract 02 capture before any parity claim |
| **Beam material (top visual defect)** | capture confirms broad cream bars; additive `tat_beam.gdshader` alpha 0.55/energy 1.7/full tube; p2 DELTA `dG=0.054 dB=0.117 dE=0.20` | P4 authored centre-line/fade |
| **GC hold-smash** | temporary `PORT_DECISION`; 95 broken layers / 79 leaves measured | authored damage path before Parity Complete |
| **Prison-door lock level** | authored `MaxLockLevel` 4, port locks at 1 (producer emits instance deltas) | producer chain resolution + regeneration on the integrator |
| **StateTree** | payload v2 emits parameters (497/566 nodes, 676 bindings, 139 templates) but the runtime still flattens nodes to names; shadow `0/21` fully evaluable | consume v2 in `tree_model`/`coverage`; never invent parameters |
| **Perf matrix** | thermal gate waived; headless only | no parallel Godot; do not claim 60 fps |

## 5. Wave plan for the next session

**P0b remainder — live reference + the 120-row baseline (do this first).** The
port-side six-pose capture is measured
(`logs/p0b/20261126T210338Z_...`); the live reference is still blocked on
VRAM/offline mode. Follow `docs/reports/p0b-live-capture.md`, then score the 120
rows from `docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md` on the
parity-only build, and publish an honest per-row PASS/PARTIAL/FAIL with recorded
evidence. Do not re-grade on frame `215507`.

**W10-B — behaviour.** StateTree payload-v2 consumer (parameters/bindings →
interpreter) then navmesh/EQS; Niagara activation bridge. Audio direction if B
finishes early.

**W10-C — look.** The beam material is the top visual defect confirmed by the
capture (authored centre-line/fade), then AEM/IBL/EV bias, mirrored winding and
the landscape docs/A-B.

## 6. How to run everything

```bash
build/qa/run_p0b_gates.sh    # 35 gates + cream RED -> docs/reports/logs/p0b/full/ (no outer flock)
make run                     # native client
make test                    # run_tests (322)
tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"  # 202
tools/godot --headless --path game --script res://tests/test_m2_player.gd
tools/godot --headless --path game --script res://tests/probe_guard_positions.gd
tools/godot --headless --path game --script res://tests/probe_guard_positions.gd -- --map=old_manor --order=3
tools/godot --headless --path game --script res://tests/test_beam_geometry.gd
tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd          # 300
tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=a2
tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=p2
tools/godot --headless --path game --script res://tests/test_parity_only.gd            # 60/60
tools/godot --headless --path game --script res://tests/test_w10a2_cream.gd            # expected exit 1
build/qa/p0b_capture.sh --dry-run && build/qa/p0b_capture.sh --self-test
build/qa/p0b_capture.sh       # real Vulkan capture, one GPU job, after the gates
make runtime-smoke           # exit 124 only, ERROR: scan
make audit && make gate-ratchet
TAT2_GUARD_DIAG=1 tools/godot --headless --path game -- --qa-free-play   # guard spawn diagnostics
```

## 7. Invariants and hazards

- **Single Godot at a time.** Use `flock /tmp/opencode/tat2-godot.lock` for every
  invocation; never wrap `runtime_smoke.sh` or `p0b_capture.sh` (they take the
  lock themselves) and never run two GPUs/captures in parallel. Never edit
  `game/` while a run is live.
- **A fresh worktree needs `--import` once.** A copied `game/.godot` does not
  know a new global `class_name`: compile fails with `Identifier
  "ParityGovernance" not declared` and `test_parity_only.gd` says `GameState
  autoload missing`. Run `tools/godot --headless --path game --import`; it writes
  only gitignored state and local `.uid` sidecars.
- **Generated data is produced, not edited.** `game/data/generated/` and `extracted/`
  are read-only; regenerate only at merged HEAD (`make normalize`, `make anims`), then
  `make audit-refresh-stamps REASON=…`.
- **Workers do not push.** Treat any worker push as a contract violation and
  verify `origin/main` after each merge.
- **Do not weaken a test.** Changing an expectation needs evidence the assertion
  was wrong. The ratchet floors in `tools/gate_ratchet.json` are
  minimums; raise them only from a committed log and never lower one.
- **Parity-only is a governance flag, not a fork.** `TAT2_PARITY_ONLY=1` may only
  drop `tat2_expansion` classes; the 11 content-override rules are all
  `parity_restoration` and an unclassified rule must fail closed. `a2`/`p2` and
  the 120-row baseline must state which build they used.
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

- `docs/reports/p0b-20261126.md` — the P0b measured table and exact lines (current).
- `docs/reports/logs/p0b/full/` — the 35 gate logs + the cream expected failure.
- `docs/reports/p0b-harness.md` — the Lane H acceptance-harness report.
- `docs/reports/p0b-live-capture.md` — live-reference prep and blockers (no launch).
- `docs/reports/p0a-20261126.md` + `docs/reports/logs/p0a/` — the preceding P0a run.
- `docs/reports/logs/w10/` — the W10-A run (historical).
- `docs/reports/r8-remediation-20261125.md`, `w9-remediation-20261125.md`.
- `build/qa/w10/` — W10-A report/audits and the guard investigation.
- `docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md` — 120-row scorecard.

## 9. Definition of done for the next run

```bash
git status --short                    # clean, or only intentional evidence
build/qa/run_p0b_gates.sh             # 35 gates + cream RED, stops on first unexpected failure
make gate-ratchet                     # PASS against the committed p0b/full logs
git push origin main
```

When a gate value moves, update `tools/gate_ratchet.json`, the report it names
(`docs/reports/p0b-20261126.md` or its successor) and this file in the same
wave. Never fabricate a capture, ROI or timing: say "not verified" instead.
