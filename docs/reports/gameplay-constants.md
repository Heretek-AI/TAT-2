# Gameplay Constants — Real UE Values Implementation

Stage: gameplay-constants. Date: 2026-11-16; authored follow-up 2026-11-17 (`f567d23`, `3e0817f`).
Regenerate data: `python3 tools/parse_gameplay.py` (writes gitignored
`game/data/generated/gameplay/*.json`; regenerate is required on fresh clones).

## Value table (UE value/units -> Godot value, source)

### Player (`game/src/player/thief_character.gd`)

| Godot field | UE value | Godot value | Source JSON path |
|---|---|---|---|
| `walk_speed` | `MaxWalkSpeed` 360.0 cm/s | 3.6 m/s | `extracted/json/Character/Player/BP_Player_Base.json` (TATCharacterMovement CharMoveComp) |
| `crouch_speed` | `MaxWalkSpeedCrouched` 180.0 cm/s | 1.8 m/s | same CharMoveComp |
| `sprint_speed` | 360 + `SprintSpeedIncrementBase` 90 + `SprintSpeedIncrementForward` 90 = 540 cm/s | 5.4 m/s | same CharMoveComp |
| `jump_velocity` | `JumpZVelocity` 550.0 cm/s | 5.5 m/s | same CharMoveComp |
| `gravity` | UE default 980 cm/s² (no override in CharMoveComp) | 9.8 m/s² | UE default |
| capsule | `CapsuleHalfHeight` 89.0, radius 32 (radius inherited from base) | r 0.32, h 1.78, y 0.89 | `extracted/json/Character/Player/BP_Player_Thief_Spider.json` (Spider CDO + CollisionOverlayCapsuleComponent) |
| crouch capsule | `CrouchedHalfHeight` 50.0 | h 1.0, y 0.5 | BP_Player_Base CharMoveComp |
| `STAND_HEAD_HEIGHT` | `BaseEyeHeight` 77.875 cm over capsule centre 89 cm | 0.89 + 0.77875 = 1.66875 m | Spider CDO (capsule-centre convention) |
| `CROUCH_HEAD_HEIGHT` | `CrouchedEyeHeight` 38.875 cm over 50 cm | 0.50 + 0.38875 = 0.88875 m | Spider CDO |
| `floor_max_angle` | `WalkableFloorAngle` 60.0 | `deg_to_rad(60)` | CharMoveComp |
| air control | `AirControl` 0.5 | 0.5 (scales airborne `steer`; ground 14.0 retained) | CharMoveComp |
| `CAMERA_FOV` | `FirstPersonFieldOfView` 85.0 (horizontal) | 54.54 vertical at 16:9 = 85 horizontal (sprint feedback 58.54 = +4); VM keeps its own 85 deg lock | BP_Player_Base OSECameraComponent |
| `INTERACT_RANGE` | `MaxInteractionRange` 175.0 | 1.75 m (`get_nearest_interactable`) | BP_Player_Base TATInteractionTargeterComponent |
| sprint drain | `StaminaPerSecond.Sprint` −5.0 (curve kept, ×3.0 dropped) | 5/s | `extracted/json/Gameplay/Tuning/CT_StaminaSystem.json` |
| `stamina_regen` | `BaseStaminaRegenRate` 2.0 × 0.25 coeff / 0.1 s period (curve kept, ×6.0 dropped) | 5/s | CT_PlayerStats × `GE_Stamina_Regen.json` |
| `WIRE_RANGE` / `WIRE_PULL_SPEED` | Hotwire Range 2000 / Speed 2300 | 20 m / 23 m/s | `DA_StandardToolSettings.json` |
| wire cooldown | `WireCooldownSecondary` 5.0 (curve kept, ×0.4 dropped) | 5 s | `CT_Tool_Wire.json` |
| grapple charges | `MaxAmmo` 4 (HUD slot shows `grapple` key; spent only on latched anchor) | 4 | `BP_Hotwire_Tool.json` |
| smoke | `MaxAmmo` 1; `InitialLifeSpan` 25.0; BoxExtent 250×250×200 | 1 charge, ttl 25 s, radius 2.5 | `BP_SmokeBomb_Bomb_Tool.json` + `BP_SmokeBomb_WorldActor.json` |
| disguise | cooldown magnitude 15; active magnitude 60 (new 60 s TTL auto-expiry) | 15 s / 60 s | `GE_Disguise_Cooldown.json` / `GE_Disguise_Active.json` |
| disguise integrity | `DisguiseTimer.IntegrityReduction` 1.0/s; `Sprinting` 40.0/s; `GuardProximity` 5.0/s within `CharacterRadius` 100 cm; `DamageTaken` 40.0 | 1.0 + 40.0 + 5.0 per s (enabled rows sum); 40 integrity per damage event | `extracted/json/Gameplay/Tools/PrimaryTools/Disguise/DT_DisguiseV3IntegrityReduction.json` |
| blackjack | `BlackjackDamageLight` 40 / `Heavy` 75 (rows kept); behind-attack 999 → heavy | 40 / 75 | `CT_Tool_Blackjack.json` |
| slithersap charges | `MaxAmmo` 4 (mechanics untouched per brief) | 4 | `BP_MagicSlime_Tool.json` |

### Progression (`game/src/core/save_system.gd`)

| Godot field | UE value | Godot value | Source JSON path |
|---|---|---|---|
| `xp_threshold_for_level` | `CT_XPToLevel.XPToLevel`: level 1–4 = 500, 5–9 = 1000, 10–24 = 2500 (`RCIM_Linear`, constant extrapolation) | per-level cost from `GameData.eval_curve`; `xp_total_for_level` / `level_for_xp` derive the level from XP | `extracted/json/Gameplay/Tuning/CT_XPToLevel.json` |

### Guard (`game/src/ai/guard_ai.gd`)

| Godot field | UE value | Godot value | Source JSON path |
|---|---|---|---|
| patrol (Neutral) | 150.0 cm/s | 1.5 m/s | `extracted/json/AI/Data/DA_AIStatesToSpeed_Guard.json` |
| suspicious | 170.0 cm/s | 1.7 m/s | same |
| alerted/combat | `MaxWalkSpeed` 250.0 cm/s | 2.5 m/s (`ALERTED_SPEED`, `chase_speed`) | `BP_Guard_Base.json` TATCharacterAIMovement |
| `sight_range` | Fresh `SightRadius` 2000 | 20 m | `AIC_GuardBase.json` TATAISenseConfig_Sight |
| `lose_sight_range` | `LoseSightRadius` 3000 (Bouncer/Hauntstable Fresh) | 30 m | `AIC_Bouncer.json` (see discrepancy note) |
| `fov_deg` | `PeripheralVisionAngleDegrees` 40 (UE half-angle) | 80 | AIC sight configs |
| `hearing_range` | `HearingRange` 2500.0 | 25 m | `AIC_GuardBase.json` TATAISenseConfig_Hearing |
| capsule | half 118 / radius 45 | r 0.45, h 2.36, y 1.18 | `BP_Guard_Base.json` CollisionOverlayCapsuleComponent |
| detection | ramp per alertness (see below) | rate = 100 / (agnostic·dist + tcrit) | `DA_DetectionSettings.json` RampSettings |
| detection decay | `DecayTimeSeconds` Neutral 1.0 / Suspicious 5.0 / Alerted 10.0 / Combat 10.0; gates `MinSecondsInCurrentDetectionLevelBeforeDecay` 6.0 and `MinSecondsSinceVisibleBeforeDecay` 4.0 | `100 / DecayTimeSeconds` = 100 / 20 / 10 / 10 per s after both gates | `extracted/json/AI/Alertness/DA_AlertnessSettings.json` + `extracted/json/AI/Data/DA_DetectionSettings.json` |
| sprint ramp | `Status.Sprinting` multipliers 8.0 in all four states | x8 detection ramp while sprinting | `extracted/json/AI/Data/DA_DetectionSettings.json` `GameplayTagRampModifiers` |
| light -> range | `C_LightIntensityToRangeMultiplier` 0.0 -> 0.15, 1.0 -> 1.0 | smoothstep multiplier on fresh sight range | `extracted/json/AI/Data/C_LightIntensityToRangeMultiplier.json` |
| speed -> min light | `C_MovementSpeedToMinimumLightDetectionValue` 0 cm/s -> 0.0, 600 cm/s -> 0.1 | max(sampled light, value) | `extracted/json/AI/Data/C_MovementSpeedToMinimumLightDetectionValue.json` |
| height -> strength | `Curve_AI_HeightDifferenceToStrengthMultiplier` 2 m -> 1.0, 3 m -> 0.0; Neutral ramp only | 1.0 below 3 m, 0.0 at/above | `extracted/json/AI/Alertness/Curve_AI_HeightDifferenceToStrengthMultiplier.json` |
| melee | close key 10.0; `DamageRadius` 100; cooldown magnitude 2.0 | 10 dmg / 1.0 m / 2.0 s | `CT_Melee_RangedAttackDamage.json` + `GA_MeleeRangedAttack.json` + `GE_Melee_RangedAttack_Cooldown.json` |

Detection ramp (`detection.json`, all per alertness: Neutral/Suspicious 0.4 s/m,
Alerted/Combat 0.2 s/m; `CriticalRange` 2.0 m, `CriticalTime` 0.0 s,
crouch 0.75 at/over 2.75 m — Combat crouch_min 2.0 m):
time-to-detect(s) = agnostic·dist_m + critical_time; instant (INF) at/inside
critical range. Check: 10 m Neutral = 4.0 s → 25/s; crouched 18.75/s.

Decay (`DA_AlertnessSettings.DecayTimeSeconds`): Neutral 1.0 s (100/s),
Suspicious 5.0 s (20/s), Alerted/Combat 10.0 s (10/s), behind the 6 s
in-level and 4 s unseen gates from `DA_DetectionSettings.DecaySettings`.
`SEARCH` is Godot-only (no authored `DA_AlertnessSettings` row): it decays
unconditionally at the `DetectionDecaySeconds` 7.0 s fallback (14.29/s) and is
not clamped on transition. Downward transitions clamp detection to the entry
ceiling (Neutral/Suspicious 15, Alerted 45, Combat 100).

## Retained approximations (no UE source found)

- Player: velocity lerp base 14.0/s; grapple arrive 1.8 m / vault 6.5 / min-range
  3.0 m / winch 0.35 s; `DISGUISE_STEAL_RANGE` 2.8; sprint velocity-FOV shape
  (+4/-0 rebased on 85); disguise 60 s TTL reading of `GE_Disguise_Active`
  (Infinite policy + magnitude 60). The `Lockpicking` (5.0/s,
  `Status.Lockpicking`) and `GuardViewCone` (10.0/s, 10 m, 65°) integrity rows
  are enabled in `DT_DisguiseV3IntegrityReduction` but not ported: there is no
  sustained lockpicking state or player-facing guard view-cone query.
- Guard: difficulty scaling of patrol/suspicious/sight (×0.85–1.2); SEARCH speed
  = patrol × 1.15; 15/45/100 state thresholds; 3.5 m close-range peripheral
  bypass. SEARCH has no authored `DA_AlertnessSettings` row, so its 7 s decay is
  the `DetectionDecaySeconds` fallback (inference, not decompiled behaviour).
- Discrepancy: GuardBase Fresh `LoseSightRadius` is 2500, not 3000; applied 30 m
  per the Bouncer/Hauntstable Fresh rows. `guard_ai.json` records both; revisit if
  the guard archetype mapping changes.

## Verification

- Temp check `game/tests/_tmp_gameplay_check.gd` (created, run, deleted):
  60/60 PASS — all JSON values, live player/guard fields, state speeds, and the
  10 m Neutral = 25/s baseline rate (crouched 18.75/s, 2.5 m crouched 100/s).
- `make test` (2026-11-17): `SUMMARY: fails=0`, exit 0, zero `SCRIPT ERROR`,
  26 numbered suites. Suites 25/26 assert the authored follow-up values:
  - `PASS: disguise drain matches DT_DisguiseV3IntegrityReduction (timer 1.0/s, sprint 40.0/s, guard proximity 5.0/s within 100.0cm; damage event 40.0)`
  - `PASS: XP thresholds match CT_XPToLevel.XPToLevel (L1=500, L5=1000, L10=2500; flat 500 would fail L5/L10)`
  - `PASS: AI detection decay matches DA_AlertnessSettings.DecayTimeSeconds (Neutral 100.0/s, Suspicious 20.0/s, Alerted 10.0/s, Combat 10.0/s; 22/s would fail)`
  - `PASS: authored 6 s in-level / 4 s unseen decay gates still hold for Neutral/Suspicious/Alerted/Combat`
  - `PASS: AI sprint ramp matches detection.json Status.Sprinting x8.0`
  - `PASS: AI height-difference strength matches Curve_AI_HeightDifferenceToStrengthMultiplier (2.0 m -> 1.0 / 3.0 m -> 0.0)`
  - `PASS: AI light curves match C_LightIntensityToRangeMultiplier (0.0 -> 0.15 / 1.0 -> 1.0) and C_MovementSpeedToMinimumLightDetectionValue (0.0 cm/s -> 0.0 / 600.0 cm/s -> 0.1)`
- Interference note: shared worktree contains other agents' in-flight work
  (`parse_interactables.py`, `_tmp_interact_check.gd`, `parse_tables.py`,
  `mission_controller.gd`, `Makefile`, etc.). None of those files were touched;
  only `tools/parse_gameplay.py`, `game/src/player/thief_character.gd`,
  `game/src/ai/guard_ai.gd`, and this report are mine. `make test` passed with
  their changes present; no interference observed.

## Files changed

- `tools/parse_gameplay.py` (new): fail-closed extractor → `character_movement.json`,
  `guard_ai.json`, `state_speeds.json`, `detection.json`, `player_tools.json`
  (all with per-value `sources`; output dir is gitignored — regenerate on clone).
- `game/src/player/thief_character.gd`: values above, plus authored disguise integrity drain and damage handling.
- `game/src/ai/guard_ai.gd`: values above, plus `get_state_speed()` / `get_detection_rate()`, authored decay helpers, the sprint x8 ramp, height curve, and downward-transition clamp.
- `game/src/core/save_system.gd`: `CT_XPToLevel`-driven level thresholds; legacy save levels are re-derived from XP.
- `game/src/stealth/light_probe.gd`: authored light-intensity/range and movement-speed/minimum-light curves.
