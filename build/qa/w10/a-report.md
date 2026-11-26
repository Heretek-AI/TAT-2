# W10-A — correctness and evidence (wave report)

Worktree `/home/john/Projects/TAT-2-rem-w10-a`, branch `w10/a`, base `29046c8`,
wave commit **`e2d783a`** (the ratchet stamp is a follow-up commit on top).
**Nothing pushed, merged or rebased.** Lead: W10-A. Nested team: 4 investigation/RE
lanes (INV-1, INV-2, INV-3, RE-1), 3 implementation lanes on disjoint files
(IMPL-A screens, IMPL-B runtime, IMPL-C locks+traversal), 1 evidence lane, and an
independent auditor that is not an author of any fix.

The wave's purpose is stated in `build/qa/w10/W10_BRIEF.md`: nine reported defects, each
with a red proof and a green gate, and the probe/ratchet hardening that stops a claim
living only in prose. Every number below is re-derivable from a committed log or a
`file:line`; nothing is quoted from memory.

## 0. Headline (asked first)

**Collision coverage, per load set** (`docs/reports/logs/w10/probe_collision_authored.log`,
exit 0, `dropped=0` on every map):

| map | files | placed paths | authored | coverage | reduced paths | shapes | bodies | load |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| guildhall | 15 | 947 | 937 | **0.989** | 16 | 30 819 | 243 | 15.0–15.7 s |
| old_manor | 9 | 692 | 687 | **0.993** | 35 | 22 567 | 471 | 19.7–20.0 s |
| ftue | 10 | 548 | 535 | **0.976** | 20 | 37 646 | 180 | 10.2–11.2 s |

`COL_MAPS PASS maps=3 min_coverage=0.976 dropped=0 planar_skipped=2 coverage_ppm=976277`.
Every reduced mesh is named in the log (71 `COL_REDUCED` lines). The static replay
predicted 36 / 20 reduced paths; OldManor measures **35** because D10 exempts the
OldManor tower stair (36 hulls) from the 16-element cap — a deliberate, tested change
(§7). Guildhall dropped 30 901 → 30 819 shapes = exactly the 82 ward-zone hulls now
skipped by D7; OldManor drops the corresponding 78.

**Runtime smoke** (`docs/reports/logs/w10/runtime_smoke.log` + the engine log it names):

```
RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 raw=0 allowed=0 script_errors=0 shader_errors=0 mission_ready=1 reason=ok
RUNTIME_SMOKE PASS
```

A real 90 s free-play boot, **0 `ERROR:` lines**, so the teardown allowlist was not
needed. Before this wave the gate accepted any exit code and never counted `ERROR:`
(§9).

## 1. Evidence ladder

Each item carries the six rungs; the independent audit adds the seventh verdict.

| Rung | Meaning | Where it lives |
|---|---|---|
| **S1** | red proof, verbatim | `build/qa/w10/inv-*.md`, `re-1-locks.md`, the red suite output |
| **S2** | change | `file:line` in this report, `impl-*.md`, `evidence.md` |
| **S3** | green proof | the suite/probe log in `docs/reports/logs/w10/` |
| **S4** | committed gate | the same log is read by `tools/check_gate_ratchet.py` |
| **S5** | doc correction | `docs/FIDELITY_GAPS.md`, `HANDOFF`, `AGENTS.md`, W9 report |
| **S6** | independent audit | `build/qa/w10/audit.md` (`AUDIT: PASS|FAIL` per item) |

## 2. Before / after, the nine defects

| # | Defect | Before (red) | After (green) | Gate |
|---|---|---|---|---|
| 1 | `continue_requested` had no consumer | `INV-1a.2/1a.4/1a.6` FAIL: the press left the screen open and `get_signal_connection_list("continue_requested")` was 0 | screen closes itself; HUD connects the signal and restores focus | suite **112**, `W10_SCREENS_SUMMARY: fails=0 checks=39` |
| 2 | main-menu focus not restored | `INV-1b.4/5/8/9` FAIL: `owner=null` after Settings/Tutorial close | `closed` → `FocusNav.install(_menu_v)` + `restore()`; pad-only owner is back inside the menu | suite 112 |
| 3 | ESC also opened pause behind PostMatch/Progression | `INV-1c.2/1c.6` FAIL: `paused=true` after the screen closed | shared `FocusNav` frame stamp skips the pause poll for exactly that frame; a later press still pauses (`1c.8`) | suite 112 |
| 4 | timeout/collapse rendered "Caught" | `INV-1d.1–1d.3`, `1d.5–1d.7` FAIL: `status='CAUGHT'` | HUD **and** PostMatchUI render `TIME EXPIRED` / `MAGIC DOOR COLLAPSED`; capture/escape rows unchanged | suite 112 |
| 5 | repeated opens stacked layers | `INV-1e.1/1e.2` FAIL: 2 children, 2 visible | HUD owns one rack-up (`remove_child` + `queue_free` before replace) | suite 112 |
| 6 | trace NDJSON unbounded after the ring filled | 9 000 rows → 9 000 file lines while the ring held 8 192 | file budget 8 192 rows / 16 MiB, `file_dropped=808`, one `STATETREE_TRACE capped` line | suite **113**, `W10_RUNTIME_SUMMARY: fails=0 checks=45` |
| 7 | zero-volume authored convex became a collider | ward-zone hull emitted for all 160 instances; a 0.2 m query hit it at 0.00/0.25 m | coplanar convex emits no shape (`planar_convex_skipped`, `COL_PLANAR`); box clamp kept (27 meshes / 314 real thin solids) | suite 113 + collision probe |
| 8 | prison door "pickable on an absent flag" | **NOT REPRODUCED** — the authored resolution is `true` (delta dump; same-class FTUE door writes `false` explicitly) | behaviour unchanged, resolution made explicit + labelled; CDO gate added | suite **114**, `check_lock_cdo.py` |
| 9 | runtime-smoke blind to `ERROR:`/exit code | fixture with 2 `ERROR:` + exit 1 printed PASS; `CODE` never read | exit **124 only**, `SCRIPT/SHADER/ERROR:` minus a documented teardown allowlist, `mission_ready`, log kept | `RUNTIME_SMOKE_SCAN_TEST PASS checks=29`, real boot PASS |
| 10 | two stale traversal tests | `W6M_STAIR_SUMMARY: fails=13`; `W6M_TRAVERSAL_SUMMARY: fails=4` | union fixtures (one shape per authored element) + stair cap exemption; both fail 0 | suites **115/116** |

Note: the brief lists nine defects; D10 ("two stale traversal tests") is the tenth row
because it is two fixtures and it produced a real game fix (the stair exemption).

## 3. Per-item evidence

### 3.1 Continue consumer (D1)

- Red: `FAIL: INV-1a.2 pressing Continue closes the post-match screen | is_open=true`;
  `FAIL: INV-1a.4 the HUD connects continue_requested (connections=0)`.
- Change: `post_match_ui.gd:127-142` (`close()` → `_close(with_cue)`), `:670-679`
  (emit then silent close); `hud.gd:2410-2413` connects `continue_requested` and
  `closed`, `:2421-2443` `_on_post_match_continue` / `_on_post_match_closed` /
  `_restore_result_focus` (with a `_result_xp_btn` fallback for the replaced-screen
  case).
- Green: suite 112, 39/39. The Den transition deliberately stays on the result panel's
  own Continue.

### 3.2 Main-menu focus (D2)

- Red: `FAIL: INV-1b.4 focus is restored after Settings closes (owner=null)` (+ b.5, b.8, b.9).
- Change: `main_menu.gd:53,632` (menu column becomes a member), `:707-718`, `:731-742`
  connect `closed` to `_on_modal_closed` (`:723-725`), the HUD pause-menu pattern.
- Green: suite 112. Pad-only; no named-button grab.

### 3.3 ESC double-handling (D3)

- Red: `FAIL: INV-1c.2 … (paused=true)`, `FAIL: INV-1c.6 … (paused=true)`.
- Change: `focus_nav.gd:33-41,176-183` (static frame stamp, monotonic so no reset),
  `post_match_ui.gd:161-170`, `progression_ui.gd:133-142`,
  `hud.gd:2907-2914` (`elif FocusNav.escape_consumed_this_frame(): pass` next to the
  lockpick `_pause_consumed_frame` branch).
- Why shared: Progression is opened by the Ledger (`ledger_ui.gd:574`), not the HUD, so a
  HUD-side `closed` connection could not cover `1c.6`.
- Green: suite 112 incl. the negative control `1c.8` (a later pause press still pauses).

### 3.4 Timeout / collapse status (D4)

- Red: `FAIL: INV-1d.1 … | status='CAUGHT'` through `1d.7`.
- Change: `hud.gd:2340-2353` and `post_match_ui.gd:328-341` branch on
  `timed_out` + non-empty `timeout_reason` before the authored Escaped/Caught rows.
  The reason is the controller's port constant (`mission_controller.gd:97-98`), carried
  in `info` — no new table key, no new literal.
- Green: suite 112, including `1d.4/1d.8` (capture still `CAUGHT`) and `1d.9` (escape
  still `ESCAPED`).

### 3.5 Layer stacking (D5)

- Red: `FAIL: INV-1e.1 … (2)`, `FAIL: INV-1e.2 … (2)`.
- Change: `hud.gd:343` member, `:2391-2406` release + `remove_child` + `queue_free`
  before the replacement. `PostMatchUI.close()` still does not free itself because
  `test_w9p3_screens.gd` reads `is_open()` after close.
- Green: suite 112.

### 3.6 Trace file budget (D6)

- Red (static and measured): the only early return in `push()` fires when no file is
  configured, so 9 000 pushed rows produced 9 000 NDJSON lines while the ring held
  8 192 (`inv-2-runtime.md`).
- Change: `trace.gd:23-59,113-142` — `MAX_FILE_ROWS = MAX_ROWS = 8192`,
  `MAX_FILE_BYTES = 16 MiB`, `file_rows/file_bytes/file_dropped`, one
  `STATETREE_TRACE capped …` print. `dropped` still means ring drops only.
- Green: suite 113 (9 000 rows → 8 192 lines, `file_dropped=808`,
  `file_bytes == FileAccess.get_length()`; a second sink binds on bytes at 16 MiB).

### 3.7 Coplanar authored convex (D7)

- Red (measured, and the brief's premise corrected): `SM_SlowWardZone_Quad` is a
  **convex** element (2×2 cm, extent 1.2e-18 m), not a clamped box — the box clamp never
  touched it. 160 placed instances (82 Guildhall + 78 OldManor). A 0.2 m shape query on
  the real placement was solid at 0.00/0.25 m and missed from 0.50 m to 41 m: a
  sub-metre invisible obstruction, **not** the "room-sized 2 cm slab" the brief assumed.
- Change: `authored_collision.gd:95-113,312-345` — a convex element whose baked point
  AABB has a minimum extent `< 1e-4 m` emits no shape; `planar_convex_skipped`,
  `planar_skipped_paths`, `COL_PLANAR`. Boxes keep `MIN_HALF_EXTENT_M` (2 cm) and are
  counted as `box_clamped`; that clamp is *measured* as legitimate (27 meshes /
  314 instances: glass, rugs, `/Engine/BasicShapes/Plane`).
- Why safe: the ward zone's collider is built by the device layer from `zone_size_m`
  (`ward_zone.gd:113-137`), so dropping the quad hull changes no ward behaviour.
- Green: suite 113 (ward zone 0 shapes at 1 and 160 instances; FX quads 0; `Plane` still
  one clamped box; `SM_OldManor_Doorway_4x650` unchanged at 14 shapes / reduced at 37;
  grounding ray reaches the floor, with the pre-fix hull as a synthetic control).
  Probe: `COL_MAP_ASSERT … PASS` on all three maps.

### 3.8 Prison door / `CanBeLockpicked` (D8) — **NOT REPRODUCED**

The RE lane (`build/qa/w10/re-1-locks.md`) proves the port is faithful:

1. The dump is a **delta** against the archetype (`Template` names it on every object);
   all six CDOs that author `_locked` are self-consistent deltas (6/6).
2. `BP_SwingingDoor` → `BP_SwingingDoor_DoubleBase` → `BP_Prison_WallA_DoorwayB2_6x6`
   author no `CanBeLockpicked`; the native `TATSwingingDoor` initialiser is not dumped.
3. A door on the **same** native class — `BP_Res_Int_Doorway_C`, FTUE spawn area object
   #53 — writes `CanBeLockpicked: false` **explicitly**; a delta dump would have dropped
   that write if the inherited value were `false`. Therefore the absent value resolves
   **`true`**.
4. `StaticMeshActor_528` is the only key-tagged actor in the POI with **no
   `KeyItemInfo`**: "key-only" would leave the cell unopenable.

So the fix is not a behaviour flip: `swinging_door.gd:38-51` states
`AUTHORED_CAN_BE_LOCKPICKED_DEFAULT = true` once (with the citation chain) and branches
on it (`:163-175`); the exclusion label became `unpickable` (`key_only` was a mislabel —
26 of the 33 explicit-false actors carry no `KeyTag`), with `key_only_exclusions()` kept
as an alias so `test_w9p2_locks.gd` passes unchanged (`LOCKS PASS checks=28`).

Gate: `build/qa/w10/check_lock_cdo.py` (dump-only, fail-closed):

```
LOCK_CDO PASS classes=31 explicit_false=34 one_false_class=BP_SlidingWindow_Base_C placed_false=33/33
```

It asserts exactly one class resolves `false` (`BP_SlidingWindow_Base_C`, zero
placements), 33/33 placed `false` are explicit, and the prison actor is
`locked: true` + `KeyTag` + no `CanBeLockpicked`.

**Adjacent defect found, not fixed here:** the authored `MaxLockLevel` for the prison
door resolves to **4** (inherited from `BP_SwingingDoor_C`), but the producer emits
instance deltas only, so the record has no cap and the port locks at **1**. Fixing it
needs a producer chain resolution + regeneration at merged HEAD (integrator) and is a
deliberate difficulty change — recorded in `FIDELITY_GAPS.md`, pinned (not fixed) by
suite 114.

### 3.9 runtime-smoke (D9)

- Red: a fixture with 2 `ERROR:` lines **and exit 1** printed `RUNTIME_SMOKE PASS`; the
  old script read `CODE` and never used it, and deleted its log on PASS
  (`inv-2-runtime.md`; `PRE_FIX_BLIND_SPOT` lines in the self-test).
- Change: `build/qa/runtime_smoke_scan.sh` (decision), `runtime_smoke.sh` (runner keeps
  the log and delegates), embedded documented allowlist (teardown only), 29-case
  self-test.
- Green: `RUNTIME_SMOKE_SCAN_TEST PASS checks=29 fails=0`; real boot
  `exit=124 … errors=0 … mission_ready=1 reason=ok`.

### 3.10 Traversal fixtures (D10)

- Red: `W6M_STAIR_SUMMARY: fails=13` (six flights aborted with "no trimesh collider"
  because they are authored as one convex hull; the tower flight walked a coalesced
  trimesh that blocked it) and `W6M_TRAVERSAL_SUMMARY: fails=4` (every roof module
  3–4 hulls, tested as `shapes[0]`).
- Change: both fixtures build one `CollisionShape3D` per authored element at its own
  offset (the `test_roof_collision.gd` pattern) and pin the authored element count
  (`_check_union_count`), so "one hull of many" cannot return. One expectation was
  re-based with written evidence (the non-uniform pitch assertion measured a face the
  metric never reports; `impl-c.md` §2c). The tower exposed a **game** defect: 36 hulls
  > the 16-element cap coalesced to an AABB trimesh with no treads; stair meshes are now
  exempt from that cap (`authored_collision.gd:370-379`) and emit per element.
- Green: `W6M_STAIR_SUMMARY: fails=0`, `W6M_TRAVERSAL_SUMMARY: fails=0`, both now
  suites **115/116** in `make test`.

## 4. Evidence hardening

| Item | Before | After |
|---|---|---|
| collision probe | Guildhall only, 937/947, no reduced names, 85 % floor | 3 load sets, per-map ≥ 0.95 + `dropped==0` gate, every reduced path named, `COL_MAPS` summary |
| lock probe | printed raw `applied=363`, never failed | de-duplicated runtime `applied=154` (144 containers + 10 door nodes, 209 discarded), fails at 0 |
| string audit | measurement only, always exit 0 | `make string-audit`, floors 306/195/111, in `make audit` |
| suite 110 | relational assertions only | absolute 77/326/113/94 and 36/233/35/32, 0/21 fully evaluable (`checks=86`) |
| literal greps | none | `tools/check_literal_greps.py`: 0 live `maxi(100` / lock formulas, 0 invented rating literals in `game/src/ui` |
| runtime-smoke | blind to `ERROR:`/exit | described in §3.9 |
| ratchet | 8 numeric + 5 probe gates | + `probe_collision`, `probe_collision_maps`, `lock_inventory`, `string_audit`, `literal_greps`, `runtime_smoke` |

Raw logs (committed, ratchet-readable) in `docs/reports/logs/w10/`:
`compile`, `run_tests`, `m2`, `e2e`, `audit`, `texture_cap`, `perf_guard`, `probe_leak`,
the five probes, `probe_collision_authored`, `probe_lock_inventory`, `string_audit`,
`literal_greps`, `statetree_suite110`, `runtime_smoke` (+ the engine log it names).

## 5. Doc corrections applied

- `docs/reports/w9-remediation-20261125.md`: locks 363 → **154 runtime (144+10)**;
  collision "every mesh" → per-map measured coverage.
- `docs/FIDELITY_GAPS.md`: W10-A status section (closed / NOT REPRODUCED / open);
  collision and lock lines corrected; localization row corrected.
- `docs/HANDOFF_NEXT_AGENT.md`: collision and `Loc.t()` claims corrected.
- `AGENTS.md`: locks 363 → 154 runtime; gate table/gates updated for the wave.
- `build/qa/w9/p3-report.md`: the `SHADOW` sentence now says the **rating word** is gone
  and 96 identifiers still contain the token (none a rating).
- `docs/reports/remediation-20261125/T07-render.md`: the IBL note no longer claims "no
  further code change is needed" — `sky_ibl_state()` is only called by the probe; a
  runtime consumer (PanoramaSkyMaterial / ambient source) is still required.
- `build/mobile_game` (stale untracked copy with `maxi(100, score/2)`): present only in
  the main checkout and git-ignored; deleting it is an integrator step (§7) because this
  worktree must not write there.

Two brief figures were re-measured rather than copied:

- "97.9 % emitted-AggGeom" is **not reproducible** at this tip; the probe measures
  98.9 / 99.3 / 97.6 % per load set, and the "not every mesh" correction is stated with
  those numbers plus the 10 heuristic paths / 14 `complex_as_simple` / 233-of-1,667
  missing records.
- "routing is `UIStrings` (99/76/127)" — at this tip the audit reports
  `st_text=83 st_upper=75 loc=125` (`UI_STRINGS total=306`). The *direction* of the
  correction holds (`Loc.t(` occurs once, in `localization.gd:11`; routing is
  `UIStrings`), the exact triple was not reproducible and is not used.

## 6. Full gate set (W10-A tip)

Every log below is committed under `docs/reports/logs/w10/` and is the run on this tree
(the 13 unchanged-gate logs were copied placeholders while the evidence lane worked and
were **overwritten** by this run).

| Gate | Result | Log |
|---|---|---|
| compile | **189 checked, 0 broken** | `compile.log` |
| `make test` | **`SUMMARY: fails=0`, 319 PASS, suites to 116** (222 s) | `run_tests.log` |
| M2 | **`M2_SUMMARY: fails=0`, 12 PASS** | `m2.log` |
| E2E | **`fails=0 passed=278 total=278`** (302 s) | `e2e.log` |
| collision probe (3 maps) | **`COL_MAPS PASS maps=3 min_coverage=0.976 dropped=0`** | `probe_collision_authored.log` |
| lock inventory | **`applied=154 containers=144 door_nodes=10 discarded=209`** | `probe_lock_inventory.log` |
| string audit | **`GATE PASS routed=306 authored=195 invented=111`** | `string_audit.log` |
| literal greps | **`PASS code_hits=0 ui_rating_literals=0 files=96`** | `literal_greps.log` |
| suite 110 (StateTree) | **77/326/113/94 · 36/233/35/32 · 0/21, `checks=86`** | `statetree_suite110.log` |
| door walk / viewmodel / Niagara / blackjack / geometry | **PASS / PASS / PASS / PASS / PASS** | the five probe logs |
| probe leak (`TAT2_NO_DEN_PROBE=1`) | clean (`PROBE start`, 0 leak/script markers) | `probe_leak.log` |
| `make audit` | **`AUDIT PASS`, baseline matches** (12,660/12,703) | `audit.log` |
| texture cap | **797 capped / 1 alpha-critical / 0 offenders** | `texture_cap.log` |
| perf guard | **`PERF_GUARD_TEST PASS checks=78 fails=0`** | `perf_guard.log` |
| `make runtime-smoke` | **`PASS exit=124 errors=0 raw=0 allowed=0 mission_ready=1`** | `runtime_smoke.log` + `runtime_smoke_godot.log` |
| `make gate-ratchet` | **`GATE_RATCHET: PASS`** (all 14 gate families incl. the 6 new) | `gate_ratchet.log` |

New suites inside `make test`: **112** screens (39 checks), **113** runtime (45),
**114** locks (25), **115** stairs, **116** traversal.

`make audit` needed a one-time baseline refresh because the wave adds two pure-Python
prerequisites to `audit:` (`string-audit`, `check-greps`): `tools/audit_baseline.json`
now records the new `root:Makefile` sha256 with the mandatory reason, and no
producer/generated output changed (`AUDIT PASS`, "baseline matches"). The extractor
binary/usmap were copied into this worktree from the main checkout only so the local
audit could pin provenance; they are git-ignored and not part of the commit.

## 7. Integrator steps

1. **Re-stamp the ratchet at the merged tip.** `tools/gate_ratchet.json` and
   `docs/reports/w10-gate-ratchet.md` carry `measured_on: e2d783a` (this wave's commit).
   After cherry-picking `w10/a`, set both to the merged tip, then `make gate-ratchet` and
   commit the refreshed `docs/reports/logs/w10/gate_ratchet.log`. No gate value needs to
   move: the wave raised `compile` 186 → 189 and `run_tests` 314 → 319 and added the six
   new families (collision maps, lock inventory, string audit, literal greps,
   runtime-smoke, collision marker).
2. **Regenerate nothing for this wave.** `game/data/generated/` was read-only; the
   collision/lock/string gates read the current payload. The only data change belongs to
   the open prison-door cap item: `tools/parse_tables.py` chain-resolving
   `_lockConfig.MaxLockLevel` needs a producer patch + `make normalize` at merged HEAD,
   and it changes the cell door from LV1 to LV4 — a deliberate call.
3. **Delete the stale mobile copy** in the main checkout: `rm -rf build/mobile_game`
   (git-ignored, still holds the old `maxi(100, score/2)` XP formula; this worktree never
   wrote to the main checkout).
4. **Commit the ignored evidence files with `-f`:** `build/qa/w10/*.md`
   (`inv-1-screens`, `inv-2-runtime`, `inv-3-evidence`, `re-1-locks`, `impl-a/b/c`,
   `evidence`, `audit`, `a-report`) and `build/qa/w10/check_lock_cdo.py` are under
   `build/qa/*`, which `.gitignore` excludes except `*.gd/.sh/.py`. The committed logs
   under `docs/reports/logs/w10/` are not ignored.
5. **Placeholder logs.** The 13 unchanged-gate logs in `docs/reports/logs/w10/` were
   copied from `docs/reports/logs/w9/` by the evidence lane so the ratchet chart could be
   checked before the full run; `§6` replaces them with this wave's runs. Confirm each
   one names this wave's compile count / suite count before pushing.
6. **Re-run on the merged tree** (the cherry-pick can move line numbers): compile,
   `make test`, M2, E2E, the probes, `make audit`, texture cap, perf guard,
   `make runtime-smoke`, `make gate-ratchet` — the same list as §6.

## 8. What the wave did not do

- **No push/merge/rebase.** No producer, `make normalize`, or data regeneration.
- **No GPU capture**; no Vulkan work in this wave, so the perf matrix stays unrun and the
  thermal caveat in `AGENTS.md` stands.
- The prison-door lock **level** (1 vs authored 4) is recorded, not fixed (§3.8).
- Collision coverage is **per map**; 233 of 1,667 placed paths repo-wide still have no
  record and keep the heuristic (mostly `/Game/Test/` graybox, `/Engine/`, third-party).
