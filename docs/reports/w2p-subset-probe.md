# W2P — subset real-map probe for the Spider chain (01 → 04)

Wave: W2P (subset real-map probe: placements + chain).
Worktree: `/tmp/opencode/tat2-w2p`. Date: 2026-11-24.
Base HEAD: `184e97e` (`feat(spider): runtime NPCs, dialogue, Owl and 04 informant`).

The probe is written and committed. **It did not run.** Every Godot launch in
this worktree was stopped by the thermal guard at 90–91 °C, so no placement,
dialogue or chain result is claimed here — see “Thermal status” and
“Deferred”.

## What was added

| File | Role |
|---|---|
| `game/src/quests/personal_quest_spawner.gd` (new) | The shipping spawn pass extracted from `mission_controller`: plan → primary/fallback pin → floor ray → 0.02 m mesh grounding → dedupe → note/owl/NPC construction → letter read and Owl→courier callbacks. Civilian body/head meshes now come from `GameData`, not mission state. |
| `game/tests/probe_personal_quest_subset.gd` (new) | QA-only subset probe: one `LevelLoader.load_sublevels()` call per map (160 lights, collision on), then the shipping deploy/hub/read/take/talk path with the real actor and dialogue nodes. |
| `game/src/missions/mission_controller.gd` | `_spawn_personal_quest_actors()` / `on_personal_quest_owl_taken()` now delegate to the seam and republish `personal_quest_actors`; behaviour and runtime contracts unchanged. |
| `game/src/core/game_data.gd` | `get_civilian_meshes()` — one source for the authored civilian variants (spawners.json, with the existing parse-time fallback pair). |
| `build/qa/subset_floor_scan.py` (new) | Godot-free static AABB scan used for the sublevel evidence below; reproducible with `python3 build/qa/subset_floor_scan.py`. |

No generated data, shared docs or expansion record changed. The accidental
working-tree deletion of `game/data/expansion/personal_spider.json` inherited
from the checkout was restored from git (`git checkout -- …`); the commit does
not touch it.

## Sublevel finding (why the probe defaults to 3 + 3, not 2 + 2)

The brief names four sublevels (`Guildhall_Gameplay`, `Guildhall_MissionClues`,
`OldManor_Gameplay`, `OldManor_Clues`). `build/qa/subset_floor_scan.py` maps
every mesh record in the generated sublevels to its GLB POSITION accessor
bounds and applies the loader's basis/scale/pos transform. Result: **none of
the four carries a walkable surface under any pin**; the surfaces live in the
building/terrain sublevels:

| Pin | Authored point | Surface owner | Surface top | Pin offset |
|---|---|---|---|---|
| letter `…_C_28` | (-26.8541, 28.0021, -9.4431) | `Building_Guildhall_POI` — `SM_TableCtrUpperA` | 28.000 | -0.002 |
| Owl `BP_QuestSpawner_Item_C_2` | (-31.6286, 36.4655, -43.9759) | `Building_Guildhall_POI` — `SM_Floor_2x2A_CornerA` | 35.500 | -0.965 |
| courier `…_C_1` | (35.9000, 27.0019, -22.7280) | `Building_Guildhall_POI` — `SM_Floor_2x2A_StraightB` | 26.000 | -1.002 |
| informant C1 | (1.5000, 10.1096, 13.0000) | `OldManor_P` — `SM_LeavesPileC` over the P landscape | 10.050 | -0.060 |

Consequence: with only the four named sublevels every floor ray misses, and the
shipping spawner correctly refuses to invent a position (all anchors skipped).
So the probe defaults to:

```text
Guildhall : Building_Guildhall_POI + Guildhall_Gameplay + Guildhall_MissionClues
Old Manor : OldManor_P              + OldManor_Gameplay  + OldManor_Clues
```

still one loader call per map and far below the full-map set (which also loads
POI_3rdFloor, Vault, P/Geometry, Landscape, Lighting, LocalVolumetric,
PeripheryA, SkyboxGeo, Loot, Contracts, SetSpawners). `-- --subset=strict`
reproduces the literal four-sublevel list for comparison.

The authored pins are spawner origins, not floor points (the Library note is on
a table at its pin; the clue/NPC pins sit 0.06–1.00 m above the walk surface).
The probe therefore asserts XZ = pin, floor ray hits, ±0.05 m flatness, actor
foot = surface + 0.02 m, standing-capsule clearance and LOS — and **prints** the
pin→surface offset as evidence instead of forcing it to zero.

## What the probe asserts when run

- Loader: one call per map, 160-light budget, collision on; prints
  `meshes/lights/bodies/shapes` per map.
- Pins: XZ = authored; primary source (no fallback); floor ray + ±0.05 m
  flatness; 0.02 m grounding; standing capsule r0.30/h1.75 no overlap;
  player-eye LOS from the first of 8 open 1.4 m stand-off directions; prompt
  (`[E] Read`, `[E] Take Theban Owl`, `[E] Talk`).
- Chain: first deploy → intro; note read → letter + `01:FoundLetter` + HUD
  toast; Den return → electrotype; next deploy → located; Owl take →
  carrying/held, no loot/value/currency/`quest_item_acquired`; courier talk →
  delivered + `03:HandedOff` + exact 03 line; Old Manor informant first talk →
  info + `04:GotInfo` + exact 04 line; follow-up → complete + exact close line.
- Invariants: 7 facts, Owl delivered, no `03:Reminder` / `04:Renegade` /
  `ObjectiveComplete_*`, no loot/currency/objective/contract mutation,
  Chameleon record untouched, `write_save`/`load_save` round-trip keeps
  `complete` + 7 facts; the borrowed save file and `GameState` fields are
  restored before exit.

## Thermal status (measured)

`coretemp` Package id 0 (`/sys/class/hwmon/hwmon4/temp1_input`):

| Time | Event | Start | Peak | End |
|---|---|---|---|---|
| 15:35 | arrival, idle | 84–87 °C | — | — |
| 15:36–15:42 | idle sampling (12 + 10 + 8 samples) | 71–79 | 90 (ambient spike) | 72 |
| 15:43 | `check_scripts_compile.gd`, `taskset -c 0-7`, unguarded | 71 | **91** | 72 |
| 15:45 | same check, guarded (abort ≥ 88) | 74 | **91 → aborted** | 72 |
| 15:47 | same check, `taskset -c 0-1`, guarded | 76 | **90 → aborted** | 76 |

The 15:43 run completed (`scripts checked: 94, broken: 0`) before the guard
existed; it covers the seam, GameData change and an earlier revision of the
probe. After the final probe rewrite, two guarded compile attempts were killed
at 90–91 °C before producing output, so **the final probe revision is
syntax-checked only** (`gdparse` OK; no Godot type-check captured).

The probe itself was never started: its loads are far heavier than a 3-second
script compile, and the previous full-map probe was aborted at 95 °C.

## Deferred / what remains

1. **Run the probe on a cool host**, alone, with an isolated save home:

   ```bash
   XDG_DATA_HOME=/tmp/opencode/w2p-data \
     taskset -c 0-7 tools/godot --headless --path game \
     --script res://tests/probe_personal_quest_subset.gd
   ```

   Optional literal-four run: append `-- --subset=strict` (expected to skip all
   anchors until the floor-bearing sublevels are included).
2. **Re-run `check_scripts_compile.gd`** to type-check the final probe/seam.
3. **Then `make test` (suite 87 at least) and the full-map probe**: the seam
   refactor is exercised only by the mock in suite 87, which does not call
   `_spawn_personal_quest_actors()`. The real-map probe is the first runtime
   cover for the refactor.
4. If the probe reports capsule/LOS failures on the Vault (Owl) or Library
   (note) pins, record them in `docs/FIDELITY_GAPS.md` with the probe line; do
   not move the authored pin.

## Risks / open questions

- **Placements unverified.** The floor-owner table is a static AABB scan; it
  cannot prove the loader generates collision for those meshes (the probe can).
- **Support mode is heavier than the brief's four** (POI 9.8k + Gameplay 1.6k +
  Clues vs the rest of the full list). It is still a subset, but the literal
  four-subset cannot ground a single pin — that is the finding, not a shortcut.
- **Owl offset −0.965 m.** The Owl grounds on the POI Vault floor, not at the
  spawner origin; if the authored intent is a shelf 0.965 m up, the floor is a
  POI mesh while the vault sublevel has no mesh at that XZ. Needs the probe (and
  a human look) to call.
- **Type-check gap** on the final probe revision (see above).
- `game/tests/probe_personal_quest.gd` (full-map W1S probe) is unchanged and
  still asserts the loose ±3 m pin height.

Run it when the host is cool; this report makes no claim about the four pins
until that output exists.
