# W9-P2 / B2 — authored locks, LV4 `[ESC] CANCEL`, and lockpick hands: fact sheet

Read-only investigation. Worktree: `/home/john/Projects/TAT-2-rem-w9-p2`
(branch `rem/w9-p2`). HEAD: `b13260b3da78273edc98e54a1ae5d167c5ad431b`
(`docs(w9): P1 report — ratchet target and the docs owed at integration`).
The worktree also contains uncommitted **W9-P2 B1** edits
(`game/src/missions/mission_controller.gd`, `game/tests/run_tests.gd`,
`build/qa/w9_grade_probe.gd`, plus new B1 probe files); every
`mission_controller.gd` line citation below is the **working-tree** line at the
time of this read, not the HEAD line.
`extracted` → `/home/john/Projects/TAT-2/extracted`, `game/assets` and
`game/data/generated` → the main checkout (symlinks, `ls -ld`).
No Godot process was run (GPU lock held); all runtime conclusions below are
static reads.

Citation form: `path:line`. Raw UE JSON is pretty-printed, so line numbers are
meaningful; generated `.tatlevel.json`/`scene_variants.json` files are one line,
so those cite `:1` and identify the key/path by name. Aggregate counts cite the
method IDs **C1–C8** in §10.

---

## 0. Headline facts (trust these first)

| # | Fact | Evidence |
|---|---|---|
| 1 | The dump has **12,541 JSON files / 708 MB** and **20,291 placed-actor records** (`Outer.ObjectName` starts `Level'`). | C1, C2 |
| 2 | Raw `_locked` occurrences: **181 in 15 files** — **175 placed** (173 `true`, 2 `false`) + **6 class-default objects** (3 `true`, 3 `false`). | C1, C2 |
| 3 | Raw `_lockConfig` occurrences: **319 in 44 files** — **288 placed in 13 files** + **31 class defaults in 31 files**. | C1, C2 |
| 4 | Locked placed actors by class family: **157 containers, 8 doors, 8 windows** = **173**. | C1, §1.2 |
| 5 | No per-instance lock **level** exists anywhere. The only per-instance numeric lock fields are `_lockConfig.MaxLockLevel` (a cap) and `_lockConfig.MinLockLevel` (a range floor). Exact key `LockLevel` = **0**, exact key `lock_level` = **0** in the whole dump. | C3, §1.4 |
| 6 | Of the 173 locked actors, **155 carry `MaxLockLevel = 2`**, 3 carry `1`, 5 have `_lockConfig` but no `MaxLockLevel`, and 10 have no `_lockConfig`. | C1, §1.2 |
| 7 | All **107** generated level JSONs contain **zero** `locked`, `lock_level`, `scene_locked`, `_locked` or `MaxLockLevel` keys. | C4 |
| 8 | At spawn today: **0 locked containers and 0 locked doors** — every level record lacks the keys the consumers read, and no currently selectable `Locks.Doors` SceneVariant applies. | §3.4, §5.3 |
| 9 | The authored door/container locks that *do* exist in the dump are dropped by `tools/parse_tables.py`; it has **0** references to `_locked`/`_lockConfig`/`MaxLockLevel`. | §2 |
| 10 | `LOOT_CONTAINER_CLASSES` has 5 entries; the 8 authored-locked `BP_SmallSafe_MajorLoot_C` in Guildhall_Loot are **not** among them, so they never become runtime containers. | §3.1 |
| 11 | SceneVariant locks: **61** lock overrides total — **33 `Locks.Doors`** (14 Always, 13 OverrideChance, 6 Never) and **28 `Locks.Windows`** (9 Always, 19 OverrideChance). | C5, §5.1 |
| 12 | No selected SceneVariant can currently lock a loaded door: the mission maps select `Guildhall/Scenes` / `OldManor/Scenes` variants (no lock overrides), and the 9 door-record source maps match none of the lock-bearing building/template variants. | §5.3 |
| 13 | The `[ESC] CANCEL` path is double-handled: `_input` finishes the lockpick, then `_process` sees the same `pause` action still “just pressed” with `_lockpick_active == false` and calls `_toggle_pause()`. | §6 |
| 14 | No test or probe exercises ESC-while-lockpicking or asserts that it does not pause. | §6.5, §8 |
| 15 | Lockpick assets: **41 filelist entries** (36 `.uasset` + 5 `.ubulk`), **0 animation assets**, **0 `.glb`**; the imported lockpick-specific set is 5 lockpicking textures + 3 icon textures + 1 audio + 1 tutorial video = 10 files. | C6, §7.1 |
| 16 | `anims_manifest.json` / `anims_meta.json` (995 entries/clips) contain **0** `lockpick` clips. | §7.2 |
| 17 | `thief_character.set_lockpicking_active()` only flips a bool; it does not select a pose, tool or hand animation. | §7.4 |

---

## 1. Authored lock data in `extracted/json/`

### 1.1 Scanner definition and full-repo totals

The dump is a list of top-level records. A record is a **placed actor** when
`Outer.ObjectName` starts with `Level'`; class defaults have
`RF_ClassDefaultObject` in `Flags`. All counts below use that split. The six
class-default `_locked` records are listed in Appendix B; the placed records are
what the runtime could ever see.

| Scope | Files | Records | `true` | `false` |
|---|---:|---:|---:|---:|
| `_locked`, all objects | 15 | 181 | 176 | 5 |
| `_locked`, placed actors only | 9 | 175 | 173 | 2 |
| `_locked`, class defaults | 6 | 6 | 3 | 3 |
| `_lockConfig`, all objects | 44 | 319 | — | — |
| `_lockConfig`, placed actors only | 13 | 288 | — | — |
| `_lockConfig`, class defaults | 31 | 31 | — | — |

First placed occurrences (representative):

- `Maps/Guildhall/Guildhall_Loot.json:5213` (`_locked: true`), `:5210` (`_lockConfig`)
- `Maps/OldManor/OldManor_Loot.json:4305`, `:4302`
- `Maps/OldManor/OldManor_Geo.json:197207`, `:194603`
- `Maps/Buildings/Guildhall/Building_Guildhall_POI.json:101439`, `:36511`
- `Maps/FTUE/FTUE_Gameplay.json:3145`, `:3142`
- `Maps/FTUE/FTUE_Building_JewelryStore.json:4278`, `:4279`
- `Maps/FTUE/FTUE_Building_SpawnArea.json:2261`, `:2262`
- `Maps/Guildhall/Guildhall_Gameplay.json` has no `_locked`; first `_lockConfig` `:53634`
- `Maps/OldManor/OldManor_Gameplay.json:292726`, `:292706`
- `Maps/Menus/MainMenu/BeautifulCorner_Startscreen_P.json:13406` (no `_lockConfig`)

### 1.2 Per-file inventory (placed actors only)

`Max` is the distribution of `_lockConfig.MaxLockLevel` over **all** placed
configs in that file; `none` includes configs that exist but omit the key and
records with no `_lockConfig` at all (the per-file `cfg` count shows which).
“First lines” are the first `_locked` / `_lockConfig` occurrence in that file.

| File | placed | `_locked` true | false | cfg | Max values | first `_locked` | first `_lockConfig` |
|---|---:|---:|---:|---:|---|---:|---:|
| `Maps/Guildhall/Guildhall_Loot.json` | 372 | 87 | 0 | 95 | `1×4, 2×87, none×4` | 5213 | 5210 |
| `Maps/OldManor/OldManor_Loot.json` | 388 | 65 | 0 | 78 | `2×78` | 4305 | 4302 |
| `Maps/OldManor/OldManor_Geo.json` | 1466 | 10 | 0 | 43 | `2×25, 3×10, none×8` | 197207 | 194603 |
| `Maps/Buildings/Guildhall/Building_Guildhall_POI.json` | 943 | 1 | 0 | 37 | `1×5, 2×8, 3×8, none×16` | 101439 | 36511 |
| `Maps/Buildings/Guildhall/Building_Guildhall_POI_3rdFloor.json` | 394 | 0 | 0 | 3 | `3×1, none×2` | — | 7025 |
| `Maps/Buildings/Guildhall/Guildhall_Vault_CeremonialChambers.json` | 506 | 0 | 0 | 4 | `3×4` | — | 15770 |
| `Maps/Guildhall/Guildhall_Gameplay.json` | 2288 | 0 | 0 | 9 | `none×9` | — | 53634 |
| `Maps/Guildhall/Guildhall_PeripheryA.json` | 1028 | 0 | 0 | 3 | `2×1, 3×1, none×1` | — | 69723 |
| `Maps/OldManor/OldManor_Gameplay.json` | 2647 | 3 | 0 | 6 | `none×6` | 292726 | 292706 |
| `Maps/OldManor/OldManor_Clues.json` | 98 | 0 | 0 | 2 | `none×2` | — | 618 |
| `Maps/FTUE/FTUE_Gameplay.json` | 126 | 3 | 0 | 3 | `1×3` | 3145 | 3142 |
| `Maps/FTUE/FTUE_Building_JewelryStore.json` | 395 | 1 | 0 | 2 | `1×1, 2×1` | 4278 | 4279 |
| `Maps/FTUE/FTUE_Building_SpawnArea.json` | 38 | 1 | 2 | 3 | `none×3` | 2261 | 2262 |
| `Maps/Menus/MainMenu/BeautifulCorner_Startscreen_P.json` | 2726 | 2 | 0 | 0 | — | 13406 | — |

All other FTUE files (`FTUE_AI`, `FTUE_Audio`, `FTUE_Checkpoints`,
`FTUE_Fairy`, `FTUE_Geometry`, `FTUE_P`, `FTUE_Perf`, `FTUE_TutorialRunner`,
`DA_FTUE_SpawnData`, `QG_FTUE_Single`) have **0** placed `_locked` /
`_lockConfig` records. `C1` scanned every FTUE file individually.

### 1.3 Per-class locked inventory (the 173 `_locked: true` actors)

| Category | Class | Count | `_lockConfig` | MaxLockLevel | Other authored fields |
|---|---|---|---:|---:|---|
| container | `BP_ChestTrunk_MajorLoot_C` | 89 | 89 | 2 | — |
| container | `BP_DisplayCaseA_MajorLoot_C` | 55 | 55 | 2 | — |
| container | `BP_SmallSafe_MajorLoot_C` | 8 | 8 | 2 | **not in `LOOT_CONTAINER_CLASSES`** |
| container | `BP_ChestTrunk_C` | 3 | 3 | 1 | **not in `LOOT_CONTAINER_CLASSES`** |
| container | `BP_BookcaseB_C` | 2 | 0 | — | main-menu only |
| **containers total** | | **157** | **155** | | |
| door | `BP_VaultDoor_Sliding_C` | 3 | 3 | — | `CanBeLockpicked:false`; `KeyTag` VaultA/B/C; wrong-key message |
| door | `BP_OldManor_Doorway_4x650_C` | 2 | 2 | 2 | `KeyTag Item.Key.Buildings.OldManor` |
| door | `BP_GB_DoorSolo_C` | 1 | 1 | 2 | `KeyTag Item.Key.Buildings.Jeweller` |
| door | `BP_Prison_WallA_DoorwayB2_6x6_C` | 1 | 1 | — | `KeyTag Item.Key.Buildings.Guildhall` |
| door | `BP_Res_Int_Doorway_C` | 1 | 1 | — | `CanBeLockpicked:false`; `KeyTag Item.Key.Buildings.Apartment` |
| **doors total** | | **8** | **8** | | |
| window | `BP_SM_OldManor_WindowB_4x850_C` | 6 | 0 | — | no lock config |
| window | `BP_Manor_WindowB_4x650_C` | 2 | 0 | — | no lock config |
| **windows total** | | **8** | **0** | | |
| **grand total** | | **173** | **163** | | |

Distribution over the 173 locked actors: **3 × max 1** (all FTUE
`BP_ChestTrunk_C`), **155 × max 2** (152 containers + 3 doors), **5 ×
`_lockConfig` present but no MaxLockLevel** (3 vault doors + 1 prison door + 1
Res doorway), **10 × no `_lockConfig`** (2 BookcaseB + 8 windows).

The 8 authored-locked **doors** in detail (all have no concrete level):

- `Building_Guildhall_POI.json:101439` — `BP_Prison_WallA_DoorwayB2_6x6_C`, `_lockConfig` is only `KeyTag Item.Key.Buildings.Guildhall`.
- `FTUE_Building_JewelryStore.json:4278` — `BP_GB_DoorSolo_C`, `MaxLockLevel 2`, key tag Jeweller.
- `FTUE_Building_SpawnArea.json:2261` — `BP_Res_Int_Doorway_C`, `CanBeLockpicked:false`, key tag Apartment.
- `OldManor_Gameplay.json:292726`, `:292984`, `:293242` — three `BP_VaultDoor_Sliding_C`, each `CanBeLockpicked:false`, a different `KeyTag`, + `IncorrectKeyTags`/`IncorrectKeyMessage`.
- `OldManor_Geo.json:197207`, `:197438` — two `BP_OldManor_Doorway_4x650_C`, `MaxLockLevel 2`, key tag OldManor.

So **4 of 8 authored-locked doors are explicitly key-only (`CanBeLockpicked:false`)**;
the other 4 carry a key tag and either `MaxLockLevel` 2 or no numeric config.

The 3 `BP_VaultDoor_Sliding_C` entries are **not** in any generated
`swinging_doors` array (`OldManor/OldManor_Gameplay.tatlevel.json` has 0 door
records; C4). They are emitted as `family: vault_door` records in
`game/data/generated/gameplay/devices_runtime.json` (e.g. `:34428`) and are
deferred by `device_layer.gd:169-193`, so they are authored-locked data with no
current runtime lock. The **classes** of the other 5 locked instances occur in
generated `swinging_doors` sources: POI (1 locked instance), FTUE Jewelry (1),
FTUE Spawn (1) and OldManor_Geo (2). The records do not carry the actor
name/lock flag, so an exact instance match cannot be made from the current
generated data.

### 1.4 `_lockConfig` fields other than `MaxLockLevel`

Field frequency over all 319 `_lockConfig` dicts (placed + class defaults):

| Field | Count | Type / observed values |
|---|---:|---|
| `MaxLockLevel` | 261 | int; all objects `1:15, 2:212, 3:29, 4:5` |
| `MinLockLevel` | 45 | int; `1:3, 2:31, 3:6, 4:5` |
| `KeyTag` | 83 | `{TagName}` e.g. `Item.Key.Buildings.Guildhall` |
| `KeyItemInfo` | 81 | blueprint object ref (key item info class) |
| `CanBeLockpicked` | 37 | bool; **all 33 placed values are `false`**, all 3 `true` values are class defaults (`BP_Dumbwaiter_C`, `BP_Urban_Ext_BayWindow_C`, `BP_Urban_Window_4x6_C`) |
| `IncorrectKeyTags` | 6 | array of wrong-key tags (vault doors) |
| `IncorrectKeyMessage` | 6 | string-table entry `Locked.Vault.IncorrectKey` |
| `LockedInteractStatusTag` | 11 | class defaults only; `Interaction.Status.Locked` |
| `UnlockedInteractStatusTag` | 11 | class defaults only; `Interaction.Status.Unlocked` |

There is **no** `bDisabled`, `Disabled`, `bLocked` or `can_lockpick` field inside
any `_lockConfig`. `bDisabled` exists 2,158 times elsewhere in the dump
(UI/widget/engine data), not in a lock config. The only “can lockpick” flag is
`CanBeLockpicked`.

For the 288 placed configs the field counts are: `MaxLockLevel 237`,
`MinLockLevel 42`, `KeyTag 83`, `KeyItemInfo 81`, `CanBeLockpicked 33`,
`IncorrectKeyTags 6`, `IncorrectKeyMessage 6`; neither interact-status tag
appears on a placed actor. Separately, `tools/parse_devices.py:1274` writes a
synthetic `can_lockpick: false` default for `vault_door` records; that is
producer metadata, not a raw `_lockConfig` key.

### 1.5 Does any per-instance lock level exist? — **No**

Searches over all 12,541 JSONs:

```text
grep -rho '"LockLevel"[[:space:]]*:'        extracted/json --include='*.json' | wc -l  -> 0
grep -rho '"lock_level"[[:space:]]*:'       extracted/json --include='*.json' | wc -l  -> 0
grep -rho '"[A-Za-z_]*LockLevel"[[:space:]]*:' extracted/json --include='*.json'
  -> "DamageByLockLevel" 1, "MaxLockLevel" 261, "MinLockLevel" 45
```

- `MaxLockLevel` is the only per-instance numeric cap. It is named “max”, not
  “level”, and every consumer in the port treats it as a cap
  (`mission_controller.gd:4205-4206`; `lockable_door.gd:41-43`;
  `interactables.json:1944`).
- `MinLockLevel` is a floor. `tools/parse_devices.py:959-961` copies the whole
  `_lockConfig` into `devices_runtime.json` for `vault_door` records, but no
  `game/src` reader reads `MinLockLevel`/`CanBeLockpicked`, and
  `game/src/devices/device_layer.gd:169-193` has no `vault_door` case (it creates
  a deferred `Node3D` with `device_deferred` meta). It does not become a runtime
  lock.
- `DamageByLockLevel` is the row name in the `CT_LockpickDamage` curve
  (`Gameplay/Tuning/CT_LockpickDamage.json:10`), not per-actor.
- `LockPicking.Lock.Level` is a string-table format string
  (`StringTables/ST_Lockpicking.json:16`); `LockCombinations` / `TATCombinationLock`
  are combination-lock data (`Maps/Guildhall/QG_Guildhall_Tower_Vault.json:315`,
  `Maps/Guildhall/Guildhall_Gameplay.json:106376`), not a pick level.
- `bLocked` (1) is a mission-lobby UI flag (`UI/MissionLobby/BPUI_MissionLobby.json:234`);
  `bIsLocked` (1) is a streaming-level flag (`Maps/Guildhall/Sequencer/LS_Airship_Launch.json:2263`).

**The only complete lock-authoring truth per placed actor is
`_locked` (bool) plus `_lockConfig.MaxLockLevel`/`MinLockLevel` (caps/range).**
There is no serialized concrete level to copy.

The full 200-key universe returned by the case-insensitive `lock` key grep is in
Appendix A. Note that `lock` matches `block`: 47 of the 200 keys are
`block*`/`Block*` false positives. Other non-value fields in that universe:
`_lockedSpawnerComponent` (451) is a `TATSpawnerComponent` reference;
`EditorLockFront/Back/IndicatorRoot`, `LockBillboardFront/Back` and
`LockArrowZTranslation` are editor/visual fields, not runtime lock data.

---

## 2. What the producer emits (`tools/parse_tables.py`)

`extract_levels()` starts at `tools/parse_tables.py:1580`. The relevant emission
sites:

| Site | Function/lines | What is emitted |
|---|---|---|
| Gameplay markers | `extract_levels()` marker branch `:2245-2258`; `marker_rec` `:2314-2321` | `name, class, pos, rotation?, basis, scale, source, scene_requirement?, spawn_group?` |
| Generic actors | `:2337-2354` branch; `actors.append` `:2369-2381` | `name, class, pos, basis, scale, tags?, scene_requirement?, spawn_group?` |
| Swinging doors | pre-pass `:1786-2038`; `swinging_doors.append` `:2026-2037` | `name, actor, class, pos, basis, leaves, source, element_tag?, spawn_group?` |
| Payload write | `:3066-3088` (keys including `markers`, `actors`, `swinging_doors`) | per-level `.tatlevel.json` |

### 2.1 Actual generated keys (current file, 107 levels)

Chest marker — `game/data/generated/levels/Guildhall/Guildhall_Loot.tatlevel.json:1`:

```text
basis, class, name, pos, scale, source
```

Door record — `game/data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI.tatlevel.json:1`:

```text
actor, basis, class, leaves, name, pos, source
```

`leaves[0]` keys: `leaf_source, mesh, rel_basis, rel_loc, rel_pos, rel_rot,
rel_scale, rel_scale_v, res, scs_parent`.

Generic actor record (same POI file) keys: `basis, class, name, pos, scale,
tags` (optional `scene_requirement`, `level_instance`).

No marker, actor or door record has `locked`, `lock_level`, `_locked` or
`MaxLockLevel`. `tools/parse_tables.py` contains **0** occurrences of
`_locked`, `_lockConfig` or `MaxLockLevel` (only the unrelated word “lock” in
comments/device keys at `:769,1389,2802,3350,3472,3503`).

### 2.2 Exact producer change needed (dicts, keys, source fields)

The source properties are on the **actor** record, not the pivot component:
`props = e.get("Properties")` in the marker/actor branches, and
`exps[aidx].get("Properties")` in the door pre-pass (`aidx` resolved at
`:1812`).

For containers/markers, in `marker_rec` (`tools/parse_tables.py:2314-2321`)
add:

```python
"locked": bool(props.get("_locked", False)),
"lock_max_level": int((props.get("_lockConfig") or {}).get("MaxLockLevel", 0)),
```

For doors, in the `swinging_doors.append` dict (`:2026-2037`) add the same two
keys from `(exps[aidx].get("Properties") or {})`:

```python
"locked": bool(actor_props.get("_locked", False)),
"lock_max_level": int((actor_props.get("_lockConfig") or {}).get("MaxLockLevel", 0)),
```

`source` fields: `Properties._locked` (bool) and
`Properties._lockConfig.MaxLockLevel` (int; absent on 51 of 288 placed
configs). Do **not** infer `locked` from `MaxLockLevel`/`MinLockLevel`; 8
authored-locked doors have no `MaxLockLevel` and 4 of them are
`CanBeLockpicked:false`.

Key-name warning: the consumers read `entry.get("lock_level", 0)`
(`loot_container.gd:211`, `swinging_door.gd:85`), **not** `lock_max_level`.
`MaxLockLevel` is a cap and must not be renamed to `lock_level` without
labelling that as a port decision; the dump contains no concrete level to put
there.

The generic actor dict (`:2369-2381`) needs the same keys only if a consumer
will read actors rather than markers.

**Consumer-side catch (not a producer change):** even after the producer adds
the keys, the level loader drops them when it converts a marker to a
`loot_containers` record — see §3.1.

---

## 3. What the consumer does today

### 3.1 `game/src/core/level_loader.gd`

| Item | Lines | Current behaviour |
|---|---|---|
| `LOOT_CONTAINER_CLASSES` | `:402-408` | exactly 5 classes: `BP_ChestTrunk_MajorLoot_C`, `BP_DisplayCaseA_MajorLoot_C`, `BP_LootStashInteractable_Secret_ThinWall_C`, `BP_Storefront_DisplayCaseB_MinorLoot_C`, `BP_Storefront_DisplayCaseD_MinorLoot_C` |
| marker → `loot_containers` | `:3455-3469` | creates a **new** dict with only `class, pos, basis, scale`; `name`, `source`, `locked`, `lock_max_level` are not copied |
| marker → `door_spawns` | `:3444-3454` | only position + `_note_scene_element("door", …)`; actual doors are separate |
| `door_spawn_records` | `:3470-3474` | Den exit-door records, duplicated then `_pivot_vec` erased |
| `scene_locked` write | `:2891-2912` | only for `stats.swinging_doors`; tags/source filter; `_sv_override_applies`; writes `dd["scene_locked"]` |
| seeded roll | `:2734-2743`, seed `:2689-2694` | `Always`→true, `Never`→false, `OverrideChance`→`fnv1a("%d|%s|%s" % [seed, actor, tag]) % 10000 < chance*100` |
| variant selection | `:2756-2789` | one record per id-group; `fnv1a("%d|%s" % [seed, group]) % members` |
| override application | `:2803-2941` | **the brief's `_apply_scene_variants` is `apply_scene_variant_overrides`** (no function by the former name); global selected variants + per-source variants (`:2839-2848`); door block `:2891-2912`; stat `"locked"` `:2809,2908` |

Important consequences:

- The 8 authored-locked `BP_SmallSafe_MajorLoot_C` in Guildhall_Loot are
  **filtered out before** `loot_containers` is built (`cls in
  LOOT_CONTAINER_CLASSES` at `:3455`); so are the 3 FTUE `BP_ChestTrunk_C` and
  the 2 main-menu `BP_BookcaseB_C`.
- Of Guildhall_Loot's 87 locked containers, the ones that survive the filter
  are 48 `BP_ChestTrunk_MajorLoot_C` + 31 `BP_DisplayCaseA_MajorLoot_C` (79);
  the 8 `BP_SmallSafe_MajorLoot_C` do not. The 65 locked OldManor_Loot
  containers are 41 + 24. Total surviving authored-locked runtime markers =
  **144** (79 Guildhall, 65 OldManor) *if* the producer carries the flag.
- The loader’s `loot_containers` records cannot carry a lock today even if the
  producer adds one.

### 3.2 `game/src/missions/mission_controller.gd`

| Function | Lines | Lock sources proven |
|---|---|---|
| `_spawn_loot_containers` | `:4170-4180` | calls `c.configure(class, e, order)`; `configure` reads only `entry.locked` and `entry.lock_level` (`loot_container.gd:211-213`) |
| `_spawn_swinging_doors` | `:4188-4241` | calls `door.configure(dd, level_loader)`; then reads only `dd.scene_locked` and calls `door.set_locked(true, 3)` (`:4213-4215`) |
| scene-variant selection | `:702-709` | `select_scene_variants(map_id, GameState.active_map_seed, [])`, ids into `GameState.active_scene_variants` |
| scene-variant application | `:764-767` | `apply_scene_variant_overrides(map_id, seed, active_scene_variants, ue_level_data)` |

There is no other spawn-time lock source. `door.configure` also reads
`entry.locked`/`entry.lock_level` (`swinging_door.gd:85-87`), but the producer
emits neither; the only lock field present on `dd` is `scene_locked` (written
by `level_loader.apply_scene_variant_overrides`, `level_loader.gd:2906`).

### 3.3 Clamps and the authored cap

| Layer | Lines | Clamp |
|---|---|---|
| `loot_container.set_locked` | `loot_container.gd:133-135` | `lock_level = clampi(p_lock_level, 1, 6)` — **1..6, not the door table** |
| `loot_container.configure` | `loot_container.gd:205-213` | `entry_lvl = int(entry.get("lock_level", 0))`; lock if `entry.locked == true or entry_lvl > 0`; `set_locked(true, maxi(entry_lvl, 1))` |
| `swinging_door.set_locked` | `swinging_door.gd:57-59` | `clampi(p_lock_level, 1, LockableDoorScript.table_max_lock_level())` |
| `swinging_door.configure` | `swinging_door.gd:82-87` | same `entry.locked`/`entry.lock_level` rule |
| `LockableDoorScript.table_max_lock_level` | `lockable_door.gd:41-43`; fallback `:20` | reads `interactables.json` `doors.max_lock_level`; fallback 4 |
| `interactables.json` | `:1944` | `"max_lock_level": 4` (produced from `BP_SwingingDoor._lockConfig.MaxLockLevel`, `tools/parse_interactables.py:253-272`) |
| `loot_container.interact` | `loot_container.gd:368` | re-clamps to 1..6 |
| `swinging_door.interact` | `swinging_door.gd:454` | re-clamps to table max (4) |

So a container lock could reach level 6 in the consumer even though no authored
value above 4 exists anywhere in the dump; the door path caps at 4.

### 3.4 Generated-data scan: zero runtime lock records

```text
grep -rlE '"(locked|lock_level|scene_locked|_locked|MaxLockLevel)"' \
  game/data/generated/levels --include='*.tatlevel.json' | wc -l   # 0
```

`C4` parsed all **107** `.tatlevel.json` files and enumerated every
`markers`, `actors`, `swinging_doors` key set: no lock key occurs. Runtime
defaults are therefore `locked = false` (`loot_container.gd:117`,
`swinging_door.gd:43`) and `scene_locked` absent.

Separate generated file: `game/data/generated/gameplay/devices_runtime.json`
does carry `_lockConfig` for deferred `vault_door` records (e.g. `:34428`),
including `MinLockLevel`/`CanBeLockpicked`, but it has no `locked` or
`lock_level` key and `device_layer.gd:169-193` does not instantiate
`vault_door`. It is not part of the 107 `.tatlevel.json` scan.

---

## 4. Invented heuristics — proof the deleted formulas did not return

### 4.1 Greps

```text
grep -rn 'count % 12\|count%12' game/src
  -> mission_controller.gd:4207 (comment only)
grep -rnE '% *2|% *3' game/src --include='*.gd'
  -> no live lock formula; the only hits near locks are comments at
     loot_container.gd:208 and mission_controller.gd:4207
grep -rn 'set_locked(true' game/src game/tests
grep -rn 'vault\|Vault\|leaf\|leaves' game/src/missions/mission_controller.gd
  -> no leaf-name lock branch; leaves are visuals only
```

The unrelated `% 2`/`% 3` sites are guard lantern/key selection
(`mission_controller.gd:3773,3801`), formatting (`game_state.gd:486`), VFX
(`vfx_manager.gd`), and difficulty cycling (`mission_controller.gd:1677`,
`contract_table_ui.gd:526`, `mission_prep_ui.gd:1373`). None reads a container
index or a door leaf.

### 4.2 Every `set_locked(true, …)` call site and its level source

| Call site | Level value | Source |
|---|---|---|
| `loot_container.gd:213` | `maxi(entry_lvl, 1)` | `entry.lock_level` (`:211`) or 1 when only `entry.locked` is true; entry comes from `loot_containers`, which currently carries only class/pos/basis/scale |
| `swinging_door.gd:87` | `maxi(entry_lvl, 1)` | `entry.lock_level` (`:85`) or 1 when only `entry.locked`; producer emits neither |
| `swinging_door.gd:321` | `maxi(lock_level, 1)` | **runtime relock** of an already-unlocked closed door (`interact_hold`); reuses the door’s current `lock_level` (0 if never set, hence 1) — not spawn data |
| `mission_controller.gd:4215` | literal `3` | only from `scene_locked == true`; SceneVariant record carries no level (`:4210-4212` documents the port default) |

No container-index term, no leaf filename term, and no `count % 12` term exists
in game code. `loot_container.configure` still stores `spawn_index` (`:160-162`)
but uses it only for minigame variation/track selection (`:143,149`) and the
loot bucket (`:434,447`), never for locking.

### 4.3 Deletion commit

```text
$ git log --all --oneline -S'count % 12 == 5' -- game/src
9d73da1 feat(missions): M4 objectives, doors/safes, guards, Den hub, OldManor
$ git log --all --oneline -S'3 + (count % 2)' -- game/src
fc71466 fix(gameplay): objective markers, portal re-arm, authored locks/loot, contract clock (T10)
ae47adb fix(gameplay): ... (same message; original branch, not HEAD)
```

`fc71466` is in HEAD (`git merge-base --is-ancestor fc71466 HEAD` → 0). Its
message says verbatim:

> “C4-04 / RE-K-07 / RE-K-17 locks: delete the invented `count % 12`,
> leaf-filename and container-index formulas. Locks come from authored records
> or the authored scene-variant Locks.Doors override (level 3, inside the
> authored 4 cap).”

The diff itself removes:

```diff
- door.set_locked(true, 3 + (count % 2))
- elif count % 12 == 5:
-     door.set_locked(true, 1 + (count % 3))
...
- set_locked(true, 2 + (p_index % 2))
- set_locked(true, 1 + (p_index % 3))
```

(`git show fc71466 -- game/src/missions/mission_controller.gd
game/src/interact/loot_container.gd`).

---

## 5. Doors authored truth

### 5.1 `game/data/generated/scene_variants.json`

One line (`:1`), 222 variant records. Lock override counts:

| Tag | Always | OverrideChance | Never | Total |
|---|---:|---:|---:|---:|
| `MapVariation.SceneElement.Locks.Doors` | 14 | 13 | 6 | **33** |
| `MapVariation.SceneElement.Locks.Windows` | 9 | 19 | 0 | **28** |
| **total** | **23** | **32** | **6** | **61** |

33 of the 222 variants carry at least one lock override. They belong to only
these `map_id`s (no `Guildhall/Scenes` or `OldManor/Scenes` variant has a lock
override):

| `map_id` | Door overrides | Window overrides |
|---|---:|---:|
| `Buildings/Apartment_Balcony` | 3 (all OverrideChance) | 3 (OverrideChance) |
| `Buildings/Apartment_Lower` | 2 (Always, Never) | 2 (OverrideChance) |
| `Buildings/Apartment_Mid` | 2 (Always, Never) | 2 (OverrideChance) |
| `Buildings/Apartment_Upper` | 2 (Always, Never) | 2 (OverrideChance) |
| `Buildings/Bakery` | 2 (Always, Never) | 2 (OverrideChance) |
| `Buildings/ElTrain_Station` | 2 (Always, Never) | — |
| `Buildings/Pub` | 2 (OverrideChance) | 2 (OverrideChance) |
| `Buildings/Tailor` | 6 (5 OverrideChance, 1 Never) | 6 (OverrideChance) |
| `Templates/Scenes` | 12 (9 Always, 3 OverrideChance) | 9 (Always) |
| **total** | **33** | **28** |

### 5.2 Seeding and matching

- `select_scene_variants(map_id, seed, requested)` `:2756-2789`:
  `map_key = map_id.lower().replace("_","").replace("-","")`; a variant matches
  when `vmap.find(map_key) >= 0` **or** `map_key.find(vmap) >= 0`; variants are
  grouped by id after stripping `_open/_closed/_quest/_damaged/_locked/_on/_off`;
  one member per group is chosen by
  `_sv_fnv1a("%d|%s" % [seed, group]) % members.size()` (`:2787`).
- `_sv_override_applies` `:2734-2743`: `Always` → true; `Never` → false;
  `OverrideChance` → `_sv_fnv1a("%d|%s|%s" % [seed, actor_name, tag]) % 10000 <
  int(clampf(chance,0,100) * 100)`.
- `apply_scene_variant_overrides` `:2803-2941` applies the globally selected
  variants first (`:2825-2827`), then selects variants per door-record source
  map (`:2839-2848`); the door block requires matching `source` (if a source
  filter is set) and `element_tag` (or untagged), writes `dd["scene_locked"]`
  once, and counts `locked` (`:2891-2912`).

The mission controller passes `map_id` = the contract map (`guildhall` /
`old_manor` etc.) at `mission_controller.gd:702-709`; the run seed is
`GameState.active_map_seed`, initialized from
`_sv_fnv1a("%s|%d" % [map_id, order]) & 0x7FFFFFFF`
(`mission_controller.gd:699-703`).

### 5.3 Which generated level JSONs actually get `scene_locked=true` at load?

**None under the current generated data.** Static proof:

1. The 10 door-bearing `.tatlevel.json` files and their record sources are:

| Level JSON | doors | source map(s) |
|---|---:|---|
| `Buildings/Guildhall/Building_Guildhall_POI` | 121 | `Buildings/Guildhall/Building_Guildhall_POI.json` |
| `Buildings/Guildhall/Building_Guildhall_POI_3rdFloor` | 6 | `Buildings/Guildhall/Building_Guildhall_POI_3rdFloor.json` |
| `Buildings/Guildhall/Guildhall_Vault_CeremonialChambers` | 8 | same |
| `FTUE/FTUE_Building_JewelryStore` | 4 | `FTUE/FTUE_Building_JewelryStore.json` |
| `FTUE/FTUE_Building_SpawnArea` | 2 | `FTUE/FTUE_Building_SpawnArea.json` |
| `FTUE/FTUE_Geometry` | 4 | `FTUE/FTUE_Building_JewelryStore.json` (level-instance merge) |
| `Guildhall/Facade_Storefront_Cluster` | 2 | `Guildhall/Facade_Storefront_Cluster.json` |
| `Guildhall/Guildhall_Geometry` | 4 | `Guildhall/Guildhall_Geometry.json` |
| `Guildhall/Guildhall_PeripheryA` | 16 | `Guildhall/Guildhall_PeripheryA.json` (14) + `Guildhall/Facade_Storefront_Cluster.json` (2) |
| `OldManor/OldManor_Geo` | 120 | `OldManor/OldManor_Geo.json` |

All 287 door records have `element_tag` either absent or `""` (C4), so an
override’s tag filter would match every door in the source; the decisive filter
is `source`.

2. `select_scene_variants` for the two mission map ids selects only
   `Guildhall/Scenes` (104 variants) and `OldManor/Scenes` (85 variants); none of
   those variants has a `Locks.Doors` or `Locks.Windows` override (C5 / §5.1).
3. The lock-bearing variant `map_id`s are only the eight building maps and
   `Templates/Scenes` in §5.1. No generated door record has one of those source
   maps: the source list is the 9 entries in the table above. None matches
   `Buildings/Apartment_*`, `Buildings/Bakery`, `Buildings/ElTrain_Station`,
   `Buildings/Pub`, `Buildings/Tailor` or `Templates/Scenes`.
4. Therefore `dd["scene_locked"]` is never written, `locked_count` stays 0, and
   `door.set_locked(true, 3)` (`mission_controller.gd:4214-4215`) is never
   reached. This is seed-independent for the current data; C7 additionally
   evaluated seeds `1`, `2`, `424242` and found no lock-bearing selection for
   `guildhall`, `old_manor`, or any of the 9 door sources.

If a `Locks.Doors` override *were* selected for a door source, every door in
that source would lock at **level 3** (the port default,
`mission_controller.gd:4210-4215`), clamped by `interactables.json:1944` /
`lockable_door.gd:41-43` to the authored cap **4**. The only maps that could
produce such a selection are the eight building maps and `Templates/Scenes`
listed in §5.1; none of them has a generated `.tatlevel.json` with doors in the
current 107-file set.

`Locks.Windows` has no runtime consumer: `_scene_override_kind` returns
`"window"` (`level_loader.gd:2700-2701`), but `apply_scene_variant_overrides`
only handles `kind == "door"` in the spawn arrays (`:2891`); windows are counted
as unmapped, matching the comment at `:2801-2802`.

---

## 6. The LV4 `[ESC] CANCEL` bug

### 6.1 Exact double-handling trace

The bug is level-independent. “LV4” is only the HUD title suffix
(`hud.gd:2170-2172` appends `— LV %d`) and the level-4 minigame data; neither
`_input` nor `_finish_lockpick` branches on the lock level.

1. `hud.gd:2392` `_input(event)` receives the ESC key.
2. `hud.gd:2407-2411` `if _lockpick_active:` → `_finish_lockpick(false)` →
   `_mark_input_handled()` → `return`.
3. `_finish_lockpick` (`hud.gd:3270-3282`) immediately sets
   `_lockpick_active = false` (`:3271`), hides the overlay, restores mouse mode
   and clears the player’s `set_lockpicking_active(false)`.
4. In the same frame, `hud.gd:2500` `_process(delta)` runs. `hud.gd:2507`
   evaluates `InputMap.has_action("pause") and Input.is_action_just_pressed("pause")`
   — still true.
5. The first branch at `hud.gd:2508` checks only
   `Engine.get_process_frames() == _npc_dialogue_closed_frame` (the existing NPC
   dialogue guard); it does not know about the lockpick.
6. `hud.gd:2517` `elif _lockpick_active:` is now **false** (step 3), so control
   falls through to `hud.gd:2523-2524` `_toggle_pause()`.
7. `_toggle_pause` → `_set_paused` (`hud.gd:3499-3519`) sets
   `get_tree().paused = true`, shows `_pause_root`, and changes mouse mode.

The lockpick is cancelled *and* the pause menu opens from one ESC press.

### 6.2 Godot event-ordering argument

Godot dispatches `_input` during input-event delivery before the frame’s
`_process`; `Input.is_action_just_pressed()` is the Input singleton’s
frame-scoped state. `Viewport.set_input_as_handled()` (`_mark_input_handled`,
`hud.gd:2482-2485`) stops further propagation of the event; it does **not**
clear the Input action state or make `is_action_just_pressed()` false for the
same frame. The HUD already relies on this exact ordering for NPC dialogue:
`_npc_dialogue_closed_frame` is set in the dialogue’s `_input` path
(`hud.gd:2288`) and checked at `_process` `:2508`. Lockpicking has the same
pattern but no frame stamp.

### 6.3 Minimal guard (one condition, mirroring the existing NPC guard)

The smallest coherent guard is to give `_finish_lockpick()` its own frame stamp
and extend the existing `:2508` guard:

- add a field next to `_lockpick_prev_mouse` (`hud.gd:313`):
  `var _lockpick_closed_frame: int = -1`
- set it in `_finish_lockpick()` (`hud.gd:3271`):
  `_lockpick_closed_frame = Engine.get_process_frames()`
- change `hud.gd:2508` from
  `if Engine.get_process_frames() == _npc_dialogue_closed_frame:`
  to
  `if Engine.get_process_frames() == _npc_dialogue_closed_frame or Engine.get_process_frames() == _lockpick_closed_frame:`

That suppresses the `pause` action for the frame in which the lockpick consumed
ESC, exactly as the NPC dialogue path already does. No other branch needs to
change.

### 6.4 Other pause paths

- `hud.gd:1996-1997` public `toggle_pause()` → `_toggle_pause()`.
- `mobile_touch_ui.gd:354-356` the on-screen “pause” button calls
  `hud.toggle_pause()` directly. It does not consult `_lockpick_active`, so a
  mobile pause button can pause during a lockpick (a separate path; no
  ESC/double-handling).
- `hud.gd:2488-2493` `NOTIFICATION_WM_GO_BACK_REQUEST` and mobile focus-out call
  `_set_paused(true)` directly; no lockpick guard.
- `input_context.gd:56` `LOCKPICK_CANCEL_CM = 200.0`; `:340` auto-pushes the
  `lockpick` modal with that cancel radius. `LOCKPICK_DISABLED`
  (`input_context.gd:26-31`) deliberately does **not** include `pause`
  (comment `:32-34` says the port’s map does not pause and `pause` stays live).
  This is why the HUD `_process` branch, not the input-context modal, is the
  pause consumer.

### 6.5 Tests/probes that touch lockpick cancel or pause

| File:line | Kind | What it asserts / does |
|---|---|---|
| `game/tests/test_input.gd:299` | unit | `InputGlyphs.format_legend("[SPACE] / [LMB] STRIKE PIN · [ESC] CANCEL", ...)` string is unchanged — text only, not behaviour |
| `game/tests/test_input.gd:391-420` | unit | pushes the lockpick modal with 200.0 cm; blocks move/interact/tools/look; `primary_action` stays live; no-player cancel does not fire |
| `game/tests/e2e/e2e_tier2_boundaries.gd:921-931` | E2E T2-15-C/D | lock level 0/99 clamp; `T2-15-D` only checks `hud_txt.find("KEY_ESCAPE")` and `map_toggle` — string presence, no ESC event |
| `game/tests/test_t05_ui_contract.gd:347-361` | unit T05.H12-H14 | `_set_paused(true/false)`, pause backdrop alpha, live HUD hidden, footer visible |
| `game/tests/run_tests.gd:4923-4956` | unit suite 60b | deterministic pause footer seed/name; does not open/close pause via ESC |
| `game/tests/test_spider_runtime.gd:211-218` | unit | dialogue ESC closes dialogue and does not pause the tree; NPC path only |
| `game/tests/test_input.gd:108-112,237` | unit | `pause` action keeps Escape + gamepad Start |

**No probe exists** for “ESC while `_lockpick_active` must not pause.” There is
no `game/tests/probe_*lock*` file; `find game/tests -iname '*lock*'` returns
nothing. The closest E2E `T2-15-D` would still pass with the bug because it only
greps the HUD source for `KEY_ESCAPE`.

---

## 7. Lockpick assets, HUD dial and hands

### 7.1 The 41 assets

`grep -ic lockpick extracted/filelist.txt` = **41** (the T04 report’s count,
`docs/reports/remediation-20261125/T04-anim.md:225`). Exact extension split:

| Extension | Count |
|---|---:|
| `.uasset` | 36 |
| `.ubulk` | 5 |
| **total** | **41** |
| animation (`.glb`/`.anim`/`.uasset` anim) | **0** |

Path families (C6):

| Prefix / family | Count | Examples |
|---|---:|---|
| `TAT/Content/Art/Gameplay/Lockpicking/` | 12 | `T_Lockpicking_BG`, `_Cursor`, `_KeyholeCover`, `_RingTrack`, `_RingTrack_Jammable`, `T_KeyholeMaskWidescreenCutout/Size`, `M_LockpickCutout`, `BG_Vignette` |
| `TAT/Content/Art/UI/Icons/` | 4 | `Icon_Ability_Lockpick`, `T_Icon_Lockpick_QuestionMark` |
| `TAT/Content/Gameplay/Interactables/Locks/` | 8 | `GA_Lockpick`, `GA_Lockpick_Cancel`, `GA_Lockpick_TrackFinished`, `…TrackInteract_Attempt/Broken/Jammed`, `GE_Lockpicking`, `DA_LockpickMinigameVariations` |
| `TAT/Content/Gameplay/Abilities/Cues/…/Lockpicking/` | 4 | `GC_Lockpick_Duration/Interrupted/TrackSection_Broken/Jammed` |
| `TAT/Content/UI/Lockpick/` | 8 | `BPUI_LockpickMinigame`, `…Screen`, `…Cursor`, `…TrackEnd`, `BPI_LockpickMInigameUI`, `BPUI_CombinationLock_Digit/Widget`, `T_Icon_LockpickTrackEnd` |
| `TAT/Content/UI/HUD/FTUE/Infographics/` | 1 | `BPUI_Tutorial_Video_Lockpicking` |
| `TAT/Content/Audio/Events/…/TristanFairy/` | 1 | `Play_tristan_fairy_ftue_lockpick_chests__doors__valuable_loot_01` |
| `TAT/Content/Gameplay/Tuning/` | 1 | `CT_LockpickDamage` |
| `TAT/Content/Movies/Tutorial/FTUE/` | 1 | `lockpicking_tutorial_video` |
| `TAT/Content/StringTables/` | 1 | `ST_Lockpicking` |
| **total** | **41** | |

There is **no lockpick tool mesh** named `*lockpick*` in the filelist, no
`SM_Lockpick*.glb`, and no animation directory under a lockpick path. The
imported files under `game/assets/ue` that match `*lockpick*` (non-`.import`) are
only:

```text
game/assets/ue/Raw/Art/Gameplay/Lockpicking/T_Lockpicking_BG.png
game/assets/ue/Raw/Art/Gameplay/Lockpicking/T_Lockpicking_Cursor.png
game/assets/ue/Raw/Art/Gameplay/Lockpicking/T_Lockpicking_KeyholeCover.png
game/assets/ue/Raw/Art/Gameplay/Lockpicking/T_Lockpicking_RingTrack.png
game/assets/ue/Raw/Art/Gameplay/Lockpicking/T_Lockpicking_RingTrack_Jammable.png
game/assets/ue/Raw/Art/UI/Icons/Icon_Ability_Lockpick.png
game/assets/ue/Raw/Art/UI/Icons/T_Icon_Lockpick_QuestionMark.png
game/assets/ue/Raw/UI/Lockpick/T_Icon_LockpickTrackEnd.png
game/assets/ue/audio/lockpick.wav
game/assets/ue/videos/Tutorial/FTUE/lockpicking_tutorial_video.ogv
```

(10 files; the `.ogv.uid` sidecar makes 11 path matches with `find`.) The
extracted raw asset directory has 8 matching PNGs
(`extracted/assets/Art/Gameplay/Lockpicking/` 5, `Art/UI/Icons/` 2,
`UI/Lockpick/` 1), again no mesh.

### 7.2 Zero animations

- `game/data/generated/anims_manifest.json`: top-level `entries` = 995;
  case-insensitive `lockpick` count = **0**.
- `game/data/generated/anims_meta.json`: `clips` = 995; `lockpick` count = **0**.
- `find -L game/assets/ue/Anims -iname '*lockpick*'` = **0**.
- `extracted/json/Gameplay/Interactables/Locks/` contains eight data/ability
  assets (`GA_Lockpick*` ×6, `GE_Lockpicking`, `DA_LockpickMinigameVariations`),
  no animation asset.

There is therefore no authored lockpick hand/arm clip in the extraction.

### 7.3 What the HUD dial draws

- The dial is an **inner class**, not a separate scene/script:
  `hud.gd:429` `class LockpickDialDraw extends Control`; instantiated at
  `hud.gd:1581-1586` (`_lockpick_dial = LockpickDialDraw.new()`, name
  `"LockpickDial"`, 280×280).
- `_draw()` (`hud.gd:438-487`) draws procedurally with `draw_arc`/`draw_circle`/
  `draw_line`: outer Art Nouveau ring, track arc, breakable sections, end caps,
  progress pips, sweeping cursor needle. It does **not** draw a hand, a
  lockpick tool, or the `T_Lockpicking_RingTrack` texture.
- Only two authored textures are placed in the overlay:
  `T_Lockpicking_BG.png` (`hud.gd:1575`) and `T_Lockpicking_KeyholeCover.png`
  (`hud.gd:1588`). `T_Lockpicking_Cursor.png`, `T_Lockpicking_RingTrack*.png`
  and `M_LockpickCutout` are imported/extracted but not referenced by
  `game/src`.
- The status line is authored UI text, not an animation:
  `hud.gd:1595` `"[SPACE] / [LMB] STRIKE PIN   ·   [ESC] CANCEL"`.
- Lockpick level title: `hud.gd:2170-2172` appends `— LV %d` to the target label.
- The overlay is a full-screen Control tree (`hud.gd:1525-1599`), built at runtime
  in `_build_lockpick_minigame`; there is no `lockpick_dial.tscn` or
  `lockpick_dial.gd` file.

### 7.4 Does `thief_character.gd` expose a hand/pose API?

No pose API. The only lockpick-related API is:

```gdscript
func set_lockpicking_active(active: bool) -> void:
    is_lockpicking = active
```

`thief_character.gd:2291-2292`. It flips the bool used for disguise drain
(`:1584`, `disguise_drain_rate`) and nothing else. The callers are
`loot_container.gd:370-372/396` and `swinging_door.gd:456-458/429` (on finish),
plus the HUD start/finish (`hud.gd:2178-2179, 3275-3277`) and tests.

The first-person rig does exist, but it is a generic tool rig:

- `THIEF_1P_UPPER_GLB` = `res://assets/ue/Content/Art/Animation/ThiefNisha/Skin/Base/SK_ThiefNisha__BodyUpper.glb`
  (`thief_character.gd:19`); it is the real 1P upper body (arms/hands/torso),
  built by `_try_build_real_fp_arms()` (`:3356-3413`).
- Tool bone candidates: `weapon_r_1p`, `hand_r_1p`, `hand_r`
  (`thief_character.gd:21`), attached by `_attach_fp_tool_to_hand()`
  (`:3439-3457`).
- Available 1P clips are table-driven in `game/src/core/animation_library.gd`
  `FP_CLIPS` `:99-103` and `FP_TOOL_CLIPS` `:104-127`; roles include
  `blackjack_idle`, `smoke_idle`, `slithersap_idle`, `fairy_idle`,
  `vistara_idle`, `zipwire_idle`, etc. There is **no** `lockpick` role.
- `_fp_play_action(role)` (`thief_character.gd:3460-3467`) can play any table
  role; `has_fp_role()` (`animation_library.gd:568-569`) rejects unknown roles.

So a labelled stand-in is possible only by choosing an existing table role
(no new clip) or by posing the rig by hand; the code has no lockpick pose.

### 7.5 What a labelled stand-in could reuse (paths only)

| Candidate | Path | Notes |
|---|---|---|
| Real 1P arms/hands | `game/assets/ue/Content/Art/Animation/ThiefNisha/Skin/Base/SK_ThiefNisha__BodyUpper.glb` | 70 `_1p` bones per `animation_library.gd:96-97`; full upper body, not isolated hands |
| 1P generic in-hand idle | `AN_Gear_Generic_InHand_R_Idle` (`animation_library.gd:119-120` `slithersap_idle`) | existing table role; authored for Slithersap, not lockpick |
| 1P pickpocket idle | `AN_Pickpocket_StandIdle` (`animation_library.gd:122-123` `fairy_idle`) | existing table role; authored for Fairy/pickpocket |
| 1P blackjack idle | `AN_BlackJack__StandIdle` (`animation_library.gd:107-108`, manifest `:12757-12765`) | existing tool idle |
| R8 takedown pair, thief half | `game/assets/ue/Anims/TAT/Content/Art/Animation/Base/Anim/Synced/AN_StealthTakedown_GuardEnforcer__Atk.glb` and `…__Atk_Montage.glb` | 3.500 s; 3P rig only (`thief_character.gd:170-178, 3002-3039`) |
| R8 takedown pair, guard half | `…/AN_StealthTakedown_GuardEnforcer__Vic.glb` and `…__Vic_Montage.glb` | 3.500 s; guard victim, not 1P |
| Base-game 3P takedown alternates | `…/AN_TakedownOverhead_Front_Montage.glb`, `…/AN_TakedownOverhead_Behind_Montage.glb` | 3P only (`animation_library.gd:655-658`) |

The R8 pair is the authored `Atk`/`Vic` pair used by
`_tp_takedown_atk_start` (`thief_character.gd:3012-3039`) with role
`takedown_atk_stealth_3p` (`animation_library.gd:657`). It is a 3P body montage,
not a 1P hand clip; reusing it for the lockpick would be a labelled stand-in,
not an authored lockpick animation.

---

## 8. Existing tests that pin locks/lockpick

| File:line | Suite / test | Assertion |
|---|---|---|
| `game/tests/run_tests.gd:198-208` | suite 6 | `lockable_door.gd` with `locked=true`, `lock_level=2`; `interact()` must advance `lockpick_progress` and prompt `[E] Pick Lock` |
| `game/tests/run_tests.gd:4679-4719` | suite 53g | explicit `set_locked(true, 1 + (5 % 3))` (level 3, test fixture), prompt `[F] PICK LOCK (Lv 3)`, repeated `interact()` must unlock, door must swing 90° |
| `game/tests/test_t10_gameplay.gd:221-239` | suite 91.3a | the JSON structures named by `GH_LEVELS` (`Guildhall_Loot`, `Guildhall_Gameplay`) must contain **0** door records with `locked`/`lock_level` |
| `game/tests/test_t10_gameplay.gd:240-265` | suite 91.3b | 6 synthetic doors, including a `SM_VaultDoorA` leaf at index 5, must spawn **6 spawned / 0 locked** (no old heuristic) |
| `game/tests/test_t10_gameplay.gd:267-277` | suite 91.3c | an authored `{"locked":true,"lock_level":2}` door record must lock at **2** |
| `game/tests/test_t10_gameplay.gd:279-289` | suite 91.3d/e | container label must not embed `(Lv`/`LV`; `BP_DisplayCaseA_MajorLoot_C` configured with **no** lock entry must stay **unlocked** |
| `game/tests/test_t10_gameplay.gd:315-326` | suite 91.4c | five container classes configured with no lock entry must stay unlocked |
| `game/tests/test_t10_gameplay.gd:390-414` | suite 91.7a-d | authored cancel distance 2.0 m; both `swinging_door.gd` and `loot_container.gd` cancel beyond 2.0 m and clear the player flag |
| `game/tests/run_tests.gd:7349-7365` | suite 94 | runs the whole `test_t10_gameplay.gd` suite above (fails closed on script error) |
| `game/tests/e2e/e2e_tier1_features.gd:1707-1713` | T1-19-A | both scripts expose `locked` + `lock_level` properties |
| `game/tests/e2e/e2e_tier1_features.gd:1717-1722` | T1-19-B | `set_lockpicking_active` is wired into both scripts |
| `game/tests/e2e/e2e_tier1_features.gd:1725-1744` | T1-19-C | manually locked (level 1) safe unlocks and spawns major loot |
| `game/tests/e2e/e2e_tier1_features.gd:1746-1749` | T1-19-D | door source references `DA_LockpickMinigameVariations`/`lock_level` |
| `game/tests/e2e/e2e_tier1_features.gd:1752-1762` | T1-19-E | `CT_LockpickDamage` 5/10/20/40 for levels 1..4 |
| `game/tests/e2e/e2e_tier2_boundaries.gd:880-914` | T2-15-A | 200 cm cancel via `interactables.json`; near 0.5 m does not cancel, far 3.0 m does |
| `game/tests/e2e/e2e_tier2_boundaries.gd:916-928` | T2-15-B/C | 0.1 s early unlock, 0.5 s jam delay; levels 0/99 clamp to valid tracks |
| `game/tests/e2e/e2e_tier2_boundaries.gd:930-931` | T2-15-D | only greps `hud.gd` for `map_toggle` + `KEY_ESCAPE`; **no ESC event** |
| `game/tests/e2e/e2e_tier2_boundaries.gd:1221-1261` | T2-19-A/B/C | container one-shot loot; stash 0 duplicates; door tween 90°/0.4 s; test explicitly clears `locked` |
| `game/tests/e2e/e2e_tier2_boundaries.gd:1268-1275` | T2-19-E | `CT_LockpickDamage` clamps 0→5, 7→40 |
| `game/tests/e2e/e2e_tier3_pairwise.gd:158-179` | T3-04 | manually locked (level 3) container drains disguise 5/s + 1/s |
| `game/tests/e2e/e2e_tier3_pairwise.gd:353-370` | T3-13 | level 4 jam damage 40, curve agrees, container minigame track non-empty |
| `game/tests/e2e/e2e_tier3_pairwise.gd:439-449` | T3-17 | container `lock_level=3` yields a minigame track |
| `game/tests/e2e/e2e_tier3_pairwise.gd:494-507` | T3-19 | container exposes `locked`; yellow prop highlight |
| `game/tests/e2e/e2e_tier4_scenarios.gd:203-229` | T4-06 | manually driven disguise lockpicking journey |
| `game/tests/test_input.gd:391-420` | lockpick modal unit | modal blocks movement/interact/tools/look, primary stays live, 200 cm cancel anchor |
| `game/tests/test_m2_player.gd:355-357` | M2.8 | `set_lockpicking_active(true/false)` flips `is_lockpicking` |
| `game/tests/test_t05_ui_contract.gd:347-361` | T05.H12-H14 | pause panel/backdrop/HUD hidden/footer visible (no lockpick) |
| `game/tests/run_tests.gd:4923-4956` | suite 60b | deterministic pause footer seed; no ESC/pause interaction |
| `game/tests/test_spider_runtime.gd:211-218` | dialogue | ESC closes dialogue without pausing; the existing NPC frame-stamp guard |

What would fail if container locks become authored:

- **91.3e (`test_t10_gameplay.gd:288-289`) and 91.4c (`:325-326`)** are the
  explicit “no authored lock ⇒ unlocked” pins. They configure **synthetic**
  entries with no `locked`/`lock_level`; they pass today and would still pass
  if only real level records gain authored locks. They would fail if the
  consumer defaults a container to locked from its class/CDO (`BP_SmallSafe_C`,
  `BP_LargeFancySafe_C`, `BP_SlidingWindow_Base_C` are class-default
  `_locked:true`/`CanBeLockpicked:...` examples) rather than from the entry.
- **91.3a (`:221-239`)** only counts `swinging_doors` in `Guildhall_Loot` and
  `Guildhall_Gameplay`; those two files currently have no authored-locked
  doors, so adding locks to `Building_Guildhall_POI` or `OldManor_Geo` would
  not trip it. It would trip if the producer emitted `locked` into either of
  the two `GH_LEVELS` door arrays.
- **Suite 53g (`run_tests.gd:4687`)** uses a test-side formula
  `set_locked(true, 1 + (5 % 3))`, not game data; it would keep passing but its
  comment (“no spawn index participates”) is the current contract.
- **T2-19-A/B/C**, **T1-19-C**, **T3-04/T3-13/T4-06** all set `locked` manually
  (and some clear it), so authored container locks would not break them unless
  the test’s own container is loaded from authored data — none of them loads a
  real `.tatlevel` container.
- **S2 `e2e_s2_loot.gd`** uses real Guildhall loot actors, not
  `loot_containers` for the major pickup; its stash (`:77-93`) has no authored
  `_locked` in the dump, so it stays a deposit point.

---

## 9. Unknowns

1. **Semantics of `MinLockLevel`/`MaxLockLevel`.** The dump proves the fields
   are serialized per placed actor, but not how the shipped Blueprint chooses a
   concrete level. “Max” could be a random-roll cap, a clamp, or the assigned
   level; no `LockLevel` property or compiled Blueprint bytecode is present.
   The fact sheet therefore cannot say that `MaxLockLevel` *is* the intended
   level — only that it is the only numeric per-instance lock value.
2. **Whether the 8 authored-locked `BP_SmallSafe_MajorLoot_C` should be
   openable at all.** They are `_locked:true`, `MaxLockLevel:2`, but filtered by
   `LOOT_CONTAINER_CLASSES` (`level_loader.gd:402-408`). Whether the lane expands
   that allowlist is a scope decision, not derivable from the dump.
3. **Whether the 8 authored-locked doors should become lockpickable.** Four are
   explicitly `CanBeLockpicked:false` and key-gated; four carry key tags and
   `MaxLockLevel 2` or no numeric config. There is no concrete level for any of
   them; selecting one is a port decision, not authored data.
4. **Actual mission contract order/seed at capture time.** The static proof is
   seed-independent for the current lock-bearing variant set (none of the
   selected groups has a lock override), but the live `GameState.active_map_seed`
   for a specific contract was not observed (no Godot run).
5. **`BP_ChestTrunk_C` vs `BP_ChestTrunk_MajorLoot_C`.** The FTUE three locked
   chests are the base `BP_ChestTrunk_C`, absent from the runtime allowlist;
   whether they are meant to be openable is unknown.
6. **The 41-file list includes 5 `.ubulk` sidecars.** They are not standalone
   assets; “41 assets” is a filelist path count, not 41 usable runtime assets.
   The actual imported lockpick-specific set is 10 files (textures/audio/video).
7. **No authored lockpick hand clip/pose exists.** The 0-animation result is
   verified; what a “labelled stand-in” should be (generic in-hand idle,
   pickpocket idle, or a hand-authored pose) is an art/content decision, not a
   data fact.
8. **The `loot_container` clamp is 1..6, the door clamp is 1..4.** No authored
   value >4 exists in the placed dump, but the container path could accept one.
   Whether that is intentional is not documented in the dump.
9. **`bDisabled` (2,158 occurrences) is not lock-domain.** It is generic
   widget/engine data; the fact sheet only asserts there is no disabled flag
   inside `_lockConfig`.

---

## 10. Methods (exact commands / scanner logic)

### C1 — full placed-actor lock inventory

```bash
python3 - <<'PY'
import json, glob, collections
def placed(o):
    return ((o.get('Outer') or {}).get('ObjectName','') or '').startswith("Level'")
def walk(o):
    if isinstance(o, dict):
        yield o
        for v in o.values(): yield from walk(v)
    elif isinstance(o, list):
        for v in o: yield from walk(v)
files = glob.glob('extracted/json/**/*.json', recursive=True)  # 12,541
rows = collections.defaultdict(collections.Counter)
for p in files:
    d = json.load(open(p))
    if not isinstance(d, list): continue
    for o in d:
        if not (isinstance(o, dict) and placed(o)): continue
        pr = o.get('Properties') or {}
        if '_locked' in pr or '_lockConfig' in pr:
            lc = pr.get('_lockConfig') if isinstance(pr.get('_lockConfig'), dict) else None
            rows[p][(o.get('Type'), pr.get('_locked'),
                     lc.get('MaxLockLevel') if lc else None,
                     lc.get('MinLockLevel') if lc else None)] += 1
PY
```

The exact per-file table is §1.2; the per-class table §1.3; class-default
details Appendix B.

### C2 — raw occurrence and scope counts

```bash
grep -rho '"_locked"'       extracted/json --include='*.json' | wc -l   # 181
grep -rho '"_lockConfig"'  extracted/json --include='*.json' | wc -l   # 319
grep -rho '"MaxLockLevel"' extracted/json --include='*.json' | wc -l   # 261
grep -rl  '"_locked"'      extracted/json --include='*.json' | wc -l   # 15
grep -rl  '"_lockConfig"'  extracted/json --include='*.json' | wc -l   # 44
```

Placed/CDO split: the same Python record walker, classifying a top-level record
by `Outer.ObjectName.startswith("Level'")` vs
`'RF_ClassDefaultObject' in Flags`.

### C3 — exact per-instance level search

```bash
grep -rho '"LockLevel"[[:space:]]*:'  extracted/json --include='*.json' | wc -l  # 0
grep -rho '"lock_level"[[:space:]]*:' extracted/json --include='*.json' | wc -l  # 0
grep -rho '"[A-Za-z_]*LockLevel"[[:space:]]*:' extracted/json --include='*.json' | sort | uniq -c
#       1 "DamageByLockLevel"
#     261 "MaxLockLevel"
#      45 "MinLockLevel"
```

### C4 — generated levels (107 files)

```bash
find game/data/generated/levels -name '*.tatlevel.json' | wc -l   # 107
grep -rlE '"(locked|lock_level|scene_locked|_locked|MaxLockLevel)"' \
  game/data/generated/levels --include='*.tatlevel.json' | wc -l   # 0
python3 - <<'PY'
import json, glob
for f in glob.glob('game/data/generated/levels/**/*.tatlevel.json', recursive=True):
    d = json.load(open(f))
    for k in ('markers','actors','swinging_doors'):
        for r in d.get(k, []) or []:
            pass  # enumerate sorted(r.keys()) -> no lock keys
PY
```

The 10 door-bearing files and 287 door records are listed in §5.3.

### C5 — scene variant lock counts

```bash
python3 - <<'PY'
import json, collections
v = json.load(open('game/data/generated/scene_variants.json'))['variants']
for x in v:
    for o in x.get('overrides', []):
        if 'Locks.Doors' in o['tag'] or 'Locks.Windows' in o['tag']:
            print(o['tag'], o['type'], o.get('chance'))
PY
```

Result: 222 variants, 61 lock overrides, 33 variants with a lock override
(§5.1).

### C6 — lockpick asset search

```bash
grep -ic lockpick extracted/filelist.txt                         # 41
find -L extracted/assets -type f -iname '*lockpick*' ! -name '*.import' | wc -l   # 8
find -L game/assets/ue -type f -iname '*lockpick*' ! -name '*.import' | wc -l     # 10
find -L game/assets/ue/Anims -iname '*lockpick*' | wc -l                           # 0
```

### C7 — scene-variant selection emulation (static)

The Python reimplementation of `_sv_fnv1a`, grouping and `select_scene_variants`
(`level_loader.gd:2689-2789`) evaluated the 9 door-record source maps plus
`guildhall`/`old_manor` at seeds `1`, `2`, `424242`; no selected variant had a
`Locks.Doors`/`Locks.Windows` override. This matches the structural argument in
§5.3 (no lock-bearing variant `map_id` equals or is a substring of any door
source map).

### C8 — lockpick cancel / pause test search

```bash
grep -rn 'CANCEL\|lockpick' game/tests | head -50
grep -rn 'pause\|paused'    game/tests | head -120
find game/tests -iname '*lock*' -o -iname '*pause*'
```

---

## Appendix A — full case-insensitive `lock` key universe (200 keys)

Generated by:

```bash
grep -rho '"[^"]*[Ll][Oo][Cc][Kk][^"]*"[[:space:]]*:' extracted/json --include='*.json' \
  | sed 's/[[:space:]]*:$//' | sed 's/^"//;s/"$//' \
  | sort | uniq -c | sort -rn
```

Caveat: `lock` is a substring of `block`; 47 of the 200 keys are block/blocker
false positives. The domain keys that matter for this lane are `_lockConfig`,
`_locked`, `MaxLockLevel`, `MinLockLevel`, `CanBeLockpicked`, `KeyTag`,
`KeyItemInfo`, `LockpickableDirection`, `_lockDirection`, `RelockDirection`,
`UnlockType`, `UnlockConditions`, `HiddenIfLocked`, `unlockRequirement`,
`LockCombinations`, `TATCombinationLock`, `DamageByLockLevel`.

| Key | Occurrences |
|---|---:|
| `TATSecurityLockdown` | 571 |
| `bLockEdges` | 538 |
| `bLockColorBounaries` | 538 |
| `OnSecurityLockdownStateChanged` | 478 |
| `_lockedSpawnerComponent` | 451 |
| `bForceRootLock` | 408 |
| `_lockConfig` | 319 |
| `_securityLockdownComponent` | 293 |
| `MaxLockLevel` | 261 |
| `EditorLockFront` | 250 |
| `_locked` | 181 |
| `LockBillboardFront` | 143 |
| `LockBillboardBack` | 143 |
| `TagsThatBlock_59_4C1CB52447E8B54792038896C1A8FB08` | 77 |
| `unlockRequirement` | 70 |
| `UnlockConditions` | 70 |
| `HiddenIfLocked` | 70 |
| `BlockerWardDynMat` | 63 |
| `BlockerMeshesRoot` | 63 |
| `ActivationBlockedTags` | 59 |
| `UnlockType` | 58 |
| `_lockDirection` | 48 |
| `MinLockLevel` | 45 |
| `LockpickableDirection` | 40 |
| `CanBeLockpicked` | 37 |
| `EditorLockIndicatorRoot` | 35 |
| `EditorLockBack` | 35 |
| `BlockedPathSentinel` | 35 |
| `blockedTags` | 24 |
| `RelockDirection` | 19 |
| `RootMotionRootLock` | 15 |
| `LockArrowZTranslation` | 14 |
| `BP_MagneticLockComponent` | 12 |
| `UnlockedInteractStatusTag` | 11 |
| `LockedInteractStatusTag` | 11 |
| `LockPlayerController` | 9 |
| `LockCombinations` | 8 |
| `LockedAxis` | 7 |
| `_lockdownAllowedDirections` | 7 |
| `bBlockingHit` | 7 |
| `WidthInBlocks` | 6 |
| `LoadoutSlotBlocks` | 6 |
| `HeightInBlocks` | 6 |
| `UnlockedBonusRewardsBitmask` | 5 |
| `Block (Layer)` | 5 |
| `StartLockpickMinigame` | 4 |
| `SM_LargeSafe_Fancy_Lock_Bar` | 4 |
| `SM_LargeSafe_Fancy_Lock02_Rotate` | 4 |
| `SM_LargeSafe_Fancy_Lock01_Rotate` | 4 |
| `MobileTextBlockScale` | 4 |
| `LockFlag` | 4 |
| `GetLockpickCursor` | 4 |
| `EndLockpickMinigame` | 4 |
| `UnlockableContentDA` | 3 |
| `TATCombinationLock` | 3 |
| `_previewLockpickTrack` | 3 |
| `CuckooClock` | 3 |
| `UpdateEditorLock` | 2 |
| `UnlockableContent` | 2 |
| `TargetBlockedTags` | 2 |
| `Show Locked Frame` | 2 |
| `ShouldAbilityBlockPlayerPromptsWhilstHeld` | 2 |
| `SetDataFromUnlockableContent` | 2 |
| `SetAvailabilityFromUnlockableContent` | 2 |
| `Plane_Reverse_GI_Blocker` | 2 |
| `MoneyBlockNotQuest1` | 2 |
| `LockableActor` | 2 |
| `HealthBlockPercentages` | 2 |
| `DeskClock` | 2 |
| `bOnlyBlockingHits` | 2 |
| `bLockOutgoing` | 2 |
| `UpdateBlockingCollision` | 1 |
| `UnlockableTag` | 1 |
| `UnlockablesEntriesDA` | 1 |
| `UnlockableContent_0` | 1 |
| `_unlockableContent` | 1 |
| `Tut_Smoke_Bomb_Blocks_LOS` | 1 |
| `Tut_Objective_Unlock_Door` | 1 |
| `Tut_Objective_Unlock_Chest` | 1 |
| `Tut_Objective_Lockpick` | 1 |
| `Tut_Learn_Lockpicking` | 1 |
| `Tut_Info_Lockpicking` | 1 |
| `TryGetLockpickableActor` | 1 |
| `TryAddUnlockableToolToBlackMarket` | 1 |
| `TryAddUnlockableGuildPerkToBlackMarket` | 1 |
| `TryAddUnlockableCustomizationToBlackMarket` | 1 |
| `Tools_Deploy_Lock_Target` | 1 |
| `ToggleLockPlayerController` | 1 |
| `TATAvailableUnlocks` | 1 |
| `TargetLockEffectHandle` | 1 |
| `TargetBlockingTags` | 1 |
| `SourceBlockedTags` | 1 |
| `SM_StreetClock` | 1 |
| `SM_LootableKeys_LockedRoomKey` | 1 |
| `SetUnlockData` | 1 |
| `SetLockVisuals` | 1 |
| `SetLockedState` | 1 |
| `SetChameleonLockedState` | 1 |
| `SetBlockPlayerVisibility` | 1 |
| `Screen.Stat.Lockpicks` | 1 |
| `Screen.PostMatch.Unlocks` | 1 |
| `Screen.Ledger.Contract.Status.Locked` | 1 |
| `RevealUnlocks` | 1 |
| `RevealSingleUnlock` | 1 |
| `RemoveAlertnessDecayBlockIfNeeded` | 1 |
| `Pragma.Error.UnableToGetUnlockables` | 1 |
| `PlayerStats.Locks.Picked` | 1 |
| `Ping.Unlocked` | 1 |
| `Ping.Locked` | 1 |
| `_overrideLockdownDirections` | 1 |
| `_overrideLockdownAllowedDirections` | 1 |
| `OnUnlockContentComplete` | 1 |
| `OnPickpocketTargetLocked` | 1 |
| `OnLockpickSuccessAnimationFinished__DelegateSignature` | 1 |
| `OnLockpickSuccessAnimationFinished` | 1 |
| `OnCheckContentUnlockedComplete` | 1 |
| `OnAvailableUnlocksChanged` | 1 |
| `MaximumFacingAngleToBlock` | 1 |
| `Loot.MoneyBlock` | 1 |
| `Loot.DeskClock` | 1 |
| `LockpickMinigameVariationDataAsset` | 1 |
| `Lockpicking.Term.Jammed` | 1 |
| `Lockpicking.Prompt.Interact` | 1 |
| `Lockpicking.Pompt.Start` | 1 |
| `LockPicking.Lock.NoPicking` | 1 |
| `LockPicking.Lock.NoKeyLock` | 1 |
| `LockPicking.Lock.Level` | 1 |
| `LockPicking.Lock.KeyUnlock` | 1 |
| `LockPicking.Lock.KeyRequired` | 1 |
| `LockPicking.Lock.KeyLock` | 1 |
| `LockPicking.Lock.Combination` | 1 |
| `Lockpicking` | 1 |
| `LockPicked` | 1 |
| `LockpickAttemptAbilityClass` | 1 |
| `LockJammed` | 1 |
| `Locked.Vault.IncorrectKey` | 1 |
| `IsInteractionBlocked` | 1 |
| `IsDoorLocked` | 1 |
| `Interaction.Status.Locked` | 1 |
| `InpActEvt_IA_Ability_Block_K2Node_EnhancedInputActionEvent_38` | 1 |
| `InitLockpickUI` | 1 |
| `InitializeXPUnlockEntry` | 1 |
| `healthBarBlockAlignment` | 1 |
| `GetUnlockables` | 1 |
| `GetTimeSinceLockpickStart` | 1 |
| `GameplayCue_Unlock` | 1 |
| `FriendList.Block` | 1 |
| `_forceMoveToRequestsToBlockPathfinding` | 1 |
| `ExecuteUbergraph_GA_Lockpick_TrackInteract_Jammed` | 1 |
| `ExecuteUbergraph_GA_Lockpick_TrackInteract_Broken` | 1 |
| `ExecuteUbergraph_GA_Lockpick_TrackInteract_Attempt` | 1 |
| `ExecuteUbergraph_GA_Lockpick_Cancel` | 1 |
| `ExecuteUbergraph_GA_Lockpick` | 1 |
| `ExecuteUbergraph_GA_Hauntstable_BlockSenses` | 1 |
| `ExecuteUbergraph_GA_CombinationLock_Use` | 1 |
| `ExecuteUbergraph_GA_CombinationLock_Attempt` | 1 |
| `ExecuteUbergraph_BP_WardZone_Blocker` | 1 |
| `ExecuteUbergraph_BPUI_XPUnlock` | 1 |
| `ExecuteUbergraph_BPUI_Tutorial_Video_Lockpicking` | 1 |
| `ExecuteUbergraph_BPUI_Reticle_TargetLock_Base` | 1 |
| `ExecuteUbergraph_BPUI_LockpickTrackEnd` | 1 |
| `ExecuteUbergraph_BPUI_LockpickScreen` | 1 |
| `ExecuteUbergraph_BPUI_LockpickMinigame` | 1 |
| `ExecuteUbergraph_BPUI_LockpickCursor` | 1 |
| `ExecuteUbergraph_BPUI_HealthBlocksAttributeBar` | 1 |
| `ExecuteUbergraph_BPUI_CombinationLockWidget` | 1 |
| `ExecuteUbergraph_BPUI_CombinationLock_Digit` | 1 |
| `ExecuteUbergraph_BP_CuckooClock_Tool` | 1 |
| `ExecuteUbergraph_BP_CuckooClock_Projectile` | 1 |
| `ExecuteUbergraph_BP_ActiveCuckooClock_WorldActor` | 1 |
| `Escape.BlockPlayer` | 1 |
| `ErrorMagneticallyLocked` | 1 |
| `EndDoorLockedWaitTasks` | 1 |
| `EarlyUnlockThresholdSeconds` | 1 |
| `DamageByLockLevel` | 1 |
| `CuckooClock_Tool_Description` | 1 |
| `CuckooClock_Tool` | 1 |
| `CityMap.Locked` | 1 |
| `CheckIfItemIsUnlocked` | 1 |
| `CanLockDoor` | 1 |
| `_canJoinLockdown` | 1 |
| `CancelLockpicking` | 1 |
| `BPUI_LockpickMinigame` | 1 |
| `BndEvt__BP_WardZone_Blocker_ZoneCollision_K2Node_ComponentBoundEvent_0_ComponentHitSignature__DelegateSignature` | 1 |
| `BndEvt__BPUI_StartMenuOptions_BPUI_MainMenuButton_BlockPlayer_K2Node_ComponentBoundEvent_0_ButtonClick__DelegateSignature` | 1 |
| `BndEvt__BPUI_EndMatchXPScreen_UnlocksList_K2Node_ComponentBoundEvent_2_OnListEntryInitializedDynamic__DelegateSignature` | 1 |
| `BndEvt__BP_ThievesDen_AvailableUpgradeNotifier_TATAvailableUnlocks_K2Node_ComponentBoundEvent_0_OnAvailableUnlocksChanged__DelegateSignature` | 1 |
| `BndEvt__BP_SecurityTurret_TATSecurityLockdown_K2Node_ComponentBoundEvent_3_SecurityLockdownStateChanged__DelegateSignature` | 1 |
| `_blockedTags` | 1 |
| `_blockedEnterTags` | 1 |
| `bLocked` | 1 |
| `Block` | 1 |
| `bIsLocked` | 1 |
| `bBlockOnSlowStreaming` | 1 |
| `Availability.Locked` | 1 |
| `Audio_Weapon_HandleBlockEvent` | 1 |
| `AttemptLockPick` | 1 |
| `ApplyAlertnessDecayBlockIfNeeded` | 1 |
| `AnimateEarlyUnlockAttempt` | 1 |
| `_allowLockWhenOff` | 1 |

## Appendix B — class-default (`RF_ClassDefaultObject`) `_lockConfig` / `_locked`

The 31 class-default `_lockConfig` records (all from the 44 raw `_lockConfig`
files; none are placed actors). This is why raw `_lockConfig` (319) is larger
than placed configs (288).

| Class | `_lockConfig` |
|---|---|
| `BP_ChestTrunk_MajorLoot_C` | `{MaxLockLevel: 3}` |
| `BP_ChestTrunk_C` | `{MaxLockLevel: 4, LockedInteractStatusTag, UnlockedInteractStatusTag}` |
| `BP_BookcaseB_C` | `{LockedInteractStatusTag, UnlockedInteractStatusTag}` |
| `BP_Dumbwaiter_C` | `{MaxLockLevel: 1, CanBeLockpicked: true}` |
| `BP_UtilityBoxA_MinorLoot_C` | `{MaxLockLevel: 2}` |
| `BP_UtilityBoxA_C` | `{LockedInteractStatusTag, UnlockedInteractStatusTag}` |
| `BP_UtilityBoxB_C` | `{LockedInteractStatusTag, UnlockedInteractStatusTag}` |
| `BP_Urban_Ext_BayWindow_C` | `{MaxLockLevel: 2, CanBeLockpicked: true}` |
| `BP_Urban_Ext_Doorway_4x6_C` | `{MaxLockLevel: 3}` |
| `BP_Urban_Window_4x6_C` | `{MaxLockLevel: 2, CanBeLockpicked: true}` |
| `BP_Civic_BigWindow_6x8_C` | `{MaxLockLevel: 2}` |
| `BP_Civic_DoorB_Wall_Ext_6x6_C` | `{MaxLockLevel: 2}` |
| `BP_Civic_WindowC_6x8_Closed_C` | `{MaxLockLevel: 2}` |
| `BP_Civic_WindowC_6x8_C` | `{MaxLockLevel: 2}` |
| `BP_Manor_WindowB_4x650_C` | `{MinLockLevel: 2, MaxLockLevel: 2}` |
| `BP_Manor_Bookcase_Cabinet_MajorLoot_C` | `{MaxLockLevel: 3}` |
| `BP_Manor_Bookcase_Cabinet_MinorLoot_C` | `{MaxLockLevel: 2}` |
| `BP_Manor_Bookcase_Cabinet_C` | `{LockedInteractStatusTag, UnlockedInteractStatusTag}` |
| `BP_Manor_Doorway_Shutterdoor_Single_C` | `{MaxLockLevel: 1}` |
| `BP_Manor_WindowB_4x6_C` | `{MinLockLevel: 2, MaxLockLevel: 2}` |
| `BP_Manor_WindowB_4x8_C` | `{MinLockLevel: 2, MaxLockLevel: 2}` |
| `BP_Res_Int_Doorway_C` | `{MaxLockLevel: 2}` |
| `BP_Manor_Displaycase_C` | `{LockedInteractStatusTag, UnlockedInteractStatusTag}` |
| `BP_DisplayCaseA_MajorLoot_C` | `{MaxLockLevel: 3}` |
| `BP_DisplayCaseA_C` | `{LockedInteractStatusTag, UnlockedInteractStatusTag}` |
| `BP_LargeFancySafe_C` | `{MaxLockLevel: 4, LockedInteractStatusTag, UnlockedInteractStatusTag}` |
| `BP_SmallSafe_MajorLoot_C` | `{MaxLockLevel: 3}` |
| `BP_SmallSafe_C` | `{MaxLockLevel: 4, LockedInteractStatusTag, UnlockedInteractStatusTag}` |
| `BP_SwingingDoor_C` | `{MaxLockLevel: 4, LockedInteractStatusTag, UnlockedInteractStatusTag}` |
| `BP_SlidingWindow_Base_C` | `{CanBeLockpicked: false}` |
| `BP_OSESimpleWindow_C` | `{MaxLockLevel: 4, LockedInteractStatusTag, UnlockedInteractStatusTag}` |

The 6 class-default `_locked` values are:

| Class | `_locked` |
|---|---|
| `BP_LargeFancySafe_C` | `true` |
| `BP_SmallSafe_C` | `true` |
| `BP_SlidingWindow_Base_C` | `true` |
| `BP_Dumbwaiter_C` | `false` |
| `BP_SmallSafe_MajorLoot_C` | `false` |
| `BP_Urban_Window_4x6_C` | `false` |

These CDO values are blueprint defaults; §1's placed records are the cooked
per-instance values and are counted separately from these 31 defaults. No
placed `_locked` value is derived from a CDO in this fact sheet.
