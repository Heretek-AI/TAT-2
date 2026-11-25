# W9-P3-C1 independent audit — the three missing screens

**AUDIT: FAIL** (one blocking integration defect; checklist items 1–7 pass on
their own criteria)

- Auditor: independent reviewer; wrote none of this code and edited nothing but
  this file.
- Worktree: `/home/john/Projects/TAT-2-rem-w9-p3`, branch `rem/w9-p3`,
  HEAD `8ce9a863a3be70deb1e23d7c5fadfe054b7f750d` plus the wave's uncommitted
  working tree (the C1 files are untracked/`M` exactly as `git status` shows).
- Date: 2026-11-25.
- Method: re-ran the three mandated suites myself; read
  `post_match_ui.gd`/`progression_ui.gd`/`tutorial_ui.gd`/`tutorial_text.gd`
  against `save_system.gd`, `progression.gd`, `unlock_catalog.gd`,
  `focus_nav.gd`, `input_glyphs.gd`; cross-checked **every** `st_text`/`st_upper`
  key against the 54 generated StringTables and every locres-only string against
  `game/data/generated/localization/sources.json`; reconciled the XP formula
  arithmetic; reviewed the whole `game/tests/` diff since `8ce9a86`.

---

## 1. The three mandated suites (re-run, not trusted from the lead log) — PASS

Commands (one Godot at a time under the shared lock):

```
flock /tmp/opencode/tat2-godot.lock -c 'timeout 900 tools/godot --headless --path game --script res://tests/test_w9p3_screens.gd'
flock /tmp/opencode/tat2-godot.lock -c 'timeout 900 tools/godot --headless --path game --script res://tests/test_t05_ui_contract.gd'
flock /tmp/opencode/tat2-godot.lock -c 'timeout 900 tools/godot --headless --path game --script res://tests/test_w7v_ui_acceptance.gd'
```

| suite | exit | summary line | PASS lines | notes |
|---|---|---|---|---|
| `test_w9p3_screens.gd` | 0 | `W9P3_SCREENS_SUMMARY: fails=0 checks=39` | 39 | no SCRIPT ERROR, no leak warning |
| `test_t05_ui_contract.gd` | 0 | `T05_SUMMARY: fails=0 checks=56` | 56 | only the pre-existing exit-time `24 ObjectDB instances` / `9 resources still in use` warnings |
| `test_w7v_ui_acceptance.gd` | 0 | `W7V_SUMMARY: fails=0 checks=49` | 49 | only the pre-existing `12 ObjectDB` / `5 resources` exit warnings |

I also re-ran the shared C3 suite because C1's screens are in it and because
item 5 asks about the rebind:

```
flock … 'timeout 900 tools/godot --headless --path game --script res://tests/test_focus_walk.gd'
→ exit 0, FOCUS_WALK_SUMMARY: fails=0 checks=64 screens=10
  PASS: C3.rebind pad interact prints X before the rebind (X)
  PASS: C3.rebind the pad glyph follows the rebind X -> Y (Y)
  PASS: C3.rebind the authored FTUE rich text prints the rebound glyph ([Y] to pick)
  PASS: C3.rebind the authored interact mapping is restored (X)
```

But that run is **not clean**: one `SCRIPT ERROR` and three silently skipped
assertions, see finding **F5**.

The C1 suite's 39 PASS lines cover every advertised id C1.1–C1.30 (C1.6 and
C1.26 repeat per row/category); no id is missing from the log, so this suite did
not silently skip anything.

All 39 checks pass. **Verdict: PASS.**

---

## 2. Every visible label traced to an authored source — PASS (cosmetic notes only)

Extraction method: regex over all `st_text`/`st_upper`/`st_template`/`raw`
calls in the four files (28 distinct table/key pairs), then a lookup in
`game/data/generated/tables/StringTables/<table>.json`. Then the locres-only
strings against `game/data/generated/localization/sources.json` (3,404 source
strings), then a full-table sweep for every port label.

**28/28 table/key pairs exist** (0 missing):

| table | keys |
|---|---|
| `ST_PostMatch` (13 literal + 2 variable-key) | literal: `PostMatch.Contract`, `PostMatch.Haul`, `XP.Breakdown`, `XP.Breakdown.Contract.Successful/Unsuccessful`, `XP.Breakdown.Mission.Successful/Unsuccessful`, `XP.Breakdown.Extraction.Successful/Unsuccessful`, `XP.Breakdown.Time`, `XP.Breakdown.Difficulty`, `XP.Breakdown.FinishedTutorial`, `XP.MaxLevel`; variable: `PostMatch.Status.Escaped`, `PostMatch.Status.Caught` |
| `ST_Screens` (12 literal + 5 variable-key) | literal: `Screen.Back`, `Screen.Continue`, `Screen.Contract.Number`, `Screen.Label.Stats`, `Screen.Label.TotalAssets`, `Screen.Label.TotalHaul`, `Screen.Ledger.Journal`, `Screen.MainMenu.PlayTutorial`, `Screen.PostMatch.CashInHand`, `Screen.PostMatch.LootEarned`, `Screen.PostMatch.LootLost`, `Screen.PostMatch.Unlocks`; variable: `Screen.Stat.StealthKOs` (`Stealth Takedowns`), `Screen.Stat.CluesFound`, `Screen.Stat.KeysFound`, `Screen.Ledger.Contract.Status.Complete` (`Completed`), `Screen.Ledger.Contract.Status.InProgress` (`Active`) |
| `ST_Settings` (2 literal) | `Settings.Controls.Header` (`Controls`), `Settings.Gameplay.ShowTutorials` (`Show Tutorials`) |
| `ST_MapTool` (1 literal) | `CluePage.Clues` (`Clues`) |

Row templates are used correctly: `Screen.Contract.Number` = `Contract #{number}`
(replaces `{number}`), `Screen.PostMatch.LootEarned/LootLost` = `… £{0}`
(replaces `{0}`).

**Locres-only strings (2/2 exist):** `Level {CurrentLevel}` → `sources.json`
exact hit; `LEVEL UP!` → exact hit. These are the only `UIStringsScript.t(...)`
calls in the four files, and both rows genuinely have no StringTable row.

**Port labels (5, all marked in code; none has an authored counterpart):**

| marker | literal | sweep result |
|---|---|---|
| `PORT_XP_EARNED` (post_match_ui.gd:36) | `XP earned` | 0 hits in all 54 tables, 0 in locres |
| `PORT_OBJECTIVES` (tutorial_ui.gd:56) | `Objectives` | 0 / 0 |
| `PORT_INFOGRAPHICS` (:57) | `Infographics` | 0 / 0 |
| `PORT_DEN` (:58) | `Thieves' Den` | 0 / 0 as a title (only the sentence `Learn About the Thieves' Den` in locres) |
| `PORT_VIDEO` (:62) | `[ VIDEO ]` | 0 / 0; renders 0 times because every one of the 6 inferred video rows has authored prose |

The three tutorial category labels are justified: no StringTable value equals
`Objectives`/`Infographics`/`Thieves' Den`/`Den` in any of the 54 tables, and no
locres source equals them. `XP earned` likewise has no total row in
`ST_PostMatch` (I listed all 71 rows: breakdown rows and `XP.MaxLevel` only).

Notes (not defects):
- `post_match_ui.gd:458` builds the multiplier as `"x" + _mult_text(mult)`. The
  authored row `ST_PostMatch.PostMatch.Haul.CountMarker = "x"` exists. The
  rendered glyph is identical, so there is no visible divergence, but this is
  the one port literal that *does* have an authored row able to supply it.
- `"(£) "` (`post_match_ui.gd:344`, `progression_ui.gd:312`) is a port currency
  symbol (no table row contains `(£)`); the plain `£` used for Cash in Hand and
  Total Haul *is* authored inside the `LootEarned`/`LootLost` rows.
- The tutorial card's small id line (`ST_Tutorial.Tut_Fey_Intro`) is the
  table-qualified authored key, documented as a technical id, not prose.

**Verdict: PASS.** Every visible string either resolves to an authored row, the
authored locres, or one of the five explicitly marked port labels.

---

## 3. Post-match XP math — PASS (formula is exact)

The screen (`post_match_ui.gd:463–473`):

```
base     = xp_award("contracts") + xp_award("mission") + xp_award("win")
         + xp_award("time", {minutes: GameState.elapsed_sec / 60})
expected = int(roundf(float(base) * difficulty_xp_multiplier(GameState.difficulty)))
```

`save_system.gd:1147–1181` (`record_contract_complete`):

```
base     = xp_award("contracts") + xp_award("mission") + xp_award("win")
         + xp_award("time", {minutes: elapsed / 60})      # elapsed <= 0 → GameState.elapsed_sec
awarded  = int(roundf(float(base) * difficulty_xp_multiplier(GameState.difficulty)))
         + (is_ftue ? ftue_level_up_xp() : 0)
```

The base and the rounding are **mathematically identical** (same calls, same
order, same `roundf`), and every call site passes three arguments, so `elapsed`
resolves to the same `GameState.elapsed_sec` the screen reads
(`mission_controller.gd:235` and `:4651` both call with 3 args;
`save_system.gd:1163–1166`). `resolve_phase()` does **not** clear `elapsed_sec`
(`game_state.gd:397–401`) and the run clock stops ticking once
`GameState.state != "playing"` (`mission_controller.gd:4481`), so the value the
screen recomputes is the value that was banked. The one caller
(`hud.gd:2310–2320`) passes `run_xp_awarded()`, the measured save delta since
HUD creation, and the HUD is created per mission scene
(`mission_controller.gd:156`, `hud.gd:960`), so the measurement is per-run.

FTUE remainder (`post_match_ui.gd:368–375`): shown only when
`_won and (_xp_awarded - _expected_xp()) > 0`. At the single integration call
site the surplus can only be the authored FTUE credit, because the base terms
are identical.

Authored inputs (`game/data/generated/project_settings.json`, schema
`tat2.project_settings/1`): `contracts_xp=20.0`, `mission_xp=20.0`,
`win_xp=80.0`, `xp_per_minute=0.6`, `maximum_time_in_game_xp=25.0`,
`difficulty_xp_multipliers={Easy:1.0, Normal:2.0, Hard:3.0}`,
`maximum_level=25`, `ftue_level_up_xp_categories=[XP.ReachExitInTime,
XP.CompleteMission, XP.CompleteContracts]`,
`ftue_level_up_xp_is_on_top_of_regular_xp=true`.

Hand calculation (Novice, 0 elapsed minutes):

```
contracts 20 + mission 20 + win 80 + time round(0.6 × 0) = 120
× Easy 1.0                                              = 120   ← _expected_xp()
first completion is FTUE: + 3 tags × contracts_xp(20)   = +60   ← save_system
measured award                                          = 180
screen: expected 120, remainder 60 → "Finished Tutorial +60", "XP earned +180"
```

Cross-check against the live suite: the fixture passes `xp_awarded=120` and the
screen prints `+120` (C1.7). 120 is only reachable with Easy/1.0 and 0 minutes,
and `GameState`'s defaults are `NOVICE` / `elapsed_sec = 0.0`
(`game_state.gd:45,79`), so the run did use the path the hand calculation
models. No FTUE row appears because the award does not exceed 120.

**Verdict: PASS.** No arithmetic difference exists between the screen and the
save, including rounding, the time cap and the FTUE condition.

---

## 4. Progression data claims — PASS on the fabrication test, two accuracy defects

- `SaveSystem.has_completed_contract` **does not exist**:
  `grep -rn "has_completed_contract" game/src/` returns only the guarded
  `has_method`/`call` sites in `progression_ui.gd` — no definition in
  `save_system.gd`. The screen's `_has_completion_api()` gate is therefore false
  today, and `_refresh_contracts` (`progression_ui.gd:328–357`) never runs the
  1..16 sweep: it appends only the current payout/active order. **No fabricated
  completion.**
- Level line: `Level {CurrentLevel}` from `UIStringsScript.t(...)` with
  `get_level_progress()` (`progression_ui.gd:280–292`); at the authored cap it
  shows the authored `ST_PostMatch.XP.MaxLevel` (`MAX`) and a full bar. The
  fallback when no SaveSystem exists is `{level:1, xp_in_level:0,
  xp_needed:Progression.level_up_xp()}`.
- Unlock rows (`progression_ui.gd:362–426`) use `unlocks.json` (via
  `unlock_catalog.gd`) rows with non-empty `display.title.text` (68/68) and
  `display.description.text`; the gate sentence is the authored
  `condition.text` (`Unlocked at Level N.`), not a port sentence. Sorting is by
  `requires_level` then title.
- Stats: only counters that exist are shown (`GameState.takedowns`,
  `clue_facts`, `stolen_keys`, currency). `takedowns` is incremented only on a
  blackjack knockout (`thief_character.gd:4005–4007`), so the authored
  `Stealth Takedowns` label is accurate. Missing counters are omitted, not
  zeroed.

Discrepancies (do not violate the brief's "must not fabricate" test, but the
claim in the code/report is wrong — see **F3**):

1. `progression_ui.gd:12–14` and `p3-report.md:93–97` say
   "`completed_contracts` is not a public accessor" / "`completed_contracts` is
   not public". That is false: `save_system.gd:168` declares `var data:
   Dictionary = {}` (GDScript has no private members) and
   `unlock_catalog.gd:264–266` already exposes
   `completed_contract_orders()` reading `SaveSystem.data["completed_contracts"]`.
2. Consequence: after escaping contract 2 and returning to the Den, the screen
   shows `Contract #2  Active` (`Screen.Ledger.Contract.Status.InProgress`)
   even though `record_contract_complete` wrote `completed_contracts["2"]`. The
   screen *understates* completion; it does not invent it. The status is
   correct only for a contract that really is in progress.

**Verdict: PASS** for the stated criterion (no fabricated completion, no
fabricated per-contract sweep), with the two accuracy defects above.

---

## 5. Tutorial screen — PASS on substance, count claim is wrong

- Table inventory: `ST_Tutorial` 75 rows, `ST_Tutorial_Infographics` 22,
  `ST_Tutorial_ThievesDen` 12 → **109 rows / 106 distinct keys** (the 3 shared
  keys are `Tut_Info_Ammo_Refills`, `Tut_Info_Zipwire`, `Tut_Info_Stashes`, and
  their bodies **differ** between the two tables — they are not duplicates).
  Classification reproduces the suite's own live counts exactly:
  objectives 25, controls 16, infographics 33, story 23, den 12 = **109 cards**.
  The docstring/report say "106 authored entries"; 106 is the distinct-key
  count, not what the screen renders. See **F4**.
- 5 categories, fixed order, empty categories skipped; a category only appears
  if its authored group is non-empty.
- `<img id="…"/>`: 12 distinct ids occur in the three tables
  (`Crouch, EquipMap, Interact, Jump, LeanLeft, LeanRight, Look, Move, Primary,
  Secondary, Tool1, Tool2`); all 14 `DT_RichTextInputs` rows load and all 12
  ids map through `InputActions.port_id_for_ia` to actions that have keyboard
  bindings in the generated `input_actions.json`. `EquipMap → map_toggle →
  Tab` renders `[TAB]` (C1.22). The rebind is live: C3's check rebinds pad
  interact X→Y and the authored tutorial body re-renders as `[Y] to pick`.
  Rebinds reach `InputMap` through `InputRebinder.apply → InputActions.
  apply_to_input_map`, and `InputGlyphs.key_name_for_action` reads
  `InputMap.action_get_events` at call time.
- `<Danger>` → `#BD1F1F`: the renderer reads
  `DT_RichTextStyleSheet_FTUE.json` (not the fallback table; C1.24 pins
  `style_fallbacks()==0`), and the infographics page contains
  `[color=#bd1f1f]` (C1.23). Note the *authored* lowercase hex; the uppercase
  in the brief is the same colour.
- Only tags present in the three tables are `Highlight`, `Danger`, `img`; no
  nested tags, no tag spans a newline, no unbalanced tag — so the non-DOTALL
  regex in `tutorial_text.gd:152–165` loses nothing today.
- `video_count()==15`: reads `res://data/generated/videos.json`, which really
  has 15 entries (13 FTUE tutorial .ogv + IntroCutscene + SplashScreen). The
  suite message says "15 FTUE movies"; 2 of the 15 are not FTUE, a wording
  nit only. All 6 inferred `VIDEO_ROW_IDS` ids exist and all 6 rows have
  prose, so no `[ VIDEO ]` marker renders (0, as reported).
- No invented prose: `_append_table` copies `rows[key]` verbatim for every row
  of all three tables, and `_entry_card` renders only that body (plus the
  table-qualified key id). There is no hardcoded tutorial sentence. The C1.30
  assertion only samples the last opened category (the Den's 12 rows, 12/0) —
  weak coverage, but the construction makes invented prose impossible without
  a code change.

**Verdict: PASS** on the authored-tables/no-invented-prose requirement, with the
count correction and one content-selection defect (F4).

---

## 6. Test weakening / deletion — PASS for C1, one cross-suite gate defect

`git diff 8ce9a86 --stat -- game/tests/`:

```
 game/tests/run_tests.gd | 27 +++++++++++++++++++++++++++
 1 file changed, 27 insertions(+)
```

The **entire** test diff since the branch point is +27/−0 lines in
`run_tests.gd`: four new suite registrations (106–109) that require **exit 0
AND** the suite's own summary marker. **No assertion was changed, relaxed or
deleted**; no existing expectation moved. The four new files
(`test_w9p3_screens.gd` 197 lines, `test_focus_walk.gd` 238,
`test_w9p3_map_toast.gd` 265, `test_w9p3_localization.gd` 154) are additions,
not replacements.

Weak spots in the new C1 test (coverage, not dishonesty — nothing here passes
without the authored data):

- C1.15 is effectively unconditional: `_refresh_stats` always adds the authored
  `Screen.Label.Stats` header, so "progression shows an authored section
  header" cannot fail while that row exists.
- C1.30 checks only the last category (Den, 12 bodies), not all 109 cards.

**Cross-suite gate defect (F5, owner C3):** `test_focus_walk.gd:203` calls
`settings.is_ancestor_of(owner_ctl)` after `close_settings()` has freed the
node. The C3 run prints
`SCRIPT ERROR: Cannot call method 'is_ancestor_of' on a previously freed instance`
and **aborts `_modal_close_check`**, skipping the three `C3.modal …`
assertions, yet still prints `FOCUS_WALK_SUMMARY: fails=0 checks=64` and exits
0. `run_tests.gd` suite 107 gates only on exit 0 + the marker, so a SCRIPT
ERROR that kills a function is invisible to the gate. This does not weaken a
C1 assertion, but it means the wave's "107 green" claim overstates that suite.

**Verdict: PASS** for C1 (no weakened/deleted C1 assertion); F5 is reported as
a wave-level gate-integrity defect.

---

## 7. Screen API honesty — PASS (one blocking wiring defect outside the API, F1)

APIs (static, verified present):

| screen | open | query | close | debug |
|---|---|---|---|---|
| PostMatchUI | `open_result(won, score, info, xp_awarded=-1)` | `is_open()` | `close()` → `closed` signal | `debug_controls()` |
| ProgressionUI | `open_progression()` | `is_open()` | `close()` → `closed` | `debug_controls()` |
| TutorialUI | `open_tutorial()`, `open_category(name)`, `category_key_for_label()` | `is_open()`, `video_count()` | `close()` → `closed` | `debug_controls()` |

- `open_*` sets `visible=true` and installs/focuses the ring; `close()` early
  returns when already closed, releases focus if it is inside the panel, sets
  `visible=false` and emits `closed`. `debug_controls()` returns
  `FocusNav.focusable_controls(panel)`, i.e. the same list the ring is built
  from.
- Focus ring: `ring_is_complete` is asserted for all three in C1 (C1.11,
  C1.18, C1.29) and again in C3's 10-screen walk (post_match 2 controls,
  progression 2, tutorial 6; bottom-neighbour chain returns to the first
  control and visits every control). Ring links are rebuilt after each refresh.
- ESC / pad-B: each screen implements `_unhandled_input` with
  `event.is_action_pressed("ui_cancel")` plus an explicit `KEY_ESCAPE` check.
  `project.godot` defines no `ui_cancel` override, so Godot's built-in
  `ui_cancel` applies (Escape + joypad button 1 = B). This is **code-verified,
  not runtime-probed**: no suite presses ESC or B against these three screens.
  Also note the HUD's `_process` pause poll (`Input.is_action_just_pressed(
  "pause")`, `process_mode = ALWAYS`, `hud.gd:732,2774`) will additionally
  toggle pause on Escape in the same frame because the C1 screens do not stamp
  `_pause_consumed_frame`. That is the **same pre-existing pattern** as
  `ledger_ui` / `wardrobe_ui` / `contract_table_ui` / `settings_ui`, not a C1
  regression, but it means "ESC closes" is true and "ESC does nothing else" is
  not.
- Preload-in-test safety: none of the four C1 scripts references an autoload
  identifier (`GameState.`, `SaveSystem.`, `AudioManager.`, …); they use
  `_autoload("Name")` → `get_node_or_null`. The two locres-only strings go
  through `Loc` via `UIStringsScript.t`. `tutorial_text.gd` uses the global
  classes `InputActions`/`InputGlyphs` (both `class_name`, not autoloads).
  Transitive caveat: `post_match_ui.gd`/`progression_ui.gd` preload
  `unlock_catalog.gd`, which *does* reference `SaveSystem`/`GameState` as
  identifiers in `player_level`, `completed_contract_orders`, `conditions_met`,
  `is_purchased`, `price_text` — none of which the C1 screens call; the suites
  construct the catalog successfully.

**Verdict: PASS** for API honesty. The blocking finding below is in the
**wiring**, not in these APIs.

---

## Findings

| id | severity | where | finding | evidence | owner / fix |
|---|---|---|---|---|---|
| **F1** | **BLOCKING** | `ledger_ui.gd:574–584` + `progression_ui.gd:2` | The progression screen is added as a `CanvasLayer` (default **layer 1**) as a child of the Ledger, whose own `CanvasLayer` is **layer 20** (`mission_controller.gd:1490–1495`). Both panels are 1100×660 centred, so the Ledger's full-rect dim (`Color(0.008,0.012,0.025,0.86)`) plus its opaque panel cover the progression screen completely; the Ledger's dim also eats the mouse. Keyboard focus is stolen by the invisible panel. The screen is therefore **not usable in game from its only entry point**, despite the comment "Open the authored progression screen above the ledger". | Godot 4.7 `CanvasLayer.layer` default `1`, "lower values are drawn behind higher values" (docs.godotengine.org/en/stable/classes/class_canvaslayer.html); no `layer =` assignment anywhere in `progression_ui.gd`; the only non-definition `open_progression` caller is `ledger_ui.gd:578`; C1/C3 instantiate the screens standalone so no test covers the Ledger → progression path | C1: set `ui.layer = 25` (or add the UI to the Ledger's parent layer and hide the Ledger panel), then add a test that opens the Ledger and asserts the progress layer/index and that the Ledger panel is not an occluder. Re-capture. |
| **F2** | risk (non-blocking) | `post_match_ui.gd:2`, HUD integration | PostMatchUI is also a default `CanvasLayer` **layer 1**, the same index as the HUD (`hud.gd` creates a `CanvasLayer` with default 1). Godot documents same-index CanvasLayer draw order as **non-deterministic**; the engine's tie-break is the sibling index (`viewport_set_canvas_stacking(layer, get_index())`), which is not something to rely on across two different parents. | CanvasLayer docs: "If multiple CanvasLayers have the same layer index … which CanvasLayer is drawn in front is non-deterministic." The Credits modal already sets `layer = 30` for the same reason (`main_menu.gd:744`). | C1: give the post-match screen an explicit layer above the HUD (e.g. 30). |
| **F3** | accuracy (non-blocking) | `progression_ui.gd:12–14, 449–459`; `p3-report.md:91–97` | The stated BLOCKED reason is half false: `SaveSystem` really has no `has_completed_contract(order)`, but `completed_contracts` **is** readable publicly (`save_system.gd:168` `var data`; `unlock_catalog.gd:264` `completed_contract_orders()`), so the report's "`completed_contracts` is not public" and "the day this 6-line accessor exists … with no UI change" overstate the gap. The screen does not fabricate completion (it fails closed), but it prints `Active` for a contract the save records as completed. | `grep -rn "has_completed_contract" game/src` → only the guarded C1 call sites; `grep -rn "completed_contract_orders" game/src` → `unlock_catalog.gd:264` (reads `SaveSystem.data["completed_contracts"]`) | C1/P1: either use `completed_contract_orders()` for the current order's status (and keep the 1..16 sweep gated on the missing API), or correct the report to "no per-order API; a raw-dict reader exists". |
| **F4** | content (non-blocking) | `tutorial_ui.gd:301–309`; report/docstring "106" | The three tables hold **109 rows / 106 distinct keys** and the screen renders **all 109 cards** (the 3 shared keys are emitted twice, with different authored prose). The wave's own facts doc (`p3-facts-screens.md:27`) says the old `ST_Tutorial` `Tut_Info_Zipwire` / `Tut_Info_Stashes` are unused by the shipped FTUE flow — the browser shows them anyway, so at least those 2 cards are rows the shipped tutorial never uses. | Python count over the three tables: 75+22+12 = 109, 106 unique; suite's live category counts 25+16+33+23+12 = 109; the 3 pairs' bodies differ | C1: state 109 cards / 106 keys in the docstring and report; prefer the `ST_Tutorial_Infographics` row for the 3 shared keys (or mark the unused ones), exactly as the facts doc recommends. |
| **F5** | gate integrity (non-blocking for C1) | `test_focus_walk.gd:203` | The C3 suite throws `SCRIPT ERROR: Cannot call method 'is_ancestor_of' on a previously freed instance`, aborts `_modal_close_check`, and silently skips the 3 `C3.modal …` assertions while still printing `fails=0 checks=64` and exiting 0. `run_tests` 107 gates on exit 0 + marker, so this is invisible. | log line `SCRIPT ERROR … at: _modal_close_check (res://tests/test_focus_walk.gd:203)`; the PASS list goes … tutorial 6/6 → rebind, with no `C3.modal` lines; expected count would be 67 | C3: capture the instance id / null-check before `is_ancestor_of`, and make the suite fail on a SCRIPT ERROR (or gate on a minimum check count). |
| **F6** | hygiene (non-blocking) | `game/src/ui/*.gd` | The 7 new scripts (`focus_nav`, `map_boundaries`, `post_match_ui`, `progression_ui`, `tutorial_text`, `tutorial_ui`, `ui_toast`) have **no `.gd.uid`** files, while every tracked script in `game/src/ui` has one (15 uid / 22 gd). A `--import` or editor open will create 7 untracked files. | `ls game/src/ui/*.uid` → 15; `ls game/src/ui/*.gd` → 22; `git ls-files` shows uids are tracked for existing scripts | C1: let the import generate and commit them, or note the intentional omission. |
| **F7** | cosmetic (non-blocking) | `post_match_ui.gd:458`; `post_match_ui.gd:344`; `progression_ui.gd:312` | The multiplier literal `"x"` has an authored row (`PostMatch.Haul.CountMarker = "x"`); `"(£) "` is an un-authored symbol. No visible divergence; no invented prose. | table dump; `grep` for `(£)` across all tables = 0 rows | optional: use `st_text("ST_PostMatch","PostMatch.Haul.CountMarker")` for the marker. |
| **F8** | semantic (non-blocking) | `tutorial_ui.gd:334–336` | The "story" tab is titled with the authored `ST_MapTool.CluePage.Clues` (`Clues`) but contains 23 mixed rows (Fey intro, contract title/description/outro/journal, quest item names, clue rows). Authored copy, port grouping; the label is authored but describes only part of the group. | classification list; `ST_MapTool.CluePage.Clues = "Clues"` | optional: label it as a port grouping or split it. |
| **F9** | verification gap | ESC/B | ESC/B close is code-verified through `ui_cancel`, but **no runtime probe** presses ESC or B against these three screens. The HUD pause poll additionally fires on ESC (pre-existing pattern). | `grep -rn "ui_cancel" game/tests` = 0 hits for these screens | C3: add an input-event test (Escape + `JOY_BUTTON_B`) per screen. |
| **F10** | minor | `hud.gd:2091–2096`, `ledger_ui.gd:309–318` | The XP and Stats buttons are not guarded against a second press: two presses stack two PostMatchUI/ProgressionUI instances. No test. | code read; no `disabled = true` / open guard | optional: disable while open. |
| **F11** | disclosure | `post_match_ui.gd:36` | `XP earned` is port-only and not localized (no locres source). Consistent with the report's disclosure; a non-English locale will show English here. | 0 hits in tables and locres | document as a port string (already done). |

### Blocking summary

**F1 blocks C1 integration as delivered.** The tutorial screen is reachable from
the startscreen (its CanvasLayer sits above a layer-0 Control) and the
post-match screen is reachable from the HUD's result panel (it shares layer 1
with the HUD — see F2 for the caveat); the progression screen is only reachable
from the Ledger and is drawn *behind* it by a deterministic layer inversion
(1 < 20) with a same-size opaque panel on top. Every suite passes because each
one instantiates the screen directly under `/root`, where there is no Ledger
layer to lose to. Nothing else in items 1–7 blocks integration; F2 should be
fixed in the same pass because it is the same class of defect and the fix is one
line.

### What I could not verify (stated as NOT VERIFIED, not accepted)

- No visual capture of any of the three screens was taken (headless only).
  F1 is proven from the engine's documented CanvasLayer ordering and the code,
  not from a screenshot.
- ESC / pad-B close was not exercised at runtime (F9).
- The full 298-expression localisation table and the C2/C3/C4 lanes are out of
  this audit's scope; I only audited the four C1 scripts and the C1 wiring.

### Bottom line

The three screens are real, built from the authored tables, and their copy and
XP arithmetic hold up under an independent re-check. The wave should not be
declared green until **F1** is fixed and a capture of the Ledger → Stats →
progression path exists; **F3**, **F4** and **F5** should be corrected in the
same wave because they are inaccurate claims in the report/gate, not merely
cosmetic.

---

## Re-audit (3a9aa34)

Scope: the C1 findings only (F1, F2, F3, F4, F6, F7, F9). F5 is C3-owned and
F8/F10/F11 were non-blocking notes; none of those four was re-audited here, and
this section makes no claim about them. Tree: `rem/w9-p3` @
`3a9aa34aeeffc057a36c2eb16f7f365ea9b4f7eb` (committed; only `build/qa/w9/audit-c4.md`
is dirty in the working tree).

| finding | verdict | evidence |
|---|---|---|
| **F1** progression layer | **FIXED** | `ledger_ui.gd:578` sets `ui.layer = 25` before `add_child(ui)` (comment cites "audit-c1 F1"). Probe 2 drives the real `ledger_ui._open_progression()`: `LEDGER layer=20 progression_layer=25 above=true open=true visible=true in_tree=true`. 25 > the Ledger's 20, so the Ledger's dim/panel can no longer cover it; the higher layer also takes GUI input first. |
| **F2** post-match layer | **FIXED** | `hud.gd:2376` sets `ui.layer = 25` before `add_child(ui)` (comment cites "audit-c1 F2"). Probe 2 drives the real `hud._open_post_match_xp()` after `show_result()`: `HUD hud_layer=1 post_match_layer=25 above=true open=true visible=true in_tree=true`. |
| **F3** completion API | **FIXED** | `_has_completion_api()` now returns true when `SaveSystem.data` is a Dictionary and `completed_contracts` is a Dictionary; `_contract_completed()` reads `data["completed_contracts"]` (falling back to `has_completed_contract` when it exists). Probe 1 seeds `completed_contracts = {"2": …, "5": …}` in memory only and opens the real screen: the label set contains `Contract #2` → `Completed` and `Contract #5` → `Completed`; `contract2=true contract5=true contract6=false statuses=Completed,Completed` — order 5 can only come from the 1..16 sweep, order 6 is absent (no fabrication), and no `Active` row remains. On-disk save verified unchanged (`completed_contracts: {}`). |
| **F4** tutorial duplicates | **FIXED** | `tutorial_ui._append_table()` skips an `ST_Tutorial` key when `ST_Tutorial_Infographics` has it (lines 301–315), i.e. `Tut_Info_Ammo_Refills`, `Tut_Info_Stashes`, `Tut_Info_Zipwire`. Live suite counts: objectives 25 + controls 16 + infographics **30** + story 23 + den 12 = **106**. Independent count: `cards: 106 distinct: 106 dups: []`. |
| **F6** `.gd.uid` | **FIXED** | `git show --stat HEAD` filtered for `.uid` lists 11: the 7 UI scripts (`focus_nav`, `map_boundaries`, `post_match_ui`, `progression_ui`, `tutorial_text`, `tutorial_ui`, `ui_toast`) + the 4 tests (`test_focus_walk`, `test_w9p3_localization`, `test_w9p3_map_toast`, `test_w9p3_screens`). |
| **F7** multiplier prefix | **FIXED** | `post_match_ui.gd:458` now reads `"value": "×" + _mult_text(mult)` (U+00D7), not the literal `"x"`. |
| **F9** ESC/B close | **FIXED** (branch) | The suite gains `C1.12a ui_cancel closes the post-match screen`, `C1.18a … progression`, `C1.29a … tutorial`, and all three PASS; total moved 39 → **42**. Note the checks inject an `InputEventAction("ui_cancel")` into `_unhandled_input`, which is the same close branch a physical Escape/B reaches (`project.godot` still has no `ui_cancel` override); they do not synthesise a key/joypad event. |

### Suites re-run on the committed tree

```
flock /tmp/opencode/tat2-godot.lock -c 'timeout 900 tools/godot --headless --path game --script res://tests/test_w9p3_screens.gd'
→ exit 0, W9P3_SCREENS_SUMMARY: fails=0 checks=42 (42 PASS lines)

flock /tmp/opencode/tat2-godot.lock -c 'timeout 900 tools/godot --headless --path game --script res://tests/test_t05_ui_contract.gd'
→ exit 0, T05_SUMMARY: fails=0 checks=56 (56 PASS lines)

flock /tmp/opencode/tat2-godot.lock -c 'timeout 900 tools/godot --headless --path game --script res://tests/test_w7v_ui_acceptance.gd'
→ exit 0, W7V_SUMMARY: fails=0 checks=49 (extra check, not requested)
```

No `SCRIPT ERROR`/`FAIL` in any of the three logs; only the pre-existing
exit-time ObjectDB/resource warnings on T05/W7V.

### Probe evidence (read-only, no repo writes)

Both probes live under `/tmp/opencode/w9p3/`, are run with
`tools/godot --headless --path game --script <absolute path>`, and only touch
in-memory state:

- `probe_c1_reaudit.gd` — seeds `SaveSystem.data["completed_contracts"]` (no
  `write_save`), opens `progression_ui.gd`, prints its labels/statuses and the
  `20 vs 25` layer pair. `PROBE_RESULT: fails=0`; the on-disk save still holds
  `completed_contracts: {}`.
- `probe_c1_reaudit2.gd` — drives the **real** entry points
  (`ledger_ui._open_progression()`, `hud.show_result()` +
  `hud._open_post_match_xp()`) and prints the resulting CanvasLayers:
  `LEDGER layer=20 progression_layer=25 above=true …` and
  `HUD hud_layer=1 post_match_layer=25 above=true …`.

Residual (non-blocking, unchanged from the first audit): physical Escape/pad-B
routing is still not exercised end-to-end (the new checks inject `ui_cancel`),
and the HUD's Escape pause poll remains the pre-existing pattern. No capture of
the Ledger → Stats → progression path exists yet; the layer probe proves the
ordering but not the pixels.

### Updated verdict

**AUDIT: PASS** for the C1 findings on `3a9aa34`. Every listed finding is
**FIXED** with code + runtime evidence, the blocking F1 is gone, and the three
UI suites re-run on the committed tree are green (42/0, 56/0, 49/0). The
earlier non-blocking notes F8/F10/F11 remain as cosmetic/optional items; F5
(C3 gate integrity) was not re-audited in this pass.

