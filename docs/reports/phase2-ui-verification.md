# Phase 2 UI lane — independent verification, round 2 (2026-11-27)

**Lane.** Worktree `/home/john/.local/share/opencode/worktree/318f41/phase2-ui`,
branch `w10/phase2-ui`, fix commit
`8a191448aa93aa4580c5f6604b1d07658547d118` (parent `8efa27b`; base `79d8b8a`).
Plan: `docs/reports/next-phases-plan-20261127.md` §5 (U-1/U-2/U-4). Lane
reports: `docs/reports/phase2-ui-20261127.md` (now updated by the fix commit)
and this file.

**Method.** Read-only except this report. Headless Godot was run serially under
`flock /tmp/opencode/tat2-godot.lock`; no Vulkan, Xvfb, Steam or GPU process was
started. The extractor was built in a `/tmp` copy with the Makefile's .NET SDK.
The worktree was clean before the report was written; after this file it is the
only untracked path. Nothing was pushed.

**Verdict: PASS (lane scope).** All five round-2 blockers are fixed and
independently re-run. The only non-green items are outside the U-4 code: the
expected audit drift (5 lane baseline/output stamps plus one external stale
materials group) and the integrator-owned final-runner update (the literal
`checks=44` marker and the `make test-producers`/capture-test registration);
the full 45-gate set is therefore **not claimed green**. The real 21-slice
decode and every GPU pixel remain unverified, as before.

## 1. Blockers — all fixed

| # | Blocker | Verdict | Evidence (re-run) |
|---|---|---|---|
| 1 | `GEM_PAYLOAD` evidence line existed only as prose | **PASS** | `probe_p5_ui.gd:74-78` one `_gem_payload_line` formatter; called in the present branch (`:323`), the `status!=payload_present` branch (`:328`) and the absent branch (`:331`). This tree printed exactly `GEM_PAYLOAD present=false: layers=0 table=0 kind= slice=-1 missing=[]` and the retained absence line; `P5.11k` printed `PASS: … GEM_PAYLOAD format pinned`; `P5_UI PASS checks=54`. The `present=true` shape is asserted by `fmt_ok` inside P5.11k (`:285`, `begins_with("GEM_PAYLOAD present=true: layers=21 table=21 kind=area_ramp slice=17 missing=[]")`). Docs now show both shapes. |
| 2 | `ui_pixel_stats.py` not executable | **PASS** | `git ls-files -s` → `100755`; `stat -c %a` → `755`; direct `./build/qa/ui_pixel_stats.py --help` → exit **0**. |
| 3 | `P5_ONLY` fail-open | **PASS** | `build/qa/test_capture_p5_ui_filter.sh` is tracked `100755`; run → `CAPTURE_P5_FILTER_TEST PASS checks=5`, exit 0: unknown name exits **2** with `P5_CAPTURE FAIL unknown shot=… known=…` and no `P5_CAPTURE_SIZE` (before the shot loop), `ledger_market` is accepted and reaches the loop (headless capture refused, exit 1). Code: validation at `capture_p5_ui.gd:619-627`; Den condition includes `ledger_market` at `:661`; `_shot_ledger` guards the journal frame at `:401` and accepts the market path. |
| 4 | .NET wording | **PASS** | `~/.dotnet10/dotnet --list-sdks` → `10.0.404`; `DOTNET_ROOT=$HOME/.dotnet10 … dotnet build -c Release` on the current `tools/tat-extract` → **0 Errors**, 15 warnings (pre-existing NU1902/NU1903 + `Program.cs:90` CS8603). Report line 4/144/165 and `FIDELITY_GAPS.md:1372` now say the build is proven; only the real decode needs the shipped game. |
| 5 | Gap fixes | **PASS** | `pause_backdrop` is in the §5 GPU command (`docs/reports/phase2-ui-20261127.md:194`) and the `--require` examples; `--strict` fails a pause frame without a same-size backdrop — a synthetic 240×160 pause-only capture exits **1** with `pause has no pause_backdrop at 240x160` (`ui_pixel_stats.py:640-648`). Single-mip `filter_linear` and the `BLEND_TranslucentGreyTransmittance` → straight-alpha approximation are documented in `hud.gd` (`:172-180`), `FIDELITY_GAPS.md:1357-1361` and the lane report (`:45-53`). Rec. 709 replaced the ITU-R 601 label in the producer (`:18`, `:259`) and pixel scorer (`:73`, `:360`). `mapping.selection = {kind: "derived-approx", angle_weight: 0.35, source: "port_decision", …}` is in `_empty` (`:249`) and `_build` (`:372`); the HUD reads it in `_normalise_gem_mapping` (`hud.gd:3444-3451`) and consumes it in `gem_slice_for` (`:3543`). |

## 2. Re-run evidence (headless, current worktree)

| Gate | Result |
|---|---|
| `tools/check_scripts_compile.gd` | `scripts checked: 217, broken: 0`, exit 0 |
| `make test` (`run_tests.gd`) | `SUMMARY: fails=0`, exit 0 (incidental `ERROR: Parameter "fd" is null.` log lines; no test failure) |
| `probe_p5_ui.gd` | `P5_UI PASS checks=54`, exit 0; exact payload lines below |
| `tools/test_stealthball_array.py` | `STEALTHBALL_ARRAY_TEST PASS checks=22` |
| `tools/test_ui_pixel_stats.py` | `UI_PIXEL_STATS_TEST PASS checks=15` |
| `build/qa/test_capture_p5_ui_filter.sh` | `CAPTURE_P5_FILTER_TEST PASS checks=5` |
| `make test-producers` | exit 0; both 22 and 15 suites PASS |
| `make string-audit` | `UI_STRINGS total=311 routed=311 authored=199 routed_authored=199 invented=112` / `GATE PASS` |
| `make audit` | `AUDIT FAILED: 6 failure(s)` = the **5 expected lane items** (missing `gen:ui/stealthball_array.json`, missing producer baseline, `Makefile`, `Exporter.cs`, `Program.cs` hashes) **plus** `stale generated group materials` — external: `extracted/assets/TAT/Content/Cubemaps/{daylight,t_fake_specular1}` are 2026-11-27 13:03 while `game/data/generated/materials.json` is 2026-11-26 22:16. All content groups `OK`; coverage `12660/12703`, `unexpected 0`. |
| `make texture-cap-check` | `targets: 1567`, `capped: 796`, `alpha-critical: 1`, `offenders: 0`, exit 0 |
| `make gate-ratchet` | `PASS` (re-run; baseline and committed evidence agree); `tools/test_manifest_audit.py` 18 groups; consumers/greps PASS |

Exact probe output in this tree (payload absent):

```
GEM_PAYLOAD present=false: layers=0 table=0 kind= slice=-1 missing=[]
GEM_PAYLOAD absent (extractor/producer not run); PORT_APPROX retained
PASS: P5.11k authored payload absent: binding covered by the synthetic 21-slice test; GEM_PAYLOAD format pinned
P5_UI PASS checks=54
```

After the integrator regenerates the payload, the same formatter prints the
`present=true` shape (asserted by `fmt_ok`); the report and `FIDELITY_GAPS`
show the line the code can now print.

## 3. Remaining, outside this lane

1. **Final-runner marker.** `build/qa/run_final_gates.sh:328` still passes the
   literal `"P5_UI PASS checks=44"` and the runner does not register
   `make test-producers` or `build/qa/test_capture_p5_ui_filter.sh`. The fix
   report explicitly assigns this to the integrator (`phase2-ui-20261127.md`
   §6, "Gate-set note"). Until it is updated — `checks=54`, or `gate_marker_re`
   with `checks=[0-9]+`, plus the two cheap tests — the full 45-gate run will
   fail at `probe_p5_ui`. This is an integrator gate-set action, not a U-4 code
   defect.
2. **Audit drift.** The five lane stamps and the external cubemap-driven
   `stale generated group materials` line clear when the integrator regenerates
   `make extract` / `make normalize` and refreshes the audit stamps. This lane
   never wrote `extracted/`.
3. **Real payload / GPU.** No extractor run (no shipped game/Steam), so the
   real 21-slice decode, the real `mapping.kind` and every GPU PNG/pixel metric
   are still unverified. The capture harness and `ui_pixel_stats.py` remain the
   integrator's GPU step. No 120-row token was moved.

## 4. Scope and commit

The fix commit touches 8 tracked files: `build/qa/{capture_p5_ui.gd,
test_capture_p5_ui_filter.sh, ui_pixel_stats.py}`,
`docs/{FIDELITY_GAPS.md,reports/phase2-ui-20261127.md}`, `game/src/ui/hud.gd`,
`game/tests/probe_p5_ui.gd`, `tools/parse_stealthball_array.py`. No
`game/data/**`, `extracted/**` or `game/assets/**` file is committed; P4, audio,
GC and nav are untouched. This verification report is the only file in its
commit (docs-only); the branch has no upstream and nothing was pushed.

**HEAD after this report:** the report commit SHA is printed in the hand-off
message; `git show --stat` must list exactly this file.
