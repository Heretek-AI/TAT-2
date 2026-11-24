# W0S — Spider personal chain data and save foundation

Wave: W0S (Spider 01→04 data/save foundation). Worktree:
`/tmp/opencode/tat2-ns-spider`. Date: 2026-11-24.

This wave is **data + save + pure controller only**. It does not add NPC
actors, dialogue UI, the Owl interaction, a world pointer, or any
`mission_controller.gd` wiring; those belong to the later runtime wave.

## What is authored vs. what was missing

`CLS_Personal_Spider_01..04` are shipped assets, but the port never emitted
their per-clue interaction fields and had no chain state at all. The shipped
facts are:

| set | facts | notes |
|---|---|---|
| `CLS_Personal_Spider_01` | `Intro` (dead), `FoundLetter`, `MallickSlip`, `StatuePet`, `ObjectiveComplete_Clue`, `ObjectiveComplete_Electrogram` | note + two electrotype messages |
| `CLS_Personal_Spider_02` | `OwlLocation` | Lucius message |
| `CLS_Personal_Spider_03` | `HandedOff`, `Reminder` (never granted) | courier hand-off |
| `CLS_Personal_Spider_04` | `GotInfo`, `Renegade` (never granted) | informant |

Eleven fact rows in four tables; six dead facts overall (unchanged), of which
`Intro` and `Renegade` are the Spider pair. `ObjectiveComplete_*` rows have no
journal text and are never granted. `Reminder`/`Renegade` are deliberately
dropped from the chain (the 03/04 electrotype warnings).

## Deliverables

1. **`tools/parse_clues.py`** — every clue record now carries the authored
   interaction fields:
   - `distribution` (`ETATElectrotypeClueDistribution::Global|Local`, verbatim),
   - `allow_follow_up_dialogue`,
   - `follow_up_dialogue` (nested `text_record`: text/key/table/namespace/
     present/resolved_from),
   - `use_override_interaction_prompt`,
   - `override_interaction_prompt` (nested text record).

   New stats: `clues_with_follow_up_dialogue=2`,
   `clues_with_override_interaction_prompt=0`. All existing census counts are
   unchanged.

2. **`game/data/expansion/personal_spider.json`** (tracked) — the full chain:
   8 beats over stages `""|intro|letter|electrotype|located|carrying|
   delivered|info|complete`, the 7 grantable fact ids, the 4 never-grant ids,
   exact 03/04 dialogue lines and follow-ups, exact journal texts,
   `start_when_completed_contract: 0`, `grant_reminder: false`, and the four
   producer position pins:
   - library note `BP_Readable_ClueSpawner_Guildhall_C_28`
     `(-26.8541, 28.0021, -9.4431)` (Guildhall MissionClues),
   - Owl `BP_QuestSpawner_Item_C_2` `(-31.6286, 36.4655, -43.9759)`
     (Guildhall Gameplay; fallback `_C_0` Tower `(10.9846, 54.5118, -54.9085)`),
   - courier `BP_Readable_ClueSpawner_Guildhall_C_1`
     `(35.9, 27.0019, -22.728)` (Lounge; fallback `_C_33` DiningHall
     `(8.2, 28.4942, -66.1)`),
   - 04 informant grounded Courtyard C1 `(1.5, 10.1096, 13.0)` (Old Manor;
     fallbacks `BP_SmartObject_GuardDefensiveLocation_C_839/838/840`).

   No Guildhall fallback exists for the 04 informant and no position is
   invented: every pin is a producer-recorded actor/pos.

3. **`game/src/quests/personal_quest.gd`** (new, `RefCounted`, static) — reads
   the expansion JSON and the SaveSystem/GameState autoloads only. API:
   `record`, `stage_for`, `spawn_plan`, `deliver_pending_messages`,
   `acquire_owl`, `deliver_owl`, `deliver_info`, `close_info`,
   `suppressed_clue_sets`, `is_grantable`, `should_start`, `hydrate_facts`,
   `entry_for`/`owl_for`/`facts_for`, `anchor`. Stage order is enforced one beat
   at a time; every transition is idempotent.

4. **`game/src/core/save_system.gd`** — `personal_quest_schema:1`,
   `personal_quest_migrated`, `personal_quest.<thief> {stage, owl, facts[]}` in
   `_defaults()`. `_ensure_personal_quest()` validates domain values, filters
   facts to the seven authored ids, dedupes, raises the stage from facts, and
   applies the 04 clamps (info/complete need `GotInfo`; delivered needs
   `HandedOff`; Owl state must match the stage). Unknown keys at thief/entry
   level are preserved. One-shot `_migrate_personal_quest()`. Public API:
   `get_personal_quest`, `set_personal_quest_stage`, `set_personal_quest_owl`,
   `add_personal_quest_facts`, `has_personal_quest_fact`,
   `reset_personal_quest`, `reset_all_personal_quests`.

   `game/src/core/game_state.gd` — `hydrate_personal_facts()` re-journals the
   active thief's stored facts from `GameData.grant_fact`; `reset_run()` calls
   it after the per-deploy journal wipe. Personal facts survive a deploy;
   contract facts (never serialized) do not.

5. **`tools/check_clue_quests.py`** — exact producer checks for the 4 sets, the
   11 fact ids, the 6 dead facts, the Owl loot row (`value=2500`, mesh
   `SM_StatueOwlA`), the expansion beats/grants/dialogue/journal, the no-
   Reminder/no-Renegade grant lists, the follow-up/override census (2/0) and
   every anchor pin + fallback set. Existing census checks are untouched.

6. **Suite 86 in `game/tests/run_tests.gd`** — defaults, one-shot migration,
   normalization (unknown keys, invalid values, fact filtering, fact-driven
   stage raise, 04 clamps), public API, the full 8-beat chain, per-thief
   isolation, free-play start without banking contract progression, write +
   fresh-load restore, and contract-fact wipe on deploy. No NPC/runtime
   assertions.

## Gate evidence (this worktree)

```text
tools/check_scripts_compile.gd   scripts checked: 83, broken: 0
make test                        SUMMARY: fails=0 (suite 86 PASS)
python3 tools/check_clue_quests.py
                                 CLUE-QUEST CHECKER: PASS (118 checks)
python3 tools/parse_clues.py     clues: fact_tables=22, fact_rows=96,
                                 reachable_facts=90, dead_facts=6, clue_sets=44,
                                 clue_entries=503, enabled_clues=406,
                                 disabled_clues=97,
                                 clues_with_follow_up_dialogue=2,
                                 clues_with_override_interaction_prompt=0 ...
make audit                       AUDIT PASS (exit 0)
```

Suite 86 evidence line:

```text
PASS: 86 Spider personal chain (schema/migration/normalization, 8-beat chain,
per-thief, free-play, save restore, contract-fact wipe)
```

## Audit baseline diff

`make audit-refresh-stamps` updated 12 baseline lines:

- `tools/parse_clues.py` source sha + `gen:gameplay/clues.json`
  bytes/mtime/sha (new fields: 1,233,863 → 1,514,019 bytes);
- `tools/parse_tables.py` and `tools/parse_gameplay.py` `gen:gameplay`
  aggregate sha/bytes/mtime — both declare the whole gameplay directory, so
  the same clues.json change moves their aggregate pins;
- `tool_versions.vgmstream` `r2168` → `missing` (pre-existing environment
  drift: the decoder is absent in this container; no audio output was
  regenerated) and `written_utc`.

No Makefile change was made. The integrator should refresh again after the
other Wave-0 Makefile edits and after vgmstream is restored on the build host.

## Risks / blockers for the runtime wave

- **No Owl transform**: the pin is the authored spawner location. The runtime
  must ground/attach `SM_StatueOwlA` and decide its rotation; nothing here
  invents a transform.
- **No pointer/indicator**: the 04 informant's primary is a grounded logical
  Courtyard C1 point with no authored actor (fallbacks are guard defensive
  smart objects). Do not add a Guildhall fallback or an invented quest pointer.
- **No runtime**: `mission_controller.gd` is untouched, so no deploy wiring,
  no NPC actor, no conversation UI and no journal UI integration yet.
  `spawn_plan()` is advisory data for that wave.
- `Intro` is a producer-dead fact (no clue set consumes it) but is intentionally
  granted as the chain's first journal line; it has authored text.
- Free play starts the chain (first Guildhall deploy) but the wave proves it
  banks no contract progression; the live `_on_extracted()` policy is still the
  mission controller's responsibility in the runtime wave.
