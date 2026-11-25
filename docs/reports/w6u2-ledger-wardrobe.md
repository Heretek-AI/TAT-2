# W6U2 — authored Ledger, Black Market and Wardrobe

Date: 2026-11-24
Worktree: `/tmp/opencode/tat2-w6u2-catalog` (cut from `f803c3b`)
Data: `XDG_DATA_HOME=/tmp/opencode/w6u2-data`, one Godot at a time, headless.

Scope: `tools/parse_unlocks.py`, new `game/src/ui/unlock_catalog.gd`,
`game/src/ui/ledger_ui.gd`, `game/src/ui/wardrobe_ui.gd`,
`game/src/core/save_system.gd` (catalog save-id migration + unlock accessors),
`game/tests/test_w6u2_catalog.gd`, plus the suite 60c / suite 8 expectations
that asserted the old hard-coded rows. No other file was edited.

## 1. What was wrong before

* `ledger_ui.gd` carried four hand-written arrays (`TOOLS`, `PERKS`,
  `SPIDER_COSMETICS`, `CHAMELEON_COSMETICS`) with 7 + 7 + 10 + 8 rows, 19 of
  them invented placeholder prices, and a player-visible **PRICE UNKNOWN**
  state for every row without a KF08-verified price. The authored table has
  68 rows and 55 authored prices; the port showed 4.
* The 68-row catalog already existed (`game/data/generated/gameplay/unlocks.json`,
  W5E) but had no consumer: no stable id, no condition text, no icon resolver.
* `wardrobe_ui.gd` built its own 4-tool list with port copy, showed tool names
  as button text, had an **APPLY** button that is not in KF03, and unlocked the
  Chameleon on *any* completed contract — contract 1 handed over a 10,000-unit
  disguise whose authored row is `Contract.Main.3`.
* `SaveSystem` persisted short UI ids (`bowler_hat`, `slithersap`, `fairy`) and
  seeded five tools + `bowler_hat` for a fresh profile, so the KF08 frame's
  locked fairies/sap and the unowned Chameleon rows could not be reproduced.

## 2. Producer — `tools/parse_unlocks.py`

Additive to the existing `tat2.unlocks/1` payload (the schema string is
unchanged so `tools/check_logic_data.py` keeps validating it):

| Field | Meaning |
|---|---|
| `save_id` | Stable id SaveSystem stores. Tools/perks keep the ids the port already persists (`zipwire` … `vistara_diamond`, `novice_difficulty` … `chameleon`); cosmetics use the authored outfit tag (`Outfit.Spider.Head.BowlerA`), which is also what the Wardrobe already saved for an equipped slot. |
| `save_category` | `tools` / `perks` / `cosmetics` — the SaveSystem list, distinct from the four display columns. |
| `icon.res` | Cooked texture object path → imported `res://assets/ue/Raw/...png` (drops the duplicated `T_X.T_X` package suffix). |
| `condition` | `text` derived from the structured `UnlockConditions` (the gate the game applies): `Unlocked at Level N.` / `Unlocked in Contract N.`; plus `requires_level`, `requires_contract`, and the authored description claim (`copy`, `copy_number`, `copy_agrees`). |
| `catalog` | `tat2.unlock_catalog/1`: the four columns with counts, the `blackjack` built-in, the save-id sets, icon counts. |

Fail-closed assertions (the producer now refuses to write on drift):

* 68 rows; column counts exactly 7 / 7 / 28 / 26; exactly 55 priced rows.
* 68 non-empty, unique `save_id`s; the tool and perk id sets are pinned to the
  SaveSystem ids, so renaming a tag without a migration fails here.
* Every row has an icon asset + `res` path; when `game/assets/ue/Raw` exists,
  all 68 PNGs must be on disk.
* Every gated row has derived condition text.

Measured output:

```
Parsed 68 unlockable entries -> game/data/generated/gameplay/unlocks.json
  content types: Cosmetic=54, Difficulty=3, Gear=7, Map=2, Thief=2
  shop columns: chameleon_cosmetics=26, guild_perks=7, spider_cosmetics=28, tools=7
  prices: 55 priced / 13 free, 0..750000
  catalog: 68 unique save ids, 68 icons (68 on disk), 5 condition-copy mismatches
```

### 2.1 The KF08 frame explains itself

KF08 shows exactly four prices (Bob 7,500 / Mustache 5,000 / Full Beard 7,500 /
Eyepatch 2,500) and a padlock on every other row. Those four are precisely the
Spider cosmetic rows whose structured level gate is ≤ 4 (4 / 3 / 4 / 2). So the
state model is: **check** = owned, **price** = gate met and purchasable,
**padlock** = level/contract gate unmet. At Level 4 with contracts 1–2 done the
catalog yields `purchased=12, locked=52, buy=4` — the frame, reproduced from
authored data.

### 2.2 Five authored contradictions, recorded not resolved

The data asset's description copy disagrees with its own structured gate on five
rows. The producer keeps both and the UI gates on the structured field:

| Row | Gate (used) | Copy (shown in the description) |
|---|---|---|
| `Difficulty.MasterThief` | Contract 5 | “Unlocked in Contract 8.” |
| `Tool.Type.MagicSlime` | Contract 7 | “Unlocked in Contract 9.” |
| `Outfit.Chameleon.Head.HairB` | Level 20 | “Unlocked at Level 16.” |
| `Outfit.Chameleon.Head.BowlerA.MustacheA` | Level 6 | “Unlocked at level 11.” |
| `Outfit.Chameleon.Head.MustacheA` | Level 11 | “Unlocked at level 7.” |

The level-gated cosmetic rows also carry the parent tag `Contract` (not
`Contract.Main.N`); that is not a gate, which is why their copy reads “Unlocked
at Level N.” and the producer ignores it.

## 3. `game/src/ui/unlock_catalog.gd`

Read-only view over the JSON, shared by the Ledger and the Wardrobe. It
validates schema, 68 rows, unique ids, the four column counts and a non-negative
price before it reports `is_available()`. A missing/corrupt file makes both
panels fail closed (a notice and no BUY path), never a silent fallback to
hand-written rows. Public surface: `entries`, `columns`, `entries_for_column`,
`entry(save_id)`, `built_in_tools`, `save_id_of`, `category_of`, `title_of`,
`description_of`, `price_of`, `icon_texture`, `condition_text`,
`requires_level/contract`, `conditions_met`, `is_purchased`, `state_of`
(`purchased` / `locked` / `buy`), `can_purchase`, `price_text`, `lock_reason`.

Free rows (price 0) whose gate is met count as owned, matching the shipped
frame (Zipwire, Smoke Bomb, Novice, Guildhall, the Spider defaults).

## 4. Ledger — KF07 and KF08

Journal (KF07): authored portrait (`T_portrait_spider/chameleon`) with the
square level badge, the handle under it, `Level N` over a slanted canvas XP bar
with the `94/500` tally, and the existing contract carousel with the status word
above each card and the italic-serif title.

Black Market (KF08):

* gold-bordered `YOUR TOTAL ASSETS: (£) 26,275` banner (thousands separated by
  `GameState.format_thousands`);
* left preview card: `✓ PURCHASED` / `LOCKED` state, the authored reward icon,
  title, description, the authored gate sentence and the price/BUY row;
* four published tables — TOOLS and GUILD PERKS under the preview, SPIDER and
  CHAMELEON COSMETICS as scrollable columns on the right — each with the
  centred caps header and the `(£)` column mark;
* row state is an authored check mark (`T_CheckMark`), a pink padlock
  (`T_Icon_Locked`) or the authored price;
* BUY calls `SaveSystem.purchase_by_save_id(category, save_id, price)`; the
  handler re-checks `conditions_met` and `state == buy`, so a locked row cannot
  be bought even if the signal is invoked directly. Insufficient funds leaves
  the balance untouched and reports have/need.
* `PRICE UNKNOWN` no longer exists anywhere in the file.

## 5. Wardrobe — KF03 / KF04

* True three-column layout: loadout + tool card (392 px min) | 3D thief stage
  (stretch 1.45) | Head/Body/Calling Card panel (stretch 0.95). **APPLY is
  gone**; BACK [ESC] bottom-right is the only action, as in KF03.
* Four slots from the authored tools: 1 Zipwire (signature, grey padlock),
  2 Smoke Bomb, 3 empty, 4 Vistara Diamond (signature, grey padlock). The hint
  “Select a loadout slot to equip or swap out tools” is unchanged; selecting a
  signature slot shows the shipped notice “Signature Tools cannot be swapped
  out”.
* Selecting a swappable slot reveals the KF04 candidate row with the four
  remaining Spider tools (Smoke Bomb, Pickpocket Fairy, Insult Fairy, Slither
  Sap), pink padlocks on the three unowned ones. Equipping swaps with the other
  swappable slot so a loadout never duplicates a tool; a locked candidate is
  never equipped.
* Tool names, descriptions, icons, gate text and 3D meshes all come from the
  catalog; every one of the seven tools has an authored gear mesh for the
  3D preview (the preview camera auto-frames the loaded model).
* Outfit cards (Head / Body / Calling Card) now show the catalog's authored
  reward icon next to the DT display name and level tag.
* The Chameleon gate is `SaveSystem.is_thief_unlocked`: the authored
  `Thief.Chameleon` perk, **Contract 3**, or a legacy explicit flag — not “any
  completed contract”. The locked hint names the price and gate.

## 6. Save migration (`game/src/core/save_system.gd`)

One-shot, flag-guarded (`unlock_ids_migrated` / `unlock_ids_schema`):

* tools: `slithersap` → `slither_sap`, `fairy` → `pickpocket_fairy`;
* cosmetics: the old ledger ids → authored tags (`bowler_hat` → both
  `Outfit.Spider.Head.BowlerA` and `Outfit.Chameleon.Head.BowlerA`, and so on
  for the other shared hats); a migration never removes a cosmetic, so a shared
  short id is granted on both thieves;
* equipped loadout: a short `head`/`body`/`calling_card` becomes that thief's
  authored tag, and legacy slot tool ids are rewritten;
* unknown ids (a newer build's, a hand-edited one) are copied through, order is
  preserved and duplicates collapse;
* fresh defaults now match the shipped profile: `blackjack` + Zipwire + Smoke
  Bomb, the four starter perks, the three Spider defaults and the Spider Bowler
  Hat. Contracts, XP, personal quest and settings are untouched.

`purchase_item`/`purchase_by_save_id` validate the category before deducting and
no longer treat an empty list as an unknown category, so buying into a
legitimately empty cosmetic list works.

## 7. Evidence (all measured in this worktree)

| Gate | Command | Result |
|---|---|---|
| compile | `tools/godot --headless --path game --script $PWD/tools/check_scripts_compile.gd` | 103 checked, **0 broken** (+`unlock_catalog.gd`, +`test_w6u2_catalog.gd`) |
| focused | `… --script res://tests/test_w6u2_catalog.gd` | **W6U2_SUMMARY: fails=0**, 61 PASS |
| suite | `… --script res://tests/run_tests.gd` | **SUMMARY: fails=0**, 262 PASS |
| M2 | `… --script res://tests/test_m2_player.gd` | **M2_SUMMARY: fails=0**, 11 PASS |
| E2E t1 | `… run_e2e_tests.gd -- --tier=1` | fails=0 passed=115 total=115 |
| E2E t2 | `… --tier=2` | fails=0 passed=110 total=110 |
| E2E t3 | `… --tier=3` | fails=0 passed=25 total=25 |
| E2E t4 | `… --tier=4` | fails=0 passed=14 total=14 |
| E2E sum | one tier at a time, serial | **264/264** |
| `T1-16-A` | 5 shell UIs teal | `wardrobe_ui.gd=true, ledger_ui.gd=true` |
| `T2-16-D` | 720p modal fit | 13 gated, no panel outside 1280×720 |
| `T4-02` | Thieves' Den journey | PASS unchanged (teal ledger/wardrobe, den + map table) |

Focused-test coverage: 68 rows; 7/7/28/26 columns; 55 priced; 68 unique save
ids; 68/68 icons load in-engine; tool/perk id sets equal to SaveSystem's;
KF08 anchors; the four Level-4 prices (and only those four) purchasable; owned
rows ✓; gated rows padlocked; purchase by save id (26,275 → 18,775); insufficient
funds; a locked row refused under a direct BUY call; the 5 copy/gate
contradictions pinned; save-id/condition-text re-derivation from the tag (drift
guard); ledger banner/level/XP/portrait/tables/states; wardrobe three-column,
no APPLY, authored slot icons, signature padlocks, 4-tool candidate row, 3D
preview, swap, locked-candidate refusal, Chameleon gate and the owned-Chameleon
swap to Glamour; legacy-save migration, idempotence and unknown-id preservation.

Suite 60c was updated because it asserted the removed behaviour (`PRICE
UNKNOWN`, Dictionary selection, `£ 7500` without a separator); it now pins the
authored states at an explicit Level-4/£26,275 profile and restores
`SaveSystem.data` afterwards. Suite 8 gained the wardrobe structure assertion
(three columns, 4 authored slots, no APPLY). No test was weakened: the old
assertions described a placeholder UI that no longer exists.

## 8. Remaining limits

1. **KF08 preview is 2D.** The shipped left card renders a 3D tool model; the
   port shows the authored reward icon (the Wardrobe owns the 3D tool preview).
   A third live SubViewport in the Ledger was not added.
2. **Slot art style.** KF03/KF04 draw monochrome silhouette icons; the port uses
   the authored coloured reward icons rather than adding a tint pass.
3. **Outfit thumbnails.** Head/Body/Card cards use the catalog's reward art.
   DT rows that are not among the 68 catalog rows fall back to a name-only card.
4. **Chameleon 3D body.** The Wardrobe figure still composes the Nisha
   body/head meshes for both thieves (pre-existing; the Cotter body bind is a
   separate job).
5. **No screen capture.** The panel geometry is asserted structurally, not by a
   PNG comparison; no Xvfb/GPU slot was taken in this wave.
6. **`make audit` is not green in this worktree.** The producer baseline is a
   shared integration artifact: `gen:gameplay/unlocks.json` legitimately changed
   and needs `make audit-refresh-stamps` at integration. The same run also
   reports two unrelated drifts (`parse_tables`, `parse_gameplay` outputs) and a
   missing `vgmstream` version, none of which this wave touched.
7. `game/data/expansion/personal_spider.json` shows as deleted in this worktree
   because `game/data` is a symlink to the shared checkout; it is not part of
   this change and is not committed.

## 9. Data notes

`unlocks.json` is generated and git-ignored: only `tools/parse_unlocks.py` and
the GDScript consumer are in the commit. Regenerate with
`python3 tools/parse_unlocks.py` (or `make normalize`); the producer is
deterministic against the shipped asset.
