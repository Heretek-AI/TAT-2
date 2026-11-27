# P4.2 mirrors — read-only lane verification

**Verdict: PASS** at fix commit **`1f5da98`** (parent `c7ddeb8`) — both blockers
from the `c7ddeb8` review are fixed and re-measured headless at `1f5da98`:
`PERF_CENSUS.source_sublevels` is back to **64,660** (not 88,438), the 15-record
gap is explicitly unattributed against the 271 pre-draw filters, and the GPU
probe now gates `--run` on the machine-readable `pass=1` result. The mirror
split itself (math, bake, fast path, standalone fallback, census) also remains
verified. The GPU `--run`, E2E, runtime-smoke, audit tool and the gate/ratchet
registration are integration-owned residuals, not lane blockers (see §6).

**Lane:** worktree `/home/john/.local/share/opencode/worktree/318f41/phase1-p4-mirrors`,
branch `p4-mirrors`; the measured tree is `1f5da98`, and the current HEAD is the
docs-only verification commit on top. **Prior review:** `c7ddeb8` was **FAIL**
on the source-count double count and the unattributed 15-record claim; this
report records the re-check.

**Method:** read the plan §4 P4.2 (`docs/reports/next-phases-plan-20261127.md:152-155`),
the fix diff `c7ddeb8..1f5da98`, the updated report/docs, and the retained lane
logs; then **re-ran the headless probes at `1f5da98`** (each verify log below
starts with `HEAD=1f5da9870ee2060f75a1eabd6949460916ba830f`). **No Godot GPU,
Vulkan, Xvfb or Steam run was made** by this verifier, per instruction.

## 1. PASS — `PERF_CENSUS` is exact again

`split_source_counts()` (`game/src/core/level_loader.gd:4143-4215`) apportions an
item's per-source map with largest-remainder allocation, a sorted-key tie-break
and a residual safety loop. The split calls it once per item
(`:5248-5250`), gives the positive node the `pos` map (`:5310`) and the negative
node the `neg` map (`:5332`), and publishes the three maps as node metadata for
the test (`mirror_item_source_counts`, `mirror_pos_source_counts`,
`mirror_neg_source_counts`, `:5318-5320`). The invariant is per key:
`pos[k] + neg[k] == item[k]`, so the two nodes contribute exactly the item's
counts once.

**Re-run at `1f5da98` — `make test`:**

```
HEAD=1f5da9870ee2060f75a1eabd6949460916ba830f
PASS: 11b W1p PERF_CENSUS (meshes=6698, surface_draws=12079, lights=170,
  shadows=7, periph_nodes=3350, source-tagged draw nodes=6612 missing=0,
  source_sum=64660)
SUMMARY: fails=0
# 324 PASS lines, 0 FAIL (same count as the baseline)
```

`game/tests/run_tests.gd:515-527,549` now pins `gh_src_sum == 64660` exactly and
prints `source_sum` in the suite-11b line; the old double count (88,438) fails
this gate. The full `PERF_CENSUS` map is the baseline map (13 keys), including
`Guildhall_SkyboxGeo: 33547` and `Guildhall_PeripheryA: 12378`; the sum is
**64,660**, with `instances=65132` and `periph_instances=13446` unchanged.

**Re-run at `1f5da98` — `probe_mirror_split.gd -- --full`:**

```
PASS: full load authored count matches the mission baseline authored=64956
PASS: full load applied count matches the mission baseline applied=64685
PASS: full PERF_CENSUS instance count matches the mission baseline instances=65132
PASS: full PERF_CENSUS PeripheryA instance count matches the baseline periph_instances=13446
PASS: PERF_CENSUS.source_sublevels equals the pre-split baseline src_sum=64660 want=64660
PASS: one negative node per split item (no hidden extra split) nodes=457 splits=457
PASS: every split item apportions pos+neg source counts exactly once checked=457 splits=457 ok=true
PASS: cull-front counter is per-instance, not per-node walk=312 counter=312
PASS: cull-disabled counter is per-instance, not per-node walk=0 counter=0
PASS: baked-variant counter is per unique mesh, not per node walk=104 counter=104
MIRROR_LOAD paths=17 authored_records_neg=3312 transform_bases=3329 draw_bases=3297
  mm=3129 single=168 split=457 cull_front=312 cull_disabled=0 baked_variants=104
  baked_bytes=31099116 unbaked=0 walk_mm=3129 walk_single=168 walk_baked_nodes=249
  untagged_neg=0 gc_native_neg=8 src_sum=64660 perf_instances=65132
MIRROR_DATA_SUMMARY: fails=0 checks=786 mode=full
```

The 17-sublevel load is the same mission set as `make test` (15 base +
`Guildhall_Contract_04` + `Guildhall_Contract_Teleporters`); `authored=64,956`
and `applied=64,685` match the committed baseline. The static 15-base
`MIRROR_STATIC_GUILDHALL` remains 64,953 records / **3,312** negatives; the 3
extra mission records are positive.

**The new checks exercise the real split and would fail on the old double count:**

* `checked=457` equals `split_n=457`; every tagged negative node has the three
  `mirror_*_source_counts` maps and `own source_counts == neg`. The old
  `c7ddeb8` loader never set the maps, so the new test's
  `_note_split_accounting()` (`probe_mirror_split.gd:636-653`) would leave
  `split_checked=0` / `split_source_ok=false` and fail the
  `checked == split_n and ok` check, before the sum check.
* The full probe's `src_sum == 64660` and the `make test` 11b `source_sum`
  pin both fail on the old values: the pre-fix logs read **88,438**
  (`/tmp/opencode/p4mirror/run_tests.log`, line 451) and **88,435**
  (`/tmp/opencode/p4mirror/full_final.log`, line 153), +23,778 over baseline.
* The synthetic `split_source_counts` cases (`probe_mirror_split.gd:261-307`)
  cover 0/all/1/7/14 negatives, a 64-instance split, a 3-key 1/3 allocation and
  a 999/1/1 500/1001 split; they assert exact per-key addition, total
  preservation, determinism and the sorted-key tie-break
  (`neg={"A":1}`), and pass in the 39-check geometry run.

**`periph_nodes` 3,218 → 3,350 is a node count, not extra instances.** The
baseline `PERF_CENSUS` is `periph_nodes=3218`, `periph_instances=13446`; the
fixed run is `periph_nodes=3350`, `periph_instances=13446`. The +132 is the 132
split items in PeripheryA that now have a positive **and** a negative draw node;
both nodes keep the authored `source_sublevels` tag list. The instance total is
unchanged because the two batches together cover exactly the item's instances;
`periph_instances` and `instances` are the same 13,446 / 65,132 as baseline.

## 2. PASS — attribution removed

The old “130 duplicate / 30 name-skipped” attribution is gone from the report
and docs. The current wording is:

* `docs/reports/p4-mirrors-20261127.md:71`: the 15-record gap is **not
  attributed**; the pre-draw filters remove 271 records in total
  (`duplicate=130`, `name_skipped=30`, `wardbox=41`, `moonshape=70`), and the
  per-filter negative split is not measured.
* `docs/FIDELITY_GAPS.md:45-50`: 271 records in the 64,956-record mission load,
  with the four filter counts and “the 15-record gap to 3,312 is **not
  attributed** per filter”.
* `docs/HANDOFF_NEXT_AGENT.md:249-251`: same unmeasured/271 statement.

The arithmetic is consistent: 64,956 − 271 = 64,685 applied; the 15 negative
records are a subset of those 271 and are not individually attributed. No
remaining claim assigns the 15 to duplicate/name.

## 3. PASS — probe exit contract

`build/qa/mirror_probe.gd:309-334` now computes
`pass_ok = controls_ok && baked_identity_ok && baked_mirror_ok && single_baked_ok
&& (!fast_expected || (cull_a_ok && cull_b_ok))
&& (single_baked_expected || single_native_ok)`, prints it as `pass=%d` on the
`MIRROR_PROBE RESULT` line, and exits `0` only when `pass_ok` is true.
`native_mm` is printed but is not a pass term. `fast_expected` is false only
when `TAT2_MIRROR_FAST=off`; `single_baked_expected` is true only when
`TAT2_MIRROR_SINGLE=baked`. The wrapper additionally requires the
machine-readable flag (`build/qa/mirror_probe.sh:105-110`):
`MIRROR_PROBE RESULT .*pass=1`, and turns an unexpected Godot exit 0 into an
abort. `--selftest` is unchanged and re-ran green at `1f5da98`:

```
HEAD=1f5da9870ee2060f75a1eabd6949460916ba830f
MIRROR_PROBE_SELFTEST PASS checks=8 fails=0
```

The GPU `--run` itself was not executed (no GPU by instruction), so the
`pass=1` terms are statically verified, not read back.

## 4. PASS — gates re-sampled and bound to `1f5da98`

Each `/tmp/opencode/p4mirror/verify_*.log` starts with the exact HEAD stamp.

| Gate | Result at `1f5da98` | Log |
|---|---|---|
| compile | `scripts checked: 218, broken: 0` | `verify_compile.log` |
| `make test` | 324 PASS / 0 FAIL, `SUMMARY: fails=0`, 11b `source_sum=64660` | `verify_run_tests.log` |
| M2 | `M2_SUMMARY: fails=0` (12 PASS) | `verify_m2.log` |
| geometry | `GEOM_PROBE checks=7 fails=0`, `GEOM_PROBE PASS` | `verify_geometry.log` |
| `probe_mirror_split` (geometry) | `MIRROR_DATA_SUMMARY: fails=0 checks=39 mode=geometry` | `verify_mirror_geometry.log` |
| `probe_mirror_split -- --full` | `MIRROR_DATA_SUMMARY: fails=0 checks=786 mode=full` | `verify_mirror_full.log` |
| `mirror_probe.sh --selftest` | `MIRROR_PROBE_SELFTEST PASS checks=8 fails=0` | `verify_mirror_selftest.log` |

The fix commit's own retained logs agree with these: `fix_compile.log`
218/0, `fix_run_tests.log` `source_sum=64660`, `fix_m2.log` fails=0,
`fix_geometry_final.log` 39/0, `fix_full_final.log` 786/0 and
`src_sum=64660`, `fix_fastoff.log` 39/0 (61 negatives / 1 variant / 335,808 B),
`fix_singlebaked.log` 954/0 (223 variants / 61,972,836 B, `single=168`,
`unbaked=0`). Those logs predate the commit by a few minutes; the `verify_*.log`
re-runs above are the commit-bound evidence.

## 5. Mirror implementation — still verified

The `B = B*S`, `M' = S*M` split (`S=diag(-1,1,1)`, `MIRROR_LOCAL_FLIP` at
`game/src/core/level_loader.gd:174`) is exact: `B'*M' = B*M`, `det(B') > 0`,
vertices `x` negated, triangle winding reversed, normals `x` negated, tangents
`x` and `w` negated; the bake reuses the authored surface materials, never
mutates the source, and is cached by mesh+override with a per-load reset. The
single-surface `BaseMaterial3D` fast path clones to `CULL_FRONT` without touching
the shared material; a two-sided source needs no flip; a standalone
`MeshInstance3D` keeps native compensation by default with
`TAT2_MIRROR_SINGLE=baked` opt-in; `TAT2_MIRROR_FAST=off` selects the bake.

The measured mirror census is unchanged from the prior review and matches the
report: 3,312 authored negatives; 3,297 draw = 3,129 MultiMesh + 168 standalone;
104 baked variants / 31,099,116 B; 312 CULL_FRONT; 0 cull-disabled/unbaked; 457
splits / 393 suppressed log lines; 8 native GC; old 3,215 not reproduced. The
`probe_mirror_split` 786-check run verifies the tree walk tags, per-instance
cull counters, unique baked-mesh counter and the 64,660 source sum.

## 6. Residual — integration-owned, not P4.2 lane blockers

These are explicitly outside the headless lane and must be handled by the
integrator; none blocks the fixed implementation:

* **GPU `--run`** — not run here; the `pass=1` contract is code-verified, and the
  probe's visual/engine verdict remains pending. The lane report says so.
* **E2E and runtime-smoke** — not run in this lane (E2E is the integrator's full
  set; runtime-smoke was blocked by the shared lock).
* **`make audit`** — red only on environment tool drift (`vgmstream ... ->
  'missing'`); content/device/anim/audio/localization/video checks are OK.
* **`make gate-ratchet` / gate registration** — the new probe is not yet in
  `build/qa/run_final_gates.sh` or the ratchet; the integrator owns the gate-set
  update and re-stamp.
* **Probe scope** — the synthetic readback is unshaded, identity-basis culling
  evidence; lighting/shadows and a general rotated mirror remain for the visual
  capture. Both split nodes carry `ue_mesh`/group metadata; this data set has
  0 negative beam-card or ward-shard records (independent 15-base parse), so the
  current device consumers are not duplicated, but future mirrored cards/shards
  need one node marked non-adoptable.

## 7. No push / scope

`1f5da98` is one commit on top of `c7ddeb8` and touches 8 files:
`game/src/core/level_loader.gd`, `game/tests/probe_mirror_split.gd`,
`game/tests/run_tests.gd`, `build/qa/mirror_probe.gd/.sh`,
`docs/FIDELITY_GAPS.md`, `docs/HANDOFF_NEXT_AGENT.md`,
`docs/reports/p4-mirrors-20261127.md`. No `game/data`, `project.godot`,
`extracted/`, tracked build artifact or GPU/Steam output. `git branch -r
--contains 1f5da98` is empty and `git log origin/main..HEAD` contains only the
lane commits; **no push**. This verification's only write is this report, which
is committed docs-only on `p4-mirrors`; its commit SHA is reported in the
handoff (a file cannot contain its own hash).

## 8. Evidence index

| Artifact | Path |
|---|---|
| Fix commit | `1f5da98` (`c7ddeb8..1f5da98`) |
| Updated lane report | `docs/reports/p4-mirrors-20261127.md` |
| Full mirror probe | `/tmp/opencode/p4mirror/verify_mirror_full.log` |
| Geometry probe | `/tmp/opencode/p4mirror/verify_mirror_geometry.log` |
| `make test` | `/tmp/opencode/p4mirror/verify_run_tests.log` |
| Compile / M2 / geometry | `verify_compile.log`, `verify_m2.log`, `verify_geometry.log` |
| Selftest | `/tmp/opencode/p4mirror/verify_mirror_selftest.log` |
| Pre-fix double-count logs | `run_tests.log` (88,438), `full_final.log` (88,435) |
| Fix lane logs | `/tmp/opencode/p4mirror/fix_*.log` |
| Split code | `game/src/core/level_loader.gd:174, 2510-2693, 4143-4215, 5248-5332` |
| Test | `game/tests/probe_mirror_split.gd` |
| Gate pin | `game/tests/run_tests.gd:515-549` |
| GPU probe contract | `build/qa/mirror_probe.gd:309-334`, `build/qa/mirror_probe.sh:105-110` |

**Bottom line:** **PASS** at `1f5da98`. The source census is exact again
(64,660; 11b and the 786-check probe pin it), the 15-record gap is honestly
unattributed against the 271 filters, the probe exit contract gates on
`pass=1`, and compile 218/0, `make test` 324/0, M2 12/0, geometry 7/0 and both
mirror probe modes (39/0, 786/0) were re-sampled with `HEAD=1f5da98`. The GPU
readback and the integrator's E2E/runtime-smoke/audit/ratchet steps remain
outside this lane.
