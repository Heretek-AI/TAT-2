extends RefCounted
## Real weather data extracted from Thick As Thieves.
##
## Loads the normalized presets written by `tools/parse_weather.py` from
## `res://data/generated/weather/` and applies them to a Godot Environment +
## DirectionalLight3D. Every value comes from the game's own
## BP_WeatherPreset_* exports; fields absent from the source JSON are left
## untouched on the live environment (never invented).
##
## Unit conversions (documented, applied in one place so they stay honest):
## - FOG_DENSITY_SCALE = 0.01: UE works in centimetres, Godot in metres. UE
##   FogDensity 0.4 (DenseFog) -> Godot fog_density 0.004. Same 0.01 convention
##   already used for level geometry in tools/parse_tables.py.
## - MOON_ENERGY_SCALE = 10.0, clamped to [0.05, 1.0]: UE night directional
##   intensities sit at 0.01-0.05 lux, roughly two orders of magnitude below a
##   Godot light_energy unit. x10 preserves the inter-preset ratios (Gloomy
##   0.01 -> 0.1 dimmest, Stormy/HeavyRain 0.05 -> 0.5 brightest) while keeping
##   a visibility floor. Presets without an Intensity key are skipped.
## - Moon rotation copies the UE RelativeRotation pitch/yaw/roll straight into
##   rotation_degrees. UE pitch -90 (straight down) equals Godot
##   rotation.x = -90 (the -Z forward axis maps to -Y), so the night presets
##   that hang the moon overhead behave identically.
## - Skylight intensity maps directly to ambient_light_energy, clamped to
##   [0.02, 1.0] (UE night values 0.04-5.0; only the lobby cubemap hits the cap).
## - PostProcess ColorSaturation.X -> adjustment_saturation,
##   ColorGainMidtones.X - 1.0 -> adjustment_brightness (Godot default 0),
##   AutoExposureBias + 1.0 -> tonemap_exposure (Godot default 1.0),
##   BloomIntensity * 0.08 -> glow_intensity (DenseFog 8.0 -> 0.64, matching the
##   previous hand-tuned 0.65). Godot has no vignette/white-temp/film-curve
##   slots, so those parsed values are exposed via getters only.
## - Fog DirectionalInscattering luminance -> fog_sun_scatter (0..1).
## - enable_rain / rain_intensity are exposed for later particle wiring; this
##   module never spawns rain.

const WEATHER_DIR := "res://data/generated/weather"
const MAP_TABLE_PATH := "res://data/generated/weather/map_weather.json"

# UE centimetres -> Godot metres (matches tools/parse_tables.py).
const FOG_DENSITY_SCALE := 0.01
# UE night lux (~0.01-0.05) -> Godot light_energy unit.
const MOON_ENERGY_SCALE := 10.0
const MOON_ENERGY_MIN := 0.05
const MOON_ENERGY_MAX := 1.0
# UE SkyLight intensity -> Godot ambient_light_energy.
const AMBIENT_ENERGY_MIN := 0.02
const AMBIENT_ENERGY_MAX := 1.0
# UE BloomIntensity -> Godot glow_intensity (DenseFog 8.0 -> 0.64).
const BLOOM_TO_GLOW := 0.08


static func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


static func load_map_table() -> Dictionary:
	var parsed: Variant = _load_json(MAP_TABLE_PATH)
	if parsed is Dictionary:
		var maps: Variant = (parsed as Dictionary).get("maps")
		if maps is Dictionary:
			return maps
	return {}


static func preset_name_for_map(map_id: String) -> String:
	var table: Dictionary = load_map_table()
	var entry: Variant = table.get(map_id)
	if entry is Dictionary:
		return str((entry as Dictionary).get("preset", ""))
	return ""


static func load_preset(preset_name: String) -> Dictionary:
	if preset_name == "":
		return {}
	var parsed: Variant = _load_json(WEATHER_DIR + "/" + preset_name + ".json")
	if parsed is Dictionary:
		return parsed
	return {}


static func preset_for_map(map_id: String) -> Dictionary:
	return load_preset(preset_name_for_map(map_id))


static func _section(preset: Dictionary, key: String) -> Dictionary:
	var s: Variant = preset.get(key)
	if s is Dictionary:
		return s
	return {}


static func _color_of(arr: Variant) -> Color:
	if arr is Array and (arr as Array).size() >= 3:
		return Color(float(arr[0]), float(arr[1]), float(arr[2]))
	return Color(1, 1, 1)


static func _has_color(arr: Variant) -> bool:
	return arr is Array and (arr as Array).size() >= 3


# --- Typed getters (null / false when the source preset lacks the field). ---

static func fog_density(preset: Dictionary) -> Variant:
	return _section(preset, "fog").get("density")


static func fog_light_color(preset: Dictionary) -> Variant:
	var c: Variant = _section(preset, "fog").get("inscattering")
	if _has_color(c):
		return _color_of(c)
	return null


static func fog_sun_scatter(preset: Dictionary) -> Variant:
	var c: Variant = _section(preset, "fog").get("directional_inscattering")
	if _has_color(c):
		var lum := 0.2126 * float(c[0]) + 0.7152 * float(c[1]) + 0.0722 * float(c[2])
		return clampf(lum, 0.0, 1.0)
	return null


static func moon_energy(preset: Dictionary) -> Variant:
	var raw: Variant = _section(preset, "moon_light").get("intensity")
	if raw == null:
		return null
	return clampf(float(raw) * MOON_ENERGY_SCALE, MOON_ENERGY_MIN, MOON_ENERGY_MAX)


static func moon_color(preset: Dictionary) -> Variant:
	var c: Variant = _section(preset, "moon_light").get("color")
	if _has_color(c):
		return _color_of(c)
	return null


static func moon_rotation(preset: Dictionary) -> Variant:
	var ml := _section(preset, "moon_light")
	if ml.get("pitch") == null or ml.get("yaw") == null:
		return null
	var roll := float(ml.get("roll", 0.0))
	return Vector3(float(ml["pitch"]), float(ml["yaw"]), roll)


static func ambient_color(preset: Dictionary) -> Variant:
	var c: Variant = _section(preset, "sky").get("light_color")
	if _has_color(c):
		return _color_of(c)
	return null


static func ambient_energy(preset: Dictionary) -> Variant:
	var raw: Variant = _section(preset, "sky").get("intensity")
	if raw == null:
		return null
	return clampf(float(raw), AMBIENT_ENERGY_MIN, AMBIENT_ENERGY_MAX)


static func background_color(preset: Dictionary) -> Variant:
	var c: Variant = _section(preset, "sky").get("overall_color")
	if _has_color(c):
		return _color_of(c)
	return null


static func saturation(preset: Dictionary) -> Variant:
	var pp := _section(preset, "postprocess")
	if pp.get("saturation") != null:
		return float(pp["saturation"])
	if pp.get("midtones_saturation") != null:
		return float(pp["midtones_saturation"])
	return null


static func brightness(preset: Dictionary) -> Variant:
	var g: Variant = _section(preset, "postprocess").get("gain_midtones")
	if _has_color(g):
		return clampf(float(g[0]) - 1.0, -1.0, 1.0)
	return null


static func tonemap_exposure(preset: Dictionary) -> Variant:
	var raw: Variant = _section(preset, "postprocess").get("auto_exposure_bias")
	if raw == null:
		return null
	return 1.0 + float(raw)


static func glow_intensity(preset: Dictionary) -> Variant:
	var raw: Variant = _section(preset, "postprocess").get("bloom_intensity")
	if raw == null:
		return null
	return clampf(float(raw) * BLOOM_TO_GLOW, 0.0, 0.8)


static func enable_rain(preset: Dictionary) -> bool:
	return bool(_section(preset, "rain").get("enabled", false))


static func rain_intensity(preset: Dictionary) -> Variant:
	return _section(preset, "rain").get("intensity")


static func ground_wetness(preset: Dictionary) -> Variant:
	return _section(preset, "rain").get("ground_wetness")


## Raw sky/moon getters for weather_visuals (null when the source JSON lacks
## the field; no invention, fallbacks live in weather_visuals and are labelled).

static func sky_stars_brightness(preset: Dictionary) -> Variant:
	return _section(preset, "sky").get("stars_brightness")


static func sky_cloud_color(preset: Dictionary) -> Variant:
	var c: Variant = _section(preset, "sky").get("cloud_color")
	if _has_color(c):
		return _color_of(c)
	return null


static func sky_cloud_opacity(preset: Dictionary) -> Variant:
	return _section(preset, "sky").get("cloud_opacity")


static func moon_disc_size(preset: Dictionary) -> Variant:
	return _section(preset, "moon").get("size")


static func moon_disc_visible(preset: Dictionary) -> bool:
	return _section(preset, "moon").get("visible", true) != false


static func moon_disc_brightness(preset: Dictionary) -> Variant:
	var m := _section(preset, "moon")
	if m.get("brightness") != null:
		return float(m["brightness"])
	if m.get("sun_brightness") != null:
		return float(m["sun_brightness"])
	return null


static func moon_disc_color(preset: Dictionary) -> Variant:
	var m := _section(preset, "moon")
	var c: Variant = m.get("color")
	if _has_color(c):
		return _color_of(c)
	var e: Variant = m.get("emissive")
	if _has_color(e):
		return _color_of(e)
	return null


## Applies a parsed preset to env/moon. Fields missing from the preset are
## skipped so existing hand-tuned values survive. Returns false only when the
## preset itself is empty/missing; true otherwise (even if partially applied).
static func apply_environment(env: Environment, moon: DirectionalLight3D, preset: Dictionary) -> bool:
	if preset.is_empty():
		return false
	if env != null:
		var fog_d: Variant = fog_density(preset)
		if fog_d != null:
			env.fog_enabled = true
			env.fog_density = float(fog_d) * FOG_DENSITY_SCALE
		var fog_c: Variant = fog_light_color(preset)
		if fog_c != null:
			env.fog_light_color = fog_c
		var scatter: Variant = fog_sun_scatter(preset)
		if scatter != null:
			env.fog_sun_scatter = float(scatter)
		var amb_c: Variant = ambient_color(preset)
		if amb_c != null:
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = amb_c
		var amb_e: Variant = ambient_energy(preset)
		if amb_e != null:
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_energy = float(amb_e)
		var bg: Variant = background_color(preset)
		if bg != null:
			env.background_mode = Environment.BG_COLOR
			env.background_color = bg
		var sat: Variant = saturation(preset)
		var bri: Variant = brightness(preset)
		if sat != null or bri != null:
			env.adjustment_enabled = true
			if sat != null:
				env.adjustment_saturation = float(sat)
			if bri != null:
				env.adjustment_brightness = float(bri)
		var expo: Variant = tonemap_exposure(preset)
		if expo != null:
			env.tonemap_exposure = float(expo)
		var glow: Variant = glow_intensity(preset)
		if glow != null:
			env.glow_enabled = true
			env.glow_intensity = float(glow)
	if moon != null:
		var energy: Variant = moon_energy(preset)
		if energy != null:
			moon.light_energy = float(energy)
		var mcol: Variant = moon_color(preset)
		if mcol != null:
			moon.light_color = mcol
		var rot: Variant = moon_rotation(preset)
		if rot != null:
			moon.rotation_degrees = rot
	return true


## Loads the preset mapped to map_id and applies it. Returns false (leaving
## env/moon untouched) when the map has no entry or its preset file is missing.
static func apply_for_map(env: Environment, moon: DirectionalLight3D, map_id: String) -> bool:
	var preset: Dictionary = preset_for_map(map_id)
	if preset.is_empty():
		return false
	return apply_environment(env, moon, preset)
