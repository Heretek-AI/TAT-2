# Task 3 — Wardrobe KF03/KF04 rebuild cite ledger

Date (UTC): 2026-11-20. Scope: rebuild `game/src/ui/wardrobe_ui.gd` to
KF03/KF04 layout + content; this ledger is the per-row cite record.
Ground truth read first: Wave 0 ledger
`.omo/evidence/tat2-playtest-round2-fixes/task-0.md` (HEAD
`ca7e8ed307d7dc2b1d8459c2c2e2144bc50377d3` + round-1 worktree; wardrobe
symptom 3 UNPROVEN, needs per-fix live proof), F3 backlog row
(`.omo/waves/tat2-ground-truth/backlog.md`, cooked-found), prior
`task-6.log` (`.omo/evidence/tat2-playtest-ground-truth-fixes/`, 23 value
cites + 10 HARD_LIMIT rows, of which wardrobe rows 15–22 and HARD_LIMIT
5.1/5.2/5.7/5.8/5.9 govern this change).
Reads in scope: `wardrobe_ui.gd`, `DT_CharacterOutfitsMetadata.json`
(54 rows, re-enumerated this turn — see row 12),
`clean/KF03_00m07s_wardrobe_loadout.jpg`,
`clean/KF04_00m16s_wardrobe_vistara_diamond.jpg`, prior `task-6.log`.
Writes: ONLY `wardrobe_ui.gd` + this file. No art/paths invented; no
ledger/market code touched.
Scope note: the standing read-only agreement for `/home/john/Projects/TAT-2`
collides with this task's explicit deliverable (edits to `wardrobe_ui.gd` +
this ledger). Per memory rules the current instruction wins for exactly
these two files; every other file was read-only.

## 1. Switcher — portraits + LOCKED (KF03)

1. `WARDROBE` centered header kept (size 30, serif, `TEAL_ACCENT`) — prior
   task-6 row 15 CITE (KF03/KF04 §3 rows). Unchanged this turn.
2. Thief switcher rebuilt as Q/E-flanked portrait cards: `[< Q]` + Spider
   card (teal `style_teal_tab` active frame) + Chameleon card (dimmed,
   pink `LOCKED` overlay) + `[E >]`, name labels `The Spider` /
   `The Chameleon` below each card (`THIEF_LABELS`, pre-existing const) —
   KF03 structural CITE (selected-glow frame, dimmed second portrait, pink
   LOCKED text, Q left / E right, names under portraits — all verified
   on-screen). New: `_build_top_bar`, `_build_thief_card`.
3. Pink `LOCKED` overlay + expanded-row locks use local
   `LOCKED_PINK = Color(1.0, 0.38, 0.72)` — KF03/KF04 chroma CITE (pink
   LOCKED text on Chameleon card; pink padlocks on KF04 expanded row) +
   standing HARD_LIMIT 5.7 (no pink-lock theme token exists; scope bars
   theme edits — see §3). New const, inline cite.
4. Portrait frames are EMPTY (button with no icon/text) — KF03 structural
   CITE for the frame + standing HARD_LIMIT 5.1 (no cooked portrait
   texture path recovered in the task-6 probe; nothing substituted — see §3).
5. Clicking a portrait selects that thief; locked portrait keeps the hint
   `The Chameleon is locked. Finish a contract to earn this disguise.`
   (pre-existing string, SaveSystem `unlocked_thieves` /
   `chameleon_unlocked` / `completed_contracts` keys pre-date this change,
   no new gating invented) — KF03 behavior CITE (clickable portraits,
   locked Chameleon). New: `_on_portrait_pressed`, `_refresh_portraits`.
   Q/E keyboard cycling unchanged.

## 2. Loadout — lock badges + slot-3 expanded row (KF03/KF04)

6. Slots 1–4 stay numbered text buttons (`[N] name`, 120×38, teal tabs),
   each now with a grey `LOCKED` badge (`TEAL_MUTED`, size 11) shown only
   when `SaveSystem.unlocked_tools` lacks the id — KF03 CITE (numbered
   slots 1–4; grey locks on slots 1 and 4). Text buttons stand: no slot
   icon-art source recovered in scope. New: `_add_tool_slot`,
   `_slot_lock_lbls`, `_refresh_tool_ui` lock loop.
7. Hint `Select a loadout slot to equip or swap out tools` kept verbatim
   below the toolbar — KF03 verified on-screen text (task-6 row 17 CITE).
   Unchanged.
8. Slot-3-style expanded candidate row added under the slots: 4 tool cells
   (`[1] Zipwire / [2] Smoke Bomb / [3] Blackjack / [4] Slithersap`) with
   PINK `LOCKED` badges on locked entries; clicking a cell equips that
   tool (`_on_tool_selected`) and both rows highlight the active tool —
   KF04 structural CITE (4-tool row under the slots, pink locks, tooltip
   card beneath). Fairy/Slither-Sap names and meshes NOT added: standing
   HARD_LIMIT 5.8 (`TOOLS` const covers only the 4 verified-mesh tools;
   no fairy/sap mesh path verified — see §3). New: `expanded` row,
   `_cell_btns`, `_cell_lock_lbls`.
9. Bottom tooltip card (3D model viewport + name + desc) kept as the KF04
   bottom-card CITE (large framed card under the expanded row, name +
   two-line desc bottom-left). `Vistara Diamond` content not shown:
   standing HARD_LIMIT 5.8 (no diamond mesh path in the verified `TOOLS`
   const; pointing the tooltip at an unverified path is forbidden).
10. Zipwire desc kept KF-verbatim (`A spring-loaded grapple gun … along
    for the ride.`) — KF08/KF03 CITE (task-6 row 12). Unchanged.

## 3. Right rail — thumbnail portrait cards (KF03/KF04)

11. `HEAD` / `BODY` / `CALLING CARD` sections now show one framed card each
    (full-width button, min height 72, teal tab frame) instead of
    `OptionButton` dropdowns — KF03/KF04 structural CITE (one square
    thumbnail card per slot under each label). Clicking a card steps to
    the next outfit in that slot (`_cycle_outfit`); the desc label still
    shows all three DT descriptions. New: `_head_card`, `_body_card`,
    `_card_card`, `_on_*_card_pressed`, `_cycle_outfit`.
12. Card text is UE-derived content: DT `LocalizedString` outfit name +
    ` · Lv N` tag parsed from the DT `LocalizedString` description
    (`Level (\d+)`; base outfits show no tag). Re-enumerated this turn
    from `DT_CharacterOutfitsMetadata.json`: 54 rows — Spider 20 Head /
    3 Body / 5 CallingCard, Chameleon 18 Head / 3 Body / 5 CallingCard
    (e.g. Spider `Top Hat` Lv 5, `Tarantula` Lv 10, `Drake's Revenge`
    Lv 25; Chameleon `Sharp Dressed` Lv 20, `Top Hat and Monocle` Lv 22).
    New: `_outfit_level_tag`, `_update_outfit_cards`.
13. Cards carry NO thumbnail image (name + level text only) — KF
    structural CITE for the card + standing HARD_LIMIT 5.9 (DT
    `IconSprite` UE paths, e.g.
    `/Game/Art/UI/Icons/Rewards/Spider/…`, cite the content, but texture
    bytes were not extracted in scope — see §3). `style_teal_option` no
    longer used here; all rail styling still routes through existing teal
    tokens (design-system path intact, task-6 row 23 holds).
14. `CUSTOMIZATION` header, teal divider, pink hint label (`_hint_lbl`,
    pre-existing `Color(0.95, 0.55, 0.65)` — predates this change, left as
    is), `APPLY` button unchanged.

## 4. BACK placement (KF03/KF04)

15. `BACK [ESC]` moved out of the top bar into a bottom-right aligned bar
    (`_build_bottom_bar`) — KF03/KF04 CITE (BACK bottom-right on both
    frames). Closes task-6 row 22 MISMATCH.

## 5. Staging numbers

16. Preview turntable rig (warm key 1.15 + amber fill + cool rim, 9×9
    plane, cam 0,1.35,3.4 fov 40, drag-rotate + idle auto-yaw) and tool
    card rig (key 1.2, fill, cam 0,0.4,1.7 fov 38) UNCHANGED — KF03/KF04
    staging-INTENT cite (full-body Spider before the armoire, warm
    practical light; tool close-up in the tooltip card) + standing
    HARD_LIMIT 5.2 (exact rig numbers are port-authored: no UMG/light
    values exist in cooked JSON; F2/F3 Ghidra `BPUI` rect targets named
    but un-pursued — see §3). Cite comments added on both setup funcs.
17. Cooked identity values carried forward from task-6 (not re-probed;
    out of read scope): `BP_ThievesDen_Wardrobe_Contents` 83 exports
    (`BlueprintGeneratedClass` incl `SM_ThievesDen_Wardrobe_Mirror`),
    `SM_ThievesDen_Wardrobe` + `T_ThievesDen_Wardrobe_D/N/ORM`,
    `SM_ThievesDen_Wardrobe_Mirror`, `MI_ThievesDen_Wardrobe` + `_NoAO` +
    `MLI_ThievesDen_Wardrobe`, shell art `T_wardrobeBackgroundImage`,
    `T_loadoutEditable/Uneditable/Editing/EditingFrame`, `T_frameCorner`,
    `T_halfFrame` under `extracted/json/Art/UI/Shell/wardrobe/`.
18. New lock/level state reads ONLY pre-existing keys: SaveSystem
    `unlocked_tools` / `unlocked_thieves` / `chameleon_unlocked` /
    `completed_contracts`, DT `LocalizedString` names/descs. No new save
    keys, no ledger/market writes (ledger/market files untouched).

## 6. Standing HARD_LIMIT closes (unrecoverable in scope — never approximated)

- 5.1 Portrait art: frames stay empty (rows 2/4). Search evidence: task-6
  probe recovered no cooked portrait texture path for Spider/Chameleon
  wardrobe portraits or the journal portrait; this turn's read scope
  (wardrobe_ui.gd, DT table, KF frames, task-6.log) contains no new art
  source. STANDING.
- 5.2 Pixel geometry: no UMG rect/anchor/font metrics, no light-rig values
  in cooked JSON (rows 16–17 carry F3 identity only); Ghidra `BPUI` rect
  targets un-pursued. All layout numbers structural/port-authored.
  STANDING.
- 5.3 Lore/desc strings: full card bodies live only in KF pixels +
  transcripts; DT rows are related facts, not copy. Zipwire/Vistara
  tooltip verbatim displayed solely as labeled KF reference (row 10);
  data text binds only to `ST_*`/DT `LocalizedString` (row 12). STANDING.
- 5.7 Missing theme tokens: pink LOCKED/padlock, purchase-green, Active
  green have no `TEAL_*` constants; `LOCKED_PINK` local const (row 3) is
  the fallback until the design-system pass adds tokens (extension must
  come first, scope bars theme edits). The pre-existing pink hint label
  (row 14) is untouched. STANDING.
- 5.8 Fairy/slither-sap tools: mesh paths unverified; expanded row uses
  the 4 verified-mesh `TOOLS` entries only (rows 8–9). No paths invented.
  STANDING.
- 5.9 Outfit thumbnails: DT `IconSprite` UE paths cite content; texture
  bytes unresolved, so name + level-tag cards stand in (rows 11–13).
  STANDING.
- 5.4/5.5/5.6/5.10: ledger/market- or engine-scoped (assets-bar ornaments,
  ledger preview binds, black-market prices, F7/F9/F14) — NOT APPLICABLE
  to this wardrobe change; wardrobe carries no prices and adds no preview
  binds beyond the pre-existing verified-mesh path.

## 7. Verification (file-level + targeted check, no suite/GPU run per task)

- Re-read edited spans from disk this turn: const block, member block,
  `_build_ui` bottom-bar call, `_build_top_bar`, `_build_thief_card`,
  `_refresh_portraits`, `_on_portrait_pressed`, `_build_bottom_bar`,
  `_add_tool_slot`, toolbar + expanded row, load-hint adjacency, tool
  tooltip card, all three right-rail card blocks, `_refresh_tool_ui`,
  card-press handlers, `_cycle_outfit`, `_outfit_level_tag`,
  `_update_outfit_cards`, `_refresh_thief_ui`, both staging comments —
  every span carries an inline KF/UE cite or a standing HARD_LIMIT note.
- Orphan sweep: `grep` for `_thief_name_lbl/_thief_lock_lbl/__*_opt/
  _fill_option/_on_*_selected` → zero hits (all replaced); `THIEF_LABELS`
  reused for card titles (no dead code).
- Targeted parse check (own file only):
  `flatpak run org.godotengine.Godot --headless --check-only --script
  res://src/ui/wardrobe_ui.gd` → exactly 1 `SCRIPT ERROR`
  (`Identifier not found: GameState`, `_ready` line 98 — pre-existing
  autoload reference, untouched by this change). Parity: untouched
  `ledger_ui.gd` fails identically on its first autoload identifier
  (`AudioManager`). Zero NEW compile errors from this change.
- `make test` / live-GPU explicitly NOT run (orchestrator owns suites at
  settle; task-0 symptom 3 stays UNPROVEN pending live proof).
- Scope: `git status` delta expected = `wardrobe_ui.gd` + this ledger only.

Cite counts: 18 value rows (§1–§5 rows 1–18: 5 switcher + 5 loadout + 4
right-rail + 1 BACK + 3 staging/state) + 6 standing HARD_LIMIT closes
(§6: 5.1/5.2/5.3/5.7/5.8/5.9; 5.4/5.5/5.6/5.10 N/A) = 24 ledger entries.
Changed code spans: 15 (const, top bar, thief card, portraits refresh,
portrait press, bottom bar, slot helper, toolbar, expanded row, 3 rail
cards, tool-ui refresh, outfit cycle/tag/cards, thief-ui refresh), each
citing one of the 18 value rows.
