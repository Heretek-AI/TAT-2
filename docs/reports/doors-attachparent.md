# Swinging doors — pivot-own-mesh resolution (2026-11-16)

Follow-up to `swinging-doors.md` (`caec0d4`). The previous wave resolved 170
doors / 262 leaves and counted 111 pivots as unresolved because no separate
`StaticMeshComponent` stub was attached to the pivot in the level. The handoff
asked for a second attempt through level-actor component `AttachParent` data.

## Root cause

`TATSwingingDoorPivotComponent` is itself a `StaticMeshComponent` subclass. For
doorway Blueprints such as `BP_OldManor_Doorway_4x650_C` and
`BP_Civic_Doorway_6x8_C`, the authored leaf mesh lives directly on the pivot
component template (`StaticMesh` + `RelativeLocation`), not on a separate SMC
child instanced in the level:

```
extracted/json/Art/Environment/OldManor/BP_OldManor_Doorway_4x650.json
  TATSwingingDoorPivotComponent'Pivot'
    StaticMesh = /Game/Art/Environment/OldManor/SM_OldManor_Door_150x4
    RelativeLocation = (-100, 0, 0)
  TATSwingingDoorPivotComponent'SecondPivot_GEN_VARIABLE'
    StaticMesh = /Game/Art/Environment/OldManor/SM_OldManor_Door_1x3
    RelativeLocation = (-300, ~0, 0)
```

The level stub only carries `AttachParent`/`Template`; the mesh and transform
come from the Blueprint class template. The old resolver searched only for
attached leaf stubs, so these 111 pivots were skipped.

## Fix

`tools/parse_tables.py` (`extract_levels`, swinging-door pre-pass):

- Resolve the pivot's Blueprint template once when either its transform or its
  `StaticMesh` is absent from the level stub.
- If no attached leaf stub resolves, use the pivot template's `StaticMesh` as
  the leaf. Its local transform is identity because the pivot world transform
  already contains the hinge position; the mesh inherits the pivot rotation.
- Validate the GLB exists before emitting the leaf. Pivots with no mesh and no
  GLB remain counted as unresolved, never replaced by placeholders.
- Emit `leaf_source: "pivot_static_mesh"` on these leaves so tests can prove the
  fallback was used.

No loader change was needed: `swinging_door.gd` already builds one
`MeshInstance3D` + `StaticBody3D` per `leaves` entry from the real GLB.

## Verified counts

Before (`docs/reports/swinging-doors.md`): 170 doors / 262 leaves / 111
unresolved.

After `make normalize`:

```
doors 281 leaves 373 unresolved 0
pivot_static_mesh leaves 111
Normalized 77 level JSONs -> 55452 mesh instances, 3479 lights
```

The static-mesh instance total is unchanged at 55,452, so the new leaves are not
duplicated in the static batches. All 111 resolved meshes exist as extracted
GLBs; the 111 unresolved pivots broke down as:

| Blueprint | Pivots |
|---|---:|
| `BP_OldManor_Doorway_4x650_C` | 32 |
| `BP_Prison_WallA_DoorwayB2_6x6_C` | 22 |
| `BP_Civic_Doorway_6x8_C` | 18 |
| `BP_Manor_Doorway_4x8_C` | 16 |
| `BP_Prison_WallA_DoorwayB_6x6_C` | 8 |
| `BP_Manor_Doorway_Shutterdoor_Single_C` | 5 |
| `BP_Manor_Doorway_4x8_Shutterdoors_C` | 4 |
| `BP_OldManor_Doorway_6x850_C` | 2 |
| `BP_GB_DoorSolo_C` | 2 |
| `BP_Prison_WallA_DoorwayA_6x6_C` | 2 |

## Runtime evidence

`make test` (log `/tmp/opencode/doors_test.log`, 2026-11-16):

```
PASS: Old Manor mission spawned 6 guards, 293 loot items and 120 doors / 176 leaves
PASS: pivot-mesh door swings 90 degrees (rot=1.571)
PASS: swinging-door extraction (103 levels, 281 doors, 373 leaves, 111 pivot meshes, 0 unresolved)
SUMMARY: fails=0
EXIT=0
```

The Old Manor mission previously logged `swinging doors: 64`; it now spawns 120
doors and 176 rendered leaves. The runtime test opens a door and verifies the
completed 90-degree tween (`rot=1.571`), covering the new pivot-mesh path.

## Regression guards

`game/tests/run_tests.gd`:

- Mission suite waits for the `swinging_doors` group, asserts Old Manor has at
  least 120 doors / 120 rendered leaves, and swings one door to 90 degrees.
- New extraction suite walks every `.tatlevel.json`, asserting >=281 doors,
  >=373 leaves, >=111 `pivot_static_mesh` leaves with identity local
  transforms, and zero `swinging_doors_unresolved` entries.

## Reproduce

```bash
make normalize
make test   # SUMMARY: fails=0
```
