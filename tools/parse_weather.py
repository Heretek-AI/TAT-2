#!/usr/bin/env python3
"""
Parse UE5 TAT weather presets into Godot-friendly JSON.

Reads every extracted `BP_WeatherPreset_*.json` under
`extracted/json/Art/Environment/Weather/` and writes one normalized file per
preset to `game/data/generated/weather/<preset_id>.json`, plus a
`map_weather.json` that maps each playable map id to its most appropriate
preset (derived from the map's TATWeatherManager PresetOverrides where
possible, otherwise from the preset that names the map).

Colours are normalized to 0-1 floats. UE stores colours in two shapes:
  - LinearColor: {"R": 0.0-1.0 floats, ...}
  - FColor:      {"R/G/B": 0-255 ints, "Hex": ...}
`_norm_color` handles both (any channel > 1.0 means 0-255 ints -> /255).

No numbers are invented: fields absent from the source JSON become null and
the Godot side leaves the corresponding environment property untouched.
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EX_WEATHER = ROOT / "extracted" / "json" / "Art" / "Environment" / "Weather"
EX_MAPS = ROOT / "extracted" / "json" / "Maps"
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


def camel_to_snake(name: str) -> str:
    s = re.sub(r"(.)([A-Z][a-z]+)", r"\1_\2", name)
    s = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", s)
    return re.sub(r"_+", "_", s).lower()


def _norm_color(v) -> list | None:
    """UE colour dict -> [r, g, b] 0-1 floats, or None."""
    if not isinstance(v, dict):
        return None
    if not all(k in v for k in ("R", "G", "B")):
        return None
    try:
        r, g, b = float(v["R"]), float(v["G"]), float(v["B"])
    except (TypeError, ValueError):
        return None
    if max(r, g, b) > 1.0:
        # FColor 0-255 ints.
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


def _find(exports: list, want_type: str, want_name: str = ""):
    for e in exports:
        if e.get("Type") == want_type:
            if not want_name or want_name in str(e.get("Name", "")):
                return e.get("Properties") or {}
    return {}


def parse_preset(path: Path) -> dict:
    exports = json.loads(path.read_text())
    preset_id = camel_to_snake(path.stem.replace("BP_WeatherPreset_", ""))

    cdo = {}
    for e in exports:
        if str(e.get("Name", "")).startswith("Default__"):
            cdo = e.get("Properties") or {}
            break

    dl = _find(exports, "DirectionalLightComponent")
    fog = _find(exports, "ExponentialHeightFogComponent")
    sky = _find(exports, "SkyLightComponent")
    pp = _find(exports, "PostProcessComponent")
    pps = pp.get("Settings") if isinstance(pp.get("Settings"), dict) else {}
    cloud = _find(exports, "VolumetricCloudComponent", "VolumetricCloud")
    rain_niagara = _find(exports, "NiagaraComponent", "Rain")

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
    cloud_material = _ref_path(cdo.get("VolumetricCloudMaterial")) or _ref_path(
        cloud.get("Material")
    )
    if cloud_material is None:
        # Some presets name the material via a different CDO key.
        cloud_material = _ref_path(cdo.get("VolumetricCloudMaterial"))

    return {
        "preset": preset_id,
        "source": str(path.relative_to(ROOT)),
        "weather_tag": TAG_BY_PRESET.get(preset_id),
        "moon": {
            "visible": cdo.get("Moon visibility")
            if isinstance(cdo.get("Moon visibility"), bool)
            else None,
            "size": _num(cdo.get("Moon Size")),
            "brightness": _num(cdo.get("Moon Brightness")),
            "sun_brightness": _num(cdo.get("Sun brightness")),
            "color": _norm_color(cdo.get("Sun / Moon Color")),
            "emissive": _norm_color(cdo.get("MoonlightEmissiveColor")),
            "overall_color": _norm_color(cdo.get("Overall Color")),
        },
        "sky": {
            "material": sky_material,
            "overall_color": _norm_color(cdo.get("Overall Color")),
            "cloud_color": _norm_color(cdo.get("Cloud color")),
            "cloud_opacity": _num(cdo.get("Cloud opacity")),
            "stars_brightness": _num(cdo.get("Stars brightness")),
            "horizon_color": _norm_color(cdo.get("Horizon color")),
            "zenith_color": _norm_color(cdo.get("Zenith Color")),
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


def choose_preset(map_id: str, overrides: dict) -> tuple[str, str, str]:
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
    # No usable overrides: fall back to the preset that names the map.
    named = {"guildhall": "midnight_clear"}
    if map_id in named:
        return (
            named[map_id],
            TAG_BY_PRESET.get(named[map_id]),
            "map manager defines no PresetOverrides, so class default applies; "
            "MidnightClear is the canonical night-clear weather",
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
        preset_id, tag, reason = choose_preset(map_id, overrides)
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
