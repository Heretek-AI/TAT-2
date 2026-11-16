# Gameplay Constants — Real UE Values Implementation

Stage: gameplay-constants. Date: 2026-11-16.
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
| `CAMERA_FOV` | `FirstPersonFieldOfView` 85.0 | 85.0 (sprint feedback 89 = 85 + retained +4) | BP_Player_Base OSECameraComponent |
| `INTERACT_RANGE` | `MaxInteractionRange` 175.0 | 1.75 m (`get_nearest_interactable`) | BP_Player_Base TATInteractionTargeterComponent |
| sprint drain | `StaminaPerSecond.Sprint` −5.0 (curve kept, ×3.0 dropped) | 5/s | `extracted/json/Gameplay/Tuning/CT_StaminaSystem.json` |
| `stamina_regen` | `BaseStaminaRegenRate` 2.0 × 0.25 coeff / 0.1 s period (curve kept, ×6.0 dropped) | 5/s | CT_PlayerStats × `GE_Stamina_Regen.json` |
| `WIRE_RANGE` / `WIRE_PULL_SPEED` | Hotwire Range 2000 / Speed 2300 | 20 m / 23 m/s | `DA_StandardToolSettings.json` |
| wire cooldown | `WireCooldownSecondary` 5.0 (curve kept, ×0.4 dropped) | 5 s | `CT_Tool_Wire.json` |
| grapple charges | `MaxAmmo` 4 (HUD slot shows `grapple` key; spent only on latched anchor) | 4 | `BP_Hotwire_Tool.json` |
| smoke | `MaxAmmo` 1; `InitialLifeSpan` 25.0; BoxExtent 250×250×200 | 1 charge, ttl 25 s, radius 2.5 | `BP_SmokeBomb_Bomb_Tool.json` + `BP_SmokeBomb_WorldActor.json` |
| disguise | cooldown magnitude 15; active magnitude 60 (new 60 s TTL auto-expiry) | 15 s / 60 s | `GE_Disguise_Cooldown.json` / `GE_Disguise_Active.json` |
| blackjack | `BlackjackDamageLight` 40 / `Heavy` 75 (rows kept); behind-attack 999 → heavy | 40 / 75 | `CT_Tool_Blackjack.json` |
| slithersap charges | `MaxAmmo` 4 (mechanics untouched per brief) | 4 | `BP_MagicSlime_Tool.json` |

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
| melee | close key 10.0; `DamageRadius` 100; cooldown magnitude 2.0 | 10 dmg / 1.0 m / 2.0 s | `CT_Melee_RangedAttackDamage.json` + `GA_MeleeRangedAttack.json` + `GE_Melee_RangedAttack_Cooldown.json` |

Detection ramp (`detection.json`, all per alertness: Neutral/Suspicious 0.4 s/m,
Alerted/Combat 0.2 s/m; `CriticalRange` 2.0 m, `CriticalTime` 0.0 s,
crouch 0.75 at/over 2.75 m — Combat crouch_min 2.0 m):
time-to-detect(s) = agnostic·dist_m + critical_time; instant (INF) at/inside
critical range. Check: 10 m Neutral = 4.0 s → 25/s; crouched 18.75/s.

## Retained approximations (no UE source found)

- Player: velocity lerp base 14.0/s; grapple arrive 1.8 m / vault 6.5 / min-range
  3.0 m / winch 0.35 s; `DISGUISE_STEAL_RANGE` 2.8; disguise integrity drain 6.7/s;
  sprint velocity-FOV shape (+4/-0 rebased on 85); disguise 60 s TTL reading of
  GE_Disguise_Active (Infinite policy + magnitude 60).
- Guard: difficulty scaling of patrol/suspicious/sight (×0.85–1.2); SEARCH speed
  = patrol × 1.15; detection decay 22/s; 15/45/100 state thresholds; 3.5 m
  close-range peripheral bypass; `Status.Sprinting` ×8 tag modifier recorded in
  `detection.json` but NOT wired (out of scope).
- Discrepancy: GuardBase Fresh `LoseSightRadius` is 2500, not 3000; applied 30 m
  per the Bouncer/Hauntstable Fresh rows. `guard_ai.json` records both; revisit if
  the guard archetype mapping changes.

## Verification

- Temp check `game/tests/_tmp_gameplay_check.gd` (created, run, deleted):
  60/60 PASS — all JSON values, live player/guard fields, state speeds, and the
  10 m Neutral = 25/s rate (crouched 18.75/s, 2.5 m crouched 100/s).
- `make test`: `SUMMARY: fails=0`, exit 0, no SCRIPT ERROR (only pre-existing
  engine exit-leak warnings). Guard/player behaviour changes did not break
  spawn/objective suites.
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
- `game/src/player/thief_character.gd`: values above.
- `game/src/ai/guard_ai.gd`: values above + `get_state_speed()` / `get_detection_rate()`.
