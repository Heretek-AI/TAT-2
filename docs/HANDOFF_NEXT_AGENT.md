# Handoff — Thick As Thieves Godot 4.7.2 port (next session)

**Repo:** `<repo>` · **Current tip:** `9c811a5` (`main`).
**Phase 3 merge:** PR #16 → `c015567`; docs tips #17 `facf6bd`, #18 `9c811a5`.
**Measured code/gate head:** `900f8eb` (route-code merge); the final **59-gate**
run was made at `5337828` (logs commit `0f6942c`). The post-gate repo-hygiene
commit `95247fb` touches docs, QA scripts and workflows only; compile **234/0**
and E2E **310/310** were re-run on it.
**Godot:** `4.7.2.stable` via native `tools/godot` (`godot` is **not** on
`$PATH`). Forward+ · Jolt 60 Hz · 1280×720 base · Linux x86_64.
**Working tree:** clean.
**Read first:** this is the post-Phase-3 handoff. Final gate evidence:
[`docs/reports/phase3-final-gates-20261128.md`](reports/phase3-final-gates-20261128.md);
GPU: [`docs/reports/phase3-gpu-20261128.md`](reports/phase3-gpu-20261128.md);
route partial: [`docs/reports/phase3-played-route-instruments.md`](reports/phase3-played-route-instruments.md).
The previous long handoff is archived at
[`docs/reports/handoff-archive-20261128.md`](reports/handoff-archive-20261128.md).

**`main` is PR-gated.** The `keep summer safe` ruleset requires a pull request
plus the `hygiene / No machine-local paths` and
`hygiene / Workflow syntax and security` checks (Sonar and CodeQL also run).
A direct `git push origin main` is rejected — always land through a PR.
`zizmor.yml` scopes one cosmetic ref-comment check to the two org reusable
workflows; the security audit itself still runs.

---

## 1. Where the project stands

| Item | State |
|---|---|
| Phase 3 tasks | **15/16 verified** (worker + verifier + falsifier + security-auditor each) |
| `played-route` | **blocked** — documented partial, `route_claim=none`, branch unmerged |
| Final gate | **59/59 exit 0** at `5337828`; `measured_on=900f8eb` |
| Pre-merge security audit | **PASS** (0 Critical/High; 2 Medium, 7 Low) |
| Independent victory audit | **VICTORY CONFIRMED 18/18** (R18 via its blocked branch) |
| `teamwork_final_verify` | **FAIL** by construction (blocked task); 8 reasons, all `played-route` |
| `main` | `9c811a5` — carries the 15/16 verified work; route branch separate |

The task-level final gate is **not** green and must not be described as green.
It cannot pass while `played-route` is blocked and has no verifier/falsifier/
auditor wave. Nothing was relabelled. The merge to `main` was the operator
decision after the victory audit confirmed the requirements.

**Run artifacts:** `.opencode/teamwork/20261127-1810-phase3/` — `final.md`,
`OPEN_ISSUES.md` (240 lines), `verify/final.json`, `GATE_STATUS.md`,
`verify/victory.json`, `verify/security-audit.json`, handoffs, specs.

## 2. What landed in Phase 3

| Area | Delivered | Evidence |
|---|---|---|
| Gate integrity | 59-gate runner; every runner gate bound; 40 orphan tests classified (39 retired + 4 registered); errscan marker/footer/min totals; ratchet fail-closed on missing/zero/duplicate keys; P1_BEAMS contract refreshed | 59/59 at `5337828` |
| Look | KF27 wide **5/9** and pinned **5/9**; framing solved (card at 18.0/40.0), four failures are **beam material** (band 38.80, six bands, glow, core saturation). Landscape `gap_view` A/B measurable (RMSE 1.0077 vs 0.0769). AEM residual **0.000 EV** at a **2.14 EV** anchor gap (default `fixed`). IBL ambient **0.001540** vs 0.16 (not a win; default `off`). UI `#636EEC` renders `#636eec`; prompt contrast **3.03–4.32** = UI2-03 DELTA | `phase3-gpu-20261128.md` |
| Systems | StateTree default `off`, `patrol` fail-closed, census **92** (3 enter + 89 transition), 1/17 events; nav v2 **78/2 · 60/4 · 4/0**, door audit, prison blocked both ways, `NAV_DELTA` 22/0; audio rain converter, VO **288/645** (357 tabulated), 3 keys/24 buses unrecoverable, `FS_Layers` double-ban refuted; GC **93 fallback confirmed**; **Cleanout first-class** (3300 s `mission_row`, safe room, no Contract 2 credit) | lane reports + 59-gate logs |
| Route instruments | deterministic input driver (0 transform writes), 27→120 scorer (120 rows/27 beats), telescope L4-13 fixed (`DEN_WINDOW 44/0`), NPC re-measure 85.4–150.7 m | `phase3-played-route-instruments.md` |

## 3. The blocked played route — the Phase 3C backlog

`route_claim=none`; **11/27 beats** captured (6 driven + 5 partial + 3 blocked +
4 unreachable + 9 not attempted), **45/120 rows**, `tokens_emitted=0`. Measured
content blockers:

- **S12**: authored spawn settles at y **23.1585** vs dressing floor **25.0**.
- **S13**: local safe-room area only **5.81 m**; KF16 car **128.7 m**, KF15 alley **153.4 m**.
- **S06**: ledger `Area3D` 0.89 m above the floor; walk reach **1.9348 m** vs **1.75 m**.
- **S19/S20/S22/S23**: NPCs **85.4–150.7 m** (nearest 85.4 m; 0 within 30 m).

These are content/placement defects, not driver/scorer defects. Fixing them and
re-running the driver + scorer is the first task of the next wave.

## 4. Next wave — recommended order

1. **Phase 3C route content** (highest value): fix S12 spawn/floor, S13 area and
   KF16/KF15 reach, S06 ledger placement/reach, S19/S20/S22/S23 NPC placement.
   Re-run `build/qa/route_driver.sh` and the 27→120 scorer; only claim a played
   route when the beats are driven and tokens are emitted. Acceptance: 27/27
   beats, or explicit measured blockers with `route_claim=none`.
2. **KF27 beam material**: the four failing terms are in the `MI_LightBeam_SM`
   additive path (band 38.80, six bands, glow falloff, core saturation p95 88).
   `MI_LightBeam_SM` is the deliberate exception to the HDR neon path (T2-04-C);
   do not delete the negative controls.
3. **Look decisions**: AEM anchor (fixed path is 2.14 EV brighter; either find
   the authoritative anchor or record `fixed` as the decision), IBL stays `off`,
   UI prompt contrast DELTA needs owner adjudication (floor 4.5 unchanged).
4. **Owner lane #13**: UI adjudication, perf/export — needs the owner; out of
   agent scope until then.
5. **Cleanups**: SEC-01 (below), SEC-05 measured-vs-pinned prose, root
   `summary*.md` files, evidence cap, `--generating-poststamp` binding.

## 5. Open issues

The full ledger is `.opencode/teamwork/20261127-1810-phase3/OPEN_ISSUES.md`.
Highest-value entries:

- **Played-route blockers** (S12/S13/S06/NPC) — §3.
- **KF27 beam material**; **AEM anchor**; **IBL off**; **UI prompt DELTA**.
- **SEC-01 (Medium)**: `build/qa/route_driver.sh:47,62` validates `--tag` with a
  line-anchored `grep -Eq '^[A-Za-z0-9._-]+$'`, so a multi-line value passes.
  Fix with a `case`/`grep -z` check; SEC-02/03 are related Low findings in
  `p0b_route.sh` / `route_driver.gd` (operator CLI, not runner-reachable).
- **SEC-05 (Low)**: the final report row now records `482–495/495`, but
  `tools/gate_ratchet.json`'s `source` prose still states `0/2 + 495/495` as if
  measured. The pins themselves (`e2e_a2 0..2`, `run_tests 482..495`) are correct.
- **SEC-07**: `--generating-poststamp` skips one poststamp binding by design;
  nothing binds the artifact to a specific run.
- **SEC-08**: `make audit` runs `manifest_audit` without `--require-usmap`; in a
  worktree the extraction provenance can be skipped.
- **SEC-09**: tracked evidence logs embed absolute local paths/hostnames; the
  hygiene scan excludes recorded evidence on purpose, so this stays a Low.
- **Victory-audit findings**: `71417ad` relaxed one synthetic `probe_p1_beams`
  source-text assertion; 1/17 authored `StateTreeEvent` tags emitted; 9/27 beats
  unattempted behind S13; three `summary*.md` at the repo root; the final run
  started with 65 uncommitted log files (source clean, logs committed after).
- **Evidence cap**: `verify/evidence` held 37 files against the engine's 32-file
  cap; later waves cite the report only (valid for the strict gate).

## 6. Current gate set (59) — values to keep

Measured at `5337828` / `900f8eb`; floors raise, never lower.

| Gate | Value | Gate | Value |
|---|---|---|---|
| compile | 234 / 0 | run_tests | 329 / 0 |
| M2 | 12 / 0 | E2E | 310 / 310 (T1=117 T2=110 T3=25 T4=14 S2=22 A2=22) |
| parity-only | 60 / 60 | cream 119 | GREEN passes=5 |
| audio 121 | 135 / 0 | VO 122 | 60 / 0 |
| AEM 123 | 77 / 0 | cubemap 124 | 51 / 0 |
| P5 UI | 54; `GEM_PAYLOAD layers=21` | P1 safe/doors/beams/ward/street | 86 / 49 / 9 / 44 / 31 |
| landscape mask | 7 / 0 | nav runtime | 97 / 0 (78/2, 60/4, 4/0) |
| GC destruction | 55 / 0 (`fallback_broken=93`) | collision | `min_coverage=0.869 coverage_ppm=868852 dropped=0 planar_skipped=2` |
| locks | 162 (152 containers + 10 doors) | gate manifest | 112 tracked / 73 reachable / 39 retired / 0 orphans |
| Den spawn / window / route NPC | 9 / 44 / 4 | capture dry-run / self-test | 9 poses / 23 |
| KF27 reference | 9/9 reference-only (port 5/9) | route self-test | 62 / 0 |
| runtime smoke | exit=124 errors=0 `mission_ready=1` | e2e_errscan | `31/33 + 0-1/2 + 482-495/495 new=0` |
| audit | 12664/12703 (floor 12660), 0 unexpected | texture cap | 1567 / 796 / 1 / 0 |
| string audit | 311 routed / 199 authored / 112 invented | perf guard | 78 / 78 |
| gate ratchet | 59 gates / 60 bindings | | |

Commands:

```bash
build/qa/run_final_gates.sh          # 59 gates, serial; no outer flock
tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"
make test                            # run_tests.gd, 329 checks
tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd
make audit                           # incl. string-audit + check-greps
make gate-ratchet                    # floors + committed logs agree
```

A fresh worktree needs `tools/godot --headless --path game --import` once; a
missing import cache fails `T1-01-C` with `moon_visible=0.0`. If `make audit`
fails on the extractor binary being older than `Exporter.cs`, run
`make build-extractor` (build artifact, not a source change).

## 7. Machine, CI and data state

- **WIP branches on `origin`:** `wip/phase3-audio-20261127`,
  `-baseline-20261127`, `-gpu-session-20261128`, `-look-code-20261127`,
  `-nav-20261127`, `-statetree-20261127` are contained in `main`;
  `wip/phase3-played-route-20261128` (`ac7b3b2`, +3 commits) is the blocked
  branch and stays unmerged. The gate-integrity WIP branch was auto-deleted on
  merge.
- **Extracted content** (`extracted/`, `game/assets/ue/`,
  `game/data/generated/`, `build/` artifacts, `game/.godot/`) is git-ignored and
  private. Never commit it. Regenerate with the producers, never hand-edit.
- **Steam reference:** `~/.local/share/Steam/steamapps/common/Thick As Thieves/`
  (appid `3341000`, build `25076818`, `1.5.148559`).
- **GPU:** one Godot at a time; the host currently measures **125 W** (max 140),
  not the old 80 W. `TAT2_AEM=fixed` and `TAT2_IBL=off` remain the defaults;
  `TAT2_NAV=off` and `TAT2_STATETREE=off` remain the defaults (no cutover).

## 8. Traps to carry forward (top 10)

1. `godot` is not on `$PATH`; use `tools/godot` (native 4.7.2).
2. Never edit `game/` while a Godot process is running.
3. Do not weaken/skip/delete a test or a ratchet floor to go green; record the
   defect with evidence instead. Floors raise, never lower.
4. `A2-WHITE` samples mesh surface materials, not `material_override` — bind the
   material on the surface as well (`SafeRoomPortalOutline` example).
5. `MI_LightBeam_SM` is the intentional additive-beam exception to the HDR neon
   path (T2-04-C); keep its negative controls.
6. StateTree is shadow-only, default `off`; nav is default `off` and consumes the
   authored links (78/2 Guildhall, not 221 raw records). No cutover without the
   producer contract.
7. The light budget is per-room fair (160 slots per 16 m bubble), not a global
   energy cut; candle lights are 0/135 by design.
8. `export_presets.cfg` must not contain `#` comments (Godot's `ConfigFile`
   parser merges them into the next key).
9. A HUD `SubViewport` must set `own_world_3d = true` or its lights leak into
   the gameplay `World3D`.
10. The run clock has two phases (`main` → `endgame`); an endgame timeout still
    banks the stashed haul, and every failure path owes exactly one payout.

## 9. Evidence map

- Final 59-gate table: `docs/reports/phase3-final-gates-20261128.md`; logs in
  `docs/reports/logs/final/`.
- GPU look results: `docs/reports/phase3-gpu-20261128.md`.
- Route instruments + blockers: `docs/reports/phase3-played-route-instruments.md`.
- Phase 3 baseline (historical): `docs/reports/phase3-baseline-20261127.md`.
- Fidelity tracker: `docs/FIDELITY_GAPS.md` (Phase 3 final section at the top).
- Run evidence: `.opencode/teamwork/20261127-1810-phase3/verify/` and `final.md`.
- Operating rules and the full trap list: `AGENTS.md`.

## 10. Definition of done for the next wave

```bash
git status --short                       # clean
build/qa/run_final_gates.sh              # 59/59 (or more), no expected failure
make audit                               # exit 0
make gate-ratchet                        # PASS at the new measured_on
```

Then, in the same wave:

- update `docs/FIDELITY_GAPS.md`, a `docs/reports/<wave>.md` with measured
  evidence, and this handoff (HEAD, gates, open work);
- raise the ratchet floors to the new measured values and re-stamp
  `measured_on`;
- land through a PR so the `hygiene / *` checks run;
- leave `played-route` unmerged unless the beats are actually driven and
  tokens are emitted — a partial is reported as a partial.
