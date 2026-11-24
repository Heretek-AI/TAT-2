extends RefCounted
## Review-only environment for the free-camera review mode and the baked
## `review_core.tscn` master.
##
## The shipped game builds its WorldEnvironment, moon and map fills in
## `mission_controller.gd` (`_setup_environment()` and the `_add_guildhall_*`
## helpers). Review mode has no mission, so before this file it rendered with
## the project's blank default environment — the Foyer/Library captures were
## black. This builder mirrors the mission's environment values but is an
## explicitly review-only aid:
##
##   * fallback Environment + moon (same values as mission_controller);
##   * `WeatherProfile.apply_environment()` then `WeatherVisuals.apply_sky()`
##     with the map's own extracted weather preset;
##   * `MobileProfile.apply_environment()` last, like the mission;
##   * Guildhall LocalVolumetric fog pass config (authored FogVolume boxes);
##   * optional gameplay fills (gate/fence/ornate/road/foyer/safe-room) copied
##     from `_add_guildhall_*` so review captures read like the shipped
##     lighting without touching authored lights.
##
## Captures built with this environment are labelled `review_only=1`. Shipped
## lighting is untouched: this script is never loaded by the mission.

const WeatherProfile: GDScript = preload("res://src/core/weather_profile.gd")
const WeatherVisuals: GDScript = preload("res://src/core/weather_visuals.gd")
const MobileProfile: GDScript = preload("res://src/core/mobile_profile.gd")

const ENV_NODE_NAME: String = "ReviewEnvironment"
const MOON_NODE_NAME: String = "ReviewMoon"
const FILLS_NODE_NAME: String = "ReviewGameplayFills"

## Copied 1:1 from mission_controller.gd `_apply_fallback_environment`.
const FALLBACK_BG: Color = Color(0.02, 0.028, 0.055)
const FALLBACK_AMBIENT: Color = Color(0.16, 0.21, 0.30)


## Builds the environment under `parent` (usually the review scene root).
## Returns a JSON-safe report: preset, sky/moon flags, fill count.
static func build(parent: Node3D, map_id: String, gameplay_fills: bool = false) -> Dictionary:
	var out: Dictionary = {
		"mode": "review_only",
		"map": map_id,
		"preset": "",
		"ambient_source": "",
		"sky": false,
		"moon": false,
		"volumetric": false,
		"gameplay_fills": 0,
	}
	if parent == null:
		return out
	var env: Environment = Environment.new()
	_apply_fallback_environment(env)
	var moon: DirectionalLight3D = DirectionalLight3D.new()
	moon.name = MOON_NODE_NAME
	_apply_fallback_moon(moon)

	var preset: Dictionary = WeatherProfile.preset_for_map(map_id)
	out["preset"] = str(preset.get("preset", "")) if not preset.is_empty() else ""
	if not preset.is_empty():
		WeatherProfile.apply_environment(env, moon, preset)
		out["sky"] = WeatherVisuals.apply_sky(env, preset, moon)
		MobileProfile.apply_environment(env)
	# Guildhall authors LocalVolumetric fog boxes; enable the world volumetric
	# pass with zero global density so only those volumes contribute. Same
	# switch as mission_controller.
	if map_id == "guildhall":
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.0
		env.volumetric_fog_albedo = Color(0.5, 0.5, 0.5, 1.0)
		env.volumetric_fog_emission = Color(0.02, 0.018, 0.026, 1.0)
		out["volumetric"] = true

	var we: WorldEnvironment = WorldEnvironment.new()
	we.name = ENV_NODE_NAME
	we.environment = env
	we.set_meta("review_kind", "environment")
	we.set_meta("review_added", true)
	we.set_meta("review_env_mode", "review_only")
	parent.add_child(we)
	moon.set_meta("review_kind", "light")
	moon.set_meta("review_added", true)
	moon.set_meta("review_env_mode", "review_only")
	parent.add_child(moon)
	out["moon"] = true
	out["ambient_source"] = str(env.ambient_light_source)
	out["background_mode"] = env.background_mode
	out["ambient_energy"] = env.ambient_light_energy
	out["sky"] = env.sky != null

	if gameplay_fills and map_id == "guildhall":
		out["gameplay_fills"] = _add_guildhall_gameplay_fills(parent)
	return out


## Mirrors the mission's review-relevant hand fills. Deliberately a copy, not a
## call into mission_controller: those methods add to the live mission tree,
## register with LightProbe and depend on GameState.active_map_id. Review has
## no mission and must not mutate gameplay state.
static func _add_guildhall_gameplay_fills(parent: Node3D) -> int:
	var holder: Node3D = Node3D.new()
	holder.name = FILLS_NODE_NAME
	holder.set_meta("review_added", true)
	holder.set_meta("review_env_mode", "review_only")
	parent.add_child(holder)
	var count: int = 0
	# Gate lamps + fence + ornate arch (mission_controller _add_guildhall_gate_fills).
	count += _omni(holder, "GuildhallGateLampFill", Vector3(11.5, 23.0, 92.0), Color(1.0, 0.74, 0.48), 2.2, 12.0, 1.2)
	count += _omni(holder, "GuildhallFenceLampFill", Vector3(10.0, 27.0, 46.0), Color(1.0, 0.76, 0.52), 3.5, 16.0, 1.2)
	count += _omni(holder, "GuildhallOrnateGateFill", Vector3(80.0, 20.0, 18.0), Color(1.0, 0.76, 0.52), 1.5, 11.0, 1.3)
	# Wet-cobble road fills (_add_guildhall_road_fills).
	count += _omni(holder, "GuildhallRoadFillL", Vector3(8.6, 21.2, 52.0), Color(1.0, 0.76, 0.52), 0.7, 8.0, 1.4)
	count += _omni(holder, "GuildhallRoadFillR", Vector3(11.4, 21.2, 52.0), Color(1.0, 0.76, 0.52), 0.7, 8.0, 1.4)
	# Foyer fills (_add_guildhall_foyer_fills).
	count += _omni(holder, "GuildhallFoyerFill_-53", Vector3(27.0, 31.0, -53.0), Color(1.0, 0.78, 0.55), 1.6, 16.0, 1.2)
	count += _omni(holder, "GuildhallFoyerFill_-64", Vector3(27.0, 31.0, -64.0), Color(1.0, 0.78, 0.55), 1.3, 16.0, 1.2)
	# Safe-room fill (_add_guildhall_saferoom_fill).
	count += _omni(holder, "GuildhallSafeRoomFill", Vector3(127.0, 29.0, -5.0), Color(0.72, 0.78, 0.95), 1.1, 12.0, 1.2)
	return count


static func _omni(holder: Node3D, node_name: String, pos: Vector3, color: Color, energy: float, omni_range: float, attenuation: float) -> int:
	var light: OmniLight3D = OmniLight3D.new()
	light.name = node_name
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = omni_range
	light.omni_attenuation = attenuation
	light.shadow_enabled = false
	light.set_meta("review_kind", "light")
	light.set_meta("review_added", true)
	light.set_meta("review_env_mode", "review_only")
	holder.add_child(light)
	return 1


static func _apply_fallback_environment(env: Environment) -> void:
	env.background_mode = Environment.BG_COLOR
	env.background_color = FALLBACK_BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = FALLBACK_AMBIENT
	env.ambient_light_energy = 0.38
	env.ambient_light_sky_contribution = 0.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.08, 0.14)
	env.fog_density = 0.008
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.glow_bloom = 0.22
	env.tonemap_mode = Environment.TONE_MAPPER_ACES


static func _apply_fallback_moon(moon: DirectionalLight3D) -> void:
	moon.rotation_degrees = Vector3(-48, 32, 0)
	moon.light_color = Color(0.68, 0.78, 0.98)
	moon.light_energy = 0.55
	moon.shadow_enabled = true
