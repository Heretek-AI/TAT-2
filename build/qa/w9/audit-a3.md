# W9-P1 / A3 — independent audit (A3a input+curves, A3b sprite tokens)

- **Auditor:** A3 independent auditor (read-only; no edits, no git writes, no producers).
- **Worktree:** `/home/john/Projects/TAT-2-rem-w9-p1` (`rem/w9-p1`).
- **HEAD at audit:** `5a516f9` (A3b `9c33541` → A3a `5b112b1` → A2 `bb37003` → A4 `b57bbf7` → A1 `ff0f21d` → E2E fix `5a516f9`).
- **Audited commits:** `5b112b1` (A3a), `9c33541` (A3b). E2E commit `5a516f9` inspected because it belongs to the A3a behaviour change.
- **Data tree:** `game/data/generated` is a **symlink to `/home/john/Projects/TAT-2/game/data/generated`** (the shared 2026-11-25 tree at 04:47–05:09). Every number below is for that tree.
- **Tree state:** `git status` was **not clean** during the audit, and it **changed under the audit** (another lane is integrating in this same worktree: `level_loader.gd`, `mission_prep_ui.gd`, `test_t05_ui_contract.gd` were modified during the Godot runs; `tools/consumer_allowlist.json` later lost the T10 `project_settings.json` and T09 `mesh_collision.json` rules). The A3 files themselves (`input_actions.gd`, `light_probe.gd`, `sprite_tokens.gd`, `niagara_library.gd`, `test_input.gd`, `probe_niagara.gd`, `game_data.gd`) are **still byte-identical to HEAD** (`git diff HEAD -- …` empty), and item 7's `check_consumers` was re-run against the current working-tree allowlist with the same result.

Commands used (serialised behind the shared Godot lock, ≤300 s):

```bash
flock /tmp/opencode/tat2-godot.lock -c 'cd … && timeout 300 tools/godot --headless --path game --script res://tests/test_input.gd'
flock /tmp/opencode/tat2-godot.lock -c 'cd … && timeout 300 tools/godot --headless --path game --script res://tests/probe_niagara.gd'
python3 tools/check_consumers.py            # + --list-unconsumed
python3 (inline) JSON / GDScript / PNG decoders; identify/convert for alpha
```

---

## Item 1 — the generated input table really loads

**AUDIT: PASS** (two caveats, below).

`res://tests/test_input.gd` (exit 0):

```
INPUT_TABLE source=generated rows=91 shipping=91 actions=52
INPUT_TABLE_SKIPPED contexts=IMC_Character_ClimbTest, IMC_Character_Testing mappings=146 dev_only_actions=IA_AbilityLoadout_01, IA_Ability_SpecialAttack
INPUT_SUMMARY: fails=0 checks=174
```

Independent parse of `game/data/generated/gameplay/input_actions.json` (`tat2.input_actions/1`):

| quantity | producer `counts` | recomputed from `contexts[*].mappings` |
|---|---|---|
| contexts | 5 | 5 (`IMC_Character`, `IMC_Character_ClimbTest`, `IMC_Character_Testing`, `IMC_MapTool`, `IMC_Radial`) |
| shipping contexts | 3 | 3 (`IMC_Character`, `IMC_MapTool`, `IMC_Radial`; `shipping:true`) |
| shipping mappings | 91 | **91** |
| shipping actions | 52 | **52** |
| all mappings | 237 | **237** (237 − 91 = 146 = `skipped_mappings`) |
| all actions | 54 | 54 (52 + the 2 dev-only IAs) |

- `AUTHORED_ROWS` is gone: `grep -c AUTHORED_ROWS game/src/core/input_actions.gd` → **0**. The old file at `c2a1cd8` had 56 entries (`const AUTHORED_ROWS` at :184, 56 `{` rows) — the commit message's red `rows=56` is real.
- The old path does not exist: `game/data/generated/input/` → *No such file or directory*; `game/data/generated/gameplay/input_actions.json` exists (270,658 B).
- Rows cover all 52 authored actions and the 40 port ids (test assertions `seen.size()==52`, `ids.size()==40`, both PASS). Row arithmetic checks: 91 mappings − IA_Move's 5 mappings + 4 split rows + 1 legacy `Pause` row = **91**.

**Spot-check (17 port ids traced; 8 quoted).** Re-derived from the JSON with the producer's own `key`/`key_is_gamepad`/`DeadZone.lower`/`trigger`/`chord_action` fields (aliases `Gamepad_*Stick_*`→signed axes, `Left2D`/`Right2D`→4 signed axes, `MouseWheelAxis`+`RequireSign`→`+`):

| port id | authored IA(s) | kb | pad | deadzone | trigger | chord |
|---|---|---|---|---|---|---|
| `interact` | IA_Interact | F | Gamepad_FaceButton_Left | – | – | – |
| `jump` | IA_Movement_Jump | SpaceBar | Gamepad_FaceButton_Bottom | – | – | – |
| `sprint` | IA_Movement_Run + IA_Ability_RunToggle | LeftShift | Gamepad_LeftThumbstick | – | – | – |
| `lean_left` | IA_Ability_Lean_Left | Q | Gamepad_LeftX- | – | – | IA_ControllerLeftShoulder |
| `look_gamepad` | IA_LookGamepad | – | RightX-/RightX+/RightY-/RightY+ | **0.12** (Axial, upper 0.98) | – | – |
| `tool_4` | IA_ToolSelect_EquipVistaraDiamond | Four | Gamepad_DPad_Down | – | – | – |
| `map_toggle` | IA_ToolSelect_EquipMap | Tab, M | Gamepad_Special_Left | – | – | – |
| `primary_action` | Primary + _Tap + _Hold | LeftMouseButton | Gamepad_RightTrigger | – | tap+hold:0.2 (authored Tap / Hold 0.2) | – |

`look_gamepad`'s edge boost is authored too: the modifier carries `edge_threshold: 0.95`, `boost_over_time: Curve_GamepadLookEdgeBoost` (not the fallback constants). The move deadzone **0.18** is the authored `DeadZone.lower` on `Gamepad_Left2D`.

**Caveats (not failures):**
1. Six rows are *not* loaded from the JSON: the four `move_*` split rows and the `pause` legacy row are hardcoded in `PORT_DECISIONS` (and the merge ids/triggers). Their values match the authored file today, but `_split_rows()` only **warns** when the IMC stops binding W/A/S/D/Left2D — no test asserts `load_report().warnings` empty. `input_actions.gd:15` ("Every key, deadzone, trigger and chord in a row comes from the generated file") is therefore inexact for those 6 rows; the file's own `PORT_DECISIONS` header says so, but the one-line claim should read "…from the generated file or the 6 documented port contracts".
2. `pause` is DefaultInput.ini legacy (Escape/Pause/Start), not an Enhanced Input mapping; documented in the row note and the test.

---

## Item 2 — no test weakened; suite 35b's new sensitivity number is justified

**AUDIT: PASS.**

`git diff c2a1cd8..HEAD -- game/tests/test_input.gd`: 99 insertions, **7 old expectation lines replaced** (3 table/source + 4 sensitivity), **no assertion deleted**. The replacements are strictly stronger:

| old | new |
|---|---|
| `ids.size() >= 30` | `ids.size() == 40` |
| `source == "authored"` (the bug: the old path did not exist) | `source == "generated"` |
| `rows().size() == rows().size()` (tautology) | `== 91` + `shipping == 91` + `actions == 52` |
| 4 sensitivity literals | 5 curve-derived literals + the fallback/edge-boost block |

The new block adds: dev contexts skipped and **named**, 146 skipped mappings counted, exactly the 2 dev-only IAs dropped, 11 port ids' authored kb keys, `pause` pad Start, `port_id_for_ia(IA_ControllerLeftShoulder)`, 16 standalone curve names, `curves_index_missing == 0`, RCIM_Constant before/at/after, all 16 curves × channels resolve, the light-curve endpoints/midpoint/clamp, and the three edge-boost samples. The old `56`/`authored` expectations did encode the bug.

**Suite 35b** (`run_tests.gd:3234,3245`, landed in `bb37003`): `0.00375 → 0.00390625`.
`MouseLookSensitivityCurve` keys: `(0.0 → 0.2)`, `(1.0 → 1.125)`, `(2.0 → 2.0)`, all `RCIM_Linear`. Step 3 ("Fast") of 5 evenly spaced over `time_range [0,2]` → `t = 1.5` → `1.125 + 0.5 × (2.0 − 1.125) = **1.5625**`; `0.0025 × 1.5625 = **0.00390625**`. The new literal is exactly the curve value; the old `0.00375` was `0.0025 × 1.5` (the removed ini ladder). Justified.

E2E `T1-16-D` was updated the same way in `5a516f9` (`fast_rad_per_px = 0.0025 * 1.5625`, tolerance and all other sub-assertions unchanged), so a wrong curve still fails.

---

## Item 3 — sensitivity behaviour change vs the authored curves

**AUDIT: PASS** (with user-visible-change notes).

Both curves are identical `(0,0.2) (1,1.125) (2,2.0)` `RCIM_Linear`, `time_range [0.0, 2.0]`. Sampling the 5 ladder steps at `t = 0, 0.5, 1.0, 1.5, 2.0` gives **0.2, 0.6625, 1.125, 1.5625, 2.0**.

| step | mouse old → new | pad look old → new |
|---|---|---|
| VeryLow | 0.5 → **0.2** (−60 %) | 0.5 → **0.2** (−60 %) |
| Low | 0.75 → **0.6625** (−11.7 %) | 0.75 → **0.6625** (−11.7 %) |
| Normal | 1.0 → **1.125** (+12.5 %) | 1.0 → **1.125** (+12.5 %) |
| Fast | 1.5 → **1.5625** (+4.2 %) | 1.25 → **1.5625** (+25 %) |
| VeryFast | 2.0 → **2.0** | 1.5 → **2.0** (+33 %) |

The commit's two headline claims (Normal mouse 1.0→1.125; pad Fast/VeryFast 1.25/1.5→1.5625/2.0) are correct, but the change is broader than the message lists: **VeryLow drops to 0.2× (−60 %)** and Low −11.7 % on both devices. That is the authored curve's low end; it is still a user-visible change worth stating.

**Is even sampling "documented"?** It is documented **as the port's bridge** in the production file (`input_actions.gd:114-118`: "The port keeps the authored 5-step input and samples each curve at evenly spaced positions across the curve's own authored time range"). It is *not* authored verbatim (the OSE ladder is a 5-value enum; the TAT curve is continuous). Supporting authored evidence that the curve's own time range is the setting range: `extracted/json/UI/Settings/BPUI_Setting_Numeric_Curve.json::SetSliderCurve` calls `CurveFloat.GetTimeRange()` (`MinTime`/`MaxTime`) into a `FloatInterval` and `UpdateLabel` reads `GetFloatValue()`; `BPUI_Settings_General.json::SetupSettings` pulls `GetMouseLookSensitivityCurve` / `GetGamepadLookSensitivityCurve`. So sampling across `[0,2]` matches the shipped UI mechanism; the 5-point discretisation is the port's (documented) choice.

**Ini ladder is still the fallback:** yes. `MOUSE_LOOK_MULT` / `PAD_LOOK_MULT` (`input_actions.gd:129-131`) are returned by `_sensitivity_multiplier` when the autoload/method is missing, the range is degenerate, or the sample is NaN (`:160-170`); `pad_move_scale` always uses `PAD_MOVE_MULT` (no shipped move-sensitivity curve; `Curve_GamepadMoveThumbstickResponse` is a response curve, distinct). Not executed in this audit (would require removing `curves.json`), verified by code inspection.

**User-visible regression risk:** no automated behaviour test is affected.
- `rg -in "gamepad|joypad|joy_axis" game/tests/e2e/*.gd` → **0 hits**: there are no E2E gamepad tests to break.
- No test drives pad-look yaw; only the multipliers are pinned (`test_input.gd:377-378`). The pad Look change (+12.5 % default, +25/+33 % top steps, −60 % bottom) is therefore behaviourally untested.
- The E2E mouse literal is fixed; a default profile's `mouse_sensitivity = 0.0025` still migrates to **Normal** (`0.0025` is nearest to `0.0028125`), so normal defaults stay on the same step.
- Minor migration quirk: a *pre-step-ladder* save (free slider) at VeryLow `0.00125` now migrates to **Low**, because the new low-end ladder is compressed toward 0.2×. Only affects legacy free-slider saves; saves that already store the step name keep their step.
- Documentation defect: the E2E comment (`e2e_tier1_features.gd:1569`) cites `tables/Gameplay/Input/Character/MouseLookSensitivityCurve.json`, which **does not exist**; the real file is `tables/UI/Settings/MouseLookSensitivityCurve.json` (verified `test -e` → NO / YES).

---

## Item 4 — curves

**AUDIT: PASS.**

`test_input.gd::_check_curves` ran green (quoted PASS lines in the log): 16 names, `curves_index_missing=0`, `Constant interp holds 1.0 across 2.0..3.0 m`, `3.0 m -> 0.0`, before-first clamps to 1.0, "all 16 standalone curves resolve to keys (missing [])", light `0.0→0.15`, `1.0→1.0`, midpoint `0.575`, speed `0→0.0`, `600→0.1`, `900→0.1`, edge boost `0.95 / 1.0 / 1.0 / 1.5`.

- **RCIM_Constant:** `game_data.gd:256` — `if str(ka.get("InterpMode","")) == "RCIM_Constant" and x < t1: return v0`. The AI curve's first key is `(Time 2.0, Value 1.0, RCIM_Constant)`, second `(3.0, 0.0)`; x=2.5 → 1.0, x=3.0 → lerp/next key → 0.0. `_eval_keys` is shared by `eval_curve` and `eval_standalone_curve`; the AI/Alertness directory is one of the nine extra scan roots (`game_data.gd:126-136`), so the same table is also in `curves` and `eval_curve` reaches the same evaluator. **Note:** the test exercises this through `eval_standalone_curve`; `eval_curve` itself has no direct Constant assertion in the suite (shared-code verification only — see "Unverifiable").
- **All 16 resolve:** all 16 `curves.json` records name table files that exist on this tree, and every record also carries its own `rows` (1–3 channels, 2–18 keys). 12 are loaded by a scanned root; the 4 outside the roots (UI/Settings ×2, Gameplay/Indicators, MaterialLibrary/Character/EyeLibrary) resolve from the index `rows` — and the passing `Normal = 1.125` assertion proves that index-only path. **Doc nit:** `game_data.gd:16` says "the five curves whose table sits outside the 13 scanned roots"; the count is **4** (verified against `curves.json` and the root list).
- **light_probe:** endpoints are read from `C_LightIntensityToRangeMultiplier` (0 → 0.15, 1 → 1.0) and `C_MovementSpeedToMinimumLightDetectionValue` (0 cm/s → 0.0, 600 cm/s → 0.1), equal to the authored keys and to the retained fallback constants; outputs are clamped to `[0.15, 1.0]` and `[0.0, 0.1]` (`light_probe.gd:131-147`). The smoothstep between endpoints is documented as the zero-tangent cubic's shape; the evaluator is intentionally not asked to reconstruct cubic tangents.

---

## Item 5 — sprite tokens: independent data verification

**AUDIT: FAIL** — one of the four numbers is wrong as written; the other three and the probe's own output are exact.

`res://tests/probe_niagara.gd` (exit 0):

```
NIAGARA_PROBE files=107 authored=3695 active=1048 skipped=2647 systems=16 nodes=140 sprites=4 params=810 tint(param/material/fallback)=743/12/293
NIAGARA_SPRITE_TOKENS bound=5 total=39 legacy=5 renderers=82 changed=2 slots=opacity:2,albedo:23,emissive:0,normal:0,orm:0,none:11,subuv:3 reasons=gate:5,kept:18,no_material_record:2,no_texture:9,opacity_fallback:2,subuv_atlas:3 additive_opaque=9 additive_total=16 library=fixed:11/kept:194/none:107 masks=6/29 ms=38 errors=0
NIAGARA_PROBE PASS
```

Independent checks (python only, no Godot):

1. **29 paths, 6 pass** — parsed `sprite_masks.gd::MEASURED`: **29** unique paths; gate `has_alpha and border<=0.20 and 0.005<=cov<=0.85` → **6** (T_LootAttract_Shine, Smoke32, T_LeafWillowGlow_D, T_BushesLeaves_DA, T_LightGlowsA_D, TX_Splash_Big_01a_ALB). 23 rejected. ✔
2. **"12 referenced by a sprite renderer"** — **wrong as written.** Across `game/data/generated/vfx/systems.json` (120 systems, 312 sprite renderers, 32 distinct `sprite_texture`), **14** of the 29 measured paths are a `type=="sprite"` renderer's `sprite_texture`. **12** is correct only when restricted to the level's **placed** systems (37 systems, 82 sprite renderers, 39 distinct materials, 15 distinct tokens) — which is the probe's own denominator, and its own docstring says so (`probe_niagara.gd:377`, "not even referenced by a **placed** sprite renderer"). The two catalogue-only textures are `T_ChimneyPipesA_D.png` and `T_Zipwire_D.png`. `build/qa/w9/p1-report.md:274` says "only **12** of those 29 are referenced by a sprite renderer **at all**" — "at all" is false; it is 14 (12 placed). Same sentence in the A3b commit message.
3. **20 of 23 rejected pages alpha-opaque** — **correct.** Decoded every rejected PNG with `convert <png> -alpha extract -format '%[min] %[max]'`: **20/23** have `alpha_min == alpha_max == 65535` (255), including the grayscale `T_Decal_Puddle_5_Opacity.png` (no alpha channel). The three exceptions: `T_TrashDebris_DA` (0..255), `T_Bomb_Liquid_DA` (16..255), `T_SlimeBomb_DA` (28..255). ✔
4. **`additive_opaque=9 / additive_total=16`** — **correct, recomputed independently.** Placed set = 37 systems → **82** sprite renderers over **39** materials (matches `renderers=82 total=39`); **16** of those renderers use a material whose `render.blend_mode` contains `additive`, over **10** distinct materials. Re-implementing the probe's exact luminance sampler (step `max(1,int(sqrt(w*h/4096)))`, `max(R,G,B)>0.1`, outer 2 sample rows) reproduced the printed cov/border **exactly**: sparkles `0.141/0.004` bind, faerie `0.290/0.000` bind, droplets `0.444/0.048` bind, dart `0.955/0.938` box. `2+1+1+1+1+2+1 = 9` renderers over 7 materials / 5 systems → **9/16**. ✔

Also exact (bonus): catalogue denominators 98 sprite-bearing systems / 312 renderers / 96 materials; `library=fixed:11/kept:194/none:107` = 312; slots and reasons histograms each sum to 39.

**Wording defects found while checking:**
- `build/qa/w9/p1-report.md:282` and the A3b commit say the 2 rain materials "**now bind** their authored mask". The probe itself prints `gate=reject reason=opacity_fallback` for both; `T_DropletsMasks_Packed.png` is not in `MEASURED`, so `SpriteMasks.acceptable()` is false and `level_loader.gd:6315-6326` still sets `use_sprite=false`. `bound` stayed 5. They **resolve to** the authored opacity token; they do not bind. Say "resolve to".
- The ceiling arithmetic (`p1-report.md:277-280`) reads "additive (+7 materials) + SubUV (+3) + packed-channel (+2) … ceiling 15", but 5+7+3+2 = 17; it only equals 15 if the packed-channel +2 are the same two rain materials already inside the +7 (they are). The number 15 is right, the sentence reads as if the terms are disjoint.

---

## Item 6 — no gate weakened

**AUDIT: PASS** (with a noted limitation).

- `git diff c2a1cd8..HEAD -- game/src/core/vfx/sprite_masks.gd` → **0 lines** (empty; exit 0).
- `game/tests/probe_niagara.gd`: the diff has **0 removed lines** — every old assertion is intact and the new block is additive. `_verify_sprite_masks()` still runs (`probe_niagara.gd:260`) and re-measures **all 29** `MEASURED` literals, failing on any `detect_alpha` mismatch or `|cov − row| > 0.02` / `|border − row| > 0.02` drift. The event-gated drift check is still called (`:347`).
- `sprites=4` is still asserted: `_check(sprites == EXPECTED_SPRITE_SYSTEMS.size(), …)` with a 4-entry list, and the run prints `sprites=4`.
- The new 23/29 check is **non-regression only**, as claimed: `_check(bound >= legacy, …)`. Note the second `_check(skipped <= legacy_skipped, …)` is algebraically identical to the first (`total` cancels), so it adds no coverage. `changed=2` is printed, not asserted: a no-op resolver (always return the catalogue token) would pass this gate. The commit says exactly this ("asserts non-regression … prints the shortfall"), so it is a weak-but-honest floor, not a weakened existing gate.

---

## Item 7 — allowlist

**AUDIT: PASS.**

Removed rules (`git diff c2a1cd8..HEAD -- tools/consumer_allowlist.json`): `curves.json` (`provenance`, optional) and `gameplay/input_actions.json` (`blocked_on_team`, T06). Both are now genuinely read:

- `game/src/core/game_data.gd:22` — `const CURVES_INDEX_PATH: String = "res://data/generated/curves.json"`.
- `game/src/core/input_actions.gd:27` — `const GENERATED_PATH: String = "res://data/generated/gameplay/input_actions.json"`.
- `rg "curves.json|gameplay/input_actions.json" tools/consumer_allowlist.json` → no hits.

`python3 tools/check_consumers.py`:

```
consumer audit: 215 generated files
  runtime-read: 151 (dir_scan 65, literal 46, table_root 40)
  allowlisted:  64 (blocked_on_team 23, build_manifest 2, folded_into_aggregate 24, placeholder 1, producer_intermediate 7, provenance 1, tests_only 3, text_via_locres 3)
  table roots parsed from game_data.gd: 13
  blocked on a named owner: T03 7, T05 13, T08 1, T10 1, T11 1
CONSUMER AUDIT PASS
```

`--list-unconsumed` does **not** list either file. The commit says "150 runtime-read"; the current tree reports **151** (+1 from A2's `project_settings.json`/progression reader) — a count drift, not a defect.

---

## Cross-cutting findings

**C1 — `5b112b1` is not independently buildable (process, disclosed).** The commit adds `const Progression := preload("res://src/core/progression.gd")` and calls `Progression.endgame_ladder_authored()` (`game_data.gd:732,747`), but that file is only added in its child `bb37003`:

```
$ git cat-file -e 5b112b1:game/src/core/progression.gd
fatal: path 'game/src/core/progression.gd' exists on disk, but not in '5b112b1'
```

So the commit's "compile 152/0" is a claim about the lane's synthetic "isolated attribution tree", not the commit. Checked out alone, `game_data.gd` fails to preload. This breaks bisect and the repo's "one coherent commit per change" rule; the message does disclose the A2 hunk. HEAD is unaffected.

**C2 — shared data tree.** `game/data/generated` is a symlink into `/home/john/Projects/TAT-2`; the A3 gate numbers are only valid for that tree. A regenerate invalidates every number above (they are producer outputs, not code).

**C3 — dirty/unstable tree.** I ran `test_input` and `probe_niagara` only. Full `run_tests` / E2E were not run because another lane's WIP would contaminate attribution, and the worktree changed during the audit. Neither A3 result depends on the changed files: `test_input` asserts the input table and curves directly, and `probe_niagara` reads the level JSON + catalogue (the `level_loader` code it exercises was the 11:07 WIP copy, not HEAD; the probe still printed the expected `authored=3695 active=1048 skipped=2647 systems=16 nodes=140 sprites=4`).

## Unverifiable in this audit

- `eval_curve()` (as opposed to `eval_standalone_curve()`) on `Curve_AI_HeightDifferenceToStrengthMultiplier` is not directly exercised by any test; verification is by the shared `_eval_keys` + the standalone assertion.
- The sensitivity **fallback** path (`curves.json` unreadable → ini ladder) was inspected, not executed (would require moving/renaming generated data, i.e. a write).
- The "ceiling 15" components are projections; only the additive 9/16 and the 7-materials/5-systems split were reproduced. SubUV slicing was not modelled (the atlas page is alpha-opaque 1.0/1.0, so "slicing alone yields a soft mask" is itself unproven).
- Commit-level compile at `5b112b1` was proven statically (preload of an absent file), not by checking out the commit (git writes are out of scope).
- E2E 278/278 and `run_tests` at HEAD (see C3).

---

## Verdict

**NOT CLEAN — 6/7 items PASS; item 5 fails on one factual sentence; no functional regression found.**

- Items **1, 2, 3, 4, 6, 7: PASS**. The table really loads (91/91/52, 237 total, `AUTHORED_ROWS` 0), the tests were strengthened not weakened and the suite-35b/E2E-T1-16-D numbers are exactly the authored curve values, the six curve behaviours and both light endpoints hold with clamps, `sprite_masks.gd` is byte-identical, and the allowlist removals are backed by real readers (`CONSUMER AUDIT PASS`).
- Item **5: FAIL** on the single claim "only 12 of those 29 are referenced by a sprite renderer": the systems.json-wide count is **14**; 12 is true only for the level's placed renderers. The other three numbers (29/6, 20/23 alpha-opaque, 9/16 additive) are exact and independently reproduced; the probe's own output is trustworthy.
- Process findings: `5b112b1` cannot compile in isolation (missing `progression.gd` preload); the report says the rain masks "now bind" when they only resolve (`gate=reject`); two doc paths/counts are wrong (`game_data.gd:16` "five" vs 4; E2E comment's `Gameplay/Input/Character/…MouseLookSensitivityCurve.json` does not exist).
- No test was weakened, no gate file was relaxed, and no A3 code change hides a regression at HEAD.
