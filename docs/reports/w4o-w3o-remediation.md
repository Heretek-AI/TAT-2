# W4O — W3O audit remediation (settle path, binding, yaw, pedestal)

Wave: W4O (remediation of the W3O application path).
Worktree: `/tmp/opencode/tat2-w2p`. Date: 2026-11-24.
Base HEAD: `27b974e` (`fix(spider): per-kind placement for the Owl, readables and NPCs`).

**No Godot process ran in this wave.** The host reported a package temperature
of ~84 °C on arrival, above the thermal rule, so nothing was launched, imported
or probed. Only the syntax gate (`gdparse 4.5.0`), a JSON parse, `py_compile`
and `tools/check_clue_quests.py` (pure Python over generated data) were run.
Type-check, UIDs, the subset probe and the runtime gates are deferred to a cool
host (see “Deferred”).

## What W3O got wrong

The W3O audit found the pure `placement_position()` policy correct but the code
that *applies* it unsafe:

1. `_settle_node()` wrote local `node.position` from a world pin and a world
   floor ray. With a non-identity parent every actor was displaced by the
   parent transform (and the NPC mesh-bottom subtraction ignored the node's
   world basis).
2. A dead `PLACE_FLOOR_FALLBACK` branch plus its warning promised an “explicit”
   invented-y path that no caller used and nobody should rely on.
3. Nothing bound the pass to the Spider thief: `spawn_plan()` returned pins for
   whatever stage the record held, for any thief.
4. The record carried no yaw, yet the report claimed “authored facing survives”.
   Nothing was rotated; Courier/Informant faced 0°.
5. The Owl pin (36.4655) looked like a floating figurine because the probe's
   ±0.35 m authored-surface search could print “none” and pass.

## Fixes (all in this commit)

| # | Fix | Where |
|---|---|---|
| 1 | `_settle_node()` writes `global_position`; NPC feet subtract `global_transform.basis.y.y * mesh_bottom(node)` (world-Y component). Probe `foot` is global too. `setup()` warns once when the host is transformed (fallback diagnostic; global settle makes a transformed host correct, so it is never a hard assert). | `personal_quest_spawner.gd`, `probe_personal_quest_subset.gd` |
| 2 | `PLACE_FLOOR_FALLBACK`, its constant, its branch and its test block are gone. A quest item with no authored surface is refused. | spawner, `test_personal_quest_spawner.gd` |
| 3 | One `thief_id` threaded through `spawn_for_map`/`spawn_anchor`/`on_owl_taken` → `PersonalQuest.spawn_plan`/`anchor`/`record`/`_make_npc` (NPC `thief_id` + metas). `spawn_plan()` returns `[]` for a non-Spider; `spawn_anchor` refuses too. The mission passes `GameState.thief_id`. | `personal_quest.gd`, spawner, `mission_controller.gd` |
| 4 | Authored `yaw_deg` on the courier and 04 informant anchors (TAT-2, with a `yaw_note`). Applied to `npc`/`info_npc` only, in world space; the Owl and the note are never rotated. The false “authored facing survives” claim is corrected in the spawner docstring and banner-noted in the W3O report. | `personal_spider.json`, spawner, W3O report |
| 5 | Owl support is the real pedestal (below). The subset probe gates the Owl on a surface within `36.4645 ± 0.1` at the pin XZ, asserts `y_source=pin`, and **fails** if it is absent. “None passes” is removed (the Library note's surface is required too). | `probe_personal_quest_subset.gd` |
| 6 | Courier feet are accepted in `[floor, floor + 0.02 + tol]` because the body settles under gravity after spawn. `y_source` is printed and asserted from the spawner record, never inferred from the kind. | probe |
| 7 | Guards: `host == null` before `add_child`; non-Array `fallbacks` ignored; a missing `pos` skips the anchor (never `Vector3.ZERO`); `spawn_for_map()` releases the previous actors (in-tree `queue_free`, off-tree `free`); an occupied candidate now falls through to the next authored fallback (occupancy check inside the resolve loop, after the y policy). | spawner |
| 8 | Owl gets `is_quest_item = true`; the note passes `BP_ReadableClueActor_Note_C` (not the spawner component name); the 2.84 mm letter sink is documented in code and here. | spawner |
| 9 | New suite 88 (`test_personal_quest_settle.gd`) registered in `run_tests.gd`; 86/87 untouched. | `run_tests.gd`, new test |

## Owl support evidence (no TAT-2 geometry)

The reverse-engineering pass found `SM_Manor_BookcasePedestal` in
`Guildhall_Gameplay` at `(-32, 35.5, -43.997)` with a measured world top of
**~36.4645 m**. The Owl pin `BP_QuestSpawner_Item_C_2` is
`(-31.6286, 36.4655, -43.9759)`: **1.0 mm above that top**, and 0.9655 m above
the walk floor (35.500). The pin is therefore a real surface point, not a
spawner display offset.

The W2P static AABB scan (and the W3O report built on it) listed only the Vault
walk floor under that pin and treated the pin as possibly a display offset, so
the W3O probe allowed a “none” authored-surface result. This wave does not
re-derive why the static scan did not surface the pedestal (narrow top, mesh
set, or transform resolution); the runtime probe is the authority and now fails
closed on it.

No TAT-2 shelf/bookcase is added. The probe now asserts:

- a surface exists within `36.4645 ± 0.1` at the pin XZ;
- the record's `y_source` is `pin`;
- the pin or the mesh bottom rests within 0.1 m of that surface;
- the surface's y is within `PEDESTAL_TOP_Y ± 0.1`.

If any of these fail on the cool host, the Owl placement is a real defect to
record in `docs/FIDELITY_GAPS.md` — not a “none passes” notice.

## Authored yaw (TAT-2 content)

UE placement pins carry no yaw, so these are TAT-2 choices, marked in the
record with `yaw_note` (and checked by `tools/check_clue_quests.py`):

| Anchor | Pin | `yaw_deg` | Meaning |
|---|---|---|---|
| `courier` | `(35.9, 27.0019, -22.728)` | **90.0** | The pin sits at the Lounge's east edge (x 35.9, the building's max); 90° faces −X, i.e. back into the room the player approaches from. |
| `informant` | `(1.5, 10.1096, 13.0)` | **0.0** | Node3D forward is −Z; the informant looks toward the Courtyard C1 approach side (the authored fallback guard spots sit at z 12.4–14.0). |

Applied by `_settle_node()` with `global_rotation = (0, yaw, 0)` for
`npc`/`info_npc` only. The Owl is a loot prop whose `visual_root` spins in
`_process`; the note is a flat sheet. Neither anchor has `yaw_deg`, and neither
is rotated.

Both values are plausible-but-unverified facings: a cool host with the loaded
interior should confirm the courier looks into the Lounge and the informant
toward the courtyard, not into a wall. Change the JSON value if not; the yaw is
data, not code.

## Letter sink (accepted, no pin move)

`SM_NoteOpenA` local y spans `-0.00494 … +0.00737`. At the authored pin
(28.0021) over the table top (28.000) the sheet bottom is at **27.99716**, i.e.
**2.84 mm** inside the table. That is paper contact, not a placement defect, so
the pin is unchanged and no per-prop offset is introduced. Documented in
`_make_note()` and asserted as “mesh bottom not sunk more than 10 mm”.

## Tests

- `game/tests/test_personal_quest_spawner.gd` (standalone, unregistered): the
  pure policy, the pedestal constant, the removed fallback source
  (`get_script_constant_map()` has no `PLACE_FLOOR_FALLBACK`), and the
  yaw-carrying anchors. Run alone on a cool host.
- **Suite 88** `game/tests/test_personal_quest_settle.gd` (new, registered):
  drives the real `spawn_anchor()`/`_settle_node()` with the real expansion
  anchors and synthetic nodes on one **transformed, off-tree host**:
  - readable and quest item land on the authored **world** pin (and their local
    position is *not* the pin — proving global settle);
  - the note uses `BP_ReadableClueActor_Note_C` and `[E] Read`;
  - the Owl is `is_quest_item`, `[E] Take Theban Owl`, not rotated;
  - the courier's `y_source` is `pin_no_floor` off-tree, its talk chain binds
    `thief_id=spider`, and its yaw equals the record;
  - a synthetic 1 m box on a 0.9 m offset: `_settle_node("npc", …)` puts the
    **mesh bottom** on the requested world y, at the requested XZ, with the
    authored yaw;
  - a prop ignores a yaw argument; a missing `pos` is skipped; non-Array
    `fallbacks` are ignored; an occupied primary uses the authored fallback;
  - Chameleon (record forced to `intro` **in memory only**, never via
    `set_personal_quest_stage()` which writes the developer save) yields zero
    actors, an unchanged save dictionary and an unchanged record.

  The suite restores the save dictionary and `GameState.thief_id` before
  returning.
- Suite count for the next full `make test` is **59** (was 58). The gate table
  in `AGENTS.md`/handoff still says 58 and must be updated by the owner on the
  merged tree; this wave does not edit shared docs.

## Verification actually run (this wave)

```text
gdparse 4.5.0 (syntax only), exit 0:
  game/src/quests/personal_quest_spawner.gd
  game/src/quests/personal_quest.gd
  game/src/missions/mission_controller.gd
  game/tests/test_personal_quest_spawner.gd
  game/tests/test_personal_quest_settle.gd
  game/tests/probe_personal_quest_subset.gd
  game/tests/run_tests.gd
python3 -c 'json.load(...personal_spider.json)'      -> ok
python3 -m py_compile tools/check_clue_quests.py     -> ok
python3 tools/check_clue_quests.py                   -> PASS (124 checks)
```

Not run (no Godot): compile/type-check, UID generation, `make test` (suites
86–88), `test_m2_player.gd`, `probe_leak.gd`, `run_e2e_tests.gd`, `make audit`,
the subset probe.

## Deferred to a cool host (ordered)

1. **Type-check** (start here; `gdparse` is syntax only):

   ```bash
   tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"
   ```

2. **UIDs**: the new `game/tests/test_personal_quest_settle.gd` (and any still
   untracked probe UID) get a `.gd.uid` on first import; commit them then.
3. **Suite 88 / 86 / 87** via the full gate (one process):

   ```bash
   make test        # expect SUMMARY: fails=0, 59 suites
   ```

   or the thermal shortcut for 87 only: `-- --spider-only`.
4. **Subset real-map probe** (one Godot, isolated save home):

   ```bash
   XDG_DATA_HOME=/tmp/opencode/w4o-data tools/godot --headless --path game \
     --script res://tests/probe_personal_quest_subset.gd
   ```

   Expect `PQ_PLACE kind=readable y=pin`, `kind=quest_item y=pin`,
   `kind=npc y=floor` (twice), an `authored surface Owl y≈36.4645` line, and
   `PERSONAL QUEST SUBSET PASS`. If the Owl support line fails, record the
   measured offsets in `docs/FIDELITY_GAPS.md`; do not move the pin.
5. **Visual yaw check** on the loaded Guildhall Lounge / Old Manor Courtyard
   (see “Authored yaw”). Adjust the JSON, not the code.
6. **Then** `make audit`, `test_m2_player.gd`, `probe_leak.gd` and
   `run_e2e_tests.gd` on the merged tree.

## Files

| File | Change |
|---|---|
| `game/src/quests/personal_quest_spawner.gd` | Global settle, world-Y mesh bottom, yaw application, thief binding, host/fallback/pos/occupancy guards, actor release, `is_quest_item` Owl, note class, dead fallback removed. |
| `game/src/quests/personal_quest.gd` | `spawn_plan()` non-Spider empty plan + non-Array `stages` guard; docs. |
| `game/src/missions/mission_controller.gd` | Passes `GameState.thief_id` to `spawn_for_map`/`on_owl_taken`. |
| `game/data/expansion/personal_spider.json` | TAT-2 `yaw_deg`/`yaw_note` on courier (90°) and informant (0°). |
| `game/tests/probe_personal_quest_subset.gd` | Pedestal gate, global foot, record `y_source`, foot range for settled NPCs, yaw print/check, spider binding. |
| `game/tests/test_personal_quest_spawner.gd` | Dead fallback block removed; pedestal and yaw-data checks. |
| `game/tests/test_personal_quest_settle.gd` | New suite 88 (settle path + binding). |
| `game/tests/run_tests.gd` | Suite 88 registration + `_run_suite88()`. |
| `tools/check_clue_quests.py` | Asserts the two TAT-2 yaws and that the Owl/note carry none. |
| `docs/reports/w3o-owl-placement.md` | “Superseded by W4O” banner correcting the yaw claim. |
| `docs/reports/w4o-w3o-remediation.md` | This report. |
