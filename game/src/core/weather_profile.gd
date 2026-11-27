extends RefCounted
## Real weather data extracted from Thick As Thieves.
##
const AutoExposure := preload("res://src/core/auto_exposure.gd")
const CubemapLoader := preload("res://src/core/cubemap_loader.gd")
##
## Loads the normalized presets written by `tools/parse_weather.py` from
## `res://data/generated/weather/` and applies them to a Godot Environment +
## DirectionalLight3D. Every value comes from the game's own
## BP_WeatherPreset_* exports; fields absent from the source JSON are left
## untouched on the live environment (never invented).
##
## Unit conversions (documented, applied in one place so they stay honest):
## - FOG_DENSITY_SCALE = 0.03: UE works in centimetres, Godot in metres. The
##   plain 0.01 cm->m convention made the near field far too clear: the authored
##   Guildhall fog (0.06-0.16) reached only ~1.8 % obscuration at 30 m, so the
##   rainy streets, the parade square and the skyline read like a clear night.
##   0.03 keeps the authored preset ratios and puts the 20-120 m band where the
##   reference reads it (transmittance exp(-density*S*d)):
##     gloomy      FogDensity 0.16 -> 0.0048/m:  9 % @20 m, 13 % @30 m,
##                                               25 % @60 m, 44 % @120 m
##     midnight_clear       0.06  -> 0.0018/m: 12 % @60 m, 19 % @120 m
##     dense_fog            0.40  -> 0.012 /m: 21 % @20 m, 30 % @30 m,
##                                               51 % @60 m, 76 % @120 m
##   The sky veil is NOT part of this factor: it is pinned by the
##   FOG_SKY_AFFECT_FLOOR / haze colour below.
## - FOG_HAZE_LUMA_FLOOR: the presets' authored FogInscatteringLuminance is
##   pre-exposed (0.0003-0.001 per channel). Blending that colour into the sky
##   at any weight darkens it to black (the "black horizon" defect). Outdoor
##   presets therefore keep the authored HUE but floor its luminance; the Den
##   keeps the exact authored inscattering (indoor, closed sky).
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
##   BloomIntensity * 0.02 -> glow_intensity (DenseFog 8.0 -> 0.16; the old
##   0.08 factor turned every ceiling practical into a white halo). Godot has no
##   vignette/white-temp/film-curve slots, so those parsed values are exposed via
##   getters only; `white_temp` / `vignette_intensity` / `film_*` need a
##   screen-space pass and a capture to settle their convention (T07 report).
## - FogHeightFalloff -> fog_height_density with the same 0.03 cm->m calibration
##   (outdoor presets only; a room has no height gradient).
## - moon_light.source_angle -> DirectionalLight3D.light_angular_distance (1:1
##   degrees). sky.volumetric_cloud_visible gates the procedural cloud stand-in.
## - Night presets (`gloomy`, `midnight_clear*`) take AGX + NIGHT_EXPOSURE.
## - `TAT2_AEM=fixed` (default) keeps that constant path exactly. `model` uses
##   the authored AEM_Basic fields + V3 curve through `auto_exposure.gd`; it
##   resolves to the same 1.15 at the documented night anchor and is a no-op
##   there. `meter` additionally attaches the live CompositorEffect meter
##   controller in mission_controller (the integrator's GPU calibration run).
##   The authored EV100 space is luminance-calibrated and tonemap_exposure is a
##   linear multiplier; `AEM_CALIBRATION` is the ONE conversion, never a
##   per-preset grade.
## - `TAT2_IBL=off` (default) leaves ambient exactly as authored. `ambient`
##   replaces the flat SkyLight colour with the CPU cosine irradiance of the
##   authored TextureCube (`cubemap_loader.gd`), energy NOT clamped.
## - Fog DirectionalInscattering luminance -> fog_sun_scatter (0..1).
## - enable_rain / rain_intensity are exposed for later particle wiring; this
##   module never spawns rain.

const MobileProfile: GDScript = preload("res://src/core/mobile_profile.gd")
## W6G: SoundCarry accessor delegates the tag join to the hearing layer, so the
## authored weather rows have exactly one reader.
const HearingData: GDScript = preload("res://src/ai/hearing_data.gd")

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
## One loud line per session for the IBL/GI state (authored cubemap reachable?
## which approximation is active?). Repeated applies stay quiet.
static var _ibl_state_logged: bool = false
## P4.1: one loud line per session for the opted-in authored paths.
static var _aem_logged: bool = false
static var _aem_non_night_logged: bool = false
static var _cubemap_ambient_logged: bool = false

# UE centimetres -> Godot metres, calibrated for the 20-120 m readability band
# (see the header table); NOT the plain 0.01 geometry convention.
const FOG_DENSITY_SCALE := 0.03
# Outdoor horizon floor. Godot's fog_sky_affect blends fog_light_color into the
# sky; at 0.0 the fogged horizon is the authored (pre-exposed, near-black) sky
# sphere, which is the reported black horizon. 0.80 lets the floored haze colour
# veil the horizon without replacing the authored gradient (the zenith term is
# independent, tat_sky.gdshader). The Den keeps 0.0: its sky is a window.
const FOG_SKY_AFFECT_FLOOR := 0.80
# The volumetric pass got the same treatment: 0.0 cut the authored local fog
# boxes off at the sky. A small floor keeps the aerial glow without flattening
# the gradient (the albedo is already hue-lifted toward 0.65/0.78/1.0 below).
const VOLUMETRIC_FOG_SKY_AFFECT_FLOOR := 0.15
# Minimum outdoor fog-light luminance: authored hue, floored brightness.
const FOG_HAZE_LUMA_FLOOR := 0.05
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
# 0.10-0.11. W5C scoped this to the bare preset id "midnight_clear", which NO
# map resolves to (`map_weather.json`: guildhall -> gloomy), so the Guildhall --
# the map this calibration was measured on (KF16/KF17/KF18 are Guildhall frames)
# -- ran at 1.0, i.e. exactly the configuration the sentence above says crushes
# the gate. T07 applies it to every authored night preset through
# is_night_preset() instead of an exact-id match.
const NIGHT_EXPOSURE := 1.15
## Authored AutoExposureBiasCurve (`Curve_Exposure_Compensation_Float_V3`, the
## curve the Gloomy -> Base_Skybox -> Base weather chain selects) now lives in
## `auto_exposure.gd` (one table, one reader) and is read through GameData's
## standalone curve index. `ev_curve_bias()` below delegates to it so existing
## callers keep working.
## EV100 the shipped night rows meter at (AEM_Basic over a 0.01-0.033 lux moon
## plus practicals). At or below this the authored curve is saturated at -4 EV.
const EV_CURVE_NIGHT_EV100 := -3.0
# UE BloomIntensity -> Godot glow_intensity (DenseFog 8.0 -> 0.16). The old
# 0.08 factor put Guildhall at 0.51 and turned every ceiling practical and
# the 2500-lumen security spot into a white halo. 0.02 keeps the practicals
# warm but stops the bloom from filling the frame.
const BLOOM_TO_GLOW := 0.02
## P3 companion: fog-energy compensation ceiling. Both density branches
## share one cap so the tuning lives in one place, not two literals.
const FOG_ENERGY_COMP_MAX := 8.0
## FIX_SPEC P0 #2: the indoor Den's near-black blue inscattering (lum ~0.0019)
## divided up to 13.4x and hit the 8.0 ceiling, veiling the attic in flat blue.
## Keep the 0.003 density but cap the Den compensation at 2.0.
const DEN_FOG_ENERGY_COMP_MAX := 2.0
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
	var preset_id: String = str(preset.get("preset", "")).to_lower()
	if "thieves_den" in preset_id:
		return clampf(want_energy, 1.0, DEN_FOG_ENERGY_COMP_MAX)
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


## W6G: authored weather gameplay tag for a map (`weather_tag` in
## map_weather.json, e.g. Weather.Type.Gloomy). "" when the map has no row.
static func weather_tag_for_map(map_id: String) -> String:
	var entry_v: Variant = load_map_table().get(map_id)
	if entry_v is Dictionary:
		return str((entry_v as Dictionary).get("weather_tag", ""))
	return ""


## W6G SoundCarry accessor: the authored range row for the map's weather type
## and the indoor/outdoor side (hearing.json weather_sound_carry). {} when the
## map/weather/side is unknown; the hearing layer then fails closed to 1.0.
## Indoor/outdoor is the same preset classification the environment apply uses
## (the Den is the only indoor preset), so AI hearing and fog share one rule.
static func sound_carry_for_map(map_id: String, indoors: bool) -> Dictionary:
	var tag: String = weather_tag_for_map(map_id)
	if tag == "":
		return {}
	return HearingData.weather_sound_carry_row(tag, indoors)


## W6G: multiplicative sound-carry range modifier for the map's weather type and
## the indoor/outdoor side. 1.0 for unknown maps/weather (fail closed).
static func sound_carry_multiplier_for_map(map_id: String, indoors: bool) -> float:
	var tag: String = weather_tag_for_map(map_id)
	if tag == "":
		return 1.0
	return HearingData.weather_sound_carry_multiplier(tag, indoors)


## Desktop GI/AO lever (T07 P1). Authored = Lumen diffuse GI + hardware RT with
## VSM (`r.DynamicGlobalIlluminationMethod=1`, `r.Lumen.HardwareRayTracing=True`)
## and `r.AllowStaticLighting=False`, so there is no lightmass bake to import —
## an "import the bake" fix is not available. Godot's approximations, cheapest
## first:
##   off   : no indirect pass (perf-ladder last resort)
##   ssil  : screen-space indirect, the shipped desktop default
##   sdfgi : voxel GI, the closest analogue to Lumen diffuse, but it re-voxelises
##           the 63 k-instance Guildhall every frame and has NOT been measured on
##           the 60 FPS desktop gate, so it is an opt-in capture lever, not a
##           default. The authored `LumenDiffuseColorBoost 2.0` is the tuning
##           target for its energy (T01 does not emit the field yet).
## `TAT2_GI` overrides the mode; `TAT2_AO=off` removes SSAO for an A/B capture.
const ENV_GI_MODE := "TAT2_GI"
const ENV_AO_MODE := "TAT2_AO"


static func gi_mode() -> String:
	var mode: String = OS.get_environment(ENV_GI_MODE).strip_edges().to_lower()
	if mode == "off" or mode == "ssil" or mode == "sdfgi":
		return mode
	return "ssil"


static func ao_enabled() -> bool:
	return OS.get_environment(ENV_AO_MODE).strip_edges().to_lower() != "off"


## Applies the desktop indirect/occlusion passes. Called from apply_environment
## so the QA levers live in exactly one place.
static func apply_gi_and_ao(env: Environment, desktop_quality: int) -> void:
	if env == null or desktop_quality < 2:
		return
	var mode: String = gi_mode()
	env.ssil_enabled = mode == "ssil"
	if mode == "ssil":
		env.ssil_radius = 4.5
		env.ssil_intensity = 0.8
		env.ssil_sharpness = 0.98
		env.ssil_normal_rejection = 1.0
	if mode == "sdfgi":
		env.sdfgi_enabled = true
		# 3 cascades / 0.5 m cells covers ~100 m of interior; the port has no
		# measured cost for this, hence the opt-in gate above.
		env.sdfgi_cascades = 3
		env.sdfgi_min_cell_size = 0.5
		env.sdfgi_use_occlusion = true
		env.sdfgi_read_sky_light = true
		env.sdfgi_energy = 1.0
		env.sdfgi_max_distance = 200.0
	if ao_enabled():
		# APPROXIMATE contact shadow (Lumen's screen-probe occlusion has no Godot
		# slot). Conservative intensity: the defect being fixed is a light
		# deficit, so AO must add depth without deepening the crush.
		env.ssao_enabled = true
		env.ssao_radius = 1.5
		env.ssao_intensity = 1.2
		env.ssao_power = 1.5
		env.ssao_detail = 0.5
		env.ssao_horizon = 0.06
		env.ssao_sharpness = 0.98
		env.ssao_light_affect = 0.0


## True when the map's authored preset is the indoor (Den style) environment.
static func map_is_indoor(map_id: String) -> bool:
	return is_indoor_preset(preset_for_map(map_id))


# --- W7H indoor scope -------------------------------------------------------
#
# The authored SoundCarry row has two sides (indoors / outdoors). The map preset
# only answers that question for the Den: Old Manor (DenseFog, outdoor 0.9) and
# Jaspering Hall (HeavyRain, outdoor 0.8) are outdoor presets that also cover
# interiors, so treating them as "outdoors everywhere" attenuated every indoor
# footstep at the street multiplier. The room question is answered with a
# straight-up ceiling probe instead: anything solid above the listener within
# INDOOR_CEILING_PROBE_M is a roof/soffit, and that listener uses the authored
# indoors row (1.0).
#
# This is a geometric heuristic, not a room volume list: an outdoor archway or a
# bridge deck also reads as covered. It is the conservative direction (the
# authored indoors row is the un-attenuated one), and every caller that already
# knows it is indoors (the Den preset) short-circuits before the probe.

## Straight-up probe reach. 15 m clears a three-storey interior, a tower stair
## well and a guildhall hall; it is deliberately shorter than a cathedral nave so
## a leaky roof does not silence the street outside it.
const INDOOR_CEILING_PROBE_M: float = 15.0


## True when a ceiling/soffit is above `world_pos`. A missing world fails closed
## to the map preset (handled by the callers).
static func is_indoors_at(space: PhysicsDirectSpaceState3D, world_pos: Vector3, exclude: Array[RID] = [], mask: int = 1) -> bool:
	if space == null:
		return false
	var from: Vector3 = world_pos
	var to: Vector3 = world_pos + Vector3.UP * INDOOR_CEILING_PROBE_M
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	var hit: Dictionary = space.intersect_ray(q)
	return not hit.is_empty()


## Sound-carry multiplier for a listener at `world_pos`: the preset indoor side
## wins when the map itself is indoor (the Den), otherwise the ceiling probe
## decides. 1.0 for unknown maps/weather (fail closed).
static func sound_carry_multiplier_at(map_id: String, space: PhysicsDirectSpaceState3D, world_pos: Vector3, exclude: Array[RID] = []) -> float:
	if map_is_indoor(map_id):
		return sound_carry_multiplier_for_map(map_id, true)
	return sound_carry_multiplier_for_map(map_id, is_indoors_at(space, world_pos, exclude))


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


## Indoor presets keep the exact authored fog/inscattering: the Den sky is a
## window pane, not a horizon. Substring match only on the preset id, matching
## the two existing Den branches in apply_environment.
static func is_indoor_preset(preset: Dictionary) -> bool:
	return "thieves_den" in str(preset.get("preset", "")).to_lower()


## Authored night rows (see NIGHT_EXPOSURE). A preset is a night preset when it
## is `gloomy` or a `midnight_clear*` row, or when its authored weather tag says
## so. `dense_fog`/`heavy_rain` are deliberately excluded: the Old Manor and
## Jaspering night grading has no reference calibration in this repo, and
## changing their exposure would be an unmeasured edit.
static func is_night_preset(preset: Dictionary) -> bool:
	var pid: String = str(preset.get("preset", "")).to_lower()
	if pid == "gloomy" or pid.begins_with("midnight_clear"):
		return true
	var tag: String = str(preset.get("weather_tag", "")).to_lower()
	return tag == "weather.type.gloomy" or tag == "weather.type.midnightclear"


## Authored V3 exposure-compensation curve, delegated to `auto_exposure.gd`
## (GameData's standalone curve index, transcribed keys as fallback). Kept as a
## WeatherProfile entry point because T07/probe code reads it here.
static func ev_curve_bias(ev100: float) -> float:
	return AutoExposure.ev_curve_bias(ev100)


## Authored UE LightSourceAngle -> Godot DirectionalLight3D.light_angular_distance
## (both degrees, 1:1). The soft night-sky moon is part of the authored look; the
## port left the angular distance at 0 (hard-edged shadows).
static func moon_source_angle(preset: Dictionary) -> Variant:
	var raw: Variant = _section(preset, "moon_light").get("source_angle")
	if raw == null:
		return null
	return clampf(float(raw), 0.0, 90.0)


## Authored FogHeightFalloff -> Godot `fog_height_density`, using the same
## 0.03 cm->m calibration as FogDensity (see FOG_DENSITY_SCALE). Godot measures
## the height fog from world y=0 and attenuates by exp(-fog_height_density * y),
## so gloomy's 1.070813 becomes 0.0321 /m: ~55 % of the authored density at the
## Guildhall's y=18.5 street floor and ~6 % at its y=87 tower top, which is the
## ground-hugging haze the uniform density could not express.
## APPROXIMATE: UE's exact height integral and its fog-base offset are not
## recovered (the base is assumed 0); indoor presets keep a uniform fog because
## the Den is a room, not a street.
static func fog_height_density(preset: Dictionary) -> Variant:
	var raw: Variant = _section(preset, "fog").get("height_falloff")
	if raw == null:
		return null
	return clampf(float(raw) * FOG_DENSITY_SCALE, 0.0, 1.0)


## Authored volumetric-cloud visibility. False means the preset authors no
## volumetric cloud pass for that sky (the Den and midnight_clear); the port's
## procedural FBM stand-in used to draw clouds on every preset regardless.
static func sky_clouds_visible(preset: Dictionary) -> bool:
	return _section(preset, "sky").get("volumetric_cloud_visible", true) != false


## Authored SkyLight specified cubemap (UE path). Every shipped night preset
## points at `/Game/MaterialLibrary/Utility/Cubemap_GroundFloor_01`; the extractor
## does not export TextureCube faces (no .hdr/.exr/.ktx2 in extracted/assets), so
## the port cannot build the authored IBL yet. Resolved and reported here, with
## the loader in sky_ibl_state() below, so the day the producer emits the faces
## the consumer already exists. Returns "" when the preset authors none.
static func sky_cubemap_path(preset: Dictionary) -> String:
	return str(_section(preset, "sky").get("cubemap", ""))


## Godot resource path the converted authored cubemap would live at: the UE path
## with `/Game/` swapped for the extracted asset root and an HDR extension. Only
## `/Game/` content is mirrored under `res://assets/ue/Raw` (an `/Engine/` or
## plugin path has no converted equivalent), so anything else returns "".
static func sky_cubemap_res_path(preset: Dictionary) -> String:
	var ue_path: String = sky_cubemap_path(preset)
	if not ue_path.begins_with("/Game/"):
		return ""
	var rel: String = ue_path.trim_prefix("/Game/")
	return "res://assets/ue/Raw/%s.exr" % rel


## What the ambient/IBL path can do with the authored SkyLight right now.
## `available=false` means the converted cubemap is not on disk; the caller keeps
## `ambient_light_sky_contribution = 0` (a flat authored colour) rather than
## mixing the display-space sky shader into ambient, which would darken it.
static func sky_ibl_state(preset: Dictionary) -> Dictionary:
	var res_path: String = sky_cubemap_res_path(preset)
	var available: bool = res_path != "" and ResourceLoader.exists(res_path)
	return {
		"cubemap_ue_path": sky_cubemap_path(preset),
		"cubemap_res_path": res_path,
		"available": available,
		"sky_contribution": 1.0 if available else 0.0,
	}


## Prep-stage grade values for T05 (mission_prep_ui.gd owns the call site and
## T07 owns the grade). The stage still hard-codes ACES 2.6 / ambient 1.8 /
## glow 1.0 / sky 0.18 while gameplay runs AGX at the authored night anchor with
## ambient 0.16-0.35 (measurable 2.6x exposure and 11x ambient gap, finding
## C1-09). These are the same authored numbers the gameplay path applies, so T05
## can replace its constants with this dictionary and keep one grade.
static func stage_grade_values(preset: Dictionary) -> Dictionary:
	var amb: Variant = ambient_energy(preset)
	var glow: Variant = glow_intensity(preset)
	var night: bool = is_night_preset(preset)
	return {
		"tonemap_mode": Environment.TONE_MAPPER_AGX if night else Environment.TONE_MAPPER_ACES,
		"tonemap_exposure": NIGHT_EXPOSURE if night else 1.0,
		"ambient_light_color": ambient_color(preset),
		"ambient_light_energy": float(amb) if amb != null else AMBIENT_ENERGY_MIN,
		"glow_intensity": float(glow) if glow != null else 0.0,
		"background_energy_multiplier": 1.0,
	}


## Outdoor fog/sky colour: the authored overcast-dome hue (sky.cloud_color,
## falling back to the authored FogInscatteringLuminance hue) at exactly
## FOG_HAZE_LUMA_FLOOR luminance. The authored fog channels are pre-exposed
## (midnight_clear 0.0011/0.0016/0.004) and gloomy's are a near-zero mint, so
## using them as-is turns the fogged horizon black or green; the cloud tint is
## the authored overcast colour the sky is actually painted with. Returns null
## when the preset authors no colour (caller leaves fog untouched).
static func fog_haze_color(preset: Dictionary) -> Variant:
	var hue_v: Variant = sky_cloud_color(preset)
	if hue_v == null:
		hue_v = fog_light_color(preset)
	if hue_v == null:
		return null
	var hue: Color = hue_v as Color
	var lum: float = 0.2126 * hue.r + 0.7152 * hue.g + 0.0722 * hue.b
	if lum <= 0.0:
		# Hue-less authored colour (all zero = authored black): no hue to keep,
		# so the neutral floor is the only honest value.
		return Color(0.05, 0.054, 0.062, 1.0)
	var scale: float = FOG_HAZE_LUMA_FLOOR / lum
	return Color(
		clampf(hue.r * scale, 0.0, 1.0),
		clampf(hue.g * scale, 0.0, 1.0),
		clampf(hue.b * scale, 0.0, 1.0),
		hue.a
	)


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
## Optional `black_lift` + `toe_end` (both > 0) layer the Den P1 additive toe
## on top of the legacy curve instead of replacing it:
##   y(x) = clamp(legacy_y(x) + black_lift * (1 - x / toe_end)^2, 0, 1)
## The bump is zero at `toe_end` (smooth quadratic falloff, no hard knee) and
## never subtracts, so the P0.1 midtones/highlights remain the floor. Omitting
## them (<= 0, the defaults) returns the legacy ramp bit-for-bit, so every
## pre-P1 caller is unchanged. Den P1 uses black_lift=0.022 / toe_end=0.030.
static func build_shadow_toe_lut(gain_shadow: float, shadow_contrast: float = 1.0, mid_bias: float = 0.0, black_lift: float = -1.0, toe_end: float = -1.0) -> GradientTexture1D:
	var key: String = "%d_%d_%d_%d_%d" % [
		int(round(gain_shadow * 100.0)),
		int(round(shadow_contrast * 100.0)),
		int(round(mid_bias * 100.0)),
		int(round(black_lift * 1000.0)),
		int(round(toe_end * 1000.0)),
	]
	if _lut_cache.has(key):
		return _lut_cache[key] as GradientTexture1D
	var lift: float = clampf((gain_shadow - 1.0) * 0.65 + (1.0 - shadow_contrast) * 0.35 + mid_bias * 0.25, 0.0, 0.42)
	var black: float = 0.008 * clampf(lift * 3.0, 0.0, 1.0)
	# Legacy curve, exactly as the pre-P1 17-knot ramp sampled it. The additive
	# toe is layered on these piecewise-linear samples so the baseline keeps
	# rendering what P0.1 rendered.
	var legacy_y := PackedFloat32Array()
	for i: int in range(17):
		var lx: float = float(i) / 16.0
		var ly: float = lx
		if i == 0:
			ly = black
		elif lx < 0.55:
			var lt: float = smoothstep(0.0, 0.55, lx)
			ly = clampf(lerpf(pow(lx, 1.0 - lift), lx, lt), 0.0, 1.0)
		legacy_y.append(ly)
	var additive: bool = black_lift > 0.0 and toe_end > 0.0
	var toe: float = clampf(toe_end, 0.0, 1.0)
	var xs: Array[float] = []
	if additive:
		# Dense samples resolve the smooth bump; the legacy knots (0.0625,
		# 0.125, ...) fall on this 1/64 grid, so the baseline is unchanged.
		for i: int in range(65):
			xs.append(float(i) / 64.0)
		var has_toe: bool = false
		for sx: float in xs:
			if is_equal_approx(sx, toe):
				has_toe = true
				break
		if not has_toe:
			xs.append(toe)
			xs.sort()
	else:
		for i: int in range(17):
			xs.append(float(i) / 16.0)
	var grad := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for x: float in xs:
		var f: float = x * 16.0
		var k: int = clampi(int(floor(f)), 0, 15)
		var base: float = lerpf(legacy_y[k], legacy_y[k + 1], f - float(k))
		var y: float = base
		if additive:
			var fall: float = maxf(0.0, 1.0 - x / toe)
			y = clampf(base + clampf(black_lift, 0.0, 1.0) * fall * fall, 0.0, 1.0)
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
		var is_indoor: bool = is_indoor_preset(preset)
		if fog_c != null and not is_indoor:
			# Outdoor presets: authored hue, floored luminance (see header).
			env.fog_light_color = fog_haze_color(preset)
		elif fog_c != null:
			env.fog_light_color = fog_c
		# Compensate UE5 pre-exposed fog inscattering (0.001..0.004) via energy
		# and aerial perspective while keeping fog_density & fog_light_color exact
		# for Suites 10 & 17 (R3 APPROXIMATE Eye Adaptation replacement). Indoor
		# presets keep the authored colour, so this only runs for the Den now;
		# the outdoor haze floor replaces the divide-up path.
		if fog_d != null and fog_c != null and is_indoor:
			var fc: Color = fog_c as Color
			var fog_lum: float = 0.2126 * fc.r + 0.7152 * fc.g + 0.0722 * fc.b
			var is_low_density: bool = float(fog_d) <= 0.1
			if fog_lum > 0.0 and fog_lum < 0.02:
				env.fog_light_energy = _clamped_fog_compensation(0.06 / fog_lum, is_low_density, preset) if is_low_density else _clamped_fog_compensation(0.025 / fog_lum, is_low_density, preset)
				env.fog_aerial_perspective = 0.65 if is_low_density else 0.25
		var scatter: Variant = fog_sun_scatter(preset)
		if scatter != null:
			env.fog_sun_scatter = float(scatter)
		# Authored FogHeightFalloff (previously dead data). Outdoor presets only:
		# the Den authors 1.0 as well, but a room has no height gradient.
		var hf: Variant = fog_height_density(preset)
		if hf != null and not is_indoor:
			env.fog_height_density = float(hf)
			env.fog_height = 0.0
		# UE's ExponentialHeightFog does not occlude the sky sphere. Godot's
		# default of 1.0 lets the height fog fully replace the sky at infinite
		# depth, so the authored gradient, stars and moon would render black.
		# Outdoor presets get the calibrated haze floor over the horizon (0.80,
		# see FOG_SKY_AFFECT_FLOOR); the Den keeps 0.0 because its sky is a pane.
		env.fog_sky_affect = 0.0 if is_indoor else FOG_SKY_AFFECT_FLOOR
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
			# Same horizon rule as fog_sky_affect: outdoor presets keep a small
			# volumetric term over the sky, the Den keeps its pane clear.
			env.volumetric_fog_sky_affect = 0.0 if is_indoor_den else VOLUMETRIC_FOG_SKY_AFFECT_FLOOR
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
			# The authored SkyLight is a specified cubemap at intensity 2.0-2.5, not
			# the near-black M_Sky sphere. Godot's default 1.0 sky contribution
			# blends that dark display-space sphere into ambient and erases the
			# authored color, which is why Guildhall/Den crushed to black. Keep 0
			# until the authored cubemap can actually be loaded (sky_ibl_state);
			# mixing the sky shader in instead would *reduce* ambient.
			env.ambient_light_sky_contribution = 0.0
			var ibl: Dictionary = sky_ibl_state(preset)
			if bool(ibl.get("available", false)):
				env.ambient_light_sky_contribution = float(ibl.get("sky_contribution", 1.0))
			if not _ibl_state_logged:
				_ibl_state_logged = true
				print("TAT-2 IBL: skylight_cubemap=", str(ibl.get("cubemap_ue_path", "")), " converted=", str(ibl.get("cubemap_res_path", "")), " available=", str(ibl.get("available", false)), " sky_contribution=", str(ibl.get("sky_contribution", 0.0)), " gi=", gi_mode(), " ao=", ao_enabled())
		var amb_e: Variant = ambient_energy(preset)
		if amb_e != null:
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_energy = float(amb_e)
		# P4.1 IBL stage 1: the authored SkyLight TextureCube -> CPU cosine
		# irradiance (cubemap_loader.gd). `TAT2_IBL=off` (default) returns
		# available=false and everything above stays byte-for-byte today's.
		# `ambient` replaces the flat SkyLight colour with the measured
		# irradiance; energy is the raw luminance (no AMBIENT_ENERGY_MAX clamp:
		# stage 1 must not hide its own measurement behind a tuning ceiling).
		var cm_amb: Dictionary = CubemapLoader.ambient_for_preset(preset)
		if bool(cm_amb.get("available", false)):
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = cm_amb.get("color", env.ambient_light_color) as Color
			env.ambient_light_energy = float(cm_amb.get("energy", env.ambient_light_energy))
			if not _cubemap_ambient_logged:
				_cubemap_ambient_logged = true
				print("TAT-2 IBL ambient: mode=%s cubemap=%s energy=%.5f color=(%.4f,%.4f,%.4f) (CPU cosine irradiance, no clamp)" % [
					str(cm_amb.get("mode", "")),
					str(cm_amb.get("cubemap", "")),
					float(cm_amb.get("energy", 0.0)),
					(env.ambient_light_color as Color).r,
					(env.ambient_light_color as Color).g,
					(env.ambient_light_color as Color).b,
				])
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
			# Desktop GI stand-ins + shadow-toe LUT (R3 APPROXIMATE replacement
			# for UE5 Lumen GI & Local Exposure). The GI/AO mode is one place so
			# the QA levers (TAT2_GI / TAT2_AO) cannot drift from the default.
			apply_gi_and_ao(env, desktop_quality)
			var gs: Variant = shadow_gain(preset)
			if gs != null and float(gs) > 1.02:
				env.adjustment_enabled = true
				env.adjustment_color_correction = build_shadow_toe_lut(float(gs))
		var expo: Variant = tonemap_exposure(preset)
		if expo != null:
			env.tonemap_exposure = float(expo)
		# Guildhall's authored night is the one place the ACES 1.0 path crushed
		# the gate into black while the interior practicals clipped. AGX rolls
		# the highlights off instead of clipping them. Both authored night
		# families take it, and both take the measured 1.15 anchor (see
		# NIGHT_EXPOSURE: the lift used to be scoped to a preset no map uses).
		if is_night_preset(preset):
			env.tonemap_mode = Environment.TONE_MAPPER_AGX
			env.tonemap_exposure = maxf(env.tonemap_exposure, NIGHT_EXPOSURE)
			# Evidence line: the authored exposure path is recorded even where
			# Godot cannot apply it (no auto exposure; EV curve is EV-space).
			print("TAT-2 exposure: preset=%s mode=AGX exposure=%.3f authored_bias=%s ev100_night=%.1f authored_curve_bias=%.2f (curve recorded, not applied)" % [
				str(preset.get("preset", "?")),
				env.tonemap_exposure,
				str(_section(preset, "postprocess").get("auto_exposure_bias")),
				EV_CURVE_NIGHT_EV100,
				ev_curve_bias(EV_CURVE_NIGHT_EV100),
			])
		# P4.1a/b authored exposure. `fixed` (default) is exactly the block
		# above. `model` reads the authored AEM fields + V3 curve at the
		# documented night anchor through auto_exposure.gd (the single
		# AEM_CALIBRATION resolves it to the same 1.15); `meter` seeds the same
		# anchor here and the CompositorEffect controller then adapts on the GPU
		# calibration run. A non-night preset has no measured scene EV100
		# without the meter, so the fixed value is kept rather than invented.
		var aem_mode: String = AutoExposure.mode()
		if aem_mode != AutoExposure.MODE_FIXED:
			if is_night_preset(preset):
				env.tonemap_exposure = AutoExposure.exposure_for_preset(preset, EV_CURVE_NIGHT_EV100)
			elif not _aem_non_night_logged:
				_aem_non_night_logged = true
				print("TAT-2 AEM: mode=%s preset=%s is not a night preset and has no measured scene EV100; keeping the fixed exposure (GPU meter run required)" % [
					aem_mode, str(preset.get("preset", "?")),
				])
			if not _aem_logged:
				_aem_logged = true
				var probe_model = AutoExposure.new()
				probe_model.configure(preset)
				var pm: Dictionary = probe_model.state()
				print("TAT-2 AEM: mode=%s preset=%s method=%s min=%.2f max=%.2f speed=%.2f/%.2f bias=%.2f curve=%s authored=%s exposure=%.4f calibration=%.9f" % [
					aem_mode,
					str(preset.get("preset", "?")),
					str(pm.get("method", "")),
					float(pm.get("min_brightness", 0.0)),
					float(pm.get("max_brightness", 0.0)),
					float(pm.get("speed_up", 0.0)),
					float(pm.get("speed_down", 0.0)),
					float(pm.get("bias", 0.0)),
					str(pm.get("bias_curve", "")),
					str(pm.get("authored", false)),
					env.tonemap_exposure,
					float(AutoExposure.AEM_CALIBRATION),
				])
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
		# Authored LightSourceAngle (previously dead data): the soft night-sky
		# moon. 1:1 degrees into Godot's directional light angular distance.
		var mangle: Variant = moon_source_angle(preset)
		if mangle != null:
			moon.light_angular_distance = float(mangle)
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
	_ibl_state_logged = false
	_aem_logged = false
	_aem_non_night_logged = false
	_cubemap_ambient_logged = false
