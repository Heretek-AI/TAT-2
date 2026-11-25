# W9-P2 B2 — producer contract for authored locks (contract only, no tree edit)

**Status:** contract + patch snippet. `tools/parse_tables.py` is **not** edited on
this branch (`git diff -- tools/parse_tables.py` is empty). Rationale: `make audit`
is a phase gate that fails closed when a producer's sha256 changes without a
regeneration, and regeneration writes the shared, read-only generated data
(`game/data/generated` is the main checkout's directory, symlinked here — see
`AGENTS.md` "The symlinked data tree is read-only for workers"). The integrator
applies this patch at merged HEAD, runs the producer, and refreshes the audit
baseline.

Consequence for this lane: the **consumer** half ships and is proven with
synthetic records (`game/tests/test_w9p2_locks.gd`), while the **runtime
application is BLOCKED-ON-INTEGRATOR-REGENERATION**: `locked_now=0` in the
committed `.tatlevel.json` files until then.

Reference HEAD: `b13260b` (`docs(w9): P1 report — ratchet target and the docs owed at integration`).
Line numbers are that file's lines; nothing else in this lane touches it.

---

## 1. Emission sites (file:line at HEAD)

| Site | Function / lines | Dict to extend |
|---|---|---|
| auth helper (new) | `extract_levels`' module scope, after `_scene_requirement_tag` (`:1121-1130`), before `_scene_element_kind` (`:1132`) | `_authored_lock_fields(props)` |
| swinging doors | door pre-pass `:1781-2038`; owning actor resolved at `aidx = actor_by_name.get(actor_name)` `:1812`; record `swinging_doors.append(...)` `:2026-2037` | add `door_actor_props` + the helper spread |
| gameplay markers | branch `# 4. Gameplay markers` `:2245`; `marker_rec` `:2314-2321`; `markers.append` `:2322` | `props` is the actor's `Properties` (the branch iterates placed actors, e.g. `BP_ChestTrunk_MajorLoot_C_0`) |
| generic actors | branch `# 4b. Generic actor capture` `:2337`; `actors.append(...)` `:2369-2381` | same `props` |

The source actor is the record itself in the marker/actor branches and
`exps[aidx]` in the door pre-pass — **not** the pivot component and not
`RootComponent` (verified on `Guildhall_Loot.json:5210` actor
`BP_ChestTrunk_MajorLoot_C_0` and on the two OldManor door owner actors, §4).

## 2. Source fields → emitted keys

| Source (on the placed actor's `Properties`) | Type | Emitted key | Rule |
|---|---|---|---|
| `_locked` | bool | `locked` | emit only when the key exists |
| `_lockConfig.MaxLockLevel` | int | `max_lock_level` | emit only when the key exists; it is a **cap**, never renamed `lock_level` |
| `_lockConfig.MinLockLevel` | int | `min_lock_level` | emit only when the key exists |
| `_lockConfig.CanBeLockpicked` | bool | `can_lockpick` | emit only when the key exists (`37` raw; all `33` placed values are `false`) |
| `_lockConfig.KeyTag.TagName` | string | `key_tag` | emit when present and not `""`/`None` |

**Absence rule (non-negotiable):** a key is absent when the source actor does not
author it. Never default `locked=false` or `max_lock_level=0` in the producer —
absence must mean "no authored lock data", so the consumer's unlocked default
applies and a class-default (`RF_ClassDefaultObject`) `_locked` can never leak
into a placed record. Do not infer `locked` from `MaxLockLevel`/`MinLockLevel`:
15 of the 173 locked actors carry no cap and 19 placed actors carry a cap while
unlocked.

Corresponding consumer keys (`game/src/core/level_loader.gd`
`MARKER_LOCK_KEYS` / `marker_lock_fields`, `loot_container.configure`,
`swinging_door.configure`) read exactly: `locked`, `max_lock_level`,
`min_lock_level`, `can_lockpick`, `key_tag`.

## 3. Patch (unified diff, applies clean to HEAD)

Verified by copying `tools/parse_tables.py` to `/tmp`, applying this diff and
running `python3 -m py_compile` (OK). Apply with `git apply` from the repo root.

```diff
--- a/tools/parse_tables.py
+++ b/tools/parse_tables.py
@@ -1129,6 +1129,35 @@
     return ""
 
 
+def _authored_lock_fields(props: dict) -> dict:
+    """Authored lock state carried 1:1 from a placed actor's Properties.
+
+    W9-P2 producer contract. ``_locked`` is the only per-instance lock flag and
+    ``_lockConfig.MaxLockLevel`` / ``MinLockLevel`` are caps, not a concrete
+    level (no ``LockLevel`` key exists anywhere in the dump). Keys are emitted
+    only when the source actor authors them: absence means "this actor has no
+    authored lock data", never "unlocked at level 0". ``CanBeLockpicked`` is
+    read from ``_lockConfig`` only; ``KeyTag.TagName`` becomes ``key_tag``.
+    """
+    out = {}
+    if "_locked" in props:
+        out["locked"] = bool(props.get("_locked"))
+    cfg = props.get("_lockConfig")
+    if isinstance(cfg, dict):
+        if "MaxLockLevel" in cfg:
+            out["max_lock_level"] = int(cfg.get("MaxLockLevel") or 0)
+        if "MinLockLevel" in cfg:
+            out["min_lock_level"] = int(cfg.get("MinLockLevel") or 0)
+        if "CanBeLockpicked" in cfg:
+            out["can_lockpick"] = bool(cfg.get("CanBeLockpicked"))
+        key_tag = cfg.get("KeyTag")
+        if isinstance(key_tag, dict):
+            tag = key_tag.get("TagName") or ""
+            if tag and tag != "None":
+                out["key_tag"] = tag
+    return out
+
+
 def _scene_element_kind(cls: str) -> str:
     if "MissionSpawner_Character" in cls or "Guard" in cls:
         return "guard"
@@ -2023,6 +2052,11 @@
                     continue
             for q in pend_idx:
                 door_leaf_idx.add(q)
+            # W9-P2: the authored lock lives on the owning actor, not on the
+            # pivot component (aidx is resolved above for the scene tag/group).
+            door_actor_props = (
+                (exps[aidx].get("Properties") or {}) if aidx is not None else {}
+            )
             swinging_doors.append(
                 {
                     "name": f"{actor_name}.{pname}",
@@ -2031,6 +2065,7 @@
                     "pos": pgt["pos"],
                     "basis": pgt["basis"],
                     "leaves": leaves,
+                    **_authored_lock_fields(door_actor_props),
                     "source": dsrc,
                     **({"element_tag": door_tag} if door_tag else {}),
                     **({"spawn_group": door_group} if door_group else {}),
@@ -2315,6 +2350,7 @@
                     "name": e.get("Name", ""),
                     "class": et,
                     **trs,
+                    **_authored_lock_fields(props),
                     "source": str(rel),
                     **({"scene_requirement": scene_tag} if scene_tag else {}),
                     **({"spawn_group": spawn_group} if spawn_group else {}),
@@ -2371,6 +2407,7 @@
                         "name": e.get("Name", ""),
                         "class": et,
                         **ue_mat4_to_godot_trs(wmat2),
+                        **_authored_lock_fields(props),
                         **(
                             {"tags": props.get("Tags")}
                             if isinstance(props.get("Tags"), list) and props.get("Tags")
```

## 4. Read-only verification (this lane, no producer run)

### 4.1 The patched helper, executed against the real dump

The patched file was imported from `/tmp` and `_authored_lock_fields()` was
called on every placed actor (`Outer.ObjectName` starts `Level'`). Exact output:

```text
== _authored_lock_fields() on Guildhall_Loot placed actors ==
   BP_ChestTrunk_MajorLoot_C locked=True max=2: 48
   BP_DisplayCaseA_MajorLoot_C locked=True max=2: 31
   BP_Manor_Bookcase_Cabinet_MinorLoot_C locked=None max=1: 4
   BP_Manor_Bookcase_Cabinet_MinorLoot_C locked=None max=None: 4
   BP_SmallSafe_MajorLoot_C locked=True max=2: 8
   key sets: {('locked', 'max_lock_level'): 87, ('max_lock_level',): 4, ('min_lock_level',): 4}
   locked=True total: 87
   max=2 total: 87
   max=1 total: 4

== OldManor_Geo: the two authored-locked door owning actors ==
   BP_LineMesh_OldManor_Wall_4x850_C_1059 [BP_OldManor_Doorway_4x650_C] -> {'locked': True, 'max_lock_level': 2, 'key_tag': 'Item.Key.Buildings.OldManor'}
   StaticMeshActor_2390 [BP_OldManor_Doorway_4x650_C] -> {'locked': True, 'max_lock_level': 2, 'key_tag': 'Item.Key.Buildings.OldManor'}

== OldManor_Geo: counts over ALL placed actors ==
   locked=None max=2: 23
   locked=None max=3: 10
   locked=None max=None: 8
   locked=True max=2: 2
   locked=True max=None: 8
   locked=True total: 10

== dump-wide totals via the patched helper ==
   {'container': 157, 'max_2': 155, 'max_None': 15, 'door': 8, 'window': 8, 'max_1': 3}
   emitted key sets (placed actors only): {('locked', 'max_lock_level'): 155, ('max_lock_level',): 19,
     ('min_lock_level',): 5, ('key_tag', 'max_lock_level', 'min_lock_level'): 25,
     ('key_tag', 'max_lock_level'): 35, ('key_tag', 'min_lock_level'): 7,
     ('can_lockpick', 'min_lock_level'): 3, ('can_lockpick', 'key_tag', 'min_lock_level'): 2,
     ('can_lockpick',): 21, ('can_lockpick', 'key_tag'): 1, ('locked',): 10,
     ('can_lockpick', 'key_tag', 'locked'): 4, ('key_tag', 'locked', 'max_lock_level'): 3,
     ('key_tag',): 5, ('key_tag', 'locked'): 1, ('can_lockpick', 'locked'): 2}
```

The dump-wide line reproduces the fact-sheet totals exactly: **173 placed
locks = 157 containers + 8 doors + 8 windows**, caps **155×2, 3×1, none×15**.
`can_lockpick` is emitted for 33 placed actors, all `false`.

### 4.2 Per-map placed `_locked: true` (independent scanner, same numbers)

```text
Maps/Guildhall/Guildhall_Loot.json: 87
Maps/OldManor/OldManor_Loot.json: 65
Maps/OldManor/OldManor_Geo.json: 10
Maps/OldManor/OldManor_Gameplay.json: 3
Maps/Buildings/Guildhall/Building_Guildhall_POI.json: 1
Maps/FTUE/FTUE_Building_JewelryStore.json: 1
Maps/FTUE/FTUE_Building_SpawnArea.json: 1
Maps/FTUE/FTUE_Gameplay.json: 3
Maps/Menus/MainMenu/BeautifulCorner_Startscreen_P.json: 2
```

`game/tests/probe_lock_inventory.gd` re-derives the same table in-engine
(`LOCK_INVENTORY PASS authored_containers=157 authored_doors=8
authored_windows=8 locked_now=0`, §4.5 of `b2-impl.md`).

## 5. Expected runtime application after the integrator regenerates

Computed by joining the generated `.tatlevel.json` records on
(`source`, `name`/`actor`, `class`) against the authored locked actors. The
consumer's documented exclusions are applied (no key inventory → key-only
doors; no window interaction → windows).

| Outcome | Records | Detail |
|---|---:|---|
| locked container markers | **144** | Guildhall_Loot 48 chests + 31 display cases; OldManor_Loot 41 + 24 — all max 2 |
| locked door nodes | **10** | POI prison doorway 2 @1 (no cap → 1); FTUE JewelryStore 2 @2; FTUE_Geometry (same actor, level-instance merge) 2 @2; OldManor_Geo `BP_OldManor_Doorway_4x650_C` 4 @2 |
| excluded window door-nodes | **16** | `BP_SM_OldManor_WindowB_4x850_C` 12 + `BP_Manor_WindowB_4x650_C` 4 (both have swinging pivots) |
| excluded key-only door nodes | **2** | `BP_Res_Int_Doorway_C` in FTUE_Building_SpawnArea |
| never spawned | 13 locked containers | `BP_SmallSafe_MajorLoot_C` 8 + `BP_ChestTrunk_C` 3 + `BP_BookcaseB_C` 2 (not in `LOOT_CONTAINER_CLASSES`) |

**Finding the consumer had to absorb:** the swinging-door pre-pass resolves
`TATSwingingDoorPivotComponent` on **window** actors too — 8 of the 8
authored-locked windows (`BP_SM_OldManor_WindowB_4x850_C` ×6,
`BP_Manor_WindowB_4x650_C` ×2) appear as generated `swinging_doors` records
(16 pivot nodes). A naive producer patch therefore stamps `locked` on window
nodes; `swinging_door.configure` excludes them (`window` counter) exactly like
the key-only doors, per the lane decision "windows: no window interaction".

## 6. Integrator regeneration + refresh step

At **merged HEAD**, with a writable generated tree (not a worker symlink):

```bash
# 1. Apply the patch, then confirm it is the only producer change:
git apply build/qa/w9/parse_tables-lock-fields.patch   # or paste §3
python3 -m py_compile tools/parse_tables.py
```

`build/qa/*` is gitignored (`.gitignore:25`); if this contract and the patch
should be committed with the wave, `git add -f build/qa/w9/b2-producer-contract.md
build/qa/w9/parse_tables-lock-fields.patch` (same as the existing
`build/qa/w9/*.md` reports).

```bash
# 2. Regenerate (repo rule: producers, never hand-edited output).
make normalize                     # runs parse_tables + every producer
# or, to touch only this producer:
python3 tools/parse_tables.py

# 3. Confirm the keys and counts landed (expected: 144 container markers,
#    10 locked door nodes, 0 locked window nodes):
python3 - <<'PY'
import json, glob
n = {"marker_locked": 0, "door_locked": 0, "window_locked": 0, "max_keys": 0}
for f in glob.glob('game/data/generated/levels/**/*.tatlevel.json', recursive=True):
    d = json.load(open(f))
    for k in ('markers', 'actors'):
        for r in d.get(k, []) or []:
            if r.get('locked') is True: n['marker_locked'] += 1
            if 'max_lock_level' in r: n['max_keys'] += 1
    for r in d.get('swinging_doors', []) or []:
        if r.get('locked') is True:
            if 'window' in str(r.get('class','')).lower(): n['window_locked'] += 1
            else: n['door_locked'] += 1
print(n)
PY

# 4. Re-baseline the audit (the producer sha256 and its outputs changed):
make audit-refresh-stamps REASON='parse_tables emits authored lock fields (_locked/_lockConfig); regenerated after make normalize'
make audit                        # must exit 0 with the refreshed baseline

# 5. Re-run the lane proofs on the integrated tree:
tools/godot --headless --path game --script res://tests/probe_lock_inventory.gd
#   -> raw locked_now=362 (markers 161 + actors 173 + door records 28; the
#      producer emits each actor into both markers and actors). Gameplay
#      de-duplicates to 144 containers + 10 door nodes; marker_locked=334 /
#      door_locked=12 / window_locked=16.
tools/godot --headless --path game --script res://tests/test_w9p2_locks.gd
```

Do not commit a producer edit without step 2+4: `manifest_audit.py` fails with
`producer <script> changed since the baseline ... regenerate with ... then run
--refresh-stamps` (see `tools/manifest_audit.py:1498-1505`) and the generated
files are git-ignored, so the sha has to be re-stamped, not reverted.
