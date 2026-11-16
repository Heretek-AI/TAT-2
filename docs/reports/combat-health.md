# Combat / Health Implementation Report

Stage: combat-health (fall damage, downed state, revive timing, guard regen).
All values below are extracted, not invented. Generated artifacts:
`game/data/generated/gameplay/{fall_damage,downed,health_blocks}.json`.

## 1. Value table (extracted -> Godot)

| Value | Extracted source | Godot location |
|---|---|---|
| Safe fall height 650 cm / 6.5 m | `extracted/json/Core/BP_TATPlayerCharacter.json` (`BP_TATPlayerCharacter_C._safeFallHeight`) | `fall_damage.json` `safe_fall_height_m`; `thief_character.gd` `_fall_safe_m` (fallback 6.5) |
| Death fall height 2325 cm / 23.25 m | `extracted/json/Character/Player/BP_Player_Base.json` (`BP_Player_Base_C._deathFallHeight`) | `fall_damage.json` `death_fall_height_m`; `_fall_death_m` (fallback 23.25) |
| Falling-damage curve keys `(0->0)`, `(0.7->0.4)`, `(1->1)`, cubic | `extracted/json/Character/Player/Curve_FallingDamage.json` (`CurveFloat.FloatCurve.Keys`, all `RCIM_Cubic`; tangents `0.0`, `1.2960153`, `0.05426467`) | `fall_damage.json` `curve_keys`; Godot `Curve` with `TANGENT_FREE` built from the keys |
| Downed duration 10.0 s | `extracted/json/Gameplay/Combat/Common/GE_GrantPlayerDowned_Duration.json` (`DurationMagnitude 10.0`) | `downed.json` `downed_duration_s`; `_downed_duration` (fallback 10.0) |
| Post-revive cooldown 3.0 s | `extracted/json/Gameplay/Combat/Common/GE_PostReviveCooldown.json` (`DurationMagnitude 3.0`) | `downed.json` `post_revive_cooldown_s`; `post_revive_cooldown_s` (fallback 3.0) |
| Revive hold 5.0 s | `.../SyncedAbilities/Player/GA_SyncedAbility_Revive_Guard.json` + `GA_SyncedAbility_Revive_Player.json` (`InteractHoldDuration 5.0` each, agree) | `downed.json` `revive_hold_s`; `guard_ai.revive_hold_s()` (fallback 5.0) replaces the old 1.6 s hold |
| Guard regen 15.0/s, Guard max HP 30 | `game/data/generated/tables/Gameplay/Tuning/CT_AIStats.json` (`GuardBaseHealthRegenRate`, `GuardBaseHealth`) | `GameData.eval_curve` with fallbacks 15.0/30.0; `_tick_regen()` while conscious |
| Spider blocks `[25,25,25,25]` | `extracted/json/Character/Player/BP_Player_Thief_Spider.json` (`HealthBlockPercentages`) | `health_blocks.json`; `health_block_percentages()` |
| Chameleon blocks `[30,30,20,20]` | `extracted/json/Character/Player/BP_Player_Thief_Chameleon.json` (`HealthBlockPercentages`) | `health_blocks.json`; `health_block_percentages()` |

`tools/parse_gameplay.py` emits the three new files and fails closed
(missing file, missing key, key-count or sum != 100 aborts with exit 1).

## 2. Curve evaluation (UE RCIM_Cubic vs Godot Curve)

`t = clamp((drop - 6.5) / (23.25 - 6.5), 0, 1)`; damage = curve(t) x max_health.
Reference = textbook cubic Hermite with the extracted tangents; Godot =
`Curve.sample()` on the key-built curve (headless probe):

| t (drop) | UE Hermite ref | Godot sample |
|---|---|---|
| 0.0 (<= 6.5 m) | 0.0 | 0.0 |
| 0.35 (~12.4 m) | 0.086599 | 0.086599 |
| 0.5075 (15 m) | 0.194743 | 0.194753 |
| 0.7 (~18.2 m) | 0.4 | 0.4 |
| 0.85 (~20.7 m) | 0.746566 | 0.746566 |
| 1.0 (>= 23.25 m) | 1.0 | 1.0 |

15 m deals 58.42 HP of 300 max (fraction 0.19475); 23.25 m deals max
health (instant downed). Godot `TANGENT_FREE` hermite reproduces the UE
cubic to 5 decimal places — no invented shaping.

## 3. Behavior implemented

- `thief_character.gd`: airborne peak tracking (`_track_fall_state`);
  landing damage via `fall_damage_for_drop`/`_apply_fall_damage` (grapple and
  astral gated, see assumptions). At 0 HP enters `is_downed` for 10 s,
  emits `downed_started(seconds)`, blocks movement/sprint/abilities/tools/
  interact via `can_act()` while camera look stays live; `downed` fires only
  when the timer expires (`_downed_fired` single-shot). `downed_remaining()`,
  `revive()` helper, `post_revive_ttl` countdown, `health_block_percentages()`.
- `guard_ai.gd`: `_tick_regen()` (+15/s to real max, any conscious state);
  `_recover_from_ko()` restores the real max; ally-revive threshold
  `revive_hold_s()` = 5.0 s. Also fixed a latent crash: `_on_noise_emitted`
  called `bool(source.get("astral_active"))` for guard sources (property
  missing -> "Nonexistent 'bool' constructor" SCRIPT ERROR); now guarded by
  `source.is_in_group("player")`.
- `mission_controller.gd`: connects `downed_started` -> countdown display;
  `downed` still fails the mission (unchanged handling).
- `hud.gd`: `downed_lbl` ("DOWNED — Ns", 26pt red) driven by
  `set_downed_display()` and a per-frame `downed_remaining()` poll; hidden
  in `show_result()`.

## 4. Assumptions (no UE source found, stated not invented)

1. Grapple/astral fall immunity: the zipwire winch controls descent and the
   Moth astral form is a spirit; no immunity flag was extracted.
2. Single-player revive is not wired to any ability; `revive()` restores full
   HP because the real post-revive attribute set
   (`GE_SetPlayerAttributesAfterRecoverFromDowned`) was not extracted.
3. Moth has no `HealthBlockPercentages` row; falls back to Spider.
4. `take_damage` is ignored while downed (no source for downed damage rules).
5. Guard regen ticks in every conscious state (no per-state gating sourced).

## 5. Verification

Temporary `game/tests/_tmp_health_check.gd` (written RED-first: initial run
failed with `Nonexistent function 'fall_damage_for_drop'` as expected;
deleted after GREEN, never touched `run_tests.gd`):

```
PASS: fall 6.4m -> 0 damage
PASS: fall 6.6m -> >0 damage
PASS: fall 15m -> ~0.195 of max
PASS: fall 23.25m -> max-health damage
PASS: grapple fall immune
PASS: astral fall immune
PASS: normal fall damages
PASS: 0 HP enters downed
PASS: downed_started carries 10s
PASS: downed NOT emitted on entry
PASS: downed_remaining starts at 10
PASS: downed ticks to 6
PASS: downed NOT emitted mid-timer
PASS: downed_remaining reaches 0
PASS: downed emitted only after timer
PASS: downed blocks actions
PASS: spider health blocks
PASS: post-revive cooldown 3s
PASS: guard regen 15/s (10->25)
PASS: guard regen caps at 30
PASS: ally still KO after 1.6s
PASS: ally woken after 5s hold
PASS: hud shows DOWNED countdown
PASS: hud hides countdown after revive
TMP_SUMMARY: fails=0
EXIT=0
```

Zero SCRIPT ERROR in the temp runs after the `_on_noise_emitted` fix.

Incidental test-harness findings (for the team, not production):
- `set_physics_process(false)` called *before* `add_child` does not stick in
  Godot 4.7 headless (probe: flag read back `true` post-add); disable
  *after* adding to the tree.
- `bool(null)` is a parse-time error and `bool(missingVariant)` a runtime
  "Nonexistent 'bool' constructor" error — never call `bool()` on an
  unchecked `Object.get()`.

## 6. Full suite

`make test` (full `run_tests.gd`, Godot 4.7.2 headless): **20 PASS,
`SUMMARY: fails=0`, exit 0, zero `SCRIPT ERROR` / `FAIL` lines.**
Suites 4/10 spawn guards, suite 5 completes a contract. (Engine-shutdown
ObjectDB/RID leak warnings only — pre-existing shutdown noise, not script
errors.) Exact tail:

```
PASS: Real weather DenseFog applied (fog=0.004 moon_energy=0.25 rot=(-90.0, 263.0, -54.52945))
SUMMARY: fails=0
EXIT=0
```
