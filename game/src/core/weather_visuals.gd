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
## - Sky gradient: sky.horizon_color / sky.zenith_color. Missing horizon falls
##   back to sky.background_color, then sky.overall_color, then the zenith
##   darkened x0.55; missing zenith falls back to overall_color, then the
##   horizon darkened x0.6. (The JSON carries only horizon/zenith/overall
##   colors; background_color/zenith aliases are accepted defensively.)
##   APPROXIMATE tone-map: authored LinearColor values are HDR (e.g. horizon
##   [1.9796, 2.5866, 3.0]) and feeding them straight into the shader's
##   vec3 uniforms clips toward white. The cooked M_Sky curve cannot be
##   recovered, so the HDR color is normalised by its max channel (not divided
##   by 255) before upload; in-range values pass through unchanged.
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
##   Tint = moon.color (else moon.emissive), energy =
##   clamp(0.3 + 0.5 * moon.brightness, 0.25, 2.0) (UE brightness spans
##   0.15-50, so the compressive map is APPROXIMATE). The sky-light intensity
##   is an ambient term and deliberately does not scale the disc.
## - Stars: sky.stars_brightness drives a sparse procedural term only when it
##   is > 0 (star_amount = clamp(brightness / 8, 0, 1); midnight_clear 10.0
##   reads full, thieves_den 3.0 subtle, 0 disables). APPROXIMATE: hash
##   sparkle, no recovered star catalogue.
## - Clouds: sky.cloud_color tints a horizon haze band with strength
##   clamp(cloud_opacity * 0.18, 0, 0.55). No cloud texture is invented.
## - Rain: GPUParticles3D box 60x40x60 m around the emitter, amount =
##   1800 * clamp(intensity, 0, 1.5) clamped to [100, 2700] (APPROXIMATE;
##   Niagara ratios were not recovered, only the on/off + intensity scalar),
##   lifetime 1.1 s, gravity 30 m/s^2, unshaded alpha streak quads
##   (0.035 x 0.7 m). Emission uses world space so the volume can follow the
##   player without smearing.

const WeatherProfile := preload("res://src/core/weather_profile.gd")
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


## APPROXIMATE tone-map for authored HDR sky colors: normalise by the max
## channel so the shader's source_color vec3 keeps its hue instead of clipping.
static func _tone_safe(c: Color) -> Color:
	var m: float = maxf(c.r, maxf(c.g, c.b))
	if m > 1.0:
		return Color(c.r / m, c.g / m, c.b / m, c.a)
	return c


## Horizon gradient color with the documented fallback chain.
static func horizon_color_of(preset: Dictionary) -> Color:
	var sky: Dictionary = preset.get("sky", {})
	for key: String in ["horizon_color", "background_color", "overall_color"]:
		var c: Variant = _color3(sky.get(key))
		if c != null:
			return _tone_safe(c as Color)
	var z: Variant = _color3(sky.get("zenith_color", sky.get("zenith", null)))
	if z != null:
		return _tone_safe((z as Color) * Color(0.55, 0.55, 0.55, 1.0))
	return FALLBACK_HORIZON


## Zenith gradient color with the documented fallback chain.
static func zenith_color_of(preset: Dictionary) -> Color:
	var sky: Dictionary = preset.get("sky", {})
	for key: String in ["zenith_color", "zenith", "overall_color"]:
		var c: Variant = _color3(sky.get(key))
		if c != null:
			return _tone_safe(c as Color)
	var h: Variant = _color3(sky.get("horizon_color", sky.get("background_color", null)))
	if h != null:
		return _tone_safe((h as Color) * Color(0.6, 0.6, 0.6, 1.0))
	return FALLBACK_ZENITH


## Builds the real-sky Sky resource for a preset. The moon disc sits along the
## moon light's +Z axis (requires apply_environment to have set its rotation).
static func make_sky(preset: Dictionary, moon: DirectionalLight3D) -> Sky:
	var horizon: Color = horizon_color_of(preset)
	var zenith: Color = zenith_color_of(preset)
	var mat := ShaderMaterial.new()
	mat.shader = SKY_SHADER
	mat.set_shader_parameter("horizon_color", horizon)
	mat.set_shader_parameter("zenith_color", zenith)

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
		var moon_section: Dictionary = preset.get("moon", {})
		var off_raw: Variant = moon_section.get("distance_offset")
		var offset: float = float(off_raw) if off_raw != null else 0.0
		diam = moon_diameter_deg(float(size_raw), offset)
	mat.set_shader_parameter("moon_angular_radius", deg_to_rad(diam * 0.5))

	var pano: Texture2D = load(MOON_PANORAMA_PATH) as Texture2D if ResourceLoader.exists(MOON_PANORAMA_PATH) else null
	if pano != null:
		mat.set_shader_parameter("moon_texture", pano)
	else:
		show_moon = false
	mat.set_shader_parameter("moon_visible", 1.0 if show_moon else 0.0)
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
		mat.set_shader_parameter("cloud_color", cloud_col)
	mat.set_shader_parameter("cloud_haze", haze)

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
	var drops := GPUParticles3D.new()
	drops.amount = clampi(int(RAIN_AMOUNT_AT_FULL * intensity), RAIN_AMOUNT_MIN, RAIN_AMOUNT_MAX)
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
