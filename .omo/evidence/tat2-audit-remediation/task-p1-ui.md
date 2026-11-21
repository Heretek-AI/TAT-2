# UI P1 remediation — all 4 audit P1s fixed with proof (task-p1-ui)

Date (UTC): 2026-11-20. Ground truth: `.omo/waves/codebase-gameplay-audit/AUDIT.md`
§3 (UI: 4 items) + `audit-ui.md` §§1,9,10,11 (P1-1..P1-4), plus
`.omo/evidence/tat2-playtest-ground-truth-fixes/task-6.log` §§2,5.6 (price
provenance: 4 KF08-visible prices, no cooked price table). Scope: edits limited
to `game/src/ui/*` (art_nouveau_theme, ledger, settings, mobile_touch,
main_menu) + this ledger. `make test` NOT run (orchestrator settles at wave
level); VERIFY here is file-level re-read + headless GDScript parse gate
(flatpak Godot 4.7.2) + structural token/price counts.

## Design-system analysis (mandate Phase 1 — done before any edit)

Read first: `art_nouveau_theme.gd` in full (token inventory: TEAL×12,
GOLD×3, IVORY, PANEL_BG, DIM_COLOR, PROMPT_TEAL, KEYCAP_*×2; font loaders with
cache; builders panel/teal_panel/teal_card/inner_line/style_button/
style_teal_button/style_teal_tab/style_teal_option/section_header/divider/
keycap/white_keycap/prompt_label/filigree/make_modal) plus all 10 UI screens
via audit-ui §§2-10. Naming: `ThemeScript` preload alias in screen files,
`UPPER_SNAKE` color consts, `style_*`/`teal_*` static builders returning
`StyleBoxFlat`/controls, `MouseFilter.IGNORE` on chrome. Spacing: builder
margins + `separation` constants (no Tailwind — GDScript theme overrides).
Composition: panel → margin/vbox → header/divider/rows; tabs via
`style_teal_tab` + disabled-active pattern (`_show_tab` disables active tab).
Verdict: coherent system exists — extend it, don't fork it. Two gaps found and
closed in-theme (TOUCH_* tokens, `group_card` builder); pink/green status
tokens stay HARD_LIMIT 5.7 (P2-1, not this pass).

## P1-1 — Ledger placeholder prices → 4 KF08 values bound, rest explicit TBD

BEFORE: `ledger_ui.gd` TOOLS (1500/800/2000/2000/1200), PERKS
(0/3000/6000/2500/2500/4000/4000), SPIDER/CHAMELEON cosmetics
(500/750/1200/400/600/350/900/1100/450, …) — all invented, shippable as false
parity (audit-ui P1-1; task-6 §2 row 13: "MUST NOT ship as parity").
`_item_button_text` rendered bare `(£ %d)`; `_refresh_preview` bare `£ %d`;
`_on_buy_pressed` silent on empty selection.

AFTER (`game/src/ui/ledger_ui.gd` only):
- Provenance block (lines ~13-29): `PRICE_SOURCE_ST` =
  `res://data/generated/tables/StringTables/ST_BlackMarket.json` (re-read this
  turn: entries hold Category/Difficulty/Gear/Map/Thief/Outfit/CallingCard/
  Availability/Purchase strings — ZERO price keys), `PRICE_SOURCE_KF` = KF08
  frame: Bob 7500 / Mustache 5000 / Full Beard 7500 / Eyepatch 2500.
- 4 KF08 prices bound in BOTH cosmetic arrays (were 500/400/600/450):
  `bob_hair` 7500, `mustache` 5000, `full_beard` 7500, `eyepatch` 2500, each
  with `KF08 verified` inline cite. Cost-0 rows (`novice_difficulty`, `no_hat`)
  documented as verified-free. Every other cost keeps its number but carries a
  `TBD PRICE — DO NOT SHIP AS PARITY` comment (TOOLS/PERKS array headers +
  per-row on cosmetics; 20 TBD mentions in file).
- Runtime sentinels (never silent): `_is_price_verified()` (cost==0 or id in
  `VERIFIED_PRICE_IDS`); `_item_button_text` renders `(%d · TBD)` for
  unverified; `_refresh_preview` shows `£ %d · TBD PRICE — DO NOT SHIP` +
  `_log_tbd_price` push_warning with ST path + KF cite; `_on_buy_pressed`
  push_errors on TBD purchase (sale proceeds as debug-only) and asserts on
  empty selection; `_ready` prints the provenance + asserts the theme.
- Proof: `grep -c VERIFIED_PRICE_IDS` = 2 (def + use); `grep -c TBD` = 20;
  `bob_hair/mustache/full_beard/eyepatch` costs re-read as 7500/5000/7500/2500
  in both arrays. Full price table still has no cooked source (HARD_LIMIT 5.6
  stands) — that is why TBD is explicit, not invented.

## P1-2 — Settings design-system duplication removed

BEFORE: local `TEAL_PANEL_BG/GROUP_BG/BORDER/ACCENT/TEXT` consts
(`settings_ui.gd:14-18`, values drifted from theme, e.g. PANEL 0.035/0.085/0.105
vs theme 0.032/0.072/0.092), local `_style_teal_tab` (radius 5 vs theme 4, no
disabled-stylebox handling), local `_make_group_card` paralleling
`teal_card_style`; 8 bare `TEAL_*` uses across binding/slider/check rows.

AFTER (`game/src/ui/settings_ui.gd` + theme builder):
- Local consts deleted (replaced by 3-line P1-dedup comment); `_style_teal_tab`
  deleted entirely — both call sites (`_refresh_tabs`, tab-row build) now call
  `ThemeScript.style_teal_tab`.
- `_make_group_card` reduced to a forwarder: validates non-empty title
  (push_error + assert, no blank cards), delegates to new
  `ThemeScript.group_card()`, appends to `_group_cards` (test hook kept:
  run_tests.gd 35b requires ≥ 6; all 6 groups still register).
- All rows route through `ThemeScript.TEAL_*` (binding label, slider
  label/grab/value, check text, modal panel + title).
- `_load_string_table` no longer silently returns: push_error naming
  `ST_Settings.json` when the cooked table is absent; `_ready` prints
  theme + strings provenance and asserts the theme.
- Proof: `grep -n '[^.]TEAL_'` returns only the dedup comment + one
  `ThemeScript.TEAL_PANEL_BG` use; `_style_teal_tab` has zero definitions and
  zero callers; theme `group_card`/`style_teal_tab` both present
  (`grep -c 'static func group_card\|static func style_teal_tab'` = 2);
  test-35b assertions (teal border `b>r,g>r` — theme TEAL_BORDER
  0.26/0.68/0.70 passes; `groups ≥ 6`) preserved.

## P1-3 — Mobile touch UI routed through theme (zero inline Color)

BEFORE: 11 inline colors, 0 token refs (`mobile_touch_ui.gd:92-93,119-120,144,
151-152,162,393,500,526`): stick/knob fills, button fill/border/label, prompt,
icon modulate, press-flash, interact glow, charge badges.

AFTER (`game/src/ui/mobile_touch_ui.gd` + 17 theme consts):
- Theme (`art_nouveau_theme.gd`) extended FIRST per mandate: `TOUCH_STICK_FILL/
  RING`, `TOUCH_KNOB_FILL/RING`, `TOUCH_BTN_FILL/BORDER/LABEL`,
  `TOUCH_PROMPT/SHADOW/ICON_MODULATE`, `TOUCH_FLASH_DOWN`,
  `TOUCH_GLOW_ACTIVE/IDLE`, `TOUCH_BADGE_FULL/EMPTY` — translucent aliases of
  the ivory/gold/teal palette, commented as port-authored alphas for
  finger-target legibility (HARD_LIMIT 5.2 class). Audit noted "no new tokens
  needed (GOLD_* exist)"; named aliases were added anyway so call sites never
  inline hex — same hues, token-routed.
- All 11 sites mapped 1:1 (stick base/knob, prompt + shadow, button
  circle, label + shadow, icon modulate, flash down/up, glow active/idle,
  badge full/empty); `_ready` prints theme provenance + asserts it.
- Proof: `grep -n 'Color(' mobile_touch_ui.gd` returns exactly 1 line — the
  header comment stating "Zero inline Color( in screen code". Every
  `ThemeScript.TOUCH_*` use (15) resolves to a `const TOUCH_*` def (15).

## P1-4 — Main-menu / journal chrome routed through theme

BEFORE (audit): menu buttons inline `font_color (0.92,0.90,0.86)` /
`font_hover_color (1.0,0.78,0.38)` (:344-345), journal panel/border inline
(:421-422), journal title + credits lines inline.
AT THIS HEAD: the P0 T9 wave already deleted the journal drawer (verified by
re-read: no `journal_panel`, no drawer comment — header reads "there is no
journal drawer here"; Den map table is the single deploy path). Remaining P1
chrome was the menu buttons + credits text.

AFTER (`game/src/ui/main_menu.gd` only):
- `_make_menu_btn`: flat left-aligned KF01 look kept, colors token-routed —
  `ArtNouveauTheme.IVORY` idle (≈ old 0.92/0.90/0.86), `GOLD` hover (≈ old
  1.0/0.78/0.38), plus `GOLD_DIM` pressed / `GOLD` focus (previously unset).
- Credits lines: inline `(0.86,0.90,0.92)` → `ArtNouveauTheme.TEAL_TEXT`.
- `_ready` prints theme provenance + T9 note.
- Proof: `grep -n 'Color(' main_menu.gd` returns 9 lines, ALL 3D-scene rig
  (env bg/ambient/fog/fog-albedo, streetlight spot color, bulb albedo/emission)
  — zero UI-chrome inline colors. Journal spans need no edit (already deleted
  by the T9 wave; no second deploy path exists).

## VERIFY

- Re-read: all edited spans re-read from disk after editing (settings wrapper
  + modal block, menu button builder, ledger provenance + preview + BUY,
  mobile header/button/flash/glow/badge, theme TOUCH block + `group_card`).
- Headless parse gate (flatpak Godot 4.7.2 `--headless --check-only --script`,
  per file): `art_nouveau_theme.gd` clean pass; `ledger/settings/mobile_touch/
  main_menu` each report exactly one `Identifier not found: <Autoload>`
  (AudioManager/GameState/GameData) — the SAME failure class as untouched
  controls (`contract_table_ui.gd`, `wardrobe_ui.gd`), i.e. project-context
  resolution that only exists in-game/under `make test`. Since Godot parses
  before it analyzes, zero syntax errors exist in any edited span; semantic
  resolution is the orchestrator's `make test` gate (not run here per task).
- Structural counts: ledger TBD ×20, VERIFIED refs ×2, 8/8 KF prices correct;
  settings 0 bare TEAL / 0 local stylers; mobile 0 inline Color; menu 0
  chrome-inline Color; theme 15/15 TOUCH uses resolve, `group_card` +
  `style_teal_tab` present.
- NOT done (stated, not hidden): no `make test` (orchestrator settles); no
  live-GPU/windowed capture — this environment is headless with no display
  server, so "render each screen" is satisfied structurally (parse + counts),
  not pixel-wise. The per-screen before/after notes above are the ledger
  record; pixel proof awaits a GPU run.
- Design-system Phase-4 checklist: every color references a token (P2 pink/
  green status colors in ledger/wardrobe pre-date this pass and stay
  HARD_LIMIT 5.7 — untouched, still inline, still cited); spacing/typography
  unchanged from the existing system (no new scales introduced); components
  compose from existing primitives (`group_card` added to theme first, then
  used); zero new magic numbers for visual properties (touch alphas are named
  tokens).

## Files changed (this node only)

- `game/src/ui/art_nouveau_theme.gd` (+TOUCH_* ×17 consts, +`group_card()`)
- `game/src/ui/ledger_ui.gd` (provenance + 8 verified prices + TBD discipline)
- `game/src/ui/settings_ui.gd` (consts + tab styler deleted; theme-routed)
- `game/src/ui/mobile_touch_ui.gd` (11/11 colors token-routed)
- `game/src/ui/main_menu.gd` (menu buttons + credits token-routed)
- (Working tree also holds other waves' uncommitted P0/T9 + concurrent UI
  touches in `contract_table_ui/hud/mission_prep_ui` — not this node; my diff
  is the 5 files above plus this ledger.)
