# Sprint 3 — close M1, take M2 (world + rendering)

Started 2026-11-21. Decisions taken with the user:

| Decision | Choice |
|---|---|
| E2E baseline policy | **Baseline and forward** — fix harness + genuine-now defects; defer system-dependent failures to their owning milestone with a GitHub issue. |
| Regeneration gate (`11.11`) | **At sprint start** — wipe regenerable data, re-extract, re-normalize, prove every gate from clean. |
| Level Niagara target | **Absolute 3,695** — reconcile extraction accounting until the audited total is spawned. |
| Visual acceptance | **Screenshot pairs + report** under `build/qa/` (gitignored) plus a short written report. |

## Order

1. `A1` E2E baseline triage (uses current generated data).
2. `A2` per-milestone issues.
3. `A3` wipe + `make extract` + `make normalize` + gates.
4. `B1`–`B5` world loading/geometry.
5. `C1`–`C5` rendering/weather/VFX/materials.

## Track B status

| Item | State | Evidence |
|---|---|---|
| B1 smart-object separation | done | `smart_objects` collection; 1,707 markers leave `guard_spawns` |
| B2 contract sublevels + MissionClues | verified | 16 contracts, 0 missing sublevel refs, MissionClues present |
| B3 FTUE collider budget | done | `probe_ftue`: 10 sublevels, 35,397 shapes, 0 dropped, safe-room start, PASS |
| B4 deterministic SV selection | done (selection) | `probe_scene_variants`: 104 Guildhall variants, stable per seed, varies across seeds, PASS |
| B4 override application | deferred | issue #11 (SceneElement -> SpawnGroup tag mapping) |
| B5 loader geometry | done | mips regenerated after downscale; volume basis applied; single-instance MultiMesh windows clipped |

### Track C (next)

C1 NPR/SNN post-process, C2 OSEXray, C3 weather (roof occlusion, lens drops, volumetric/clouds), C4 Niagara placements, C5 material fallback warnings to 0.

| Item | State | Evidence |
|---|---|---|
| C4 level Niagara | **done** | clean re-extraction yields **3,695 placements / 37 systems** (matches the audit); `probe_niagara` spawns all 3,695 instances as 37 MultiMesh nodes, shader clean |
| C5 material fallbacks | **done** | 37 warnings → 0; `fallback_material_count=0` on Guildhall; `track-c.md` |
| C1 NPR/SNN | **done** | `ose_renderer.gd` + `tat_npr.gdshader`; F6/F7; `build/qa/c1_post_*.png`; 0 SHADER ERROR |
| C2 OSEXray | **done** | `xray_overlay.gd` + `tat_xray.gdshader`; authored MI_Xray colours; `build/qa/c2_xray_*.png` |
| C3 weather | **done** | roof rain columns, lens drops, Guildhall FogVolumes; `probe_weather` PASS; `build/qa/c3_*.png` |
| B4 override application (#11) | **done (exact + class map)** | `probe_scene_variant_apply`; per-source building variants; Limits in `track-c.md` |

## Baseline evidence

- E2E run (unmasked): `/tmp/opencode/e2e_unmasked.log`; Track C re-run 212 passed / 44 failed (baseline 210/46), no new failure IDs.
- Unit suite: `run_tests` fails=0, 0 material fallbacks, 0 leaks, 0 `SCRIPT ERROR`.
- M2 player suite: 9/9.
- Compile: 46/46.
- UID: 0/0.
- Pipeline: 107/107 maps, 210 patrol paths / 673 waypoints, 222 SV variants, 21 device families.

## Notes

- `11.11` wipes `extracted/` and `game/data/generated/`; both are gitignored, so no commit risk.
- The Niagara reconciliation starts from `game/data/generated/levels/**` record totals vs the audit's 3,695; the 107-map emission may have changed the accounting versus the audit's 70-map snapshot.

## Regeneration gate evidence (11.11)

Executed from a wiped tree (`extracted.bak` / `generated.bak` kept until green):

| Step | Result |
|---|---|
| `make extract` | exit 0 — 107 maps, 995 anim USD dumps, 14 known BlendSpace skips |
| `make normalize` | exit 0 — 107 levels, 673 waypoints, 222 variants, 4,118 devices |
| `make anims` | exit 0 — **995/995** clips, manifest written |
| `tools/reimport_assets.sh` | exit 0 |
| `make audit` | exit 0 — 14 known-unsupported (0 unexpected), all 7 groups fresh |
| `check_uid_duplicates` | 0 errors / 0 warnings |
| `check_scripts_compile` | 46/46 |
| `run_tests` | **fails=0**, 0 leaks, MESH HOLES 0 |
| `test_m2_player` | **9/9** |

Defects found and fixed by the gate:

1. Audio generation was absent from the normalizer chain after a wipe — `extract_audio` + `convert_wwise` added to `make normalize`.
2. `parse_interactables.py` ran after `parse_tables.py` and overwrote the `arc_deg` alias — alias now emitted at source.
3. `.gdignore` counted as a material source — dotfiles excluded from freshness scans.
4. 14 `UBlendSpace*` assets are a converter limitation — enumerated as known-unsupported; any other error still fails the audit.
