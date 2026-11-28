# Handoff — Thick As Thieves Godot 4.7.2 port (next session)

**Repo:** `/home/john/Projects/TAT-2`
**Current tip:** `101fc91` — local `main` = `origin/main` (pushed).
**Measured code/gate head:** `37bb69e`; the final 49-gate run was made at its
docs pre-stamp `60474c0` (code identical). Evidence commit `5a66567`; final
audit `5dadcfc`.
**Gate set:** **49/49 exit 0** — compile **228/0**, `run_tests` **327/0**
(suites 119/121/122/123/124), `make gate-ratchet` PASS, `make audit` PASS.
**Godot:** `4.7.2.stable` via native `tools/godot` (`godot` is **not** on
`$PATH`). Forward+ · Jolt 60 Hz · 1280×720 base · Linux x86_64.
**Working tree:** clean, except an untracked 0-byte `-1` shell artifact in the
main checkout (not tracked, not part of any wave).
**Read first:** this is the post-Phase-1/2 handoff. The previous long handoff is
archived at [`docs/reports/handoff-archive-20261127.md`](reports/handoff-archive-20261127.md).
**Steam reference:** `/home/john/.steam/steam/steamapps/common/Thick As Thieves/`
(appid `3341000`, build `25076818`, `1.5.148559`).

---

## 1. What just landed (Phase 1/2, 2026-11-27)

Seven lanes were implemented in isolated worktrees, independently verified
PASS, then integrated in this order:

| Lane | What landed | Key measured values |
|---|---|---|
| **P4 landscape/beams** | `TAT2_LANDSCAPE_MASK=discard\|raw\|off`; all **15/15** authored beam scalars consumed; 2 cm fake-glow core; side/sphere/edge uniforms exposed but inert; `foyer_beam` KF27 cue; `beam_close` relabelled the Lounge **extra** | landscape **7/0**; beams **9/0**; safe-room gap comp 12 (`Weightmap_20`, mask 0.0 → visible) |
| **P4 mirrors** | negative-determinant split; baked `S·M`/`B·S` variant; single-surface `CULL_FRONT` fast path; exact `source_counts` apportionment | draw **3,297 = 3,119 MultiMesh + 178 standalone**; 464 splits; 103 baked / **31,097,388 B**; `PERF_CENSUS.source_sublevels=64,660`; probe **39/0**, full **790/0** |
| **P4 exposure/IBL** | authored AEM fields (`-10/+1`, `0.2/2.0`, bias 0, V3); pure `auto_exposure.gd`; `TAT2_AEM=fixed\|model\|meter`; 3 cubemaps / 18 faces; CPU cosine IBL; CompositorEffect meter | AEM **77/0**; cubemap **37/0**; fixed 1.150 / ambient 0.160 unchanged; model no-op 1.1500 |
| **Audio W11** | 645-line VO index + `vo_director`; `FS_Layers`; music decision tree; RTPC domains; state-row report | suite 121 **123/0**; VO 122 **53/0**; 249/645 events reachable (35 triples); 396/645 still unmapped |
| **GC/bookcases** | 3 container classes; 8 bookcases + 2 POI + 8 safes; static glass-pane binding (0.472 m); `{leaves, broken}` owner index | Guildhall containers 107→**125**; locks **162 = 152 + 10**; GC **52/0**; p2 **17/17**; A2 static leaves **20** |
| **Navmesh** | `parse_nav` + `nav_runtime.gd`; one region per map; 80 baked links + door links | Guildhall **221→123→80**, Old Manor **216→113→64**, FTUE **11→8→4**; probe **70/0**; `TAT2_NAV=off` default |
| **UI** | allowlisted `UTexture2DArray` for `T_stealthball_Array`; 21 slices; HUD `sampler2DArray`; 12-screen capture + pixel stats | `GEM_PAYLOAD present=true: layers=21`, `mapping_kind=directional`; P5 **54/0**; capture **28/28**, sidecars fixed |

Two real integration defects were found and fixed:

1. Array slices were written as `slice_00png` (missing dot), so Godot could not
   import them and P5 stayed `PORT_APPROX`; `Exporter.cs` now always adds the
   extension dot.
2. E2E `T1-13-A` read the procedural `lit_amount` on the authored-array
   material; it now follows the authored slice path while retaining the
   centered/frame-tint checks and the procedural fallback.

Data regeneration at the merged HEAD: cubemaps `ok=3 fail=0`; nav Guildhall
2,958 tiles / 14,930 polys / 221 offmesh, Old Manor 1,469 / 9,275 / 216, FTUE
1,558 / 5,587 / 11, all `max_poly_verts=6`, `decompress_fail=0`; UI array 21
slices; `AUDIO_CONTROL_OK … music=2 music_keys=6/9`; audit **12660/12703**,
texture cap **1567/796/1/0**.

---

## 2. Current gates (49, measured at `37bb69e`; one serial run at `60474c0`)

| Gate | Value |
|---|---|
| compile | **228 checked / 0 broken** |
| `run_tests.gd` | **327 PASS / fails=0** (suites 119 cream, 121 audio, 122 VO, 123 AEM, 124 cubemap) |
| M2 | **12/0** |
| P1 route probes | safe **86**, doors **47**, beams **9**, ward **44**, street **31** (`hard_limits=2`) |
| landscape mask | **7/0** |
| navmesh runtime | **70/0** |
| guards | Guildhall `C_20`, buckets 4/4; Old Manor order 3, 4/4 |
| collision | `COL_MAPS PASS min_coverage=0.869 dropped=0 planar_skipped=2 coverage_ppm=868852` |
| locks | **162** = 152 containers + 10 door nodes |
| E2E `all` | **300/300** (T1=117 T2=110 T3=25 T4=14 S2=12 A2=22) |
| E2E p2 | **17/17**, `expected_fail=0 expected_delta=0 fixed=0 unexpected_fail=0` |
| parity-only | **60/60**, 11 rules all `parity_restoration` |
| cream 119 | **GREEN**, `passes=5` |
| audio 121 | **123/0** |
| VO director 122 | **53/0** † |
| AEM 123 | **77/0**, no PENDING † |
| cubemap 124 | **37/0**, no PENDING; `CUBEMAP_ORIENT` daylight WARN † |
| P5 UI | **54/0**; `GEM_PAYLOAD present=true: layers=21` |
| Den spawn | **9/0**, `source=authored` |
| capture harness | dry-run `poses=7`; self-test **23/0**; KF27 **9/9** (reference-only) |
| producer tests / P5 filter | **PASS** (stealthball 22, UI pixel 15, parse_nav 7) / **5/5** |
| runtime smoke | `RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 mission_ready=1` |
| route self-test | **62/0** |
| audit / texture / perf / ratchet | **PASS** / 796 capped, 1 alpha, 0 offenders / **78/78** / **PASS** |
| string audit | 311 routed / 199 authored / **112** invented (ceiling 112) |

† **Carried forward, not reproduced by the committed 49-gate runner.** These
three counts come from the standalone logs `test_vo_director.log`,
`probe_auto_exposure.log` and `probe_cubemap.log`, written at **14:51** — before
the 14:52 merge and ~2 h 15 min before the 17:06 run. The three subjects now run
transitively inside `run_tests` suites 122/123/124, and those suites print no
per-suite count, so the 49-gate run itself does not regenerate these numbers. A
re-run of the three probes is an open Phase 2.5.1 item.

The in-run `docs/reports/logs/final/gate_ratchet.log` is the runner's own
wrapped log (`sha256 7d859b97…`; its internal `FINISHED:` stamp is 17:28:55 and
its filesystem mtime is 17:30:01). Do **not** overwrite it with a
post-stamp run; redirect any later ratchet check to
`gate_ratchet_poststamp.log`.

---

## 3. GPU results — measured, not all passing

Run serially under Xvfb on the integrated tree; evidence in
[`docs/reports/gpu-phase12-20261127.md`](reports/gpu-phase12-20261127.md).

| Probe | Measured | Verdict |
|---|---|---|
| **Mirror readback** | `control_ok=true`; 8 red triangles + 2 expected black (CULL_FRONT control, uncompensated `mm_native_mirror`); `native_mm=not_compensated`, `native_single=compensated`, `baked_mm=ok`, `cull_front_mm=ok`, `single_baked=ok` | **PASS** (`pass=1`, exit 0) |
| **UI 12-screen capture** | `captures=28 failures=0`; 28/28 sidecars with `roi.*`; authored gem 21 layers; **24 strict fails** | sidecar bug fixed; **4 real prompt-contrast rows** (crank 3.81/4.32, doors 3.24/3.70 vs 4.5); 2 pause-blur box artifacts (actual ratio **0.19/0.18**); 18 ROI-mask artifacts |
| **KF27 beam** (`foyer_beam`) | **5/9**: one band at **50.00 %** (needs 40.0–40.5), emitter **(0,0)** (not in frame; reference 17.8/40.0), falloff `(+78.04,+79.46)`, cream **1.30 %** | **FAIL/open** |
| **Landscape A/B** | `upper_foyer`/`gate` contain no landscape subject; RMSE discard↔raw 0.003357 (505 px), off↔raw 0.000164 (3 px); no mode holed the gap | **unmeasured**, not a code failure |
| **IBL `ambient`** | energy **0.00005**; upper_foyer 39.81→**20.11**, yaw180 39.10→**12.06**; `cubemap_ground_floor_01` near-black (raw irradiance ≈0.0001 vs 0.16) | default **`off`** stays |
| **AEM `model`** | exposure **1.1500**, ≤241 px vs off | no-op ✔ |
| **AEM `meter`** | stable **0.2615** (ev100 −0.863, adapted −4.863), frames 88→256 | **not converged** (60-frame capture settle, not the ≥25 s settle) |

**Do not cite KF27 `9/9` as a port pass.** That gate scores the tracked reference
against itself (`--reference-only`); the first port-side `foyer_beam` capture is
**5/9**.

---

## 4. Next actions, in priority order

### A. Port-side look fixes (no owner required; GPU re-capture only)

1. **KF27 beam fidelity.** The measured band is **50.0 %**, not 40.0–40.5; the
   emitter is absent at (0,0); the glow falloff is wrong. Decide whether the
   `foyer_beam` pose framing or the beam terms are responsible. Use the authored
   card `BP_Detector_LightBeam_C_107` at `(23.27,29.76,-57.4)` and the current
   eye `(27,29.67,-55)`; do not move the pose just to hit the row. If the UE
   graph/sphere centre remains unavailable, record a `HARD_LIMIT` with the
   measured 5/9. Re-capture and score with
   `p0b_roi_stats.py --port … --pose foyer_beam`.
2. **Landscape A/B.** The data assertion is green; the visual A/B has no
   landscape in frame. Add a **gap-view** pose only from an authored eye/target
   (the safe-room gap is Guildhall component 12 / `Weightmap_20`). If no
   authored camera exists, record that the A/B is not measurable and keep the
   data gate. Never invent a pose and call it authored.
3. **AEM meter.** Default is `fixed`; do not flip. To calibrate, run
   `TAT2_AEM=meter` with a **≥25 s** settle and record the residual; the current
   60-frame capture gives 0.2615 vs 1.150 and is not convergence. Re-pin the
   single `AEM_CALIBRATION` only from a measured residual, then re-run suite 123.
4. **IBL orientation / energy.** `daylight` has a black `nz` face and
   `+Y 0.0680 < −Y 0.0712` (orientation WARN); `cubemap_ground_floor_01` is
   near-black on every face. Default stays `off`. Check the UE `ECubeFace` slice
   order before trusting an ambient direction; decide whether stage 1 needs a
   normalization/energy term, then A/B `off` vs `ambient` at gate/foyer/yaw180.
5. **UI prompt contrast.** Four genuine strict rows: crank **3.81/4.32**, doors
   **3.24/3.70** vs the 4.5 floor, light-blue text over the bright bloom. This is
   consistent with the reference `UI2-03 DELTA`; either raise the contrast or
   record it as a parity delta. Do **not** lower the 4.5 threshold. The other 20
   rows are ROI/mask artifacts; the pause blur is actually 0.19/0.18.

### B. Owner/GPU (Phase 3)

- **#13 — Cleanout live capture** (owner unavailable). The 2026-11-27 capture is
  the **Staff of Edinburgh Item Collection Heist**, not the Cleanout. Checklist
  in §5.
- **Played 120-row run.** Re-score from a **port** full-route run, not the live
  capture. Current baseline: **9 PASS / 33 DELTA / 4 MISSING / 2 HARD_LIMIT /
  16 UNVERIFIED / 56 N/A-route** (2026-11-24; predates W10; V4-07/V6-03
  re-scored in W9-P1). The official V6-03 erratum: emitter **17.8 %/40.0 %**,
  **one** band at **40.0–40.5 %**, cyan node **above the doors**.
- **UI visual adjudication.** The 28-frame capture is measured; the gem, pause
  blur, briefing fit and line weights still need a human/reference score.
- **Perf matrix / Linux export.** Not run; thermal gate waived; no parallel
  Godot; host idles near 80 °C. Export only with `make linux-build` +
  `make linux-stamp-verify`; never hand-edit the stamp.

### C. Long-standing system gaps

- **StateTree:** shadow only; `fully_parity_covered_trees=0` of 21, one
  structural tree; `TAT2_STATETREE=off`; FSM drives. Cutover needs the authored
  task/condition parameters and a live event bus — do not invent values.
- **Audio:** W11 landed, but **396/645 VO lines (41/76 triples) have no caller**;
  3 unnamed music keys stay id-only; 24 unnamed buses carry 98/183 state rows;
  5 `FS_Layers` values are unproduced; Hauntstable1 never recorded
  `ExertionCombat/KnockedOut`; `blood_moon` rain 10.0 is clamped to the RTPC
  0..1 domain (owner decision).
- **GC/destructibles:** `Destructibles/` is still absent from the shared tree;
  the 93-chest fallback is a prediction, not a claim. Bookcases/safes landed;
  the authored damage-driven break remains open and hold-F `break_container` is
  a labelled `PORT_DECISION`.
- **Navmesh N-P3:** default is `off`; 38/80 door groups were skipped by the
  2.5 m snap; the prison baked link is one-way; `NavLink_71` is ~6 m off the
  mesh. Default-on needs a trajectory/full-route delta and a per-actor door
  audit.

---

## 5. Machine state and the Cleanout capture checklist

The shipped launcher needs an online login; Steam Offline Mode gives
`LOGIN FAILED!`. The **A path works**: copied install `~/tat2-ref-build` plus
copied prefix `/tmp/opencode/tat2-ref-prefix`, launched through Proton, with
Steam online for auth. The original install/prefix/save are untouched.

**Save state:** the copied prefix has **774 files**; `SaveGames/` holds
`TAT_ETS.sav` md5 **`976f8730eac989bab1c6c792343b7c00`**,
`EnhancedInputUserSettings.sav`, `steam_autocloud.vdf`. The archive
`SaveGames.pre-p0b-20261126-230522/` is untouched. Never use `stage` + `tail -1`
to pick a save; use the archive path explicitly. Issue **#13**.

**Cleanout pre-start checks:**

- The prep must read **Cleanout Heist** / **Time Limit: 55 minutes**; the spawn
  must be the **brick safe room**. If it reads **Item Collection Heist** /
  **120 minutes** / Staff of Edinburgh, back out and select the
  `CONSTABLES' GUILDHALL` Cleanout contract; do not start the recorder.
- One **900 s** file, started at the **main menu** (the 2026-11-27 run opened in
  the Den and missed S01/S02); 2560×1440, High groups, Resolution Scale **100**
  after the preset, VSync off, 60 cap, FOV 85.
- Audio Master/Music/SFX/Dialogue **80** (or a 10 s test max below −1 dBFS); the
  2026-11-27 Master 100 peaked at 0.0 dBFS.
- Hold each pose **3 s**; the last run had 0 poses present / 3 partial.
- Window title `TAT` (the helper searches `TAT` and `Thick As Thieves`).

**Port route evidence:** the staged 27-beat runner
`build/qa/p0b_route.sh` captured `route2-clean` at `912a481`
(`status=captured`, 13 staged / 14 deferred / 17 frames, 18 PNGs at 1920×1080,
exit 0, `route_claim=none`). It is a **staged port** run, not a played route.
Evidence: `docs/reports/logs/p0b-route/route2-clean/`.

---

## 6. Data state and regeneration

Generated data and extracted assets are **gitignored** and must never be
committed: `extracted/`, `game/assets/ue/`, `game/data/generated/`, `build/`
artifacts, `game/.godot/`. Commit producers/code/docs only.

Toolchain: `~/.dotnet10/dotnet` **10.0.404**. The extractor mapping is
`tools/ue4ss/output/TAT-5.5.4-148559+++TAT+tat_release_nosrc-30afe5ff.usmap`;
pass `--usmap <abs path>` if the worktree has no `tools/ue4ss/output`.

Minimal regeneration at a merged HEAD:

```bash
make build-extractor
EX=tools/tat-extract/bin/Release/net10.0/tat-extract
$EX cubemaps
$EX nav --overwrite --filter 'Maps/(Guildhall|OldManor|FTUE)/.*\.umap$'
$EX textures                       # writes the allowlisted 21-slice array
make normalize                     # parse_containers/audio/weather/cubemap/nav/stealthball/...
tools/godot --headless --path game --import
make audit-refresh-stamps REASON='<wave>; regenerated after make normalize'
make audit
make texture-cap-check             # 1567 targets / 796 capped / 1 alpha / 0 offenders
```

Success markers: `[cubemaps] ok=3 fail=0`; nav `max_poly_verts=6`,
`decompress_fail=0`; `textures-array ok=1`; `AUDIO_CONTROL_OK … music=2
music_keys=6/9`; `STEALTHBALL_ARRAY status=payload_present slices=21
mapping_kind=directional`; `AUDIT PASS`.

---

## 7. Commands and gates

```bash
make run
make test                         # 327 checks
tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"
tools/godot --headless --path game --script res://tests/run_tests.gd
tools/godot --headless --path game --script res://tests/test_m2_player.gd
tools/godot --headless --path game --script res://tests/probe_lock_inventory.gd
tools/godot --headless --path game --script res://tests/probe_gc_destruction.gd
tools/godot --headless --path game --script res://tests/probe_landscape_mask.gd
tools/godot --headless --path game --script res://tests/probe_p1_beams.gd
tools/godot --headless --path game --script res://tests/probe_p5_ui.gd
tools/godot --headless --path game --script res://tests/probe_auto_exposure.gd
tools/godot --headless --path game --script res://tests/probe_cubemap.gd
build/qa/nav_runtime_probe.sh     # NAV_RUNTIME_PROBE 70/0
make test-producers
build/qa/test_capture_p5_ui_filter.sh
build/qa/runtime_smoke.sh 90      # exit 124 only, no outer flock
build/qa/run_final_gates.sh       # 49 gates, serial, logs docs/reports/logs/final/
make audit && make gate-ratchet
```

GPU wrappers (one Godot at a time; they take `/tmp/opencode/tat2-godot.lock` and
own Xvfb):

```bash
build/qa/mirror_probe.sh --run --tag=p4mirrors_final
build/qa/p0b_capture.sh --poses=foyer_beam --tag=kf27_foyer_beam
build/qa/p0b_capture.sh --poses=beam_close --tag=lounge_extra
TAT2_LANDSCAPE_MASK=raw build/qa/p0b_capture.sh --poses=upper_foyer --tag=landscape_raw
TAT2_IBL=off|ambient build/qa/p0b_capture.sh --poses=gate,upper_foyer,yaw180 --tag=ibl_<mode>
TAT2_AEM=model|meter build/qa/p0b_capture.sh --poses=gate,upper_foyer,yaw180 --tag=aem_<mode>
xvfb-run -a -s "-screen 0 2560x1440x24" env XDG_DATA_HOME=/tmp/opencode/p5-ui-data \
  tools/godot --path game --rendering-driver vulkan \
  --script "$PWD/build/qa/capture_p5_ui.gd"
```

Use the **absolute** `--script` path; a project-relative path fails.

---

## 8. Hazards and traps (current)

- **Never commit extracted/generated content.** `extracted/`,
  `game/assets/ue/`, `game/data/generated/`, `build/` artifacts, `.godot/` are
  private/derived. `build/qa/` script sources are tracked; PNG/log artifacts are
  not.
- **Never weaken a test or lower a ratchet floor.** Truth corrections already
  accepted: collision `976321 → 868852` (authored element coverage), texture
  `797 → 796` (`texture_refs 1523 → 1522`), string ceiling 112. Anything else
  needs measured evidence and a report note.
- **KF27 `9/9` is reference-only.** The port capture is **5/9**. Do not merge
  the two numbers.
- **Defaults that must not flip without a measured A/B:** `TAT2_IBL=off`,
  `TAT2_AEM=fixed`, `TAT2_NAV=off`, `TAT2_STATETREE=off`. `TAT2_IBL=ambient`
  currently darkens (energy 0.00005); `TAT2_AEM=meter` is not converged.
- **Mirror native behaviour:** MultiMesh negative scale is **not**
  compensated (`mm_native_mirror=black`); standalone negative scale **is**
  (`single_native=red`). The port fast path (baked mesh / CULL_FRONT clone) is
  measured `pass=1`; 103 variants / 31.1 MB (59.1 MB if all standalones bake),
  caches cleared per load. Do not change the bake math without re-running
  `probe_mirror_split` and the GPU readback.
- **Landscape:** keep the authored `vis > 0.5` discard; `TAT2_LANDSCAPE_MASK`
  is a diagnostic mode, not a convention flip. The safe-room gap is component
  12 (`Weightmap_20`, mask 0.0); the synthetic 50/50 test counts exactly.
- **Bookcase glass:** the doors are already static geometry; only the **glass
  pane** is the GC leaf (16 Guildhall_Loot panes at 0.472 m, nearest other
  ≥0.838 m). Leaf census is **166 authored / 168 placements / 79 Guildhall**;
  do not emit duplicate leaves.
- **Locks are authored only:** **162 = 152 containers + 10 door nodes**; 363 is
  the raw record join. Do not invent lock levels.
- **Audio RTPC domains:** disguise integrity is 0..100 at the game layer but the
  authored curve is 0..1; `push_disguise_integrity` divides by 100. The other
  four callers are authored-domain. The player signal rebinds per instance
  (autoload + new player per contract) — do not restore the one-shot bool.
- **UI capture:** `_save()` extras must be a **flat Array of Strings**; use
  `_hud_sidecar(hud) + ["pose=…"]`, never `[_hud_sidecar(hud), …]`. The
  `P5_ONLY` filter fails closed on an unknown shot.
- **Ratchet log:** never overwrite the runner's in-run
  `docs/reports/logs/final/gate_ratchet.log`; a later `make gate-ratchet` goes
  to `gate_ratchet_poststamp.log` or `/tmp`.
- **Fresh worktree:** run `tools/godot --headless --path game --import` after
  checkout; a copied `.godot` does not know a new `class_name`. An editor run
  rewrites `project.godot`; never commit that rewrite.
- **`export_presets.cfg` must not contain `#` comments**; Godot's `ConfigFile`
  parser merges the comment into the next key, silently dropping
  `exclude_filter`. Use `;`.
- **StateTree trace is budgeted:** 8,192 rows / 16 MiB, then `STATETREE_TRACE
  capped`; `dropped` is ring drops only.
- **No parallel GPU.** One Godot at a time, shared lock; the host idles near
  80 °C.
- **Main checkout has an untracked 0-byte `-1` artifact.** It is not tracked and
  not part of any wave; leave it or ignore it.

---

## 9. Evidence map

- [`docs/reports/integration-20261127.md`](reports/integration-20261127.md) —
  merge order, conflicts, cherry-pick provenance (matching patch-ids), regen
  outputs, 49-gate table.
- [`docs/reports/integration-verification-20261127.md`](reports/integration-verification-20261127.md)
  — final independent audit **PASS**.
- [`docs/reports/gpu-phase12-20261127.md`](reports/gpu-phase12-20261127.md) —
  every GPU command/result, including mirror PASS, UI 24-row strict table, KF27
  5/9, landscape no-subject, IBL/AEM.
- `docs/reports/logs/final/` — the 49-gate logs at `60474c0`, including the
  in-run `gate_ratchet.log`.
- `docs/reports/logs/p4-mirrors/p4mirrors_final.{log,wrapper.log}` — mirror
  readback.
- `docs/reports/logs/phase2-ui/20261127T215654Z/` — integrated 28-frame UI
  capture, sidecars and pixel stats.
- `docs/reports/logs/p0b-route/route2-clean/` — staged port route.
- `docs/reports/handoff-archive-20261127.md` — the previous long handoff.
- Lane reports: `p4-landscape-beam-20261127.md`, `p4-mirrors-20261127.md`,
  `p4-exposure-ibl-lane.md`, `w11-audio-20261127.md`,
  `lane-gc-bookcases-20261127.md`, `navmesh-p0-p2-20261127.md`,
  `phase2-ui-20261127.md`.
- Scorecard: `docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md`
  (9/33/4/2/16/56), `row_route_matrix.md`, `ADJUDICATIONS.md`.

**Provenance:** main advanced `7de2f0c..5dadcfc`; the six lane tips were
cherry-picked with matching stable patch-ids, mirrors was fast-forwarded
(`07ecb56`), and the later mirror probe fix was replayed as `8111bbe`
(patch-id `58174ae13e08…`). The full table is in the integration report.

---

## 10. Definition of done for the next wave

```bash
git status --short                 # clean (or only intentional new files)
make test                          # 327 PASS, fails=0
tools/godot … check_scripts_compile.gd   # 228/0
tools/godot … run_e2e_tests.gd           # 300/300
build/qa/run_final_gates.sh              # 49/49
make audit                         # exit 0
make gate-ratchet                  # PASS (measured_on=37bb69e until a new run)
git push origin main
```

Then update this handoff, `AGENTS.md` (gate table), `docs/FIDELITY_GAPS.md`, and
a dated `docs/reports/<wave>.md` with the measured evidence. Record open gaps as
open; do not turn a reference-only score, a staged route, or an unmeasured GPU
pose into a parity claim.
