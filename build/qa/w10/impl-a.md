# IMPL-A — W10 Wave A defects 1–5, implementation record

**Worker:** IMPL-A · **Tree:** `/home/john/Projects/TAT-2-rem-w10-a` (branch `w10/a`, HEAD `29046c8`)
**Date:** 2026-11-25 · **Scope:** the five UI defects in INV-1
(`build/qa/w10/inv-1-screens.md`), red suite `game/tests/test_w10_screens.gd`
(17 fails / 39 checks before these edits).

**Verification status of this document: the lead runs the suite.** I edited files only.
I launched **no Godot process** (the lane's one in-flight run was watched until it
exited before the first edit; see "Process discipline"), ran **no test**, and edited
**no test file**. The per-check reasoning below is a code argument against the named
assertions, not a measured pass. Syntax was checked with `gdlint 4.5.0` (parser, not
Godot): all five files parse; it reports only the repository's pre-existing style
findings (long lines, HUD return counts), none introduced by these edits except one
line of pre-existing text that moved into an `else` branch unchanged.

Files changed (only the five owned files):

| File | Lines added | Defect |
|---|---|---|
| `game/src/ui/post_match_ui.gd` | +41/−9 | 1, 3, 4 |
| `game/src/ui/hud.gd` | +77/−10 | 1, 3, 4, 5 |
| `game/src/ui/main_menu.gd` | +25/−2 | 2 |
| `game/src/ui/progression_ui.gd` | +7/−0 | 3 |
| `game/src/ui/focus_nav.gd` | +22/−0 | 3 (shared hook) |

---

## 1. `PostMatchUI.continue_requested` had no consumer — INV-1a.2 / 1a.4 / 1a.6

**`game/src/ui/post_match_ui.gd:127-142`.** `close()` now delegates to a private
`_close(with_cue: bool)`. The body is byte-identical to the old `close()` except the
`_play_ui("back")` call is conditional. Every existing caller (`_back_btn`,
`_unhandled_input`, tests that call `close`) keeps the authored back cue.

**`game/src/ui/post_match_ui.gd:670-679`.** `_on_continue_pressed()` plays the click,
then `continue_requested.emit()`, then `_close(false)`. The silent close avoids a
click + back cue stack on one press. This makes the button close the screen on its
own, which is exactly what **INV-1a.2** drives on a standalone `PostMatchUI` (open,
find `ContinueButton`, emit `pressed`, two frames, `is_open()` must be false).

**`game/src/ui/hud.gd:2410-2413`.** `_open_post_match_xp()` connects
`continue_requested` to `_on_post_match_continue` (and keeps `closed` on the new
`_on_post_match_closed`). **INV-1a.4** reads
`get_signal_connection_list("continue_requested")` on the live HUD-created instance
and requires `>= 1`; that list is now length 1.

**`game/src/ui/hud.gd:2421-2443`.** `_on_post_match_continue()` closes the HUD-owned
screen when `is_open()` is still true (idempotent with the screen's own close) and
then `_restore_result_focus()`. `_on_post_match_closed()` does the same hand-back for
the Back/ESC path. `_restore_result_focus()` mirrors the old inline `closed` lambda
(`FocusNav.install(_root)` + `restore()`) and adds a fallback to `_result_xp_btn`
because `restore()` is a no-op when the remembered control was removed with a
replaced screen (defect 5). **INV-1a.4/1a.6** are satisfied without touching the Den
transition: the result panel's own `_result_continue_btn` still owns
`_continue_to_den()`, and this button never changes scene.

## 2. Main-menu focus restore after Settings / Tutorial — INV-1b.4/1b.5/1b.8/1b.9

**`game/src/ui/main_menu.gd:53`** adds `_menu_v: VBoxContainer`; **`:632`** assigns it
in `_build_ui()` (it was the local `menu_v`, so the handlers previously had no root to
re-install).

**`game/src/ui/main_menu.gd:707-718`** and **`:731-742`** connect each child's
`closed` signal to `_on_modal_closed` before opening. **`:723-725`**
`_on_modal_closed()` is `FocusNav.install(_menu_v)` then `FocusNav.restore()` — the
same order as the HUD's pause-menu Settings handler. Pad-only: no mouse events, no
`grab_focus` on a named button; `restore()` targets whatever the player had focused
when the modal opened.

This satisfies **INV-1b.4/1b.5** (`SettingsUI.close_settings()`:
`release_if_inside()` → `closed.emit()` → handler re-grabs the remembered menu
control) and **INV-1b.8/1b.9** (`TutorialUI.close()`: release → emit → same handler).
`SettingsUI` frees itself after the emit; `TutorialUI` only hides, so the handler
deliberately owns focus only (no lifetime change there).

## 3. ESC on PostMatch/Progression also opened pause — INV-1c.2/1c.6 (1c.8 preserved)

**`game/src/ui/focus_nav.gd:33-41, 176-183`.** Shared frame stamp:
`static var _escape_consumed_frame` plus `mark_escape_consumed()` /
`escape_consumed_this_frame()`. The stamp stores
`Engine.get_process_frames()` and the predicate compares the exact
frame, so it cannot outlive its frame and needs no reset — the same monotonic
argument as the lockpick `_pause_consumed_frame`. It lives on `FocusNav` because
Progression's live opener is the Ledger (`ledger_ui._open_progression()`), not the
HUD, so a HUD-side `closed` connection could not cover **INV-1c.6**.

**`game/src/ui/post_match_ui.gd:161-170`** and **`game/src/ui/progression_ui.gd:136-142`**
call `FocusNavScript.mark_escape_consumed()` immediately before `close()` and before
`set_input_as_handled()`. **`game/src/ui/hud.gd:2900-2914`** adds
`elif FocusNavScript.escape_consumed_this_frame(): pass` to the `pause` branch,
directly after the lockpick stamp check and before `_toggle_pause()`.

**INV-1c.2/1c.6** deliver the ESC in the same frame as the hand-driven
`hud._process`, so the pause poll skips. **INV-1c.8** presses pause on a later frame:
the stored frame number no longer matches, the `elif` is false, and `_toggle_pause()`
runs — the guard is per-frame, not a blanket pause disable.

## 4. Timeout / collapse rendered as "Caught" — INV-1d.1–1d.3, 1d.5–1d.7

**`game/src/ui/hud.gd:2340-2353`.** `show_result()` branches before the
Escaped/Caught fallback: when `info.get("timed_out", false)` is true and
`timeout_reason` is non-empty, `result_lbl` is that reason uppercased; otherwise the
authored `PostMatch.Status.Escaped/Caught` rows are unchanged.

**`game/src/ui/post_match_ui.gd:328-341`.** `_refresh()` does the same with `_info`,
which `open_result()` already receives from the HUD's `_last_info` — no signature
change.

The strings are the producer's port constants `TIME_EXPIRED_REASON` /
`DOOR_COLLAPSED_REASON` (`mission_controller.gd:97-98`, set in `_finish_run` and
passed by `_on_door_collapsed`), not a new table key and not a new literal in
`game/src/ui/` — the values come from `info`. **INV-1d.4/1d.8/1d.9** stay green
because the timeout branch requires both the flag and a non-empty reason; `{}` and
normal capture/escape records fall through to the authored rows.

## 5. Repeated opens stacked `PostMatchUI` layers — INV-1e.1/1e.2

**`game/src/ui/hud.gd:343`** adds `_post_match_ui: CanvasLayer`.
**`game/src/ui/hud.gd:2391-2406`** (`_open_post_match_xp`) releases focus from any
live instance, `remove_child()` then `queue_free()` it, clears the member, and only
then remembers/creates the new screen. `remove_child` is immediate, so the HUD's
child list holds exactly one rack-up at all times; **INV-1e.1** (count) and
**INV-1e.2** (visible count) both read 1 after two opens.

`PostMatchUI.close()` still does **not** free itself: `test_w9p3_screens.gd` reads
`is_open()` after close. Lifetime stays with the HUD, which is the only owner that
creates these screens.

---

## Process discipline

- `pgrep -af "[g]odot.*--path game"` was non-empty on arrival (the lane's
  `test_w10_runtime.gd` d10 run). I waited for it to exit, confirmed empty, and made
  the first edit only then. I launched no Godot afterwards — the lead's acceptance
  run is the only one this tree should see.
- No test file was opened for writing; `game/tests/test_w10_screens.gd` is untouched
  (`git status` shows it as untracked, as it was on arrival, and unmodified by me).
- Nothing outside the five owned files and this report was written. No commit, push,
  checkout, reset or stash. `/home/john/Projects/TAT-2` was never written to.
- No new English copy literals in `game/src/ui/`: the only new strings are signal and
  method identifiers (`"is_open"`, `"close"`, `"continue_requested"`, `"closed"`) and
  empty-string fallbacks; the timeout text is data from `info`.
- **Not verified by me:** the suite result, compile gate, literal grep gate and all
  other wave gates. The lead must run them; this record claims only the code paths
  above.
