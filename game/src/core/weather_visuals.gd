extends RefCounted
## Real night sky + weather-driven rain from the extracted TAT presets.
##
## Every visual comes from `game/data/generated/weather/*.json` (parsed by
## weather_profile.gd); fields absent from the JSON keep engine defaults and
## are never invented. Procedural stand-ins (star sparkle, cloud haze, moon
## panorama framing, rain particle counts) are labelled APPROXIMATE below and
## in tat_sky.gdshader.
##
## UE -> Godot value mapping used here:
## - Sky gradient: authored_colour * sky.overall_color, where authored_colour
##   is sky.horizon_color / sky.zenith_color. The multiplier is applied
##   exactly once, and only to a colour that came from horizon_color,
##   zenith_color or background_color.
##   Missing horizon falls back to sky.background_color, then to the authored
##   zenith darkened x0.55 (multiplied by overall_color when present), then to
##   sky.overall_color returned UNMULTIPLIED (that colour already is the
##   multiplier, so multiplying again would square it), then to
##   FALLBACK_HORIZON. Missing zenith falls back to the authored horizon
##   darkened x0.6 (multiplied by overall_color when present), then to
##   sky.overall_color returned UNMULTIPLIED, then to FALLBACK_ZENITH.
##   (The JSON carries only horizon/zenith/overall colors;
##   background_color/zenith aliases are accepted defensively.)
##   sky.overall_color is UE M_Sky's Overall Color multiplier (e.g.
##   midnight_clear 0.001), so the authored HDR horizon [1.9796, 2.5866, 3.0]
##   becomes a legitimately very dark night gradient and is not re-brightened.
##   APPROXIMATE fallback only when a preset has no authored overall_color:
##   the HDR colour is normalised by its max channel (not divided by 255)
##   before upload, because the cooked M_Sky curve cannot be recovered.
##   In-range values pass through unchanged on that fallback path.
## - Moon disc: placed along the moon DirectionalLight3D's +Z axis (the axis
##   the light shines from). moon.size is the authored SM_Moon static-mesh
##   RelativeScale3D.x; the real angular DIAMETER comes from the sphere
##   geometry: 2 * asin(sphere_radius * size / (orbit_distance +
##   moon.distance_offset)). A preset with no authored size keeps the 6-degree
##   fallback. moon.visible == false hides the disc. The disc maps the whole
##   real T_Moon_D lunar panorama onto the visible hemisphere (4096x2048
##   equirectangular, atan/acos UV over the near hemisphere nz >= 0); the
##   cooked M_Moon / MI_Moon_Base materials kept the texture but no UV framing
##   rect, so the hemisphere mapping is APPROXIMATE.
##   Tint = moon.emissive (the authored MoonlightEmissiveColor tint; the
##   binding to the disc material is INFERRED), else moon.color (the authored
##   `Sun / Moon Color` sky term), else the directional light colour
##   (moon_light.color). Energy =
##   clamp(0.3 + 0.5 * moon.brightness, 0.25, 2.0) (UE brightness spans
##   0.15-50, so the compressive map is APPROXIMATE). The sky-light intensity
##   is an ambient term and deliberately does not scale the disc.
## - Stars: sky.stars_brightness drives a sparse procedural term only when it
##   is > 0 (star_amount = clamp(brightness / 8, 0, 1); midnight_clear 10.0
##   reads full, thieves_den 3.0 subtle, 0 disables). APPROXIMATE: hash
##   sparkle, no recovered star catalogue.
## - Clouds: sky.cloud_color tints a horizon haze band with strength
##   clamp(cloud_opacity * 0.18, 0, 0.55). This is an APPROXIMATE term, not the
##   cooked volumetric cloud material, and its tint follows the authored
##   `Overall Color` multiplier (cloud_color * sky.overall_color when present),
##   matching UE M_Sky's whole-sky multiply. No cloud texture is invented.
## - Rain: GPUParticles3D box 60x40x60 m around the emitter, amount =
##   1800 * clamp(intensity, 0, 1.5) clamped to [100, 2700] (APPROXIMATE;
##   Niagara ratios were not recovered, only the on/off + intensity scalar),
##   lifetime 1.1 s, gravity 30 m/s^2, unshaded alpha streak quads
##   (0.035 x 0.7 m). Emission uses world space so the volume can follow the
##   player without smearing.

const WeatherProfile := preload("res://src/core/weather_profile.gd")
const MobileProfile := preload("res://src/core/mobile_profile.gd")
const SKY_SHADER := preload("res://src/core/tat_sky.gdshader")
const MOON_PANORAMA_PATH := "res://assets/ue/Raw/Art/Environment/City/Architecture/BeautifulCorner/Materials/T_Moon_D.png"

# Moon disc: authored SM_Moon scale -> real angular diameter (see mapping).
# MOON_SPHERE_RADIUS_CM: SM_Moon SphereRadius, 10771.60558231864 cm
#   (extracted/json/Art/Environment/City/Architecture/BeautifulCorner/SM_Moon.json).
const MOON_SPHERE_RADIUS_CM := 10771.60558231864
# MOON_ORBIT_DISTANCE_CM: |Moon_GEN_VARIABLE RelativeLocation.X|, 1469413.0 cm
#   (extracted/json/Art/Environment/Weather/BP_WeatherPreset_Base_Skybox.json).
const MOON_ORBIT_DISTANCE_CM := 1469413.0
# moon.size is the authored Blueprint variable "Moon Size", which the extracted
# data exposes as the Moon_GEN_VARIABLE RelativeScale3D.x. The BP graph that
# drives it is cooked, so the correspondence is INFERRED from the matching
# value (9.838636 in both), not decompiled. "Moon Distance Offset" is treated
# as an additive centimetre term (worth 0.048 degrees on DenseFog).
const DEFAULT_MOON_DIAMETER_DEG := 6.0
const MOON_ENERGY_MIN := 0.25
const MOON_ENERGY_MAX := 2.0
const STAR_NORMALIZER := 8.0
const CLOUD_OPACITY_TO_HAZE := 0.18
const CLOUD_HAZE_MAX := 0.55

# Rain volume (documented approximations, see mapping above).
const RAIN_MIN_INTENSITY := 0.05
const RAIN_AMOUNT_AT_FULL := 1800
const RAIN_AMOUNT_MAX := 2700
const RAIN_AMOUNT_MIN := 100
const RAIN_LIFETIME := 1.1
const RAIN_GRAVITY := 30.0
const RAIN_BOX_HALF := Vector3(30.0, 20.0, 30.0)

const FALLBACK_HORIZON := Color(0.02, 0.03, 0.06)
const FALLBACK_ZENITH := Color(0.005, 0.008, 0.02)

## W1: the 4096x2048 moon panorama was load()ed synchronously on every
## make_sky call. One static cache: disk decode happens once per session,
## every later sky build reuses the texture. RefCounted Sky/ShaderMaterial
## pairs are still built per preset (W2) — they are small and the old pair
## is refcount-freed when env.sky is reassigned, so no Sky objects
## accumulate; the 4K texture was the allocation that mattered.
static var _pano_cache: Texture2D = null
static var _pano_cache_miss_logged: bool = false


static func _color3(raw: Variant) -> Variant:
	if raw is Array and (raw as Array).size() >= 3:
		var a: Array = raw
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return null


## Real angular diameter of the moon disc for an authored SM_Moon scale and
## orbit offset. See the header mapping.
static func moon_diameter_deg(size: float, distance_offset: float) -> float:
	var r: float = MOON_SPHERE_RADIUS_CM * size
	var d: float = MOON_ORBIT_DISTANCE_CM + distance_offset
	# Result clamp is a corrupt-data guard only; shipped presets span 2.10-11.90.
	return clampf(2.0 * rad_to_deg(asin(clampf(r / d, 0.0, 0.999))), 0.0, 20.0)


## APPROXIMATE tone-map for authored HDR sky colors when the preset carries no
## overall_color: normalise by the max channel so the shader's source_color
## vec3 keeps its hue instead of clipping.
static func _tone_safe(c: Color) -> Color:
	var m: float = maxf(c.r, maxf(c.g, c.b))
	if m > 1.0:
		return Color(c.r / m, c.g / m, c.b / m, c.a)
	return c


## UE M_Sky multiplies the authored gradient by sky.overall_color. Apply that
## authored multiplier when present; only the no-overall_color fallback uses
## the approximate tone-map.
static func _authored_sky_color(c: Color, overall: Variant) -> Color:
	if overall != null:
		return c * (overall as Color)
	return _tone_safe(c)


## Horizon gradient color with the documented fallback chain.
static func horizon_color_of(preset: Dictionary) -> Color:
	var sky: Dictionary = preset.get("sky", {})
	var overall: Variant = _color3(sky.get("overall_color"))
	for key: String in ["horizon_color", "background_color"]:
		var c: Variant = _color3(sky.get(key))
		if c != null:
			return _authored_sky_color(c as Color, overall)
	var z: Variant = _color3(sky.get("zenith_color", sky.get("zenith", null)))
	if z != null:
		return _authored_sky_color((z as Color) * Color(0.55, 0.55, 0.55, 1.0), overall)
	# An authored overall_color is already the multiplier: return it as-is so it
	# is never multiplied by itself (which would square it).
	if overall != null:
		return overall as Color
	return FALLBACK_HORIZON


## Zenith gradient color with the documented fallback chain.
static func zenith_color_of(preset: Dictionary) -> Color:
	var sky: Dictionary = preset.get("sky", {})
	var overall: Variant = _color3(sky.get("overall_color"))
	for key: String in ["zenith_color", "zenith"]:
		var c: Variant = _color3(sky.get(key))
		if c != null:
			return _authored_sky_color(c as Color, overall)
	var h: Variant = _color3(sky.get("horizon_color", sky.get("background_color", null)))
	if h != null:
		return _authored_sky_color((h as Color) * Color(0.6, 0.6, 0.6, 1.0), overall)
	# An authored overall_color is already the multiplier: return it as-is so it
	# is never multiplied by itself (which would square it).
	if overall != null:
		return overall as Color
	return FALLBACK_ZENITH


## W1 cached fetch: logs the UE path once on first decode (hit or miss),
## then serves the cache silently — one pano load per session, never per sky.
static func _moon_panorama() -> Texture2D:
	if _pano_cache != null:
		return _pano_cache
	if ResourceLoader.exists(MOON_PANORAMA_PATH):
		_pano_cache = load(MOON_PANORAMA_PATH) as Texture2D
	if not _pano_cache_miss_logged:
		_pano_cache_miss_logged = true
		if _pano_cache != null:
			print("MoonPanorama: cached ", MOON_PANORAMA_PATH, " (4096x2048, one decode per session)")
		else:
			push_warning("[weather_visuals] moon panorama missing at ", MOON_PANORAMA_PATH, "; moon disc hidden (no invented texture)")
	return _pano_cache


## Builds the real-sky Sky resource for a preset. The moon disc sits along the
## moon light's +Z axis (requires apply_environment to have set its rotation).
static func make_sky(preset: Dictionary, moon: DirectionalLight3D) -> Sky:
	var horizon: Color = horizon_color_of(preset)
	var zenith: Color = zenith_color_of(preset)
	var mat := ShaderMaterial.new()
	mat.shader = SKY_SHADER
	mat.set_shader_parameter("horizon_color", horizon)
	mat.set_shader_parameter("zenith_color", zenith)

	var sky_sec_v: Variant = preset.get("sky", {})
	var sky_sec: Dictionary = sky_sec_v as Dictionary if sky_sec_v is Dictionary else {}
	var overall: Variant = _color3(sky_sec.get("overall_color"))
	# Decouple rendered sky radiance from UE5's pre-exposed 0.001 overall_color
	# scalar while keeping horizon_color_of() / zenith_color_of() untouched (Suite 22).
	var sky_radiance_scale: float = 1.0
	if overall != null:
		var oc: Color = overall as Color
		var max_overall: float = maxf(oc.r, maxf(oc.g, oc.b))
		if max_overall > 0.0 and max_overall < 0.05:
			sky_radiance_scale = clampf(0.025 / max_overall, 1.0, 35.0)
	mat.set_shader_parameter("sky_radiance_scale", sky_radiance_scale)

	var moon_dir := Vector3(0.0, 1.0, 0.0)
	if moon != null:
		var d: Vector3 = moon.basis * Vector3(0.0, 0.0, 1.0)
		if d.length() > 0.001:
			moon_dir = d.normalized()
	mat.set_shader_parameter("moon_direction", moon_dir)

	var show_moon: bool = moon != null and WeatherProfile.moon_disc_visible(preset)
	var size_raw: Variant = WeatherProfile.moon_disc_size(preset)
	var diam: float = DEFAULT_MOON_DIAMETER_DEG
	if size_raw != null:
		var moon_section_v: Variant = preset.get("moon", {})
		var moon_section: Dictionary = moon_section_v as Dictionary if moon_section_v is Dictionary else {}
		var off_raw: Variant = moon_section.get("distance_offset")
		var offset: float = float(off_raw) if off_raw != null else 0.0
		diam = moon_diameter_deg(float(size_raw), offset)
	mat.set_shader_parameter("moon_angular_radius", deg_to_rad(diam * 0.5))

	var pano: Texture2D = _moon_panorama()
	if pano != null:
		mat.set_shader_parameter("moon_texture", pano)
	else:
		show_moon = false
	mat.set_shader_parameter("moon_visible", 1.0 if show_moon else 0.0)
	mat.set_shader_parameter("moon_halo_strength", 0.45 if show_moon else 0.0)
	var mcol: Variant = WeatherProfile.moon_disc_color(preset)
	if mcol == null and moon != null:
		mcol = moon.light_color
	mat.set_shader_parameter("moon_color", mcol if mcol != null else Color.WHITE)
	var bright_raw: Variant = WeatherProfile.moon_disc_brightness(preset)
	var bright: float = float(bright_raw) if bright_raw != null else 1.0
	var energy: float = clampf(0.3 + 0.5 * bright, MOON_ENERGY_MIN, MOON_ENERGY_MAX)
	mat.set_shader_parameter("moon_energy", energy)

	var stars_raw: Variant = WeatherProfile.sky_stars_brightness(preset)
	var stars: float = 0.0
	if stars_raw != null and float(stars_raw) > 0.0:
		stars = clampf(float(stars_raw) / STAR_NORMALIZER, 0.0, 1.0)
	mat.set_shader_parameter("star_amount", stars)

	var haze: float = 0.0
	var cloud_col: Variant = WeatherProfile.sky_cloud_color(preset)
	var cloud_op: Variant = WeatherProfile.sky_cloud_opacity(preset)
	if cloud_col != null and cloud_op != null:
		haze = clampf(float(cloud_op) * CLOUD_OPACITY_TO_HAZE, 0.0, CLOUD_HAZE_MAX)
		# Lift cloud tint separately from UE5's 0.001 dome scalar so procedural
		# FBM wisps read in deep indigo night skies (R3 APPROXIMATE stand-in
		# calibrated from MI_VolumetricCloud_* ratios and Steam captures).
		var haze_col: Color = cloud_col as Color
		if overall != null:
			var oc2: Color = overall as Color
			var mo2: float = maxf(oc2.r, maxf(oc2.g, oc2.b))
			if mo2 > 0.0 and mo2 < 0.05:
				haze_col *= oc2 * clampf(0.085 / mo2, 1.0, 85.0)
			else:
				haze_col *= oc2
		mat.set_shader_parameter("cloud_color", haze_col)
	mat.set_shader_parameter("cloud_haze", haze)

	var vc_mat: String = str(sky_sec.get("volumetric_cloud_material", "")).to_lower()
	var cloud_cov: float = 0.42
	if "stormy" in vc_mat:
		cloud_cov = 0.78
	elif "overcast" in vc_mat or "cloudy" in vc_mat:
		cloud_cov = 0.68
	if cloud_op != null:
		cloud_cov = clampf(cloud_cov * clampf(float(cloud_op) / 3.3, 0.3, 1.2), 0.12, 0.90)
	mat.set_shader_parameter("cloud_coverage", cloud_cov)

	var sky := Sky.new()
	sky.sky_material = mat
	return sky


## Swaps the environment to the preset's real sky. Returns false (leaving env
## untouched) when the preset carries no sky/moon data, so the BG_COLOR
## fallback survives. Ambient stays COLOR-sourced from the light_color /
## intensity values weather_profile already applied; reflections switch to the
## live sky.
static func apply_sky(env: Environment, preset: Dictionary, moon: DirectionalLight3D) -> bool:
	if env == null or preset.is_empty():
		return false
	if not preset.has("sky") and not preset.has("moon"):
		return false
	env.sky = make_sky(preset, moon)
	env.background_mode = Environment.BG_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	return true


## Builds the rain volume for presets with rain.enabled and
## rain.intensity > 0.05 (intensity 1e-06 "off" presets return null).
static func make_rain(parent: Node3D, preset: Dictionary) -> Node3D:
	if parent == null or preset.is_empty():
		return null
	if not WeatherProfile.enable_rain(preset):
		return null
	var raw: Variant = WeatherProfile.rain_intensity(preset)
	if raw == null or float(raw) <= RAIN_MIN_INTENSITY:
		return null
	var intensity: float = clampf(float(raw), 0.0, 1.5)
	var tier_scale: float = MobileProfile.rain_scale()
	var scaled_max: int = maxi(int(float(RAIN_AMOUNT_MAX) * tier_scale), RAIN_AMOUNT_MIN)
	var drops := GPUParticles3D.new()
	drops.amount = clampi(int(RAIN_AMOUNT_AT_FULL * intensity * tier_scale), RAIN_AMOUNT_MIN, scaled_max)
	if tier_scale < 1.0:
		print("RainTier: mobile scale=", tier_scale, " max=", scaled_max, " (preset intensity=", intensity, ")")
	drops.lifetime = RAIN_LIFETIME
	drops.local_coords = false
	drops.visibility_aabb = AABB(-Vector3(35.0, 25.0, 35.0), Vector3(70.0, 50.0, 70.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = RAIN_BOX_HALF
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 4.0
	pm.gravity = Vector3(0.0, -RAIN_GRAVITY, 0.0)
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.0
	drops.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.7)
	var qmat := StandardMaterial3D.new()
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qmat.albedo_color = Color(0.62, 0.72, 0.88, 0.38)
	qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = qmat
	drops.draw_pass_1 = quad
	parent.add_child(drops)
	return drops


## Keeps the rain volume centered on the follow target (called each _process).
static func snap_rain_to(rain: Node3D, target: Node3D) -> void:
	if rain == null or target == null:
		return
	if not is_instance_valid(rain) or not is_instance_valid(target):
		return
	rain.global_position = (target as Node3D).global_position


## Clears the cached panorama texture held for the process lifetime.
static func cleanup_static_caches() -> void:
	_pano_cache = null
