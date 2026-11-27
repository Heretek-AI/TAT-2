# Handoff — Thick As Thieves Godot 4.7.2 port (next session)

**Repo:** `/home/john/Projects/TAT-2`
**Code/data tip:** `5135f53` (P2/P3/P5/data + Den/navmesh/UI/audio merged).
**Docs/evidence tip / `origin/main`:** `3d62f6b` (44-gate final evidence, pushed)
plus this handoff commit.
**Working tree:** clean. No uncommitted tracked work.
**Godot:** `4.7.2.stable` via native `tools/godot` (`godot` is **not** on `$PATH`).
**Renderer:** Forward+ · Jolt 60 Hz · 1280×720 base · Linux x86_64.
**Steam reference:** `/home/john/.steam/steam/steamapps/common/Thick As Thieves/`
(appid `3341000`, build `25076818`, `1.5.148559`).

Read this section first: the offline capture attempt failed and the machine has
been restored; the matched-settings capture is still not taken.

---

## 0. Machine state — RESTORED; the offline path is disproven; one decision blocks the capture

The shipped build `25076818` **will not run in Steam Offline Mode**: with
`WantsOfflineMode=1` it reaches the launcher's `LOGIN FAILED!` with only `QUIT`.
The launcher requires an online login. The port itself is fully offline; this is
a capture constraint, not a port requirement.

The machine was restored after the attempt. Verified state:

- `compatdata/3341000` is the **original** prefix again; the swapped-in copy was
  removed and no `.orig-p0b` remains.
- `TAT_ETS.sav` md5 `976f8730eac989bab1c6c792343b7c00` matches the archive at
  `/tmp/opencode/tat2-ref-prefix/.../SaveGames.pre-p0b-20261126-230522/`.
  The canonical copy's `SaveGames/` holds only `EnhancedInputUserSettings.sav` —
  there is no fresh `TAT_ETS.sav`; the archive is the only save.
- Steam is stopped; `WantsOfflineMode=0`; no launch option for 3341000.
- The failed attempt used the **original** prefix because the
  `STEAM_COMPAT_DATA_PATH=... %command%` launch option did **not** redirect
  Proton. It rewrote the original's `pfx/system.reg`, `pfx/user.reg` (now
  2026-11-26 23:06) and the prefix's `steamclient*.dll` stubs, and grew
  `vkd3d-proton.cache` 1,743,312 → 1,744,384 B; the `.write` sidecar is now
  0 B. Save/config hashes are unchanged. Both are benign and were not reverted.
- The prefix copy is staged: **771 files vs the original's 775**, so
  `verify-copy` now **FAILs by design**; it is only meaningful before `stage`.
- Host at the last check: **177 G** free on `/home`; **5,143 MiB** VRAM free
  (VRAM moves with the desktop; re-run `preflight`); Proton
  `experimental-11.0-20261112-x86_64`; `buildid=25076818`, `up_to_date:true`
  (last check).

**Options considered (offline is not a fallback):**

- **A — matched-settings live capture, updater out of the path (recommended,
  UNTESTED):** copy the 3.8 GB install to a private path and launch the copy's
  `TAT-Win64-Shipping.exe` directly under Proton with the copied prefix; keep
  Steam online only for auth. Steam never launches the app, so
  `AutoUpdateBehavior=0` cannot replace the reference. The open question is
  SteamAPI init without the `TAT.exe` launcher; Step 6A of the runbook is the
  test.
- **B — Steam Play with the prefix swapped:** stop Steam, snapshot the install
  and appmanifest, `mv` the original prefix aside and `cp -a` the staged copy
  in, then start Steam online. Accept the update race only with owner approval;
  abort on any appmanifest/buildid change.
- **C — no shipped launch:** re-score the 120 rows from the official clip and
  keyframes (`~/Videos/clip_1,795,033,698,901.mp4`, 3840×2160 @ 29.67 fps,
  225.5 s; keyframes in `docs/reference/clip_1795033698901/clean/`), marking
  live-only rows `UNVERIFIED`. This does not need a capture and can run now.

**Decision (2026-11-26, owner):** run **A first with B as fallback**; restore the
archived owner save into the isolated prefix (Steam Cloud off); capture at
**2560×1440**; re-score the 120 rows now from a **port** full-route run. A is
still untested; runbook Step 6A must pass before a scored run.

**Do not press Play in Steam until the Step 6A isolation proof is in place.**
The runbook is `docs/reports/p0b-live-capture.md` §5; the pre-attempt Offline
Mode and launch-option instructions are retired. The live capture is a
matched-settings **P4/ROI** reference; the 120-row scorecard is re-scored from a
**port** full-route run, not from this capture.

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
  N/A-route**, 2026-11-24) but **stale**: it predates every wave. Re-scoring it
  needs a new **port** full-route run, not a shipped-build capture.
- **Matched-settings live capture** — still not taken; it is the P4/ROI
  instrument for exposure/look, not the source of the 120-row tally. Its
  offline path is disproven; the owner's decision is **A first, B fallback**
  (§0).

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
| audit / texture / perf / ratchet | **PASS** / 796 capped, 1 alpha, 0 offenders / 78/78 / PASS |
| string audit | 311 routed / 199 authored / 112 invented (one documented `Thieves' Den` port copy) |

**Truth corrections, not regressions:** collision `976321 → 868852` (authored
**element** coverage; the old value counted invented render-trimesh fallbacks),
texture cap `797 → 796` from the accepted `texture_refs 1523 → 1522` pants fix.
The old `coverage=0.989` is not a valid authored number; do not restore it.

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
  `LOGIN FAILED!`. **Decision: A first, B fallback** (see §0); **C** remains the
  no-launch fallback. A build preflight is not update protection.
- The 120-row scorecard is
  `docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md`; current
  baseline is **9 PASS / 33 DELTA / 4 MISSING / 2 HARD_LIMIT / 16 UNVERIFIED /
  56 N/A-route** from 2026-11-24, predating every wave. Re-score it from a new
  parity-only **port** full-route run (not from the live capture).
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
  `docs/reports/logs/p0b-route/route2/`). The **120-row re-score is still
  next**. The Guildhall stage is a **free-play substitute**
  (`Mission.Guildhall.LootTheRoom`, contract 2) used only for the KF13 letter;
  it is **not** the official selection (canonical contract-2 row:
  `Mission.Guildhall.VaultHeist`; historical baseline: `LootTheRoom`,
  `free_play=false`). The wrapper exports `TAT2_PARITY_ONLY=1` for every mode.
  Contract and measured runs: [`docs/reports/p0b-route.md`](p0b-route.md).

### 4.2 P4 look (the visible parity gap)

- **Exposure/IBL/AEM:** rooftop/city is near-black (your screenshots), gate is
  ~1.4 stops dark, foyer/Lounge ~1 stop bright. Authored Gloomy chain:
  `AEM_Basic`, EV100 −10…+1, SpeedUp 0.2 / SpeedDown 2.0, bias 0, V3 curve;
  the curve is recorded but not applied. SkyLight cubemap
  `Cubemap_GroundFloor_01` is a 512×512 PF_FloatRGBA TextureCube; the extractor
  has no `UTextureCube` branch and `TextureQueued` filters the package. Need
  producer + consumer (`AT_CUBEMAP_PASS`), a pure `step(dt, ev100)` model, and
  one global calibration offset; no per-room grade, no global 0.44 cut.
- **Mirrors:** 3,312 negative-determinant instances, 3,215 in MultiMeshes;
  standalone `MeshInstance3D` mirrors are compensated by Godot 4.7, but the
  MultiMesh node is identity. Fix: sign-split + `CULL_FRONT` on the mirrored
  batch, with a synthetic 2-instance GPU test.
- **Landscape:** current `vis > 0.5` discard is likely **correct** (raw weight
  1 = hole; UE node output 1 = visible). Do not flip without the A/B; correct
  the stale docs and add raw-mask tests.
- **Beam material:** already authored-parameter match; capture shows a thin
  line and no cream bars. The old "63 moon-plane" claim is retired.

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

1. **Execute the chosen live-capture path** (§0): **A** first (runbook Step 6A),
   **B** as fallback. Offline is retired; a preflight is not update protection.
   Do not fabricate measurements.
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
build/qa/run_final_gates.sh       # 44 gates, logs docs/reports/logs/final/
make audit && make gate-ratchet
build/qa/runtime_smoke.sh 90      # no outer flock
```

- `build/qa/run_p0b_gates.sh` is the historical P1 40-gate set; the current
  runner is `build/qa/run_final_gates.sh`.
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
- `docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md` — 120-row scorecard.
- `docs/FIDELITY_GAPS.md`, `AGENTS.md` — invariants, traps, gate table.
