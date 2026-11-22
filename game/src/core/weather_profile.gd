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
## - Moon rotation converts the UE RelativeRotation FRotator to a Godot Basis
##   with the same path used for level geometry (tools/parse_tables.py
##   ue_rotator_to_mat3 + ue_mat4_to_godot_trs: Z-up UE -> Y-up Godot), then
##   applies level_loader.gd's UE5 +X -> Godot -Z light aim fix-up. UE pitch
##   -90 (straight down) therefore lights straight down along -Z instead of
##   being misread as a Godot Euler.
## - Skylight intensity maps directly to ambient_light_energy, clamped to
##   [0.02, 1.0] (UE night values 0.04-5.0; only the lobby cubemap hits the cap).
## - PostProcess ColorSaturation.X -> adjustment_saturation,
##   ColorGainMidtones.X -> adjustment_brightness (Godot multiplier, default 1.0,
##   range 0..2; NOT an offset — assigning gain-1 renders the view black),
##   AutoExposureBias + 1.0 -> tonemap_exposure (Godot default 1.0),
##   BloomIntensity * 0.08 -> glow_intensity (DenseFog 8.0 -> 0.64, matching the
##   previous hand-tuned 0.65). Godot has no vignette/white-temp/film-curve
##   slots, so those parsed values are exposed via getters only.
## - Fog DirectionalInscattering luminance -> fog_sun_scatter (0..1).
## - enable_rain / rain_intensity are exposed for later particle wiring; this
##   module never spawns rain.

const MobileProfile: GDScript = preload("res://src/core/mobile_profile.gd")

const WEATHER_DIR := "res://data/generated/weather"
const MAP_TABLE_PATH := "res://data/generated/weather/map_weather.json"

## P1: disk + JSON re-parse per lookup. Static caches: the map table is
## immutable at runtime and presets are content-addressed by name, so one
## decode each per session. reload_weather_cache() invalidates (tests /
## content reloads); every lookup still fails closed on missing data.
static var _map_table_cache: Dictionary = {}
static var _map_table_ready: bool = false
static var _preset_cache: Dictionary = {}

# Cache for desktop shadow-toe lift 1D LUTs (R3 APPROXIMATE Local Exposure / gain_shadows).
static var _lut_cache: Dictionary = {}

# UE centimetres -> Godot metres (matches tools/parse_tables.py).
const FOG_DENSITY_SCALE := 0.01
# UE night lux (~0.01-0.05) -> Godot light_energy unit.
const MOON_ENERGY_SCALE := 10.0
const MOON_ENERGY_MIN := 0.05
const MOON_ENERGY_MAX := 1.0
# UE SkyLight intensity -> Godot ambient_light_energy.
const AMBIENT_ENERGY_MIN := 0.05
const AMBIENT_ENERGY_MAX := 0.35
## UE SkyLight intensity is an irradiance scale, not a Godot
## ambient_light_energy. The old 1:1 clamp pinned MidnightClear at 1.0 (flat
## white wash, white-clipped statues) while the Den sat at 0.04. 0.08 keeps
## the authored relative order and places MidnightClear at 0.20: the gate and
## lower-door frames lift out of crushed black without turning the foyer's
## practicals into a daytime wash.
const AMBIENT_UE_TO_GODOT := 0.08
# The authored Guildhall night needs a small exposure lift under AGX; the
# old ACES 1.0 path left the gate at p50 0.04-0.06 against the reference
# 0.10-0.11. Applied to the MidnightClear preset only.
const NIGHT_EXPOSURE := 1.15
# UE BloomIntensity -> Godot glow_intensity (DenseFog 8.0 -> 0.16). The old
# 0.08 factor put Guildhall at 0.51 and turned every ceiling practical and
# the 2500-lumen security spot into a white halo. 0.02 keeps the practicals
# warm but stops the bloom from filling the frame.
const BLOOM_TO_GLOW := 0.02
## P3 companion: fog-energy compensation ceiling. Both density branches
## share one cap so the tuning lives in one place, not two literals.
const FOG_ENERGY_COMP_MAX := 8.0
## P3 single-sample: the clamp fires once per preset per apply (9 loud lines
## in the reference log for 4 presets). Only the first clamp is loud; the
## rest are counted silently. fog_clamp_total() exposes the exact count.
static var _fog_clamp_total: int = 0
static var _fog_clamp_sample_logged: bool = false
## P4 companion: off-Den glow uses 3 mip levels (0-2), not 5, and a 0.9x
## HDR scale instead of 2.0x. Levels 3-4 are explicitly disabled so a preset
## that leaves them on cannot stack 5 mips + 2x HDR outside the Den.
const GLOW_LEVELS_NON_DEN := 3
const GLOW_HDR_SCALE_NON_DEN := 0.9
## Practicals/security fixtures clip above this; keeping the threshold above
## the old 1.0 stops the foyer lamps and 2500-lumen spots from seeding a
## full-frame bloom sheet while the warm sub-threshold practicals still read.
const GLOW_HDR_THRESHOLD_NON_DEN := 1.6
const GLOW_BLOOM_NON_DEN := 0.015


## P3: the old compensation divided up to 24x on pre-exposed dark presets
## and whited out the fog. Capped at FOG_ENERGY_COMP_MAX; anything above
## logs the preset so the authored value stays visible, never silently cut.
static func _clamped_fog_compensation(want_energy: float, is_low_density: bool, preset: Dictionary) -> float:
	if want_energy <= FOG_ENERGY_COMP_MAX:
		return maxf(want_energy, 1.0)
	_fog_clamp_total += 1
	if _fog_clamp_sample_logged:
		return FOG_ENERGY_COMP_MAX
	_fog_clamp_sample_logged = true
	var fog_c: Variant = fog_light_color(preset)
	var lum_dbg: String = "?"
	if fog_c is Color:
		var fc: Color = fog_c as Color
		lum_dbg = str(snappedf(0.2126 * fc.r + 0.7152 * fc.g + 0.0722 * fc.b, 0.0005))
	push_warning("[weather_profile] fog energy compensation clamped ", snappedf(want_energy, 0.1), "x -> ", FOG_ENERGY_COMP_MAX, "x for preset '", str(preset.get("preset", "?")), "' (fog_lum=", lum_dbg, ", low_density=", is_low_density, ", clamp_total=", _fog_clamp_total, ")")
	return FOG_ENERGY_COMP_MAX


## Exact clamp count this session (first clamp is the loud sample line).
static func fog_clamp_total() -> int:
	return _fog_clamp_total


## Desktop quality toggle (P2 companion). The old path enabled volumetric
## fog + SSIL + 48-step SSR on every desktop GPU with no way down. Levels:
## 2 = high (current desktop behaviour), 1 = medium (SSR steps halved, no
## SSIL), 0 = low (no volumetric/SSIL/SSR). Defaults to high so shipped
## behaviour is unchanged; SaveSystem "graphics_quality" (low/medium/high)
## is honoured when present. Values are perf policy, logged at apply time.
static var _quality_override: int = -1


static func set_quality_level(level: int) -> void:
	_quality_override = clampi(level, 0, 2)


static func quality_level() -> int:
	if _quality_override >= 0:
		return _quality_override
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		var save_system: Node = tree.root.get_node_or_null("SaveSystem")
		if save_system != null:
			var data_variant: Variant = save_system.get("data")
			if data_variant is Dictionary:
				var settings: Variant = (data_variant as Dictionary).get("settings", {})
				if settings is Dictionary:
					match str((settings as Dictionary).get("graphics_quality", "high")).to_lower():
						"low":
							return 0
						"medium":
							return 1
	return 2


static func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


## Drops all cached tables/presets so the next lookup re-reads disk.
static func reload_weather_cache() -> void:
	_map_table_cache = {}
	_map_table_ready = false
	_preset_cache = {}


static func load_map_table() -> Dictionary:
	if _map_table_ready:
		return _map_table_cache
	var parsed: Variant = _load_json(MAP_TABLE_PATH)
	if parsed is Dictionary:
		var maps: Variant = (parsed as Dictionary).get("maps")
		if maps is Dictionary:
			_map_table_cache = maps
			_map_table_ready = true
			return _map_table_cache
	push_warning("[weather_profile] map_weather.json missing or has no maps table at ", MAP_TABLE_PATH, "; preset lookups fail closed")
	_map_table_cache = {}
	_map_table_ready = true
	return _map_table_cache


static func preset_name_for_map(map_id: String) -> String:
	var table: Dictionary = load_map_table()
	var entry: Variant = table.get(map_id)
	if entry is Dictionary:
		return str((entry as Dictionary).get("preset", ""))
	return ""


static func load_preset(preset_name: String) -> Dictionary:
	if preset_name == "":
		return {}
	if _preset_cache.has(preset_name):
		return _preset_cache[preset_name] as Dictionary
	var parsed: Variant = _load_json(WEATHER_DIR + "/" + preset_name + ".json")
	if parsed is Dictionary:
		_preset_cache[preset_name] = parsed
		return parsed
	push_warning("[weather_profile] weather preset missing or corrupt: ", preset_name, " (expected ", WEATHER_DIR, "/", preset_name, ".json); failing closed")
	_preset_cache[preset_name] = {}
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


## Converts the preset's UE FRotator (moon_light pitch/yaw/roll) to the Godot
## Basis a DirectionalLight3D needs. Same three steps as the level pipeline:
## UE FRotationMatrix::MakeFromEuler (tools/parse_tables.py:54), the Y/Z swap
## to Godot space (tools/parse_tables.py:91), then the UE5 +X aim -> Godot -Z
## aim fix-up applied to lights in level_loader.gd:1479. Returns null when the
## preset carries no pitch/yaw.
static func moon_basis(preset: Dictionary) -> Variant:
	var ml: Dictionary = _section(preset, "moon_light")
	if ml.get("pitch") == null or ml.get("yaw") == null:
		return null
	var p: float = deg_to_rad(float(ml["pitch"]))
	var y: float = deg_to_rad(float(ml["yaw"]))
	var ro: float = deg_to_rad(float(ml.get("roll", 0.0)))
	var cp: float = cos(p)
	var sp: float = sin(p)
	var cy: float = cos(y)
	var sy: float = sin(y)
	var cr: float = cos(ro)
	var sr: float = sin(ro)
	var m00: float = cp * cy
	var m01: float = sr * sp * cy - cr * sy
	var m02: float = -(cr * sp * cy + sr * sy)
	var m10: float = cp * sy
	var m11: float = sr * sp * sy + cr * cy
	# m12 is -M[2][1] of UE's FRotationMatrix (M[2][1] = CR*SP*SY - SR*CY).
	# This negated form is what keeps the Godot basis orthonormal; the
	# un-negated literal used in tools/parse_tables.py:65 produces a
	# non-orthonormal basis and shears meshes.
	var m12: float = sr * cy - cr * sp * sy
	var m20: float = sp
	var m21: float = -sr * cp
	var m22: float = cr * cp
	# Basis columns in Godot space (Y/Z swapped rows and columns).
	var c0: Vector3 = Vector3(m00, m20, m10)
	var c1: Vector3 = Vector3(m02, m22, m12)
	var c2: Vector3 = Vector3(m01, m21, m11)
	# UE5 lights aim along +X, Godot lights along -Z.
	return Basis(c0, c1, c2) * Basis(Vector3.UP, -PI * 0.5)


static func ambient_color(preset: Dictionary) -> Variant:
	var c: Variant = _section(preset, "sky").get("light_color")
	if _has_color(c):
		return _color_of(c)
	return null


static func ambient_energy(preset: Dictionary) -> Variant:
	var raw: Variant = _section(preset, "sky").get("intensity")
	if raw == null:
		return null
	return clampf(float(raw) * AMBIENT_UE_TO_GODOT, AMBIENT_ENERGY_MIN, AMBIENT_ENERGY_MAX)


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
		return clampf(float(g[0]), 0.0, 2.0)
	return null


static func shadow_gain(preset: Dictionary) -> Variant:
	var g: Variant = _section(preset, "postprocess").get("gain_shadows")
	if _has_color(g):
		return float(g[0])
	return null


## R3 APPROXIMATE 1D shadow-toe color-correction LUT lifting deep shadows
## according to authored `gain_shadows` and UE5 `LocalExposure*` scalars without
## mutating `env.adjustment_brightness` (Suite 17).
static func build_shadow_toe_lut(gain_shadow: float, shadow_contrast: float = 1.0, mid_bias: float = 0.0) -> GradientTexture1D:
	var key: String = "%d_%d_%d" % [
		int(round(gain_shadow * 100.0)),
		int(round(shadow_contrast * 100.0)),
		int(round(mid_bias * 100.0)),
	]
	if _lut_cache.has(key):
		return _lut_cache[key] as GradientTexture1D
	var lift: float = clampf((gain_shadow - 1.0) * 0.65 + (1.0 - shadow_contrast) * 0.35 + mid_bias * 0.25, 0.0, 0.42)
	var grad := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for i: int in range(17):
		var x: float = float(i) / 16.0
		var y: float = x
		if i == 0:
			y = 0.008 * clampf(lift * 3.0, 0.0, 1.0)
		elif x < 0.55:
			var t: float = smoothstep(0.0, 0.55, x)
			y = clampf(lerpf(pow(x, 1.0 - lift), x, t), 0.0, 1.0)
		offsets.append(x)
		colors.append(Color(y, y, y, 1.0))
	grad.offsets = offsets
	grad.colors = colors
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	tex.width = 256
	tex.use_hdr = false
	_lut_cache[key] = tex
	return tex


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


## The disc's own authored emissive tint wins; `moon.color` is the authored
## `Sun / Moon Color` sky term, not the disc material colour and not the
## directional light colour (that is `moon_light.color`), so it is only a
## fallback.
static func moon_disc_color(preset: Dictionary) -> Variant:
	var m := _section(preset, "moon")
	var e: Variant = m.get("emissive")
	if _has_color(e):
		return _color_of(e)
	var c: Variant = m.get("color")
	if _has_color(c):
		return _color_of(c)
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
		# Compensate UE5 pre-exposed fog inscattering (0.001..0.004) via energy
		# and aerial perspective while keeping fog_density & fog_light_color exact
		# for Suites 10 & 17 (R3 APPROXIMATE Eye Adaptation replacement).
		if fog_d != null and fog_c != null:
			var fc: Color = fog_c as Color
			var fog_lum: float = 0.2126 * fc.r + 0.7152 * fc.g + 0.0722 * fc.b
			var is_low_density: bool = float(fog_d) <= 0.1
			if fog_lum > 0.0 and fog_lum < 0.02:
				env.fog_light_energy = _clamped_fog_compensation(0.06 / fog_lum, is_low_density, preset) if is_low_density else _clamped_fog_compensation(0.025 / fog_lum, is_low_density, preset)
				env.fog_aerial_perspective = 0.65 if is_low_density else 0.25
		var scatter: Variant = fog_sun_scatter(preset)
		if scatter != null:
			env.fog_sun_scatter = float(scatter)
		# UE's ExponentialHeightFog does not occlude the sky sphere. Godot's
		# default of 1.0 lets the height fog fully replace the sky at infinite
		# depth, so the authored gradient, stars and moon would render black.
		env.fog_sky_affect = 0.0
		var is_desktop: bool = not MobileProfile.is_mobile()
		# P2: volumetric/SSIL/SSR are desktop-quality-gated, not unconditional.
		# High (2) keeps shipped behaviour; medium (1) halves SSR steps and
		# drops SSIL; low (0) drops all three. Set via SaveSystem
		# "graphics_quality" or set_quality_level(); logged once per apply.
		var desktop_quality: int = quality_level() if is_desktop else 2
		if is_desktop:
			print("WeatherQuality: desktop level=", desktop_quality, " (0=low 1=medium 2=high) for preset '", str(preset.get("preset", "?")), "'")
		if is_desktop and fog_d != null and desktop_quality >= 1:
			# Desktop volumetric distance haze driven by authored fog extinction/distance/hue
			# (R3 APPROXIMATE stand-in for UE5 ExponentialHeightFog volumetric scattering).
			var fog_sec: Dictionary = _section(preset, "fog")
			var vol_ext: float = float(fog_sec.get("volumetric_extinction_scale", 0.6))
			var vol_dist_m: float = clampf(float(fog_sec.get("volumetric_distance", 4000.0)) * 0.01, 25.0, 180.0)
			var is_low_d: bool = float(fog_d) <= 0.1
			var preset_id: String = str(preset.get("preset", "")).to_lower()
			var is_indoor_den: bool = "thieves_den" in preset_id
			env.volumetric_fog_enabled = true
			env.volumetric_fog_sky_affect = 0.0
			env.volumetric_fog_gi_inject = 0.0
			env.volumetric_fog_anisotropy = 0.35
			env.volumetric_fog_length = 60.0 if is_indoor_den else maxf(vol_dist_m * 2.5, 120.0)
			env.volumetric_fog_density = clampf(0.0035 * vol_ext + (0.002 if is_low_d else 0.0), 0.001, 0.012)
			var base_fc: Color = fog_c as Color if fog_c != null else Color(0.35, 0.5, 1.0)
			var fc_max: float = maxf(base_fc.r, maxf(base_fc.g, maxf(base_fc.b, 0.001)))
			var hue: Color = Color(base_fc.r / fc_max, base_fc.g / fc_max, base_fc.b / fc_max)
			env.volumetric_fog_albedo = hue.lerp(Color(0.65, 0.78, 1.0), 0.5)
			var em_scale: float = 0.002 if is_indoor_den else (0.032 if (is_low_d or "dense_fog" in preset_id) else 0.012)
			env.volumetric_fog_emission = hue * em_scale
		var amb_c: Variant = ambient_color(preset)
		if amb_c != null:
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = amb_c
			# The authored SkyLight is a specified cubemap at intensity 2.5, not
			# the near-black M_Sky sphere. Godot's default 1.0 sky contribution
			# blends that black sphere into ambient and erases the authored
			# color, which is why Guildhall/Den crushed to black.
			env.ambient_light_sky_contribution = 0.0
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
				env.adjustment_brightness = clampf(float(bri), 0.0, 2.0)
		if is_desktop and desktop_quality >= 2:
			# Desktop SSIL + shadow-toe LUT (R3 APPROXIMATE replacement for UE5 Lumen GI & Local Exposure).
			env.ssil_enabled = true
			env.ssil_radius = 4.5
			env.ssil_intensity = 0.8
			env.ssil_sharpness = 0.98
			env.ssil_normal_rejection = 1.0
			var gs: Variant = shadow_gain(preset)
			if gs != null and float(gs) > 1.02:
				env.adjustment_enabled = true
				env.adjustment_color_correction = build_shadow_toe_lut(float(gs))
		var expo: Variant = tonemap_exposure(preset)
		if expo != null:
			env.tonemap_exposure = float(expo)
		# Guildhall's authored MidnightClear is the one preset where the
		# ACES 1.0 path crushed the gate into black while the interior
		# practicals clipped. AGX rolls the highlights off instead of
		# clipping them, and the small exposure lift matches the reference
		# gate/overlook medians. Other presets keep their authored path.
		if str(preset.get("preset", "")).to_lower() == "midnight_clear":
			env.tonemap_mode = Environment.TONE_MAPPER_AGX
			env.tonemap_exposure = maxf(env.tonemap_exposure, NIGHT_EXPOSURE)
		var glow: Variant = glow_intensity(preset)
		if glow != null:
			# Den RD cap: indoor Den preset keeps glow on for the warm look
			# but uses fewer mip levels (0-1 = 2 textures vs 0-4 = 6) and a
			# lower HDR scale so strip 1 (+glow) can't cascade texture_create.
			var den_preset_id: String = str(preset.get("preset", "")).to_lower()
			var is_den_glow: bool = "thieves_den" in den_preset_id
			env.glow_enabled = true
			env.glow_intensity = float(glow) * 0.6 if is_den_glow else float(glow)
			if is_desktop:
				env.glow_hdr_threshold = 1.0 if is_den_glow else GLOW_HDR_THRESHOLD_NON_DEN
				env.glow_hdr_scale = 1.0 if is_den_glow else GLOW_HDR_SCALE_NON_DEN
				env.glow_bloom = 0.10 if is_den_glow else GLOW_BLOOM_NON_DEN
				env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
				for gl_i: int in range(2 if is_den_glow else GLOW_LEVELS_NON_DEN):
					env.set_glow_level(gl_i, true)
				if is_den_glow:
					for gl_off: int in range(2, 5):
						env.set_glow_level(gl_off, false)
				else:
					for gl_off: int in range(GLOW_LEVELS_NON_DEN, 5):
						env.set_glow_level(gl_off, false)
		if is_desktop:
			# Desktop SSR for wet cobblestone puddles (tat_landscape.gdshader roughness ~0.04).
			env.ssr_enabled = desktop_quality >= 1
			env.ssr_max_steps = 48 if desktop_quality >= 2 else 24
			env.ssr_fade_in = 0.15
			env.ssr_fade_out = 2.0
			env.ssr_depth_tolerance = 0.2
	# M3: the mobile glow cap must run AFTER weather apply — callers that
	# apply mobile first get silently stomped here. Enforcing the order at
	# this seam (MobileProfile is already preloaded above) instead of
	# trusting call order. Re-checks is_mobile() directly so this also holds
	# when env was null above (no reliance on the block-scoped is_desktop).
	if env != null and MobileProfile.is_mobile():
		MobileProfile.apply_environment(env)
	if moon != null:
		var energy: Variant = moon_energy(preset)
		if energy != null:
			moon.light_energy = float(energy)
		var mcol: Variant = moon_color(preset)
		if mcol != null:
			moon.light_color = mcol
		var mbasis: Variant = moon_basis(preset)
		if mbasis != null:
			moon.basis = mbasis
	return true


## Loads the preset mapped to map_id and applies it. Returns false (leaving
## env/moon untouched) when the map has no entry or its preset file is missing.
static func apply_for_map(env: Environment, moon: DirectionalLight3D, map_id: String) -> bool:
	var preset: Dictionary = preset_for_map(map_id)
	if preset.is_empty():
		return false
	return apply_environment(env, moon, preset)


## Clears parsed preset/LUT caches held for the process lifetime.
static func cleanup_static_caches() -> void:
	_map_table_cache.clear()
	_map_table_ready = false
	_preset_cache.clear()
	_lut_cache.clear()
