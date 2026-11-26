# INV-1 — five reported UI defects: reproduction fact sheet (W10-A)

**Worker:** INV-1 · **Tree:** `/home/john/Projects/TAT-2-rem-w10-a` (branch `w10/a`,
HEAD `29046c8`) · **Date:** 2026-11-25 · **Scope:** investigation only; no game
source was modified.

**Red suite:** `game/tests/test_w10_screens.gd` (new file, standalone
`SceneTree`). **Command (the only way it was run):**

```bash
cd /home/john/Projects/TAT-2-rem-w10-a
flock /tmp/opencode/tat2-godot.lock -c \
  "timeout 900 tools/godot --headless --path game --script res://tests/test_w10_screens.gd"
```

**Result on the current tree (red proof):**

```
W10_SCREENS_SUMMARY: fails=17 checks=39
EXIT=1
```

Godot `v4.7.2.stable.official.ed1daf0bf`. All five reported defects reproduced.
Nothing in the report failed to reproduce; two small corrections to the report's
file/identifier wording are noted in §7.

> **Commit note for the lead:** this fact sheet is under `build/qa/w10/`, which
> `.gitignore` ignores (`build/qa/*`; only `*.gd`/`*.sh`/`*.py` are un-ignored).
> It needs `git add -f build/qa/w10/inv-1-screens.md`, exactly as the tracked
> `build/qa/w9/*.md` evidence was added. The suite
> `game/tests/test_w10_screens.gd` is not ignored.

| # | Defect | Red checks | Verdict |
|---|---|---|---|
| 1 | `PostMatchUI.continue_requested` has no consumer | `1a.2`, `1a.4`, `1a.6` | **reproduced** |
| 2 | Main-menu focus not restored after Settings/Tutorial | `1b.4`, `1b.5`, `1b.8`, `1b.9` | **reproduced** |
| 3 | ESC on PostMatch/Progression also opens the pause menu | `1c.2`, `1c.6` | **reproduced (both screens)** |
| 4 | Timeout/collapse renders as "Caught" | `1d.1`–`1d.3`, `1d.5`–`1d.7` | **reproduced (both renderers)** |
| 5 | Repeated opens stack `PostMatchUI` layers | `1e.1`, `1e.2` | **reproduced** |

The suite also keeps four **negative controls** that already pass and must stay
green after the fixes: normal capture still renders `CAUGHT` (`1d.4`, `1d.8`),
escape still renders `ESCAPED` (`1d.9`), and a later pause press with no screen
open still pauses (`1c.8`) — i.e. the ESC fix must not become a blanket pause
disable, and the timeout fix must not rename the capture vocabulary.

---

## 1. `continue_requested` has no consumer

**Where:** `game/src/ui/post_match_ui.gd:20` (signal), `:642-644`
(`_on_continue_pressed()` only emits), `game/src/ui/hud.gd:2369-2383`
(`_open_post_match_xp()` connects `closed` only). The only grep hit for the
signal in the whole tree is its own emit — there is no `connect` at all.

**Observed (verbatim):**

```
FAIL: INV-1a.2 pressing Continue closes the post-match screen | is_open=true
FAIL: INV-1a.4 the HUD connects continue_requested (connections=0)
FAIL: INV-1a.6 pressing Continue closes the HUD post-match screen | valid=true is_open=true
```

The failing path is a real node call: `INV-1a.2` opens a standalone
`PostMatchUI`, finds the real `ContinueButton` (named node), emits `pressed` and
waits two frames; the screen stays open. `INV-1a.4` opens the screen through
`hud._open_post_match_xp()` and reads
`get_signal_connection_list("continue_requested")` on that live instance (0
connections), then `INV-1a.6` presses the same button on the HUD-created
instance and waits. No grep is used for either assertion.

**Intended fix (1-2 sentences):** make the press actually close the rack-up
(e.g. `_on_continue_pressed()` emits and then `close()`), and have
`hud._open_post_match_xp()` consume the signal as well as `closed` so the
HUD-owned instance is closed/freed and focus is returned. The test does **not**
require the Den transition from this button (the result panel's own Continue
already owns `_continue_to_den()`); a consumer that changes scene is tolerated
only because the check runs last, but closing the XP screen is the smaller,
intended path.

---

## 2. Main-menu focus is not restored after Settings/Tutorial

**Where:** `game/src/ui/main_menu.gd:701-717` (`FocusNavScript.remember()` on
open, no `closed` connection and no `restore()`), `settings_ui.gd:136-145`
(`release_if_inside()` → `closed.emit()` → `queue_free()`), `tutorial_ui.gd:115-121`
(same release/emit/shutdown). The correct pattern is `hud.gd:2204-2213`
(remember → connect `closed` → `FocusNav.install(panel)` + `restore()`).

**Observed (verbatim):**

```
FAIL: INV-1b.4 focus is restored after Settings closes (owner=null)
FAIL: INV-1b.5 the restored focus owner is inside the main menu
FAIL: INV-1b.8 focus is restored after the Tutorial closes (owner=null)
FAIL: INV-1b.9 the restored focus owner is inside the main menu
```

Driven exactly as the brief requires (pad-only, no mouse events): the real
startscreen `Control` is built with the documented `TAT2_UI_NO_STAGE=1` hook,
`_on_settings_pressed()` / `_on_tutorial_pressed()` are called, the resulting
`SettingsUI` / `TutorialUI` child is found, its real `close_settings()` /
`close()` is called, and `root.gui_get_focus_owner()` is read after frames. The
modal itself takes focus while open (`1b.3`, `1b.7` PASS), so only the restore
step is missing. `1b.1` proves the menu could take focus before the modal.

**Intended fix (1-2 sentences):** connect each child's `closed` signal in
`_on_settings_pressed()` / `_on_tutorial_pressed()` to a handler that calls
`FocusNavScript.install(...)` (or `restore()`) so the remembered opener is
re-focused after `release_if_inside()`; mirror `hud.gd:2204-2213` and free the
closed modal.

---

## 3. ESC on PostMatch/Progression also opens the pause menu behind it

**Where:** `post_match_ui.gd:144-154` and `progression_ui.gd:125-135` close on
ESC and call `get_viewport().set_input_as_handled()`, but the HUD polls the
`pause` action in `_process` (`hud.gd:2841-2863`) and `set_input_as_handled()`
does not clear `Input.is_action_just_pressed()`. The lockpick guard is
`hud.gd:2742` (`_pause_consumed_frame = Engine.get_process_frames()`) checked at
`:2841-2846`. `progression_ui.gd` has no consumer connected at its live entry
point either (`ledger_ui.gd:574-584` connects `closed` for focus only).

**Observed (verbatim):**

```
FAIL: INV-1c.2 ESC on the HUD post-match screen must not open the pause menu behind it (paused=true)
FAIL: INV-1c.6 ESC on Progression must not open the pause menu behind it (paused=true)
```

Play order is preserved: the suite presses the `pause` action, delivers a real
`InputEventKey` (KEY_ESCAPE, non-echo) to the screen's `_unhandled_input`, then
calls `hud._process(0.016)` once. The screen does close (`1c.3`, `1c.7` PASS),
which is why the bug is the pause menu behind it. `1c.8` then proves the guard
is not a blanket disable: on a later frame with no screen open the same pause
press **does** pause the tree, and `1c.9` restores it.

**Intended fix (1-2 sentences):** give the screens a way to stamp the frame the
pause poll must ignore (the lockpick's `_pause_consumed_frame` protocol) when
their `_unhandled_input` consumes ESC, and have `hud._process` skip the `pause`
action on that stamp. Because Progression is opened by the Ledger
(`ledger_ui.gd:574`) and not by the HUD, a per-screen `closed` connection inside
`_open_post_match_xp()` alone will not cover `1c.6`; the stamp needs a shared
hook the screens can reach (e.g. a `GameState` frame field, or a HUD lookup)
rather than only the PostMatch open path.

---

## 4. Timeout / door collapse render as "Caught"

**Where:** `post_match_ui.gd:309-313` (`status_key` is only
`PostMatch.Status.Escaped` / `PostMatch.Status.Caught`), `hud.gd:2319-2350`
(identical binary choice at `:2335-2336`). The producer sets
`contract_info["timed_out"] = true` and `contract_info["timeout_reason"]` in
`mission_controller.gd:4656-4657` (`TIME EXPIRED`, `MAGIC DOOR COLLAPSED`; the
constants are `mission_controller.gd:97-98` and `:4688` passes the collapse
reason; the client-side mirror is `:240`). Note: the report's `_short_status`
helper **does not exist** — the actual HUD status key is `hud.gd:2335`; see §7.

**Observed (verbatim):**

```
FAIL: INV-1d.1 PostMatchUI timeout renders TIME EXPIRED | status='CAUGHT'
FAIL: INV-1d.2 PostMatchUI timeout does not render CAUGHT | status='CAUGHT'
FAIL: INV-1d.3 PostMatchUI door collapse renders MAGIC DOOR COLLAPSED | status='CAUGHT'
FAIL: INV-1d.5 HUD result timeout renders TIME EXPIRED | status='CAUGHT'
FAIL: INV-1d.6 HUD result timeout does not render CAUGHT | status='CAUGHT'
FAIL: INV-1d.7 HUD result door collapse renders MAGIC DOOR COLLAPSED | status='CAUGHT'
```

Both paths were driven with the real public API:
`PostMatchUI.open_result(false, 0, {"timed_out": true, "timeout_reason": ...}, 0)`
and `hud.show_result(false, 0, {"timed_out": true, "timeout_reason": ...})`; the
status `Label` text is read back from the live node. Normal capture remains
`CAUGHT` (`1d.4`, `1d.8` PASS) and escape remains `ESCAPED` (`1d.9` PASS), so
the red is specifically the timeout branch, not a broken status vocabulary.

**Intended fix (1-2 sentences):** before the Escaped/Caught fallback, branch on
`info.get("timed_out", false)` and render
`info.get("timeout_reason", ...)` (uppercased like the existing rows) in both
`hud.show_result()` and `PostMatchUI._refresh()`; keep the authored
`CAUGHT`/`ESCAPED` rows unchanged for the non-timeout outcomes.

---

## 5. Repeated opens stack hidden `PostMatchUI` CanvasLayers

**Where:** `hud.gd:2369-2383` constructs `script.new()` on every
`_open_post_match_xp()` and never checks for an existing child;
`post_match_ui.gd:127-133` only sets `visible = false` on close (no `queue_free`,
and the HUD's `closed` handler at `hud.gd:2379-2382` only restores focus), so
even an open→close→open cycle leaves the old layer in the tree.

**Observed (verbatim):**

```
FAIL: INV-1e.1 exactly one PostMatchUI lives under the HUD after two opens (2)
FAIL: INV-1e.2 exactly one PostMatchUI is visible after two opens (2)
```

The suite calls the real HUD open path twice (two frames apart) and counts
direct children whose `get_script().resource_path` is
`res://src/ui/post_match_ui.gd`, plus their `CanvasLayer.visible` flags. Both
opens are visible: the second covers the first, which is why the defect is not
merely cosmetic. The named "hidden" variant (open → close → open) is
code-verified by `hud.gd:2369-2383` + `post_match_ui.gd:127-133` rather than
separately measured, because the deliverable's required assertion is the
double-open count.

**Intended fix (1-2 sentences):** reuse an existing `PostMatchUI` child (call
`open_result()` again on it) or free/replace the previous instance before the
new one is added, so the HUD owns at most one post-match screen; the test
requires exactly one child and exactly one visible instance after two opens.

---

## 6. Run inventory / check-to-defect map

Check names are stable so the implementer can rerun individual groups.

| Check | Defect | What it drives |
|---|---|---|
| `1a.0`–`1a.2` | 1 | standalone `PostMatchUI`, real `ContinueButton.pressed` |
| `1b.0`–`1b.9` | 2 | main menu `_on_settings_pressed` / `_on_tutorial_pressed`, real `close_settings()` / `close()` |
| `1c.0`–`1c.3` | 3 | HUD → `_open_post_match_xp()` → ESC key → `hud._process(0.016)` |
| `1c.4`–`1c.7` | 3 | `ProgressionUI` under the HUD → ESC key → `hud._process(0.016)` |
| `1c.8`–`1c.9` | 3 (negative control) | later pause press with no screen open must still pause |
| `1d.1`–`1d.4` | 4 | `PostMatchUI.open_result(...)` timeout/collapse + normal capture |
| `1d.5`–`1d.9` | 4 (HUD half + controls) | `hud.show_result(...)` timeout/collapse/capture/escape |
| `1e.1`–`1e.2` | 5 | two HUD opens → child count and visible count |
| `1a.3`–`1a.6` | 1 (HUD half) | HUD-opened instance: connection list + real button press |
| `1.0` | harness | `hud.gd` builds headlessly (same recipe as `test_lockpick_cancel.gd`) |

No existing test or game source was edited, skipped or weakened.

---

## 7. Corrections / notes (nothing failed to reproduce)

1. **`_short_status` does not exist.** The report cites "`_short_status`/status
   key at ~:2337" in `hud.gd`; the actual code is
   `var status_key: String = "PostMatch.Status.Escaped" if won else
   "PostMatch.Status.Caught"` at `hud.gd:2335-2336`. The defect itself
   reproduces exactly as described; only the helper name is wrong.
2. **Defect 5's "hidden" wording.** The double-open repro yields two **visible**
   `PostMatchUI` instances (the second covers the first). The hidden-layer case
   is real but occurs on open→close→open because `close()` only hides
   (`post_match_ui.gd:127-133`) and nothing frees the child; it is cited from
   code, not separately asserted, per §5.
3. **Teardown noise.** The red run ends with
   `WARNING: 18 ObjectDB instances were leaked at exit` and
   `ERROR: 6 resources still in use at exit` because the suite quits with
   screens freed on the last frames (static theme/font caches included). This is
   teardown noise, not a claim: every node the suite creates is `queue_free()`d,
   and the pass/fail evidence is the `W10_SCREENS_SUMMARY` line and exit code.
4. **Green-run caveat for defect 1.** If the consumer chosen for
   `continue_requested` calls `_continue_to_den()` (scene change), the press is
   the suite's last action and `1a.6` tolerates the freed screen, but a deferred
   `mission.tscn` load would run before `quit()`. Prefer closing the XP screen
   only (the result panel's own Continue already owns the Den transition).
5. **The two timeout reasons are literals in `mission_controller.gd:97-98`**
   (`TIME EXPIRED`, `MAGIC DOOR COLLAPSED`); the assertions check for those
   exact strings, not a re-derived vocabulary.

---

## Appendix — raw red output (stdout+stderr, init/boot lines elided)

Full run output is reproducible with the command at the top; the pass/fail
block was:

```
PASS: INV-1a.0 post_match_ui.gd loads
PASS: INV-1a.1 the Continue button exists (ContinueButton)
FAIL: INV-1a.2 pressing Continue closes the post-match screen | is_open=true
PASS: INV-1b.0 main_menu.gd loads
PASS: INV-1b.1 the menu can take focus before opening a modal
PASS: INV-1b.2 SettingsUI opened as a child of the menu
PASS: INV-1b.3 settings takes focus while open
FAIL: INV-1b.4 focus is restored after Settings closes (owner=null)
FAIL: INV-1b.5 the restored focus owner is inside the main menu
PASS: INV-1b.6 TutorialUI opened as a child of the menu
PASS: INV-1b.7 tutorial takes focus while open
FAIL: INV-1b.8 focus is restored after the Tutorial closes (owner=null)
FAIL: INV-1b.9 the restored focus owner is inside the main menu
FAIL: INV-1d.1 PostMatchUI timeout renders TIME EXPIRED | status='CAUGHT'
FAIL: INV-1d.2 PostMatchUI timeout does not render CAUGHT | status='CAUGHT'
FAIL: INV-1d.3 PostMatchUI door collapse renders MAGIC DOOR COLLAPSED | status='CAUGHT'
PASS: INV-1d.4 PostMatchUI normal capture still renders CAUGHT
PASS: INV-1.0 hud.gd loads and builds headlessly
FAIL: INV-1d.5 HUD result timeout renders TIME EXPIRED | status='CAUGHT'
FAIL: INV-1d.6 HUD result timeout does not render CAUGHT | status='CAUGHT'
FAIL: INV-1d.7 HUD result door collapse renders MAGIC DOOR COLLAPSED | status='CAUGHT'
PASS: INV-1d.8 HUD normal capture still renders CAUGHT
PASS: INV-1d.9 HUD escape still renders ESCAPED
PASS: INV-1c.0 the HUD opened a PostMatchUI
PASS: INV-1c.1 the HUD post-match screen is open
FAIL: INV-1c.2 ESC on the HUD post-match screen must not open the pause menu behind it (paused=true)
PASS: INV-1c.3 ESC still closes the post-match screen
PASS: INV-1c.4 progression_ui.gd loads
PASS: INV-1c.5 the progression screen is open
FAIL: INV-1c.6 ESC on Progression must not open the pause menu behind it (paused=true)
PASS: INV-1c.7 ESC still closes the progression screen
PASS: INV-1c.8 a later pause press with no screen open still pauses (paused=true)
PASS: INV-1c.9 pause closed again for a clean exit
FAIL: INV-1e.1 exactly one PostMatchUI lives under the HUD after two opens (2)
FAIL: INV-1e.2 exactly one PostMatchUI is visible after two opens (2)
PASS: INV-1a.3 the HUD opened a PostMatchUI
FAIL: INV-1a.4 the HUD connects continue_requested (connections=0)
PASS: INV-1a.5 the HUD post-match screen has a Continue button
FAIL: INV-1a.6 pressing Continue closes the HUD post-match screen | valid=true is_open=true
W10_SCREENS_SUMMARY: fails=17 checks=39
```

Boot/init lines that precede the checks (authored data only, unchanged by this
wave): `Godot Engine v4.7.2.stable.official.ed1daf0bf`, three
`[game_data] map fallback` warnings for `Mission.Example.*`, the `Loc` reverse
map line, and `INPUT_TABLE source=generated rows=91 shipping=91 actions=52`.
The three per-screen build lines (`TAT-2 UI main-menu`, `TAT-2 UI settings`,
`TAT-2 HUD build: id=1 root_children=28 ...`) are also elided above.
