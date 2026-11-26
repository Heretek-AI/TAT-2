# IMPL-C (W10-A) — D8 lock resolution + the two stale traversal fixtures

Lane: IMPL-C on W10-A. Worktree `/home/john/Projects/TAT-2-rem-w10-a` (branch
`rem/w10-a`). **No Godot process was launched by this lane** (it edits only; the
lead runs the gates). Before the first edit `pgrep -f "godot.*--path game"`
matched only a transient PID that had already exited, and a full
`ps -eo pid,cmd | grep -i godot` scan was empty; edits began after that check.

Files changed (6 + this report):

```
game/src/interact/swinging_door.gd            (D8 branch + label rename)
game/src/interact/loot_container.gd           (label rename only, no behaviour)
game/tests/test_stair_walk.gd                 (D10: per-element union)
game/tests/test_traversal_routes.gd           (D10: per-element union)
game/tests/test_w10_locks.gd                  (new: D8 branch gate)
build/qa/w10/check_lock_cdo.py                (new: fail-closed CDO gate)
build/qa/w10/impl-c.md                        (this file)
```

Nothing else was touched: `level_loader.gd`, `authored_collision.gd`, `hud.gd`,
`run_tests.gd`, `test_w9p2_locks.gd` and `game/data/**` are untouched by this
lane (the other modified files in `git status` are other lanes' work in the same
tree).

Commit note for the lead: `build/qa/*` ignores whole subdirectories, and the
`!build/qa/**/*.py` negation cannot re-include a file whose parent directory is
ignored, so both new files need `git add -f build/qa/w10/check_lock_cdo.py
build/qa/w10/impl-c.md` (same as the tracked W9 gate script/reports). The gate
script must be tracked — it is a gate, not an artifact.

Line numbers below are as of this lane's last edit. The loader lane was editing
`game/tests/test_stair_walk.gd` concurrently (the tower's `FLIGHTS` entry and
one header sentence — see §2d), so re-anchor that file's refs by content, not by
line.

---

## 1. D8 — verdict handling: NOT REPRODUCED, behaviour unchanged

`build/qa/w10/re-1-locks.md` proves the prison door is *pickable as authored*
(the dump is a delta serialisation; `CanBeLockpicked` absent ⇒ inherit ⇒ `true`,
forced by the same-class FTUE door that writes `false` explicitly, §3.2). So D8
is **not** "flip the prison door to key-only". This lane therefore only makes the
resolution explicit and testable.

### 1a. Named authored default + deliberate branch

| Item | Location |
|---|---|
| `const AUTHORED_CAN_BE_LOCKPICKED_DEFAULT: bool = true` (+ citation of re-1-locks §2, §3.2, §3.4, §7.1) | `game/src/interact/swinging_door.gd:38-51` |
| Resolution branch | `game/src/interact/swinging_door.gd:163-175` |
| Comment block on the authored gate (why absence is pickable, why key-only would be unopenable) | `game/src/interact/swinging_door.gd:138-162` |

The exact rule now in `configure()`:

```gdscript
if entry.get("locked") == true:
    var cls_name: String = str(entry.get("class", ""))
    var can_pick: bool = AUTHORED_CAN_BE_LOCKPICKED_DEFAULT   # absent flag => true
    var can_pick_v: Variant = entry.get("can_lockpick", null)
    if can_pick_v is bool:
        can_pick = bool(can_pick_v)                            # a bool is literal
    if cls_name.to_lower().find("window") >= 0:
        _note_lock_exclusion("window", cls_name)
    elif not can_pick:
        _note_lock_exclusion("unpickable", cls_name)
    else:
        var cap_lvl: int = int(entry.get("max_lock_level", 1))
        set_locked(true, clampi(cap_lvl, 1, LockableDoorScript.table_max_lock_level()))
```

Behaviour is **identical** to before for every input class:

| recorded `can_lockpick` | before | after |
|---|---|---|
| `false` (bool) | excluded (`key_only`) | excluded (`unpickable`) |
| `true` (bool) | locked at the authored cap | locked at the authored cap |
| absent / non-bool | locked at the authored cap (via `else`) | locked at the authored cap (via the named default) |

The prison door (`StaticMeshActor_528`: `locked: true`, `key_tag`, no
`can_lockpick`) therefore still locks at Lv1 and stays pickable. The difference
is that the default is now stated once, cited, and branched on, instead of being
the fallthrough of an `else`.

### 1b. Label rename `key_only` → `unpickable` (+ deprecated alias)

| Item | Location |
|---|---|
| Reason key `unpickable` used by `configure()` | `game/src/interact/swinging_door.gd:172` |
| `unpickable_exclusions()` (canonical) | `game/src/interact/swinging_door.gd:95-100` |
| `key_only_exclusions()` deprecated alias | `game/src/interact/swinging_door.gd:103-107` |
| Reason-label comment (26 of 33 explicit-false actors carry no KeyTag) | `game/src/interact/swinging_door.gd:69-77` |
| Container: `_unpickable_excluded`, `_note_unpickable_exclusion()`, `unpickable_exclusions()` | `game/src/interact/loot_container.gd:125-151` |
| Container: alias `key_only_exclusions()` | `game/src/interact/loot_container.gd:147-151` |
| Container: rule comment (flag means "cannot be picked", not "needs a key") | `game/src/interact/loot_container.gd:245-253` |

### 1c. `test_w9p2_locks.gd` compatibility argument (the file was **not** edited)

`game/tests/test_w9p2_locks.gd` reads, and still gets, exactly what it did:

| Test line | Call | Result after the rename |
|---|---|---|
| `:104`, `:107` | `loot_container.key_only_exclusions()` | alias → `unpickable_exclusions()`; same `{class: count}` dict, same values |
| `:110` | `excl_after.get(CLS) == excl_before.get(CLS) + 1` | unchanged (per-class count still increments) |
| `:127`, `:130` | `swinging_door.key_only_exclusions()` | alias → same per-class tally |
| `:133-135` | `d_excl_after.get("BP_VaultDoor_Sliding_C") == before + 1` | unchanged (the class key is unchanged; only the *reason prefix* changed) |
| `:143-145` | `door_script.lock_exclusions().get("window|BP_SM_OldManor_WindowB_4x850_C") == 1` | unchanged (`window` is a different reason and was not renamed) |

The alias is the whole compatibility shim: no test file was modified, no key that
the test reads disappeared, and `lock_exclusions()` still exposes the same raw
`reason|class` dictionary (with `unpickable|…` instead of `key_only|…`; the only
consumer of that raw dict, `:143-145`, asserts a `window|…` key).

### 1d. New branch gate — `game/tests/test_w10_locks.gd`

Standalone `SceneTree`; prints `W10_LOCKS_SUMMARY: fails=N checks=M`; exits 1 on
failure. It drives the **real** `configure()` on the **real** scripts (nodes are
created outside the tree, then freed by the fixture).

| Branch / assertion | Location |
|---|---|
| `AUTHORED_CAN_BE_LOCKPICKED_DEFAULT` is `true` in the script's constant map | `:114-119` |
| (1) `can_lockpick: false` + KeyTag ⇒ **not locked**, counter +1 under `unpickable` | `:121-132` |
| (2) `can_lockpick: false`, **no** KeyTag ⇒ same | `:134-144` |
| Label: `lock_exclusions()` has `unpickable|<class>`, not `key_only|<class>`; alias returns the same tally | `:146-160` |
| (3) absent flag + KeyTag (prison shape) ⇒ **locked, pickable, `lock_level == 1`**, not counted as excluded | `:162-172` |
| (4) absent flag, no KeyTag, `locked: true` (control) ⇒ locked at Lv1 | `:174-178` |
| (5) explicit `can_lockpick: true` ⇒ locked at the authored cap 3 | `:180-188` |
| Containers: explicit `false` ⇒ excluded + counted (+ alias); no flag ⇒ locked at the 1 minimum | `:190-209` |
| Generated record: actor `StaticMeshActor_528` → `locked == true`, `key_tag == Item.Key.Buildings.Guildhall`, **no** `can_lockpick`, **no** `max_lock_level` | `:232-242` |
| Generated record: exactly **two** `swinging_doors` entries with `"actor": "StaticMeshActor_528"`, each with the same keys (and the real entry configured once through the real consumer ⇒ locked) | `:244-271` |
| Printed (NOT asserted): authored `doors.max_lock_level = 4` vs the port's Lv1, naming the adjacent incomplete-input defect (§7.2) | `:273-282` |

The generated-record half is what pins the *input* the runtime consumes: the
record carries `locked` + `key_tag` and **no** cap, so the port locks at 1. The
authored cap is 4 and is printed only — changing the level is a documented,
player-visible decision for the lead (re-1-locks.md §7.2 options 1/2), not a side
effect of D8.

### 1e. CDO gate — `build/qa/w10/check_lock_cdo.py`

Plain `python3` (stdlib only, no deps), `python3 -m py_compile` clean, ~3.5 s.

What it does: one pass over `extracted/json/**`; every
`BlueprintGeneratedClass` whose CDO owns a `_lockConfig` is walked through
`Super` (`ObjectPath`) / `SuperStruct` (native tail) and resolved to the
**nearest explicit** `CanBeLockpicked`. Placements are every object in
`extracted/json/Maps/**` whose `Properties` carry `_lockConfig`; a placement's
class comes from its `Template` object path. The expectations are in the script
(`EXPECTED_*`, lines 58-71), never read from the dump's own summary.

Assertions (terminate non-zero on any violation):

1. `classes with a CDO _lockConfig` == 31.
2. Exactly one class resolves `false` → `BP_SlidingWindow_Base_C`, and it has
   **zero** direct placements in `Maps/**`.
3. Every placed actor that resolves `false` authors it **explicitly** on the
   instance (0 inherited-false placements).
4. Explicit author census: 34 `false` (33 placed + 1 CDO) and 3 `true`.
5. `StaticMeshActor_528` (Guildhall POI): exactly one object, `_locked: true`,
   `KeyTag.TagName == Item.Key.Buildings.Guildhall`, `CanBeLockpicked` **absent**.

Header states explicitly that this proves the **resolved value**, not the
unreadable C++ initialiser (no `/Script` package is dumped), citing
`re-1-locks.md` §2-§3 (§3.2 the decisive FTUE door, §3.4 the missing native
package).

Expected output — **actually run in this worktree** (exit 0):

```
LOCK_CDO: classes with a CDO _lockConfig = 31
LOCK_CDO: explicit CanBeLockpicked authors = 34 false / 3 true (33 placed false + 1 CDO false; 0 placed true + 3 CDO true)
LOCK_CDO: resolved false classes = ['BP_SlidingWindow_Base_C'] (direct placements 0); resolved true = 3; unresolved tail (native default) = 27
LOCK_CDO: placed lock actors = 288; explicit false = 33; resolved false = 33
LOCK_CDO: StaticMeshActor_528 _locked=True key_tag=Item.Key.Buildings.Guildhall CanBeLockpicked_present=False
LOCK_CDO PASS classes=31 explicit_false=34 one_false_class=BP_SlidingWindow_Base_C placed_false=33/33
```

Negative controls (run against synthetic trees, exit codes verified):
a fake class that resolves `false` with a placed actor inheriting it produces
`LOCK_CDO FAIL: … 1 placed actor(s) resolve false by INHERITANCE …` and exit 1;
a missing dump exits 2 with an actionable message. Fail-closed in both
directions.

---

## 2. D10 — the two stale traversal fixtures

### 2a. Root cause (confirmed from the data, no Godot)

`level_loader._get_mesh_and_shape()` returns `shapes` + `shape_offsets` (one per
authored UE `AggGeom` element) and also `shape` as a **single-shape compatibility
field** = `shapes[0]` (`level_loader.gd:2015-2028`). Both stale fixtures built
their body from `info["shape"]` only. Counts below are read from
`game/data/generated/mesh_collision.json`:

| Mesh | authored elements | `resolve()` result with n=1 | old fixture outcome |
|---|---:|---|---|
| `SM_Stairs_Civic_3x150cm` | 1 convex | 1 hull | aborted: "no trimesh collider" |
| `SM_Stairs_Industrial_3x150cm` | 1 convex | 1 hull | aborted |
| `SM_StairsCity6x2m` | 1 convex | 1 hull | aborted |
| `SM_Stairs_Civic_3x850cm` | 1 convex | 1 hull | aborted |
| `SM_OldManor_Tower_Stairs_4x850` | **36** convex | **36 hulls**, `reduced = false` (W10-A D10 stair exemption, `authored_collision.gd:370-379`) | walked one coalesced AABB trimesh and failed (§2d) |
| `SM_RoofUrban_Ext_Mid_4x4` | 3 convex | 3 hulls | walked hull 0 only |
| `SM_RoofUrbanB_Ext_Mid_6x8` | 4 convex | 4 hulls | walked hull 0 only |
| `ROOFUrban_Ext_EndA/EndB/EndB_Mirror_2x4x4` | 4 convex each | 4 hulls | walked hull 0 only |

The six single-hull stair flights are authored as **wedge ramps**: the baked hull
points give a rise/run of 1.584 m / 2.143 m (36.5°), 1.584 / 2.132 (36.6°),
2.000 / 3.900 (27.1°) and 8.509 / 10.047 (40.3°) — all inside the authored 60°
walkable angle, and each rise exceeds the flight's `min_ascent`. That is why a
per-element fixture is expected to walk them (prediction, not a run — see §2d).

### 2b. `game/tests/test_stair_walk.gd`

| Item | Location |
|---|---|
| Header rewritten: "authored per-element union", old trimesh claim removed, element counts named | `:1-38` |
| `FLIGHTS` gains `authored_elements` / `reduced` per flight (1 × 6, and 36 for the tower) | `:41-95` |
| `_walk_flight()` builds the union, asserts it, then one `CollisionShape3D` per element at `rot * offset` with the shipped scale on the shape (same treatment as before) | `:159-214` |
| Scaffolding AABB from the union point set (frame-local, `basis * (p * scale)`) | `:215-224` |
| `_authored_union()` | `:435-470` |
| `_shape_points()` + `_points_aabb()` (copied from `test_roof_collision.gd`) | `:477-518` |
| `_check_union_count()` — authored element count, reduction flag, emitted shape count and shape family | `:527-551` |

The count assertion is what stops "one hull of many" returning: for a non-reduced
flight the emitted shape count must **equal** the authored element count
(`1` for the six, `36` for the tower) and **every** emitted shape must be a
`ConvexPolygonShape3D`; for a reduced one it must be exactly **one**
`ConcavePolygonShape3D`. A future regression that hands a 3-element mesh to the
stair fixture fails here instead of silently walking a third of it. All existing
assertions are kept unchanged (ascent/grounded per flight, rise/step metrics,
max zero streak, drift, camera settle, descent, wardrobe prompt + LOS negative,
`INTERACT_RANGE`, 35° ramp not stepped).

Note the union shape count is asserted against `info["col"]["elements"]`, which
`resolve()` reports as the **pre-D7-skip** element count. That is correct for
these meshes (no coplanar convex element among stairs/roofs), but it is the
reason the assertion compares `col.elements` rather than `shapes.size()` alone.

### 2c. `game/tests/test_traversal_routes.gd`

| Item | Location |
|---|---|
| Header rewritten with the per-element union statement | `:12-22` |
| `_authored_union()` (shapes/offsets/elements/reduced/source) | `:599-624` |
| `_make_roof()` builds every element at its own offset (same body-scale treatment as before) and asserts `elements == 3 or 4`, `shapes.size() == elements`, all `ConvexPolygonShape3D` (or the reduced trimesh) | `:627-681` |
| Non-uniform pitch assertion re-based on the unit-scale union's measured pitch | `:893-920` |

The sampling scaffold deliberately stays the **render-mesh AABB**: every height
assertion in this suite is written against the authored render `top` (the plateau
the old box collider floated), and switching the grid footprint to the union AABB
would silently re-tune all of them. The collider is the union; the scaffold is
unchanged. (The stair fixture, whose scaffold *is* the collider, does derive it
from the union points as specified: `_shape_points()`/`_points_aabb()` live in
`test_stair_walk.gd:475-520`; adding them here would have produced a point set the
roof code never reads.)

**One expectation was changed, with written evidence** (AGENTS rule 3, "the
assertion itself was wrong"): the non-uniform POI pitch check hardcoded
`atan(tan(45.2°)/0.8)` = 51.5°. `_roof_field_pitch()` returns the *steepest
sampled pair over the whole union*, not hull 1's authored 45.4° face:
`build/qa/w10/inv-2-runtime.md` §B measured 51.8° at unit scale and 57.9° at
`[1,1,0.8]` — i.e. the old expectation measured a face the metric never reports
and "cannot pass with any hull count". The assertion now compares the scaled
measurement against `atan(tan(unit_pitch)/0.8)`, where `unit_pitch` is the
*same* union's unit-scale measurement: same intent (the collider follows the
instance scale), no hardcoded face, strictly self-consistent (57.9 vs 57.75
expected with the INV-2 numbers, tolerance 2.5°).

### 2d. Predicted gate state (NOT verified — this lane ran no Godot)

| Suite | Before (`inv-2-runtime.md`) | Predicted after | Basis |
|---|---|---|---|
| `test_stair_walk.gd` | `fails=13` (six aborts + six grounded cascades + tower walk) | **`fails=0`** | six ramps 27-40° < 60° and rise ≥ `min_ascent`; the tower now emits its 36 authored hulls (stair exemption, §2d-note) with a 10.34 m union rise, so the 8.4 m target is reachable |
| `test_traversal_routes.gd` | `fails=4` | **`fails=2`** (steep refusal, non-uniform ascent) | hip fixed by the union (eave 1.92 → 0.72 m, INV-2 §B); pitch fixed by the re-based expectation |

Note on the tower: while this lane was writing the fixture, the loader lane landed
the source fix — `authored_collision.gd:370-379` exempts meshes whose path
contains `stair` from `MAX_CONVEX_ELEMENTS_PER_MESH`, so
`SM_OldManor_Tower_Stairs_4x850` emits 36 per-element hulls (`reduced = false`)
instead of one coalesced AABB trimesh. The same lane also updated that flight's
`FLIGHTS` entry/comment in `test_stair_walk.gd` (`"reduced": false`) and the
header sentence; this lane's `_authored_union`/`_check_union_count`/collider
builder are generic (`shapes.size() == authored_elements` for a non-reduced
flight) and needed no change. That removes the residual tower defect this report
would otherwise have listed.

Residual reds, both **pre-existing and not caused by this lane**, and neither
fixable inside this lane's file set:

1. **Steep-roof refusal** — `SM_RoofUrbanB_Ext_Mid_6x8` measures 74.0° and the
   body mantles it: `ascent 3.42 m` with `mantle=true` (INV-2 red log). The union
   raises sample coverage 15 → 25 and moves the eave 4.37 → 1.33 m but leaves the
   pitch and the mantle unchanged, so the refusal verdict must be re-measured (and
   possibly re-decided with the mantle guard) outside this lane.
2. **Non-uniform POI roof walk** — `ascent 0.78 m` against
   `ROOF_MIN_WALKABLE_ASCENT_M = 0.8` at a 57.9° measured pitch. INV-2 §B
   measured the sampled field at `[1,1,0.8]` to be identical for one hull and all
   hulls, so the union does not move this number. It is a threshold miss on a
   near-limit roof, not a fixture bug; changing the threshold would be a
   weakening, so it is left to the lead.

---

## 3. Re-derivation (no Godot)

```bash
# D8 CDO gate (exit 0, prints the PASS line in §1e)
python3 build/qa/w10/check_lock_cdo.py
python3 -m py_compile build/qa/w10/check_lock_cdo.py

# authored element counts / hull ramps quoted in §2a (read the generated data)
python3 - <<'EOF'
import json
d = json.load(open('game/data/generated/mesh_collision.json'))['meshes']
for p in ["/Game/Art/Environment/Civic/Stairs/SM_Stairs_Civic_3x150cm",
          "/Game/Art/Environment/Urban/Industrial/Stairs/SM_Stairs_Industrial_3x150cm",
          "/Game/Art/Environment/City/Architecture/Stairs/2m/SM_StairsCity6x2m",
          "/Game/Art/Environment/Civic/Stairs/SM_Stairs_Civic_3x850cm",
          "/Game/Art/Environment/OldManor/SM_OldManor_Tower_Stairs_4x850",
          "/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_Mid_4x4",
          "/Game/Art/Environment/Urban/Roofs/SM_RoofUrbanB_Ext_Mid_6x8"]:
    print(p.split('/')[-1], len(d[p]['elements']), [e['type'] for e in d[p]['elements']])
EOF

# the generated record the runtime consumes (actor + two pivots, no cap)
python3 -c "
import json; d=json.load(open('game/data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI.tatlevel.json'))
print([a for a in d['actors'] if a['name']=='StaticMeshActor_528'])
print(len([s for s in d['swinging_doors'] if s.get('actor')=='StaticMeshActor_528']))"
```

Gate runs are the lead's (each under
`flock /tmp/opencode/tat2-godot.lock`):

```bash
tools/godot --headless --path game --script res://tests/test_w10_locks.gd       # W10_LOCKS_SUMMARY: fails=0
tools/godot --headless --path game --script res://tests/test_w9p2_locks.gd      # unchanged, must stay fails=0
tools/godot --headless --path game --script res://tests/test_stair_walk.gd      # see §2d
tools/godot --headless --path game --script res://tests/test_traversal_routes.gd
tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"
```
