#!/usr/bin/env python3
"""
Parse UE5 TAT weather presets into Godot-friendly JSON.

Reads every extracted `BP_WeatherPreset_*.json` under
`extracted/json/Art/Environment/Weather/` and writes one normalized file per
preset to `game/data/generated/weather/<preset_id>.json`, plus a
`map_weather.json` that maps each playable map id to its most appropriate
preset (derived from the map's TATWeatherManager PresetOverrides where
possible, otherwise from the preset that names the map).

Colours keep UE's two serialized shapes distinct:
  - LinearColor: float channels with A == 1.0; HDR values above 1.0 are kept.
  - FColor:      integer 0-255 channels with A == 255; divided by 255.
When the extracted JSON declares a property's struct type, that declaration
decides; the serialized-shape check is only a fallback.
Presets inherit from parent presets, so `parse_preset` walks the
BlueprintGeneratedClass Super / CDO Template chain and merges child over
parent before normalizing.

No numbers are invented: fields absent from the source JSON become null and
the Godot side leaves the corresponding environment property untouched.

The post-process block also carries the authored auto-exposure chain
(`auto_exposure_method`, `min_brightness`, `max_brightness`, `speed_up`,
`speed_down`, `bias_curve`) consumed by `game/src/core/auto_exposure.gd`.
Base authors -3.5/+1.0/0.5/V1; Base_Skybox overrides Min -10.0, Bias 0.0 and
the V3 curve, and every shipped night preset inherits Base_Skybox.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EX_ROOT = ROOT / "extracted" / "json"
EX_WEATHER = EX_ROOT / "Art" / "Environment" / "Weather"
EX_MAPS = EX_ROOT / "Maps"
OUT_DIR = ROOT / "game" / "data" / "generated" / "weather"

# Preset id -> canonical gameplay weather tag (ManualMatch of UE Weather.Type.*).
# Only tags observed in extracted map data get an entry; anything else is null.
TAG_BY_PRESET = {
    "dense_fog": "Weather.Type.DenseFog",
    "dense_fog_old_manor": "Weather.Type.DenseFog",
    "gloomy": "Weather.Type.Gloomy",
    "stormy": "Weather.Type.Stormy",
    "heavy_rain": "Weather.Type.HeavyRain",
    "midnight_clear": "Weather.Type.MidnightClear",
    "midnight_clear_thieves_den": "Weather.Type.MidnightClear",
    "midnight_clear_mission_lobby": "Weather.Type.MidnightClear",
    "sunrise_clear_skybox": "Weather.Type.SunriseClear",
}

# Playable map id -> persistent-level dump that owns its TATWeatherManager.
MANAGER_BY_MAP = {
    "old_manor": "OldManor/OldManor_P.json",
    "guildhall": "Guildhall/Guildhall_P.json",
    "thieves_den": "ThievesDenTest/ThievesDenTest_P.json",
    "jaspering_hall": "FTUE/FTUE_P.json",
    "main_menu": "MissionLobby/MissionLobby_P.json",
}

# Hub maps whose TATWeatherManager authors no PresetOverrides. The weather type
# is then whatever the level's own dressing says it is, so count the authored
# actors that only exist for one weather state. Guildhall_P's streets carry
# curated puddles + a landscape puddle layer (wet ground), 27 named local fog
# volumes (haze on the main entrance / parade square / roofs / periphery), a
# cloud-mask generator with four composited masks (overcast) and authored
# BP_MoonShape cards + BP_Light_SpotFakeMoonFills spots (a visible moon).
# That combination is BP_WeatherPreset_Gloomy: EnableRain implicitly on
# (RainIntensity 1.0), GroundWetness 1.0, FogDensity 0.16, Stars 0 and the
# MI_Sky_HeavyRain overcast dome with the moon still visible. HeavyRain is
# excluded by its own authored `Moon visibility = False`; Stormy is excluded by
# its near-black zenith (0.068) and GroundWetness 0.5.
EVIDENCE_DUMPS = {
    "wet_ground": ("Guildhall/Guildhall_PeripheryA.json", "BP_Puddle_C"),
    "haze_volumes": (
        "Guildhall/Guildhall_LocalVolumetric.json",
        "BP_LocalFog_Volume_C",
    ),
    "cloud_masks": ("Guildhall/Guildhall_Clouds.json", "BP_CloudMask_Object_C"),
    "moon_actors": (
        "Guildhall/Guildhall_LightingNoGameplay.json",
        "BP_MoonShape_C",
    ),
}
EVIDENCE_PRESET_BY_MAP = {
    "guildhall": {
        "preset": "gloomy",
        "weather_tag": "Weather.Type.Gloomy",
        "requires": ("wet_ground", "haze_volumes", "cloud_masks", "moon_actors"),
    },
}


def camel_to_snake(name: str) -> str:
    s = re.sub(r"(.)([A-Z][a-z]+)", r"\1_\2", name)
    s = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", s)
    return re.sub(r"_+", "_", s).lower()


def _norm_color(v, struct_type: str | None = None) -> list | None:
    """UE colour dict -> [r, g, b] floats, or None.

    A declared struct type wins: FColor (Color) is integer 0-255 channels
    divided by 255, LinearColor is float channels with A == 1.0 and may exceed
    1.0 for HDR, so those are kept. Without a declaration, fall back to the
    serialized shape: FColor has integer channels and A == 255.
    """
    if not isinstance(v, dict):
        return None
    if not all(k in v for k in ("R", "G", "B")):
        return None
    try:
        r, g, b = float(v["R"]), float(v["G"]), float(v["B"])
    except (TypeError, ValueError):
        return None
    channels = (v["R"], v["G"], v["B"])
    if struct_type == "Color" or (
        struct_type is None
        and v.get("A") == 255
        and all(isinstance(c, int) and not isinstance(c, bool) for c in channels)
    ):
        r, g, b = r / 255.0, g / 255.0, b / 255.0
    return [round(r, 4), round(g, 4), round(b, 4)]


def _norm_vec(v, n: int = 3):
    """UE {X,Y,Z[,W]} dict -> list of floats, or None."""
    if not isinstance(v, dict) or not all(k in v for k in ("X", "Y", "Z")[:n]):
        return None
    try:
        return [round(float(v[k]), 4) for k in (["X", "Y", "Z", "W"][:n])]
    except (TypeError, ValueError):
        return None


def _num(v):
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return round(float(v), 6)
    return None


def _ref_path(v):
    """UE object reference dict -> asset path string, or None."""
    if isinstance(v, dict):
        p = v.get("ObjectPath") or v.get("AssetPathName")
        if isinstance(p, str) and p:
            return p.split(".")[0]
    return None


def _aem_method(v):
    """EAutoExposureMethod enum -> 'AEM_Basic' (the serialized enum's tail)."""
    if isinstance(v, str) and v:
        return v.split("::", 1)[1] if "::" in v else v
    return None


def _curve_ref_name(v):
    """CurveFloat object ref -> curve asset name (the `curves.json` key)."""
    if isinstance(v, dict):
        obj = v.get("ObjectName")
        if isinstance(obj, str):
            match = re.search(r"'([^']+)'", obj)
            if match:
                return match.group(1)
    return None


def _find(exports: list, want_type: str, want_name: str = "", prefer_name: str = ""):
    """Properties of the best export of want_type.

    Construction-script nodes carry no Properties; they are skipped whenever a
    non-empty candidate exists. The canonical `prefer_name` export wins over
    the first non-empty one. Returns {} when nothing usable matches.
    """
    fallback = {}
    for e in exports:
        if e.get("Type") != want_type:
            continue
        name = str(e.get("Name", ""))
        if want_name and want_name not in name:
            continue
        props = e.get("Properties") or {}
        if not props:
            continue
        if prefer_name and name == prefer_name:
            return props
        if not fallback:
            fallback = props
    return fallback


def _cdo_export(exports: list) -> dict:
    for e in exports:
        if str(e.get("Name", "")).startswith("Default__"):
            return e
    return {}


def _declared_structs(exports: list) -> dict:
    """Property name -> struct type declared in the class's ChildProperties."""
    out = {}
    for e in exports:
        if e.get("Type") != "BlueprintGeneratedClass":
            continue
        for prop in e.get("ChildProperties") or []:
            name = prop.get("Name")
            ref = prop.get("Struct")
            if isinstance(ref, dict):
                ref = ref.get("ObjectName")
            if not isinstance(name, str) or not isinstance(ref, str):
                continue
            match = re.search(r"'([^']+)'", ref)
            if match:
                out[name] = match.group(1)
    return out


def _cdo_color(cdo: dict, structs: dict, key: str) -> list | None:
    """CDO colour, using the property's declared struct type when known."""
    return _norm_color(cdo.get(key), structs.get(key))


def _package_from_ref(ref) -> str | None:
    """UE object reference -> package path without the trailing .<index>."""
    if not isinstance(ref, dict):
        return None
    p = ref.get("ObjectPath")
    if not isinstance(p, str) or not p:
        return None
    return re.sub(r"\.\d+$", "", p)


def _package_path(package: str) -> Path | None:
    """UE package path -> extracted JSON file inside EX_WEATHER, or None."""
    prefix = "/Game/"
    if not package.startswith(prefix):
        return None
    candidate = (EX_ROOT / (package[len(prefix) :] + ".json")).resolve()
    try:
        candidate.relative_to(EX_WEATHER.resolve())
    except ValueError:
        return None
    return candidate


def _parent_package(exports: list) -> str | None:
    """Parent preset package named by the class Super or CDO Template."""
    for e in exports:
        if e.get("Type") == "BlueprintGeneratedClass":
            package = _package_from_ref(e.get("Super"))
            if package:
                return package
            break
    for e in exports:
        if str(e.get("Name", "")).startswith("Default__"):
            return _package_from_ref(e.get("Template"))
    return None


def preset_chain(path: Path) -> list:
    """Exports for path and its Blueprint parents, child first, root last."""
    chain = []
    seen = set()
    current = path
    while current is not None and current not in seen:
        seen.add(current)
        exports = json.loads(current.read_text())
        chain.append(exports)
        package = _parent_package(exports)
        if package is None:
            break
        parent = _package_path(package)
        if parent is None or not parent.is_file():
            print(
                "warning: %s: cannot resolve parent preset package %s under %s; "
                "inherited fields will be null" % (path.name, package, EX_WEATHER),
                file=sys.stderr,
            )
            break
        current = parent
    return chain


def _merge_dicts(parent: dict, child: dict) -> dict:
    """Recursively merge property dicts; child values win over parent ones."""
    merged = dict(parent)
    for key, value in child.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = _merge_dicts(merged[key], value)
        else:
            merged[key] = value
    return merged


def parse_preset(path: Path) -> dict:
    chain = preset_chain(path)
    preset_id = camel_to_snake(path.stem.replace("BP_WeatherPreset_", ""))
    structs = {}
    for exports in reversed(chain):
        structs.update(_declared_structs(exports))

    cdo = {}
    dl = {}
    fog = {}
    sky = {}
    pp = {}
    cloud = {}
    rain_niagara = {}
    # Chain is child-first; merge root-ward so child properties win and
    # inherited ones fill the gaps.
    for exports in reversed(chain):
        cdo = _merge_dicts(cdo, _cdo_export(exports).get("Properties") or {})
        dl = _merge_dicts(
            dl,
            _find(
                exports,
                "DirectionalLightComponent",
                prefer_name="PrimaryDirectionalLightComponent",
            ),
        )
        fog = _merge_dicts(fog, _find(exports, "ExponentialHeightFogComponent"))
        sky = _merge_dicts(sky, _find(exports, "SkyLightComponent"))
        pp = _merge_dicts(pp, _find(exports, "PostProcessComponent"))
        cloud = _merge_dicts(
            cloud, _find(exports, "VolumetricCloudComponent", "VolumetricCloud")
        )
        rain_niagara = _merge_dicts(
            rain_niagara, _find(exports, "NiagaraComponent", "Rain")
        )

    pps = pp.get("Settings") if isinstance(pp.get("Settings"), dict) else {}

    rot = (
        dl.get("RelativeRotation")
        if isinstance(dl.get("RelativeRotation"), dict)
        else {}
    )

    rain_intensity = _num(cdo.get("RainIntensity"))
    if "EnableRain" in cdo:
        enable_rain = bool(cdo.get("EnableRain"))
    elif rain_intensity is not None:
        # No explicit flag (e.g. Gloomy ships RainIntensity=1.0 without the
        # flag): treat a non-trivial intensity as rain, ~zero as dry.
        enable_rain = rain_intensity >= 0.5
    else:
        enable_rain = False

    sky_material = _ref_path(cdo.get("Sky material"))
    own_cdo = _cdo_export(chain[0]).get("Properties") or {}
    own_cloud = _find(chain[0], "VolumetricCloudComponent", "VolumetricCloud")
    # The preset's own CDO slot wins when it authors one; otherwise its own
    # component material beats an inherited CDO value, which would shadow it.
    cloud_material = (
        _ref_path(own_cdo.get("VolumetricCloudMaterial"))
        or _ref_path(own_cloud.get("Material"))
        or _ref_path(cdo.get("VolumetricCloudMaterial"))
        or _ref_path(cloud.get("Material"))
    )

    return {
        "preset": preset_id,
        "source": str(path.relative_to(ROOT)),
        "weather_tag": TAG_BY_PRESET.get(preset_id),
        "moon": {
            "visible": cdo.get("Moon visibility")
            if isinstance(cdo.get("Moon visibility"), bool)
            else None,
            "size": _num(cdo.get("Moon Size")),
            "distance_offset": _num(cdo.get("Moon Distance Offset")),
            "brightness": _num(cdo.get("Moon Brightness")),
            "sun_brightness": _num(cdo.get("Sun brightness")),
            "color": _cdo_color(cdo, structs, "Sun / Moon Color"),
            "emissive": _cdo_color(cdo, structs, "MoonlightEmissiveColor"),
            "overall_color": _cdo_color(cdo, structs, "Overall Color"),
        },
        "sky": {
            "material": sky_material,
            "overall_color": _cdo_color(cdo, structs, "Overall Color"),
            "cloud_color": _cdo_color(cdo, structs, "Cloud color"),
            "cloud_opacity": _num(cdo.get("Cloud opacity")),
            "stars_brightness": _num(cdo.get("Stars brightness")),
            "horizon_color": _cdo_color(cdo, structs, "Horizon color"),
            "zenith_color": _cdo_color(cdo, structs, "Zenith Color"),
            "volumetric_cloud_material": cloud_material,
            "volumetric_cloud_visible": cdo.get("VolumetricCloudVisibility")
            if isinstance(cdo.get("VolumetricCloudVisibility"), bool)
            else None,
            "local_volumetric_fog_density": _num(cdo.get("LocalVolumetricFogDensity")),
            "intensity": _num(sky.get("Intensity")),
            "light_color": _norm_color(sky.get("LightColor")),
            "cubemap": _ref_path(sky.get("Cubemap")),
        },
        "fog": {
            "density": _num(fog.get("FogDensity")),
            "height_falloff": _num(fog.get("FogHeightFalloff")),
            "inscattering": _norm_color(fog.get("FogInscatteringLuminance")),
            "directional_inscattering": _norm_color(
                fog.get("DirectionalInscatteringLuminance")
            ),
            "volumetric_extinction_scale": _num(
                fog.get("VolumetricFogExtinctionScale")
            ),
            "volumetric_distance": _num(fog.get("VolumetricFogDistance")),
        },
        "moon_light": {
            "intensity": _num(dl.get("Intensity")),
            "color": _norm_color(dl.get("LightColor")),
            "pitch": _num(rot.get("Pitch")),
            "yaw": _num(rot.get("Yaw")),
            "roll": _num(rot.get("Roll")),
            "source_angle": _num(dl.get("LightSourceAngle")),
        },
        "postprocess": {
            "saturation": (_norm_vec(pps.get("ColorSaturation")) or [None])[0]
            if pps.get("ColorSaturation") is not None
            else None,
            "midtones_saturation": (
                _norm_vec(pps.get("ColorSaturationMidtones")) or [None]
            )[0]
            if pps.get("ColorSaturationMidtones") is not None
            else None,
            "gain": _norm_vec(pps.get("ColorGain")),
            "gain_midtones": _norm_vec(pps.get("ColorGainMidtones")),
            "gain_highlights": _norm_vec(pps.get("ColorGainHighlights")),
            "gain_shadows": _norm_vec(pps.get("ColorGainShadows")),
            "gamma_highlights": _norm_vec(pps.get("ColorGammaHighlights")),
            "bloom_intensity": _num(pps.get("BloomIntensity")),
            "auto_exposure_bias": _num(pps.get("AutoExposureBias")),
            # P4.1a authored AEM_Basic (the merged chain: Base authors
            # -3.5/+1.0/0.5/V1, Base_Skybox overrides Min -10.0, Bias 0.0 and
            # V3, so the shipped Gloomy preset is -10/+1, 0.2/2.0, 0, V3).
            # Consumers: game/src/core/auto_exposure.gd; citations in
            # build/qa/w9/re-b1-exposure.md §1.
            "auto_exposure_method": _aem_method(pps.get("AutoExposureMethod")),
            "min_brightness": _num(pps.get("AutoExposureMinBrightness")),
            "max_brightness": _num(pps.get("AutoExposureMaxBrightness")),
            "speed_up": _num(pps.get("AutoExposureSpeedUp")),
            "speed_down": _num(pps.get("AutoExposureSpeedDown")),
            "bias_curve": _curve_ref_name(pps.get("AutoExposureBiasCurve")),
            "vignette_intensity": _num(pps.get("VignetteIntensity")),
            "white_temp": _num(pps.get("WhiteTemp")),
            "film_slope": _num(pps.get("FilmSlope")),
            "film_toe": _num(pps.get("FilmToe")),
        },
        "rain": {
            "enabled": enable_rain,
            "intensity": rain_intensity,
            "ground_wetness": _num(cdo.get("GroundWetness")),
            "niagara_asset": _ref_path(
                (rain_niagara.get("Asset") or {})
                if isinstance(rain_niagara.get("Asset"), dict)
                else {}
            ),
        },
    }


def preset_name_from_asset(asset_path: str) -> str | None:
    """'/Game/.../BP_WeatherPreset_X.BP_WeatherPreset_X_C' -> 'x' id."""
    if not asset_path:
        return None
    base = asset_path.split(".")[0].split("/")[-1]
    if not base.startswith("BP_WeatherPreset_"):
        return None
    return camel_to_snake(base.replace("BP_WeatherPreset_", ""))


def manager_overrides(map_dump: Path) -> dict:
    """weather tag -> preset id from a map's TATWeatherManager PresetOverrides."""
    try:
        exports = json.loads(map_dump.read_text())
    except (OSError, json.JSONDecodeError):
        return {}
    for e in exports:
        if e.get("Type") == "TATWeatherManager":
            out = {}
            for o in (e.get("Properties") or {}).get("PresetOverrides", []) or []:
                tag = (
                    ((o.get("Key") or {}).get("TagName"))
                    if isinstance(o.get("Key"), dict)
                    else None
                )
                asset = (
                    ((o.get("Value") or {}).get("AssetPathName"))
                    if isinstance(o.get("Value"), dict)
                    else None
                )
                pid = preset_name_from_asset(asset or "")
                if tag and pid:
                    out[tag] = pid
            return out
    return {}


def count_exports(dump: Path, type_name: str) -> int:
    """Exports of `type_name` in a level dump (0 when it is missing/unreadable)."""
    try:
        exports = json.loads(dump.read_text())
    except (OSError, json.JSONDecodeError):
        return 0
    return sum(1 for e in exports if e.get("Type") == type_name)


def authored_evidence(map_id: str) -> dict:
    """Count the weather-only actors the hub level authors (see EVIDENCE_DUMPS)."""
    if map_id != "guildhall":
        return {}
    return {
        key: count_exports(EX_MAPS / rel, type_name)
        for key, (rel, type_name) in EVIDENCE_DUMPS.items()
    }


def evidence_preset(map_id: str, evidence: dict) -> str | None:
    """Preset implied by authored level dressing, or None when it is absent."""
    rule = EVIDENCE_PRESET_BY_MAP.get(map_id)
    if rule is None:
        return None
    if all(int(evidence.get(key, 0)) > 0 for key in rule["requires"]):
        return rule["preset"]
    return None


def choose_preset(
    map_id: str, overrides: dict, evidence: dict | None = None
) -> tuple[str, str, str]:
    """Return (preset_id, weather_tag, reason) for a playable map id."""
    if map_id == "old_manor" and "Weather.Type.DenseFog" in overrides:
        return (
            overrides["Weather.Type.DenseFog"],
            "Weather.Type.DenseFog",
            "OldManor_P PresetOverrides Weather.Type.DenseFog; preset is named for OldManor",
        )
    if overrides:
        uniq = set(overrides.values())
        if len(uniq) == 1:
            # The manager routes every weather type to a single preset, so the
            # preset's own identity is the weather tag.
            pid = next(iter(uniq))
            return (
                pid,
                TAG_BY_PRESET.get(pid),
                "map TATWeatherManager routes every weather type to this single preset",
            )
        if "Weather.Type.MidnightClear" in overrides:
            return (
                overrides["Weather.Type.MidnightClear"],
                "Weather.Type.MidnightClear",
                "map TATWeatherManager PresetOverrides entry for Weather.Type.MidnightClear",
            )
    # No usable overrides: read the authored dressing before falling back.
    authored = evidence or {}
    implied = evidence_preset(map_id, authored)
    if implied is not None:
        rule = EVIDENCE_PRESET_BY_MAP[map_id]
        return (
            implied,
            rule["weather_tag"],
            "map manager defines no PresetOverrides; authored level dressing "
            "implies %s (%s)"
            % (
                implied,
                ", ".join(
                    "%s=%d" % (key, int(authored.get(key, 0)))
                    for key in rule["requires"]
                ),
            ),
        )
    # No usable overrides and no authored dressing: fall back to the preset
    # that names the map.
    named = {"guildhall": "midnight_clear"}
    if map_id in named:
        return (
            named[map_id],
            TAG_BY_PRESET.get(named[map_id]),
            "map manager defines no PresetOverrides and the level authors no "
            "weather dressing; MidnightClear is the canonical night-clear weather",
        )
    raise ValueError("no preset choice for map %s" % map_id)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    preset_files = sorted(EX_WEATHER.glob("BP_WeatherPreset_*.json"))
    if not preset_files:
        raise SystemExit("no presets found under %s" % EX_WEATHER)
    known_ids = set()
    for path in preset_files:
        data = parse_preset(path)
        known_ids.add(data["preset"])
        (OUT_DIR / (data["preset"] + ".json")).write_text(
            json.dumps(data, indent=2) + "\n"
        )
    print("Parsed %d weather presets -> %s" % (len(preset_files), OUT_DIR))

    maps = {}
    for map_id, rel in MANAGER_BY_MAP.items():
        overrides = manager_overrides(EX_MAPS / rel)
        evidence = authored_evidence(map_id)
        preset_id, tag, reason = choose_preset(map_id, overrides, evidence)
        if preset_id not in known_ids:
            raise SystemExit(
                "chosen preset '%s' for map '%s' has no parsed JSON"
                % (preset_id, map_id)
            )
        maps[map_id] = {
            "preset": preset_id,
            "weather_tag": tag,
            "source_map": "extracted/json/Maps/%s" % rel,
            "reason": reason,
            "manager_overrides": overrides,
        }
        if evidence:
            maps[map_id]["authored_evidence"] = evidence
        print("map %-14s -> preset %-32s tag %s" % (map_id, preset_id, tag))
        print("    reason: %s" % reason)

    # Fix source_preset to the exact on-disk filename (CamelCase is ambiguous).
    stem_by_id = {}
    for path in preset_files:
        stem_by_id[camel_to_snake(path.stem.replace("BP_WeatherPreset_", ""))] = (
            path.name
        )
    for map_id in maps:
        pid = maps[map_id]["preset"]
        maps[map_id]["source_preset"] = (
            "extracted/json/Art/Environment/Weather/%s" % stem_by_id[pid]
        )

    (OUT_DIR / "map_weather.json").write_text(
        json.dumps({"maps": maps}, indent=2) + "\n"
    )
    print("Wrote %s" % (OUT_DIR / "map_weather.json"))


if __name__ == "__main__":
    main()
