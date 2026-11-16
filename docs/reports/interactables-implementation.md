# Interactables Implementation Report

Stage: replace hardcoded interactable/loot/lockpick values with real extracted data (1:1 fidelity).

## Value table (extracted -> in-game)

| Item | Extracted source | Real value | In-game use |
|---|---|---|---|
| Minor loot range | `extracted/json/Gameplay/Loot/Data/DT_LootInfo_Minor.json` (30 rows; spawn pool 18 rows with Value > 1) | min **45**, max **180** (tiers 45 / 100 / 180) | `loot_item.tier_entry("minor", i)` cycles pool; `mission_controller._spawn_loot_and_quest` names + values |
| Major loot range | `extracted/json/Gameplay/Loot/Data/DT_LootInfo_Major.json` (24 rows; pool 18) | min **225**, max **1000** (tiers 225 / 375 / 650 / 1000) | every 4th spawn uses `tier_entry("major", ...)` |
| Quest loot flagship | `extracted/json/Gameplay/Loot/Data/DT_LootInfo_Quest.json` (45 rows; pool 38) | **2500** (BookOfTruth, Diamond, CarrazReliquary, ThebanOwl, Piety, WesternPainting, ...) | `quest_value_for_tag(contract loot_tag)`, fallback 2500 |
| Jam damage by lock level | `game/data/generated/tables/Gameplay/Tuning/CT_LockpickDamage.json` row `DamageByLockLevel` | L1 **5**, L2 **10**, L3 **20**, L4 **40** | `lockable_door.get_jam_damage()` via `GameData.eval_curve("CT_LockpickDamage", "DamageByLockLevel", lvl)` (old code queried nonexistent row `LockpickDamage`) |
| Minigame variations | `extracted/json/Gameplay/Interactables/Locks/DA_LockpickMinigameVariations.json` (24 variations, difficulties 0-5) | e.g. diff 0: 3.0 s / 80 deg; diff 1: 1.8 s / 70 deg; diff 3: 1.2 s / 120-160 deg; default `Jammable`, breakable windows listed per track | `get_minigame_track()` / `get_track_duration()` (lock_level -> difficulty lock_level - 1); full timing-bar UI out of scope |
| GA_Lockpick defaults | `extracted/json/Gameplay/Interactables/Locks/GA_Lockpick.json` (`Default__GA_Lockpick_C`) | jam delay **0.5 s**, early-unlock **0.1 s**, cancel distance **200**, required section `Lockpick.TrackSection.Breakable` | stored in `lockpick` section of generated JSON |
| Escape open duration | `extracted/json/Gameplay/Interactables/EscapePoints/BP_EscapePoint.json` (`Default__BP_EscapePoint_C`) | `_escapeOpenDuration` **240.0** | `escape_gate.open_duration_sec` |
| Escape reusable | same | `_canBeUsedMultipleTimes` **true** | `escape_gate.can_be_used_multiple_times` + `use_count` gate |
| Door MaxLockLevel | `extracted/json/Gameplay/Interactables/Doors/BP_SwingingDoor.json` (`_lockConfig`) | **4** | `lock_level` clamped 1..4 |
| Door shake timeline | same (`Shake Mesh_Template`) | **0.75 s** | recorded in JSON; swing tween kept at 0.35 s (no open/close duration in data -> `null`) |

Zero-Value rows (CoinBronze/Silver/Platinum, Money stacks, Crown, Briefcase) are currency
placeholders with dynamic value in UE; excluded from spawn pools (Value > 1 rule) but kept
in `entries` with a `loot_tag` for auditability. `JEWELKNIFERENOWN` (Value 1 renown test item)
likewise excluded from the pool.

## Progress -> attempts mapping (doors)

One `[E]` press = one pick attempt; progress gain = `5.0 / jam_damage`:
L1 1.0 (1 attempt), L2 0.5 (2), L3 0.25 (4), L4 0.125 (8).
Higher levels cost more time and per-attempt noise (`NoiseBus` 4.0 each press) - the
per-level penalty, derived from the real damage values. No new minigame UI was invented;
track duration/arc/breakable windows are exposed via `get_minigame_track()` for the future UI.

## Files changed

- `tools/parse_interactables.py` (new) -> `game/data/generated/gameplay/interactables.json` (new)
- `game/src/interact/loot_item.gd`: static table loader + `spawn_pool` / `tier_entry` /
  `tier_min/max_value` / `quest_value_for_tag` / `quest_flagship_value`; new `loot_tier` export
- `game/src/interact/lockable_door.gd`: correct curve row `DamageByLockLevel`, `get_jam_damage()`,
  `get_minigame_track()` / `get_track_duration()`, clamp to table MaxLockLevel, gain mapping
- `game/src/interact/escape_gate.gd`: `open_duration_sec` (240), `can_be_used_multiple_times`,
  `use_count`, `escape_config()` / `apply_escape_config()`; objective gating unchanged
- `game/src/missions/mission_controller.gd`: `_spawn_loot_and_quest` uses real minor/major
  tables + tag-matched quest value; `_spawn_escape` applies table config
- `game/tests/_tmp_interact_check.gd`: temporary RED/GREEN check (deleted after run)

Not touched: `game/tests/run_tests.gd`, `thief_character.gd`, `guard_ai.gd`, `level_loader.gd`,
`parse_tables.py`, `parse_materials.py`, Makefile, Android files.

## Commands (exit codes)

- `python3 tools/parse_interactables.py` -> exit 0
- `flatpak run org.godotengine.Godot --headless --path game --script res://tests/_tmp_interact_check.gd`:
  RED run (pre-change code): 13 JSON PASS + `SCRIPT ERROR: Nonexistent function 'get_jam_damage'` (live API absent);
  GREEN run (post-change): `SUMMARY: fails=0`, exit 0, no SCRIPT ERROR
- `make test` -> exit 0, `SUMMARY: fails=0`, zero `SCRIPT ERROR` lines.
  All 17 checks pass, incl. suite 6 LockableDoor lockpick (level-2 progress 0.5 > 0,
  prompt prefix intact), suite 7 ThievesDen hub, and Old Manor spawn
  (6 guards, 13 loot items = 12 table-driven + 1 quest item).

## Self-audit

- Fallback constants in `.gd` files intentionally mirror the table numbers and are only used
  when `interactables.json` is missing (fail closed); the JSON is authoritative at runtime.
- Door open/close durations are `null` in the JSON because the extracted dump provides none;
  the 0.35 s tween is retained and documented, not presented as extracted data.
- Pick duration: GA data exposes no single pick duration; track `duration_s` values are the
  real timing params (`pick_duration_s: null`, documented).
- Temp check file deleted after the GREEN run; `make test` run against the final tree.
