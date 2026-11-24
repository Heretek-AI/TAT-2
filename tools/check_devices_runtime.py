#!/usr/bin/env python3
"""Validate game/data/generated/gameplay/devices_runtime.json.

Exit 0 only when the emitted device layer matches the audited authored counts
and its internal graph is consistent:

* 2,095 devices: guildhall 903, old_manor 1,164, ftue 26, thieves_den 2
* 6,005 deduped detector->action edges, 613 nulls dropped, 90 duplicates,
  0 unresolved
* 1,475 device->power edges, 15 power sources, 7 distinct feeding supplies
* exact whole-game family counts (turrets 478, alarm eyes 181, beams 330,
  plates 581, noise alarms 136, ward_slow 80, ward_blocker 63, goo 135,
  vault doors 12, wall supplies 15, junctions 11, acoustic portals 285)

It also checks id uniqueness/format, action and power references, transform
shapes (basis orthonormal + det +1, unit scale for behaviour devices) and the
presence of the required per-instance overrides. Generated JSON is gitignored;
this checker is the repo's gate for the producer.
"""

from __future__ import annotations

import json
import math
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEVICES_JSON = (
    ROOT / "game" / "data" / "generated" / "gameplay" / "devices_runtime.json"
)

SCHEMA = "tat2.devices_runtime/1"
EXPECTED_TOTAL = 2095
EXPECTED_BY_MAP = {"guildhall": 903, "old_manor": 1164, "ftue": 26, "thieves_den": 2}

# family -> (loaded, whole_game)
EXPECTED_FAMILIES = {
    "turret": (478, 478),
    "alarm_eye": (181, 181),
    "light_beam": (330, 330),
    "pressure_plate": (581, 581),
    "noise_alarm": (136, 136),
    "ward_slow": (80, 80),
    "ward_blocker": (63, 63),
    "goo_pipe": (135, 135),
    "vault_door": (12, 12),
    "power_wall": (15, 15),
    "power_switch": (59, 57),  # 2 are level-instance duplicates in FTUE_Geometry
    "junction": (11, 11),
    "acoustic_portal": (14, 285),  # only 14 of the 285 authored portals are loaded
    "magnetic_lock": (12, 12),  # component-only data family
}

EXPECTED_ACTIONS = {
    "edges": 6005,
    "nulls_dropped": 613,
    "duplicates_dropped": 90,
    "unresolved": 0,
}
EXPECTED_POWER = {
    "edges": 1475,
    "sources": 15,
    "source_names_feeding_devices": 7,
    "unresolved": 0,
}

ID_RE = re.compile(r"^[a-z_]+/[A-Za-z0-9_]+:[A-Za-z0-9_]+$")
BASIS_TOL = 1e-3
SCALE_TOL = 1e-4

REQUIRED_DEVICE_KEYS = {
    "id",
    "map",
    "sublevel",
    "actor",
    "class",
    "family",
    "pos",
    "basis",
    "scale",
    "params",
    "power",
    "actions",
    "breakable",
}


class Check:
    def __init__(self):
        self.failures: list[str] = []
        self.checks = 0

    def expect(self, condition: bool, message: str) -> None:
        self.checks += 1
        if not condition:
            self.failures.append(message)

    def equal(self, have, want, label: str) -> None:
        self.expect(have == want, f"{label}: have {have!r}, want {want!r}")


def basis_ok(basis) -> tuple[bool, bool]:
    if not isinstance(basis, list) or len(basis) != 9:
        return False, False
    try:
        values = [float(v) for v in basis]
    except (TypeError, ValueError):
        return False, False
    cols = [values[0:3], values[3:6], values[6:9]]
    orthonormal = True
    for col in cols:
        if abs(math.sqrt(sum(v * v for v in col)) - 1.0) > BASIS_TOL:
            orthonormal = False
    for i in range(3):
        for j in range(i + 1, 3):
            if abs(sum(cols[i][k] * cols[j][k] for k in range(3))) > BASIS_TOL:
                orthonormal = False
    det = (
        cols[0][0] * (cols[1][1] * cols[2][2] - cols[1][2] * cols[2][1])
        - cols[0][1] * (cols[1][0] * cols[2][2] - cols[1][2] * cols[2][0])
        + cols[0][2] * (cols[1][0] * cols[2][1] - cols[1][1] * cols[2][0])
    )
    return orthonormal, det > 0.0


def unit_scale(scale) -> bool:
    return (
        isinstance(scale, list)
        and len(scale) == 3
        and all(abs(float(v) - 1.0) <= SCALE_TOL for v in scale)
    )


def main() -> int:
    check = Check()
    if not DEVICES_JSON.is_file():
        print(f"DEVICES_RUNTIME FAIL: missing {DEVICES_JSON}")
        print("  run: python3 tools/parse_devices.py")
        return 1
    try:
        data = json.loads(DEVICES_JSON.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        print(f"DEVICES_RUNTIME FAIL: cannot parse {DEVICES_JSON}: {exc}")
        return 1

    check.equal(data.get("schema"), SCHEMA, "schema")
    maps = data.get("maps")
    check.expect(isinstance(maps, dict), "maps must be an object")
    if not isinstance(maps, dict):
        return report(check)
    stats = data.get("stats")
    check.expect(isinstance(stats, dict), "stats must be an object")
    if not isinstance(stats, dict):
        return report(check)

    all_devices = []
    authored_scale_count = 0
    ids_by_map: dict[str, set[str]] = {}
    counts_by_map: dict[str, int] = {}
    family_loaded = Counter()

    for map_id, map_data in maps.items():
        check.expect(isinstance(map_data, dict), f"map {map_id} must be an object")
        if not isinstance(map_data, dict):
            continue
        devices = map_data.get("devices")
        sources = map_data.get("power_sources", [])
        check.expect(isinstance(devices, list), f"map {map_id}.devices must be a list")
        check.expect(
            isinstance(sources, list), f"map {map_id}.power_sources must be a list"
        )
        devices = devices if isinstance(devices, list) else []
        sublevels = map_data.get("sublevels")
        check.expect(
            isinstance(sublevels, list) and bool(sublevels),
            f"map {map_id}.sublevels must be a non-empty list",
        )
        counts_by_map[map_id] = len(devices)
        ids_by_map[map_id] = set()
        for device in devices:
            check.expect(
                isinstance(device, dict), f"map {map_id}: device must be an object"
            )
            if not isinstance(device, dict):
                continue
            all_devices.append(device)
            device_id = str(device.get("id", ""))
            check.expect(
                REQUIRED_DEVICE_KEYS <= set(device),
                f"{device_id}: missing keys {sorted(REQUIRED_DEVICE_KEYS - set(device))}",
            )
            check.expect(
                bool(ID_RE.match(device_id)), f"bad device id format: {device_id!r}"
            )
            check.expect(
                device_id not in ids_by_map[map_id],
                f"duplicate device id in {map_id}: {device_id}",
            )
            ids_by_map[map_id].add(device_id)
            check.equal(device.get("map"), map_id, f"{device_id}: map")
            check.expect(
                isinstance(device.get("sublevel"), str) and device["sublevel"],
                f"{device_id}: sublevel must be a non-empty string",
            )
            check.expect(
                device_id.endswith(":" + str(device.get("actor", ""))),
                f"{device_id}: id must end with :ActorName",
            )
            check.expect(
                device_id.startswith(f"{map_id}/"),
                f"{device_id}: id must start with {map_id}/",
            )
            check.equal(
                device_id,
                f"{map_id}/{device.get('sublevel')}:{device.get('actor')}",
                f"{device_id}: id must be <map>/<sublevel_stem>:<ActorName>",
            )
            family = str(device.get("family", ""))
            check.expect(
                family in EXPECTED_FAMILIES, f"{device_id}: unknown family {family}"
            )
            family_loaded[family] += 1
            pos = device.get("pos")
            check.expect(
                isinstance(pos, list) and len(pos) == 3,
                f"{device_id}: pos must be 3 floats",
            )
            orthonormal, det_positive = basis_ok(device.get("basis"))
            check.expect(orthonormal, f"{device_id}: basis is not orthonormal")
            check.expect(det_positive, f"{device_id}: basis determinant is not +1")
            check.expect(
                unit_scale(device.get("scale")),
                f"{device_id}: device scale must be [1,1,1]",
            )
            if family == "acoustic_portal" and "authored_scale" in (
                device.get("params") or {}
            ):
                authored_scale_count += 1
            power = device.get("power")
            check.expect(
                isinstance(power, dict), f"{device_id}: power must be an object"
            )
            if isinstance(power, dict):
                check.expect(
                    "source" in power and "require" in power, f"{device_id}: power keys"
                )
            actions = device.get("actions")
            check.expect(
                isinstance(actions, list), f"{device_id}: actions must be a list"
            )
            check.expect("breakable" in device, f"{device_id}: breakable field missing")
            check.expect(
                device.get("breakable") is None, f"{device_id}: breakable must be null"
            )

    # ---- counts ----------------------------------------------------------
    check.equal(len(all_devices), EXPECTED_TOTAL, "total devices")
    check.equal(
        authored_scale_count, 14, "acoustic portals with preserved authored scale"
    )
    check.equal(stats.get("devices_total"), EXPECTED_TOTAL, "stats.devices_total")
    for map_id, want in EXPECTED_BY_MAP.items():
        check.equal(counts_by_map.get(map_id, 0), want, f"{map_id} device count")
        check.equal(stats.get("by_map", {}).get(map_id), want, f"stats {map_id} count")
    check.equal(sum(counts_by_map.values()), EXPECTED_TOTAL, "sum of per-map counts")

    stats_families = stats.get("families", {})
    check.expect(isinstance(stats_families, dict), "stats.families must be an object")
    for family, (want_loaded, want_whole) in EXPECTED_FAMILIES.items():
        if family != "magnetic_lock":  # component-only family, no device records
            check.equal(
                family_loaded.get(family, 0), want_loaded, f"{family}: loaded devices"
            )
        entry = stats_families.get(family)
        check.expect(isinstance(entry, dict), f"stats.families.{family} missing")
        if not isinstance(entry, dict):
            continue
        check.equal(entry.get("loaded"), want_loaded, f"stats {family}.loaded")
        check.equal(entry.get("whole_game"), want_whole, f"stats {family}.whole_game")
        by_class = entry.get("by_class_whole_game", {})
        check.expect(isinstance(by_class, dict), f"stats {family}.by_class_whole_game")
        if isinstance(by_class, dict) and by_class:
            check.equal(
                sum(int(v) for v in by_class.values()),
                want_whole,
                f"stats {family}.by_class_whole_game sum",
            )

    # ---- actions ---------------------------------------------------------
    action_stats = stats.get("actions", {})
    check.expect(isinstance(action_stats, dict), "stats.actions must be an object")
    for key, want in EXPECTED_ACTIONS.items():
        check.equal(action_stats.get(key), want, f"stats.actions.{key}")
    action_targets = 0
    for device in all_devices:
        device_id = device["id"]
        map_id = device["map"]
        for target in device.get("actions", []) or []:
            action_targets += 1
            check.expect(
                isinstance(target, str) and bool(ID_RE.match(target)),
                f"{device_id}: bad action id {target!r}",
            )
            check.expect(
                target in ids_by_map.get(map_id, set()),
                f"{device_id}: unresolved action target {target}",
            )
    check.equal(action_targets, EXPECTED_ACTIONS["edges"], "emitted action edge count")

    # ---- power -----------------------------------------------------------
    power_stats = stats.get("power", {})
    check.expect(isinstance(power_stats, dict), "stats.power must be an object")
    for key, want in EXPECTED_POWER.items():
        check.equal(power_stats.get(key), want, f"stats.power.{key}")
    power_edges = 0
    devices_with_source = 0
    source_records = 0
    feeding_names = set()
    for map_id, map_data in maps.items():
        source_ids = {s.get("id") for s in map_data.get("power_sources", [])}
        source_records += len(source_ids)
        for src in map_data.get("power_sources", []):
            check.expect(
                bool(ID_RE.match(str(src.get("id", "")))),
                f"bad power source id {src.get('id')!r}",
            )
            if int(src.get("feeds_devices", 0)) > 0:
                feeding_names.add(src.get("actor"))
        for device in map_data.get("devices", []):
            power = device.get("power") or {}
            source = power.get("source")
            edge_count = power.get("edges")
            check.expect(
                isinstance(edge_count, int) and edge_count >= 0,
                f"{device['id']}: power.edges must be an int",
            )
            power_edges += int(edge_count or 0)
            if source:
                devices_with_source += 1
                check.expect(
                    source in source_ids,
                    f"{device['id']}: power source {source} not in map power_sources",
                )
            if int(edge_count or 0) > 0:
                check.expect(
                    bool(source), f"{device['id']}: power edges without a source id"
                )
    check.equal(source_records, EXPECTED_POWER["sources"], "power source record count")
    check.equal(power_edges, EXPECTED_POWER["edges"], "authored power edge count")
    check.equal(
        power_stats.get("devices_with_source"),
        devices_with_source,
        "stats.power.devices_with_source",
    )
    check.equal(
        len(feeding_names),
        EXPECTED_POWER["source_names_feeding_devices"],
        "distinct feeding power names",
    )

    # ---- params / authored values ---------------------------------------
    turret_variants = {"base", "90", "180", "360", "180_triggered"}
    alarm_variants = {
        "base",
        "long_narrow",
        "long_wide",
        "short_narrow",
        "short_wide",
        "long_ftue",
    }
    vault_variants = {"single", "single_starts_open", "double", "double_always_open"}
    noise_overrides = noise_nulls = 0
    ward_zones = Counter()
    cone_overrides = 0
    for device in all_devices:
        family = device["family"]
        params = device.get("params") or {}
        if family == "turret":
            check.expect(
                params.get("variant") in turret_variants,
                f"{device['id']}: turret variant",
            )
            if "State" in params:
                check.expect(
                    "starts_on" in params, f"{device['id']}: starts_on with State"
                )
        elif family == "alarm_eye":
            check.expect(
                params.get("variant") in alarm_variants,
                f"{device['id']}: alarm variant",
            )
            if "OuterConeAngle" in params:
                cone_overrides += 1
        elif family in ("ward_slow", "ward_blocker"):
            if "ZoneSize" in params:
                zone = params["ZoneSize"]
                check.expect(
                    isinstance(zone, dict) and {"X", "Y", "Z"} <= set(zone),
                    f"{device['id']}: ZoneSize must have X/Y/Z",
                )
                ward_zones[family] += 1
        elif family == "noise_alarm":
            value = params.get("_triggeringDuration")
            if value is None:
                noise_nulls += 1
            else:
                noise_overrides += 1
                check.equal(value, 0.5, f"{device['id']}: noise trigger override")
        elif family == "vault_door":
            check.expect(
                params.get("variant") in vault_variants,
                f"{device['id']}: vault variant",
            )
            check.expect(
                "magnetic_lock" in params, f"{device['id']}: magnetic lock param"
            )
            if "_lockConfig" in params:
                check.expect(
                    isinstance(params["_lockConfig"], dict),
                    f"{device['id']}: _lockConfig must be an object",
                )
        elif family in ("power_wall", "power_switch"):
            if "_state" in params:
                check.expect(
                    isinstance(params["_state"], dict),
                    f"{device['id']}: _state must be an object",
                )
        elif family == "light_beam":
            for key in ("BeamLength", "BaseRotation", "MaxDistanceToFireBeam"):
                if key in params:
                    check.expect(
                        params[key] is not None,
                        f"{device['id']}: {key} must be a value",
                    )

    check.equal(noise_overrides, 11, "noise alarm authored trigger overrides")
    check.equal(noise_nulls, 125, "noise alarm null trigger fallbacks")
    check.equal(cone_overrides, 181, "alarm eye cone overrides")
    check.equal(ward_zones["ward_slow"], 80, "ward_slow ZoneSize overrides")
    check.equal(ward_zones["ward_blocker"], 52, "ward_blocker ZoneSize overrides")

    # ---- family defaults -------------------------------------------------
    defaults = stats.get("family_defaults", {})
    check.expect(isinstance(defaults, dict), "stats.family_defaults must be an object")
    if isinstance(defaults, dict):
        beam = defaults.get("light_beam", {})
        check.equal(beam.get("trigger_seconds"), 0.5, "beam trigger")
        check.equal(beam.get("reset_seconds"), 0.2, "beam reset")
        check.equal(beam.get("radius_cm"), 10.0, "beam radius")
        check.equal(beam.get("axis"), "+X", "beam axis")
        plate = defaults.get("pressure_plate", {})
        check.equal(plate.get("trigger_seconds"), 1.5, "plate trigger")
        check.equal(plate.get("reset_seconds"), 0.2, "plate reset")
        check.equal(plate.get("overlap_radius_cm"), 45.0, "plate overlap radius")
        check.equal(plate.get("plate_extent_cm"), [45.0, 45.0, 3.0], "plate extent")
        check.equal(plate.get("timeline_seconds"), 0.2, "plate timeline")
        check.equal(
            ((plate.get("damage") or {}).get("DamageAmount") or {}).get("Value"),
            10.0,
            "plate damage",
        )
        check.equal(
            ((plate.get("damage") or {}).get("DamageType") or {}).get("TagName"),
            "DamageType.Physical",
            "plate damage type",
        )
        check.equal(
            ((plate.get("hearing_stim") or {}).get("max_range_cm")),
            1000.0,
            "plate hearing range",
        )
        turret = defaults.get("turret", {})
        check.equal(
            turret.get("fire_interval_seconds_by_difficulty"),
            [1.0, 0.5, 0.33],
            "turret fire",
        )
        check.equal(
            turret.get("alarm_delay_seconds_by_difficulty"),
            [2.0, 1.0, 0.25],
            "turret alarm",
        )
        check.equal(turret.get("reset_seconds"), 10.0, "turret reset")
        check.equal(
            (turret.get("perception") or {}).get("SightRadius"), 1200.0, "turret sight"
        )
        check.equal(
            ((turret.get("projectile") or {}).get("max_speed_cm_s")),
            4000.0,
            "turret projectile speed",
        )
        alarm = defaults.get("alarm_eye", {})
        check.equal(
            alarm.get("alarm_delay_seconds_by_difficulty"),
            [2.0, 1.0, 0.2],
            "alarm delay",
        )
        check.equal(alarm.get("swivel_angle_deg"), 45.0, "alarm swivel angle")
        check.equal(alarm.get("swivel_seconds"), 10.0, "alarm swivel seconds")
        check.equal(alarm.get("swivel_pause_seconds"), 2.0, "alarm swivel pause")
        check.equal(
            ((alarm.get("stim") or {}).get("max_range_cm")), 2500.0, "alarm stim range"
        )
        ward = defaults.get("ward_slow", {})
        check.equal(ward.get("slow_multiplier"), 0.25, "ward slow multiplier")
        check.equal(ward.get("slow_seconds"), 6.0, "ward slow duration")
        check.equal(ward.get("magic_damage"), 50.0, "ward magic damage")
        check.equal(ward.get("WardImmunityDuration"), 1.0, "ward immunity")
        blocker = defaults.get("ward_blocker", {})
        check.equal(blocker.get("blocks_player_only"), True, "ward blocker player only")
        check.equal(blocker.get("ImpactFXCooldown"), 1.0, "ward blocker cooldown")
        noise = defaults.get("noise_alarm", {})
        check.equal(
            ((noise.get("stim") or {}).get("max_range_cm")), 1500.0, "noise stim range"
        )
        goo = defaults.get("goo_pipe", {})
        check.equal(goo.get("auto_off_seconds"), 7.0, "goo auto off")
        check.equal(goo.get("puddle_radius_cm"), 200.0, "goo puddle radius")
        check.equal(goo.get("puddle_spawn_interval_seconds"), 2.5, "goo spawn interval")
        check.equal(goo.get("puddle_trace_cone_deg"), 45.0, "goo cone")
        vault = defaults.get("vault_door", {})
        check.equal(vault.get("slide_seconds"), 8.0, "vault slide seconds")
        check.equal(vault.get("can_lockpick"), False, "vault lockpick")
        variants = vault.get("variants", {})
        check.equal(
            (variants.get("BP_VaultDoor_Sliding_C") or {}).get("SlideDistance_cm"),
            -300.0,
            "vault single slide",
        )
        check.equal(
            (variants.get("BP_VaultDoor_SlidingDouble_C") or {}).get(
                "SlideDistance_cm"
            ),
            -275.0,
            "vault double slide",
        )
        power = defaults.get("power_wall", {})
        check.equal(power.get("starts_on"), True, "power wall starts on")
        check.equal(
            power.get("auto_reset_seconds_options"),
            [0, 10, 30],
            "power wall auto reset",
        )

        # Metric fallbacks (Godot metres) — the values the runtime consumes.
        beam_metric = beam.get("metric", {})
        check.equal(beam_metric.get("trigger_seconds"), 0.5, "beam metric trigger")
        check.equal(beam_metric.get("reset_seconds"), 0.2, "beam metric reset")
        check.equal(beam_metric.get("radius_m"), 0.1, "beam metric radius")
        check.equal(beam_metric.get("axis"), "+X", "beam metric axis")
        # CDO serializes 5000 cm, i.e. 50 m. The task summary says "5 m";
        # the authored value wins (do not fabricate a 10x conversion).
        check.equal(
            beam_metric.get("max_distance_default_m"), 50.0, "beam metric max distance"
        )
        plate_metric = plate.get("metric", {})
        check.equal(plate_metric.get("overlap_radius_m"), 0.45, "plate metric radius")
        check.equal(
            plate_metric.get("plate_extent_m"),
            [0.45, 0.45, 0.03],
            "plate metric extent",
        )
        check.equal(plate_metric.get("timeline_seconds"), 0.2, "plate metric timeline")
        check.equal(
            (plate_metric.get("damage") or {}).get("amount"),
            10.0,
            "plate metric damage",
        )
        check.equal(
            (plate_metric.get("damage") or {}).get("type"),
            "DamageType.Physical",
            "plate metric damage type",
        )
        check.equal(
            (plate_metric.get("hearing_stim") or {}).get("range_m"),
            10.0,
            "plate metric stim range",
        )
        turret_metric = turret.get("metric", {})
        check.equal(turret_metric.get("sight_m"), 12.0, "turret metric sight")
        check.equal(turret_metric.get("lose_sight_m"), 12.0, "turret metric lose sight")
        check.equal(turret_metric.get("half_fov_deg"), 15.0, "turret metric half FOV")
        check.equal(
            turret_metric.get("pov_backward_m"), 0.5, "turret metric POV backward"
        )
        check.equal(turret_metric.get("near_clip_m"), 1.5, "turret metric near clip")
        check.equal(turret_metric.get("max_age_seconds"), 5.0, "turret metric max age")
        check.equal(
            (turret_metric.get("projectile") or {}).get("speed_m_s"),
            40.0,
            "turret metric projectile speed",
        )
        check.equal(
            (turret_metric.get("projectile") or {}).get("life_seconds"),
            30.0,
            "turret metric projectile life",
        )
        alarm_metric = alarm.get("metric", {})
        check.equal(
            alarm_metric.get("alarm_delay_seconds_by_difficulty"),
            [2.0, 1.0, 0.2],
            "alarm metric delay",
        )
        check.equal(
            alarm_metric.get("swivel_angle_deg"), 45.0, "alarm metric swivel angle"
        )
        check.equal(alarm_metric.get("swivel_seconds"), 10.0, "alarm metric swivel")
        check.equal(alarm_metric.get("swivel_pause_seconds"), 2.0, "alarm metric pause")
        check.equal(
            (alarm_metric.get("stim") or {}).get("range_m"),
            25.0,
            "alarm metric stim range",
        )
        ward_metric = ward.get("metric", {})
        check.equal(ward_metric.get("slow_multiplier"), 0.25, "ward metric slow")
        check.equal(ward_metric.get("slow_seconds"), 6.0, "ward metric duration")
        check.equal(ward_metric.get("magic_damage"), 50.0, "ward metric damage")
        check.equal(ward_metric.get("immunity_seconds"), 1.0, "ward metric immunity")
        check.equal(
            ward_metric.get("initially_active"), False, "ward metric initially active"
        )
        blocker_metric = blocker.get("metric", {})
        check.equal(
            blocker_metric.get("blocks_player_only"),
            True,
            "blocker metric player only",
        )
        check.equal(
            blocker_metric.get("impact_cooldown_seconds"),
            1.0,
            "blocker metric cooldown",
        )
        noise_metric = noise.get("metric", {})
        check.equal(
            (noise_metric.get("stim") or {}).get("range_m"),
            15.0,
            "noise metric stim range",
        )
        check.equal(noise_metric.get("trigger_seconds"), 0.5, "noise metric trigger")
        goo_metric = goo.get("metric", {})
        check.equal(goo_metric.get("auto_off_seconds"), 7.0, "goo metric auto off")
        check.equal(goo_metric.get("puddle_radius_m"), 2.0, "goo metric radius")
        check.equal(
            goo_metric.get("spawn_interval_seconds"), 2.5, "goo metric interval"
        )
        check.equal(
            (goo_metric.get("velocity_m_s") or {}).get("min"),
            2.5,
            "goo metric min velocity",
        )
        check.equal(
            (goo_metric.get("velocity_m_s") or {}).get("max"),
            6.0,
            "goo metric max velocity",
        )
        check.equal(goo_metric.get("trace_cone_deg"), 45.0, "goo metric cone")
        vault_metric = vault.get("metric", {})
        check.equal(
            (vault_metric.get("slide_distance_m") or {}).get("BP_VaultDoor_Sliding_C"),
            -3.0,
            "vault metric single slide",
        )
        check.equal(
            (vault_metric.get("slide_distance_m") or {}).get(
                "BP_VaultDoor_SlidingDouble_C"
            ),
            -2.75,
            "vault metric double slide",
        )
        check.equal(vault_metric.get("can_lockpick"), False, "vault metric lockpick")
        panel_metric = power.get("metric", {})
        check.equal(panel_metric.get("starts_on"), True, "power wall metric starts on")
        check.equal(
            panel_metric.get("auto_reset_seconds_options"),
            [0, 10, 30],
            "power wall metric auto reset",
        )

    # ---- param stats (authored ranges the review cites) -------------------
    param_stats = stats.get("param_stats", {})
    check.expect(isinstance(param_stats, dict), "stats.param_stats must be an object")
    if isinstance(param_stats, dict):
        beam_stats = param_stats.get("light_beam") or {}
        guild = beam_stats.get("BeamLength_cm_guildhall") or {}
        check.equal(guild.get("count"), 133, "guildhall BeamLength count")
        check.equal(guild.get("min"), 250.0, "guildhall BeamLength min")
        check.equal(guild.get("max"), 1995.194458, "guildhall BeamLength max")
        check.expect(
            abs(float(guild.get("p50") or 0) - 774.824) < 0.01,
            f"guildhall BeamLength p50: {guild.get('p50')} != 774.824",
        )
        loaded = beam_stats.get("BeamLength_cm_all_loaded") or {}
        check.equal(loaded.get("count"), 328, "all-loaded BeamLength count")
        overrides = beam_stats.get("MaxDistanceToFireBeam_cm_overrides") or {}
        check.equal(overrides.get("count"), 50, "MaxDistanceToFireBeam override count")

    # ---- transforms ------------------------------------------------------
    transforms = stats.get("transforms", {})
    check.expect(isinstance(transforms, dict), "stats.transforms must be an object")
    if isinstance(transforms, dict):
        check.equal(transforms.get("non_orthonormal_basis"), 0, "non-orthonormal bases")
        check.equal(transforms.get("det_not_positive"), 0, "negative determinants")
        check.equal(transforms.get("non_unit_scale"), 0, "non-unit behaviour scales")
        check.equal(
            transforms.get("non_unit_scale_any"),
            14,
            "non-unit authored scales (normalized data-only portals)",
        )
        check.equal(
            transforms.get("level_instance_expanded"),
            4,
            "level-instance expanded devices",
        )
        check.equal(
            transforms.get("matched_generated"),
            EXPECTED_TOTAL,
            "generated transform matches",
        )
        check.equal(
            transforms.get("generated_crosscheck_mismatches"),
            0,
            "generated level device-set cross-check mismatches",
        )

    return report(check)


def report(check: Check) -> int:
    if check.failures:
        print(
            f"DEVICES_RUNTIME FAIL: {len(check.failures)} of {check.checks} checks failed"
        )
        for failure in check.failures:
            print(f"  - {failure}")
        return 1
    print(f"DEVICES_RUNTIME PASS: {check.checks} checks, 0 failures")
    return 0


if __name__ == "__main__":
    sys.exit(main())
