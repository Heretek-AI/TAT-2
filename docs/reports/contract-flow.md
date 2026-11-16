# Contract Flow — real sublevel lists + match timer

Stage report: stop hardcoding contract sublevel lists; add the real match
timer from the extracted tables.

## 1. What changed (files touched)

| File | Change |
|---|---|
| `tools/parse_contracts.py` | NEW. Normalizes `DT_Contracts_1_to_16.json` + 4 `DT_Missions_*` tables into `game/data/generated/gameplay/contracts.json`. UE->res rule identical to `parse_tables.py` (`/Game/Maps/` prefix stripped). |
| `game/data/generated/gameplay/contracts.json` | GENERATED (gitignored, like all of `game/data/generated/`). 16 contracts + 6 mission-duration rows. Rebuild with `python3 tools/parse_contracts.py`. |
| `game/src/core/game_data.gd` | Loads `contracts.json` as overlay (`_load_contracts_json`); new `get_contract_sublevels(order)` (existing files only) and `get_match_duration(map_id, difficulty)` (0 = unlimited). Table parsing kept as fallback when the file is missing. |
| `game/src/missions/mission_controller.gd` | `_map_id_to_sublevels` keeps the base map lists; the `Contract%02d`-style wildcard entry is deleted and replaced by `GameData.get_contract_sublevels(order)` (dedup, append). `start_contract` sets `GameState.run_time_limit`; `_process` fails the run via `_on_time_expired` (state `failed`, `TIME EXPIRED` reason, standard result panel). |
| `game/src/core/game_state.gd` | NEW `run_time_limit: float = 0.0`, reset in `reset_run`. |
| `game/src/ui/hud.gd` | Objective line shows `%02d:%02d LEFT` while a limit is active; `show_result` appends a `Time expired … (TIME EXPIRED)` note when the run failed by timer. |
| `game/tests/_tmp_contracts_check.gd` | TEMP check, deleted after green run (never added to `run_tests.gd`). |

`run_tests.gd`, `thief_character.gd`, `guard_ai.gd`, `level_loader.gd`,
other parsers, extractor, Makefile, Android files: untouched.

## 2. Contract → map → sublevel table (from `contracts.json`)

| Order | Contract id | map_id | Sub-level file(s) under `res://data/generated/levels/` | Loot tag |
|---|---|---|---|---|
| 1 | Contract.Main.1 | thieves_den | (none — Thieves' Den hub tutorial) | Loot.Quest.Tutorial.Jewel |
| 2 | Contract.Main.2 | guildhall | Guildhall/Guildhall_Contract_02 | Loot.Quest.VistaraFiles |
| 3 | Contract.Main.3 | old_manor | OldManor/OldManor_Contract03 | Loot.Quest.MaryElwayPapers |
| 4 | Contract.Main.4 | guildhall | Guildhall/Guildhall_Contract_04; Guildhall/Guildhall_Contract_Teleporters | Loot.Quest.SecretTrinket |
| 5 | Contract.Main.5 | old_manor | OldManor/OldManor_Contract05 | Loot.Quest.GuestNote |
| 6 | Contract.Main.6 | guildhall | Guildhall/Guildhall_Contract_06 | Loot.Quest.NightingaleFile |
| 7 | Contract.Main.7 | old_manor | OldManor/OldManor_Contract07 | Loot.Quest.Contract7.Set.Boots (+EyeArgon, +RussianEgg via `ItemsToSteal`) |
| 8 | Contract.Main.8 | old_manor | OldManor/OldManor_Contract08 | Loot.Quest.SocialCalendar |
| 9 | Contract.Main.9 | guildhall | Guildhall/Guildhall_Contract_09 | Loot.Quest.MissingThiefFile |
| 10 | Contract.Main.10 | old_manor | OldManor/OldManor_Contract10 | Loot.Quest.PactofOberon |
| 11 | Contract.Main.11 | guildhall | Guildhall/Guildhall_Contract_11 | Loot.Quest.PactofOberonFiles |
| 12 | Contract.Main.12 | old_manor | OldManor/OldManor_Contract12 | Loot.Quest.OberonContract |
| 13 | Contract.Main.13 | guildhall | Guildhall/Guildhall_Contract_13 | Loot.Quest.OldCityMap1 |
| 14 | Contract.Main.14 | old_manor | OldManor/OldManor_Contract14 | Loot.Quest.OldCityMap2 |
| 15 | Contract.Main.15 | guildhall | Guildhall/Guildhall_Contract_15 | Loot.Quest.ArrestTranscript |
| 16 | Contract.Main.16 | guildhall | Guildhall/Guildhall_Contract_16 | Loot.Quest.ValuableTrinket |
| 17–18 | (expansion, table-defined) | jaspering_hall | (none) | BlueMalcolm / OberonSeal |

All 16 resolved `sublevels_res_paths` verified present on disk (16/16).
Each entry also carries `map_ue_path`, `clues_ue_path`, `outro_flow`,
`intro_text`/`outro_text`, `title_text`/`description_text`.

## 3. Duration table (from `DT_Missions_*`, seconds by difficulty 1/2/3)

| map_id | Novice | Thief | Master | Source row / table |
|---|---|---|---|---|
| guildhall | 7200 | 2700 | 1800 | `Mission.Guildhall.VaultHeist` / `DT_Missions_Guildhall.json` |
| old_manor | 7200 | 2700 | 1800 | `Mission.OldManor.Vault` / `DT_Missions_OldManor.json` |
| thieves_den | 5400 | 3600 | 2700 | `Mission.Tutorial.ThievesDen` / `DT_Missions_ThievesDen_Tutorial.json` |
| ftue | 0 | 0 | 0 | `Mission.Tutorial.Single` / `DT_Missions_Tutorial.json` |
| jaspering / jaspering_hall | 0 (`alias_of: ftue`) | 0 | 0 | same FTUE row (expansion has no timer) |

The `LootTheRoom` mission variants (Guildhall 3300/1200/1200, OldManor
4500/1800/1500) are side-mission rows and are intentionally NOT used; the
per-map canonical row is the Vault heist. Difficulty index is clamped, so
out-of-range values fall back to the nearest real value, never invented.

## 4. Timer behaviour

- `start_contract`: `run_time_limit = get_match_duration(map_id, difficulty)`.
  FTUE/tutorial/expansion/Jaspering and unknown maps → `0.0` (unlimited).
- `_process` (state `playing` only): `elapsed_sec += delta`; when
  `limit > 0 and elapsed >= limit`, `_on_time_expired()` sets state
  `failed`, flags `contract_info.timed_out/timeout_reason = "TIME EXPIRED"`,
  and reuses `hud.show_result(false, …)`. No new state string.
- HUD: objective line appends `MM:SS LEFT` (remaining, floored); result
  panel appends `Time expired — the match window closed before you
  escaped. (TIME EXPIRED)` whenever the failure was by timer (flag or
  limit/elapsed comparison as backstop).
- `reset_run` zeroes `run_time_limit` (and `elapsed_sec` as before), so a
  stale limit can never leak into the next run.

## 5. Fallbacks (no invented data)

- `contracts.json` missing/unparseable: `_load_contracts_json` returns
  early; contracts stay as parsed from `DT_Contracts_1_to_16.json`,
  `mission_durations` stays empty, `get_match_duration` returns `0.0`.
- Unknown `map_id`: falls back to the FTUE zero row when available, else `0.0`.
- `get_contract_sublevels` returns only paths where
  `FileAccess.file_exists` is true; missing files are skipped, never faked.
- Shipped-table bug handled, not hidden: `Contract.Main.15` carries
  `ContractOrder = 0` in BOTH `DT_Contracts_1_to_16.json` and
  `CDT_Contracts.json`; the parser repairs it from the row key
  (`Contract.Main.N`) and the overlay matches by repaired order.

## 6. Temp-check output (`_tmp_contracts_check.gd`, since deleted)

30/30 PASS, `TMP SUMMARY: fails=0`:
contract 2 → `Guildhall_Contract_02` exists + map `guildhall`;
contract 3 → `OldManor_Contract03` exists + map `old_manor`;
durations guildhall/old_manor `[7200,2700,1800]`, thieves_den
`[5400,3600,2700]`, jaspering/jaspering_hall/ftue `0`, unknown map `0`;
`reset_run` clears the limit; simulated `elapsed >= limit` drives state to
`failed` with `TIME EXPIRED`; contract-2 sublevel list has no duplicates,
every entry exists on disk, no `Contract%02d`-style wildcard remains in
`mission_controller.gd`; HUD shows `44:00 LEFT` and the result panel
contains `Time expired (TIME EXPIRED)`.

Self-audit note (stated plainly): the brief asked the temp check to show
the contract-2 list has "fewer entries than the fallback". That is not
true and was not faked: old list 13 entries vs new list 13 entries —
the old `Guildhall_Contract_02` wildcard path coincides string-for-string
with the resolved file (it exists on disk), so replace-vs-append yields
the same count. The check instead proves the wildcard *mechanism* is gone
(no `%02d` formatting left in the controller source), the list has no
duplicates, and all entries exist. The `<=` size assertion guards the
no-dup-append regression.

## 7. Full suite

`make test` → `SUMMARY: fails=0`, zero `SCRIPT ERROR` lines (suites 4/7/10
spawn Old Manor / Thieves' Den / Guildhall missions). Full output in §8.

## 8. Exact commands + exit codes

- `python3 tools/parse_contracts.py` → exit 0
  (`Wrote 16 contracts + 6 mission durations -> …/contracts.json`).
- `flatpak run org.godotengine.Godot --headless --path game --script res://tests/_tmp_contracts_check.gd` → exit 0, `TMP SUMMARY: fails=0` (file deleted afterwards).
- `make test` → exit 0, `SUMMARY: fails=0`, no `SCRIPT ERROR`.
