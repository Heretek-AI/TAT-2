# Handoff — Thick As Thieves Godot 4.7.2 port (next session)

**Repo:** `/home/john/Projects/TAT-2`
**Code/data tip:** `5135f53` (P2/P3/P5/data + Den/navmesh/UI/audio merged).
**Docs/evidence tip / `origin/main`:** `a9ac606` (live-reference review, pushed).
**This session:** Phase 0a truth/save/gate hygiene; the Phase 0a commit is local
and **not pushed**.
**Working tree:** clean after the Phase 0a commit. No uncommitted tracked work.
**Godot:** `4.7.2.stable` via native `tools/godot` (`godot` is **not** on `$PATH`).
**Renderer:** Forward+ · Jolt 60 Hz · 1280×720 base · Linux x86_64.
**Steam reference:** `/home/john/.steam/steam/steamapps/common/Thick As Thieves/`
(appid `3341000`, build `25076818`, `1.5.148559`).

Read this section first: the offline capture attempt failed and the machine has
been restored; the matched-settings capture is still not taken.

---

## 0. Machine state — A path proven; the live capture is the Staff mission, not the Cleanout

The offline finding stands: the shipped launcher needs an online login. On
2026-11-27 the **A path worked**: the copied install (`~/tat2-ref-build`)
launched directly through Proton with the copied prefix
(`/tmp/opencode/tat2-ref-prefix`), reached the startscreen, and the copy wrote
its prefix while the original did not (copy `system.reg`/`user.reg` at
01:23:49; original unchanged at 2026-11-26 23:06). The original install, prefix
and save are untouched. Steam is online for auth; the game may still be at the
main menu.

**Save state (Phase 0a, 2026-11-27):** the copied prefix is **774 files** and
its `SaveGames/` explicitly holds the owner save restored from
`SaveGames.pre-p0b-20261126-230522/.`:
`TAT_ETS.sav` md5 **`976f8730eac989bab1c6c792343b7c00`**, `EnhancedInputUserSettings.sav`
and `steam_autocloud.vdf`. The archive is untouched (same md5), and **never**
run `stage` + `tail -1` to pick it: use the archive path explicitly. The live
capture is deferred as issue **#13**.

The live capture is **not the official route**: it is the **Staff of Edinburgh
Item Collection Heist** (120-minute limit, outdoor canal-side spawn), not the
Cleanout Heist (55-minute, brick safe room). It is two 600 s parts with a
226.5 s unrecorded gap (part 2 was lost to a cleanup kill) and part 3 ends at
541.7 s. Review: `docs/reports/live-ref-review-20261127.md` — 10 beats present /
12 partial / 2 wrong mission / 3 absent; 0 poses present / 3 partial; 55/120
rows have supportable look/geometry or HUD/UI subjects; the 120-row tally is
unchanged (48/56/16).

**Next capture (Cleanout) checklist:**

- **Mission pre-start:** the prep must read `Cleanout Heist` / `Time Limit: 55
  minutes`, and the spawn must be the brick safe room. If it reads `Item
  Collection Heist` / `120 minutes` / Staff of Edinburgh, back out and select
  the `CONSTABLES' GUILDHALL` Cleanout contract; do not start the recorder.
- **A path:** use `~/tat2-ref-build` + `/tmp/opencode/tat2-ref-prefix`; keep
  Steam online for auth; do not use the retired launch option.
- **Recorder:** one 900 s file, started at the **main menu** (the 2026-11-27 run
  opened in the Den and missed S01/S02); 2560×1440, High groups, Resolution
  Scale **100** after the preset, VSync off, 60 cap, FOV 85.
- **Audio:** Master/Music/SFX/Dialogue **80** (or a level whose 10 s test max is
  below −1 dBFS); the 2026-11-27 Master 100 peaked at 0.0 dBFS.
- **Poses:** hold each 3 s; the 2026-11-27 run has 0 poses present, 3 partial.
- **Window title:** `TAT` (the helper now searches both `TAT` and `Thick As
  Thieves`).

The live capture is a P4/ROI reference; the 120-row scorecard is re-scored from
a **port** full-route run, not from the shipped capture. The **official** V6-03
cell was corrected in Phase 0a with a dated erratum: emitter **17.8 %/40.0 %**,
**one** band at **40.0–40.5 %**, cyan node **above the doors**; the old
`y~56 %`/two-beam/ceiling-diamond text was a transcription error. The port-side
cell and the 120 tally stay for Phase 3.

---

## 1. State in one paragraph

The port has completed **P0a/P0b**, **P1 route content**, the **Den spawn
hotfix**, **P2 StateTree v2 shadow runtime**, the **navmesh extraction spike**,
**P3 Wwise control plane**, **P5 UI correctness** and the **data-truth wave**.
The complete 44-gate set passes at `5135f53`; the evidence is in
`docs/reports/logs/final/` and `docs/reports/final-20261127.md`. The port is not
Parity Complete, and the remaining measurement work splits into two tracks that
the previous handoff conflated:

- **120-row scorecard** — already filled against the official clip
  (**9 PASS / 33 DELTA / 4 MISSING / 2 HARD_LIMIT / 16 UNVERIFIED / 56
  N/A-route**, 2026-11-24) but **stale**: it **predates W10**, and V4-07/V6-03
  were re-scored in W9-P1. Re-scoring it needs a new **port** full-route run,
  not a shipped-build capture.
- **Matched-settings live capture** — taken 2026-11-27, but it is the **Staff of
  Edinburgh Item Collection Heist**, not the Cleanout; 10 beats present / 12
  partial / 2 wrong / 3 absent, 0 poses present / 3 partial, 55/120 rows with
  supportable look/HUD subjects, 120 tally unchanged. **No valid Cleanout live
  reference exists yet** (issue **#13**); see §0/§4.1.

Still open: P4 look/exposure, the navmesh runtime consumer, the StateTree shadow
ceiling (`fully_parity_covered_trees=0`, FSM authoritative), partial audio
(14/23 switches, 4/8 states, 16/50 RTPCs), UI headless-only, and the GC
hold-smash `PORT_DECISION`.

---

## 2. Gates at the final tip (measured at `5135f53`, evidence `3d62f6b`)

| Gate | Value |
|---|---|
| compile | **217 checked / 0 broken** |
| `run_tests.gd` | **324 PASS / fails=0** (suites 119 cream, 121 audio registered) |
| M2 | **12 PASS / fails=0** |
| P1 route probes | safe **86**, doors **47**, beams **7**, ward **44**, street **31** (`hard_limits=2`) |
| guards | Guildhall `C_20`, buckets 4/4; Old Manor order 3, 4/4 |
| collision | `COL_MAPS PASS min_coverage=0.869 dropped=0 planar_skipped=2 coverage_ppm=868852` (Guildhall 0.910, Old Manor 0.912, FTUE 0.869; `no_record=0`) |
| locks | `applied=154` (144 containers + 10 door nodes) |
| E2E `all` | **300/300** (T1=117 T2=110 T3=25 T4=14 S2=12 A2=22) |
| E2E p2 | **14/14**, `expected_fail=0 expected_delta=0 fixed=0 unexpected_fail=0` |
| parity-only | **60/60**, 11 rules all `parity_restoration` |
| cream suite 119 | **GREEN**, `CREAM_PROOF: GREEN passes=5` (old RED proof retired) |
| audio control 121 | **71/0** (14/23 switch groups, 4/8 states, 16/50 RTPCs, 142 curves) |
| P5 UI | **44/0** headless |
| Den spawn | **9/0**, `source=authored`, `(5.669,40.117,270.686)` |
| StateTree suite 110 | **191/0**, `fully_covered_trees=1`, `fully_parity_covered_trees=0` |
| navmesh spike | 2,958 tiles / 14,930 polys / 221 off-mesh; consumer 16/0; doorway 3 waypoints / 4.15 m |
| runtime smoke | `RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 mission_ready=1` |
| route self-test (Phase 0a) | `P0B_ROUTE_SELFTEST PASS checks=62 fails=0` (headless wrapper `--self-test`; `bash -n` on the route/live wrappers) |
| audit / texture / perf / ratchet | **PASS** / 796 capped, 1 alpha, 0 offenders / 78/78 / PASS |
| string audit | 311 routed / 199 authored / 112 invented (one documented `Thieves' Den` port copy) |

**Truth corrections, not regressions:** collision `976321 → 868852` (authored
**element** coverage; the old value counted invented render-trimesh fallbacks),
texture cap `797 → 796` from the accepted `texture_refs 1523 → 1522` pants fix.
The old `coverage=0.989` is not a valid authored number; do not restore it.

Phase 0a added `p0b_route_self_test` to `build/qa/run_final_gates.sh` (45
gates). The route self-test and the wrapper `bash -n` checks are green; the
first full **45-gate serial run** is Phase 0b (GPU, clean route2), not yet
measured.

---

## 3. Closed by this session

- **P0a:** guard bucket/layer selection (`C_20`, no Hauntstable), 330 beam cards
  corrected to the authored col2 axis/length, 28-gate evidence.
- **P0b:** suites 117/118/120, E2E `a2`, p2 parity tier, `TAT2_PARITY_ONLY`,
  capture harness, the then-current 35-gate set (cream was still RED then; the
  RED proof has since been retired).
- **P1:** safe-room portal/lantern/SPIDER, S21 blue-door prompt/stack and lock
  band, authored beam material + foyer dressing, ward shards/vines/alarm,
  street car/headlights/horn, gate sign/griffins/gear plate, MACLEOD sign.
- **Den:** the P0a `/Game/Developers/` filter removed the authored Den floor
  (`SM_ThievesDen_Floor`). The filter now skips only `_GENERATED`, `Disc_*`,
  `Debug_*`, `SplineEditorMesh`; the Den spawns at the authored marker
  `(5.669,42.159,270.686)`, grounded player origin `(5.669,40.117,270.686)`,
  with 2434 meshes / 3017 collision shapes. `probe_den_spawn.gd` is the gate.
- **P2-ST:** payload v2 node identity/parameters/bindings, UNKNOWN semantics,
  event gates, coverage split; 566/566 keys, one structural tree, no cutover.
- **P3:** Wwise switch/state/RTPC producer + consumer, first core wiring,
  suite 121.
- **P5:** Light Gem direction/amount, card/compass, pause dim, 11-line briefing,
  hotbar/prompt/prep fixes, 44-check probe.
- **Data:** cream suite 119 green, pants albedo fixed (p2 zero), collision truth,
  GC intact-lid finding (keep the labelled `_Broken` fallback), `Destructibles/`
  dump absent, no extractor root change.

**Traps added to `AGENTS.md`:** `A2-WHITE` samples surface materials, not
`material_override`; a HUD `SubViewport` must set `own_world_3d = true` (the P1
jaw-trap light lit the whole level); the fresh-worktree `--import` class-cache
trap; the narrowed developer-mesh skip; the cream/white fallback rule; the
StateTree shadow ceiling; the authored-element collision floor.

---

## 4. Remaining waves and open items

### 4.1 Live reference (P4/ROI) and the 120-row re-score

- Shipped launcher requires **online login**; Steam Offline Mode gives
  `LOGIN FAILED!`. **A worked on 2026-11-27**; the capture is the Staff mission,
  not the Cleanout. The corrected Cleanout checklist is §0; **C** remains the
  no-launch fallback.
- The 120-row scorecard is
  `docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md`; current
  baseline is **9 PASS / 33 DELTA / 4 MISSING / 2 HARD_LIMIT / 16 UNVERIFIED /
  56 N/A-route** from 2026-11-24. It **predates W10** (V4-07 and V6-03 were
  re-scored in W9-P1); re-score it from a new parity-only **port** full-route
  run (not from the live capture).
- The corrected six-pose port capture is at
  `docs/reports/logs/p0b/20261127T015115Z_fafb78f122d5_bon/` (gate 23.85,
  upper_foyer 40.88, yaw180 39.47, Lounge 28.37, audio 92.8 s); it is not the
  120-row baseline.
- **Staged 27-beat runner (v1):** `build/qa/p0b_route.sh` writes a
  `tat2.p0b_route/1` manifest for all S01–S27 — 13 staged beats, 14 deferred
  with reasons, `route_claim=none` (no played route). **route1 was
  `status=partial`** (S06 `_show_tab` called on the CanvasLayer instead of the
  `LedgerUI` Control); the hook is fixed and **route2 is all-green**
  (`captured=13 deferred=14 partial=0 frame_errors=0 frames=17`, exit 0,
  `docs/reports/logs/p0b-route/route2/`) but it is **`git.dirty=true`** at
  `4341439` (the S06 fix was uncommitted at capture time; it is `f44bc23` in
  the current tree). A **clean route2 re-run is Phase 0b** (GPU). The
  **120-row re-score** is Phase 2 R-2 / Phase 3 R-3. The Guildhall stage is a
  **free-play substitute** (`Mission.Guildhall.LootTheRoom`, contract 2) used
  only for the KF13 letter; it is **not** the official selection (canonical
  contract-2 row: `Mission.Guildhall.VaultHeist`; historical baseline:
  `LootTheRoom`, `free_play=false`). The wrapper exports `TAT2_PARITY_ONLY=1`
  for every mode. Contract, measured runs and the staged evidence index:
  [`docs/reports/p0b-route.md`](p0b-route.md),
  [`docs/reports/p0b-route-rescore.md`](p0b-route-rescore.md).

- **Live-reference review (2026-11-27):**
  `docs/reports/live-ref-review-20261127.md` — the two-part capture is the
  Staff of Edinburgh Item Collection Heist, not the Cleanout; 10 present / 12
  partial / 2 wrong / 3 absent; 0 poses present / 3 partial; 55/120 look/HUD
  rows supportable; the 120 tally unchanged; 226.5 s gap, part 3 ends at
  541.7 s. The **official** KF27 correction (17.8 %/40.0 %, one band at
  40.0–40.5 %, above-door node) is now a dated erratum in the scorecard
  (Phase 0a); the port-side V6-03 cell stays Phase 3. The Cleanout capture
  remains **deferred as issue #13** (save `976f`, 900 s, audio 80).

### 4.2 P4 look (the visible parity gap)

- **Exposure/IBL/AEM:** rooftop/city is near-black (your screenshots), gate is
  ~1.4 stops dark, foyer/Lounge ~1 stop bright. Authored Gloomy chain:
  `AEM_Basic`, EV100 −10…+1, SpeedUp 0.2 / SpeedDown 2.0, bias 0, V3 curve;
  the curve is recorded but not applied. SkyLight cubemap
  `Cubemap_GroundFloor_01` is a 512×512 PF_FloatRGBA TextureCube; the extractor
  has no `UTextureCube` branch and `TextureQueued` filters the package. Need
  producer + consumer (`AT_CUBEMAP_PASS`), a pure `step(dt, ev100)` model, and
  one global calibration offset; no per-room grade, no global 0.44 cut.
- **Mirrors — carried, not re-measured (UNVERIFIED).** 3,312
  negative-determinant instances, 3,215 in MultiMeshes; standalone
  `MeshInstance3D` mirrors are compensated by Godot 4.7, but the MultiMesh node
  is identity. Fix: sign-split + a baked mirrored mesh variant (reverse
  winding/normals/tangents); `CULL_FRONT` is only a single-surface
  `BaseMaterial3D` fast path. Needs the synthetic 2-instance probe in Phase 1
  P4.2; the counts are carried from the earlier audit.
- **Landscape — carried, not re-measured (UNVERIFIED).** Current `vis > 0.5`
  discard is *likely* correct (raw weight 1 = hole; UE node output 1 = visible).
  Do not flip without the raw-mask A/B and the safe-room data assertion in
  Phase 1 P4.4; the stale docs still need correcting.
- **Beam material — qualified, not settled.** The authored-parameter material
  and geometry are a real match (330 cards, `max_axis_err_deg=0.000006`), but
  the route2 `upper_foyer` frame still measures peak row **49.07 %**, excess
  **131.15**, and **12** cream-unexplained 16×9 cells (8 on the beam row),
  against KF27 **40.19 %** and **0.12 %** cream outside the band. The earlier
  "thin line and no cream bars" claim came from a different pose and is
  qualified, not repeated. P4.5 must implement the authored sphere-mask / edge
  / fake-glow terms and re-measure at the KF27 pose. The old "63 moon-plane"
  claim is retired.

### 4.3 Navmesh runtime (authored tiles proven)

The spike emitted 2,958 tiles / 14,930 polys / 221 off-mesh links from the cooked
archive (no bake needed). Next: convert to a generated runtime asset, build one
`NavigationMesh` per map (1.0–1.5 s headless budget, ~60 MB), map authored area
63/62/1/3/4, consume off-mesh links as `NavigationLink3D`, exclude
`swinging_doors`, prove a doorway path, then wire `nav_steering` in a separate
lane. Do not call an offline bake parity.

### 4.4 StateTree patrol cutover (shadow only)

B2.1 reads payload v2 and measures one **structural** tree
(`ST_Subtree_IntruderNoLongerSuspicious`), `fully_parity_covered_trees=0`.
`TAT2_STATETREE` stays `off`; FSM drives. Remaining: a live `StateTreeEvent.*`
bus (0 emitters), `GlobalParameterData` values (`ResetAlertness`, `Target`,
etc. UNKNOWN), Setup Patrol outputs, SharedInstanceData source, and the
smart-object/distraction branch. Navmesh + event bus are prerequisites for
`ST_Patrol` cutover. Do not invent parameters.

### 4.5 Full audio direction (W11)

Control plane is partial: 14/23 switches, 4/8 states, 16/50 RTPCs; state
property rows, music DecisionTree keys and `FS_Layers` are deferred; 645 VO
lines and the full Wwise effects/mix are not wired. The current work is not
"full Wwise parity".

### 4.6 GC / destructibles

- `GC_ChestTrunkALid.AutoInstanceMeshes` is the **intact** lid
  (`SM_ChestTrunkALid`), so the labelled `SM_ChestTrunkALid_Broken` fallback is
  correct; do not use the intact auto-instance as the broken state.
- `extracted/json/Destructibles/**` is absent from the shared tree; the assets
  are in the pak. A future extraction can settle the 93-chest fallback; the GC
  probe expects 336 hidden / 166 leaves / 93 fallback.
- Bookcase loot classes (`BP_Manor_Bookcase_Cabinet_MinorLoot_C/_MajorLoot_C`)
  are not in `parse_containers.CLASSES`/`LOOT_CONTAINER_CLASSES`; the 8 Guildhall
  bookcases carry authored minor/major slots. Open animations/lid shadows and
  the authored damage-driven break (hold-smash is a labelled `PORT_DECISION`)
  remain.

### 4.7 UI visual score / remaining UI

P5 is headless-verified only. A GPU capture is needed for Light Gem appearance
(the 21-slice `T_stealthball_Array` is absent → `PORT_APPROX`), pause blur/line
weights, briefing fit and the `Thieves' Den` port-copy label. The string-audit
ceiling is 112 and must not rise further without evidence.

### 4.8 Data/perf/ship

- `Destructibles/` extraction and GC census.
- Perf matrix / 60 FPS target is **not** run (thermal gate waived); no parallel
  Godot; the host idles near 80 °C.
- Linux export + stamp only when shipping; do not hand-edit
  `build/tat2-linux-x86_64.stamp.json`.
- Expansion is not frozen; `TAT2_PARITY_ONLY` excludes it from parity builds.
  All 11 content-override rules are `parity_restoration`; expansion work must
  stay labelled and out of parity captures.

---

## 5. Recommended next order

1. **Run the corrected Cleanout capture** (§0) if the live reference is still
   wanted: the A path is proven, but the 2026-11-27 capture is the Staff mission.
   The mission pre-start check, 900 s recorder, audio 80 and pose holds are §0.
2. **P4 look** (exposure/IBL/AEM first, then mirrors/landscape) because it is the
   visible gap in the current playtest and blocks honest visual scoring.
3. **Navmesh P1 Detour consumer**, then **P2.3 patrol cutover + event bus**.
4. **Full audio direction** and **GC/bookcase destruction** in parallel where
   files allow.
5. Re-score the 120 rows from a **port** full-route run and raise the ratchet
   only from measured logs.

---

## 6. Commands and hazards

```bash
make run
make test                         # 324 checks
tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"
tools/godot --headless --path game --script res://tests/run_tests.gd
tools/godot --headless --path game --script res://tests/test_m2_player.gd
tools/godot --headless --path game --script res://tests/probe_guard_positions.gd
tools/godot --headless --path game --script res://tests/probe_den_spawn.gd
tools/godot --headless --path game --script res://tests/probe_p5_ui.gd
tools/godot --headless --path game --script res://tests/test_audio_control.gd
tools/godot --headless --path game --script res://tests/test_w10a2_cream.gd
tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd
build/qa/run_final_gates.sh       # 45 gates, logs docs/reports/logs/final/
build/qa/p0b_route.sh --self-test # 62 checks, headless; part of the 45-gate set
make audit && make gate-ratchet
build/qa/runtime_smoke.sh 90      # no outer flock
```

- `build/qa/run_p0b_gates.sh` is the historical P1 40-gate set; the current
  runner is `build/qa/run_final_gates.sh`. Phase 0a added
  `p0b_route_self_test` (route/live `bash -n` + the 62-check self-test); the
  first full 45-gate measured run is Phase 0b.
- One Godot at a time: `flock /tmp/opencode/tat2-godot.lock`.
- A fresh worktree with a copied `.godot` needs
  `tools/godot --headless --path game --import` before scripts using a new
  `class_name` compile.
- Do not weaken a test or lower a floor except the documented truth corrections
  (collision 868852, texture_refs 1522, string 112); any further change needs
  measured evidence and a report note.
- No worker pushes; verify `origin/main` after every merge.
- `game/data/generated/`, `extracted/`, `game/assets/ue/`, `build/` artifacts and
  `game/.godot/` are private/derived; never commit them.

---

## 7. Evidence map

- `docs/reports/final-20261127.md` — 44-gate measured table and truth corrections.
- `docs/reports/phase0a-20261127.md` — Phase 0a save/docs/provenance/gate/issue
  evidence (no GPU; 45-gate runner, not yet measured as a set).
- `docs/reports/logs/final/` — every final gate log.
- `docs/reports/p1-integration-20261126.md` — P1 route content and 40-gate evidence.
- `docs/reports/p5-ui-20261126.md` — P5 UI probe and string audit.
- `docs/reports/w10-p3-audio.md` — Wwise control-plane counts/wiring.
- `docs/reports/w10p2-20261126.md` — data wave, collision truth, cream/pants.
- `docs/reports/navmesh-spike.md` — authored Detour tile extraction/consumer.
- `docs/reports/p0b-live-capture.md` — offline attempt, restore, and the online
  capture runbook (A/B/C).
- `docs/reports/p0b-route.md` — staged 27-beat route runner v1 (schema, beat
  status, deferred blockers, owner GPU command).
- `docs/reports/p0b-route-rescore.md` — route2 staged evidence index (beam/ROI
  numbers, provenance status; no row token changed).
- `docs/reports/live-ref-review-20261127.md` — live-reference review
  (Staff mission, 2026-11-27); plan (`live-ref-review-plan.md`), three lanes
  (`live-ref-lane-r1/r2/r3.md`) and verification (`live-ref-review-verification.md`).
- `docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md` — 120-row scorecard.
- `docs/reference/clip_1795033698901/row_route_matrix.md` and
  `ADJUDICATIONS.md` — the provenance moved from the git-ignored
  `build/qa/review_20261124/` in Phase 0a; the 2026-11-24 capture media and
  frames remain outside git.
- Issue **#13** (deferred Cleanout live reference); issues **#2–#11** triaged in
  Phase 0a (see their labels/comments).
- `docs/FIDELITY_GAPS.md`, `AGENTS.md` — invariants, traps, gate table.
