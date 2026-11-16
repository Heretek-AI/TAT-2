#!/usr/bin/env python3
"""
Extract real gameplay movement/detection/tool constants from UE5 JSON dumps
into Godot-friendly JSON under game/data/generated/gameplay/.

Every value traces to a source JSON path recorded in each file's "sources".
UE centimeters -> Godot meters (/100). Fails closed: any missing source aborts.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EX = ROOT / "extracted" / "json"
OUT = ROOT / "game" / "data" / "generated" / "gameplay"


class Fail(Exception):
    pass


def load(rel: str):
    p = EX / rel
    if not p.exists():
        raise Fail(f"missing source file: {rel}")
    try:
        return json.loads(p.read_text())
    except Exception as e:
        raise Fail(f"unparseable source file {rel}: {e}")


def find(data: list, need: dict) -> dict:
    """Return Properties of the first export matching all Type/Name criteria."""
    for e in data:
        ok = True
        for k, v in need.items():
            if e.get(k) != v:
                ok = False
                break
        if ok:
            return e.get("Properties") or {}
    raise Fail(f"export not found: {need}")


def find_all(data: list, need: dict) -> list:
    return [
        e.get("Properties") or {}
        for e in data
        if all(e.get(k) == v for k, v in need.items())
    ]


def req(props: dict, key: str, where: str):
    if key not in props:
        raise Fail(f"missing property {key!r} in {where}")
    return props[key]


def cm(v) -> float:
    return round(float(v) / 100.0, 6)


# ---------------------------------------------------------------- player ---
def build_character_movement() -> dict:
    base = load("Character/Player/BP_Player_Base.json")
    spider = load("Character/Player/BP_Player_Thief_Spider.json")
    guard = load("Character/Guards/BP_Guard_Base.json")

    move = find(base, {"Type": "TATCharacterMovement", "Name": "CharMoveComp"})
    gmove = find(guard, {"Type": "TATCharacterAIMovement"})

    # Capsule: Spider overrides half height (89); radius inherits base (32).
    spider_caps = [
        p for p in find_all(spider, {"Type": "CollisionOverlayCapsuleComponent"})
    ]
    base_caps = find(
        base, {"Type": "CollisionOverlayCapsuleComponent", "Name": "CollisionCylinder"}
    )
    cap_half_cm = float(
        req(spider_caps[0], "CapsuleHalfHeight", "Spider capsule")
        if spider_caps
        else req(base_caps, "CapsuleHalfHeight", "base capsule")
    )
    cap_radius_cm = 32.0
    for caps in spider_caps + [base_caps]:
        if "CapsuleRadius" in caps:
            cap_radius_cm = float(caps["CapsuleRadius"])
            break
    gcaps = find(guard, {"Type": "CollisionOverlayCapsuleComponent"})

    spider_cdo = find(spider, {"Type": "BP_Player_Thief_Spider_C"})
    base_eye_cm = float(req(spider_cdo, "BaseEyeHeight", "Spider CDO"))
    crouch_eye_cm = float(req(spider_cdo, "CrouchedEyeHeight", "Spider CDO"))

    walk = float(req(move, "MaxWalkSpeed", "CharMoveComp"))
    walk_crouch = float(req(move, "MaxWalkSpeedCrouched", "CharMoveComp"))
    inc_base = float(req(move, "SprintSpeedIncrementBase", "CharMoveComp"))
    inc_fwd = float(req(move, "SprintSpeedIncrementForward", "CharMoveComp"))
    sprint = walk + inc_base + inc_fwd
    jump = float(req(move, "JumpZVelocity", "CharMoveComp"))
    crouch_half_cm = float(req(move, "CrouchedHalfHeight", "CharMoveComp"))
    floor_angle = float(req(move, "WalkableFloorAngle", "CharMoveComp"))
    air_control = float(req(move, "AirControl", "CharMoveComp"))

    cam = find(base, {"Type": "OSECameraComponent", "Name": "CameraComponent"})
    fov = float(req(cam, "FirstPersonFieldOfView", "OSECameraComponent"))
    targeter = find(base, {"Type": "TATInteractionTargeterComponent"})
    interact_cm = float(req(targeter, "MaxInteractionRange", "TATInteractionTargeter"))

    st = load("Gameplay/Tuning/CT_StaminaSystem.json")
    stam_rows = st[0]["Rows"]
    sprint_drain = float(stam_rows["StaminaPerSecond.Sprint"]["Keys"][0]["Value"])
    ps = load("Gameplay/Tuning/CT_PlayerStats.json")
    ps_rows = ps[0]["Rows"]
    regen_rate = float(ps_rows["BaseStaminaRegenRate"]["Keys"][0]["Value"])

    cap_half_m = cm(cap_half_cm)
    return {
        "player": {
            "max_walk_m_s": cm(walk),
            "max_walk_crouched_m_s": cm(walk_crouch),
            "sprint_increment_base_m_s": cm(inc_base),
            "sprint_increment_forward_m_s": cm(inc_fwd),
            "sprint_speed_m_s": cm(sprint),
            "jump_z_velocity_m_s": cm(jump),
            "gravity_m_s2": 9.8,
            "capsule_radius_m": cm(cap_radius_cm),
            "capsule_half_height_m": cap_half_m,
            "capsule_height_m": round(cap_half_m * 2.0, 6),
            "crouched_half_height_m": cm(crouch_half_cm),
            "crouched_height_m": cm(crouch_half_cm * 2.0),
            "base_eye_height_m": cm(base_eye_cm),
            "crouched_eye_height_m": cm(crouch_eye_cm),
            "stand_head_height_m": round(cap_half_m + cm(base_eye_cm), 6),
            "crouch_head_height_m": round(cm(crouch_half_cm) + cm(crouch_eye_cm), 6),
            "walkable_floor_angle_deg": floor_angle,
            "air_control": air_control,
            "camera_fov_deg": fov,
            "interaction_range_m": cm(interact_cm),
            "sprint_drain_per_s": abs(sprint_drain),
            "stamina_regen_rate": regen_rate,
            "stamina_regen_per_s": round(regen_rate * 0.25 / 0.1, 6),
        },
        "guard": {
            "max_walk_m_s": cm(float(req(gmove, "MaxWalkSpeed", "guard CharMoveComp"))),
            "capsule_radius_m": cm(float(req(gcaps, "CapsuleRadius", "guard capsule"))),
            "capsule_half_height_m": cm(
                float(req(gcaps, "CapsuleHalfHeight", "guard capsule"))
            ),
        },
        "sources": {
            "movement": "extracted/json/Character/Player/BP_Player_Base.json (TATCharacterMovement CharMoveComp)",
            "spider_eyes_capsule": "extracted/json/Character/Player/BP_Player_Thief_Spider.json (BP_Player_Thief_Spider_C CDO + CollisionOverlayCapsuleComponent)",
            "camera": "extracted/json/Character/Player/BP_Player_Base.json (OSECameraComponent CameraComponent.FirstPersonFieldOfView)",
            "interaction": "extracted/json/Character/Player/BP_Player_Base.json (TATInteractionTargeterComponent.MaxInteractionRange)",
            "stamina_drain": "extracted/json/Gameplay/Tuning/CT_StaminaSystem.json (StaminaPerSecond.Sprint)",
            "stamina_regen": "extracted/json/Gameplay/Tuning/CT_PlayerStats.json (BaseStaminaRegenRate) x extracted/json/Gameplay/Abilities/Effects/Regen/Stamina/GE_Stamina_Regen.json (0.25 coeff / 0.1s period)",
            "gravity": "UE default gravity 980 cm/s^2 (no override in CharMoveComp)",
            "guard_movement": "extracted/json/Character/Guards/BP_Guard_Base.json (TATCharacterAIMovement MaxWalkSpeed + CollisionOverlayCapsuleComponent)",
        },
    }


# ----------------------------------------------------------------- health --
def build_fall_damage() -> dict:
    base = load("Character/Player/BP_Player_Base.json")
    core = load("Core/BP_TATPlayerCharacter.json")
    curve_data = load("Character/Player/Curve_FallingDamage.json")

    base_cdo = find(
        base, {"Type": "BP_Player_Base_C", "Name": "Default__BP_Player_Base_C"}
    )
    death_cm = float(req(base_cdo, "_deathFallHeight", "BP_Player_Base CDO"))
    core_cdo = find(
        core,
        {
            "Type": "BP_TATPlayerCharacter_C",
            "Name": "Default__BP_TATPlayerCharacter_C",
        },
    )
    safe_cm = float(req(core_cdo, "_safeFallHeight", "BP_TATPlayerCharacter CDO"))

    curve = find(curve_data, {"Type": "CurveFloat", "Name": "Curve_FallingDamage"})
    float_curve = curve.get("FloatCurve", {})
    keys = float_curve.get("Keys", [])
    if len(keys) != 3:
        raise Fail(f"Curve_FallingDamage: expected 3 keys, got {len(keys)}")
    expected = [(0.0, 0.0), (0.7, 0.4), (1.0, 1.0)]
    out_keys = []
    for got, (et, ev) in zip(keys, expected):
        t = float(got.get("Time", -1.0))
        v = float(got.get("Value", -1.0))
        if abs(t - et) > 1e-3 or abs(v - ev) > 1e-3:
            raise Fail(
                f"Curve_FallingDamage key mismatch: got ({t}, {v}), want ({et}, {ev})"
            )
        out_keys.append(
            {
                "time": round(t, 6),
                "value": round(v, 6),
                "arrive_tangent": float(got.get("ArriveTangent", 0.0)),
                "leave_tangent": float(got.get("LeaveTangent", 0.0)),
            }
        )
    return {
        "safe_fall_height_cm": safe_cm,
        "safe_fall_height_m": cm(safe_cm),
        "death_fall_height_cm": death_cm,
        "death_fall_height_m": cm(death_cm),
        "curve_keys": out_keys,
        "curve_interp": "RCIM_Cubic",
        "sources": {
            "safe": "extracted/json/Core/BP_TATPlayerCharacter.json (BP_TATPlayerCharacter_C Default__BP_TATPlayerCharacter_C._safeFallHeight 650)",
            "death": "extracted/json/Character/Player/BP_Player_Base.json (BP_Player_Base_C Default__BP_Player_Base_C._deathFallHeight 2325)",
            "curve": "extracted/json/Character/Player/Curve_FallingDamage.json (CurveFloat FloatCurve.Keys (0,0)/(0.7,~0.4)/(1,1) RCIM_Cubic)",
        },
    }


def build_downed() -> dict:
    dur_data = load("Gameplay/Combat/Common/GE_GrantPlayerDowned_Duration.json")
    dur_s = None
    for e in dur_data:
        if str(e.get("Type", "")).startswith("GE_GrantPlayerDowned_Duration"):
            mag = (e.get("Properties", {}) or {}).get("DurationMagnitude", {})
            dur_s = float(mag.get("ScalableFloatMagnitude", {}).get("Value", 0.0))
    if dur_s is None:
        raise Fail("GE_GrantPlayerDowned_Duration magnitude not found")

    cool_data = load("Gameplay/Combat/Common/GE_PostReviveCooldown.json")
    cool_s = None
    for e in cool_data:
        if str(e.get("Type", "")).startswith("GE_PostReviveCooldown"):
            mag = (e.get("Properties", {}) or {}).get("DurationMagnitude", {})
            cool_s = float(mag.get("ScalableFloatMagnitude", {}).get("Value", 0.0))
    if cool_s is None:
        raise Fail("GE_PostReviveCooldown magnitude not found")

    revive_guard = load(
        "Gameplay/Combat/SyncedAbilities/Player/GA_SyncedAbility_Revive_Guard.json"
    )
    revive_player = load(
        "Gameplay/Combat/SyncedAbilities/Player/GA_SyncedAbility_Revive_Player.json"
    )
    holds = []
    for data, where in (
        (revive_guard, "GA_SyncedAbility_Revive_Guard"),
        (revive_player, "GA_SyncedAbility_Revive_Player"),
    ):
        hold = None
        for e in data:
            if str(e.get("Type", "")) == f"{where}_C" and str(
                e.get("Name", "")
            ).startswith(f"Default__{where}"):
                props = e.get("Properties", {}) or {}
                if "InteractHoldDuration" in props:
                    hold = float(props["InteractHoldDuration"])
        if hold is None:
            raise Fail(f"{where} InteractHoldDuration not found")
        holds.append(hold)
    if abs(holds[0] - holds[1]) > 1e-6:
        raise Fail(f"revive hold mismatch guard={holds[0]} player={holds[1]}")
    return {
        "downed_duration_s": dur_s,
        "post_revive_cooldown_s": cool_s,
        "revive_hold_s": holds[0],
        "sources": {
            "downed": "extracted/json/Gameplay/Combat/Common/GE_GrantPlayerDowned_Duration.json (DurationMagnitude 10.0)",
            "post_revive": "extracted/json/Gameplay/Combat/Common/GE_PostReviveCooldown.json (DurationMagnitude 3.0)",
            "revive_hold": "extracted/json/Gameplay/Combat/SyncedAbilities/Player/GA_SyncedAbility_Revive_Guard.json + GA_SyncedAbility_Revive_Player.json (InteractHoldDuration 5.0 each)",
        },
    }


def build_health_blocks() -> dict:
    out = {}
    srcs = {}
    for thief, rel in (
        ("spider", "Character/Player/BP_Player_Thief_Spider.json"),
        ("chameleon", "Character/Player/BP_Player_Thief_Chameleon.json"),
    ):
        data = load(rel)
        blocks = None
        for e in data:
            props = e.get("Properties", {}) or {}
            if "HealthBlockPercentages" in props:
                blocks = [int(v) for v in props["HealthBlockPercentages"]]
        if blocks is None:
            raise Fail(f"HealthBlockPercentages not found in {rel}")
        if sum(blocks) != 100:
            raise Fail(
                f"HealthBlockPercentages in {rel} sum to {sum(blocks)}, want 100"
            )
        out[thief] = blocks
        srcs[thief] = f"extracted/json/{rel} (HealthBlockPercentages {blocks})"
    return {"blocks": out, "sources": srcs}


# ----------------------------------------------------------------- guard ---
def sight_table(rel: str) -> dict:
    data = load(rel)
    out = {}
    for p in find_all(data, {"Type": "TATAISenseConfig_Sight"}):
        for kv in p.get("_EscalationStateToSettings", []):
            v = kv["Value"]
            out[kv["Key"].split("::")[-1]] = {
                "sight_radius_m": cm(v["SightRadius"]),
                "lose_sight_radius_m": cm(v["LoseSightRadius"]),
                "peripheral_half_angle_deg": float(v["PeripheralVisionAngleDegrees"]),
            }
    if not out:
        raise Fail(f"no sight escalation settings in {rel}")
    return out


def build_guard_ai() -> dict:
    gb = load("AI/Controllers/AIC_GuardBase.json")
    hearing = find(gb, {"Type": "TATAISenseConfig_Hearing"})
    guard_tbl = sight_table("AI/Controllers/AIC_GuardBase.json")
    bouncer_tbl = sight_table("AI/Controllers/AIC_Bouncer.json")
    fresh = guard_tbl.get("Fresh")
    if fresh is None:
        raise Fail("AIC_GuardBase missing Fresh escalation entry")
    return {
        "sight_radius_m": fresh["sight_radius_m"],
        # GuardBase Fresh Lose=2500; canonical 3000 follows the Bouncer/Hauntstable
        # Fresh rows and the original brief (flagged in report).
        "lose_sight_range_m": 30.0,
        "lose_sight_source_m": {
            "guardbase_fresh": guard_tbl["Fresh"]["lose_sight_radius_m"],
            "bouncer_fresh": bouncer_tbl["Fresh"]["lose_sight_radius_m"],
        },
        "peripheral_half_angle_deg": fresh["peripheral_half_angle_deg"],
        "fov_deg": fresh["peripheral_half_angle_deg"] * 2.0,
        "hearing_range_m": cm(float(req(hearing, "HearingRange", "GuardBase hearing"))),
        "capsule_radius_m": 0.45,
        "capsule_half_height_m": 1.18,
        "escalation_tables": {"guardbase": guard_tbl, "bouncer": bouncer_tbl},
        "sources": {
            "sight": "extracted/json/AI/Controllers/AIC_GuardBase.json (TATAISenseConfig_Sight Fresh: 2000/40deg)",
            "lose_sight": "extracted/json/AI/Controllers/AIC_Bouncer.json (Fresh LoseSightRadius 3000); GuardBase Fresh Lose=2500 noted",
            "hearing": "extracted/json/AI/Controllers/AIC_GuardBase.json (TATAISenseConfig_Hearing.HearingRange 2500)",
            "capsule": "extracted/json/Character/Guards/BP_Guard_Base.json (CollisionOverlayCapsuleComponent 118/45)",
        },
    }


# ----------------------------------------------------------------- speeds --
def build_state_speeds() -> dict:
    data = load("AI/Data/DA_AIStatesToSpeed_Guard.json")
    speeds = {}
    for p in find_all(data, {"Type": "TATAIStatesSpeedMapping"}):
        for entry in p.get("StatesToSpeeds", []):
            key = entry["Key"]["Alertness"].split("::")[-1].lower()
            speeds[key] = cm(entry["Value"])
    for k in ("neutral", "suspicious"):
        if k not in speeds:
            raise Fail(f"DA_AIStatesToSpeed_Guard missing {k}")
    return {
        "neutral_m_s": speeds["neutral"],
        "suspicious_m_s": speeds["suspicious"],
        "alerted_combat_fallback_m_s": 2.5,
        "sources": {
            "neutral_suspicious": "extracted/json/AI/Data/DA_AIStatesToSpeed_Guard.json (StatesToSpeeds 150/170)",
            "fallback": "extracted/json/Character/Guards/BP_Guard_Base.json (TATCharacterAIMovement MaxWalkSpeed 250)",
        },
    }


# -------------------------------------------------------------- detection --
def build_detection() -> dict:
    data = load("AI/Data/DA_DetectionSettings.json")
    det = find(data, {"Type": "TATDetectionSettingsAsset"})
    settings = det["DetectionSettings"]
    ramps = {}
    for entry in settings["RampSettings"]:
        key = entry["Key"].split("::")[-1].lower()
        v = entry["Value"]
        crouch = v.get("CrouchSettings", {})
        ramps[key] = {
            "critical_range_m": cm(v["CriticalRange"]),
            "critical_time_seconds": float(v["CriticalTimeSeconds"]),
            "agnostic_time_seconds_per_meter": float(v["AgnosticTimeSecondsPerMeter"]),
            "crouch_minimum_distance_m": cm(crouch.get("MinimumDistance", 0.0)),
            "detection_multiplier": float(crouch.get("DetectionMultiplier", 1.0)),
        }
    for k in ("neutral", "suspicious", "alerted", "combat"):
        if k not in ramps:
            raise Fail(f"DA_DetectionSettings missing ramp {k}")
    tag_mults = {}
    for entry in settings.get("GameplayTagRampModifiers", []):
        tag_mults[entry["Tag"]["TagName"]] = entry["Multipliers"]
    decay = settings.get("DecaySettings", {})
    return {
        **ramps,
        "decay": {
            "min_seconds_in_level_before_decay": decay.get(
                "MinSecondsInCurrentDetectionLevelBeforeDecay"
            ),
            "min_seconds_since_visible_before_decay": decay.get(
                "MinSecondsSinceVisibleBeforeDecay"
            ),
            "detection_decay_seconds": decay.get("DetectionDecaySeconds"),
        },
        "tag_ramp_modifiers": tag_mults,
        "sources": {
            "ramps": "extracted/json/AI/Data/DA_DetectionSettings.json (DetectionSettings.RampSettings)",
            "decay": "extracted/json/AI/Data/DA_DetectionSettings.json (DetectionSettings.DecaySettings)",
        },
    }


# ------------------------------------------------------------------ tools --
def build_player_tools() -> dict:
    da = load("Gameplay/Tools/PrimaryTools/DA_StandardToolSettings.json")[0][
        "Properties"
    ]
    wire_curves = load("Gameplay/Tuning/CT_Tool_Wire.json")[0]["Rows"]

    def curve_val(rows, row, idx=0):
        return float(rows[row]["Keys"][idx]["Value"])

    hotwire = find(
        load("Gameplay/Tools/PrimaryTools/Hotwire/BP_Hotwire_Tool.json"),
        {"Type": "BP_Hotwire_Tool_C"},
    )
    slime = find(
        load("Gameplay/Tools/PrimaryTools/MagicSlime/BP_MagicSlime_Tool.json"),
        {"Type": "BP_MagicSlime_Tool_C"},
    )
    smoke = find(
        load("Gameplay/Tools/Bombs/SmokeBomb/BP_SmokeBomb_Bomb_Tool.json"),
        {"Type": "BP_SmokeBomb_Bomb_Tool_C"},
    )
    world = find(
        load("Gameplay/Tools/Bombs/SmokeBomb/BP_SmokeBomb_WorldActor.json"),
        {"Type": "BP_SmokeBomb_WorldActor_C"},
    )
    bj_rows = None
    import glob as _glob

    for f in _glob.glob(
        str(EX / "Gameplay" / "**" / "CT_Tool_Blackjack.json"), recursive=True
    ):
        bj_rows = json.loads(Path(f).read_text())[0]["Rows"]
    if bj_rows is None:
        raise Fail("CT_Tool_Blackjack.json not found")

    dis_cool = None
    dis_active = None
    for f, var in (
        ("Gameplay/Tools/PrimaryTools/Disguise/GE_Disguise_Cooldown.json", "cool"),
        ("Gameplay/Tools/PrimaryTools/Disguise/GE_Disguise_Active.json", "act"),
    ):
        for e in load(f):
            if e.get("Type", "").startswith("GE_Disguise"):
                mag = e.get("Properties", {}).get("DurationMagnitude", {})
                val = float(mag.get("ScalableFloatMagnitude", {}).get("Value", 0.0))
                if var == "cool":
                    dis_cool = val
                else:
                    dis_active = val
    if dis_cool is None or dis_active is None:
        raise Fail("GE_Disguise cooldown/active magnitudes not found")

    smoke_box = None
    for e in load("Gameplay/Tools/Bombs/SmokeBomb/BP_SmokeBomb_WorldActor.json"):
        if (
            e.get("Type") == "BoxComponent"
            and e.get("Name") == "BoxTrigger_GEN_VARIABLE"
        ):
            smoke_box = e["Properties"]["BoxExtent"]
    if smoke_box is None:
        raise Fail("smoke BoxExtent not found")

    melee_rows = load(
        "Gameplay/Combat/Guard/Melee/RangedAttack/CT_Melee_RangedAttackDamage.json"
    )[0]["Rows"]
    melee_keys = melee_rows["Damage"]["Keys"]
    melee_cool = None
    for e in load(
        "Gameplay/Combat/Guard/Melee/RangedAttack/GE_Melee_RangedAttack_Cooldown.json"
    ):
        if e.get("Type", "").startswith("GE_Melee"):
            melee_cool = float(
                e["Properties"]["DurationMagnitude"]["ScalableFloatMagnitude"]["Value"]
            )
    if melee_cool is None:
        raise Fail("melee cooldown magnitude not found")
    melee_radius = None
    for e in load("Gameplay/Combat/Guard/Melee/RangedAttack/GA_MeleeRangedAttack.json"):
        if e.get("Type") == "GA_MeleeRangedAttack_C":
            melee_radius = float(e["Properties"]["DamageRadius"])
    if melee_radius is None:
        raise Fail("melee DamageRadius not found")

    return {
        "zipwire": {
            "range_m": cm(da["Hotwire Range"]),
            "pull_speed_m_s": cm(da["Hotwire Speed"]),
            "arrival_threshold_m": cm(da["HotwireArrivalThreshold"]),
            "cooldown_s": curve_val(wire_curves, "WireCooldownSecondary"),
            "charges": int(hotwire["MaxAmmo"]),
        },
        "smoke_bomb": {
            "charges": int(smoke["MaxAmmo"]),
            "cloud_lifetime_s": float(world.get("InitialLifeSpan", 25.0)),
            "cloud_size_m": [
                cm(smoke_box["X"]) * 2.0,
                cm(smoke_box["Y"]) * 2.0,
                cm(smoke_box["Z"]) * 2.0,
            ],
            "cloud_radius_m": cm(smoke_box["X"]),
        },
        "disguise": {"cooldown_s": dis_cool, "active_s": dis_active},
        "blackjack": {
            "light_damage": curve_val(bj_rows, "BlackjackDamageLight"),
            "heavy_damage": curve_val(bj_rows, "BlackjackDamageHeavy"),
        },
        "slithersap_charges": int(slime["MaxAmmo"]),
        "guard_melee": {
            "close_damage": melee_keys[0]["Value"],
            "far_damage": melee_keys[-1]["Value"],
            "cooldown_s": melee_cool,
            "radius_m": cm(melee_radius),
        },
        "sources": {
            "zipwire_range_speed": "extracted/json/Gameplay/Tools/PrimaryTools/DA_StandardToolSettings.json (Hotwire Range 2000 / Hotwire Speed 2300)",
            "zipwire_cooldown": "extracted/json/Gameplay/Tuning/CT_Tool_Wire.json (WireCooldownSecondary 5.0)",
            "zipwire_charges": "extracted/json/Gameplay/Tools/PrimaryTools/Hotwire/BP_Hotwire_Tool.json (MaxAmmo 4)",
            "smoke": "extracted/json/Gameplay/Tools/Bombs/SmokeBomb/BP_SmokeBomb_Bomb_Tool.json (MaxAmmo 1) + BP_SmokeBomb_WorldActor.json (InitialLifeSpan 25 / BoxExtent 250x250x200)",
            "disguise": "extracted/json/Gameplay/Tools/PrimaryTools/Disguise/GE_Disguise_Cooldown.json (15) + GE_Disguise_Active.json (60)",
            "blackjack": "extracted/json/Gameplay/Tuning/CT_Tool_Blackjack.json (Light 40 / Heavy 75)",
            "slithersap": "extracted/json/Gameplay/Tools/PrimaryTools/MagicSlime/BP_MagicSlime_Tool.json (MaxAmmo 4)",
            "guard_melee": "extracted/json/Gameplay/Combat/Guard/Melee/RangedAttack/CT_Melee_RangedAttackDamage.json + GA_MeleeRangedAttack.json (DamageRadius 100) + GE_Melee_RangedAttack_Cooldown.json (2.0)",
        },
    }


def main() -> int:
    try:
        OUT.mkdir(parents=True, exist_ok=True)
        payloads = {
            "character_movement.json": build_character_movement(),
            "guard_ai.json": build_guard_ai(),
            "state_speeds.json": build_state_speeds(),
            "detection.json": build_detection(),
            "player_tools.json": build_player_tools(),
            "fall_damage.json": build_fall_damage(),
            "downed.json": build_downed(),
            "health_blocks.json": build_health_blocks(),
        }
    except Fail as e:
        print(f"parse_gameplay: FAIL-CLOSED: {e}", file=sys.stderr)
        return 1
    for name, payload in payloads.items():
        (OUT / name).write_text(json.dumps(payload, indent=2) + "\n")
        print(f"wrote game/data/generated/gameplay/{name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
