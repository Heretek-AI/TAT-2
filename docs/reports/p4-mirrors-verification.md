# P4.2 mirrors — read-only rebase verification

**Verdict: PASS at `dffb35f`** — the rebased branch (`354fab0` six-lane
integration + `a371852` mirror split + `96283f9` source-count/probe fix +
`9a5b242` verification report + `dffb35f` GC glass probe fix) keeps the mirror
math, the integrated GC bookcase-glass registration and the landscape/beam
work. The merged census is 3,297 mirrored draw instances = **3,119 MultiMesh +
178 standalone**; the `make test` failure is the expected stale
`audio_control.json` suite 121 only. No GPU was run; no data was regenerated.

**Lane:** worktree `/home/john/.local/share/opencode/worktree/318f41/phase1-p4-mirrors`,
branch `p4-mirrors`, measured tip **`dffb35f`**. The verification report is a
docs-only commit on top; its SHA is reported in the handoff (a file cannot
contain its own hash).

**Method:** read the rebased diff (`354fab0..dffb35f`), the conflict-resolved
`level_loader.gd`, the updated mirror report and docs, and the lane's retained
`merge_*.log`; then re-ran the headless probes at `dffb35f`. Every
`/tmp/opencode/p4mirror/rebased_verify_*.log` starts with
`HEAD=dffb35f95d451a241162309161b947d02379bb96`. **No Godot GPU, Vulkan, Xvfb,
Steam, `make normalize` or extractor run was made** by this verifier.

## 1. PASS — conflict resolution keeps both intents

The shared `level_loader.gd` has one `_build_one_draw_item()` /
`_finish_draw_node()` path that carries both the mirror split and the six-lane
integrations:

| Intent | Current code | Evidence |
|---|---|---|
| Mirror partition | `partition_mirror_indices()` at `:5212-5222`; `MIRROR_LOCAL_FLIP=diag(-1,1,1)` at `:181` | Full probe `MIRROR_RECON ok=true`; static 3,312 neg |
| `B'=B*S` / `M'=S*M` | `:5340-5361` (baked `neg_trs[bi] = basis*S`; single opt-in `:5361`) | Full probe 3,297; 0 unbaked |
| Reverse winding | `_bake_mirrored_mesh()` `:2635-2704`: vertices x negated, index pair swap, normals x, tangents x/w | Probe bake checks 3-surface door; `PASS: baked triangle winding…` |
| Bake cache | `_get_mirror_variant()` `:2546-2614`; `_mirror_variant_cache` keyed mesh+override+allow-clone+fast | `baked=103` unique variants; full probe |
| CULL_FRONT fast path | `_get_mirror_variant()` `:2566-2582`, `_get_mirror_cull_front_material()` `:2616-2631` | `cull_front=312`; geometry 39/0 |
| Standalone native + opt-in | `_build_one_draw_item()` `:5352-5378`; `TAT2_MIRROR_SINGLE=baked` | default `single=178`; SINGLE=baked 968/0 |
| Source apportionment | `split_source_counts()` `:4184-4254`; call `:5316-5318`; pos/neg `:5377-5402`; metas `:5386-5388` | `src_sum=64660`; `checked=464 splits=464 ok=true` |
| Per-load reset | `_reset_mirror_counters()` `:2511-2525`; calls `:7577`, `:7628` | Full load cache/counters correct |
| GC bookcase glass | `GC_BOOKCASE_GLASS_MESH` per-instance `:3817-3823`; shared `_finish_draw_node()` `:5127`; glass registration `:5178-5205`; MM fallback `gc_static_leaf_multi += instance_count` `:5201-5205`; owner binding `_build_gc_layers()` `:7786-7901` | GC probe 52/0; 16 static panes; no duplicate |
| Landscape mask | `LANDSCAPE_MASK_ENV`/modes `:8197-8221`; `sample_mask` binding `:8313`; `LANDSCAPE_MASK` log `:8404-8410` | `probe_landscape_mask` 7/0 |
| Beams | authored beam path intact | `probe_p1_beams` 9/0 |

The GC glass block is deliberately in the **shared** `_finish_draw_node()`: a
split negative bookcase pane is a `MeshInstance3D`, so it receives
`gc_static_leaf=true`, `gc_no_collision=true` and enters `_gc_static_glass`
(`:5189-5196`) exactly like the positive pane. The `MultiMeshInstance3D`
fallback is still counted per instance (`:5201-5205`). The dffb35f test fix
orders the mirror-probe walk as “tagged node first, GC exclusion second”
(`probe_mirror_split.gd:582-591`), so a tagged glass pane is not swallowed by
the GC overlay exclusion.

## 2. PASS — measured counts at `dffb35f`

| Gate / count | Result | Evidence |
|---|---|---|
| compile | **228 checked / 0 broken** | `rebased_verify_compile.log` |
| `probe_mirror_split` geometry | **39/0** | `rebased_verify_mirror_geometry.log` |
| `probe_mirror_split -- --full` | **790/0**, `src_sum=64660` | `rebased_verify_mirror_full.log` |
| `TAT2_MIRROR_SINGLE=baked` | **968/0**, `single=178`, 223 variants / 61,972,836 B | `rebased_verify_singlebaked.log` |
| `TAT2_MIRROR_FAST=off` | **39/0** | `rebased_verify_fastoff.log` |
| M2 | **12/0** | `rebased_verify_m2.log` |
| geometry | `GEOM_PROBE checks=7 fails=0` | `rebased_verify_geometry.log` |
| GC destruction | **52/0** | `rebased_verify_gc.log` |
| landscape mask | **7/0** | `rebased_verify_landscape.log` |
| P1 beams | **9/0** | `rebased_verify_beams.log` |
| mirror probe selftest | **8/0** | `rebased_verify_selftest.log` |
| `make test` | **371 PASS**, `SUMMARY: fails=1`; only suite 121 | `rebased_verify_run_tests.log` |

The full mirror load prints the exact requested census:

```
MESH_RECON authored=64956 applied=64685 … mirrored_bases=3297
  mirrored_multimesh=3119 mirrored_single=178 mirrored_splits=464
  mirrored_cull_front=312 mirrored_cull_disabled=0
  mirrored_mesh_bytes=31097388 mirrored_mesh_count=103 mirrored_unbaked=0
MIRROR_RECON bases=3297 multimesh=3119 single=178 split=464 cull_front=312
  cull_disabled=0 baked=103 baked_bytes=31097388 unbaked=0 suppressed=400 ok=true
PASS: one negative node per split item (no hidden extra split) nodes=464 splits=464
PASS: every split item apportions pos+neg source counts exactly once
  checked=464 splits=464 ok=true
PASS: PERF_CENSUS.source_sublevels equals the pre-split baseline
  src_sum=64660 want=64660
MIRROR_LOAD paths=17 authored_records_neg=3312 … mm=3119 single=178 split=464
  … baked_variants=103 baked_bytes=31097388 unbaked=0 walk_mm=3119
  walk_single=178 walk_baked_nodes=246 untagged_neg=0 gc_native_neg=8
  src_sum=64660 perf_instances=65132
MIRROR_DATA_SUMMARY: fails=0 checks=790 mode=full
```

`make test` 11b prints `source_sum=64660` and
`PERF_CENSUS instances=65132`, `periph_instances=13446`, `periph_nodes=3350`,
`chunk_nodes=6624`, `surface_draws=12093`, `SkyboxGeo=33547`,
`PeripheryA=12378`. Total mirrored draw instances are **3,297**
(`3119 + 178`), unchanged from the pre-merge 3,297; only the ownership split
changed.

## 3. PASS — the 786 → 790 delta is the 10 GC glass panes

Pre-merge `1f5da98` full probe (retained `verify_mirror_full.log`) had 786
checks: 289 tagged-MM meta checks, 168 native-standalone checks, 249 baked-MM
checks, 40 cull-front batch checks and 1 cull-disabled check. The rebased
`dffb35f` run has 790: **286 tagged-MM meta, 178 native-standalone, 246
baked-MM**, 40 cull-front and 1 cull-disabled.

* `+10` native standalone checks — the 10 negative GC glass panes.
* `-3` tagged-MM meta + `-3` baked-MM = **-6** checks — the 3 MultiMesh nodes
  those 10 panes used to share (each had a meta and a baked-mesh check).
* Net **+4** = 790 − 786.

The instance ledger is unchanged: `multimesh` 3,129 → **3,119** (−10),
`single` 168 → **178** (+10), `bases` **3,297** unchanged. `split` moves
457 → **464** (10 panes in 7 item groups), `baked` 104 → **103** and bytes
31,099,116 → **31,097,388** (−1,728) because the removed glass batch loses one
baked variant. The full run's `walk_mm=3119`, `walk_single=178`,
`walk_baked_nodes=246`, `untagged_neg=0`, `gc_native_neg=8` and
`MIRROR_RECON ok=true` confirm the walk.

## 4. PASS — GC bookcase glass still binds and hides

The GC probe at `dffb35f` prints:

```
GC_PROBE load layers=95 leaves=79 hidden_initial=95 visible_broken=0 meshless=0 owner_index=87 collision_shapes=256
GC_PROBE owner_index broken_owners=87 leaf_owners=87 paired=87 broken_only=0
  broken_kinds={ "chest": 48, "display_case": 31, "bookcase": 16 }
  leaf_kinds={ "chest": 48, "display_case": 31 }
  static_leaves=16 static_kinds={ "bookcase": 16 }
GC_CHECK PASS bookcase intact panes bound from the static batch 16 panes (expected 16)
GC_CHECK PASS static-batch binding is exact (no duplicate, no fallback guess) bound=16 unmatched=0 batched_panes=0
GC_CHECK PASS bookcase break hides both panes and shows both authored overlays panes_visible=0 broken_visible=2
GC_CHECK PASS bookcase break created no duplicate glass node static_panes=16 before/after
GC_PROBE checks=52 fails=0
GC_PROBE PASS
```

The split negative panes are registered via the shared node path; the
`gc_static_leaf_multi` fallback is exercised only if a glass node is still a
`MultiMeshInstance3D`, and it adds `instance_count` (`level_loader.gd:5201-5205`).
This data set's per-instance glass produces **0** batched-pane failures and
16 bound static panes, with no duplicate node.

## 5. PASS — suite 121 is the expected stale-data failure

`make test` at `dffb35f`: **371 PASS**, `SUMMARY: fails=1`; the three `FAIL`
lines belong to suite 121 (`AUD6.10 authored fade=nan`,
`mix_state().music ... fade_s=-1.0`) and `AUDIO_CONTROL_SUMMARY: fails=15
checks=123`. The cause is the stale `audio_control.json` without its `music`
block; **no data was regenerated** (no `make normalize`, no extractor). This is
the documented integrator-owned data-refresh item, not a mirror lane failure.
All other 371 `PASS` lines pass, including 11b with `source_sum=64660`.

## 6. PASS — docs union

`git diff --name-status 354fab0..dffb35f -- docs/reports` contains only:

```
A docs/reports/p4-mirrors-20261127.md
A docs/reports/p4-mirrors-verification.md
```

The six-lane verification reports are present at `354fab0` and in the rebased
tree: `gc-bookcases-verification.md`, `p4-exposure-verification.md`,
`p4-landscape-beam-verification.md`, `navmesh-p0-p2-verification.md`,
`w11-audio-verification.md`, `phase2-ui-verification.md`. No lane report is
modified or deleted by `dffb35f`; the mirror docs add the merged census and the
six-lane notes. This verifier updates only its own
`p4-mirrors-verification.md`, as instructed; no other report is touched.

## 7. Residual integration items (not lane blockers)

* GPU `mirror_probe --run` remains integrator-owned and was not run (no GPU by
  instruction); the synthetic culling/`pass=1` contract is unchanged.
* `make audit` remains subject to the environment's vgmstream tool drift.
* E2E/runtime-smoke and the gate/ratchet registration of the new probe remain
  integrator steps.
* Suite 121's stale `audio_control.json` needs the integrator's permitted
  `make normalize`/audio refresh; this lane did not regenerate it.

## 8. No push / scope

`git branch -r --contains dffb35f` is empty; the branch is local and no push
was made. The rebased branch adds the mirror code/tests/probe and mirror docs to
`354fab0`; no `game/data`, `extracted/`, `project.godot`, tracked build artifact
or GPU/Steam output changed. The only write in this verification is this report,
committed docs-only on `p4-mirrors`; its commit SHA is reported in the handoff.

## 9. Evidence index

| Artifact | Path |
|---|---|
| Measured tip | `dffb35f` (`354fab0` + `a371852`, `96283f9`, `9a5b242`, `dffb35f`) |
| Mirror full / geometry | `/tmp/opencode/p4mirror/rebased_verify_mirror_full.log`, `rebased_verify_mirror_geometry.log` |
| SINGLE=baked / FAST=off | `rebased_verify_singlebaked.log`, `rebased_verify_fastoff.log` |
| GC / landscape / beams | `rebased_verify_gc.log`, `rebased_verify_landscape.log`, `rebased_verify_beams.log` |
| compile / M2 / geometry / selftest | `rebased_verify_compile.log`, `rebased_verify_m2.log`, `rebased_verify_geometry.log`, `rebased_verify_selftest.log` |
| `make test` | `rebased_verify_run_tests.log` |
| Retained lane logs | `/tmp/opencode/p4mirror/merge_*.log` |
| Conflict-resolved loader | `game/src/core/level_loader.gd:181, 2511-2704, 3817-3823, 4184-4254, 5127-5222, 5316-5402, 7577-7628, 7786-7901, 8197-8221` |
| Mirror test | `game/tests/probe_mirror_split.gd:582-591` (GC tagged-first order) |
| Mirror report | `docs/reports/p4-mirrors-20261127.md` |

**Bottom line:** **PASS at `dffb35f`**. The rebase keeps the exact mirror math
and source apportionment, the integrated GC glass registration (16 static
panes bound/hidden, no duplicates) and the landscape/beams work; compile 228/0,
mirror 39/0 and 790/0 with `src_sum=64660`, SINGLE=baked 968/0, FAST=off 39/0,
GC 52/0, landscape 7/0, beams 9/0, M2 12/0 and geometry 7/0 all re-measured at
the tip. The only `make test` failure is the expected stale `audio_control.json`
suite 121; no data was regenerated.
