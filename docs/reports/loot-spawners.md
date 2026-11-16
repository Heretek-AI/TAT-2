# Loot-spawner wave — real actors at the 546 mission loot markers

Spawns the actual loot actors at all `BP_MissionSpawner_MinorLoot_C` (543)
and `BP_MissionSpawner_MajorLoot_C` (3) markers: bucket-weighted actor
classes, real meshes, and `DT_LootInfo_*` names/values — plus the contract
quest item through the `loot_tag -> actor` map.

## 1. Bucket -> class -> mesh (all extracted, existence-checked)

Source tool: `tools/parse_loot.py` ->
`game/data/generated/gameplay/loot_actors.json`
(20 weighted minor entries / 7 unique classes, 60 weighted major entries /
13 unique classes; every bucket-actor `mesh_res` verified on disk at parse
time — the parser asserts and fails closed on a missing mesh).

| Bucket | Class (weight) | Mesh | Table.Row | Name | Value |
|---|---|---|---|---|---|
| MinorLoot | BP_LootActor_Minor_JewelKnife_C x2 | SM_JeweledKnifeA | DT_LootInfo_Minor.JewelKnife | Jewel Knife | 180 |
| MinorLoot | BP_LootActor_Minor_Purse_C x4 | SM_PurseA | DT_LootInfo_Minor.Purse | Purse | 45 |
| MinorLoot | BP_LootActor_Minor_SilverPitcher_C x2 | SM_PitcherUpperSilverA | DT_LootInfo_Minor.SilverPitcher | Silver Pitcher | 100 |
| MinorLoot | BP_LootActor_Minor_SilverPlatter_C x2 | SM_PlatterUpperSilverA | DT_LootInfo_Minor.SilverPlatter | Silver Platter | 100 |
| MinorLoot | BP_LootActor_Minor_TrinketGlobe_C x2 | SM_TrinketGlobe | DT_LootInfo_Minor.TrinketGlobe | Globe Trinket | 100 |
| MinorLoot | BP_LootActor_Minor_WritingSet_C x4 | SM_WritingSetUpperA | DT_LootInfo_Minor.WritingSet | Writing Set | 45 |
| MinorLoot | BP_LootActor_ServantBell_C x4 | SM_ServantBellA | DT_LootInfo_Minor.ServantBell | Servant Bell | 45 |
| MajorLoot | BP_LootActor_Major_CatStatue_C x9 | SM_CatStatueA | DT_LootInfo_Major.CatStatue | Cat Statue | 225 |
| MajorLoot | BP_LootActor_Major_Chalice_C x9 | SM_ChaliceB | DT_LootInfo_Major.Chalice | Chalice | 225 |
| MajorLoot | BP_LootActor_Major_CheeseWheel_C x1 | SM_LootCheese | DT_LootInfo_Major.CheeseWheel | Cheese Wheel | 1000 |
| MajorLoot | BP_LootActor_Major_CrownGoldA_C x1 | SM_Crown_GoldA | DT_LootInfo_Major.CrownGoldA | Golden Crown | 1000 |
| MajorLoot | BP_LootActor_Major_FabergeEgg_C x1 | SM_FabergeEggA | DT_LootInfo_Major.FabergeEgg | Jeweled Egg | 1000 |
| MajorLoot | BP_LootActor_Major_GobletGoldA_C x9 | SM_Goblet_GoldA | DT_LootInfo_Major.GobletGoldA | Golden Goblet | 225 |
| MajorLoot | BP_LootActor_Major_GoldBars_C x2 | SM_GoldBar_03 | DT_LootInfo_Major.GoldBars | Gold Bars | 650 |
| MajorLoot | BP_LootActor_Major_Hippo_C x9 | SM_HippoArtifactA | DT_LootInfo_Major.HippoStatue | Hippo Statue | 225 |
| MajorLoot | BP_LootActor_Major_LootBookA_C x2 | SM_LootBookA | DT_LootInfo_Major.MagicalTomeA | Magical Tome | 650 |
| MajorLoot | BP_LootActor_Major_LootBookB_C x2 | SM_LootBookB | DT_LootInfo_Major.MagicalTomeB | Magical Tome | 650 |
| MajorLoot | BP_LootActor_Major_LootBookC_C x5 | SM_LootBookC | DT_LootInfo_Major.MagicalTomeC | Magical Tome | 375 |
| MajorLoot | BP_LootActor_Major_OwlStatue_C x5 | SM_StatueOwlA | DT_LootInfo_Major.OwlStatue | Owl Statue | 375 |
| MajorLoot | BP_LootActor_Major_UrnGoldA_C x5 | SM_Urn_Gold_01 | DT_LootInfo_Major.UrnGoldA | Golden Urn | 375 |

Godot GLBs live under `res://assets/ue/Content/...` (full paths in
`loot_actors.json`, e.g. `.../Art/Gameplay/Loot/LootMinor/Purse/SM_PurseA.glb`).

Mesh-choice notes (rule: SCS `StaticMeshComponent` tagged `Interact` wins,
else the primary mesh — the component named `StaticMesh_GEN_VARIABLE` —
else the first static mesh):

- No loot-actor Blueprint carries an `Interact` tag on a
  `StaticMeshComponent` (all 20 bucket + 44 quest actors resolve `primary`).
  `Interact` tags appear only on `InstancedStaticMeshComponent` proxies
  (e.g. the `SM_NoteEnvelopeA` proxy next to the real `SM_CursedIdol` on
  BerlinStatue); the proxy path is recorded as `interact_proxy_ue_path`
  but is never spawned as the loot visual.
- `BP_LootActor_Major_UrnGoldA` has two static meshes: the urn cap
  (`SM_UrnCap_Gold_01_GEN_VARIABLE`) and the urn body
  (`StaticMesh_GEN_VARIABLE` = `SM_Urn_Gold_01`); the primary rule picks
  the body. The reliquary `Glass_GEN_VARIABLE` display cover loses to the
  same rule and is never treated as loot.
- 44 quest actors parsed (40 `BP_LootActor_Quest_*` + 4
  `BP_QuestLootActor_*`); `tag_to_actor` maps 43 `loot_tag`s whose RowName
  matches an `interactables.json` row.

## 2. Per-map marker counts (loader result, shipped maps)

| Map | Minor | Major | Source files |
|---|---|---|---|
| old_manor | 293 | 0 | OldManor_Loot (280), OldManor_Gameplay (7), OldManor_Clues (6) |
| guildhall | 250 | 3 | Guildhall_Loot (245 + 3 major), Guildhall_Gameplay (5) |
| jaspering_hall | 0 | 0 | — |
| thieves_den | 0 | 0 | — (hub spawns no loot, unchanged) |
| **Total** | **543** | **3** | **546 markers** |

Contract-specific sublevels (`Guildhall_Contract_*`,
`OldManor_Contract*`) carry no `MissionSpawner_Minor/MajorLoot` markers
(their `BP_QuestSpawner_Item_C` markers still feed the legacy `loot_spawns`
and clue placement), so counts are stable across contract orders.
`level_loader.gd` exposes `minor_loot_spawns / major_loot_spawns` (each
`{pos, rotation, class, source_file}`; rotation = marker basis as euler
degrees) plus `minor/major_loot_spawn_count` stats; the legacy `loot_spawns`
Vector3 array is byte-for-byte unchanged for compatibility.

## 3. Value mapping

Names/values come from `interactables.json` (A7) keyed by RowName, so the
parser and the Godot runtime read the same numbers — no second table to
drift. Minor 45–180, major 225–1000, quest per-row (flagship 2500).
Sampled in the temp check: Purse 45, ServantBell 45, FabergeEgg 1000 —
all match `interactables.json`.

## 4. Runtime behaviour

- `mission_controller.gd::_spawn_loot_and_quest` spawns one `LootScript`
  per minor/major marker. The actor class is picked deterministically from
  the weighted bucket list (`_loot_bucket_index`: pure function of marker
  position + order, no RNG), carrying the real `mesh_path`, `item_name`,
  `value`, `loot_tier` (`is_quest_item=false`) and the marker rotation.
- The contract quest item occupies the **last minor marker** (last major
  when a map has no minors), so node count == marker count exactly and
  every position stays unique (plus a deterministic +Y nudge guard). It
  resolves `contract_info["loot_tag"]` through `tag_to_actor` with the
  real row name/value, e.g. contract 2 -> `BP_LootActor_Quest_VistaraFiles_C`
  (`SM_NoteEnvelopeA.glb`, "Vistara Files", 1000).
- Escape setup, group membership (`interactables`, `loot`,
  `thief_vision_highlight`) and the Thieves' Den skip are unchanged. When
  `loot_actors.json` is unreadable, spawns fall back to the old tier-entry
  pool with legacy meshes (labelled fallback, same node counts).
- `loot_item.gd`: new `mesh_path`, `mesh_rotation_deg`, `display_name`
  exports; instantiates the real GLB on the visual root (rotation applied),
  keeps authored-unit scale 1.0 when the assembled prop already reads as a
  hand prop (max dimension 0.08–1.6 m), else rescales uniformly to the tier
  target (minor 0.35 m / major 0.55 m / quest 0.45 m) — deterministic, never
  random. The name label now shows for major + quest items. The procedural
  box appears only when the mesh file is missing.

## 5. Quest fallback note

All 16 shipped JSON contracts resolve to a dedicated actor — **including
contract 2's `Loot.Quest.VistaraFiles`**
(`BP_LootActor_Quest_VistaraFiles_C`, envelope mesh, value 1000), contrary
to the stage brief's expectation that it had no matching file; the temp
check asserts exactly this mapping. Quest table rows with no actor are
`Diamond`, `Diamond_Temp`, `Example.Diamond`, `OrbOfScrying` (none is a
contract tag). The two code-appended expansion contracts (17 `BlueMalcolm`,
18 `OberonSeal`) have neither an actor nor a quest row, so they take the
documented generic path: `BP_LootActor_Quest_Abbessford_Northgate_60_Piety_C`
(first quest-tier actor with an existing mesh), flagship value 2500, real
contract `quest_item` name. Actors whose mesh is missing on disk keep
`mesh_res: ""` and get the box fallback: the two CarrazReliquary variants
(`ReliquaryLoot.glb` absent — only the skeletal `SK_ReliquaryLoot.glb`
exists) and the coin actors (individual `Coin_*` GLBs absent, only
`SM_CoinPileA.glb`) — none on the shipped-contract path.

## 6. Temp-check output (`game/tests/_tmp_loot_check.gd`, deleted after)

```
LOOTCHECK files=73 minor=543 major=3 loot_spawns=546
PASS: loader minor total 543 (got 543)
PASS: loader major total 3 (got 3)
PASS: loot_spawns compat preserved (>=546, got 546)
PASS: old_manor minor 293 (got 293)
PASS: guildhall minor 250 (got 250)
PASS: guildhall major 3 (got 3)
PASS: minor/major entry shape (pos/rotation/class), class strings kept
PASS: loot_actors.json readable + parses
PASS: minor bucket 20 weighted entries
PASS: major bucket 60 weighted entries
PASS: 20 unique bucket actors (got 20)
PASS: all bucket actor meshes exist []
PASS: rows Purse / ServantBell / FabergeEgg resolve + values 45 / 45 / 1000
PASS: VistaraFiles tag mapped to BP_LootActor_Quest_VistaraFiles_C
PASS: VistaraFiles value 1000 (got 1000)
TAT-2 Loaded guildhall: meshes=16970 lights=96
TAT-2 Perf: chunks=4860 collision_bodies=170 collision_shapes=8838 occluders=768
TAT-2 spawners: throwable=133 ammo=45 health=5 civilian=3
LOOTCHECK guildhall loot nodes=253
PASS: guildhall 252 regular + 1 quest = 253 (got 253)
LOOTCHECK quest item=Vistara Files value=1000 mesh=res://assets/ue/Content/Art/Gameplay/Clues/Notes/SM_NoteEnvelopeA.glb
PASS: all loot positions unique (dups=0)
PASS: exactly one quest item (got 1)
PASS: quest item is Vistara Files/1000 with real mesh
SUMMARY: fails=0
```

Measured raw GLB extents (max dimension, metres) — all inside the
0.08–1.6 m keep band, so every bucket mesh ships at authored scale 1.0 and
`_fit_prop_scale` never fires on current content: JewelKnife 0.386, Purse
0.308, SilverPitcher 0.544, SilverPlatter 0.931, TrinketGlobe 0.540,
WritingSet 0.391, ServantBell 0.244, CatStatue 0.547, Chalice 0.437,
CheeseWheel 0.443, CrownGoldA 0.358, FabergeEgg 0.462, GobletGoldA 0.317,
GoldBars 0.294, Hippo 0.553, LootBookA 0.487, LootBookB 0.494, LootBookC
0.594, OwlStatue 0.469, UrnGoldA 0.364.

## 8. Full suite (`make test`, after deleting the temp check)

`SUMMARY: fails=0`, exit 0, zero `SCRIPT ERROR` lines. Suites 4/7/10 green:
Old Manor (contract 3) spawns 6 guards and 293 loot items (292 regular +
1 quest), Thieves' Den hub peaceful (0 guards), Guildhall ground/raycast
verified. The single `ERROR` line in the log is Godot's benign
at-exit RID-leak notice, unrelated to the tests.

## 9. Performance note

Guildhall (contract 2) spawns 253 loot `Area3D`s (each: sphere trigger +
visual root + instanced GLB + `Label3D`) on top of the existing
16 970-mesh / 4 860-chunk level; Old Manor spawns 293 + 1. Loot visuals
carry no static physics and no shadow/occluder registration (level loader
only chunks level meshes), so the added cost is ~546 draw nodes + trigger
shapes, well within the chunking/culling budget the suite asserts
(chunks 4860, culled nodes in the thousands). No new per-frame work:
`loot_item._process` still only rotates the visual root.
