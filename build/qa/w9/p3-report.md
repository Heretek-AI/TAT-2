# W9-P3 — UI completeness (report)

Phase lead: W9-P3. Worktree `/home/john/Projects/TAT-2-rem-w9-p3`, branch
`rem/w9-p3`, base `8ce9a86` (W9-P2 merged). **Nothing pushed, merged or
rebased.** Every Godot invocation ran under `flock /tmp/opencode/tat2-godot.lock`
and was run serially; no Vulkan capture was needed for any claim in this report
(every number is a headless measurement or a source/extract quote); no producer,
`make normalize` or `make audit-refresh-stamps` was run — the data tree stayed
read-only for this phase.

## 0. Headline numbers — read this first

| requirement | before (`8ce9a86`) | after | verdict |
|---|---|---|---|
| visible UI strings routed through the Loc pipeline | **26 / 151 = 17.2 %** | **306 / 306 = 100 %** | **MET** |
| authored-mappable rows routed | **26 / 51 = 51.0 %** | **195 / 195 = 100 %** | **MET** |
| authored (table/locres) share of visible strings | 51 / 151 = 33.8 % | 195 / 306 = **63.7 %** | improved; the rest is port-only copy |
| port-only copy (no authored row, explicitly labelled) | 100 | 111 (routed + labelled) | — |
| gamepad focus | 0 `grab_focus` / 0 `focus_neighbor` in `game/src/ui/**` | every menu ring-linked; **58 controls**, 10 menus, no dead end | **MET** |
| post-match/XP / progression / tutorial screens | absent | present from the authored tables | **MET** |
| TAB map authored boundaries | 13 actors extracted, 0 consumed | consumer + contract; **0 emitted today** | **BLOCKED-ON-INTEGRATOR-REGENERATION** |
| authored loot toast | bare `Label3D` font 28 | authored `Toasts.MajorLootTaken` toast; HUD suppresses the label | **PARTIAL** (label creation is a P2 file, see §C4) |

The string audit is a committed, reproducible tool
(`build/qa/w9/p3_string_audit.py`). It counts one row per visible string
expression, including the HUD feedback emitted from `mission_controller` /
`loot_container` / `clue_item` and every `UIStrings`/`Loc` helper call:

```bash
python3 build/qa/w9/p3_string_audit.py --rev 8ce9a86            # before
python3 build/qa/w9/p3_string_audit.py --same-files-as 8ce9a86  # after, old file set
python3 build/qa/w9/p3_string_audit.py                          # after, all files
```

```
before: UI_STRINGS total=151 routed=26 authored=51 routed_authored=26 invented=100
        COVERAGE routed/total=0.1722   COVERAGE authored_routed/authored=0.5098
after : UI_STRINGS total=306 routed=306 authored=195 routed_authored=195 invented=111
        COVERAGE routed/total=1.0000   COVERAGE authored_routed/authored=1.0000
        KINDS _loc=5 _loc_upper=5 glyph_prompt=1 loc=124 loc_template=4
              st_template=9 st_text=83 st_upper=75
```

Read honestly: **111 of 306 visible expressions (36.3 %) are port-only copy**
with no authored counterpart — the HUD map legend/footer, the lockpick minigame
legend, loading percentage, mobile-touch labels, and a handful of fallbacks.
They are routed through the same pipeline (so they are keyed and
future-translatable) and every one carries a `## PORT COPY (no authored row)`
comment. **The translatable share is 195 / 306 = 63.7 %**; the independent
investigation lane (`build/qa/w9/p3-facts-strings.md`) counted 210 invented
sites in the pre-wave tree, so the remainder is genuinely port-invented, not a
table the wave failed to find.

## 1. The three missing screens (C1)

### 1.1 Screen inventory with authored citations

| screen | file | authored source | content |
|---|---|---|---|
| post-match rack-up + XP | `game/src/ui/post_match_ui.gd` (650 lines) | `ST_PostMatch` 71 rows, `ST_Screens.Screen.PostMatch.*`, `Screen.Label.TotalAssets/TotalHaul`, locres `Level {CurrentLevel}` / `LEVEL UP!`, `unlocks.json` 68 rows | status (Escaped/Caught), contract outcome, haul/earned/lost/cash/assets, `XP.Breakdown` 5 authored weights, measured XP, level + XP bar, `LEVEL UP!` + authored Black Market unlocks |
| progression | `game/src/ui/progression_ui.gd` (578) | `ST_Screens.Screen.Label.Stats`, `Screen.Contract.Number`, `Screen.Ledger.Contract.Status.*`, `Screen.Stat.*`, `Screen.PostMatch.Unlocks`, `ST_PostMatch.Contract.<n>.*`, `ST_PostMatch.XP.MaxLevel`, `unlocks.json` | level/XP, live stats (StealthKOs/CluesFound/KeysFound/TotalAssets), current contract + authored status, next authored unlock ladder |
| tutorial / FTUE | `game/src/ui/tutorial_ui.gd` (448) + `tutorial_text.gd` (188) | `ST_Tutorial` 75, `ST_Tutorial_Infographics` 22, `ST_Tutorial_ThievesDen` 12, `DT_RichTextInputs` 14, `DT_RichTextStyleSheet_FTUE` 5, `videos.json` 15 | **106 authored entries** in 5 categories (3 superseded ST_Tutorial duplicates skipped in favour of the FTUE infographic rows), live input glyphs, authored rich-text colours, `Play Tutorial` entry + FTUE boot |
| result panel (existing) | `hud.gd` | `ST_PostMatch.PostMatch.Status.Escaped/Caught` (T05) | unchanged; the invented GHOST/BRAWLER rating words are gone from UI source and pinned by C1.4. `SHADOW` was **not** removed as a token: 96 identifiers still contain it in `game/src/` (`SHADOW_CASTING_SETTING`, `TAT2_SHADOW_HEROES`, `shadow_runner`), none of them a result rating (W10-A correction) |

Entry points: the HUD result panel gets an authored `XP.BREAKDOWN` button
(measured award = save XP delta since HUD creation, so the screen never
recomputes a banked number); the ledger level block gets an authored `Stats`
button that opens progression; the startscreen gets the authored
`PlayTutorial` entry (RE-L-02), whose `START TUTORIAL` boots the authored FTUE
map set (`GameData.get_ftue_sublevels()` → `active_map_id = "ftue"`).

### 1.2 Evidence

`tools/godot --headless --path game --script res://tests/test_w9p3_screens.gd`
→ **`W9P3_SCREENS_SUMMARY: fails=0 checks=42`**. It asserts the authored
status vocabulary, the five authored XP breakdown rows, the measured `+120`,
the level line, `Continue`/`Back`/`Play Tutorial` rows, `CAUGHT`, the
`[TAB]` FTUE glyph, the `#BD1F1F` Danger colour, 14 rich-text input ids, the
15-movie index, all 5 categories, and that **every rendered tutorial body
traces to an authored row (12 hit / 0 miss)** in the sampled page.

### 1.3 Port labels introduced (5, all marked in code)

`XP earned` (no total row in `ST_PostMatch`), `Objectives`, `Infographics`,
`Thieves' Den` (no category-title rows; the authored tables carry only
sentences), `[ VIDEO ]` (structural marker; **0 rendered today**). The
progression screen title reuses the authored `Screen.Ledger.Journal`
("Journal", the same KF07 card title); the tutorial title reuses
`Settings.Gameplay.ShowTutorials` ("Show Tutorials").

### 1.4 Data halves (reported, never hardcoded)

- **Per-contract completion** — `SaveSystem.data` is a public var and carries
  `completed_contracts` (the same dictionary the ledger and `unlock_catalog`
  already read), so the authored 1..16 sweep is **live** without a new API.
  `has_completed_contract(order)` remains a P1 convenience, not a blocker
  (audit-c1 F3 corrected the earlier "not public" claim).
- **Player stats — BLOCKED-ON P1/T01.** No save counters and no generated
  `DT_PlayerStats` (`game_data.gd:394` expects a table that `parse_tables.py`
  does not emit). `GuardKOs`/`LocksPicked`/`Stashes` are omitted, never zeroed;
  the screen shows only the live counters it has (`GameState.takedowns`,
  `clue_facts`, `stolen_keys`, currency).
- **Tutorial video binding — BLOCKED-ON T01.** `videos.json` is really read
  (15 ids) but the ST-row → `.ogv` binding lives in a UE blueprint not in the
  extract; the 6 inferred bindings only decide the marker and all 6 rows have
  authored prose, so **0 markers render**. Playback stays blocked (no
  `VideoStreamPlayer` use yet).

## 2. Localisation (C2)

### 2.1 Per-file after (sites routed / total)

| file | routed / total |
|---|---|
| `hud.gd` | 69 / 69 |
| `mission_controller.gd` (UI feedback only) | 36 / 36 |
| `mission_prep_ui.gd` | 34 / 34 |
| `wardrobe_ui.gd` | 28 / 28 |
| `ledger_ui.gd` | 24 / 24 |
| `contract_table_ui.gd` / `post_match_ui.gd` | 21 / 21, 21 / 21 |
| `mobile_touch_ui.gd` / `settings_ui.gd` | 16 / 16, 15 / 15 |
| `main_menu.gd` | 14 / 14 |
| `progression_ui.gd` | 9 / 9 |
| `loot_container.gd` / `clue_item.gd` | 9 / 9, 3 / 3 |
| `tutorial_ui.gd` / `loading_screen.gd` | 5 / 5, 2 / 2 |

`settings_ui.gd`'s private `_label()` used to read `ST_Settings.json` directly
and bypass Loc; it now calls `UIStrings.st_text("ST_Settings", key, fallback)`,
which routes all 24 table-only settings rows in one change (RE-L-16). Two authored keys are genuinely missing from the producer
(`Settings.Volume.AmbienceVolume`, `Settings.Volume.UIVolume`) and stay English;
`Settings.GraphicsQuality.DesktopQuality` was a port key-name error (the
authored row is `Settings.GraphicsQuality`), and `Settings.Header` is also
missing (the settings title falls back). Disclosed, not hidden.

### 2.2 Deleted invented copy (not wrapped)

- `loading_screen.gd`: the five flavour status lines (`Preparing sublevels…`,
  `Unlocking the doors…`, `Raising the rooftops…`, `Lighting the lanterns…`,
  `Ready.`) are gone. The authored `BPUI_LoadingScreen` has one
  `ST_GeneralUI.Loading` line; the status label now prints real percentage
  progress (`%d%%`, no words).
- `contract_table_ui.gd`: the invented `MAP TABLE — CONTRACT SELECTOR` title is
  gone (the authored map table has no title).

### 2.3 Untranslated-key fallback proof

`Loc.t()` returns the **source string unchanged** for an unknown source, never
the GUID and never empty; `UIStrings.t`/`st_text` add the table row as the
source first. `tests/test_w9p3_localization.gd` (19 checks) asserts a
non-English locale renders authored text (German `Play`), an unknown source
round-trips, and the reverse map stays at the pre-W9 size:

```
TAT-2 Loc: 8 translations, reverse map 2946/3404 en.csv keys, locale=en
W9P3_LOC_SUMMARY: fails=0 checks=19
```

The reverse map construction, first-key-wins rule, ALL-CAPS normalisation and
`out == key` fallback are **byte-identical** to `8ce9a86` except the added
counters (`t_stats`/`reset_t_stats`) — the 120-row/i18n behaviour is untouched.

## 3. Gamepad focus + glyphs (C3)

New `game/src/ui/focus_nav.gd`: tree-order focus ring with wrap-around on all
four axes, `install_and_focus`, `remember`/`restore`, `release_if_inside`,
`ring_is_complete`. `art_nouveau_theme.gd` now draws a gold 2 px **focus**
stylebox (Godot only draws the theme's `focus` box; the port had no focus style
at all) and sets `focus_mode = ALL` on buttons, tabs and option buttons.

Evidence: `tools/godot --headless --path game --script res://tests/test_focus_walk.gd`
→ **`FOCUS_WALK_SUMMARY: fails=0 checks=67 screens=10`**. The walk follows each
control's bottom-neighbour chain, asserts it visits every control exactly once
and returns to the start; a missing neighbour, a hidden control or a 1-control
menu fails it.

| menu | focusable controls | ring | walk |
|---|---:|---|---|
| startscreen | 5 | complete | 5/5 |
| settings | 11 | complete | 11/11 |
| ledger | 3 | complete | 3/3 |
| wardrobe | 14 | complete | 14/14 |
| map table | 8 | complete | 8/8 |
| mission prep | 3 | complete | 3/3 |
| pause | 4 | complete | 4/4 |
| post-match | 2 | complete | 2/2 |
| progression | 2 | complete | 2/2 |
| tutorial | 6 | complete | 6/6 |
| **total** | **58** | — | — |

Modals: settings releases on close, the map-table confirm releases + re-rings +
restores the opener, the ledger's progression overlay restores, the HUD pause
releases on resume — no focus is trapped behind a hidden panel.

Glyphs: `InputGlyphs` now drives the HUD map/ping hint bar, crank prompt, pause
ESC badge, lockpick legend, map footer, ledger tabs, wardrobe thief switch, map
table difficulty/mode/action hints and mission prep ready/back. The rebind
assertion in the focus test prints `X → Y`, re-renders the authored FTUE text as
`[Y] to pick`, and restores the authored mapping exactly. `TAT2_UI_NO_STAGE`
is a headless test hook that skips only the startscreen/prep 3D SubViewports,
never a Control (unset in every shipped path).

## 4. TAB map + toast (C4)

### 4.1 Authored boundaries

`game/src/ui/map_boundaries.gd` consumes the producer's `map_boundaries` array:
13 `TATWorldMapBoundary` actors (Guildhall 5, OldManor 6, FTUE 1,
ThievesDenTest 1), their `MapLabel` (StringTable ref or locres GUID), `MapType`,
anchors (e.g. 315,621 → 1712,1679 of 2048), `MapRenderTextureHeightOffset`, and
the BoxComponent transform. Positions are the level producer's
`(x, z, y)·0.01`; `BoxExtent` is not serialized and the class default is 100 cm
(verified against the map extent: Guildhall's mesh pivots span 228 × 113 m and
boundary_0 is 100 cm × 117.5 = 235 m full). The HUD `TacticalMapDraw` uses the
**primary** box as the authored map extent and draws the secondaries as floor
rects with their authored labels and an active-floor highlight.

**Today the generated payloads carry 0 boundary rows** (verified: zero
`map_boundaries` hits in `game/data/generated/levels/**`). The producer contract
is `build/qa/w9/parse_tables-map-boundaries.patch` (`git apply --check` passes;
not applied, no producer run). `MapBoundaries.source_for_map()` and
`Hud.map_boundary_source()` report `fallback`; the fallback window is labelled
in the map draw (`FALLBACK BOUNDS - NO AUTHORED TATWorldMapBoundary`) and in
code/docs.

The invented 600 × 600 floor at y = −15 is now labelled **PORT INVENTED — NOT
AUTHORED** in `mission_controller._add_safety_floor()`. No authored
KillZ/KillZVolume exists in `extracted/json` or `extracted/raw`; the authored
behaviour is **UNKNOWN** (UE's un-serialized default is not evidence).

### 4.2 Loot toast

`game/src/ui/ui_toast.gd` implements the `BPUI_ToastWidget` pattern: a stacked
rounded smoke-style panel (labelled reconstruction of `M_UI_Smoke`, a UE
`MD_UI` material with CornerRadius/Power and no texture), an icon well using the
authored major-loot glyph (`T_Glyph_MajorLoot.png`; the exact
`S_LootItem_Artifact_Chalice` PaperSprite atlas is not decoded, counted as
`icon_fallback`), the authored text and `Show`/`EyeCatchingShow` as Tweens.
Text is `ST_Toasts.MajorLootTaken` = `{PlayerName} took the {MajorLootName}!`
with `GameState.player_display_name()` and the item's `display_name`. The HUD
subscribes to `GameState.carried_loot_changed`, fires only for a **major**-tier
pickup (not minor, not stash), and suppresses the port-invented world-space
`Label3D` from the UI side. The label's creation site (`game/src/interact/loot_item.gd`)
is a P2-owned file and was **not edited**; deleting it is listed as
BLOCKED-ON P2 for the integrator.

Evidence: `W9P3_MAP_TOAST_SUMMARY: fails=0 checks=37` (parser, labels, anchors,
floor selection, all-four-payload-empty, the authored template, a live toast,
the HUD integration — fallback reported, major pickup toasts, minor does not —
and the world-label suppression across a thief-vision toggle).

## 5. Gates on the merged tree

All runs serial under the lock, on this worktree, final tree unless noted.

| gate | result |
|---|---|
| `tools/check_scripts_compile.gd` | **175 checked, 0 broken** (base 164; +7 UI files, +4 tests) |
| `tests/run_tests.gd` | **`SUMMARY: fails=0`, 312 `^PASS`** (base 308 + suites 106–109). First run hit a pre-existing physics flake in suite 45 (`blocker_rise=0.415` vs 0.40 — 15 mm settle, not a UI change); the immediate rerun was `fails=0` |
| `tests/test_m2_player.gd` | **`M2_SUMMARY: fails=0`** |
| `tests/e2e/run_e2e_tests.gd -- --tier=1` | **`fails=0 passed=117 total=117`** |
| `tests/e2e/run_e2e_tests.gd` | **`fails=0 passed=278 total=278`** |
| `probe_door_walk` / `probe_viewmodel_truth` / `probe_niagara` | **DOORWALK PASS** / **VIEWMODEL_TRUTH PASS** / **NIAGARA_PROBE PASS** (3695 authored / 1048 active / 16 systems) |
| `probe_blackjack_race` / `probe_geometry_placement` | **BLACKJACK_PROBE PASS fails=0** / **GEOM_PROBE PASS checks=7 fails=0** |
| `test_t05_ui_contract` / `test_w7v_ui_acceptance` / `test_hud_gem_compass` | **56/56**, **49/49**, **11/11 PASS** (no expectation changed) |
| `test_w9p3_screens` / `test_focus_walk` / `test_w9p3_map_toast` / `test_w9p3_localization` | **42/0**, **67/0**, **37/0**, **19/0** |
| `make audit` | **AUDIT PASS** (baseline matches; `videos.json` rule removed) |
| `make gate-ratchet` | **GATE_RATCHET: PASS** |
| `make texture-cap-check` | **OK** (0 offenders) |
| `build/qa/test_perf_guard.sh` | **PERF_GUARD_TEST PASS checks=78 fails=0** |

One allowlist change: `tools/consumer_allowlist.json` drops the `videos.json`
`blocked_on_team` rule because `tutorial_ui.gd` now reads the file (video ids),
so the rule matched no unconsumed file and the audit correctly failed it as
stale. Playback remains blocked (no `VideoStreamPlayer`), recorded here.

## 6. Independent audits

One auditor per lane, each a separate agent that did not write the code, each
read-only apart from its own report. They re-ran the proofs themselves.

| lane | report | first verdict | outcome |
|---|---|---|---|
| C1 screens | `build/qa/w9/audit-c1.md` | **FAIL** | F1/F2 the progression/post-match CanvasLayers defaulted to layer 1 under the layer-20 ledger / the HUD → set to 25; F3 "completed_contracts is not public" was false → the 1..16 sweep now reads the public save dictionary; F4 the tutorial indexed 3 superseded duplicate rows → skipped (106 distinct cards); F5 (C3) the modal assertion crashed on a freed node; F6 missing `.gd.uid` → generated; F7 an `"x"` multiplier prefix → `×`; F9 ESC/B close untested → close assertions added. Re-ran: screens 42/0, T05 56/0, W7V 49/0 |
| C2 localisation | `build/qa/w9/audit-c2.md` | **FAIL** (evidence integrity, not behaviour) | the tool's prefix rule inflated the authored count by 11 rows → **strict exact/case rule now: 195 authored / 108 port copy**, not 205/93; the KINDS line was stale → regenerated; the universe missed 5 visible sites (`Touch Look`, rebind status, two `_set_hint` sites) → counted and the raw one wired; four mixed lines still carried raw English → wired. Loc proof independently reproduced (`Spielen`, unknown source verbatim, 2946/3404) |
| C3 focus/glyphs | `build/qa/w9/audit-c3.md` | **FAIL** | the modal check threw `is_ancestor_of` on a freed settings node and silently skipped 3 assertions → guarded, **67/0** and all three modal checks run; the HUD hint-bar keycaps were still hardcoded `TAB`/`MMB` → `InputGlyphs` + a `device_changed` re-render of the built-once labels (also the pause badge and map footer); rebind X→Y + FTUE `[Y]` reproduced twice with an exact mapping restore; no test weakened |
| C4 map/toast | `build/qa/w9/audit-c4.md` | **FAIL** | 13/13 actors, every position/extent, the producer patch and the fallback were reproduced exactly; **5d** thief vision re-showed the invented world label (`label.visible = on or is_quest_item`) → the HUD re-hides it on the vision toggle, proven by C4.34–36; the icon-fallback counter never fired for the HUD's empty `icon_res` → counted (C4.23 asserts ≥1); the growth guard swallowed the first major pickup after a stash → the baseline now follows the decrease (C4.33a); the sound constant/docstring cited the wrong toast row → corrected; `loot_item.gd` untouched (P2) |

After the fixes, each auditor re-ran the affected proofs on the committed tree
and all four updated their verdict to **AUDIT: PASS** (C1 `## Re-audit`, C2
`## Re-audit`, C3 `## Re-audit`, C4 `## Re-audit` + `## Re-audit 2`).
The four suites are 42/0 (C1), 19/0 (C2), 67/0 (C3) and 37/0 (C4). The remaining audit items are P2/T01/P1-owned files or port-copy wording:
the `loot_item.gd` label creation (P2), `thief_character.gd`'s bottom-right
keycaps (P2), the `DT_PlayerStats` producer (T01), and the unlocalised
`XP earned` port label (no authored row).

## 7. Open risks / blocked / deferred

1. **TAB map boundaries are not in the data**: the consumer and the producer
   patch are ready, but the map will keep showing the labelled fallback until
   the integrator applies the patch and regenerates (see §8).
2. **World-label removal is a P2 file**: the HUD suppresses the bare
   `loot_item.gd` Label3D at spawn, on node add, and after every thief-vision
   toggle (audit-c4 5d); deleting the label creation (4 lines) is BLOCKED-ON P2
   and cosmetic-only now.
3. **Player stats** are BLOCKED-ON P1/T01 (§1.4); the screen shows only real
   counters and never zeroes a missing one. Per-contract completion now reads
   the public save dictionary (no blocker).
4. **Port copy is 36.3 % of visible strings** and stays English (it has no
   authored row). It is routed and labelled so a TAT-2 string table can
   translate it later; do not read the 100 % routing as 100 % authored.
5. **Focus ring is a port reconstruction** of the CommonUI focus graph (the
   authored neighbour table is not extractable). It is a ring, not a spatial
   grid; the authored behaviour (pad traverses, visible focus) is reproduced.
6. **Suite 45 is a physics flake** on this host (15 mm step-rise settle); it was
   green on the rerun and is unrelated to UI. Watch it in the merged gate run.
7. **`video_count()==15` requires `game/data/generated/videos.json`**; a
   producer-less checkout shows 0 and the test fails closed (correct).
8. **English text changed where the authored row differs** — every such change
   is the authored value (e.g. `LOCK JAMMED!` now composes `LOCK` +
   `ST_Lockpicking` Jammed; `LEGEND`/`RETURN TO THIEF'S DEN` already authored).
   The C2 lane lists each; the auditor re-checks them.
9. **Mobile touch labels** are port-only (`WIRE`/`ASTRAL`/`SKILL`/`MASK`) and
   remain `loc()` port copy; the shipped game has no touch UI.

## 8. Integrator steps

1. **Cherry-pick the commit; do not squash.** The four lanes interleave in
   `hud.gd` / `ledger_ui.gd` / `main_menu.gd` (a lane-per-commit split would not
   compile alone), so the wave is **one coherent commit** whose message carries
   the per-lane red/green evidence; this report has the detail. Nothing was
   pushed, merged or rebased.
2. **Map boundaries (one producer change, at merged HEAD):** apply
   `build/qa/w9/parse_tables-map-boundaries.patch`, run `make normalize`, then
   `make audit-refresh-stamps REASON='parse_tables emits authored TATWorldMapBoundary rows'`.
   Re-run `probe_*`/`run_tests`/E2E; `MapBoundaries.source_for_map("guildhall")`
   must flip from `fallback` to `authored` (5 Guildhall rows; 13 total across
   the four maps). The HUD needs no further change.
3. **Force-add the evidence** (`build/qa/*.md`, `.tsv`, `.patch` are
   gitignored): `p3-report.md`, `audit-c1..c4.md`, `p3-facts-strings.md`,
   `p3-facts-screens.md`, `p3-strings-before.tsv`,
   `parse_tables-map-boundaries.patch`, `p3_string_audit.py`.
4. **P1/T01 follow-ups** (not P3 files): `SaveSystem.get_player_stat(id)` + a
   `DT_PlayerStats` producer; three missing `ST_Settings` keys
   (`Settings.Volume.AmbienceVolume`, `Settings.Volume.UIVolume`,
   `Settings.Header`). The `DesktopQuality` port key name is corrected to the
   authored `Settings.GraphicsQuality` row.
5. **P2 follow-up**: delete the `Label3D` creation in `loot_item.gd:209-214`
   (the HUD already suppresses it and the authored toast replaces it).
6. **Docs owed at integration (not P3-owned):** `docs/FIDELITY_GAPS.md` — the
   three screens now exist (with the BLOCKED data halves), the localisation
   coverage table, the focus model, the TAB-map fallback + producer contract,
   the toast; `docs/HANDOFF_NEXT_AGENT.md` — new HEAD, gate numbers, open list;
   `README.md` only if a user-facing command changed (none did).
7. **Re-run the complete gate set serially at merged HEAD** (the floors are
   §5: compile 175/0, run_tests 312/0, M2 12/0, E2E 278/278 + 117/117, five
   probes, `make audit`, `gate-ratchet`, `texture-cap-check`, perf guard 78/0).
   A silent drop is a regression; `docs/reports/logs/` re-stamping is P0's job.
8. **No capture is claimed.** Layout claims are structural (headless). If a
   pixel check is wanted, the three screens and the toast are the captures to
   take, one Godot at a time under the lock.
