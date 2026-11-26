# W10-A evidence (EVIDENCE lane)

| | |
|---|---|
| worktree | `/home/john/Projects/TAT-2-rem-w10-a` (branch `rem/w10-a`; the brief calls it `w10/a`) |
| HEAD | `29046c8` (W9 tip; nothing committed by this lane) |
| date | 2026-11-25 |
| engine | `tools/godot` 4.7.2 headless; **every** run `flock /tmp/opencode/tat2-godot.lock -c "timeout 900 tools/godot --headless --path game --script <res://…>"`, one at a time |
| data | `extracted`, `game/assets`, `game/data/generated` are the shared read-only symlinks |
| wrote to | this worktree only; nothing in `/home/john/Projects/TAT-2` was modified |

Logs referenced here are the raw command outputs committed under
`docs/reports/logs/w10/` (plus `statetree_suite110.log` for suite 110). No line
in any log was hand-edited.

> `build/qa/w10/evidence.md` itself is **not committable without `git add -f`**:
> `.gitignore` ignores `build/qa/*` except `*.gd/*.sh/*.py` (same as the other
> W9/W10 lane reports). The gate scripts and logs below are tracked.

---

## 1. Collision probe covers Guildhall + OldManor + FTUE, names every reduced mesh, fails per map

Command (raw log `docs/reports/logs/w10/probe_collision_authored.log`, exit 0):

```bash
flock /tmp/opencode/tat2-godot.lock -c 'timeout 900 tools/godot --headless --path game --script res://tests/probe_collision_authored.gd'
```

Files changed: `game/tests/probe_collision_authored.gd` (three explicit map
sets, fresh host + fresh loader + fresh 45 s deadline per map, `COL_MAP`,
`COL_REDUCED`, `COL_MAP_ASSERT`, `COL_MAPS`); `game/src/core/level_loader.gd`
**counters/report only** (`col_reduced_names` in the load-result dict, and
`col_planar_skipped` / `col_planar_paths` as per-load deltas of
`AuthoredCollision.stats()` snapshotted in `_new_build_ctx`). No collision
decision changed.

Verbatim decisive lines:

```
COL_AUDIT mode=authored placed_meshes=947 placed_meshes_seen=947 placed_instances=27222 authored_hull=937 authored_prims=599 absent=10 no_collision=7 query_only=7 reduced=16 shapes=30819 bodies=243 dropped=0 load_ms=14986 coverage=0.989 fps_pose=n/a
COL_DETAIL payload_meshes=1992 payload_elements=8601 payload_convex=5922 payload_load_ms=236 authored_instances=24404 authored_shape_demand=27685 heuristic_shapes=3511 mode_requested=authored elements_on_placed=2184 convex_on_placed=899 complex_default_paths=70 placed_paths_payload=947 scale_baked_shapes=3926
COL_ASSERT coverage=0.989 (937/947) prims_subset=true classification=937+10==947 mode=authored dropped=0
COL_MAP map=guildhall files=15 placed_meshes=947 placed_instances=27222 authored=937 absent=10 coverage=0.989 reduced=16 planar_skipped=1 drops=0 shapes=30819 bodies=243 load_ms=14986
COL_MAP map=old_manor files=9 placed_meshes=692 placed_instances=20210 authored=687 absent=5 coverage=0.993 reduced=35 planar_skipped=1 drops=0 shapes=22567 bodies=471 load_ms=19999
COL_MAP map=ftue files=10 placed_meshes=548 placed_instances=34673 authored=535 absent=13 coverage=0.976 reduced=20 planar_skipped=0 drops=0 shapes=37646 bodies=180 load_ms=11196
COL_MAP_ASSERT map=guildhall coverage>=0.950 dropped==0 coverage=0.989 dropped=0 PASS
COL_MAP_ASSERT map=old_manor coverage>=0.950 dropped==0 coverage=0.993 dropped=0 PASS
COL_MAP_ASSERT map=ftue coverage>=0.950 dropped==0 coverage=0.976 dropped=0 PASS
COL_MAPS PASS maps=3 min_coverage=0.976 dropped=0 planar_skipped=2 coverage_ppm=976277
COL_WALL total_ms=46711 (whole probe: three map loads)
```

Every reduced path is named: 16 `COL_REDUCED` lines for Guildhall, 35 for
OldManor, 20 for FTUE. Per-map counts and the full lists are grep-able:

```bash
grep -c '^COL_REDUCED map=old_manor' docs/reports/logs/w10/probe_collision_authored.log   # 35
```

### Measured vs predicted reduced meshes

| map | files | static prediction (`inv-3-evidence.md` §2b) | D10-adjusted prediction | **measured** | reduced instances (pred / measured) |
|---|---:|---:|---:|---:|---|
| Guildhall | 15 | 16 | 16 | **16** | 962 / 962 |
| OldManor | 9 | 36 | **35** | **35** | 297 / 296 |
| FTUE | 10 | 20 | 20 | **20** | 1 788 / 1 773 |

* **Guildhall 16 / 962 instances is an exact match** to the static replay, so the
  replay model is validated on the one set the W9 baseline already measured.
* **OldManor 35 = 36 − 1**: the brief's predictions named
  `SM_OldManor_Tower_Stairs_4x850` (36 elements) as reduced; the D10 stair
  exemption (`authored_collision.gd:370-379`) keeps it per-element, so it is the
  only predicted path that does not reduce. `grep -c Tower_Stairs_4x850` on the
  log is 0 and the measured instance total is 297 − 1 = 296.
  The two paths the brief singled out are measured exactly:
  `/Game/Art/Environment/OldManor/SM_OldManor_Doorway_4x650 elements=14 instances=37`
  and `…/Combo_Pieces/SM_OldManor_Tower_VaultRoom elements=112 instances=1`.
* **FTUE 20 = 20** including
  `/Game/Art/Environment/Urban/Walls/SM_Urban_Ext_BayWindow_Open_6x6_4m elements=22 instances=2`.
  The 15-instance delta (1 773 vs 1 788) is the static model's documented
  residual on multi-instance paths: `SM_Manor_Bookcase_Cabinet_2x8` 12→6 and
  `SM_Books_BookshelfA` 6→3 (shared sublevels / exact-duplicate dedupe) and four
  roof paths each −2 (`Mid_4x4` 193→191, `MidWindowA` 172→170, `Mid_1x4` 162→160,
  `RoofUrban_Ext_MidWindowA`), i.e. the loader's per-instance CPD/colour skip and
  exact-transform dedupe, not a reduction-rule difference. The reduced **path
  set** is identical to the prediction.
* Planar skips: 2 total (Guildhall ward quad 1, OldManor ward quad 1); FTUE 0.
  `COL_PLANAR_LOAD` names each path per map. The D7 rule is visible in the shape
  count: Guildhall `shapes` 30 901 (W9) → **30 819** (−82 = the 82 Guildhall ward
  placements), with `reduced` still 16 and coverage unchanged at 0.989.

**Delta found and fixed in the probe (not in the game):** the first run reused
one `level_loader` instance across the three maps and measured **OldManor 37 /
FTUE 16**. Cause: the loader's per-instance mesh cache (`_mesh_res_cache`)
stores ONE `info` dict per UE path whose `reduced` flag was computed from that
map's placement count; reusing it across maps reported meshes reduced by
*Guildhall's* counts (`SM_Manor_Bookcase_2x8` 16 el @ 45, `SM_ExhaustChimney`
4 el @ 101, `SM_CrossBeam_SupportWall` 4 el @ 106) and hid FTUE's high-instance
roofs reduced only in FTUE. A production process loads one mission, so the probe
now creates a **fresh loader per map** (plus fresh host + deadline). The numbers
above are from that final, production-faithful run. No loader logic changed for
this: `AuthoredCollision.resolve` is already keyed by `(path, instances)`.

FTUE note: the log carries the expected
`WARNING: [level_loader] FTUE collider budget raised to 40000 building / 44000 total`
line (the authored city demand exceeds the default cap). With the correct
20-mesh reduction set FTUE emits 37 646 shapes and **drops 0**; the earlier
shared-loader run reduced only 16 meshes, emitted over 40 000 and dropped 1 032,
which is what the per-map gate caught.

---

## 2. Lock probe prints the de-duplicated runtime count and fails at zero

Command (raw log `docs/reports/logs/w10/probe_lock_inventory.log`, exit 0):

```bash
flock /tmp/opencode/tat2-godot.lock -c 'timeout 900 tools/godot --headless --path game --script res://tests/probe_lock_inventory.gd'
```

File changed: `game/tests/probe_lock_inventory.gd`. `LOOT_CONTAINER_CLASSES` is
read from `level_loader.gd` via `get_script_constant_map()` (no duplicate list);
containers = locked **markers** in that list, de-duplicated by `(class, rounded
pos)`; door nodes = locked `swinging_doors` records without "Window" in the class
and without an explicit `can_lockpick: false`; the raw 363 stays its own number.
`applied == 0`, `containers == 0` or `door_nodes == 0` fails (exit 1).

Verbatim decisive lines:

```
  ok: LOOT_CONTAINER_CLASSES read from level_loader.gd (5 classes)
  runtime level records (markers+actors+swinging_doors): 17744
  runtime records carrying an authored lock: 363 (raw: markers=161 actors=174 doors=28)
  runtime applied containers: 144 de-duplicated by (class,pos) from 144 locked container markers
  runtime applied door nodes: 10 (windows and explicit can_lockpick=false excluded)
LOCK_INVENTORY runtime: authored=173 raw=363 applied=154 containers=144 door_nodes=10 discarded=209 state=APPLIED
  ok: runtime applies at least one authored lock (applied=154)
  ok: runtime applies container locks (containers=144)
  ok: runtime applies door-node locks (door_nodes=10)
  ok: applied = containers + door_nodes (154 = 144 + 10)
LOCK_INVENTORY PASS authored_containers=157 authored_doors=8 authored_windows=8 locked_now=363 applied=154 containers=144 door_nodes=10
```

Measured vs the brief: **containers 144 / door_nodes 10 / applied 154 / raw 363
/ discarded 209 — exactly the predicted numbers** (`inv-3-evidence.md` §3b). Every
pre-existing authored-dump assertion still passes (`total 173`, containers 157,
doors 8, windows 8, caps 155/3, no-cap 15).

---

## 3. String audit is a gate

Command (raw log `docs/reports/logs/w10/string_audit.log`, exit 0):

```bash
python3 build/qa/w9/p3_string_audit.py --min-routed 306 --min-authored 195 --max-invented 111
```

`build/qa/w9/p3_string_audit.py` gained `--min-routed/--min-authored/--max-invented`
(default `None` = the old measurement, still exit 0) and prints
`UI_STRINGS GATE FAIL …` + exit 1 on a missed floor. The `string-audit` Makefile
target pins the measured floors and is a prerequisite of `audit:`.

Verbatim lines:

```
UI_STRINGS total=306 routed=306 authored=195 routed_authored=195 invented=111
UI_STRINGS GATE PASS routed=306 authored=195 invented=111
COVERAGE routed/total=1.0000
COVERAGE authored_routed/authored=1.0000
```

Negative control (not committed): `--min-routed 9999` printed
`UI_STRINGS GATE FAIL routed=306 < min-routed=9999 (…)` and exited 1.

---

## 4. Suite 110 asserts the coverage ceiling (additive)

Command (raw log `docs/reports/logs/w10/statetree_suite110.log`, exit 0):

```bash
flock /tmp/opencode/tat2-godot.lock -c 'timeout 900 tools/godot --headless --path game --script res://tests/test_w9p4_statetree.gd'
```

File changed: `game/tests/test_w9p4_statetree.gd` — `_check_coverage` gained 9
absolute assertions after the existing relational ones (nothing replaced or
weakened): `task_classes == 77`, `task_instances == 326`, `task_covered == 113`,
`task_blind == 94`, `condition_classes == 36`, `condition_instances == 233`,
`condition_covered == 35`, `condition_blind == 32`, and
`fully.size() == 0 and coverage.per_tree.size() == 21`.

Verbatim lines:

```
STATETREE_COVERAGE trees=21 task_classes=77 task_instances=326 task_covered=113 task_blind=94 condition_classes=36 condition_instances=233 condition_covered=35 condition_blind=32 implemented=0 mapped=24 unsupported=89
P4COVERAGE fully_covered_trees=0 names=[]
W9P4_STATETREE_SUMMARY: fails=0 checks=86
```

`checks` moved 77 → **86** because the nine absolute assertions are new
`_ok()` calls; `fails=0`. The old coincidence "checks=77 = task_classes" is gone
by design.

---

## 5. Literal greps are gated

Command (raw log `docs/reports/logs/w10/literal_greps.log`, exit 0):

```bash
python3 tools/check_literal_greps.py
```

New `tools/check_literal_greps.py` (stdlib only, exit 0/1):

* **code-only** over `game/src/**/*.gd`: string literals and `#` comments are
  stripped, then 0 hits of `maxi(100`, `count % 12`, `3 + count % 2`. The
  explanatory comments in `save_system.gd:1127` and
  `mission_controller.gd:4201-4202` stay legal.
* **string literals only** over `game/src/ui/**`: 0 hits of `GHOST`, `BRAWLER`,
  `CONSTABULARY`. The removal comment at `hud.gd:2108` cannot trip it; a real
  rating label would.

Verbatim line:

```
LITERAL_GREPS PASS code_hits=0 ui_rating_literals=0 files=96
```

Negative controls (synthetic, exercised through the module, not committed):
`var x = maxi(100, score / 2)` → code hit; `## W9 replaces \`maxi(100, …)\`` →
no hit; `"GHOST"` / `'BRAWLER'` / `"CONSTABULARY"` → literal hit; a `##` comment
containing them → no hit; `3 + count % 2` → code hit.

---

## 6. Runtime-smoke evidence

Command (ONE run; raw output `docs/reports/logs/w10/runtime_smoke.log`, exit 0):

```bash
build/qa/runtime_smoke.sh 90
```

The script keeps its engine log and prints `log: <path>`. The committed
`runtime_smoke.log` is the smoke command's own output (it carries the decision
line the ratchet reads); the engine log it names is copied verbatim to
`docs/reports/logs/w10/runtime_smoke_godot.log`.

Verbatim lines:

```
log: /tmp/tat2-smoke-lWbIon.log
RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 raw=0 allowed=0 script_errors=0 shader_errors=0 mission_ready=1 reason=ok path=/tmp/tat2-smoke-lWbIon.log
RUNTIME_SMOKE PASS
```

`allowed=0`: **no allowlist entry was needed** for this run. The engine log has
0 `SCRIPT ERROR`, 0 `SHADER ERROR` and 0 `ERROR:` lines (it does carry the
expected `Mission.Example.*` fallback warning). The smoke scripts were not edited
by this lane (IMPL-B owns them).

---

## 7. Ratchet wiring

`make gate-ratchet` output (tail; exit 0):

```
PASS: probe_collision_authored.log records probe_collision.coverage_ppm=976277 >= 950000
PASS: probe_lock_inventory.log records lock_inventory.applied=154 >= 154
PASS: string_audit.log records string_audit.routed=306 >= 306
PASS: literal_greps.log records LITERAL_GREPS PASS
PASS: runtime_smoke.log records runtime_smoke.mission_ready=1 >= 1
PASS: report records compile ('compile\\s*\\|\\s*186\\s*/\\s*0')
PASS: report names measured_on=29046c8

GATE_RATCHET: PASS (baseline and committed evidence agree; Godot gates run locally)
```

* `evidence.dir` = `docs/reports/logs/w10`; every gate has an `evidence.<gate>`
  filename (13 existing gates, 5 W9 probes, and the six W10-A entries).
* `measured_on` is `29046c8` **as a placeholder**: the lead re-stamps it with the
  W10-A wave commit. `docs/reports/w10-gate-ratchet.md` already contains the
  literal floor lines the checker reads (`compile | 186 / 0`, `run_tests | 314`,
  `M2 | 12`, `E2E | 278 / 278`, `12660 / 12703`, `measured_on 29046c8`).
* The 13 unchanged-gate logs in `docs/reports/logs/w10/` are **copies of
  `docs/reports/logs/w9/` as placeholders only**; the lead must overwrite every
  one with this wave's run before pushing.

### Logs the lead must produce in the full W10-A run

| ratchet key | log file | command |
|---|---|---|
| `compile` | `compile.log` | `tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"` |
| `run_tests` | `run_tests.log` | `make test` |
| `m2` | `m2.log` | `tools/godot --headless --path game --script res://tests/test_m2_player.gd` |
| `e2e` | `e2e.log` | `tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=s2` (full set) |
| `audit` | `audit.log` | `make audit` (now includes `string-audit` + `check-greps`) |
| `texture_cap` | `texture_cap.log` | `make texture-cap-check` |
| `perf_guard` | `perf_guard.log` | `build/qa/test_perf_guard.sh` |
| `probe_leak` | `probe_leak.log` | `TAT2_NO_DEN_PROBE=1 tools/godot … res://probe_leak.gd` |
| `probe_door_walk` | `probe_door_walk.log` | `tools/godot … res://tests/probe_door_walk.gd` |
| `probe_viewmodel_truth` | `probe_viewmodel_truth.log` | `tools/godot … res://tests/probe_viewmodel_truth.gd` |
| `probe_niagara` | `probe_niagara.log` | `tools/godot … res://tests/probe_niagara.gd` |
| `probe_blackjack_race` | `probe_blackjack_race.log` | `tools/godot … res://tests/probe_blackjack_race.gd` |
| `probe_geometry_placement` | `probe_geometry_placement.log` | `tools/godot … res://tests/probe_geometry_placement.gd` |
| `probe_collision`, `probe_collision_maps` | `probe_collision_authored.log` | `tools/godot … res://tests/probe_collision_authored.gd` (**done this lane**) |
| `lock_inventory` | `probe_lock_inventory.log` | `tools/godot … res://tests/probe_lock_inventory.gd` (**done this lane**) |
| `string_audit` | `string_audit.log` | `make string-audit` (**done this lane**) |
| `literal_greps` | `literal_greps.log` | `make check-greps` (**done this lane**) |
| `runtime_smoke` | `runtime_smoke.log` | `build/qa/runtime_smoke.sh 90` (**done this lane**) |

The lead must also re-run the wave's own suites (screen/runtime/locks/stairs/
roofs) and, if any count rises above the W9 floors, raise the corresponding
`tools/gate_ratchet.json` value **and** the matching line in
`docs/reports/w10-gate-ratchet.md`, then re-stamp `measured_on`.

---

## 8. NOT MEASURED

| item | status | reason |
|---|---|---|
| `probe_collision_authored.gd` in `TAT2_COLLISION=aabb` mode | NOT MEASURED | the wave gate is authored mode; `build/qa/w9_collision_ab.sh` is a W9 diagnostic, not a ratchet gate |
| full gate set (`run_tests`, E2E, M2, probes, audit, texture cap, perf guard) | NOT MEASURED by this lane by design | the lead runs it serially; the w10 logs for those keys are W9 placeholders |
| `make audit` end-to-end | NOT MEASURED | it needs the full tree/private extract and is the lead's run; `string-audit` and `check-greps` were each run directly and are wired into `audit:` |
| wireframes/screenshots | NOT MEASURED | no rendering was performed; the host must not run parallel GPU jobs |
