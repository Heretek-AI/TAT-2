# W9-P1 / A2 — authored progression fact sheet

Worktree: `/home/john/Projects/TAT-2-rem-w9-p1`  
HEAD: `c2a1cd8` (`docs(w9): P0 capture evidence, perf matrix, scorecard closure`)  
Date: 2026-11-25  
Scope: facts only. No source, data, save or test file was changed. Every shell command was read-only.

Citation form: `path:line` for text/JSON line numbers, `path $.json.path` where a line citation would be noisy. All runtime values below are the current code, not a proposal.

---

## 0. Current vs authored (headline table)

| Field | Current code value | Authored value |
|---|---|---|
| XP required to leave level 1–4 | 500 each: `save_system.gd:1100-1105` evaluates `CT_XPToLevel`; authored keys `CT_XPToLevel.json:8-19` | 500: `CT_XPToLevel.json:12-19`; `level_up_xp = 500`, `project_settings.json:45` |
| XP required to leave level 5–9 | 1000 each: same code + `CT_XPToLevel.json:20-27` | 1000: `CT_XPToLevel.json:20-27` |
| XP required to leave level 10–24 | 2500 each: same code + `CT_XPToLevel.json:28-35` | 2500: `CT_XPToLevel.json:28-35` |
| Max level | `MAX_SAVE_LEVEL = 200` defensive only, no gameplay cap: `save_system.gd:25,1121-1130` | 25: `project_settings.json:48`; `extracted/raw/TAT/Config/DefaultGame.ini:722` (`MaximumLevel=25`) |
| Cumulative XP to reach level 25 | 44,500 (derived by `save_system.gd:1109-1117`) | 44,500 = sum of curve thresholds 1..24 (`CT_XPToLevel.json:12-35`) |
| XP awarded on a contract escape | `data["xp"] += maxi(100, score / 2)`, integer division, clamped `0..MAX_SAVE_XP=1_000_000`: `save_system.gd:1091` | 11 authored `XP.*` categories (`DT_PlayerExperience.json:5-125`, tags only) and the project-settings weights (`project_settings.json:32-52,127-129`); no per-category formula is extracted |
| XP cap | `MAX_SAVE_XP = 1_000_000`: `save_system.gd:26` | `MaximumTimeInGameXP = 25.0`, `maximum_level = 25`: `project_settings.json:48-49` |
| Level storage | `level` int default 1, always re-derived from XP: `save_system.gd:343,728-735,1314-1321` | Level 1..25 from `CT_XPToLevel`; no authored `level` save field |
| Starting currency | 0: `save_system.gd:350` | `ftue_min_thieves_den_money = 5000`: `project_settings.json:160`; `DefaultGame.ini:175` |
| Contract score | `round(kept * stealth)`, stealth 1.25 Ghost / 1.10 Shadow: `loot_inventory.gd:383-386`, `game_state.gd:797-803` | `ContractCompleteBonus = 100.0`, `MissionCompleteBonus = 300.0`, both loot-value multipliers `0.1`: `project_settings.json:658-669`; `DefaultGame.ini:800-803` — no runtime reader |
| Money banked | `money_taken = score + stashed + reward`; reward 1000: `loot_inventory.gd:392`; `loot_settings.json:81-87` | Same authored mission reward (1000 in `DT_Missions_Guildhall.json` Rewards); scoring bonuses above are unread |
| Endgame window, LootTheRoom | 1200 s at **every** difficulty from the tracked KF13 override: `game/data/expansion/briefing_overrides.json:6`, `game_data.gd:578-585` | 1200/600/300 indexed 0/1/2: `project_settings.json:150-159`; `DefaultGame.ini:334-336`; index→difficulty mapping labelled `unproven: index order only` at `project_settings.json:145` |
| Endgame window, other missions | Authored QG `EndgameDuration` (480 LootTheRoom/Set/OldManor, 300 VaultHeist) then 480 fallback: `game_data.gd:578-585`, `mission_controller.gd:95,803-810`, `game_state.gd:370-373` | The same global 1200/600/300 ladder; project settings authors no per-mission endgame |
| Main clock, LootTheRoom | Mission row 3300/1200/1200 Novice/Thief/Master: `DT_Missions_Guildhall.json:109-111`, `game_data.gd:535-544`; map row 7200/2700/1800 fallback: `contracts.json $.mission_durations.guildhall` | `project_settings.project.maps` lists the mission order only: `project_settings.json:312-316`; no main-clock value |
| Market level gate | 48 rows compare `condition.requires_level` with `get_level_progress().level`: `unlock_catalog.gd:248-279`; purchase only re-checks the category/price/currency: `save_system.gd:1261-1286` | 48 `RequiredLevel` conditions; levels 2–23 and 25: `unlocks.json:195-197` + the 48-row table in §3.2 |
| Initial unlocks | Starter tools/perks/cosmetics hard-coded in `save_system.gd:92-103,345-347` | 8 initial tags: `project_settings.json:162-171`; 3 post-FTUE tags: `project_settings.json:422-426` — no runtime reader |
| Save schema | `SAVE_SCHEMA_VERSION = 8`: `save_system.gd:11`; no version chain (stamp only): `docs/reports/remediation-20261125/T02-state.md:478-486` | n/a |
| `project_settings.json` consumer | None in `game/src` or `game/tests`; allowlisted `blocked_on_team`, owner `T10`: `tools/consumer_allowlist.json:156-163` | Producer emits XP / max level / endgame ladder / FTUE bankroll / map order: `project_settings.json:31-137,150-171,295-408,657-669` |

---

## 1. Current progression runtime — `game/src/core/save_system.gd` (1,447 lines)

### 1.1 Constants and curve identity

| Constant | Value | Line | Note |
|---|---|---|---|
| `XP_CURVE_TABLE` | `"CT_XPToLevel"` | `save_system.gd:18` | Passed to `GameData.eval_curve`. |
| `XP_CURVE_ROW` | `"XPToLevel"` | `save_system.gd:19` | The only row in the curve table. |
| `XP_PER_LEVEL_FALLBACK` | `500` | `save_system.gd:21` | Only used when the curve is unreadable; comment says "its level 1-4 value". |
| `MAX_SAVE_LEVEL` | `200` | `save_system.gd:25` | Defensive loop bound, explicitly "not gameplay caps". |
| `MAX_SAVE_XP` | `1_000_000` | `save_system.gd:26` | Defensive clamp for save-sourced XP. |
| `SAVE_SCHEMA_VERSION` | `8` | `save_system.gd:11` | Root save stamp. |
| `LOOT_SCHEMA_VERSION` | `1` | `save_system.gd:12` | Payout layer stamp. |
| `SETTINGS_SCHEMA_VERSION` | `2` | `save_system.gd:33` | FOV migration schema. |
| `UNLOCK_IDS_SCHEMA_VERSION` | `1` | `save_system.gd:55` | W6U2 catalogue-id migration. |
| `PERSONAL_QUEST_SCHEMA_VERSION` | `1` | `save_system.gd:115` | Spider personal chain. |

There is no `MAX_LEVEL` constant in `save_system.gd`; the only level bound is `MAX_SAVE_LEVEL = 200` (defensive).

### 1.2 XP award path (`record_contract_complete`)

`record_contract_complete(order: int, score: int, ghost: bool)` is the only production XP award: `save_system.gd:1083-1093`.

```gdscript
func record_contract_complete(order: int, score: int, ghost: bool) -> void:
	var k: String = str(order)
	var prev_raw: Variant = data["completed_contracts"].get(k, {})
	var prev: Dictionary = prev_raw as Dictionary if prev_raw is Dictionary else {}
	data["completed_contracts"][k] = {
		"best_score": maxi(int(prev.get("best_score", 0)), score),
		"ghost": bool(prev.get("ghost", false)) or ghost,
	}
	data["xp"] = clampi(int(data["xp"]) + maxi(100, score / 2), 0, MAX_SAVE_XP)
	_sync_level_from_xp()
	write_save()
```

- `score` is the payout `score` (`int(round(kept * stealth))`, `loot_inventory.gd:386`) passed as `final_score` from `GameState.last_payout` at `mission_controller.gd:231-234` (co-op resolved path) and `mission_controller.gd:4580-4583` (local `_finish_run`).
- Both call sites are guarded by `if not GameState.free_play` and only run for `outcome == "escape"` (`mission_controller.gd:232-234`, `4581-4583`). A capture, main timeout, or door collapse awards **no XP**.
- `ghost` only changes `completed_contracts[order].ghost`; it does not add XP directly. `ever_spotted` already changed `score` through the 1.25/1.10 stealth multiplier (`game_state.gd:797-803`).
- `score / 2` is GDScript integer division (both operands `int`), so score 625 → 312; `maxi(100, …)` makes any score ≤ 200 award exactly 100 XP.
- No other file under `game/src` calls `record_contract_complete` (grep: only `mission_controller.gd:234,4583`).

### 1.3 Level derivation

- `_sync_level_from_xp()` — `save_system.gd:728-735`: reads `data["xp"]`, clamps to `0..MAX_SAVE_XP`, rewrites `data["xp"]` only when the clamp changes it, then sets `data["level"] = level_for_xp(xp)`. Comment at 725-727: stored levels are legacy and "never trusted".
- `xp_threshold_for_level(level)` — `save_system.gd:1100-1105`: `GameData.eval_curve("CT_XPToLevel", "XPToLevel", max(1, level), 500)`, rounded to int; `<= 0` falls back to 500. Comment 1097-1099 states the result: "1-4 = 500, 5-9 = 1000, 10-24 = 2500".
- `xp_total_for_level(level)` — `save_system.gd:1109-1117`: cumulative sum of thresholds for levels 1..target-1; clamps target to `1..MAX_SAVE_LEVEL`.
- `level_for_xp(xp)` — `save_system.gd:1121-1130`: starts at 1, subtracts `xp_threshold_for_level(level)` while `remaining >= need and level < MAX_SAVE_LEVEL`; at 1,000,000 XP it returns 200.
- `get_level_progress()` — `save_system.gd:1314-1321`: returns `{level, xp_in_level, xp_needed}` with level re-derived from XP; `xp_in_level = clampi(xp - xp_total_for_level(level), 0, max(0, needed - 1))`.
- `GameData.eval_curve()` — `game_data.gd:168-195`: table lookup, linear interpolation between `Keys`; before the first key returns the first value; after the last key returns the last value (post-infinity constant). `CT_XPToLevel` declares `RCIM_Linear` + `RCCE_Constant` at `CT_XPToLevel.json:6,37-39`.

Authored per-level values derived exactly from `CT_XPToLevel.XPToLevel` (the file has 7 keys, not 24 rows; the 24 thresholds are the linear result):

| Level | XP to leave this level | Cumulative XP to reach this level |
|---:|---:|---:|
| 1 | 500 | 0 |
| 2 | 500 | 500 |
| 3 | 500 | 1000 |
| 4 | 500 | 1500 |
| 5 | 1000 | 2000 |
| 6 | 1000 | 3000 |
| 7 | 1000 | 4000 |
| 8 | 1000 | 5000 |
| 9 | 1000 | 6000 |
| 10 | 2500 | 7000 |
| 11 | 2500 | 9500 |
| 12 | 2500 | 12000 |
| 13 | 2500 | 14500 |
| 14 | 2500 | 17000 |
| 15 | 2500 | 19500 |
| 16 | 2500 | 22000 |
| 17 | 2500 | 24500 |
| 18 | 2500 | 27000 |
| 19 | 2500 | 29500 |
| 20 | 2500 | 32000 |
| 21 | 2500 | 34500 |
| 22 | 2500 | 37000 |
| 23 | 2500 | 39500 |
| 24 | 2500 | 42000 |
| 25 | 2500 | 44500 |

So: level 4 at 1,500 XP, level 5 at 2,000 XP, level 10 at 7,000 XP, level 25 at 44,500 XP. `xp_threshold_for_level(25)` still returns 2,500 (post-infinity), but a level-25 cap is not enforced anywhere; `MAX_SAVE_LEVEL=200` is the only bound. At `MAX_SAVE_XP=1,000,000`, `level_for_xp` returns 200.

Level readers:

- `unlock_catalog.player_level()` uses `SaveSystem.get_level_progress().level` (`unlock_catalog.gd:258-261`).
- `ledger_ui._refresh_journal()` uses `get_level_progress()` for the `Level %d` label and `xp_in_level/xp_needed` (`ledger_ui.gd:581-590`).
- The HUD level badge reads the **stored** `SaveSystem.data["level"]` directly (`hud.gd:967-969`, `2722-2724`); `_sync_level_from_xp()` keeps that value current on load and after a completion (`save_system.gd:913,947,1092`).
- Tests read `data["level"]` directly: `run_tests.gd:4305`, `e2e_tier4_scenarios.gd:413,480`, `test_w6u2_catalog.gd:226`.

### 1.4 Save schema, defaults, load/write, migrations

There is **no `read_save()`** in the file. The read API is `load_save()` at `save_system.gd:907`; the atomic writer is `write_save()` at `save_system.gd:1026-1071` (write `user://tat2_save.json.tmp`, read back, compare text, re-parse as object, then `DirAccess.rename_absolute` into `user://tat2_save.json`; `SAVE_PATH`/`TMP_PATH` at `save_system.gd:5-6`).

`_defaults()` — `save_system.gd:336-386` — every root key (line in the literal):

| Root key | Default | Line | Affected by XP/level/currency? |
|---|---|---|---|
| `save_schema` | `8` | 338 | Schema stamp; bump for a new progression migration. |
| `loot_schema` | `1` | 339 | Payout schema. |
| `last_match` | `_default_payout_record()` | 340 | Holds `score`, `money_taken`, `banked`; written by `bank_payout`. |
| `pending_payout` | `_default_payout_record()` | 341 | Crash outbox; settled on load. |
| `xp` | `0` | 342 | **Yes** — award/clamp/sync. |
| `level` | `1` | 343 | **Yes** — rewritten by `_sync_level_from_xp`. |
| `completed_contracts` | `{}` | 344 | **Yes** — `record_contract_complete` writes `{best_score, ghost}` per order. |
| `unlocked_tools` | `["blackjack","smoke_bomb","zipwire"]` | 345 | **Yes** — purchase adds; migration rewrites legacy ids. |
| `unlocked_perks` | `["novice_difficulty","guildhall","old_manor","spider"]` | 346 | **Yes** — purchase adds; `is_thief_unlocked` reads. |
| `unlocked_cosmetics` | `STARTER_COSMETICS` (3 Spider defaults + BowlerA) | 347 | **Yes** — purchase adds; wardrobe reads. |
| `unlock_ids_schema` | `1` | 348 | Catalogue migration stamp. |
| `unlock_ids_migrated` | `false` | 349 | One-shot catalogue migration flag. |
| `currency` | `0` | 350 | **Yes** — `bank_payout` adds, `purchase_item` deducts, `add_currency` adds. |
| `player_name` | `""` | 351 | No. |
| `player_name_migrated` | `false` | 352 | No. |
| `equipped_loadout` | `{"spider": …, "chameleon": …}` | 353 | Indirect: purchases gate what the wardrobe can equip. |
| `active_decoration` | `"faberge_egg"` | 354 | No. |
| `personal_quest_schema` | `1` | 355 | No. |
| `personal_quest_migrated` | `false` | 356 | No. |
| `personal_quest` | `{"spider": …, "chameleon": …}` | 357-360 | No. |
| `settings_schema` | `2` | 361 | No (FOV migration). |
| `settings` | 22 keys, `fov=54.54`, volumes, locale, quality | 362-385 | No. |

Supporting literals: `_default_loadout()` at `save_system.gd:288-299` (`tools: ["zipwire","smoke_bomb","","vistara_diamond"]`); `_default_personal_quest_entry()` at 302-303; `_default_payout_record()` at 309-328 (`match_id`, `mission_id`, `contract_order`, `map_id`, `outcome`, `original`, `kept`, `stashed`, `reward`, `score`, `money_taken`, `stealth_mult`, `capture`, `free_play`, `applied`, `banked`, `carried`).

Load path and migration hook (`load_save()`):

- No file: `_ensure_defaults()`, `_sync_level_from_xp()`, `_migrate_unlock_ids()`, `_migrate_save_schema()`, return (`save_system.gd:911-916`).
- Existing file: open/parse; non-object root is quarantined and defaults stay in memory without a write (`save_system.gd:917-944`, `_report_load_failure` 967-985).
- Valid object: `_merge_validated(parsed)` (type-checked merge, unknown root keys dropped), `_ensure_defaults()`, `_sync_level_from_xp()`, then the one-shot migrations (`save_system.gd:945-962`):
  - `_migrate_settings_schema()` 742-752
  - `_migrate_player_name()` 760-767
  - `_migrate_personal_quest()` 717-722
  - `_migrate_unlock_ids()` 779-810
  - `_migrate_save_schema()` 862-883
  - if any returned true → one `write_save()` (960-961)
  - `_settle_pending_on_load()` 962 / 889-897

`_merge_validated`/`_merge_into` — `save_system.gd:415-462`: only keys already present in the default schema are accepted; free-form `completed_contracts` is the one empty-dictionary schema (unknown completion rows accepted); `last_match`/`pending_payout` are strict-normalised; wrong-typed values leave the default intact.

`_ensure_defaults()` — `save_system.gd:549-636`: backfills missing root keys from `_defaults()`, normalises settings volumes/locale/graphics quality, guarantees starter tools/perks/cosmetics, normalises legacy loadout shapes, then `_ensure_personal_quest()`.

`_migrate_save_schema()` — `save_system.gd:862-883`: compares a JSON fingerprint before/after; stamps `save_schema` and `loot_schema` only upward (`if save_schema < SAVE_SCHEMA_VERSION`), strict-normalises both payout records, returns whether anything changed. It is a **stamp, not a versioned chain** (documented in `docs/reports/remediation-20261125/T02-state.md:478-486`).

### 1.5 Currency and other award paths

- `add_currency(amount)` — `save_system.gd:1137-1139`: `data["currency"] = int(data.get("currency", 0)) + amount; write_save()`. No clamp, no negative guard. Production grep: **no caller in `game/src`**; only the save-round-trip test calls it (`run_tests.gd:4249`).
- `bank_payout(payout)` — `save_system.gd:1153-1174`: idempotent on `match_id`; `bank = 0` when `free_play` else `max(money_taken, 0)` (1159-1161); writes the staged outbox first (1164), then `data["currency"] = maxi(int(data.get("currency", 0)), 0) + bank` (1168), `last_match = p`, clears `pending_payout`, second `write_save()` (1173-1174). Production callers: `mission_controller.gd:226` (co-op resolved path) and `mission_controller.gd:4571` (`_finish_run`); a staged record is settled on load by `_settle_pending_on_load()` (`save_system.gd:897`).
- `money_taken` is authored by `LootInventory.build_payout` — `loot_inventory.gd:375-418`: `kept = round(carried_total * kept_ratio(outcome))`, `score = round(kept * stealth)`, `reward = contract_reward(active_map_id)` only on escape + complete + non-free-play, `money_taken = score + stashed + reward` (383-392). `kept_ratio` is 1.0 escape / 0.0 capture; stashed always kept (`loot_inventory.gd:108-113`; `loot_settings.json:79-80`).
- `purchase_item(category, item_id, cost)` — `save_system.gd:1261-1286`: validates category/id/cost, `is_unlocked`, `currency >= cost`, then deducts exactly `cost` and appends the id. It does **not** validate level or contract; the ledger checks those before calling (`ledger_ui.gd:948-964`).
- `is_thief_unlocked(thief)` — `save_system.gd:1298-1311`: Spider always true; Chameleon true if `unlocked_perks` has `"chameleon"`, or `completed_contracts` has order 3, or legacy `unlocked_thieves`/`chameleon_unlocked`. Contract 3 alone therefore unlocks the thief, independent of the 10,000 price row (`W6U2.18b` pins this).

---

## 2. Authored data — `game/data/generated/project_settings.json` (674 lines)

Source: `extracted/raw/TAT/Config/DefaultGame.ini` (`project_settings.json:671-672`; sha256 `8d01268989eff43caa3df22d2d01ddfe85833e85ff8be9519a76bd7a2232c751`). The file has `general`, `progression`, `project`, `scoring`, `schema`, `source`, `source_sha256`, `unmapped_keys: []`.

### 2.1 `progression` block, verbatim (`project_settings.json:31-137`)

```json
  "progression": {
    "contracts_xp": 20.0,
    "coop_xp_multiplier": 1.5,
    "difficulty_xp_multipliers": {
      "Easy": 1.0,
      "Hard": 3.0,
      "Normal": 2.0
    },
    "ftue_level_up_xp_categories": [
      "XP.ReachExitInTime",
      "XP.CompleteMission",
      "XP.CompleteContracts"
    ],
    "ftue_level_up_xp_is_on_top_of_regular_xp": true,
    "level_up_xp": 500,
    "looting_player_xp_multiplier": 1.1,
    "major_loot_xp": 6.0,
    "maximum_level": 25,
    "maximum_time_in_game_xp": 25.0,
    "minor_loot_xp": 2.0,
    "mission_xp": 20.0,
    "open_queue_xp": 5.0,
    "player_stat_data_table": "/Game/Gameplay/Progression/DT_PlayerStats.DT_PlayerStats",
    "raw": {
      "ContractsXP": "20.000000",
      "CoopXPMultiplier": "1.500000",
      "EasyDifficultyXPMultiplier": "1.000000",
      "FtueLevelUpXPCategories": [
        "(TagName=\"XP.ReachExitInTime\")",
        "(TagName=\"XP.CompleteMission\")",
        "(TagName=\"XP.CompleteContracts\")"
      ],
      "FtueLevelUpXpIsOnTopOfRegularXp": "True",
      "HardDifficultyXPMultiplier": "3.000000",
      "LevelUpXP": "500",
      "LootingPlayerXPMultiplier": "1.100000",
      "MajorLootXP": "6.000000",
      "MaximumLevel": "25",
      "MaximumTimeInGameXP": "25.000000",
      "MinorLootXP": "2.000000",
      "MissionXP": "20.000000",
      "NormalDifficultyXPMultiplier": "2.000000",
      "OpenQueueXP": "5.000000",
      "PlayerStatDataTable": "/Game/Gameplay/Progression/DT_PlayerStats.DT_PlayerStats",
      "UpgradeEditorProgressionNodeStyles[0]": "(Style=BorderDark,Color=(R=0.500000,G=0.500000,B=0.500000,A=1.000000))",
      "UpgradeEditorProgressionNodeStyles[1]": "(Style=Flat,Color=(R=0.178403,G=0.461299,B=1.000000,A=1.000000))",
      "UpgradeEditorProgressionNodeStyles[2]": "(Style=BorderLight,Color=(R=0.037109,G=0.395833,B=0.238891,A=1.000000))",
      "UpgradeEditorProgressionNodeStyles[3]": "(Style=Glossy,Color=(R=0.566993,G=0.000000,B=1.000000,A=1.000000))",
      "WinXP": "80.000000",
      "XPDataTable": "/Game/Gameplay/Tuning/DT_PlayerExperience.DT_PlayerExperience",
      "XPPerMinute": "0.600000",
      "XPToLevel": "(Value=1.000000,Curve=(CurveTable=\"/Script/Engine.CurveTable'/Game/Gameplay/Tuning/CT_XPToLevel.CT_XPToLevel'\",RowName=\"XPToLevel\"),RegistryType=\"None\")",
      "XPToLevelTable": "/Game/Gameplay/Tuning/DT_XPToLevel.DT_XPToLevel"
    },
    "upgrade_editor_progression_node_styles": [
      {
        "color": {
          "A": 1.0,
          "B": 0.5,
          "G": 0.5,
          "R": 0.5
        },
        "index": 0,
        "style": "BorderDark"
      },
      {
        "color": {
          "A": 1.0,
          "B": 1.0,
          "G": 0.461299,
          "R": 0.178403
        },
        "index": 1,
        "style": "Flat"
      },
      {
        "color": {
          "A": 1.0,
          "B": 0.238891,
          "G": 0.395833,
          "R": 0.037109
        },
        "index": 2,
        "style": "BorderLight"
      },
      {
        "color": {
          "A": 1.0,
          "B": 1.0,
          "G": 0.0,
          "R": 0.566993
        },
        "index": 3,
        "style": "Glossy"
      }
    ],
    "win_xp": 80.0,
    "xp_data_table": "/Game/Gameplay/Tuning/DT_PlayerExperience.DT_PlayerExperience",
    "xp_per_minute": 0.6,
    "xp_to_level": {
      "registry_type": "None",
      "row": "XPToLevel",
      "table": "/Game/Gameplay/Tuning/CT_XPToLevel.CT_XPToLevel",
      "value": 1.0
    },
    "xp_to_level_table": "/Game/Gameplay/Tuning/DT_XPToLevel.DT_XPToLevel"
  },
```

### 2.2 `scoring` block, verbatim (`project_settings.json:657-670`)

```json
  "scoring": {
    "carried_loot_value_multiplier_bonus": 0.1,
    "contract_complete_bonus": 100.0,
    "escape_order_bonus_curve": "/Game/Matchmaking/Ranking/C_Ranking_EscapeOrderBonus.C_Ranking_EscapeOrderBonus",
    "mission_complete_bonus": 300.0,
    "raw": {
      "CarriedLootValueMultiplierBonus": "0.100000",
      "ContractCompleteBonus": "100.000000",
      "EscapeOrderBonus": "/Game/Matchmaking/Ranking/C_Ranking_EscapeOrderBonus.C_Ranking_EscapeOrderBonus",
      "MissionCompleteBonus": "300.000000",
      "StashedLootValueMultiplierBonus": "0.100000"
    },
    "stashed_loot_value_multiplier_bonus": 0.1
  },
```

### 2.3 `project` keys requested

#### Endgame ladder (`project_settings.json:150-159`)

```json
    "endgame_duration_seconds_by_difficulty_index": {
      "0": 1200.0,
      "1": 600.0,
      "2": 300.0
    },
    "endgame_durations_by_difficulty": [
      1200.0,
      600.0,
      300.0
    ],
```

`project.difficulty_index_source` (`project_settings.json:145`) is `"unproven: index order only"`. The producer explicitly does not claim `[0] == Easy` (no `ETATDifficulty` enum in the dumps): `tools/parse_project_ini.py:833-837`, documented in `docs/reports/remediation-20261125/T01-pipeline.md:93-99`.

#### FTUE bankroll + hub + initial unlock content (`project_settings.json:160-171`)

```json
    "ftue_min_thieves_den_money": 5000,
    "hub_map_name": "MissionLobby_P",
    "initial_unlocked_content": [
      "Difficulty.Novice",
      "Thief.Spider",
      "Outfit.Spider.Head.Default",
      "Outfit.Spider.Body.Default",
      "Outfit.Spider.CallingCard.Default",
      "Outfit.Chameleon.Body.Default",
      "Outfit.Chameleon.CallingCard.Default",
      "Outfit.Chameleon.Head.Default"
    ],
```

#### `map_type_settings`, verbatim (`project_settings.json:173-294`)

```json
    "map_type_settings": [
      {
        "add_default_player_gear_loadout_on_spawn": false,
        "allow_active_quests": false,
        "allow_default_player_tools": false,
        "index": 0,
        "raw": {
          "AddDefaultPlayerGearLoadoutOnSpawn": false,
          "AllowActiveQuests": false,
          "AllowDefaultPlayerTools": false,
          "RunMapVariation": false,
          "UseMapIntroStates": true
        },
        "run_map_variation": false,
        "use_map_intro_states": true
      },
      {
        "add_default_player_gear_loadout_on_spawn": false,
        "allow_active_quests": false,
        "allow_default_player_tools": false,
        "index": 1,
        "raw": {
          "AddDefaultPlayerGearLoadoutOnSpawn": false,
          "AllowActiveQuests": false,
          "AllowDefaultPlayerTools": false,
          "RunMapVariation": false,
          "UseMapIntroStates": true
        },
        "run_map_variation": false,
        "use_map_intro_states": true
      },
      {
        "add_default_player_gear_loadout_on_spawn": false,
        "allow_active_quests": false,
        "allow_default_player_tools": false,
        "index": 2,
        "raw": {
          "AddDefaultPlayerGearLoadoutOnSpawn": false,
          "AllowActiveQuests": false,
          "AllowDefaultPlayerTools": false,
          "RunMapVariation": false,
          "UseMapIntroStates": true
        },
        "run_map_variation": false,
        "use_map_intro_states": true
      },
      {
        "add_default_player_gear_loadout_on_spawn": true,
        "allow_active_quests": true,
        "allow_default_player_tools": true,
        "index": 3,
        "raw": {
          "AddDefaultPlayerGearLoadoutOnSpawn": true,
          "AllowActiveQuests": true,
          "AllowDefaultPlayerTools": true,
          "RunMapVariation": true,
          "UseMapIntroStates": true
        },
        "run_map_variation": true,
        "use_map_intro_states": true
      },
      {
        "add_default_player_gear_loadout_on_spawn": false,
        "allow_active_quests": false,
        "allow_default_player_tools": false,
        "index": 4,
        "raw": {
          "AddDefaultPlayerGearLoadoutOnSpawn": false,
          "AllowActiveQuests": false,
          "AllowDefaultPlayerTools": false,
          "RunMapVariation": false,
          "UseMapIntroStates": false
        },
        "run_map_variation": false,
        "use_map_intro_states": false
      },
      {
        "add_default_player_gear_loadout_on_spawn": false,
        "allow_active_quests": true,
        "allow_default_player_tools": false,
        "index": 5,
        "raw": {
          "AddDefaultPlayerGearLoadoutOnSpawn": false,
          "AllowActiveQuests": true,
          "AllowDefaultPlayerTools": false,
          "RunMapVariation": true,
          "UseMapIntroStates": false
        },
        "run_map_variation": true,
        "use_map_intro_states": false
      },
      {
        "add_default_player_gear_loadout_on_spawn": true,
        "allow_active_quests": true,
        "allow_default_player_tools": true,
        "index": 6,
        "raw": {
          "AddDefaultPlayerGearLoadoutOnSpawn": true,
          "AllowActiveQuests": true,
          "AllowDefaultPlayerTools": true,
          "RunMapVariation": true,
          "UseMapIntroStates": true
        },
        "run_map_variation": true,
        "use_map_intro_states": true
      },
      {
        "add_default_player_gear_loadout_on_spawn": false,
        "allow_active_quests": false,
        "allow_default_player_tools": false,
        "index": 7,
        "raw": {
          "AddDefaultPlayerGearLoadoutOnSpawn": false,
          "AllowActiveQuests": false,
          "AllowDefaultPlayerTools": false,
          "RunMapVariation": false,
          "UseMapIntroStates": false
        },
        "run_map_variation": false,
        "use_map_intro_states": false
      }
    ],
```

#### `maps`, verbatim (`project_settings.json:295-408`)

```json
    "maps": [
      {
        "coordinates_on_city_map": {
          "X": 65.0,
          "Y": 10.0
        },
        "game_mode": "/Game/Core/BP_TATPvEGameMode.BP_TATPvEGameMode_C",
        "map": "/Game/Maps/Guildhall/Guildhall_P.Guildhall_P",
        "map_display_name": "LOCTABLE(\"/Game/StringTables/ST_MapTool.ST_MapTool\", \"Guildhall.MapName\")",
        "map_flavor_text": "LOCTABLE(\"/Game/StringTables/ST_MapTool.ST_MapTool\", \"Guildhall.MapFlavorText\")",
        "map_name": "Guildhall",
        "map_preview_mesh": "/Game/Art/UI/Map/SM_MapBuilding_GuildHall.SM_MapBuilding_GuildHall",
        "mesh_scaling": {
          "X": 0.5,
          "Y": 0.5,
          "Z": 0.5
        },
        "missions": [
          "Mission.Guildhall.VaultHeist",
          "Mission.Guildhall.Set",
          "Mission.Guildhall.LootTheRoom"
        ],
        "raw": {
          "CoordinatesOnCityMap": {
            "X": 65.0,
            "Y": 10.0
          },
          "GameMode": "/Game/Core/BP_TATPvEGameMode.BP_TATPvEGameMode_C",
          "Map": "/Game/Maps/Guildhall/Guildhall_P.Guildhall_P",
          "MapDisplayName": "LOCTABLE(\"/Game/StringTables/ST_MapTool.ST_MapTool\", \"Guildhall.MapName\")",
          "MapFlavorText": "LOCTABLE(\"/Game/StringTables/ST_MapTool.ST_MapTool\", \"Guildhall.MapFlavorText\")",
          "MapName": "Guildhall",
          "MapPreviewMesh": "/Game/Art/UI/Map/SM_MapBuilding_GuildHall.SM_MapBuilding_GuildHall",
          "MapTag": {
            "TagName": "Map.Guildhall"
          },
          "MeshScaling": {
            "X": 0.5,
            "Y": 0.5,
            "Z": 0.5
          },
          "Missions": [
            {
              "TagName": "Mission.Guildhall.VaultHeist"
            },
            {
              "TagName": "Mission.Guildhall.Set"
            },
            {
              "TagName": "Mission.Guildhall.LootTheRoom"
            }
          ],
          "SplashImage": "/Game/Art/UI/Icons/Rewards/Maps/T_Map_Guildhall.T_Map_Guildhall"
        },
        "splash_image": "/Game/Art/UI/Icons/Rewards/Maps/T_Map_Guildhall.T_Map_Guildhall",
        "tag": "Map.Guildhall"
      },
      {
        "coordinates_on_city_map": {
          "X": -10.0,
          "Y": 20.0
        },
        "game_mode": "/Game/Core/BP_TATPvEGameMode.BP_TATPvEGameMode_C",
        "map": "/Game/Maps/OldManor/OldManor_P.OldManor_P",
        "map_display_name": "LOCTABLE(\"/Game/StringTables/ST_OldManor_map.ST_OldManor_map\", \"OldManor.MapName\")",
        "map_flavor_text": "LOCTABLE(\"/Game/StringTables/ST_OldManor_map.ST_OldManor_map\", \"OldManor.MapFlavorText\")",
        "map_name": "Old Manor",
        "map_preview_mesh": "/Game/Art/UI/Map/SM_MapBuilding_OldManor.SM_MapBuilding_OldManor",
        "mesh_scaling": {
          "X": 0.333333,
          "Y": 0.333333,
          "Z": 0.333333
        },
        "missions": [
          "Mission.OldManor.Set",
          "Mission.OldManor.Vault",
          "Mission.OldManor.LootTheRoom"
        ],
        "raw": {
          "CoordinatesOnCityMap": {
            "X": -10.0,
            "Y": 20.0
          },
          "GameMode": "/Game/Core/BP_TATPvEGameMode.BP_TATPvEGameMode_C",
          "Map": "/Game/Maps/OldManor/OldManor_P.OldManor_P",
          "MapDisplayName": "LOCTABLE(\"/Game/StringTables/ST_OldManor_map.ST_OldManor_map\", \"OldManor.MapName\")",
          "MapFlavorText": "LOCTABLE(\"/Game/StringTables/ST_OldManor_map.ST_OldManor_map\", \"OldManor.MapFlavorText\")",
          "MapName": "Old Manor",
          "MapPreviewMesh": "/Game/Art/UI/Map/SM_MapBuilding_OldManor.SM_MapBuilding_OldManor",
          "MapTag": {
            "TagName": "Map.OldManor"
          },
          "MeshScaling": {
            "X": 0.333333,
            "Y": 0.333333,
            "Z": 0.333333
          },
          "Missions": [
            {
              "TagName": "Mission.OldManor.Set"
            },
            {
              "TagName": "Mission.OldManor.Vault"
            },
            {
              "TagName": "Mission.OldManor.LootTheRoom"
            }
          ],
          "SplashImage": "/Game/Art/UI/Icons/Rewards/Maps/T_Map_OldManor.T_Map_OldManor"
        },
        "splash_image": "/Game/Art/UI/Icons/Rewards/Maps/T_Map_OldManor.T_Map_OldManor",
        "tag": "Map.OldManor"
      }
    ],
```

#### Post-FTUE contract/unlock lists (`project_settings.json:412-426`)

```json
    "post_ftue_contracts": [
      {
        "requirement": "Complete",
        "tag": "Contract.Main.1"
      },
      {
        "requirement": "Objective",
        "tag": "Contract.Main.2"
      }
    ],
    "post_ftue_unlocked_content": [
      "Map.Guildhall",
      "Tool.Type.Zipwire",
      "Tool.Type.SmokeBomb"
    ],
```

#### `unlockable_content_data` (`project_settings.json:654`)

```json
"unlockable_content_data": "/Game/UI/Progression/DA_UnlockableContentEntries.DA_UnlockableContentEntries"
```

The projected raw key is `UnlockableContentData` at `project_settings.json:639`. No generated DataTable for `DA_UnlockableContentEntries` exists under `game/data/generated/tables/**` (see §3).

### 2.4 Where the real per-level XP data lives

- **`curves.json` does not contain XPToLevel.** `grep -n "XPToLevel" game/data/generated/curves.json` → no hit; `curves.json` is a curve *index/provenance* (`schema`, `counts`, `standalone`, `nested`; 23 curve tables / 16 emitted standalone / 108 nested) and its allowlist entry says "The runtime reads the per-asset tables, not this index" (`tools/consumer_allowlist.json:150-155`).
- **The actual curve is `game/data/generated/tables/Gameplay/Tuning/CT_XPToLevel.json`**, emitted by `tools/parse_tables.py` (the `CT_*` CurveTable normaliser; `tools/parse_curves.py:24-32` says 23 CurveTables are already normalised 1:1 by `parse_tables.py`). `tools/parse_settings.py:54-55,214-231` reads the same table only to copy its 7 keys into `loot_settings.json`. Full file:

```json
{
  "type": "CurveTable",
  "name": "CT_XPToLevel",
  "rows": {
    "XPToLevel": {
      "InterpMode": "ERichCurveInterpMode::RCIM_Linear",
      "Keys": [
        {
          "Time": 0.0,
          "Value": 0.0
        },
        {
          "Time": 1.0,
          "Value": 500.0
        },
        {
          "Time": 4.0,
          "Value": 500.0
        },
        {
          "Time": 5.0,
          "Value": 1000.0
        },
        {
          "Time": 9.0,
          "Value": 1000.0
        },
        {
          "Time": 10.0,
          "Value": 2500.0
        },
        {
          "Time": 24.0,
          "Value": 2500.0
        }
      ],
      "DefaultValue": 3.4028235e+38,
      "PreInfinityExtrap": "ERichCurveExtrapolation::RCCE_Constant",
      "PostInfinityExtrap": "ERichCurveExtrapolation::RCCE_Constant"
    }
  }
}
```

`DT_PlayerExperience.json` is present in the same directory but authors **category tags only** — every one of its 11 rows is `{Tag, DisplayName}` with no amount: `DT_PlayerExperience.json:5-125` (`XP.FinishedTutorial`, `XP.ReachExitInTime`, `XP.DidNotReachExitInTime`, `XP.CompleteMission`, `XP.CompleteContracts`, `XP.TimeInMatch`, `XP.OpenQueue`, `XP.MajorLoot`, `XP.MinorLoot`, `XP.Cooperative`, `XP.Difficulty`). The producer records this explicitly (`loot_settings.json $.xp.amounts_note`: "DT_PlayerExperience authors category tags only; the capture carries no per-category XP amounts, so none are invented").

- **`DT_XPToLevel` is referenced but not extracted.** `project_settings.json:136` points at `/Game/Gameplay/Tuning/DT_XPToLevel.DT_XPToLevel`, but there is no `DT_XPToLevel.json` in `game/data/generated/tables/**` and no dump under `extracted/json/**`; the only references in the tree are the project-settings value (`:136`; raw `XPToLevelTable` at `:83`), the source `extracted/raw/TAT/Config/DefaultGame.ini:740`, and `tools/test_parse_project_ini.py:253`. So the 24 level transitions are the interpolated `CT_XPToLevel` values in §1.3; there is no 24-row authored table in the tree.

- `game/data/generated/gameplay/loot_settings.json` also carries a copy of the 7 curve keys: `$.xp.curve_keys` (lines 109-140), values identical to `CT_XPToLevel.json`. It is producer output; no `game/src` reader consumes `$.xp` (`loot_inventory.gd:39,62-63` reads `settings()` but the `xp` block is not referenced).

---

## 3. Market gating — `game/data/generated/gameplay/unlocks.json` (3,478 lines)

### 3.1 Structure and counts

Top-level keys (line): `schema` (2), `game_version` (3), `source` (4), `units` (12), `derivation` (16), `catalog` (21), `price_provenance` (144), `stats` (175), `condition_copy_audit` (212), `string_tables` (242), `entries` (350).

`source` (`unlocks.json:4-11`): `extracted/json/UI/Progression/DA_UnlockableContentEntries.json`, class `TATUnlockableContentDataAsset`, string tables `ST_BlackMarket` and `ST_Tools`. `units` (`12-15`): price = authored in-game currency units, level = authored player level (1-based).

`stats` (`unlocks.json:175-211`) verbatim:

```json
{
  "entries": 68,
  "by_content_type": {
    "Cosmetic": 54,
    "Difficulty": 3,
    "Gear": 7,
    "Map": 2,
    "Thief": 2
  },
  "by_shop_category": {
    "chameleon_cosmetics": 26,
    "guild_perks": 7,
    "spider_cosmetics": 28,
    "tools": 7
  },
  "by_save_category": {
    "cosmetics": 54,
    "perks": 7,
    "tools": 7
  },
  "by_unlock_type": {
    "RequiredContract": 10,
    "RequiredLevel": 48
  },
  "priced_entries": 55,
  "free_entries": 13,
  "free_entries_with_conditions": 3,
  "min_price": 0,
  "max_price": 750000,
  "unique_save_ids": 68,
  "icons_with_asset": 68,
  "icons_on_disk": 68,
  "condition_copy_mismatches": 5,
  "string_keys_used": 134,
  "string_keys_unreferenced": 12,
  "conditions": 58
}
```

Interpretation of the counts: 68 entries; 55 priced (48 level-gated + 7 contract-gated priced); 13 free (10 ungated + 3 contract-gated Chameleon defaults); 58 gate conditions = 48 `RequiredLevel` + 10 `RequiredContract`; every `RequiredLevel` row is a Cosmetic; the 10 contract rows are 7 perks/tools + 3 free Chameleon cosmetics.

**The level field is `$.entries[].condition.requires_level`** (the runtime reads this exact field: `unlock_catalog.gd:248-250`). It is derived from the raw `UnlockConditions` `RequiredLevel` entry (`$.entries[].unlock.conditions[].level`) by `tools/parse_unlocks.py:246-294`; the producer rejects multiple different level/contract conditions (`parse_unlocks.py:257-262`) and writes `condition.text` from the structured gate (`parse_unlocks.py:264-300`).

**No `DA_UnlockableContentEntries` DataTable exists under `game/data/generated/tables/**`.** `find` only returns `tables/StringTables/ST_BlackMarket.json` (the string table). The runtime source of truth is `gameplay/unlocks.json`, read by `unlock_catalog.gd:19` (`CATALOG_PATH`) and validated for `tat2.unlock_catalog/1`, 68 entries, and column counts 7/7/28/26 (`unlock_catalog.gd:19-27,50-120`).

### 3.2 The 48 level-gated entries

All 48 are `content_type: "Cosmetic"`, `save_category: "cosmetics"`, and all have `price > 0`. The `unlocks.json` line is the line of that row’s `"requires_level"` key.

| # | save_id | requires_level | price | unlocks.json line |
|---:|---|---:|---:|---:|
| 1 | `Outfit.Spider.Head.NoCap` | 11 | 10000 | 1081 |
| 2 | `Outfit.Spider.Head.Hair.Bob` | 4 | 7500 | 1128 |
| 3 | `Outfit.Spider.Head.Hair.Bob.EyepatchA` | 9 | 10000 | 1175 |
| 4 | `Outfit.Spider.Head.Hair.Chignon` | 6 | 7500 | 1222 |
| 5 | `Outfit.Spider.Head.Hair.Chignon.ThiefMaskA` | 11 | 10000 | 1269 |
| 6 | `Outfit.Spider.Head.BowlerA` | 2 | 2500 | 1316 |
| 7 | `Outfit.Spider.Head.BowlerA.MustacheA` | 17 | 17500 | 1363 |
| 8 | `Outfit.Spider.Head.TopHatA` | 5 | 10000 | 1410 |
| 9 | `Outfit.Spider.Head.TopHatA.MonocleA` | 16 | 25000 | 1457 |
| 10 | `Outfit.Spider.Head.TopHatA.MustacheA` | 14 | 20000 | 1504 |
| 11 | `Outfit.Spider.Head.MustacheA` | 3 | 5000 | 1551 |
| 12 | `Outfit.Spider.Head.BeardA` | 4 | 7500 | 1598 |
| 13 | `Outfit.Spider.Head.GlassesA` | 8 | 15000 | 1645 |
| 14 | `Outfit.Spider.Head.ThiefMaskA` | 8 | 10000 | 1692 |
| 15 | `Outfit.Spider.Head.ThiefMaskA.MustacheA` | 13 | 15000 | 1739 |
| 16 | `Outfit.Spider.Head.MonocleA` | 9 | 15000 | 1786 |
| 17 | `Outfit.Spider.Head.EyepatchA` | 2 | 2500 | 1833 |
| 18 | `Outfit.Spider.Body.AltA` | 10 | 25000 | 1880 |
| 19 | `Outfit.Spider.Body.AltA.PatternB` | 15 | 25000 | 1927 |
| 20 | `Outfit.Spider.Head.AltA` | 10 | 25000 | 1974 |
| 21 | `Outfit.Spider.Head.AltA.PatternB` | 15 | 25000 | 2021 |
| 22 | `Outfit.Chameleon.Head.HairB` | 20 | 40000 | 2068 |
| 23 | `Outfit.Chameleon.Head.HairBob` | 11 | 7500 | 2115 |
| 24 | `Outfit.Chameleon.Head.CapA` | 13 | 15000 | 2162 |
| 25 | `Outfit.Chameleon.Head.BowlerA` | 6 | 7500 | 2209 |
| 26 | `Outfit.Chameleon.Head.BowlerA.MustacheA` | 6 | 7500 | 2256 |
| 27 | `Outfit.Chameleon.Head.BowlerA.ThiefMaskA` | 21 | 17500 | 2303 |
| 28 | `Outfit.Chameleon.Head.TopHatA` | 14 | 20000 | 2350 |
| 29 | `Outfit.Chameleon.Head.TopHatA.MonocleA` | 22 | 25000 | 2397 |
| 30 | `Outfit.Chameleon.Head.TopHatA.MustacheA` | 20 | 30000 | 2444 |
| 31 | `Outfit.Chameleon.Head.MustacheA` | 11 | 10000 | 2491 |
| 32 | `Outfit.Chameleon.Head.BeardA` | 12 | 10000 | 2538 |
| 33 | `Outfit.Chameleon.Head.GlassesA` | 17 | 15000 | 2585 |
| 34 | `Outfit.Chameleon.Head.ThiefMaskA` | 12 | 10000 | 2632 |
| 35 | `Outfit.Chameleon.Head.ThiefMaskA.MustacheA` | 19 | 20000 | 2679 |
| 36 | `Outfit.Chameleon.Head.MonocleA` | 18 | 15000 | 2726 |
| 37 | `Outfit.Chameleon.Head.EyepatchA` | 10 | 7500 | 2773 |
| 38 | `Outfit.Chameleon.Head.EyepatchA.BeardA` | 18 | 17500 | 2820 |
| 39 | `Outfit.Chameleon.Body.AltA` | 20 | 40000 | 2867 |
| 40 | `Outfit.Chameleon.Body.AltA.PatternB` | 22 | 75000 | 2914 |
| 41 | `Outfit.Chameleon.CallingCard.Silver` | 16 | 10000 | 3048 |
| 42 | `Outfit.Spider.CallingCard.Silver` | 7 | 10000 | 3095 |
| 43 | `Outfit.Chameleon.CallingCard.Gold` | 19 | 35000 | 3142 |
| 44 | `Outfit.Spider.CallingCard.Gold` | 15 | 25000 | 3189 |
| 45 | `Outfit.Chameleon.CallingCard.Magic` | 23 | 150000 | 3236 |
| 46 | `Outfit.Spider.CallingCard.Magic` | 21 | 100000 | 3283 |
| 47 | `Outfit.Spider.CallingCard.ModelShip` | 25 | 750000 | 3330 |
| 48 | `Outfit.Chameleon.CallingCard.ModelShip` | 25 | 750000 | 3377 |

Level distribution (count of rows):

- 2: 2
- 3: 1
- 4: 2
- 5: 1
- 6: 3
- 7: 1
- 8: 2
- 9: 2
- 10: 3
- 11: 4
- 12: 2
- 13: 2
- 14: 2
- 15: 3
- 16: 2
- 17: 2
- 18: 2
- 19: 2
- 20: 3
- 21: 2
- 22: 2
- 23: 1
- 25: 2

Levels present: 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 25. No row gates at level 1 or 24. The maximum gate is 25, matching `progression.maximum_level = 25`.

### 3.3 The 10 contract-gated entries (for completeness)

| save_id | requires_contract | price | category | content type | unlocks.json line |
|---|---:|---:|---|---|---:|
| `thief_difficulty` | 4 | 1 | perks | Difficulty | 419 |
| `master_thief_difficulty` | 5 | 1 | perks | Difficulty | 466 |
| `pickpocket_fairy` | 3 | 5000 | tools | Gear | 593 |
| `insult_fairy` | 6 | 7500 | tools | Gear | 640 |
| `slither_sap` | 7 | 15000 | tools | Gear | 687 |
| `old_manor` | 2 | 1 | perks | Map | 774 |
| `chameleon` | 3 | 10000 | perks | Thief | 861 |
| `Outfit.Chameleon.Head.Default` | 3 | 0 | cosmetics | Cosmetic | 908 |
| `Outfit.Chameleon.Body.Default` | 3 | 0 | cosmetics | Cosmetic | 955 |
| `Outfit.Chameleon.CallingCard.Default` | 16 | 0 | cosmetics | Cosmetic | 3002 |

### 3.4 How the runtime gates

- `unlock_catalog.gd:248-250` — `requires_level(entry)` returns `int(condition.requires_level)` or 0.
- `unlock_catalog.gd:258-261` — `player_level()` returns `SaveSystem.get_level_progress().level` (XP-derived, not the raw stored level).
- `unlock_catalog.gd:272-279` — `conditions_met(entry)`: level gate `player_level() < need_level` → false; contract gate `not completed_contract_orders().has(str(need_contract))` → false. Both are enforced when present.
- `unlock_catalog.gd:285-292` — `is_purchased`: save-owned, or `price == 0` and gates met.
- `unlock_catalog.gd:296-301` — `state_of`: `purchased` / `locked` / `buy` (the three KF08 states).
- `unlock_catalog.gd:304-309` — `can_purchase`: `STATE_BUY` and `SaveSystem.get_currency() >= price`.
- `ledger_ui.gd:948-964` — `_on_buy_pressed` re-checks `conditions_met` and `state_of == STATE_BUY`, then calls `SaveSystem.purchase_by_save_id(category, selected_id, price)`.
- `SaveSystem.purchase_item` (`save_system.gd:1261-1286`) only validates category, id, owned state, and `currency >= cost`; **it does not know about levels/contracts**, so a direct call bypasses the gate (the ledger is the enforcement point).
- Wardrobe uses `state_of(entry) == STATE_PURCHASED` to decide owned (`wardrobe_ui.gd:264`), so the same level/contract gate indirectly controls equippable cosmetics.
- `is_thief_unlocked` has an additional contract-3 path (`save_system.gd:1298-1311`), separate from the market row price; see §1.5.

---

## 4. Existing consumption and the KF13/endgame precedence

### 4.1 `project_settings.json` has no runtime consumer

- `grep -rn "project_settings" game/src game/tests --include=*.gd` → no hits. The only references are the producer (`tools/parse_project_ini.py`), its test (`tools/test_parse_project_ini.py`), the audit baseline (`tools/audit_baseline.json:397`), the manifest gate (`tools/manifest_audit.py:180,416`) and the consumer allowlist.
- `tools/consumer_allowlist.json:156-163`: `glob: project_settings.json`, `kind: blocked_on_team`, `owner: T10`, reason "DefaultGame.ini producer (XP, MaximumLevel, endgame durations, authored map->mission lists). T10-GAMEPLAY owns the consumer; the producer exists to unblock it.", `optional: true`.
- `tools/check_consumers.py` runs in `make audit`; consuming the file requires removing/updating this rule, or the allowlist rule becomes stale.
- `docs/reports/remediation-20261125/T01-pipeline.md:528` records `project_settings.json` reader as BLOCKED-ON T10; `docs/reports/re-audit-20261124.md:219-220,316,524` records the authored XP/endgame/bankroll data as unread.

### 4.2 Where the run clock is set

- `GameState.run_time_limit` declaration/comment: `game_state.gd:77`; `GameState.endgame_time_limit`: `game_state.gd:83`; phase constants: `game_state.gd:25-27`; difficulty enum (1-based): `game_state.gd:19,42`.
- The controller publishes both limits in `_apply_run_clock(map_id)` — `mission_controller.gd:774-827`:
  - Den hub: both 0.0, source `"hub"` (775-788).
  - Main: `GameData.get_match_duration(map_id, difficulty)` (map row, `game_data.gd:665-682`) and `GameData.get_mission_duration(mid, difficulty)` (mission row, `game_data.gd:535-544`); mission row wins when it validates against the map (`mission_controller.gd:789-800`).
  - Endgame: `GameData.get_mission_endgame_seconds(mid)` + source (`801-807`), then `ENDGAME_FALLBACK_SEC = 480.0` if <= 0 (`95,808-810`).
  - Assignment: `GameState.run_time_limit = main_limit; GameState.endgame_time_limit = endgame_limit` (`811-812`); phase reset to main (`813-815`).
- `GameState.begin_endgame(seconds_override = -1.0)` — `game_state.gd:365-377`: only a main-phase run can transition; `seconds_override > 0` writes `endgame_time_limit`; if the stored value is <= 0 it sets 480.0; resets `endgame_elapsed`; sets phase `endgame`. `_start_endgame()` calls it with no override (`mission_controller.gd:4497-4501`), so the controller-published value is what runs.
- Ticking/timeout: main expiry checks `run_time_limit` at `mission_controller.gd:4421`; endgame expiry checks `endgame_time_limit` at `4433`; `phase_time_limit()/phase_elapsed()` in `game_state.gd:388-411`; HUD countdown at `hud.gd:2622`.

### 4.3 Is 1200 s for LootTheRoom hardcoded?

**No — it is tracked data, not a code literal.** The value is `endgame_seconds: 1200`, `source: "KF13"` in `game/data/expansion/briefing_overrides.json:5-13` (evidence `docs/reference/clip_1795033698901/clean/KF13_01m10s_briefing_letter.jpg`; note records the authored QG value 480).

The precedence code that must keep winning:

```gdscript
# game/src/core/game_data.gd:573-595
func get_mission_endgame_seconds(mission_id: String) -> float:
	var ov_v: Variant = briefing_overrides.get(mission_id)
	if ov_v is Dictionary:
		var secs: Variant = (ov_v as Dictionary).get("endgame_seconds", null)
		if secs is float or secs is int:
			return float(secs)
	var plan: Dictionary = get_mission_plan(mission_id)
	return float(plan.get("endgame_duration", 0.0))

func get_mission_endgame_source(mission_id: String) -> String:
	var ov_v: Variant = briefing_overrides.get(mission_id)
	if ov_v is Dictionary:
		return str((ov_v as Dictionary).get("source", ""))
	return ""
```

If a W9 change starts reading `project_settings.project.endgame_durations_by_difficulty`, the KF13 override must remain the first branch for `Mission.Guildhall.LootTheRoom`; otherwise `get_mission_endgame_seconds()` starts returning the QG 480 s and the shipped 20-minute briefing becomes false. Tests that fail if this precedence is dropped: `test_w7e_endgame.gd:165-168,172-174`, `test_w6u1_briefing.gd:57-75`, and the QG-parity assertion `run_tests.gd:5847-5856` (plan must stay 480).

### 4.4 Current endgame ladder vs authored ladder

| Path | Current value | Source |
|---|---:|---|
| LootTheRoom (free play, any difficulty) | 1200 s | `briefing_overrides.json:6`; `game_data.gd:578-583` |
| LootTheRoom QG plan (kept at 480, not used by the runtime when the override exists) | 480 s | `game_data.gd:584-585`; `test_w7e_endgame.gd:162-164`; `run_tests.gd:5853` |
| Guildhall VaultHeist | 300 s | QG plan; `test_w7e_endgame.gd:178-180` |
| OldManor Vault / LootTheRoom | 480 s | QG plan; `test_w7e_endgame.gd:155-158` |
| Any mission with no override/plan | 480 s | `mission_controller.gd:95,808-810`; `game_state.gd:370-373` |
| Thieves’ Den hub | 0 s (unlimited) | `mission_controller.gd:775-788`; `test_t02_state_lifecycle.gd:287-290` |
| **Authored global ladder** | **1200 / 600 / 300** | `project_settings.json:150-159`; `DefaultGame.ini:334-336` |

Current code has **no difficulty parameter** on `get_mission_endgame_seconds(mission_id)` and therefore applies 1200/480/300/480 regardless of `GameState.difficulty`. The authored array is `[1200.0, 600.0, 300.0]`; the index map is `{"0":1200.0,"1":600.0,"2":300.0}`, and the producer labels the index→difficulty mapping `"unproven: index order only"` (`project_settings.json:145`). The 600 value has no runtime consumer: `grep -n "600" game/src/missions game/src/core/game_data.gd game/src/core/game_state.gd` finds only `3600/2700` comments and unrelated literals, never an endgame 600.

Main clock for LootTheRoom is separate and already authored by the mission row: `MatchDurationsByDifficulty` 3300 / 1200 / 1200 at `game/data/generated/tables/Gameplay/Quests/DT_Missions_Guildhall.json:109-111`; `game_data.gd:535-544`; `mission_controller.gd:789-800`; `test_w7e_endgame.gd:129-131`; `e2e_tier2_boundaries.gd:1207-1215`. The project-settings `maps` list only names the missions in authored order (`project_settings.json:312-316,368-372`), and the runtime mission rows come from the `DT_Missions_*` tables (`game_data.gd:814-859`).

---

## 5. Tests that assert these values

### 5.1 XP / level / progress

| Test | Citation | Assertion (quoted) |
|---|---|---|
| `run_tests.gd` suite 25 | `run_tests.gd:1510-1545` | Reads `CT_XPToLevel.json`, builds `authored_xp` from `Time`→`Value`, then `xp_l1 == authored_l1`, `xp_l5 == authored_l5`, `xp_l10 == authored_l10`, `authored_l1==500.0`, `authored_l5==1000.0`, `authored_l10==2500.0`, and `float(xp_l5) != 500.0`, `float(xp_l10) != 500.0` (1532-1540). Failure text: "FAIL: XP authored curve (keys=… authored L1/L5/L10=… thresholds=…)" (1542). Pass: "XP thresholds match CT_XPToLevel.XPToLevel (L1=…, L5=…, L10=…; flat 500 would fail L5/L10)" (1545). |
| `run_tests.gd` suite 9 | `run_tests.gd:311-315` | `var lvl_prog: Dictionary = save_sys.get_level_progress()` (311); fails if `int(lvl_prog.get("xp_needed", 0)) <= 0` (315). |
| `run_tests.gd` suite 49 | `run_tests.gd:4289,4305` | Staged save `sv49_case_a["xp"] = 1200`; asserts `sv49_xp_a != 1200 or sv49_level_a != 3` fails (4305). This is the 1200 XP → level 3 pin. |
| `run_tests.gd` suite 60 | `run_tests.gd:4977-4982` | "KF08 profile: Level 4 with £26,275"; sets `xp=1500`, `level=4`, asserts Bob Hair shows `£ 7,500` + BUY (4982). |
| `test_w6u2_catalog.gd` | `test_w6u2_catalog.gd:232-234` | `_check(int(save.call("level_for_xp", 1500)) == 4, "W6U2.14 1500 XP is Level 4 under the authored curve", …)`. |
| `test_w6u2_catalog.gd` | `test_w6u2_catalog.gd:304-306` | `level.text == "Level 4"` and `xp.text == "0/500"` (W6U2.21). This pins `get_level_progress()` at 1500 XP: cumulative level 4 = 1500, threshold level 4 = 500. |
| `e2e_tier3_pairwise.gd` T3-21 | `e2e_tier3_pairwise.gd:567-569` | `var xp10 := int(ss.call("xp_threshold_for_level", 10)); … xp10 == 2500` (569). |

### 5.2 Currency / payout / save values

| Test | Citation | Assertion (quoted) |
|---|---|---|
| `test_t02_save_integrity.gd` T02-01 | `:140` | `int(recovered.get("currency", -1)) == 0` — corrupt load keeps defaults. |
| `test_t02_save_integrity.gd` T02-03 | `:183,196,197,209` | writes `data["currency"]=777`; asserts loaded `currency == 777` (196), `save_schema == 8` (197), second load `get_currency() == 777` (209). |
| `test_t02_save_integrity.gd` T02-05 | `:242,256,260` | staged payout from currency 100; reload `get_currency() == 600` (256); second load still 600 (260). |
| `test_t02_save_integrity.gd` T02-06 | `:271-304` | bank 300 → disk `currency == 300` (288); replay duplicate unchanged (293); failed write still 410 in memory (304). |
| `test_w7s_loot_save.gd` 90.16-90.23 | `:152-164` | `data["currency"]=0`; first payout `currency == 2500` (155); duplicate `currency` unchanged (159); `last_match` fields `original=1000/kept=1000/stashed=250/money_taken=2500` (162). |
| `test_w7s_loot_save.gd` 90.24-90.27 | `:172-178` | `data["currency"]=123`; free play `banked == 0` (175), `currency == 123` (176). |
| `test_w7s_loot_save.gd` 90.28-90.33 | `:187-202` | staged payout from 100; reload `currency == 800` (197); second load still 800 (202). |
| `test_w7s_loot_save.gd` 90.34-90.39 | `:215-231` | migration `currency == 900` unchanged (227); stamps 8/1 (220); one-shot (226); newer stamp 9 never downgraded (231). |
| `e2e_s2_loot.gd` S2-09/10/12 | `:131-151,156-165,180-206` | S2-09: `after_currency - before_currency == expected_money` where `expected_money = expected_score + stashed + 1000` (137-146). S2-10: duplicate `reason == "duplicate"` and currency unchanged (159-164). S2-12: free play `currency == currency_before_free` and `xp == xp_before_free` (202-203). |
| `e2e_tier4_scenarios.gd` T4-13 | `:366-368,398-410` | free-play extraction: `int(save_data.get("xp", 0)) == before_xp` and `int(save_data.get("currency", 0)) == before_currency` (409-410). |
| `e2e_tier4_scenarios.gd` T4-14 | `:440-491` | normal ghost deploy: `after_currency == before_currency + 625` (485), `best_score == 625`, `ghost=true` (475-476). |
| `test_w7e_endgame.gd` S5.9 | `:433-458` | free play: `xp == before_xp` (454), `currency == before_currency` (455). |
| `run_tests.gd` suite 49 | `:4248-4251,4305,4322,4367-4370` | `add_currency(7)` survives write/reload (4251); staged `currency == 0` (4305); nested `completed_contracts.currency` does not leak (4322); developer xp/level/currency restored exactly (4367-4370). |
| `run_tests.gd` suite 86 | `:7117-7136` | free-play chain start leaves `completed_contracts`, `currency`, and `xp` unchanged (7133-7135). |
| `test_t02_state_lifecycle.gd` | `:329-334,358-378,407` | capture/timeout/collapse each bank the stashed 750 (`after - before == 750`, 333); escape banks `banked` (368); replay unchanged (378); host finish banks `money_taken` (407). |
| `test_w6u2_catalog.gd` W6U2.30-32 | `:364-403` | Bob Hair purchase `bob_funds == before - 7500` (376); zero funds refuses (387-390); locked row refuses and `currency == locked_before` (399-403). |
| `probe_personal_quest.gd` | `:104,154,225` | `currency == currency_before` after Owl pickup (154) and after chain (225). Same assertions in `probe_personal_quest_subset.gd:605,654,724`. |

### 5.3 Endgame ladder / run clock

| Test | Citation | Assertion (quoted) |
|---|---|---|
| `test_w7e_endgame.gd` S5.1a | `:129-131` | `run_time_limit == 3300.0` and `main_source == "mission_row"` for LootTheRoom. |
| `test_w7e_endgame.gd` S5.1b | `:134-136` | No mission id → `run_time_limit == 7200.0`, `main_source == "map_row"`. |
| `test_w7e_endgame.gd` S5.1c | `:144-148` | Contract deploy → `run_time_limit == 7200.0`, `main_source == "mission_row"`, `endgame_time_limit == 300.0`. |
| `test_w7e_endgame.gd` S5.1d | `:155-158` | OldManor contract → `run_time_limit == 7200.0`, `endgame_time_limit == 480.0`. |
| `test_w7e_endgame.gd` S5.2a | `:162-164` | `get_mission_plan(OUT_MISSION).endgame_duration == 480` ("no silent re-baseline"). |
| `test_w7e_endgame.gd` S5.2b | `:165-168` | `get_mission_endgame_seconds(OUT_MISSION) == 1200.0` and `get_mission_endgame_source(...) == "KF13"`. |
| `test_w7e_endgame.gd` S5.2c | `:172-174` | `endgame_time_limit == 1200.0` and `clock.endgame_source == "KF13"`. |
| `test_w7e_endgame.gd` S5.2d | `:178-180` | VaultHeist `endgame_time_limit == 300.0`, source `"quest_graph"`. |
| `test_w7e_endgame.gd` S5.3/S5.4 | `:186-212` | Fresh run phase `main`; objective completion → `endgame` with elapsed 0; 10 s ticks only `endgame_elapsed`; repeated completion does not reset; main expiry → `failed` + reason `TIME EXPIRED`. |
| `test_w7e_endgame.gd` S5.10 | `:464-486` | HUD `phase_countdown_text()` is `"55:00"` for 3300 s main, then `"20:00"` after `begin_endgame(1200.0)`, then `"19:00"` at 60 s. |
| `test_w6u1_briefing.gd` W6U1.3-8 | `:57-75` | Override `endgame_seconds == 1200`, `source == "KF13"`, `authored_qg_endgame_seconds == 480` (57-65); plan `endgame_duration == 480` (68-70); accessor `1200` (71-73); source `"KF13"` (74-75). |
| `test_w6u1_briefing.gd` W6U1.12 | `:111` | `format_mission_briefing(raw, 3300.0, 1200.0)` equals the authored 11-line letter (minutes 55 / 20). |
| `run_tests.gd` suite 65f | `:5811` | Guildhall Set plan `int(plan.get("endgame_duration", 0)) == 480`. |
| `run_tests.gd` suite 65h | `:5847-5856` | LootTheRoom plan: loot goals `4000/6000/8000`, `main_phase_duration == 1320`, `endgame_duration == 480`, mission durations `3300/1200/1200` (5851-5854). Pass message at 5900. |
| `e2e_tier2_boundaries.gd` T2-18-E | `:1207-1215` | `Mission.Guildhall.LootTheRoom` durations `3300/1200/1200` (1214). |
| `e2e_tier4_scenarios.gd` T4-13 | `:381,419` | free-play run `timer` is 3300 s (`absf(timer - 3300.0) < 0.5`). |
| `test_t02_state_lifecycle.gd` | `:287-306` | Den hub `run_time_limit == 0.0` and `endgame_time_limit == 0.0`, source `"hub"` (287-290); next Guildhall map row `7200.0`, `main_source == "map_row"` (303-306). |
| `e2e_tier2_boundaries.gd` T2-17-E | `:1119-1124` | Den mission-row timers 5400/3600/2700 (`absf(t1-5400)<1`, etc.). |

### 5.4 Unlock gating

| Test | Citation | Assertion (quoted) |
|---|---|---|
| `test_w6u2_catalog.gd` W6U2.14 | `:225-234` | KF08 profile `xp=1500`, `level=4`, contracts 1-2, `currency=26275`; `level_for_xp(1500) == 4`. |
| `test_w6u2_catalog.gd` W6U2.15a/b | `:240-249` | Every KF08 price row is `STATE_BUY`; exactly 4 Spider rows with `price > 0` are `STATE_BUY` at level 4 ("exactly the four authored Level-4 prices show, the rest lock"). |
| `test_w6u2_catalog.gd` W6U2.16/17 | `:254-264` | `zipwire`, `smoke_bomb`, `novice_difficulty`, `guildhall`, `old_manor`, `spider`, `Outfit.Spider.Head.BowlerA` are `STATE_PURCHASED`; `pickpocket_fairy`, `thief_difficulty`, `chameleon`, `Outfit.Spider.Head.TopHatA` are `STATE_LOCKED`. |
| `test_w6u2_catalog.gd` W6U2.18a-d | `:268-287` | Contract 1 does not unlock Chameleon; contract 3 does; `Thief.Chameleon` price 10000 + contract 3; starter perks do not include Chameleon. |
| `test_w6u2_catalog.gd` W6U2.29-32 | `:364-403` | Bob Hair shows £7,500 + BUY; BUY deducts 7,500 and owns the save id; zero funds refuses; locked `TopHatA` refuses and shows `Requires Level` (401). |
| `run_tests.gd` suite 60c | `:4950-4999` | Sets `xp=0,currency=0,completed_contracts={}`; `pickpocket_fairy` shows `"Requires Contract 3"` and hides BUY (4972-4973); locked button reads `LOCKED`, not `PRICE UNKNOWN` (4975-4976); level 4 profile shows Bob Hair `£ 7,500` + BUY (4982); `Outfit.Spider.Head.BowlerA` shows `✓ PURCHASED` (4985); all 68 rows carry an authored state (4999). |
| `test_w6u2_catalog.gd` W6U2.25/28 | `:339-362` | Table row counts 7/7/28/26; all 68 rows label as ✓/price/locked, 0 unknown prices. |

### 5.5 Save schema / migration / producer

| Test / gate | Citation | Assertion (quoted) |
|---|---|---|
| `test_w7s_loot_save.gd` 90.1/90.2 | `:83-86` | Persisted `save_schema == 8` and `loot_schema == 1`; comment says the literal must be updated deliberately with a bump. |
| `test_w7s_loot_save.gd` 90.34-90.40 | `:208-231` | Pre-v8 stamp 0 upgrades once; `save_schema == 8` + `loot_schema == 1` (220); unknown payout keys dropped (223); second call returns false (226); currency untouched (227); newer stamp 9 not downgraded (231). |
| `test_t02_save_integrity.gd` T02-03 | `:177-212` | Good save migrates `save_schema` to `8` (197), writes only once (208), never quarantines. |
| `run_tests.gd` suite 90 registration | `:7235-7244` | Runs `test_w7s_loot_save.gd` and prints "PASS: 90 W7S-S2 loot save v8 (payout idempotency, migration, major mesh)". |
| `tools/test_parse_project_ini.py` | `:223-224,317,350` | Producer self-test: `prog["maximum_level"] == 25`, `prog["level_up_xp"] == 500`; `proj["endgame_durations_by_difficulty"] == [1200.0, 600.0, 300.0]`; `scoring["contract_complete_bonus"] == 100.0`. |
| `tools/check_logic_data.py` | `:67` | `UNLOCK_TYPES = {"RequiredLevel", "RequiredContract"}` — the only two gate kinds the logic gate accepts. |
| `tools/check_consumers.py` + allowlist | `tools/consumer_allowlist.json:156-163` | `project_settings.json` is `blocked_on_team T10`; consuming it must update the allowlist, and `make audit` runs `check-consumers`. |

---

## 6. Save-migration precedent (for a v9 progression migration)

### 6.1 Code pattern already in the repo

The established pattern is a one-shot migration function with its own schema constant + flag, returning `bool`, called from `load_save()` and persisted by a single `write_save()`:

| Migration | Schema const | Flag / stamp | Function | Hook |
|---|---|---|---|---|
| Settings/FOV | `SETTINGS_SCHEMA_VERSION=2` (`:33`) | `settings_schema`, `settings.fov_migrated` | `_migrate_settings_schema` (`:742-752`) | `load_save` `:951` |
| Capture persona | n/a | `player_name_migrated` | `_migrate_player_name` (`:760-767`) | `:952` |
| Personal quest | `PERSONAL_QUEST_SCHEMA_VERSION=1` (`:115`) | `personal_quest_schema`, `personal_quest_migrated` | `_migrate_personal_quest` (`:717-722`) | `:954` |
| Unlock catalogue ids | `UNLOCK_IDS_SCHEMA_VERSION=1` (`:55`) | `unlock_ids_schema`, `unlock_ids_migrated` | `_migrate_unlock_ids` (`:779-810`) | `:956` |
| Root loot/payout | `SAVE_SCHEMA_VERSION=8` (`:11`), `LOOT_SCHEMA_VERSION=1` (`:12`) | `save_schema`, `loot_schema` | `_migrate_save_schema` (`:862-883`) | `:958` |
| Payout outbox settle | n/a | `pending_payout.match_id/applied` | `_settle_pending_on_load` (`:889-897`) / `settle_pending_payout` (`:1206-1210`) | `:962` |

`_migrate_unlock_ids` is the closest precedent for a new keyed migration: it validates/strips/merges known ids, preserves unknown ids, stamps `unlock_ids_schema`, sets `unlock_ids_migrated`, and returns true only when it ran. `_migrate_save_schema` additionally fingerprints before/after so a second boot writes nothing.

A new v9 progression migration would therefore normally: add `SAVE_SCHEMA_VERSION 9` (or a dedicated `PROGRESSION_SCHEMA_VERSION`), add its defaults to `_defaults()`, add its one-shot `_migrate_*() -> bool`, call it from `load_save()` `:951-961`, and update every test that pins the literal 8.

### 6.2 Documentation precedent

- `docs/reports/w7s-s2-loot-save.md:85-99` — "Save v8 migration": old saves merge into v8 defaults, `_migrate_save_schema()` stamps 8/1 once, strict payout records, unknown keys dropped, `bank_payout` idempotent, crash outbox settles once, fields retained.
- `docs/reports/remediation-20261125/T02-state.md:478-486` — RE-N-02: "`save_schema = 8` is a label, not a history"; a versioned chain is deferred because the shipped save layout is unextracted; the fix was pinning the persisted literals 8/1 in tests so a silent bump is visible.
- `docs/HANDOFF_NEXT_AGENT.md:423` — W7 close-out describes "save v8 with an idempotent payout outbox"; `AGENTS.md:123` architecture line names `save_system (save v8 + payout outbox)`.

### 6.3 Tests that pin the current schema literal (will need a deliberate update)

- `game/tests/test_w7s_loot_save.gd:84` (`persisted_save_schema == 8`), `:86` (`loot_schema == 1`), `:220` (`save_schema == 8 and loot_schema == 1`).
- `game/tests/test_t02_save_integrity.gd:197` (`save_schema == 8`).
- `game/tests/run_tests.gd:7235` comment "save v8"; suite 90 is the registration, not a literal assertion.
- Any new migration test should copy the `test_w7s_loot_save.gd:208-233` shape (pre-version → version, one-shot, unknown keys dropped, newer forward stamp not downgraded, currency untouched).

---

## 7. Additional exact facts worth carrying forward

- `GameState.difficulty` is 1-based (`enum Difficulty { NOVICE = 1, THIEF = 2, MASTER_THIEF = 3 }`, `game_state.gd:19`; default `NOVICE`, `:42`). `get_mission_duration()`/`get_match_duration()` index with `clampi(difficulty - 1, 0, size - 1)` (`game_data.gd:543,681`).
- `project_settings.project.endgame_durations_by_difficulty` is a 0-based array `[1200,600,300]`; `endgame_duration_seconds_by_difficulty_index` is the equivalent map `{"0":1200,"1":600,"2":300}` (`project_settings.json:150-159`). No code indexes it.
- `project_settings.project.maps` order is Guildhall → `Mission.Guildhall.VaultHeist`, `Mission.Guildhall.Set`, `Mission.Guildhall.LootTheRoom`; OldManor → `Mission.OldManor.Set`, `Mission.OldManor.Vault`, `Mission.OldManor.LootTheRoom` (`project_settings.json:312-316,368-372`).
- `project_settings.project.map_type_settings` has 8 rows (`project_settings.json:173-294`): indexes 0/1/2 are all `allow_active_quests=false, allow_default_player_tools=false, add_default_player_gear_loadout_on_spawn=false, run_map_variation=false, use_map_intro_states=true`; 3 is all true; 4 is all false (including `use_map_intro_states=false`); 5 is `allow_active_quests=true, run_map_variation=true`, tools/loadout false, intro false; 6 is all true; 7 is all false. No runtime reader.
- `project_settings.project.post_ftue_contracts` = `Contract.Main.1` Complete, `Contract.Main.2` Objective (`project_settings.json:412-421`); no runtime reader. The runtime contract chain/order comes from `DT_Contracts_1_to_16.json` and `GameData.contracts` (`game_data.gd:310-360`).
- `project_settings.project.post_ftue_unlocked_content` = `Map.Guildhall`, `Tool.Type.Zipwire`, `Tool.Type.SmokeBomb` (`project_settings.json:422-426`); no runtime reader. SaveSystem starters already include `zipwire`, `smoke_bomb`, `guildhall`, `old_manor`, and the three Spider defaults + Bowler (`save_system.gd:92-103,345-347`).
- `project_settings.project.initial_unlocked_content` = 8 tags (`project_settings.json:162-171`): `Difficulty.Novice`, `Thief.Spider`, `Outfit.Spider.Head.Default`, `Outfit.Spider.Body.Default`, `Outfit.Spider.CallingCard.Default`, `Outfit.Chameleon.Body.Default`, `Outfit.Chameleon.CallingCard.Default`, `Outfit.Chameleon.Head.Default`. No runtime reader.
- `project_settings.project.ftue_min_thieves_den_money = 5000` (`:160`); default save currency is 0 (`save_system.gd:350`), and there is no FTUE bankroll grant in `game/src` (grep for `5000`/`ftue.*money` finds no grant path).
- `project_settings.project.unlockable_content_data` = `/Game/UI/Progression/DA_UnlockableContentEntries.DA_UnlockableContentEntries` (`:654`; raw key at `:639`); it is an asset path, not runtime data. The generated `gameplay/unlocks.json` is the runtime source.
- The authored `progression` block also has `player_stat_data_table = /Game/Gameplay/Progression/DT_PlayerStats.DT_PlayerStats` (`:53`); that table has 5 rows (`PlayerStats.Alarms.Disabled`, `.Cooperation.Respawns`, `.Detected`, `.Keys.Acquired`, `.Locks.Picked`) and no XP amounts (it is display metadata).
- The authored `progression.xp_to_level.value = 1.0`, `registry_type = "None"`, row `XPToLevel`, table `CT_XPToLevel` (`:130-135`); `xp_to_level_table` points at the unextracted `DT_XPToLevel` (`:136`).
- `docs/reports/re-audit-20261124.md:219-220` claims "the endgame ladder is flat 1200 s at every difficulty"; the exact code shows 1200 only for the LootTheRoom KF13 path and QG 480/300 for other missions. The shared fact is that the authored 1200/600/300 ladder is unread; the per-mission current values are in §4.4.
- `docs/reports/re-audit-20261124.md:524` records the XP award `max(100, score/2)` and "cap 200 vs authored 25" as a known gap; `docs/reports/remediation-20261125/T02-state.md:487-496` records XP/contract recording as not idempotent/deferred ("the port-invented `xp += max(100, score/2)` is unchanged and remains a KNOWN gap").

---

*End of A2 fact sheet. No code, data, save, test or documentation file other than this one was written.*
