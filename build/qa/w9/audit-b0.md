# W9-P2 / B0 — independent audit (final re-audit)

Auditor: independent B0 auditor (did not write this lane).
Worktree: `/home/john/Projects/TAT-2-rem-w9-p2`, base `b13260b`, dirty tree.
Read-only: the only file written is this report. No code changed since the audit
runs (`test_roof_collision.gd` md5 `39b625f3…`, `probe_collision_authored.gd`
`a44dc838…`, `level_loader.gd` mtime 13:04); every number below was re-parsed
from `build/qa/w9/logs/perf_ab_{authored,aabb}_r{1,2}.log`.

## Final verdict at a glance

| item | verdict |
|---|---|
| claim 1 — roof probe rebased, RED 42/9 & 51/0, GREEN 53/0 & 53/0 | **PASS** (unchanged) |
| claim 2 — no check removed; 9 rebased with same intent; 2 census checks | **PASS** (disclosure now in `§B0-1`) |
| claim 3 — union numbers exact | **PASS** (unchanged) |
| claim 4 — `COL_AUDIT` dropped=0 / coverage=0.989 / shapes=30901 / bodies=243 | **PASS** (unchanged) |
| claim 5 — FPS p50/p95, per-round, not resolvable | **PASS** (corrected) |
| claim 6 — load attribution, payload 258–386, aabb trimesh not larger, emission inseparable | **PASS** (remediated) |
| finding 1 — per-round FPS bounds | **PASS** |
| finding 2 — load peak-to-peak span / outside range | **PASS** |
| finding 3 — 92 °C qualifier | **PASS** |
| finding 4 — minor ranges, +376 ms, fact-sheet lines | **PASS with editorial residue** |

## Finding 1 — per-round FPS — PASS

The "≤4 % in both rounds" and "up to ~14 % in the hot round" claims are gone.
`p2-report.md:266-277` now gives the ABBA means and the per-round deltas; the
verdict line (`:305-307`) says "FPS ABBA-mean p50 +0.9/+1.3/+3.8 % but per-round
up to +7.7 %, p95 up to +23.1 % in r2; unresolved from two runs", and "a
cool-host 3-repeat run is needed before any conclusion". Re-computed:

| pose | p50 r1 | p50 r2 | p95 r1 | p95 r2 | ABBA p50 | ABBA p95 |
|---|---:|---:|---:|---:|---:|---:|
| upper_foyer | −0.92 % | +2.75 % | −6.12 % | +9.15 % | +0.90 % | +1.25 % |
| foyer_yaw180 | −2.78 % | +5.36 % | +0.30 % | +23.09 % | +1.29 % | +11.72 % |
| gate | −0.13 % | +7.72 % | +7.35 % | +20.42 % | +3.79 % | +14.14 % |

Report rounds: r1 −0.9/−2.8/−0.1 % and r2 +2.8/+5.4/+7.7 % (p50); r1
−6.1/+0.3/+7.4 % and r2 +9.2/+23.1/+20.4 % (p95) — exact. The conclusion
("unresolved; authored r2 is the hot round") is correct and conservative.

## Finding 2 — load span and range — PASS

`p2-report.md:278-289` now: round deltas **−3,205 / +705 ms**, ABBA mean
**−1,250 ms**, "a **3,910 ms peak-to-peak span**, half-width **±1,955**", and
"P1's +3.65 s and the A1 audit's −5.0 s lie outside the observed round-delta
range **[−3,205, +705]**". Verified: `|−3,205 − 705| = 3,910`; half-width
1,955; P1 +3,653 > +705; A1 −5,011 < −3,205. The direction is not quoted and
"no stable multi-second penalty" is the right reading. Numbers exact.

## Finding 3 — 92 °C qualifier — PASS

Open risk 6 (`p2-report.md:606-608`) now reads: "the CPU package measured
**92 °C after** the runs, not during them; the recorded GPU is **67.9–74.8 °C**;
yaw/gate 37–44 vs P0's 43.6–46.7". Matches the `.gpu_before/.gpu_after`
artefacts (67.91–74.76 °C) and no longer implies a during-run capture.

## Finding 4 — ranges, +376 ms, fact-sheet lines — PASS (with residue)

Measured phase values (authored r1/r2 vs aabb r1/r2):

| phase | authored | aabb | report (corrected clause) |
|---|---|---:|---|
| terrain delta | **0.59 / 0.81 s** | 0.77 / 0.78 s | 0.55/0.81 vs 0.77/0.78 — r1 **0.55 is wrong** (must be 0.59) |
| `glb_ms` | 1,235 / 1,551 | 1,540 / 1,402 | 1.24/1.55 vs **1.54/1.40** ✓ |
| `mat_ms` | 4,121 / 4,940 | 4,566 / 4,533 | 4.12/4.94 vs **4.57/4.53** ✓ |

The payload-adjusted attribution is correct: authored pays 258/386 ms inside
`mesh_ms`, aabb pays it after `draw_ms` (`_finalize`), so the raw `mesh_ms`
delta −54 ms becomes **≈ +376 ms** for the aabb trimesh cost — still below the
1.25 s mean and inside the drift, so "not the larger term" holds. The fact
sheet's loader pointers are now current-tree: `LoadTiming` draw **6798**
(6775 at `b13260b`), parse 6727, lights 6763, terrain 6778, sync parse 6664;
`_add_collider` **4225-4245**, `perf_build_ms` close **4593-4596**.

**Residue:** the same attribution paragraph still carries the pre-correction
list before the corrected clause — `terrain 0.59/0.86` (`:290`), `glb_ms
1.24/1.55 vs 1.40/1.50` and `mat_ms … vs 4.53/4.57` (`:292`) — so it states two
different terrain pairs (0.59/0.86 and 0.55/0.81) and two glb/mat pairs. The
corrected values are present; the stale ones were appended over, not replaced.
This is an editing residue, not a change of any claim or conclusion, but the
paragraph should not ship in that state.

## Remaining inaccuracies (fix before committing the report; non-blocking for B0)

1. `p2-report.md:290-293` — delete the stale first list. Keep one list only:
   **terrain 0.59/0.81 s** authored vs 0.77/0.78 aabb (0.55 → **0.59**; the
   measured r1 delta is 5,339 − 4,753 = 586 ms), `glb_ms` 1.24/1.55 vs
   **1.54/1.40**, `mat_ms` 4.12/4.94 vs **4.57/4.53**.
2. `p2-report.md:571` (wave summary) — "the ±3.9 s round-to-round spread" is the
   same notation error §B0-2 just fixed: say "a 3,910 ms peak-to-peak span
   (±1,955)". `facts-b0.md:63` ("±3,910 ms drift") likewise.
3. `facts-b0.md:45` — `_fill_authored_shape` is **2000** in the current tree
   (call site 1910); 1981 is the `b13260b` line. The "1981-2010" range mixes
   revisions; use 2000 (current) or 1981 (base).
4. Grammar/duplication only: `p2-report.md:272` "the p50 ABBA mean p50 is" →
   "the ABBA-mean p50 is"; `:281-282` "with a observed round deltas are" → "the
   observed round deltas are −3,205 and +705 ms".

None of these touches a claim, a gate or a conclusion; items 1–2 are the only
wrong numbers left, and the correct values sit beside them.

## Per-claim verdicts (final)

| # | claim | verdict |
|---|---|---|
| 1 | rebased; RED authored 42/9, RED aabb 51/0, GREEN 53/0 both | **PASS** — reruns `fails=0` both modes; RED values reproduce from data + old code |
| 2 | no assertion deleted/weakened; same intent; 2 census checks | **PASS** — 51→53 executed checks, no check line removed; the three condition changes are now disclosed in `§B0-1` (z-span removed/0.198 m, top 0.01→0.10 m/0.082 m, ">8 points" replaced) |
| 3 | Mid_4x4 3/45.4°/3.51; Mid_6x8 4/67.0°/7.06; End 4 hulls ≤0.082; OldManor 3+10+box+complex | **PASS** — independently replayed (eave union-top-relative; probe prints 3.55/7.09 render-relative) |
| 4 | `COL_AUDIT` dropped=0 coverage=0.989 shapes=30901 bodies=243 | **PASS** — exact in rerun (`load_ms` differs run to run, not claimed) |
| 5 | FPS p50/p95 with per-round disclosure, not resolvable, no load direction | **PASS** — all values exact; per-round table now in the report |
| 6 | payload 258–386; aabb trimesh not larger (≈+376 adjusted); emission inseparable; no phase attribution | **PASS** — every sub-claim re-derived from the logs and the loader |

## AUDIT: PASS

All six claims are true and the four findings are substantively remediated. The
remaining defects are duplicated/stale transcription in a non-load-bearing
phase list (the corrected values are present in the same paragraph), two
notation slips in the summary/fact sheet, one mixed-revision line pointer, and
two grammar artefacts. They must be cleaned in the docs commit (fix list
above), but they do not falsify a claim, a measurement conclusion or a gate.

---

## Appendix — audit-1 evidence (still valid; code hashes unchanged)

```
ROOF_COLLISION_SUMMARY: fails=0   (authored, 53 PASS / 0 FAIL, exit 0)
ROOF_COLLISION_SUMMARY: fails=0   (TAT2_COLLISION=aabb, 53 PASS / 0 FAIL, exit 0)
```

```
COL_AUDIT mode=authored placed_meshes=947 placed_meshes_seen=947 placed_instances=27222 authored_hull=937 authored_prims=599 absent=10 no_collision=7 query_only=7 reduced=16 shapes=30901 bodies=243 dropped=0 load_ms=17112 coverage=0.989 fps_pose=n/a
```

Union replay (`mesh_collision.json`, `P(v)=(x,z,y)·0.01`, 15 %-of-run eave band,
deeper end for mirrors): `Mid_4x4` 3 hulls, AABB `(-4.142,-0.058,-3.129) →
(0.199,4.179,1.043)`, 45.44°, eave 3.51; `Mid_6x8` 4 hulls, AABB
`(-6.070,-0.086,-2.464) → (0.074,8.281,1.085)`, 67.02°, eave 7.06; End shells
4 hulls each, max union-top delta 0.082 m, eave 3.50–7.63 m; Old Manor 3 reduced
+ 10-hull + 1 box + 1 complex. Reduction 27 els; (13−1)·38 = 456 > 250; 6·45 =
225 ≤ 250. Policy census 19 / 426 (four box-policy chimneys add 20 convex
instances to the raw 23/446). Top spans 0.019 / 0.144.

Gate sweep (unchanged): `run_tests.gd` additions only (suites 101–105);
`col_shapes >= 32000` still fails (`:501`); `MAX_TOTAL_SHAPES=32000`,
`MAX_BUILDING_SHAPES=31400`, `MAX_SHAPES_PER_BODY=384`; `dropped==0` asserted by
the probe and `budget_ok=true` in all four A/B logs; no floor or baseline
touched; the roof probe is in no gate.
