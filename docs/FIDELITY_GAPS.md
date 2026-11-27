# TAT-2 Fidelity Coverage (1:1 rebuild tracker)

Source of truth: `/home/john/.local/share/Steam/steamapps/common/Thick As Thieves/`
extracted through `tools/tat-extract` (CUE4Parse, `EGame.GAME_UE5_5`).

Generated from `extracted/filelist.txt` (22,005 entries) and the current `extracted/` tree.
Re-run the census with the commands at the bottom.

## P1 status — 2026-11-26 (newest; supersedes the P0b section below where they differ)

The P1 route-content wave restored the S12–S26 subjects in five lanes (safe room,
blue doors, beams/foyer, ward/alarm, street) and measured them at
`78884fe` (`3998761` merged tip + one integration fix) in one serial run of
`build/qa/run_p0b_gates.sh`: **40 gates** plus the cream expected failure, logs
in [`reports/logs/p1/full/`](logs/p1/full/), report
[`reports/p1-integration-20261126.md`](reports/p1-integration-20261126.md).
`compile` is **213/0**, `run_tests` **322**, E2E **300/300**, p2
`expected_fail=1 expected_delta=0`, and the five lane probes are
**86 / 47 / 7 / 44 / 31** checks. **P1 is not Parity Complete**: it makes the
route subjects present and scoreable; the visual score still needs a port
capture, and the live reference/120-row baseline remain unscored (no GPU run in
P1).

- **Safe room (S12/KF14) — present.** `SafeRoomPortalOutline` (authored
  `BP_EscapePoint` emerald `#7EFF9B` / violet `#C651FF`, `SummonBox` size, violet
  `Door_Light`), the `BP_ToggleableLanternA` port (`5.0` / `#FFC277` / 80° /
  4.5 m spot, glass emission 6.0, `[F] TURN ON`/`[F] TURN OFF`), and the
  `"SPIDER"` `SM_PosterWantedA` flyer (UV cell proven) are anchored to authored
  landmarks. The shimmer/particle components remain `APPROX_SHADER` (HL-1).
  V6-01, G1-05, V1-04 scoreable.
- **Blue double doors (S21/KF24) — present.** The four authored
  `BP_Manor_Porch_Door_8x8_C` pivots spawn; the leaf binds **two** authored slots
  in GLB order (`MI_TrimMetalA_brass` diamond mullions + twin pulls,
  `MI_ManorTrim` slab). There is no authored “blue paint” or glass material —
  those reads are lighting. The HUD secondary row is a real keycap +
  `[F] [HOLD] LOCK`, flipping to `[F] CLOSE`; `[HOLD] LOCK` re-locks inside the
  authored `MinLockLevel 2 / MaxLockLevel 3` band (floor used for an unlocked
  door, `PORT_DECISION`). V3-03, UI2-05 scoreable; PG-2’s lockpick art is
  **HARD_LIMIT** (dial exists with authored arc parameters; the UMG widget tree
  is absent from the dump) and its node-name mapping is `PORT_DECISION`.
- **Beams / foyer (S24/KF27) — authored-parameter match.** `tat_beam.gdshader`
  now carries the authored `MI_LightBeam_SM` model: 1.5 cm centre line at
  opacity 0.5, 6 % fake glow (8.5 cm), 25 m fade, HDR `(5.0, 4.3813, 3.5156)`
  × 3.0, additive/unlit/two-sided; the P0a column-2 axis/length fix is
  untouched (330 cards, `max_axis_err_deg=0.000006`, `clamped=0`). The foyer
  vitrine/armchair/plaque/floor-plate dressing is built; the exact shipped cyan
  ceiling node is **HARD_LIMIT** (the POI record is `hidden_in_game: true`;
  the visible KF27 node is a BP/Niagara overlay) and the port uses a labelled
  `PORT_APPROX` lozenge at the authored light position. V6-03, V4-07 scoreable.
- **Ward / lockdown / alarm (S25–S26/KF28–29) — restored.** The flat violet
  pane is gone: `ward_zone.gd` adopts the authored `SM_BlockerWard_*` shards
  (233/233 paired on Guildhall, 6 m nearest-ward cap, 7-shard foyer cluster),
  `vine_lock.gd` reproduces the authored `BP_OneWayBarrier` green door ward
  (2.6 × 3.4 m plane, `0.16 × 2.56 × 3.36 m` BlockerBox, tint
  `(0.1334, 1.0, 0.0)`), and a beam trip seals both and raises the jaw-trap
  status icon. Contact-dwell shatter → ward/vine collapse + crimson alarm
  spotlight (authored cone 15° / range 15.32772 m; colour/energy `APPROX_LIGHT`)
  + `guard_alerted` sting. The Kismet shatter trigger is a `PORT_DECISION`
  (HL-3). V6-04, G5-03, G5-04, V1-07, UI5-06 scoreable.
- **Street / car / gate / MACLEOD (S13–S20/KF15–16/18/23) — present.** The
  authored `BP_Automobile_Truck_A_Alarm_C_3` carries `[F] INTERACT`, the
  authored `Play_Obj_Vehicle_Car_Horn_OneOff`, the 10 s alarm with the 2 s
  headlight flash (50 lm, `CurveFloat_2` keys 0/1/0), and the authored
  `AI.Stim.Hearing.CarAlarm` row (50 m). `SM_SignMacleod` emits the authored
  `M_Crystal_Glow` tint at the 4.0 loader cap (authored 5.0). Crates, ladder,
  weeds, wall light, gate sign (4 surfaces), 2 griffins and the transformer
  plate are authored and pinned; the wet path uses the existing
  `ground_wetness=1.0` + Puddle bindings. V4-05, V4-06, V1-05, V3-01, G1-04,
  AU5-01 scoreable; V4-04 is **PARTIAL**.
- **HARD_LIMITs recorded, not faked.** `BARRON'S DEMOLITION` banner (0 name
  hits in the extraction; the only banners are the blue `KILCAIRN`
  `T_BannerSet_D` set), KF15 fallen-drum placement (assets exist, no placement
  within 12 m of the alley), the exact cyan KF27 node, and the circular-lockpick
  widget art. Beam pixel falloff and the ward/vine shader graphs are
  `PORT_APPROX`; the indirect lantern bounce is HL-7.
- **Integration fix.** The first run at the merged tip `3998761` failed
  `A2-WHITE` (1 unexplained near-white node: `SafeRoomPortalOutline` carried
  only a `material_override`, which the audit’s surface sampler read as
  glTF-default white). `78884fe` binds the same shader on the QuadMesh surface
  and keeps the override; the red proof is committed under
  `reports/logs/p1/pre-fix/`. No test was weakened.

## P0b status — 2026-11-26 (prior; the P1 section above supersedes where they differ)

The parity instruments and the honest acceptance baseline, measured on `dfa8c7e`
in one serial run by `build/qa/run_p0b_gates.sh` (35 gates + the cream expected
failure). Evidence: [`reports/p0b-20261126.md`](reports/p0b-20261126.md) and
[`reports/logs/p0b/full/`](logs/p0b/full/). **P0b is not Parity Complete**; it
builds the instruments and records what is still wrong.

- **Parity-only governance — `PARITY_RESTORATION` vs `TAT2_EXPANSION`.** Every
  rule in `game/data/expansion/content_overrides.json` now carries a
  `parity_class` (11 rules, all `parity_restoration`) and the producer/checker
  fails closed on an unclassified rule. `TAT2_PARITY_ONLY=1` (default off)
  excludes every registered expansion record/node (prep skyline, personal
  Spider quest, co-op transport, briefing overrides, candle-fire nodes) and
  applies only restoration rules; off changes nothing. `test_parity_only.gd`
  proves both directions and that no shipped marker/guard/GC/loot record is
  dropped: **60/60**, 11 classified rules, 0 unclassified. This is the build the
  120-row scorecard must use.
- **Acceptance harness — tier `a2`.** One real Contract 02 Novice load now runs
  in the full E2E suite (and standalone): boot identity, guard marker/distance/
  floor/bucket, the Lounge `C_20` guard in the tracked bbox, 3 civilians with 9
  bound surfaces and `default_white=0`, a scene-wide near-white audit with 0
  unexplained, the Lounge shell rays, the 1,145-part turret census and the GC
  runtime census (`layers=174`, `leaves=80`, `visible_broken=0`, `missing=0`).
  E2E is **300/300** (T1=117 T2=110 T3=25 T4=14 S2=12 A2=22); `run_tests` is
  **322** (suites 117/118/120).
- **Parity tier `p2` — pants is the only expected failure; beam promoted.**
  12/12 with `expected_fail=1` and `expected_delta=0`: the civilian **pants
  albedo** remains a producer defect (`parse_materials` puts the authored
  `T_CivFemale_Common_01_Pants_D.png` in the `opacity` slot and
  `T_Civ_M_01_Top_D.png` in albedo). P1-BEAMS (`372bf74`) replaced the
  full-tube beam with the authored centre-line material, so the beam is no
  longer a DELTA. The gate is `unexpected_fail=0`; the data wave promotes
  `fixed` when the pants producer is repaired.
- **Cream — beam cards confirmed; invented-white fix still RED.** The visible
  cream bars in the 2026-11-26 capture are the `SM_LightBeam` cards (axis
  fixed, full-tube material), not the moon planes. `test_w10a2_cream.gd` remains
  a standalone RED proof (not suite 119): `_apply_ue_emissive()` still invents
  white for an `EmissiveStrength`-only material and the loader has no
  `tat_invented_white` counter. The authored moon cards are safe (122/122
  `hidden_in_game`); the invented-white path is a separate data-wave fix.
- **Capture instruments — port capture run, live reference pending.** Six fixed
  poses (`gate`, `upper_foyer`, `yaw180`, `lounge`, `lounge_beam`, `beam_close`)
  at the shipped 54.54° vertical lens, 1920×1080, 60 settle + 5 median frames,
  a Master-bus `AudioEffectCapture` tap with a headless `dummy_audio_driver`
  fallback, a tracked manifest (HEAD/seed/lens/pose), and the ROI script
  (luma/percentiles, beam rows, 16×9 cream map, KF27 criteria). The dry-run
  manifest validates (`poses=6`), the self-test is **21/21**, and the KF27
  reference frame scores **7/7**.
  The first port run is
  `docs/reports/logs/p0b/20261126T210338Z_5301fc661750_bon/` (1920×1080, 93 s,
  audio 85.3 s at RMS −36.50/peak −15.12 dBFS; gate 23.2/10, upper_foyer
  45.8/29, yaw180 39.0/31, Lounge 28.6/23, lounge_beam 24.4/23, beam_close
  20.8/19); it confirmed the visible cream bars were the `SM_LightBeam` cards.
  After the P1 beam material and HUD-world fixes, the corrected run is
  `docs/reports/logs/p0b/20261127T015115Z_fafb78f122d5_bon/` (1920×1080, 98 s,
  audio 92.8 s at RMS −36.38/peak −15.69, 0 dropped; gate 23.85, upper_foyer
  40.88, yaw180 39.47, Lounge 28.37, lounge_beam 24.52, beam_close 21.02).
  The frames show the authored thin beam line, no cream bars, and the P1 foyer
  dressing. The P1-W HUD status-icon SubViewport had shared the gameplay
  `World3D` (its `DirectionalLight3D` lit the level); `own_world_3d = true` in
  `status_icon.gd` fixed it. The live reference and 120-row baseline remain
  **PENDING** owner steps; PNGs are ignored, manifests/logs tracked.
- **Live reference — prepared, not launched.** The appid 3341000 prefix is
  copied and verified at `/tmp/opencode/tat2-ref-prefix`; the blockers (Steam
  auto-update `AutoUpdateBehavior=0`, 2.2–2.5 GiB free VRAM, Wayland capture
  path, Steam Cloud overwrite risk) and the exact offline launch/capture steps
  are in [`reports/p0b-live-capture.md`](reports/p0b-live-capture.md). No Steam,
  Proton or game process was started by the prep lane.

## P1 Lane T — street / car / gate / MACLEOD (2026-11-26)

P1 route-content lane T. Evidence: [`reports/p1-street-20261126.md`](reports/p1-street-20261126.md)
and the tracked probe log under `reports/logs/p1-street/`.

- **KF16 car interact — restored.** `game/src/interact/street_car.gd` adds the
  authored `[F] INTERACT` on `BP_Automobile_Truck_A_Alarm_C_3` at
  `(19.0, 18.5304, 66.3382)`, plays the authored
  `Play_Obj_Vehicle_Car_Horn_OneOff` and drives the authored 10 s alarm flash
  (2 s loop, keys 0@0 / 1@0.2–1.0 / 0@1.1, 50 lm) on the two KF16 headlight
  spots. The authored `AI.Stim.Hearing.CarAlarm` row is emitted (50 m, Heavy,
  Long). Lens emission is dark at rest and pulses to the authored 2.0 during
  the alarm; the existing 2.0 override remains the fallback.
- **KF23 `MACLEOD` — emissive restored.** `SM_SignMacleod` binds the authored
  `M_Crystal_Glow` tint `(1.0, 0.361, 0.078)`; the post-load override enables
  that emission at the loader's existing 4.0 ceiling (authored `Emissive
  Amount 2 = 5.0`). Placement `(116.6284, 53.2895, 22.6352)` is the authored
  PeripheryA record. `APPROX_SHADER` remains for the final exposure check.
- **Already authored and measured:** 19 crates within 10 m of the KF15 alley,
  the two truck ladders, the weeds and the authored bulkhead wall fixture; the
  `SM_Guildhall_Sign` 4-surface arch, two `SM_StatueGriffonA`, and the white
  10-bolt `MI_ElectricalTransformer` / `T_ElectricalTransformer_D.png` plate;
  the gloomy `ground_wetness=1.0` + Guildhall landscape `Puddle` layers on the
  existing `tat_landscape.gdshader` path (no new shader).
- **HARD_LIMIT — `BARRON'S DEMOLITION` banner.** No `barron`/`demolition`
  name exists in the extracted JSON/assets or the nine relevant Guildhall
  level JSONs. The only banner assets are `SM_BannerB` /
  `SM_BannerWall_IronBeam` with `T_BannerSet_D.png` (the blue `KILCAIRN`
  heraldic banner), not the KF15 brick-wall banner. Not invented.
- **HARD_LIMIT (placement) — KF15 fallen steel drums.** The authored
  `SM_Metal_BarrelA/B/C` assets exist and are placed elsewhere in PeripheryA,
  but there is no barrel/cask placement within 12 m of the KF15 alley.

## P0a status — 2026-11-26 (supersedes the sections below where they differ)

Parity restorations plus the evidence repair, measured on `84912ee` in one serial
run by `build/qa/run_p0a_gates.sh` (28 gates). Evidence:
[`reports/p0a-20261126.md`](reports/p0a-20261126.md) and
[`reports/logs/p0a/`](logs/p0a/).

- **Guard selection — `PARITY_APPROX`.** `tools/parse_tables.py` now carries the
  authored `VariationSpawner.SpawnBucket` and `Layers` into every generated guard
  marker (`Guildhall_Gameplay`: 116 markers, 116 with bucket, 113 with layers, 0
  unresolved). `guard_placement.gd` selects one guard per authored `spawn_layer`
  first, then fills from the remaining eligible guard-bucket markers in authored
  order (10–120 m from the anchor; `Hauntstable`, civilians and SmartObject posts
  excluded). Guildhall Contract 2 `--order=2` selects `Guard_3` at the authored
  Lounge marker `C_20` (`DA_SpawnBucket_StandardGuards_Bouncers`, four
  `Security_GroundFloor_Lounge_*` layers); all `4/4` selected guards have a guard
  bucket and none is Hauntstable. Old Manor `--order=3` (labelled Novice) also
  selects `4/4` guard buckets (`PrivateSecurity*`). The 4/6/8 difficulty count
  remains a labelled **`PORT_DECISION`**; a live Contract 02 capture is still
  needed to confirm counts/positions. Gates: `probe_guard_positions` Guildhall +
  Old Manor, `test_w10a2_guard_placement` (35 checks).
- **Security beams — `PARITY_RESTORATION` (geometry).** `beam_card_transform()`
  applies the merged record/device **column 2** as the authored beam axis (the
  SM_LightBeam component's `RelativeRotation.Yaw=90` makes the 0.102 m mesh long
  axis run along the actor's local +Z) and the authored `BeamLength`/scale there;
  the old column-0 scaling made all 330 cards 90° cross-beam bars. All 330 cards
  (134 Guildhall + 196 Old Manor) pair 1:1 with their detector record;
  `max_axis_err_deg=0.000006`, `max_len_err=0.0406 %`, `clamped=0`; Old Manor's
  authored maximum `236.9539` (24.169 m) is applied verbatim (the removed 200
  ceiling would clip 5/196; the old 40 m clamp would clip 322/330). The beam
  **material is now an authored-parameter match**: 1.5 cm centre line, opacity
  0.5, 6% fake glow, 25 m fade, tint `(5.0, 4.381, 3.516)` × 3.0,
  additive/unlit/two-sided; the corrected 2026-11-27 capture shows a thin line
  and no cream bars. The exact UE graph remains `APPROX_SHADER`; the p2 beam
  delta was promoted (`expected_delta=0`).
- **Destructibles / GC — `PORT_DECISION`.** The authored destruction payload is
  336 hidden GeometryCollection components on 264 actors; a real `Guildhall_Loot`
  load builds **95** hidden broken layers (48 chest + 31 display case + 16
  bookcase) and 79 visible intact leaves, and a break swaps leaf → broken with
  exactly two overlays visible (`visible_broken=2 of 95`, the rest still hidden).
  The deliberate held-secondary smash (same stacked hold doors use) is the only
  break path; ordinary tap keeps the lockpick path. That smash is a temporary
  **`PORT_DECISION`** — the authored damage path is required before Parity
  Complete. Gates: `probe_gc_destruction` (44 checks) + `test_gc_break_trigger`
  (21 checks).
- **Turrets and civilian (measured here; landed between W10-A and P0a).** 229
  turret actors now emit **1,145 visible parts, 0 hidden** (`TURRET_PROBE PASS`);
  the civilian body/head is dressed and sight casts from the head
  (`W10A2_CIV_SUMMARY: fails=0 passed=22`). These replace the W10-A handoff's
  "all 229 turrets invisible" / "untextured, blind civilian" entries.
- **Landscape — no change, no new pixel claim.** The landscape docs remain
  authoritative: 210/210 components across OldManor/Startscreen/Guildhall have
  real heightmaps + weightmaps and the two-weightmap/five-slot blend
  (`reports/landscape-weightmaps.md`, `reports/visual-polish.md`, A5 below), with
  the `discard_holes=0` Guildhall rule. P0a is headless: landscape splines/grass
  are still unparsed and the visibility-convention reference sample is still open
  (`HANDOFF_NEXT_AGENT.md` §3.3); do not treat this wave as landscape verification.

## W10-A status — 2026-11-25 (supersedes the sections below where they differ)

Correctness-and-evidence wave: nine reported defects, each with a red proof and a green
gate, plus the probe/ratchet hardening that keeps the claims re-derivable. Evidence:
`build/qa/w10/a-report.md`, `docs/reports/w10-gate-ratchet.md`, and the committed logs in
`docs/reports/logs/w10/`.

**Closed by W10-A**

- **Screens:** `PostMatchUI.continue_requested` has a consumer (the screen closes, the HUD
  restores focus); main-menu focus is restored after Settings/Tutorial (`closed` →
  `FocusNav.install` + `restore()`); ESC on the post-match/progression screens no longer
  opens the pause menu behind them (shared `FocusNav` frame stamp, the lockpick protocol);
  timeout/door-collapse render `TIME EXPIRED` / `MAGIC DOOR COLLAPSED` instead of "Caught"
  (HUD *and* PostMatchUI, authored rows unchanged for capture/escape); the HUD owns at
  most one rack-up `CanvasLayer` (replace, never stack). Suite **112** (39 checks).
- **Runtime:** the StateTree NDJSON trace has a hard file budget (8192 rows / 16 MiB) with
  a reported `file_dropped` count — the ring contract is unchanged; `runtime-smoke` now
  fails on `ERROR:`/`push_error`, accepts exit **124 only**, checks `mission_ready`, keeps
  its log, and has a documented teardown allowlist plus a 29-check self-test. Suite **113**.
- **Collision:** a coplanar authored **convex** element emits no collider
  (`planar_convex_skipped`, named by `COL_PLANAR`): the 160 `SM_SlowWardZone_Quad`
  billboards (82 Guildhall + 78 OldManor) and 2 `FXSHAPES_1_*` quads (the third coplanar
  convex element is the ward quad itself). The box `2 cm` clamp stays, and is now
  *measured*: it fires on 27 box elements across 18 placed meshes (295 placed instances
  once the 20 `/Engine/BasicShapes/Plane` instances are excluded, 235 of them glass) — real
  thin solids, not effects billboards. Stair meshes are exempt from the 16-hull reduce cap, so the
  OldManor tower flight (36 hulls) is per-element and walkable. Suites **115/116**.
- **Locks:** `CanBeLockpicked` now resolves through a named authored default
  (`AUTHORED_CAN_BE_LOCKPICKED_DEFAULT = true`) instead of an `else` accident; the
  exclusion label is `unpickable` (26 of 33 explicit-false actors carry no `KeyTag`).
  Suite **114** + `build/qa/w10/check_lock_cdo.py`.

**Defect 8 — NOT REPRODUCED (documented, not "fixed")**

`StaticMeshActor_528` (the Guildhall prison door) is **pickable as authored**. The dump is
a delta serialisation, so an absent `CanBeLockpicked` means "inherit", and the resolved
value is `true`: a door on the *same* native class (`BP_Res_Int_Doorway_C`, FTUE spawn
area) writes `CanBeLockpicked: false` explicitly, which a delta dump would have discarded
if the inherited value were already `false`; 33 placed actors author `false` and not one
authors `true`. The actor is also the only key-tagged POI actor with no `KeyItemInfo`, so
"key-only" would leave it unopenable. Evidence: `build/qa/w10/re-1-locks.md`; gate:
`check_lock_cdo.py` (31 classes, exactly one resolves `false` — unplaced — 33/33 placed
`false` explicit).

**Open, found by W10-A (recorded, not hidden)**

- **Prison-door lock level:** the authored `MaxLockLevel` resolves to **4** (inherited from
  `BP_SwingingDoor_C`), but `tools/parse_tables.py` emits instance deltas only, so the
  record has no cap and the port locks at **1**. A fix is a producer chain resolution +
  regeneration (integrator) and a deliberate difficulty change (LV4 pick on the cell door).
- **Collision coverage is per map, not universal:** 233 of the 1,667 distinct placed mesh
  paths repo-wide still have no `mesh_collision.json` record (mostly `/Game/Test/` graybox,
  `/Engine/`, third-party cobwebs); they keep the heuristic collider. The extended probe
  measures Guildhall, OldManor and FTUE separately — see the W10-A report.

## W9 status — 2026-11-25 (supersedes the sections below where they differ)

Four phases, 34 commits, every phase audited by an agent that did not write the code.
Measured detail: [`reports/w9-remediation-20261125.md`](reports/w9-remediation-20261125.md).

**Closed by W9**

- **Collision is authored data — not "every mesh".** Guildhall-15: **937/947 collidable
  paths (98.9 %)**, `dropped=0`, 30,901 shapes, and **+2,878 instances** the old 0.45 m AABB
  gate discarded. The 10 remainder are `/Game/Test/` graybox paths with no dump (heuristic);
  14 payload meshes are `complex_as_simple` (the render trimesh *is* the authored answer),
  and 233 of 1,667 distinct placed paths repo-wide have no record. Three producer bugs
  fixed on the way (full-vs-half extent, capsule axis, convex bake scale). W10-A measured
  all three load sets separately: **Guildhall 937/947 (0.989), OldManor 687/692 (0.993),
  FTUE 535/548 (0.976)**, `dropped=0` on each.
- **Progression is authored.** Level cap 25 with XP preserved, authored award, endgame
  precedence KF13 → 1200/600/300 → QG → 480, FTUE 5,000 migrated once, 48 market gates.
- **Locks are authored only.** 154 runtime locks applied (144 de-duplicated container
  placements + 10 door pivot nodes; 363 is the raw record join and 8 window actors are
  excluded by class); zero invented levels; the LV4 `ESC` no longer escapes into the pause menu.
- **UI reads the authored tables.** String routing 26 → 306; authored-mappable 195/195;
  post-match, progression and tutorial screens exist; pad focus walks 10 screens / 58
  controls; the TAB map consumes all 13 `TATWorldMapBoundary` actors.
- **Prep composition matches KF11** in pixels: mean 37.1 vs 37.2, black floor 18.8 % vs
  22.9 %, skyline visible (RMSE 9.1 %) via a **cull rule**, not a camera move.
- **A runtime-error gate exists.** `make runtime-smoke` boots a real mission and fails on
  any `SCRIPT ERROR`; a footstep-occlusion type error had spammed every step while E2E
  reported 278/278.

**Open after W9 (recorded, not hidden)**

- **Interior brightness**: upper foyer p50 **29 / 1.1 %**, `yaw180` **31 / 2.5 %**, against
  13–15 / 9–24. Fill removal recovered 5 of ~19 points; the remainder is authored-light
  level plus highlights (p95 182 vs 34). The next attempt must be the **temporal**
  `AEM_Basic` adaptation (0.2 f-stops/s, ~20 s), validated against the gate pose too — a
  spatial or scene-wide grade was tried and **failed its pre-registered criteria**.
- **StateTree ceiling:** 18/77 task and 6/36 condition classes mapped; **0 of 21 trees
  fully evaluable** because the payload drops node parameters. Runs in shadow
  (`TAT2_STATETREE=off|shadow`); the FSM still drives. Contract:
  `build/qa/w9/p4-t01-contract.md`.
- **IBL** remains an approximation until the SkyLight cubemap export exists
  (`available=false, sky_contribution=0.0` in the live log).
- **Lockpick** ships a labelled stand-in (41 assets, 0 animations).
- **VFX sprites:** 6 soft-mask textures bind; 34 of 39 placed materials keep the procedural
  falloff; the ceiling without new shader modes is 15/39.
- The 600×600 `KillZ` floor is **PORT INVENTED** (no authored KillZ).
- Suite-45 stairs flake observed once; a clean rerun is recorded in the P4 report.

## R8 remediation status — 2026-11-25

The tables below predate the R8 wave and are **not** authoritative for the areas it
touched. Twelve remediation teams audited and then fixed the port against the shipped
build; the measured detail is in
[`docs/reports/r8-remediation-20261125.md`](reports/r8-remediation-20261125.md), the
audit that motivated it in [`docs/reports/re-audit-20261124.md`](reports/re-audit-20261124.md),
and the recorded-run evidence in
[`docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md`](../reference/clip_1795033698901/COMPARISON_PORT_20261124.md).

**Closed by R8** (each with a red proof and a regression test):

- Guildhall lighting: 976 authored lights were reduced to 159 by a global energy rank;
  now 154 of 189 room bubbles are covered (was 95) and 63 of 64 gameplay interiors are lit
  (was 31). Exposure applies to the preset maps actually use, with the authored EV curve.
- Mission-prep stage: the authored `CameraActor_0` is restored (13 → 387 mesh pivots inside
  the authored 10° cone) and the skyline is re-authored to ≤0.54 frame widths.
- Materials: 110,396 binds carried tints in the wrong colour space (447 materials) — now
  zero; 776 instances bound the wrong slot by name — now zero; `M_sf2_birch_bark` and
  `M_BlockerWard` bind their own art.
- Collision: the authored `AggGeom` is extracted (8,601 elements) and is the collision
  source instead of render-AABB heuristics.
- Animation: clips were `(N−1)/N` of their authored length; damage fired at swing frame 0;
  the takedown played on the wrong rig — all three fixed and proved.
- AI: the blackjack is winnable (detection 61.25 → 0.00 at the same 0.45 s hold), the sight
  model is the authored one, ranged combat exists, and hearing occlusion uses 285 portals.
- Input: the authored IMC table drives 39 InputMap blocks; right-stick look, rebinding and
  rebind-aware prompt glyphs work.
- State: corrupt saves are quarantined instead of overwritten, the payout outbox has real
  callers, and co-op resolves host-authoritatively.
- Audio: the Wwise control plane is produced and consumed (130 buses, per-event attenuation,
  occlusion, music, 645 VO lines, emitted from 90 emitters).
- VFX: activation flags are honoured (3,308 → 1,048 instances), 810 placements carry
  decoded parameters, sprites sample for 5 systems, and culling exists.
- Geometry: splines loft, LevelInstance coverage is 190/190, the authored streaming graph is
  consumed, and 307 misplaced origin markers are fixed.

**Still open after R8** (deliberate, documented, or blocked):

- Candle **lights** remain 0/135 by design (sconce glows; a slot costs a room its practical).
- The authored SkyLight **cubemap export** is not produced yet (T01 contract), so IBL is a
  documented approximation.
- Lockpick has 41 assets and **0 animations**; the dial minigame has no hand animation.
- VFX sprite resolution is wrong-token for most systems (6 of 29 textures pass the soft-mask
  gate); the authored "footstep" texture is a crate decal used as a thief-vision mask.
- Texture streaming/eviction is deferred; the roughness bake is ~54 % of the Guildhall
  scene build.
- The authored `FrustumPitch −22°` caps a guard's view at +0.75° elevation — faithful, but
  it changes stealth and needs a playtest (`--sight-frustum=off` isolates it).
- The prep composition and the new interior lighting still need one capture to confirm the
  pixels, not just the numbers.

## Summary

| Area | In install | Extracted / parsed | Status |
|---|---|---|---|
| Packages (`.uasset` + `.umap`) | 13,162 (12,547 TAT) | 12,541 JSON dumps; 12,439/12,547 TAT packages = 99.1 % | **done** |
| Static/skeletal meshes | 1,852 `SM_` + 156 `SK_` | 2,065 GLB (`2,047` GLB-ordered + `18` sidecar `mesh_materials.json`) | **done (`6783c2d`)** |
| Textures | 2,211 `T_` packages | 2,529 PNG; all 3,817 material texture refs exist; 1,059 exceed 1024 px (773 loader-managed capped; 1 alpha-critical decal kept full-res by design) | **done, with a documented 1024 px cap and a stale-cap gate** |
| Levels | 107 `.umap` | 107 `.tatlevel.json` (`159,941` orthonormal bases, `OverrideMaterials`, `bVisible:false`/`SplineEditorMesh` filtered, `1,293` emissive CPD shapes) | **done (`7458198`, `24cac7e`, `d0f895a`)** |
| DataTables / CurveTables / StringTables | 58 `DT_` / 79 `ST_` / curves | 144 normalized tables | **done** |
| **Animations** | **879 `AN_`** | **995 GLB clips** + **3,594 authored notifies** / 235 montage sections; 14 blend-space graphs unsupported | **export done; ~90 clip names wired, notifies data-only** |
| **Weather / atmosphere** | 16 presets + `TATWeatherManager` in 103 levels | **applied** (`tools/parse_weather.py` -> `game/data/generated/weather/`, `weather_profile.gd`, mission wiring, suite 17); W5C: Guildhall resolves to the authored `gloomy` preset from level dressing, fog calibrated for 20–120 m, horizon haze floor | **done (7aa34db, W5C `34c2893`)** |
| **Niagara VFX** | 120 `NS_` systems + 3,695 placements | 3,303 unique records; 3,308 active / 36 systems; one additive billboard per placement (not authored rates) | **catalogue + placement stand-in; VM rates blocked** |
| **Materials** | 1,247 `MI_` + 386 `M_` + 167 `MF_` + 289 material layers | 1,629 resolved (`1,379` albedo, `149` opacity); **307 albedos are heuristic fallback guesses**, 250 have none | **done for parameters; graphs unrecoverable** |
| **Decals** | 675 records (17 files) | 347 spawned / 112 skipped in 3 maps; 216 in other maps are not accounted for | **partial** |
| **Rect / sky lights** | 31 rect placements, 1 sky light, 1 atmosphere | 1 active rect light wired (26 authored off), sky/atmosphere applied | **wired (9b1a22a)** |
| **Light intensity / range** | 682 Guildhall lights, authored intensity `0.01–2500` (median `15`) | linear `1/15` scale (median -> `1.0`, floor `0.01`, ceiling `4.0`); radius 1:1 in metres (200 m guard); attenuation `1.0`; budget ranking uses the same scale | **done (cd3590a; `docs/reports/lighting-intensity.md`)** |
| **Post-process / fog** | 2 `PostProcessVolume`, 1 `ExponentialHeightFog` | fog + Godot-mappable post-process applied; Lumen-only fields logged as unmappable | **wired (9b1a22a)** |
| **Landscape** | 128 `LandscapeComponent`, 128 heightfield collisions, splines, Nanite components | heightmaps + collision + two-weightmap layer blend (`tat_landscape.gdshader`); 210 components across 3 maps (OldManor 128, Startscreen 64, Guildhall 18) now all have real heightmaps/weightmaps, including OldManor_P's 128 (155 PNGs: 101 heightmaps + 54 weightmaps) | **done (fadefa5, 2a8f3d5, 24abf18; `docs/reports/landscape-weightmaps.md`, `docs/reports/visual-polish.md`)** |
| **Packed Level Actors** | 39 `BPP_PL_*` classes, 3,210 instanced components, 30,127 instances | all instances expanded with real `PerInstanceSMData`; Guildhall PeripheryA 3,587 -> 12,594 meshes, collidable; **138 LevelInstances / 32,166 meshes** merged at authored transforms | **done (packed-level-instances)** |
| **Audio** | 5,018 Wwise media chunks + 1,296 event assets | **5,018/5,018 decoded to Ogg** (39,222.2 s, 581,494,198 bytes); 5,862/5,868 event media entries resolved; all 9 gameplay tags wired to verified event/media pairs (`docs/reports/audio-wwise.md`) | **done (2ec9138)** |
| **Tools** | MagicSlime 4 charges / 2 m puddle / 30 s / 10 s slip; smoke 1 ch / 5x5x4 m / 25 s; pickpocket 25 m/9°/0.5 s/4.5 m/s | **implemented** (`50252b5`); projectile flight and player-slip are documented simplifications | **done** |
| **Combat/health** | fall 6.5→23.25 m curve, 10 s downed, 5 s revive, 15/s guard regen | **implemented** (`16edb4e`) with curve-verified damage and a downed countdown | **done** |
| **Blueprints (logic)** | 979 `BP_` + 225 `BPUI_` | 963 `BP_` + 225 `BPUI_` dumped; 18 `BP_` missing (Test/ClothSimulation); movement/detection/tools/contracts wired | **graphs not translatable; selective transpiler only** |
| **Spawners** | 689 markers + 546 loot markers + 254 containers | all spawned: real meshes/pickups/civilians (7172096), real loot actors (1c5225f), openable containers (`5bc2d83`) | **done** |
| **Devices** | 4,118 / 21 families | 2,095 loaded-map records, 6,005 trigger edges, 1,475 power edges; **5 families run** (beams, plates, noise alarms, power, turrets, cameras, wards) | **partial** |
| **Patrols** | 210 paths / 673 waypoints | 120 Guildhall / 350 points merged; guards use authored waits/yaw/PingPong | **done** |
| **Clues / quests** | 96 fact rows / 18 QGs | 90 reachable / 6 dead (Spider `03:Reminder` withheld, `04:Renegade` excluded; the producer-dead `01:Intro` is granted at runtime); authored readable clues, quest items, journal, Set/LootTheRoom objectives; **Spider 01→04 personal chain live** (note → electrotype → Owl → courier → informant, 7 facts, 90/90 real-map probe) | **done (`eb55bc1`); residuals in the 2026-11-24 integration entry** |
| **Player identity** | `PlayerState.GetPlayerName` | explicit handle, else authored `The Spider` / `The Chameleon`; no capture Steam persona | **done (W0a)** |
| **Localization** | 8 locales | 8 `.translation` registered; 2,946 source→key entries; every visible UI expression routed through `UIStrings` (306/306, 195 authored), **not** `Loc.t()` call sites — `Loc.t(` occurs once, in the `localization.gd` docstring | **partial (111 labelled port-copy rows)** |
| Skeletal meshes / skins | 156 `SK_` | 156 GLB | guards play 10 real retargeted clips (a29a06f); player uses real 1P arms (9ef3bdc) |
| Player model | `Mesh1P_UpperBody/LowerBody`, `Mesh3P_Body/Head` = ThiefNisha meshes | real ThiefNisha 3P body/head + 1P upper-body arms with Walk/Sprint/Crouch 1P clips | **done (9ef3bdc)** |

## What is already 1:1 (or close)

- **Geometry**: every shipped mesh is a real GLB exported from the install. Guildhall 63,210 runtime instances / Old Manor 19,503 / Thieves' Den 286, with 32 m chunks, real material slots and landscape heightmaps. Packed Level Actors expand their real `PerInstanceSMData` (30,127 instances across 39 `BPP_*` classes), 138 LevelInstance sublevels merge at authored transforms, and Guildhall's packed-city `PeripheryA` is collidable.
- **Materials (albedo/normal/ORM)**: `materials.json` maps 1,272 UE material instances to real textures; glass, wallpaper, wood, brick and stone overrides were derived from those assets.
- **Tuning data**: 141 DataTables/CurveTables/StringTables drive contracts, difficulty, tools, stamina, AI and progression.
- **Lighting positions/colours/intensity**: 3,479 extracted lights (96 loaded per map, brightest 4 shadowed); authored intensity maps linearly (`1/15`, median -> energy `1.0`) and radius is 1:1 in metres. Report: `docs/reports/lighting-intensity.md`; the stealth probe normalizes local lights to the authored median (energy 1.0 -> weight 0.90; suites 36/36b, 2026-11-18).
- **Level layout**: 77 normalized `.tatlevel.json` files feed the loader (meshes, landscapes, lights, markers).

## Gaps and the plan

### A1 — Weather / atmosphere (done)
`TATWorldSettings` → `TATWeatherManager.PresetOverrides` → `BP_WeatherPreset_*`.
Presets carry moon brightness/colour/size, sun brightness, cloud colour/opacity,
`ExponentialHeightFog` density/falloff/inscattering, `SkyLight` intensity/colour/cubemap,
`SkyAtmosphere`, post-process colour grading, rain/wind flag and intensity.
Implemented: `tools/parse_weather.py` → `game/data/generated/weather/*.json`;
applied to Godot `Environment`, moon `DirectionalLight3D`, fog and glow.
The sky/moon follow-up is `docs/reports/sky-moon.md`.

### A2 — Animations (export done; runtime wiring in progress)
`anims` exports 0/1,002 because `AnimationExporter` only supports ActorX/UEFormat/USD.
Implemented: USD export, headless Blender GLB conversion, ACL natives and a manifest
(995 clips, `docs/reports/anims-pipeline-implementation.md`); 14 blend-space graphs
remain unsupported. Runtime `AnimationPlayer` wiring continues.

### A3 — Material fidelity (done, ec9f700)
`MI_`/`M_` JSON contains scalar/vector/texture parameters, blend mode, two-sided,
opacity mask and emissive values. Implemented: `tools/parse_materials.py` resolves
1,552 materials with real scalar/vector/static-switch/blend/two-sided/phys
material values and keeps per-material overrides. Report:
`docs/reports/materials-implementation.md`.

### Hard limit — cooked material graphs
Cooked UE `Material` exports contain **no expression graph and no texture references** (verified: `M_Decal_Puddle` has only BlendMode/flag properties). Textures that live in a material graph are not recoverable from the install; only exposed `TextureParameterValues` on MaterialInstances resolve. Consequence: 667 level decals and some Niagara sprite materials have no trustworthy texture. The runtime must validate material->texture stem matches and skip the rest rather than bind generic fallbacks. A true 1:1 look for those assets would require recreating graphs from reference, which is not in the cooked data.

### A4 — Niagara VFX (catalogue done, runtime constrained)
120 systems catalogued (`tools/parse_vfx.py`, 26f9838): 29 sprite-only, 70 mesh/ribbon, 21 graph-heavy; 139 of 148 renderer materials resolve, but 91 of the 139 carry no texture and only 129 of 456 renderer entries have a real texture. Loop duration is null for all systems; spawn rate, lifetime, velocity and colour curves are computed inside **Niagara VM bytecode**, not stored as values. A 1:1 particle conversion would require decompiling the Niagara VM; the runtime therefore must not invent rates. Level placements (3,692) are extracted so effects can be anchored/activated once a specific system is hand-matched or its bytecode is analysed.

### A4b — Niagara VFX (original)
120 systems dumped (curves/LUTs included). A faithful Niagara graph translation is a
separate project; first extract emitter material, spawn/lifetime/colour parameters, then
drive GPUParticles3D from those values. No fabricated effects.

### A5 — Level component fidelity
The level JSONs contain the missing actors; components from Blueprint actors are
`SimpleConstructionScript` stubs whose templates live in the `BP_*` class JSON.
Resolved for the shipped level content (`e17beae`, `9b1a22a`): `rect_lights`,
`sky_lights`, `decals`, `niagara`, `postprocess` and `volumes` are emitted;
landscape spline/grass data remains unparsed.

**Packed Level Actors are now expanded** (`docs/reports/packed-level-instances.md`):
level stubs with a `Template` ref and no `PerInstanceSMData` resolve the BPP
class template's mesh + instance transforms, so the city blocks no longer
collapse at actor roots. Guildhall `PeripheryA` is collidable (25,074 shapes,
222 bodies) and its 4 `LevelInstance` actors merge the car-underpass /
apartment / storefront sublevels at authored transforms (138 LevelInstances /
32,166 meshes across all maps). Landscape layer weightmaps are also blended by
`tat_landscape.gdshader` (GroundA/GrassA/CobbleA/CobbleB/RockTileA +
Visibility, plus Puddle normal/opacity and GroundWet darkening). Guildhall sets
`discard_holes=0` because the safe-room gap has no lower-floor mesh; the
authored surface fills it. The second weightmap and fifth colour slot shipped
(`fadefa5`, `2a8f3d5`; `docs/reports/landscape-weightmaps.md`): 210/210
components emit `weightmaps`, 15 have two, 8/18 Guildhall components use
`weightmap_1`; the two captured viewpoints showed no measurable pixel delta
(within run-to-run jitter). OldManor_P extracted 2026-11-18 (155 files, suite 38; `docs/reports/visual-polish.md`); remaining A5 work is landscape splines/grass runtime.

### A6 — Gameplay constants (done, f567d23 + 3e0817f)
BP defaults carry the real movement and perception values: player 360/180 cm/s walk/crouch, +90 sprint increment, 550 jump, 91 cm capsule half height, 79.625 cm eye offset; guard 250 cm/s, 25 m sight, 30 m lose-sight, 40° half-FOV, 25 m hearing; `DA_AIStatesToSpeed_Guard` 1.5/1.7 m/s; `DA_DetectionSettings` 0.4 s/m (0.2 alerted) with crouch multiplier. Parsed into `game/data/generated/gameplay/` and wired into the player/guard.

Authored follow-up values (`docs/reports/gameplay-constants.md`): disguise integrity drains `1.0/s` on the timer, `+40.0/s` while sprinting and `+5.0/s` within 1 m of a guard, with `40.0` lost per damage event (`DT_DisguiseV3IntegrityReduction`); XP uses `CT_XPToLevel` (500/1000/2500 per level band) instead of a flat 500; detection decays at `100 / DecayTimeSeconds` (Neutral 1 s, Suspicious 5 s, Alerted/Combat 10 s) behind the authored 6 s in-level and 4 s unseen gates; `Status.Sprinting` x8 ramp; light/speed/height curves. The Godot-only `SEARCH` state decays unconditionally at the 7 s fallback and detection is clamped on downward transitions. Retained: difficulty scaling, `SEARCH` speed, 15/45/100 state thresholds, 3.5 m close-range bypass.

### A9 — Sky and rain (done, dba6988)
- **Real moon panorama**: `game/assets/ue/Raw/Art/Environment/City/Architecture/BeautifulCorner/Materials/T_Moon_D.png` is a 4096x2048 equirectangular lunar panorama (the weather sky material `M_Moon`/`MI_Moon_Base` uses it). `tat_sky.gdshader` now projects it onto the visible hemisphere. `tools/parse_weather.py` walks the Blueprint `Super`/`Template` chain, so `midnight_clear` inherits `moon.visible`, `moon.size`, `moon.emissive` and the HDR sky colours. The disc diameter comes from `SM_Moon` geometry (`2*asin(R*size/D)`): `8.2718°` for `midnight_clear` (`SphereRadius 10771.60558231864 cm` at `1469413 cm`). `sky.overall_color` (`0.001`) multiplies the gradient once, `Environment.fog_sky_affect = 0` keeps the sky visible through fog, and the disc uses the authored emissive tint `[0.5137, 0.5216, 1.0]`. Suite 22 asserts these. Commits: `9f337cf`, `cfd9771`, `48e67c6`, `7ea5d59`, `156999e`, `7e240bb`, `dba6988`; report `docs/reports/sky-moon.md`.
- **Moon planes**: 100 `1m_Plane_Reverse` instances use `MI_MoonshapeEmissive`, which is unlit with `IsMoonshape` but has no texture in the cooked graph; 25 duplicate planes are hidden in Old Manor where the panorama covers them.
- **Rain**: weather presets expose real `enable_rain`/`rain_intensity` and the Niagara asset name (`NS_Rain_WeatherSystem`), but spawn rate/speed live in Niagara VM bytecode. The Godot rain layer is driven by the real flag/intensity with labelled approximate particle parameters; no fake asset claim.

### A8 — Doors and containers
- **Doors done** (`caec0d4`, extended `doors-attachparent`): 281 pivots → 281 doors / 373 leaves / 0 unresolved. The first wave resolved 170 doors / 262 leaves through attached leaf stubs; the follow-up wave resolves the remaining 111 doorway-BP pivots through the pivot component's own template `StaticMesh` (the pivot is a `StaticMeshComponent` subclass), with identity leaf transforms and GLB existence checks. Static meshes stay at 55,452 (no duplicates). Runtime `[F] OPEN/CLOSE` 90°/0.4 s with per-leaf layer-1 collision. Desktop/headless probe: Old Manor 120 doors / 176 rendered leaves, `rot 0.0→1.571`, suite `fails=0`. Evidence: `docs/reports/doors-attachparent.md`, `/tmp/opencode/doors_test.log`.
- **Doors (old note)**: 281 pivots resolve through their parent Blueprint actor (e.g. `BP_Storefront_Facade_1200a_C` instance `StaticMeshActor_10`) to SCS leaf nodes whose `ParentComponentOrVariableName` is `Pivot`/`SecondPivot` (`SM_Urban_Ext_FrontDoorA_Glass`); the pivot carries the real relative transform (`(-500,-70,10)`, yaw -90). Static batches currently contain door leaves (26 `sm_urban_ext_frontdoora_glass`, 60 `sm_urban_ext_door_closed_4x6`, 3 `sm_doorcityexta`), so the door wave (A21) excludes the resolved leaves from `meshes` and spawns them as rotatable pivot nodes with collision.
- **Containers**: 89 `BP_ChestTrunk_MajorLoot`, 68 `BP_DisplayCaseA_MajorLoot`, 57 secret wall stashes, 20 storefront display cases. Each has real meshes (`SM_ChestTrunk`, lid, filler) and a `TATContainerSpawnerComponent` with `SpawnBucket` (major/minor). These are actor markers with real transforms and can be spawned with loot-on-open using A16's loot actor data.
- **Guard patrols**: not recoverable — `BP_AIPatrolPath` has no spline points in the cooked actor; 249 path actors give positions only.

### A7 — Audio
Wwise media are RIFF with codec tag `0xFFFF` (Wwise Vorbis); FFmpeg alone reports "no decoder found", but vgmstream r2168 decodes them. The `1,296` `AkAudioEvent` dumps carry `EventCookedData.EventLanguageMap[].Value.Media[]` with `MediaId`, `DebugName` and `PackagedFile.Hash`.
**Mapping recovered** (`docs/reports/audio-wwise.md`): `tools/extract_audio.py` walks the cooked ubulk with a strict unpadded chunk walk (`5,050` media chunks = `5,018` RIFF + `32` PLUG), and `tools/convert_wwise.py` joins the k-th non-plugin `IsWemFile` entry to the k-th RIFF chunk, validated against `4,160` `SoundSfxVoice` `InMemoryMediaSize` values (`4,155` exact = `99.88%`). All `5,018` clips decode to Ogg under `game/assets/ue/audio/wwise/`; `5,862` of `5,868` event media entries resolve, and all nine gameplay tags are wired to a verified event dump + resolved clip. The `6` unresolved entries are convolution-reverb IRs in PLUG chunks; `51` WEMs are `bStreaming: true` but their chunks are present and decode.

### A7 — Blueprint gameplay logic
981 `BP_` packages exist. DataTables/CurveTables already drive most tuning; BP graphs
(visual scripting) are not machine-translated. Further gains: dump all `BP_` JSON,
extract component defaults (AI perception, interactables, doors), and port state logic
from those defaults rather than guessing.

## Reproduce the census

```bash
# package inventory
awk -F'\t' '{print $1}' extracted/filelist.txt | grep -E '\.(uasset|umap)$' | wc -l
# JSON dump coverage per class
find extracted/json -name '*.json' | wc -l
# assets
find extracted/assets -name '*.glb' | wc -l
find extracted/assets -name '*.png' | wc -l
# animations (currently 0)
find extracted/assets -name '*.ueanim' -o -name '*.anim.glb' | wc -l
# weather
find extracted/json/Art/Environment/Weather -name '*.json' | wc -l
# niagara
find extracted/json -name 'NS_*.json' | wc -l
```

## Update log

- 2026-11-16: census created; Niagara systems (120) dumped; animation export failure isolated (`Gltf2` unsupported); audio codec limitation confirmed.
- 2026-11-16: loot containers shipped (`5bc2d83`): 234 containers spawn trigger-only Areas at real marker transforms; opening spawns one real loot actor from the mapped bucket; Guildhall 103/103, no duplicated meshes, tests green. Audio extracted (`4742103`): vgmstream r2168 decodes all 3,425 Wwise chunks to Ogg with a library manifest; `AkAudioEvent` event IDs/DebugNames preserved but no chunk↔media map was found at the time (verified 0 MediaId matches, no `.wem`/`.bnk`), so no guessed tag wiring. Spawners shipped (`7172096`): all 689 markers spawn real throwable/ammo/health/civilian content (SM_BottleWineA/B, SM_Toolbox, SM_HealthPackA, SK_CivMale/Female), pickup interactions, bottle distraction throw, civilian wander + MM_Unarmed clips. Contract flow shipped (`1b8db68`): real `SublevelsToLoad` per contract, difficulty match timers (7200/2700/1800, Den 5400/3600/2700, FTUE unlimited), HUD countdown and timeout failure. Loot actors mapped: each BP has a `LootRowHandle` + real mesh (e.g. `SM_PurseA`, `SM_FabergeEggA`) for the next wave. Tool mechanics (`50252b5`) and combat/health (`16edb4e`) shipped with real values; contract-driven sublevels + match timer shipped (`1b8db68`). Character animation shipped: guards retarget 95/97 bones with rest-delta + unit correction and 10 state clips (`a29a06f`); player uses the real ThiefNisha 3P body and 1P arms with Walk/Sprint/Crouch clips (`9ef3bdc`). Level runtime shipped (`9b1a22a`): 347 decals, 138 blocking-volume colliders, 1 active rect light, sky/fog/post-process; niagara placements counted for the VFX wave. Animations shipped (`acd368a`): 995 USD->GLB clips with ACL natives, exact durations, Godot 354-track load check; 14 blend spaces documented. Level components shipped (`e17beae`): 667 decals, 3,692 Niagara placements (0 unresolved), 31 rect lights, 288 volumes, 52 splines, 1 sky/fog/atmosphere; material-graph limit documented. A1 weather shipped (`7aa34db`): 16 presets parsed, map mapping with provenance, fog 0.4 -> 0.004, moon energy/rotation, sky-light ambient, post-process saturation/bloom; suite 17 asserts real preset values. A3 materials shipped (`ec9f700`): 1,552 materials with real roughness/metallic/emissive/static-switch/render flags. A2 animations and A5 level components running.

- 2026-11-16: packed Level Actor instances shipped (`docs/reports/packed-level-instances.md`): level stubs now resolve BPP template `PerInstanceSMData` (39 classes, 3,210 components, 30,127 instances); Guildhall PeripheryA 3,587 -> 10,590 meshes and is collidable; runtime 51,305 meshes / 23,125 shapes; safe-room spawn has 630 meshes within 25 m. Guildhall landscape uses the real `T_RoadBricksA_D/N` street surface named by `MI_Landscape.TextureStreamingData`; `make test` fails=0, `make audit` 99.4%.

- 2026-11-16: landscape layer blend shipped (`tat_landscape.gdshader`): parser emits `WeightmapTextures` + `WeightmapLayerAllocations`; shader blends GroundA/GrassA/CobbleA/CobbleB/RockTileA by channel and discards `LandscapeVisibilityLayerInfo` holes; `Puddle`/`GroundWet` remain skipped. Visual: `/tmp/opencode/qa_weightmap_walk.png`; `make test` fails=0, audit 99.4%.

- 2026-11-16: LevelInstance sublevels shipped: 138 instances / 32,166 meshes merged with `LevelInstanceComponent` transforms; Guildhall PeripheryA 12,594 meshes; car-underpass LevelInstance has 697 meshes near its authored transform; Guildhall runtime 63,210 meshes / 25,074 shapes. Tests suite 20; `make test` fails=0.

- 2026-11-16: Puddle/GroundWet landscape layers: `Puddle` uses the real `T_Decal_Puddle_1_Normal/Opacity` textures plus the authored weightmap channel with a labelled dark-water tint; `GroundWet` darkens albedo and lowers roughness. Shader compiles/renders (`/tmp/opencode/qa_puddle_spawn.png`); `make test` fails=0.

- 2026-11-16: Guildhall visibility-hole fallback: no floor-like mesh within 6 m of the safe-room gap (only foundation walls at y=12); vertical ray hits an overhang at y=25. `discard_holes=0` for Guildhall landscape components so the authored surface fills the gap; suite 21 asserts it. `make test` fails=0.

- 2026-11-16: spawn-area light priority: `_prioritize_lights` puts lights within 25 m of player spawns ahead of the global brightest-96 budget. Guildhall loads the authored safe-room wall `SpotLight3D` at `(126.2948, 27.1426, -2.28)` (energy 4.20 under the old clamp; `cd3590a` now gives `0.333` at the authored `9.0 m` range); suite 10 asserts the light is loaded. `make test` fails=0.

- 2026-11-17: Guildhall safe-room overhang closed (`badf7d5`, `docs/reports/lighting-overhang.md`): the black rectangle was not a visibility hole and not a black mesh — `_dict_to_transform()` clamped `LandscapeComponent` scale `[100,100,100]` to `40.0` (`0.4x`), shrinking `63 m` terrain tiles to `25.2 m` and leaving a `37.8 m` void gap under the alley; `tools/parse_tables.py` now resolves Blueprint `Template` chain transforms/properties for lights so `BP_WallLightB_C_5` aims into the safe room, and `_build_light()` keeps the authored `88` degree outer cone. `make test` fails=0, `make audit` 99.4%.

- 2026-11-17: Wwise audio recovered (`1b78590`, `2ec9138`, `637da18`, `docs/reports/audio-wwise.md`): the unpadded ubulk walk extracts all `5,050` media chunks (`5,018` RIFF + `32` PLUG); an order join validated at `4,155/4,160` `InMemoryMediaSize` matches (`99.88%`) resolves `5,862/5,868` event media entries; `5,018` clips decode and all nine gameplay tags are wired to verified event/media pairs. `make test` fails=0, `make audit` 99.4%.

- 2026-11-17: Overhang wave recorded with a resume point (`f831e17`, `docs/reports/lighting-overhang.md`); the `badf7d5` code fix is logged above.

- 2026-11-17: Sky/moon wave shipped (`9f337cf`, `cfd9771`, `48e67c6`, `7ea5d59`, `156999e`, `7e240bb`, `dba6988`; `docs/reports/sky-moon.md`): preset inheritance + HDR colours, UE rotator -> Godot basis, map resolved before environment, `SM_Moon` geometry gives `8.2718°` for `midnight_clear`, hemisphere panorama projection, `sky.overall_color` (`0.001`) multiplies the gradient, `fog_sky_affect = 0`, authored emissive moon tint; suite 22. `make test` fails=0, `make audit` 99.4%.

- 2026-11-17: Lighting intensity/range wave shipped (`cd3590a`; `docs/reports/lighting-intensity.md`): authored intensity now maps linearly (`1/15`, median -> energy `1.0`, floor `0.01`, ceiling `4.0`) instead of the two-branch clamp that pinned 468/682 Guildhall lights (68.6%); radius is 1:1 in metres (200 m defensive ceiling), attenuation `1.0`, and `_light_score` uses the same mapping. Spawned-set energy is ~41% lower and ranges ~57% shorter; light-probe stealth weights are a parked follow-up. `make test` fails=0, `make audit` 99.4%.

- 2026-11-17: Landscape second weightmap + fifth colour slot shipped (`fadefa5`, `2a8f3d5`; `docs/reports/landscape-weightmaps.md`): all 210 components emit `weightmaps`, 15 have two, Guildhall 8/18; loader binds `weightmap_1`, five colour slots and dedicated visibility/puddle/groundwet indices; shader `weight_at()` returns zero for unknown indices. No measurable pixel delta at the two captured viewpoints (within run-to-run jitter); `OldManor_P`/`BeautifulCorner_Startscreen_P` heightmaps/weightmaps still missing at that time (`OldManor_P` since extracted 2026-11-18 by `24abf18`; `BeautifulCorner_Startscreen_P` extracted 2026-11-17 by `8f07b7d`, 20 PNGs). `make test` fails=0, `make audit` 99.4%.

- 2026-11-17: Gameplay defaults follow-up shipped (`f567d23`, `3e0817f`; `docs/reports/gameplay-constants.md`): disguise integrity rows (`1.0/s` + `40/s` sprint + `5/s` within 1 m, `40` on damage), XP curve `CT_XPToLevel` (500/1000/2500), authored detection decay (`100/20/10/10` per s behind 6 s/4 s gates), `Status.Sprinting` x8 ramp, and the light/speed/height curves; `SEARCH` decays unconditionally at the 7 s fallback and detection is clamped on downward transitions. `make test` fails=0, `make audit` 99.4%.

- 2026-11-18: Visual-fidelity wave (Phases 1–3) shipped (`7458198`..`2da2ebe` + Phase 3 QA/docs; `docs/reports/visual-fidelity.md`):
  - **Phase 1**: `ue_rotator_to_mat3` m12 shear fix + Gram-Schmidt orthonormalization (`7458198`, `146,563` bases); startscreen landscape + `WindowPanels` PNGs (`8f07b7d`, `754bbb6`, `2,261` PNGs, `1,571` materials / `1,367` albedo, 0 map/eye/glass leaks); Overlay/Multiply + `BlackUnlitMaterial` (`7737ed1`); GLB primitive-order `mesh_materials.json` (`6783c2d`, `2,027+18`, `27/27 MATCH`); per-surface `OverrideMaterials` + MID Parent + `BPP_*` overrides + `bVisible:false`/`SplineEditorMesh` filtering (`24cac7e`, 73 clean levels); emissive `CustomPrimitiveData` MultiMesh + `tat_emissive_cpd.gdshader` (`d0f895a`, `1,293` shapes); `tat_glass.gdshader` with authored albedo + opacity map (`123` opacity bindings, `_load_tex` unimported PNG fallback, flat-blue fallback removed, opaque glass preserved; `32d6a52`). Suites 27–33 + red-proofs verified.
  - **Phase 2**: Thieves' Den exit door (`BP_ThievesDenExitDoorInteractable_C` wired into swinging-door path reusing `SM_DoorInaccessibleA`, 0 static duplicates), Den lighting (`7.7 -> 1.90 <= 2.0` hand fills, dark ambient `0.12`, 1 interior `ReflectionProbe`, real `SM_FabergeEggA`/`SM_StatueOwlA`/`SM_HugeJewel` GLBs), footprint decal (`T_Decal_Footstep.png` alpha mask, `emission_enabled=false`), map table (`+0.75` removed, `M_MapBuilding_*` tokens bound; `0361577`); Startscreen `CineCameraActor_0` (`(-12.7196, 0.4566, 14.6089)`, pitch `+13.8°`, vFOV `48.03°`, loader added to tree), Settings teal theme + 6 grouped cards (`ST_Settings.json`) + persisted values wired into `SaveSystem`/`ThiefCharacter`, Mission Prep real location art + `ObjectiveDisplayImage` icons + all 11 `CDT_Missions` rows (`2da2ebe`). Suites 34–35 verified.
  - **Phase 3**: Live Vulkan Forward+ test & visual QA on RTX 4070 (`build/qa/make_test_vulkan_vf.log`, 9 captures in `build/qa/vf_*.png`, `SHADER ERROR = 0`, `SCRIPT ERROR = 0`, `SUMMARY: fails=0` across 35 suites, `make audit` `99.4%`). Compared against 30 official captures in `/home/john/Pictures/Screenshots/` (2 scenes without official reference — Old Manor and Den exit door close-up — skipped comparison and documented). Fixed 720p Mission Prep anchor clipping and `SK_ThiefNisha__Head.glb` +1.45 m offset caught during live capture.

- 2026-11-18: Light-probe stealth retune (`277baba`; `docs/reports/lighting-intensity.md`): probe restores the authored median to weight 0.90 at energy 1.0 (pre-retune 0.35) via `energy * 0.9` clamped to `[0.15, 0.90]`; sub-median rebalance (authored 5 -> 0.30, authored 2.5 -> 0.15 floor); the old 19.9/20.0 dip is removed; suites 36/36b, `make test` fails=0, `make audit` 99.4%.

- 2026-11-18: Visual-polish wave (`3448f82`, `63ea64c`, `1912d04`, `24abf18`; `docs/reports/visual-polish.md`): map tokens `0.08 -> 0.24` (suite 34d), unshaded HDR neon pass (suite 37; retained capture thin tubes `(255,183,101)`/`(255,157,84)`, before red blobs `(254,78,77)`/`(254,57,67)` measured at the time in the discarded run with no artifact retained; earlier `StandardMaterial3D`-emission approach discarded before commit), Mission Prep ThiefNisha PBR (suite 35c), OldManor_P 155 landscape PNGs (suite 38). `make test` 38 suites `fails=0`, `make audit` 99.4% (`29,939` files written); live Vulkan Forward+ captures (`capture_vf.sh`, `capture_mp_only.sh`) `SHADER ERROR = 0`, `SCRIPT ERROR = 0`.

### Visual verification log (desktop, live GPU)

- **Weather blackout** (`cba4cf2`): `Environment.adjustment_brightness` was written as `gain−1` (−0.2) but is a multiplier (default 1.0). Fixed to the gain (0.8 den / 1.1 dense fog) with a suite-17 regression test. Evidence: black `/tmp/opencode/tat_den.png` → working `/tmp/opencode/tat_den_fixed.png`.
- **Spawn yaw** (`90486ef`): authored PlayerStart basis is now applied; Guildhall `rot_y=-175°`, forward dot 1.0. Evidence: `/tmp/opencode/tat_guildhall_yaw.png` (safe-room overlook + moon).
- **Old Manor spawn** (`b06cf8b`): 6 authored starts float outside the playable space; floor-grounded fallback picks `major_loot pos=(17.53,23.49,58.39)`. Evidence: `/tmp/opencode/tat_om_fixed.png`; a follow-up raycast showed the point sits under a low roof (headroom wave A23).
- **Doors** (`caec0d4`): 281 pivots → 170 doors / 262 leaves / 111 unresolved; static meshes −246; probe `rot 0.0→1.570796`; suite green. Evidence: `/tmp/opencode/make_test_final.log`.
- **HUD hotbar** (`e2a61aa`): opaque `T_Ability_Background/Border` mask textures covered the icons; now StyleBox slots + real icons. Evidence: `/tmp/opencode/tat_hotbar.png` shows `[1] Sap / [2] Smoke / [3] Fairy / [G] Ability` (counts 4/1/999/4).
- **Sky/rain** (`a801e79`): real gradient/moon shader from weather presets, 25 moonshape planes hidden in Old Manor, weather rain layer. Guildhall shows the moon and authored sky (`/tmp/opencode/tat_guildhall_yaw.png`).
- **Title + forward clearance** (`0729e90`): missing string-table titles render as `Contract N — <quest item>` (contract 3 = `Contract 3 — Mary Elway's Papers`); fallback spawns require floor + 2.2 m headroom + 1.5 m forward clearance. Verified: Old Manor `source=major_loot`, `headroom_clear=true forward_clear=true`, on floor, `fails=0`. Evidence: `/tmp/opencode/final_title_spawn_test.log`.
- **Open visual items**: Old Manor fallback headroom verified (`05f8657`: same marker, 2.2 m column clear); a forward ray still hits the porch 10–13 m ahead, so A24 adds forward-clearance scoring. The 111 doorway-BP pivots are resolved through their own template `StaticMesh` (`docs/reports/doors-attachparent.md`); Guildhall periphery building fragments (authored periphery geometry), `Contract.Main3` HUD title fallback, and the blank-free hotbar are confirmed.
- **Visual-fidelity wave live Vulkan QA (2026-11-18)**: Verified on `NVIDIA GeForce RTX 4070 Laptop GPU` (`Vulkan 1.4.357 - Forward+`, `SHADER ERROR = 0`, `SCRIPT ERROR = 0`, 35 suites `fails=0`). Captures in `build/qa/vf_*.png` (`vf_startscreen.png`, `vf_settings.png`, `vf_mission_prep.png`, `vf_thieves_den.png`, `vf_thieves_den_map_table.png`, `vf_thieves_den_exit_door.png`, `vf_guildhall.png`, `vf_guildhall_street.png`, `vf_old_manor.png`). The three follow-ups are now resolved by the polish wave (preview PBR, token scale `0.08 -> 0.24`, neon bloom via `tat_hdr_emissive.gdshader`); residual: Startscreen ambient/exposure difference and neon core slightly more saturated than UE's pale gold. See `docs/reports/visual-polish.md`.
- **Visual-polish wave (2026-11-18)**: `3448f82` (map tokens `0.08 -> 0.24`, suite 34d), `63ea64c` (unshaded HDR neon pass `tat_hdr_emissive.gdshader`, suite 37; retained capture thin tubes `(255,183,101)`/`(255,157,84)`, before red blobs `(254,78,77)`/`(254,57,67)` measured at the time in the discarded run with no artifact retained; earlier `StandardMaterial3D`-emission approach discarded before commit), `1912d04` (Mission Prep ThiefNisha PBR, suite 35c), `24abf18` (OldManor_P 155 landscape PNGs, suite 38). `make test` 38 suites `SUMMARY: fails=0`, zero `SCRIPT ERROR`; `make audit` `12,630/12,704 (99.4%)`, `29,939` files written. Live Vulkan Forward+ (`bash build/qa/capture_vf.sh`, `bash build/qa/capture_mp_only.sh`, `SHADER ERROR = 0`, `SCRIPT ERROR = 0`): `vf_mission_prep.png` (authored blue top/dark trousers/skin/hair), `vf_old_manor.png` (landscape builds, `runtime build=1`, renders cleanly; terrain walk/collision not verified), `vf_map_tokens_024.png` (0.24 tokens). Full report: `docs/reports/visual-polish.md`.
- **Fidelity-mechanics wave (2026-11-18)**: RD-hardening `deabbbd` (glass/icon samplers linear-only) + `432f1bf` (tiny-texture mip guard, suite 39) + `fe31e58` (preview viewports update-when-visible) + E2E harness `d9bc629` (arc-bound alias vars24/tracks48, settle/lambda, suites 40/41/42; tier-1 `19 -> 17` fails, `SCRIPT 1 -> 0`). Live RTX 4070 Vulkan Forward+: VF 6 PNGs (`startscreens/settings/mission_prep/guildhall/guildhall_street/old_manor`) `EXIT=0`, `SHADER ERROR = 0`, `SCRIPT ERROR = 0`; MP `EXIT=0` 0/0; E2E 21 shots `parity 14/7` (`shader0 script0 missing0`), 7 content fails (map look-at card, wardrobe clipped controls, lobby FOV-20 x2, zipwire equip, guard pips/arcs, circular lockpick). RD cascade gone: zero `texture_create`/`update_sizes`/`uniform_set` in all three logs. `make test` 42 suites `SUMMARY: fails=0`; `make audit` `12,630/12,704 (99.4%)`, `29,939` files. Full report: `docs/reports/fidelity-mechanics-wave.md`.

- **Full-port Phase 4 (2026-11-18)** — headless-green, live blocked (`9f4ef7c` Den 2-level glow cap, `6ab91a3` zipwire crank clip, `2799c8e` stairs snap `0.3`/angle `50`, `bcb3e0a` tiny-resource mip strip with accounting, `dd2ecb2` triage tier-1 `17 -> 2`, `b58c69e` open-leaf disable past 70° + Den window gap `0.95 m`; suites 39b/43/44/45/46, `make test` `SUMMARY: fails=0`, zero `SCRIPT ERROR`). Live still blocked: Den RD cascade (reported `strip 0=591 / 1=17 / 2=569`), parity `14/21`, tier-1 `T1-03-E`/`T1-18-E`, crank headless-only, screenshot teardown breaks, no 60 FPS profile. TEMP `--env-strip=0-8` hook uncommitted in `game/src/missions/mission_controller.gd` (debug only — revert before commit). Next: user-GPU strip 0/8 counts, FPS profile (§5.2 shape), parity recapture, crank/stairs/doors live confirm. Details: `docs/reports/fidelity-mechanics-wave.md` §6.

- **Residual close-out wave (2026-11-23)** — `d3cf9ca`, `c1e5abd`, `e72d781`, `206c965`, `4f41c60`, `2aab8c6`, `6f9238d`, `c13ceba`:
  - **Standing disguise**: `ABPL_Disguise` uses `AN_ThiefCotter_Disguise_StandIdle` (not the Nisha `AN_Disguise_*_1P` set, which belongs to `ABPL_AntiStealth`). Added the `disguise_idle` role and a stationary branch; T3-20 asserts both exact clips. Retarget: 311 tracks, 1.983 s, 70/70 `_1p` bones covered.
  - **Startscreen title/layout**: the logo is a 2048² texture with content `2012x1269`; the old `TextureRect` fitted it to 170×170 (visible 166×106). Now an `AtlasTexture` at 317×200, right block shifted 54 px left, menu font 22→18 / separation 5 / spacer 53. Measured 1280×720: title `874-1190 x 193-392` (target 874-1191 x 193-393), menu rows within 5 px, pitch 35 vs 33.3.
  - **Storefront gold decals**: the authored UE tint is linear `(1.0,0.327,0.106)`; Godot treats `albedo_color` as sRGB, so the decals rendered red. Exact-path `linear_to_srgb()` fix plus short-range warm fills and a deep interior fill. Measured decal ROI mean 0.293 (UE 0.299), gold coverage 37.8% (29.1%), pale-trim ROI unchanged. Residual: gold-mask G/R 0.388 vs UE 0.555 (the reference scrollwork is self-lit; a texture-masked emissive was tested and blew the whole window, so it was reverted).
  - **Guildhall sky**: `midnight_clear` authors a 400 m sky sphere inside height fog; `fog_sky_affect=0.0` removed it. Restored for the exact preset (`0.85`), background 2.0, stars ×0.12, and an indigo haze floor `(0.12,0.13,0.15)` because the authored fog inscattering is self-lit and was *dimmer* than the sky. Measured KF17/KF18 sky p50 0.167 (targets 0.10-0.25), 18 star components (<=25). Residual: cool blue-grey vs the UE warm grey.
  - **Den KF10 metric**: full-frame p95 63.3 vs UE 78 is a framing/state artifact (port east window vs UE's highlighted Guildhall token + broad parchment). The capture now selects and logs `guildhall`; active token emission 0.85→1.4 raises the token ROI p95 80.4→88.3 with zero clip; full-frame p95 is report-only. Residual: paper midtones (core p50 30.5 vs UE 52.6) are Lumen/GI, not grade.
  - **KF16/KF17 re-shoot**: derived KF17 roof pose works (roof hang, cable, skyline, viewmodel; sky at target). The derived KF16 street pose at `(13,18.2,75.8)` fails: the gate ground renders as a flat untextured grey plane and the car/sign are not visible (the periphery sublevel has no landscape/interior there). KF16 composition remains open; the gate state (authored open), car beams (no LightComponents) and clocktower (no mesh) are content gaps.
  - **QA**: worktrees cleaned (11 merged removed, harness files preserved); E2E 260/260, `run_tests` 0, M2 0, compile 58/0.

- **Residual follow-up wave (2026-11-23, second pass)** — `46f5157`, `e038108`, `61a4f0c`, `a66220f`, `665246a`, `adcb86f`:
  - **KF16 lighting/framing**: moved `GuildhallFenceLampFill` to the street side `(10,27,46)`, zeroed the head yaw in the capture aim, and added two shadowless car headlight spots at the authored lens centres plus a per-instance `MI_Glass_Automobile` emission override. The capture now shows the gate arch, street and two warm headlights. The sign lettering still does not read: the gold `MI_TrimMetalSurfaceA_Brass` surface is present but the remaining authored gate spots are still dropped by the position-only light dedupe and the 160-light budget. Documented, not forced.
  - **KF16 mission state**: the UE reference is a free-play `Cleanout Heist` (`Contract Inactive`, `Mission.Guildhall.LootTheRoom`, 4,000 loot at Novice). No port contract carries a loot-value objective; the capture stays on contract 4 and the HUD string difference (`Secrets to Uncover / Steal the Ritual Scroll` vs `Steal 4,000 in loot value`) is documented.
  - **KF17 skyline**: one authored `SM_DistantTowerA` instance at `(10,20,-120)` scale 2.6 (material `/Game/Art/Environment/Skybox/Buildings/ML/MI_DistantBuidingA`) now provides the clocktower silhouette; decorative, no collision, no lights.
  - **Warm sky**: the shader veil is uploaded as a `Vector3` (a `Color` vec3 is sRGB-decoded and had left the sky blue). Final linear `(0.052,0.040,0.028)`, amount 1.0, `fog_sky_affect 0.80`, stars x0.10. Measured KF18 sky p50 0.242 (UE 0.235-0.26), right-sky mean (0.252,0.241,0.238), 22 star components; Den/lobby haze remains 0.
  - **Gold decal**: exact-material `tat_storefront_decal.gdshader` with a dark-gold diffuse background and luma-gated emission; `Rougness` typo fixed. Measured decal ROI mean 0.353 (UE 0.319), G/R 0.472 (UE 0.555), pale-trim and whole-image guards pass. Residual: the magenta neon/SSIL-lit interior raises coverage and lowers the hue; forcing G/R further would need the SSIL wash removed or new interior art.
  - **Den GI proxy**: `DenMapTableBounce` (Den-only downward warm spot, energy 2.0, range 3.3, 45 deg) lifts the KF10 table-core p50 to 38.6 (target 38-42) with hotspot p95 81.9, token 88.7, KF02 9.6, KF06 8.2, zero clip. UE's 52.6 remains a real Lumen-GI gap (50-strength emissive shade + diffuse boost).
  - **QA**: compile 58/0, run_tests 0, M2 0, door walk, viewmodel truth, Niagara, E2E 260/260.

- **KF16 / road / decal / gate follow-up (2026-11-23, third pass)** — `28baa54`, `728f272`, `fcad2f6`:
  - **Road grey fixed**: `tat_landscape.gdshader` used flat `fallback_color` when all layer weights were zero; the Guildhall gate approach is a puddle-only zero-weight strip. The shader now falls back to `layer_tex_0`, and Guildhall binds `T_RoadBricksA_D` as `fallback_tex` so the approach reads as cobbles. Textures were never missing (all 18 landscapes and 140 street meshes had non-null albedo).
  - **KF16 gate lights**: added a 10 m hero allowlist in `_add_lights` that forces the six sign-side Guildhall lights into the 160 budget (two 20.0 uplights, two 4.1 omnis, two 20.0 Gameplay lights), with a deterministic sort tie-break and six distant 25.0 evictions. Verified `total=160 forced=6` over two runs.
  - **KF16 sign lettering still does not read**: the forced lights are live and the sign surface exists, but the brightened capture shows only the iron arch/back — the gold `MI_TrimMetalSurfaceA_Brass` letter face appears oriented away/under from the street. This is an orientation/content gap, not a lighting gap; a targeted spot would not help. Documented rather than faked.
  - **Decal masked discard**: the decal now cuts its black background (`ALPHA=smoothstep(0.03,0.20,luma)`, scissor 0.5) and emits gold only on the scrollwork, matching the authored `BLEND_Masked`. A dim brown backing plane behind the decals and a startscreen glow of 1.2/0.18/3.0 keep the revealed interior from blowing out. Measured ROI mean 0.281, gold coverage 29.4%, G/R 0.507, pale-trim 0.142.
  - **Gate**: capture-only closed leaves (hide the open front MultiMesh, spawn two non-colliding closed leaves at `C ± 5 m`); gameplay keeps the open gate. HUD `Contract Inactive` / `Cleanout Heist` / 4,000 loot remains documented; no free-play state was added.
  - **Den VoxelGI**: attempted a Den-only VoxelGI bake (subdiv 256, interior, two bounces, bake-time shade emission 50, 3.6 s bake). At propagation 1.0 core reached 44.4 but KF02/KF06/KF09 rose to 15.1/15.8/37.1; at propagation 0.6 all guards passed but core fell to 41.7. The two-capture tradeoff is structural, so the change was reverted; the 38.6 bounce proxy remains.
  - **Colinear warning**: `DenMapTableBounce.look_at` now uses a non-colinear up vector.

- **World/free-play wave (2026-11-23, fourth pass)** — `bf19d78`, `e5e31f7`, `c7735e5`, `3d010f7`, `f5b90ff`, `6fb3475`:
  - **Startscreen floor fixed**: the heightfield winding was clockwise-from-above, so `cull_back` hid the terrain top and the "floor" was sky/fog. Reversed both triangles and dropped the manual normal negation; `generate_normals` now yields up-facing normals. Startscreen ground ROI SD 0.030 -> 0.062 with visible cobbles/puddles. The startscreen `GroundA` layer is remapped to `T_RoadBricksA_D`.
  - **Guildhall road fixed**: the zero-weight fallback sampler now repeats (`repeat_enable`), binds `T_RoadBricksA_N`, and uses damp roughness/specular. Two unregistered gate-mouth fills and retargeted car beams light the approach. The KF16 capture now shows a textured wet road instead of a flat blue-grey plane.
  - **KF16 sign**: runtime surface split of `SM_Guildhall_Sign` s0 (268 letter-band triangles, gold material, `CULL_DISABLED`) plus the original s1/s2; arch/crest silhouette unchanged. The lettering is still not legible at the 27 m capture distance - the geometry is gold and front-facing, but the light/contrast at that range remains a residual.
  - **Den paper**: removed the 2.0 `DenMapTableBounce`; added `DenShadeFill` (0.60, in `den_hand_fills`, sum 1.90) and a Den-only parchment emission (`albedo * 0.20`, warm tint). Measured KF10 core p50 43.5, hotspot 83.4, token 88.6, KF02 10.3, KF06 8.2, KF09 30.5, zero clip. The 38.6 ceiling is lifted without room spill.
  - **Free-play / Contract Inactive**: order-2-hosted mode, mission `Mission.Guildhall.LootTheRoom`, 4000/6000/8000 goals, `Steal {Amount} in loot value`, 3300 s, HUD `Mission: Steal 4,000 in loot value[0/4,000]` and `£ 0`, no contract-completion write; `--qa-free-play`/`--qa-mission`. New E2E T4-13; suite 261/261.
  - **Probe shutdown**: attempted `visible=false` + `free()` before exit; the 7-texture RID warning still appears at finalization, so the `TAT2_NO_DEN_PROBE` switch remains the clean-exit path.
  - **QA**: compile 58/0, run_tests 0, M2 0, door/VM/Niagara, E2E 261/261.

- **Review remediation wave (2026-11-23, fifth pass)** — `3ed80c0`, `4b9fa03`, `0e89d2c`, `e7fcb7d`; evidence and residuals in [`docs/reports/review-remediation-wave.md`](reports/review-remediation-wave.md):
  - **Security beams**: `MI_LightBeam_SM` now uses `tat_beam.gdshader` (warm additive, alpha 0.55, energy 1.7) instead of an opaque white lit material; generic additive/textured-unlit mapping added. The 134 Guildhall beams no longer render as solid white bars.
  - **Two-sided flags**: the parser reads `BasePropertyOverrides.TwoSided`; 24 materials gained the flag (gates, fences, brass doors, vault panels, sign). Gates/fences no longer vanish from one side.
  - **Paint-stroke albedo**: the parser prefers the child MI's companion `_D` over the parent master; 15 materials recovered, including `MI_BrickNewClean_XYZ` (gate frame) and `MI_FloorTileA_AlignXYZ`.
  - **Mirrored doors**: negative-determinant leaves get per-surface `CULL_DISABLED` duplicates (36 POI + 4 vault pivots).
  - **WorldGrid doors**: fully-grid `SM_OldManor_Gate_FrontDoor` / `SM_OldManor_Gallery_Door_Glass` get referenced metal/glass substitutions; partial-grid door surfaces copy the main door material.
  - **Blocking volumes**: tagged `blocking_volume`; mantle/wall-climb/zipwire reject them. New T1-10-J covers tall/low blockers, 4 m/5 m mantles, real walls and no soft-lock. Invisible designer ledges are no longer climbable.
  - **FOV**: schema-v2 migration rewrites only the legacy saved `fov:75` to 54.54; the KF16 capture pins 54.54. Gate/street framing now matches the authored lens.
  - **Loot grounding**: 253 Guildhall loot items and 3 civilians now sit 0.03 m above the floor ray (0 floating, 0 sunk); the blanket +0.5 m offset is gone.
  - **Ornate gate fill**: unregistered warm omni at `(80,20,18)`.
  - **Sign letters**: per-instance s1 emission `(1.0,0.62,0.20)` energy 0.10. The letters are gold and front-facing at 54.54; at the 27 m capture they remain low-contrast in the frame, so legibility is still a residual.
  - **Free-play**: autostart `_bind_menu_env` no longer throws; `_on_extracted` skips currency in free play; a real Den map-table entry (`FREE PLAY: GUILDHALL CLEANOUT [G]`) reaches the Contract Inactive prep card. Captures show `CONSTABLES' GUILDHALL / Contract Inactive / Cleanout Heist / 55 minutes` and HUD `Mission: Steal 4,000 in loot value[0/4,000]`, `£ 0`. The prep body text clips at the card edge (minor UI polish).
  - **Den**: KF10 core p50 remains 43.5 with the new material flags; KF02 10.3, KF06 8.2, KF09 30.5, zero clip.
  - **QA**: compile 58/0, run_tests 0, M2 0, door/VM/Niagara, E2E **262/262** (T1-10-J added; T2-04-C accepts the intentional beam shader). The 7-texture probe leak still warns at exit; `TAT2_NO_DEN_PROBE=1` remains the clean gate.
  - **Documented residuals**: Guildhall POI graybox floors/floating furniture, white glass/emissive plates, mirrored `PICK LOCK` reflection, sign legibility at 27 m.

- 2026-11-24: **Gameplay truth wave** (`886eff1`..`3202283`): fail-closed audit
  (18 producers, tracked baseline, 14 negative-control groups); guard sight
  restored; schema-based save merge + restore-safe suite 49; composed mirrored
  door determinant; non-vacuous free-play test + normal-mode control; FOV flag
  only on a real slider change; authored patrols (120 Guildhall paths / 350
  points), surface loudness (22 rows), interaction LOS, civilian capsule;
  authored devices (2,095 loaded, 6,005 edges; beams/plates/noise/power/turrets/
  cameras/wards); authored clues/quests (96/90/6, Contract 2's 7 facts and 6
  clues, Guildhall gems on 3 Office spawners, LootTheRoom 4000/6000/8000);
  995/995 animation metadata with 3,594 notifies; UI countdown/identity/portal/
  rain and 8-locale `Loc.t()`; co-op pose + host-validated door events.
  Gates: compile 69/0, 58 suites fails=0, M2 fails=0, E2E 264/264, probes PASS,
  audit PASS. Current Guildhall steady state ~39 FPS @1080p/high (p10 36, p90 41).
  Residuals: device breakables/goo/vault/windows/portals, co-op loot/AI
  authority, 60 FPS, Den GI, partial UI `tr()`.

- 2026-11-24: **Identity / key-name / texture-cap correction (W0a)**:
  - **Player identity**: the HUD/ledger card no longer ships the capture
    machine's Steam persona. `GameState.player_name` defaults to blank;
    `player_display_name()` returns an explicit handle or the authored title
    (`The Spider` / `The Chameleon`). `SaveSystem.set_player_name()` is the API
    (no Settings field, owned by W0b); a one-shot `player_name_migrated` flag
    rewrites only the exact legacy persona and preserves any other name.
  - **Key names**: `STOLEN_KEY_NAMES` is `Guildhall Key` / `Elway Manor Key` /
    `Vault Key`; the mission key pool maps Guildhall → `key_guildhall`,
    Old Manor → `key_manor`, vault rows → `key_vault`. The previous
    `Manor Key`/`Locked Room Key`/`Secret Chest Key`/`Small Chest Key` labels
    were the Den wardrobe mesh/icon names.
  - **Texture cap**: the two 2048 px `T_SafeBlackFaction_*_D.png` sidecars had
    reverted to `process/size_limit=0` + no mips; `make desktop-texture-cap`
    restored 1024 + mips. `tools/prebake_texture_cap.py --check` /
    `make texture-cap-check` is a prerequisite of `make audit` and treats
    `size_limit=0` as over-cap; the alpha-critical 4096 px storefront decal
    stays uncapped. Suite 82 covers the sidecars and the exception.
  - **NPC clue status (superseded by the Spider integration)**: the Spider
    personal chain is live; see the 2026-11-24 integration entry below and
    [`reports/spider-chain-integration.md`](reports/spider-chain-integration.md).
    The old note ("two orphaned lines, NPC quest planned W2") described the
    pre-runtime state and is no longer the live status. The producer census still
    reports 6 dead fact rows; `03:Reminder` is withheld and `04:Renegade`
    excluded by design, while `01:Intro` is granted as the chain's first journal
    line.
  - Gates: compile 69/0, 59 suites fails=0, M2 fails=0, E2E 264/264, probes
    PASS, `make audit` PASS (with the new cap check).

- 2026-11-24: **W0b measurement truth** (this wave): `settings.graphics_quality`
  (low/medium/high, default high) is now persisted, validated and exposed as a
  desktop Settings control; `--perf-*` CLI overrides set
  `WeatherProfile.set_quality_level`, viewport scale/mode and light/shadow caps
  before the mission builds and log one `PERF_CONFIG` line; `mission_controller`
  emits `mission_ready(map_id, stats)` after the load/spawn pass; the fixed
  six-pose Guildhall matrix (`game/tests/perf/`, `build/qa/run_perf_matrix.sh`)
  records wall frame time, `TIME_PROCESS`/`TIME_PHYSICS_PROCESS`, render
  CPU/GPU, draw calls, objects, primitives, VRAM, lights/devices/chunks and
  fails closed on truncation. Validation (release export, host Wayland,
  1920×1080, pose `spawn_overlook`, 300 frames): p50 **20.40 ms**, GPU
  **19.67 ms**, 9,738 draw calls; 1280×720 p50 **21.18 ms** (geometry-bound
  pose; run-to-run/world-state variance is larger than the resolution delta,
  so this is not a ladder result). Low/medium/high now log `WeatherQuality`
  levels 0/1/2 (previously all 2). Xvfb measured 66.55 ms for the same 1080p
  pose, so the wrapper defaults to the host compositor. Not a ladder
  conclusion: one exterior pose only; the full six-pose matrix remains for the
  integrator. 60 FPS is still not achieved and no FPS improvement is claimed.
  Details: `docs/reports/perf-measurement-w0b.md`.

- **W1p structural perf prototype (2026-11-24, worker branch)** — off by default,
  no FPS claim; evidence: [`docs/reports/w1p-structural-perf-prototype.md`](reports/w1p-structural-perf-prototype.md).
  Every loader draw item now carries `source_sublevel`/`source_counts`;
  `PERF_CENSUS` measures Guildhall 5,782 mesh nodes / 64,547 instances / 10,642
  surface draws / 171 lights (7 shadow-casting) / 768 occluders / 24,311
  collision shapes, PeripheryA 3,104 nodes / 5,945 surface draws. Env levers
  (`TAT2_PERIPH_RANGE=100|120|150`, `TAT2_SHADOW_HEROES`, `TAT2_LIGHT_BUDGET`,
  `TAT2_MERGE_CELLS=plain`) are QA-only; defaults stay 6/160 and no range/merge.
  Headless merge probe: 639 plain candidates -> 47 cell nodes, 1,370 -> 722
  surfaces, draws 10,642 -> 9,994 (-6.1 %), collision/occluders unchanged.
  **Not GPU-verified**: visuals, popping and frame time still need the honest
  harness / integrator capture.

- 2026-11-24: **World review pipeline — snapshot, not gameplay truth**:
  - `tools/bake_review_map.gd` + `game/addons/tat2_review/` build one tagged
    binary `LevelLoader` scene per `.tatlevel.json` (plus instancing
    `world.scn`/`review.tscn` and a manifest), and `review_mode.tscn` provides a
    no-mission free camera through the same loader. Verified on `thieves_den`
    (285 mesh instances, 4.08 s, 26.9 MiB across 3 sublevel scenes) and
    `mission_lobby` (66.3 MB, 4.21 s); see
    [`reports/review-map-baker.md`](reports/review-map-baker.md).
  - **Measured**: the full Guildhall bake is 18.76 s / 371 MB across 18 scenes
    (16 sublevels), 33,356 tagged nodes, 312 `beam_lines`, 481 emissive plates;
    the master loads headless in 9.1 s / 3.4 GB RSS. The review scenes are
    static snapshots: no player, AI, doors, loot, devices, missions, weather or
    streaming, so they cannot validate gameplay or lighting parity.
  - **Residual**: per-sublevel loads each receive the loader's 160-light
    budget in the editor master, so it shows 562 lights and 1,479 occluders
    versus the shipped 160/768; the Lighting toggle hides them. The full
    editor master failed Vulkan device creation on the 8 GB laptop GPU, and a
    visible 87 MB per-sublevel scene was still loading after 2.5 min, so the
    editor path is unverified on this machine. The in-game review
    (`make review`) and six-bookmark captures (`make review-capture`) are
    verified; `--hide=Beams` confirms the long lines are the 312 beam-tagged
    meshes (vault crop RMSE 3.2 % vs 0 % in beam-free views).

- 2026-11-24: **Spider personal chain integrated (01 → 04, `7aa2a67`..`eb55bc1`)**;
  full detail and probe output in
  [`reports/spider-chain-integration.md`](reports/spider-chain-integration.md).
  - **Chain live**: first Guildhall deploy → Library letter → Den/next deploy
    electrotype → Vault Owl → Lounge courier → Old Manor Courtyard informant;
    `stage=complete`, 7 persistent facts, exact shipped 03/04 lines and
    follow-ups, `[E] Talk`, `[E] Take Theban Owl`. No `03:Reminder`,
    `04:Renegade` or `ObjectiveComplete_*`; no loot/currency/contract/objective
    mutation; Chameleon no-op. Save schema `personal_quest_schema:1`, per thief.
  - **Placements**: letter pin `y=28.0021` on the table (`28.0000`), Owl pin
    `36.4655` on the authored `SM_Manor_BookcasePedestal` top (`~36.4645`;
    1.0 mm offset), courier `[floor]` at `27.0019` with authored yaw **90°**,
    informant `[floor]` at `10.1096` with authored yaw **0°**. No pin was moved
    and no TAT-2 shelf was added. The probe stands the player on the walk floor
    inside the authored 1.75 m interaction range, so no radius is invented.
  - **Verification actually run** on `eb55bc1`: full compile **96/0**;
    `run_tests.gd -- --spider-only` **fails=0** (suites 87 + 88); pure placement
    test **26/26**; subset real-map probe **90/90** with `stage=complete`;
    `probe_leak` **PASS**; `make audit` **PASS**. Thermal peaks: compile 92 °C,
    `--spider-only` 90 °C, probe 90 °C (hard kill 95 °C).
  - **Deferred, not claimed**: full `make test` (all 59 suites),
    `test_m2_player`, E2E 264/264, the real six-pose perf matrix and a full
    editor open on the 8 GB laptop. The host idles near 82 °C.
  - **Perf guard (W4P, `eb55bc1`)**: `--start-temp` 78 / `--max-temp` 95,
    independent 1 s sampler, guarded pre-warm, `VmHWM` 8 GiB cap and a 12 GiB / 0
    swap cgroup; `test_perf_guard.sh` **42/42**. No real matrix run.
  - **codebase-memory** (`9f8f36a`, `877d6ad`): 4 GiB max / 3 GiB high / swap 0,
    `CBM_MEM_BUDGET_MB=3072`, `index_max_files=20000`,
    `index_max_source_mb=512`, marketplace patched, `.cbmignore` +
    `tools/check_cbmignore.sh` **26/26**.
  - **Residuals**: no authored pointer to the 04 informant (the chain can idle
    at `delivered`; Old Manor is contract-only), no VO/nameplate, the letter
    sinks 2.84 mm into the table (accepted), run vs persistent fact semantics
    (personal persisted, contract run-only) and co-op is local-only for this
    chain.

- 2026-11-24: **W5 integrated — movement, loader/render, weather, audio/HUD,
  data producers, sonar P0** (`e6daa96`..`94a75e3`; six branches cut from
  `950f7ca`). Full detail, conflicts and every measured gate in
  [`reports/w5-integration.md`](reports/w5-integration.md).
  - **Traversal (W5A)**: UE-authored `WalkableFloorAngle` 60° (was 50°),
    `MaxStepHeight` 45 cm (was 30 cm), 1.82 m capsule (half-height 0.91, was
    1.78/0.89), step probe 0.20 m forward from the capsule **surface** before
    `move_and_slide`, a mantle gate in `(0.45, 0.50]` without a jump press, and
    an interaction-LOS standoff (`0.6 m`) for the Den wardrobe. The civic flight
    is walkable for the first time (0.25 m risers / 0.33 m treads = 37.1°).
  - **Loader/render (W5B)**: roof meshes use convex shapes (733 boxes → 399
    boxes + 334 convex, 13 unique meshes), roof occluders (398 candidates) are
    no longer emitted, masked materials bind their authored opacity map
    (`MI_HorizonA` no longer a black wall), `DiffuseMaskTint` gated on
    `DiffuseColorMask?` so `MI_PosterWanted` keeps its sepia albedo.
  - **Weather/backdrop (W5C)**: Guildhall = authored `gloomy` (rain 1.0,
    wetness 1.0, fog 0.16; `wet_ground=5, haze_volumes=27, cloud_masks=4,
    moon_actors=8`), `FOG_DENSITY_SCALE` calibrated for 20–120 m, an outdoor
    horizon-haze floor (0.55 @ lum 0.129, Den 0) instead of a black horizon, one
    moonlit cloud tint, and the Den vista staged on the authored **west** window
    (`(-6.06, 43.05, 271.4)`, yaw 148°) instead of the south-wall hatch.
  - **Audio/HUD (W5D)**: 120 ms `cue|position` dedupe, one handle per sustained
    loop (`alarm_loop`/`smoke_cloud`/`lightbeam_hum`) with a stop path, single
    bed on scene re-entry, spherical Light Gem mask, compass reduced to the
    authored centre-line strip and one heading.
  - **Data producers (W5E)**: `unlocks.json` (68 entries), `hearing.json` +
    `perception.json` (54 stimuli / 22 surfaces / 285 portals), and
    `guard_behavior.json` (21 StateTrees / 459 states / 467 transitions) are
    produced, pinned and audited. Guards' runtime use of the tree remains
    **partial** — the producer is data, not behaviour (see the W5E report's
    "not implemented" table).
  - **Verification actually run** on `94a75e3`, serial: compile **101/0**
    (96 + 5 new tests), `run_tests` **fails=0** (261 PASS), `test_m2_player`
    **fails=0**, door walk / viewmodel truth / Niagara **PASS**
    (3695/3308/387/36), `probe_leak` clean (`TAT2_NO_DEN_PROBE=1`), E2E
    **264/264**, `make texture-cap-check` **OK** (773/1/0), `make audit`
    **PASS** (coverage 12657/12703, 0 unexpected) after `make normalize`
    (idempotent) + `audit-refresh-stamps`.
  - **Baseline re-stamp**: four content changes accepted — `gen:weather` (W5C),
    `gen:gameplay` 17→21 files (W5E), plus `devices_runtime.json` and `gen:vfx`,
    which are **pre-existing checkout drift** (no W5 commit touches those
    producers or their inputs); both reproduce deterministically and pass their
    content gates. Stamps only for W5F's `extract_audio.py` / `Program.cs` /
    `prebake_texture_cap.py` / `fetch_vgmstream.sh`.
  - **Deferred, not claimed**: the perf matrix, GI, Vulkan captures, `make run`
    visual pass and a full editor open. Thermal gate was waived by the user;
    still no parallel Godot. Not pushed.
  - **Residuals**: step/floor feel is headless-verified only (0.45 m ledges and
    45–60° slopes are now walkable, which changes routes); the 1.82 m capsule
    needs 4 cm more headroom; `INTERACT_LOS_STANDOFF_M` is global; the Den
    white-clip exact-material caps are still deferred (need captures); the
    guard StateTree data is not yet driving `guard_ai.gd`.

- 2026-11-24: **W6M movement truth** (`fix(player): blocker-safe step-up,
  traversal coverage and capsule contract`; report
  [`reports/w6m-movement-truth.md`](reports/w6m-movement-truth.md)):
  - `_try_step_up()` now refuses a `blocking_volume` on both the blocked sweep
    and the floor probe (a 0.40 m designer blocker used to be a legal tread), and
    evaluates headroom at the **landing** rather than the origin (2.25 m soffit
    over a 0.45 m step refuses; 2.35 m commits). The walkable-normal ramp guard
    only applies when the body is not actually walled, which fixes mid-flight
    stalls caused by the capsule bottom catching the next tread's top (Old Manor
    tower stalled at 2.39 m, POI 3x850 at 5.74 m).
  - Added a post-move `_try_step_down()` (UE `FindFloor` shape) so a walked
    descent re-seats onto the tread under the axis; the destination capsule pose
    must be free, otherwise the rear of the capsule would be pushed into the
    step behind (measured 0.248 m solver bounce).
  - `body_height_m()` / `BODY_HEIGHT_STANDING` now report the built 1.82 m
    capsule (W5A rebuilt the body but left 1.78 m). `device_geometry.gd`'s
    fallback constant and the W3 beam **mock** fixture remain 1.78 m — follow-up
    owner: devices.
  - `try_auto_mantle()` gains a 0.3 m wall sample so a 0.50 m ledge can mantle
    with the authored jump press (`mantle_050`); it previously had no probe
    below a 0.50 m top.
  - **Residual — stair descent is re-seated, not glued.** Godot snaps before
    `move_and_slide`. On shipped 0.33 m treads with the 0.32 m capsule the
    descent still takes short one-riser falls (civic rotated run: 33 airborne
    frames over 100 frames, ends grounded). Deep-tread 0.60 m fixtures settle to
    a max 11-frame interval. Not a soft-lock; recorded rather than hidden.
  - **Deferred (W6L)**: roof `EndA`/`EndB` classifier and roof-hull tests. No
    roof-dependent route assertion is claimed here.
  - Verified in the worktree: compile **102/0**, `run_tests` **fails=0**
    (261 PASS, suite 45 updated to the 1.82 m fixtures + blocker control),
    `test_stair_walk` **fails=0** (7 shipped routes incl. rotated/non-uniform and
    a descent), new `test_traversal_routes` **fails=0**, `test_m2_player`
    **fails=0**. E2E to be re-run by the integrating parent.

- 2026-11-24: **W6 integration — six waves merged** (`91ce8db` W6L loader,
  `d2a6d6c` W6M movement, `77a5c1a` W6G AI, `dc58f60` W6U1 UI, `9884082` W6U2
  ledger/wardrobe, `e8052ef` W6T tooling; integration fixes `96fae4f`; report
  [`reports/w6-integration.md`](reports/w6-integration.md)). All six applied
  with **no file conflicts**; `run_tests.gd` auto-merged four times with every
  hunk kept (33b, 45, 26/55b, 60c/8).
  - **Loader/materials (W6L)**: authored metallic/roughness/emissive ranges are
    mapped (218 materials bake a real roughness range, 0 keep the midpoint;
    two-tone emissive tint with family ceilings), pitched roofs use convex hulls
    and the roof classifier/occluders/searchlights are authored. W5B roof
    census now **733 instances / 46 meshes, 426 convex / 19 + 307 box / 27**
    (was 334/399), roof occluders **0**.
  - **Movement (W6M)**: blocker-safe step-up (a `blocking_volume` is never a
    tread), landing-headroom check, post-move `_try_step_down()`, `1.82 m`
    `body_height_m()`, 0.3 m wall sample for the 0.50 m mantle.
  - **AI (W6G)**: all 54 authored hearing stims are wired (`HearingData`:
    MaxRange × surface × weather, `heard_by`/query gating, Short/Long
    investigation, 285 portals read-only); hearing raises alertness only and
    **never writes the 0..100 meter**; the port-only `vis_mult` light
    multiplier is gone — light gates acquisition **range** only. 5 authored
    range anomalies are clamped and logged once.
  - **UI (W6U1/W6U2)**: authored briefings (3), 1200 s prep override, prep stage
    and Den poster light; the Black Market and Wardrobe are driven by the
    68-row authored unlock catalog with stable `save_id`s, a one-time legacy id
    migration (tools `fairy`/`slithersap`, short cosmetic ids), no placeholder
    prices, and KF03/KF04 three-column wardrobe panels.
  - **Tooling (W6T)**: graybox P0 + 3rd-floor re-materialisation moved into
    `game/data/expansion/content_overrides.json` (11 rules, **508 matched / 133
    re-materialised**, 6/6 coverage regions clean, `add_cap` validated but
    disabled), applied by `parse_tables` before each `.tatlevel.json`; Sonar CI
    workflow + GDScript gate ratchet (`gate_ratchet.json`).
  - Five merged-tree defects fixed (none weakened, none skipped):
    `level_loader.get_meta(…, null)` engine-error spam → `has_meta()`;
    `run_tests` 60c now pins the starter profile instead of trusting a live,
    migrated save; E2E `T3-25` asserts the documented "reaches SUSPICIOUS"
    contract (the old exact `state == 1` depended on the removed light
    multiplier); `test_content_overrides.gd`'s `dict.get(k) or []` returned a
    bool and made the whole static test vacuous (2 → **447** assertions);
    `parse_state_tree.py` said the 54 hearing rows were unwired.
  - Verified on `96fae4f`, serial: compile **110/0**, `run_tests` **fails=0**
    (263 PASS), M2 **fails=0** (11), door walk / viewmodel / Niagara **PASS**,
    `probe_leak` clean, E2E **264/264**, standalone W6 suites all fails=0
    (W5B materials 71, roof 51, searchlight 16, hearing 39, light-once 7,
    briefing 37, catalog 61, stair/traversal/content-overrides static 447),
    `make audit` **PASS** (coverage 12657/12703, 0 unexpected), texture cap
    **773/1/0**.
  - **Residuals**: stair **descent is re-seated, not glued** (short one-riser
    falls on 0.33 m treads; deep-tread fixtures settle); the 1.82 m capsule
    needs ~4 cm more headroom in tight fits; `device_geometry.gd` and the W3
    beam mock still assume 1.78 m (owner: devices); W6T graybox materials are
    authored but not capture-verified and `add_cap` is disabled; the W6L
    roughness bake costs **~3.85 s / ~98 MiB per Guildhall load** (sanctioned
    fallback `roughness=high` not taken); guard StateTree data still does not
    drive `guard_ai.gd`.
  - **Not run**: perf matrix, Vulkan captures, `make run` visual pass, full
    editor open, Sonar scan. Not pushed.
- **W7G — export provenance, roughness cache, core bake, Sonar plan**
  (`74a43b8` + wave, 2026-11-24):
  - `make linux-build` writes `build/tat2-linux-x86_64.stamp.json` (HEAD short +
    full, UTC time, Godot version, dirty flag, binary/PCK SHA-256 + bytes). The
    perf wrapper verifies it and **fails closed** on a missing, stale
    (`stamp HEAD != HEAD`) or hash-mismatched stamp, logs
    `PERF_PROVENANCE`/`PERF_PCK`, marks a dirty build or an unverified
    `PERF_BINARY` non-publishable, and `--publishable-only` refuses those runs.
    Measured PCK: 2,574,092,822 B / `642fb055…`; binary 73,519,416 B /
    `d9f79ab8…`; the worktree is dirty by design (private data symlinked), so
    `publishable=0`.
  - `MemoryMax` is derived from RAM at 75 % (2 GiB floor, override
    `PERF_SCOPE_MEMORY_MAX`); RSS sanity is now 1024..262144 MB, ≤ total RAM and
    ≤ the scope. `--rss-check=<MB>` proves the decision without a launch.
    `test_perf_guard.sh` is **78/78**.
  - `scenes/review/**` is excluded from the QA export. **Trap:** Godot's
    `ConfigFile` does not accept `#` comments; an explanatory comment above
    `exclude_filter` silently merged into the key and unset the exclusion with
    no error. Comment removed; `has_section_key("preset.0","exclude_filter")` is
    true; the second export has 0 `res://scenes/review/` lines and only +1.44 MB
    PCK vs the pre-bake export.
  - Roughness keeps **full authored resolution**. The L8 bake is now cached
    process-wide by ORM+range and released when the last live loader leaves; the
    first Guildhall load measured **86 bakes / 73,924,608 px / 4,089 ms /
    98,566,111 B / 46 cache hits**. A two-loader probe confirms sharing, a
    distinct range and teardown re-bake. `probe_leak` is clean (0 leaks) with the
    cache active. `TAT2_ROUGH_BAKE=off` is a documented fallback only.
  - Core bake at this HEAD: `guildhall_core.scn` **203,393,969 B = 194.0 MiB**,
    **52.6 MiB (24.2 %) under** the 256 MiB guard; headless load `VmHWM`
    **782 MB** (`/proc`), `load_ms=387`.
  - Visible editor open: process `VmHWM` **3,934 MB** (within ≤5.6 GB), but
    `nvidia-smi memory.used` is **device-wide**, so the 6,931 MB peak **cannot
    be evaluated against the ≤2.5 GB process threshold** — not a pass. GPU
    82.38 °C / CPU 97 °C recorded (thermal waived); the harness terminated the
    session, so a per-process VRAM measurement and a normal close remain open.
  - Sonar Path A config repaired: `.github` in `sonar.sources`, actions pinned
    by SHA, gate = new-code Reliability A + Security A + duplication ≤3 %;
    `qualitygate.wait` with 600 s timeout. **No scan run**; the gate stays
    unbound until autoscan-off, `SONAR_TOKEN`, "TAT-2 New Code" and
    Previous-version are set manually.
  - Ratchet floors (**base measurements, not merged-tree numbers**):
    compile 110/0, `run_tests` 263/0, M2 11/0, E2E 264/264, coverage_den 12703,
    `measured_on: 74a43b8`. `check_gate_ratchet.py` derives every expectation
    from `gate_ratchet.json` and verifies committed logs under
    `docs/reports/logs/`; missing/stale logs fail with the command to re-run.
    S2/W7E/W7H will measure higher at integration, which raises the floors with
    fresh logs.
  - **Not measurable here:** `make audit` — W7S's uncommitted loot producers
    changed 4 `gen:gameplay` files plus a directory hash; integration
    regenerates and re-stamps at the merged HEAD. Audit floors unchanged.
  - **Not run:** perf matrix (explicitly), Vulkan capture (no rendering change),
    Sonar scan.

- 2026-11-24: **W7H — surface-resolved hearing, swing-door creak, indoor weather
  scope, stair descent** (report
  [`reports/w7h-hearing-descent.md`](reports/w7h-hearing-descent.md)).
  - **Surface resolver** (`src/stealth/surface_resolver.gd`): the old map rule
    (`contract 1 = wood`, everything else `stone`) is gone. A down-ray resolves
    the authored collider per shape (`CollisionShape3D` `ue_mesh` from
    `_add_collider`, explicit `surface_type`/`ue_surface`/`surface` overrides,
    `override_materials`, mesh/material name rules) onto one of the 22 authored
    `DA_LoudnessModifiers` rows, and the same decision feeds the AudioManager
    pool token. Unknown/empty -> stone (authored 1.5), never a crash and never a
    silent 1.0. Matched on the file name first, so UE folder words
    ("/Game/Art/Environment/...") cannot decide a surface.
  - **Hearing matrix**: 22 surfaces x 3 gaits x 3 weather rows = **198 cases**
    assert `radius = min(stim x surface, 25 m x weather)` exactly, heard at the
    radius and silent 0.01 m past it. Silent faces 0.0 (carpet, foliage, ivy,
    grass, dirt), hard 1.5 (15 rows), medium 1.0 (lattice, tile); 3D distance
    with no floor occlusion; astral and knocked-out negative controls.
  - **SEARCH timer refresh**: a repeated stimulus now refreshes the authored
    fan-out window (4 s short / 8 s long) instead of letting the search expire
    mid-investigation. `lockpick` (Picked 3 m) and `lockpick_jammed` (Jammed
    10 m) are split so a jam is the loud outcome.
  - **Swinging doors** emit exactly one authored `OpeningCreak` (5 m) per open
    and per close, with the lock path no longer double-firing (the unlock emits
    only when it does not start a swing).
  - **Indoor weather scope**: `WeatherProfile.is_indoors_at()` (ceiling probe)
    and `sound_carry_multiplier_at()` decide the authored indoors/outdoors side
    per listener, so Old Manor interiors use 1.0 (exterior 0.9) and Jaspering
    interiors 1.0 (exterior 0.8); the Den stays indoor everywhere.
  - **Descent D1 + D5**: the step-down ray casts 0.40 m but accepts only a floor
    <= 0.30 m below the origin; air->floor transitions at or below 0.30 m no
    longer play `jump_land` or the airborne viewmodel (T1-T6: 1 interval,
    0 landing events, grounded; the 0.45 m control stays one real fall).
  - **Residual — walked descents are still not glued**: with D2 default-off a
    0.18-0.30 m walk-off takes 4-12 airborne frames (D1 sees the tread, but the
    destination capsule still grazes the riser behind). The measured D2 opt-in
    (0.06 m destination-query shrink, guarded by `STEP_UP_GUARD_SEC`) reaches
    1-2 air frames with a **0.001 m** shove-back and a full 3-riser stair ascent,
    and stays behind `STEP_DOWN_QUERY_SHRINK_M = 0.0` by decision.
  - **Roof routes are now asserted** (W6L had deferred them): the shipped 45.2°
    hip walks up 3.37 m with no step-up or mantle, the 67.6° module is refused,
    EndA/EndB eave bands sit 3.40 m below the AABB top the old box floated and a
    dropped body falls off the shell, the hip's four faces fall 2.70 m below the
    ridge, and the non-uniform POI instance (scale 0.8 on the slope axis)
    measures 51.1° vs the expected 51.5° and stays walkable.

- **Visual acceptance wave W7V (2026-11-24)** — KF11 skyline, Chameleon Cotter
  wardrobe, live Black Market tool preview, acceptance captures.
  - **KF11 prep (TAT-2 expansion, not shipped art)**: the authored lobby
    sublevels carry no usable skyline in the framed sector, so
    `game/data/expansion/prep_skyline.json` is **new TAT-2 expansion content**
    (`expansion: true`, `source` names the expansion) placing shipped Skybox
    assets: `SM_DistantBuildingC`, `SM_DistantTowerA/B`,
    `SM_SkyboxSmokestacksA`, `SM_Skybox_UrbanTowerB` with their authored
    materials (`M_DistantBuildingC`, `ML/MI_DistantBuidingA`,
    `M_DistantTowerB`, `ML/MI_SkyboxSmokestacks`, `M_DarkGrey`). It is
    decorative (no collision/shadows), excluded from the lobby fog/ambient
    passes and graded as a backlit silhouette. The stage keeps FOV 20
    `KEEP_WIDTH`, roll −14.78°, `midnight_clear_mission_lobby`, the moon at
    screen (0.76, 0.09), and the thief at screen x 0.77 via a 1.26 m dummy
    offset (a camera yaw into the authored city block hid the moon).
  - **Wardrobe**: defaults now resolve to `Head.BowlerA` / `Body.Default` /
    `CallingCard.Default` (not the alphabetic `AltA` Tarantula row); the
    Chameleon renders the authored ThiefCotter body and all 18 Head-row Cotter
    meshes (TopHatA.MonocleA uses the shipped combined `..._TopHatA_MonocleA_BeardA`
    mesh), with `AN_ThiefCotter_WardrobeIdle`. KF03 three-column layout and no
    APPLY unchanged.
  - **Ledger/Black Market**: shared `ToolPreviewStage` drives the Wardrobe tool
    card and a new live `LedgerToolPreview` SubViewport for tool rows; non-tool
    rows keep the authored reward icon. Ledger modal is centred at 1280×720 and
    1920×1080. Catalog rows/prices/gates untouched.
  - **Captures** (1920×1080, serialized Vulkan, sidecars with pose/FOV/preset/
    save/profile/ROIs): `prep_before`/`prep_after`, `prep_720`, `briefing`,
    `den_poster`, `den_west_window` (C1), `ledger_kf07`/`kf08`,
    `wardrobe_kf03`/`kf04`/`chameleon`. No pre-W6L PNG is cited as current.
  - **Deferred**: monochrome slot-icon shader; blurred Ledger/Wardrobe panel
    background; briefing `T_Paper01` tone/creases and the `SPACE` keycap (HUD
    pass; `hud.gd` untouched); C8 Guildhall haze/wet ground and C9 horizon vs
    zenith captures (Guildhall mission staging, not owned here).
  - **Gates**: compile 112/0, W7V 49/0, W6U1 0, W6U2 0, `run_tests` 0,
    E2E 264/264. `make audit` exit 2 on the W7S producer drift +
    missing `vgmstream`; not fixed, not re-stamped.
