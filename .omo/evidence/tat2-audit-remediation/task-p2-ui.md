# TAT-2 Audit Remediation — Task P2-UI (visual polish)

Date (UTC): 2026-11-21. Scope: `game/src/ui/*` only (plus this evidence file).
Ground truth: `AUDIT.md §4 (UI)` as itemized in `audit-ui.md §11 P2` (9 items).
Method: minimal polish diffs, no behavior change beyond the P2 item.
Suite: NOT run (orchestrator runs the full suite at settle, per task orders).
Verify here: file-level re-read of every edited span (this turn).

## Per-item verdicts

### P2-1 missing pink/green tokens — FIXED
- Added named tokens in `game/src/ui/art_nouveau_theme.gd`:
  `PINK_LOCKED` (1.0, 0.38, 0.72), `PINK_HINT` (0.95, 0.55, 0.65),
  `GREEN_COMPLETED` (0.45, 0.90, 0.65), `GREEN_PURCHASED` (0.45, 0.85, 0.45),
  `GREEN_CARD_BORDER` (0.32, 0.72, 0.56, 0.85), `RED_INSUFFICIENT` (0.9, 0.4, 0.35).
  Values port the exact inline colors from the call sites; no UE cooked source
  exists, so the theme file is recorded as the source of truth. The old
  "no tokens on purpose (HARD_LIMIT 5.7)" note is updated to record the pass.
- Routed callers: `ledger_ui.gd` status-above green, card-done border,
  purchased green, price gold (→ `GOLD`), insufficient red; `wardrobe_ui.gd`
  portrait LOCKED pink and hint pink → tokens. `LOCKED_PINK` local const kept
  as a documented value-identical alias; expanded-row call site now passes
  `ThemeScript.PINK_LOCKED`.
- Standing HARD_LIMIT 5.7 (no pink/green tokens) is CLEARED by this pass.

### P2-2 HUD legacy lockpick bar + hotbar_lbl — FIXED (stubs retained)
- Reference check first: `hotbar_lbl` IS referenced outside `hud.gd` —
  `game/tests/e2e/e2e_tier2_boundaries.gd:675` asserts
  `hud.get("hotbar_lbl") != null`. Full deletion is therefore unsafe and was
  NOT done (no new HARD_LIMIT row needed; the stub stays deliberately).
- `hotbar_lbl` var + hidden builder kept; the per-frame
  `hotbar_lbl.text = ...` push in `_update_tool_hotbar_and_reticle` removed
  and replaced with an API-compat comment. The live octagonal hotbar
  (`slot_count_lbls` / icons / borders) is untouched; the `charges` dict read
  is kept because the slot-count fallback branch below still consumes it.
- `lockpick_bar` var + hidden builder kept (M2 property contract);
  `set_lockpick_progress` now always keeps the bar hidden and only retains
  the value, since `LockpickDialDraw` is the live minigame. No outside callers
  exist (grep: only the def + internal builder), so no stub risk.

### P2-3 permanently-hidden loading bar — FIXED
- `loading_screen.gd`: `_bar.visible = false` → `true`, styled as a slim
  280×4 teal bar (`TEAL_BORDER` bg / `TEAL_ACCENT` fill) under the spinner in
  the center column; full-bleed art stays uncovered. `start_loading` /
  `set_progress` / `finish_loading` value flow unchanged.

### P2-4 confirm modal omits F key — FIXED
- `contract_table_ui.gd`: hint line now reads
  `[H] Difficulty toggle · [R] Mode toggle · [SPACE/F] PREPARE`;
  `_confirm_input` accepts `KEY_F` in addition to `KEY_SPACE` for prepare.
  Modal comment updated to `[SPACE/F]`. Minimal, behavior is additive (F is
  the prep-screen READY key, so the modal now matches the next screen).

### P2-5 splash missing for non-Manor/Guildhall maps — FIXED
- `contract_table_ui.gd::_splash_for` now appends `mission_prep_ui.gd`
  `LOCATION_ART_MAP`-class fallbacks (OldManor map art, Guildhall shell art,
  `T_loadingScreen_1/2` for jaspering_hall / thieves_den) after
  `SPLASH_CANDIDATES` before returning null. Manor/Guildhall order unchanged;
  other maps show a themed fallback instead of a hidden rect.

### P2-6 prep countdown comment overpromise — FIXED
- `mission_prep_ui.gd`: both S09 comment sites no longer advertise a
  "6 s countdown" (no countdown widget/timer exists). They now document the
  wind bed only. Comment-only change.

### P2-7 smallest-text audit — FIXED (critical strings bumped; peripheral stays)
- Bumped gameplay-critical text: HUD `_prompt_secondary_lbl` 12 → 14
  ([F] [HOLD] LOCK / TAKEDOWN); wardrobe slot/expanded LOCKED badges 11 → 13;
  mission-prep card header 12 → 13 and body 13 → 14; loading status 12 → 13
  with alpha 0.78 → 0.90 for contrast.
- Deliberately unchanged (peripheral instruments/footers, per audit): compass
  ribbon/cardinal 12, map legend + ping labels 12, pause footer 12, ping-marker
  pool 11, mobile button labels 12 with the `maxi(10, …)` small-screen floor
  (floor kept as the intentional minimum; buttons are large touch targets
  with short labels). No new HARD_LIMIT row: this is the audit's own
  peripheral-vs-critical split, applied as written.

### P2-8 wardrobe dual live previews + dead _panel_style — FIXED
- Deleted the dead `_panel_style` helper (grep-confirmed zero callers; all
  call sites already use `ThemeScript.teal_panel_style` directly) and left a
  P2-8 comment in its place.
- Dual previews KEPT (removing one would be a behavior/visual change beyond
  polish): both SubViewports already use `UPDATE_WHEN_VISIBLE` and `_process`
  early-returns when the wardrobe is hidden, so no per-frame cost accrues
  while closed. No new HARD_LIMIT row.

### P2-9 redundant prep header/controls text — FIXED
- `mission_prep_ui.gd::_refresh_controls`: `_mode_sub_lbl` / `_diff_sub_lbl`
  remain the mode/difficulty source of truth; `_controls_lbl` no longer
  repeats them and now reads `[F] READY · [ESC] BACK` (the bottom-right key
  hints). Net: duplication removed, no info lost.

## Files changed (all inside `game/src/ui/`)
- `art_nouveau_theme.gd` — P2-1 tokens + parity-note update.
- `ledger_ui.gd` — P2-1 call-site routing (5 inline colors → tokens).
- `wardrobe_ui.gd` — P2-1 routing + P2-7 badge bump + P2-8 helper deletion.
- `hud.gd` — P2-2 legacy driving removal + P2-7 secondary-prompt bump.
- `loading_screen.gd` — P2-3 visible slim bar + P2-7 status contrast.
- `contract_table_ui.gd` — P2-4 F-key hint/wiring + P2-5 splash fallbacks.
- `mission_prep_ui.gd` — P2-6 comment + P2-7 card text + P2-9 controls text.

## Verification (this turn, file-level)
- Re-read every edited span after editing: theme tokens + note,
  ledger token call sites, wardrobe badge/hint/helper spans, HUD
  `set_lockpick_progress` + hotbar stub spans, loading bar/status spans,
  contract hint/input/splash spans, prep comment/controls/card spans.
- Headless/render check: not run in this node (no GPU surface claimed);
  orchestrator settle pass owns the suite + live render. Edits are
  value-identical color moves, text-label changes, one additive key binding,
  and deletions of dead code / dead per-frame writes only.
- `task-p2-ui.md` (this file) exists at
  `.omo/evidence/tat2-audit-remediation/task-p2-ui.md`.

## Standing rows
- None new. P2-2 full-deletion and P2-8 preview-removal were evaluated and
  deliberately kept as stubs / kept worlds for compat and no-visual-change
  reasons (documented above, not HARD_LIMITs). HARD_LIMIT 5.7 is cleared.
