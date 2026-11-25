# W9-P3-C3 audit — gamepad focus, visible focus state, device glyphs

- **Auditor:** independent (did not write C3; verified from the worktree, no source/test edits)
- **Worktree:** `/home/john/Projects/TAT-2-rem-w9-p3`
- **Branch / base:** `rem/w9-p3` @ `8ce9a86` (W9-P2 merged); C3 changes are uncommitted in the worktree
- **Date:** 2026-11-25
- **Only write:** this file.
- **Snapshot note:** another session was editing this shared worktree during the
audit (`hud.gd` mtime 15:52). The C3-relevant regions were re-read after that
edit and the gate was re-run; line numbers below are current at 15:57.

## Verdict

**AUDIT: FAIL**

Two material defects:

1. **The C3 gate is not a sound gate.** `test_focus_walk.gd` prints the expected
   `FOCUS_WALK_SUMMARY: fails=0 checks=64 screens=10` and exits 0, but it emits a
   `SCRIPT ERROR` at line 203 and **never executes its three modal-close checks**
   (`grep -c "C3.modal"` = 0). The advertised `checks=64` is the *crashed* count:
   60 ring checks + 4 rebind checks. The contract the test header claims ("a
   closed modal releases focus instead of trapping it") has no runtime evidence,
   and `run_tests` suite 107 accepts the run because it only checks exit 0 + the
   summary substring.
2. **The glyph formatter is not used in the HUD hint bar.** `MapPingHintBar`
   still hardcodes `TAB` / `MMB` keycaps, and the bottom-right action hints still
   hardcode `LMB` / `RMB` / `4`. The map-table confirm legend is also hardcoded
   (`[H]` / `[R]` / `[SPACE/F]`), and the shipped door/pickup prompt strings stay
   device-blind. So prompts do **not** follow the active device at every site the
   task names.

Per-item verdicts below. The ring half of item 1 is genuinely non-vacuous; the
failure is that the test also claims a modal assertion it does not run.

| # | item | verdict |
|---|---|---|
| 1 | focus-walk run, summary, non-vacuous ring test | **FAIL** (ring PASS, gate emits SCRIPT ERROR and skips 3 modal checks) |
| 2 | every menu calls `install`/`install_and_focus` on open | **PASS** (all 10) |
| 3 | gold 2 px `focus` stylebox + `FOCUS_ALL` in the theme | **PASS** |
| 4 | closed modal releases / re-rings / restores | **PASS** for the 4 named modals in code; **runtime proof absent** (see item 1); other modals listed under F4 |
| 5 | `InputGlyphs` at every named prompt/keycap site | **FAIL** (HUD hint bar; map-table confirm legend; device-blind door prompts) |
| 6 | rebind assertion + exact restore, two runs | **PASS** |
| 7 | `TAT2_UI_NO_STAGE` hook scope | **PASS** with notes (env-gated, backdrop-only; skipped container is a non-focusable `SubViewportContainer`) |
| 8 | no test weakened since `8ce9a86` | **PASS** |

---

## 1. The mandated run and the vacuity checks

### Command (run three times, serialized on the repo lock)

```bash
cd /home/john/Projects/TAT-2-rem-w9-p3
flock /tmp/opencode/tat2-godot.lock -c 'timeout 1200 tools/godot --headless \
  --path game --script res://tests/test_focus_walk.gd'
```

### Output (identical on all three runs)

```
...
PASS: C3.tutorial the walk visits every control (6/6)
SCRIPT ERROR: Cannot call method 'is_ancestor_of' on a previously freed instance.
          at: _modal_close_check (res://tests/test_focus_walk.gd:203)
          GDScript backtrace (most recent call first):
              [0] _modal_close_check (res://tests/test_focus_walk.gd:203)
              [1] _wait (res://tests/test_focus_walk.gd:34)
PASS: C3.rebind pad interact prints X before the rebind (X)
PASS: C3.rebind the pad glyph follows the rebind X -> Y (Y)
PASS: C3.rebind the authored FTUE rich text prints the rebound glyph ([Y] to pick)
PASS: C3.rebind the authored interact mapping is restored (X)
FOCUS_WALK_SUMMARY: fails=0 checks=64 screens=10
EXIT=0
```

Logs: `/tmp/opencode/focus_walk_run1.log`, `focus_walk_run2.log` and
`focus_walk_run3.log` (run 3 is against the tree as of 15:56, after a concurrent
non-C3 `hud.gd` edit). All three: `EXIT=0`, 64 `PASS:` lines, 1 `SCRIPT ERROR`,
0 `FAIL:`.

### The four vacuity criteria

**(a) Fails if a screen's ring is incomplete — YES.**
`_walk_all()` calls `_check(bool(FocusNavScript.ring_is_complete(walk_root)), ...)`
for every screen. `ring_is_complete()` (`focus_nav.gd:226-244`) returns false if
any of the four `focus_neighbor_*` paths is empty, does not resolve, or resolves
outside the focusable set. It is a real assertion, not a constant.

**(b) Fails if a screen has < 2 controls — YES.**
`_check(controls.size() >= 2, ...)` before the ring checks; the observed counts
are 5/11/3/14/8/3/4/2/2/6 for the ten screens, so the check is exercised.

**(c) Every control visited exactly once and returns to the start — YES.**
`_check(cur == first, ...)` plus `_check(seen.size() == controls.size(), ...)`.
The loop performs exactly `controls.size()` steps and records one entry per
step, so `distinct == N` after `N` insertions is mathematically equivalent to
"each control exactly once". A cycle smaller than N (or a skip) makes
`seen.size() < N` and fails. The walk follows `focus_neighbor_bottom`; combined
with (a) all four axes are asserted resolvable. Correct.

**(d) No `or true` — CONFIRMED.**
`grep -n "or true" game/tests/test_focus_walk.gd game/src/ui/focus_nav.gd` → no
matches. The only `or` is `restored or owner_ctl == null` in the (never-run)
modal check — weak, but not `or true`.

### Why this still fails as a gate

`checks=64` is not 60 (ring) + 3 (modal) + 4 (rebind) = 67. It is 60 + **0** + 4.
The three modal checks are skipped because `_modal_close_check()` evaluates
`settings.is_ancestor_of(owner_ctl)` **after** `close_settings()` has
`queue_free()`d the settings node (`_wait(3)` lets the free run). Calling a method
on the freed `CanvasLayer` aborts the function before the first `_check(...)`
argument is evaluated. Therefore:

- `C3.modal a closed settings panel does not keep the focus owner` — never runs;
- `C3.modal settings ring stays well-formed after close` — never runs;
- `C3.modal the opener can take focus back after the modal closes` — never runs.

It also would have been a weak assertion even without the crash: the test grabs
focus on the **pause opener** immediately before closing settings, never on a
control *inside* settings, so "owner is not inside settings" could not fail from
`release_if_inside` being absent.

`run_tests.gd` suite 107 requires only `exit == 0` and the substring
`FOCUS_WALK_SUMMARY: fails=0`; Godot exits 0 with `SCRIPT ERROR`, so `make test`
would go green on this. This is precisely the "exits 0 despite SCRIPT ERROR"
trap called out in the repo rules.

**Item 1 verdict: FAIL** (the ring walk itself passes (a)-(d); the gate as
advertised is not non-vacuous and the expected `checks=64` is the artifact of
the crash).

---

## 2. `grab_focus` / `focus_neighbor` / `FocusNav` call inventory

`grep -rn "FocusNav\.\|FocusNavScript\.\|grab_focus\|focus_neighbor" game/src/ui/`
gives every call. All `grab_focus` / `focus_neighbor_*` assignments live in
`game/src/ui/focus_nav.gd` itself (`install_and_focus` 149-153, `focus_first`
156-161, `restore` 181-187, `link_ring` 64-84, `link_grid` 88-136). No menu
pokes focus fields directly.

| menu | open path | install call | close path |
|---|---|---|---|
| startscreen | `main_menu.gd` `_build_ui()` from `_ready()` | `694 FocusNavScript.install_and_focus(menu_v)` | n/a |
| settings | `open_settings()` | `settings_ui.gd:133` `install_and_focus(_modal_panel)`; `153` re-ring on tab switch | `141 release_if_inside(_modal_panel)` |
| ledger | `open_ledger()` (and `_ready`) | `ledger_ui.gd:149` `install_and_focus(_panel)`; `137` on ready; `569` re-ring on tab switch | `1037 release_if_inside(_panel)` |
| wardrobe | `open_customizer()` (and `_ready`) | `wardrobe_ui.gd:179` `install_and_focus(self)`; `169` on ready | `186 release_if_inside(self)` |
| map table | `open_table()` | `contract_table_ui.gd:70` `install_and_focus(_panel)`; confirm modal `466 install_and_focus(_confirm_root)` | `660 release_if_inside(_panel)`; confirm `476-479 release + install(_panel) + restore()` |
| mission prep | `open_prep(...)` | `mission_prep_ui.gd:264` `install_and_focus(self)` | `269 release_if_inside(self)` |
| pause | `toggle_pause()` → `_set_paused(true)` | `hud.gd:3828` `install_and_focus(_pause_panel_for_focus)` | `3831 release_if_inside(_pause_panel_for_focus)` on resume |
| post-match | `open_result(...)` | `post_match_ui.gd:124` `install_and_focus(_panel)`; `320` re-ring | `131 release_if_inside(_panel)` |
| progression | `open_progression()` | `progression_ui.gd:105` `install_and_focus(_panel)`; `277` re-ring | `112 release_if_inside(_panel)` |
| tutorial | `open_tutorial()` / `open_category()` | `tutorial_ui.gd:101` and `112` `install_and_focus(_panel)`; `379` re-ring | `119 release_if_inside(_panel)` |

The real openers call these APIs: `mission_controller.gd:2718` `open_table`,
`:1486` `open_customizer`, `:1490` `open_ledger_ui`; `main_menu.gd:717`
`open_tutorial`, `:705` `open_settings`; `ledger_ui.gd:578`
`open_progression`; `hud.gd:2327` `open_result`. **No listed menu is missing.**

Non-menu UI files (`loading_screen`, `mobile_touch_ui`, `tool_preview`,
`ui_toast`, `review_mode`) contain no focusable menu surface, so their absence
is correct.

**Item 2 verdict: PASS.**

---

## 3. Visible focus state is real

`game/src/ui/art_nouveau_theme.gd`:

- `focus_style()` (342-357): `draw_center = false`, `border_color = GOLD`
  (`Color(0.95, 0.80, 0.45, 1.0)`, line 35), `set_border_width_all(2)`,
  corner radius + 2, 2 px expand on all sides.
- `_apply_focus_style()` (360-364): `add_theme_stylebox_override("focus",
  focus_style(...))` **and** `add_theme_color_override("font_focus_color", GOLD)`.
- `style_teal_button` → `focus_mode = Control.FOCUS_ALL` (370) and
  `_apply_focus_style(btn, 4, 10)` (411).
- `style_teal_tab` → `FOCUS_ALL` (417) and `_apply_focus_style` (442).
- `style_teal_option` → `FOCUS_ALL` (466) and `_apply_focus_style` (467).

These three style functions are the ones every menu button/tab/option uses
(53 call sites across `game/src/ui/`; spot-checked post-match 258/268,
progression 195/235, tutorial 227/237/253/375, map-table 213, settings 629/664/835,
mission-prep 558). The test also proves each screen's first control actually
takes `has_focus()` (`C3.<screen> the first control takes focus`, 10/10 PASS).

Not independently pixel-verified: the comment's claim that Godot would draw
*nothing* without the override. The override itself is present and gold/2 px.

**Item 3 verdict: PASS.**

---

## 4. No focus trapped behind a closed modal

The four named modals are implemented in code:

1. **Settings** — `settings_ui.gd:136-145` `close_settings()` calls
   `FocusNavScript.release_if_inside(_modal_panel)` **before** `queue_free()`
   (line 141). It does not restore the opener itself.
2. **Map-table confirm** — `contract_table_ui.gd:469-480` `_hide_confirm()` calls
   `release_if_inside(_confirm_root)`, hides it, `install(_panel)` and
   `restore()`. `_show_confirm()` called `remember()` first (463). The ring is
   rebuilt after the hide.
3. **Ledger → progression modal** — `ledger_ui.gd:574-582` `_open_progression()`
   calls `remember()`, and on `closed` calls `install(_panel)` + `restore()`.
   `progression_ui.gd:111-112` itself `release_if_inside(_panel)`.
4. **HUD pause** — `hud.gd:3825-3832` on resume calls
   `release_if_inside(_pause_panel_for_focus)` before restoring the live HUD.

Additional modals that hide without an explicit release, and their real impact:

- `main_menu.gd:743-800` **credits** modal: no `FocusNav` install at all and
  `layer.queue_free()` on close. Not part of the ten-screen contract; a pad-only
  user can click Close but cannot enter it.
- `hud.gd:3734-3739` **mission letter**: `_close_mission_letter()` only hides
  `_letter_root`; no `release_if_inside`. The Continue button is a themed
  `Button` (`FOCUS_ALL` from `style_teal_button`), so it can be tabbed into.
  An isolated Godot 4.7.2 headless probe confirms that hiding the focused
  control's ancestor clears the viewport focus owner (`owner=null`,
  `has_focus()=false`), so this is not a trap, but focus is not restored either.
- `contract_table_ui.gd:644-652` **return from mission prep**: prep releases
  itself (`mission_prep_ui.gd:269`), but the table does not re-ring/`restore()`
  here; focus is null when the table reappears.
- Settings closed from the startscreen/pause: `release_if_inside` nulls the
  owner but the opener never calls `restore()` in those flows (`main_menu.gd:702-705`,
  `hud.gd:2156-2163`). Focus is lost, not trapped.

**Item 4 verdict: PASS for the four named modals by code inspection.** The
automated proof of this property is the section that crashes (item 1), so the
gate currently provides no runtime evidence for it.

---

## 5. Glyph formatter coverage

`InputGlyphs` is the formatter (`game/src/ui/input_glyphs.gd`): `text`,
`bracket`, `prompt`, `format_legacy`, `format_legend`, `key_label`,
`note_event`, device state (`kb` / `pad` / `touch`). `InputContext._input`
calls `InputGlyphs.note_event(event)` (`input_context.gd:137`).

| required site | status | evidence |
|---|---|---|
| HUD hint bar (`MapPingHintBar`) | **FAIL — hardcoded** | `hud.gd:1602` `ThemeScript.white_keycap("TAB", 10)`; `hud.gd:1616` `white_keycap("MMB", 10)`. No `InputGlyphs` call; never rebuilt. On a pad `map_toggle` is bound to BACK (`project.godot:162-167`) and `ping_menu` to RB (`:156-160`) — the bar still says TAB/MMB. |
| bottom-right action hints | **FAIL — hardcoded** | `thief_character.gd:1256-1274` emits `"key": "LMB"/"RMB"/"4"`; rendered via `white_keycap` at `hud.gd:3184`. |
| crank prompt | PASS | `hud.gd:1429` `InputGlyphs.prompt("secondary_action", loc("Crank"))` |
| pause ESC badge | PASS | `hud.gd:2184` `ThemeScript.keycap(InputGlyphs.bracket("pause"), 12)` |
| lockpick legend | PASS | `hud.gd:1812` and `:3462` `InputGlyphs.format_legend(... LOCKPICK_LEGEND_ACTIONS)`, mapping SPACE→jump, LMB→primary_action, ESC→pause |
| map footer | PASS | `hud.gd:1881` `InputGlyphs.format_legend(... MAP_LEGEND_ACTIONS)`, LMB→primary_action, TAB→map_toggle, ESC→pause |
| ledger tabs | PASS (partial) | `ledger_ui.gd:206/215` `InputGlyphs.key_label("Q"/"E")`, `:226` `InputGlyphs.text("pause")`. Q/E are raw keycodes, so the formatter is used but the labels cannot follow a device |
| wardrobe thief switch | PASS (partial) | `wardrobe_ui.gd:405/413` `key_label("Q"/"E")`, `:509` `text("pause")` — same raw-key limitation |
| map-table difficulty/mode/action hints | **FAIL (partial)** | confirm legend `contract_table_ui.gd:521` still hardcodes `"[H] Difficulty toggle · [R] Mode toggle · [SPACE/F] PREPARE"`; the buttons do use glyphs (`:530` `prompt("jump")`, `:536` `prompt("pause")`, `:271` `text("pause")`, `:255` `key_label("G")`) |
| mission-prep ready/back | PASS | `mission_prep_ui.gd:620/627` and `1523/1526` use `InputGlyphs.text("interact")` / `text("pause")` |

Remaining hardcoded `[KEY]` tokens that should be glyphs (all device-blind;
the HUD manually maps `E→F` at `hud.gd:3941`):

- `game/src/interact/lockable_door.gd:337,339,340,353` — `[E]` pick/close/open,
  `[F] [HOLD] LOCK`
- `game/src/interact/swinging_door.gd:331,333,334,362` — `[F]`
- `game/src/interact/loot_inventory.gd:329,331,333,334` — `[E]`
- `game/src/interact/loot_stash.gd:76,78,79` — `[F]`
- `game/src/interact/world_pickup.gd:119,121,123,124` — `[E]`
- `game/src/ui/settings_ui.gd:457` — `"[Q] / [E] SWITCH TAB · [ESC] BACK"` modal subtitle
- `game/src/ui/hud.gd:1452` — default keycap text `"F"` placeholder (filled from
  the raw prompt token, never from `InputGlyphs`)
- `game/src/ui/hud.gd:1602,1616` — TAB / MMB hint bar (above)

Device-live refresh gap: `InputContext` emits `device_changed`
(`input_context.gd:20,140,144`) but **no UI node connects to it** (`grep -rn
"device_changed" game/` returns only the emitter). Labels built once at screen
construction (map footer, lockpick legend, pause badge, hint bar) keep the device
that was active when they were built; only the settings rebind list re-renders
explicitly.

**Item 5 verdict: FAIL** — the HUD hint bar is a named required site and does not
use `InputGlyphs`; the map-table confirm legend and the interact prompt strings
remain hardcoded.

---

## 6. Rebind assertion and restore

`test_focus_walk.gd:216-238`:

1. `before_pad = InputGlyphs.text("interact", "pad")` → asserted `"X"`.
2. `original: Array[InputEvent] = InputMap.action_get_events("interact")`.
3. erase events, add `InputEventJoypadButton` with `button_index = JOY_BUTTON_Y`.
4. `after_pad == "Y"` asserted.
5. `TutorialText.render('<img id="Interact"/> to pick', "pad")` contains
   `"[Y]"` (the `DT_RichTextInputs` id `Interact` resolves through
   `InputActions.port_id_for_ia` to the port action, then
   `InputGlyphs.bracket(action, device)` — `tutorial_text.gd:146-148`).
6. erase again and re-add every event from `original` in its original order;
   `restored_glyph == before_pad` asserted.

The restore is exact: the same `InputEvent` objects are re-added in the order
`action_get_events` returned; deadzone is untouched; nothing calls
`InputRebinder.persist`, so no on-disk override is written. Two consecutive
processes both printed `before X` / `after Y` / `restored X` — no cross-run leak.

`project.godot:144-149` binds `interact` to physical F + pad button 2 (X), so the
`X → Y` premise is real and a mapping change would fail the first check.

**Item 6 verdict: PASS.**

---

## 7. `TAT2_UI_NO_STAGE` hook

Only two production sites, both env-gated (`OS.has_environment`):

- `main_menu.gd:81` — skips `_build_3d_backdrop()` only; `_build_ui()` and
  `_maybe_autostart_contract()` always run. The skipped function builds a
  `SubViewportContainer` + `SubViewport` + `Node3D` level loader (`:153-183`).
- `mission_prep_ui.gd:409` — skips the `SubViewportContainer`
  "PrepBackdropContainer" + `SubViewport` + `_build_stage()` (3D `Node3D`,
  lights, `WorldEnvironment`). Everything after (shade, header, cards, buttons)
  is always built.

`grep -rn "TAT2_UI_NO_STAGE" game/ tools/ docs/` shows only the two hooks and
`test_focus_walk.gd:49,54`; no shipped run path or `tools/godot` sets it.

Nuance: the skipped `SubViewportContainer` *is* a `Control` subclass, contrary to
the comment's literal "never a Control". It is a mouse-ignore, non-focusable
(default `FOCUS_NONE`) backdrop wrapper containing only 3D nodes; no interactive
menu Control is skipped, and the prep ring still has its 3 action buttons. Also
the hook is env-gated, not `DisplayServer.get_name() == "headless"`-gated: an
operator who exported `TAT2_UI_NO_STAGE` would lose the backdrop. Neither is a
contract violation in the shipped path.

**Item 7 verdict: PASS** (with the two notes above).

---

## 8. No test weakened

```bash
git diff --numstat 8ce9a86 -- game/tests/
# 27  0  game/tests/run_tests.gd
```

The entire tracked test diff is 27 added lines (suites 106-109 in `run_tests.gd`,
which spawn the four W9-P3 standalone suites and require exit 0 + summary
marker). Zero deletions, zero modified expectations. The new suites
(`test_focus_walk.gd`, `test_w9p3_screens.gd`, `test_w9p3_map_toast.gd`,
`test_w9p3_localization.gd`) are untracked new files in this worktree, not edits
to existing tests. (`probe_w9p3_text_dump.gd` also appeared untracked during the
audit and was removed again by its author; it is not part of the C3 gate.)

**Item 8 verdict: PASS.**

---

## Findings summary

| id | severity | finding |
|---|---|---|
| F1 | **blocker (gate)** | `test_focus_walk.gd:203` calls `is_ancestor_of` on the freed settings `CanvasLayer`; `_modal_close_check()` aborts, its 3 checks never run, and `checks=64` (60 ring + 4 rebind) is mistaken for a full run. Exit 0 + summary substring keeps `run_tests` 107 green. Fix: read the focus owner and capture `settings` validity *before* `await`, or check `is_instance_valid(settings)` and use the panel node while it lives; then the run should report 67 checks with 0 modal errors. |
| F2 | **scope miss** | HUD hint bar `TAB`/`MMB` (and bottom-right `LMB`/`RMB`/`4`) are hardcoded and wrong on a pad (BACK/RB). Use `InputGlyphs.bracket("map_toggle"/"ping_menu"/...)` and rebuild on `device_changed`. |
| F3 | partial | Map-table confirm legend `[H]/[R]/[SPACE/F]` hardcoded; door/pickup prompt strings hardcoded and the HUD rewrites `E→F` by hand, so a pad sees `F`. No `device_changed` listener anywhere, so even formatted labels do not re-render on a mid-session device swap. |
| F4 | minor | Settings/credits/mission-letter/prep-return paths release or lose focus but do not restore the opener; not a trap (Godot 4.7.2 clears focus when the owner is hidden — verified in an isolated probe), but the pad is dead until the next click/tab. |

## Commands used (all headless, serialized on `/tmp/opencode/tat2-godot.lock`)

```bash
# gate, twice (identical output/exit)
flock /tmp/opencode/tat2-godot.lock -c 'timeout 1200 tools/godot --headless \
  --path game --script res://tests/test_focus_walk.gd'
# -> EXIT=0; 64 PASS; 1 SCRIPT ERROR at test_focus_walk.gd:203; 0 C3.modal checks
# -> FOCUS_WALK_SUMMARY: fails=0 checks=64 screens=10 (both runs)

grep -rn "FocusNav\.\|FocusNavScript\.\|grab_focus\|focus_neighbor" game/src/ui/
grep -n "or true" game/tests/test_focus_walk.gd game/src/ui/focus_nav.gd
grep -rn "InputGlyphs" game/src/ui game/src/player game/src/interact game/src/missions
grep -rn "device_changed" game/                      # only the emitter
grep -rn "TAT2_UI_NO_STAGE" game/ tools/ docs/       # 2 hooks + the test
git diff --numstat 8ce9a86 -- game/tests/            # 27/0 run_tests.gd
git diff 8ce9a86 -- game/tests/                      # additive only
```

---

## Re-audit (3a9aa34)

- **Tree:** `3a9aa34` (`w9(p3): authored screens, Loc wiring, pad focus, TAB map + toast`)
  on `rem/w9-p3`; `git diff --stat HEAD -- game/src game/tests` is empty, so the
  source/tests below are the committed tree.
- **Scope:** only the C3 findings F1/F5 and the F4 caveat. No source/test edits.
- **Result:** F1 **FIXED**, F5 **FIXED**, F4 **minor gap remains (not a trap)**.

### F1 — gate crash + skipped modal checks: **FIXED**

`test_focus_walk.gd:202-220` now guards the freed settings node:
`is_instance_valid(settings) and settings.is_inside_tree()` before
`is_ancestor_of`, an explicit `is_instance_valid` branch for the ring check, and
a clean fallback for a missing opener.

Command (twice back-to-back, same lock; logs in `/tmp/opencode/c3-reaudit/`):

```bash
for n in 1 2; do
  flock /tmp/opencode/tat2-godot.lock -c 'timeout 1200 tools/godot --headless \
    --path game --script res://tests/test_focus_walk.gd' \
    > /tmp/opencode/c3-reaudit/run$n.log 2>&1
done
```

Both runs, identical:

```
PASS: C3.modal a closed settings panel does not keep the focus owner
PASS: C3.modal the freed settings panel owns no focus ring
PASS: C3.modal the opener can take focus back after the modal closes
FOCUS_WALK_SUMMARY: fails=0 checks=67 screens=10
```

- `EXIT=0`; `grep -c "SCRIPT ERROR\|is_ancestor_of"` = **0**.
- 67 `PASS:` lines. Category counts: 6 × 10 screens = 60 ring checks, 4 rebind,
  **3 modal** → **64 → 67 is exactly the three modal checks**; nothing else
  changed. `screens=10` unchanged.
- **FIXED.** Residual observation (not a blocker): because `_wait(3)` still runs
  after `close_settings()` `queue_free()`s the panel, the panel is already freed
  when observed. The run takes the `else` branch at lines 215-216
  (`_check(true, "the freed settings panel owns no focus ring")`, a constant),
  and the containment check at lines 210-211 is false by construction (a freed
  panel cannot be an ancestor). Only the restore assertion at lines 217-220 has
  test content. The crash and the silent skip are gone; the release assertion is
  still structurally weak. A stronger form would capture the focus owner and
  `ring_is_complete(settings)` *before* the `await`/free.

### F5 — device glyphs: **FIXED**

Code (committed tree):

- `hud.gd:1648` / `:1664` — hint keycaps built from
  `InputGlyphs.text("map_toggle")` / `InputGlyphs.text("ping_menu")`, labels
  retained in `_hint_map_key_lbl` / `_hint_ping_key_lbl` (`:1649`, `:1665`).
- `hud.gd:1039-1049` `_on_input_device_changed()` re-texts the hint keys, the
  pause badge (`InputGlyphs.bracket("pause")`) and the map footer
  (`InputGlyphs.format_legend(... MAP_LEGEND_ACTIONS)`); map footer label kept at
  `:1930`, pause badge label at `:2236`.
- Connected in `_ready` to `/root/InputContext.device_changed` (`:890-893`);
  disconnected in `_exit_tree` (`:1059-1060`).

Probe (isolated headless scene, `--path game`, never touches the repo):

```
PROBE connected_after_ready=true
PROBE signal map=[VIEW] ping=[RB] esc=[[MENU]]
PROBE footer=[[RT] PLACE WAYPOINT   ·   [VIEW] / [MENU] CLOSE MAP]
PROBE connected_after_free=false hud_valid=false
```

For comparison, the same probe with `InputGlyphs.set_device("kb")`:
`map=[TAB] ping=[MMB] esc=[[ESC]] footer=[[LMB] … [TAB] / [ESC] …]`. The
signal-driven path (not just a direct method call) changes all four labels, and
the connection is gone after `queue_free()`.

- Remaining `[H]` / `[R]` hint: documented port copy at
  `contract_table_ui.gd:519-520` (“port’s own two-toggle confirm hint … stay
  fixed tokens”). **Confirmed as port copy.** Nit: the parenthetical “no
  InputMap action” is inaccurate — `R` is bound to `secondary_interact` and `H`
  to `melee_toggle` in `game/project.godot`; the correct justification is that
  the modal’s *toggle* handlers read raw `KEY_H`/`KEY_R` and have no action.
- `thief_character.gd` keycaps (`:1256-1274`, `"LMB"/"RMB"/"4"`):
  `git diff --stat 8ce9a86 3a9aa34 -- game/src/player/thief_character.gd` is
  empty (file untouched by the fix). It is listed as P2-owned in
  `build/qa/w9/p3-report.md:290` (“remaining audit items … `thief_character.gd`’s
  bottom-right keycaps (P2)”). Note: it is *not* in
  `tools/consumer_allowlist.json` and not tagged `BLOCKED-ON P2` the way
  `loot_item.gd` is — the P2 ownership is only in the report sentence.

- **FIXED** on the code and behaviour checks; the P2 item and the `[H]/[R]`
  wording remain open by design.

### F4 caveat — settings / prep-return focus: **NOT TRAPPED (requirement met); restore gap remains**

- `settings_ui.gd:141` still calls `FocusNavScript.release_if_inside(_modal_panel)`
  before `queue_free()`; `mission_prep_ui.gd:269` releases on `close_prep()`.
  Focus is therefore never trapped behind the closed panel (owner becomes null).
- Still no opener restore in `main_menu.gd:701-705` or the HUD pause settings
  button, and `contract_table_ui.gd:645-652` (`_on_prep_closed`) re-shows the
  table without `install(_panel)`/`restore()`. A pad user must click/tab once
  after the modal closes. Unchanged minor gap, no trap.

### Cross-run leak

Two consecutive processes both printed
`C3.rebind pad interact prints X before the rebind (X)` →
`… X -> Y (Y)` → `… restored (X)`; the mapping is saved/re-added exactly, and
both runs reported `67/0`. No leak.

### Updated audit verdict

The two findings that made the first audit fail are fixed on `3a9aa34`
(F1 and F5), and the F4 caveat is a minor UX gap with no focus trap. Remaining
items are documented port copy and a P2-owned file.

**AUDIT: PASS**
