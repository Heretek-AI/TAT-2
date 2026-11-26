# W10-A independent audit

Auditor: a fresh session that wrote no part of W10-A.
Tree: `/home/john/Projects/TAT-2-rem-w10-a`, branch `w10/a`, tip **`b3e4a68`**,
base `29046c8` (verified ancestor). Nothing outside this worktree was written.
Scratch logs: `/tmp/opencode/audit/`. The only file created in the tree is this one.

**Working-tree note (found at audit start, no action taken):** `git status --short`
shows `M AGENTS.md` and `M build/qa/w10/a-report.md` in addition to the
symlinked private data (`extracted`, `game/assets`, `game/data/generated`). The
two edits are uncommitted at `b3e4a68`; they are improvements (per-map reduced
names, the "78 derived not measured" caveat, the new DoD commands) but the tree
is not clean, which AGENTS.md's own definition of done asks for.

Method: every Godot run was serial under
`flock /tmp/opencode/tat2-godot.lock -c "timeout … tools/godot --headless --path game --script …"`.
One collision-probe run was made while this audit's own Python gates were running
and **failed on the probe's 45 s wall-clock deadline** (guildhall `load_ms=46234`,
`deadline hit 75`, shapes 30 609 instead of 30 819). The clean serial re-run below
is the audit result; the loaded-host failure is recorded in §F as a robustness
note, not as a wave failure.

---

## A. The ten defect claims

| ITEM | AUDIT | evidence (verbatim line / command) |
|---|---|---|
| **D1** `continue_requested` consumer | **PASS** | `PASS: INV-1a.6 pressing Continue closes the HUD post-match screen`; `PASS: INV-1a.4 the HUD connects continue_requested (connections=1)`; `PASS: INV-1a.2 pressing Continue closes the post-match screen`; `W10_SCREENS_SUMMARY: fails=0 checks=39` (my run). Test presses the real `ContinueButton`; code `post_match_ui.gd:_on_continue_pressed → _close(false)`, `hud.gd:_on_post_match_continue`. |
| **D2** main-menu focus restore | **PASS** | `PASS: INV-1b.4 focus is restored after Settings closes (owner=@Button@69)`; `INV-1b.5/1b.8/1b.9` PASS. Real `_on_settings_pressed()` / `_on_tutorial_pressed()` and real `close_settings()` / `close()`; `SettingsUI.closed` / `TutorialUI.closed` exist and are connected to `main_menu._on_modal_closed` (`install(_menu_v)` + `restore()`). |
| **D3** ESC also opens pause behind PostMatch/Progression | **PASS** | `PASS: INV-1c.2 … (paused=false)`; `PASS: INV-1c.6 ESC on Progression must not open the pause menu behind it (paused=false)`; negative control `PASS: INV-1c.8 a later pause press with no screen open still pauses (paused=true)`; `INV-1c.3/1c.7` still close. Stamp lives in `focus_nav.gd` (`Engine.get_process_frames()`), set by `post_match_ui` and `progression_ui` before `close()`, read by `hud._process` — so it is opener-independent (the Ledger path is covered by construction, see §F). |
| **D4** timeout/collapse renders "Caught" | **PASS** | `PASS: INV-1d.1 PostMatchUI timeout renders TIME EXPIRED`; `INV-1d.3` MAGIC DOOR COLLAPSED; `INV-1d.5/1d.7` HUD halves; negatives `INV-1d.4/1d.8` capture still `CAUGHT`, `INV-1d.9` escape still `ESCAPED`. Producer wiring re-read: `mission_controller.gd:4656-4657` sets `timed_out`+`timeout_reason`, `:4688` calls `_finish_run("timeout", DOOR_COLLAPSED_REASON)`, `:4663` passes `contract_info` to `hud.show_result`, and `hud._open_post_match_xp` passes `_last_info` to `open_result`. Not merely a test fixture. |
| **D5** repeated opens stack layers | **PASS** | `PASS: INV-1e.1 exactly one PostMatchUI lives under the HUD after two opens (1)`; `INV-1e.2 … visible (1)`. `hud.gd:_open_post_match_xp` does `release_if_inside` + `remove_child` + `queue_free` before replacing; `_post_match_ui` member. |
| **D6** NDJSON unbounded after ring fills | **PASS** | `D6_TRACE ring=8192 dropped=808 pushed=9000 file_lines=8192 file_bytes=369466`; `D6_FILE pushed=9000 file_rows=8192 file_dropped=808 file_bytes=369466 disk_bytes=369466 lines=8192 cap_rows=8192 cap_bytes=16777216`; stop phase `D6_FILE_STOP pushed=15000 lines=8192 file_rows=8192 file_dropped=6808`; byte cap `D6_BYTES pushed=400 file_rows=255 file_dropped=145 file_bytes=16720750 … cap_bytes=16777216`. Code re-read: `_file_capped` returns without `store_line`; `dropped` still ring-only. Mine, `test_w10_runtime.gd`. |
| **D7** zero-volume authored convex became a collider | **PASS** | `D7_WARD source=hull elements=1 convex=1 shapes=0 offsets=0 degenerate_hulls=0`; `D7_WARD instances=160 shapes=0 planar=1`; `D7_FX …FXQuadPivotCenter … shapes=0`, `…DownEdge … shapes=0`; `D7_PLANE source=prims elements=1 shapes=1 size=(1.0, 0.02, 1.0) box_clamped=1`; `D7_GLASS … one clamped box size=(0.990266, 4.554503, 0.02) box_clamped=1 planar=0`; `D7_DOORWAY elements=14 instances=1 shapes=14 reduced=false \| instances=37 shapes=1 reduced=true`; grounding `fixed_y=0.0000 pre_fix_y=1.0000`. Code re-read: only `KIND_CONVEX` with `_planar_extent < 1e-4` is skipped; boxes keep `MIN_HALF_EXTENT_M` and are counted. |
| **D8** prison door pickable on an absent flag | **PASS (NOT REPRODUCED confirmed)** | My own dump reads: `StaticMeshActor_528 | _locked= True \| lockConfig= {"KeyTag": {"TagName": "Item.Key.Buildings.Guildhall"}}`; FTUE #53 `BP_Manor_Doorway_4x6_C_2 _locked= True _lockConfig={"CanBeLockpicked": false, …}`; chain `BP_Prison_WallA_DoorwayB2_6x6_C → BP_SwingingDoor_DoubleBase_C → BP_SwingingDoor_C (SuperStruct TATSwingingDoor, MaxLockLevel 4)`; census 34 `false` / 3 `true`; 33 placed `false`, 7 with KeyTag, 26 without. Gate: `W10_LOCKS_SUMMARY: fails=0 checks=25`; `LOCK_CDO PASS classes=31 explicit_false=34 one_false_class=BP_SlidingWindow_Base_C placed_false=33/33`. Disposition correct (see §G.1). |
| **D9** runtime-smoke blind to `ERROR:`/exit | **PASS** | `RUNTIME_SMOKE_SCAN_TEST PASS checks=29 fails=0` with `PRE_FIX_BLIND_SPOT: ERROR: line -> runtime_smoke.sh at 29046c8=PASS, scanned=FAIL` (+ push_error, crash, premature exit 0, clean-log-exit-1); runner `build/qa/runtime_smoke.sh` delegates and keeps the log; scanner accepts exit 124 only, requires `mission_ready`. Real boot, my run: `RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 … mission_ready=1 reason=ok` (§D). |
| **D10** two stale traversal tests + stair exemption | **PASS** | `W6M_STAIR_SUMMARY: fails=0`; `PASS: oldmanor_tower_4x850 authored union: 36 element(s) (per element), 36 emitted shape(s) — the per-element set, not shapes[0]`; `W6M_TRAVERSAL_SUMMARY: fails=0`; `PASS: SM_RoofUrban_Ext_Mid_4x4 roof collider: 3 authored element(s), 3 emitted shape(s)` and the hip/End modules. Both fixtures now emit one `CollisionShape3D` per authored element at its own offset and pin the count; if the stair exemption vanished, `elements=36, reduced=true` would fail the test's `got_reduced == want_reduced`; if only `shapes[0]` were built, the roof `elements == 3/4 && shapes.size()==elements` and stair `shapes.size()==authored` checks fail. |

## B. Evidence-hardening items (brief §"Wave A scope")

| ITEM | AUDIT | evidence |
|---|---|---|
| Collision probe covers OldManor+FTUE, names every reduced mesh, fails on `dropped>0`/coverage<0.95 | **PASS** | my clean run: `COL_MAPS PASS maps=3 min_coverage=0.976 dropped=0 planar_skipped=2 coverage_ppm=976277`; `COL_MAP_ASSERT map=guildhall … 0.989 … PASS`, `old_manor … 0.993 … PASS`, `ftue … 0.976 … PASS`; 71 `COL_REDUCED` lines (16+35+20); failure branches at `probe_collision_authored.gd:253-285`. |
| Lock probe fails at `applied==0`, prints runtime (containers + door nodes) not raw 363 | **PASS** | `LOCK_INVENTORY runtime: authored=173 raw=363 applied=154 containers=144 door_nodes=10 discarded=209 state=APPLIED`; `LOCK_INVENTORY PASS … applied=154 containers=144 door_nodes=10`; `_check(applied > 0)`, `_check(containers > 0)`, `_check(door_nodes > 0)` all increment `fails` → `quit(1)`. Authored-dump assertions 173/157/8/8 and 155/3/15 intact. |
| String audit is a gate with floors | **PASS** | `UI_STRINGS GATE PASS routed=306 authored=195 invented=111` (exit 0); negative control `--min-routed 9999` → `UI_STRINGS GATE FAIL routed=306 < min-routed=9999`, exit 1. `make audit` includes `string-audit`. |
| StateTree coverage asserted (77/326/113/94, 36/233/35/32, 0/21) | **PASS** | `W9P4_STATETREE_SUMMARY: fails=0 checks=86`; diff adds exactly 9 `_ok` absolute assertions (77/326/113/94/36/233/35/32 + `fully.size()==0 and per_tree.size()==21`), no relational assertion removed; 86−9=77 = the W9 check count. |
| Literal greps gated | **PASS** | `LITERAL_GREPS PASS code_hits=0 ui_rating_literals=0 files=96`; `make check-greps` in `audit:`; PROBE_GATES marker added. |
| Ratchet extended to the six new families | **PASS** | `make gate-ratchet` → `GATE_RATCHET: PASS`; `tools/gate_ratchet.json` adds `probe_collision`, `probe_collision_maps`, `lock_inventory`, `string_audit`, `literal_greps`, `runtime_smoke`; compile floor 189, run_tests 319. |
| "No further re-run" claims are backed by committed logs | **FAIL** | 16 of the 21 logs post-date the last source edit (21:17:08); 5 pre-date it (lock probe, suite 110, string audit, literal greps, smoke engine log) and of those only `runtime_smoke_godot.log` carries evidence of the shift. Its backtraces name `level_loader.gd:6238/4480` while the tip has `6243/4483` (`stat` 21:13:46). The tip-tree run exists at the path `runtime_smoke.log` names (`/tmp/tat2-smoke-ZV6qT7.log`, 21:44) and I scanned it: `RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 raw=0 allowed=0 … mission_ready=1 reason=ok`; my own fresh 90 s boot (§D, 22:16, `level_loader.gd:4483`) also passes. Both runs are clean; the committed pair is mismatched, so the file must be replaced. |

## C. Doc corrections

| ITEM | AUDIT | evidence |
|---|---|---|
| `docs/reports/w9-remediation-20261125.md` locks 363→154 and per-map collision | **PASS** | `154 runtime locks (144 container placements + 10 door nodes; … pre-dedup record join is 363)`; my probe prints exactly `raw=363 applied=154 containers=144 door_nodes=10 discarded=209`; `937/947 (0.989) / 687/692 (0.993) / 535/548 (0.976)` reproduced. Wording nit: "the 8 window pivots" are 8 window **actors** → 16 locked pivot records (I counted 16 records / 8 actors); harmless but imprecise. |
| `docs/FIDELITY_GAPS.md` collision/lock rows | **PASS with one error** | 233 of 1,667 and 82+78 ward instances reproduced exactly (see §G.2); **the sentence "the 160 `SM_SlowWardZone_Quad` billboards … and the 3 FX quads" is wrong**: the dump has 3 coplanar convex elements = 1 ward + **2** FX quads (`D7_DATA … flat_convex=3`; expected list `[FXSHAPES_1_FXQuadPivotCenter, …DownEdge, SM_SlowWardZone_Quad]`). |
| `docs/FIDELITY_GAPS.md` localization row | **PASS** | `Loc.t(` occurs exactly once in `game/src`, in `localization.gd:11` (docstring); routing is `UIStrings` 306/306, 195 authored. "111 labelled port-copy rows" is loose (the audit's `invented` = routeable copy with no authored counterpart) but not false. |
| `docs/HANDOFF_NEXT_AGENT.md` gate block and W10-A summary | **PASS with clarification needed** | 189/319/116, 278/278, 154/144+10, 306/195/111 all reproduced. The IBL clause "cubemap export missing *and* no runtime consumer of it" is defensible only if "consumer" means *the texture* (nothing loads it); read next to the false T07 sentence it will mislead: `weather_profile.gd:959` (`apply_environment`, the runtime builder) already calls `sky_ibl_state()` and `:960-964` flip `ambient_light_sky_contribution` from it. Clarify to "no texture/reflection consumer". |
| `AGENTS.md` (gate table, 154, new traps) | **PASS with one error** | 189/319/116/278 and 154 runtime reproduced. **"the 160 … billboards and the 3 FX quads" repeats the miscount** (2 FX quads). Also the gate-table header still says "(W9 tip, logs in `docs/reports/logs/r8/`)" while the logs are `…/w10/` — stale label, not a number. |
| `build/qa/w9/p3-report.md` SHADOW sentence | **PASS** | `grep -rn SHADOW game/src --include=*.gd \| wc -l` → **96**; none is a result rating (`SHADOW_CASTING_SETTING`, `TAT2_SHADOW_HEROES`, `shadow_runner` …). |
| `docs/reports/remediation-20261125/T07-render.md` IBL note | **FAIL** | The replacement text says **"`sky_ibl_state()` is called only by `game/tests/probe_render_t07.gd`"** — false: `game/src/core/weather_profile.gd:959` calls it in the environment build, `:960-964` consume `available`/`sky_contribution`, and `:540` already documents that consumer. "Emitting the `.exr` alone would change no pixel" is therefore also not established: `available` would flip `ambient_light_sky_contribution` 0→1. The true residual is narrower: no `PanoramaSkyMaterial`/reflection texture consumer. |
| `build/qa/w10/a-report.md` before/after table and per-map numbers | **PASS** | My re-runs reproduce 0.989/0.993/0.976, 30 819/22 567/37 646 shapes, 71 reduced names, 154/144/10, 306/195/111, D6/D7 lines. Exception: row 7's "27 meshes / 314 real thin solids" is **NOT REPRODUCED** — see §G.3. |
| `build/qa/w10/a-report.md` §0 runtime-smoke line | **PASS (claim), evidence file stale** | `RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 … mission_ready=1`; my 90 s run (§D) reproduces it; the committed `runtime_smoke_godot.log` is the pre-21:17 run (see B). |

## D. Gate re-runs (all by me, this tree)

| Gate | Result | evidence |
|---|---|---|
| compile | **PASS** | `scripts checked: 189, broken: 0` |
| `make test` | **PASS** | `319` `PASS:` lines, `SUMMARY: fails=0`, suites 112–116 present (`PASS: 116 … (63094 ms)`), 22:05:26–22:09:50 |
| M2 | **PASS** | `M2_SUMMARY: fails=0` (12 checks), 22:09:50–22:09:53 |
| E2E | **PASS** | `SUMMARY: fails=0 passed=278 total=278`, 22:09:53–22:16:09 |
| `test_w10_screens.gd` | **PASS** | `W10_SCREENS_SUMMARY: fails=0 checks=39` |
| `test_w10_runtime.gd` | **PASS** | `W10_RUNTIME_SUMMARY: fails=0 checks=45` |
| `test_w10_locks.gd` | **PASS** | `W10_LOCKS_SUMMARY: fails=0 checks=25` |
| `test_stair_walk.gd` | **PASS** | `W6M_STAIR_SUMMARY: fails=0` |
| `test_traversal_routes.gd` | **PASS** | `W6M_TRAVERSAL_SUMMARY: fails=0` |
| `test_w9p4_statetree.gd` | **PASS** | `W9P4_STATETREE_SUMMARY: fails=0 checks=86` |
| `probe_collision_authored.gd` | **PASS** (clean run) | `COL_MAPS PASS maps=3 min_coverage=0.976 dropped=0 planar_skipped=2 coverage_ppm=976277`; `COL_WALL total_ms=63887` |
| `probe_lock_inventory.gd` | **PASS** | `LOCK_INVENTORY PASS … applied=154 containers=144 door_nodes=10` |
| `p3_string_audit.py --min-routed 306 --min-authored 195 --max-invented 111` | **PASS** | `UI_STRINGS GATE PASS routed=306 authored=195 invented=111`, exit 0 |
| same, `--min-routed 9999` | **PASS (negative control)** | exit 1, `GATE FAIL routed=306 < min-routed=9999` |
| `tools/check_literal_greps.py` | **PASS** | `LITERAL_GREPS PASS code_hits=0 ui_rating_literals=0 files=96` |
| `build/qa/w10/check_lock_cdo.py` | **PASS** | `LOCK_CDO PASS classes=31 explicit_false=34 one_false_class=BP_SlidingWindow_Base_C placed_false=33/33` |
| `test_runtime_smoke_scan.sh` | **PASS** | `RUNTIME_SMOKE_SCAN_TEST PASS checks=29 fails=0` |
| `test_perf_guard.sh` | **PASS** | `PERF_GUARD_TEST PASS checks=78 fails=0` |
| `make gate-ratchet` | **PASS** | `GATE_RATCHET: PASS (baseline and committed evidence agree; Godot gates run locally)` |
| `make audit` | **PASS** | `AUDIT PASS`, `baseline: matches …/tools/audit_baseline.json`, `Disk-backed content coverage: 12660/12703 (99.7%) … unexpected 0`, texture cap OK |
| `runtime_smoke.sh 90` | **PASS** | fresh 90 s boot 22:16:09–22:17:39, engine log `/tmp/tat2-smoke-ePeA92.log` (tip line `level_loader.gd:4483`, 138 lines): `RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 raw=0 allowed=0 script_errors=0 shader_errors=0 mission_ready=1 reason=ok`; `RUNTIME_SMOKE PASS` |

### D.1 NOT RE-RUN (with the reason)

| Item | Why | what I did instead |
|---|---|---|
| Pre-fix red proofs (`INV-1a…1e`, `INV-2` D6/D7, D10 `fails=13/4`) | They require the base tree (`29046c8`) with the new suites, i.e. a separate worktree; the wave's rule is one worktree, and reverting here is forbidden. | Read the committed red lines in `inv-1-screens.md`, `inv-2-runtime.md`; verified the new suites exercise the same node paths and negatives, and that their failure modes are reachable (e.g. D6 `lines <= 8192` fails on a 9 000-line file). |
| `probe_door_walk.gd`, `probe_viewmodel_truth.gd`, `probe_niagara.gd`, `probe_blackjack_race.gd`, `probe_geometry_placement.gd`, `probe_leak.gd` | Unchanged probes, not part of the nine defects; re-running all six would add ~10 min of GPU-free engine time with no new claim. | Verified the committed logs' markers: `DOORWALK PASS`, `VIEWMODEL_TRUTH PASS`, `NIAGARA_PROBE PASS`, `BLACKJACK_PROBE PASS fails=0`, `GEOM_PROBE PASS`, and `probe_leak.log` 0 `ERROR:`/`SCRIPT`/`SHADER` lines ending `PROBE after gh free players=0`. |
| `tools/tat-extract` rebuild, `make normalize`, producer chain fix for `MaxLockLevel` | Out of scope: regeneration is the integrator's job at merged HEAD; the cap item is explicitly recorded, not fixed. | Confirmed the wave does not claim to have regenerated anything (`git status` shows no generated-data change). |
| Linux export / perf matrix / Vulkan captures | Not part of W10-A (no GPU work; brief says so). | Not claimed by the report. |

## E. No-weakening review (every changed test/probe, diffed against `29046c8`)

| File | Removed/weakened? | Assessment |
|---|---|---|
| `test_traversal_routes.gd` (30→31 checks) | No assertion removed. **One expectation re-based**: `atan(tan(45.2°)/0.8)=51.5°` → `atan(tan(unit_union_pitch)/0.8)`; the fixture now builds the full authored union (3–4 hulls) and pins `elements`/`reduced`. | **Justified, not easier.** Written evidence: `impl-c.md` §2c + `inv-2-runtime.md` §B measured unit 51.8° vs scaled 57.9° and state the old 51.5° target could not pass with any hull count (the metric reports the steepest sampled pair, not one face). My run: `measured 57.8 deg == atan(tan(51.9 deg unit union pitch)/0.8) 57.9 deg` — a collider that ignored the scale would measure 51.9° and miss by 6° ≫ the 2.5° tolerance. Strictly self-consistent. |
| `test_stair_walk.gd` (8→9 checks) | No assertion removed. The old `ConcavePolygonShape3D` demand (which aborted six flights) is replaced by the per-element union; `authored_elements`/`reduced` pinned; `_check_union_count` added. | **Stricter.** It fails if the authored count changes, if a non-reduced flight is coalesced, or if the tower exemption disappears (`reduced` would be `true` vs the pinned `false`); `_check_union_count` also asserts every emitted shape is a `ConvexPolygonShape3D`. |
| `test_w9p4_statetree.gd` | Additions only: exactly 9 `+_ok(` absolute assertions; 77→86 checks. | **No weakening.** |
| `probe_lock_inventory.gd` | Authored-dump assertions (173/157/8/8, 155/3/15) intact; `ALLOWLIST` replaced by the loader's identical `LOOT_CONTAINER_CLASSES` (same five strings); runtime half is now fail-closed (`applied>0`, `containers>0`, `door_nodes>0`, identity). | **Stricter.** |
| `probe_collision_authored.gd` | Guildhall legacy lines/assertions preserved (`MIN_AUTHORED_COVERAGE` unchanged at 0.95); per-map loop, `COL_MAP_ASSERT`, reduced names, `dropped==0`, classification identity added. | **Stricter.** |
| `test_w9p2_locks.gd` | `git diff 29046c8 -- game/tests/test_w9p2_locks.gd` → empty. | **Byte-identical.** |
| `run_tests.gd` | Additive registration of suites 112–116 (`exit 0 AND marker` pattern). | **No weakening.** |
| `test_w10_screens.gd`, `test_w10_runtime.gd`, `test_w10_locks.gd` | New files. | n/a |

## F. Weakened or hidden

**No assertion was removed, skipped or softened, and no failure was converted to a
pass.** The single re-based expectation is justified above and is *harder* to
satisfy than a hardcoded wrong face. Caveats found (not assertion weakening):

1. **D3 Progression path in the test is HUD-parented, not Ledger-opened.** The fix
   is screen-side (`progression_ui.gd` stamps before `close()`), so it covers the
   Ledger opener by construction, but the suite does not exercise
   `ledger_ui._open_progression()`. Worth a note, not a defect.
2. **D7's ward assertions use `AuthoredCollision.resolve()` directly**; the
   *placement* evidence is the collision probe's per-map `COL_PLANAR`/shape counts,
   not the suite. Both are present, so the claim is covered.
3. **The collision probe is load-sensitive.** Its 45 s per-map deadline failed
   when I ran my Python gates concurrently (guildhall 46 s, 210 fewer shapes);
   it passes cleanly and quickly on an idle host (21/27/15 s here, 66 s total).
   The gate's own rule (serial Godot) must be obeyed; the report does not mention
   the sensitivity.
4. **`runtime_smoke_godot.log` is stale** (pre-21:17 source edit) although
   `runtime_smoke.log` names a tip-tree run. Claim true, evidence file mismatched.
5. **The working tree is not clean** (`AGENTS.md`, `a-report.md` uncommitted).

## G. Claim-by-claim notes

### G.1 D8 — is `NOT REPRODUCED` right, or is the port wrong?

`NOT REPRODUCED` is the right disposition. I re-derived all three decisive
citations from the dump, not from `re-1-locks.md`:

* `StaticMeshActor_528` (object #1417, `Building_Guildhall_POI.json`):
  `_locked=True`, `_lockConfig={"KeyTag": {"TagName": "Item.Key.Buildings.Guildhall"}}`,
  `Template` → `Default__BP_Prison_WallA_DoorwayB2_6x6_C` — delta serialisation.
* Chain: `BP_Prison_WallA_DoorwayB2_6x6_C` (no `_lockConfig`) → `BP_SwingingDoor_DoubleBase_C`
  (none) → `BP_SwingingDoor_C` (`SuperStruct Class'TATSwingingDoor'`, `{"MaxLockLevel": 4, …}`).
* FTUE #53 `BP_Manor_Doorway_4x6_C_2` (class `BP_Res_Int_Doorway_C`, same native root):
  `_locked=True`, `_lockConfig={"CanBeLockpicked": false, "KeyTag": …, "KeyItemInfo": …}` —
  an explicit `false` on the instance; a delta dump would have dropped it if the
  inherited value were `false`. Census: 34 `false` (33 placed + the
  `BP_SlidingWindow_Base_C` CDO) and 3 `true` (CDOs), no placed `true`.
* The port's current rule (absent → lock, pickable at Lv1) is faithful to that
  resolution; the *adjacent* incomplete input (`MaxLockLevel` 4 not carried by the
  instance-delta producer) is real and is recorded as open in
  `FIDELITY_GAPS.md`/`HANDOFF`, pinned by the new suite. So: not a pickability bug,
  and not silently "fixed" either.

### G.2 Numbers I re-derived independently

* `233 of 1,667`: union of `meshes[].mesh` over the 107 `game/data/generated/levels/**/*.tatlevel.json`
  = 1,667 distinct paths; 233 have no `mesh_collision.json` record (1,434 do). Exact.
* 82 Guildhall + 78 OldManor `SM_SlowWardZone_Quad` instances = 160. Exact.
* 33 placed `CanBeLockpicked:false`, 7 with a `KeyTag`, 26 without. Exact.
* 96 `SHADOW` lines in `game/src/**/*.gd`; none a result rating. Exact.

### G.3 "27 meshes / 314 instances" is not reproducible

`a-report.md` row 7, `FIDELITY_GAPS.md` §W10-A and `impl-b.md` justify the kept box
clamp with "27 thin-box meshes / 314 instances". Reproducing the clamp criterion
(`min(|half_extent|)·0.01 < 0.02` over `mesh_collision.json`, intersected with the
placed paths) gives: **19 placed meshes containing a clamped box, 28 clamped box
elements including `/Engine/BasicShapes/Plane` (exactly 27 excluding it), 315 raw
placed instances (295 excluding Plane; 296 after within-level exact-duplicate
removal)**. So 27 is the clamped *element* count (excluding the Plane the same
sentence names separately), not a mesh count, and 314 matches none of the raw /
deduped / Plane-excluded denominators I tried. The qualitative claim (the clamp is
reached by real thin solids, so it must stay) holds; the label and the 314 need
correcting.

## Verdict

The nine defects and D10 are genuinely fixed or correctly `NOT REPRODUCED`; every
gate re-derives green on this tree; no test was weakened. **However, the wave's own
doc-correction deliverable contains one flatly false sentence (T07's "called only by
the probe"; HANDOFF's IBL shorthand needs the same clarification), two miscounts
(the "3 FX quads"; "27 meshes / 314 instances"), one stale evidence file
(`runtime_smoke_godot.log` from before the last source edit), and the tree is not
clean.** None of these changes a gate result, and all are text/log fixes (the smoke
log already exists at the named path; I also ran a fresh boot), but the brief's rule
1 ("every claim must be re-derivable") is not met by the IBL sentence and the
thin-box count.

**Required to flip this to PASS:** correct T07 + HANDOFF to "no *texture/reflection*
consumer; `weather_profile.gd:959` already flips the ambient sky contribution";
replace "3 FX quads" with "2 FX quads (3 coplanar convex elements incl. the ward)";
fix or drop "27 meshes / 314 instances" with the element/mesh counts above; commit
the tip-tree `runtime_smoke_godot.log` (or re-run `make runtime-smoke` at the merged
tip); commit or drop the two uncommitted doc edits. No gate needs re-running for
the doc rows; the smoke log needs the 10-minute boot (or the existing 21:44 log,
which I scanned `PASS`).

Scope note: if the project treats doc errata as non-blocking, the code/test verdict
alone is PASS — every defect gate re-derived green, no assertion weakened. I am not
willing to call the *wave* PASS while two sentences it was chartered to correct are
false and the smoke evidence file is from the pre-edit tree. The fix is four text
lines plus one log copy, not a re-run.

AUDIT VERDICT: FAIL
