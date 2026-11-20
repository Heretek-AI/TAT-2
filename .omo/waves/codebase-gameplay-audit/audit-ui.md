# TAT-2 UI Screens + Theme System Audit

Date: 2026-11-20. Scope: read-only analysis, no product-code edits.
Files audited: all 10 files under `game/src/ui/`
(`main_menu.gd`, `mission_prep_ui.gd`, `contract_table_ui.gd`,
`ledger_ui.gd`, `wardrobe_ui.gd`, `hud.gd`, `loading_screen.gd`,
`settings_ui.gd`, `mobile_touch_ui.gd`, `art_nouveau_theme.gd`).
Ground truth: `.omo/waves/tat2-ground-truth/backlog.md` (F2/F3 cooked-found),
`.omo/evidence/tat2-playtest-ground-truth-fixes/task-6.log` (23 value cites + 10 HARD_LIMIT rows),
`.omo/evidence/tat2-playtest-ground-truth-fixes/task-3.md` (car HARD_LIMIT + guard SK coverage),
`.omo/evidence/tat2-playtest-round2-fixes/task-3.md` (wardrobe KF03/KF04 rebuild, 18 value rows + 6 standing HARD_LIMIT closes).
KF frames: `docs/reference/clip_1795033698901/clean/KF01,KF03,KF04,KF07,KF08,KF10,KF11,KF12,KF30`.

## 1. Theme system (`art_nouveau_theme.gd`)

Token inventory (single source of truth, working as designed):
teal family `TEAL/TEAL_DIM/TEAL_DARK/TEAL_PANEL_BG/TEAL_CARD_BG/TEAL_GROUP_BG/TEAL_BORDER/TEAL_BORDER_SOFT/TEAL_ACCENT/TEAL_TITLE/TEAL_TEXT/TEAL_MUTED`,
`GOLD/GOLD_DIM/GOLD_DARK/IVORY/PANEL_BG/DIM_COLOR/PROMPT_TEAL/KEYCAP_WHITE_BG/KEYCAP_DARK_TEXT`,
font paths `FONT_SANS/ITALIC/SERIF/TYPEWRITER_PATH` + `font_*()` loaders with cache,
builders `panel_style/teal_panel_style/teal_card_style/inner_line_style`,
`style_button/style_teal_button/style_teal_tab/style_teal_option`,
`section_header/divider/teal_divider/keycap/white_keycap/prompt_label`,
`add_filigree/add_teal_filigree`, `make_modal`.
Per-screen theme routing: contract_table 28 `ThemeScript.` refs, ledger 29, wardrobe 40, mission_prep 17 —
all screen chrome (panels/cards/dividers/buttons/tabs/filigree) routes through tokens (task-6 row 23 holds).

Known token gaps (standing HARD_LIMIT 5.7, re-cited — NOT new findings, carried as P2 polish):
> `game/src/ui/art_nouveau_theme.gd:18-21`
> `# Task-6 parity note (KF08/KF03-KF04 cite): purchase-green check, "Active"`
> `# green, and pink LOCKED/padlock accents are verified on footage but have no`
> `# cooked UE source in scope (HARD_LIMIT 5.1). No tokens added here on purpose:`
> `# extend the system with named tokens first, never inline hex at call sites.`
Consequence: every pink/green usage below is an inline `Color(...)` by necessity, each citing HARD_LIMIT 5.7.
A design-system pass adding `PINK_LOCKED / GREEN_PURCHASED / GREEN_ACTIVE` tokens would clear 5+ inline sites at once.

Inline-`Color(` count per file (via grep): main_menu 15 (mostly 3D rig), mission_prep 10 (mostly 3D rig),
contract_table 5, ledger 7, wardrobe 13 (mostly 3D rig + 2 pink), loading 11, settings 10 (5 local consts),
mobile_touch 11, hud 112 (deliberate UE-parity custom draw — see §8), theme 57 (token definitions themselves).

## 2. Main menu (`main_menu.gd`) — KF01

Layout: full-rect 3D startscreen stage (`_build_3d_backdrop`, SubViewportContainer `main_menu.gd:63`,
SubViewport `main_menu.gd:68`, `UPDATE_WHEN_VISIBLE` `main_menu.gd:71`) loading two authored sublevels
(BeautifulCorner P + Lighting), right-aligned title/menu column (`right_anchor.offset_left = -460`,
`offset_right = -64`), vertical menu PLAY / SETTINGS / CREDITS / QUIT (`main_menu.gd:391,400,404,408`),
serif fallback title 44 (`main_menu.gd:382`), menu buttons 22 (`main_menu.gd:343`).
Sound: PLAY click + hover SFX wired; credits modal uses `ArtNouveauTheme.make_modal` + `style_button` (themed, good).

Theme coverage: weakest of the themed screens — only 2 `ArtNouveauTheme` refs (credits modal).
Menu buttons bypass the theme system entirely:
> `main_menu.gd:344-345`
> `b.add_theme_color_override("font_color", Color(0.92, 0.90, 0.86))`
> `b.add_theme_color_override("font_hover_color", Color(1.0, 0.78, 0.38))`
Journal drawer style is inline gold-on-dark rather than `teal_panel_style`:
> `main_menu.gd:421-422`
> `style.bg_color = Color(0.03, 0.035, 0.06, 0.94)`
> `style.border_color = Color(0.55, 0.45, 0.25, 0.8)`
Journal title `main_menu.gd:438`, credits lines `main_menu.gd:621` likewise inline.
Moth portrait tint is inline (`main_menu.gd:552` `portrait_rect.modulate = Color(0.75, 0.65, 1.0)`).

Preview-world cost: highest of any screen. Full level load of two sublevels through LevelLoader,
`scaling_3d_scale = 0.75` (`main_menu.gd:70`), desktop-only volumetric fog + SSR (48 steps) + SSIL block,
per-frame camera sway in `_process` (always runs while menu is up), guard GLB + AnimationPlayer.
No `queue_free`/teardown of the stage on launch (scene change discards it — fine, but the cost is paid
on every menu visit including post-mission returns).

Dead widget / unreachable screen: the Contract Journal drawer is built and permanently hidden
(`main_menu.gd:414` `journal_panel.visible = false`) behind a comment that names a button that does not exist:
> `main_menu.gd:412`
> `# Contract Journal drawer (hidden until "CONTRACTS & CO-OP" is clicked)`
No "CONTRACTS & CO-OP" button exists — the menu has exactly PLAY/SETTINGS/CREDITS/QUIT
(`main_menu.gd:391,400,404,408`) — and PLAY hardcodes `selected_order = 1` then launches
(`main_menu.gd:393`), so the journal (contract list, difficulty, co-op host/join, LAUNCH) is unreachable
in the shipped flow. Ranked P0 below.

Accessibility: menu 22 / title 44 / detail 18 / credits 14 — all adequate. Co-op `ip_edit` min width 130
with no input hint beyond "127.0.0.1"; `net_status` has no font-size override (inherits default ~16, fine).

KF01 parity: startscreen camera constants (`main_menu.gd:18-24`, eye/fwd/focus/VFov/pitch) cite authored
MainMenu.json; trim-specular clamp pass (T1-03-E) is port-authored staging, no UE numbers — acceptable per HARD_LIMIT 5.2.

## 3. Mission prep (`mission_prep_ui.gd`) — KF11

Layout: full-rect 3D rooftop stage + top-center title block + left info stack (LOCATION / MISSION / CONTRACT cards)
+ bottom-right READY/BACK. Title 24 / mode+difficulty subs 14 / card header 12 / card title 20 / card body 13 /
controls 14 (`mission_prep_ui.gd:224,237,247,326,399,407,416`). Card header 12 and body 13 are the smallest
desktop prose in the flow (see P2-7).

Theme coverage: good — 17 `ThemeScript.` refs; cards via `teal_card_style`,
buttons/selector via `style_teal_button/style_teal_option`, filigree on cards.
Inline leftovers are all 3D-rig colors plus two UI cases:
shade `mission_prep_ui.gd:203` (`Color(0.0, 0.01, 0.03, 0.08)`),
shadow `mission_prep_ui.gd:226`, card bg `mission_prep_ui.gd:388`
(`ThemeScript.teal_card_style(1, 4, Color(0.024, 0.056, 0.075, 0.84), 12)` — inline bg instead of `TEAL_GROUP_BG`).

Preview-world cost: second-highest. Full MissionLobby geo load (2 sublevels) + moonlight + SSIL
(`env.ssil_enabled = true` in `_build_stage`), authored 1280x720 floor with a crush-guard
(`STAGE_VIEWPORT_SIZE`, `_ensure_stage_size` on `resized` + deferred). Thief body+head GLBs + retargeted idle
AnimationPlayer. Cost is per-visit; prep is freed on READY/BACK (`queue_free` in `_emit_ready`/`close_prep`) — good.

Parity leftovers:
- KF11 countdown: the file header/comment promises a "6 s countdown"
  (`mission_prep_ui.gd:112` `# S09: soft rooftop wind under the prep screen + 6 s countdown`),
  but grep for `countdown` returns only that comment — no countdown label, timer, or auto-ready logic exists.
  Either the comment overpromises (fix comment) or a countdown widget is missing (add it). P2.
- Controls label duplicates the header subs: `_refresh_controls` (`mission_prep_ui.gd:844`)
  `Difficulty: %s · Mode: %s` repeats `_mode_sub_lbl`/`_diff_sub_lbl` (`mission_prep_ui.gd:237,247`). Redundant, P2.
- KF11 frame itself (countdown card) has no further citable numbers; staging numbers remain
  port-authored per HARD_LIMIT 5.2 (LOBBY_CAM_* consts cite authored MissionLobby.json FOV/geometry — fine).

Dead widgets: none — READY (`[F] READY`), BACK (`[ESC] BACK`), mission selector, difficulty/mode subs all wired.

## 4. Contract table (`contract_table_ui.gd`) — KF10

Layout: dim + centered 1020x640 panel (`teal_panel_style` + filigree), title 26 (`contract_table_ui.gd:135`),
list (360px) + splash/title/detail/intel right column, difficulty + co-op rows, DEPLOY/CLOSE bottom bar.
Title 22 / detail 15 / intel 14 / diff 16 / net 14 / confirm 20 / hint 14 — adequate; nothing below 14.

Theme coverage: best in the project — 28 `ThemeScript.` refs, only dim/confirm-bg colors inline.
No pink/green/gold inline leakage in screen code. Exemplary path; use as the reference when theming main_menu/settings.

Parity leftovers (KF10 KILCAIRN `[H]/[R]/[F]` card):
- Confirm modal hint covers H + R only:
  > `contract_table_ui.gd:467`
  > `hint.text = "[H] Difficulty toggle   ·   [R] Mode toggle"`
  while the primary action is `[SPACE] PREPARE FOR MISSION` (`contract_table_ui.gd:477`).
  KF10 cites an `[H]/[R]/[F]` card; the F-slot equivalent (prepare) is undiscoverable from the hint. P2.
- Splash art covers 2 maps: `SPLASH_CANDIDATES` (`contract_table_ui.gd:14-23`) + `_splash_for`
  (`contract_table_ui.gd:331`) only try OldManor/Guildhall splash paths; any other `map_id` yields null
  and the splash rect is hidden (`_update_splash`). Contracts on jaspering_hall/thieves_den (cf.
  `mission_prep_ui.gd` `LOCATION_ART_MAP`, which does cover them) show a blank splash slot here. P2.
- Host/join dual-API fallback (`host_game`→`host`, `join_game`→`join`) is defensive but correct for NetManager skew; keep.

Dead widgets: none — `_confirm_root` lazily built, `_prep` freed on ready/closed, list refresh on reopen.

## 5. Ledger (`ledger_ui.gd`) — KF07/KF08

Layout: 1100x660 panel, `[Q] JOURNAL` / `BLACK MARKET [E]` / `BACK [ESC]` header, XP row, horizontal contracts
carousel (slot 340px + status-above + `Contract #N` tab — task-6 rows 2/4 implemented), market preview 300px +
4 vertical sections. Font ladder 22/20/20/18/17/16/15/14 — good.

Theme coverage: good — 29 `ThemeScript.` refs. Inline colors are exactly the HARD_LIMIT 5.7 set plus neutrals:
dim `ledger_ui.gd:128`, XP bar `ledger_ui.gd:197-205`, completed-green `ledger_ui.gd:361`
(`Color(0.45, 0.90, 0.65)`), card-done border `ledger_ui.gd:368` (`Color(0.32, 0.72, 0.56, 0.85)`),
purchased-green `ledger_ui.gd:470`, price-gold `ledger_ui.gd:474` (`Color(0.95, 0.82, 0.48)`),
insufficient-red `ledger_ui.gd:500`. All clearable by the token pass (P2-1).

Parity leftovers carried from task-6 (standing, re-verified — no re-litigation, listed for ranking):
- BACK placement: `back_btn` (`ledger_ui.gd:163` `back_btn.text = "BACK [ESC]"`) sits in the header HBox,
  KF07 cites bottom-right (task-6 row 7 MISMATCH, still present). P2.
- XP bar is a plain rectangular ProgressBar; KF07 chamfered/angled fill has no UMG token (HARD_LIMIT 5.2). P2.
- Market tables stack 4 sections vertically; KF08 cites TOOLS|GUILD-PERKS side-by-side + twin cosmetic columns
  (task-6 row 10 MISMATCH, HARD_LIMIT 5.2 geometry). P2.
- Prices remain placeholders; only 4 KF-visible prices recovered (HARD_LIMIT 5.6). MUST NOT ship as parity — P1.
- Card lore bodies bind to DT facts, not KF card copy (HARD_LIMIT 5.3). Correct as-is; no action.

Dead widgets: none — tabs, preview, BUY, back all wired; `_show_tab` disables active tab (good).

## 6. Wardrobe (`wardrobe_ui.gd`) — KF03/KF04

Layout per round-2 task-3 rebuild: centered WARDROBE header 30, Q/E portrait cards, numbered slots + expanded row,
hint verbatim, tool tooltip card, right rail Head/Body/CallingCard cards (72px) + desc + APPLY, bottom-right BACK
(task-3 rows 1/2/6/7/11/15 — all verified present this audit).

Theme coverage: 40 refs, all chrome themed. Inline: `LOCKED_PINK` (`wardrobe_ui.gd:46`
`const LOCKED_PINK: Color = Color(1.0, 0.38, 0.72)`, used `wardrobe_ui.gd:253,392`) — documented HARD_LIMIT 5.7
fallback with inline cites (`wardrobe_ui.gd:231,314`); pre-existing pink hint `wardrobe_ui.gd:509`
(`Color(0.95, 0.55, 0.65)`); dim `wardrobe_ui.gd:169`; 3D rig colors `wardrobe_ui.gd:529-591`.

Preview-world cost: two `own_world_3d` SubViewports alive simultaneously — turntable (`wardrobe_ui.gd:360-363`)
and tool close-up (`wardrobe_ui.gd:413-416`), each with its own lights (key+fill+rim / key+fill) and cameras,
plus per-frame `_process` rotation of both turntable and tool holder. Highest per-frame UI cost in the project
after the menu stage; acceptable on desktop, worth a quality-gate on mobile (hide tool viewport when market
preview philosophy applies — currently no mobile gate in this file). P2.

Parity leftovers (standing HARD_LIMIT, re-verified):
- Portrait frames are empty buttons (HARD_LIMIT 5.1, task-3 rows 2/4). No invented art — correct; P2 until source found.
- Expanded row reuses the same 4 verified-mesh TOOLS; Pickpocket/Insult Fairy + Slither Sap absent
  (HARD_LIMIT 5.8, task-3 rows 8/9). TOOLS const intentionally not extended — correct; P2.
- Outfit cards are name + `· Lv N` text, no thumbnails (HARD_LIMIT 5.9, task-3 rows 11-13). Correct; P2.
- Lock badges: slots grey (`TEAL_MUTED`), expanded row pink (`LOCKED_PINK`) — matches KF03/KF04 cite. Good.

Dead code: `_panel_style` (`wardrobe_ui.gd:520-521`) is defined but never called (grep: only the def lines) —
all call sites use `ThemeScript.teal_panel_style` directly. Trivial dead helper. P2.

Accessibility: lock badges 11 (`wardrobe_ui.gd:333`), section hints 14 — the 11px LOCKED badges are the smallest
text in the Den flow and sit on dimmed cards; contrast of `TEAL_MUTED` on dark card is adequate but size is
marginal. P2 (covered by P2-7).

## 7. Loading screen (`loading_screen.gd`) — KF12

Layout: full-bleed splash art (KEEP_ASPECT_COVERED, full modulate), centered 56px spinner + LOADING... 24
(`loading_screen.gd:130`), subtitle 14, status 12, bottom-center gold logo
(`loading_screen.gd:188` `modulate = Color(0.92, 0.72, 0.22, 0.98)`). Matches KF12 presentation intent.

Theme coverage: thinnest — 2 refs (`font_serif/font_sans` only). All colors inline
(`loading_screen.gd:64,72,122,131-132,144-145,167-168,188,242`). Functionally harmless (single-purpose overlay),
but the title/status/subtitle colors duplicate theme tokens by value; route through
`TEAL_TITLE/TEAL_TEXT/TEAL_MUTED` when convenient. P2.

Issues:
- Progress bar exists but is permanently invisible (`loading_screen.gd:160` `_bar.visible = false`;
  `start_loading`/`set_progress` drive values nobody sees). Users get spinner + status text only; on long
  sublevel loads there is no proportion indicator. Either show a slim bar or delete `_bar` and keep the
  API as no-ops. P2 (dead-widget-adjacent).
- Status label 12px at 0.78 alpha (`loading_screen.gd:167-168`) — lowest-contrast text in the project. P2.
- `_update_splash` ignores its map parameter (`_map_id`, `loading_screen.gd:238-249` always loads
  `LOADING_ART_PRIMARY` then ALT): every map shows T_loadingScreen_1. KF12 shows one art, and per-map arts
  for other maps are unrecovered, so this is acceptable — noted, no action.

## 8. HUD (`hud.gd`, 3054 lines) — KF13-KF30

Layout (verified builders): compass strip 580x30 (`_build_compass_strip`), portrait badge 82x90 + level badge,
top-left health/loot/objectives stack, bottom-center stealth ball + bilateral SoundWaves, bottom-left 4-slot
octagonal hotbar + TAB/MMB hint bar, bottom-right action hints, center reticle + crank prompt + stacked secondary
prompt (KF24/KF25), Den look-at card, FPS overlay (hidden), lockpick overlay 390x440, tactical map 760x540,
ping radial, mission letter on T_Paper01, result panel, pause menu. This is the UE-parity centerpiece and its
custom-draw approach (shaders, AtlasTextures, masked backgrounds) is appropriate — the 112 inline `Color(`
hits are overwhelmingly gameplay-presentation constants (orb shader, reticle, pips, map markers), NOT theme
bypasses. Overlay chrome (pause/result/map/lockpick/letter/buttons/keycaps) routes through ThemeScript (40 refs). Verdict: sound.

Preview-world cost: none — HUD adds no SubViewport; all custom draw is 2D canvas. Good.

Dead / legacy widgets (both preserved for API compat, both invisible, both still driven per-frame):
- `hotbar_lbl` (`hud.gd:105` decl; `hud.gd:629-631` built + `visible = false`) still gets text updates
  (`hud.gd:2244` `hotbar_lbl.text = "[1]Zip:%d ..."`). Invisible label updated every refresh — dead. P2.
- `lockpick_bar` (`hud.gd:111` decl; `hud.gd:610-618` built + `visible = false`) still driven
  (`hud.gd:1761-1762` `lockpick_bar.visible = active; lockpick_bar.value = ...`) while the real minigame
  is the `LockpickDialDraw` dial. Two lockpick progress representations; the legacy bar should be removed
  (or the dial should drive it — currently both exist). P2.
- `VERSION_STRING` (`hud.gd:24` `"v1.5.148559"`) feeds the KF30-exact pause footer
  (`hud.gd:1646-1656` strips "v", appends difficulty + `_run_seed`). Correct; keep.

Parity notes:
- TacticalMapDraw marker scaling (`hud.gd:448-458`: objective diamonds scale with `_world_span`, guard/loot/ping
  constant) cites KF10/S08 — good, keep.
- Compass ribbon 13 (`hud.gd:710`) at 0.62 alpha + cardinal 12 (`hud.gd:721`): smallest HUD text, dim by design
  (peripheral instrument). Noted under P2-7; do not "fix" upward without a KF readability check.
- Crank/hold arcs, SoundWaves, stealth orb: custom presentation, no UE numeric tokens — HARD_LIMIT 5.2 class, fine.

Accessibility: 12px tier is concentrated here (compass 12, badge 12, crank 12, secondary prompt 12, map legend 12,
ping labels 12, pause footer 12, fps 13, slot counts 13, lockpick status 13). Individually justified (badges,
peripheral instruments, footers), but the secondary prompt (`_prompt_secondary_lbl`, 12px, 0.88 alpha) carries
gameplay-critical text ([F] [HOLD] LOCK / TAKEDOWN) — consider 13-14. P2.

## 9. Settings (`settings_ui.gd`)

Layout: modal 680 wide via `make_modal`, 4 tabs (GENERAL/VIDEO/AUDIO/CONTROLS, Q/E + ui_cancel), grouped teal cards,
sliders + value labels, binding rows with keycap badges, RESET DEFAULTS / APPLY & BACK + [ESC] badge.
Live-apply on change + persist on close; mobile-only touch-quality rows gated by `MobileProfile.is_mobile()`. Sound.

Theme coverage: structural duplication. The file defines its own teal constants
(`settings_ui.gd:14-18` `TEAL_PANEL_BG/GROUP_BG/BORDER/ACCENT/TEXT` — same values as the theme file)
and its own tab styler (`_style_teal_tab`, body `settings_ui.gd:340-345`) paralleling
`ArtNouveauTheme.style_teal_tab`, plus a local `_make_group_card` paralleling `teal_card_style`.
Only 8 `ThemeScript.` refs (`make_modal`, `divider`, `style_button`, `keycap`). Any future token change
(accent hue, radii, margins) must be made in two places or settings visibly drifts. Ranked P1 below.

Accessibility: 14-15px throughout, CheckBoxes 15 — adequate. Slider value labels right-aligned 70px, fine.

## 10. Mobile touch (`mobile_touch_ui.gd`)

Layout: floating left stick (deadzone 0.15, auto-sprint at 0.9 mag + 0.35 s), right-side look zone (x ≥ 0.45),
13 action buttons (HIT/JUMP/USE/SKILL/SAP/SMOKE/FAIRY/EYE/CROUCH/SPRINT/LEAN L/LEAN R/II) with safe-area layout,
prompt mirror from `hud.current_prompt`, charge badges, thief-ability label (WIRE/MASK/ASTRAL). Input dispatches
through real actions; look through `add_look_pixel_delta`. Architecturally sound; desktop untouched.

Theme coverage: zero — no `ThemeScript`/token reference in the file; all chrome inline:
stick `mobile_touch_ui.gd:92-93`, buttons `mobile_touch_ui.gd:144`
(`Color(0.04, 0.06, 0.09, 0.42)` / gold `Color(0.9, 0.78, 0.45, 0.55)`),
labels `mobile_touch_ui.gd:151`, prompt `mobile_touch_ui.gd:119-120`,
pressed-flash `mobile_touch_ui.gd:393`, interact-glow `mobile_touch_ui.gd:500`.
A mobile pass should map these onto theme tokens (gold accents already exist as GOLD_*). P1.

Accessibility: button labels 12 (`mobile_touch_ui.gd:150`), dynamically shrunk to
`maxi(10, int(13.0 * s))` (`mobile_touch_ui.gd:250`) — 10px floor on small screens is very small,
though buttons are large touch targets with short labels (HIT/USE/EYE). Prompt 14 fine.
Charge badges dim to 0.35 alpha when empty (`mobile_touch_ui.gd:526`) — intentional affordance, fine.
Note: `tool_3` is labeled "FAIRY" while charges bind `pickpocket_fairy`; with only verified-mesh tools
(HARD_LIMIT 5.8) the label is generic rather than wrong — leave until tool roster resolves.

## 11. Ranked issue list

### P0 — broken screen (1)

- **P0-1. Main-menu Contract Journal is unreachable.** The journal drawer (contract list, thief/difficulty
  selectors, co-op host/join, LAUNCH) is built then permanently hidden (`main_menu.gd:414`
  `journal_panel.visible = false`) behind a comment naming a button that was never built:
  > `main_menu.gd:412`
  > `# Contract Journal drawer (hidden until "CONTRACTS & CO-OP" is clicked)`
  The menu offers only PLAY/SETTINGS/CREDITS/QUIT (`main_menu.gd:391,400,404,408`), and PLAY hardcodes
  `selected_order = 1` (`main_menu.gd:393`) straight into `_launch`. Net effect: contract selection,
  difficulty choice, and co-op from the main menu are dead code paths; the only live route is the
  Den map table. Fix: add the CONTRACTS entry (or remove the drawer and the comment if the Den table
  is the intended single route).

### P1 — parity / correctness (4)

- **P1-1. Black-market prices are placeholders and must not ship as parity.**
  `ledger_ui.gd` TOOLS/PERKS/COSMETICS costs (1500/800/2000/3000/6000/2500/4000/…) have no cooked source;
  only 4 KF-visible prices exist (HARD_LIMIT 5.6, task-6 row 13). Either recover the price table or gate
  purchases as debug. (Carried from task-6; still true at HEAD.)
- **P1-2. `settings_ui.gd` duplicates the design system.** Local `TEAL_*` consts (`settings_ui.gd:14-18`),
  local `_style_teal_tab` (`settings_ui.gd:340-345`), local `_make_group_card` vs theme builders, with only
  8 `ThemeScript.` refs. Delete the locals and route through `art_nouveau_theme.gd`; add any missing
  builder (group card) to the theme first per the §1 mandate.
- **P1-3. `mobile_touch_ui.gd` bypasses the theme entirely.** Zero token refs; 11 inline colors
  (`mobile_touch_ui.gd:92-93,119-120,144,151-152,393,500,526`). Map fills/borders/labels onto existing
  teal + gold tokens (no new tokens needed — GOLD_* already exist).
- **P1-4. `main_menu.gd` menu + journal chrome bypass the theme.** Menu button colors
  (`main_menu.gd:344-345`), journal panel/border (`main_menu.gd:421-422`), journal title
  (`main_menu.gd:438`), credits text (`main_menu.gd:621`) are inline; only the credits modal uses the theme.
  Route buttons through `style_teal_button` (left-aligned variant) and panels through `teal_panel_style`.

### P2 — polish (9)

- **P2-1. Add missing theme tokens (clears HARD_LIMIT 5.7).** `LOCKED_PINK` (`wardrobe_ui.gd:46`),
  hint pink (`wardrobe_ui.gd:509`), completed/purchase greens (`ledger_ui.gd:361,368,470`),
  Active-teal usage, insufficient-red (`ledger_ui.gd:500`) → named tokens in `art_nouveau_theme.gd`
  (see `art_nouveau_theme.gd:18-21` mandate note). Design-system pass, not inline edits.
- **P2-2. Remove HUD legacy widgets.** Invisible `hotbar_lbl` still updated (`hud.gd:629-631` vs `hud.gd:2244`);
  invisible `lockpick_bar` still driven (`hud.gd:610-618` vs `hud.gd:1761-1762`) alongside the real
  `LockpickDialDraw` dial. Delete both + their update lines (keep M2 API names as no-op stubs only if
  `run_tests.gd`/callers reference them — `hotbar_lbl/lockpick_bar` are documented preserved properties).
- **P2-3. Loading progress is invisible.** `_bar` permanently hidden (`loading_screen.gd:160`) while
  `start_loading/set_progress` (`loading_screen.gd:200-201,218-219`) maintain values. Show a slim bar under
  the spinner or remove `_bar` and document spinner+status as the intended pattern.
- **P2-4. Contract-table confirm omits the F key.** Hint lists H/R only (`contract_table_ui.gd:467`);
  primary action is SPACE (`contract_table_ui.gd:477`); KF10 cites an H/R/F card. Add the prepare-key hint.
- **P2-5. Contract-table splash missing for non-Manor/Guildhall maps.** `_splash_for`
  (`contract_table_ui.gd:331`) only resolves two maps; others hide the rect. Reuse the
  `LOCATION_ART_MAP`-style fallback from `mission_prep_ui.gd` for jaspering_hall/thieves_den.
- **P2-6. Mission-prep countdown comment overpromises.** `mission_prep_ui.gd:112` advertises a 6 s countdown;
  no countdown widget/timer exists. Add it or correct the comment.
- **P2-7. Smallest-text audit.** 11px wardrobe LOCKED badges (`wardrobe_ui.gd:333`); 12px mission-prep card
  header/body (`mission_prep_ui.gd:399,416`), HUD secondary prompt (`hud.gd:1073`), compass readouts
  (`hud.gd:710,721`), map legend + ping labels (`hud.gd:1401,1452`), pause footer (`hud.gd:1638`),
  loading status at 0.78 alpha (`loading_screen.gd:167-168`), mobile labels shrinking to 10px
  (`mobile_touch_ui.gd:250`). Gameplay-critical strings (secondary prompt, lock badges) should be ≥13-14;
  peripheral instruments/footers may stay.
- **P2-8. Wardrobe carries two live 3D preview worlds + dead helper.** Turntable + tool SubViewports
  (`wardrobe_ui.gd:360-363,413-416`) both render every frame with per-frame `_process` rotation; consider
  pausing the tool viewport when hidden and gating pixel ratio on mobile. `_panel_style`
  (`wardrobe_ui.gd:520-521`) is never called — delete.
- **P2-9. Redundant prep header/controls text.** `_controls_lbl` (`mission_prep_ui.gd:844`) repeats the
  mode/difficulty subs (`mission_prep_ui.gd:237,247`); `loading_screen._update_splash` ignores `map_id`
  (`loading_screen.gd:238-249`, acceptable — single recovered art, noted only). Consolidate the prep labels.

## 12. Counts and verification

- P0: 1 item. P1: 4 items. P2: 9 items. Total: 14 ranked issues.
- Every P0/P1 cites an exact `file:line` with the quoted line reproduced in §§1-11.
- Re-verification performed this turn: re-read all 10 UI files; grep-pinned line numbers for
  `journal_panel.visible` (414), menu buttons (391/400/404/408), theme note (art_nouveau_theme 18-21),
  `LOCKED_PINK` (wardrobe 46), `_panel_style` (wardrobe 520-521, no callers), confirm hint (contract_table 467),
  prepare button (477), splash func (331), countdown comment (mission_prep 112), `_bar.visible=false`
  (loading 160), mobile label floor (mobile_touch 250), HUD legacy widgets (hud 105/111/629-631/610-618
  vs updates 2244/1761-1762), settings local consts (14-18) and tab styler (340-345).
- Not run (read-only task, no live/GPU): `make test`, headless GDScript parse, in-game screenshots.
  KF-frame claims (KF01/KF03/KF04/KF07/KF08/KF10/KF11/KF12/KF30) are carried from the task-6/task-3 ledgers,
  which viewed the frames; no new pixel claims are made here.
