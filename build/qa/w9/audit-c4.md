# W9-P3 C4 — independent audit (authored [TAB]-map boundaries + authored loot toast)

**Auditor:** independent subagent. I did not write the C4 code, did not edit source, tests or commits.
**Worktree:** `/home/john/Projects/TAT-2-rem-w9-p3`, branch `rem/w9-p3`.
**HEAD:** `3a9aa34aeeffc057a36c2eb16f7f365ea9b4f7eb` ("w9(p3): authored screens, Loc wiring, pad
focus, TAB map + toast"), which is hash-identical to the audited worktree for every C4 file
below (the commit landed mid-audit; the older commit in the text, `8ce9a86`, is its parent and
the only correct "no test weakened" baseline).
**Date:** 2026-11-25.
**Rules honoured:** read-only except this file; every Godot run headless and serial under
`flock /tmp/opencode/tat2-godot.lock -c 'timeout … tools/godot --headless --path game --script …'`;
no Vulkan, no capture, no producer run, no `make normalize`, no commit.

**Snapshot timeline.** The C4 owner was editing this worktree while the audit ran. Several
snapshots were seen; the authoritative audit below is the **final settled snapshot**
(settled 16:26:58, unchanged through the runs at 16:29; all final runs on these hashes):

```
7b6634320bd0bd76  game/src/ui/hud.gd                       (final)
a96abee3464c1746  game/src/ui/ui_toast.gd                  (final; icon + sound fixed mid-audit)
5f3fa03e9d0542fc  game/src/ui/map_boundaries.gd            (unchanged throughout)
3b4120c50f751cbe  game/src/interact/loot_item.gd           (P2-owned, unmodified vs 8ce9a86)
51db8a1753878aef  game/src/missions/mission_controller.gd
4ead6017fcfcf2da  game/tests/test_w9p3_map_toast.gd        (final; 36 checks, +C4.34–36)
cf602b695f4c2f7c  build/qa/w9/p3-report.md
99cede86d45b102c  build/qa/w9/parse_tables-map-boundaries.patch
```

Mid-audit the owner landed fixes for the label re-show, the icon counter and the sound
constant, and added the carried-loot growth guard (which introduced F10). All are
re-verified below on the final code. Line numbers refer to the final snapshot.

---

## 1. Independent run of the C4 suite — **PASS**

```
flock /tmp/opencode/tat2-godot.lock -c 'timeout 900 tools/godot --headless --path game \
  --script res://tests/test_w9p3_map_toast.gd'
→ exit 0, 36 × ^PASS, 0 × ^FAIL
   W9P3_MAP_TOAST_SUMMARY: fails=0 checks=36
```

Log: `/tmp/opencode/w9c4/c4_test_final3.log` (not committed). The run ends with
`WARNING: 6 ObjectDB instances were leaked at exit` / `ERROR: 2 resources still in use at exit`,
the same shutdown noise other SceneTree suites emit; exit code 0. An earlier 33-check version of
the test (`ace9ede3`) was also 33/0 before the owner added C4.34–36.

### 1.1 Tautology review — the five required failure modes *are* covered

| If this broke… | check that fails | real? |
|---|---|---|
| parser drops a row | C4.1 `rows.size()==5` | yes |
| label missing/unresolved | C4.6/7/8 compare against the authored label; an empty label falls through to the actor name (`TATWorldMapBoundary_1`) | yes for a missing `label_source`; **no** for a broken Loc map (see T2) |
| anchor rect off | C4.9/C4.10 assert 315,621 and 1397×1058 /2048 | yes |
| HUD stops reporting fallback | C4.4 + C4.28 (`source_for_map`/`HUD.map_boundary_source` == `fallback`) and C4.29 (rows empty) | yes |
| major toast does not fire | C4.31 counts `Toast_*` panels 0→1; C4.32 finds the authored line; C4.33 proves minor raises none | yes (fresh pickup only — see F10) |

Tautologies / weak checks found (none of them is one of the five named modes):

* **T1 — C4.23 is still vacuous.** `_check(int(tstats.get("icon_fallback", 0)) >= 0, …)` can
  never fail: a counter is non-negative. The count is now real (0 → 1 with the HUD path, §5b),
  but the assertion does not test it. The report claims "C4.23 now asserts ≥1"
  (`p3-report.md:286`) — **false at this snapshot**.
* **T2 — C4.6/7/8 cannot distinguish a working Loc from a no-op.** `label_for()` falls back to
  `label_source`, and every `label_source` is already the English string the check expects
  (`Constables' Guildhall`, `First Floor`, `Basement`). With `UIStrings.loc()` returning its
  input untouched, all three still pass. (The GUID→source reverse map *does* contain these
  strings — verified — but the test does not prove it is used.)
* **T3 — C4.24 is a negative-existence check.** `not ResourceLoader.exists(T_UI_Smoke.png)`
  passes as long as no such texture is added; it does not verify the port *labels* the
  reconstruction (that label is only a comment in `ui_toast.gd`).
* **T4 — no extent assertion.** The test never asserts any `size` value, and C4.4/15 would
  still pass with `game/data` absent (only the anchor checks touch parsed numbers). A Y/Z swap
  would be caught only indirectly by C4.11; an X/Z swap would not be caught at all (the
  Guildhall boxes are square in XZ). The formula and emitted sizes are nevertheless correct
  (§2/§3).
* **T5 (new, coverage)** — the toast checks never exercise a **decrease** in carried slots
  (stash) followed by a pickup, which is exactly the path F10 breaks.

C4.30 (`pause_panel_for_test() != null`) is unrelated to C4 (a focus-walk leftover); harmless.
C4.15 deliberately pins *today's* un-produced state — see F9. The new C4.35 pins the P2 label
re-show until `loot_item.gd` is cleaned up — see F9.

---

## 2. Authored truth from the extract — **PASS (13/13, every number reproduced)**

`extracted/json/Maps/{Guildhall,OldManor,FTUE,ThievesDenTest}/*_P.json` contain exactly
**5 + 6 + 1 + 1 = 13** actors whose `Type` is `TATWorldMapBoundary` (not `"Actor"` — the
producer's `et` test is valid). Positions are the producer's `ue_mat4_to_godot_trs` =
`(x, z, y)·0.01`; `size` is the full extent in Godot metres `(2·ex·sx, 2·ez·sy, 2·ey·sz)·0.01`;
Y span is `pos.y ± size.y/2`.

| map | actor | UE RelativeLocation (cm) | UE scale | Godot pos (m) | size (m, x/y/z) | Y span | label: source / key / table | MapType | anchors | hOff |
|---|---|---|---|---|---|---|---|---|---|---|
| Guildhall | `_0` | 1454, 701, 6730 | 117.5, 117.5, 1 | 14.54, 67.3, 7.01 | 235, 2, 235 | 66.3–68.3 | Constables' Guildhall / `Guildhall.MapName` / `ST_MapTool` | (empty → primary) | 315,621→1712,1679 | 7500 |
| Guildhall | `_1` | 1024, −3784, 2750 | 50, 50, 7 | 10.24, 27.5, −37.84 | 100, 14, 100 | 20.5–34.5 | First Floor / `F5968C2D…` / — | Secondary | 315,621→1712,1679 | 0 |
| Guildhall | `_2` | 1024, −3784, 3950 | 50, 50, 4 | 10.24, 39.5, −37.84 | 100, 8, 100 | 35.5–43.5 | Second Floor / `2812591E…` / — | Secondary | 315,621→1712,1679 | 0 |
| Guildhall | `_3` | 1024, −3784, 5224 | 50, 50, 8 | 10.24, 52.24, −37.84 | 100, 16, 100 | 44.24–60.24 | Rooftop / `9E203849…` / — | Secondary | 315,621→1712,1679 | 0 |
| Guildhall | `_5` | 2984, −951, 625 | 74, 74, 12 | 29.84, 6.25, −9.51 | 148, 24, 148 | −5.75–18.25 | Basement / `0432A8E5…` / — | Secondary | 315,621→1712,1679 | −350 |
| OldManor | `_1` | −465.0, 3839.08, 927.81 | 106, 98, 4.25 | −4.65, 9.278, 38.391 | 212, 8.5, 196 | 5.03–13.53 | Elway Manor / `OldManor.MapName` / `ST_OldManor_map` | (empty → primary) | 451,577→1598,1724 | 0 |
| OldManor | `_4` | −465.0, 3839.08, 1204.60 | 106, 98, 4.25 | −4.65, 12.046, 38.391 | 212, 8.5, 196 | 7.80–16.30 | Ground Floor / `8F118E07…` / — | Secondary | 451,577→1598,1724 | 0 |
| OldManor | `_5` | −465.0, 3839.08, 2033.22 | 106, 98, 4.25 | −4.65, 20.332, 38.391 | 212, 8.5, 196 | 16.08–24.58 | 2nd Floor / `7ED94439…` / — | Secondary | 451,577→1598,1724 | 0 |
| OldManor | `_6` | −465.0, 3839.08, 2830.55 | 106, 98, 4.25 | −4.65, 28.306, 38.391 | 212, 8.5, 196 | 24.06–32.56 | 3rd Floor / `290F5523…` / — | Secondary | 451,577→1598,1724 | 0 |
| OldManor | `_7` | −465.0, 3839.08, 4682.23 | 106, 98, 7.25 | −4.65, 46.822, 38.391 | 212, 14.5, 196 | 39.57–54.07 | "Tower " / `0025608A…` / — | Secondary | 451,577→1598,1724 | 0 |
| OldManor | `_8` | −465.0, 3839.08, −197.15 | 106, 98, 7.5 | −4.65, −1.972, 38.391 | 212, 15, 196 | −9.47–5.53 | Basement / `CF693FF0…` / — | Secondary | 451,577→1598,1724 | 0 |
| FTUE | `_0` | −5043.64, 8919.88, 2000 | 146.01367, 161.17963, 1 | −50.436, 20.0, 89.199 | 292.027, 2, 322.359 | 19–21 | Kilcairn Back Alley / `93A665B8…` / — | (empty → primary) | 315,621→1712,1679 | 1000 |
| ThievesDenTest | `_1` | 317.83, 26886.75, 4000 | 32, 32, 1 | 3.178, 40.0, 268.867 | 64, 2, 64 | 39–41 | *(no MapLabel)* | (empty → primary) | 0,0→0,0 | 0 |

Confirmations:

* **The 5-row synthetic payload in the test is 1:1 with Guildhall** `_0/_1/_2/_3/_5`:
  positions, sizes, label source/key/table, `map_type`, `primary`, anchors and height offsets
  all match the table. **No wrong number found.**
* **100 cm class default.** None of the 13 *actors* serializes `BoxExtent`; the 9 root
  `BoxComponent`s that do serialize it carry exactly `(100,100,100)` (Guildhall
  `_1/_2/_3/_5`, OldManor `_4.._8`), and four omit it (the primaries `_0`/`_1`, FTUE `_0`,
  Den `_1`). The default is independently corroborated by the authored scene-capture
  `OrthoWidth`: Guildhall `_0` 23500 cm = 235 m = 2·100·117.5 cm; FTUE 29202.734 cm = 292.027 m
  = 2·100·146.01367 cm; OldManor `_1` 21180.918 cm = 211.81 m ≈ 212 m. (The C++ CDO is not in
  the extract — there is no `Default__TATWorldMapBoundary` export — so 100 cm is inferred, but
  the three exact matches make it solid.)
* **GUID-only labels** (Guildhall `_1/_2/_3/_5`, OldManor `_4.._8`, FTUE `_0`) carry a locres
  GUID in `MapLabel.Key` with no `TableId`; every `SourceString` is present in
  `game/data/generated/localization/sources.json` (checked for all, including `Tower ` with its
  authored trailing space), so `label_for()`'s `UIStrings.loc(source)` does hit the reverse map.
* **Den `_1`** has no label → `label_for()` returns the actor name `TATWorldMapBoundary_1`;
  the shipped scene has no label here either, so nothing better exists.
* The anchors fit the 2048² map textures (all 14 `T_mapTool_*`/`T_Map_FTUE_D` PNGs are 2048²;
  the only non-2048 file in that tree is the unrelated `Clues/T_clue_bg.png` 1024×256).

---

## 3. Producer contract — **PASS (applies, compiles, right fields, not applied, not run)**

```
git apply --check build/qa/w9/parse_tables-map-boundaries.patch   → exit 0
patch -p1 (on a /tmp copy) + python3 -m py_compile               → PY_COMPILE_OK
git diff -- tools/parse_tables.py | wc -l                        → 0
git status --short tools/                                        → " M tools/consumer_allowlist.json" only
```

The patch adds `boundaries = []` (line 1784), a `if et == "TATWorldMapBoundary":` branch
(lines 2374–2441) before the generic actor capture, and `"map_boundaries": boundaries` in the
level payload (line 3177). Fields emitted per row: `name`, `class`, `**trs` (`pos`, `basis`,
`scale`), `size`, `label_source`, `label_key`, `label_table`, `map_type`, `primary`,
`anchor_top_left`, `anchor_bottom_right`, `texture_height_offset`, `source` — a superset of
what `MapBoundariesScript.parse()` consumes (it ignores `class`, `basis`, `scale`, `source`).
`primary` = empty `MapType` or `…Primary`, which marks exactly the four primaries above.

Contract caveats (none changes today's numbers):

* **The patch reads `BoxExtent` from the wrong object.** `props` is the *actor's* bag; the
  serialized `BoxExtent` lives on the root `BoxComponent` (which `get_world_mat` already
  resolves). All 13 resolve to 100 cm today, so `size` is correct, but "Override per actor if
  serialized" is not what the code does. Fix: read the resolved component's extent.
* **Axis-label nit** in the patch comment `# Full extent in Godot metres (x, z, y)`: the array
  is Godot `(x, y, z)` (x = UE X, y = UE Z, z = UE Y). The numbers are right; the parenthetical
  invites a future Y/Z swap.
* **`map_boundaries` is not in `li_merge_keys`** (Pass-2 LevelInstance merge, `parse_tables.py`
  ~3134). All 13 actors are in the persistent `*_P` levels, so nothing is lost today; a
  boundary authored in a LevelInstance would be dropped. `spawn_elements` has the same
  precedent, but the contract should say so.
* **`continue` removes boundaries from `actors`.** `TATWorldMapBoundary` matched none of the 4b
  capture predicates before (not `_C`, no spawner keyword), so the `continue` is a no-op for
  `actors`; `manifest_audit.py` iterates `actors` and is unaffected.
* **`map_boundaries: []` will appear in every level payload** after regeneration, not only the
  four with actors. The reader ignores empty arrays; it is extra JSON churn.

**No producer was run:** `grep -rn map_boundaries game/data/generated/levels/` → **0 hits**; the
four payload mtimes are `2026-11-25 14:37`, before the earliest P3 edit (14:54), and the shared
`game/data` tree is the main checkout's symlink. `git diff` for `parse_tables.py` is empty, so
the patch is *not* applied.

---

## 4. Today's fallback and the invented floor — **PASS**

* **0 authored rows today:** `grep -rl map_boundaries game/data/generated/levels/` → 0 files.
  `MapBoundaries.source_for_map("guildhall")` → `fallback`; the test's
  `HUD.map_boundary_source()` → `fallback` (C4.28) and `map_boundary_rows()` is empty (C4.29).
* **The fallback is labelled in code:** `hud.gd:643` draws
  `"FALLBACK BOUNDS - NO AUTHORED TATWorldMapBoundary"` whenever `boundaries.is_empty()`, and
  `map_boundaries.gd:215` names the state `fallback`, documented as "the player-centred 64 m
  window is the port's labelled stand-in, not authored data".
* **The invented floor is labelled:** `mission_controller.gd:3352–3358` opens
  `_add_safety_floor()` with `## PORT INVENTED — NOT AUTHORED (W9-P3 C4). No authored KillZ /
  ## KillZVolume exists anywhere in the extract … the authored behaviour is UNKNOWN`. Call
  site `mission_controller.gd:713`.
* **No authored KillZ exists:** `grep -ril killz extracted/json/` → **0** files;
  `grep -ril killz extracted/raw/` → **0** files. The comment's claim is true and it correctly
  refuses to use UE's un-serialized default as evidence.

---

## 5. The authored toast — **FAIL** (the growth guard now swallows a legitimate pickup)

### 5a Authored text + live names — PASS

`extracted/json/UI/Toasts/DT_ToastConfig.json` `NewRow_12`:
`ToastId = Toast.Type.Gameplay.Loot.Taken`, `CooldownType = NoCooldown`,
`SingletonToast = false`, `MatchRelatedToast = true`,
`DefaultIcon = S_LootItem_Artifact_Chalice`,
`SoundEffect = Play_ToastSystem_LootDeposited_Message_FlyIn`.
`extracted/json/StringTables/ST_Toasts.json` (namespace `Toasts`):
`MajorLootTaken = "{PlayerName} took the {MajorLootName}!"` and
`DepositedMajorLoot_Local = "You stashed the {MajorLootName}!"` — both exact.
`game/data/generated/tables/StringTables/ST_Toasts.json` carries both rows, so
`UIStringsScript.raw()` reads real data (C4.16 is a genuine check with an empty fallback).
`ui_toast.gd:63–66` uses `st_template("ST_Toasts","MajorLootTaken",…)`; `show_major_loot()`
(78–83) fills `PlayerName` from `GameState.player_display_name()` (`game_state.gd:143–152`,
"The Spider"/"The Chameleon", Loc-routed) and the HUD passes the entry's `display_name`
(falling back to `name`) at `hud.gd:936–939`. Cat Statue is authored `tier: "major"`
(`DT_LootInfo_Major.json` row `CatStatue`, value 225), so a real pickup
(`LootInventory.carry` → `notify_carried_loot_changed`) produces
"The Spider took the Cat Statue!" (C4.17/C4.20/C4.21/C4.32).

Port decision: `MajorLootTaken` has no Local/Remote pair in the table (the facts file already
flags the local substitution as UNKNOWN); the code uses the local display name without saying
it is a port decision — minor labelling gap.

### 5b Panel / icon / animation — PASS (the icon fallback is now counted)

The widget is the authored `BPUI_ToastWidget`: `Border_255` with
`Background.ResourceObject = Material'M_UI_Smoke'`, a `HorizontalBox` of `SizeBox_0`
(`ToastText`, CF_Raleway 32) + `MessageIconOuter` (72×72) → `MessageIcon` (64×64), animations
`Show` and `EyeCatchingShow`; the container is a `VerticalBox` (`MessageContainer`).
`M_UI_Smoke.json` is `EMaterialDomain::MD_UI` + `BLEND_TranslucentGreyTransmittance` with
global `CornerRadius`/`Power` parameters and **no texture object** (no `T_UI_Smoke` on disk).
`ui_toast.gd:195–204` labels its `StyleBoxFlat` a "Port reconstruction of `M_UI_Smoke`", and
`_play_show` labels the two UMG animations as a reconstruction. Honest.

The mid-audit fix is real: `icon_source = "major_loot_glyph"` for `MAJOR_LOOT_ICON`, and
`_icon_fallback += 1` when that texture loads (`ui_toast.gd:98–109`). With the HUD passing
`icon_res=""`, the counter now goes 0 → 1 (`stats()` at 225–226), matching the report's
"counted as `icon_fallback`". Residual: the class docstring at `ui_toast.gd:13–14` still says
the NewRow_12 sound is `Play_ToastSystem_Generic_Message_FlyIn` — the constant at line 30 is
correctly `…LootDeposited…`, and NewRow_13 (`Loot.Dropped`) is the generic cue. Also
`LOOT_SOUND` is still never used (runtime plays `AudioManager.play_ui("toast")`), so either
wire it or mark it diagnostic.

The destination glyph is authored (`T_Glyph_MajorLoot.png`, 256², referenced by
`MI_ThiefWriting_MajorLoot`/quest data), and the row's PaperSprite atlas is available
(`T_Icon_Loot.png` 2048², `BakedSourceUV 1024,768`, 256²), so a faithful `AtlasTexture` is
possible and the glyph is a labelled-but-substituted icon.

### 5c Major-only trigger — **FAIL (new regression: the growth guard misses a post-stash pickup)**

The tier gate is right: `hud.gd:934` returns unless `entry.tier == "major"`; C4.33 proves a
minor entry raises nothing, and a stash cannot false-toast (deposit keeps only quest entries,
authored `tier: "quest"`, `mission_controller.gd:3997`; `reset_run` clears `carried_loot`
before emitting, `game_state.gd:305,338`).

The owner then added the facts-file growth guard (`hud.gd:913–921`) — and it is wrong:

```gdscript
if _carried_used_seen >= 0 and used <= _carried_used_seen:
    return                     # ← baseline is NOT updated on a decrease
_carried_used_seen = used
```

`_carried_used_seen` is only written when `used` grows. On a stash (or a run reset) `used`
drops to 0 and the handler returns early, leaving the baseline at the pre-stash peak. Major
loot costs **3 slots** (`SLOT_COST = {"minor": 1, "major": 3, "quest": 1}`), so after stashing
one major item the next major pickup is `used == _carried_used_seen` and is **silently
swallowed** — no toast at all until the player's carried slots exceed the old peak.

Probe (`/tmp/opencode/w9c4/probe_growth_guard.gd`, final hud `7b663432`, log
`c4_growth_probe3.log`):

```
PROBE start toasts=0 seen=0
PROBE after_major_1 toasts=1 seen=3     ← first major pickup toasts
PROBE after_stash toasts=1 seen=3       ← stash (3→0) does not lower the baseline
PROBE after_major_2 toasts=1 seen=3     ← second major pickup is NOT toasted (bug)
```

Same for a run reset while the HUD persists (HUD is created once in
`mission_controller._ready`, and the Den → contract flow reuses the controller). Fix is one
line: compute `grew = used > _carried_used_seen` first, **always** assign
`_carried_used_seen = used`, then return when `not grew`. The test (C4.31–33) never exercises a
decrease (T5), so it stays green over the bug.

### 5d Suppressing the port-invented world Label3D — **PASS (fixed and independently reproduced)**

The HUD suppresses at spawn (`hud.gd:954–983`: initial `loot` group scan + `node_added` →
deferred group check) and now also re-hides after the authored thief-vision highlight:
`set_thief_vision()` (`hud.gd:2433–2443`) schedules `_hide_all_loot_labels()` on every toggle,
and it runs after `thief_character._update_thief_vision()` has re-shown the label
(`loot_item.gd:155` group → `set_xray_highlight` → `set_highlighted` at 327–334). The HUD hook
is wired in `mission_controller.gd:722–723` (player `thief_vision_toggled` → `hud.set_thief_vision`)
and also driven each HUD tick at `hud.gd:2896`.

Probe (`/tmp/opencode/w9c4/probe_label.gd`, final hud/loot hashes; log `c4_label_probe3.log`):

```
PROBE label_after_spawn_visible=false
PROBE label_after_xray_on=true           ← the authored highlight pass re-shows it
PROBE label_after_hud_vision_on=false    ← the HUD undo now wins
PROBE label_after_hud_vision_off=false
```

The test now pins the same behaviour at C4.34 (hidden at spawn), C4.35 (vision re-shows — the
bug being undone) and C4.36 (HUD re-hides after the toggle). Quest/personal labels remain
visible by design (`is_quest_item`), which is the authored `Label3D` behaviour, not the toast's
target. Deleting the creation site stays BLOCKED-ON P2 as the report says; the HUD-side
suppression is now complete for the Cat Statue flow.

---

## 6. Does the HUD actually consume the rows? — **PASS (with dead fields)**

`_refresh_tactical_map()` (`hud.gd:3632–3656`) runs on map open, on every HUD tick while the
map is open, and on map click, and sets:

```
_map_draw.boundaries      = MapBoundariesScript.for_map(active_map_id)   (line 3653)
_map_draw.boundary_source = "authored"|"fallback"                        (line 3654)
_map_draw.active_boundary = MapBoundariesScript.boundary_at(rows, player) (line 3655)
```

`TacticalMapDraw._compute_bounds()` (546) uses the primary row's XZ box as the map extent;
`_draw()` (587) iterates `boundaries` and draws every floor rect (primary filled, active border
2 px/0.86 alpha vs 1 px/0.26), then a label list on the left and the active label at the top;
the empty case draws the fallback string. There is no dead `boundaries`/`active_boundary`.

Dead / runtime-unused fields found:

* **`TacticalMapDraw.boundary_source` (line 536)** is assigned at 3654 and never read (not even
  by `_draw`, which tests `boundaries.is_empty()`). The HUD's `_boundary_source` is the one
  exposed by the test hook. Delete the inner field or use it for the fallback label.
* **`anchor_top_left` / `anchor_bottom_right` / `anchor_rect()` / `texture_height_offset`** are
  parsed but have **no runtime consumer**: `anchor_rect()` is called only by the test. The [TAB]
  map draws world boxes, not the authored map render texture, so the authored crop and
  `MapRenderTextureHeightOffset` never reach the screen. Not a wrong number (2048 is correct),
  but an unconsumed part of the actor.
* `UIToast.stashed_text()` (70–72) has no runtime caller (only C4.18) — the authored stash line
  is implemented but unwired.
* `UIToast.show_text(..., eye_catching)` is never called with `true` (the authored
  `EyeCatchingShow` is unreachable); `show_major_loot` hardcodes `icon_res=""`.

Floor selection is a **port reconstruction, not authored switching**: `boundary_at()` uses the
root capture boxes with a −3/+1 m vertical tolerance. The extract has a separate authored
`AutoSwitchOverlapComponent` on every secondary (a ~1.98 m box, Pawn = Overlap; disabled on
the primaries) — the component whose name/collision response says "auto-switch the map floor" —
which the reader does not mention or use. Practical effect of the root boxes + tolerance:
first-match wins in the overlap bands, e.g. on OldManor y 4.80–5.53 m (basement top) reads as
**Ground Floor**, and on Guildhall y 32.5–35.5 m reads as **First Floor**. Worth a labelled note
(or using the auto-switch volume) before calling the floor pick authored.

Also wrong (comment only): `hud.gd:548` says "Guildhall `_0` is a **75.2 m** slab". The
producer's 100 cm default makes it **235 m**; 75.2 m is exactly the abandoned 32 cm default
(2·32·117.5 cm), so the comment is a leftover from the earlier hypothesis and contradicts
`map_boundaries.gd`'s own "235 m full".

---

## 7. No test or P2 file was weakened — **PASS**

```
git diff 8ce9a86 --stat -- game/tests game/src/interact
 game/src/interact/clue_item.gd      | 11 +++++++----
 game/src/interact/loot_container.gd | 20 +++++++++++---------
 game/tests/run_tests.gd             | 27 +++++++++++++++++++++++++++
 3 files changed, 45 insertions(+), 13 deletions(-)
```

* `game/tests/`: only `run_tests.gd` changed, **+27 lines, 0 deletions** (suites 106–109, each
  gated on exit 0 *and* its summary marker; suite 108 is `test_w9p3_map_toast.gd` /
  `W9P3_MAP_TOAST_SUMMARY: fails=0`). No expectation changed, no test skipped/deleted. The
  C4 suite itself was **strengthened** during the audit (33 → 36 checks, +C4.34–36).
* `game/src/interact/loot_item.gd`: **unchanged vs 8ce9a86** (label creation 209–215,
  `set_highlighted` 327–334 are originals). The suppression is HUD-side, as claimed;
  `clue_item.gd`/`loot_container.gd` are the C2 localization lane (Loc routing), not C4.
* `git status --short tools/` shows only `consumer_allowlist.json` (removal of the
  `videos.json` blocked-on-team entry — another P3 lane, not C4; `parse_tables.py` untouched).

---

## Per-item verdict

| # | item | verdict |
|---|---|---|
| 1 | C4 suite passes 36/0 and fails on the five required modes; tautologies reported | **PASS** (T1–T5; C4.23 still vacuous) |
| 2 | 13 authored actors, labels/anchors/extents; synthetic payload + producer formula match | **PASS** (13/13; 100 cm corroborated by OrthoWidth) |
| 3 | Producer patch applies/compiles, emits the consumed fields, is not applied, no producer run | **PASS** (5 contract caveats) |
| 4 | 0 `map_boundaries` today → labelled fallback; safety floor PORT INVENTED; no authored KillZ | **PASS** |
| 5 | Authored toast string/names/pattern; major-only trigger; label suppression | **FAIL** — 5a/5b/5d pass; **5c fails** (growth guard swallows the first major pickup after a stash) |
| 6 | HUD consumes `boundaries`/`active_boundary` in `_refresh_tactical_map` + `_draw`; dead fields reported | **PASS** (dead `boundary_source`, unused anchors/offset, floor-pick caveat, wrong 75.2 m comment) |
| 7 | No test weakened; `loot_item.gd` untouched; suppression HUD-side | **PASS** (suite strengthened) |

## Final verdict

**AUDIT: FAIL (1 of 7 items).** The data/producer half is sound and the mid-audit fixes hold: the
13 actors, every position, full extent, label and anchor in the synthetic payload match the
extract and the producer formula; the patch applies/compiles, emits exactly what the reader
consumes, is not applied and was not run; today's payloads are empty and the fallback + invented
safety floor are labelled; the HUD consumes the rows; the icon fallback is now counted, the
label is now suppressed across the thief-vision toggle (probe + C4.34–36), the sound constant is
corrected, and no test or P2 file was weakened. The remaining blocker is the **new carried-loot
growth guard**: after a stash (or a run reset while the HUD persists) `_carried_used_seen` keeps
its stale peak, so the next major pickup of the same slot cost raises **no toast** — proven with
a read-only probe (1 → 1 toast, `seen` stuck at 3). The test does not cover a decrease, so it
stays green.

Fix list, smallest first:

1. **F10 (blocking):** in `hud.gd:913–921` compute `grew = used > _carried_used_seen` (or
   `_carried_used_seen < 0`), **always** assign `_carried_used_seen = used`, then return when
   `not grew`; add a test step: major (3) → clear/stash → major (3) must toast again.
2. **F11 (report accuracy):** `p3-report.md:286` says "C4.23 now asserts ≥1" — the final test
   still has `>= 0`; either change the assertion to `>= 1` (the counter now reaches 1) or fix
   the report.
3. **F2 residual:** `ui_toast.gd:13–14` still names `Play_ToastSystem_Generic_Message_FlyIn`
   as NewRow_12's sound (line 30 is correct). Wire or delete the unused `LOOT_SOUND`.
4. **F4:** fix `hud.gd:548` — the primary slab is **235 m**, not 75.2 m (that is the 32 cm
   default the producer correctly abandoned).
5. **F3:** make C4.23 assert the icon *source* (`major_loot_glyph`) and consider asserting the
   parsed `size` values so an X/Z swap is caught.
6. **F6:** delete `TacticalMapDraw.boundary_source`; consume the anchors/height offset or mark
   them test-only; wire `stashed_text()` or mark it diagnostic.
7. **F8:** label the floor pick as a port reconstruction (or use the authored
   `AutoSwitchOverlapComponent`) and note the ±3/+1 m overlap bands.
8. **F9 (integrator):** C4.15 pins the un-produced state; applying the producer contract and
   regenerating will (correctly) flip C4.4/15 to `authored`, so update them in the same wave.
   C4.35 pins the P2 `Label3D` re-show and must be updated when `loot_item.gd` is cleaned up.

## Not verified / limits

* The HUD's *authored* draw path (rows present) was **not executed**: injecting rows would
  require writing into the shared generated data tree or a test file, both outside this audit's
  write scope. It is statically verified (assignments + draw loops) but has no runtime evidence
  yet; the producer regeneration is the natural first exercise.
* The 8 non-Guildhall rows are not in the synthetic payload; their numbers are computed from the
  extract with the patch's formula, not from a produced payload.
* The C++ class default (100 cm) has no CDO in the extract; it is inferred and corroborated by
  three exact `OrthoWidth` matches (§2).
* Only the C4 suite and two purpose-built read-only probes (label suppression, growth guard)
  were run. `run_tests.gd` (312 PASS claimed), compile, E2E, `make audit` and the other lanes'
  gates were **not** re-run by this audit; they belong to the lead's merged-tree gate set.
* The worktree is shared with other W9-P3 lanes (localization, screens, focus, ledger,
  post-match); their edits (including the `consumer_allowlist.json` change and the mid-audit
  `hud.gd`/`ui_toast.gd`/test rewrites) were not audited beyond the C4 surface. The final
  snapshot hashes above were unchanged from 16:26:58 through the 16:29 test and probe runs;
  if the tree moves again, the C4 suite and the two probes must be repeated.

---

## Re-audit (3a9aa34)

**Scope:** only the C4 findings above, re-checked on the committed tree `3a9aa34` (HEAD; its C4
files are hash-identical to the audited snapshot: `hud.gd 7b663432`, `ui_toast.gd a96abee3`,
`test_w9p3_map_toast.gd 4ead6017`, `map_boundaries.gd 5f3fa03e`, `loot_item.gd 3b4120c5`,
`mission_controller.gd 51db8a17`). No source or test file was edited. **This section
supersedes §5d and §6's dead-field line above; all other §1–§7 findings stand.**

All runs headless and serial under `flock /tmp/opencode/tat2-godot.lock`; logs in
`/tmp/opencode/w9c4/` (not committed).

| item | verdict | one-line evidence |
|---|---|---|
| 5d label suppression | **FIXED** | probe: spawn `false` → xray on `true` → HUD vision on `false` → off `false`; C4.34–36 pass |
| 5b F2 icon counter/source | **FIXED** | `stats() = {"shown":1,"live":1,"icon_fallback":1}`; `show_major_loot(...,"")` returns `icon="major_loot_glyph"` |
| 5b C4.23 assertion | **NOT FIXED** | `test_w9p3_map_toast.gd:208` still `>= 0`; "C4.23 now asserts ≥1" is false |
| 5b sound constant | **FIXED** | `LOOT_SOUND = Play_ToastSystem_LootDeposited_Message_FlyIn` == DT_ToastConfig `NewRow_12.SoundEffect` |
| 5c growth guard | **NOT FIXED** | probe: stash 3→0 leaves `seen=3`; next major (used 3) raises no toast |
| 6 `boundary_source` dead field | **FIXED** (my §6 report was stale) | `_draw` now reads it: `elif boundary_source == "fallback"` (`hud.gd:640`) |
| 6 still-unused parsed fields | **NOT FIXED** | anchors/`anchor_rect` test-only; `texture_height_offset` and `map_type` have no consumer |
| `loot_item.gd` untouched | **CONFIRMED** (confirmation item, no fix expected) | `git diff 8ce9a86 -- game/src/interact/loot_item.gd \| wc -l` → `0` |

### 5d — FIXED

`hud.gd:2433–2443` now calls `_hide_all_loot_labels()` (deferred) whenever
`set_thief_vision()` changes state; the hook is wired from the player signal in
`mission_controller.gd:722–723` (`thief_vision_toggled` → `hud.set_thief_vision`) and also
driven per HUD tick at `hud.gd:2896`. Probe (`probe_label.gd`, `re_c4_label.log`, exit 0):

```
PROBE label_after_spawn_visible=false
PROBE label_after_xray_on=true
PROBE label_after_hud_vision_on=false
PROBE label_after_hud_vision_off=false
```

The suite reproduces it at C4.34/C4.35/C4.36 (all PASS):
`W9P3_MAP_TOAST_SUMMARY: fails=0 checks=36`, 36 `^PASS`, 0 `FAIL`, exit 0
(`re_c4_test.log`). The deferred hide runs after `loot_item.set_highlighted`, so the
port-invented Cat Statue `Label3D` no longer survives the authored thief-vision pass.

### 5b icon — counter FIXED, C4.23 assertion NOT FIXED

`ui_toast.gd:98–110` now sets `icon_source = "major_loot_glyph"` for `MAJOR_LOOT_ICON` and
increments `_icon_fallback` when it loads. Probe (`probe_icon.gd`, `re_c4_icon.log`, exit 0)
through the real HUD toast:

```
PROBE hud_toast_stats={ "shown": 1, "live": 1, "icon_fallback": 1 }
PROBE direct_icon_source=major_loot_glyph displayed=true
```

So the report's "counted as `icon_fallback`" is true. **However** the test is unchanged at
`game/tests/test_w9p3_map_toast.gd:208`:

```gdscript
_check(int(tstats.get("icon_fallback", 0)) >= 0, "W9P3-C4.23 icon fallback counted (%d)" ...)
```

`p3-report.md:286` still says "C4.23 now asserts ≥1" — false at `3a9aa34`. The counter is
verified by the probe, not by the test.

### 5b sound — FIXED (one docstring residual)

`ui_toast.gd:30` is now
`const LOOT_SOUND: String = "Play_ToastSystem_LootDeposited_Message_FlyIn"`.
Extract check (`DT_ToastConfig.json` `Rows.NewRow_12`): `ToastId =
Toast.Type.Gameplay.Loot.Taken`, `DefaultIcon = S_LootItem_Artifact_Chalice`,
`SoundEffect = Play_ToastSystem_LootDeposited_Message_FlyIn` — exact match.
Residual: the class docstring at `ui_toast.gd:13–14` still names
`Play_ToastSystem_Generic_Message_FlyIn` (that is NewRow_13, `Loot.Dropped`). Comment-only.

### 5c — NOT FIXED (the guard still drops a post-stash pickup)

`hud.gd:913–921` is still:

```gdscript
if _carried_used_seen >= 0 and used <= _carried_used_seen:
    return                     # baseline is not updated on a decrease
_carried_used_seen = used
```

It *does* require growth (`used > _carried_used_seen` to proceed) and is initialised from
`GameState.carried_slots_used()` (`hud.gd:907`), but because the baseline is only written on a
growth, a stash (used 3 → 0) or a run reset leaves `_carried_used_seen` at the old peak.
Major loot is 3 slots (`SLOT_COST = {"minor":1,"major":3,"quest":1}`), so the next major pickup
after a stash is `used == seen` and is swallowed. Probe (`probe_growth_guard.gd`,
`re_c4_growth.log`, exit 0):

```
PROBE start toasts=0 seen=0
PROBE after_major_1 toasts=1 seen=3
PROBE after_stash toasts=1 seen=3
PROBE after_major_2 toasts=1 seen=3     ← no toast for the post-stash major pickup
```

Fix is still one line: compute `grew = used > _carried_used_seen` (or `seen < 0`), **always**
assign `_carried_used_seen = used`, then return if `not grew`; add a decrease→pickup step to
the suite.

### 6 — `boundary_source` is live now (correction to §6)

The fallback draw reads it: `hud.gd:640` `elif boundary_source == "fallback":` after the
`if not boundaries.is_empty():` branch, so `TacticalMapDraw.boundary_source` (assigned at
`hud.gd:3654`) is no longer dead. My §6 "dead field" line was stale.

Still parsed but unconsumed (with reasons):

* `anchor_top_left` / `anchor_bottom_right` — exposed through `MapBoundaries.anchor_rect()`,
  which only the test calls; the [TAB] map draws world boxes, not the authored map texture.
* `texture_height_offset` — no consumer anywhere (producer emits it, reader stores it).
* `map_type` — stored, no reader outside the test; `primary` is the usable projection of it.

### `loot_item.gd` — CONFIRMED untouched

`git diff 8ce9a86 -- game/src/interact/loot_item.gd | wc -l` → `0`. The label creation
(209–215) and `set_highlighted` (327–334) are the originals; the re-hide is HUD-side.

### Updated verdict

**AUDIT: FAIL** — of the six requested items, five are FIXED or CONFIRMED (5d, the icon
behaviour, the sound constant, `boundary_source`, `loot_item.gd`) and one is **NOT FIXED**
(5c). Two sub-claims also remain open: C4.23 is still a vacuous `>= 0` (the counter itself is
verified = 1), and the anchors/height-offset/`map_type` are still parsed but unconsumed. **5c is
the blocker**: the growth guard still swallows the first major pickup after a stash (or after a
run reset while the HUD persists), because `_carried_used_seen` is not lowered on a decrease.
The suite stays green only because it never exercises a decrease, and the report's
"C4.23 now asserts ≥1" remains false.

---

## Re-audit 2

**Scope:** only the two remaining C4 blockers on the current working tree (`3a9aa34` + the
lead's uncommitted fixes; `hud.gd 67554d41`, `ui_toast.gd 370f36a2`,
`test_w9p3_map_toast.gd 2b27c5e0`, `loot_item.gd 3b4120c5`). No source/test edit.

### 5c growth guard — **FIXED**

`hud.gd:913–922` is now:

```gdscript
var grew: bool = _carried_used_seen < 0 or used > _carried_used_seen
_carried_used_seen = used          # always follows the decrease
if not grew:
    return
```

Probe (`probe_growth_guard.gd`, `re2_c4_growth.log`, exit 0) — major, stash, major:

```
PROBE start toasts=0 seen=0
PROBE after_major_1 toasts=1 seen=3
PROBE after_stash toasts=1 seen=0     ← baseline follows 3 → 0
PROBE after_major_2 toasts=2 seen=3   ← post-stash major toasts again
```

Suite: `test_w9p3_map_toast.gd` exit 0, **37 `^PASS`, 0 `FAIL`**,
`W9P3_MAP_TOAST_SUMMARY: fails=0 checks=37`; the new regression pin passes:
`PASS: W9P3-C4.33a a major pickup after a stash decrease still toasts (1 -> 2)`.

### C4.23 assertion + toast docstring — **FIXED**

* `test_w9p3_map_toast.gd:208` now asserts `icon_fallback >= 1` (was `>= 0`);
  `PASS: W9P3-C4.23 the missing row PaperSprite is counted as an icon substitution (1)`.
* `ui_toast.gd:13–14` now names `Play_ToastSystem_LootDeposited_Message_FlyIn` for
  `NewRow_12` (matches `DT_ToastConfig.Rows.NewRow_12.SoundEffect`); the constant at line 30
  is the same value.
* Probe (`probe_icon.gd`, `re2_c4_icon.log`, exit 0):
  `hud_toast_stats={ "shown": 1, "live": 1, "icon_fallback": 1 }`,
  `direct_icon_source=major_loot_glyph displayed=true`.
* `loot_item.gd` still untouched vs `8ce9a86` (`git diff … | wc -l` → `0`).

### Updated verdict

**AUDIT: PASS.** Both remaining blockers are fixed and independently reproduced (stash→major
toast 1→2; `icon_fallback=1` with `major_loot_glyph`; 37/0). Residual non-blocking notes from
§6 stand: the `hud.gd:548` comment still says "75.2 m slab" where the 100 cm default gives
235 m, and `anchor_top_left/bottom_right` (`anchor_rect()` is test-only),
`texture_height_offset` and `map_type` remain parsed but unconsumed; the floor pick is still a
port reconstruction, not authored switching.

