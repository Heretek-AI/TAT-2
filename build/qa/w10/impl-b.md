# W10-A · IMPL-B — D6 trace file budget · D7 coplanar convex skip · D9 runtime-smoke scan gate

Branch `w10/a`, worktree `/home/john/Projects/TAT-2-rem-w10-a`. **No Godot was
launched by this lane** (the last engine run in the worktree, a 90 s
`--qa-free-play`, was polled to completion before the first edit; every gate
below that needs an engine is marked *not verified*). No other worktree was
written, nothing was committed, checked out, reset or stashed.

Files changed:

| File | Defect | Lines |
|---|---|---|
| `game/src/ai/statetree/trace.gd` | D6 | 23–29, 32–59, 79–95, 103–108, 113–142, 163–170 |
| `game/src/core/collision/authored_collision.gd` | D7 | 48–52, 88–117, 122–131, 213–229, 232–238, 268–276, 312–381, 451–472, 644–657 |
| `game/tests/test_w10_runtime.gd` | D6/D7 proof | 34–56, 103–122, 143–150, 181–259, 478–677 |
| `build/qa/runtime_smoke.sh` | D9 | 1–48 (the decision moved out) |
| `build/qa/runtime_smoke_scan.sh` (new) | D9 | 1–120 |
| `build/qa/runtime_smoke_allowlist.txt` (new) | D9 | 1–35 (documented copy; `.gitignore`d) |
| `build/qa/test_runtime_smoke_scan.sh` (new) | D9 self-test | 1–167 |

Note on concurrency: two D9 artifacts were being edited by another agent at the
same time as me.

* `build/qa/test_runtime_smoke_scan.sh` came back **much richer than the version
  I wrote** (a `pre_fix` decider replaying `runtime_smoke.sh:26-45` at
  `29046c8`, asserting the old gate stays blind to all five new failures, plus
  the machine-line and usage contracts). I kept it and added the required
  `RUNTIME_SMOKE_SCAN_TEST PASS checks=N fails=0` summary, a per-case `PASS`
  echo, and the missing `clean log + exit 1` case → 29 checks.
* `build/qa/runtime_smoke_scan.sh` was rewritten by the same hand to **embed the
  allowlist defaults** (necessary: `.gitignore:25` keeps only `*.gd/*.sh/*.py`
  under `build/qa/`, so the `.txt` is uncommittable). I kept that and added the
  missing `Parameter "fd" is null` default. The `.txt` remains the documented
  record + optional local extension.
* The grounding control's basis in `test_w10_runtime.gd` was corrected by that
  agent from my 90° X rotation to an identity basis. They were right — the
  decoded hull is flat in mesh **Y** — and I re-derived it from the payload
  (`Y extent 1.225e-18 m`) before keeping it.

If a second lane owns those two files, this is the merge point: keep both
intents. Nothing else in this lane's diff overlaps theirs.

---

## D6 — StateTree trace file budget

### What was wrong

`push()` returned early when the ring was full **only when no file was
configured** (`trace.gd:86-87` at HEAD): with `TAT2_STATETREE_TRACE` set it kept
`store_line`-ing every row for the whole mission. `dropped` described the ring
only, so the artefact that a long mission leaves behind grew without bound and
nothing said so.

### Constants and why

| Constant | Value | Why |
|---|---|---|
| `MAX_ROWS` | 8192 | unchanged (ring) |
| `MAX_FILE_ROWS` | `= MAX_ROWS` → 8192 | The file budget **is** the ring budget. The NDJSON artefact then holds exactly the rows the ring retains, so one number describes retention for both, and it is identical to the ring's documented contract ("the first 8192 rows are the part that explains the branch choice"). It also keeps the pre-existing D6 assertion `lines <= TRACE_MAX_ROWS` (`test_w10_runtime.gd:172`) literally true with **no edit** — see "decision for the lead" below. |
| `MAX_FILE_BYTES` | 16 MiB (`16 * 1024 * 1024`) | Independent hard stop for pathological rows. A `transition_unmet` row carries every candidate's unmet conditions; 8192 rows at the measured ~0.4 KB is ~3.3 MB, but a churn-heavy run can be far wider. 16 MiB / 8192 ≈ 2 KiB per row, so this is a real second bound, not decoration. |

Measured basis for "8192 does not truncate a real mission": a real 60 s
free-play boot in shadow mode with 4 guards wrote **209 rows**
(`build/qa/w9/p4-report.md` §trace), and rows are emitted per **event**, never
per tick (`every_tick` is test-only) — so a guard idling in `Move To` writes
nothing.

**Decision for the lead.** The prompt suggested 32768 rows. 32768 cannot be
chosen without relaxing `_check(lines <= TRACE_MAX_ROWS)` (8192) in the existing
red proof — a 9000-row push would then write 9000 lines. I chose not to weaken
that assertion. If 32768 headroom is wanted, raise `MAX_ROWS` (ring + file move
together) or change `MAX_FILE_ROWS`, and change `TRACE_MAX_ROWS` in the test in
the same commit; that is a one-line pair.

### Semantics kept / added

* `dropped` still means **"rows not kept in the in-memory ring"** — the ring
  append path is untouched.
* New public counters: `file_rows`, `file_bytes`, `file_dropped` (+ the same
  three keys in `summary()`).
* `file_bytes` is exact: `String.to_utf8_buffer().size() + 1` per NDJSON line,
  i.e. the byte length `store_line` writes, and the test proves it equals
  `FileAccess.get_length()`.
* When the budget first binds: `_file_capped = true`, one
  `print("STATETREE_TRACE capped rows=%d bytes=%d dropped_file=%d ring_dropped=%d path=%s")`
  (`trace.gd:132`), then every later row increments `file_dropped` and writes
  nothing. One line per process per sink.
* `configure()` resets the three counters (a new sink is a new budget);
  `clear()` deliberately does not (ring-only). `flush()`/`close()` unchanged.

### Proof (`test_w10_runtime.gd:181 _check_trace_file_budget`, additive)

| Assertion | Expected |
|---|---|
| `MAX_FILE_ROWS` / `MAX_FILE_BYTES` read from the script's constant map | both > 0 |
| push 9000 rows, `file_rows` | == `MAX_FILE_ROWS` (8192) |
| NDJSON lines | == `file_rows` |
| `file_dropped` | == 9000 − `file_rows` (808) |
| `file_bytes` vs disk | `== FileAccess.get_length()` |
| push 6000 more | line count unchanged, `file_dropped` == 15000 − 8192 |
| 400 × 64 KiB rows on a second sink | `file_rows < 400`, `file_dropped == 400 − file_rows`, `file_bytes`/disk ≤ 16 MiB |

The original D6 block (`_check_trace_cap`, 9000 rows → ring 8192 / dropped 808 /
`lines <= 8192`) is untouched; its line assertion now passes *because* the sink
stops, which is the point.

---

## D7 — coplanar authored convex geometry (corrected rule)

### Rule as implemented

In `resolve()` (`authored_collision.gd:312-345`), for **every convex element**
the baked point AABB is computed in mesh space (identity offset, i.e. after the
`P·M·P` bake but before any instance transform). If its **minimum extent is
`< PLANAR_EPS_M`** the element is a coplanar surface, not a solid:

* it **emits no shape at all** (skipped before `_shape_of`),
* `planar_convex_skipped` (per resolve + process total) increments,
* the path is recorded once in `planar_skipped_paths` (max 32),
* one `COL_PLANAR <ue_path> instances=<n> skipped=<k>` line prints the first
  time that path is skipped in the process (`_planar_reported` dedupes; the
  resolve cache already makes a repeat of the same key free).

**Boxes are not part of the rule.** They keep
`maxf(absf(ext), MIN_HALF_EXTENT_M * 2)` exactly as before, and each box element
whose authored extent is below the clamp is counted in `box_clamped`. No path
allowlist, no `push_warning`, no degenerate classification for boxes.

`_decode_element` now keeps `raw_size` (authored, pre-clamp) and `clamped` per
box so the counter is attributable; `_planar_extent()` returns `INF` for a point
set with < 4 points so the unknown-element-type placeholder keeps its old
behaviour.

### Constants and why

| Constant | Value | Why |
|---|---|---|
| `MIN_HALF_EXTENT_M` | 0.01 (unchanged) | A thin box is a real solid here (glass, rugs, the engine plane; the payload's clamp fires on 27 box elements across 18 placed meshes = 295 placed instances excluding the 20 engine Plane instances, 235 glass). Thickening to 2 cm remains the best available encoding. |
| `PLANAR_EPS_M` | `1e-4` m (0.1 mm) | Measured: the three coplanar convexes are **1.2e-18 m** (float residue of an authored exactly-0 extent); the next-flattest convex element in the whole 8,601-element dump is **2.000e-3 m** (`SM_TriangleRing`), then the 2.001e-3 m window glass. Nothing lies in `[1e-4, 1e-3)` or `[1e-3, 2e-3)`. One order of magnitude of headroom on the real side, fourteen on the defect side. |
| `PLANAR_PATH_REPORT_MAX` | 32 | `planar_skipped_paths` is a report list; the counters stay exact. |

Measured payload (my own scan of `game/data/generated/mesh_collision.json`):

* convex elements < 1e-4 m: **3** — `SM_SlowWardZone_Quad`,
  `FXSHAPES_1_FXQuadPivotCenter`, `FXSHAPES_1_FXQuadPivotDownEdge`.
* the authored ward quad is **2 × 2 cm** (mesh-space extents
  `X 2.000e-02, Y 1.225e-18, Z 2.000e-02`, i.e. flat in mesh Y / the XZ plane);
  placements **82** Guildhall + **78** OldManor = 160, with non-uniform instance
  scales (Guildhall authored x 149.608–399.3602, z 7.6564–593.3717).
* box elements whose clamp fires (any authored axis < 2 cm): **39 elements /
  29 meshes** in the payload.

### Behaviour change (intended)

160 ward colliders (82 + 78) disappear and the 2 coplanar FX convexes emit no shape (the third coplanar element is the ward quad itself). No other mesh
changes shape count. The reduced branch keeps its caps
(`MAX_CONVEX_ELEMENTS_PER_MESH`, `MAX_ELEMENT_SHAPE_COST`) and its AABB
coalescing; it now consumes the *kept* element list so a skipped coplanar
surface cannot come back through the coalesced trimesh (`:370`). Nothing in
`level_loader.gd` was touched — `_fill_authored_shape` already handles an empty
`shapes` array (`shape = null`, no collider emitted).

`stats()` gains `planar_convex_skipped`, `box_clamped`, `planar_skipped_paths`;
`resolve()` gains `planar_convex_skipped` and `box_clamped` per mesh, plus the
investigation's old `degenerate` key kept as an alias for the skip count so the
pre-existing assertion `ward.get("degenerate", 0) >= 1`
(`test_w10_runtime.gd:470`) still reads the right number.

### Proof (`test_w10_runtime.gd:478 _check_planar_rule`, `:611 _check_ward_grounding`)

| Case | Expected |
|---|---|
| `SM_SlowWardZone_Quad` @ 1 | `shapes == []`, `offsets == []`, `planar_convex_skipped == 1` |
| same key twice | process counter +1 only once (cache is free) |
| `SM_SlowWardZone_Quad` @ 160 | `shapes == []`, counter +1 more; path listed |
| `FXSHAPES_1_FXQuadPivotCenter` @ 6 | `shapes == []`, `planar_convex_skipped == 1`, listed |
| `FXSHAPES_1_FXQuadPivotDownEdge` @ 6 | `shapes == []`, `planar_convex_skipped == 1` |
| `/Engine/BasicShapes/Plane` @ 1 | 1 `BoxShape3D`, size `(1, 0.02, 1)`, `box_clamped == 1`, `planar_convex_skipped == 0` |
| `SM_Civic_GlassPanel_Window6x6` @ 4 (8.5 mm glass, real thin solid) | 1 `BoxShape3D`, min axis `0.02`, `box_clamped == 1`, planar 0 |
| `SM_OldManor_Doorway_4x650` @ 1 | 14 shapes, `reduced == false`, planar 0 |
| same @ 37 (real `OldManor_Geo` count; `(14−1)·37 = 481 > 250`) | 1 shape, `reduced == true`, planar 0 |
| `stats().box_clamped` | ≥ 1 |
| grounding, resolved data | ward set is 0 shapes / 0 offsets; a downward ray from y=2.0 over the fixture floor (top at y=0) hits at \|y\| ≤ 0.02 |
| grounding, synthetic control | the pre-fix coplanar hull (rebuilt from `decoded_elements()` points; the decoded hull is flat in mesh Y, so an `identity` basis lays it horizontally) at y=1.0 answers the same ray at 1.0 ± 0.1 — i.e. the defect was real |

Which half is what, stated in the code: **resolved data** = `resolve()`'s empty
set (this is what the loader consumes); **synthetic control** = a
`ConvexPolygonShape3D` built from the authored points the module no longer
emits. The fixture rig sits at world `(500, 0, 500)`, far from the Jolt probe
bodies the investigation's D7 block builds at the origin and at the authored
ward transform. (An earlier draft of this control used a 90° X rotation on the
assumption that the hull was flat in mesh Z; it is flat in **Y** — measured
`Y extent 1.2e-18 m` — so the rotation was removed and the control is an
identity basis. Credit where due: that correction came from the concurrent
editor of the test file, and I re-derived it from the payload before keeping
it.)

Expected load-time log delta: three `COL_PLANAR` lines per full load (one per
path), no new warnings, `AUTHORED_COLLISION ... reduced=16` unchanged.

---

## D9 — runtime-smoke gate hardening

### Split

* `build/qa/runtime_smoke_scan.sh <log> <exit_code>` — the whole decision, one
  machine line, exit 0/1 (2 for usage). No Godot.
* `build/qa/runtime_smoke.sh [secs]` — boots the mission under `flock` +
  `timeout`, never deletes the log, prints `log: <path>` on stdout **and**
  stderr, then calls the scan and maps its exit to `RUNTIME_SMOKE PASS|FAIL`.
* `build/qa/runtime_smoke_allowlist.txt` — the documented teardown allowlist
  (the effective defaults are embedded in the scan; see below).
* `build/qa/test_runtime_smoke_scan.sh` — deterministic self-test, fixture logs
  in a temp dir, no GPU.

### Policy (in this order)

1. **Exit 124 only.** 124 is the `timeout` kill, i.e. the game stayed up for the
   window. Any other code fails with the code in the line
   (`reason=unexpected_exit_<code>`); `0` gets its own message ("the mission
   exited on its own, it did not stay up").
2. `TAT-2 mission_ready` must appear ≥ 1 (`reason=no_mission_ready`).
3. Error lines = lines matching `SCRIPT ERROR|SHADER ERROR|ERROR:` (one count
   per line; `ERROR:` covers Godot 4's `USER ERROR:` rendering of
   `push_error()`) **minus** lines matched by the allowlist
   (`reason=runtime_errors`). The allowlist is applied only to `ERROR:` lines,
   so a pattern can never hide a warning or a normal print; the subtraction is
   floored at 0.

Machine line:

```
RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 raw=0 allowed=0 script_errors=0 shader_errors=0 mission_ready=1 reason=ok path=/tmp/tat2-smoke-XXXX.log
```

### Allowlist — every entry, and why it is not a game defect

`.gitignore:25` ignores everything under `build/qa/` except `*.gd/*.sh/*.py`, so
`runtime_smoke_allowlist.txt` **cannot be committed as-is**. The effective
defaults are therefore **embedded in `runtime_smoke_scan.sh:63-68`** (one
`<<'ALLOW'` heredoc), and the `.txt` file is the human-readable record plus an
optional local extension that the scan appends when present. I verified the
embedded set alone passes a log containing all four families (moved the `.txt`
away, re-ran). The `.txt` header says this too.

| Pattern (POSIX ERE, embedded) | Observed line | Why it is not a game defect |
|---|---|---|
| `^ERROR: [0-9]+ resources? still in use at exit` | `ERROR: 2 resources still in use at exit (run with --verbose for details).` | Godot's ObjectDB/resource teardown report when `timeout` SIGTERMs a still-live scene. Exit 124 is the accepted termination, so the scene is expected to be alive at shutdown. |
| `^ERROR: [0-9]+ RID allocations of type` | `ERROR: 7 RID allocations of type 'N17PhysicsServer3D' were leaked at exit.` | Same teardown class; the count varies with the frame the kill lands on. |
| `^ERROR: Pages in use exist at exit in PagedAllocator` | `ERROR: Pages in use exist at exit in PagedAllocator` | Allocator exit report; names no script and no path. |
| `^ERROR: Parameter "fd" is null` | `ERROR: Parameter "fd" is null.` | `FileAccessUnix` closing a pipe whose descriptor was already reaped after SIGTERM; carries no game-code frame. |

The header of the `.txt` states the admission rule: exact observed line +
written reason, teardown/exit noise only, a new entry is a wave decision. No
game-code error is allowlisted, and the allowlist is applied only to lines
already counted as `ERROR:`.

### Self-test matrix (from `build/qa/test_runtime_smoke_scan.sh`, 29 checks)

| # | Case | exit code fed | Old gate | New gate |
|---|---|---|---|---|
| 1 | clean boot | 124 | PASS | **PASS** |
| 2 | warning-only boot | 124 | PASS | **PASS** |
| 3 | allowlisted teardown `ERROR:` | 124 | PASS | **PASS** |
| 4 | `ERROR: Condition … is true` | 124 | PASS (blind) | **FAIL** |
| 5 | `USER ERROR:` (push_error) | 124 | PASS (blind) | **FAIL** |
| 6 | crash / signal 11 | 139 | PASS (blind) | **FAIL** |
| 7 | premature exit 0 | 0 | PASS (blind) | **FAIL** |
| 8 | clean log, exit 1 | 1 | PASS (blind) | **FAIL** |
| 9 | `SCRIPT ERROR` | 124 | FAIL | **FAIL** |
| 10 | `SHADER ERROR` | 124 | FAIL | **FAIL** |
| 11 | never `mission_ready` | 124 | FAIL | **FAIL** |
| 12 | machine line PASS/FAIL shape | — | — | PASS |
| 13 | usage / missing log | — | — | exit 2 / 1 |

Verbatim output:

```
PASS scan   clean boot               exit=0
PASS prefix clean boot               exit=0
PASS scan   warning-only boot        exit=0
PASS scan   allowlisted ERROR        exit=0
PRE_FIX_BLIND_SPOT: ERROR: line -> runtime_smoke.sh at 29046c8=PASS, scanned=FAIL
PRE_FIX_BLIND_SPOT: push_error line -> runtime_smoke.sh at 29046c8=PASS, scanned=FAIL
PRE_FIX_BLIND_SPOT: signal-11 crash -> runtime_smoke.sh at 29046c8=PASS, scanned=FAIL
PRE_FIX_BLIND_SPOT: premature exit 0 -> runtime_smoke.sh at 29046c8=PASS, scanned=FAIL
PRE_FIX_BLIND_SPOT: clean log, exit 1 -> runtime_smoke.sh at 29046c8=PASS, scanned=FAIL
PASS prefix ERROR: line              exit=0
PASS prefix push_error line          exit=0
PASS prefix signal-11 crash          exit=0
PASS prefix premature exit 0         exit=0
PASS prefix clean log, exit 1        exit=0
PASS scan   ERROR: line              exit=1
PASS scan   push_error line          exit=1
PASS scan   signal-11 crash          exit=1
PASS scan   premature exit 0         exit=1
PASS scan   clean log, exit 1        exit=1
PASS prefix SCRIPT ERROR             exit=1
PASS scan   SCRIPT ERROR             exit=1
PASS prefix SHADER ERROR             exit=1
PASS scan   SHADER ERROR             exit=1
PASS prefix never mission_ready      exit=1
PASS scan   never mission_ready      exit=1
RUNTIME_SMOKE_SCAN_TEST PASS checks=29 fails=0
```

`bash -n` passes on all three scripts. Example machine lines from direct runs:

```
RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 raw=0 allowed=0 script_errors=0 shader_errors=0 mission_ready=1 reason=ok path=/tmp/tmp.QxYOsrFvEj/clean.log
RUNTIME_SMOKE_SCAN FAIL exit=124 errors=1 raw=2 allowed=1 script_errors=1 shader_errors=0 mission_ready=1 reason=runtime_errors path=/tmp/tmp.KxC8CH8OIh/mixed.log
RUNTIME_SMOKE_SCAN FAIL exit=0 errors=0 raw=0 allowed=0 script_errors=0 shader_errors=0 mission_ready=1 reason=unexpected_exit_0 path=/tmp/tmp.QxYOsrFvEj/clean.log
```

(The mixed log had one teardown line + one `SCRIPT ERROR`; `raw=2 allowed=1
errors=1`, and the failure dump prints only the `SCRIPT ERROR` line.)

---

## Gate impact / risks for the lead

* **Committing this evidence.** `build/qa/*` is git-ignored except
  `*.gd/*.sh/*.py` (`.gitignore:23-28`), so `git status` will show the two new
  `.sh` files but not `runtime_smoke_allowlist.txt` or this report. Either
  `git add -f build/qa/w10/impl-b.md build/qa/runtime_smoke_allowlist.txt`, or
  add `!build/qa/w10/*.md` / `!build/qa/*.txt` exceptions in a wave commit. The
  gate itself does **not** depend on the `.txt` (defaults are embedded).
* `make runtime-smoke` now prints three lines: `log: <path>`,
  `RUNTIME_SMOKE_SCAN …`, `RUNTIME_SMOKE PASS|FAIL`. Old greps for
  `RUNTIME_SMOKE PASS` still work; the old `RUNTIME_SMOKE seconds=…` line is gone
  (nothing in `tools/`, the Makefile or `gate_ratchet.json` reads it — checked).
* The smoke log is no longer deleted on PASS: commit it from
  `/tmp/tat2-smoke-*.log` when the wave records evidence.
* D7 removes the ward colliders (160 placements) and the two FX quads'
  colliders from a full load; `AUTHORED_COLLISION`'s `shapes_per_instance_avg`
  and `collision_bodies` will drop slightly, `col_authored_hull`/coverage will
  not. **Not verified** — no engine run here.
* E2E risk (by design): ward-zone billboards are now passable.
* `COL_PLANAR` prints `instances=` from the resolve argument, which is the
  load-total placement count the loader pre-pass supplies.
* All three defects are proven by `game/tests/test_w10_runtime.gd`; its runtime
  behaviour is **not verified** by this lane (no Godot). Compile it with the rest
  of the gate set.
