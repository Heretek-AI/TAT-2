# T06-INPUT — controls & input remediation

Team: **T06-INPUT** · worktree `<worktree>/T06-input` · branch `rem/T06-input`
Base: `38e7b03` (main at spawn). Findings: RE-H-01…14 (plus adjacent 15/16/17).
Plan: `../REMEDIATION_PLAN.md` §1 invariants, §2 S1–S6. No push, no merge, no rebase.

## Team summary

| verdict | findings |
|---|---|
| **FIXED** | RE-H-02, RE-H-03 (P0), RE-H-04 (P0), RE-H-05, RE-H-06 (formatter), RE-H-07, RE-H-08, RE-H-09, RE-H-11 (gating), RE-H-12 (map/ping), RE-H-14 (device selection), RE-H-15 (settings handlers), RE-H-17 |
| **FIXED + handoff** | RE-H-06 / RE-H-07 / RE-H-12 / RE-H-14: the mechanism and tests are in this branch; the remaining call sites are in T05-UI's files (exact list below). |
| **BLOCKED-ON T01** | RE-H-01 (producer half only — the consumer is implemented and tested), RE-H-10 (CurveFloat whitelist) |
| **BLOCKED-ON T05** | RE-H-11 cancel-distance anchor (mechanism exists), RE-H-12 mission-letter modal push |
| **NOT ADDRESSED (recorded)** | RE-H-13 (per-device sprint toggle, P3), RE-H-16 (ping radial direction, hud.gd is T05's) |

New files: `game/src/core/input_actions.gd` (authored table + InputMap builder),
`game/src/core/input_rebinder.gd` (rebind/conflict/persist), `game/src/core/input_context.gd`
(autoload: boot apply, device tracking, chords, modal gates), `game/src/ui/input_glyphs.gd`
(single prompt formatter), `game/tests/test_input.gd` (138 checks).

## S1–S6 status table

`✓` = done with evidence below/in the gate table · `—` = not required for this verdict.

| finding | sev | S1 investigate | S2 research | S3 red proof | S4 fix | S5 test | S6 green | verdict |
|---|---|---|---|---|---|---|---|---|
| RE-H-01 producer/consumer | P1 | ✓ | ✓ | ✓ (no producer, no consumer) | ✓ consumer only | ✓ loader fallback test | ✓ | **BLOCKED-ON T01** (data half) |
| RE-H-02 five keys / 31 dropped | P1 | ✓ | ✓ | ✓ (base key dump) | ✓ | ✓ | ✓ | **FIXED** |
| RE-H-03 pad look | **P0** | ✓ | ✓ | ✓ (no RX/RY) | ✓ | ✓ | ✓ | **FIXED** |
| RE-H-04 pad fire/tools/map | **P0** | ✓ | ✓ | ✓ (no pad events) | ✓ | ✓ | ✓ | **FIXED** |
| RE-H-05 rebinding | P1 | ✓ | ✓ | ✓ (0 mutations) | ✓ | ✓ round trip | ✓ | **FIXED** |
| RE-H-06 prose glyphs | P1 | ✓ | ✓ | ✓ (`E→F` patch) | ✓ formatter | ✓ | ✓ | **FIXED** + T05 call sites |
| RE-H-07 printed contradictions | P2 | ✓ | ✓ | ✓ (`H`/`C` rows) | ✓ | ✓ | ✓ | **FIXED** |
| RE-H-08 invented sensitivity | P2 | ✓ | ✓ | ✓ (free slider) | ✓ ladder | ✓ | ✓ | **FIXED** (base-unit caveat) |
| RE-H-09 deadzones | P3 | ✓ | ✓ | ✓ (all 0.2) | ✓ | ✓ | ✓ | **FIXED** |
| RE-H-10 dropped curves | P2 | ✓ | ✓ | ✓ | producer is T01's | — | ✓ consumer ready | **BLOCKED-ON T01** |
| RE-H-11 lockpick gating | P2 | ✓ | ✓ | ✓ (`can_act` only downed) | ✓ | ✓ | ✓ | **FIXED** (cancel anchor → T05) |
| RE-H-12 map/letter gating | P2 | ✓ | ✓ | ✓ (no player check) | ✓ map/ping | ✓ | ✓ | **FIXED** (letter push → T05) |
| RE-H-13 sprint per-device | P3 | ✓ | ✓ | — | — | — | — | **RECORDED** |
| RE-H-14 platform prompts | P2 | ✓ | ✓ | ✓ | ✓ keyboard/pad/touch | ✓ | ✓ | **FIXED** (touch cluster → UI owner) |
| RE-H-15 physical vs logical | P3 | ✓ | ✓ | ✓ | ✓ owned files | ✓ | ✓ | **FIXED** (owned files) |
| RE-H-16 ping radial | P3 | ✓ | — | — | — | — | — | **RECORDED** (T05) |
| RE-H-17 dead gamepad keys | P3 | ✓ | ✓ | ✓ (no reader) | ✓ live | ✓ | ✓ | **FIXED** |


---

## RE-H-03 — gamepad camera look did not exist (P0)
- **severity**: P0
- **S1 investigate**: `game/project.godot:50-167` had 4 joypad-motion events, all axes 0/1; no
  RX/RY. `thief_character.gd:778` was the only look path (`InputEventMouseMotion`), plus the touch
  hook at `:1122`. `rg "JOY_AXIS" game/src` → 0 hits. A pad player could walk and jump but not turn.
- **S2 research**: `extracted/json/Gameplay/Input/Character/IMC_Character.json` row 53:
  `IA_LookGamepad` → `Gamepad_Right2D`, modifiers `OSEEnhancedInputModifierInvertGamepadLook_1`,
  `InputModifierDeadZone_2` (Lower 0.12 / Upper 0.98 / `EDeadZoneType::Axial`),
  `OSEInputModifierGamepadLookSpeed_0` (Horizontal 90.0, Vertical 52.0),
  `OSEEnhancedInputGamepadEdgeAcceleration_0` (EdgeThreshold 0.95, curve
  `Curve_GamepadLookEdgeBoost`), two sensitivity modifiers.
- **S3 confirm (red)**: `git show 38e7b03:game/project.godot` decoded →
  `port actions = 21`, `joypad-motion events = 4`, `axes = [0, 1]`, `RX/RY look present = False`.
  Script: the red-proof block in this report's appendix.
- **S4 fix**: new `look_gamepad` action bound to right-stick X/Y (canonical signed names) with
  `deadzone 0.12` in `project.godot`; consumed by `thief_character.gd:_tick_gamepad_look()` —
  per-axis axial deadzone `(a-0.12)/(0.98-0.12)`, `90°/s` yaw and `52°/s` pitch, `×` the authored
  GamepadLookSensitivity step, invert from `gamepad_invert_y`, delta-based (Hz independent).
  The stick is read with `Input.get_joy_axis` because Godot cannot return a 2D vector from one
  action; the InputMap action remains the declared/rebindable binding.
- **S5 test**: `game/tests/test_input.gd` §2 — every authored action resolves on both devices;
  `look_gamepad` specifically has 4 motion events on axes 2/3 and the 0.12 deadzone; the player
  instantiation test builds the real script headless.
- **S6 confirm (green)**: `INPUT_SUMMARY: fails=0 checks=138`; compile 125/0; E2E 278/278;
  `perf_guard 78/78`.
- **verdict**: **FIXED**. Edge-boost curve not applied: its `CurveFloat` is not produced
  (RE-H-10, BLOCKED-ON T01); the 0.95 threshold constant is recorded in `InputActions`.

## RE-H-04 — pad fire / secondary / tools / map unbound (P0)
- **severity**: P0
- **S1**: only 6 joypad events existed (A, B, X, L3, Y + one button); `primary_action` /
  `secondary_action` were LMB/RMB only (`project.godot:102-111`); `tool_1..4`, lean, `ability`,
  `map_toggle` had no pad event.
- **S2**: IMC rows 1 (RT primary), 7 (LT secondary), 9 (A jump), 11 (B crouch), 19 (X interact),
  34/36/38/73 (DPad slots), 67 (View = map), 61 (Y secondary interact), 65 (RB radial/ping),
  55 (RB attack), 57 (LT block), 75/20 (LB melee), 50/52 (LB + LS lean).
- **S3 (red)**: decoded base `[input]`: `primary pad buttons = []`; actions present = 21.
- **S4**: all of the above are bound by `InputActions.apply_to_input_map()` and by the committed
  `project.godot` baseline. Consumers already existed for jump/crouch/interact/primary/secondary/
  tools/map/ping; authored actions without a port verb are bound and recorded (see diff table).
- **S5/S6**: `test_input.gd` §2 asserts RT fires `primary_action`, DPad Left selects `tool_1`,
  View opens `map_toggle`, Y is `secondary_interact`; E2E T1-09-C (LMB smoke bomb), T1-10-C/F/G/H/I
  (RMB crank/attach) and T1-14 map/ping tests pass in the 278/278 run.
- **verdict**: **FIXED**.

## RE-H-02 — five invented/swapped keys, 31 dropped actions (P1)
- **severity**: P1
- **S1**: `project.godot:84` crouch C+Ctrl, `:98` interact F+E, `:125` lean_right R, `:114`
  thief_vision V, `:130` ability G.
- **S2**: IMC_Character rows 54 (C = Attack), 32/51 (E = Traversal / Lean_Right), 60 (R =
  Secondary Interact), 56 (V = Block), 37/74 (Four = `IA_Ability05`/Vistara), 66/68 (Tab + M = Map),
  20 (H = MeleeToggle), 30 (CapsLock = MissionPanel).
- **S3 (red)**: decoded base `[input]` → `crouch keys = [67, 4194326]`, `interact = [70, 69]`,
  `lean_right = [82]`, `thief_vision = [86]`, `ability = [71]`, `map_toggle = [4194306]`.
- **S4**: replaced by the authored table. Adopted: Ctrl crouch, F interact, E lean-right, R
  secondary-interact, V block, C attack, H melee, Tab+M map, 1-4 tools with DPad, View map.
  Port actions with **no authored counterpart** are no longer given an invented key:
  `thief_vision` is unbound (vision is the Vistara tool, as authored; the code hook stays behind
  `InputMap.has_action`). `ability` is re-homed to the authored X (`IA_Ability_OpenThiefsignRadial`)
  and labelled **EXPANSION** in the table: the shipped build has no generic ability action and the
  port's per-thief signature verb must stay reachable. That is a documented substitution, not an
  authored value.
- **S5/S6**: `test_input.gd` §3 (10 assertions), including that `crouch` no longer holds C and that
  tool 4 prints `4` on keyboard and `DPAD DOWN` on pad (the hotbar/Controls disagreement is gone).
- **verdict**: **FIXED**.

## RE-H-05 — rebinding absent although shipped (P1)
- **severity**: P1
- **S1**: `rg "rebind|InputMap.action_|action_erase|action_add" game/src` → 4 read-only
  `has_action` guards; `settings_ui.gd:658` rendered a static `ThemeScript.keycap(...)`.
- **S2**: `DefaultInput.ini:119-124` `bEnableUserSettings=True`,
  `UserSettingsClass=/Script/TAT.TATEnhancedInputUserSettings`,
  `DefaultPlayerMappableKeyProfileClass=EnhancedPlayerMappableKeyProfile`; 17 rows carry
  `PlayerMappableKeySettings` (indices 0,2,4,8,10,12,13,23,24,25,26,33,35,37,64,66,74);
  conflict string `ST_Settings_Input.InputSetting.Input.RebindSameKey` =
  `"{InKey} is already bound to {ActionNames}."`; `InputSetting.PressAnyKey` = `"Press Any Key"`;
  `IA_ChangeInputMapping` = Backslash.
- **S3 (red)**: zero mutation sites; the Controls tab was a label list; no `bindings` save key.
- **S4**: `input_rebinder.gd` — `rebind()` / `conflicts_for()` / `conflict_message()` (template read
  from the generated string table), `overrides_from_settings()` (drops unknown actions/keys),
  `write_overrides()`, `persist()` through `SaveSystem.write_save()`, per-device reset.
  `settings_ui.gd` CONTROLS tab: device toggle (`DISPLAY: KEYBOARD / MOUSE · [BACKSLASH] TO SWAP`),
  the four authored categories, 15 rebind cells (17 shipped rows − the Primary Tap/Hold repeats −
  the four Move repeats), `[ PRESS ANY KEY ]` capture with ESC cancel, authored conflict sentence,
  per-row reset and RESET BINDINGS. Backslash also swaps the displayed device at runtime
  (`InputContext`, authored `IA_ChangeInputMapping`).
- **S5/S6**: `test_input.gd` §5 — rebind → apply → glyph changes; conflict refused with the
  authored sentence and the owning action named; pad conflict on LB; **JSON round trip**
  (`settings.bindings` → `JSON.stringify` → parse → `overrides_from_settings` → apply) keeps G and
  R3; reset restores F/X; garbage keys/actions dropped. §8 checks the real SettingsUI instance
  exposes the 15 cells and the ladder.
- **verdict**: **FIXED**. Storage schema: `SaveSystem.data.settings.bindings` +
  `bindings_schema = 1`; only changed actions are stored, so a later table fix (T01) flows through.

## RE-H-06 — prompt glyphs parsed out of prose (P1)
- **severity**: P1
- **S1**: `hud.gd:3357 _set_prompt()` splits the leading `[X]`, `:3377` rewrites `E→F`;
  `:3387` prints the token. The glyph is whatever the interactable hardcoded.
- **S2**: `UOSEInputFunctionLibrary::GetKeyTextForInputAction()` resolves the bound key;
  `DT_InputKeysToGlyphs` (132 rows) supplies the sprite; `BPUI_InputActionIcon::
  _OnInputHardwareTypeChanged` re-renders on device change; `DT_RichTextInputs` binds prompt text
  to actions.
- **S3 (red)**: base `hud.gd` contains `if key == "E": key = "F"` and a prose-splitting
  `_set_prompt`; `rg "InputKeysToGlyphs|RichTextInputs|DT_UI_DefaultInputActions" game/src` → 0.
- **S4**: `input_glyphs.gd` — `text(action, device)`, `bracket()`, `prompt()`, `icon_name()`
  (authored sprite names), `format_legacy(raw, action)` (re-keys only the leading token, leaves
  `[HOLD]`/prose alone), `format_legend(raw, token_actions)` (multi-key legends), device tracking
  (`note_event` / `set_device`, kb/pad/touch), `action_label`/`action_category` from
  `ST_Settings_Input`, `rebindable_by_category()`.
- **S5/S6**: `test_input.gd` §4 — `[F]`/`[X]` for interact, `[DPAD DOWN]` for tool 4,
  `[LB + LS LEFT]` for the chorded lean, `[RIGHT STICK]` for pad look, authored sprites
  `S_Controller_PC_F` / `S_Controller_Xbox_X`, `[E] Pick Lock` → `[F] Pick Lock`,
  `[LMB] CRANK` → `[RT] CRANK` on pad, prose tokens untouched, and a **post-rebind glyph update**
  (`[G]`) — the property the old prose parsing could never have.
- **verdict**: **FIXED (mechanism + tests)**; the HUD/main_menu/contract-table call sites are T05's
  (list below). `hud.gd` still contains the `E→F` patch until T05 makes that one-line switch.

## RE-H-07 — printed glyphs contradict the authored table (P2)
- **severity**: P2
- **S1**: `settings_ui.gd:485-493` printed `C` for crouch, `1 2 3` for slots, `H` for Vistara,
  no gamepad group, no wheel row; the hotbar printed `4`.
- **S2**: `ST_Settings.json` labels; IMC rows; `Settings.Controls.KBM.MiddleMouse =
  "Cycle Gear (Scroll)\nPing (Button Press)"`.
- **S3 (red)**: base rows contained `["C", …"Crouch / Slide"]` and `["H", …"Vistara Diamond"]`.
- **S4**: rows deleted; the Controls tab is generated from the table, so every printed key is a
  binding query. Slot 4 prints `4`/`DPAD DOWN` on both screens.
- **S5/S6**: `test_input.gd` §3 tool-4 glyph on both devices; §4 label/category from the string
  table; §8 the 15 cells render through `InputGlyphs`.
- **verdict**: **FIXED** (settings half). HUD legends are the T05 call sites below.

## RE-H-08 — invented rad/px slider replaces the authored ladder (P2)
- **severity**: P2
- **S1**: `settings_ui.gd:37-40` `SENS_MIN/MAX/STEP` + a free `HSlider`;
  `thief_character.gd:781` applies rad/px.
- **S2**: `DefaultGame.ini:483-486` MouseLookSensitivity 0.5/0.75/1.0/1.5/2.0,
  GamepadLookSensitivity 0.5/0.75/1.0/1.25/1.5, GamepadMoveSensitivity 0.5/0.75/1.0/1.5/2.0;
  saved per hardware type (`OSECore.hpp` `FOSEGamepadMouseKeyboardSettings` /
  `FOSEGamepadInputSettings`); shipped defaults all `Normal`.
- **S3 (red)**: base `const SENS_MIN = 0.0005 / SENS_MAX 0.008 / SENS_STEP 0.0002`, default 0.0025,
  and no gamepad row.
- **S4**: ladder adopted: three `OptionButton`s (mouse look, pad look, pad move), `VeryLow…VeryFast`,
  persisted as **step names**; `mouse_sensitivity` stays written as the derived effective rad/px so
  every existing reader keeps working; legacy free values migrate to the nearest step
  (`nearest_mouse_step`). `gamepad_invert_y` (previously written by `save_system.gd:339` and read by
  nothing) is now a live per-device setting; `gamepad_sensitivity` is superseded by
  `gamepad_look_sensitivity` and no longer written by the UI.
- **S5/S6**: `test_input.gd` §6 (7 assertions incl. 1.25× pad Fast ≠ 1.5× mouse Fast) and §8
  (VeryFast writes 0.005 and the step name). `run_tests` 35b and E2E T1-16-D were updated to drive
  the ladder instead of the removed slider — the assertions' intent (settings reach the player) is
  unchanged, only the invented control they poked.
- **verdict**: **FIXED**, with one honest caveat: the 0.0025 rad/px **base is the port's unit
  bridge**, not authored. The authored chain (0.07 deg/count × FOVScale/tan(half-FOV)) cannot be
  mapped to Godot pixels without a measurement this lane is not allowed to fabricate. Multipliers
  and step names are authored.

## RE-H-09 — one invented deadzone for everything (P3)
- **severity**: P3
- **S1**: all 21 actions declared `deadzone 0.2`.
- **S2**: move 0.18; look 0.12 axial / 0.98; legacy stick 0.25.
- **S3/S4/S5**: base file shows `0.2` on all 21; now move = 0.18, look = 0.12 (engine action
  deadzone), everything else stays 0.2 (inert for button events — recorded as not authored).
  `test_input.gd` asserts both values from the live InputMap.
- **verdict**: **FIXED**.

## RE-H-11 — lockpick modal gates nothing (P2)
- **severity**: P2
- **S1**: `thief_character.gd:598 can_act() → not is_downed`; `hud.gd:2018` sets `_lockpick_active`
  and calls `set_lockpicking_active(true)`, which only sets a disguise-drain flag (`:2086`).
- **S2**: `GA_Lockpick` CDO `ActivationOwnedTags` = `Status.InteractionDisabled`,
  `Status.MovementDisabled`, `Status.ToolEquippingDisabled`, `Status.LookDisabled`,
  `Status.Lockpicking`; `DistanceBeforeCancel = 200.0` cm; `EarlyUnlockThresholdSeconds = 0.1`.
- **S3 (red)**: base `can_act() = return not is_downed`; 0 occurrences of the four
  `Status.*Disabled` tags in `game/src`.
- **S4**: `InputContext` autoload with a modal stack. LOCKPICK_DISABLED mirrors the four tags
  (movement, jump, crouch, sprint, lean, interact, tools, ping, ability, vision, pad look — primary
  fire deliberately stays, because Attack is not in the authored tag set and the strike uses it).
  Disabled actions are released in `_input` (before the physics tick) and re-released each frame.
  `can_act()` now also consults `InputContext.blocks_gameplay()`, and `_physics_process` damps to a
  stop under a gameplay-blocking modal. The 200 cm cancel is implemented (`push_modal(..., 200.0)`
  + `set_cancel_anchor()` + distance tick + `modal_cancel_requested`), but the anchor needs the lock
  target's world position, which the HUD owns → T05 call site.
- **S5/S6**: `test_input.gd` §7 asserts each disabled action, that `primary_action` stays live, the
  cancel does not fire without a player, and the real player's `can_act()` flips with the modal.
- **verdict**: **FIXED (gating)**; cancel-distance wiring **BLOCKED-ON T05** (one call).

## RE-H-12 — map / letter are not input modals (P2)
- **severity**: P2
- **S1**: `hud.gd:2185 toggle_map_overlay()` never pauses and never tells the player;
  `thief_character.gd` has no `_map_open` check → `Input.get_vector` at `:1277`, lean at
  `:1190-1192`, sprint at `:1287` and `primary_action` at `:1033` keep running.
- **S2**: the map is a `BPTool`-gated CommonUI overlay that takes focus and adds `IMC_MapTool`
  (`IA_MapSwitch_Prev/Next` = R/F); there is no authored tag set.
- **S3 (red)**: `grep -n "is_map_open\|_map_open" thief_character.gd` → no output.
- **S4**: MAP_DISABLED (movement, look, interaction, tools, attack, ping, ability) pushed while
  `hud.is_map_open()`; `map_toggle`/`pause` stay live so the HUD's own close key works.
  PING_DISABLED for the radial. The mission letter is **not auto-polled**: its open signal races
  sublevel streaming (observed once in a full E2E run), so `LETTER_DISABLED` is exposed for T05 to
  push/pop inside `show_mission_letter()` / `_close_mission_letter()` (deterministic, one place).
- **S5/S6**: `test_input.gd` §7 (map blocks movement, not its toggle) + full E2E 278/278 with the
  harness dismissing the start letter as a player would (`e2e_helpers.gd:instantiate_mission`, test
  setup, no assertion changed).
- **verdict**: **FIXED (map/ping)**; letter push **BLOCKED-ON T05**.

## RE-H-14 — prompts never adapt to hardware (P2)
- **severity**: P2
- **S1**: hardcoded keycaps; mobile hides the keycap.
- **S2**: `DT_InputKeysToGlyphs` 132 rows incl. 16 `S_Controller_Xbox_*`; 14 widgets implement
  `ReceiveOnInputHardwareTypeChanged`; **no mobile UI is shipped** (only
  `DefaultVirtualJoysticks`, `pakchunk0-Windows`).
- **S3/S4/S5**: device selection in `InputGlyphs` (kb / pad / touch), pad labels from the authored
  Xbox sprite names, `icon_name()` returns the authored `S_Controller_*` sprite name, touch returns
  no keycap (nothing authored to print) so the verb still shows. Tests cover both devices plus
  touch, and the load-time device switch.
- **verdict**: **FIXED (selection + glyphs)**. The touch **cluster** (missing `tool_4`,
  `secondary_action`, map, ping; invented button labels) is `mobile_touch_ui.gd`, not in this
  lane's file set → recorded for the mobile/UI owner.

## RE-H-15 — InputMap physical, handlers logical (P3)
- **S1**: `project.godot` physical (correct); ~20 handlers test `keycode`.
- **S4/S5**: the handlers in this lane's files are fixed: `settings_ui.gd` tab switching and
  ESC/rebind capture now use `physical_keycode` first, falling back to `keycode`; `project.godot`
  keeps physical keys only. The remaining handlers (`hud.gd`, `contract_table_ui.gd`,
  `mission_prep_ui.gd`, `wardrobe_ui.gd`, `ledger_ui.gd`, `mission_controller.gd`) are listed for
  their owners.
- **verdict**: **FIXED (owned files)** / recorded elsewhere.

## RE-H-17 — dead gamepad save keys (P3)
- **S1**: `save_system.gd:338-339` wrote `gamepad_sensitivity` / `gamepad_invert_y`; no reader.
- **S4/S5**: `gamepad_invert_y` is read by `apply_saved_settings()` and applied to pad look;
  `gamepad_look_sensitivity` / `gamepad_move_sensitivity` replace the dead float. `save_system.gd`
  itself was not edited (T02 owns it); the old keys remain harmlessly in old saves.
- **verdict**: **FIXED**.

## RE-H-01 — no producer, no consumer (P1)
- **S1**: `tools/parse_tables.py:172` whitelists DataTable/CurveTable/… only;
  `game/data/generated/tables/Gameplay/Input/` does not exist; nothing reads the IMCs.
- **S2**: 3 IMCs, 91 rows, 52 actions (this report's table is transcribed from them).
- **S4 (this lane)**: **consumer** implemented: `InputActions.load_table()` reads
  `res://data/generated/input/input_actions.json` when present (documented schema
  `tat2.input_actions/1`, `actions[]` with `id/ia/ctx/kb[]/pad[]/deadzone/trigger/chord/mappable{}`),
  validates it, and otherwise uses the provenance-stamped `AUTHORED_ROWS` mirror. Precedence:
  generated → authored mirror → leave `project.godot [input]` untouched. `project.godot` is the
  no-code baseline; a boot-time `apply_to_input_map()` re-applies the same data plus rebinds.
- **verdict**: **BLOCKED-ON T01** for the producer + audit baseline. The mirror is explicitly a
  fallback, not a second producer; delete it when the generated file is in `tools/audit_baseline.json`.

## RE-H-10 — the two gamepad curves are dropped (P2)
- **S1**: `parse_tables.py:172` has no `CurveFloat`; all 76 curve assets are dropped;
  `game_data.gd:99` still lists a non-existent `tables/Gameplay/Input/Character` root.
- **S4**: no producer edit (T01 owns it). The consumer is ready: once the curves land, add the
  response-curve sampling to `_tick_gamepad_look`/move. The comment in `game_data.gd` remains
  misleading and is flagged in Doc corrections; **do not** change the path or the comment until the
  producer emits the files.
- **verdict**: **BLOCKED-ON T01**.

## RE-H-13 — sprint toggle is one global default (P3)
- **S1**: `settings_ui.gd:187 s["sprint_toggle"] = false`, one key for both devices; shipped
  `SprintToggle=True` per hardware type (`OSECore.hpp:452-468`).
- **verdict**: **NOT ADDRESSED (recorded)** — P3, and the shipped ini value is plausibly a stale
  editor snapshot (RE-H-13's own caveat). The per-device split needs a device-changed signal; the
  signal now exists (`InputContext.device_changed`) for whoever picks this up.

## RE-H-16 — ping radial direction (P3)
- **S1**: selection reads `InputEventMouseMotion.position - centre` while the cursor is captured.
- **verdict**: **NOT ADDRESSED (recorded)** — `hud.gd` is T05's; the authored `IA_Radial_*` rows are
  in the table (`ctx: "radial"`) and the pad DPad actions exist, so T05 can switch selection to
  `radial_directional` without new input work.

---

## Authored-vs-port binding diff (final state)

40 port action ids (39 with InputMap events; `look_mouse` is metadata-only because mouse
look is read as motion). *Correction: commit `6e7cf40`'s message says "21 -> 38"; the
measured count on that commit is 39 action blocks — the message is off by one, the tree is not.* `MouseWheelAxis+` = wheel up (`IA_ToolSelect_EquipNextWeapon` has explicit
`Sign: Positive`; the sign convention itself is the one inference — see Open risks).
Coverage-only rows (16) are listed after the table.

| port action | authored IA | KB/M | gamepad | deadzone | consumer |
|---|---|---|---|---|---|
| `move_forward` | `IA_Move` | W | Gamepad_LeftY- | 0.18 | thief_character.gd:1277 |
| `move_backward` | `IA_Move` | S | Gamepad_LeftY+ | 0.18 | thief_character.gd:1277 |
| `move_left` | `IA_Move` | A | Gamepad_LeftX- | 0.18 | thief_character.gd:1277 |
| `move_right` | `IA_Move` | D | Gamepad_LeftX+ | 0.18 | thief_character.gd:1277 |
| `jump` | `IA_Movement_Jump` | SpaceBar | FaceButton_Bottom | 0.2 | thief_character.gd:1319 |
| `crouch` | `IA_Movement_Crouch` | LeftControl | FaceButton_Right | 0.2 | thief_character.gd:794 |
| `crouch_hold` | `IA_Movement_CrouchHold` | LeftAlt | — | 0.2 | — recorded |
| `sprint` | `IA_Movement_Run` (+`RunToggle`) | LeftShift | L3 | 0.2 | thief_character.gd:787,1287 |
| `dodge` | `IA_Movement_Dodge` | MB4, MB5, LeftShift | L3 | 0.2 | — recorded |
| `lean_left` | `IA_Ability_Lean_Left` | Q | LB + LS Left | 0.2 | thief_character.gd:1190 |
| `lean_right` | `IA_Ability_Lean_Right` | E | LB + LS Right | 0.2 | thief_character.gd:1192 |
| `look_gamepad` | `IA_LookGamepad` | — | Right stick X/Y | **0.12** | thief_character.gd:_tick_gamepad_look |
| `look_mouse` | `IA_LookMouseKeyboard` | Mouse2D | — | — | thief_character.gd:778 (motion, not an action) |
| `prevent_look_gamepad` | `IA_PreventLookGamepad` | — | LB + Right2D | 0.2 | InputContext |
| `prevent_move_gamepad` | `IA_PreventMoveGamepad` | — | LB + Left2D | 0.2 | InputContext |
| `interact` | `IA_Interact` | F | X | 0.2 | thief_character.gd:800 |
| `secondary_interact` | `IA_Secondary_Interact` | R | Y | 0.2 | — recorded |
| `ping_menu` | `IA_Ability_OpenRadial` | MMB | RB | 0.2 | hud.gd:2297 |
| `map_toggle` | `IA_ToolSelect_EquipMap` | Tab, M | View | 0.2 | hud.gd:2289 |
| `mission_panel` | `IA_MissionPanelToggle` | CapsLock | View | 0.2 | — recorded |
| `primary_action` | `IA_Ability_Action_Primary` (+Tap/Hold) | LMB | RT | 0.2 | thief_character.gd:837 |
| `secondary_action` | `IA_Ability_Action_Secondary` | RMB | LT | 0.2 | thief_character.gd:839 |
| `attack` | `IA_Ability_Attack` | C | RB | 0.2 | — recorded |
| `block` | `IA_Ability_Block` | V | LT | 0.2 | — recorded |
| `melee_toggle` | `IA_Ability_MeleeToggle` | H | LB | 0.2 | — recorded |
| `ranged_attack` | `IA_Ability_RangedAttack` | RMB | LT | 0.2 | — recorded |
| `ranged_reload` | `IA_Ability_RangedReload` | F | X | 0.2 | — recorded |
| `traversal` | `IA_Ability_Traversal` | E | — | 0.2 | — recorded |
| `ability` | `IA_Ability_OpenThiefsignRadial` | X | — | 0.2 | thief_character.gd:819 (**EXPANSION substitution**) |
| `tool_1` | `IA_Ability03` | 1 | DPad Left | 0.2 | thief_character.gd:821 |
| `tool_2` | `IA_Ability04` | 2 | DPad Up | 0.2 | thief_character.gd:823 |
| `tool_3` | `IA_Ability05` | 3 | DPad Right | 0.2 | thief_character.gd:825 |
| `tool_4` | `IA_ToolSelect_EquipVistaraDiamond` | 4 | DPad Down | 0.2 | thief_character.gd:835 |
| `tool_select_next` | `IA_ToolSelect_EquipNextWeapon` | Wheel up | LB + RS Right | 0.2 | — recorded |
| `tool_select_prev` | `IA_ToolSelect_EquipPreviousWeapon` | Wheel down | LB + RS Left | 0.2 | — recorded |
| `input_chord_lb` | `IA_ControllerLeftShoulder` | — | LB | 0.2 | InputContext chord source |
| `pause` | `Pause` (legacy ActionMapping) | Escape, Pause | Menu (Start) | 0.2 | hud.gd:2340 |
| `change_input_mapping` | `IA_ChangeInputMapping` | Backslash | — | 0.2 | InputContext device toggle |
| `display_input_debug` | `IA_DisplayInputDebug` | Enter | — | 0.2 | — recorded |
| `display_input_cycle` | `IA_DisplayInputCycle` | Enter (tap) | — | 0.2 | — recorded |

Coverage-only rows (no port action of their own): `IA_Ability_Action_Primary_Tap`,
`IA_Ability_Action_Primary_Hold`, `IA_Ability_RunToggle` (merged into `sprint`), `IA_Ability06`
(Four double-bound; Vistara owns the key), `IA_Ability07…10` (5–8, no port slot),
`IA_Radial_Directional`, `IA_Radial_Cancel`, `IA_Radial_NextPage`, `IA_Radial_PreviousPage`,
`IA_Radial_Select_Primary` (G), `IA_Radial_Select_Secondary` (T), `IA_MapSwitch_Prev` (R),
`IA_MapSwitch_Next` (F). The radial and map-tool contexts have no port consumer; their rows exist
so the table, the diff and the rebind/glyph layer are complete.

---

## T05-UI call sites (exact)

`game/src/ui/input_glyphs.gd` is ready; these are the only edits needed outside T06's files.
Do them in one pass so no prompt can be left reading a stale key.

1. **`hud.gd:3357 _set_prompt(raw)`** — delete the `[X]` split, the `if key == "E": key = "F"`
   patch (`:3377`) and the raw print (`:3387`). Replace with:
   ```gdscript
   var hint: String = str(interact_target.get_meta("input_action", "interact")) if interact_target != null else ""
   var line: String = InputGlyphs.format_legacy(raw, hint)
   # then split the leading bracket only to size the keycap, or render `line` whole
   ```
   Interactables should publish `set_meta("input_action", "interact" | "secondary_interact")`
   (or return `{"action": "...", "verb": "..."}` from `get_interact_prompt()`); until they do,
   pass `"interact"` and the `E→F` case is solved by the binding query.
2. **`hud.gd:3398 _set_secondary_prompt(raw)`** — same `format_legacy(raw, "secondary_interact")`.
3. **`hud.gd:1300` hotbar `default_keys`** — replace `["1","2","3","4"]` with
   `InputGlyphs.text("tool_%d" % (i+1))` per slot (pad shows `DPAD LEFT/UP/RIGHT/DOWN`).
4. **`hud.gd:1158` crank legend** — `InputGlyphs.bracket("secondary_action") + " CRANK"`.
5. **`hud.gd:1346` ping hint** — `InputGlyphs.bracket("ping_menu") + " [HOLD] PING MENU"`.
6. **`hud.gd:1534` and `:3019` lockpick legend** —
   `InputGlyphs.format_legend("[SPACE] / [LMB] STRIKE PIN · [ESC] CANCEL", {"SPACE":"jump","LMB":"primary_action","ESC":"pause"})`.
7. **`hud.gd:1593` map footer** — same `format_legend` with
   `{"LMB":"primary_action","TAB":"map_toggle","ESC":"pause"}`.
8. **`hud.gd` `_input()`** — first line: `InputGlyphs.note_event(event)` so the HUD follows the
   last device even when InputContext is absent in a trimmed scene.
9. **`hud.gd _ready()`** — `InputContext.register_hud(self)` (skips the duck-typed discovery scan).
10. **`hud.gd show_mission_letter()/ _close_mission_letter()`** —
    `InputContext.push_modal("mission_letter", InputContext.LETTER_DISABLED)` /
    `InputContext.pop_modal("mission_letter")`. This is the deterministic letter gate RE-H-12 asks
    for (auto-polling raced sublevel streaming and was removed).
11. **`hud.gd start_lockpick_minigame()`** — after `_lockpick_active = true`:
    `InputContext.set_cancel_anchor("lockpick", <lock_global_position>)` so the authored 200 cm
    walk-away cancel works (`InputContext` already pushes the modal with 200 cm and emits
    `modal_cancel_requested`; connect it to `_finish_lockpick(false)`).
12. **`hud.gd:2311` ping radial** — prefer the authored actions (`radial_directional` axes, DPad) over
    the captured-mouse position (RE-H-16); the rows are already in the table.
13. **`hud.gd:2289` map toggle** — `InputMap.has_action("map_toggle")` guard can stay; the action now
    is Tab + M + View.
14. **`mobile_touch_ui.gd:104-122`** — add `tool_4` and `secondary_action` buttons and label them
    with `InputGlyphs.action_label()` (RE-H-14 touch cluster; no authored touch glyphs exist).
15. **`thief_character.gd:1158-1176` reticle hints** — the `"LMB"`/`"4"` strings should call
    `InputGlyphs.text("primary_action")` / `text("tool_4")` when T05 touches the HUD hint path; the
    player script itself is T06/T04 shared, so this is listed rather than edited.

---

## Gate evidence (this worktree, uncommitted → committed in the same wave)

| gate | command | result |
|---|---|---|
| compile | `tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"` | `scripts checked: 125, broken: 0` (floor 120) |
| unit | `make test` | `SUMMARY: fails=0` (278 PASS; suite 35b green) |
| **input (new)** | `tools/godot --headless --path game --script res://tests/test_input.gd` | `INPUT_SUMMARY: fails=0 checks=138` |
| M2 | `… --script res://tests/test_m2_player.gd` | `M2_SUMMARY: fails=0` (11) |
| E2E | `… --script res://tests/e2e/run_e2e_tests.gd` | `SUMMARY: fails=0 passed=278 total=278` (tier 1 alone: 117/117) |
| perf guard | `build/qa/test_perf_guard.sh` | `PERF_GUARD_TEST PASS checks=78 fails=0` |
| ratchet | `make gate-ratchet` | `GATE_RATCHET: PASS` |
| leak probe | `TAT2_NO_DEN_PROBE=1 … probe_leak.gd` | exit 0, only the documented Den/streaming warnings |
| audit | `make audit` | **pre-existing failure, not T06**: `FAIL: tool version drift: vgmstream … -> 'missing'`; every content group passed (`levels 107/107, tables 144/144, materials 1629, devices 4118, audio 5018, niagara 3695`). `which vgmstream` → not on PATH. Stamps were **not** refreshed (forbidden for teams). |

Red/green proof commands for the P0 (RE-H-03), reproducible without this worktree:

```bash
# RED (base 38e7b03): 21 actions, 4 pad-motion events, axes [0,1], no RX/RY
git show 38e7b03:game/project.godot | python3 -c '
import sys,re; s=sys.stdin.read().split("[input]",1)[1].split("[editor_plugins]")[0]
a=re.findall(r"^([a-z_0-9]+)=\{",s,re.M); j=re.findall(r"InputEventJoypadMotion[^)]*\"axis\":(\d+)",s)
print(len(a),a); print("axes",sorted({int(x) for x in j}), "look", any(int(x) in (2,3) for x in j))'
# RED: can_act() = not is_downed, 0 Status.*Disabled references
git show 38e7b03:game/src/player/thief_character.gd | grep -A1 "func can_act"
git show 38e7b03:game/src/player/thief_character.gd | grep -c "MovementDisabled\|LookDisabled"
# RED: hud E->F hand patch, invented C/H control rows
git show 38e7b03:game/src/ui/hud.gd | grep -n 'key == "E"'
git show 38e7b03:game/src/ui/settings_ui.gd | grep -n '"H"\|Crouch / Slide'
# GREEN (this branch): every authored action resolves on both devices
tools/godot --headless --path game --script res://tests/test_input.gd
```

---

## Doc corrections (integrator applies — T06 did not edit these files)

1. **`docs/HANDOFF_NEXT_AGENT.md:556-561`** — “gamepad focus” / “joypad” claims: now true for
   camera look, primary/secondary fire, tools, jump/crouch/interact, lean (LB chord), map, ping and
   pause. Still false for a touch-parity claim and for melee/ranged verbs (bound, no port consumer).
2. **`docs/FIDELITY_GAPS.md`** — has no input entry; add one covering: bindings source
   (`input_actions.json` when T01 lands, `AUTHORED_ROWS` mirror until then), authored deadzones
   0.18/0.12, pad turn 90/52 °/s with no edge-boost curve (T01), rebinding schema
   `settings.bindings` + `bindings_schema=1`, the mouse ladder's **unit-bridge base caveat**, 15
   rebindable cells (Interact is deliberately not rebindable — shipped), and `thief_vision` now
   unbound.
3. **`AGENTS.md` rule 7 (runtime contracts)** — add: autoload `InputContext`; action ids
   `look_gamepad`, `secondary_interact`, `input_chord_lb`, `change_input_mapping`, `pause` (now also
   gamepad Menu); `InputGlyphs` as the only prompt formatter; save keys
   `settings.mouse_look_sensitivity` / `gamepad_look_sensitivity` / `gamepad_move_sensitivity`
   (step names) and `settings.bindings`; `thief_vision` exists but is intentionally unbound;
   `ability` is an **expansion** mapping onto X.
4. **`AGENTS.md` known traps** — “`game/project.godot [input]` is authored baseline, and
   `InputActions.apply_to_input_map()` re-applies it plus rebinds at boot; never hand-edit one
   without the other — `test_input.gd` fails on drift.” Also: adding a `class_name` file requires
   `tools/godot --headless --path game --import` before `check_scripts_compile` (new global classes
   are not registered until the class cache refreshes).
5. **`README.md` commands** — add
   `tools/godot --headless --path game --script res://tests/test_input.gd` (input gate, 138 checks).
6. **`tools/gate_ratchet.json`** — compile floor 120 → observed 125 on this branch; run_tests floor
   278 unchanged; the new input suite is standalone (not part of `make test`). Update only with a
   real log.
7. **`game_data.gd:99-113`** — the comment claims the two gamepad response curves load; the
   directory cannot exist until T01 adds `CurveFloat` to the producer. Correct the comment **when**
   the data lands, not before.
8. **`docs/` ownership note** — REMEDIATION_PLAN §3 lists `settings_ui.gd` under T05; the T06
   spawn prompt assigned it to T06. T06's changes there are confined to the Controls tab, the
   sensitivity rows and the physical-key handlers, to keep the T05 merge small.

## Open risks

1. **Two binding sources until T01.** `project.godot [input]` and `AUTHORED_ROWS` must agree; the
   resolution assertions in `test_input.gd` catch drift, but the union is duplicated data by
   design (one is the editor/no-code baseline, one is the runtime/rebind default). Delete the
   mirror when `input_actions.json` is in the audit baseline.
2. **Godot has no chord triggers.** The LB chord is enforced by re-releasing the chorded actions
   while LB is up; a fresh press can theoretically be observed by a `_physics_process` in the same
   frame if the release ordering ever changes. Bounded by one frame, not measured on hardware.
3. **Modal gating is a release loop, not a filter.** `Input.action_release` runs in `_input`
   (before physics) and again in `_process`. A system that polls `Input.is_action_just_pressed`
   inside `_input` *before* `InputContext` (autoload order) could still see one press.
4. **`thief_character.gd` is shared with T04-ANIM.** This branch touches only
   `apply_saved_settings`, `can_act`, `_unhandled_input` look/vision, `_physics_process` gate/look
   call and the new `_tick_gamepad_look`; expect a merge touch in the same functions, not a
   conflict of intent.
5. **E2E harness change.** `e2e_helpers.instantiate_mission()` now closes the mission-start letter
   (a player action). This is setup, not an assertion, and it is required for the letter to be
   gateable. If T05 pushes the letter modal, this dismissal must stay.
6. **Wheel direction** is inferred from `RequireSign` (Positive on Next); the enum's default
   serialization is not in this worktree's dump. No consumer today (`tool_select_next/prev` are
   recorded), so the blast radius is a future gear-cycle feature.
7. **Mouse sensitivity unit bridge** (0.0025 rad/px base) is not authored; the ladder shape is.
   A future measurement must replace the base, not the ladder.
8. **Save schema**: `settings.bindings` / `bindings_schema` were added without bumping
   `SETTINGS_SCHEMA_VERSION` (T02 owns `save_system.gd`). Old saves are forward-compatible; T02
   should fold the block into the next migration and decide whether the dead
   `gamepad_sensitivity` float is dropped or aliased.
9. **File ownership overlap**: `settings_ui.gd` is listed under T05 in REMEDIATION_PLAN §3 but was
   assigned to T06 by the spawn prompt. Keep the T05 review focused on the Controls tab diff.
10. **Unauthored pad verbs** (`attack`/`block`/`melee_toggle`/`ranged_*`) now resolve to real keys
   but have no consumer; a pad player pressing RB/LT in combat gets nothing where the shipped game
   attacks/blocks. That is a T10-GAMEPLAY gap, recorded, not hidden.
11. **Touch cluster** (`mobile_touch_ui.gd`) still lacks tool 4, secondary action, map and ping; the
   glyph layer can label them but cannot create them.
12. **One flake observed and removed**: auto-polling the mission-letter HUD flag made the full E2E
   run fail 16–18 movement/tool checks once (letter opened after the harness had started playing).
   Design changed to an explicit push/pop; two subsequent full runs passed. Any future auto-polling
   of a streaming-timed modal must be treated as a flake source.
