# Loot Containers — implementation report

The 234 placed loot containers are openable and grant real loot. Container
meshes were already in the level geometry and are **not** duplicated: the new
`loot_container.gd` is an Area3D trigger only (zero mesh children verified).

## Class -> kind -> bucket -> loot table

Source: `game/data/generated/gameplay/containers.json` (new
`tools/parse_containers.py`; `tools/parse_loot.py` untouched). Slot entries
are raw UE centimetres + FRotator degrees from each
`TATContainerSpawnerComponent`.

| Container class | Kind | Bucket | Slots (offset cm / rotation deg) |
|---|---|---|---|
| `BP_ChestTrunk_MajorLoot_C` | major | `DA_SpawnBucket_MajorLoot` | 1x `[0,0,50]/[0,0,0]` (+ minor bonus spawner `DA_SpawnBucket_MinorLoot` recorded under `extra_spawners`, not spawned) |
| `BP_DisplayCaseA_MajorLoot_C` | major | `DA_SpawnBucket_MajorLoot` | 1x `[0,-5,61]/[0,0,0]` |
| `BP_Storefront_DisplayCaseB_MinorLoot_C` | minor | `DA_SpawnBucket_MinorLoot` | 1x `[-50,50,100]/[0,15,0]` |
| `BP_Storefront_DisplayCaseD_MinorLoot_C` | minor | `DA_SpawnBucket_MinorLoot` | 2x `[-50,50,65]/[0,15,0]` + `[-150,50,65]/[0,-15,0]` (first slot used) |
| `BP_LootStashInteractable_Secret_ThinWall_C` | none | — (no spawn bucket) | — |

Buckets (from A16 `loot_actors.json`, reused unchanged):
- Major: 60 weighted entries / 13 unique actor classes
  (e.g. `BP_LootActor_Major_FabergeEgg_C` = "Jeweled Egg", 1000,
  `SM_FabergeEggA.glb`, mesh exists).
- Minor: 20 weighted entries / 7 unique actor classes
  (e.g. `BP_LootActor_Minor_Purse_C` = "Purse", 45, `SM_PurseA.glb`,
  mesh exists).

`open_interact` is `null` for all five classes: no Interact tags/durations
are authored on these Blueprints (or their parents), so opening is instant.

## Per-map counts (normalized markers, `class` census)

| Map (tatlevel files) | ChestTrunk | DisplayCaseA | Stash | StorefrontB | StorefrontD | Total |
|---|---|---|---|---|---|---|
| OldManor (Loot 41+37, PickUps stash 31, Gameplay stash 1) | 41 | 37 | 32 | 0 | 0 | 110 |
| Guildhall (Loot 48+31, Gameplay stash 24) | 48 | 31 | 24 | 0 | 0 | 103 |
| FTUE / Jaspering Hall (JewelryStore B 4 + D 12, Gameplay stash 1) | 0 | 0 | 1 | 4 | 12 | 17 |
| Facade_Storefront_Cluster (not loaded by any mission) | 0 | 0 | 0 | 2 | 2 | 4 |
| **Total** | **89** | **68** | **57** | **6** | **14** | **234** |

## Open behaviour (`game/src/interact/loot_container.gd`)

- Spawned by `mission_controller._spawn_loot_containers()` after the loot
  wave, one node per `loot_containers` marker (Thieves' Den hub skipped like
  loot). Area at the marker transform (position + orthonormalized rotation;
  marker scale recorded but never applied to the trigger).
- Prompt `[F] OPEN` (via `interact`), one-shot: guarded by `opened` flag +
  meta, so repeat interacts spawn nothing.
- Major/minor: picks one class from the mapped bucket deterministically
  (`bucket_index`, same position-hash formula as the mission loot wave),
  spawns a `loot_item.gd` with the real mesh/name/value/tier at
  marker position + slot offset (UE cm -> Godot m with the extractor's Y/Z
  swap, rotated by the marker basis) and slot rotation (FRotator conjugated
  into Godot space, composed with the marker basis).
- `kind:none` (secret stash): marks opened, spawns zero loot, no error. Its
  real meshes (`SM_Stash_ThinWallA_Base/DoorLeft/DoorRight/Glow`) are level
  geometry; no loot is invented. Its loot arrives as separately placed actors.
- Groups: `interactables` (+ `loot_containers` for counting). No physics
  body (Area only, layer/mask 0), no `_process`, no meshes.

## Loader (`game/src/core/level_loader.gd`)

- `result["loot_containers"]`: array of `{class, pos, basis, scale}` from the
  five container marker classes. All existing keys untouched.
- `result["loot_container_count"]` stat (234 across shipped maps).

## Verification

Temp async-mission check (`game/tests/_tmp_container_mission.gd`, guildhall
contract 4; deleted after the run — one-line syntax fix applied vs. draft:
`in ["major", "minor"]`, GDScript has no tuple literals):

```
TAT-2 Loaded guildhall: meshes=16973 lights=96
TAT-2 loot containers: 103
CONTAINERS expected=103 nodes=103 wait_frames=115
OPEN tier=major before=253 after=254 after2=254 opened=true duplicated_meshes=0
PASS: containers spawn and open one real loot item, no duplicated meshes
```

- 103 container nodes = `loot_container_count` for the guildhall mission
  (48 + 31 + 24), all with unique marker transforms.
- Opening a major chest: exactly one new `loot` node (253 -> 254), second
  open stays at 254, `opened=true`, zero `MeshInstance3D` under any container.
- `make test`: `SUMMARY: fails=0`, exit 0, zero `SCRIPT ERROR`
  (Old Manor mission now reports 293 loot items; all 20 existing checks pass,
  including Thieves' Den hub with 0 guards).

## Files changed

- `tools/parse_containers.py` (new) -> `game/data/generated/gameplay/containers.json`
  (gitignored generated data, present on disk like `loot_actors.json`)
- `game/src/core/level_loader.gd` (+27)
- `game/src/missions/mission_controller.gd` (+19)
- `game/src/interact/loot_container.gd` (new)
- `docs/reports/loot-containers.md` (this file)

Not touched: `game/tests/run_tests.gd`, `loot_item.gd`, `world_pickup.gd`,
`civilian_npc.gd`, `thief_character.gd`, `guard_ai.gd`, other parsers,
extractor, Makefile, Android files. No fabricated meshes or loot.
