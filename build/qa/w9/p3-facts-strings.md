# W9-P3 — Visible UI string inventory (before)

- Repo: `/home/john/Projects/TAT-2` @ `8ce9a86` (read-only checkout). **Line numbers refer to this tree**; the writable W9 worktree may carry other lanes' edits.
- Worktree for outputs: `/home/john/Projects/TAT-2-rem-w9-p3`
- Date: 2026-11-25
- Machine-readable inventory: `build/qa/w9/p3-strings-before.tsv` (columns: `file`, `line`, `literal`, `kind`, `routed`, `table`, `key`)

## 1. Scope and counting rule

Files audited (the exact scope given to this lane):

- `game/src/ui/hud.gd`
- `game/src/ui/main_menu.gd`
- `game/src/ui/settings_ui.gd`
- `game/src/ui/ledger_ui.gd`
- `game/src/ui/wardrobe_ui.gd`
- `game/src/ui/contract_table_ui.gd`
- `game/src/ui/mission_prep_ui.gd`
- `game/src/ui/loading_screen.gd`
- `game/src/ui/mobile_touch_ui.gd`
- `game/src/ui/review_mode.gd`
- `game/src/ui/art_nouveau_theme.gd` — 0 literal strings (theme/sink only)
- `game/src/missions/mission_controller.gd`
- `game/src/interact/loot_container.gd`
- `game/src/interact/loot_item.gd`
- `game/src/interact/clue_item.gd`
- `game/src/interact/escape_gate.gd` — 0 visible strings

A row is one **assignment site** where a string literal is assigned to, or passed as, visible text.
`routed` means:

- `yes` — the displayed value goes through the Loc pipeline (`UIStrings.st_text/st_upper`, or `_loc`/`_loc_upper` -> `/root/Loc.t`).
- `table` — `settings_ui.gd`'s private `_label()` reads `ST_Settings.json` directly and uppercases the value. Authored, but **not** Loc-routed and not translated.
- `no` — the literal (or a hardcoded fallback) reaches the Control without Loc.

A row is **authored-mappable** when a whole-string counterpart exists in (a) a generated StringTable value, (b) `localization/sources.json`, or (c) a gameplay JSON text field (`title*`, `description*`, `intro*`, `outro*`, `objective_text`, `display_name`, `prompt`, `text`, `label`, `briefing`, `location`, `quest_item`).
Case-only (`PLAY` vs `Play`) and placeholder-only (`Contract #%d` vs `Contract #{number}`) matches are counted, with the match type recorded below.
Component-only matches (e.g. `[Q] JOURNAL` contains `Journal`, `Host Co-op` is a prefix of `Host Co-op (Friends Only)`) are noted but **not** counted as authored-mappable, because the whole visible string has no authored row.

Counted rows require at least two consecutive ASCII letters after removing `%...`, `{...}` and `<...>`. Pure numeric/currency/symbol glue is therefore excluded (examples: `%d`, `%d%%`, `(£) %d`, `∞`, `↺`, `✓`, `❧`, `  (%s)`, `%s   £ %d`).
`< Q` / `E >` (single-letter input glyph labels) and empty strings are also excluded. They are listed in §9.

Arrays: one row per literal when the elements have different counterparts (Ping labels, mobile buttons, fallback contracts); one row for compact arrays whose elements share one treatment (compass directions, desktop quality labels, review toggles).

## 2. Reproduction commands

```bash
# counted assignment rows (355) and distinct literals (317)
wc -l build/qa/w9/p3-strings-before.tsv          # 356 = header + 355 rows
cut -f3 build/qa/w9/p3-strings-before.tsv | tail -n +2 | sort -u | wc -l   # 317

# already routed through Loc (35)
awk -F'\t' 'NR>1 && $5=="yes"' build/qa/w9/p3-strings-before.tsv | wc -l
# settings table-only, no Loc (24)
awk -F'\t' 'NR>1 && $5=="table"' build/qa/w9/p3-strings-before.tsv | wc -l
# unwired literals (296)
awk -F'\t' 'NR>1 && $5=="no"' build/qa/w9/p3-strings-before.tsv | wc -l
# unwired but authored row exists (86)
awk -F'\t' 'NR>1 && $5=="no" && $6!=""' build/qa/w9/p3-strings-before.tsv | wc -l
# unwired and invented (210)
awk -F'\t' 'NR>1 && $5=="no" && $6==""' build/qa/w9/p3-strings-before.tsv | wc -l

# per-file split
awk -F'\t' 'NR>1{print $1"\t"$5}' build/qa/w9/p3-strings-before.tsv | sort | uniq -c

# helper audit
grep -n 'ui_strings.gd\|UIStrings\|func _loc' game/src/ui/hud.gd game/src/ui/main_menu.gd game/src/ui/mission_prep_ui.gd
grep -n 'func _label\|ST_SETTINGS_PATH' game/src/ui/settings_ui.gd

# source spot checks (assignment sites, not counted rows)
grep -cE '\.text[[:space:]]*=' game/src/ui/hud.gd game/src/ui/ledger_ui.gd game/src/ui/wardrobe_ui.gd
grep -nE '\.text[[:space:]]*=' game/src/ui/hud.gd | grep -E '1397|1410|1872|1917|1922|1932|1940|2040|2057|2062|2065|2067|2115'
```

Run the TSV/awk commands from `/home/john/Projects/TAT-2-rem-w9-p3`; run the source greps from `/home/john/Projects/TAT-2`. The TSV is the source of truth for every number below; the same commands were used to derive them.

## 3. Helper audit — what each file already imports

| File | Loc helper / import | Preloaded `ui_strings.gd`? | Loc-routed today |
|---|---|---|---|
| `hud.gd` | `const UIStringsScript := preload("res://src/ui/ui_strings.gd")` line 22; `_loc()` line 2749 -> `/root/Loc.t`; `_loc_upper()` line 2756 | **yes** | yes (UIStrings rows + `_loc_upper` pause labels) |
| `main_menu.gd` | `const UIStringsScript := preload("res://src/ui/ui_strings.gd")` line 12; `_loc_upper()` line 578 -> `/root/Loc.t` (no `_loc`) | **yes** | yes (4 menu buttons) |
| `settings_ui.gd` | **no** UIStrings/Loc wrapper. Private `_label(key, fallback)` line 115 reads `ST_Settings.json` directly; `_loc_node()` line 665 is only used for the language list and `set_locale` | **no** | **no** — 24 table-only labels; 3 keys are missing and fall back to literals |
| `ledger_ui.gd` | none | **no** | no |
| `wardrobe_ui.gd` | none | **no** | no |
| `contract_table_ui.gd` | none | **no** | no |
| `mission_prep_ui.gd` | `const UIStringsScript: GDScript = preload("res://src/ui/ui_strings.gd")` line 48; `_loc()` line 1522 -> `UIStrings.t`; `_loc_fmt()` line 1526 | **yes** | yes (16 rows) |
| `loading_screen.gd` | none | **no** | no |
| `mobile_touch_ui.gd` | none | **no** | no |
| `review_mode.gd` | none | **no** | no (dev-only tool) |
| `art_nouveau_theme.gd` | none; the theme only renders caller-supplied text | **no** | n/a — 0 literals |
| `mission_controller.gd` | none | **no** | no — emits literals to HUD/GameState |
| `loot_container.gd` | none | **no** | no — one toast reuses authored `loot_settings.json` prompts |
| `loot_item.gd` | none | **no** | no — prompt delegates to `loot_inventory.gd` (outside scope) |
| `clue_item.gd` | none | **no** | no |
| `escape_gate.gd` | none | **no** | n/a — 0 visible strings (Label3D removed) |

The Loc autoload is `game/src/core/localization.gd` (`/root/Loc`). `UIStrings` (`game/src/ui/ui_strings.gd`) reads a table row and then calls `Loc.t`; `Loc.t` reverse-maps the English source string to a GUID and only normalises all-caps labels for lookup (`PLAY` -> `Play`).

## 4. Totals

- **Counted assignment sites: 355**
- **Distinct literal strings: 317**
- **(a) Authored-mappable: 145 (40.8%)** — 35 already Loc-routed + 24 `ST_Settings` table-only + 86 authored but unwired
- **(b) Invented, no authored counterpart: 210 (59.2%)**
- **(c) Already routed through Loc: 35 (9.9%)**
- `ST_Settings` table-only (authored, bypasses Loc): **24** (6.8%)
- Unwired raw literals: **296 (83.4%)** = 86 authored-unwired + 210 invented

At the distinct-string level (317 strings): authored-mappable **120**, invented **197**, Loc-routed **34**.

**Ceiling with existing authored rows only:** wiring all 86 authored-unwired literals and converting the 24 table-only settings rows to `UIStrings`/Loc gives `35 + 86 + 24 = 145 / 355 = 40.8%`. To reach the 90% DoD, **at least 175 of the 210 invented literals** need an authored row (or an explicit TAT-2/port string table routed through Loc). Wrapping invented strings in `Loc.t` alone will not translate them: `Loc.t` passes unknown source strings through unchanged.

Excluding the developer-only review overlay and FPS overlay (20 rows): player-facing rows **335**; Loc-routed **35 (10.4%)**; authored **143 (42.7%)**; invented **192 (57.3%)**.

### Per-file split

| File | Rows | Loc `yes` | `table` | Unwired | Authored | Invented |
|---|---:|---:|---:|---:|---:|---:|
| `game/src/ui/hud.gd` | 66 | 15 | 0 | 51 | 31 | 35 |
| `game/src/ui/main_menu.gd` | 12 | 4 | 0 | 8 | 8 | 4 |
| `game/src/ui/settings_ui.gd` | 49 | 0 | 24 | 25 | 26 | 23 |
| `game/src/ui/ledger_ui.gd` | 42 | 0 | 0 | 42 | 12 | 30 |
| `game/src/ui/wardrobe_ui.gd` | 30 | 0 | 0 | 30 | 11 | 19 |
| `game/src/ui/contract_table_ui.gd` | 24 | 0 | 0 | 24 | 2 | 22 |
| `game/src/ui/mission_prep_ui.gd` | 42 | 16 | 0 | 26 | 31 | 11 |
| `game/src/ui/loading_screen.gd` | 6 | 0 | 0 | 6 | 1 | 5 |
| `game/src/ui/mobile_touch_ui.gd` | 17 | 0 | 0 | 17 | 4 | 13 |
| `game/src/ui/review_mode.gd` | 19 | 0 | 0 | 19 | 2 | 17 |
| `game/src/ui/art_nouveau_theme.gd` | 0 | 0 | 0 | 0 | 0 | 0 |
| `game/src/missions/mission_controller.gd` | 35 | 0 | 0 | 35 | 17 | 18 |
| `game/src/interact/loot_container.gd` | 9 | 0 | 0 | 9 | 0 | 9 |
| `game/src/interact/loot_item.gd` | 1 | 0 | 0 | 1 | 0 | 1 |
| `game/src/interact/clue_item.gd` | 3 | 0 | 0 | 3 | 0 | 3 |
| `game/src/interact/escape_gate.gd` | 0 | 0 | 0 | 0 | 0 | 0 |

## 5. Top 40 highest-value unwired literals

Ranked by player-facing exposure and by whether a shipped authored row is already available. `Authored` = exact/case/placeholder whole-string counterpart.

| # | Area | Site | Literal | Authored counterpart | Why it matters |
|---:|---|---|---|---|---|
| 1 | HUD / objectives | `game/src/ui/hud.gd:1805` | `Esteemed Colleague -` | none | Letter salutation; shipped briefings start with it but no standalone row. |
| 2 | HUD / objectives | `game/src/ui/hud.gd:2017` | `Mission: %s [%d/%d]\n  (£) %d` | none | Objective header; no authored wrapper. |
| 3 | HUD / downed | `game/src/ui/hud.gd:2129` | `DOWNED — %ds` | none | Downed countdown. |
| 4 | HUD / clue toast | `game/src/ui/hud.gd:2136` | `CLUE — %s: %s` | none | Clue toast wrapper. |
| 5 | HUD / objectives | `game/src/ui/hud.gd:2661` | `Reach Escape Gate` | none | Objective complete status. |
| 6 | HUD / endgame | `game/src/ui/hud.gd:2682` | `THE MAGIC DOOR IS OPEN` | none | Endgame banner; ST_Toasts uses different wording. |
| 7 | HUD / map | `game/src/ui/hud.gd:1649` | `● YOU    ◆ OBJECTIVE    • LOOT    ▲ GUARD    ◎ WAYPOINT PING` | none | Map legend. |
| 8 | HUD / map | `game/src/ui/hud.gd:1636` | `TACTICAL MAP` | none | Map title. |
| 9 | HUD / map | `game/src/ui/hud.gd:3345` | `WAYPOINT` | none | Player-placed map ping label. |
| 10 | Main menu | `game/src/ui/main_menu.gd:707` | `Thick As Thieves — OtherSide Entertainment / Megabit` | none | Composite credits subtitle; only the pieces are authored. |
| 11 | Main menu | `game/src/ui/main_menu.gd:747` | `CLOSE` | `ST_Interactables` `PromptClose` = `Close` | Credits close; 'Close' authored PromptClose. |
| 12 | Map table | `game/src/ui/contract_table_ui.gd:442` | `Join Mission with these settings?\nDifficulty: %s\nMode: %s` | `ST_ThievesDen` `CityMap.ConfirmJoinLobby` = `Join Mission with these settings? Difficulty: {difficulty} Mode: {mode` | Authored CityMap.ConfirmJoinLobby exists (CRLF/placeholder variant). |
| 13 | Map table | `game/src/ui/contract_table_ui.gd:141` | `MAP TABLE — CONTRACT SELECTOR` | none | Map Table title; assembled. |
| 14 | Map table | `game/src/ui/contract_table_ui.gd:206` | `Difficulty:` | `ST_ThievesDen` `CityMap.DifficultyHeader` = `Difficulty:` | Authored CityMap.DifficultyHeader. |
| 15 | Map table | `game/src/ui/contract_table_ui.gd:211` | `Novice (1)` | none | Authored difficulty + port index suffix. |
| 16 | Map table | `game/src/ui/contract_table_ui.gd:222` | `Host Co-op` | none | Prefix of ST_ListenServers HostGamePrivate/Public rows. |
| 17 | Map table | `game/src/ui/contract_table_ui.gd:234` | `Join Co-op` | none | No authored row. |
| 18 | Map table | `game/src/ui/contract_table_ui.gd:252` | `FREE PLAY: GUILDHALL CLEANOUT [G]` | none | Port-authored free-play entry. |
| 19 | Map table | `game/src/ui/contract_table_ui.gd:258` | `DEPLOY CONTRACT` | none | Deploy button; not authored. |
| 20 | Map table | `game/src/ui/contract_table_ui.gd:328` | `Target: %s\nLocation: %s\n\n%s` | none | Target/Location labels are port copy. |
| 21 | Ledger | `game/src/ui/ledger_ui.gd:195` | `[Q] JOURNAL` | none | 'Journal' authored Screen.Ledger.Journal; key prefix unwired. |
| 22 | Ledger | `game/src/ui/ledger_ui.gd:201` | `BLACK MARKET [E]` | none | 'Black Market' authored; key prefix unwired. |
| 23 | Ledger | `game/src/ui/ledger_ui.gd:210` | `BACK [ESC]` | none | 'Back' authored Screen.Back; key prefix unwired. |
| 24 | Ledger | `game/src/ui/ledger_ui.gd:613` | `Completed` | `ST_Screens` `Screen.Ledger.Contract.Status.Complete` = `Completed` | Authored Screen.Ledger.Contract.Status.Complete. |
| 25 | Ledger | `game/src/ui/ledger_ui.gd:632` | `Contract #%d` | `ST_Screens` `Screen.Contract.Number` = `Contract #{number}` | Authored Screen.Contract.Number uses {number}. |
| 26 | Ledger | `game/src/ui/ledger_ui.gd:734` | `YOUR TOTAL ASSETS: (£) %s` | none | Contains authored 'Your Total Assets'; banner assembled. |
| 27 | Ledger | `game/src/ui/ledger_ui.gd:468` | `BUY` | none | Buy button; no authored row. |
| 28 | Ledger | `game/src/ui/ledger_ui.gd:909` | `✓ PURCHASED` | none | 'Purchased' authored Availability.Purchased; glyph added. |
| 29 | Ledger | `game/src/ui/ledger_ui.gd:972` | `Insufficient funds (have (£) %s, need £ %s)` | none | Authored alternative Purchase.NotEnoughMoney. |
| 30 | Wardrobe | `game/src/ui/wardrobe_ui.gd:358` | `WARDROBE` | `ST_ThievesDen` `Wardrobe.Header` = `Wardrobe` | Authored Wardrobe.Header. |
| 31 | Wardrobe | `game/src/ui/wardrobe_ui.gd:501` | `BACK [ESC]` | none | 'Back' authored Screen.Back; key prefix unwired. |
| 32 | Wardrobe | `game/src/ui/wardrobe_ui.gd:636` | `Edit Loadout` | `ST_ThievesDen` `Wardrobe.Loadout` = `Edit Loadout` | Authored Wardrobe.Loadout. |
| 33 | Wardrobe | `game/src/ui/wardrobe_ui.gd:664` | `Select a loadout slot to equip or swap out tools` | `ST_ThievesDen` `Wardrobe.SelectLoadout` = `Select a loadout slot to equip or swap out tools` | Authored Wardrobe.SelectLoadout. |
| 34 | Wardrobe | `game/src/ui/wardrobe_ui.gd:728` | `WARDROBE — DRAG TO ROTATE` | none | Preview header; assembled. |
| 35 | Wardrobe | `game/src/ui/wardrobe_ui.gd:765` | `CUSTOMIZATION` | none | Customization header; not authored. |
| 36 | Prep | `game/src/ui/mission_prep_ui.gd:1374` | `Vault Heist` | `ST_Screens` `Screen.MissionLobby.VaultQuestTitle` = `Vault Heist` | Same line also sets `Item Collection Heist` and `Cleanout Heist`, both authored in ST_Screens. |
| 37 | Prep | `game/src/ui/mission_prep_ui.gd:1378` | `\nTime Limit: %d minutes` | `ST_Screens` `Screen.MissionLobby.TimeLimit` = `Time Limit: {matchDurationInMinutes} minutes` | Authored Screen.MissionLobby.TimeLimit uses {matchDurationInMinutes}. |
| 38 | Settings | `game/src/ui/settings_ui.gd:531` | `Ambience Volume` | none | ST_Settings key missing; hardcoded fallback displayed. |
| 39 | Settings | `game/src/ui/settings_ui.gd:572` | `RESET DEFAULTS` | `ST_Settings` `Settings.Changes.Revert` = `Revert Changes` (table-only, no Loc) | Table value is 'Revert Changes'; bypasses Loc. |
| 40 | Settings | `game/src/ui/settings_ui.gd:882` | `[ PRESS ANY KEY ]` | none | Component 'Press Any Key' authored; brackets invented. |

**Next 10 (also worth wiring):** contract-table `264 CLOSE [ESC]`, `336 Intel:`; ledger `914 LOCKED`, `734 YOUR TOTAL ASSETS`; wardrobe `1043 Signature Tools cannot be swapped out`; prep `1459 Free play...`; settings `581 APPLY & BACK`, `640 Language`, `762 GAMEPAD`; HUD `1665` map footer.
## 6. Dynamic / format strings and how to convert them

The pause menu and the post-match/result panel have **no high-value unwired literals**: their labels already go through `_loc_upper`/`UIStrings` (only the pause-footer difficulty words `Novice`/`Thief`/`Master Thief` are bare but authored). The top-40 therefore concentrates on the HUD, map table, ledger, wardrobe, prep and settings, which is where the DoD gap is.

Authored templates in the shipped tables use `{0}`, `{PlayerName}`, `{MajorLootName}`, `{MatchDurationInMinutes}`, `{number}`, `{mode}`, `{difficulty}`. The port already has the right pattern in `hud.gd:2062` and `mission_prep_ui.gd:1446/1481`.

| Site | Format literal | Conversion |
|---|---|---|
| `hud.gd:2013/2603/2607` | `(£) %d` | Keep numeric formatting; the currency symbol is a Control decoration, not copy. Route any label word separately. |
| `hud.gd:2605` | `(£) %d / £ %d` | Numeric only; keep. |
| `hud.gd:2017` | `Mission: %s [%d/%d]\n  (£) %d` | Move the `Mission: {0} [{1}/{2}]` wrapper to a port/objective table; substitute with `.replace("{0}", title)` etc. |
| `hud.gd:2632` | `Mission: %s[%s/%s]` | Same objective wrapper; use a `{0}`/`{1}`/`{2}` template. |
| `hud.gd:2654` | `Mission: %s [%d/%d]%s\n%s` | One template + preformatted sub-lines; route only the template. |
| `hud.gd:2662` | `Mission: %s%s\n   %s` | Same; the `✓`/`❧` mark is a Control ornament. |
| `hud.gd:2129` | `DOWNED — %ds` | `UIStrings.st_text("ST_HUD","DownedTimer","Downed — {0}s").replace("{0}", ...)`; key does not exist yet. |
| `hud.gd:2136` | `CLUE — %s: %s` | `ST_HUD`/`ClueToast` template `{0}`/`{1}`; title/body already authored data. |
| `hud.gd:2179` | `LOCK` + ` — LV %d` | Route `LOCK` via `ST_Lockpicking` `LockPicking.Lock.NoKeyLock`; use `Lock Level {LockLevel}` for the suffix. |
| `hud.gd:3416` | `◆ %s (%dm)` | `ST_GeneralUI Format.Distance` exists (`{Distance} m`); compose icon + translated distance. |
| `hud.gd:2068` | `%s   £ %d` | No linguistic content beyond `Cash in Hand`; already routed. |
| `hud.gd:3690` | `FPS %d | ...` | Dev overlay; leave as-is or move labels into a diagnostic table. |
| `contract_table_ui.gd:295` | `#%02d  %s  (%s)` | Use `Screen.Contract.Number` (`Contract #{number}`) + a list-row template with `{0}`/`{1}`. |
| `contract_table_ui.gd:324` | `#%02d  %s` | Same. |
| `contract_table_ui.gd:328` | `Target: %s\nLocation: %s\n\n%s` | Add `Target:`/`Location:` labels to a TAT-2 map-table table; substitute `{0}`/`{1}`/`{2}`. |
| `contract_table_ui.gd:442` | `Join Mission with these settings?\nDifficulty: %s\nMode: %s` | Wire `ST_ThievesDen` `CityMap.ConfirmJoinLobby` (`{difficulty}`/`{mode}`); CRLF is already handled by the table loader. |
| `ledger_ui.gd:585/595/632/654/734/920/923/972` | `Level %d`, `%d/%d`, `Contract #%d`, `Location: %s\n`, `YOUR TOTAL ASSETS: (£) %s`, `£ %s`, `BUY — £ %s`, `Insufficient funds...` | Use `ST_Screens` `Screen.Contract.Number`, `Screen.Label.TotalAssets`; add `Level`/`Location`/`Insufficient funds` rows or reuse `ST_BlackMarket Purchase.NotEnoughMoney`. |
| `mission_prep_ui.gd:1299` | `%s (%s)` | Mission selector: keep title/id formatting in code; names are authored data. |
| `mission_prep_ui.gd:1378/1396` | `\nTime Limit: %d minutes` | Wire `ST_Screens` `Screen.MissionLobby.TimeLimit` (`{matchDurationInMinutes}`). |
| `mission_prep_ui.gd:1470/1472` | `Active contract: %s`, `\nTarget: %s` | Add a contract-card template with `{0}`/`{1}`; title/quest data already authored. |
| `mission_prep_ui.gd:1503/1505` | `[F]  %s`, `[F] %s  ·  [ESC] BACK` | Keep the keycap as a separate Control; route the action word (already `Screen.Lobby.Ready/Unready`). |
| `mission_prep_ui.gd:1446` | `...{MatchDurationInMinutes}...` | Already correct: `UIStrings.st_text(...).replace("{MatchDurationInMinutes}", mins)`. |
| `settings_ui.gd:340/557/595` | `MOBILE QUALITY: ` + tier | Add a `Settings.MobileQuality` row `MOBILE QUALITY: {0}`; `MobileProfile.TIER_LABELS` are port strings. |
| `settings_ui.gd:415-431` | `%d`, `%d%%`, `x%.1f` | Numeric only; keep. |
| `settings_ui.gd:875` | `DISPLAY: ` + device + `  ·  [BACKSLASH] TO SWAP` | Add `Settings.Controls.DisplayDevice` `DISPLAY: {0}  ·  [BACKSLASH] TO SWAP`. |
| `settings_ui.gd:922` | `BOUND: ` + action + `  →  ` + key | Add `Settings.Controls.Bound` `BOUND: {0}  →  {1}`. |
| `loading_screen.gd:205` | `title + " — " + clue` | Currently hidden (`_subtitle_lbl.text = ""`); if re-enabled, use a `{0} — {1}` template. |
| `mobile_touch_ui.gd:533` | `%s\n%d` | Keep numeric badge; route the label word separately (already a const). |
| `review_mode.gd:125-490` | `%s` / `%d` formats | Dev-only; out of the player DoD. |
| `mission_controller.gd:2521/2522` | `Difficulty: %s`, `Mode: %s` | Wire the existing `ST_Screens` templates; substitute `{difficulty}`/`{mode}`. |
| `mission_controller.gd:2837` | `Steal %s in loot value` | Use `sources.json` `ST_Quests.LootValueObjective.Default` (`Steal {Amount} in loot value`) or add a table row. |
| `mission_controller.gd:2874/2881` | `Steal the %s` | Add a `{0}` objective template (no exact shipped row today). |
| `mission_controller.gd:2950` | `...{MatchDurationInMinutes}...` | Already substituted before the letter is shown. |
| `loot_container.gd:308` | `[F] PICK LOCK (Lv %d)` | Add `PromptPickLock` `[F] PICK LOCK (Lv {0})`; `Lock Level {LockLevel}` already exists. |
| `clue_item.gd:117/125/126` | `[%s]`, `[E] %s`, `[Read] `, `[E] Read Clue: ` | Route to `ST_Interactables` `PromptRead`/`PromptReadClue`; keep `[E]` keycap as a Control. |
| `hud.gd:2068/2637/2639` | `%s   £ %d`, `  (DOOR %s)`, `  (%s)` | Numeric/glue only; the `DOOR` label needs a `{0}` template. |

**Rule of thumb:** move the sentence to the table with `{0}`/`{1}`/`{name}` tokens, keep numeric/currency formatting in code, and call `UIStrings.st_text(table,key,fallback).replace("{token}", value)` — exactly the pattern at `hud.gd:2062` and `mission_prep_ui.gd:1446`.

## 7. Authored but unwired — the easy wins

86 unwired rows already have an authored row. Grouped by table:

### `ST_Screens` (20)

- `game/src/missions/mission_controller.gd:2511` — `CONSTABLES' GUILDHALL` -> `Screen.MissionLobby.RandomQuestLocation` = `Constables' Guildhall`
- `game/src/missions/mission_controller.gd:2521` — `Difficulty: %s` -> `Screen.MissionLobby.Difficulty` = `Difficulty: {difficulty}`
- `game/src/missions/mission_controller.gd:2522` — `Mode: %s` -> `Screen.MissionLobby.Mode` = `Mode: {mode}`
- `game/src/ui/hud.gd:2657` — `Contract #%d` -> `Screen.Contract.Number` = `Contract #{number}`
- `game/src/ui/ledger_ui.gd:24` — `Constables' Guildhall` -> `Screen.MissionLobby.RandomQuestLocation` = `Constables' Guildhall`
- `game/src/ui/ledger_ui.gd:25` — `Constables' Guildhall` -> `Screen.MissionLobby.RandomQuestLocation` = `Constables' Guildhall`
- `game/src/ui/ledger_ui.gd:29` — `Constables' Guildhall` -> `Screen.MissionLobby.RandomQuestLocation` = `Constables' Guildhall`
- `game/src/ui/ledger_ui.gd:613` — `Active` -> `Screen.Ledger.Contract.Status.InProgress` = `Active`
- `game/src/ui/ledger_ui.gd:613` — `Completed` -> `Screen.Ledger.Contract.Status.Complete` = `Completed`
- `game/src/ui/ledger_ui.gd:632` — `Contract #%d` -> `Screen.Contract.Number` = `Contract #{number}`
- `game/src/ui/mission_prep_ui.gd:449` — `MISSION STARTING IN 5...` -> `Screen.MissionLobby.Countdown` = `Mission Starting in <Num>{number}</>...`
- `game/src/ui/mission_prep_ui.gd:468` — `Mode: Solo` -> `Screen.MissionLobby.Mode` = `Mode: {mode}`
- `game/src/ui/mission_prep_ui.gd:478` — `Difficulty: Novice` -> `Screen.MissionLobby.Difficulty` = `Difficulty: {difficulty}`
- `game/src/ui/mission_prep_ui.gd:574` — `READY` -> `Screen.Lobby.Ready` = `Ready`
- `game/src/ui/mission_prep_ui.gd:1374` — `Cleanout Heist` -> `Screen.MissionLobby.OldManor.LootTheRoomTitle` = `Cleanout Heist`
- `game/src/ui/mission_prep_ui.gd:1374` — `Item Collection Heist` -> `Screen.MissionLobby.SetQuestTitle` = `Item Collection Heist`
- `game/src/ui/mission_prep_ui.gd:1374` — `Vault Heist` -> `Screen.MissionLobby.VaultQuestTitle` = `Vault Heist`
- `game/src/ui/mission_prep_ui.gd:1378` — `\nTime Limit: %d minutes` -> `Screen.MissionLobby.TimeLimit` = `Time Limit: {matchDurationInMinutes} minutes`
- `game/src/ui/mission_prep_ui.gd:1396` — `\nTime Limit: %d minutes` -> `Screen.MissionLobby.TimeLimit` = `Time Limit: {matchDurationInMinutes} minutes`
- `game/src/ui/review_mode.gd:452` — `ready` -> `Screen.Lobby.Ready` = `Ready`

### `ST_ThievesDen` (19)

- `game/src/missions/mission_controller.gd:2511` — `ELWAY MANOR` -> `CityMap.OldManor` = `Elway Manor`
- `game/src/missions/mission_controller.gd:2519` — `Prepare for Mission` -> `CityMap.JoinLobby` = `Prepare for Mission`
- `game/src/missions/mission_controller.gd:2523` — `Prepare for Mission` -> `CityMap.JoinLobby` = `Prepare for Mission`
- `game/src/ui/contract_table_ui.gd:206` — `Difficulty:` -> `CityMap.DifficultyHeader` = `Difficulty:`
- `game/src/ui/contract_table_ui.gd:442` — `Join Mission with these settings?\nDifficulty: %s\nMode: %s` -> `CityMap.ConfirmJoinLobby` = `Join Mission with these settings? Difficulty: {difficulty} Mode: {mode}`
- `game/src/ui/hud.gd:2322` — `Difficulty:` -> `CityMap.DifficultyHeader` = `Difficulty:`
- `game/src/ui/hud.gd:2323` — `Mode:` -> `CityMap.GameModeHeader` = `Mode:`
- `game/src/ui/hud.gd:2336` — `Prepare for Mission` -> `CityMap.JoinLobby` = `Prepare for Mission`
- `game/src/ui/ledger_ui.gd:26` — `Elway Manor` -> `CityMap.OldManor` = `Elway Manor`
- `game/src/ui/ledger_ui.gd:914` — `LOCKED` -> `CityMap.Locked` = `LOCKED`
- `game/src/ui/wardrobe_ui.gd:358` — `WARDROBE` -> `Wardrobe.Header` = `Wardrobe`
- `game/src/ui/wardrobe_ui.gd:442` — `LOCKED` -> `CityMap.Locked` = `LOCKED`
- `game/src/ui/wardrobe_ui.gd:636` — `Edit Loadout` -> `Wardrobe.Loadout` = `Edit Loadout`
- `game/src/ui/wardrobe_ui.gd:664` — `Select a loadout slot to equip or swap out tools` -> `Wardrobe.SelectLoadout` = `Select a loadout slot to equip or swap out tools`
- `game/src/ui/wardrobe_ui.gd:773` — `Head` -> `Wardrobe.OutfitHead` = `Head`
- `game/src/ui/wardrobe_ui.gd:785` — `Body` -> `Wardrobe.OutfitBody` = `Body`
- `game/src/ui/wardrobe_ui.gd:794` — `Calling Card` -> `Wardrobe.OutfitCallingCard` = `Calling Card`
- `game/src/ui/wardrobe_ui.gd:1043` — `Signature Tools cannot be swapped out` -> `Wardrobe.DeclinePrimarySwap` = `Signature Tools cannot be swapped out`
- `game/src/ui/wardrobe_ui.gd:1060` — `Signature Tools cannot be swapped out` -> `Wardrobe.DeclinePrimarySwap` = `Signature Tools cannot be swapped out`

### `ST_Interactables` (8)

- `game/src/missions/mission_controller.gd:2479` — `EXIT` -> `PromptHidingSpotExit` = `Exit`
- `game/src/missions/mission_controller.gd:2480` — `EXIT` -> `PromptHidingSpotExit` = `Exit`
- `game/src/missions/mission_controller.gd:2535` — `PONDER` -> `PromptLookAtHubSecret` = `Ponder`
- `game/src/missions/mission_controller.gd:2536` — `PONDER` -> `PromptLookAtHubSecret` = `Ponder`
- `game/src/missions/mission_controller.gd:3178` — `Read` -> `PromptRead` = `Read`
- `game/src/ui/hud.gd:3649` — `OPEN` -> `PromptOpen` = `Open`
- `game/src/ui/hud.gd:3651` — `CLOSE` -> `PromptClose` = `Close`
- `game/src/ui/main_menu.gd:747` — `CLOSE` -> `PromptClose` = `Close`

### `ST_MapTool` (7)

- `game/src/missions/mission_controller.gd:656` — `Contract` -> `Legend.Contract` = `Contract`
- `game/src/missions/mission_controller.gd:670` — `Contract` -> `Legend.Contract` = `Contract`
- `game/src/ui/hud.gd:3308` — `CONSTABLES' GUILDHALL` -> `Guildhall.MapName` = `Constables' Guildhall`
- `game/src/ui/ledger_ui.gd:641` — `Contract` -> `Legend.Contract` = `Contract`
- `game/src/ui/mission_prep_ui.gd:31` — `CONSTABLES' GUILDHALL` -> `Guildhall.MapName` = `Constables' Guildhall`
- `game/src/ui/mission_prep_ui.gd:32` — `This is the headquarters and operational base for the Constables, Kilcairn's pol` -> `Guildhall.MapFlavorText` = `This is the headquarters and operational base for the Constables, Kilcairn's pol`
- `game/src/ui/mission_prep_ui.gd:557` — `CONTRACT` -> `Legend.Contract` = `Contract`

### `sources.json` (6)

- `game/src/missions/mission_controller.gd:2837` — `Steal %s in loot value` -> `ST_Quests.LootValueObjective.Default` = `Steal {Amount} in loot value`
- `game/src/missions/mission_controller.gd:3708` — `Vault Key` -> `17C527AE4CF0F1D3E991BEB4EC7D02F2` = `Vault Key`
- `game/src/missions/mission_controller.gd:3712` — `Guildhall Key` -> `05C7F6C4444DF32070196ABE94425CD7` = `Guildhall Key`
- `game/src/missions/mission_controller.gd:3715` — `Elway Manor Key` -> `B847A1B24015CF72A6DFD8AF63B85205` = `Elway Manor Key`
- `game/src/ui/hud.gd:2620` — `Steal %s in loot value` -> `ST_Quests.LootValueObjective.Default` = `Steal {Amount} in loot value`
- `game/src/ui/ledger_ui.gd:585` — `Level %d` -> `8B4C117444C09873AE6B93A479489972` = `Level {CurrentLevel}`

### `ST_GeneralUI` (5)

- `game/src/ui/hud.gd:1976` — `Novice` -> `Mission.Difficulty.Easy` = `Novice`
- `game/src/ui/hud.gd:1978` — `Thief` -> `Mission.Difficulty.Normal` = `Thief`
- `game/src/ui/hud.gd:1980` — `Master Thief` -> `Mission.Difficulty.Hard` = `Master Thief`
- `game/src/ui/loading_screen.gd:130` — `LOADING...` -> `Loading` = `Loading...`
- `game/src/ui/review_mode.gd:452` — `loading...` -> `Loading` = `Loading...`

### `ST_Settings` (5)

- `game/src/ui/hud.gd:3416` — `PING` -> `Settings.Controls.Ping` = `Ping`
- `game/src/ui/mobile_touch_ui.gd:107` — `JUMP` -> `Settings.Controls.Jump` = `Jump`
- `game/src/ui/mobile_touch_ui.gd:118` — `SPRINT` -> `Settings.Controls.KBM.Sprint` = `Sprint`
- `game/src/ui/settings_ui.gd:640` — `Language` -> `Settings.General.Language` = `Language`
- `game/src/ui/settings_ui.gd:762` — `GAMEPAD` -> `Settings.Gamepad` = `Gamepad`

### `ST_Credits` (3)

- `game/src/ui/main_menu.gd:646` — `THICK AS THIEVES` -> `Game.Title` = `Thick As Thieves`
- `game/src/ui/main_menu.gd:707` — `CREDITS` -> `Section.Credits` = `Credits`
- `game/src/ui/main_menu.gd:737` — `OtherSide Entertainment` -> `Company.Otherside` = `Otherside Entertainment`

### `ST_OldManor_map` (3)

- `game/src/ui/hud.gd:3307` — `ELWAY MANOR` -> `OldManor.MapName` = `Elway Manor`
- `game/src/ui/mission_prep_ui.gd:29` — `ELWAY MANOR` -> `OldManor.MapName` = `Elway Manor`
- `game/src/ui/mission_prep_ui.gd:30` — `This is the estate of the three Elway sisters. Although it has fallen into disre` -> `OldManor.MapFlavorText` = `This is the estate of the three Elway sisters. Although it has fallen into disre`

### `ST_BlackMarket` (2)

- `game/src/ui/wardrobe_ui.gd:102` — `The Chameleon` -> `Thief.Chameleon.Title` = `The Chameleon`
- `game/src/ui/wardrobe_ui.gd:102` — `The Spider` -> `Thief.Spider.Title` = `The Spider`

### `ST_Social` (2)

- `game/src/ui/hud.gd:620` — `DANGER` -> `Ping.Danger` = `Danger`
- `game/src/ui/hud.gd:620` — `LOOT` -> `Ping.Loot` = `Loot`

### `contracts.json` (2)

- `game/src/ui/ledger_ui.gd:24` — `In the Eye of the Beholder` -> `/contracts[2]/title_text` = `In the Eye of the Beholder`
- `game/src/ui/ledger_ui.gd:25` — `Into the Lion's Den` -> `/contracts[1]/title_text` = `Into the Lion's Den`

### `ST_Lockpicking` (1)

- `game/src/ui/hud.gd:2179` — `LOCK` -> `LockPicking.Lock.NoKeyLock` = `Lock`

### `ST_PostMatch` (1)

- `game/src/ui/mission_prep_ui.gd:526` — `MISSION` -> `PostMatch.Mission` = `Mission`

### `ST_Settings_Input` (1)

- `game/src/ui/mobile_touch_ui.gd:117` — `CROUCH` -> `InputSetting.Movement.Crouch` = `Crouch`

### `ST_Tools` (1)

- `game/src/ui/mobile_touch_ui.gd:109` — `USE` -> `Tools_Deploy_Generic_Use` = `Use`

Plus the **24** `ST_Settings` rows that are authored but bypass Loc (`settings_ui.gd` `_label`). Converting `_label` to `UIStrings.st_text("ST_Settings", key, fallback)` routes all of them through Loc in one change. Three keys must be added first: `Settings.Volume.AmbienceVolume`, `Settings.Volume.UIVolume`, `Settings.GraphicsQuality.DesktopQuality` (currently fallbacks).
## 8. Full inventory

355 counted assignment sites, grouped by file. `routed` is `yes`/`table`/`no` as defined in §1. The TSV is authoritative; this table is the readable view (literals truncated to 80 chars).

### `game/src/ui/hud.gd`

| Line | Literal | Kind | Routed | Authored counterpart | Notes |
|---:|---|---|---|---|---|
| 29 | `N/NE/E/SE/S/SW/W/NW` | label | no | none | COMPASS_DIRECTIONS (8 values, one const array) assigned to compass_lbl.text. |
| 620 | `DANGER` | label | no | `ST_Social` / `Ping.Danger` = `Danger` (case-normalised) | PingRadialDraw.LABELS element. |
| 620 | `LOOT` | label | no | `ST_Social` / `Ping.Loot` = `Loot` (case-normalised) | PingRadialDraw.LABELS element. |
| 620 | `MOVE` | label | no | none | PingRadialDraw.LABELS element. Component: `ST_Tutorial` / `Tut_Movement_Intro` = `Move with <img id="Move"/>\nLook with <img id="Look"/>`. |
| 620 | `OBJECTIVE` | label | no | none | PingRadialDraw.LABELS element. |
| 1221 | `[RMB] CRANK` | prompt | no | none | Crank hint; component 'Crank' authored ST_Tools Tools_Deploy_Crank. |
| 1397 | `MAP` | button | yes | `ST_HUD` / `MapButtonLabel` = `Map` (case-normalised) |  |
| 1410 | `[HOLD] PING MENU` | button | yes | `ST_HUD` / `PingButtonLabel` = `[Hold] Ping Menu` (case-normalised) |  |
| 1562 | `LOCKPICKING` | label | no | none |  |
| 1571 | `TUMBLER 1 / 1` | label | no | none |  |
| 1602 | `[SPACE] / [LMB] STRIKE PIN   ·   [ESC] CANCEL` | prompt | no | none | Component: `ST_Tools` / `Tools_Disguise_Cancel` = `Cancel`. |
| 1636 | `TACTICAL MAP` | label | no | none |  |
| 1649 | `● YOU    ◆ OBJECTIVE    • LOOT    ▲ GUARD    ◎ WAYPOINT PING` | label | no | none |  |
| 1665 | `[LMB] PLACE WAYPOINT   ·   [TAB] / [ESC] CLOSE MAP` | prompt | no | none |  |
| 1805 | `Esteemed Colleague -` | heading | no | none | Letter salutation. Shipped briefings begin with this exact prefix, but there is no standalone row. |
| 1830 | `[SPACE]  CONTINUE` | button | no | none | 'Continue' authored Screen.Continue; keycap prefix invented. |
| 1872 | `CONTINUE` | button | yes | `ST_Screens` / `Screen.Continue` = `Continue` (case-normalised) |  |
| 1917 | `Resume` | button | yes | `ST_GeneralUI` / `Escape.Resume` = `Resume` (exact) |  |
| 1922 | `Settings` | button | yes | `ST_GeneralUI` / `Escape.Settings` = `Settings` (exact) |  |
| 1932 | `Return to Thief's Den` | button | yes | `ST_GeneralUI` / `Escape.toThievesDen` = `Return to Thief's Den` (exact) |  |
| 1940 | `Quit To Desktop` | button | yes | `ST_GeneralUI` / `Escape.Quit` = `Quit To Desktop` (exact) |  |
| 1952 | `Resume` | label | yes | `ST_GeneralUI` / `Escape.Resume` = `Resume` (exact) |  |
| 1976 | `Novice` | label | no | `ST_GeneralUI` / `Mission.Difficulty.Easy` = `Novice` (exact) | Pause footer difficulty; authored ST_GeneralUI Mission.Difficulty.Easy. |
| 1978 | `Thief` | label | no | `ST_GeneralUI` / `Mission.Difficulty.Normal` = `Thief` (exact) | Pause footer difficulty; authored ST_GeneralUI Mission.Difficulty.Normal. |
| 1980 | `Master Thief` | label | no | `ST_GeneralUI` / `Mission.Difficulty.Hard` = `Master Thief` (exact) | Pause footer difficulty; authored ST_GeneralUI Mission.Difficulty.Hard. |
| 2017 | `Mission: %s [%d/%d]\n  (£) %d` | objective | no | none | No authored template for the 'Mission:' wrapper. Component: `ST_PostMatch` / `PostMatch.Mission` = `Mission`. |
| 2025 | `NOTICE` | toast | no | none | show_toast() reuses the clue toast with title NOTICE. Component: `ST_Missions_Guildhall_Procurment` / `Guildhall.Procurement.Archives.Primary17` = `Notice to all personnel - the shut off switch to vault secur`. |
| 2040 | `Caught` | label | yes | `ST_PostMatch` / `PostMatch.Status.Caught` = `Caught` (exact) |  |
| 2040 | `Escaped` | label | yes | `ST_PostMatch` / `PostMatch.Status.Escaped` = `Escaped` (exact) |  |
| 2057 | `Ill-Gotten Gains` | label | yes | `ST_PostMatch` / `PostMatch.Haul` = `Ill-Gotten Gains` (exact) |  |
| 2062 | `Loot Earned: £{0}` | label | yes | `ST_Screens` / `Screen.PostMatch.LootEarned` = `Loot Earned: £{0}` (exact) |  |
| 2065 | `Loot Lost: £{0}` | label | yes | `ST_Screens` / `Screen.PostMatch.LootLost` = `Loot Lost: £{0}` (exact) |  |
| 2067 | `Cash in Hand` | label | yes | `ST_Screens` / `Screen.PostMatch.CashInHand` = `Cash in Hand` (exact) |  |
| 2115 | `Contract` | label | yes | `ST_PostMatch` / `PostMatch.Contract` = `Contract` (exact) |  |
| 2129 | `DOWNED — %ds` | label | no | none | Downed countdown; no authored row. |
| 2136 | `CLUE — %s: %s` | toast | no | none | Clue toast wrapper; no authored row. |
| 2179 | ` — LV %d` | label | no | none | Two literals on this line: LOCK fallback + ' — LV %d' suffix. |
| 2179 | `LOCK` | label | no | `ST_Lockpicking` / `LockPicking.Lock.NoKeyLock` = `Lock` (case-normalised) | Two literals on this line: LOCK fallback + ' — LV %d' suffix. |
| 2322 | `Difficulty:` | label | no | `ST_ThievesDen` / `CityMap.DifficultyHeader` = `Difficulty:` (exact) | Den look-at card fallback row; authored CityMap.DifficultyHeader. |
| 2323 | `Mode:` | label | no | `ST_ThievesDen` / `CityMap.GameModeHeader` = `Mode:` (exact) | Den look-at card fallback row; authored CityMap.GameModeHeader. |
| 2336 | `Prepare for Mission` | label | no | `ST_ThievesDen` / `CityMap.JoinLobby` = `Prepare for Mission` (exact) | Den card prompt fallback; authored CityMap.JoinLobby. |
| 2620 | `Steal %s in loot value` | objective | no | `sources.json` / `ST_Quests.LootValueObjective.Default` = `Steal {Amount} in loot value` (placeholder/whitespace-normalised) | Free-play objective label; authored sources.json ST_Quests.LootValueObjective.Default. |
| 2632 | `Mission: %s[%s/%s]` | objective | no | none | Component: `ST_PostMatch` / `PostMatch.Mission` = `Mission`. |
| 2637 | `  (DOOR %s)` | label | no | none |  |
| 2652 | `Objective` | objective | no | none | Objective sub-line fallback when label missing. |
| 2653 | `Heist` | objective | no | none | Objective header fallback when title missing. |
| 2654 | `Mission: %s [%d/%d]%s\n%s` | objective | no | none | Component: `ST_PostMatch` / `PostMatch.Mission` = `Mission`. |
| 2657 | `Contract #%d` | objective | no | `ST_Screens` / `Screen.Contract.Number` = `Contract #{number}` (placeholder/whitespace-normalised) | Authored Screen.Contract.Number uses {number}. |
| 2658 | `Objective` | objective | no | none | Quest item fallback. |
| 2661 | `Reach Escape Gate` | objective | no | none | Objective status when all objectives complete. Component: `ST_HUD` / `Spectator.Escape` = `Escape`. |
| 2662 | `Mission: %s%s\n   %s` | objective | no | none | Component: `ST_PostMatch` / `PostMatch.Mission` = `Mission`. |
| 2682 | `THE MAGIC DOOR IS OPEN` | label | no | none | Endgame door banner (no countdown). ST_Toasts MatchEnd_* has different wording. |
| 2683 | `THE MAGIC DOOR IS OPEN — %s BEFORE IT COLLAPSES` | label | no | none | Endgame door banner with countdown. |
| 3196 | `TUMBLER %d / %d` | label | no | none |  |
| 3198 | `[SPACE] / [LMB] STRIKE PIN   ·   [ESC] CANCEL` | prompt | no | none | Component: `ST_Tools` / `Tools_Disguise_Cancel` = `Cancel`. |
| 3265 | `PIN SET! HIT NEXT SWEET SPOT` | label | no | none |  |
| 3272 | `LOCK JAMMED!` | label | no | none | Component 'Jammed!' authored ST_Lockpicking Lockpicking.Term.Jammed. |
| 3307 | `ELWAY MANOR` | label | no | `ST_OldManor_map` / `OldManor.MapName` = `Elway Manor` (case-normalised) |  |
| 3308 | `CONSTABLES' GUILDHALL` | label | no | `ST_MapTool` / `Guildhall.MapName` = `Constables' Guildhall` (case-normalised) |  |
| 3309 | `THIEVES' DEN` | label | no | none | No standalone authored value (substrings only). |
| 3313 | `TACTICAL MAP — ` | label | no | none |  |
| 3345 | `WAYPOINT` | label | no | none |  |
| 3416 | `PING` | label | no | `ST_Settings` / `Settings.Controls.Ping` = `Ping` (case-normalised) | World ping marker format; PING fallback authored Settings.Controls.Ping. |
| 3649 | `OPEN` | prompt | no | `ST_Interactables` / `PromptOpen` = `Open` (case-normalised) | Door prompt rewrite; authored ST_Interactables PromptOpen. |
| 3651 | `CLOSE` | prompt | no | `ST_Interactables` / `PromptClose` = `Close` (case-normalised) | Door prompt rewrite; authored ST_Interactables PromptClose. |
| 3690 | `FPS %d \| %.1f ms \| draws %d \| objs %d \| prims %d\nnodes %d \| VRAM %.0f MB \| pos ` | debug-overlay | no | none | F3 developer overlay; not player-facing. |

### `game/src/ui/main_menu.gd`

| Line | Literal | Kind | Routed | Authored counterpart | Notes |
|---:|---|---|---|---|---|
| 646 | `THICK AS THIEVES` | title | no | `ST_Credits` / `Game.Title` = `Thick As Thieves` (case-normalised) | Game title; authored ST_Credits Game.Title (case-normalised). |
| 656 | `PLAY` | button | yes | `ST_Screens` / `Screen.MainMenu.Play` = `Play` (case-normalised) |  |
| 665 | `SETTINGS` | button | yes | `ST_Screens` / `Screen.MainMenu.Settings` = `Settings` (case-normalised) |  |
| 669 | `CREDITS` | button | yes | `ST_Screens` / `Screen.MainMenu.Credits` = `Credits` (case-normalised) |  |
| 673 | `QUIT` | button | yes | `ST_Screens` / `Screen.MainMenu.Quit` = `Quit` (case-normalised) |  |
| 707 | `CREDITS` | title | no | `ST_Credits` / `Section.Credits` = `Credits` (case-normalised) | Credits modal title, unwrapped. |
| 707 | `Thick As Thieves — OtherSide Entertainment / Megabit` | subtitle | no | none | Credits modal title, unwrapped. Component: `ST_Credits` / `Company.Otherside` = `Otherside Entertainment`. |
| 737 | `Godot 4.7 Port — TAT-2` | label | no | none | Credits fallback row (only if DT_Credits.json is missing/unreadable). |
| 737 | `OtherSide Entertainment` | label | no | `ST_Credits` / `Company.Otherside` = `Otherside Entertainment` (case-normalised) | Credits fallback row (only if DT_Credits.json is missing/unreadable). |
| 737 | `Paul Neurath — Executive Producer` | label | no | none | Credits fallback row (only if DT_Credits.json is missing/unreadable). Component: `ST_Credits` / `Role.Producer` = `Producer`. |
| 737 | `Warren Spector — Studio Director` | label | no | none | Credits fallback row (only if DT_Credits.json is missing/unreadable). |
| 747 | `CLOSE` | button | no | `ST_Interactables` / `PromptClose` = `Close` (case-normalised) | Authored PromptClose 'Close' (case-normalised) but unwired. |

### `game/src/ui/settings_ui.gd`

| Line | Literal | Kind | Routed | Authored counterpart | Notes |
|---:|---|---|---|---|---|
| 340 | `MOBILE QUALITY: ` | button | no | none | Mobile quality button prefix; tier word from MobileProfile.TIER_LABELS. |
| 460 | `GENERAL` | tab | table | `ST_Settings` / `Settings.General` = `General` (case-normalised) | ST_Settings direct (_label), NOT Loc. Table-only, no translation. |
| 461 | `VIDEO` | tab | table | `ST_Settings` / `Settings.Display.Header` = `Video` (case-normalised) | ST_Settings direct (_label), NOT Loc. Table-only, no translation. |
| 462 | `AUDIO` | tab | table | `ST_Settings` / `Settings.Audio.Header` = `Audio` (case-normalised) | ST_Settings direct (_label), NOT Loc. Table-only, no translation. |
| 463 | `CONTROLS` | tab | table | `ST_Settings` / `Settings.Controls.Header` = `Controls` (case-normalised) | ST_Settings direct (_label), NOT Loc. Table-only, no translation. |
| 492 | `Mouse` | group-header | table | `ST_Settings` / `Settings.Mouse` = `Mouse` (exact) |  |
| 495 | `Mouse Sensitivity` | label | table | `ST_Settings` / `Settings.Mouse.MouseSensitivity` = `Mouse Sensitivity` (exact) |  |
| 496 | `Mouse Invert Y-Axis` | label | table | `ST_Settings` / `Settings.Mouse.MouseInvertYAxis` = `Mouse Invert Y-Axis` (exact) |  |
| 498 | `Gameplay` | group-header | table | `ST_Settings` / `Settings.Gameplay` = `Gameplay` (exact) |  |
| 501 | `Sprint Toggle` | label | table | `ST_Settings` / `Settings.Gameplay.SprintToggle` = `Sprint Toggle` (exact) |  |
| 502 | `Reduced Camera Bounce` | label | table | `ST_Settings` / `Settings.Gameplay.ReducedCameraBounce` = `Reduced Camera Bounce` (exact) |  |
| 507 | `Display` | group-header | table | `ST_Settings` / `Settings.Display` = `Display` (exact) |  |
| 512 | `Field of View` | label | table | `ST_Settings` / `Settings.Camera.FOV` = `Field of View` (exact) |  |
| 513 | `Fullscreen` | label | table | `ST_Settings` / `Settings.Display.WindowMode.Fullscreen` = `Fullscreen` (exact) |  |
| 514 | `V-Sync` | label | table | `ST_Settings` / `Settings.Display.VSync` = `V-Sync` (exact) |  |
| 516 | `Graphics Quality` | group-header | table | `ST_Settings` / `Settings.GraphicsQuality` = `Graphics Quality` (exact) |  |
| 519 | `Resolution Scale` | label | table | `ST_Settings` / `Settings.GraphicsQuality.ResolutionScale` = `Resolution Scale` (exact) |  |
| 525 | `Volume` | group-header | table | `ST_Settings` / `Settings.Volume` = `Volume` (exact) |  |
| 528 | `Master Volume` | label | table | `ST_Settings` / `Settings.Volume.MasterVolume` = `Master Volume` (exact) |  |
| 529 | `Music Volume` | label | table | `ST_Settings` / `Settings.Volume.MusicVolume` = `Music Volume` (exact) |  |
| 530 | `SFX Volume` | label | table | `ST_Settings` / `Settings.Volume.SFXVolume` = `SFX Volume` (exact) |  |
| 531 | `Ambience Volume` | label | no | none | KEY MISSING in ST_Settings -> hardcoded fallback displayed; not routed. Component: `ST_Settings` / `Settings.Volume` = `Volume`. |
| 532 | `UI Volume` | label | no | none | KEY MISSING in ST_Settings -> hardcoded fallback displayed; not routed. Component: `ST_Settings` / `Settings.Volume` = `Volume`. |
| 533 | `Dialogue Volume` | label | table | `ST_Settings` / `Settings.Volume.DialogueVolume` = `Dialogue Volume` (exact) |  |
| 539 | `Controls` | group-header | table | `ST_Settings` / `Settings.Controls.Header` = `Controls` (exact) |  |
| 543 | `STICK / MOVE` | binding-row | no | none | Mobile controls binding row (keycap + action). |
| 544 | `DRAG / LOOK` | binding-row | no | none | Mobile controls binding row; 'Look' authored Settings.Controls.Look. |
| 545 | `USE / INTERACT / STEAL` | binding-row | no | none | Mobile controls binding row; 'Use' authored Tools_Deploy_Generic_Use. Component: `ST_Interactable_Props` / `PromptInteract` = `Interact`. |
| 546 | `HIT / WIRE / ATTACK / ABILITY` | binding-row | no | none | Mobile controls binding row; no authored counterparts. Component: `ST_Social` / `Ping.Attack` = `Attack`. |
| 547 | `1 2 3 / TOOLS` | binding-row | no | none | Mobile controls binding row; 'Tools' authored InputSetting.Category.Tools. |
| 548 | `EYE / THIEF VISION` | binding-row | no | none | Mobile controls binding row; no authored counterparts. |
| 549 | `II / BACK / PAUSE` | binding-row | no | none | Mobile controls binding row; no authored counterparts. |
| 551 | `Touch Look` | label | no | none | Mobile touch sensitivity label; not authored. |
| 572 | `RESET DEFAULTS` | button | table | `ST_Settings` / `Settings.Changes.Revert` = `Revert Changes` (staged) | Table value is 'Revert Changes', so the fallback literal is not displayed when the table loads. Still bypasses Loc. |
| 581 | `APPLY & BACK` | button | table | `ST_Settings` / `Settings.Changes.Apply` = `Apply Changes` (staged) | Table value is 'Apply Changes', so the fallback literal is not displayed when the table loads. Still bypasses Loc. |
| 605 | `Graphics Quality` | label | no | none | KEY MISSING -> fallback displayed; same value exists under Settings.GraphicsQuality. Component: `ST_Settings` / `Settings.GraphicsQuality` = `Graphics Quality`. |
| 616 | `Low/Medium/High` | option | no | none | DESKTOP_QUALITY_LABELS ladder; only engine scalability labels in sources.json (weak). |
| 640 | `Language` | label | no | `ST_Settings` / `Settings.General.Language` = `Language` (exact) | Hardcoded, not via _label. Authored Settings.General.Language exact but unused. |
| 762 | `GAMEPAD` | group-header | no | `ST_Settings` / `Settings.Gamepad` = `Gamepad` (case-normalised) | Hardcoded. Authored Settings.Gamepad exact but unused. |
| 772 | `RESET BINDINGS` | button | no | none | Rebind reset button; not authored. |
| 798 | `Reset this binding` | tooltip | no | none | Clear-binding tooltip; not authored. |
| 822 | `VeryLow/Low/Normal/Fast/VeryFast` | option | no | none | InputActions.SENSITIVITY_STEPS values; authored ST_Settings uses 'Very Low'/'Very Fast' spacing. Component: `ST_Settings` / `Settings.InputSensitivity.Normal` = `Normal`. |
| 875 | `  ·  [BACKSLASH] TO SWAP` | label | no | none | Controls device button prefix/suffix. |
| 875 | `DISPLAY: ` | label | no | none | Controls device button prefix/suffix. |
| 882 | `[ PRESS ANY KEY ]` | label | no | none | Component 'Press Any Key' authored InputSetting.PressAnyKey; brackets invented. |
| 886 | `[ UNBOUND ]` | label | no | none | Unbound action button; not authored. |
| 893 | `PRESS ANY KEY  ·  [ESC] CANCEL` | status | no | none | Rebind status; component 'Press Any Key' authored. |
| 922 | `BOUND: ` | status | no | none | Rebind success prefix. |
| 924 | `That input cannot be bound here.` | status | no | none | Rebind error fallback string. Component: `ST_Social` / `Ping.Cannot` = `Cannot`. |

### `game/src/ui/ledger_ui.gd`

| Line | Literal | Kind | Routed | Authored counterpart | Notes |
|---:|---|---|---|---|---|
| 24 | `Constables' Guildhall` | fallback-card-location | no | `ST_Screens` / `Screen.MissionLobby.RandomQuestLocation` = `Constables' Guildhall` (exact) |  |
| 24 | `In the Eye of the Beholder` | fallback-card-title | no | `contracts.json` / `/contracts[2]/title_text` = `In the Eye of the Beholder` (exact) |  |
| 24 | `Steal the Beholder's Eye diamond from the Guildhall vault.` | fallback-card-description | no | none |  |
| 25 | `Constables' Guildhall` | fallback-card-location | no | `ST_Screens` / `Screen.MissionLobby.RandomQuestLocation` = `Constables' Guildhall` (exact) |  |
| 25 | `Infiltrate the Guildhall under heightened watch.` | fallback-card-description | no | none |  |
| 25 | `Into the Lion's Den` | fallback-card-title | no | `contracts.json` / `/contracts[1]/title_text` = `Into the Lion's Den` (exact) |  |
| 26 | `Burgle the Elway Manor gallery without waking the household.` | fallback-card-description | no | none | Component: `ST_BlackMarket` / `Map.OldManor.Title` = `Elway Manor`. |
| 26 | `Elway Manor` | fallback-card-location | no | `ST_ThievesDen` / `CityMap.OldManor` = `Elway Manor` (exact) |  |
| 26 | `Shadows over Old Manor` | fallback-card-title | no | none | Component: `ST_Settings` / `Settings.GraphicsQuality.Shadows` = `Shadows`. |
| 27 | `A high-wire score across the rooftops of Kilcairn.` | fallback-card-description | no | none |  |
| 27 | `Kilcairn Rooftops` | fallback-card-location | no | none |  |
| 27 | `The Spider's Gambit` | fallback-card-title | no | none | Component: `ST_BlackMarket` / `Thief.Spider.Title` = `The Spider`. |
| 28 | Ledger | `game/src/ui/ledger_ui.gd:909` | `✓ PURCHASED` | none | 'Purchased' authored Availability.Purchased; check glyph added. |
| 28 | Ledger | `game/src/ui/ledger_ui.gd:909` | `✓ PURCHASED` | none | 'Purchased' authored Availability.Purchased; check glyph added. |
| 28 | Ledger | `game/src/ui/ledger_ui.gd:909` | `✓ PURCHASED` | none | 'Purchased' authored Availability.Purchased; check glyph added. |
| 29 | `Constables' Guildhall` | fallback-card-location | no | `ST_Screens` / `Screen.MissionLobby.RandomQuestLocation` = `Constables' Guildhall` (exact) |  |
| 29 | `Reclaim impounded loot from the constabulary lockup.` | fallback-card-description | no | none |  |
| 29 | `The Constable's Due` | fallback-card-title | no | none |  |
| 195 | `[Q] JOURNAL` | tab | no | none | 'Journal' authored Screen.Ledger.Journal; key prefix unwired. |
| 201 | `BLACK MARKET [E]` | tab | no | none | 'Black Market' authored Screen.Ledger.BlackMarket; key prefix unwired. |
| 210 | `BACK [ESC]` | button | no | none | 'Back' authored Screen.Back; key prefix unwired. |
| 275 | `Level 1` | label | no | none | No authored Level row (sources.json has 'Level {CurrentLevel}'). |
| 468 | `BUY` | button | no | none | No authored 'Buy' row. Component: `ST_ThievesDen` / `Ledger.BlackMarket.ConfirmPurchase` = `Buy {item} for £{price}?`. |
| 551 | `Contract %d` | fallback-card-title | no | none | _collect_contracts fallback. Component: `ST_MapTool` / `Legend.Contract` = `Contract`. |
| 585 | `Level %d` | label | no | `sources.json` / `8B4C117444C09873AE6B93A479489972` = `Level {CurrentLevel}` (placeholder/whitespace-normalised) | sources.json Level {CurrentLevel} placeholder-normalised (weak). |
| 613 | `Active` | label | no | `ST_Screens` / `Screen.Ledger.Contract.Status.InProgress` = `Active` (exact) | Authored Screen.Ledger.Contract.Status.* exact. |
| 613 | `Completed` | label | no | `ST_Screens` / `Screen.Ledger.Contract.Status.Complete` = `Completed` (exact) | Authored Screen.Ledger.Contract.Status.* exact. |
| 632 | `Contract #%d` | label | no | `ST_Screens` / `Screen.Contract.Number` = `Contract #{number}` (placeholder/whitespace-normalised) | Authored Screen.Contract.Number uses {number}. |
| 641 | `Contract` | fallback-card-title | no | `ST_MapTool` / `Legend.Contract` = `Contract` (exact) | Card title fallback. |
| 654 | `Location: %s\n` | label | no | none | Contract card location prefix. |
| 734 | `YOUR TOTAL ASSETS: (£) %s` | label | no | none | Contains authored 'Your Total Assets', but assembled banner is not authored. |
| 738 | `The Black Market catalog could not be read (%s). Nothing can be purchased. Run p` | label | no | none | Port diagnostic shown in the market panel; not authored. Component: `ST_Screens` / `Screen.Ledger.BlackMarket` = `Black Market`. |
| 873 | `Black Market unavailable` | label | no | none | Preview fallback title; not authored. Component: `ST_Screens` / `Screen.Ledger.BlackMarket` = `Black Market`. |
| 874 | `The authored catalog is missing. Nothing can be purchased.` | label | no | none | Preview fallback description; not authored. Component: `ST_BlackMarket` / `Availability.Purchased` = `Purchased`. |
| 884 | `No item selected` | label | no | none | Preview fallback title; not authored. |
| 885 | `Select an item from a table.` | label | no | none | Preview fallback description; not authored. |
| 906 | `BUY` | button | no | none | Component: `ST_ThievesDen` / `Ledger.BlackMarket.ConfirmPurchase` = `Buy {item} for £{price}?`. |
| 909 | `✓ PURCHASED` | label | no | none | 'Purchased' authored Availability.Purchased; check glyph added. Component: `ST_BlackMarket` / `Availability.Purchased` = `Purchased`. |
| 911 | `✓ PURCHASED` | label | no | none | Component: `ST_BlackMarket` / `Availability.Purchased` = `Purchased`. |
| 914 | `LOCKED` | label | no | `ST_ThievesDen` / `CityMap.Locked` = `LOCKED` (exact) | Authored Availability.Locked 'Locked' / CityMap.Locked 'LOCKED'. |
| 923 | `BUY — £ %s` | button | no | none |  |
| 972 | `Insufficient funds (have (£) %s, need £ %s)` | label | no | none | Authored alternative Purchase.NotEnoughMoney 'Not enough money!'; not wired. |

### `game/src/ui/wardrobe_ui.gd`

| Line | Literal | Kind | Routed | Authored counterpart | Notes |
|---:|---|---|---|---|---|
| 102 | `The Chameleon` | label | no | `ST_BlackMarket` / `Thief.Chameleon.Title` = `The Chameleon` (exact) |  |
| 102 | `The Spider` | label | no | `ST_BlackMarket` / `Thief.Spider.Title` = `The Spider` (exact) |  |
| 358 | `WARDROBE` | title | no | `ST_ThievesDen` / `Wardrobe.Header` = `Wardrobe` (case-normalised) | Authored ST_ThievesDen Wardrobe.Header (case-normalised). |
| 442 | `LOCKED` | label | no | `ST_ThievesDen` / `CityMap.Locked` = `LOCKED` (exact) | Authored CityMap.Locked exact. |
| 488 | `The Chameleon is locked. Unlock it in the Black Market (£10,000, Contract 3).` | hint | no | none | Port-authored hint (price/contract values are tuning). Component: `ST_BlackMarket` / `Thief.Chameleon.Title` = `The Chameleon`. |
| 501 | `BACK [ESC]` | button | no | none | 'Back' authored Screen.Back; key prefix unwired. |
| 636 | `Edit Loadout` | heading | no | `ST_ThievesDen` / `Wardrobe.Loadout` = `Edit Loadout` (exact) | Authored Wardrobe.Loadout exact. |
| 644 | `LOADOUT SLOTS` | heading | no | none | Not authored; ST_Settings has 'Tool Slots'. Component: `ST_Screens` / `Screen.Loadout` = `Loadout`. |
| 664 | `Select a loadout slot to equip or swap out tools` | hint | no | `ST_ThievesDen` / `Wardrobe.SelectLoadout` = `Select a loadout slot to equip or swap out tools` (exact) | Authored Wardrobe.SelectLoadout exact. |
| 728 | `WARDROBE — DRAG TO ROTATE` | heading | no | none | Assembled, not authored. Component: `ST_ThievesDen` / `Wardrobe.Header` = `Wardrobe`. |
| 765 | `CUSTOMIZATION` | heading | no | none | Not authored. Component: `ST_BlackMarket` / `Category.Customizations` = `Customizations`. |
| 773 | `Head` | heading | no | `ST_ThievesDen` / `Wardrobe.OutfitHead` = `Head` (exact) | Authored Wardrobe.OutfitHead exact. |
| 785 | `Body` | heading | no | `ST_ThievesDen` / `Wardrobe.OutfitBody` = `Body` (exact) | Authored Wardrobe.OutfitBody exact. |
| 794 | `Calling Card` | heading | no | `ST_ThievesDen` / `Wardrobe.OutfitCallingCard` = `Calling Card` (exact) | Authored Wardrobe.OutfitCallingCard exact. |
| 1017 | `The Chameleon is locked. Unlock it in the Black Market (£10,000, Contract 3).` | hint | no | none | Component: `ST_BlackMarket` / `Thief.Chameleon.Title` = `The Chameleon`. |
| 1043 | `Signature Tools cannot be swapped out` | hint | no | `ST_ThievesDen` / `Wardrobe.DeclinePrimarySwap` = `Signature Tools cannot be swapped out` (exact) | Authored Wardrobe.DeclinePrimarySwap exact. |
| 1060 | `Signature Tools cannot be swapped out` | hint | no | `ST_ThievesDen` / `Wardrobe.DeclinePrimarySwap` = `Signature Tools cannot be swapped out` (exact) |  |
| 1065 | `Locked - %s` | hint | no | none | Not authored. Component: `ST_BlackMarket` / `Availability.Locked` = `Locked`. |
| 1065 | `Locked - not owned` | hint | no | none | Not authored. Component: `ST_BlackMarket` / `Availability.Locked` = `Locked`. |
| 1146 | `Empty slot` | label | no | none | Not authored. |
| 1150 | `Select a tool below to fill this slot` | label | no | none | Not authored. |
| 1154 | `Locked - %s` | label | no | none | Not authored. Component: `ST_BlackMarket` / `Availability.Locked` = `Locked`. |
| 1154 | `Locked - not owned` | label | no | none | Not authored. Component: `ST_BlackMarket` / `Availability.Locked` = `Locked`. |
| 1207 | ` · Lv ` | label | no | none | Tool level suffix. |
| 1537 | `Body: ` | label | no | none | Outfit description prefix. |
| 1539 | `Head: ` | label | no | none | Outfit description prefix. |
| 1541 | `Calling Card: ` | label | no | none | Outfit description prefix. |
| 1543 | `No outfits found for this thief.` | label | no | none | Not authored. |
| 1613 | `(None)` | label | no | none | Not authored. |
| 1734 | `Default` | label | no | none | Only unrelated AudioSettings.DefaultSettingsName in sources.json. |

### `game/src/ui/contract_table_ui.gd`

| Line | Literal | Kind | Routed | Authored counterpart | Notes |
|---:|---|---|---|---|---|
| 141 | `MAP TABLE — CONTRACT SELECTOR` | title | no | none | Assembled Map Table title; not authored. Component: `ST_MapTool` / `Legend.Contract` = `Contract`. |
| 206 | `Difficulty:` | label | no | `ST_ThievesDen` / `CityMap.DifficultyHeader` = `Difficulty:` (exact) | Authored CityMap.DifficultyHeader exact. |
| 211 | `Novice (1)` | option | no | none | Authored 'Novice' + port index suffix. Component: `ST_GeneralUI` / `Mission.Difficulty.Easy` = `Novice`. |
| 212 | `Thief (2)` | option | no | none |  |
| 213 | `Master Thief (3)` | option | no | none | Component: `ST_GeneralUI` / `Mission.Difficulty.Hard` = `Master Thief`. |
| 222 | `Host Co-op` | button | no | none | Prefix of ST_ListenServers HostGamePrivate/Public rows; not wired. |
| 234 | `Join Co-op` | button | no | none | No authored row. |
| 239 | `Solo Mode` | label | no | none | ST_GeneralUI Mission.Mode.Offline is 'Solo'; 'Solo Mode' is port copy. |
| 252 | `FREE PLAY: GUILDHALL CLEANOUT [G]` | button | no | none | Port-authored free-play entry. |
| 258 | `DEPLOY CONTRACT` | button | no | none | Not authored. Component: `ST_MapTool` / `Legend.Contract` = `Contract`. |
| 264 | `CLOSE [ESC]` | button | no | none | 'Close' authored PromptClose; key prefix unwired. |
| 328 | `Target: %s\nLocation: %s\n%s` | label | no | none | 'Target'/'Location' labels are port copy. |
| 329 | `• Reconnoiter the landmark for clues.` | label | no | none | Port-authored default intel line. |
| 336 | `Intel:\n` | label | no | none | Port-authored intel header. |
| 398 | `Hosting co-op` | label | no | none | Port-authored host status. |
| 401 | `Host failed: %d` | label | no | none | Port-authored host error. Component: `ST_Screens` / `Screen.MissionLobby.Matchmaking.Status.Failed` = `Failed`. |
| 416 | `Connecting to ` | label | no | none | Port-authored join status. |
| 419 | `Join failed: %d` | label | no | none | Port-authored join error. Component: `ST_Screens` / `Screen.MissionLobby.Matchmaking.Status.Failed` = `Failed`. |
| 442 | `Join Mission with these settings?\nDifficulty: %s\nMode: %s` | confirm | no | `ST_ThievesDen` / `CityMap.ConfirmJoinLobby` = `Join Mission with these settings?\nDifficulty: {difficulty}\nMode: {mo` (placeholder/whitespace-normalised) | Authored CityMap.ConfirmJoinLobby (CRLF/placeholder variant); not wired. |
| 498 | `[H] Difficulty toggle   ·   [R] Mode toggle   ·   [SPACE/F] PREPARE` | prompt | no | none | Port-authored controls hint. Component: `ST_BlackMarket` / `Category.Difficulty` = `Difficulty`. |
| 508 | `[SPACE] PREPARE FOR MISSION` | button | no | none | Port-authored confirm action. Component: `ST_ThievesDen` / `CityMap.JoinLobby` = `Prepare for Mission`. |
| 514 | `[ESC] CANCEL` | button | no | none | 'Cancel' authored Tools_Disguise_Cancel; not wired. Component: `ST_Tools` / `Tools_Disguise_Cancel` = `Cancel`. |
| 540 | `Co-op Mode (pending host/join)` | label | no | none | Port-authored pending co-op status. |
| 540 | `Solo Mode` | label | no | none | Port-authored pending co-op status. |

### `game/src/ui/mission_prep_ui.gd`

| Line | Literal | Kind | Routed | Authored counterpart | Notes |
|---:|---|---|---|---|---|
| 29 | `ELWAY MANOR` | label | no | `ST_OldManor_map` / `OldManor.MapName` = `Elway Manor` (case-normalised) | Authored ST_OldManor_map OldManor.MapName (case-normalised). |
| 30 | `This is the estate of the three Elway sisters. Although it has fallen into disre` | label | no | `ST_OldManor_map` / `OldManor.MapFlavorText` = `This is the estate of the three Elway sisters. Although it has fallen ` (exact) | Authored ST_OldManor_map OldManor.MapFlavorText exact. |
| 31 | `CONSTABLES' GUILDHALL` | label | no | `ST_MapTool` / `Guildhall.MapName` = `Constables' Guildhall` (case-normalised) | Authored ST_MapTool Guildhall.MapName (case-normalised). |
| 32 | `This is the headquarters and operational base for the Constables, Kilcairn's pol` | label | no | `ST_MapTool` / `Guildhall.MapFlavorText` = `This is the headquarters and operational base for the Constables, Kilc` (placeholder/whitespace-normalised) | Authored ST_MapTool Guildhall.MapFlavorText (trailing-space variant). |
| 33 | `Contract Inactive` | label | yes | `ST_Screens` / `Screen.MissionLobby.ContractInactive` = `Contract Inactive` (exact) | Routed via _loc(CONTRACT_INACTIVE). |
| 449 | `MISSION STARTING IN 5...` | countdown | no | `ST_Screens` / `Screen.MissionLobby.Countdown` = `Mission Starting in <Num>{number}</>...` (staged) | Initial placeholder overwritten by routed Countdown; authored template with {number}. |
| 468 | `Mode: Solo` | label | no | `ST_Screens` / `Screen.MissionLobby.Mode` = `Mode: {mode}` (staged) | Initial placeholder overwritten by routed Mode template. |
| 478 | `Difficulty: Novice` | label | no | `ST_Screens` / `Screen.MissionLobby.Difficulty` = `Difficulty: {difficulty}` (staged) | Initial placeholder overwritten by routed Difficulty template. |
| 494 | `LOCATION` | card-header | no | none | Location card header; no authored exact row. Component: `ST_Social` / `Ping.LocationCompromised_02` = `Location Compromised`. |
| 526 | `MISSION` | card-header | no | `ST_PostMatch` / `PostMatch.Mission` = `Mission` (case-normalised) | 'Mission' authored PostMatch.Mission (case-normalised). |
| 557 | `CONTRACT` | card-header | no | `ST_MapTool` / `Legend.Contract` = `Contract` (case-normalised) | 'Contract' authored PostMatch.Contract / Legend.Contract (case-normalised). |
| 574 | `READY` | label | no | `ST_Screens` / `Screen.Lobby.Ready` = `Ready` (case-normalised) | Initial placeholder overwritten by routed UIStrings Ready. |
| 614 | `[F]  READY` | button | no | none | Initial button overwritten by '[F]  %s'; 'Ready' authored. |
| 621 | `[ESC]  BACK` | button | no | none | Initial button overwritten by '[F]  %s'; 'Back' authored. |
| 1359 | `A glittering jewelry house and private gallery in Kilcairn's merchant quarter, h` | label | no | none | TAT-2 expansion map name/description; not in shipped tables. Component: `ST_OldManor_map` / `OldManor.Gallery` = `Gallery`. |
| 1359 | `JASPERING HALL` | label | no | none | TAT-2 expansion map name/description; not in shipped tables. |
| 1364 | `A shadowed mark in Kilcairn, ripe for the taking.` | label | no | none | Port-authored unknown-map description. |
| 1374 | `Cleanout Heist` | label | no | `ST_Screens` / `Screen.MissionLobby.OldManor.LootTheRoomTitle` = `Cleanout Heist` (exact) | Mission title set; all three authored in ST_Screens. |
| 1374 | `Item Collection Heist` | label | no | `ST_Screens` / `Screen.MissionLobby.SetQuestTitle` = `Item Collection Heist` (exact) | Mission title set; all three authored in ST_Screens. |
| 1374 | `Vault Heist` | label | no | `ST_Screens` / `Screen.MissionLobby.VaultQuestTitle` = `Vault Heist` (exact) | Mission title set; all three authored in ST_Screens. |
| 1378 | `\nTime Limit: %d minutes` | label | no | `ST_Screens` / `Screen.MissionLobby.TimeLimit` = `Time Limit: {matchDurationInMinutes} minutes` (placeholder/whitespace-normalised) | Authored Screen.MissionLobby.TimeLimit uses {matchDurationInMinutes}. |
| 1396 | `\nTime Limit: %d minutes` | label | no | `ST_Screens` / `Screen.MissionLobby.TimeLimit` = `Time Limit: {matchDurationInMinutes} minutes` (placeholder/whitespace-normalised) | Authored Screen.MissionLobby.TimeLimit (duplicate path). |
| 1398 | `\nTime Limit: Unlimited` | label | no | none | No authored unlimited-time row. Component: `ST_Settings` / `Settings.FPSLimit.Unlimited` = `Unlimited`. |
| 1446 | `A rare bust called the Warburg Effigy is being held at the Guildhall for safekee` | label | yes | `ST_Screens` / `Screen.MissionLobby.VaultQuestDescription` = `A rare bust called the Warburg Effigy is being held at the Guildhall f` (exact) | Routed UIStrings row; literal is the fallback duplicate. |
| 1446 | `The Claymur Urns have been held by the Elway family for centuries. The Guild wil` | label | yes | `ST_Screens` / `Screen.MissionLobby.Oldmanor.SetQuestDescription` = `The Claymur Urns have been held by the Elway family for centuries. The` (staged) | Routed UIStrings row; literal is the fallback duplicate. |
| 1446 | `The Constables' Guildhall is full of confiscated treasures. Infiltrate the build` | label | yes | `ST_Screens` / `Screen.MissionLobby.GuildHall.LootTheRoomDescription` = `The Constables' Guildhall is full of confiscated treasures. Infiltrate` (exact) | Routed UIStrings row; literal is the fallback duplicate. |
| 1446 | `The Elway family has a magical tome they keep under the utmost protection in a v` | label | yes | `ST_Screens` / `Screen.MissionLobby.Oldmanor.VaultQuestDescription` = `The Elway family has a magical tome they keep under the utmost protect` (exact) | Routed UIStrings row; literal is the fallback duplicate. |
| 1446 | `The precious gems needed to restore an artifact are hidden among the trinkets ga` | label | yes | `ST_Screens` / `Screen.MissionLobby.SetQuestDescription` = `The precious gems needed to restore an artifact are hidden among the t` (exact) | Routed UIStrings row; literal is the fallback duplicate. |
| 1446 | `Though both the Elway family and their estate are a shadow of what they once wer` | label | yes | `ST_Screens` / `Screen.MissionLobby.OldManor.LootTheRoomDescription` = `Though both the Elway family and their estate are a shadow of what the` (exact) | Routed UIStrings row; literal is the fallback duplicate. |
| 1459 | `Free play: clean out the location for a score. No contract progress is recorded.` | label | no | none | Free-play body is port copy; title CONTRACT_INACTIVE is routed. Component: `ST_PostMatch` / `XP.Breakdown.Contract.NoContract` = `No Contract`. |
| 1461 | `Your active contract is not available for the currently selected map.` | label | yes | `ST_Screens` / `Screen.MissionLobby.ContractWrongMap` = `Your active contract is not available for the currently selected map.` (exact) | Routed UIStrings row; literal is the fallback duplicate. |
| 1470 | `Active contract: %s` | label | no | none | Contract card body prefix; port copy. |
| 1472 | `\nTarget: %s` | label | no | none | Contract card target line; port copy. |
| 1480 | `Mode: {mode}` | label | yes | `ST_Screens` / `Screen.MissionLobby.Mode` = `Mode: {mode}` (exact) | Routed UIStrings row; {mode} substituted. |
| 1483 | `Difficulty: {difficulty}` | label | yes | `ST_Screens` / `Screen.MissionLobby.Difficulty` = `Difficulty: {difficulty}` (exact) | Routed UIStrings row; {difficulty} substituted. |
| 1498 | `Ready` | label | yes | `ST_Screens` / `Screen.Lobby.Ready` = `Ready` (exact) | Routed UIStrings row. |
| 1499 | `Unready` | label | yes | `ST_Screens` / `Screen.Lobby.Unready` = `Unready` (exact) | Routed UIStrings row. |
| 1505 | `[F] %s  ·  [ESC] BACK` | prompt | no | none | Authored action word + port keycap glue. |
| 1515 | `Mission Starting in <Num>{number}</>...` | countdown | yes | `ST_Screens` / `Screen.MissionLobby.Countdown` = `Mission Starting in <Num>{number}</>...` (exact) | Routed UIStrings row; markup stripped and {number} substituted. |
| 1541 | `Novice` | label | yes | `ST_GeneralUI` / `Mission.Difficulty.Easy` = `Novice` (exact) | Routed via _loc -> UIStrings.t -> Loc. |
| 1543 | `Thief` | label | yes | `ST_GeneralUI` / `Mission.Difficulty.Normal` = `Thief` (exact) | Routed via _loc -> UIStrings.t -> Loc. |
| 1544 | `Master Thief` | label | yes | `ST_GeneralUI` / `Mission.Difficulty.Hard` = `Master Thief` (exact) | Routed via _loc -> UIStrings.t -> Loc. |

### `game/src/ui/loading_screen.gd`

| Line | Literal | Kind | Routed | Authored counterpart | Notes |
|---:|---|---|---|---|---|
| 130 | `LOADING...` | title | no | `ST_GeneralUI` / `Loading` = `Loading...` (case-normalised) | Authored ST_GeneralUI Loading exact (case-normalised) but unwired. |
| 211 | `Preparing sublevels...` | status | no | none | Port-authored loading status. |
| 224 | `Unlocking the doors...` | status | no | none | Port-authored loading status. |
| 226 | `Raising the rooftops...` | status | no | none | Port-authored loading status. |
| 228 | `Lighting the lanterns...` | status | no | none | Port-authored loading status. |
| 236 | `Ready.` | status | no | none | Contains authored 'Ready' but punctuation/context differs. |

### `game/src/ui/mobile_touch_ui.gd`

| Line | Literal | Kind | Routed | Authored counterpart | Notes |
|---:|---|---|---|---|---|
| 106 | `HIT` | button | no | none | Touch button label. |
| 107 | `JUMP` | button | no | `ST_Settings` / `Settings.Controls.Jump` = `Jump` (case-normalised) | Authored Settings.Controls.Jump (case-normalised). |
| 109 | `USE` | button | no | `ST_Tools` / `Tools_Deploy_Generic_Use` = `Use` (case-normalised) | Authored Tools_Deploy_Generic_Use 'Use' (case-normalised). |
| 110 | `SKILL` | button | no | none | Not authored. |
| 112 | `SAP` | button | no | none | Not authored. |
| 113 | `SMOKE` | button | no | none | Prefix of authored 'Smoke Bomb' but not exact. |
| 114 | `FAIRY` | button | no | none | Contained in authored 'Pickpocket Fairy' but not exact. |
| 115 | `EYE` | button | no | none | Not authored. Component: `ST_BlackMarket` / `Outfit.Chameleon.Head.EyepatchABeardA.Title` = `Eyepatch with beard`. |
| 117 | `CROUCH` | button | no | `ST_Settings_Input` / `InputSetting.Movement.Crouch` = `Crouch` (case-normalised) | Authored InputSetting.Movement.Crouch (case-normalised). |
| 118 | `SPRINT` | button | no | `ST_Settings` / `Settings.Controls.KBM.Sprint` = `Sprint` (case-normalised) | Authored Settings.Controls.KBM.Sprint (case-normalised). |
| 119 | `LEAN L` | button | no | none | Prefix of authored 'Lean' but not exact. |
| 120 | `LEAN R` | button | no | none | Prefix of authored 'Lean' but not exact. |
| 122 | `II` | button | no | none | Pause glyph label; not authored. |
| 548 | `WIRE` | button | no | none | Runtime ability label for spider; not authored. |
| 550 | `MASK` | button | no | none | Runtime ability label for chameleon; only unrelated Nanite 'Mask' in sources.json. |
| 552 | `ASTRAL` | button | no | none | Runtime ability label for moth; not authored. |
| 554 | `SKILL` | button | no | none | Runtime ability label fallback; not authored. |

### `game/src/ui/review_mode.gd`

| Line | Literal | Kind | Routed | Authored counterpart | Notes |
|---:|---|---|---|---|---|
| 50 | `Periphery/POI/Gameplay/Lighting/Decals/Collision/Niagara/Beams/World labels/Emis` | label | no | none | NUMBER_TOGGLES (10 developer toggle names). Component: `ST_Settings` / `Settings.Gameplay` = `Gameplay`. |
| 125 | `No sublevels resolved for map '%s'.` | status | no | none | Review tool (developer-only). |
| 128 | `Loading %d sublevels through LevelLoader...` | status | no | none |  |
| 145 | `Missing sublevel: %s` | status | no | none |  |
| 150 | `No readable sublevels for map '%s'.` | status | no | none |  |
| 159 | `Loading %d sublevels in one LevelLoader call...` | status | no | none |  |
| 245 | `Bookmark F%d: %s` | status | no | none |  |
| 364 | `Capture failed (empty image).` | status | no | none | Component: `ST_Screens` / `Screen.MissionLobby.Matchmaking.Status.Failed` = `Failed`. |
| 369 | `Saved %s (err=%d, review-only)` | status | no | none |  |
| 431 | `WASD move  LMB mouse  Shift fast  Q/E down/up  1-0 toggles  H hidden-in-game  F1` | hint | no | none | Review HUD controls hint (developer-only). Component: `ST_Interactable_Props` / `PromptToggle` = `Toggle`. |
| 452 | `TAT-2 review  \|  map=%s  \|  %s` | title | no | none | Review HUD state words (developer-only). |
| 452 | `loading...` | status | no | `ST_GeneralUI` / `Loading` = `Loading...` (case-normalised) | Review HUD state words (developer-only). |
| 452 | `ready` | status | no | `ST_Screens` / `Screen.Lobby.Ready` = `Ready` (case-normalised) | Review HUD state words (developer-only). |
| 459 | `none` | label | no | none | Review environment label; 'none' is generic and only spuriously matches a sources value. |
| 459 | `review-only` | label | no | none | Review environment label; 'none' is generic and only spuriously matches a sources value. |
| 462 | ` (preset=%s)` | label | no | none |  |
| 463 | `sublevels=%d  nodes=%d  draws=%d  instances=%d  lights=%d  surfaces=%d\nhidden: ` | label | no | none | Review HUD statistics block (developer-only). |
| 490 | `(none)` | label | no | none | Review toggle summary (developer-only). |
| 490 | `on:  %s\noff: %s` | label | no | none | Review toggle summary (developer-only). |

### `game/src/missions/mission_controller.gd`

| Line | Literal | Kind | Routed | Authored counterpart | Notes |
|---:|---|---|---|---|---|
| 96 | `TIME EXPIRED` | status | no | none | Stored in contract_info['timeout_reason']; no consumer in game/src (not rendered). |
| 97 | `MAGIC DOOR COLLAPSED` | status | no | none | Stored in contract_info['timeout_reason']; not rendered. |
| 656 | `Contract` | objective | no | `ST_MapTool` / `Legend.Contract` = `Contract` (exact) | Mission/briefing title fallback. |
| 670 | `Contract` | label | no | `ST_MapTool` / `Legend.Contract` = `Contract` (exact) | Loading title fallback. |
| 690 | `Loading sublevels...` | status | no | none | Passed to LoadingScreen.set_progress, whose _status_text parameter is ignored (not visible). |
| 1228 | `[F] ENTER MATCH` | prompt | no | none | Den map-table prompt (embedded GDScript). |
| 1265 | `[F] READ LEDGER` | prompt | no | none | Den ledger prompt. Component: `ST_ThievesDen` / `Ledger.Interact` = `Read Ledger`. |
| 1296 | `[F] EXIT` | prompt | no | none | Telescope ponder-mode prompt; 'Exit' authored PromptHidingSpotExit. |
| 1297 | `[F] PONDER` | prompt | no | none | Telescope prompt; 'Ponder' authored PromptLookAtHubSecret. Component: `ST_Interactables` / `PromptLookAtHubSecret` = `Ponder`. |
| 1348 | `[F] CUSTOMIZE LOADOUT` | prompt | no | none | Den wardrobe prompt. Component: `ST_Screens` / `Screen.Loadout` = `Loadout`. |
| 2478 | `KILCAIRN SKYLINE` | title | no | none | Telescope card title; not authored. |
| 2479 | `EXIT` | prompt | no | `ST_Interactables` / `PromptHidingSpotExit` = `Exit` (case-normalised) | Telescope card prompt; 'Exit' authored. |
| 2480 | `EXIT` | label | no | `ST_Interactables` / `PromptHidingSpotExit` = `Exit` (case-normalised) | Telescope card bottom hint. |
| 2511 | `CONSTABLES' GUILDHALL` | title | no | `ST_Screens` / `Screen.MissionLobby.RandomQuestLocation` = `Constables' Guildhall` (case-normalised) | Den map-table token title(s). |
| 2511 | `ELWAY MANOR` | title | no | `ST_ThievesDen` / `CityMap.OldManor` = `Elway Manor` (case-normalised) | Den map-table token title(s). |
| 2511 | `JASPERING HALL` | title | no | none | Den map-table token title(s). |
| 2519 | `Prepare for Mission` | prompt | no | `ST_ThievesDen` / `CityMap.JoinLobby` = `Prepare for Mission` (exact) | Authored CityMap.JoinLobby exact. |
| 2521 | `Difficulty: %s` | label | no | `ST_Screens` / `Screen.MissionLobby.Difficulty` = `Difficulty: {difficulty}` (placeholder/whitespace-normalised) | Authored Mode/Difficulty templates; not wired. |
| 2522 | `Mode: %s` | label | no | `ST_Screens` / `Screen.MissionLobby.Mode` = `Mode: {mode}` (placeholder/whitespace-normalised) |  |
| 2523 | `Prepare for Mission` | label | no | `ST_ThievesDen` / `CityMap.JoinLobby` = `Prepare for Mission` (exact) |  |
| 2534 | `TELESCOPE` | title | no | none | Telescope card title; not authored. |
| 2535 | `PONDER` | prompt | no | `ST_Interactables` / `PromptLookAtHubSecret` = `Ponder` (case-normalised) | Telescope card prompt; authored 'Ponder'. |
| 2536 | `PONDER` | label | no | `ST_Interactables` / `PromptLookAtHubSecret` = `Ponder` (case-normalised) |  |
| 2616 | `[F] CHANGE DECORATION` | prompt | no | none | Decoration pedestal prompt. |
| 2668 | `[F] TURN OFF` | prompt | no | none | Gramophone prompts; authored Turn Off/Turn On. Component: `ST_Interactables` / `PromptTurnOff` = `Turn Off`. |
| 2668 | `[F] TURN ON` | prompt | no | none | Gramophone prompts; authored Turn Off/Turn On. Component: `ST_Interactables` / `PromptTurnOn` = `Turn On`. |
| 2837 | `Steal %s in loot value` | objective | no | `sources.json` / `ST_Quests.LootValueObjective.Default` = `Steal {Amount} in loot value` (placeholder/whitespace-normalised) | Free-play objective label; authored sources.json. |
| 2874 | `Steal the %s` | objective | no | none | Contract objective label; no exact authored template. |
| 2881 | `Steal the %s` | objective | no | none |  |
| 2950 | `Esteemed Colleague — Infiltrate the target site, secure the objective, and slip ` | letter | no | none | Mission-letter fallback body; port-authored. |
| 3178 | `Read` | prompt-verb | no | `ST_Interactables` / `PromptRead` = `Read` (exact) | Prompt verb set on spawned clues; authored PromptRead exact. |
| 3708 | `Vault Key` | label | no | `sources.json` / `17C527AE4CF0F1D3E991BEB4EC7D02F2` = `Vault Key` (exact) | Guard-carried key display name; authored sources.json. |
| 3712 | `Guildhall Key` | label | no | `sources.json` / `05C7F6C4444DF32070196ABE94425CD7` = `Guildhall Key` (exact) | Guard-carried key display name; authored sources.json. |
| 3715 | `Elway Manor Key` | label | no | `sources.json` / `B847A1B24015CF72A6DFD8AF63B85205` = `Elway Manor Key` (exact) | Guard-carried key display name; authored sources.json. |
| 4572 | `THE MAGIC DOOR HAS BEEN SUMMONED` | toast | no | none | Endgame summon toast; no authored row. |

### `game/src/interact/loot_container.gd`

| Line | Literal | Kind | Routed | Authored counterpart | Notes |
|---:|---|---|---|---|---|
| 304 | `[Opened]` | prompt | no | none | Container prompt; not authored. |
| 307 | `[Picking Lock...]` | prompt | no | none | Container prompt; not authored. |
| 308 | `[F] PICK LOCK (Lv %d)` | prompt | no | none | Container prompt; not authored. Component: `ST_Lockpicking` / `Lockpicking.Pompt.Start` = `Pick Lock`. |
| 309 | `[F] OPEN` | prompt | no | none | 'Open' authored PromptOpen; key prefix/upper-case composition unwired. |
| 350 | `Display Safe` | label | no | none | Lockpick target label; not authored. Component: `ST_Settings` / `Settings.Display` = `Display`. |
| 352 | `Locked Chest` | label | no | none | Lockpick target label; not authored. Component: `ST_BlackMarket` / `Availability.Locked` = `Locked`. |
| 353 | `Safe Lock` | label | no | none | Lockpick target label; not authored. |
| 468 | `Noble Relic` | label | no | none | Loot name fallback; not authored. |
| 479 | `Noble Relic #%d` | label | no | none | Loot name fallback; not authored. |

### `game/src/interact/loot_item.gd`

| Line | Literal | Kind | Routed | Authored counterpart | Notes |
|---:|---|---|---|---|---|
| 4 | `Silver Candlestick` | label | no | none | Default item_name; not authored. |

### `game/src/interact/clue_item.gd`

| Line | Literal | Kind | Routed | Authored counterpart | Notes |
|---:|---|---|---|---|---|
| 8 | `Contract Clue` | label | no | none | Default clue_title; not authored. Component: `ST_MapTool` / `Legend.Contract` = `Contract`. |
| 9 | HUD / map | `game/src/ui/hud.gd:3345` | `WAYPOINT` | none | Player-placed map ping label; no authored row. |
| 126 | `[E] Read Clue: ` | prompt | no | none | 'Read Clue' authored PromptReadClue; prefix not wired. |

## 9. Excluded / out-of-scope visible strings (not counted)

- Pure numeric/currency/symbol glue: `%d`, `%d%%`, `x%.1f`, `(£)`, `(£) 0`, `(£) %d`, `(£) %d / £ %d`, `∞`, `0`, `1`, `↺`, `✓`, `❧`, `  (%s)`, `%s   £ %d`, `  ·  `, ` *`, `[`, `]`, `...`.
- Single-letter input glyph labels: `< Q`, `E >` (wardrobe prev/next), `H`/`R`/`F` keycaps, `F` prompt keycap.
- Empty strings (`""`) used to clear labels.
- `Label3D` world labels (not Controls): `loot_item.gd:212` (`label.text = display_name/item_name`), `clue_item.gd:74` (`label.text = clue_title`).
- Out-of-scope adjacent visible strings (would raise the total if included): `thief_character.gd` prompts (`[E] Steal %s`, `[E] Interact`, `[E] Steal Guard Disguise`, `[F] [HOLD] TAKEDOWN`), `loot_inventory.gd prompt_for` (`[E] Take %s`, `[E] Steal %s`), `loot_stash.gd` `[F] %s` wrappers, `game_state.gd difficulty_label()` (`Novice`/`Thief`/`Master Thief`), `unlock_catalog.gd` catalog strings (authored JSON), `localization.gd` language labels (`English`, `Deutsch`, ...).
- `art_nouveau_theme.gd` has no literal display strings; it is the sink that renders caller text (`make_modal`, `group_card`, `keycap`, `prompt_label`).

## 10. Caveats that affect the DoD reading

- `settings_ui.gd` is **not** Loc-routed. 24 authored `ST_Settings` labels bypass Loc, and 3 keys do not exist (`AmbienceVolume`, `UIVolume`, `DesktopQuality`) so the hardcoded fallback is displayed. This is the single biggest "looks authored but is not routed" pocket.
- `_label` fallbacks `RESET DEFAULTS` / `APPLY & BACK` are never displayed when the table loads; the displayed text is `REVERT CHANGES` / `APPLY CHANGES`. The hardcoded literals still exist in code and inflate a raw literal count.
- `Loc.t` only translates strings present in `sources.json`; unknown invented strings pass through unchanged. Routing them through Loc improves the "wrapped" metric but not actual translation coverage.
- `mission_prep_ui.gd` initial placeholders (`MISSION STARTING IN 5...`, `Mode: Solo`, `Difficulty: Novice`, `READY`, `[F] READY`, `[ESC] BACK`) are overwritten by the routed refresh in `_ready()`. They are counted because they are assigned to Controls, but they are transient.
- `mission_controller.gd:690` passes `Loading sublevels...` to `LoadingScreen.set_progress`, whose `_status_text` parameter is ignored; it is not visible.
- `mission_controller.gd:96/97` (`TIME EXPIRED`, `MAGIC DOOR COLLAPSED`) are stored in `contract_info["timeout_reason"]` but no consumer in `game/src` renders them; they are not visible today.
- `review_mode.gd` and the F3 FPS overlay are developer-only; the player-facing split in §4 excludes 20 rows.
- Some auto-matches are weak: `Level %d` -> sources.json `Level {CurrentLevel}`; `Default` -> `AudioSettings.DefaultSettingsName` (cleared as invented); `MASK` -> Nanite `Mask` (cleared); `none` -> a generic sources value (cleared).

*Generated from the tree by the W9-P3 string audit lane. No source file was modified.*