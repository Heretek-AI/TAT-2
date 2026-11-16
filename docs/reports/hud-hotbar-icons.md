# HUD Tool Hotbar Icons — Implementation Report

- Stage: hud-hotbar-icons
- Date: 2026-11-16
- Files changed: `game/src/ui/hud.gd` only (plus temp check, now deleted)

## Root cause

`hud.gd::_build_tool_hotbar` built each of the four tool slots as a stack of
three plain `TextureRect`s:

1. `T_Ability_Background.png` — verified opaque white 155×155 texture,
2. the real tool icon (44×44),
3. `T_Ability_Border.png` — verified opaque blue-green gradient texture.

Both the background and the border are fully opaque, so the border (drawn
last, on top) and the background (drawn first, underneath) completely covered
the icon. The hotbar therefore rendered as four blank white/gradient squares
instead of the real tool icons.

## New layering (`_build_tool_hotbar`)

Each slot (`Control`, 68×68) is now layered:

1. **Background** — `Panel` with `ThemeScript.panel_style(1, 10,
   Color(0.04, 0.06, 0.09, 0.55))`, border color overridden to gold
   `Color(0.9, 0.78, 0.45, 0.5)` (dark translucent rounded `StyleBoxFlat`,
   corner radius 10, 1px gold border). First child = behind everything.
2. **Icon** — single `TextureRect` child, `EXPAND_IGNORE_SIZE` /
   `KEEP_ASPECT_CENTERED`, 44×44 at offset (12, 12), modulate white.
   Loaded via `ResourceLoader.load`; if the texture is missing the slot keeps
   its background and text with no blank white rectangle and no error.
3. **Key label** — top-left `[[1] Sap]`-style label (left-aligned).
4. **Count label** — bottom-right count label; appended to `slot_count_lbls`
   exactly as before (4 entries, same update contract in `_process`).

Slot hotkeys/names/counts are unchanged: `[1] Sap`, `[2] Smoke`, `[3] Fairy`,
`[G] Ability`. The opaque `T_Ability_Background.png` / `T_Ability_Border.png`
textures are no longer referenced anywhere in the hotbar.

## Icon mapping per slot

| Slot | Hotkey / name | Icon texture |
|------|---------------|--------------|
| 0 | `[1] Sap` | `res://assets/ue/Raw/Art/UI/Icons/Icon_Ability_Lockpick.png` |
| 1 | `[2] Smoke` | `res://assets/ue/Raw/Art/UI/Icons/Rewards/Gear/T_Bomb_Smoke_Wide.png` |
| 2 | `[3] Fairy` | `res://assets/ue/Raw/Art/UI/Icons/Rewards/Gear/T_PickpocketFairy_Wide.png` |
| 3 | `[G] Ability` | `res://assets/ue/Raw/Art/UI/Icons/Rewards/Gear/T_Zipwire_Wide.png` |

## Verification (temp SceneTree script, deleted after run)

Temporary `game/tests/tmp_hotbar_check.gd` instantiated the HUD with autoloads
(`GameState.active_contract_order = 3`), awaited frames, and asserted:

- four slots exist and `slot_count_lbls` still has 4 entries;
- each slot has exactly one `TextureRect` icon child whose texture path is one
  of the four real icons and whose `size` is non-zero (44×44);
- no child uses `T_Ability_Border.png` (or `T_Ability_Background.png`);
- the slot background is a `Panel` with a `StyleBoxFlat` and precedes the icon
  in child order.

Temp output (exit 0, no script errors):

```
PASS: slot_count_lbls has 4 entries
PASS: four hotbar slots exist
PASS: slot has exactly one TextureRect icon child        (x4)
PASS: slot icon uses .../Icon_Ability_Lockpick.png
PASS: slot icon uses .../T_Bomb_Smoke_Wide.png
PASS: slot icon uses .../T_PickpocketFairy_Wide.png
PASS: slot icon uses .../T_Zipwire_Wide.png
PASS: slot background is styled Panel/ColorRect          (x4)
PASS: background precedes icon in child order            (x4)
PASS: slot icon size non-zero: (44.0, 44.0)              (x4)
HOTBAR-CHECK: all icon/layering assertions passed
```

The temp file was deleted afterwards (`game/tests/tmp_hotbar_check.gd` no
longer exists; `game/tests/run_tests.gd` untouched).

## Full suite

- `make test` → `SUMMARY: fails=0`, exit 0.
- `make test 2>&1 | grep -c "SCRIPT ERROR"` → `0` (zero SCRIPT ERROR lines).
  Only benign exit-time ObjectDB/RID leak warnings remain.

## Self-audit

- Touched only `game/src/ui/hud.gd`, the temp check (deleted), and this report.
- Did not touch `game/tests/run_tests.gd`, other UI scripts, gameplay/level/
  weather/audio files, parsers, extractor, Makefile, or Android files.
- No stubs: missing-icon path keeps background + text, no `TODO`/placeholder.
- Nothing unfinished.
