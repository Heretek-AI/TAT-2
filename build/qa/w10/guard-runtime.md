# Guard spawn — runtime diagnostic (Contract 02, Guildhall)

Diagnostic-only lane: no gameplay, selection, count, grounding or visual change.
Every number below is copied from the run in this worktree (raw log
`build/qa/w10/guard-diag.log`, 143 lines). Nothing is inferred from the source.

| | |
|---|---|
| worktree | `/home/john/Projects/TAT-2-rem-w10-guards`, branch `rem/w10-guards` |
| HEAD | `04d2e15` + uncommitted diagnostic (1 file, +125 lines, 0 deletions) |
| Godot | 4.7.2.stable headless, one process at a time under `flock /tmp/opencode/tat2-godot.lock` |
| mission | `Mission.Guildhall.VaultHeist` hosted on Contract 2 (`--qa-mission`, no `--qa-free-play`) |
| raw log | `build/qa/w10/guard-diag.log` (run 2: candidate-pool fields added) |

## Change under test

`game/src/missions/mission_controller.gd`, `_spawn_guards()` only:

- before the spawn loop, one `GUARD_DIAG candidates=<n> guard_scene_elements=<n>
  smart_objects=<n>` line (missing/wrong-typed `level_stats` keys count as 0) and
  a local `diag_scene` list of `scene_element_spawns` records with `kind=="guard"`;
- an `if OS.get_environment("TAT2_GUARD_DIAG") == "1":` block **after
  `add_child(g)`** that prints one `GUARD_DIAG` line per guard (marker, grounded,
  delta/moved, mesh count, global mesh AABB union, down/up rays from
  `global_position + 0.10`, a separate 4 m floor ray under the **marker**, and
  `src_name`/`src_class` from the `scene_element_spawns` guard record whose `pos`
  matches the marker within 0.01 m on all three axes, else `-`);
- one `GUARD_DIAG total=<n>` after the loop;
- helper `_diag_ray()`, called only from inside the gated block.

`git diff --stat` → `1 file changed, 125 insertions(+)`, 0 deletions. With the
env var unset the only executed additions are inert locals (`diag_scene` empty,
counter, declarations); no side effects outside the blocks.

## The run

**Claim:** a real Contract 02 boot reaches `mission_ready` and spawns the
Novice squad with the diagnostic on.

**Command** (exact, from the worktree root):

```bash
mkdir -p build/qa/w10
flock /tmp/opencode/tat2-godot.lock -c 'TAT2_GUARD_DIAG=1 timeout 45 tools/godot --headless --path game -- --qa-mission=Mission.Guildhall.VaultHeist' \
  > build/qa/w10/guard-diag.log 2>&1
```

**Output:**

- exit code **124** (the `timeout`, the expected termination);
- `TAT-2 QA autostart contract=2 map=guildhall mission=Mission.Guildhall.VaultHeist free_play=false`
- `TAT-2 mission_ready map=guildhall meshes=63100 lights=160 chunks=6015`
- `grep -c GUARD_DIAG` → **6** (1 candidate line + 4 guards + total);
  `moved=true` ×4, `moved=false` ×0;
- `grep -c 'SCRIPT ERROR'` → **0**; `grep -c 'ERROR:'` → **0**;
- no missing-texture / import-cache line, so no `--import` was needed.

**Verdict:** the requested boot form works; the mission id did not need the
`--qa-free-play` fallback. Run 2 reproduces run 1's spawn geometry exactly
(same markers, grounded positions, AABBs and ray hits).

## GUARD_DIAG output (verbatim)

```
GUARD_DIAG candidates=119 guard_scene_elements=119 smart_objects=800
GUARD_DIAG idx=0 name=Guard_ClubLantern_0 marker=(39.599,36.500,-13.880) grounded=(39.599,44.202,-13.880) delta=7.70 moved=true meshes=4 aabb_min=(38.659,44.203,-14.371) aabb_max=(40.539,46.522,-13.590) down={hit=1 pos=(39.599,44.052,-13.880) collider=LevelCollision_1_-1_3 parent=Mission meta_ue_mesh=- meta_key=- dy=-0.15} up={hit=0} floor_hit=1 floor=(39.599,35.533,-13.880) src_name=BP_MissionSpawner_Character_C_100 src_class=BP_MissionSpawner_Character_C
GUARD_DIAG idx=1 name=Guard_1 marker=(34.299,36.650,-4.980) grounded=(34.299,44.202,-4.980) delta=7.55 moved=true meshes=3 aabb_min=(33.359,44.203,-5.352) aabb_max=(35.239,46.522,-4.690) down={hit=1 pos=(34.299,44.052,-4.980) collider=LevelCollision_1_-1_3 parent=Mission meta_ue_mesh=- meta_key=- dy=-0.15} up={hit=0} floor_hit=1 floor=(34.299,35.533,-4.980) src_name=BP_MissionSpawner_Character_C_101 src_class=BP_MissionSpawner_Character_C
GUARD_DIAG idx=2 name=Guard_ClubLantern_2 marker=(9.449,37.850,-10.980) grounded=(9.449,36.650,-10.980) delta=1.20 moved=true meshes=4 aabb_min=(8.509,36.651,-11.471) aabb_max=(10.389,38.970,-10.690) down={hit=1 pos=(9.449,36.500,-10.980) collider=LevelCollision_0_-1_2 parent=Mission meta_ue_mesh=- meta_key=- dy=-0.15} up={hit=0} floor_hit=1 floor=(9.449,36.500,-10.980) src_name=BP_MissionSpawner_Character_C_102 src_class=BP_MissionSpawner_Character_C
GUARD_DIAG idx=3 name=Guard_3 marker=(49.249,46.315,-35.930) grounded=(49.249,45.202,-35.930) delta=1.11 moved=true meshes=2 aabb_min=(48.309,45.203,-36.302) aabb_max=(50.189,47.522,-35.640) down={hit=1 pos=(49.249,45.052,-35.930) collider=LevelCollision_1_-2_3 parent=Mission meta_ue_mesh=- meta_key=- dy=-0.15} up={hit=0} floor_hit=1 floor=(49.249,45.052,-35.930) src_name=BP_MissionSpawner_Character_C_114 src_class=BP_MissionSpawner_Character_C
GUARD_DIAG total=4
```

Derived from those lines (reproduce with the parser below; `down_dy` is the
guard's own down ray, `g-floor` is grounded minus the floor under the marker):

```
idx  src_name                            src_class                    marker_y  ground_y  g-marker  floor_y  g-floor  down_y  down_dy  up  aabb_h  meshes
0    BP_MissionSpawner_Character_C_100   BP_MissionSpawner_Character_C   36.500    44.202    +7.702   35.533   +8.669  44.052    -0.15   0   2.319       4
1    BP_MissionSpawner_Character_C_101   BP_MissionSpawner_Character_C   36.650    44.202    +7.552   35.533   +8.669  44.052    -0.15   0   2.319       3
2    BP_MissionSpawner_Character_C_102   BP_MissionSpawner_Character_C   37.850    36.650    -1.200   36.500   +0.150  36.500    -0.15   0   2.319       4
3    BP_MissionSpawner_Character_C_114   BP_MissionSpawner_Character_C   46.315    45.202    -1.113   45.052   +0.150  45.052    -0.15   0   2.319       2
```

<details><summary>parser used</summary>

```python
import re
pat = re.compile(
    r"idx=(?P<idx>\d+).*marker=\((?P<mx>[-\d.]+),(?P<my>[-\d.]+),(?P<mz>[-\d.]+)\)"
    r".*grounded=\((?P<gx>[-\d.]+),(?P<gy>[-\d.]+),(?P<gz>[-\d.]+)\)"
    r".*delta=(?P<delta>[-\d.]+).*meshes=(?P<meshes>\d+)"
    r".*aabb_min=\([-\d.]+,(?P<amin_y>[-\d.]+),[-\d.]+\).*aabb_max=\([-\d.]+,(?P<amax_y>[-\d.]+),[-\d.]+\)"
    r".*down=\{hit=(?P<down_hit>\d).*?pos=\([-\d.]+,(?P<down_y>[-\d.]+),[-\d.]+\).*dy=(?P<down_dy>[-\d.]+)\}"
    r" up=\{hit=(?P<up_hit>\d).*floor_hit=(?P<floor_hit>\d) floor=\([-\d.]+,(?P<floor_y>[-\d.]+),[-\d.]+\)"
    r" src_name=(?P<src_name>\S+) src_class=(?P<src_class>\S+)")
for line in open("build/qa/w10/guard-diag.log"):
    m = pat.search(line)
    if not m:
        continue
    d = {k: float(v) for k, v in m.groupdict().items()
         if k not in ("src_name", "src_class")}
    g = m.groupdict()
    print(int(d["idx"]), g["src_name"], g["src_class"], d["my"], d["gy"],
          round(d["gy"] - d["my"], 3), d["floor_y"],
          round(d["gy"] - d["floor_y"], 3), d["down_y"], d["down_dy"],
          int(d["up_hit"]), round(d["amax_y"] - d["amin_y"], 3), int(d["meshes"]))
```

</details>

## Candidate pool — is `_spawn_guards` contaminated by SmartObject posts?

**Claim (lead):** the raw guard rows are 916 (800
`BP_SmartObject_GuardDefensiveLocation_C` + 116
`BP_MissionSpawner_Character_C`), the loader routes `SmartObject` first, and
`smart_objects` is never consumed — so `_spawn_guards` may be receiving posts.

**Command:** the `GUARD_DIAG candidates=` line (runtime), plus a read-only
count of the authored rows for cross-check:

```bash
python3 - <<'PY'
import json
from collections import Counter
p = "game/data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json"
d = json.load(open(p))
rows = [r for r in d.get("spawn_elements", []) if r.get("kind") == "guard"]
print(len(rows), dict(Counter(r.get("class", "") for r in rows)))
PY
```

**Output:**

- runtime: `candidates=119 guard_scene_elements=119 smart_objects=800`;
- authored `Guildhall_Gameplay.tatlevel.json`: `916 {'BP_MissionSpawner_Character_C': 116, 'BP_SmartObject_GuardDefensiveLocation_C': 800}`
  (identical class counts on that file's `markers` array, which is what the
  loader actually parses: 116 + 800);
- all four chosen markers are `src_class=BP_MissionSpawner_Character_C`
  (`_100`, `_101`, `_102`, `_114`), none is a post;
- `guard_scene_elements == candidates` (119 = 119): `_note_scene_element(...,
  "guard", ...)` fires on exactly the rows that enter `guard_spawns`.

**Verdict:** **the SmartObject contamination is not in `_spawn_guards`.**
`candidates` is **119**, not 916: the 800 posts are excluded into
`smart_objects` (`smart_objects=800` matches the authored count exactly), and no
selected guard is a post. It is also **not 116**: the pool has 3 more rows than
`Guildhall_Gameplay` authors, from the loaded `Guildhall_SkyboxGeo` sublevel —
2 `BP_AirshipGuard_Patrol_C` + 1 `BP_AirshipGuard_Swarm_C`
(authored positions `(-1163.839, 178.160, -806.849)`,
`(-194.441, 394.096, 678.888)`, `(340.731, 122.000, -319.670)`). They are in the
candidate array but 1,000+ m away and 96+ m above the player anchor
(`127.275, 26.469, -5.330`), so the 10–120 m annulus rejects them in this run;
this log cannot say what happens on a map where they fall inside it. The +3 is
arithmetic from the two loaded sublevels' JSON (only files with guard-class
markers in the Guildhall set) plus the runtime total; the diagnostic prints
`src_name`/`src_class` only for the rows it spawns.

## H1 — does `_ground_position` land the guard on a ceiling/upper slab?

**Claim:** the first hit of the ingest ray (`pos + (0,8,0)` → `pos + (0,-30,0)`,
mask 1) is the slab above the marker, so the guard is placed in the storey
above instead of the marker's room.

**Command:** the log lines above; mechanism from
`game/src/missions/mission_controller.gd` (`_ground_position(pos, 8.0, 30.0, 0.15)`).

**Output:**

- idx 0: marker y `36.500`, ingest start `marker+8 = 44.500`, first hit
  y `44.052` (0.448 m below the start) → grounded y `44.202`, **+7.702 m above
  the marker**. Floor under the marker is `35.533`, so the guard is **+8.669 m
  above the surface below its own marker**.
- idx 1: same slab (`44.052`), ingest start `44.650`, grounded `44.202`,
  **+7.552 m above the marker**, +8.669 m above the marker's floor.
- idx 2: marker y `37.850`, floor under marker `36.500`, grounded `36.650` —
  the ingest ray reached the real floor (nothing in the column) and the guard
  is **1.200 m below the marker**, +0.150 m above the floor.
- idx 3: marker y `46.315`, floor under marker `45.052`, grounded `45.202` —
  **1.113 m below the marker**, +0.150 m above the floor.
- All four guards: `down={hit=1 ... dy=-0.15}` against the same surface
  `grounded.y - 0.15`, i.e. each guard rests on the surface the ingest ray
  selected (self-consistent, no falling through).
- All four: `up={hit=0}` (no collision surface within 6 m above the guard).

**Verdict:** **H1 mechanism confirmed for 2 of 4 guards, and only as a
displacement to the storey above — not as an embedded guard.** For idx 0/1 the
ingest ray begins 0.448 m / 0.598 m *above* the `44.052` slab top, so its first
hit is that slab and the guard is placed on the slab's upper face — 7.552 m /
7.402 m above its marker, and 8.519 m above the floor under that marker. The
down/up pair shows 0.10 m clearance below and ≥6 m open above, so the guard
stands **on top of** the slab (in whatever space is above it), not inside it.
Which storey or void that space is cannot be decided from this log.

For idx 2/3 there is no obstruction in the marker's column, so the ingest ray
reaches the true floor and the guard is placed correctly (+0.150 m). Their
`delta` is the authored marker floating 1.350 m / 1.263 m above that floor —
a separate observation, not the ceiling mechanism.

Note the ingest start for idx 0 is only 0.448 m above the slab that captures it:
an 8 m up-start is above the storey ceiling for these columns. That is the
measured cause; the fix direction is not evaluated here.

## H2 — is the guard body present and sane?

**Claim:** the guard has no visual, or a degenerate one.

**Command:** `meshes=` and the AABB fields of the lines above.

**Output:**

- `meshes` = 4 / 3 / 4 / 2 (never 0, `aabb=none` never printed).
- Global AABB height = **2.319 m** for all four; bottom = `grounded.y + 0.001`
  (`44.203` vs `44.202`, `36.651` vs `36.650`, `45.203` vs `45.202`).
- AABB XZ extents 1.880 m × 0.662–0.781 m, centred within ±0.5 m of the
  guard origin (e.g. idx 0 x 38.659..40.539 around 39.599).

**Verdict:** **H2 rejected as the cause of the four guards not being seen.** Each
spawned guard has 2–4 MeshInstance3D children and a human-scale 2.32 m AABB
resting on the selected ground, not a zero-size or detached visual. Caveat: a
skinned GLB's `mesh.get_aabb()` is the rest-pose AABB; this proves the meshes
exist at human scale, not that they were on screen.

## H3 — did any guard disappear?

**Claim:** fewer than 4 guards exist after spawning.

**Command:** `GUARD_DIAG total=4` vs the Novice limit
(`_spawn_guards`: `limit = 4` for `GameState.Difficulty.NOVICE`).

**Output:** `total=4`, with four distinct names
(`Guard_ClubLantern_0`, `Guard_1`, `Guard_ClubLantern_2`, `Guard_3`). No
`SCRIPT ERROR`/`ERROR:` line mentions a guard. Two `WARNING`s carry `guard_ai.gd`
frames and are both authored-data/degradation warnings, not failures:
`[hearing_data] 5 authored investigation-range anomalies clamped` (raised from
guard `_ready` → `_apply_authored_escalation`) and
`[nav_steering] no synchronised navigation map ... AI uses straight-line steering`
(raised from a guard's `_move_ai` in `_physics_process`, i.e. a guard was alive
and processing at the timeout). `guard_ai.gd` has no `queue_free()` of the guard
itself (only `head_inst` and `_carried_node`).

**Verdict:** **H3 negative at spawn time** — all four selected markers produced
a guard and none was dropped. Long-run disappearance is **not verified**: the 45 s
window was mostly level load (`mission_ready` is log line 136 of 143), so only
7 log lines of runtime follow the spawn.

## Limitations (what this log cannot say)

- `meta_ue_mesh=-` for every hit is expected, not a missing tag: the ray
  collider is a merged 32 m `LevelCollision_<cx>_<cy>_<bucket>` `StaticBody3D`,
  and `level_loader.gd:4240` puts `ue_mesh` on its child `CollisionShape3D`, not
  on the body or the body's parent. Naming the `44.052` slab's UE mesh needs a
  child-shape probe or `surface_resolver` (not in this diagnostic's contract).
- One run, spawn instant only: guard positions/visibility later in the mission
  were not sampled.
- The log records the four chosen markers and the pool size; it does not list
  every candidate, so the 3 skybox rows are identified by JSON arithmetic, not
  by a printed record.
- `candidates` includes all loaded sublevels' guard-class markers; it is not a
  per-file count.
