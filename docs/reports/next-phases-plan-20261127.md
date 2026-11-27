# TAT-2 next phases — execution plan (2026-11-27)

**Status:** HEAD `912a481` = `origin/main`; **measured gate baseline `912a481`
(45 gates, Phase 0b)**; working tree clean after the Phase 0b evidence commit.
**Phase 0a executed:** 2026-11-27, no GPU — save `976f8730…` restored (774 files), docs/gate numbers aligned, provenance moved to `docs/reference/`, route self-test gate added (45-gate runner), V6-03 official erratum recorded, issues #2–#11 triaged. Phase 0a is not a visual/parity result.
**Phase 0b executed:** 2026-11-27, GPU headless Xvfb — clean route2 at `912a481`
(`status=captured`, `git.dirty=false`, 13 captured / 14 deferred / 0 partial /
17 frames / 18 PNGs), then the first full **45/45** serial gate set at the same
HEAD; the ratchet is re-stamped `measured_on=912a481` and
`p0b_route_self_test=62` is a floor. Evidence:
[`final-20261127-phase0b.md`](final-20261127-phase0b.md).
**Source:** four read-only lanes (repo audit, P4 look, navmesh + StateTree, remaining systems). Their findings are summarised in §1; the work packages in §2–§6 are the execution contract.
**Owner decisions (2026-11-27):** Phase 0 first; P4 meter = `CompositorEffect`; mirrors = baked mesh variant; 120-row mission = **official Cleanout (`LootTheRoom`, `free_play=false`)**; restore the `976f8730…` save now; move adjudication provenance under `docs/reference/`; run audio + GC in parallel; triage all open issues.

---

## 1. Baseline — what is true, and what is not

### 1.1 The gate evidence is solid

The 44-gate set at `5135f53` matches the committed logs: compile **217/0**, `run_tests` **324/0** (suites 119 + 121), M2 **12/0**, E2E **300/300** (T1=117 T2=110 T3=25 T4=14 S2=12 A2=22), p2 **14/14** `expected_fail=0`, parity-only **60/60**, cream **GREEN 5**, audio **71/0**, P5 **44**, Den **9**, P1 probes **86/47/7/44/31**, guards C_20/order-3, collision **868852 / 0.869** `no_record=0`, locks **154**, StateTree **191/0**, navmesh spike **2,958 / 14,930 / 221**, runtime smoke **124/0/1**, audit **12660/12703**, texture **796/1/0**, perf **78/78**, ratchet PASS. `check_gate_ratchet.py` still passes at HEAD; no `game/` code changed after `3d62f6b`.

### 1.2 Truth gaps (fix before anything else)

| Gap | Evidence | Action |
|---|---|---|
| Live save is `369e20d0…` (02:00:54), not the `976f8730…` archive | prefix `SaveGames/` vs `SaveGames.pre-p0b-20261126-230522/` | restore `976f` explicitly; never `stage` + `tail -1` |
| README reports the W9 tip (186 scripts / 314 checks / 278 E2E / suites 111) | `README.md:12,19-24,58` | 217 / 324 / 300 / 12660 / 121 |
| Handoff header still points at `3d62f6b`; §7 omits `p0b-route-rescore.md` | `docs/HANDOFF_NEXT_AGENT.md:4-6,323-339` | `a9ac606`; add the rescore + live-ref plan/lanes |
| `p0b-live-capture.md` says 771 files / empty `SaveGames/` | prefix is 774 files with a save | update the state and restore wording |
| P4 beam “thin line, no cream” is contradicted by route2 at the same pose | `p0b-route-rescore.md:190-220` vs `HANDOFF:211-212`, `FIDELITY_GAPS:230` | qualify both docs; re-measure in P4 |
| `row_route_matrix.md` + `ADJUDICATIONS.md` are gitignored | `.gitignore:25`; scorecard/rescore depend on them | moved under `docs/reference/` (Phase 0a); references updated |
| New QA code is ungated | `build/qa/p0b_route.gd` 2,155 lines; not in compile/44 gates | add a route self-test gate; log the wrapper exit |
| route2 is `git.dirty=true` at `4341439` | route2 manifest | clean re-run at the current HEAD (Phase 0b) |
| V6-03 official cell says `y~56 %`, two beams, cyan ceiling diamond | `COMPARISON_PORT_20261124.md:92` | dated erratum: 17.8 %/40.0 %, one band, above-door node; 120 tally unchanged |
| 10 open issues #2–#11 untriaged | `gh issue list` | triage all; link #13 |
| Mirror `3,312/3,215`, “645 VO”, landscape “likely correct”, rooftop near-black are carried, not re-measured | handoff/FIDELITY_GAPS | label UNVERIFIED or measure in the owning lane |

### 1.3 P4 look (the visible gap)

- **Exposure:** authored `AEM_Basic`, EV100 −10…+1, SpeedUp 0.2 / SpeedDown 2.0, bias 0, `Curve_Exposure_Compensation_Float_V3` (already in `curves.json`). The producer drops six fields; the port applies a constant 1.15. Plan: pure `step(dt, ev100)`, one global calibration, `TAT2_AEM=fixed` preserved; meter `CompositorEffect`; no per-room grade.
- **IBL:** `Cubemap_GroundFloor_01` is 512² `PF_FloatRGBA` in the dump; the extractor has no `UTextureCube` branch. Plan: `AT_CUBEMAP_PASS` producer + `parse_cubemap`; stage-1 CPU cosine irradiance into ambient colour/energy; stage-2 sky radiance optional (visible-sky conflict); no authored rotation.
- **Mirrors:** cull flip is per owning `GeometryInstance`; `MultiMeshInstance3D` has no surface override. Plan: bake a mirrored mesh variant (reverse winding/normals/tangents), `CULL_FRONT` fast path only for single-surface `BaseMaterial3D`; synthetic 3-object probe.
- **Landscape:** keep `vis > 0.5`; raw-mask A/B and data assertion before any flip.
- **Beams:** authored sphere-mask/edge/fake-glow terms unimplemented; `beam_close` is the Lounge C_57, not KF27; add `foyer_beam` `(27,29.67,-55)→(23.27,29.76,-57.4)`; KF27 is **one** band 40.0–40.5 %, emitter 17.8 %/40.0 %; gold bulb vs white is likely exposure.

### 1.4 Navmesh + StateTree

- **221 off-mesh records → 80 logical links** (123 exact pairs, collinear merge); **63 = `NavArea_Default` and Recast null** (14,558 polys); areas are per-map (Guildhall Door=4/Bushes=3; Old Manor Door=3/Bushes=4).
- `nav_steering` is already wired; adding a region changes all guard/civilian movement — enable behind `TAT2_NAV=off|on`.
- Door links from the leaf midpoint + normal, enabled at `open_angle_deg() > 70`, not the co-located `NavLinkFront/Back`.
- `ST_Patrol` loop needs no new parameter data; `ResetAlertness` is schema-only; event bus/smart objects are separate (deferred).
- Producer + asset first (Guildhall/Old Manor/FTUE), then region, links/doors, default, parity probe, opt-in cutover; no `ST_Guard` cutover.

### 1.5 Audio / GC / UI

- **Audio:** 645 authored VO lines; only 4 pins; music decision keys 6/9; `FS_Layers` never set; 183 state-row refs on unnamed buses; 136 room beds blocked on T09. W11-A VO director, W11-B music, W11-C `FS_Layers`, W11-D RTPCs, W11-E state report, W11-F serialized Master tap.
- **GC/bookcases:** 8 Guildhall bookcases + 8 safes are dropped by the class filter; 93-chest `_Broken` fallback is correct; bookcase leaves/multi-door owner index; `Destructibles/` needs the extractor `json` pass.
- **UI:** P5 headless only; 21-slice gem array record present, payload absent; GPU capture + pixel metrics + adjudication; string ceiling stays 112.

### 1.6 120-row / live / data / perf

- The 120-row tally is **48 scored / 56 N/A / 16 UNVERIFIED**; the staged route2 is **not** a played route; the live 2026-11-27 capture is the Staff mission, not the Cleanout.
- The official KF27 cell is wrong (56 %/two beams/ceiling); the port-side V6-03 text is stale too.
- `make extract` has no `json` stage; `Destructibles/` absent; export is stale and unstamped; the perf matrix is not at the shipped lens; `audio_mix.json` is an unregistered expansion overlay.
- **Owner-dependent:** the Cleanout live reference (#13), a played port 120-row run, a UI visual score, the perf matrix thermal waiver, the store/export.

---

## 2. Phase 0a — truth, save and gate hygiene (no GPU)

**Goal:** make the repo’s stated state true and gate the new QA, so the later lanes cannot inherit a false baseline.

### 0a.1 Save baseline

- Restore `SaveGames.pre-p0b-20261126-230522/.` into `/tmp/opencode/tat2-ref-prefix/pfx/drive_c/users/steamuser/AppData/Local/TAT/Saved/SaveGames/`.
- Verify `TAT_ETS.sav` md5 `976f8730eac989bab1c6c792343b7c00`; keep the archive; never run `stage` + `tail -1`.
- Update `docs/reports/p0b-live-capture.md` (774 files, save present, explicit restore), handoff §0, and issue #13’s checklist.

### 0a.2 Docs truth

- `README.md`: 217 scripts / 324 checks / 300 E2E / 12660 audit / suites 121.
- `docs/HANDOFF_NEXT_AGENT.md`: header `a9ac606`; §7 add `p0b-route-rescore.md` + live-ref plan/lanes; save state; beam qualification; route2 dirty; cite #13; the 10 issues; the 120 tally note (“predates W10; V4-07/V6-03 re-scored in W9-P1”).
- `docs/FIDELITY_GAPS.md`: valid Cleanout reference pending (not “none”); beam claim qualified with the route2 numbers; gem “record present, payload absent”; mirror/landscape unverified.
- `docs/reports/live-ref-review-verification.md`: remove the stale UI4-05/S27 note.
- `docs/reports/p0b-live-capture.md`: 774 files; save; disk 126 G / `~/Videos` 52 G / `/tmp` 9.1 G; 900 s; audio 80; save restore.
- `docs/reports/p0b-route-rescore.md`: provenance status; the official-cell erratum pointer.

### 0a.3 Scorecard provenance

- **Done (Phase 0a):** moved `build/qa/review_20261124/row_route_matrix.md` and `ADJUDICATIONS.md` under `docs/reference/clip_1795033698901/`; scorecard/rescore/live-ref/plan references updated.
- The 2026-11-24 recording and 281 frames remain outside git; record that in the scorecard provenance section.

### 0a.4 QA gates

- Add a headless `p0b_route_self_test` gate (wrapper `--self-test`, 62 checks) to `build/qa/run_final_gates.sh`; update the gate-table docs.
- Write the wrapper’s process exit into the captured log; add `bash -n` for the live/route wrappers to the gate list.
- Do not add `build/qa` scripts to `check_scripts_compile.gd` in this wave (it scans `res://`); the route self-test parses `p0b_route.gd`.
- A clean route2 re-run is Phase 0b (GPU).

### 0a.5 V6-03 official erratum

- In `COMPARISON_PORT_20261124.md`, correct the **official** V6-03 cell with a dated note: emitter **17.8 %/40.0 %**, **one** band at 40.0–40.5 %, **above-door** cyan node; the old 56 %/two-beam/ceiling text is a transcription error.
- Leave the port-side cell and the 120 tally for Phase 3; no row token changes.

### 0a.6 Issue triage

- Read `gh issue list` / each of #2–#11; map each to a phase, close, or explicitly defer; label/comment; link #13.
- Do not close an issue without a recorded reason.

**Phase 0a acceptance:** save md5 `976f`; docs consistent; provenance tracked; route self-test gate green; V6-03 erratum recorded; #2–#11 mapped; `git diff --check` + `make check-greps` clean; no `game/` or generated-data changes; no GPU; one coherent commit; no push.

---

## 3. Phase 0b — clean route2 (GPU, headless Xvfb)

- Run `build/qa/p0b_route.sh --tag=route2-clean` at the Phase 0a HEAD; expect `status=captured captured=13 deferred=14 partial=0 frame_errors=0 frames=17`, `git.dirty=false`.
- Commit the manifest/log/exit line; update the route provenance; keep the old route1/route2.
- Run the full 45-gate set (the new route self-test gate + the 44) serially; record the logs; update the ratchet/report only from the measured logs.
- One Godot at a time; no parallel GPU; delete the old 52 G video parts if the next capture needs the space.

**Acceptance:** clean route2 manifest `git.dirty=false`; 45/45 gates; the route self-test green; the gate table `measured_on` updated with a report.

---

## 4. Phase 1 — P4 look (the visual floor)

### P4.0 — instruments

- `build/qa/mirror_probe.gd/.sh`: a 2-instance MultiMesh (identity + `scale.x=-1`), a `MeshInstance3D` control, `CULL_BACK`, readback; negative control first.
- `TAT2_LANDSCAPE_MASK=discard|raw|off` + a synthetic 50/50 mask probe; the data assertion at the safe-room gap.
- Re-measure the beam at the current tree at the `upper_foyer`/KF27 pose with `p0b_roi_stats.py`; record the thick-band/cream result before changing the material.

### P4.1a — exposure data + pure model (headless)

- `tools/parse_weather.py`: emit `auto_exposure_method`, `min_brightness`, `max_brightness`, `speed_up`, `speed_down`, `bias_curve`.
- New `game/src/core/auto_exposure.gd`: `configure`, `step(dt, ev100)` with the authored clamp/speeds/bias + `GameData.eval_standalone_curve`, one `AEM_CALIBRATION`; `reset`/`state`.
- `weather_profile.gd`: delegate the hard-coded curve; `TAT2_AEM=fixed` reproduces 1.15 exactly; `model` uses the authored fields.
- `probe_auto_exposure.gd`: +4 EV 20 s / −4 EV 2 s, clamps, curve points from `curves.json`, monotonicity, determinism.

### P4.1 IBL — producer + consumer

- Extractor `UTextureCube` branch for `Cubemap_GroundFloor_01`, `T_FakeSpecular1`, `/Engine/.../daylight`; `AT_CUBEMAP_PASS`; `parse_cubemap.py` → `game/data/generated/ibl/cubemaps.json`.
- `cubemap_loader.gd`; stage-1 CPU irradiance → ambient colour/energy (no clamp); `probe_cubemap.gd` (6 faces, axis, irradiance, `available=false` matches today).
- Stage-2 sky radiance only after a dome A/B; no authored rotation.

### P4.1b/c — meter + calibration

- `CompositorEffect` log-luminance reduction, async readback, `TAT2_AEM=meter|fixed`.
- Synthetic radiance test; six-pose measurement; **one** global calibration at the gate pose; no per-room grade; record the residuals.

### P4.2 — mirrors

- Partition negative-determinant instances; bake the mirrored mesh variant (reverse winding/normals/tangents), cached; `CULL_FRONT` fast path only for single-surface `BaseMaterial3D`; standalone compensation test.
- `mirror_probe` positive; per-level count reconciliation; memory/draw-call report.

### P4.4 — landscape

- Keep `vis > 0.5`; raw-mask A/B; the synthetic negative control; the safe-room data assertion; correct the docs.

### P4.5 — beams

- Implement the authored sphere-mask/edge/fake-glow terms; add `foyer_beam`; correct the KF27 expectation to one band/40.0–40.5 and emitter 17.8 %/40.0; re-measure the gold bulb after exposure; leave `MI_LightBeam_02` unused.

**Phase 1 acceptance:** `probe_auto_exposure`/`cubemap`/`mirror`/landscape/beam probes green; one global calibration; no per-room grade; the KF27-framed capture shows one band + the emitter; the P4 docs qualified; no visual claim without a capture.

---

## 5. Phase 2 — in-tree content/systems (parallel-safe)

### Audio W11

- **W11-A VO director:** index the 645 lines by `(speaker, verb, state)`; `vo_pick`; cooldowns/priority; wire guard transitions + player/quest events; suite 122; the zero-media line refused; no “all 645 wired” claim.
- **W11-B music:** `parse_audio_control` music containers/keys/transitions/stingers; `music_select` 6/9; authored fades; 3 unnamed keys fail closed.
- **W11-C `FS_Layers`:** `surface_resolver.layer_for`; `audio_manager` sets it; the 44/52 media tests.
- **W11-D RTPCs:** stamina/crouch/fall/weather/disguise; exact curve values.
- **W11-E state rows:** a counted `state_override_report`; defer the unnamed buses with a number.
- **W11-F mix:** serialized Master tap; AU rows; the menu BGM divergence documented.

### GC / bookcases

- **G-1 containers:** add bookcase-minor/major + safe-major to `parse_containers.CLASSES`/`level_loader.LOOT_CONTAINER_CLASSES`; primary spawner preference; 8+8 records; re-measure locks/GC.
- **G-2 leaves:** bookcase door leaves + multi-door owner index; the static-batch measurement first; update the p2 GC census.
- **G-3 break labels:** `authored_breakable` vs `disabled_component`; keep hold-F as `PORT_DECISION`; no invented damage path.
- **G-4 Destructibles:** after the extractor `json` pass; confirm/refute `fallback_broken=93`.

### Navmesh / StateTree

- **N-P0:** extractor `SupportedAreas`/`NavDataConfig`, fail on `max_poly_verts>6`; `parse_nav.py`; the binary/manifest; the 2,958/14,709/30,918/80; per-map areas; 63=Default; the probe.
- **N-P1:** `nav_runtime.gd` + the region behind `TAT2_NAV=off|on`; the mission insertion; the 3-waypoint doorway; the off regression.
- **N-P2:** 80 links + door links (leaf midpoint, >70°); the snap/prison link-on/off tests.
- **N-P3:** default on; the full gate set; the trajectory deltas.
- **N-P4:** ST_Patrol parity probe; loop coverage; the trace budget.
- **N-P5:** `TAT2_STATETREE=patrol` cutover; 0.70 m/15°/one writer; the alertness signatures.
- **N-P6/P7:** event bus/smart objects deferred.

### UI

- **U-4:** extractor `UTexture2DArray` (21 slices); `hud.gd` binds the authored array; pin the slice mapping; `PORT_APPROX` removed only with the payload.
- **U-1/U-2:** GPU capture harness + `ui_pixel_stats.py` (gem, compass, prompts, pause, briefing, text).
- **U-3:** adjudication report; no token without a capture; string ceiling 112.

### 120-row scorer

- **R-2:** `p0b_route_stats.py` (or a scorer extension) maps route frames to row ids; validates on route2; no tokens.

**Phase 2 acceptance:** all new suites/probes green; the GC/lock/texture/audit gate numbers re-measured; no worker-side data regen; one writer per file; worktrees merged and verified.

---

## 6. Phase 3 — evidence, owner, ship

- **R-1:** a **played** parity-only port full-route run on the **official Cleanout (`LootTheRoom`, `free_play=false`)**; verify the R10 path first; otherwise canonical `VaultHeist` with a labelled mission delta. Frames + `mark_beat()` + audio tap + session log + build stamp.
- **R-3:** row adjudication against the official keyframes; the V6-03 official erratum already in Phase 0a; the port-side cell; old vs new tally; every changed row has frame + reference + comparison.
- **#13:** the Cleanout live reference when the owner is available; `976f` save; 55-minute prep; safe-room spawn; 900 s main-menu recorder; audio 80; poses; `P0B_LIVE_VERIFY`.
- **D-3/D-4:** the shipped-lens perf matrix (3 runs, serialized, thermal waiver) and `make linux-build` + stamp verification; no hand-edited stamp.
- **D-1/D-2:** the extractor `json` stage, Destructibles, texture arrays, expansion labelling; `audio_mix` classification decision.

**Phase 3 acceptance:** the 120 tally updated only from measured rows; the live reference `P0B_LIVE_VERIFY PASS` or a recorded reason; perf/export evidence or an explicit “not run”; the ratchet only from committed logs.

---

## 7. Parallelism, worktrees, rules

- **Worktrees:** P4 model/IBL, P4 mirrors, P4 landscape/beams, audio, GC, navmesh, UI may run in separate worktrees; `game/data` is read-only for workers; only the integrator runs `make normalize`/audit re-stamps.
- **GPU:** one Godot at a time; the route2 clean, the mirror/landscape/beam probes, the UI capture, the perf matrix are serialized; no parallel Vulkan/Xvfb.
- **Gates:** every new script/suite/probe is registered; floors move only with a measured log; the QA/live-capture gates are added to the final set.
- **Commits:** one coherent commit per wave; workers do not push; the integrator verifies and pushes; docs updated in the same wave.
- **Owner-dependent:** #13, the played 120-row, the UI visual score, the perf thermal waiver, the store/export; no other lane blocks on them.

---

## 8. Gate and ratchet impact (re-measure, never hand-edit)

| Gate | Current | Expected movement |
|---|---|---|
| `compile` | 217/0 | new scripts (`auto_exposure`, `cubemap_loader`, `vo_director`, `nav_runtime`, `patrol_cutover`, probes) |
| `run_tests` | 324/0 | new suites (VO, AEM, nav, cutover) |
| GC p2 / probe | 95/79; 336/166/93/5 | bookcase leaves/owners; Destructibles |
| locks | 154 | +8 safes (+bookcases) |
| texture cap | 796/1/0 | +21 gem slices; target set/offenders |
| audit | 12660/12703 | new `nav`/`audio_control`/`containers`/`levels` blocks; re-stamp |
| string audit | 311/199/112 | keep 112; no new invented literals |
| final set | 44 gates | + route self-test + live-capture checks; 45+ |
| ratchet | `5135f53` | new serial run + committed logs + report |

---

## 9. Deferred / owner-dependent

- Cleanout live reference **#13** (save `976f`, 900 s, audio 80, mission check).
- Played port 120-row run (official Cleanout; the R10 path).
- UI visual score (GPU capture; the gem array if U-4 lands).
- Perf matrix (thermal waiver) and the Linux export/stamp.
- The smart-object/distraction branch and the full `ST_Guard` cutover.
- The unnamed Wwise keys/groups/RTPCs (id-only, counted).
- The bookcase static-batch question, the 21-slice direction mapping, the 93-chest Destructibles confirmation.

---

## 10. References

- `docs/HANDOFF_NEXT_AGENT.md` — current gate table, traps, open items.
- `docs/reports/final-20261127.md` + `docs/reports/logs/final/` — the W10 FINAL
  44-gate evidence at `5135f53` (history) and the Phase 0b 45-gate measurement
  at `912a481`; current report:
  [`final-20261127-phase0b.md`](final-20261127-phase0b.md).
- `docs/reports/p0b-route.md` + `docs/reports/logs/p0b-route/route2/` — the staged runner and measured capture.
- `docs/reports/live-ref-review-20261127.md` (+ plan/lanes/verification) — the Staff-mission live review and KF27 correction.
- `docs/reports/p0b-route-rescore.md` — the staged evidence index; the beam/ROI numbers.
- `docs/reference/clip_1795033698901/` — the official clip, keyframes, scorecard, matrix/adjudications.
- `docs/FIDELITY_GAPS.md`, `AGENTS.md` — invariants, traps, gate rules.
- Issue **#13** — deferred Cleanout live reference (save caveat in the comment).

---

## 11. Execution log

| Date | Phase | Measured evidence |
|---|---|---|
| 2026-11-27 | 0a | `276a5bd` (truth/save/provenance/gate hygiene); independent verification `912a481` = **8/8 PASS** ([`phase0a-verification-20261127.md`](phase0a-verification-20261127.md)). No GPU. |
| 2026-11-27 | 0b | Route2-clean at `912a481`: `status=captured beats=27 captured=13 deferred=14 partial=0 frame_errors=0 frames=17`, `git.dirty=false`, 18 PNGs 1920×1080, exit 0, wrapper wall 207 s (`docs/reports/logs/p0b-route/route2-clean/`). One Godot at a time under Xvfb; no Steam/shipped game. |
| 2026-11-27 | 0b | First full 45-gate set at `912a481`: **45/45 exit 0**, wall 19 m 49 s (`docs/reports/logs/final/`); route self-test `P0B_ROUTE_SELFTEST PASS checks=62 fails=0`. Ratchet re-stamped `measured_on=912a481` with `p0b_route_self_test.checks=62`; `make gate-ratchet` and `make audit` PASS. Report: [`final-20261127-phase0b.md`](final-20261127-phase0b.md). Commits local, **not pushed**. |
| next | 1 | P4 look: instruments (`mirror_probe`, landscape mask probe, KF27 beam re-measure) → exposure/IBL/AEM → mirrors/landscape/beams. No visual claim without a capture. |
