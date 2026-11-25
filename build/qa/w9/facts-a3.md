# W9-P1 / A3 — plumbing facts: input path, curves consumers, material/token resolution

Worktree: `/home/john/Projects/TAT-2-rem-w9-p1` (branch `rem/w9-p1`, HEAD `c2a1cd89e5e3859c590c408236929da65567cb74`, 2026-11-25).
Read-only investigation: no edits, no Godot runs. All counts below were produced from the tree on disk
(`game/data/generated` is a symlink to the main checkout's generated tree; `extracted` and `game/assets` likewise).

---

# A. `input_actions.gd` — the generated table is unreachable (wrong directory **and** wrong schema)

## A1. Consumer constants and loader

| item | file:line | value / behaviour |
|---|---|---|
| class | `game/src/core/input_actions.gd:1` | `class_name InputActions` (global class, no preload needed) |
| docstring contract path | `game/src/core/input_actions.gd:14` | ``res://data/generated/input/input_actions.json`` — T01-PIPELINE's producer |
| `GENERATED_PATH` | `game/src/core/input_actions.gd:29` | `"res://data/generated/input/input_actions.json"` |
| `SCHEMA` | `:30` | `"tat2.input_actions/1"` |
| `load_table()` | `:321-339` | `FileAccess.file_exists(GENERATED_PATH)` → parse → `_validate_generated` → if non-empty use it as `source:"generated"`; else `AUTHORED_ROWS` → `source:"authored"`; else `source:""` (leave `project.godot [input]` untouched) |
| `_validate_generated()` | `:344-370` | `schema` must be empty or `tat2.input_actions/1`; bag is `doc["actions"]` else `doc["rows"]` and **must be an Array** (`:349-352`); each row needs non-empty `ia` (`:359-361`) and array `kb`/`pad` (`:362-364`); missing `deadzone` is filled with 0.2 (`:365-367`) |
| `AUTHORED_ROWS` | `:184-241` | **56 rows** (40 with a port `id`, 16 coverage-only `id:""`) |
| every use of `AUTHORED_ROWS` | `:247` (`rows()`), `:253` (`row_for()`), `:261` (`ids()`), `:304` (`port_id_for_ia()`), `:337` (`load_table()` fallback check) |

Public API (all `static`): `sensitivity_step_index/name`, `mouse_rad_per_px`, `pad_look_scale`,
`pad_move_scale`, `nearest_mouse_step` (`:116-146`); `rows`, `row_for`, `ids`, `is_coverage_only`,
`is_metadata_only`, `authored_key_names`, `deadzone_for`, `port_id_for_ia`, `is_pad_key`
(`:245-313`); `load_table` (`:321`), `events_for_key` (`:379`), `key_name_for_event` (`:418`),
`device_for_key` (`:452`), `apply_to_input_map` (`:464`), `bound_keys` (`:505`).

## A2. Producer path — proof

`tools/parse_input.py`:

- docstring output contract `:28` — `<out-dir>/gameplay/input_actions.json`.
- `--out-dir` default `:788-790` — `ROOT / "game" / "data" / "generated"`.
- write `:802-806` — `out_path = args.out_dir / "gameplay" / "input_actions.json"`, `write_text(json.dumps(...)+"\n")`.
- success line `:810` — `wrote gameplay/input_actions.json (contexts=…, shipping=91 mappings / 52 actions, …)`.

So the producer's real output is **`res://data/generated/gameplay/input_actions.json`**, i.e.
`game/data/generated/gameplay/input_actions.json` (270,658 bytes, present, 2026-11-25 04:48).

`game/data/generated/input/` **does not exist at all**:

```
$ ls -la game/data/generated/gameplay/input_actions.json game/data/generated/input/
-rw-r--r-- 1 john john 270658 Nov 25 04:48 game/data/generated/gameplay/input_actions.json
ls: cannot access 'game/data/generated/input/': No such file or directory
```

Because `GENERATED_PATH` names `input/`, `FileAccess.file_exists()` is false and `load_table()` takes
the `AUTHORED_ROWS` branch on every boot. `docs/reports/logs/r8/audit.log:48` reflects the same fact for
the *audit* (it says the allowlist rule "matched nothing", see A7).

## A3. Generated file facts (real file, measured now)

Top-level keys: `schema`, `generated_by`, `source`, `counts`, `contexts`, `actions`, `curves`, `unresolved`
(`schema:"tat2.input_actions/1"`, `generated_by:"tools/parse_input.py"`).

`counts` exactly as emitted (`tools/parse_input.py:754-767`):

```json
{"contexts": 5, "shipping_contexts": 3, "shipping_mappings": 91,
 "shipping_actions": 52, "all_mappings": 237, "all_actions": 54,
 "actions_assets": 65, "curve_assets": 2}
```

- **237 mapping rows total**, of which **91 are in the 3 shipping contexts**
  (`IMC_Character` 76, `IMC_Character_ClimbTest` 69, `IMC_Character_Testing` 77, `IMC_MapTool` 4, `IMC_Radial` 11).
- **54 distinct actions appear in rows** (52 shipping + 2 dev-only), while the `actions` object has **65** entries
  (11 more actions exist as assets with no authored mapping row: `IA_Ability01`, `IA_Ability02`,
  `IA_AbilityCancel`, `IA_Ability_LeanGamepadEnable`, `IA_Ability_SpecialAttack_Chord`,
  `IA_Open_Radial_Ability_Next`, `IA_Open_Radial_Ability_Prev`, `IA_Shove`, `IA_Weapon_01`, `IA_Weapon_02`,
  `IA_Weapon_03`).
- Real row 0 (all 18 fields, trimmed of nothing; `contexts.IMC_Character.mappings[0]`):

```json
{"action": "IA_Ability_Action_Primary",
 "action_path": "/Game/Gameplay/Input/Character/IA_Ability_Action_Primary.0",
 "key": "LeftMouseButton", "key_is_gamepad": false, "value_type": "Boolean",
 "trigger": null, "trigger_path": null, "modifiers": [], "chord_action": null,
 "player_mappable": true, "mappable_name": "ActionPrimary",
 "setting_behavior": "EPlayerMappableKeySettingBehaviors::InheritSettingsFromAction",
 "display_category": "Primary Fire", "display_name": "Interaction",
 "display_name_key": "InputSetting.Category.Interaction",
 "display_category_key": "InputSetting.PrimaryFire",
 "display_table": "/Game/StringTables/ST_Settings_Input.ST_Settings_Input",
 "mappable_settings_path": "/Game/Gameplay/Input/Character/IMC_Character.37"}
```

(A row that has a trigger carries it as an object: `{type, hold_time, path, properties}`, e.g.
`InputTriggerHold` → `{"type":"Hold","hold_time":0.2,...}`; all modifiers are `{type, lower, upper, path, properties}`
for `DeadZone`, or full OSE/TAT names for the custom ones — see `tools/parse_input.py:52-124`.)

## A4. Critical second defect: the producer's schema is not the consumer's schema

Even if `GENERATED_PATH` were corrected to `gameplay/`, **the generated file still cannot load**:

1. `_validate_generated` (`input_actions.gd:349-352`) looks for an **Array** under `actions` or `rows`.
   The producer's `actions` is a **Dictionary of 65 action assets** (`tools/parse_input.py:768-770`), and its
   mapping rows live under `contexts[*].mappings` — there is no top-level row array at all. The validator emits
   `"generated input table has no actions[]/rows[] array"` and returns `rows: []`.
2. Each producer row uses `action` + `key` + `key_is_gamepad` (A3), **not** the consumer's `ia` + `kb[]` + `pad[]`.
   Even a hand-built array of these rows fails `str(r.get("ia","")) == ""` at `:359-361`.
3. The producer has no port `id`/`consumer`/`mappable{}` concept; `IA_Move` is one authored 2D action, while the
   runtime needs the four 1D port actions (`move_forward/back/left/right`, `AUTHORED_ROWS:185-188`) that
   `thief_character.gd:1442` polls via `Input.get_vector`.
4. The producer has no legacy `Pause` row (it is a `DefaultInput.ini` mapping, not Enhanced Input —
   `AUTHORED_ROWS:221`), so a pure generated replacement would drop `pause` (`hud.gd:2340` consumer).

Conclusion: **the path fix is necessary but not sufficient**. A complete fix needs either
(a) a producer-side `rows[]` emission in `tat2.input_actions/1` row shape (T01), or
(b) a consumer-side adapter in `load_table()` that flattens `contexts[*].mappings` and applies the
port id/consumer split table (T06). Today `AUTHORED_ROWS` is the only usable representation.

## A5. Generated vs transcription diff (exact)

| metric | generated (`gameplay/input_actions.json`) | transcription (`AUTHORED_ROWS`) |
|---|---|---|
| mapping rows | 237 (91 shipping) | 56 |
| rows with a bindable port id | n/a (producer has no port ids) | 40 |
| coverage-only rows | 0 | 16 |
| distinct `IA_*` in rows | 52 shipping / 54 all | 52 `IA_*` + `Pause` |
| action assets | 65 | — |
| contexts | 5 (3 shipping) | character / radial / map / legacy row tags |

Action-set diff:

- **generated-only (rows):** `IA_AbilityLoadout_01`, `IA_Ability_SpecialAttack` — both only in
  `IMC_Character_Testing` (dev context), so not shipping content.
- **transcription-only:** `Pause` (`ctx:"legacy"`, `ia:"Pause"`, `AUTHORED_ROWS:221`).
- **generated action assets with no row:** the 11 names listed in A3.
- **transcription-only port ids with no 1:1 IA:** the four `IA_Move` splits and the merged
  `sprint` (`IA_Movement_Run` + `IA_Ability_RunToggle`), `primary_action` (`…_Primary`, `_Tap`, `_Hold`),
  `tool_4` (`IA_ToolSelect_EquipVistaraDiamond` vs `IA_Ability06`), and `input_chord_lb`
  (`IA_ControllerLeftShoulder`). These are *port decisions*, not producer data.

`AUTHORED_ACTIONS` (`:151-170`) declares exactly 52 `IA_*` names, matching the shipping count;
`test_input.gd:70,80` pins it.

## A6. Is the transcription live at runtime today? **Yes.**

`class_name InputActions` is a global class; no file preloads `input_actions.gd`. Callers (`grep`):

- `game/src/core/input_context.gd` (autoload `InputContext`, `game/project.godot:22`):
  `_ready()` `:71` `_table = InputActions.load_table()`; `reload_bindings()` `:92`
  `apply_to_input_map(_table.rows, _overrides)`; chord loop `:288-289` `InputActions.ids()/row_for()`.
- `game/src/core/input_rebinder.gd:45,52,63,65,120,129,174,177,181,231` — rebind UI and re-apply.
- `game/src/player/thief_character.gd:834-837` (sensitivity), `:993,995` (pad turn 90/52 °/s),
  `:1003,1005` (0.12 axial deadzone), `:1445` (device check).
- `game/src/ui/input_glyphs.gd:161,170,186,271,281,289`; `game/src/ui/settings_ui.gd:24,50,223,229,273,353,858-867`.
- `game/tests/test_input.gd` (standalone suite; e.g. `:86-87` asserts
  `load_table().source == "authored"` with the comment "T01 JSON absent", `:88` asserts
  `rows.size() == InputActions.rows().size()` = 56).

So today the `AUTHORED_ROWS` transcription **is the runtime input table**; `bindings_source()` returns
`"authored"`. `docs/FIDELITY_GAPS.md:33-34` describes the shipped effect as "the authored IMC table drives
39 InputMap blocks" — that is this transcription (40 bindable ids; `InputMap` actions include legacy ids).

## A7. Audit / allowlist status

- `tools/consumer_allowlist.json:161-168`:
  `{"glob":"gameplay/input_actions.json","kind":"blocked_on_team","owner":"T06", …,"optional":true}`.
- `tools/manifest_audit.py:183-185` and `:419-421`: producer `tools/parse_input.py` macro
  `python3 tools/parse_input.py` → `("gen:gameplay/input_actions.json",)`; the `input_actions` group is
  `extracted:json/Gameplay/Input` → that file.
- `tools/audit_baseline.json` → `producers.tools/parse_input.py.outputs."gen:gameplay/input_actions.json"`
  has `bytes:270658`, `exists:true`, `files:1`, `sha256:db01b27f…`. So the manifest side of `make audit` passes.
- Current `python3 tools/check_consumers.py` (run now, read-only) prints **exactly**:

```
  note: optional rule gameplay/input_actions.json matched nothing (producer output not regenerated here)
consumer audit: 215 generated files
  runtime-read: 148 (dir_scan 65, literal 43, table_root 40)
  allowlisted:  67 (blocked_on_team 25, build_manifest 2, folded_into_aggregate 24, placeholder 1, producer_intermediate 7, provenance 2, tests_only 3, text_via_locres 3)
  table roots parsed from game_data.gd: 13
CONSUMER AUDIT PASS
```

  The same line is committed at `docs/reports/logs/r8/audit.log:48`.

Why it says "matched nothing" although the file exists: `check_consumers.is_reachable()` (`tools/check_consumers.py:189-212`)
classifies a generated file as **runtime-read** when `<stem>.json` appears anywhere in `game/src/**/*.gd`
(`:204`). `input_actions.json` appears in `game/src/core/input_actions.gd:29` — with the **wrong directory**.
I verified: `is_reachable('gameplay/input_actions.json') == (True, 'literal')`. So the audit gate is
**path-blind**: it sees the basename, marks the file consumed, the allowlist rule matches zero files, and the
`optional:true` flag suppresses the STALE RULE failure. `make audit` is green while the consumer never opens
the file. (Without `optional`, the gate would fail "STALE RULE".)

Fix shape: change `GENERATED_PATH` to `res://data/generated/gameplay/input_actions.json` (and docstring `:14`),
add the row adapter (A4), update `test_input.gd:86-88` (it currently asserts the fallback), then delete the
allowlist rule. Any one of those alone leaves a false green.

---

# B. `curves.json` — the index has no reader; the 16 table files it indexes load but are never sampled

## B1. `game/data/generated/curves.json` structure

80,654 bytes; top-level keys (6): `counts`, `generated_by` (`"tools/parse_curves.py"`), `nested` (list, 108),
`schema` (`"tat2.curves/1"`), `source` (`"extracted/json/**"`), `standalone` (list, 16).

`counts` exactly (`tools/parse_curves.py:350-359`):

```json
{"curve_tables": 23, "emitted": 16, "nested": 108,
 "nested_by_type": {"CurveFloat": 99, "CurveLinearColor": 3, "CurveVector": 6},
 "standalone": 16, "standalone_by_type": {"CurveFloat": 14, "CurveLinearColor": 2}}
```

`curve_tables:23` reconciles with the existing `parse_tables.py` output: 18 `CT_*.json` + 5
`Curve_*_Table.json` in `game/data/generated/tables` (measured: 18 and 5; 160 JSON files total under `tables/`).

## B2. `standalone` record format (16 records; real example, key names exact)

Keys: `asset`, `channels`, `key_count`, `name`, `rows`, `source_dump`, `sparse_channels`, `table`,
`time_range`, `type`. There is **no `emitted` field** on standalone records — all 16 are emitted.

Real record (`Curve_AI_HeightDifferenceToStrengthMultiplier`), trimmed to 2 keys:

```json
{"asset": "/Game/AI/Alertness/Curve_AI_HeightDifferenceToStrengthMultiplier",
 "channels": ["Value"], "key_count": 2,
 "name": "Curve_AI_HeightDifferenceToStrengthMultiplier",
 "rows": {"Value": {"Keys": [
   {"ArriveTangent": 0.0, "ArriveTangentWeight": 0.0, "InterpMode": "RCIM_Constant",
    "LeaveTangent": 0.0, "LeaveTangentWeight": 0.0, "TangentMode": "RCTM_Auto",
    "TangentWeightMode": "RCTWM_WeightedNone", "Time": 2.0, "Value": 1.0},
   {"ArriveTangent": 0.0, "ArriveTangentWeight": 0.0, "InterpMode": "RCIM_Linear",
    "LeaveTangent": 0.0, "LeaveTangentWeight": 0.0, "TangentMode": "RCTM_Auto",
    "TangentWeightMode": "RCTWM_WeightedNone", "Time": 3.0, "Value": 0.0}]}},
 "source_dump": "extracted/json/AI/Alertness/Curve_AI_HeightDifferenceToStrengthMultiplier.json",
 "sparse_channels": [],
 "table": "res://data/generated/tables/AI/Alertness/Curve_AI_HeightDifferenceToStrengthMultiplier.json",
 "time_range": [2.0, 3.0], "type": "CurveFloat"}
```

Each standalone also has a table file with 8 keys `asset, channels, key_count, name, rows, sparse_channels,
time_range, type` (no `table`/`source_dump`). `rows` is keyed by channel: `Value` for `CurveFloat`,
`R/G/B/A` for `CurveLinearColor`, `X/Y/Z` for `CurveVector` (`tools/parse_curves.py:38-70`).

## B3. `nested` record format (108 records; real example)

Keys: `channels`, `dump`, `emitted`, `key_count`, `name`, `owner`, `reason`, `type`. All 108 have
`"emitted": false` and `"reason": "blueprint sub-object default"` (`tools/parse_curves.py:301`).

```json
{"channels": ["Value"],
 "dump": "extracted/json/Art/Effects/Traps/BP_MagicalTrapsPostProcVolume.json",
 "emitted": false, "key_count": 2, "name": "CurveFloat_1",
 "owner": "/Game/Art/Effects/Traps/BP_MagicalTrapsPostProcVolume",
 "reason": "blueprint sub-object default", "type": "CurveFloat"}
```

**Emitted count semantics:** `counts.emitted = 16` is the number of *table files written*
(`parse_curves.py:311-356`, `written` increments only in the standalone loop), not a per-record flag.
Nested: `emitted:true = 0`, `emitted:false = 108`. So "16 emitted, 108 not" is exact.

## B4. `game_data.gd` load pipeline — the 13 roots

`_load_curves()` (`game/src/core/game_data.gd:92-112`) calls `_load_tables_from_dir` **13 times**:

| # | root | line | recursive |
|---|---|---|---|
| 1 | `tables/Gameplay/Tuning` | `:93` | false |
| 2 | `tables/Character/Player` | `:94` | false |
| 3 | `tables/Gameplay/Tools` | `:95` | true |
| 4 | `tables/AI/Data` | `:96` | false |
| 5 | `tables/Gameplay/Abilities/Effects` | list `:102` | true |
| 6 | `tables/Gameplay/Combat/Guard/Melee/RangedAttack` | `:103` | true |
| 7 | `tables/Gameplay/Interactables/ElectricPower` | `:104` | true |
| 8 | `tables/Gameplay/Progression` | `:105` | true |
| 9 | `tables/AI/Alertness` | `:106` | true |
| 10 | `tables/Art/Environment/Weather` | `:107` | true |
| 11 | `tables/Gameplay/Carry` | `:108` | true |
| 12 | `tables/Gameplay/Input/Character` | `:109` | true |
| 13 | `tables/Gameplay/Traversal/Dodge` | `:110` | true |

The brief's **"five roots"** are the five that did not exist on the W7 tree and that `parse_curves.py` filled
(`docs/reports/remediation-20261125/T01-pipeline.md:338-380`): **`Gameplay/Input/Character`,
`Gameplay/Traversal/Dodge`, `AI/Alertness`, `Gameplay/Carry`, `Art/Environment/Weather`**. All 5 are non-empty
now (verified on disk). The other 8 roots already existed.

`_load_tables_from_dir` (`:115-132`) walks `.json`, `_store_table_file` (`:135-157`) requires `rows` to be a
Dictionary and decides curve vs data:
`is_curve = kind=="CurveTable" or fname.begins_with("CT_")`, `is_data = kind=="DataTable" or fname.begins_with("DT_")`
(`:147-148`); ambiguous names fall to `_rows_look_like_curves()` (`:160-165`, any row has `Keys`).
Curves go to `curves[tname] = rows` (`:150` or `:155`).

- `curves` dictionary declaration: `game_data.gd:5` — `table_name -> {row_name -> Array[{time,value}]}`.
- `eval_curve` (`:168-195`): reads `curves[table]`, falls back to `tables[table]` (`:170-171`), requires a
  row Dictionary with `Keys`, clamps before/after the first/last key, and **linearly interpolates every
  segment** (`:193`) — it ignores `InterpMode` even though parse_curves emits it (`parse_curves.py:69`
  explicitly says the current eval always lerps).

## B5. Is `curves.json` loaded anywhere? **No.**

`grep -rn "curves.json" game/src` → 0 hits. `grep` across `game/**/*.gd` and `game/tests` → 0 hits.
`game_data.gd` never names the file; it only scans the 13 `tables/**` roots. The only non-producer references
are the allowlist (`tools/consumer_allowlist.json:149-155`, kind `provenance`, `optional:true`), the audit
baseline, and the producer/tests. `check_consumers.is_reachable('curves.json') == (False, '')` — it is
explicitly allowlisted as provenance, not read. The *table files* it indexes are read through the roots; the
index itself is not.

## B6. Consumers of `eval_curve` and `GameData.curves`

`eval_curve` call sites (all `game/src`, exact lines):

- `game/src/core/game_data.gd:282` (`get_upgrade_curve`; **no caller** — the function is dead)
- `game/src/core/save_system.gd:1102` — `CT_XPToLevel:XPToLevel` (constants `save_system.gd:18-21`)
- `game/src/ai/guard_ai.gd:1211` (`CT_AIStats:GuardBaseHealth`), `:1215` (`…BaseHealthRegenRate`),
  `:2062` (`…GuardKnockoutDuration`)
- `game/src/interact/lockable_door.gd:188` (`CT_LockpickDamage:DamageByLockLevel`)
- `game/src/player/thief_character.gd:528` (`CT_PlayerStats:BaseHealth`), `:530` (BaseStamina),
  `:533` (BaseStaminaRegenRate), `:1479` (`CT_StaminaSystem:StaminaPerSecond.Sprint`),
  `:1687,1749` (`CT_WireCrank:CrankDuration`), `:2232` (`CT_StaminaSystem:StaminaPerSecond.Climb.Base`),
  `:2665` (`CT_Tool_Wire:WireCooldownSecondary`), `:2947,2948` (`CT_Tool_Blackjack:…Light/Heavy`)
- tests: `game/tests/run_tests.gd:91-95`, `e2e/e2e_tier2_boundaries.gd:613`, `e2e/e2e_tier3_pairwise.gd:366`

Direct `GameData.curves` access: **0** (no `.curves` in `game/src` or `game/tests`). `get_data_row`
(`game_data.gd:285-294`) reads `tables` then `curves`, but has **no caller**.

So the 16 standalone curves are loaded into `GameData.curves` and **never sampled** — no call passes any of
their names. Only 8 `CT_*` tables are ever sampled.

## B7. The 16 emitted standalone curves — equivalent hardcodes / intended readers

`grep` of each exact name in `game/src` + `game/tests` (bold = a hardcoded/approximate equivalent exists):

| # | emitted curve | type | game/src evidence today | intended reader |
|---|---|---|---|---|
| 1 | `Curve_AI_HeightDifferenceToStrengthMultiplier` | Float | **`guard_ai.gd:188-194`** comment + `:1401-1405` `height_difference_strength_multiplier()` = step 1.0 → 0.0 at 3.0 m (2 keys, `HEIGHT_STRENGTH_ZERO_M=3.0`); consumed at `:1335` inside `detection_gain_per_second` (`:1330`) | guard detection ramp (Neutral only) |
| 2 | `C_LightIntensityToRangeMultiplier` | Float | **`light_probe.gd:16-24`** constants `LIGHT_INTENSITY_RANGE_MIN/MAX` (0.15→1.0) + `light_intensity_range_multiplier()` `:121-123` (lerp); doc says consumed by `BP_NPC_Base`, port applies it in range gating | guard acquisition range vs light |
| 3 | `C_MovementSpeedToMinimumLightDetectionValue` | Float | **`light_probe.gd:19-27`** constants (600 cm/s, 0.0→0.1) + `minimum_light_detection_for_speed()` `:129-132` (smoothstep); used by `guard_ai.gd:1408-1416` `_player_light_value` | player light floor vs speed |
| 4 | `C_WaitingAIToNavLinkAcceptanceRadius` | Float | **none** (0 grep hits; no acceptance-radius logic in `nav_steering.gd`) | AI nav-link acceptance |
| 5 | `Curve_Exposure_Compensation_Float` | Float | only `_V3` named in `weather_profile.gd:122`; no plain-Float reader | auto-exposure bias (weather) |
| 6 | `Curve_Exposure_Compensation_Float_V3` | Float | **`weather_profile.gd:122-135`** `EV_CURVE_POINTS` hardcoded 8-point approximation + `ev_curve_bias()` `:488-500` | exposure decision per weather preset |
| 7 | `C_Sky_Gradient` | LinearColor (R,G,B) | **`weather_visuals.gd:8-24`** uses authored `horizon_color`/`zenith_color`/`overall_color` from `weather/*.json`; curve not sampled | `tat_sky.gdshader` sky gradient (M_Sky curve) |
| 8 | `Curve_FallingDamage` | Float | **`thief_character.gd:257`** `FALL_DAMAGE_PATH=".../gameplay/fall_damage.json"`, load `:541-545`, `_build_fall_curve()` `:565-582`; `parse_fall_damage.py` already emits the same 3 keys/tangents into that JSON | fall damage (already consumed via an aggregate JSON, not the table) |
| 9 | `Curve_CarryTargetThrowStrengthVsDirection` | Float | **none** (0 hits; no carry/throw gameplay code in `game/src`) | carried-body throw strength |
| 10 | `C_GlyphIndicator_MajorLoot` | Float | **none** (0 hits; `level_loader` only has MajorLoot spawn tags) | HUD major-loot glyph indicator |
| 11 | `Curve_GamepadLookEdgeBoost` | Float | **`input_actions.gd:44`** `EDGE_BOOST_THRESHOLD=0.95` — **declared but never used** (only occurrence); `_tick_gamepad_look()` `thief_character.gd:981-996` has no edge boost | pad look acceleration near full deflection |
| 12 | `Curve_GamepadMoveThumbstickResponse` | Float | **none sampled**; movement uses `Input.get_vector` (`thief_character.gd:1442`) with only the 0.18 InputMap deadzone (`input_actions.gd:185-188,485`) — linear response, no authored 4-key shape | pad move response |
| 13 | `Curve_Dodge` | Float | **none** (0 hits; no dodge implementation) | dodge distance/curve |
| 14 | `C_EyeGlow` | LinearColor | **none** (0 hits; EyeLibrary materials `guard_ai.gd:347-357` carry no glow curve) | eye glow/emissive |
| 15 | `GamepadLookSensitivityCurve` | Float | **`input_actions.gd:100-113`** `PAD_LOOK_MULT=[0.5,0.75,1.0,1.25,1.5]` (authored DefaultGame.ini ladder) + `pad_look_scale()` `:129-130` | pad look sensitivity (replaces curve with 5-step ladder) |
| 16 | `MouseLookSensitivityCurve` | Float | **`input_actions.gd:108-112,125-126`** `MOUSE_LOOK_MULT=[0.5,0.75,1.0,1.5,2.0]` + `mouse_rad_per_px()` | mouse look sensitivity ladder |

Net: 6 of 16 have a real hardcoded approximation in code (#1, #2, #3, #6, #15, #16); #8 is consumed through
a different generated JSON; 9 have no reader and no approximation. `InterpMode` is emitted but ignored by
`eval_curve` (only linear), so even a first reader would be wrong for `RCIM_Constant` curves such as #1.

## B8. The 108 nested curves grouped by owner

Nested records have **67 distinct owners**. All are Blueprint sub-object defaults; no fake table is written.
Domain grouping (by owner path, exact counts):

| domain bucket | records | representative owners |
|---|---|---|
| Tools / bombs / traps | 24 | `BP_SmokeBomb_WorldActor` (3), `BP_SecurityTurret` (3), `BP_PowerSupply_Wall` (3), `BP_JawTrap_WorldActor`, `BP_KnockoutGas_WorldActor`, `BP_StaminaBomb_WorldActor`, `BP_DoorWard_Ward`, `BP_MagicSlime_ExplodingProjectile`, `BP_Detector_PressurePlate`, `BP_MagicAlarm` |
| Doors / gates / containers / switches | 23 | `BP_VaultDoor_Sliding` (2), `BP_VaultDoor_SlidingDouble` (2), `BP_VaultDoor_Sliding_StartsOpen` (2), `BP_WallSwitchTrigger_Base` (2), `BP_SwingingDoor`, `BP_Manor_SecretBookcaseDoor`, `BP_ChestTrunk`, `BP_LargeFancySafe`, `BP_SmallSafe`, `BP_SlidingGateDoubleBase`, `BP_Manor_Displaycase` (2), `BP_EscapePoint` (5), `BP_ConcealedWallSafe_SlidingProp_Base` |
| Characters | 4 | `BP_NPC_Base` (2), `BP_Player_Base` (2) |
| Lights | 2 | `BP_ToggleableLight_Spot` (2) |
| Weather | 1 | `BP_WeatherPreset_Base` |
| VFX | 1 | `BP_MagicalTrapsPostProcVolume` |
| Other blueprints (disguise, vehicles, props, pickpocket, UI, etc.) | 53 | `BP_DisguisePostProcVolume` (7), `BP_LootStashInteractable_Secret_ThinWall` (5), `BP_Automobile_AlarmBase` (3), `GC_RespawnRitual_SafeRoom_ActiveVFX` (3, CurveVector+Float), `BP_LootAura…`, `BP_CableSpline`, `BP_Phonograph`, `BP_Dumbwaiter` (Vector), `BP_MapNode` |

Most-frequent owners: `BP_DisguisePostProcVolume` 7, `BP_EscapePoint` 5, `BP_LootStashInteractable_Secret_ThinWall` 5,
then eight owners with 3 and twenty-three with 2. Types: 99 `CurveFloat`, 6 `CurveVector`, 3 `CurveLinearColor`.
Full owner list is in `game/data/generated/curves.json` `nested[*].owner` (diffable).

## B9. Conclusion (curves)

- `curves.json` is a **provenance index**; nothing reads it, by design, and `check_consumers` says so.
- The 16 standalone table files **are** loaded (`GameData.curves`) but **no code samples them**; `eval_curve`
  is called only with 8 `CT_*` table names. The "31 CurveTables" comment at `game_data.gd:97-100` is stale
  (23 CurveTables exist; the 13 roots load 45 curve/data files per T01).
- A first real consumer is cheap for the pair `C_LightIntensityToRangeMultiplier` /
  `C_MovementSpeedToMinimumLightDetectionValue` (`light_probe.gd:121-132` already implements exactly the
  authored two-key shape) and `Curve_Exposure_Compensation_Float_V3` (`weather_profile.gd:488-500`); the
  others need either gameplay that does not exist (dodge/carry) or a producer decision.
- `eval_curve` must learn `RCIM_Constant` (and ideally `RCIM_Cubic`) before #1 and other constant/cubic
  curves can replace hardcodes faithfully.

---

# C. Material / token resolution — effect sprites

## C1. The "6 of 29" measurement (docs + the list)

Quotes:

- `docs/FIDELITY_GAPS.md:52-53`: "VFX sprite resolution is wrong-token for most systems (6 of 29 textures pass the
  soft-mask gate); the authored 'footstep' texture is a crate decal used as a thief-vision mask."
- `docs/reports/r8-remediation-20261125.md:114-115`: "**VFX sprite resolution is wrong-token for most systems**
  (6 of 29 textures pass the soft-mask gate) — reported, not papered over."
- `docs/reports/remediation-20261125/T12-vfx.md:84-105`: "Sprite mask measurement (why only 5 systems sample art)"
  — "Every sprite texture referenced by a *placed* system was measured headless (`Image.load_from_file`,
  `detect_alpha()`, sampled alpha coverage, border coverage). A texture is used only when it has alpha, border
  coverage ≤ 0.20 … and 0.005 ≤ coverage ≤ 0.85." Table: 6 `mask`, 4 `reject (page)`, "19 further `_D`/`_BC`/`_N`
  maps … reject (albedo, not a mask)" → "**24** of 29 measured textures are opaque albedo/atlas pages."
  **Doc arithmetic bug:** 6 usable + 19 + 4 = 29 → 23 opaque, not 24; `sprite_masks.gd:12-15` says "The other
  **23** resolve to opaque albedo/atlas pages". There is no literal "23 of 29" string in the tree; the
  correct statement is **6 usable / 23 rejected / 29 measured**.
- `T12-vfx.md:448`: "sprite textures measured / usable | 0 / 0 | **29 / 6** (5 active systems bound)";
  `:460` and `:510` repeat "6 of 29". After R8 the probe expects **4** active sprite systems
  (`probe_niagara.gd:58-61`, `NS_LootStash` removed because it is a mesh renderer).

The list lives in **`game/src/core/vfx/sprite_masks.gd:18-48`**, `const MEASURED: Dictionary` — exactly 29 entries.
A second copy of the summary table is in `docs/reports/remediation-20261125/T12-vfx.md:92-106`
(`build/qa/review_20261124/remediation/T12-vfx.md` is the identical pre-merge copy).

Full 29 (`path → [has_alpha, coverage, border]`, verdict from `acceptable()` at `sprite_masks.gd:56-62`:
alpha && border ≤ 0.20 && 0.005 ≤ coverage ≤ 0.85):

| # | texture | alpha | cov | border | verdict |
|---|---|---|---|---|---|
| 1 | `Art/Character/ThiefNisha/Base/Textures/T_ThiefNisha_Eyes_D.png` | no | 1.000 | 1.000 | reject |
| 2 | `Art/Effects/LootAttract/T_LootAttract_Shine.png` | **yes** | 0.019 | 0.000 | **mask** |
| 3 | `Art/Effects/MagicWarp/T_MageHandGradientB.png` | no | 1.000 | 1.000 | reject |
| 4 | `Art/Effects/Moths/T_Moths_N.png` | no | 1.000 | 1.000 | reject |
| 5 | `Art/Effects/Puddles/T_Decal_Puddle_5_Opacity.png` | no | 1.000 | 1.000 | reject |
| 6 | `Art/Effects/Smoke/Smoke32.png` | **yes** | 0.072 | 0.006 | **mask** |
| 7 | `Art/Environment/City/Architecture/BeautifulCorner/Materials/T_Pipes_D.png` | no | 1.000 | 1.000 | reject |
| 8 | `Art/Environment/Nature/Trees/Willow/Materials/T_LeafWillowGlow_D.png` | **yes** | 0.218 | 0.034 | **mask** |
| 9 | `Art/Environment/Props/Debris/DebrisNanite/T_Newspaper_D.png` | no | 1.000 | 1.000 | reject |
| 10 | `Art/Environment/Props/Debris/T_TrashDebris_DA.png` | yes | 0.765 | 0.752 | reject (page) |
| 11 | `Art/Environment/Props/Furniture/Desk/Scrolls/T_ScrollsABC_D.png` | no | 1.000 | 1.000 | reject |
| 12 | `Art/Environment/Props/Paintings/T_PaintingA_D.png` | no | 1.000 | 1.000 | reject |
| 13 | `Art/Environment/Skybox/SkyboxSmokestacks/T_SkyboxSmokestacks_D.png` | no | 1.000 | 1.000 | reject |
| 14 | `Art/Environment/Urban/Roofs/Chimneys/T_ChimneyPipesA_D.png` | no | 1.000 | 1.000 | reject |
| 15 | `Art/Gameplay/EscapeRoutes/T_EscapeRouteTunnelA_D.png` | no | 1.000 | 1.000 | reject |
| 16 | `Art/Gameplay/Gear/AntiStealthDevice/T_AntiStealthDevice_D.png` | no | 1.000 | 1.000 | reject |
| 17 | `Art/Gameplay/Gear/Bomb/Liquid/T_Bomb_Liquid_DA.png` | yes | 0.837 | 0.861 | reject (page) |
| 18 | `Art/Gameplay/Gear/Dart/T_Dart_Electric_D.png` | no | 1.000 | 1.000 | reject |
| 19 | `Art/Gameplay/Gear/Faerie/Faerie_Body01.png` | no | 1.000 | 1.000 | reject |
| 20 | `Art/Gameplay/Gear/LootBag/T_LootBag_D.png` | no | 1.000 | 1.000 | reject |
| 21 | `Art/Gameplay/Gear/Slithersap/T_SlimeBomb_DA.png` | yes | 1.000 | 1.000 | reject (page) |
| 22 | `Art/Gameplay/Gear/SmokeBomb/T_SmokeBomb_D.png` | no | 1.000 | 1.000 | reject |
| 23 | `Art/Gameplay/Gear/Zipwire/T_Zipwire_D.png` | no | 1.000 | 1.000 | reject |
| 24 | `Art/Gameplay/Loot/Stash/LootStash_Line.png` | no | 1.000 | 1.000 | reject |
| 25 | `Art/VFX/Textures/Noise/_Noise_71.png` | no | 1.000 | 1.000 | reject |
| 26 | `MaterialLibrary/Environment/Nature/Plants/T_BushesLeaves_DA.png` | **yes** | 0.338 | 0.016 | **mask** (mesh system, not bound) |
| 27 | `MaterialLibrary/VFX/T_LightGlowsA_D.png` | **yes** | 0.413 | 0.105 | **mask** |
| 28 | `ThirdParty/DEKO_VFX/VOL1_Water/Textures/TX_Splash_Big_01a_ALB.png` | **yes** | 0.148 | 0.000 | **mask** |
| 29 | `ThirdParty/StylizedPirateTreasures/Textures/Treasures/T_Atlas_B_01_BC.png` | no | 1.000 | 1.000 | reject |

Counted programmatically from the file: 6 accepted, 23 rejected. Note that several of the 29 are obviously
**not effect sprites** (`T_ThiefNisha_Eyes_D`, `T_Pipes_D`, `T_Newspaper_D`, `T_PaintingA_D`,
`T_SkyboxSmokestacks_D`, `T_ChimneyPipesA_D`, `T_Bolt…`-class environment pages) — that is the wrong-token bug
itself: `systems.json` resolved each sprite renderer to its material's `texs.albedo`, and for many materials
that guess is a world texture.

## C2. Measurement command and output format

The table is not produced by a committed standalone tool; it is the measured literal in `sprite_masks.gd` and
is **re-measured by the Niagara probe**:

```
tools/godot --headless --path game --script res://tests/probe_niagara.gd
```

(T12 red-proof list `docs/reports/remediation-20261125/T12-vfx.md:32-37`; gate row `:418` → `NIAGARA_PROBE PASS`.)

Probe measurement (`game/tests/probe_niagara.gd:350-389`): for every `SpriteMasks.MEASURED` path,
`Image.load_from_file(ProjectSettings.globalize_path(path))`, `detect_alpha()`, grid sample step
`max(1, int(sqrt(w*h/4096)))`, coverage = samples with `a > 0.1`, border = same test on the outer
`2 * step` rows/cols, tolerated drift 0.02. Output format:

- always: `NIAGARA_PROBE files=<n> authored=<n> active=<n> skipped=<n> systems=<n> nodes=<n> sprites=<n> params=<n> tint(param/material/fallback)=<a>/<b>/<c>` (`probe_niagara.gd:127-131`, then `NIAGARA_PROBE PASS|FAIL`) — currently expects `sprites=4` (`:183-184`, `:58-61`).
- on drift: `NIAGARA_SPRITE_MASK drift <file> alpha=<bool> cov=%.3f border=%.3f row=[...]` (`:387-389`).
- on missing: `NIAGARA_SPRITE_MASK missing <path>` (`:362-364`).

So "the 6/29 result" = 6 rows of `MEASURED` satisfy `acceptable()`; the probe fails if any of the 29 drifts
from its recorded `[alpha, coverage, border]`.

## C3. `level_loader.gd` — material resolution functions (exact lines)

| function | line | what it does |
|---|---|---|
| `_load_material_dbs()` | `:633-654` | loads `res://data/generated/materials.json` into `_materials_db` (+lowercase map) and `mesh_materials.json` into `_mesh_mats_db` |
| `_load_tex()` | `:699-745` | caches; `ResourceLoader.exists` path with tiny-texture mip guard; raw-PNG fallback; `_cap_image` + mip generation; no token logic |
| `_is_tiny_texture` / `_guard_tiny_resource_texture` | `:659-697` | icon-size sprite (<32 px) mip guard |
| `_apply_ue_pbr_params` | `:783-980` | roughness/metallic/specular/emissive scalars/vectors; roughness remap bake metadata |
| `_apply_ue_render_flags` | `:985-1032` | `two_sided` → `CULL_DISABLED` (`:987-988`); `blend_mode` contains `additive` → `TRANSPARENCY_ALPHA` + `BLEND_MODE_ADD` (`:997-999`); `translucent`/`alphacomposite` → `TRANSPARENCY_ALPHA` (`:1000-1001`); `masked` → `TRANSPARENCY_ALPHA_SCISSOR` + `alpha_scissor_threshold` from `opacity_mask_clip` (`:1002-1004`); empty blend + `opacity_mask_clip` + foliage → scissor at 0.3333 (`:1005-1013`); foliage backlight (`:1010-1019`); `MSM_Unlit` with albedo → `SHADING_MODE_UNSHADED` (`:1020-1025`) |
| `_is_authored_foliage` | `:1034-1046` | token haystack (path+parent+albedo+normal) against `FOLIAGE_TOKENS` |
| `_apply_ue_emissive` | `:1144-…` | binds `texs.emissive`; unlit/light/glow flat-emissive gate; `Emissive On?` switch |
| `_masked_opacity_albedo` | `:1310-1360` (helpers `_mask_uses_alpha` `:1361-1372`, `_copy_mask_to_alpha` `:1374-1383`) | copies the authored opacity texture's alpha (or red) into the albedo's alpha for masked materials |
| **`get_material_for_ue`** | **`:1385-1702`** | the StandardMaterial3D builder. Early exact-MI exceptions: `blackunlit` (`:1392`), `MI_LightBeam_SM` additive shader (`:1405-1413`), glass (`:1414-1422`), storefront decal (`:1427-1444`). Then: **`texs.albedo` → `mat.albedo_texture` (`:1461`)**; masked + `texs.opacity` → `_masked_opacity_albedo` (`:1467-1474`); `texs.normal` → `normal_texture` (`:1475-1477`); `texs.orm` → AO/rough/metal (`:1478-1512`); tint → `albedo_color` incl. HDR neon path (`:1513-1605`); `texs.emissive` → `emission_texture` (`:1594-1599`) |
| **`_bind_glb_materials`** | **`:1943-1956`** | per GLB surface: `mat_slots[s]` is the authored slot; empty slot → `_slot_name_fallback`; then `surface_set_material(s, get_material_for_ue(mp))` (`:1953`) |
| **`_slot_name_fallback`** | **`:1959-1980`** | only for an empty authored slot; lowercased surface name vs slot short name, substring either direction; requires exactly 1 hit; counts `slot_name_fallback_count` |
| `_has_token` | `:2467-2471` | substring token test |
| `_is_decal_material_usable` | `:5587-5640` | decal-specific strict check: bound albedo stem must share a len≥4 non-generic token with the material name; otherwise flat tint or reject |
| `_spawn_level_niagara` | `:5883-6081` | VFX billboard path (see C6) |

There is no generic `_D`/`_N`/`_ORM` companion resolver in `level_loader.gd`; companion mapping (`T_X_N → T_X_D`)
is done by the producer (`parse_materials.py:_companion_diffuse`, `:1079-1105`) and frozen into `texs`.
`level_loader` only consumes the already-resolved `texs` slots and applies `M_`/`MI_` name heuristics for
art-direction overrides (brick/stone/dirt/wood/metal fallback chain `:1607-1650`, wallpaper `:1681-1696`).

## C4. `materials.json` / `mesh_materials.json` record shape

`game/data/generated/materials.json` — 2,784,668 bytes, **1,629 records**, keyed by UE package path.
Final record keys (`tools/parse_materials.py:1796-1812`): `path`, `texs`, `tint`, `parent`, `params`, `vectors`,
`switches`, `albedo_source`, optional `render`, optional `phys_material`. `texs` keys are the **resolved slots**
`albedo|normal|orm|emissive|opacity` (values are `res://assets/ue/{Raw,Content}/…png`). Raw UE texture parameter
names are **not** preserved — only `albedo_source` records how the albedo was chosen (`authored`,
`stream-ranked`, `stream-single`, `fallback-1/2/3`, `instance-diffuse`, `companion-diffuse`, `none`).
`render` is the flattened `BasePropertyOverrides`/top-level result: `blend_mode`, `shading_model`, `two_sided`,
`opacity_mask_clip` (`tools/parse_materials.py:660-690`).

`mesh_materials.json` — 443,572 bytes, **2,065 records**, `{mesh UE path: [material UE path per GLB primitive]}`
(`/Game/VFX/Meshes/SM_thick → ["/Game/Art/Environment/Props/Tarps/ML/MI_Tarps"]`, `mesh_materials.json:11-13`).

### Effect material record 1 — a SubUV atlas "flame" (the candle sprite)

`materials.json:87505-87600` (`MI_FlameCandleOrangeB`), trimmed to fields that matter:

```json
{"path": "/Game/Art/Environment/Lights/Candles/MI_FlameCandleOrangeB",
 "texs": {"albedo": "res://assets/ue/Raw/ThirdParty/StylizedPirateTreasures/Textures/Treasures/T_Atlas_B_01_BC.png"},
 "parent": "/Game/Art/VFX/FluidNinja/Core/AtlasPlayer/M_AtlasPlayAdvanced_v2",
 "params": {"EmissiveStrength": 0.5, "Horizontal Subimages": 8.0, "Vertical Subimages": 8.0,
            "Color3Exponent": 0.1, "Contrast": 1.4187, "AlphaStrength": 1.0, …},
 "switches": {"Enable Edge Mask": true, "Enable Particle Alpha": false, …},
 "albedo_source": "fallback-ranked",
 "render": {"blend_mode": "EBlendMode::BLEND_TranslucentGreyTransmittance",
            "two_sided": true,
            "shading_model": "EMaterialShadingModel::MSM_Unlit",
            "opacity_mask_clip": 0.3333}}
```

This is exactly the wrong token: the sprite is an **8×8 SubUV atlas page** (`Horizontal/Vertical Subimages 8`),
`albedo_source` is a **guess** (`fallback-ranked`), and the runtime binds that atlas as a billboard.

### Effect material record 2 — rain (has the correct opacity mask, but the wrong slot is preferred)

`materials.json:44763-44790` (`MI_RainDrops_Additive_BC`):

```json
{"path": "/Game/Art/VFX/Environment/RainStorm/MI_RainDrops_Additive_BC",
 "texs": {"opacity": "res://assets/ue/Raw/Art/VFX/Environment/RainStorm/Textures/T_DropletsMasks_Packed.png",
          "normal":  "res://assets/ue/Raw/Art/VFX/Environment/RainStorm/Textures/T_Droplets_Normal.png",
          "albedo":  "res://assets/ue/Raw/Art/Gameplay/Gear/Bomb/Liquid/T_Bomb_Liquid_DA.png"},
 "parent": "/Game/Art/VFX/Environment/RainStorm/M_LiquidMaster_Additive",
 "albedo_source": "fallback-ranked",
 "render": {"blend_mode": "EBlendMode::BLEND_Additive",
            "shading_model": "EMaterialShadingModel::MSM_Unlit",
            "opacity_mask_clip": 0.3333}}
```

The sprite wants `opacity` (`_Packed` mask); `parse_vfx` prefers `albedo` and the renderer gets
`T_Bomb_Liquid_DA` (a 0.837-coverage opaque page).

### Effect material record 3 — electric spark (pure wrong token)

`materials.json:61299-61315` (`M_ElectricShocks_01`):

```json
{"path": "/Game/Art/Gameplay/ElectricFence/M_ElectricShocks_01",
 "texs": {"albedo": "res://assets/ue/Raw/Art/Gameplay/Gear/Dart/T_Dart_Electric_D.png"},
 "tint": null, "parent": "", "params": {}, "vectors": {}, "switches": {},
 "albedo_source": "fallback-ranked",
 "render": {"blend_mode": "EBlendMode::BLEND_Additive", "two_sided": true,
            "shading_model": "EMaterialShadingModel::MSM_Unlit", "opacity_mask_clip": 0.333}}
```

No opacity/normal at all — the only texture is a guessed dart albedo, used by the turret/shock/truncheon systems.

### Effect material record 4 — a true VFX master with a floor ORM

`materials.json:1799-1820` (`M_ParticleAdd_Niagara`): `texs` = `{orm: T_IntRoomFloorA_ORM.png,
normal: Engine/DefaultNormal.png}`, tint/Color `[0.4377,1.0,0.413]`, `render.blend_mode =
EBlendMode::BLEND_Additive`, `two_sided: true`, no albedo/opacity. (The ORM is also a non-VFX token — another
wrong-token bind, though harmless for an untextured additive card.)

## C5. `tools/parse_materials.py` — how texture bindings are emitted

1. `texs = {}` (`:1266`). Iterate authored `TextureParameterValues` (`:1267-1351`). The **parameter name**
   decides the slot (`normal/norm` → `normal`, `orm/roughness/arm` → `orm`, `emissive` → `emissive`,
   `opacity` → `opacity`, `albedo/diffuse/basecolor/base color/color/bc/base texture` or a `_d/_da/_bc/_bco/_c/_alb`
   stem → `albedo`; `is_mask` guards `blend/mask/grunge/noise/stroke/pattern/detail/cavity/height` and
   `_ma/_mask/_m/_r/_g/_b/_a/_ao` from being albedo) (`:1295-1350`).
2. Master materials also read group-3 cached base defaults (`:1352-1380`), instances deliberately do not.
3. Fallback: `TextureStreamingData` + `CachedExpressionData.ReferencedTextures` (`:1388-1415`).
   For instance children, a cached `Diffuse` slot is trusted only when its `Normal` matches the bound normal
   (`:1478-1517`); then a `_companion_diffuse` (`T_X_N → T_X_D`) recovery (`:1519-1526`).
4. If still no albedo: `_best_albedo_candidate(stream_paths, …)` → `_stem_fallback_albedo` → ranked
   reference (`:1528-1568`). `albedo_source` records the tier (`authored` > `stream-*` > `fallback-1/2/3` >
   `reference-ranked` > `none`) (`:1570-1578`).
5. `opacity` is only bound from an explicit opacity parameter/stem or the `_best_texture_candidate(("_o","_opacity"))`
   path (`:1441-1452`); there is **no "sprite renderer needs alpha" awareness** in the producer.
6. `BasePropertyOverrides`: `_bpo_overrides()` (`:610-633`) honours `bOverride_BlendMode/ShadingModel/TwoSided`
   unless explicitly false; `_extract_real_params()` (`:635-698`) emits `render.blend_mode`,
   `render.two_sided`, `render.shading_model`, `render.opacity_mask_clip` (`:660-690`). That is why the runtime
   sees `render`, not the raw BPO dict.

**What a "wrong token" looks like:** the producer binds a `_D`/`_BC`/`_DA` albedo page (often a
`fallback-ranked` guess) where a VFX sprite needs an alpha/opacity mask (or a SubUV atlas page with a correct
sub-image grid). There is no metadata saying "this material is a sprite material", so the runtime cannot tell
a sprite albedo from a wall albedo. Concrete: `M_ElectricShocks_01` → `T_Dart_Electric_D`; candle
`MI_FlameCandleOrangeB` → `T_Atlas_B_01_BC`; rain `MI_RainDrops_Additive_BC` → `T_Bomb_Liquid_DA` while its
correct `opacity` (`T_DropletsMasks_Packed`) sits unused.

## C6. How the runtime actually chooses the sprite texture (the exact functions)

Chain, in order:

1. **Producer `tools/parse_vfx.py:96-117` — `_resolve_sprite_texture(material_path, materials)`**:
   reads `materials[mat]["texs"]` and returns the first non-empty slot in
   `TEX_PREFERENCE = ("albedo", "emissive", "normal", "orm")` (`:58-59`), then any sorted slot (`:112-115`).
   Called from `_parse_renderer()` for `sprite|ribbon|decal` (`:120-130`) and from mesh override materials
   (`:146-157`). **`opacity` is not in `TEX_PREFERENCE` at all** — it can only win via the sorted fallback when
   albedo/emissive/normal/orm are all empty. This is the single line that decides "sprite texture = albedo"
   for the whole VFX lane.
2. **Consumer gate `game/src/core/vfx/niagara_library.gd:52-113` — `NiagaraLibrary.ensure_loaded()`**:
   iterates `systems[*].renderers`, for `type=="sprite"` takes `r.sprite_texture` and sets the system's
   `sprite_path` only if `SpriteMasks.acceptable(tex)` (`:86-96`, gate at `:94`). First acceptable wins.
   `BASE_SIZE_BY_CLASS` (`:26-30`) and fallback tints (`:36-43`, `:153-167`) are separate stand-ins.
3. **Mesh/GLB path `level_loader.gd:1943-1956` / `:1385-1702`**: `get_material_for_ue` binds
   `texs.albedo`/`normal`/`orm`/`emissive` (C3) — this is the regular material path, not the Niagara sprite path.
4. **Binding `game/src/core/level_loader.gd:5883-6081` — `_spawn_level_niagara()`**:
   `var sprite_path = str(info.get("sprite_path", ""))` (`:6015`), then at `:6022-6027`:
   `if sprite_path != "": var tex = _load_tex(sprite_path); if tex != null: mat.set_shader_parameter("sprite_tex", tex); mat.set_shader_parameter("use_sprite", true); sprites += 1`.
   The shader `game/src/core/level_niagara.gdshader:17-18,53-54` samples `sprite_tex` when `use_sprite`, else
   the procedural radial falloff. There is **no second token check in the loader**; the only gate is
   `SpriteMasks.acceptable()` inside the library.
5. Decal path (`M_Decal_*`): `_is_decal_material_usable()` (`:5587-5640`) applies a stricter local token rule
   (albedo stem ∩ material name) — a different, ad-hoc token resolver; it is not used for Niagara sprites.

So the exact answer to "which function picks the sprite texture" is:
**`tools/parse_vfx.py::_resolve_sprite_texture()` (line 96) picks the material slot (albedo first), and
`game/src/core/vfx/niagara_library.gd::ensure_loaded()` (line 94) is the runtime gate that accepts/rejects it
via `SpriteMasks.acceptable()`; `level_loader.gd:6022-6027` only binds the already-chosen path.**

## C7. Consequences / fix candidates (no code written)

- Changing `TEX_PREFERENCE` to prefer `opacity` (then a SubUV-aware albedo) would fix the rain case and many
  particle masters at once; adding the renderer `type` to `_resolve_sprite_texture` would let sprite renderers
  use a different preference than ribbons/decals.
- The candle case needs SubUV awareness: the `params` already carry `Horizontal/Vertical Subimages 8.0`, but
  neither `parse_vfx` nor the shader uses them; the shader has one UV rect (no atlas slicing).
- The measurement gate (`SpriteMasks.acceptable`) is the safety net, not a fix: it drops 23 of 29 to the
  procedural falloff, which is why the visual regression is "missing sprites" rather than "box artifacts".
- `materials.json` does not preserve the authored texture-parameter name for a slot, so a later consumer cannot
  recover which parameter produced `texs.albedo`; only `albedo_source` says how trustworthy it is. Adding
  `tex_source` (parameter name per slot) in `parse_materials.py` would make the token audit mechanical.

---

## A3 quick answers (for the integrator)

1. **Input fix:** change `input_actions.gd:29` (and docstring `:14`) from
   `res://data/generated/input/input_actions.json` to `res://data/generated/gameplay/input_actions.json`,
   **and** add a contexts→rows adapter because the producer's `actions` is a Dictionary of 65 assets and its rows
   use `action/key`, not `ia/kb/pad`; otherwise the path fix still falls back to `AUTHORED_ROWS`.
2. **Counts:** generated = 237 rows / 91 shipping / 54 row-actions / 65 action assets; transcription = 56 rows
   (40 bindable + 16 coverage-only) / 52 `IA_*` + legacy `Pause`; generated-only rows = 2 dev actions
   (`IA_AbilityLoadout_01`, `IA_Ability_SpecialAttack`), transcription-only = `Pause`.
3. **Five roots:** `Gameplay/Input/Character`, `Gameplay/Traversal/Dodge`, `AI/Alertness`, `Gameplay/Carry`,
   `Art/Environment/Weather` — 5 of the 13 `_load_tables_from_dir` roots (`game_data.gd:93-112`). `curves.json`
   sits outside all 13; it is an index only, never loaded. The 16 standalone table files it indexes do load
   (`GameData.curves`), but `eval_curve` is never called with their names — only 8 `CT_*` tables are sampled.
4. **Emitted curves (16):** `Curve_AI_HeightDifferenceToStrengthMultiplier`,
   `C_LightIntensityToRangeMultiplier`, `C_MovementSpeedToMinimumLightDetectionValue`,
   `C_WaitingAIToNavLinkAcceptanceRadius`, `Curve_Exposure_Compensation_Float`,
   `Curve_Exposure_Compensation_Float_V3`, `C_Sky_Gradient`, `Curve_FallingDamage`,
   `Curve_CarryTargetThrowStrengthVsDirection`, `C_GlyphIndicator_MajorLoot`, `Curve_GamepadLookEdgeBoost`,
   `Curve_GamepadMoveThumbstickResponse`, `Curve_Dodge`, `C_EyeGlow`, `GamepadLookSensitivityCurve`,
   `MouseLookSensitivityCurve`. 108 nested (99 Float / 6 Vector / 3 LinearColor) all `emitted:false`.
5. **Soft-mask measurement:** `tools/godot --headless --path game --script res://tests/probe_niagara.gd`
   re-measures `sprite_masks.gd:18-48` (29 textures; `Image.load_from_file` + `detect_alpha()` + 4096-sample
   alpha/border coverage); result **6 of 29 acceptable** (the docs' "24 of 29 opaque" is off by one — 23 are
   rejected; `sprite_masks.gd:12-15` says 23). Probe prints `NIAGARA_PROBE … sprites=<n> …` and
   `NIAGARA_SPRITE_MASK drift …` on failure.
6. **Sprite texture picker:** `tools/parse_vfx.py::_resolve_sprite_texture()` line 96 with
   `TEX_PREFERENCE=("albedo","emissive","normal","orm")` line 59; runtime gate
   `niagara_library.gd::ensure_loaded()` line 94 (`SpriteMasks.acceptable`); bind
   `level_loader.gd:6022-6027`. The wrong token is chosen in the producer, not the renderer.
