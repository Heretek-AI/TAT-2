# Phase 1/2 integration — mirrors + six lanes — 2026-11-27

Status: **headless integration measured**; the GPU evidence lane is now
included ([`gpu-phase12-20261127.md`](gpu-phase12-20261127.md)): mirror readback
PASS and UI sidecars complete, with KF27 5/9, landscape A/B no-subject, AEM
meter not converged and prompt contrast 3.24–4.32 still open.
Merge base: `354fab0` (six lanes: landscape/beams, GC/bookcases, navmesh,
audio W11, P4-E exposure/IBL, UI). Mirrors fast-forwarded at `07ecb56`.
Final code/gate commit: `37bb69e` (mirrors merge, P4.1 regeneration, extractor
fix, audit baseline, gate wiring, ratchet floors and the E2E authored-array
fix, GPU harness fixes and GPU evidence). The final 49-gate serial run at
`37bb69e` is recorded in the “Final gate run at 37bb69e” section below; this
report and its logs are the commit that follows it.

## Merge order and conflicts

| Order | Lane | Commits | Result |
|---|---|---|---|
| 1 | P4 landscape/beams | `8bb89fe`, `acf5953` | clean |
| 2 | GC/bookcases | `0adfea7`, `66fcbd4` | clean |
| 3 | Navmesh | `e5a2805`, `178c4aa` | clean |
| 4 | Audio W11 | `d25ea4b`, `b7f03fa`, `262d138` | clean |
| 5 | P4 exposure/IBL | `12fb0d7`, `518ca94`, `93a518b` | `Makefile` union |
| 6 | UI | `79c097b`, `7fa6186`, `495e554` | `Makefile` + `FIDELITY_GAPS.md` union |
| 7 | Mirrors | `a371852` → `dffb35f` → `07ecb56` | `--ff-only`, no conflict |

- `Makefile`: one `NORMALIZERS` assignment (31 producers, no duplicates) with
  `parse_cubemap`, `parse_nav` and `parse_stealthball_array`; extract stages
  `cubemaps`, `nav` and `textures` (the array pass is inside `textures`).
- `docs/FIDELITY_GAPS.md`: Phase 0a bullets unioned; kept the landscape beam /
  mirrors / landscape entries and UI's newer Light Gem authored-array entry.
- `game/tests/run_tests.gd`: auto-merged with duplicate suite 122. Audio keeps
  **122**; P4-E moved to **123** (AEM) and **124** (cubemap). Every P4-E doc
  reference was renumbered. No duplicate suite IDs remain (`101…124` each once).
- `mission_controller.gd`, `Exporter.cs`, `Program.cs`, `level_loader.gd`:
  auto-merged; no substantive conflict. Door → nav → guard order holds; the
  mirror bake math was not edited.

### Cherry-pick provenance

`main` was checked out in the primary worktree, so the six lanes were applied
with `git cherry-pick <base>..<tip>` on `phase12-integration` rather than as
merge commits. The verifier-approved lane tips are therefore **not ancestors**;
the content is preserved with **identical stable patch-ids**:

| Lane | Verifier tip | Integrated commits | Patch-id of the tip |
|---|---|---|---|
| P4 landscape/beams | `371eb4a` | `8bb89fe`, `acf5953` | `7b3bd0093a10…` |
| GC/bookcases | `dfa1a40` | `0adfea7`, `66fcbd4` | `2d04d7c3dab7…` |
| Navmesh | `0200d62` | `e5a2805`, `178c4aa` | `3cc23f76cd05…` |
| Audio W11 | `f4b907f` | `d25ea4b`, `b7f03fa`, `262d138` | `e0468f2277be…` |
| P4 exposure/IBL | `26ed975` | `12fb0d7`, `518ca94`, `93a518b` | `290b614f9e15…` |
| UI | `b4471e9` | `79c097b`, `7fa6186`, `495e554` | `8c93e7a23ab8…` |
| Mirrors | `07ecb56` | `a371852` → `07ecb56` | ancestor (`--ff-only`) |
| Mirror harness fix (post-integration) | `dd0bec8` | `8111bbe` | `58174ae13e08…` |

Reproduce with `git show <tip> | git patch-id --stable` and the same command on
the corresponding integrated commit. The six lane patch-ids and the seventh
harness-fix patch-id match byte-for-byte. `dd0bec8` is the probe-winding /
viewport-scale fix, not a lane tip; its content is the ancestor `8111bbe`.

## Real-extraction defect found and fixed

The first real `textures` run wrote the UI array slices as `slice_00png` (no
dot), because the CUE4Parse encoder returns `png` without the leading dot. The
parser reads the manifest and tolerated it, but Godot cannot import the files,
so P5 printed `GEM_PAYLOAD present=false`. Fixed the one-line filename
construction in `tools/tat-extract/Exporter.cs` to always add a dot; rebuilt and
regenerated the array. This is a producer bug fix, not hand-edited data.

The authored-array activation then exposed a second integration bug: E2E
`T1-13-A` read the procedural orb's `lit_amount`, which the authored array
material does not carry, so `float(null)` aborted T1-13 with a SCRIPT ERROR and
left its player/mission alive. Those leaked bodies emitted walking noise and
contaminated `T1-23` (heard Walking instead of Running) and `T3-25` (body block
det=5.8). `T1-13-A` now follows the authored path: it asserts the selected slice
changes (16 → 5 for 0.05 → 0.95), keeps the centre/frame-tint checks, and keeps
the procedural `lit_amount` assertion for the fallback. No assertion or floor
was weakened; T1 is 117/117, T3 25/25 and the full E2E is 300/300 again.

## Data regeneration (integrator-only)

The worktree has no `tools/ue4ss/output`, so the extractor was given the main
checkout's mapping explicitly:
`--usmap /home/john/Projects/TAT-2/tools/ue4ss/output/TAT-5.5.4-148559+++TAT+tat_release_nosrc-30afe5ff.usmap`.
The first run without it failed with `MappingException: Package has unversioned
properties but mapping file is missing`; rerunning with `--usmap` is the
recorded path.

| Step | Marker |
|---|---|
| `cubemaps --overwrite` | `[cubemaps] ok=3 skip=0 fail=0` |
| `nav --overwrite --filter 'Maps/(Guildhall\|OldManor\|FTUE)/.*\.umap$'` | Guildhall 2958 tiles / 14930 polys / 221 offmesh; Old Manor 1469 / 9275 / 216; FTUE 1558 / 5587 / 11; `max_poly_verts=6`, `decompress_fail=0` |
| `textures` | `[textures-array] ok=1`; 21 slices + manifest |
| `make normalize` | `AUDIO_CONTROL_OK … music=2 music_keys=6/9 …`; `STEALTHBALL_ARRAY status=payload_present slices=21 mapping_kind=directional` |
| `make audit` | exit 0; disk-backed coverage **12660 / 12703** (99.7 %), unexpected 0 |
| `make texture-cap-check` | targets 1567, capped **796**, alpha-critical **1**, offenders **0** |

Generated files present: `game/data/generated/ibl/cubemaps.json`,
`nav/{guildhall,old_manor,ftue}.nav.bin` + `manifest.json`, and
`ui/stealthball_array.json` (all 21 authored slices bind).

Audit integration fixes: added `tools/parse_nav.py` to `manifest_audit.py`'s
`PRODUCERS` (it was a `NORMALIZERS` entry with no baseline stamp) and re-ran
`parse_materials.py` after the array re-extraction so the broad
`extracted:assets` freshness group was not older than `materials.json`.

## Merged gate table (49 gates, one serial run)

| Gate | Measured |
|---|---|
| compile | 228 / 0 |
| run_tests | 327 PASS, fails=0 (suites to 124) |
| M2 | 12 / 0 |
| E2E | 300 / 300 (T1=117 T2=110 T3=25 T4=14 S2=12 A2=22) |
| E2E a2 | 22 / 22, `static_bookcase_leaves>=20` |
| E2E p2 | 17 / 17, all expected groups 0 |
| parity-only | 60 / 60 |
| cream suite 119 | 5 / 0 |
| audio control | 123 / 0 (`music=2`, `music_keys=6/9`) |
| VO director (122) | 53 / 0 |
| AEM (123) | 77 / 0, no PENDING |
| cubemap (124) | 37 / 0, no PENDING |
| P5 UI | 54 |
| Den spawn | 9 / 0 |
| P1 safe / doors / beams / ward / street | 86 / 47 / 9 / 44 / 31 |
| landscape mask | 7 / 0 |
| nav runtime | 70 / 0 |
| GC destruction | 52 / 0 |
| lock inventory | applied 162 = 152 containers + 10 doors |
| collision | `COL_MAPS PASS`, coverage_ppm 868852, dropped 0 |
| capture dry-run | 7 poses |
| capture self-test | 23 / 0 |
| KF27 reference | 9 / 9 |
| route self-test | 62 / 0 |
| producer tests | `test-producers` + `test_parse_nav.py` 7/7 |
| P5 capture filter | 5 / 5 |
| runtime smoke | exit 124, errors 0, mission_ready 1 |
| audit | exit 0, 12660 / 12703, unexpected 0 |
| string audit | total 311, routed 311, authored 199, invented 112 |
| texture cap | 1567 targets / 796 capped / 1 alpha / 0 offenders |
| perf guard | 78 / 78 |
| gate ratchet | PASS |

`measured_on` = `37bb69e` (the code/gate HEAD measured, the GPU harness/evidence
tip; the docs/logs commit is its child). The previous 71e77f6 run took 22m38s;
the 37bb69e run’s wall and exact `FINAL_GATES PASS` line are in the final
section below.

## Final gate run at 37bb69e

- **Run head:** `60474c004d21b0f19481cdf0b223afde2e12a78a` — the pre-stamp docs
  commit on top of `37bb69e`; the code is identical to `37bb69e`.
- **Result:** `FINAL_GATES PASS head=60474c004d21b0f19481cdf0b223afde2e12a78a gates=49`
  (exit 0), started `2026-11-27T17:06:31-05:00`, finished `17:28:55` (**22m24s**),
  `uncommitted_entries_at_start: 0`.
- **Value delta vs the 71e77f6 run: none.** The full 49-gate table above is the
  final-run table: compile **228/0**, `run_tests` **327/0** (suites to 124),
  audio **123/0**, VO **53/0**, AEM **77/0**, cubemap **37/0**, P5 **54** with
  `GEM_PAYLOAD present=true: layers=21`, beams **9/0**, landscape **7/0**, nav
  **70/0**, GC **52/0**, locks **162 (152+10)**, E2E **300/300**, a2 **22/22**,
  p2 **17/17**, capture **7 poses / 23 / 9-of-9**, audit **12660/12703**,
  texture **1567/796/1/0**, string **112**, perf **78/78**.
- **GPU evidence (included at `37bb69e`):** mirror readback **PASS**
  (`control_ok=true`, 8 red + the 2 expected black, `pass=1`, exit 0); UI
  sidecars **28/28** carry `roi.*` (the truncation is resolved). Open gaps:
  **KF27 5/9** (band 50.0 %, emitter absent, falloff), **landscape A/B no
  landscape subject** at `upper_foyer`/`gate`, **AEM meter 0.2615 vs authored
  1.150** (not converged), and **prompt contrast 3.24–4.32** on crank/doors.
  Details: [`gpu-phase12-20261127.md`](gpu-phase12-20261127.md).
- **In-run ratchet evidence:** `docs/reports/logs/final/gate_ratchet.log` is the
  runner's own log (`== FINAL_GATE gate_ratchet`, `EXIT: 0`), sha256
  `7d859b9740a50710bf127c1b126ae513d59431f82f2540cbd1ac30944c2912b2`,
  mtime `2026-11-27 17:28:55`. It was not re-run into. The separate
  `gate_ratchet_poststamp.log` is a post-run baseline check only.

## Residual warnings / still pending (GPU, no capture run here)

- `CUBEMAP_ORIENT`: daylight `+Y` luminance 0.0680 < `-Y` 0.0712 (informational
  WARN; the probe passes and reports the values). Check the UE ECubeFace slice
  order before trusting the ambient direction.
- Mirror engine readback: `build/qa/mirror_probe.sh --run --tag=p4mirrors`
  (Vulkan; the headless split census is 29/0, 772 with `--full`).
- Landscape A/B at `upper_foyer`: `TAT2_LANDSCAPE_MASK=discard|raw|off`.
- `foyer_beam` KF27 capture + `p0b_roi_stats.py` (one band 40.0–40.5 %,
  emitter 17.8 %/40.0 %); Lounge `beam_close` prints `P0B_EXTRA`, never KF27.
- IBL `off` vs `ambient` (KF16/KF17/KF18), `TAT2_AEM=model` no-op, then
  `TAT2_AEM=meter` at six poses with >=25 s settle; re-pin `AEM_CALIBRATION`
  only if the residual is measured non-zero.
- `capture_p5_ui.gd` at 720p/1080p + `ui_pixel_stats.py --strict` (the headless
  filter and manifest checks pass; the pixels are not scored).

No `make extract` (full), `make normalize` rerun of audio/anims, or GPU/Vulkan
capture was run after this measurement.
