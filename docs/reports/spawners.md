# Spawner content wave — map pickups, bottles, civilians

Covers the 689 `BP_MissionSpawner_*` markers: real meshes for every pickup,
full-mission spawn parity, bottle throwing, and ambient civilians.

## 1. Bucket -> class -> mesh (all extracted, existence-checked)

Source tool: `tools/parse_spawners.py` -> `game/data/generated/gameplay/spawners.json`
(8 bucket entries, 4 civilian variants; every `mesh_res_path` verified on disk
at parse time — the parser asserts and fails closed on a missing mesh).

| Bucket | Kind | ClassToSpawn | Mesh (UE path) | Godot GLB (exists) | Extra extracted |
|---|---|---|---|---|---|
| DA_SpawnBucket_Bottles | throwable | BP_ItemActor_Throwable_Distraction_Bottle1 | SM_BottleWineB | `.../Props/Dining/Food/Wine/SM_BottleWineB.glb` | — |
| DA_SpawnBucket_Bottles | throwable | BP_ItemActor_Throwable_Distraction_Bottle3 | SM_BottleWineA | `.../Props/Dining/Food/Wine/SM_BottleWineA.glb` | — |
| DA_SpawnBucket_AmmoRefill | ammo | BP_AmmoRefill_Pickup | SM_Toolbox (interact mesh) | `.../Props/Containers/Toolbox/SM_Toolbox.glb` | InteractionSphereTrigger radius 35.0 cm (0.35 m); hidden `bVisible=false` decor SM_Briefcase_01/02 recorded but never spawned |
| DA_SpawnBucket_Health | health | BP_Health_Pickup | SM_HealthPackA | `.../Gameplay/Health/SM_HealthPackA.glb` | InteractDuration 1.0 s (real CDO value) |
| DA_SpawnBucket_Civilians | civilian | BP_CivilianGeneratorMale_LowerClass1 | SK_CivMale_Common_01 + SK_CivMale_Head_Adam_Fade01 | `.../CivMale/Skin/Common/SK_CivMale_Common_01.glb`, `.../Heads/SK_CivMale_Head_Adam_Fade01.glb` | full outfit/head set in JSON |
| DA_SpawnBucket_Civilians | civilian | BP_CivilianGeneratorMale_LowerClass2 | SK_CivMale_Common_01D + SK_CivMale_Head_Adam_Fade02 | both exist | — |
| DA_SpawnBucket_Civilians | civilian | BP_CivilianGeneratorFemale_LowerClass1 | SK_CivFemale_Common_01C + SK_CivFemale_Head_Abby_Short01 | both exist | — |
| DA_SpawnBucket_Civilians | civilian | BP_CivilianGeneratorFemale_LowerClass2 | SK_CivFemale_Common_01C + SK_CivFemale_Head_Abby_Braid01B | both exist | Short01 is NOT referenced by the L2 file, so the L2 representative head falls back to Braid01B (first head in its set) |

Mesh-choice notes: the ammo JSON lists the briefcases first, but both are
authored `bVisible=false` dressing — the parser skips hidden components and
resolves the visible SM_Toolbox as the interact mesh. Civilian pairs are the
canonical outfits; each generator file's full referenced set is kept in
`spawners.json` under `skeletal_meshes`.

## 2. Per-map spawn counts (loader result, shipped contracts)

| Map | Throwable | Ammo | Health | Civilian | Source files |
|---|---|---|---|---|---|
| old_manor | 385 | 97 | 7 | 2 | OldManor_Gameplay (T385 C2), OldManor_Loot (A3 H1), OldManor_PickUps (A93 H6), OldManor_Clues (A1) |
| guildhall | 133 | 45 | 5 | 3 | Guildhall_Gameplay (T125 A45 H5 C3), Guildhall_P (T8) |
| jaspering_hall | 11 | 1 | 0 | 0 | FTUE_Gameplay |
| **Total** | **529** | **143** | **12** | **5** | **689 markers** |

Contract-specific sublevels (`Guildhall_Contract_*`, `OldManor_Contract*`)
carry no spawner markers, so counts are stable across contract orders.
`level_loader.gd` exposes `throwable_spawns / ammo_spawns / health_spawns /
civilian_spawns` (absolute Vector3 positions) plus `*_spawn_count` stats;
existing marker behaviour is untouched.

## 3. Runtime behaviour

- `mission_controller.gd::_spawn_spawner_content` spawns after escape setup on
  every map (thieves_den has no spawner markers -> no-op). Throwable meshes
  alternate Bottle1/Bottle3 by index; civilian variants cycle the 4 generator
  pairs from `spawners.json` (hardcoded extracted fallbacks apply only when
  the JSON is unreadable).
- `world_pickup.gd`: trigger-only Area3D in groups `interactables`,
  `spawner_pickup`, `thief_vision_highlight`; mesh `visibility_range_end`
  45 m with self-fade, shadows off, zero static physics bodies. Single-use
  (frees itself after pickup).
- `thrown_bottle.gd`: RigidBody3D thrown by `secondary_action` when the
  player holds a bottle charge; impact (or 6 s failsafe) emits
  `NoiseBus.emit_noise(pos, 10.0, player, "bottle")` so guards investigate.
- `civilian_npc.gd`: CharacterBody3D on layer 8 / mask 1 (world grounds it,
  the player mask 1|4 never collides with it); head skinned meshes grafted
  onto the body skeleton; MM_Unarmed idle/walk retargeted by bone name via
  `animation_library.gd`; wander loop (6 m radius, idle 2-5 s pauses).
- Interaction scan cost is unchanged: the thief highlight scan already runs
  at 10 Hz (`PROP_SCAN_INTERVAL`); pickups add no physics bodies.
- HUD: hotbar line now ends with `BOTTLES:N` (follows `charges["bottle"]`).

## 4. Documented approximations (NOT extracted — cooked graphs carry none)

| Value | Implementation | Status |
|---|---|---|
| Health heal amount | full HP restore | APPROXIMATION, labelled in `world_pickup.gd` |
| Ammo refill amount | every charge key to max (slithersap 4, smoke 1, fairy 999, grapple 4, bottle 99) | APPROXIMATION, `AMMO_REFILL_MAX` |
| Bottle throw speed | 12.0 m/s + fixed spin | APPROXIMATION, `THROW_SPEED_M_S` |
| Bottle impact noise | 10.0 m radius, `"bottle"` tag | APPROXIMATION, `IMPACT_NOISE_M`; guards investigate via the standard `_on_noise_emitted` path |
| Civilian walk speed | 1.4 m/s | APPROXIMATION, `WALK_SPEED_M_S` |
| Civilian clips | generic `MM_Unarmed_IdleBreak_Fidget` (idle) + `MM_Unarmed_Walk_Fwd` (walk, root-stripped, looped); NO CivFemale clips exist in the manifest, so females use the same generic clips; zero shared bones -> rest pose + 2.2 Hz position bob | documented fallback in `civilian_npc.gd` |
| Health InteractDuration 1.0 s | real extracted CDO value, recorded in `spawners.json` | EXTRACTED (pickup itself applies instantly like other pickups) |
| Ammo trigger 35 cm | real extracted sphere value | EXTRACTED (all pickups use a 0.35 m trigger) |

No meshes, clips, or numbers were fabricated: every mesh path is an
existence-checked conversion of an extracted UE path, and every invented
number above is a labelled constant.

## 5. Verification (temp check, deleted after run)

`game/tests/_tmp_spawners_check.gd` (temporary, NOT part of `run_tests.gd`;
deleted before `make test`). Full log: final rerun `EXIT:0` with zero
`SCRIPT ERROR` / `ERROR` lines.

```
PASS: one contract order per shipped map { "guildhall": 2, "old_manor": 3, "jaspering_hall": 17 }
PASS: loader totals 529/143/12/5 across shipped maps { "t": 529, "a": 143, "h": 12, "c": 5 }
PASS: old_manor per-map spawns { "t": 385, "a": 97, "h": 7, "c": 2 }
PASS: guildhall per-map spawns { "t": 133, "a": 45, "h": 5, "c": 3 }
PASS: jaspering_hall per-map spawns { "t": 11, "a": 1, "h": 0, "c": 0 }
TAT-2 spawners: throwable=385 ammo=97 health=7 civilian=2
PASS: pickup node count matches loader nodes=489 expected=489
PASS: civilian node count matches loader nodes=2 expected=2
PASS: no duplicate spawner positions dupes=0
PASS: all three pickup kinds present in mission
PASS: health pickup restores full HP was=175.0 now=225.0
PASS: ammo pickup refills charges { "slithersap": 4, "smoke_bomb": 1, "pickpocket_fairy": 999, "grapple": 4, "bottle": 99 }
PASS: bottle pickup increments charges['bottle']
PASS: throw decrements bottle count
PASS: bottle impact emits 10m noise [{ "loud": 10.0, "tag": "bottle" }]
PASS: civilian nodes carry real body/head meshes civs=2
PASS: civilian anim player or documented rest fallback
PASS: HUD shows bottle count [1]Sap:4  [2]Smoke:1  [3]Fairy:999  [G]Grapple  |  BOTTLES:0
SUMMARY: fails=0
```

Notes: `now=225.0` equals `max_health` at the test difficulty (curve-scaled);
full-heal verified by equality with `max_health`. HUD reads `BOTTLES:0`
because the throw test consumed the picked-up bottle. One mid-course bug was
found and fixed by the check itself (head-mesh graft removed from the wrong
parent; final log is error-free).

## 6. Full suite + follow-up fixes

- `make test` after all changes: `SUMMARY: fails=0`, exit 0, zero
  `SCRIPT ERROR` lines; suites 4 (Old Manor spawns), 7 (ThievesDen hub),
  10 (Guildhall ground) all still pass.
- Follow-up fix after the green run: the male head GLB's skin binds use a
  capital-`Head` bone name while the body skeleton uses lowercase `head`,
  which printed `Skin bind #6 ... no bone by that name`. `civilian_npc.gd`
  now duplicates the head skin and remaps bind names case-insensitively
  onto the body bones (female heads already match exactly and are
  untouched). Re-ran `make test`: still `SUMMARY: fails=0`, skin error gone.
- The remaining `WARNING: 3 ObjectDB instances were leaked` /
  `ERROR: 3 RID allocations ... leaked at exit` lines also appear on the
  unmodified baseline (verified via a stashed-tree run), i.e. pre-existing
  test-teardown noise, not from this wave.
