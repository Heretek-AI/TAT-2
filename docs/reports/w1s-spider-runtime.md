# W1S — Spider personal chain runtime (01 → 04)

Wave: W1S (runtime NPCs, dialogue, Owl pickup, 04 informant, mission hooks).
Worktree: `/tmp/opencode/tat2-w1s`. Date: 2026-11-24.

This wave turns the W0S data/save foundation into a playable chain. It does not
change the authored expansion record, the save schema, generated data or any
shared docs. The real-map walkthrough probe is written and compile-checked but
**was aborted by the thermal watchdog before it produced a result** (see
“Thermal status”).

## Runtime chain as implemented

| Stage | Trigger (runtime) | Actor / pin | Facts |
|---|---|---|---|
| `intro` | first `guildhall` deploy, contract or free play (`on_deploy`) | Library note `BP_Readable_ClueSpawner_Guildhall_C_28` `(-26.8541, 28.0021, -9.4431)` | `01:Intro` |
| `letter` | interact with the note (`ClueItem` `clue_collected`) | same note | `01:FoundLetter` |
| `electrotype` | `on_hub_enter()` at Den setup, or the next deploy | — | `01:MallickSlip`, `01:StatuePet` |
| `located` | `guildhall` deploy while `electrotype` (`on_deploy`) | Vault Owl `BP_QuestSpawner_Item_C_2` `(-31.6286, 36.4655, -43.9759)`; authored fallback `_C_0` `(10.9846, 54.5118, -54.9085)` | `02:OwlLocation` |
| `carrying` | Owl `interact` (`PersonalQuest.acquire_owl`) | courier `BP_Readable_ClueSpawner_Guildhall_C_1` `(35.9, 27.0019, -22.728)`; fallback `_C_33` `(8.2, 28.4942, -66.1)` | — (Owl held) |
| `delivered` | first courier talk (`deliver_owl`) | same courier | `03:HandedOff` |
| `info` | first informant talk on Old Manor (`deliver_info`) | Courtyard C1 `(1.5, 10.1096, 13.0)`; fallbacks `BP_SmartObject_GuardDefensiveLocation_C_839/838/840` | `04:GotInfo` |
| `complete` | the **next** informant interaction (`close_info`) | — | — |

Never granted: `03:Reminder`, `04:Renegade`, `ObjectiveComplete_Clue`,
`ObjectiveComplete_Electrogram`. No loot count/value, currency, contract
progress, objective or `quest_item_acquired` is touched by this chain. The Owl
pickup is a personal item and is deliberately **not** in the `loot` group.

Authored lines (from the expansion record, not code literals):

- 03 first: `Aye, it's a Langnacht night tonight. I'll take the goods.`
- 03 follow-up: `We're done here. Skedaddle aff.`
- 04 first: `I heard you're looking for dirt on Mallick. This might help. If anyone asks, you didn't get it from me.`
- 04 follow-up: `We're done here. I have nothing else for you.`

Journal lines come from the authored facts (`I delivered the goods`;
`Chisholm gave me a copy of Mallick's police records. I'll review them later.`).

## Files

- **`game/src/quests/npc_clue_actor.gd`** (new) — `CivilianNPC` subclass; reuses
  the authored body/head rig and idle clip but holds the pinned spot (gravity
  only). Adds `interactables` / `personal_quest_npcs`, a chest LOS point
  (`+1.2 m`), the shipped `[E] Talk` prompt, and `resolve_talk()` for the
  courier (carrying → delivered) / informant (delivered → info → complete).
  The first line and follow-up are read from `PersonalQuest.beat_for()`;
  the follow-up is only shown on a later interaction.
- **`game/src/quests/npc_clue_dialogue.gd`** (new) — HUD-child `CanvasLayer`
  modal, one authored line, `CONTINUE` button (Alata 30) and body Alata 32.
  No pause, no portrait/nameplate/VO. Escape and the interact action close it;
  input in the opening frame is ignored so the talking press cannot
  immediately dismiss it. Registers with the HUD via `set_npc_dialogue()`.
- **`game/src/quests/personal_quest.gd`** — adds `character_id()`,
  `runtime_thief()`, `on_deploy(map_id)`, `on_hub_enter()`. The existing
  `record`/`deliver_pending_messages`/`acquire_owl`/`deliver_owl`/`deliver_info`/
  `close_info` remain the only transitions; every hook is Spider-guarded and
  idempotent.
- **`game/src/interact/loot_item.gd`** — `personal_quest_id` branch:
  `[E] Take Theban Owl`, `PersonalQuest.acquire_owl()`, no `add_loot`, no value,
  no objectives/facts; skips the `loot` and `xray_target` groups. Notifies the
  mission so the courier spawns in the same frame.
- **`game/src/missions/mission_controller.gd`** — `on_deploy(map_id)` before
  the level load, `on_hub_enter()` at Den setup, `_spawn_personal_quest_actors()`
  after `_spawn_clues()` (non-Den). Spawns the Library note (ClueItem), Vault Owl
  (LootItem personal branch), Lounge courier and Old Manor informant. Grounds
  each actor with a floor ray and **0.02 m** clearance on the real mesh AABB;
  tries an authored fallback only when the primary pin has no floor; never
  invents a position; dedupes personal anchors by id and point. Exposes
  `personal_quest_actors` (`{anchor_id, kind, node, pos, source, actor}`).
  `on_personal_quest_owl_taken()` spawns the courier immediately.
- **`game/src/ui/hud.gd`** — minimal arbitration: `set_npc_dialogue()`,
  `is_npc_dialogue_open()`, pause/Escape close, map/ping/mouse guards and prompt
  suppression while the conversation is open. Existing letter/map/ping/pause
  paths are unchanged when no NPC dialogue is open.
- **`game/tests/test_spider_runtime.gd`** (new) — in-process mock/unit suite.
- **`game/tests/probe_personal_quest.gd`** (new) — real Guildhall + Old Manor
  walkthrough probe (deferred; see below).
- **`game/tests/run_tests.gd`** — suite 87 calls the mock; also adds
  `--spider-only` to run just suite 87 (`run_tests.gd -- --spider-only`) for a
  thermal-safe QA pass.

## Gates (measured)

```text
tools/check_scripts_compile.gd    scripts checked: 92, broken: 0
run_tests.gd -- --spider-only     PASS: 87 ... / SUMMARY: fails=0 (69 spider PASS lines)
tools/godot ... test_m2_player.gd M2_SUMMARY: fails=0
make test (14:53)                 SUMMARY: fails=0
make audit                        exit 2 — only the pre-existing vgmstream
                                  tool-version drift recorded by W0S
                                  ('r2168' -> 'missing'); all content/freshness
                                  checks pass (levels 107, contracts 16, tables
                                  144, materials 1629, devices 4118, anims 995,
                                  audio 5018, localization 8, videos 15)
```

The 14:53 full `make test` reported `fails=0`, but the captured 40-line tail did
not contain suite 87's PASS line. Suite 87 was therefore re-run explicitly with
`--spider-only` (same helper, no mission load): 69 spider PASS lines (68
checks plus the mock summary) and the suite line, `SUMMARY: fails=0`. A second full `make test` was started to capture the complete log and
**was aborted by the thermal watchdog at 96 °C** before it reached suite 87, so
the full-suite line is not independently re-captured in this worktree.

## Thermal status / what was deferred

- Package id 0 started at **91 °C**; windows below 88 °C were used for compile
  and the mock suite. `test_m2_player` ran from 80 °C and returned `fails=0`.
- The first full `make test` completed (`fails=0`, tail captured).
- The second full `make test` hit **96 °C** and the watchdog terminated it
  (`make: *** [Makefile:74: test] Terminated`); the run never reached suite 87.
- **The real-map probe `tests/probe_personal_quest.gd` was attempted once from
  79 °C and aborted by its watchdog at 95 °C (SIGTERM) before the first map
  finished loading — zero `[pq]` lines were produced.** The developer save was
  never at risk: the probe ran with `XDG_DATA_HOME=/tmp/opencode/w1s-data`.
  No real-map position, dialogue or chain result is claimed in this report.

Run it when the host is cool, alone, with one Godot process:

```bash
tools/godot --headless --path game --script res://tests/probe_personal_quest.gd
```

It restores the developer save and the borrowed `GameState` fields, and prints
`PERSONAL QUEST PASS|FAIL checks=... fails=...`.

## Risks / open work

- **Real-map grounding unverified.** The probe is the first evidence that the
  four pins ground in the loaded levels. The fallback rule is “primary grounds,
  else authored fallback”, not a scene-actor presence test: the loader records
  positions, not spawner names for readable spawners.
- **Possible spawner sharing.** `BP_Readable_ClueSpawner_Guildhall_C_28` can also
  be chosen by the contract clue pass for a Library clue. Personal actors are
  spawned after `_spawn_clues()` with fixed pins, so a contract clue and the
  Library note can share a point. No position is moved to avoid it (the chain
  must stay on the authored pin); if the probe shows overlap, the fix is to
  reserve personal pins in the clue pass, not to invent a fallback.
- **New scripts have no `game/**/*.gd.uid`** yet (headless `--script` runs do not
  write them). The next editor/import run generates them; add them in the
  integration commit if the repo wants UID parity.
- `--spider-only` is a QA/thermal convenience added to `run_tests.gd`; the
  default suite and gate behaviour are unchanged.
- The HUD dialogue modal keeps the mouse visible while open (same pattern as the
  mission-start letter) and never pauses; no gameplay input is blocked except
  map/ping/pause arbitration.
