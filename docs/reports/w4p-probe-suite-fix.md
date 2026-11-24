# W4P — subset-probe autoload fix, `--spider-only` suites 87 + 88

**Worktree:** `/tmp/opencode/tat2-w2p` @ `f1b0cbd` + this commit.
**Integration:** **not performed.** The subset probe fails on this tree (see
“Probe run”), so per the brief the cherry-pick onto `main` was skipped and
`main` was left untouched.

## What changed

1. **`game/tests/probe_personal_quest_subset.gd`** — the spawner is no longer a
   `const … preload()`. A `--script` SceneTree entry is parsed before the
   project autoloads exist, and `personal_quest_spawner.gd` (plus the
   `clue_item.gd` / `loot_item.gd` classes it preloads) names `GameState`
   directly, so the preload failed to resolve it and the probe never reached a
   map load. It is now `var PersonalQuestSpawnerScript: GDScript` loaded at the
   top of `_run()`, with a null guard — the pattern from commit `8018a83`.
   `level_loader.gd`, `light_probe.gd` and `personal_quest.gd` stay `preload()`:
   none of them names an autoload at parse time (`personal_quest.gd` resolves it
   through a runtime `_autoload()` helper).
2. **`game/tests/run_tests.gd`** — `-- --spider-only` ran suite 87 only, so the
   W4O settle suite was unreachable from the thermal shortcut. It now runs 87
   then 88, counts both into one `SUMMARY`, and still never touches the mission
   loader. Suites 86/87 and the full-suite path are unchanged.
3. **`game/tests/test_personal_quest_settle.gd`** (suite 88) — the suite was
   written for an **off-tree** host and had never been executed. Its first run
   failed every world-space assertion with
   `Condition "!is_inside_tree()" is true. Returning: Transform3D()`: an
   off-tree `Node3D` reports identity for `global_transform` / `global_position`,
   so each pin measured `(0, 0, 0)` and the “occupied primary falls back” case
   saw no occupancy. The host now lives under a `SubViewport` with
   `own_world_3d`, i.e. in-tree (real global transforms) but isolated from the
   root world. Because `_resolve_anchor()` requires a floor hit once the host is
   in-tree, every candidate pin gets a thin synthetic support slab whose top is
   at the authored y, and `run()` awaits one physics frame so the slabs reach
   the broadphase. `run(host)` is therefore a coroutine and `_run_suite88()`
   awaits it. The two NPC height checks now measure the **mesh bottom**, not the
   node origin (the same rule the real-map probe uses); those actors carry a
   sub-millimetre AABB offset.

No assertion was relaxed and no expected value moved.

## Evidence (measured)

Thermal rule for every run below: one Godot, `taskset -c 0-3`, cgroup
`MemoryMax=12G` / `MemorySwapMax=0`, 0.25 s package sampler, hard kill at
95 °C, start refused above 90 °C. Logs under `/tmp/opencode/thermal-*.log`.

### `run_tests.gd -- --spider-only`

```
THERMAL spider-only start=89000mC peak=90000mC end=85000mC rc=0 aborted=0
PASS: 87 Spider personal chain runtime (mock only)
PASS: [pq-settle] synthetic supports ground every candidate pin at its authored y (worst 0.000000 m)
PQ-SETTLE npc=courier   origin_y=27.022449 foot_y=27.021900 mesh_bottom=-0.000549 pin_y=27.0019 floor_y=27.001900
PQ-SETTLE npc=informant origin_y=10.130150 foot_y=10.129600 mesh_bottom=-0.000549 pin_y=10.1096 floor_y=10.109600
PASS: 88 Spider personal chain settle path (mock only)
SUMMARY: fails=0
```

### Probe run (one attempt, `XDG_DATA_HOME=/tmp/opencode/w2p-data`)

```
THERMAL subset start=84000mC peak=90000mC end=90000mC rc=1 aborted=0
PQ-SUBSET loaded guildhall meshes=11132 lights=160 bodies=74  shapes=8864
PQ-SUBSET loaded old_manor meshes=5483  lights=160 bodies=397 shapes=5003
PERSONAL QUEST SUBSET FAIL checks=68 fails=18
```

No thermal kill: the sampler never crossed 95 °C, so the run is a genuine
result, not a truncation.

What passed — the placement policy on the real maps:

```
PQ_PLACE kind=readable  y=pin anchor=library_note pin_y=28.0021 floor_y=28.0000 pos=(-26.8541, 28.0021, -9.4431)
PQ_PLACE kind=quest_item y=pin anchor=owl         pin_y=36.4655 floor_y=36.4645 pos=(-31.6286, 36.4655, -43.9759)
PQ-SUBSET authored surface Owl y=36.4645 lateral=0.000 pin_offset=0.0010 foot_offset=0.0011
```

plus authored XZ, flat surface, `y_source=pin`, “mesh bottom not sunk”,
authored-support and pedestal-top checks, prompts, interactability and the
letter’s HUD toast, for both props.

What failed, and why (two independent causes; 18 failures are 2 causes + their
cascade):

1. **No NPC ever spawns → courier, hand-off, 04 informant and the whole tail
   (`stage=carrying owl=held`, 5 facts).**
   `loot_item.gd:266` asks the node in the `mission` group for
   `on_personal_quest_owl_taken()`; the real provider is
   `mission_controller.gd:2631`. The probe puts the **spawner itself** in the
   group, and the spawner only has `on_owl_taken()`, so the Owl pickup advances
   the stage (`PQ-SUBSET stage=carrying owl=held`) but the courier hook is never
   called: there is no `courier spawned after Owl pickup` line and no spawner
   warning. The informant is stage-gated to `delivered`
   (`game/data/expansion/personal_spider.json`), so it can never appear either.
   The probe’s comment claiming the spawner is found “exactly as it finds the
   mission controller in play” is stale since the controller gained that hook.
2. **`letter` / `Owl` standing capsule overlaps 1 shape.**
   `_check_pin()` places the standing capsule at
   `Vector3(pin.x, floor_y + 0.02, pin.z)` where `floor_y` is the floor ray
   under the pin — on a table/pedestal that is the **support top**, so the
   capsule is stood *on the table* and a 1.75 m capsule then intersects one level
   body (wall/shelf). Since W3O props keep the authored pin instead of dropping
   to the walk floor, this check no longer describes what a player does. The
   meaningful check for a prop — “interaction LOS clear” from a direction where a
   standing capsule fits on the floor — **passes** for both.

Neither cause is a gameplay regression: the props place exactly as specified on
the real maps, and the courier/informant failure is the probe’s mission stub,
not the shipping controller.

## Not run (blocked by the failure)

`make audit`, the 96-file compile check and `git push` on the merged tree: the
cherry-pick was not performed, per the brief (“only if both pass”).
