extends RefCounted
## Authored guard ranged attack (RE-I-11), `GA_MeleeRangedAttack`.
##
## Shipped assets (`extracted/json/Gameplay/Combat/Guard/Melee/RangedAttack/`):
## * `CT_Melee_RangedAttackDamage` row `Damage`: linear keys (0 cm -> 10.0) and
##   (2000 cm -> 2.0), RCIM_Linear, RCCE_Constant at both infinities, so a shot
##   deals 10 at 0 m, 2 at 20 m and 2 beyond. `GA_MeleeRangedAttack_C`
##   `DamageAmount` wires curve table `Damage`, `DamageType = DamageType.Shock`,
##   `EffectToApplyOnHit = GE_Melee_RangedAttack_Shock`, `DamageRadius = 100 cm`,
##   `NumberOfShots = 1`, `DelayBeforeFirstShot = 0.1`,
##   `DelayBetweenShots = 1.5`, `DelayAfterAttackAnimation = 0.75`,
##   `LineOfSightTraceProfile = AOE`.
## * `GE_Melee_RangedAttack_Cooldown`: 2.0 s, tag `Cooldown.AI.RangedAttack`.
## * `GE_Melee_RangedAttack_AccuracyStack`: 10.0 s, `AggregateBySource`,
##   `StackLimitCount = 3`.
## * `GE_Melee_RangedAttack_Shock`: 3.0 s, `DamageReductionMultiplier`
##   Multiplicitive x1.1, HUD icon `S_HUD_Icon_shock`.
## * `EQS_FindRangedAttackLocation`: grid 1500 cm / 250 cm around the target with
##   a Distance test 200..1000 cm and a visibility trace at 50 cm height, i.e.
##   the authored firing position is 2..10 m from the target with line of sight.
## * `DT_ReactionEvents.Combat`: default role `AI.Behavior.Role.Combat.RangedAttack`,
##   `Chaser` max 1 (5 s grace) -- the reaction pair this module feeds.
##
## The port shipped a 1 m melee: `MELEE_RADIUS 1.0`, damage only inside 1 m.
## `player_tools.json.guard_melee.far_damage` (2.0) was extracted and unread.
##
## NOT RECOVERABLE, therefore not invented:
## * `RandomizationBasedOnAccuracyStack` is a MapProperty<int, Vector> on the
##   ability CDO with no serialised keys, so no per-stack aim jitter value
##   exists in the dump. The port tracks the stacks (count/window/limit, all
##   authored) and applies **no** jitter; `accuracy_randomization_available()`
##   reports false so a future producer can turn it on.
## * The victim-side `DamageReductionMultiplier` attribute lives in OSECore and
##   has no port counterpart, so shock is delivered as a call/contract
##   (`apply_shock(seconds, multiplier)`) with the authored numbers and the HUD
##   icon name; the player-side application is BLOCKED-ON the player status
##   effort (see the team report).

const CURVE_ROW := "Damage"
const CURVE_NEAR_M := 0.0
const CURVE_FAR_M := 20.0
const DAMAGE_NEAR := 10.0
const DAMAGE_FAR := 2.0
const DAMAGE_RADIUS_M := 1.0
const COOLDOWN_S := 2.0
const EQS_MIN_RANGE_M := 2.0
const EQS_MAX_RANGE_M := 10.0
const ACCURACY_WINDOW_S := 10.0
const ACCURACY_LIMIT := 3
const SHOCK_SECONDS := 3.0
const SHOCK_DAMAGE_REDUCTION_MULTIPLIER := 1.1
const SHOCK_HUD_ICON := "S_HUD_Icon_shock"
const SHOCK_DAMAGE_TYPE := "DamageType.Shock"
const DELAY_BEFORE_FIRST_SHOT_S := 0.1
const DELAY_BETWEEN_SHOTS_S := 1.5

## Player-side method this module calls when a shot lands. Guarded by
## has_method() so a missing implementation is a documented gap, not a crash.
const PLAYER_SHOCK_METHOD := "apply_shock"


## Authored damage for a hit at `dist_m`, evaluated on the curve's linear
## segment and clamped to its authored keys (RCCE_Constant).
static func damage_at_m(dist_m: float) -> float:
	var d: float = clampf(dist_m, CURVE_NEAR_M, CURVE_FAR_M)
	if CURVE_FAR_M <= CURVE_NEAR_M:
		return DAMAGE_NEAR
	var t: float = (d - CURVE_NEAR_M) / (CURVE_FAR_M - CURVE_NEAR_M)
	return lerpf(DAMAGE_NEAR, DAMAGE_FAR, t)


## Hard firing range: the curve's own extent. A guard outside it has no authored
## damage value above the floor, and DT_ReactionEvents' ranged role is what keeps
## it at the EQS band instead.
static func fire_range_m() -> float:
	return CURVE_FAR_M


## Authored EQS firing band (metres).
static func ideal_band_m() -> Vector2:
	return Vector2(EQS_MIN_RANGE_M, EQS_MAX_RANGE_M)


## True when the guard should reposition instead of firing: too close (the EQS
## minimum) or beyond the curve.
static func needs_reposition(dist_m: float) -> bool:
	if dist_m < EQS_MIN_RANGE_M:
		return true
	return dist_m > EQS_MAX_RANGE_M


## Can the guard fire at all this frame?
static func can_fire(dist_m: float, cooldown_left_s: float, has_los: bool) -> bool:
	if not has_los:
		return false
	if cooldown_left_s > 0.0:
		return false
	return dist_m <= fire_range_m()


## Accuracy stack count after a shot lands (authored limit 3).
static func stacks_after_shot(stacks: int) -> int:
	return clampi(stacks + 1, 0, ACCURACY_LIMIT)


## Stacks that survive `seconds_since_last_shot` (authored 10 s window, so the
## whole stack group expires together: AggregateBySource with one source = the
## guard itself, refreshed by every shot).
static func stacks_after_age(stacks: int, seconds_since_last_shot: float) -> int:
	return 0 if seconds_since_last_shot > ACCURACY_WINDOW_S else clampi(stacks, 0, ACCURACY_LIMIT)


## False: the per-stack randomization vector map is authored but empty in the
## dump, so the port applies no aim jitter. Kept as a function so the switch is
## one edit when a producer recovers the values.
static func accuracy_randomization_available() -> bool:
	return false


## Deliver a hit to a victim node. `victim` only needs `take_damage(amount,
## source)`; `apply_shock` is optional and reported through the returned
## dictionary so the caller (and its test) can see whether the debuff landed.
static func deliver(victim: Node, dist_m: float, source_tag: String = "guard_ranged") -> Dictionary:
	var out: Dictionary = {
		"damage": damage_at_m(dist_m),
		"shock_seconds": SHOCK_SECONDS,
		"shock_applied": false,
		"damage_type": SHOCK_DAMAGE_TYPE,
		"hud_icon": SHOCK_HUD_ICON,
	}
	if victim == null:
		return out
	if victim.has_method("take_damage"):
		victim.call("take_damage", float(out["damage"]), source_tag)
	if victim.has_method(PLAYER_SHOCK_METHOD):
		victim.call(PLAYER_SHOCK_METHOD, SHOCK_SECONDS, SHOCK_DAMAGE_REDUCTION_MULTIPLIER)
		out["shock_applied"] = true
	return out
