# W3O — per-kind placement for the Owl, readables and NPCs

Wave: W3O (Spider personal-chain placement fix).
Worktree: `/tmp/opencode/tat2-w2p`. Date: 2026-11-24.
Base HEAD: `828e6ef` (`test(spider): subset real-map probe for placements and chain`).

**No Godot process ran in this wave.** The package sat at 80 °C on arrival and
87 °C during the edits (cores 75–79 °C), above the 70 °C threshold. A syntax-only
`gdparse 4.5.0` check passed for all changed scripts; the type-check, the
probe and UID generation are deferred (see “Deferred”).

## The defect

`personal_quest_spawner.gd` floor-grounded every personal actor with
`floor + 0.02`. That is correct for an NPC's feet but wrong for authored props:
the Vault Owl's pin `BP_QuestSpawner_Item_C_2` is 0.9655 m above the POI vault
floor, and the Library letter's pin is on a table.

## Authored pins (expansion record, real values)

`game/data/expansion/personal_spider.json`, dispatcher positions as extracted:

| Anchor | Actor | Kind | Pin (x, y, z) |
|---|---|---|---|
| `library_note` | `BP_Readable_ClueSpawner_Guildhall_C_28` | `readable` | (-26.8541, 28.0021, -9.4431) |
| `owl` | `BP_QuestSpawner_Item_C_2` | `quest_item` | (-31.6286, 36.4655, -43.9759) |
| `courier` | `BP_Readable_ClueSpawner_Guildhall_C_1` | `npc` | (35.9000, 27.0019, -22.7280) |
| `informant` | `OldManor.Courtyard.C1` | `npc` | (1.5000, 10.1096, 13.0000) |

## Surface evidence

Walk-surface tops under the pins, from the W2P static AABB scan
(`build/qa/subset_floor_scan.py`, recorded in `docs/reports/w2p-subset-probe.md`):

| Pin | Surface owner | Surface top | Pin offset |
|---|---|---|---|
| letter | `Building_Guildhall_POI` — `SM_TableCtrUpperA` | 28.000 | -0.002 |
| Owl | `Building_Guildhall_POI` — `SM_Floor_2x2A_CornerA` | 35.500 | **-0.965** |
| courier | `Building_Guildhall_POI` — `SM_Floor_2x2A_StraightB` | 26.000 | -1.002 |
| informant | `OldManor_P` — `SM_LeavesPileC` | 10.050 | -0.060 |

Mesh bounds measured for this wave (glTF POSITION accessor union, no Godot):

- Owl `SM_StatueOwlA.glb`: y `+0.00012 … +0.30989`, size 0.198 × 0.310 × 0.290 m.
  The mesh origin is at its base; `_fit_prop_scale()` leaves scale 1.0 because
  0.310 m is inside its 0.08–1.6 m “hand prop” band.
- Letter `SM_NoteOpenA.glb`: y `-0.00494 … +0.00737`, a 1.2 cm-thick sheet.

## Policy (implemented)

`personal_quest_spawner.placement_position(kind, pin, floor_y, allow_floor_fallback)`
is the pure rule; `_resolve_anchor()` feeds it the same floor ray as before
(+2 m → −6 m on layer 1) and `_settle_node()` applies it after `add_child`.

| Kind | XZ | y | `y_source` | Fallback |
|---|---|---|---|---|
| `readable` | pin | `pin.y` (no drop) | `pin` | none |
| `quest_item` | pin | `pin.y` (no drop) | `pin` | floor + 0.02 m **only** when the pin has no authored surface (NAN) **and** `allow_floor_fallback` is set; logs `PQ_PLACE … y=floor_fallback` + `push_warning` |
| `npc` / `info_npc` | pin | `floor_y + 0.02` (mesh AABB bottom compensated) | `floor` | off-tree/no ray: `pin.y + 0.02`, `y_source=pin_no_floor` (explicit) |

- Rotation is never touched, so authored yaw/facing survives; only `y` (and
  nothing else) is adjusted.
- The floor ray still gates candidate selection (primary pin, then authored
  fallbacks): a pin in a void with no floor is still refused, as in W2P.
- Every spawn prints one line: `PQ_PLACE kind=<kind> y=<pin|floor|…> anchor=…
  pin_y=… floor_y=… pos=(…)`. The record now carries `y_source` too.

## Files

| File | Change |
|---|---|
| `game/src/quests/personal_quest_spawner.gd` | Pure `placement_position()`, per-kind `_settle_node()` replacing the blanket `_ground_node()`, `PQ_PLACE` logging, explicit floor fallback, `info_npc` accepted. |
| `game/tests/probe_personal_quest_subset.gd` | Per-kind assertions: letter/Owl keep the authored pin y; courier/informant feet stay at floor + 0.02; a local authored-surface ray (±0.35 m, separate from the walk-floor ray) is asserted when it hits and otherwise reported as `authored surface …: none`; `PQ_PLACE` line per pin. |
| `game/tests/test_personal_quest_spawner.gd` | New standalone pure-policy test using the real expansion pins (no map, no autoload state). |
| `docs/reports/w3o-owl-placement.md` | This report. |

No generated data, shared docs or expansion record changed. The test is not
registered in `run_tests.gd` (the brief asks for a standalone suite), so the
58-suite gate is unchanged; run it directly.

## Open risk: the Owl's authored pin

The decision for this wave is to trust the authored spawner origin and never
move the pin. The measured evidence still leaves one question for a human:

- The Owl pin is **0.9655 m** above the POI vault floor, while the statue mesh
  is **0.310 m** tall with its origin at its base. The W2P scan found no other
  surface at that XZ. So, unless a thin shelf exists that the static AABB scan
  missed, placing at the pin leaves the figurine floating ~0.97 m above the
  floor. That may be the authored `BP_QuestSpawner_Item` display offset (the UE
  blueprint may offset the item mesh inside the spawner actor) rather than a
  shelf; the port has no such offset, and inventing one is out of scope.
- The probe therefore asserts: pin y kept, mesh bottom not sunk below the walk
  floor, and — if a local surface is found within ±0.35 m — the pin or mesh
  bottom rests on it. Otherwise it prints
  `PQ-SUBSET authored surface Owl: none within +/-0.35 m of the pin (pin 0.965 m
  over the walk surface, foot offset 0.966 m)`.
- If that line appears on the cool host, record it in `docs/FIDELITY_GAPS.md`
  with the measured offsets and get a human call on the spawner's intended
  item offset. Do not silently move the pin or re-add a blanket floor drop.

## Deferred (cool host)

1. **Type-check** (start here; `gdparse` is syntax only):

   ```bash
   tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"
   ```

2. **UID generation**: the new `game/tests/test_personal_quest_spawner.gd`
   (and the still-untracked W2P probe UID) will get a `.gd.uid` on the first
   import; commit it then.
3. **Pure policy test** (no GPU, still alone):

   ```bash
   tools/godot --headless --path game \
     --script res://tests/test_personal_quest_spawner.gd
   ```

   Expect `PQ-PLACE SUMMARY: fails=0`. It checks Owl y == pin y (36.4655),
   letter y == pin y (28.0021), courier 26.02, informant 10.07, XZ preserved,
   and that the floor fallback needs both “no authored surface” and an explicit
   opt-in.
4. **Subset real-map probe** (one Godot process, isolated save home):

   ```bash
   XDG_DATA_HOME=/tmp/opencode/w3o-data \
     tools/godot --headless --path game \
     --script res://tests/probe_personal_quest_subset.gd
   ```

   Expected placement lines: `kind=readable y=pin`, `kind=quest_item y=pin`,
   `kind=npc y=floor` twice. Watch the Owl authored-surface line (open risk
   above) and the existing capsule/LOS results.
5. **Owl AABB surface**: the cool-host probe output above decides whether the
   authored pin is a shelf or a spawner display offset (see “Open risk”).
6. **Then the normal wave gates** (`make audit`, `make test`,
   `test_m2_player.gd`, `run_e2e_tests.gd`) on the merged tree; they were not
   run here under the thermal rule.
