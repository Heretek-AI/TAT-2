extends Node3D
## Mission & Contract runner: loads the FULL extracted UE5 sublevels
## (OldManor_Geo/Gameplay/Loot, Guildhall_POI/Geometry/Periphery/Gameplay/Loot,
## ThievesDen_Geo, or FTUE_Geometry for Jaspering Hall expansion),
## spawns real Guard & Thief models, loot spawners, lights, and escape gates.

## Emitted exactly once per start_contract(), after the level build, all
## spawns/devices and the loading-screen teardown have completed. QA harnesses
## wait on this instead of polling player/doors, so a truncated load cannot be
## mistaken for a completed one.
signal mission_ready(map_id: String, stats: Dictionary)

const ThiefScript := preload("res://src/player/thief_character.gd")
const GuardScript := preload("res://src/ai/guard_ai.gd")
const LootScript := preload("res://src/interact/loot_item.gd")
const LootContainerScript := preload("res://src/interact/loot_container.gd")
const SwingingDoorScript := preload("res://src/interact/swinging_door.gd")
const DeviceLayerScript := preload("res://src/devices/device_layer.gd")
const WorldPickupScript := preload("res://src/interact/world_pickup.gd")
const CivilianScript := preload("res://src/ai/civilian_npc.gd")
const DoorScript := preload("res://src/interact/lockable_door.gd")
const EscapeScript := preload("res://src/interact/escape_gate.gd")
const LightProbeScript := preload("res://src/stealth/light_probe.gd")
const LevelLoaderScript := preload("res://src/core/level_loader.gd")
const MobileProfile := preload("res://src/core/mobile_profile.gd")
const PerfProfile := preload("res://src/core/perf_profile.gd")
const WeatherProfile := preload("res://src/core/weather_profile.gd")
const WeatherVisuals := preload("res://src/core/weather_visuals.gd")
const VfxManager := preload("res://src/core/vfx_manager.gd")
const HudScript := preload("res://src/ui/hud.gd")
const WardrobeUIScript := preload("res://src/ui/wardrobe_ui.gd")
const ContractTableUIScript := preload("res://src/ui/contract_table_ui.gd")
const ClueItemScript := preload("res://src/interact/clue_item.gd")
const PersonalQuestScript := preload("res://src/quests/personal_quest.gd")
const PersonalQuestSpawnerScript := preload("res://src/quests/personal_quest_spawner.gd")
const LoadingScreenScript := preload("res://src/ui/loading_screen.gd")
const LedgerUIScript := preload("res://src/ui/ledger_ui.gd")
const MobileTouchUIScript := preload("res://src/ui/mobile_touch_ui.gd")

var light_probe: Node
var level_loader: Node
var player: CharacterBody3D
var hud: CanvasLayer
var smokes: Array[Dictionary] = []
var rain_node: Node3D = null
var lens_rain_node: CanvasLayer = null
var contract_info: Dictionary = {}
var level_stats: Dictionary = {}
## Level names actually loaded this run ("Guildhall/Guildhall_Contracts").
## Authored spawner records are filtered to these so a clue can never be
## placed on a sublevel that was not loaded.
var _loaded_level_names: Array[String] = []
## Authored quest items spawned this run (record has node + spawner + facts).
var _quest_item_spawns: Array[Dictionary] = []
## Authored readable clues spawned this run (QA/tests read this).
var _clue_spawn_records: Array[Dictionary] = []
## W1S Spider personal-chain actors spawned for the current map. Each record
## is {anchor_id, kind, node, pos, source}; exposed so the real-map probe can
## assert what the deploy produced without walking the scene tree by name.
var personal_quest_actors: Array[Dictionary] = []
var spawner_meshes: Dictionary = {}
var spawner_civilians: Array = []
var loot_tables: Dictionary = {}
## Which spawn path the player used: "authored" for a floor-grounded
## PlayerStart, otherwise the marker fallback that won ("major_loot",
## "minor_centroid", "guard", "escape", "legacy"). Logged for QA.
var fallback_spawn_source: String = "authored"
## Whether the chosen spawn passed the fallback headroom check (2.2 m clear
## above the floor plus a standing-capsule overlap test). Authored starts
## report true; the legacy last-resort reports false. Logged for QA.
var fallback_spawn_headroom_clear: bool = true
## Whether the chosen spawn passed the fallback forward-clearance check
## (no layer-1 geometry within 1.5 m on the 3 m horizontal ray toward the
## loot centroid). Authored starts report true; the legacy last-resort and
## the floor/headroom-only fallbacks report false. Logged for QA.
var fallback_spawn_forward_clear: bool = true
## W2 patrol QA: guards that fell back to the synthetic 6x6 m square (no
## authored APatrolPath point within PATROL_MATCH_RADIUS_M) and their exact
## logged lines, plus how many guards adopted an authored path.
var patrol_fallback_count: int = 0
var patrol_fallback_log: Array[String] = []
var patrol_paths_assigned: int = 0
const PATROL_MATCH_RADIUS_M: float = 30.0

var _is_thieves_den: bool = false
var _letter_grace_sec: float = 0.0 # P1 timer-during-letter: run-clock hold after the start letter (see _process).
var _den_map_table_pos: Vector3 = Vector3.ZERO
var _den_telescope_pos: Vector3 = Vector3(-4.9202, 41.0, 270.7337)
var _den_selected_map_id: String = "old_manor"
var _den_lookat_card: Dictionary = {}
var _den_tokens: Dictionary = {}
var _ponder_active: bool = false
var _ponder_cam: Camera3D = null
var _ponder_cheese: Node3D = null
var _ponder_vista: Node3D = null
## Den P1 shadow-toe: `_den_lut_p1` is the capture LUT (`black_lift` 0.014,
## toe 0.03); `_den_lut_legacy` keeps the level-load LUT so the KF05 telescope
## vista can be restored to its pre-P1 look while the ponder view is up.
var _den_env: Environment = null
var _den_lut_p1: GradientTexture1D = null
var _den_lut_legacy: GradientTexture1D = null
## Den reflection probe node, freed explicitly at mission exit (see _exit_tree):
## Godot 4.7.2 retains the probe atlas (7 texture RIDs) until the node is freed.
var _den_reflection_probe: ReflectionProbe = null
var _active_mission_row: Dictionary = {}
## One-shot guard for mission_ready (start_contract resets it).
var _mission_ready_emitted: bool = false


func _ready() -> void:
	add_to_group("mission")
	light_probe = LightProbeScript.new()
	add_child(light_probe)
	level_loader = LevelLoaderScript.new()
	add_child(level_loader)
	hud = HudScript.new()
	add_child(hud)
	MobileProfile.apply_runtime(get_tree())
	if MobileProfile.is_mobile():
		var touch_ui: CanvasLayer = MobileTouchUIScript.new()
		touch_ui.set("hud", hud)
		add_child(touch_ui)

	# Resolve the map before building the environment so the weather preset is
	# chosen from the contract's map, not the GameState default ("old_manor").
	var map_id: String = str(GameData.get_contract_display(GameState.active_contract_order).get("map_id", "old_manor"))
	GameState.active_map_id = map_id
	_setup_environment()
	_connect_coop_listener()
	start_contract(GameState.active_contract_order)


## W6b: the only replicated mission interaction is the swinging-door state.
## Loot, AI and mission progression stay local (documented in the wave report).
func _connect_coop_listener() -> void:
	if NetManager == null or not NetManager.has_signal("world_event_applied"):
		return
	if not NetManager.world_event_applied.is_connected(_on_world_event_applied):
		NetManager.world_event_applied.connect(_on_world_event_applied)


func _on_world_event_applied(kind: String, target: Node, _from_peer: int) -> void:
	if kind != "open" and kind != "close":
		return
	if target == null or not is_instance_valid(target):
		return
	if target.is_in_group("swinging_doors") and target.has_method("apply_remote_toggle"):
		target.call("apply_remote_toggle", kind == "open")


func _setup_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	_apply_fallback_environment(e)
	var moon := DirectionalLight3D.new()
	# Stable name so QA provenance (perf_profile.config_mismatches) can find the
	# same moonlight the weather preset configured, not an authored directional
	# light from the extracted level.
	moon.name = "MissionMoon"
	_apply_fallback_moon(moon)
	# Real TAT weather first; hand-tuned values above survive any field the
	# preset does not define, and fully survive when no preset maps the map.
	# The real night sky then replaces the flat fallback color (BG_SKY);
	# MobileProfile's glow override still runs last.
	var wpreset: Dictionary = WeatherProfile.preset_for_map(GameState.active_map_id)
	WeatherProfile.apply_environment(e, moon, wpreset)
	WeatherVisuals.apply_sky(e, wpreset, moon)
	MobileProfile.apply_environment(e)
	# QA only: --perf-dir-shadow / --perf-shadow-splits /
	# --perf-shadow-max-distance. The moon exists only here (after the weather
	# preset), so perf_profile applies these last and logs the measured values
	# as PERF_SHADOW. No-op without perf flags.
	PerfProfile.apply_directional_shadow(moon, PerfProfile.collect_cli_config())
	# C3 LocalVolumetric: the Guildhall sublevel carries authored fog boxes with
	# MI_LocalVolumetricFog_Outside_Preset_A (Color .5, Global Multiplier .05,
	# EdgeFalloff .75). FogVolume needs the world volumetric pass enabled; the
	# global density stays 0 so only authored volumes contribute.
	if GameState.active_map_id == "guildhall":
		e.volumetric_fog_enabled = true
		e.volumetric_fog_density = 0.0
		e.volumetric_fog_albedo = Color(0.5, 0.5, 0.5, 1.0)
		e.volumetric_fog_emission = Color(0.02, 0.018, 0.026, 1.0)
	env.environment = e
	add_child(env)
	print("TAT-2 environment: bg=", e.background_mode, " ambient_src=", e.ambient_light_source, " ambient_energy=", e.ambient_light_energy, " ambient_color=", e.ambient_light_color, " sky=", e.sky != null, " fog=", e.fog_enabled, " fog_density=", e.fog_density)

	add_child(moon)
	light_probe.register_light(moon)
	_add_guildhall_gate_fills()
	_add_guildhall_car_lights()
	_add_guildhall_road_fills()
	_add_guildhall_foyer_fills()
	_add_guildhall_saferoom_fill()


## The extracted Guildhall gate/fence sublevel carries the iron gate, arch,
## star finials and fence, but no LightComponent on the gate pillars (the
## reference KF16 gate is warm from its carriage lamps/headlights). With only
## the cool skylight these meshes render as flat blue silhouettes. Two local,
## shadowless warm practicals light the authored metal without raising global
## ambient or flattening the rest of the map. Positions are the authored gate
## tunnel (10, 20, 100 -> 10, 22, 88) and fence/finial run (10, 24, 62 ->
## 10, 25.3, 48.7); ranges stop at 12 m, so the foyer and interior are untouched.
func _add_guildhall_gate_fills() -> void:
	if GameState.active_map_id != "guildhall":
		return
	var gate_lamp := OmniLight3D.new()
	gate_lamp.name = "GuildhallGateLampFill"
	gate_lamp.position = Vector3(11.5, 23.0, 92.0)
	gate_lamp.light_color = Color(1.0, 0.74, 0.48)
	gate_lamp.light_energy = 2.2
	gate_lamp.omni_range = 12.0
	gate_lamp.omni_attenuation = 1.2
	gate_lamp.shadow_enabled = false
	add_child(gate_lamp)
	light_probe.register_light(gate_lamp)
	var fence_lamp := OmniLight3D.new()
	fence_lamp.name = "GuildhallFenceLampFill"
	# KF16: the sign plane sits at z 48.35-49.02, so the old z 50.0 position put
	# this fill behind the sign and backlit it. Street side (z 46.0) lights the
	# fence/finial run from the audience like the reference gate.
	fence_lamp.position = Vector3(10.0, 27.0, 46.0)
	fence_lamp.light_color = Color(1.0, 0.76, 0.52)
	fence_lamp.light_energy = 3.5
	fence_lamp.omni_range = 16.0
	fence_lamp.omni_attenuation = 1.2
	fence_lamp.shadow_enabled = false
	add_child(fence_lamp)
	light_probe.register_light(fence_lamp)
	# KF16 ornate gate fill: the arch/finial ironwork between the carriage lamps
	# reads as a blue silhouette at night. A soft warm omni under the arch
	# (80, 20, 18 — the approach side) lifts the ornament without touching the
	# stealth cone set: deliberately NOT registered with light_probe.
	var ornate_fill := OmniLight3D.new()
	ornate_fill.name = "GuildhallOrnateGateFill"
	ornate_fill.position = Vector3(80.0, 20.0, 18.0)
	ornate_fill.light_color = Color(1.0, 0.76, 0.52)
	ornate_fill.light_energy = 1.5
	ornate_fill.omni_range = 11.0
	ornate_fill.omni_attenuation = 1.3
	ornate_fill.light_volumetric_fog_energy = 0.0
	ornate_fill.shadow_enabled = false
	add_child(ornate_fill)


## KF16 road lighting: the gate approach (z ~52-57) between the car and the
## arch reads as a wet cobble black hole once the headlights are re-aimed at the
## approach. Two shadowless warm omnis kiss the road surface either side of the
## approach axis. Deliberately NOT registered with light_probe (scene dressing,
## not a stealth influence) and added after the authored 160-light budget pass.
func _add_guildhall_road_fills() -> void:
	if GameState.active_map_id != "guildhall":
		return
	if MobileProfile.is_mobile():
		return
	var specs: Array = [
		["GuildhallRoadFillL", Vector3(8.6, 21.2, 52.0)],
		["GuildhallRoadFillR", Vector3(11.4, 21.2, 52.0)],
	]
	for spec: Array in specs:
		var road_fill := OmniLight3D.new()
		road_fill.name = str(spec[0])
		road_fill.position = spec[1] as Vector3
		road_fill.light_color = Color(1.0, 0.76, 0.52)
		road_fill.light_energy = 0.7
		road_fill.omni_range = 8.0
		road_fill.omni_attenuation = 1.4
		road_fill.shadow_enabled = false
		road_fill.light_volumetric_fog_energy = 0.0
		add_child(road_fill)


## KF16: the reference gate has the vintage car's headlights flashing on the wet
## cobbles under the arch, and the authored car underpass sublevel carries no
## LightComponent for them (only emissive lens geometry, which the loader's
## material path drops). Two shadowless spots recreate the authored beam at the
## car nose. They are deliberately NOT registered with light_probe: they are
## scene dressing outside the stealth cone set, so guard/player visibility is
## unchanged. Desktop only (the mobile budget stays on authored lights).
## The lens glass emission is applied separately (_override_guildhall_car_lenses)
## because it has to run after the authored sublevels are built.
func _add_guildhall_car_lights() -> void:
	if GameState.active_map_id != "guildhall":
		return
	if MobileProfile.is_mobile():
		return
	var specs: Array = [
		["GuildhallCarHeadlightL", Vector3(17.83, 19.96, 65.81), Vector3(11.0, 18.6, 54.0)],
		["GuildhallCarHeadlightR", Vector3(17.91, 19.96, 67.02), Vector3(9.0, 18.6, 57.0)],
	]
	for spec: Array in specs:
		var beam := SpotLight3D.new()
		beam.name = str(spec[0])
		beam.position = spec[1] as Vector3
		beam.light_color = Color(1.0, 0.843, 0.651)
		beam.light_energy = 4.5
		beam.spot_range = 16.0
		beam.spot_angle = 55.0
		beam.spot_attenuation = 1.0
		beam.shadow_enabled = false
		beam.light_volumetric_fog_energy = 0.0
		beam.distance_fade_enabled = true
		beam.distance_fade_begin = 25.0
		beam.distance_fade_length = 20.0
		add_child(beam)
		# Aim after add_child so look_at uses the global transform; per-light
		# targets throw the beams down the gate approach instead of the kerb.
		beam.look_at(spec[2] as Vector3, Vector3.UP)


## KF16 lens cores: SM_Automobile_Lights_B's authored slot 1 is
## MI_Automobile_Glass, and its authored emissive (MI_Glass_Automobile
## EmissiveStrength 2.0 / EmissiveTint 1.0 0.6186 0.2552) is not carried by the
## loader's material join, so the lenses render dead. Duplicate the surface
## materials per instance (the mesh resource is shared across every car) and
## enable the authored warm emission on the glass surface only. Runs after the
## Guildhall sublevels build; skips cleanly when the node is absent.
func _override_guildhall_car_lenses() -> void:
	if GameState.active_map_id != "guildhall":
		return
	if MobileProfile.is_mobile():
		return
	const LENS_TARGET: Vector3 = Vector3(17.93, 19.88, 66.41)
	var best: MeshInstance3D = null
	var best_d: float = 4.0
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh == null:
			continue
		if not str(mi.get_meta("ue_mesh", "")).contains("SM_Automobile_Lights_B"):
			continue
		var d: float = mi.global_position.distance_to(LENS_TARGET)
		if d <= best_d:
			best_d = d
			best = mi
	if best == null:
		print("TAT-2 KF16 car lenses: SM_Automobile_Lights_B node not found within 4 m of ", LENS_TARGET, "; lens emission skipped")
		return
	for s in range(best.mesh.get_surface_count()):
		if not best.mesh.surface_get_name(s).to_lower().contains("glass"):
			continue
		var mat: Material = best.get_active_material(s)
		if mat == null:
			print("TAT-2 KF16 car lenses: glass surface ", s, " has no material; lens emission skipped")
			return
		var dup: Material = mat.duplicate()
		if dup is StandardMaterial3D:
			var smat: StandardMaterial3D = dup as StandardMaterial3D
			smat.emission_enabled = true
			smat.emission = Color(1.0, 0.6186, 0.2552)
			smat.emission_energy_multiplier = 2.0
		elif dup is ShaderMaterial:
			var shmat: ShaderMaterial = dup as ShaderMaterial
			shmat.set_shader_parameter("emission_color", Vector3(1.0, 0.6186, 0.2552))
			shmat.set_shader_parameter("emission_energy", 2.0)
		best.set_surface_override_material(s, dup)
		print("TAT-2 KF16 car lenses: node=", best.name, " dist=", snappedf(best_d, 0.01), " glass_surface=", s, " emission=1.0,0.6186,0.2552 energy=2.0")
		return
	print("TAT-2 KF16 car lenses: no glass surface on ", best.name, "; lens emission skipped")


## KF16 sign letters: the split SM_Guildhall_Sign mesh keeps the 268-tri
## letter band on surface 1 with the authored gold material. Under the night
## skylight the raised caps read flat, so give only that surface a faint warm
## self-illumination (energy 0.10 — a lift, not a lamp). The surface material is
## duplicated per instance so the shared/cached sign mesh and the crest surface
## (surface 3) stay untouched. Runs after the Guildhall sublevels build.
func _add_guildhall_sign_letter_emission() -> void:
	if GameState.active_map_id != "guildhall":
		return
	if MobileProfile.is_mobile():
		return
	var found: MeshInstance3D = null
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh == null or mi.mesh.get_surface_count() != 4:
			continue
		if str(mi.get_meta("ue_mesh", "")).contains("SM_Guildhall_Sign"):
			found = mi
			break
	if found == null:
		print("TAT-2 KF16 sign letters: SM_Guildhall_Sign (4 surfaces) not found; letter emission skipped")
		return
	var src: Material = found.get_active_material(1)
	var dup: StandardMaterial3D = null
	if src is StandardMaterial3D:
		dup = (src as StandardMaterial3D).duplicate() as StandardMaterial3D
	else:
		dup = StandardMaterial3D.new()
		if src is BaseMaterial3D:
			var base: BaseMaterial3D = src as BaseMaterial3D
			dup.albedo_color = base.albedo_color
			dup.albedo_texture = base.albedo_texture
			dup.metallic = base.metallic
			dup.roughness = base.roughness
		else:
			# No usable surface material: keep the authored gold albedo.
			dup.albedo_color = Color(1.0, 0.685, 0.273)
			dup.metallic = 0.85
			dup.roughness = 0.35
	dup.emission_enabled = true
	dup.emission_texture = null
	dup.emission = Color(1.0, 0.62, 0.20)
	dup.emission_energy_multiplier = 0.10
	dup.cull_mode = BaseMaterial3D.CULL_DISABLED
	found.set_surface_override_material(1, dup)
	print("TAT-2 KF16 sign letters: node=", found.name, " surface=1 emission=", dup.emission, " energy=", dup.emission_energy_multiplier, " albedo=", dup.albedo_color)


## KF17: the reference rooftop-aim frame holds a damped clocktower silhouette in
## the mist. The port has no Guildhall skyline tower, so place the authored
## SM_DistantTowerA vista piece (same 50 m body, MI_DistantBuidingA slot) behind
## the gate on the street axis. Decorative and shadowless: no collision, no
## light_probe registration, desktop only. Needs the loaded material DB, so it
## runs after the sublevels build.
func _add_guildhall_skyline_clocktower() -> void:
	if GameState.active_map_id != "guildhall":
		return
	if MobileProfile.is_mobile():
		return
	const TOWER_UE_MESH: String = "/Game/Art/Environment/Skybox/Buildings/SM_DistantTowerA"
	# mesh_materials.json slot 0 keeps the authored material under the ML/
	# subfolder (/Game/.../Buildings/ML/MI_DistantBuidingA), not the bare
	# /Game/.../Buildings/MI_DistantBuidingA form; pass that authored path.
	const TOWER_UE_MAT: String = "/Game/Art/Environment/Skybox/Buildings/ML/MI_DistantBuidingA"
	var info: Dictionary = level_loader.call("_get_mesh_and_shape", TOWER_UE_MESH) as Dictionary
	var mesh: Mesh = info.get("mesh") as Mesh
	if mesh == null:
		print("TAT-2 KF17 clocktower: mesh missing for ", TOWER_UE_MESH, "; skipped")
		return
	var mat: Material = level_loader.call("get_material_for_ue", TOWER_UE_MAT) as Material
	if mat == null:
		print("TAT-2 KF17 clocktower: material missing for ", TOWER_UE_MAT, "; skipped")
		return
	var mi := MeshInstance3D.new()
	mi.name = "GuildhallSkylineClocktower"
	mi.mesh = mesh
	mi.position = Vector3(10.0, 20.0, -120.0)
	mi.scale = Vector3(2.6, 2.6, 2.6)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_surface_override_material(0, mat)
	add_child(mi)
	print("TAT-2 KF17 clocktower: placed ", mi.name, " mat=", TOWER_UE_MAT)


## The safe room starts the mission; under the 0.20 skylight its wood/plaster
## walls read as a black frame around the blue portal. A single neutral fill
## at the authored spawn (127.27, 26.47, -5.33) keeps the portal mood while
## making the room navigable.
func _add_guildhall_saferoom_fill() -> void:
	if GameState.active_map_id != "guildhall":
		return
	var fill := OmniLight3D.new()
	fill.name = "GuildhallSafeRoomFill"
	fill.position = Vector3(127.0, 29.0, -5.0)
	fill.light_color = Color(0.72, 0.78, 0.95)
	fill.light_energy = 1.1
	fill.omni_range = 12.0
	fill.omni_attenuation = 1.2
	fill.shadow_enabled = false
	add_child(fill)
	light_probe.register_light(fill)


## The authored Guildhall foyer is a large checkered hall with a refill
## station; its practicals are sparse, so the 0.20 skylight leaves the stone
## walls and busts near-black. Two warm, shadowless fills lift the hall
## without touching the gate or the upper floors (range 16 m, y=31).
func _add_guildhall_foyer_fills() -> void:
	if GameState.active_map_id != "guildhall":
		return
	for spec: Array in [
		[Vector3(27.0, 31.0, -53.0), 1.6],
		[Vector3(27.0, 31.0, -64.0), 1.3],
	]:
		var fill := OmniLight3D.new()
		fill.name = "GuildhallFoyerFill_%d" % int((spec[0] as Vector3).z)
		fill.position = spec[0] as Vector3
		fill.light_color = Color(1.0, 0.78, 0.55)
		fill.light_energy = float(spec[1])
		fill.omni_range = 16.0
		fill.omni_attenuation = 1.2
		fill.shadow_enabled = false
		add_child(fill)
		light_probe.register_light(fill)


## Previous hand-tuned night look. Used as the base under real weather data
## and as the full fallback when a map has no weather preset.
func _apply_fallback_environment(e: Environment) -> void:
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.028, 0.055)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.16, 0.21, 0.30)
	e.ambient_light_energy = 0.38
	e.ambient_light_sky_contribution = 0.0
	e.fog_enabled = true
	e.fog_light_color = Color(0.05, 0.08, 0.14)
	e.fog_density = 0.008
	e.glow_enabled = true
	e.glow_intensity = 0.65
	e.glow_bloom = 0.22
	e.tonemap_mode = Environment.TONE_MAPPER_ACES


func _apply_fallback_moon(moon: DirectionalLight3D) -> void:
	moon.rotation_degrees = Vector3(-48, 32, 0)
	moon.light_color = Color(0.68, 0.78, 0.98)
	moon.light_energy = 0.55
	moon.shadow_enabled = true


func start_contract(order: int) -> void:
	contract_info = GameData.get_contract_display(order)
	var map_id: String = str(contract_info.get("map_id", "old_manor"))
	_is_thieves_den = (map_id == "thieves_den")
	_mission_ready_emitted = false
	GameState.reset_run(order, map_id)
	# W1S Spider personal chain: first Guildhall deploy starts it; a later
	# deploy flushes pending electrotype messages and pins the Owl. Runs before
	# the level load so the spawn pass below sees this deploy's beat.
	var pq_deploy: Dictionary = PersonalQuestScript.on_deploy(map_id)
	var pq_transitions: Array = pq_deploy.get("transitions", []) as Array
	if not pq_transitions.is_empty():
		print("TAT-2 personal quest: deploy map=", map_id, " stage=", str(pq_deploy.get("stage", "")), " transitions=", pq_transitions.size())
	# Deterministic per-contract scene-variant seed. active_map_seed is the
	# single source of truth; a zero seed is initialised from map+contract so
	# repeated runs of the same contract reproduce the same variant set.
	if GameState.active_map_seed == 0:
		GameState.active_map_seed = LevelLoaderScript._sv_fnv1a("%s|%d" % [map_id, order]) & 0x7FFFFFFF
	var sv_selected: Array = LevelLoaderScript.select_scene_variants(map_id, GameState.active_map_seed, [] as Array[String])
	var sv_ids: Array[String] = []
	for sv_rec_v: Variant in sv_selected:
		if sv_rec_v is Dictionary:
			sv_ids.append(str((sv_rec_v as Dictionary).get("id", "")))
	GameState.active_scene_variants = sv_ids
	if not sv_ids.is_empty():
		print("TAT-2 scene variants selected=", sv_ids.size(), " seed=", GameState.active_map_seed)
	# Real match timer from the extracted DT_Missions_* tables (0 = unlimited).
	# Free play reads the selected mission row's authored limit instead (the
	# LootTheRoom Cleanout Heist is 3300 s / 55:00 at Novice) rather than the
	# hosting contract's map window, so set it after the mission id resolves.
	GameState.run_time_limit = GameData.get_match_duration(map_id, GameState.difficulty)
	_setup_mission_objectives(map_id, order)
	if GameState.free_play:
		GameState.run_time_limit = GameData.get_mission_duration(GameState.active_mission_id, GameState.difficulty)
		# Free play is the side mission itself, not the hosting contract: the
		# letter/loading screen carry the mission row title ("Cleanout Heist")
		# and its description, while the Guildhall contract order only supplies
		# map + sublevels.
		var fp_title: String = str(_active_mission_row.get("title", contract_info.get("title", "Contract")))
		var fp_desc: String = str(_active_mission_row.get("description", "")).strip_edges()
		if fp_title != "":
			contract_info["title"] = fp_title
			contract_info["mission_title"] = fp_title
		if fp_desc != "":
			contract_info["intro"] = fp_desc
			contract_info["description"] = fp_desc

	var loading: Node = LoadingScreenScript.new()
	# Root-level CanvasLayer: the menu/Den swap used to leave the loading UI
	# anchored inside a stale SubViewport, producing the 967x640 top-left tile.
	get_tree().root.add_child(loading)
	if loading.has_method("start_loading"):
		loading.call("start_loading", str(contract_info.get("title", "Contract")), _contract_clue_text(contract_info, ""), map_id)

	var sublevels: Array[String] = _map_id_to_sublevels(map_id, order)
	_loaded_level_names = _levels_from_sublevel_paths(sublevels)
	var ue_level_data: Dictionary = {}
	var light_budget: int = MobileProfile.max_lights()
	if level_loader.has_method("load_sublevels_async"):
		if level_loader.has_signal("load_progress") and loading.has_method("set_progress"):
			var prog_cb: Callable = Callable(loading, "set_progress")
			if not level_loader.is_connected("load_progress", prog_cb):
				level_loader.connect("load_progress", prog_cb)
		var async_res: Variant = await level_loader.call("load_sublevels_async", sublevels, self, light_probe, light_budget)
		if async_res is Dictionary:
			ue_level_data = async_res
		if level_loader.has_signal("load_progress") and loading.has_method("set_progress"):
			var prog_cb2: Callable = Callable(loading, "set_progress")
			if level_loader.is_connected("load_progress", prog_cb2):
				level_loader.disconnect("load_progress", prog_cb2)
	else:
		if loading.has_method("set_progress"):
			loading.call("set_progress", 0.4, "Loading sublevels...")
		ue_level_data = level_loader.load_sublevels(sublevels, self, light_probe, light_budget)
	print("TAT-2 Loaded ", map_id, ": meshes=", ue_level_data.get("mesh_instances", 0), " lights=", ue_level_data.get("light_count", 0))
	# #11: apply only exact authored SceneElement tags. Untagged spawners stay
	# untouched and are reported as unmapped; no category guessing.
	if level_loader.has_method("apply_scene_variant_overrides"):
		var sv_apply: Dictionary = level_loader.call("apply_scene_variant_overrides", map_id, GameState.active_map_seed, GameState.active_scene_variants, ue_level_data) as Dictionary
		if int(sv_apply.get("applied", 0)) > 0 or int(sv_apply.get("unmapped", 0)) > 0:
			print("TAT-2 scene variants: active=", sv_apply.get("active", 0), " applied=", sv_apply.get("applied", 0), " suppressed=", sv_apply.get("suppressed", 0), " locked=", sv_apply.get("locked", 0), " unmapped=", sv_apply.get("unmapped", 0))
	level_stats = ue_level_data
	_apply_level_atmosphere(ue_level_data)
	# KF16/KF17 dressing needs the authored sublevels (the car lens node and the
	# loaded material DB), so these run after the build, next to the gate fills.
	if map_id == "guildhall":
		_override_guildhall_car_lenses()
		_add_guildhall_skyline_clocktower()
		_add_guildhall_sign_letter_emission()
	if int(ue_level_data.get("chunk_count", 0)) > 0:
		print("TAT-2 Perf: chunks=", ue_level_data.get("chunk_count", 0), " collision_bodies=", ue_level_data.get("collision_bodies", 0), " collision_shapes=", ue_level_data.get("collision_shapes", 0), " occluders=", ue_level_data.get("occluder_count", 0))

	# Safety floor plane far below map so player never falls into void if stepping outside bounds
	_add_safety_floor()

	_setup_thieves_den_env(map_id)

	_spawn_player(ue_level_data.get("player_spawns", []), ue_level_data.get("player_spawn_transforms", []), ue_level_data)
	var weather_preset: Dictionary = WeatherProfile.preset_for_map(map_id)
	rain_node = WeatherVisuals.make_rain(self, weather_preset)
	lens_rain_node = WeatherVisuals.make_lens_rain(self, weather_preset)
	if player != null and hud != null:
		if player.has_signal("thief_vision_toggled") and hud.has_method("set_thief_vision"):
			player.thief_vision_toggled.connect(hud.set_thief_vision)

	var anchor: Vector3 = player.global_position if player != null else Vector3.ZERO
	if map_id == "thieves_den":
		_setup_thieves_den_hub(anchor, ue_level_data)
	else:
		_spawn_guards(ue_level_data.get("guard_spawns", []), anchor, ue_level_data.get("patrol_paths", []))
		_spawn_loot_and_quest(ue_level_data, anchor)
		_spawn_loot_containers(ue_level_data)
		_audit_loot_economy()
		_spawn_clues(ue_level_data.get("loot_spawns", []), anchor)
		# W1S: after the contract clue pass, add the Spider personal actors the
		# current beat pins (Library note, Vault Owl, Lounge courier, Old Manor
		# informant). Never on the Den hub.
		_spawn_personal_quest_actors()
		_spawn_escape(ue_level_data.get("escape_points", []), anchor)
	_spawn_spawner_content(ue_level_data)
	_spawn_swinging_doors(ue_level_data)
	_spawn_devices()

	if hud.has_method("set_contract_info"):
		hud.set_contract_info(contract_info)

	if is_instance_valid(loading) and loading.has_method("finish_loading"):
		loading.call("finish_loading")

	# PG-6 audio: scene ambience beds (AU1) + S09 countdown ticks (AU4) +
	# briefing VO line (AU6). All clips are decoded Wwise OGGs via the join.
	if AudioManager != null:
		if AudioManager.has_method("play_bed_scene"):
			AudioManager.play_bed_scene(map_id)
		if not _is_thieves_den:
			if AudioManager.has_method("start_countdown"):
				AudioManager.start_countdown()
			if AudioManager.has_method("play_vo"):
				AudioManager.play_vo("fairy_intro")

	if not _is_thieves_den:
		_trigger_mission_start_letter()

	# Load completion is the signal boundary: everything above (level build,
	# player, AI, loot/clues/doors/devices, loading-screen finish) is done.
	if not _mission_ready_emitted:
		_mission_ready_emitted = true
		print("TAT-2 mission_ready map=", map_id, " meshes=", int(level_stats.get("mesh_instances", 0)), " lights=", int(level_stats.get("light_count", 0)), " chunks=", int(level_stats.get("chunk_count", 0)))
		mission_ready.emit(map_id, level_stats)


func _setup_thieves_den_env(map_id: String) -> void:
	if map_id != "thieves_den":
		return
	for child in get_children():
		if child is WorldEnvironment:
			var wenv: WorldEnvironment = child as WorldEnvironment
			if wenv.environment != null:
				var den_env: Environment = wenv.environment
				den_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
				den_env.ambient_light_color = Color(0.06, 0.08, 0.12)
				den_env.ambient_light_energy = 0.12
				den_env.background_color = Color(0.012, 0.016, 0.032)
				# Den P0 authored look (FIX_SPEC): the UE MidnightClear_ThievesDen
				# preset is graded with AGX and a 1.9 exposure bias. Keep the
				# room dark (ambient above stays <= 0.15 for Suite 34b) while
				# the warm practicals carry the scene. Glow is a restrained
				# 4-level stack (0-3) so the map-table lamp/gold glass bloom
				# warm instead of clipping white. Vignette/GainHighlights stay
				# at their inactive authored values (never forced on here).
				den_env.tonemap_mode = Environment.TONE_MAPPER_AGX
				den_env.tonemap_exposure = 1.9
				# Den P1 shadow-toe: layer an additive toe on the level-load LUT
				# (ThievesDenTest_P LocalExposure 1.2 / 0.6 / 0.25) instead of
				# replacing it. The bump is +2.2% at black and falls smoothly to
				# zero at 3%, so the P0.1 midtones/highlights keep their base
				# curve (measured LUT-only: p50 +0.1..+0.2, p95 +0.0) while the
				# darkest-half shadow median lifts +1.3..+2.2 units. No
				# auto-exposure, no global mapping change. The pre-P1 LUT is
				# kept for the KF05 scope view (see _set_ponder_shadow_toe).
				_den_env = den_env
				if _den_lut_legacy == null:
					# First call: the level loader has already applied the
					# authored LocalExposure LUT; keep that as the KF05 baseline.
					_den_lut_legacy = den_env.adjustment_color_correction as GradientTexture1D
				_den_lut_p1 = WeatherProfile.build_shadow_toe_lut(1.2, 0.6, 0.25, 0.022, 0.030)
				den_env.adjustment_color_correction = _den_lut_p1
				den_env.adjustment_enabled = true
				den_env.adjustment_brightness = 1.0
				den_env.adjustment_saturation = 0.95
				var glow_allowed: bool = not MobileProfile.is_mobile() or MobileProfile.glow_enabled()
				den_env.glow_enabled = glow_allowed
				if glow_allowed:
					den_env.glow_intensity = 0.45
					den_env.glow_bloom = 0.15
					den_env.glow_hdr_threshold = 0.85
					den_env.glow_hdr_scale = 1.25
					for gl_i: int in range(4):
						den_env.set_glow_level(gl_i, true)
					den_env.set_glow_level(4, false)


## Applies level-authored atmosphere entries extracted from the UE maps.
## Runs after fallback -> weather preset -> mobile overrides, most specific
## last; the existing ordering is otherwise untouched. Only fields Godot
## supports are mapped — Lumen/UE-only post-process fields are logged as
## unmappable and leave the environment unchanged.
func _apply_level_atmosphere(stats: Dictionary) -> void:
	var wenv: WorldEnvironment = null
	for child in get_children():
		if child is WorldEnvironment:
			wenv = child as WorldEnvironment
			break
	if wenv == null or wenv.environment == null:
		return
	var env: Environment = wenv.environment
	var sky: Dictionary = stats.get("sky_light", {})
	if not sky.is_empty() and float(sky.get("intensity", 0.0)) > 0.0:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_energy = clampf(float(sky.get("intensity", 0.0)) * 0.2, 0.02, 1.0)
		var scol: Variant = sky.get("color", null)
		if scol is Array and (scol as Array).size() >= 3:
			env.ambient_light_color = _level_color(scol)
	var fog: Dictionary = stats.get("fog_volume", {})
	if not fog.is_empty() and float(fog.get("density", 0.0)) > 0.0:
		env.fog_enabled = true
		# Same UE -> Godot density scale as weather_profile.
		env.fog_density = float(fog.get("density", 0.0)) * 0.01
		var insc: Variant = fog.get("inscattering", null)
		if insc is Array and (insc as Array).size() >= 3:
			env.fog_light_color = _level_color(insc)
	var pp: Dictionary = stats.get("post_process", {})
	if not pp.is_empty():
		_apply_level_post_process(env, pp)


## Accepts both 0-255 UE bytes and 0-1 floats (HeightFog inscattering is
## already 0-1 while RectLight colours are 0-255).
func _level_color(arr: Array) -> Color:
	var r := float(arr[0])
	var g := float(arr[1])
	var b := float(arr[2])
	if maxf(r, maxf(g, b)) > 1.0:
		return Color(r / 255.0, g / 255.0, b / 255.0)
	return Color(r, g, b)


## Maps only the post-process fields Godot supports (same scales as
## weather_profile). Lumen/UE-only fields — e.g. LumenSkylightLeaking,
## LumenFullSkylightLeakingDistance, LocalExposure* — have no Godot
## counterpart and are reported, not guessed.
func _apply_level_post_process(env: Environment, pp: Dictionary) -> void:
	var settings: Dictionary = pp.get("settings", {})
	if settings.is_empty():
		return
	var mapped: int = 0
	if settings.has("BloomIntensity"):
		# Den RD cap: level post-process BloomIntensity re-enables glow after
		# the weather preset; clamp lower and keep levels 0-1 only (2 textures).
		var is_den_map: bool = str(GameState.active_map_id) == "thieves_den"
		# PG-1: level post-process must not re-enable glow the mobile
		# PERFORMANCE tier turned off (fill-rate budget for 60 FPS).
		var glow_allowed: bool = not MobileProfile.is_mobile() or MobileProfile.glow_enabled()
		env.glow_enabled = glow_allowed
		if glow_allowed:
			var glow_cap: float = 0.32 if is_den_map else 0.8
			env.glow_intensity = clampf(float(settings["BloomIntensity"]) * 0.08, 0.0, glow_cap)
			if is_den_map:
				env.glow_hdr_scale = 1.0
				env.glow_bloom = 0.10
				for gl_i: int in range(2):
					env.set_glow_level(gl_i, true)
				for gl_off: int in range(2, 5):
					env.set_glow_level(gl_off, false)
		mapped += 1
	if settings.has("Saturation"):
		env.adjustment_enabled = true
		env.adjustment_saturation = float(settings["Saturation"])
		mapped += 1
	var unmapped: Array[String] = []
	for k in settings.keys():
		var ks := str(k)
		if ks != "BloomIntensity" and ks != "Saturation" and ks != "unbound":
			unmapped.append(ks)
	if mapped == 0:
		print("TAT-2 post_process '", str(pp.get("source_actor", "?")), "' carries only Lumen/UE-only settings (", ", ".join(unmapped), "); nothing Godot-mappable, environment unchanged")


func _map_id_to_sublevels(map_id: String, order: int = 2) -> Array[String]:
	# Base map geometry/gameplay/loot lists (kept as extracted). The old
	# zero-padded Contract-number wildcard entry is gone: real per-contract
	# sublevels from the extracted tables (GameData.get_contract_sublevels)
	# are appended when present, never duplicating a path.
	var base: Array[String] = []
	match map_id:
		"old_manor":
			base = [
				"res://data/generated/levels/OldManor/OldManor_P.tatlevel.json",
				"res://data/generated/levels/OldManor/OldManor_Geo.tatlevel.json",
				"res://data/generated/levels/OldManor/OldManor_Landscape.tatlevel.json",
				"res://data/generated/levels/OldManor/OldManor_Gameplay.tatlevel.json",
				"res://data/generated/levels/OldManor/OldManor_Loot.tatlevel.json",
				"res://data/generated/levels/OldManor/OldManor_PickUps.tatlevel.json",
				"res://data/generated/levels/OldManor/OldManor_Clues.tatlevel.json",
				"res://data/generated/levels/OldManor/OldManor_Contracts.tatlevel.json",
				"res://data/generated/levels/OldManor/OldManor_SkyboxGeo.tatlevel.json",
			]
		"guildhall":
			base = [
				"res://data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI.tatlevel.json",
				"res://data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI_3rdFloor.tatlevel.json",
				"res://data/generated/levels/Buildings/Guildhall/Guildhall_Vault_CeremonialChambers.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_P.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_Geometry.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_Landscape.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_LightingNoGameplay.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_LocalVolumetric.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_PeripheryA.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_Loot.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_Contracts.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_SetSpawners.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_MissionClues.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_SkyboxGeo.tatlevel.json",
			]
		"thieves_den":
			base = [
				"res://data/generated/levels/ThievesDen/ThievesDen_Geo.tatlevel.json",
				"res://data/generated/levels/ThievesDenTest/ThievesDenTest_P.tatlevel.json",
				"res://data/generated/levels/ThievesDenTest/ThievesDenTest_Periphery.tatlevel.json",
			]
		"ftue":
			# Steam's tutorial map set. The old key was "jaspering_hall", a scene
			# that does not exist in the shipped game, and it loaded only 4 of the
			# 10 authored FTUE sublevels.
			for ftue_sub: String in GameData.get_ftue_sublevels():
				base.append("res://data/generated/levels/FTUE/%s.tatlevel.json" % ftue_sub)
	if base.is_empty():
		return base
	for sub: String in GameData.get_contract_sublevels(order):
		if not base.has(sub):
			base.append(sub)
	return base


## Godot 4.7.2 leaks the ReflectionProbe atlas (7 texture RIDs) at exit;
## default ON for fidelity. CI/QA can pass --no-den-probe, set
## TAT2_NO_DEN_PROBE=1, or set tat2/den_reflection_probe=false.
func _den_probe_enabled() -> bool:
	if OS.has_environment("TAT2_NO_DEN_PROBE"):
		return false
	for args: PackedStringArray in [OS.get_cmdline_user_args(), OS.get_cmdline_args()]:
		for arg: String in args:
			if arg == "--no-den-probe":
				return false
	return bool(ProjectSettings.get_setting("tat2/den_reflection_probe", true))


func _setup_thieves_den_hub(anchor: Vector3, ue_level_data: Dictionary = {}) -> void:
	# W1S: returning to the Den is when the pending Spider electrotype messages
	# arrive (letter -> electrotype). Idempotent; the deploy hook may have
	# already flushed them.
	var pq_hub: Dictionary = PersonalQuestScript.on_hub_enter()
	if str(pq_hub.get("reason", "")) == "advanced":
		print("TAT-2 personal quest: hub stage=", str(pq_hub.get("stage", "")))
	# Authored Den practicals carry the room; the hand fills stay subtle:
	# attic 0.15 + moon shaft 0.25 + wardrobe 0.20 + wisp 0.30 = 0.90 total
	# (Suite 34b keeps the <= 2.0 contract). The old fake map-table candle +
	# DenTableLight duplicated the authored desk spot and were removed.
	var attic_fill := OmniLight3D.new()
	attic_fill.name = "DenAtticFill"
	attic_fill.position = anchor + Vector3(1.5, 2.6, -1.5)
	attic_fill.light_color = Color(1.0, 0.78, 0.50)
	attic_fill.light_energy = 0.15
	attic_fill.omni_range = 8.0
	attic_fill.omni_attenuation = 1.2
	attic_fill.add_to_group("den_hand_fills")
	add_child(attic_fill)
	light_probe.register_light(attic_fill)

	# P0.1 balance: a short-range floor/room fill so the authored practicals do
	# not leave the floor and lower walls crushed without washing out the
	# window view. Warm-neutral 0.40 / 8 m / attenuation 2.0 at ~1 m above the
	# floor. It joins den_hand_fills so the Suite 34b budget stays honest
	# (0.15 + 0.40 + 0.25 + 0.20 + 0.30 = 1.30 <= 2.0).
	var room_fill := OmniLight3D.new()
	room_fill.name = "DenRoomFill"
	room_fill.position = Vector3(1.3, anchor.y + 1.05, 271.4)
	room_fill.light_color = Color(1.0, 0.85, 0.68)
	room_fill.light_energy = 0.40
	room_fill.omni_range = 8.0
	room_fill.omni_attenuation = 2.0
	room_fill.shadow_enabled = false
	room_fill.add_to_group("den_hand_fills")
	add_child(room_fill)
	light_probe.register_light(room_fill)

	# Arched east window moonlight shaft (authored geometry, not hand values).
	# UE WindowBorder StaticMeshComponent0 at cm
	# (523.73975, 26666.291, 4064.7085) -> port m
	# (5.2374, 40.6471, 266.6629). The shaft lands mid-room on the
	# scope->window sightline: L = 6.1076 m is the horizontal
	# WindowBorder->floor-shell-center distance (UE SM_ThievesDen shell/floor
	# at cm (132.74524, 27135.502, 3957.8376) -> port
	# (1.3275, 39.5784, 271.355)), stepped back from the window along the
	# sightline axis with Y on the floor plane (F1 rule). outward
	# (= win_pos - beam_target) therefore extends the scope->window axis past
	# the wall, so the ponder ray threads the collider gap onto the vista.
	var win_pos: Vector3 = Vector3(5.2374, 40.6471, 266.6629)
	var moon_beam := SpotLight3D.new()
	moon_beam.name = "DenMoonBeam"
	moon_beam.position = win_pos
	moon_beam.light_color = Color(0.55, 0.82, 0.96)
	moon_beam.light_energy = 0.25
	moon_beam.spot_range = 14.0
	moon_beam.spot_angle = 6.0
	moon_beam.spot_attenuation = 2.0
	moon_beam.shadow_enabled = true
	moon_beam.add_to_group("den_hand_fills")
	add_child(moon_beam)
	var beam_target: Vector3 = Vector3(-0.4317, anchor.y + 0.1, 268.9349)
	moon_beam.look_at(beam_target, Vector3.UP)
	light_probe.register_light(moon_beam)
	VfxManager.spawn_window_godray(self, win_pos, beam_target)
	_spawn_den_window_vista(win_pos, beam_target)

	# Authored window backlight assistant: a small shadowless cool omni just
	# outside the glass so the frosted panes read like KF02/KF06 instead of a
	# black hole. Deliberately NOT a hand fill: total stays 0.90. The authored
	# BP_MoonShape_C_5 plane itself is unhidden by the loader.
	var window_backlight := OmniLight3D.new()
	window_backlight.name = "DenWindowBacklight"
	window_backlight.position = Vector3(5.75, 41.1, 266.3)
	window_backlight.light_color = Color(0.45, 0.78, 0.95)
	window_backlight.light_energy = 0.6
	window_backlight.omni_range = 4.0
	window_backlight.omni_attenuation = 2.0
	window_backlight.shadow_enabled = false
	add_child(window_backlight)
	light_probe.register_light(window_backlight)

	# Single interior ReflectionProbe for Thieves' Den specular reflections.
	# Godot 4.7.2 leaks the probe atlas color buffer + 6 views at exit
	# (godot#122498, fixed in 4.8). Keep the node for the test contract, but
	# skip the capture when the QA/CI opt-out is set.
	var den_probe: ReflectionProbe = ReflectionProbe.new()
	den_probe.name = "ThievesDenReflectionProbe"
	den_probe.position = Vector3(1.5, 42.0, 271.5)
	den_probe.size = Vector3(20.0, 10.0, 16.0)
	den_probe.interior = true
	den_probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	den_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	if not _den_probe_enabled():
		# Godot 4.7.2 has no UPDATE_DISABLED enum; hiding the probe prevents
		# the one-shot atlas capture while keeping the test-visible node.
		den_probe.visible = false
		print("TAT-2 Den reflection probe: disabled (TAT2_NO_DEN_PROBE/--no-den-probe/setting)")
	den_probe.intensity = 0.8
	add_child(den_probe)
	_den_reflection_probe = den_probe

	# F1 ground-placement rule: authored tatlevel positions are UE-grounded
	# (ThievesDen_Geo, 348 exports — per-prop StaticMeshComponent AttachParent
	# + relative transform vs BodySetup bounds) and are used as-is. Hand
	# fallback offsets are built from the floor (anchor = floor-grounded
	# player spawn) upward: floor-standing props sit at floor_y, table-top
	# items add the hand table height on top. Nothing floats on a bare offset.
	var floor_y: float = anchor.y
	var desk_positions: Array = ue_level_data.get("desk_positions", [])
	var desk_pos: Vector3 = Vector3(anchor.x + 3.2, floor_y + 0.8, anchor.z - 2.5)
	if not desk_positions.is_empty() and desk_positions[0] is Vector3:
		desk_pos = desk_positions[0] as Vector3
	_den_map_table_pos = desk_pos
	# Den P1 KF10: re-aim + raise the authored desk spot onto the map table
	# (authored lights are already built by the level loader at this point).
	_aim_den_desk_spot(desk_pos)

	# Den paper P2: the old 2.0 downward DenMapTableBounce spot is gone. The
	# parchment now self-lights (emission pass below) and a soft near-table
	# shade fill closes the shadow side without a hard cone.
	# den_hand_fills total: 1.30 + 0.60 = 1.90 <= 2.01 (Suite 34b).
	if not MobileProfile.is_mobile():
		var shade_fill := OmniLight3D.new()
		shade_fill.name = "DenShadeFill"
		shade_fill.position = Vector3(4.011, 41.7004, 267.5435)
		shade_fill.light_color = Color(1.0, 0.74, 0.42)
		shade_fill.light_energy = 0.60
		shade_fill.omni_range = 3.0
		shade_fill.omni_attenuation = 1.5
		shade_fill.light_specular = 0.0
		shade_fill.shadow_enabled = false
		shade_fill.light_volumetric_fog_energy = 0.0
		shade_fill.add_to_group("den_hand_fills")
		add_child(shade_fill)
		light_probe.register_light(shade_fill)

	_apply_den_parchment_emission()

	# Interactive Map Table -> opens ContractTableUI (diegetic HUD prompt, no giant Label3D billboard)
	var desk_area := Area3D.new()
	desk_area.name = "DenMapTableArea"
	desk_area.position = desk_pos
	desk_area.add_to_group("interactables")
	# W2 interaction LOS target: just above the authored map-table surface, not
	# the desk origin (which sits inside the tabletop mesh).
	desk_area.set_meta("interaction_point", desk_pos + Vector3.UP * 0.35)
	var dcol := CollisionShape3D.new()
	var dsph := SphereShape3D.new()
	dsph.radius = 2.2
	dcol.shape = dsph
	desk_area.add_child(dcol)
	var desk_script := GDScript.new()
	desk_script.source_code = """extends Area3D
var mission_ctrl: Node = null
func get_interact_prompt() -> String:
\treturn "[F] ENTER MATCH"
func interact(_actor: Node) -> void:
\tif mission_ctrl != null and mission_ctrl.has_method("open_contract_table_ui"):
\t\tmission_ctrl.open_contract_table_ui()
"""
	desk_script.reload()
	desk_area.set_script(desk_script)
	desk_area.set("mission_ctrl", self)
	add_child(desk_area)

	# Miniature 3D buildings on the Map Table (Elway Manor & Constables' Guildhall)
	_spawn_map_table_miniatures(desk_pos)

	# Rolltop Desk Open Ledger -> [F] READ LEDGER (Journal & Black Market) + Blue Wisp VFX
	var ledger_positions: Array = ue_level_data.get("ledger_positions", [])
	var ledger_pos: Vector3 = Vector3(anchor.x + 3.4, floor_y + 0.95, anchor.z + 1.8)
	if not ledger_positions.is_empty() and ledger_positions[0] is Vector3:
		ledger_pos = (ledger_positions[0] as Vector3) + Vector3(0.0, 0.12, 0.0)
	var wisp_node: Node3D = VfxManager.spawn_blue_wisp(self, ledger_pos + Vector3(-0.35, 0.42, -0.15), 0.30)
	if wisp_node != null:
		var wisp_light: Node = wisp_node.get_node_or_null("WispLight")
		if wisp_light is Light3D:
			(wisp_light as Light3D).add_to_group("den_hand_fills")
	var ledger_area := Area3D.new()
	ledger_area.name = "DenLedgerArea"
	ledger_area.position = ledger_pos
	ledger_area.add_to_group("interactables")
	ledger_area.set_meta("interaction_point", ledger_pos + Vector3.UP * 0.7)
	var lcol := CollisionShape3D.new()
	var lsph := SphereShape3D.new()
	lsph.radius = 1.6
	lcol.shape = lsph
	ledger_area.add_child(lcol)
	var l_script := GDScript.new()
	l_script.source_code = """extends Area3D
var mission_ctrl: Node = null
func get_interact_prompt() -> String:
\treturn "[F] READ LEDGER"
func interact(_actor: Node) -> void:
\tif mission_ctrl != null and mission_ctrl.has_method("open_ledger_ui"):
\t\tmission_ctrl.open_ledger_ui()
"""
	l_script.reload()
	ledger_area.set_script(l_script)
	ledger_area.set("mission_ctrl", self)
	add_child(ledger_area)

	# Telescope -> [F] PONDER. UE BP_HidingSpot_Telescope_C_1 Root in
	# ThievesDenTest_P:PersistentLevel sits at UE cm
	# (-492.02435, 27073.371, 4011.2234) -> port m (-4.9202, floor, 270.7337);
	# the tripod is floor-standing (F1 rule), so Y snaps to floor_y instead of
	# the stale 41.0 hand value. SM_TeleScope BodySetup_1 + MI_TeleScope_Inst.
	_den_telescope_pos = Vector3(-4.9202, floor_y, 270.7337)
	var tele_area := Area3D.new()
	tele_area.name = "DenTelescopeArea"
	tele_area.position = _den_telescope_pos
	tele_area.add_to_group("interactables")
	tele_area.set_meta("interaction_point", _den_telescope_pos + Vector3.UP * 1.4)
	var tcol := CollisionShape3D.new()
	var tsph := SphereShape3D.new()
	tsph.radius = 1.8
	tcol.shape = tsph
	tele_area.add_child(tcol)
	var tele_script := GDScript.new()
	tele_script.source_code = """extends Area3D
var mission_ctrl: Node = null
func get_interact_prompt() -> String:
\tif mission_ctrl != null and mission_ctrl.get("_ponder_active") == true:
\t\treturn "[F] EXIT"
\treturn "[F] PONDER"
func interact(_actor: Node) -> void:
\tif mission_ctrl != null and mission_ctrl.has_method("toggle_telescope_ponder"):
\t\tmission_ctrl.toggle_telescope_ponder()
"""
	tele_script.reload()
	tele_area.set_script(tele_script)
	tele_area.set("mission_ctrl", self)
	add_child(tele_area)

	# Trunk Decoration Pedestal + Gramophone
	_spawn_thieves_den_props(anchor)
	# P0.1: the wardrobe shelf gear (knockout grenade + stun truncheon) carries
	# authored emissive maps (strength 1.5/2.0) that clip white under AGX 1.9.
	# Tone only those Den display instances down; shared pickup materials are
	# duplicated and other maps are untouched.
	_tone_down_den_shelf_gear()

	# Interactive Bureau / Wardrobe -> opens WardrobeUI (diegetic HUD prompt, no giant Label3D billboard)
	var wardrobe_positions: Array = ue_level_data.get("wardrobe_positions", [])
	var wardrobe_pos: Vector3 = Vector3(anchor.x - 2.6, floor_y, anchor.z - 2.0)
	if not wardrobe_positions.is_empty() and wardrobe_positions[0] is Vector3:
		wardrobe_pos = wardrobe_positions[0] as Vector3
	var ward_light := OmniLight3D.new()
	ward_light.name = "DenWardLight"
	ward_light.position = wardrobe_pos + Vector3(0.0, 1.1, 0.4)
	ward_light.light_color = Color(1.0, 0.82, 0.55)
	ward_light.light_energy = 0.20
	ward_light.omni_range = 5.0
	ward_light.add_to_group("den_hand_fills")
	add_child(ward_light)
	light_probe.register_light(ward_light)

	var ward_area := Area3D.new()
	ward_area.name = "DenWardrobeArea"
	ward_area.position = wardrobe_pos
	ward_area.add_to_group("interactables")
	ward_area.set_meta("interaction_point", wardrobe_pos + Vector3.UP * 1.2)
	var wcol := CollisionShape3D.new()
	var wsph := SphereShape3D.new()
	wsph.radius = 2.2
	wcol.shape = wsph
	ward_area.add_child(wcol)
	var ward_script := GDScript.new()
	ward_script.source_code = """extends Area3D
var mission_ctrl: Node = null
func get_interact_prompt() -> String:
\treturn "[F] CUSTOMIZE LOADOUT"
func interact(_actor: Node) -> void:
\tif mission_ctrl != null and mission_ctrl.has_method("open_wardrobe_ui"):
\t\tmission_ctrl.open_wardrobe_ui()
"""
	ward_script.reload()
	ward_area.set_script(ward_script)
	ward_area.set("mission_ctrl", self)
	add_child(ward_area)

	# IS-2: the den spawn faces the hub. Authored PlayerStart yaw is kept when
	# it already faces the map table; otherwise the spawn rotates to face the
	# table so first sight is the hub (map table + telescope wall), never a
	# wall. The logged before-angle is the <=30 deg proof.
	if player != null and _den_map_table_pos != Vector3.ZERO:
		var to_hub: Vector3 = _den_map_table_pos - player.global_position
		to_hub.y = 0.0
		if to_hub.length() > 0.05:
			var hub_dir: Vector3 = to_hub.normalized()
			var facing_now: Vector3 = -player.global_transform.basis.z
			facing_now.y = 0.0
			var misalign_deg: float = 180.0
			if facing_now.length() > 0.05:
				misalign_deg = rad_to_deg(facing_now.normalized().angle_to(hub_dir))
			var rotated: bool = misalign_deg > 30.0
			if rotated:
				player.rotation = Vector3(0.0, atan2(-hub_dir.x, -hub_dir.z), 0.0)
			print("TAT-2 den spawn hub-facing: misalign_before_deg=", snappedf(misalign_deg, 0.1), " rotated_to_face=", rotated, " table=", _den_map_table_pos)


## Den paper P2: the authored map parchment (SM_Map_ThievesDen, MI_Map_ThievesDen)
## sits on the desk in deep shade now that the hard downward bounce is gone.
## Give it a faint self-lit parchment wash instead: duplicate the instance
## material (the mesh/material is shared with OldManor via the level loader's
## cache, so the shared resource is never mutated) and multiply a warm
## emission by the albedo so the ink/crease detail survives.
func _apply_den_parchment_emission() -> void:
	const PARCHMENT_ENERGY: float = 0.20
	for n: Node in find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if not str(mi.get_meta("ue_mesh", "")).contains("SM_Map_ThievesDen"):
			continue
		var base: Material = mi.get_surface_override_material(0)
		if base == null:
			base = mi.mesh.surface_get_material(0)
		if not base is StandardMaterial3D:
			continue
		var parchment: StandardMaterial3D = (base as StandardMaterial3D).duplicate() as StandardMaterial3D
		if parchment == null:
			continue
		parchment.emission_enabled = true
		parchment.emission_texture = parchment.albedo_texture
		parchment.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		parchment.emission = Color(1.0, 0.92, 0.82)
		parchment.emission_energy_multiplier = PARCHMENT_ENERGY
		mi.set_surface_override_material(0, parchment)
		print("TAT-2 Den parchment emission: node=", mi.name, " energy=", PARCHMENT_ENERGY)
		return


## P0.1: damp the Den wardrobe shelf gear emissive. The knockout grenade
## (EmissiveStrength 1.5) and stun truncheon (2.0) clip to white when the
## authored emissive maps meet AGX 1.9 + 0.85 glow. Materials are duplicated
## per instance so pickups/other maps keep their authored emission.
func _tone_down_den_shelf_gear() -> void:
	for n: Node in find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var ue: String = str(mi.get_meta("ue_mesh", "")).to_lower()
		if ue.find("knockoutgrenade") < 0 and ue.find("sm_truncheon") < 0:
			continue
		for s: int in range(mi.mesh.get_surface_count()):
			var m: Material = mi.get_surface_override_material(s)
			if m == null:
				m = mi.mesh.surface_get_material(s)
			if m is StandardMaterial3D:
				var dup: StandardMaterial3D = (m as StandardMaterial3D).duplicate()
				# Matte the display copies so the nearby wardrobe wall spot does
				# not produce a clipped specular ball, and damp the emissive map.
				dup.roughness = maxf(dup.roughness, 0.95)
				dup.metallic_specular = minf(dup.metallic_specular, 0.10)
				dup.emission_energy_multiplier = minf(dup.emission_energy_multiplier, 0.20)
				mi.set_surface_override_material(s, dup)


func open_wardrobe_ui() -> void:
	var ui: CanvasLayer = WardrobeUIScript.new()
	add_child(ui)
	if ui.has_method("open_customizer"):
		ui.call("open_customizer")


func open_ledger_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 20
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var ui: Control = LedgerUIScript.new()
	layer.add_child(ui)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if ui.has_signal("closed"):
		ui.connect("closed", func() -> void:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			if is_instance_valid(layer):
				layer.queue_free()
		)


func _spawn_map_table_miniatures(desk_pos: Vector3) -> void:
	_den_tokens.clear()
	var miniatures: Array[Dictionary] = [
		{
			"name": "MapTokenOldManor",
			"map_id": "old_manor",
			"ue_mesh": "/Game/Art/UI/Map/SM_MapBuilding_OldManor",
			"ue_mat": "/Game/Art/UI/Map/M_MapBuilding_OldManor",
			"offset": Vector3(-0.32, 0.02, -0.08),
			# UE-derived token size: SM_MapBuilding_OldManor ExtendedBounds
			# SphereRadius 45.56192 vs SM_MapBuilding_GuildHall 27.39531
			# (extracted/json/Art/UI/Map/SM_MapBuilding_*.json, StaticMesh
			# ExtendedBounds). GuildHall keeps the port base 0.24; OldManor
			# scales by the UE SphereRadius ratio (~0.399).
			"scale": 0.24 * (45.56192 / 27.39531),
		},
		{
			"name": "MapTokenGuildHall",
			"map_id": "guildhall",
			"ue_mesh": "/Game/Art/UI/Map/SM_MapBuilding_GuildHall",
			"ue_mat": "/Game/Art/UI/Map/M_MapBuilding_GuildHall",
			"offset": Vector3(0.28, 0.02, 0.10),
			# UE anchor of the token-size ratio above (GuildHall SphereRadius
			# 27.39531); base kept at the port 0.24.
			"scale": 0.24,
		},
		# The invented "jaspering_hall" token was removed: Steam ships no such
		# map, scene or token mesh. The tutorial route is "ftue".
	]
	for item: Dictionary in miniatures:
		if bool(item.get("fallback_token", false)):
			_add_fallback_map_token(item, desk_pos)
			continue
		var ue_mesh: String = str(item["ue_mesh"])
		var ue_mat: String = str(item["ue_mat"])
		var mesh: Mesh = null
		if level_loader != null and level_loader.has_method("_get_mesh_and_shape"):
			var info: Dictionary = level_loader.call("_get_mesh_and_shape", ue_mesh)
			mesh = info.get("mesh") as Mesh
		if mesh == null:
			# Never silent: a missing token mesh must name its UE path so
			# the GH token can never vanish quietly (round-2 GH-mini fix).
			push_error("[mission_controller] missing mesh for UE path %s; skipping map token %s (%s)" % [ue_mesh, str(item["name"]), str(item["map_id"])])
			assert(false, "missing map token mesh: " + ue_mesh)
			continue
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = str(item["name"])
		mi.mesh = mesh
		if level_loader != null and level_loader.has_method("get_material_for_ue"):
			var tok_mat: Material = level_loader.call("get_material_for_ue", ue_mat) as Material
			if tok_mat != null:
				# Duplicate per token so warm golden emissive highlight toggles
				# independently while keeping StandardMaterial3D + albedo_texture intact.
				var inst_mat: Material = tok_mat.duplicate() as Material
				for s: int in range(mesh.get_surface_count()):
					mi.set_surface_override_material(s, inst_mat if inst_mat != null else tok_mat)
		mi.position = desk_pos + (item["offset"] as Vector3)
		var sc: float = float(item["scale"])
		mi.scale = Vector3(sc, sc, sc)
		# UE-derived per-token base for the selection grow/shrink below.
		mi.set_meta("minis_base", sc)
		mi.add_to_group("map_table_tokens")
		add_child(mi)
		_den_tokens[str(item["map_id"])] = mi
	_update_map_token_highlights()


## P1 Jaspering fallback token: procedural stand-in so the expansion map is
## selectable/previewable despite the missing authored mesh. Loud by design
## (UE SM_MapBuilding_* family has no Jaspering entry in extracted data).
func _add_fallback_map_token(item: Dictionary, desk_pos: Vector3) -> void:
	push_warning("[mission_controller] Jaspering Hall has no authored Den token mesh; using a procedural fallback (UE SM_MapBuilding_* family)")
	var mi := MeshInstance3D.new()
	mi.name = str(item.get("name", "MapTokenFallback"))
	var bm := BoxMesh.new()
	bm.size = Vector3(0.30, 0.10, 0.22)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.42, 0.20)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.72, 0.24)
	mat.emission_energy_multiplier = 0.0
	mi.set_surface_override_material(0, mat)
	mi.position = desk_pos + (item.get("offset", Vector3.ZERO) as Vector3)
	var sc: float = float(item.get("scale", 0.20))
	mi.scale = Vector3(sc, sc, sc)
	mi.set_meta("minis_base", sc)
	mi.add_to_group("map_table_tokens")
	add_child(mi)
	_den_tokens[str(item.get("map_id", "jaspering_hall"))] = mi


func _update_map_token_highlights() -> void:
	# Selection grow/shrink (KF10/S08 KILCAIRN tokens: the selected map token
	# reads larger with a warm-gold emissive). Per-token bases are UE-derived
	# (minis_base meta, see _spawn_map_table_miniatures); 1.15x/0.25s is port
	# presentation — no UE scale timeline exists in cooked data (F4 backlog:
	# material-param vs timeline undecided). Highlight energies kept
	# (active 0.85 / inactive 0.0).
	const MINIS_SELECT_GROW := 1.15
	const MINIS_GROW_TIME := 0.25
	for mid_v: Variant in _den_tokens.keys():
		var mid: String = str(mid_v)
		var mi_v: Variant = _den_tokens.get(mid, null)
		if not (mi_v is MeshInstance3D) or not is_instance_valid(mi_v as Node):
			continue
		var mi: MeshInstance3D = mi_v as MeshInstance3D
		var active: bool = (mid == _den_selected_map_id)
		var base_sc: float = float(mi.get_meta("minis_base", mi.scale.x))
		var target_sc: float = base_sc * MINIS_SELECT_GROW if active else base_sc
		var target_scale := Vector3(target_sc, target_sc, target_sc)
		if mi.is_inside_tree():
			if mi.has_meta("minis_tween"):
				var old_tw: Tween = mi.get_meta("minis_tween") as Tween
				if old_tw != null and old_tw.is_valid():
					old_tw.kill()
			var tw: Tween = mi.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.tween_property(mi, "scale", target_scale, MINIS_GROW_TIME)
			mi.set_meta("minis_tween", tw)
		else:
			mi.scale = target_scale
		var surf_cnt: int = mi.mesh.get_surface_count() if mi.mesh != null else 0
		for s: int in range(surf_cnt):
			var mat: Material = mi.get_surface_override_material(s)
			if mat is StandardMaterial3D:
				var sm: StandardMaterial3D = mat as StandardMaterial3D
				sm.emission_enabled = active
				if active:
					sm.emission = Color(1.0, 0.72, 0.24)
					sm.emission_energy_multiplier = 1.4
				else:
					sm.emission = Color.BLACK
					sm.emission_energy_multiplier = 0.0


## P1 Jaspering-Hall-unpreviewable roster: selectable Den maps in one place so
## set_den_selected_map and the gaze path cannot drift (P2 gaze bypass).
static func is_selectable_den_map(map_id: String) -> bool:
	return map_id == "old_manor" or map_id == "guildhall" or map_id == "ftue"


func set_den_selected_map(map_id: String) -> void:
	if not is_selectable_den_map(map_id):
		push_warning("[mission_controller] rejecting non-selectable Den map (UE Den map table): ", map_id)
		return
	if _den_selected_map_id == map_id:
		return
	_den_selected_map_id = map_id
	_update_map_token_highlights()
	_refresh_den_lookat_card(true)


func cycle_den_difficulty() -> void:
	GameState.difficulty = (GameState.difficulty % 3) + 1
	_refresh_den_lookat_card(true)


func cycle_den_mode() -> void:
	GameState.active_mission_mode = "Co-op" if GameState.active_mission_mode == "Solo" else "Solo"
	_refresh_den_lookat_card(true)


func get_den_lookat_card() -> Dictionary:
	return _den_lookat_card.duplicate(true)


## F5 window vista (procedural replica). The loader hides authored moonshape
## billboards (they cook to gray quads; the real sky carries the moon disc)
## and the Den wall keeps only the collision split + moonbeam shaft, so the
## arched east window showed no exterior. This stages the exterior the UE
## level authors in the same PersistentLevel (ThievesDen_Geo, 348 exports):
## full moon BP_MoonShape_C_1 (SM_Shape_Sphere at UE cm
## (750.6698, 27377.701, 4185.192)), seven companion glow discs
## (BP_MoonShape_C_0/C_2..C_7), glass shell SM_ThievesDen_Glass + frame
## SM_ThievesDen_WindowBorder (UE cm (523.73975, 26666.291, 4064.7085)).
## The replica is laid along the scope->window axis: the hub seats
## beam_target on that sightline (telescope UE Root cm
## (-492.02435, 27073.371, 4011.2234)), so outward extends the axis past the
## wall and the ponder ray threads the collider gap.
## Staging matches KF05 (00:20.80): Kilcairn rooftop/chimney silhouettes,
## bright full moon, giant golden cheese wedge with 3 orbiting chunks.
## Sizes are framed from KF05 for the 13 deg ponder zoom (frame half-width
## ~3.9 m at the 34 m focus): moon 2.2 m radius, rooftop row inside +/-4.5 m,
## cheese center-frame below the moon.
## Decorative only: no collision, no occluder, unshaded materials.
func _spawn_den_window_vista(win_pos: Vector3, beam_target: Vector3) -> void:
	var old: Node = get_node_or_null("DenWindowVista")
	if old != null:
		old.queue_free()
	var outward: Vector3 = win_pos - beam_target
	# UE-fed axis: win_pos is the WindowBorder port and beam_target sits on
	# the scope->window sightline, so outward extends that axis past the wall
	# (the ponder ray threads the collider gap onto the focus below).
	outward.y = 0.0
	if outward.length() < 0.01:
		outward = Vector3(-1.0, 0.0, 0.0)
	outward = outward.normalized()
	var side: Vector3 = outward.cross(Vector3.UP).normalized()
	var root := Node3D.new()
	root.name = "DenWindowVista"
	root.position = win_pos
	add_child(root)
	var moon := MeshInstance3D.new()
	moon.name = "VistaMoon"
	var moon_mesh := SphereMesh.new()
	# KF05-framed: 2.2 m radius at ~49 m from the scope eye subtends ~5 deg,
	# sharing the 13 deg ponder frame with the rooftops + cheese below.
	moon_mesh.radius = 2.2
	moon_mesh.height = 4.4
	moon.mesh = moon_mesh
	var moon_mat := StandardMaterial3D.new()
	moon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	moon_mat.albedo_color = Color(0.92, 0.95, 0.88)
	moon_mat.emission_enabled = true
	moon_mat.emission = Color(0.92, 0.95, 0.88)
	moon_mat.emission_energy_multiplier = 1.6
	moon.set_surface_override_material(0, moon_mat)
	# Moon rides low on the axis (+3 m over the window) so the sightline
	# through the opening lands it inside the ponder frame (KF05).
	moon.position = outward * 38.0 + Vector3(0.0, 3.0, 0.0)
	root.add_child(moon)
	var sil_mat := StandardMaterial3D.new()
	sil_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sil_mat.albedo_color = Color(0.03, 0.045, 0.09)
	# KF05-framed row: +/-3.2 m lateral + 1.3 m half-width fits the 13 deg
	# frame (~3.9 m half-width at the 30 m roof line).
	var roof_heights: Array[float] = [3.0, 5.5, 2.2, 7.0, 4.2]
	for i in range(roof_heights.size()):
		var h: float = roof_heights[i]
		var block := MeshInstance3D.new()
		block.name = "VistaRoof%d" % i
		var box := BoxMesh.new()
		box.size = Vector3(2.6, h, 5.0)
		block.mesh = box
		block.set_surface_override_material(0, sil_mat)
		block.position = outward * 30.0 + side * (float(i) * 1.6 - 3.2) + Vector3(0.0, h * 0.5 - 4.0, 0.0)
		root.add_child(block)
	var cheese_mat := StandardMaterial3D.new()
	cheese_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cheese_mat.albedo_color = Color(1.0, 0.78, 0.25)
	cheese_mat.emission_enabled = true
	cheese_mat.emission = Color(1.0, 0.72, 0.2)
	cheese_mat.emission_energy_multiplier = 0.9
	var wedge := MeshInstance3D.new()
	wedge.name = "VistaCheese"
	var wedge_mesh := BoxMesh.new()
	wedge_mesh.size = Vector3(4.2, 2.0, 3.0)
	wedge.mesh = wedge_mesh
	wedge.set_surface_override_material(0, cheese_mat)
	# Center-frame below the moon (KF05 cheese-against-moon composition).
	wedge.position = outward * 30.0 + Vector3(0.0, 1.5, 0.0)
	wedge.rotation = Vector3(0.0, 0.6, 0.35)
	root.add_child(wedge)
	for c in range(3):
		var chunk := MeshInstance3D.new()
		chunk.name = "VistaCheeseChunk%d" % c
		var chunk_mesh := BoxMesh.new()
		chunk_mesh.size = Vector3(0.7, 0.7, 0.7)
		chunk.mesh = chunk_mesh
		chunk.set_surface_override_material(0, cheese_mat)
		chunk.position = wedge.position + Vector3(cos(float(c) * TAU / 3.0) * 3.2, 0.8 + 0.5 * float(c), sin(float(c) * TAU / 3.0) * 3.2)
		chunk.rotation = Vector3(0.3 * float(c), 0.5 * float(c), 0.2 * float(c))
		root.add_child(chunk)
	# On-axis focus: the ray from the scope eye through the window opening
	# lands here, so the ponder frame centers on the staged vista (KF05).
	root.set_meta("focus", root.position + outward * 34.0 + Vector3(0.0, 0.65, 0.0))
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.albedo_color = Color(0.6, 0.8, 0.9, 0.18)
	var halo := MeshInstance3D.new()
	halo.name = "VistaHalo"
	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = 4.0
	halo_mesh.height = 8.0
	halo.mesh = halo_mesh
	halo.set_surface_override_material(0, halo_mat)
	halo.position = moon.position
	root.add_child(halo)


## KF05 camera-space diorama framing. Everything below is authored in
## DenTelescopeCam space (13 deg, 16:9) so the vista composition is fixed
## regardless of where the tripod stands. Screen fractions are measured from
## KF05 (00:20.80): moon (0.708, 0.150) r=0.055 W, cheese wheel centre
## (0.470, 0.462) r=0.145 H, chunks to its left/right, distant rooftops from
## the 0.66 line down, near roof band below 0.76. The KILCAIRN SKYLINE card
## occupies top-centre 0.39..0.61 x 0.02..0.24, so moon and roofs stay clear.
static var _ponder_sky_tex: ImageTexture = null
static var _ponder_glow_tex: ImageTexture = null


func _ponder_half_frame(depth: float) -> Vector2:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = vp.x / maxf(vp.y, 1.0)
	var half_h: float = tan(deg_to_rad(_ponder_cam.fov * 0.5)) * depth
	return Vector2(half_h * aspect, half_h)


func _ponder_at(nx: float, ny: float, depth: float) -> Vector3:
	var half: Vector2 = _ponder_half_frame(depth)
	return Vector3((nx - 0.5) * 2.0 * half.x, (0.5 - ny) * 2.0 * half.y, -depth)


func _ponder_wh(w_frac: float, h_frac: float, depth: float) -> Vector2:
	var half: Vector2 = _ponder_half_frame(depth)
	return Vector2(w_frac * 2.0 * half.x, h_frac * 2.0 * half.y)


func _ponder_hash(ix: int, iy: int) -> float:
	var n: int = ix * 374761393 + iy * 668265263
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0x7FFFFFFF) / 2147483647.0


func _ponder_vnoise(x: float, y: float) -> float:
	var ix: int = int(floor(x))
	var iy: int = int(floor(y))
	var fx: float = x - float(ix)
	var fy: float = y - float(iy)
	var sx: float = fx * fx * (3.0 - 2.0 * fx)
	var sy: float = fy * fy * (3.0 - 2.0 * fy)
	var a: float = _ponder_hash(ix, iy)
	var b: float = _ponder_hash(ix + 1, iy)
	var c: float = _ponder_hash(ix, iy + 1)
	var d: float = _ponder_hash(ix + 1, iy + 1)
	return lerpf(lerpf(a, b, sx), lerpf(c, d, sx), sy)


func _ponder_fbm(x: float, y: float) -> float:
	var total: float = 0.0
	var amp: float = 0.55
	var freq: float = 1.0
	for _i in range(4):
		total += _ponder_vnoise(x * freq, y * freq) * amp
		freq *= 2.0
		amp *= 0.5
	return total


## Baked teal night sky: vertical gradient + two fbm cloud layers, plus a
## sparse star field in the upper third. Cached across ponder enters.
func _ponder_sky_texture() -> ImageTexture:
	if _ponder_sky_tex != null:
		return _ponder_sky_tex
	var w: int = 384
	var h: int = 216
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGB8)
	var top := Color(0.100, 0.180, 0.230)
	var mid := Color(0.120, 0.260, 0.320)
	var low := Color(0.240, 0.470, 0.530)
	var cloud_dark := Color(0.050, 0.120, 0.145)
	var cloud_lit := Color(0.300, 0.550, 0.600)
	for y in range(h):
		var v: float = float(y) / float(h - 1)
		var base: Color = top.lerp(mid, smoothstep(0.0, 0.55, v))
		base = base.lerp(low, smoothstep(0.60, 1.0, v))
		for x in range(w):
			var u: float = float(x) / float(w - 1)
			var n1: float = _ponder_fbm(u * 4.2 + 9.1, v * 6.2 + 3.7)
			var n2: float = _ponder_fbm(u * 10.5 + 21.3, v * 14.0 + 7.9)
			var cloud: float = smoothstep(0.38, 0.66, n1 * 0.78 + n2 * 0.22)
			# Dark cloud tops, moonlit teal cloud bases near the horizon.
			var ccol: Color = cloud_dark.lerp(cloud_lit, smoothstep(0.30, 0.90, v))
			var col: Color = base.lerp(ccol, cloud * 0.80)
			# Long dark cloud shelf across the upper third (KF05).
			var shelf: float = smoothstep(0.085, 0.0, absf(v - 0.20 - 0.06 * sin(u * 5.2 + 1.3)))
			col = col.lerp(cloud_dark, shelf * 0.25)
			if v < 0.30 and _ponder_hash(int(u * 900.0), int(v * 520.0)) > 0.9992:
				col = col.lerp(Color(0.80, 0.90, 0.92), 0.40)
			img.set_pixel(x, y, col)
	_ponder_sky_tex = ImageTexture.create_from_image(img)
	return _ponder_sky_tex


func _ponder_glow_texture() -> ImageTexture:
	if _ponder_glow_tex != null:
		return _ponder_glow_tex
	var n: int = 96
	var img: Image = Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in range(n):
		for x in range(n):
			var d: float = Vector2(float(x), float(y)).distance_to(Vector2(n - 1, n - 1) * 0.5) / (float(n) * 0.5)
			var a: float = pow(clampf(1.0 - d, 0.0, 1.0), 2.6) * 0.55
			img.set_pixel(x, y, Color(0.74, 0.87, 0.93, a))
	_ponder_glow_tex = ImageTexture.create_from_image(img)
	return _ponder_glow_tex


func _ponder_surface_tri(st: SurfaceTool, a: Vector3, ca: Color, b: Vector3, cb: Color, c: Vector3, cc: Color, n: Vector3) -> void:
	st.set_normal(n)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_normal(n)
	st.set_color(cc)
	st.add_vertex(c)
	return


## Godot treats clockwise winding as front-facing; the wheel fan is authored
## CCW for readable maths, so emit it reversed.
func _ponder_surface_tri_cw(st: SurfaceTool, a: Vector3, ca: Color, b: Vector3, cb: Color, c: Vector3, cc: Color, n: Vector3) -> void:
	_ponder_surface_tri(st, a, ca, c, cc, b, cb, n)


## Pac-man cheese wheel: a solid disc with a wedge cut facing -X, extruded
## along Z with flat mouth faces. Vertex colours shade the front, rim and cut.
func _ponder_cheese_wheel_mesh(radius: float, thickness: float, mouth_deg: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_t: float = thickness * 0.5
	var start_a: float = deg_to_rad(220.0)
	var arc: float = deg_to_rad(360.0 - mouth_deg)
	var segs: int = 56
	var front_c := Vector3(0.0, 0.0, half_t)
	var back_c := Vector3(0.0, 0.0, -half_t)
	var bright := Color(1.0, 0.82, 0.10)
	var rimc := Color(1.0, 0.74, 0.05)
	var cutc := Color(0.58, 0.36, 0.02)
	var dark := Color(0.42, 0.26, 0.02)
	var front: Array[Vector3] = []
	var back: Array[Vector3] = []
	var fcols: Array[Color] = []
	for i in range(segs + 1):
		var a: float = start_a + arc * float(i) / float(segs)
		var p := Vector3(cos(a) * radius, sin(a) * radius, 0.0)
		front.append(p + Vector3(0.0, 0.0, half_t))
		back.append(p + Vector3(0.0, 0.0, -half_t))
		# Moonlight from the upper-right: bake a rind highlight into the rim.
		var shade: float = 0.68 + 0.32 * (0.5 + 0.5 * cos(a - deg_to_rad(50.0)))
		fcols.append(Color(rimc.r * shade, rimc.g * shade, rimc.b * shade))
	for i in range(segs):
		var f0: Vector3 = front[i]
		var f1: Vector3 = front[i + 1]
		var b0: Vector3 = back[i]
		var b1: Vector3 = back[i + 1]
		var c0: Color = fcols[i]
		var c1: Color = fcols[i + 1]
		_ponder_surface_tri_cw(st, front_c, bright, f0, c0, f1, c1, Vector3.BACK)
		_ponder_surface_tri_cw(st, back_c, dark, b1, dark, b0, dark, Vector3.FORWARD)
		var mid_a: float = start_a + arc * (float(i) + 0.5) / float(segs)
		var rn := Vector3(cos(mid_a), sin(mid_a), 0.0)
		_ponder_surface_tri_cw(st, f0, c0, b0, dark, b1, dark, rn)
		_ponder_surface_tri_cw(st, f0, c0, b1, dark, f1, c1, rn)
	# Mouth faces: lower jaw at start_a, upper jaw at start_a + arc.
	var lo_f: Vector3 = front[0]
	var lo_b: Vector3 = back[0]
	var hi_f: Vector3 = front[segs]
	var hi_b: Vector3 = back[segs]
	var lo_a: float = start_a
	var lo_n := Vector3(sin(lo_a), -cos(lo_a), 0.0)
	_ponder_surface_tri_cw(st, front_c, cutc, lo_b, cutc, lo_f, cutc, lo_n)
	_ponder_surface_tri_cw(st, front_c, cutc, back_c, cutc, lo_b, cutc, lo_n)
	var hi_a: float = start_a + arc
	var hi_n := Vector3(-sin(hi_a), cos(hi_a), 0.0)
	_ponder_surface_tri_cw(st, front_c, cutc, hi_f, cutc, hi_b, cutc, hi_n)
	_ponder_surface_tri_cw(st, front_c, cutc, hi_b, cutc, back_c, cutc, hi_n)
	return st.commit()


func _ponder_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var n: Vector3 = (b - a).cross(c - a).normalized()
	var centroid: Vector3 = (a + b + c + d) * 0.25
	if n.dot(centroid) < 0.0:
		var tmp: Vector3 = b
		b = d
		d = tmp
		n = (b - a).cross(c - a).normalized()
	_ponder_surface_tri_cw(st, a, col, b, col, c, col, n)
	_ponder_surface_tri_cw(st, a, col, c, col, d, col, n)


## Cheese wedge chunk: a trapezoid prism with the +X top edge cut down, so it
## reads as a broken-off cheese block instead of a cube.
func _ponder_cheese_chunk_mesh(size: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx: float = size.x * 0.5
	var hy: float = size.y * 0.5
	var hz: float = size.z * 0.5
	var drop: float = hy * 1.15
	var v0 := Vector3(-hx, -hy, hz)
	var v1 := Vector3(hx, -hy, hz)
	var v2 := Vector3(hx, hy - drop, hz)
	var v3 := Vector3(-hx, hy, hz)
	var v4 := Vector3(-hx, -hy, -hz)
	var v5 := Vector3(hx, -hy, -hz)
	var v6 := Vector3(hx, hy - drop, -hz)
	var v7 := Vector3(-hx, hy, -hz)
	var face := Color(0.95, 0.70, 0.06)
	var topc := Color(1.0, 0.86, 0.14)
	var sidec := Color(0.78, 0.48, 0.03)
	var botc := Color(0.42, 0.26, 0.02)
	_ponder_quad(st, v0, v1, v2, v3, face)
	_ponder_quad(st, v5, v4, v7, v6, sidec)
	_ponder_quad(st, v0, v4, v5, v1, botc)
	_ponder_quad(st, v3, v2, v6, v7, topc)
	_ponder_quad(st, v4, v0, v3, v7, sidec)
	_ponder_quad(st, v1, v5, v6, v2, sidec)
	return st.commit()


func _ponder_roof_block(root: Node3D, name: String, mat: Material, nx: float, ny_top: float, w_frac: float, depth: float, ny_base: float = 1.16) -> void:
	var wh: Vector2 = _ponder_wh(w_frac, ny_base - ny_top, depth)
	var box := BoxMesh.new()
	box.size = Vector3(wh.x, wh.y, 0.35 + depth * 0.03)
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = box
	mi.set_surface_override_material(0, mat)
	mi.position = _ponder_at(nx, (ny_top + ny_base) * 0.5, depth)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


func _ponder_chimney(root: Node3D, name: String, mat: Material, nx: float, ny_top: float, w_frac: float, ny_bottom: float, depth: float) -> void:
	var wh: Vector2 = _ponder_wh(w_frac, ny_bottom - ny_top, depth)
	var box := BoxMesh.new()
	box.size = Vector3(wh.x, wh.y, 0.30)
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = box
	mi.set_surface_override_material(0, mat)
	mi.position = _ponder_at(nx, (ny_top + ny_bottom) * 0.5, depth)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


func _spawn_ponder_vista() -> void:
	if _ponder_cam == null:
		return
	if _ponder_vista != null and is_instance_valid(_ponder_vista):
		_ponder_vista.queue_free()
		_ponder_cheese = null
	var root := Node3D.new()
	root.name = "PonderVista"
	_ponder_cam.add_child(root)
	_ponder_vista = root
	# Render only the diorama while pondering: the room/ceiling is layer 1 and
	# would otherwise occlude the camera-space vista at close range.
	_ponder_cam.cull_mask = 2

	# Sky card: baked teal gradient + clouds far behind every silhouette.
	var sky := MeshInstance3D.new()
	sky.name = "VistaSky"
	var sky_mesh := QuadMesh.new()
	# Sized just past the 16:9 frame at 30 m so the baked gradient's dark top
	# and bright horizon are both visible instead of only its middle band.
	sky_mesh.size = Vector2(16.0, 7.6)
	sky.mesh = sky_mesh
	var sky_mat := StandardMaterial3D.new()
	sky_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sky_mat.albedo_texture = _ponder_sky_texture()
	sky_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	sky_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sky_mat.disable_fog = true
	sky.set_surface_override_material(0, sky_mat)
	sky.position = Vector3(0.0, 0.0, -30.0)
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sky)

	# Full moon: KF05 (0.708, 0.150), r = 0.055 W at 21 m.
	var moon_pos: Vector3 = _ponder_at(0.708, 0.150, 21.0)
	var moon_r: float = 0.055 * 2.0 * _ponder_half_frame(21.0).x
	var moon := MeshInstance3D.new()
	moon.name = "VistaMoon"
	var moon_mesh := SphereMesh.new()
	moon_mesh.radius = moon_r
	moon_mesh.height = moon_r * 2.0
	moon_mesh.radial_segments = 48
	moon_mesh.rings = 24
	moon.mesh = moon_mesh
	var mmat := StandardMaterial3D.new()
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmat.albedo_color = Color(0.92, 0.95, 0.88)
	mmat.emission_enabled = true
	mmat.emission = Color(0.92, 0.95, 0.88)
	mmat.emission_energy_multiplier = 2.6
	mmat.disable_fog = true
	var moon_tex: Texture2D = load("res://assets/ue/Raw/Art/Environment/City/Architecture/BeautifulCorner/Materials/T_Moon_D.png") as Texture2D
	if moon_tex != null:
		mmat.albedo_texture = moon_tex
		mmat.emission_texture = moon_tex
	moon.set_surface_override_material(0, mmat)
	moon.position = moon_pos
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(moon)
	var glow := MeshInstance3D.new()
	glow.name = "VistaMoonGlow"
	var glow_mesh := QuadMesh.new()
	glow_mesh.size = Vector2(moon_r * 2.8, moon_r * 2.8)
	glow.mesh = glow_mesh
	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_mat.albedo_texture = _ponder_glow_texture()
	glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow_mat.disable_fog = true
	glow_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	glow.set_surface_override_material(0, glow_mat)
	glow.position = moon_pos + Vector3(0.0, 0.0, -0.15)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glow)

	var sil_near := StandardMaterial3D.new()
	sil_near.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sil_near.albedo_color = Color(0.006, 0.011, 0.016)
	sil_near.disable_fog = true
	var sil_mid := StandardMaterial3D.new()
	sil_mid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sil_mid.albedo_color = Color(0.016, 0.032, 0.042)
	sil_mid.disable_fog = true
	var sil_far := StandardMaterial3D.new()
	sil_far.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sil_far.albedo_color = Color(0.030, 0.060, 0.070)
	sil_far.disable_fog = true

	# Far horizon row: narrow stepped blocks with sky gaps between them so the
	# distant skyline stays serrated instead of merging into the near roofs.
	var far_row: Array[Array] = [
		[0.285, 0.712, 0.038], [0.330, 0.700, 0.030], [0.372, 0.706, 0.042],
		[0.420, 0.692, 0.032], [0.462, 0.700, 0.040], [0.508, 0.686, 0.030],
		[0.548, 0.696, 0.036], [0.588, 0.682, 0.032], [0.628, 0.700, 0.040],
		[0.670, 0.676, 0.030], [0.706, 0.690, 0.042], [0.752, 0.684, 0.030],
		[0.792, 0.700, 0.040], [0.836, 0.688, 0.032], [0.876, 0.696, 0.042],
		[0.920, 0.684, 0.030], [0.958, 0.700, 0.040],
	]
	for i in range(far_row.size()):
		var fr: Array = far_row[i]
		_ponder_roof_block(root, "VistaFarRoof%d" % i, sil_far, float(fr[0]), float(fr[1]), float(fr[2]), 22.0, 1.20)
	var far_pots: Array[Array] = [
		[0.330, 0.666, 0.009], [0.462, 0.658, 0.010], [0.588, 0.650, 0.009],
		[0.670, 0.648, 0.009], [0.792, 0.662, 0.010], [0.876, 0.652, 0.009],
	]
	for i in range(far_pots.size()):
		var fp: Array = far_pots[i]
		_ponder_chimney(root, "VistaFarPot%d" % i, sil_far, float(fp[0]), float(fp[1]), float(fp[2]), float(fp[1]) + 0.045, 22.0)

	# Mid roofline: the long centre roof behind the cheese + its chimneys.
	_ponder_roof_block(root, "VistaMidRoof0", sil_mid, 0.465, 0.635, 0.260, 15.0, 1.16)
	_ponder_roof_block(root, "VistaMidRoof1", sil_mid, 0.355, 0.662, 0.100, 15.0, 1.16)
	_ponder_roof_block(root, "VistaMidRoof2", sil_mid, 0.600, 0.655, 0.120, 15.0, 1.16)
	_ponder_roof_block(root, "VistaMidRoof3", sil_mid, 0.800, 0.660, 0.080, 15.0, 1.16)
	_ponder_chimney(root, "VistaMidPot0", sil_mid, 0.445, 0.592, 0.011, 0.635, 15.0)
	_ponder_chimney(root, "VistaMidPot1", sil_mid, 0.492, 0.582, 0.013, 0.635, 15.0)
	_ponder_chimney(root, "VistaMidPot2", sil_mid, 0.545, 0.596, 0.010, 0.635, 15.0)

	# Near-left building mass + stepped roofline + chimney row (KF05 left).
	_ponder_roof_block(root, "VistaLeftTower", sil_near, 0.018, 0.455, 0.045, 9.5, 1.16)
	_ponder_roof_block(root, "VistaLeftStep", sil_near, 0.060, 0.555, 0.050, 9.5, 1.16)
	_ponder_roof_block(root, "VistaLeftRoof", sil_near, 0.125, 0.615, 0.185, 9.5, 1.16)
	_ponder_roof_block(root, "VistaLeftRoof2", sil_near, 0.230, 0.660, 0.060, 9.5, 1.16)
	_ponder_roof_block(root, "VistaLeftParapet", sil_near, 0.125, 0.598, 0.200, 9.3, 0.616)
	_ponder_chimney(root, "VistaLeftPot0", sil_near, 0.105, 0.505, 0.010, 0.615, 9.4)
	_ponder_chimney(root, "VistaLeftPot1", sil_near, 0.128, 0.486, 0.012, 0.615, 9.4)
	_ponder_chimney(root, "VistaLeftPot2", sil_near, 0.152, 0.518, 0.010, 0.615, 9.4)
	_ponder_chimney(root, "VistaLeftPot3", sil_near, 0.175, 0.538, 0.009, 0.615, 9.4)
	_ponder_chimney(root, "VistaLeftStack", sil_near, 0.140, 0.548, 0.022, 0.615, 9.4)

	# Near-right chimney stack + far-right tall block (KF05 right edge).
	_ponder_roof_block(root, "VistaRightStack", sil_near, 0.735, 0.405, 0.085, 9.2, 0.95)
	_ponder_chimney(root, "VistaRightPot0", sil_near, 0.705, 0.368, 0.010, 0.405, 9.1)
	_ponder_chimney(root, "VistaRightPot1", sil_near, 0.727, 0.358, 0.011, 0.405, 9.1)
	_ponder_chimney(root, "VistaRightPot2", sil_near, 0.750, 0.370, 0.010, 0.405, 9.1)
	_ponder_chimney(root, "VistaRightPot3", sil_near, 0.772, 0.380, 0.009, 0.405, 9.1)
	_ponder_roof_block(root, "VistaRightLow", sil_near, 0.800, 0.550, 0.060, 9.2, 0.95)
	_ponder_roof_block(root, "VistaRightTower", sil_mid, 0.965, 0.430, 0.100, 11.0, 1.12)
	_ponder_roof_block(root, "VistaRightTowerStep", sil_mid, 0.925, 0.520, 0.050, 11.0, 1.12)

	# Near foreground roof band across the bottom third (KF05 0.76 -> frame).
	var lip_mat := StandardMaterial3D.new()
	lip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lip_mat.albedo_color = Color(0.018, 0.030, 0.038)
	lip_mat.disable_fog = true
	_ponder_roof_block(root, "VistaNearRoof", sil_near, 0.500, 0.765, 1.300, 5.2, 1.20)
	_ponder_roof_block(root, "VistaNearRoofLip", lip_mat, 0.500, 0.748, 1.300, 5.0, 0.768)

	# Golden cheese wheel: pac-man bite facing left, centre-left of frame.
	var cheese_mat := StandardMaterial3D.new()
	cheese_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cheese_mat.vertex_color_use_as_albedo = true
	cheese_mat.vertex_color_is_srgb = true
	cheese_mat.emission_enabled = true
	cheese_mat.emission = Color(1.0, 0.58, 0.02)
	cheese_mat.emission_energy_multiplier = 0.55
	cheese_mat.disable_fog = true
	var cheese := MeshInstance3D.new()
	cheese.name = "VistaCheese"
	cheese.mesh = _ponder_cheese_wheel_mesh(0.334, 0.155, 78.0)
	cheese.set_surface_override_material(0, cheese_mat)
	cheese.position = _ponder_at(0.470, 0.462, 10.0)
	cheese.rotation = Vector3(0.0, deg_to_rad(-8.0), deg_to_rad(2.0))
	cheese.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(cheese)
	_ponder_cheese = cheese
	var chunk_specs: Array[Array] = [
		[0.297, 0.397, 0.095, 0.120, 18.0, 20.0, 9.4],
		[0.396, 0.423, 0.052, 0.042, 24.0, -12.0, 9.4],
		[0.700, 0.515, 0.082, 0.072, -14.0, -20.0, 8.9],
	]
	for c in range(chunk_specs.size()):
		var cs: Array = chunk_specs[c]
		var chunk_depth: float = float(cs[6])
		var wh: Vector2 = _ponder_wh(float(cs[2]), float(cs[3]), chunk_depth)
		var chunk := MeshInstance3D.new()
		chunk.name = "VistaCheeseChunk%d" % c
		chunk.mesh = _ponder_cheese_chunk_mesh(Vector3(wh.x, wh.y, wh.y * 0.9))
		chunk.set_surface_override_material(0, cheese_mat)
		chunk.position = _ponder_at(float(cs[0]), float(cs[1]), chunk_depth)
		chunk.rotation = Vector3(deg_to_rad(-12.0), deg_to_rad(float(cs[4])), deg_to_rad(float(cs[5])))
		chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(chunk)
	for child: Node in root.get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).layers = 2


func toggle_telescope_ponder() -> void:
	if not _is_thieves_den:
		push_warning("[mission_controller] toggle_telescope_ponder called outside thieves_den; ignoring")
		return
	# F dispatch guard: Area.interact (player _unhandled_input) and the
	# lookat path below both route here on the same keypress, so an
	# unguarded toggle would fire twice and collapse to a no-op. Collapse
	# same-frame re-entry so F flips ponder exactly once per press.
	var frame_now: int = Engine.get_process_frames()
	# has_meta first: get_meta on a missing key logs a Godot ERROR even with
	# a default, which would bury the single-fire proof line in noise.
	var last_toggle: int = int(get_meta("ponder_toggle_frame")) if has_meta("ponder_toggle_frame") else -1
	if last_toggle == frame_now:
		return
	set_meta("ponder_toggle_frame", frame_now)
	_ponder_active = not _ponder_active
	# KF05 safeguard: the P1 black lift would also wash the unshaded vista
	# silhouettes, so the scope view runs on the level-load LUT and the P1 toe
	# comes back on exit (see _set_ponder_shadow_toe).
	_set_ponder_shadow_toe(_ponder_active)
	if _ponder_active:
		# F6: real zoom view against UE values. Authored rig is
		# BP_HidingSpot_Telescope_C_1 in ThievesDenTest_P:PersistentLevel:
		# MainMesh yaw 60.08 deg, Camera rel (10, 0, 170) cm yaw 148 deg —
		# eye 1.7 m above the tripod base, aimed out the east window at the
		# KF05 vista (rooftops, full moon, golden cheese, [F] EXIT).
		# No cooked FOV exists on the UE CameraComponent, so the zoom
		# (13 deg) is framed from KF05 (moon + rooftops in one frame).
		if _ponder_cam == null or not is_instance_valid(_ponder_cam):
			_ponder_cam = Camera3D.new()
			_ponder_cam.name = "DenTelescopeCam"
			_ponder_cam.fov = 13.0
			add_child(_ponder_cam)
		# Global-space eye: the tripod's world position plus the UE camera
		# rel (10, 0, 170) cm -> port m (0.1, 1.7, 0.0). Refreshed on every
		# enter (not just at creation) so a moved tripod stays framed.
		var tele_global: Vector3 = _den_telescope_pos
		var tele_area: Node = get_node_or_null("DenTelescopeArea")
		if tele_area is Node3D:
			tele_global = (tele_area as Node3D).global_position
		_ponder_cam.global_position = tele_global + Vector3(0.1, 1.7, 0.0)
		# On-axis fallback focus (3x the UE scope->window port delta) when
		# the replica is absent; the vista focus meta wins when present.
		var focus: Vector3 = _den_telescope_pos + Vector3(10.1576, 0.55, -4.0708) * 3.0
		var vista: Node = get_node_or_null("DenWindowVista")
		if vista != null and vista.has_meta("focus"):
			var focus_v: Variant = vista.get_meta("focus")
			if focus_v is Vector3:
				focus = focus_v
		_ponder_cam.look_at(focus, Vector3.UP)
		_ponder_cam.current = true
		_spawn_ponder_vista()
		# S05 rooftop wind swell (KF 00:19.6-00:21.9, peaks -39.5 dBFS RMS
		# = the wind bed trim): opt-in bed, off again on exit.
		if AudioManager != null and AudioManager.has_method("start_bed"):
			AudioManager.start_bed("wind")
		# Log-count proof: exactly one ponder-enter line per F press (the
		# frame guard above collapses the Area + lookat double dispatch).
		print("TAT-2 telescope ponder-enter: cam=", _ponder_cam.name, " current=", _ponder_cam.current, " fov=", _ponder_cam.fov, " eye=", _ponder_cam.global_position)
	else:
		if _ponder_vista != null and is_instance_valid(_ponder_vista):
			_ponder_vista.queue_free()
			_ponder_vista = null
			_ponder_cheese = null
		if _ponder_cam != null and is_instance_valid(_ponder_cam):
			_ponder_cam.current = false
			_ponder_cam.cull_mask = 0xFFFFF
		if player != null and is_instance_valid(player):
			var pcam_v: Variant = player.get("cam")
			if pcam_v is Camera3D and is_instance_valid(pcam_v as Node):
				(pcam_v as Camera3D).current = true
		if AudioManager != null and AudioManager.has_method("stop_bed"):
			AudioManager.stop_bed("wind")
		print("TAT-2 telescope ponder-exit")
	_refresh_den_lookat_card(true)


## Den P1 KF10: the authored desk spot (ThievesDen_Geo light #4) sits at
## (3.6446, 41.803, 267.8289) with a 6.49 m range / 80 deg cone / 2.0
## attenuation. Its authored intensity piped through the Den 0.75 scale left
## it at 1.5 and aimed it off the table; the KF10 bank of warm light on the
## KILCAIRN parchment and tokens needs the authored 2.0 energy aimed at the
## map-table surface (+6 cm). Colour, range, cone, attenuation and shadow stay
## authored, and no other authored light or hand fill is touched.
## Measured on the 2026-11-22 capture: energy 2.2 moved p95 by 0.0
## (63.3 both) and lifted p50 +0.3, so 2.0 is kept.
const DEN_KF10_DESK_SPOT_POS: Vector3 = Vector3(3.6446, 41.803, 267.8289)
const DEN_KF10_DESK_SPOT_TOL: float = 0.05

func _aim_den_desk_spot(table_pos: Vector3) -> void:
	var best: SpotLight3D = null
	var best_d: float = DEN_KF10_DESK_SPOT_TOL
	for node: Node in find_children("*", "SpotLight3D", true, false):
		var spot: SpotLight3D = node as SpotLight3D
		var d: float = spot.global_position.distance_to(DEN_KF10_DESK_SPOT_POS)
		if d <= best_d:
			best_d = d
			best = spot
	if best == null:
		push_warning("[mission_controller] Den KF10 desk spot not found within %.2f m of %s; authored aim kept" % [DEN_KF10_DESK_SPOT_TOL, str(DEN_KF10_DESK_SPOT_POS)])
		return
	best.light_energy = 2.0
	var aim: Vector3 = table_pos + Vector3(0.0, 0.06, 0.0)
	best.look_at(aim, Vector3.UP)
	print("TAT-2 Den KF10 desk spot: energy=", best.light_energy, " pos=", best.global_position, " range=", best.spot_range, " cone=", best.spot_angle, " aimed_at=", aim)


## KF05 safeguard: ColorCorrection runs on the final sRGB frame, so the P1
## shadow-toe also changes the unshaded vista silhouettes (roofs at ~0.03-0.09
## sRGB) seen through the telescope. While `_ponder_active`, restore the
## level-load LUT so the vista keeps its P0 capture baseline; the P1 toe comes
## back on exit. Opt out with `--den-kf05-p1-lut` (or TAT2_DEN_KF05_P1_LUT=1 or
## tat2/den_kf05_legacy_lut=false) to A/B the P1 LUT inside the scope view.
func _den_kf05_legacy_lut_enabled() -> bool:
	if OS.has_environment("TAT2_DEN_KF05_P1_LUT"):
		return false
	for args: PackedStringArray in [OS.get_cmdline_user_args(), OS.get_cmdline_args()]:
		for arg: String in args:
			if arg == "--den-kf05-p1-lut":
				return false
	return bool(ProjectSettings.get_setting("tat2/den_kf05_legacy_lut", true))


func _set_ponder_shadow_toe(legacy: bool) -> void:
	if _den_env == null or not is_instance_valid(_den_env) or _den_lut_p1 == null:
		return
	if legacy and _den_lut_legacy != null and _den_kf05_legacy_lut_enabled():
		_den_env.adjustment_color_correction = _den_lut_legacy
		print("TAT-2 Den KF05 scope: level-load shadow-toe LUT restored for vista baseline")
	else:
		_den_env.adjustment_color_correction = _den_lut_p1


func _refresh_den_lookat_card(force_push: bool = false) -> void:
	if not _is_thieves_den or player == null or not is_instance_valid(player):
		return
	var eye: Vector3 = player.global_position + Vector3(0.0, 1.55, 0.0)
	var fwd: Vector3 = -player.global_transform.basis.z
	var pcam_v: Variant = player.get("cam")
	if pcam_v is Camera3D and is_instance_valid(pcam_v as Node):
		var pcam: Camera3D = pcam_v as Camera3D
		eye = pcam.global_position
		fwd = -pcam.global_transform.basis.z
	if fwd.length() > 0.001:
		fwd = fwd.normalized()
	else:
		fwd = Vector3.FORWARD

	var card: Dictionary = {"visible": false, "target": "", "title": "", "prompt": "", "bottom_hints": []}
	if _ponder_active:
		card = {
			"visible": true,
			"target": "telescope",
			"title": "KILCAIRN SKYLINE",
			"prompt": "EXIT",
			"bottom_hints": [{"key": "F", "label": "EXIT"}],
		}
	else:
		var to_table: Vector3 = _den_map_table_pos - eye
		var table_dist: float = to_table.length()
		var table_dot: float = fwd.dot(to_table / maxf(table_dist, 0.001))
		var looking_at_table: bool = (table_dist <= 4.5 and table_dot >= 0.52) or (table_dist <= 2.6 and table_dot >= 0.22)
		if looking_at_table:
			# Check which miniature token the player's gaze ray passes closer to.
			var best_mid: String = ""
			var best_perp: float = 0.55
			for mid_v: Variant in _den_tokens.keys():
				var mid: String = str(mid_v)
				var mi_v: Variant = _den_tokens.get(mid, null)
				if not (mi_v is MeshInstance3D) or not is_instance_valid(mi_v as Node):
					continue
				var tpos: Vector3 = (mi_v as MeshInstance3D).global_position + Vector3(0.0, 0.12, 0.0)
				var v_to: Vector3 = tpos - eye
				var along: float = v_to.dot(fwd)
				if along <= 0.1 or along > 5.0:
					continue
				var perp: float = (v_to - fwd * along).length()
				if perp < best_perp:
					best_perp = perp
					best_mid = mid
			if best_mid != "" and best_mid != _den_selected_map_id and is_selectable_den_map(best_mid):
				# P2 gaze bypass: intentional direct write, not set_den_selected_map
				# (that setter re-enters _refresh_den_lookat_card; we are inside
				# it). Highlights converge on _update_map_token_highlights, one path.
				_den_selected_map_id = best_mid
				_update_map_token_highlights()
			var loc_title: String = "ELWAY MANOR" if _den_selected_map_id == "old_manor" else ("JASPERING HALL" if _den_selected_map_id == "jaspering_hall" else "CONSTABLES' GUILDHALL")
			card = {
				"visible": true,
				"target": "map_table",
				"map_id": _den_selected_map_id,
				"title": loc_title,
				"difficulty": GameState.difficulty_label(),
				"mode": GameState.active_mission_mode,
				"prompt": "Prepare for Mission",
				"bottom_hints": [
					{"key": "H", "label": "Difficulty: %s" % GameState.difficulty_label()},
					{"key": "R", "label": "Mode: %s" % GameState.active_mission_mode},
					{"key": "F", "label": "Prepare for Mission"},
				],
			}
		else:
			var to_tele: Vector3 = _den_telescope_pos - eye
			var tele_dist: float = to_tele.length()
			var tele_dot: float = fwd.dot(to_tele / maxf(tele_dist, 0.001))
			if tele_dist <= 3.5 and tele_dot >= 0.62:
				card = {
					"visible": true,
					"target": "telescope",
					"title": "TELESCOPE",
					"prompt": "PONDER",
					"bottom_hints": [{"key": "F", "label": "PONDER"}],
				}

	var changed: bool = force_push \
		or card.get("visible") != _den_lookat_card.get("visible") \
		or str(card.get("target", "")) != str(_den_lookat_card.get("target", "")) \
		or str(card.get("title", "")) != str(_den_lookat_card.get("title", "")) \
		or str(card.get("difficulty", "")) != str(_den_lookat_card.get("difficulty", "")) \
		or str(card.get("mode", "")) != str(_den_lookat_card.get("mode", ""))
	if changed:
		_den_lookat_card = card
		if hud != null and hud.has_method("set_den_lookat_card"):
			hud.call("set_den_lookat_card", _den_lookat_card.duplicate(true))


func _unhandled_input(event: InputEvent) -> void:
	if not _is_thieves_den or GameState.state != "playing":
		return
	if not (event is InputEventKey):
		return
	var kev: InputEventKey = event as InputEventKey
	if not kev.pressed or kev.echo:
		return
	if _ponder_active:
		if kev.keycode == KEY_F or kev.keycode == KEY_ESCAPE:
			toggle_telescope_ponder()
			get_viewport().set_input_as_handled()
		return
	# Lookat-path enter: the [F] PONDER card shows up to 3.5 m, past the
	# 1.8 m Area3D range, so F here enters the zoom when the card offers the
	# scope. Same-press double dispatch with Area.interact collapses to one
	# flip in toggle_telescope_ponder's frame guard.
	if kev.keycode == KEY_F and str(_den_lookat_card.get("target", "")) == "telescope":
		toggle_telescope_ponder()
		get_viewport().set_input_as_handled()
		return
	if str(_den_lookat_card.get("target", "")) == "map_table":
		if kev.keycode == KEY_H:
			cycle_den_difficulty()
			get_viewport().set_input_as_handled()
		elif kev.keycode == KEY_R:
			cycle_den_mode()
			get_viewport().set_input_as_handled()


func _spawn_thieves_den_props(anchor: Vector3) -> void:
	var floor_y: float = anchor.y
	# Trunk Decoration Pedestal -> [F] CHANGE DECORATION
	# Trunk pedestal is floor-standing: base snaps to floor_y (F1 rule).
	var deco_pos: Vector3 = Vector3(anchor.x - 1.8, floor_y, anchor.z + 1.4)
	var deco_area := Area3D.new()
	deco_area.name = "DenDecorationPedestal"
	deco_area.position = deco_pos
	deco_area.add_to_group("interactables")
	deco_area.set_meta("interaction_point", deco_pos + Vector3.UP * 1.0)
	var dcol := CollisionShape3D.new()
	var dsph := SphereShape3D.new()
	dsph.radius = 1.4
	dcol.shape = dsph
	deco_area.add_child(dcol)
	var deco_visual: Node3D = Node3D.new()
	deco_visual.name = "DecorationVisual"
	deco_area.add_child(deco_visual)
	var deco_script := GDScript.new()
	deco_script.source_code = """extends Area3D
const DECORATIONS: Array[String] = ["faberge_egg", "owl_statue", "emerald"]
const DECO_UE_MESHES: Dictionary = {
\t"faberge_egg": "/Game/Art/Gameplay/Loot/LootMajor/FabergeEgg/SM_FabergeEggA",
\t"owl_statue": "/Game/Art/Gameplay/Loot/LootMajor/FigurineOwl/SM_StatueOwlA",
\t"emerald": "/Game/Art/Gameplay/Loot/LootMajor/HugeJewel/SM_HugeJewel",
}
var level_loader: Node = null
var active_idx: int = 0
func _ready() -> void:
\tvar saved: String = str(SaveSystem.data.get("active_decoration", "faberge_egg"))
\tvar found: int = DECORATIONS.find(saved)
\tif found >= 0:
\t\tactive_idx = found
\t_rebuild_visual()
func get_interact_prompt() -> String:
\treturn "[F] CHANGE DECORATION"
func interact(_actor: Node) -> void:
\tactive_idx = (active_idx + 1) % DECORATIONS.size()
\tSaveSystem.data["active_decoration"] = DECORATIONS[active_idx]
\tSaveSystem.write_save()
\t_rebuild_visual()
func _rebuild_visual() -> void:
\tvar vis: Node3D = get_node_or_null("DecorationVisual") as Node3D
\tif vis == null:
\t\treturn
\tfor c in vis.get_children():
\t\tc.queue_free()
\tvar key: String = DECORATIONS[active_idx]
\tvar ue_mesh: String = str(DECO_UE_MESHES.get(key, ""))
\tif ue_mesh != "" and level_loader != null and level_loader.has_method("_get_mesh_and_shape"):
\t\tvar info: Dictionary = level_loader.call("_get_mesh_and_shape", ue_mesh)
\t\tvar mesh: Mesh = info.get("mesh") as Mesh
\t\tif mesh != null:
\t\t\tvar mi := MeshInstance3D.new()
\t\t\tmi.name = "DecoMesh"
\t\t\tmi.mesh = mesh
\t\t\tmi.scale = Vector3(0.35, 0.35, 0.35)
\t\t\tvis.add_child(mi)
\t\t\treturn
\tvar glb_path: String = "res://assets/ue/Content/" + ue_mesh.trim_prefix("/Game/") + ".glb"
\tif ue_mesh != "" and ResourceLoader.exists(glb_path):
\t\tvar p: PackedScene = load(glb_path) as PackedScene
\t\tif p != null:
\t\t\tvar inst: Node3D = p.instantiate() as Node3D
\t\t\tif inst != null:
\t\t\t\tinst.scale = Vector3(0.35, 0.35, 0.35)
\t\t\t\tvis.add_child(inst)
"""
	deco_script.reload()
	deco_area.set_script(deco_script)
	deco_area.set("level_loader", level_loader)
	add_child(deco_area)

	# Gramophone -> [F] TURN ON / [F] TURN OFF
	var gram_area := Area3D.new()
	gram_area.position = deco_pos + Vector3(-0.55, 0.0, 0.0)
	gram_area.add_to_group("interactables")
	gram_area.set_meta("interaction_point", deco_pos + Vector3(-0.55, 0.8, 0.0))
	var gcol := CollisionShape3D.new()
	var gsph := SphereShape3D.new()
	gsph.radius = 1.3
	gcol.shape = gsph
	gram_area.add_child(gcol)
	var gram_script := GDScript.new()
	gram_script.source_code = """extends Area3D
var playing: bool = false
func get_interact_prompt() -> String:
\treturn "[F] TURN OFF" if playing else "[F] TURN ON"
func interact(_actor: Node) -> void:
\tplaying = not playing
\tif AudioManager == null:
\t\treturn
\tif AudioManager.has_method("toggle_gramophone"):
\t\tAudioManager.toggle_gramophone()
\telif AudioManager.has_method("play_ui"):
\t\tAudioManager.play_ui("click")
"""
	gram_script.reload()
	gram_area.set_script(gram_script)
	add_child(gram_area)


func open_contract_table_ui() -> void:
	var ui: CanvasLayer = ContractTableUIScript.new()
	ui.set("selected_map_id", _den_selected_map_id)
	# P2 table highlights wrong row: the opener set the map but never the
	# order, so the highlight sat on contract #1 regardless of the active
	# contract (contract_table_ui default selected_order = 1).
	ui.set("selected_order", GameState.active_contract_order)
	ui.set("coop_mode", GameState.active_mission_mode)
	add_child(ui)
	if ui.has_signal("deploy_requested"):
		ui.connect("deploy_requested", func(order_id: int, map_id: String) -> void:
			# T7: reset_run clears active_mission_id on map change (Den -> mission map
			# always changes), which dropped the prep-table choice; the table-local
			# coop_mode likewise never reached GameState. Stash both across the reset;
			# _setup_mission_objectives validates the id against missions_by_id + map.
			# Free play is stashed the same way: its live flag is cleared by reset_run,
			# so the mode + mission id are re-staged for the mission scene to consume.
			var pending_mission_id: String = GameState.active_mission_id
			var pending_mode: String = GameState.active_mission_mode
			var pending_free_play: bool = GameState.free_play
			GameState.reset_run(order_id, map_id)
			GameState.active_mission_id = pending_mission_id
			GameState.active_mission_mode = pending_mode
			if pending_free_play:
				GameState.begin_free_play(pending_mission_id)
			else:
				GameState.end_free_play()
			get_tree().reload_current_scene()
		)
	if ui.has_method("open_table"):
		ui.call("open_table")


func _setup_mission_objectives(map_id: String, _order: int) -> void:
	_active_mission_row = {}
	if map_id == "thieves_den":
		GameState.set_mission_objectives([], 0)
		return
	var chosen: Dictionary = {}
	if GameState.active_mission_id != "" and GameData.missions_by_id.has(GameState.active_mission_id):
		var cand: Variant = GameData.missions_by_id.get(GameState.active_mission_id)
		if cand is Dictionary and str((cand as Dictionary).get("map_id", "")) == map_id:
			chosen = (cand as Dictionary).duplicate(true)
	if chosen.is_empty():
		# T7: no positional re-derivation — the contract order never identified a
		# mission (absi(order) % size silently discarded the OptionButton override).
		# The deploy handoff threads the chosen id via GameState.active_mission_id;
		# this fallback only serves legacy paths that never set one, and stays
		# deterministic without pretending the order selects a mission.
		var matching: Array[Dictionary] = GameData.get_missions_for_map(map_id)
		if not matching.is_empty():
			chosen = matching[0].duplicate(true)
	_active_mission_row = chosen
	var mid: String = str(chosen.get("id", ""))
	if mid != "":
		GameState.active_mission_id = mid
	contract_info["mission_id"] = mid
	contract_info["mission_title"] = str(chosen.get("title", ""))

	var active: Dictionary = _active_quest_objective()
	var objective: Dictionary = active.get("objective", {}) as Dictionary
	var plan: Dictionary = active.get("plan", {}) as Dictionary
	var objs: Array[Dictionary] = []
	var goals: Array = plan.get("loot_goals", []) as Array
	var goal_val: int = 0
	if not goals.is_empty():
		goal_val = int(goals[clampi(GameState.difficulty - 1, 0, goals.size() - 1)])
	var kind: String = str(objective.get("kind", ""))
	if kind == "loot_amount" or (kind == "" and mid.ends_with(".LootTheRoom")):
		if kind == "loot_amount" and objective.get("amount", null) != null:
			goal_val = int(objective.get("amount"))
		if goal_val <= 0:
			push_error("[mission_controller] loot_amount objective for mission '", mid, "' has no authored amount; no goal invented")
		# The HUD string "Steal 4,000 in loot value" is the shipped reference
		# text (docs/REFERENCE_BASELINE.md UI3-02); the amount is authored.
		var label: String = "Steal %s in loot value" % GameState.format_thousands(goal_val) if goal_val > 0 else str(objective.get("objective_text", ""))
		if label != "":
			objs = [
				{"id": "cleanout_loot", "label": label, "done": false, "current": 0, "target": goal_val},
			]
	elif kind == "set":
		var items: Array = objective.get("items", []) as Array
		var label: String = str(objective.get("objective_text", ""))
		if label == "":
			label = str(chosen.get("title", ""))
		var set_target: int = items.size()
		if objective.get("override_min_number_to_steal", false) == true and objective.get("min_number_to_steal", null) != null:
			set_target = maxi(int(objective.get("min_number_to_steal")), 1)
		objs.append({"id": "set_main", "label": label, "done": false, "current": 0, "target": maxi(set_target, 1)})
		for i: int in range(items.size()):
			var item: Dictionary = items[i] as Dictionary
			objs.append({
				"id": "set_item_%d" % i,
				"label": str(item.get("display_name", item.get("loot_row", ""))),
				"done": false,
				"current": 0,
				"target": 1,
			})
	elif kind == "single" or kind == "multiple":
		var target_name: String = str(objective.get("objective_text", "")).strip_edges()
		if target_name == "":
			var items: Array = objective.get("items", []) as Array
			var first_item: Dictionary = items[0] as Dictionary if not items.is_empty() and items[0] is Dictionary else {}
			target_name = str(first_item.get("display_name", "")).strip_edges()
		if target_name == "":
			target_name = str(contract_info.get("quest_item", "")).strip_edges()
		if target_name == "" or target_name == "Objective" or target_name.begins_with("Loot."):
			target_name = str(chosen.get("title", "Contract Objective"))
		var target_count: int = 1
		if kind == "multiple":
			target_count = maxi(int(objective.get("min_number_to_steal", 0)), (objective.get("items", []) as Array).size())
		objs = [
			{"id": "vault_main", "label": "Steal the %s" % target_name, "done": false, "current": 0, "target": maxi(target_count, 1)},
		]
	else:
		var target_name: String = str(contract_info.get("quest_item", "")).strip_edges()
		if target_name == "" or target_name == "Objective" or target_name.begins_with("Loot."):
			target_name = str(chosen.get("title", "Contract Objective"))
		objs = [
			{"id": "vault_main", "label": "Steal the %s" % target_name, "done": false, "current": 0, "target": 1},
		]
	GameState.set_mission_objectives(objs, goal_val)


## Objective the live mode actually plays: free play reads the mission row's
## reachable QG objective; a contract deploy reads the contract row's authored
## objective (DT_LootInfo_Quest items). Returns {"objective", "plan"}.
func _active_quest_objective() -> Dictionary:
	if GameState.free_play and GameState.active_mission_id != "":
		var plan: Dictionary = GameData.get_mission_plan(GameState.active_mission_id)
		var plan_obj: Dictionary = _plan_objective_for_difficulty(plan)
		if not plan_obj.is_empty():
			return {"objective": plan_obj, "plan": plan}
	var contract: Dictionary = GameData.get_quest_contract(GameState.active_contract_order)
	var obj_v: Variant = contract.get("objective", {})
	if obj_v is Dictionary and not (obj_v as Dictionary).is_empty():
		return {"objective": GameData.enrich_quest_objective(obj_v as Dictionary), "plan": {}}
	return {}


## Pick the objective node for the current difficulty. Unconditional nodes
## (difficulty 0, e.g. Mission.Guildhall.Set) always win; otherwise the
## Difficulty.Novice/Thief/MasterThief-gated node is selected.
func _plan_objective_for_difficulty(plan: Dictionary) -> Dictionary:
	var objs_v: Variant = plan.get("objectives", [])
	if not (objs_v is Array) or (objs_v as Array).is_empty():
		return {}
	var objs: Array = objs_v as Array
	for node_v: Variant in objs:
		if node_v is Dictionary and int((node_v as Dictionary).get("difficulty", 0)) == GameState.difficulty:
			return node_v as Dictionary
	for node_v: Variant in objs:
		if node_v is Dictionary and int((node_v as Dictionary).get("difficulty", 0)) == 0:
			return node_v as Dictionary
	return objs[0] as Dictionary if objs[0] is Dictionary else {}


func _trigger_mission_start_letter() -> void:
	var title_s: String = str(contract_info.get("title", _active_mission_row.get("title", "Contract")))
	var intro_s: String = str(contract_info.get("intro", "")).strip_edges()
	if intro_s == "":
		intro_s = str(_active_mission_row.get("description", contract_info.get("description", ""))).strip_edges()
	if intro_s.find("{MatchDurationInMinutes}") >= 0:
		var mins: int = int(round(GameState.run_time_limit / 60.0)) if GameState.run_time_limit > 0.0 else 120
		intro_s = intro_s.replace("{MatchDurationInMinutes}", str(mins))
	if intro_s == "":
		intro_s = "Esteemed Colleague — Infiltrate the target site, secure the objective, and slip away unseen."
	contract_info["intro"] = intro_s
	GameState.request_mission_letter(title_s, intro_s)
	_letter_grace_sec = LETTER_GRACE_SEC


## T8: GameData.get_contract_display writes clue text only as "clue_facts"
## (array, game_data.gd:389); zero producers write a "clue" key. Resolve in
## that order: legacy "clue" first (forward-compat), then the "clue_facts"
## joined exactly the way the table intel panel shows them
## (contract_table_ui.gd:310-315), then the caller fallback. The assert pins
## the key contract: a dict carrying neither key is a producer bug, caught
## in debug without changing release behavior.
func _contract_clue_text(info: Dictionary, fallback: String) -> String:
	if not info.has("clue") and not info.has("clue_facts"):
		push_error("[mission_controller] contract dict carries neither 'clue' nor 'clue_facts'; using fallback")
		assert(false, "contract clue key contract broken: expected 'clue_facts' (game_data.gd:389)")
		return fallback
	var legacy: String = str(info.get("clue", "")).strip_edges()
	if legacy != "":
		return legacy
	var facts_v: Variant = info.get("clue_facts", null)
	if facts_v is Array and not (facts_v as Array).is_empty():
		var parts: Array[String] = []
		for fact: Variant in (facts_v as Array):
			var f: String = str(fact).strip_edges()
			if f != "":
				parts.append("• " + f)
		if not parts.is_empty():
			return "\n".join(parts)
	return fallback


## Data-driven clue pass. Contract deploys spawn every enabled clue in the
## contract's authored CLS_Contract_NN; free-play/mission deploys follow the
## mission QG's reachable clue nodes (a ClueSetNode spawns the whole set, a
## ClueSetForSpawnNode contributes one clue tied to its loot tag). A missing
## spawner is a loud error, never a generic parchment substitution.
func _spawn_clues(_ue_spawns: Array, _anchor: Vector3) -> void:
	var map_id: String = GameState.active_map_id
	var requests: Array[Dictionary] = _active_clue_requests()
	if requests.is_empty():
		_clue_spawn_records = []
		print("TAT-2 clues: no active authored clue set for map=", map_id, " mission=", GameState.active_mission_id, " free_play=", GameState.free_play)
		return
	var records: Array[Dictionary] = spawn_clue_requests(requests, map_id, GameState.active_map_seed, _loaded_level_names, _quest_item_spawns)
	_clue_spawn_records = records
	for rec: Dictionary in records:
		var node: Node = rec.get("node", null) as Node
		if node != null and node.has_signal("clue_collected") and hud != null and hud.has_method("show_clue_toast"):
			node.connect("clue_collected", hud.show_clue_toast)
	print("TAT-2 clues: spawned=", records.size(), " set(s)=", _request_set_names(requests), " map=", map_id)


func _active_clue_requests() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if GameState.free_play and GameState.active_mission_id != "":
		var plan: Dictionary = GameData.get_mission_plan(GameState.active_mission_id)
		var refs_v: Variant = plan.get("clue_set_nodes", [])
		if refs_v is Array:
			var seen_all: Dictionary = {}
			for ref_v: Variant in (refs_v as Array):
				if not (ref_v is Dictionary):
					continue
				var ref: Dictionary = ref_v as Dictionary
				var set_name: String = str(ref.get("clue_set", ""))
				if set_name == "":
					continue
				var ntype: String = str(ref.get("node_type", ""))
				if ntype.ends_with("ClueSetForSpawnNode"):
					out.append({"set": set_name, "mode": "one", "loot_tag": str(ref.get("loot_tag", "")), "node": str(ref.get("node", ""))})
				elif not seen_all.has(set_name):
					seen_all[set_name] = true
					out.append({"set": set_name, "mode": "all", "loot_tag": "", "node": str(ref.get("node", ""))})
		return out
	# Contract deploy: the authored CLS_Contract_NN from the contract row.
	var set_name: String = ""
	var clues_path: String = str(contract_info.get("clues_ue_path", ""))
	if clues_path != "":
		set_name = str(GameData.get_clue_set(clues_path).get("name", ""))
	if set_name == "":
		var contract: Dictionary = GameData.get_quest_contract(GameState.active_contract_order)
		set_name = str(contract.get("clues_name", ""))
	if set_name == "":
		return out
	out.append({"set": set_name, "mode": "all", "loot_tag": "", "node": ""})
	return out


func _request_set_names(requests: Array[Dictionary]) -> String:
	var names: Array[String] = []
	for req: Dictionary in requests:
		var n: String = str(req.get("set", ""))
		if n != "" and not names.has(n):
			names.append(n)
	return ",".join(names)


# =============================================================================
# W1S/W2P Spider personal-chain actors
# =============================================================================
#
# The spawn pass lives in `personal_quest_spawner.gd` so the mission and the
# subset real-map probe run the same code. Pins come from
# game/data/expansion/personal_spider.json through PersonalQuest.spawn_plan();
# grounding, authored fallbacks, dedupe and the letter/Owl callbacks are owned
# there. This controller only supplies the mission host/HUD and republishes the
# records as `personal_quest_actors` for QA.

var _personal_quest_spawner: Node = null


func _personal_spawner() -> Node:
	if _personal_quest_spawner == null or not is_instance_valid(_personal_quest_spawner):
		_personal_quest_spawner = PersonalQuestSpawnerScript.new()
		_personal_quest_spawner.name = "PersonalQuestSpawner"
		add_child(_personal_quest_spawner)
	_personal_quest_spawner.call("setup", self, hud)
	return _personal_quest_spawner


func _spawn_personal_quest_actors() -> void:
	var spawner: Node = _personal_spawner()
	spawner.call("spawn_for_map", GameState.active_map_id)
	_sync_personal_actors(spawner)


## Called by loot_item after acquire_owl(): the Lounge courier appears at once
## instead of waiting for the next deploy.
func on_personal_quest_owl_taken() -> void:
	var spawner: Node = _personal_spawner()
	spawner.call("on_owl_taken")
	_sync_personal_actors(spawner)


## Copy the seam's records into the QA-facing list (same Dictionary objects,
## never a second truth).
func _sync_personal_actors(spawner: Node) -> void:
	personal_quest_actors.clear()
	for rec_v: Variant in spawner.get("actors") as Array:
		if rec_v is Dictionary:
			personal_quest_actors.append(rec_v as Dictionary)


## Spawn a list of clue requests. Public so the headless suite can exercise the
## same pass the mission uses without loading a whole level.
func spawn_clue_requests(requests: Array[Dictionary], map_id: String, seed_value: int, levels: Array = [], quest_items: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var used_spawners: Dictionary = {}
	for req: Dictionary in requests:
		var set_name: String = str(req.get("set", ""))
		var set_data: Dictionary = GameData.get_clue_set(set_name)
		if set_data.is_empty():
			push_error("[mission_controller] clue spawn: unknown clue set '", set_name, "' (map=", map_id, ")")
			continue
		var clues_v: Variant = set_data.get("clues", [])
		if not (clues_v is Array):
			continue
		var enabled: Array[Dictionary] = []
		for clue_v: Variant in (clues_v as Array):
			if clue_v is Dictionary and (clue_v as Dictionary).get("enabled", false) == true:
				enabled.append(clue_v as Dictionary)
		if enabled.is_empty():
			continue
		var loot_tag: String = str(req.get("loot_tag", ""))
		var params: Dictionary = _clue_params_for_loot(loot_tag, quest_items)
		if str(req.get("mode", "all")) == "one":
			var picked: Dictionary = _pick_spawnable_clue(set_name, enabled, map_id, levels, seed_value, loot_tag, used_spawners)
			if picked.is_empty():
				push_error("[mission_controller] clue spawn: no readable spawner for set '", set_name, "' node '", str(req.get("node", "")), "' loot_tag '", loot_tag, "' map '", map_id, "'")
				continue
			var rec: Dictionary = _spawn_clue_entry(picked.get("clue", {}) as Dictionary, set_name, picked.get("spawner", {}) as Dictionary, params)
			if not rec.is_empty():
				out.append(rec)
			continue
		for clue: Dictionary in enabled:
			var placement: String = str(clue.get("placement_tag", ""))
			if placement == "":
				# Authored briefing facts (ObjectiveText/Intro) carry no
				# placement tag: they are not world readables.
				continue
			var spawner: Dictionary = _find_distinct_spawner(map_id, placement, levels, used_spawners, seed_value, set_name, int(clue.get("index", 0)))
			if spawner.is_empty():
				push_error("[mission_controller] clue spawn: no readable spawner for placement tag '", placement, "' set '", set_name, "' map '", map_id, "'")
				continue
			var rec2: Dictionary = _spawn_clue_entry(clue, set_name, spawner, params)
			if not rec2.is_empty():
				out.append(rec2)
	return out


## One enabled clue for a ClueSetForSpawnNode, choosing the first authored
## entry (seeded order) whose placement tag still has an unused spawner.
func _pick_spawnable_clue(set_name: String, enabled: Array[Dictionary], map_id: String, levels: Array, seed_value: int, loot_tag: String, used_spawners: Dictionary) -> Dictionary:
	if enabled.is_empty():
		return {}
	var start: int = posmod(LevelLoaderScript._sv_fnv1a("%d|%s|%s" % [seed_value, set_name, loot_tag]), enabled.size())
	for offset: int in range(enabled.size()):
		var clue: Dictionary = enabled[(start + offset) % enabled.size()]
		var placement: String = str(clue.get("placement_tag", ""))
		if placement == "":
			continue
		var spawner: Dictionary = _find_distinct_spawner(map_id, placement, levels, used_spawners, seed_value, set_name, int(clue.get("index", offset)))
		if not spawner.is_empty():
			return {"clue": clue, "spawner": spawner, "key": str(clue.get("index", offset))}
	return {}


func _spawn_clue_entry(clue: Dictionary, set_name: String, spawner: Dictionary, params: Dictionary) -> Dictionary:
	if spawner.is_empty():
		return {}
	var placement: String = str(clue.get("placement_tag", ""))
	var body: String = _format_authored_text(str(clue.get("text", "")), params)
	var visual_key: String = str(clue.get("visuals", ""))
	var visual: Dictionary = GameData.readable_visuals.get(visual_key, {}) as Dictionary
	var authored_class: String = str(visual.get("actor_class_name", ""))
	var visual_type: String = str(visual.get("type", ""))
	var fact_ids: Array[String] = []
	var facts_v: Variant = clue.get("fact_ids", [])
	if facts_v is Array:
		for fid_v: Variant in (facts_v as Array):
			var fid: String = str(fid_v)
			if fid != "" and not fact_ids.has(fid):
				fact_ids.append(fid)
	var clue_node: Area3D = ClueItemScript.new()
	clue_node.set("clue_title", visual_type)
	clue_node.set("clue_body", body)
	clue_node.set("prompt_verb", "Read")
	clue_node.set("authored_class", authored_class)
	clue_node.set("visual_type", visual_type)
	clue_node.set("fact_ids", fact_ids)
	clue_node.set("fact_params", params)
	clue_node.set("fact_source", "clue")
	clue_node.set("fact_source_item_tag", str(params.get("loot_tag", "")))
	clue_node.set("fact_source_index", int(clue.get("index", 0)))
	clue_node.transform = _spawner_transform(spawner)
	add_child(clue_node)
	return {
		"node": clue_node,
		"body": body,
		"set": set_name,
		"index": int(clue.get("index", 0)),
		"placement_tag": placement,
		"spawner": spawner,
		"visual_type": visual_type,
		"authored_class": authored_class,
		"fact_ids": fact_ids,
		"params": params,
		"fact_params": params,
	}


## Resolve a placement demand against the authored spawner tags. Mirrors
## tools/parse_quests.py resolve_demand: exact, normalised (Common/Locations
## removed), namespace alias, then parent prefix. The generated validation
## uses the same rules, so a tag accepted there is accepted here.
func _placement_candidate_tags(map_id: String, placement_tag: String, levels: Array) -> Array[String]:
	var available: Dictionary = {}
	for rec: Dictionary in GameData.readable_spawners:
		if str(rec.get("map_id", "")) != map_id:
			continue
		if not levels.is_empty() and not levels.has(str(rec.get("level", ""))):
			continue
		var tag: String = str(rec.get("placement_tag", ""))
		if tag == "":
			continue
		available[tag] = int(available.get(tag, 0)) + 1
	if available.has(placement_tag):
		return [placement_tag]
	var demand_norm: Array[String] = _normalise_placement_tag(placement_tag)
	var same: Array[String] = []
	var alias: Array[String] = []
	var prefix: Array[String] = []
	for tag_v: Variant in available.keys():
		var tag: String = str(tag_v)
		var tag_norm: Array[String] = _normalise_placement_tag(tag)
		if tag_norm == demand_norm:
			same.append(tag)
		elif tag_norm.size() == demand_norm.size() and tag_norm.size() >= 2 and tag_norm[0] == demand_norm[0] and tag_norm[1] != demand_norm[1] and tag_norm.slice(2) == demand_norm.slice(2):
			alias.append(tag)
		elif demand_norm.size() < tag_norm.size() and tag_norm.slice(0, demand_norm.size()) == demand_norm:
			prefix.append(tag)
	for group: Variant in [same, alias, prefix]:
		var group_tags: Array = group as Array
		if not group_tags.is_empty():
			group_tags.sort()
			var out_tags: Array[String] = []
			for tag_v: Variant in group_tags:
				out_tags.append(str(tag_v))
			return out_tags
	return []


func _normalise_placement_tag(tag: String) -> Array[String]:
	var out: Array[String] = []
	for part: String in tag.split("."):
		if part == "" or part == "Common" or part == "Locations":
			continue
		out.append(part)
	return out


## Deterministic distinct spawner pick (seed + set/node + clue index). Returns
## {} when every candidate is already used.
func _find_distinct_spawner(map_id: String, placement_tag: String, levels: Array, used: Dictionary, seed_value: int, key: String, index: int) -> Dictionary:
	var tags: Array[String] = _placement_candidate_tags(map_id, placement_tag, levels)
	if tags.is_empty():
		return {}
	var pool: Array[Dictionary] = []
	for tag: String in tags:
		pool.append_array(GameData.get_readable_spawners(map_id, tag, levels))
	if pool.is_empty():
		return {}
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _spawner_key(a) < _spawner_key(b))
	var start: int = posmod(LevelLoaderScript._sv_fnv1a("%d|%s|%d" % [seed_value, key, index]), pool.size())
	for offset: int in range(pool.size()):
		var rec: Dictionary = pool[(start + offset) % pool.size()]
		var skey: String = _spawner_key(rec)
		if used.has(skey):
			continue
		used[skey] = true
		return rec
	return {}


func _spawner_key(rec: Dictionary) -> String:
	var pos_v: Variant = rec.get("pos", [])
	var pos_key: String = ""
	if pos_v is Array:
		var pa: Array = pos_v as Array
		pos_key = "%.3f,%.3f,%.3f" % [float(pa[0]), float(pa[1]), float(pa[2])]
	return "%s|%s|%s" % [str(rec.get("level", "")), str(rec.get("actor", "")), pos_key]


## Authored {item}/{Location} values for a loot tag: the display name and the
## spawner's clue_location_text recorded by the quest-item pass. Empty when the
## cooked data does not link them (never synthesised).
func _clue_params_for_loot(loot_tag: String, quest_items: Array) -> Dictionary:
	if loot_tag == "":
		return {}
	for rec_v: Variant in quest_items:
		if not (rec_v is Dictionary):
			continue
		var rec: Dictionary = rec_v as Dictionary
		if str(rec.get("loot_tag", "")) != loot_tag:
			continue
		return {
			"item": str(rec.get("display_name", "")),
			"Location": str(rec.get("location_text", "")),
			"loot_tag": loot_tag,
		}
	return {}


func _format_authored_text(text: String, params: Dictionary) -> String:
	var out: String = text
	for key_v: Variant in params.keys():
		var key: String = str(key_v)
		var value: String = str(params[key_v])
		if key == "" or key == "loot_tag":
			continue
		out = out.replace("{%s}" % key, value)
		out = out.replace("{%s}" % key.to_lower(), value)
		out = out.replace("{%s}" % key.capitalize(), value)
	return out


func _levels_from_sublevel_paths(paths: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for path: String in paths:
		var level: String = path.trim_prefix("res://data/generated/levels/").trim_suffix(".tatlevel.json")
		if level != "":
			out.append(level)
	return out


## Authored spawner transform (same row-major basis -> Godot Basis conversion
## as level_loader._dict_to_transform).
func _spawner_transform(rec: Dictionary) -> Transform3D:
	var p: Array = rec.get("pos", [0.0, 0.0, 0.0]) as Array
	var b: Array = rec.get("basis", [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]) as Array
	var s: Array = rec.get("scale", [1.0, 1.0, 1.0]) as Array
	var basis: Basis = Basis(
		Vector3(float(b[0]), float(b[3]), float(b[6])),
		Vector3(float(b[1]), float(b[4]), float(b[7])),
		Vector3(float(b[2]), float(b[5]), float(b[8]))
	).scaled_local(Vector3(
		clampf(float(s[0]), 0.05, 40.0),
		clampf(float(s[1]), 0.05, 40.0),
		clampf(float(s[2]), 0.05, 40.0)
	))
	return Transform3D(basis, Vector3(float(p[0]), float(p[1]), float(p[2])))


func _add_safety_floor() -> void:
	var sb := StaticBody3D.new()
	sb.position = Vector3(0, -15.0, 0)
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(600, 1, 600)
	cs.shape = sh
	sb.add_child(cs)
	add_child(sb)


## Authored PlayerStart yaw in Godot space (the extractor already converted the
## marker basis to Godot axes; UE forward is -basis.z and Godot yaw 0 faces
## -Z). Upright only: pitch and roll are discarded so the thief never spawns
## tilted. Returns {"yaw": float, "valid": bool}: every degenerate path warns
## loudly and reports valid=false, so a silent 0.0 can never pose as authored
## facing again (GAP-2).
func _spawn_yaw_from_basis(basis_arr: Variant) -> Dictionary:
	var b: Array = basis_arr if (basis_arr is Array) else []
	if b.size() < 9:
		push_warning("[mission_controller] spawn yaw: basis array has %d entries (need 9); yaw 0.0 is a fallback, not authored" % b.size())
		return {"yaw": 0.0, "valid": false}
	var basis := Basis(
		Vector3(float(b[0]), float(b[3]), float(b[6])),
		Vector3(float(b[1]), float(b[4]), float(b[7])),
		Vector3(float(b[2]), float(b[5]), float(b[8]))
	).orthonormalized()
	if absf(basis.determinant()) < 0.0001:
		push_warning("[mission_controller] spawn yaw: degenerate basis (determinant ~0); yaw 0.0 is a fallback, not authored")
		return {"yaw": 0.0, "valid": false}
	var fwd: Vector3 = -basis.z
	if absf(fwd.x) < 0.000001 and absf(fwd.z) < 0.000001:
		push_warning("[mission_controller] spawn yaw: degenerate forward (straight up/down); yaw 0.0 is a fallback, not authored")
		return {"yaw": 0.0, "valid": false}
	return {"yaw": atan2(-fwd.x, -fwd.z), "valid": true}


func _spawn_player(ue_spawns: Array, ue_spawn_transforms: Array = [], stats: Dictionary = {}) -> void:
	player = ThiefScript.new()
	player.light_probe = light_probe
	player.level_ctrl = self
	var spawn: Vector3 = Vector3(0, 2.0, 0)
	var spawn_yaw: float = 0.0
	var have_yaw: bool = false
	var w3d: World3D = get_world_3d()
	var chosen_transform: Variant = null
	if not ue_spawn_transforms.is_empty():
		if w3d != null:
			var phys_t: PhysicsDirectSpaceState3D = w3d.direct_space_state
			for t_var: Variant in ue_spawn_transforms:
				if t_var is Dictionary:
					var tp: Vector3 = (t_var as Dictionary).get("pos", Vector3.ZERO)
					var qt: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(tp + Vector3(0, 1.0, 0), tp + Vector3(0, -6.0, 0), 1)
					var hitt: Dictionary = phys_t.intersect_ray(qt)
					if not hitt.is_empty():
						chosen_transform = t_var
						break
		else:
			chosen_transform = ue_spawn_transforms[0]
	if chosen_transform is Dictionary:
		spawn = ((chosen_transform as Dictionary).get("pos", Vector3.ZERO) as Vector3) + Vector3(0, 1.0, 0)
		var yaw_res: Dictionary = _spawn_yaw_from_basis((chosen_transform as Dictionary).get("basis", []))
		spawn_yaw = float(yaw_res.get("yaw", 0.0))
		# GAP-2: only an authored-valid basis may set facing; a degenerate
		# basis keeps the legacy facing instead of a silent 0.0.
		have_yaw = bool(yaw_res.get("valid", false))
		fallback_spawn_source = "authored"
		fallback_spawn_headroom_clear = true
		fallback_spawn_forward_clear = true
	else:
		# Authored positions only count when a floor raycast grounds them;
		# a blind ue_spawns[0] here used to drop Old Manor onto the safety
		# net (its TATPlayerStarts float outside the playable space).
		var grounded: Variant = null
		if not ue_spawns.is_empty():
			if w3d != null:
				var phys: PhysicsDirectSpaceState3D = w3d.direct_space_state
				for cand: Variant in ue_spawns:
					if cand is Vector3:
						var cp: Vector3 = cand as Vector3
						var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(cp + Vector3(0, 1.0, 0), cp + Vector3(0, -6.0, 0), 1)
						var hit: Dictionary = phys.intersect_ray(q)
						if not hit.is_empty():
							grounded = cand
							break
			else:
				grounded = ue_spawns[0]
		if grounded is Vector3:
			spawn = (grounded as Vector3) + Vector3(0, 1.0, 0)
			fallback_spawn_source = "authored"
			fallback_spawn_headroom_clear = true
			fallback_spawn_forward_clear = true
		else:
			var fb: Dictionary = _marker_fallback_spawn(stats, w3d)
			if not fb.is_empty():
				spawn = fb["pos"] as Vector3
				fallback_spawn_source = str(fb["source"])
				fallback_spawn_headroom_clear = bool(fb.get("headroom", false))
				fallback_spawn_forward_clear = fb.get("forward") == true
				var face: Variant = fb.get("face", null)
				if face is Vector3:
					var to: Vector3 = (face as Vector3) - spawn
					to.y = 0.0
					if to.length() > 0.05:
						spawn_yaw = atan2(-to.x, -to.z)
						have_yaw = true
			else:
				# GAP-8: no blind spawns. The old mesh fallback posed an
				# arbitrary mesh position as a spawn with no facing (Old Manor
				# fell through to it and the safety net). Last resort keeps
				# the legacy origin but still faces the loot centroid when
				# the map has one, and says so loudly.
				spawn = Vector3(0, 2.0, 0)
				fallback_spawn_source = "legacy"
				fallback_spawn_headroom_clear = false
				fallback_spawn_forward_clear = false
				var last_face: Variant = _loot_centroid(stats)
				if last_face is Vector3:
					var last_to: Vector3 = (last_face as Vector3) - spawn
					last_to.y = 0.0
					if last_to.length() > 0.05:
						spawn_yaw = atan2(-last_to.x, -last_to.z)
						have_yaw = true
				push_warning("[mission_controller] spawn fallback exhausted (no grounded authored start, no marker floor hit); legacy origin with centroid facing, source=legacy")
	player.position = spawn
	if have_yaw:
		player.rotation = Vector3(0.0, spawn_yaw, 0.0)
	print("TAT-2 player spawn: source=", fallback_spawn_source, " pos=", spawn, " yaw=", (spawn_yaw if have_yaw else "legacy"), " headroom_clear=", fallback_spawn_headroom_clear, " forward_clear=", fallback_spawn_forward_clear)
	player.downed_started.connect(_on_player_downed_started)
	player.downed.connect(_on_player_downed)
	add_child(player)
	_snap_player_to_ground()


## Marker-driven spawn fallback for maps whose authored PlayerStarts have no
## floor (Old Manor's TATPlayerStarts float outside the playable space, so the
## authored raycasts miss and the player used to end up on the safety net).
## Candidates span every marker in priority order: all major-loot markers
## (legacy loot_spawns when the map has no major records), every minor-loot
## marker plus the minor centroid, every guard, every escape. Each is raycast
## from +30 m to -120 m on layer 1 and the first floor hit wins at hit + 0.2 m
## (unchanged floor behavior). The winner must also pass the headroom check
## (2.2 m clear above hit + 0.3 m, capsule height 1.7 + margin, and no
## standing-capsule overlap) so the player never spawns under a low roof such
## as the porch over Old Manor's first major-loot marker, and the forward
## clearance check (no layer-1 geometry within 1.5 m on a ~3.0 m horizontal
## ray toward the loot centroid) so the player does not spawn facing a wall
## or roof 10-13 m ahead. Remaining candidates are tried when a check fails;
## when no candidate passes the forward check the first headroom-clear choice
## wins (logged as fallback_no_forward_clearance), and when none passes the
## headroom check the first floor-only hit wins (logged as
## fallback_no_headroom). Returns {} when nothing hits (the caller keeps the
## legacy mesh fallback). "face" is the loot-marker centroid the player should
## face when one exists, "headroom"/"forward" report which checks passed.
func _marker_fallback_spawn(stats: Dictionary, w3d: World3D) -> Dictionary:
	var majors: Array = stats.get("major_loot_spawns", [])
	var minors: Array = stats.get("minor_loot_spawns", [])
	var loots: Array = stats.get("loot_spawns", [])
	var guards: Array = stats.get("guard_spawns", [])
	var escapes: Array = stats.get("escape_points", [])
	var candidates: Array = []
	for m_var in majors:
		if m_var is Dictionary and (m_var as Dictionary).get("pos", null) is Vector3:
			candidates.append({"pos": (m_var as Dictionary).get("pos", null), "source": "major_loot"})
	if candidates.is_empty():
		for l_var in loots:
			if l_var is Vector3:
				candidates.append({"pos": l_var, "source": "major_loot"})
	var macc := Vector3.ZERO
	var mn := 0
	for e_var in minors:
		if e_var is Dictionary and (e_var as Dictionary).get("pos", null) is Vector3:
			var mp: Vector3 = (e_var as Dictionary).get("pos", null)
			candidates.append({"pos": mp, "source": "minor_loot"})
			macc += mp
			mn += 1
	if mn > 0:
		candidates.append({"pos": macc / float(mn), "source": "minor_centroid"})
	for g_var in guards:
		if g_var is Vector3:
			candidates.append({"pos": g_var, "source": "guard"})
	for x_var in escapes:
		if x_var is Vector3:
			candidates.append({"pos": x_var, "source": "escape"})
	if candidates.is_empty() or w3d == null:
		return {}
	var face: Variant = _loot_centroid(stats)
	var phys: PhysicsDirectSpaceState3D = w3d.direct_space_state
	var floor_only: Dictionary = {}
	var headroom_only: Dictionary = {}
	for c_var in candidates:
		var c: Dictionary = c_var as Dictionary
		var cp: Vector3 = c["pos"] as Vector3
		var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(cp + Vector3(0, 30, 0), cp + Vector3(0, -120, 0), 1)
		var hit: Dictionary = phys.intersect_ray(q)
		if hit.is_empty() or not (hit.get("position", null) is Vector3):
			continue
		var ground: Vector3 = (hit.get("position", null) as Vector3) + Vector3(0, 0.2, 0)
		if floor_only.is_empty():
			floor_only = {"pos": ground, "source": str(c["source"]), "face": face, "headroom": false, "forward": false}
		if not _fallback_spawn_has_headroom(phys, ground):
			continue
		if headroom_only.is_empty():
			headroom_only = {"pos": ground, "source": str(c["source"]), "face": face, "headroom": true, "forward": false}
		if _fallback_spawn_has_forward_clearance(phys, ground, face):
			return {"pos": ground, "source": str(c["source"]), "face": face, "headroom": true, "forward": true}
	if not headroom_only.is_empty():
		print("TAT-2 fallback_no_forward_clearance: no headroom-clear candidate had 1.5 m forward clearance; using headroom-only ", str(headroom_only["source"]), " pos=", headroom_only["pos"])
		return headroom_only
	if not floor_only.is_empty():
		print("TAT-2 fallback_no_headroom: no candidate passed the headroom check; using floor-only ", str(floor_only["source"]), " pos=", floor_only["pos"])
		return floor_only
	return {}


## Rejects fallback floor hits under low roofs: the 2.2 m column above
## floor + 0.3 m (standing capsule height 1.7 + margin) must be clear on
## layer 1, and a standing capsule (r 0.32, h 1.7, centered at floor + 0.9 m)
## must not overlap geometry. Fail-closed: any hit or overlap rejects.
func _fallback_spawn_has_headroom(phys: PhysicsDirectSpaceState3D, ground: Vector3) -> bool:
	var up_from: Vector3 = ground + Vector3(0, 0.3, 0)
	var uq: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(up_from, up_from + Vector3(0, 2.2, 0), 1)
	uq.hit_back_faces = true
	if not phys.intersect_ray(uq).is_empty():
		return false
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.7
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = cap
	sq.collision_mask = 1
	sq.transform = Transform3D(Basis(), ground + Vector3(0, 0.9, 0))
	return phys.intersect_shape(sq, 1).is_empty()


## Forward-clearance check for a fallback spawn candidate: from 1.0 m above
## the floor hit, cast ~3.0 m toward the loot centroid (horizontal only) on
## layer 1. A hit within 1.5 m (wall, column, or overhang edge right in front
## of the spawn) rejects the candidate; geometry farther out — e.g. the porch
## roof desktop rays hit 10-13 m ahead of Old Manor's major-loot point —
## passes. No centroid or a degenerate (straight-down) direction passes since
## there is nothing to face. Fail-closed on a hit that carries no position.
func _fallback_spawn_has_forward_clearance(phys: PhysicsDirectSpaceState3D, ground: Vector3, target: Variant) -> bool:
	if not (target is Vector3):
		return true
	var dir: Vector3 = (target as Vector3) - ground
	dir.y = 0.0
	if dir.length() < 0.05:
		return true
	var from: Vector3 = ground + Vector3(0, 1.0, 0)
	var fq: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * 3.0, 1)
	var hit: Dictionary = phys.intersect_ray(fq)
	if hit.is_empty():
		return true
	var hp: Variant = hit.get("position", null)
	if hp is Vector3:
		return (hp as Vector3).distance_to(from) >= 1.5
	return false


## Mean of all loot-marker positions (major + minor records plus the legacy
## loot_spawns vectors); the fallback spawn faces this point so the player
## starts looking toward the mission space. Returns null when the map has no
## loot markers at all.
func _loot_centroid(stats: Dictionary) -> Variant:
	var acc := Vector3.ZERO
	var n := 0
	for e_var in stats.get("major_loot_spawns", []):
		if e_var is Dictionary and (e_var as Dictionary).get("pos", null) is Vector3:
			acc += ((e_var as Dictionary).get("pos", null) as Vector3)
			n += 1
	for e_var in stats.get("minor_loot_spawns", []):
		if e_var is Dictionary and (e_var as Dictionary).get("pos", null) is Vector3:
			acc += ((e_var as Dictionary).get("pos", null) as Vector3)
			n += 1
	for p_var in stats.get("loot_spawns", []):
		if p_var is Vector3:
			acc += p_var as Vector3
			n += 1
	if n == 0:
		return null
	return acc / float(n)


func _snap_player_to_ground() -> void:
	if player == null:
		return
	var w3d: World3D = get_world_3d()
	if w3d == null:
		return
	var phys: PhysicsDirectSpaceState3D = w3d.direct_space_state
	# Cast from inside the room (0.5m above spawn) downward so we hit the floor, not the roof above.
	var from_pos: Vector3 = player.position + Vector3(0, 0.5, 0)
	var to_pos: Vector3 = player.position + Vector3(0, -32, 0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from_pos, to_pos, 1)
	var hit: Dictionary = phys.intersect_ray(query)
	if not hit.is_empty():
		var hit_pos: Variant = hit.get("position")
		if hit_pos is Vector3:
			player.position = hit_pos + Vector3(0, 0.15, 0)


func _ground_position(pos: Vector3, up_m: float = 8.0, down_m: float = 30.0, offset_y: float = 0.15) -> Vector3:
	# Off-tree callers (unit probes / spawn previews) have no world; the engine
	# would log "!is_inside_world()" for get_world_3d(), so return the same
	# clearance the no-hit path below uses.
	if not is_inside_tree():
		return pos + Vector3(0.0, offset_y, 0.0)
	var w3d: World3D = get_world_3d()
	if w3d == null:
		return pos + Vector3(0.0, offset_y, 0.0)
	var phys: PhysicsDirectSpaceState3D = w3d.direct_space_state
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(pos + Vector3(0.0, up_m, 0.0), pos + Vector3(0.0, -down_m, 0.0), 1)
	var hit: Dictionary = phys.intersect_ray(q)
	if not hit.is_empty():
		var hp: Variant = hit.get("position", null)
		if hp is Vector3:
			return (hp as Vector3) + Vector3(0.0, offset_y, 0.0)
	return pos + Vector3(0.0, 0.5, 0.0)


## P2 ground loot/civilians: marker positions are authored points on the floor
## or shelf, but loot actors are centred on their origin, so the old blanket
## +0.5 left some items floating (763 loot items) and sank outliers (the
## Fabergé egg AABB min is -0.155 m). Rest the spawned node's real mesh AABB
## bottom on the floor under the marker: ray from +2 m to -6 m on the world
## layer (1) and place the origin so the lowest mesh point sits `clearance`
## above the hit. Meshes are gathered after add_child because LootScript and
## CivilianNPC build their visuals in _ready. Falls back to the marker plus a
## small clearance (still AABB-adjusted) when there is no world/floor.
const SPAWN_GROUND_CLEARANCE: float = 0.03


func _ground_spawn_node(node: Node3D, marker: Vector3, clearance: float = SPAWN_GROUND_CLEARANCE) -> void:
	var bottom: float = _spawned_mesh_bottom(node)
	var w3d: World3D = get_world_3d()
	if w3d != null:
		var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(marker + Vector3(0.0, 2.0, 0.0), marker + Vector3(0.0, -6.0, 0.0), 1)
		var hit: Dictionary = w3d.direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var hp: Variant = hit.get("position", null)
			if hp is Vector3:
				node.position = Vector3(marker.x, (hp as Vector3).y + clearance - bottom, marker.z)
				return
	node.position = marker + Vector3(0.0, clearance - bottom, 0.0)


## Lowest mesh point of a spawned node in its own local space (loot visual
## root, civilian mesh root). Includes each MeshInstance3D's authored scale and
## rotation so the AABB bottom is the real resting point; 0.0 when the node
## carries no mesh (small clearance only).
func _spawned_mesh_bottom(node: Node3D) -> float:
	return PersonalQuestSpawnerScript.mesh_bottom(node)


## Guard-carried keys use the shipped item names (authored text tables), not
## the extracted mesh/icon names. The Guildhall constable carries the
## Guildhall Key (S22/KF25 pickpocket); Old Manor carries the Elway Manor Key;
## the remaining safe/lock meshes are Vault Keys. Mesh paths stay the
## extracted KeyCabinets assets so the belt visual is unchanged.
func _key_pool_for_map(map_id: String) -> Array[Dictionary]:
	var primary_id: String = "key_vault"
	var primary_name: String = "Vault Key"
	match map_id:
		"guildhall":
			primary_id = "key_guildhall"
			primary_name = "Guildhall Key"
		"old_manor":
			primary_id = "key_manor"
			primary_name = "Elway Manor Key"
	return [
		{"id": primary_id, "name": primary_name, "kind": "key", "value": 150, "mesh_path": "res://assets/ue/Content/Art/Gameplay/KeyCabinets/SM_LootableKeys_ManorKey.glb"},
		{"id": "key_vault", "name": "Vault Key", "kind": "key", "value": 120, "mesh_path": "res://assets/ue/Content/Art/Gameplay/KeyCabinets/SM_LootableKeys_LockedRoomKey.glb"},
		{"id": "key_vault", "name": "Vault Key", "kind": "key", "value": 180, "mesh_path": "res://assets/ue/Content/Art/Gameplay/KeyCabinets/SM_LootableKeys_SecretChestKey.glb"},
		{"id": "key_vault", "name": "Vault Key", "kind": "key", "value": 90, "mesh_path": "res://assets/ue/Content/Art/Gameplay/KeyCabinets/SM_LootableKeys_SmallChestKey.glb"},
	]


func _spawn_guards(ue_spawns: Array, anchor: Vector3, patrol_paths: Array = []) -> void:
	# P1 flat Novice-to-Thief guard count: the old limit ignored the first two
	# difficulties (identical patrol density Novice/Thief). Novice 4 / Thief 6 /
	# Master Thief 8 (UE path: none authored per difficulty; retained tuning,
	# fail-loud if the difficulty enum is unreadable).
	var limit: int = 6
	match GameState.difficulty:
		GameState.Difficulty.NOVICE:
			limit = 4
		GameState.Difficulty.MASTER_THIEF:
			limit = 8
	var chosen: Array[Vector3] = []
	for p in ue_spawns:
		if p is Vector3 and p.distance_to(anchor) > 10.0 and p.distance_to(anchor) < 120.0:
			chosen.append(p)
			if chosen.size() >= limit:
				break
	if chosen.is_empty():
		chosen = [anchor + Vector3(12, 0, 0), anchor + Vector3(-12, 0, -10), anchor + Vector3(0, 0, -18), anchor + Vector3(16, 0, -16)]

	var key_pool: Array[Dictionary] = _key_pool_for_map(str(GameState.active_map_id))

	var used_paths: Dictionary = {}
	for idx: int in range(chosen.size()):
		var pos: Vector3 = chosen[idx]
		var g := GuardScript.new()
		g.level_ctrl = self
		if idx % 2 == 0:
			g.name = "Guard_ClubLantern_%d" % idx
			g.carries_lantern = true
		else:
			g.name = "Guard_%d" % idx
		var grounded_pos: Vector3 = _ground_position(pos, 8.0, 30.0, 0.15)
		var path_index: int = _authored_patrol_index_for(pos, patrol_paths, used_paths)
		if path_index >= 0:
			used_paths[path_index] = true
			_assign_authored_patrol(g, patrol_paths[path_index] as Dictionary)
			patrol_paths_assigned += 1
		else:
			# Synthetic 6x6 m square is the documented fallback; say which guard
			# and how far the nearest real path was, once per guard.
			var nearest_m: float = _nearest_patrol_point_distance(pos, patrol_paths)
			patrol_fallback_count += 1
			var line: String = "patrol fallback: guard %d spawn (%.1f, %.1f, %.1f) has no authored path within %.0f m (nearest %.2f m); using synthetic 6x6 m square" % [
				idx, pos.x, pos.y, pos.z, PATROL_MATCH_RADIUS_M, nearest_m,
			]
			patrol_fallback_log.append(line)
			print("[mission_controller] ", line)
			g.patrol_points = [
				grounded_pos,
				_ground_position(pos + Vector3(6, 0, 0), 8.0, 30.0, 0.15),
				_ground_position(pos + Vector3(6, 0, 6), 8.0, 30.0, 0.15),
				_ground_position(pos + Vector3(0, 0, 6), 8.0, 30.0, 0.15),
			] as Array[Vector3]
		g.position = grounded_pos
		if idx % 2 == 0 or idx == 1:
			g.set_carried_item(key_pool[idx % key_pool.size()])
		add_child(g)


## Index of the authored APatrolPath to give a guard spawned at `pos`, or -1.
## First pass searches unused paths (one path is never handed to two guards
## while another is available); the second pass may reuse a path better than
## inventing a square. The nearest point of the candidate path must be within
## PATROL_MATCH_RADIUS_M. `used` is index -> true and is updated by the caller.
func _authored_patrol_index_for(pos: Vector3, patrol_paths: Array, used: Dictionary) -> int:
	var best_used: int = -1
	var best_used_d: float = PATROL_MATCH_RADIUS_M
	var best_any: int = -1
	var best_any_d: float = PATROL_MATCH_RADIUS_M
	for i: int in range(patrol_paths.size()):
		if not (patrol_paths[i] is Dictionary):
			continue
		var d: float = _patrol_path_point_distance(pos, patrol_paths[i] as Dictionary)
		if d > PATROL_MATCH_RADIUS_M:
			continue
		if d < best_any_d:
			best_any_d = d
			best_any = i
		if not used.has(i) and d < best_used_d:
			best_used_d = d
			best_used = i
	if best_used >= 0:
		return best_used
	return best_any


## Nearest authored waypoint distance (metres) for one path record; INF when
## the record has no readable points.
func _patrol_path_point_distance(pos: Vector3, path: Dictionary) -> float:
	var best: float = INF
	for p_var: Variant in path.get("points", []) as Array:
		if not (p_var is Dictionary):
			continue
		var point: Vector3 = _patrol_point_position(p_var as Dictionary)
		if point.is_finite():
			best = minf(best, pos.distance_to(point))
	return best


## Nearest authored waypoint distance across every path; INF when none parse.
func _nearest_patrol_point_distance(pos: Vector3, patrol_paths: Array) -> float:
	var best: float = INF
	for path_var: Variant in patrol_paths:
		if path_var is Dictionary:
			best = minf(best, _patrol_path_point_distance(pos, path_var as Dictionary))
	return best


## Reads a parser point record (pos is a 3-element Godot-metres Array; the
## parser already converted UE axes) into a Vector3. INF marks a malformed row.
func _patrol_point_position(point: Dictionary) -> Vector3:
	var pos_v: Variant = point.get("pos", null)
	if not (pos_v is Array) or (pos_v as Array).size() < 3:
		return Vector3(INF, INF, INF)
	return Vector3(float((pos_v as Array)[0]), float((pos_v as Array)[1]), float((pos_v as Array)[2]))


## Copies APatrolPath points onto the guard: positions (authored y kept; the
## guard's movement is planar and floor contact owns y), per-point dwell in
## seconds, facing yaw in UE degrees (applied only when facing was authored)
## and the loop type (PingPong reverses). Records are not transformed again:
## the parser already wrote Godot metres/axes.
func _assign_authored_patrol(guard: Node, path: Dictionary) -> void:
	var points: Array[Vector3] = []
	var waits: Array[float] = []
	var yaws: Array[float] = []
	var facings: Array[bool] = []
	for p_var: Variant in path.get("points", []) as Array:
		if not (p_var is Dictionary):
			continue
		var pt: Dictionary = p_var as Dictionary
		var point: Vector3 = _patrol_point_position(pt)
		if not point.is_finite():
			continue
		points.append(point)
		waits.append(maxf(0.0, float(pt.get("wait", 0.0))))
		yaws.append(float(pt.get("yaw", 0.0)))
		facings.append(bool(pt.get("facing", false)))
	if points.is_empty():
		return
	guard.set("patrol_points", points)
	guard.set("patrol_waits", waits)
	guard.set("patrol_yaws", yaws)
	guard.set("patrol_facing", facings)
	guard.set("patrol_loop_mode", str(path.get("loop_type", "")))


## Real loot wave from loot_actors.json (tools/parse_loot.py): one LootScript
## per minor/major marker with the bucket actor class picked deterministically
## from the weighted bucket list, the real mesh + table name/value, and the
## marker rotation. Quest items are added separately at their authored
## BP_QuestSpawner_Item_C transform (see _spawn_quest_items); the regular
## markers are never consumed for them. Escape gating, groups and the
## Thieves' Den skip in start_contract() are unchanged.
func _spawn_loot_and_quest(stats: Dictionary, anchor: Vector3) -> void:
	_load_loot_tables()
	var minor: Array = []
	minor.append_array(stats.get("minor_loot_spawns", []))
	var major: Array = []
	major.append_array(stats.get("major_loot_spawns", []))
	if minor.is_empty() and major.is_empty():
		# Compat: maps with no exact-class markers reuse the legacy Vector3
		# loot_spawns as minor entries (keeps old counts on such maps).
		for p in stats.get("loot_spawns", []):
			if p is Vector3:
				minor.append({"pos": p, "rotation": Vector3.ZERO, "class": "BP_MissionSpawner_MinorLoot_C", "source_file": ""})
	if minor.is_empty() and major.is_empty():
		# Maps with no markers at all keep six hand-placed fallback positions.
		for off in [Vector3(4, 0.8, -6), Vector3(-6, 0.8, -8), Vector3(10, 0.8, -14), Vector3(-10, 0.8, -16), Vector3(0, 0.8, -22), Vector3(8, 0.8, 4)]:
			minor.append({"pos": anchor + (off as Vector3), "rotation": Vector3.ZERO, "class": "BP_MissionSpawner_MinorLoot_C", "source_file": ""})
	var mid: String = str(_active_mission_row.get("id", ""))
	_spawn_loot_entries(minor, "minor")
	_spawn_loot_entries(major, "major")
	var quest_count: int = _spawn_quest_items()
	if quest_count > 0:
		print("TAT-2 quest items: spawned=", quest_count, " mission=", mid, " free_play=", GameState.free_play)


## Authored quest-item pass: the mission plan (free play) or contract row
## (contract deploy) names the items, their NumberToSpawn and their
## QuestLocation tag. Each item is placed on a distinct authored
## BP_QuestSpawner_Item_C at the spawner transform; no loot marker is
## substituted, and a missing tag is a loud error.
func _spawn_quest_items() -> int:
	var active: Dictionary = _active_quest_objective()
	var objective: Dictionary = active.get("objective", {}) as Dictionary
	if objective.is_empty():
		return 0
	var kind: String = str(objective.get("kind", ""))
	if kind != "single" and kind != "multiple" and kind != "set":
		return 0
	var records: Array[Dictionary] = spawn_authored_quest_items(objective, GameState.active_map_id, GameState.active_map_seed, _loaded_level_names)
	_quest_item_spawns = records
	return records.size()


## Public quest-item spawn pass used by the mission and the headless suite.
## Returns one record per spawned actor (node, authored item, spawner, facts).
func spawn_authored_quest_items(objective: Dictionary, map_id: String, seed_value: int, levels: Array = []) -> Array[Dictionary]:
	_load_loot_tables()
	var out: Array[Dictionary] = []
	var items_v: Variant = objective.get("items", [])
	if not (items_v is Array):
		return out
	var items: Array = items_v as Array
	var kind: String = str(objective.get("kind", ""))
	var used_spawners: Dictionary = {}
	for item_index: int in range(items.size()):
		if not (items[item_index] is Dictionary):
			continue
		var item: Dictionary = items[item_index] as Dictionary
		var loot_tag: String = str(item.get("loot_tag", ""))
		var location_tag: String = str(item.get("effective_quest_location", item.get("quest_spawn_location", "")))
		if location_tag == "" or location_tag == "None":
			var loot_row: Dictionary = GameData.get_loot_quest_row(loot_tag)
			location_tag = str(loot_row.get("quest_location_tag", ""))
		var count: int = 1
		if item.get("number_to_spawn", null) != null:
			count = maxi(int(item.get("number_to_spawn")), 1)
		if location_tag == "" or location_tag == "None":
			push_error("[mission_controller] quest item spawn: no authored QuestLocation for loot tag '", loot_tag, "' mission '", GameState.active_mission_id, "' map '", map_id, "'")
			continue
		var candidates: Array[Dictionary] = GameData.get_quest_spawners(map_id, location_tag, levels)
		if candidates.is_empty():
			push_error("[mission_controller] quest item spawn: no BP_QuestSpawner_Item_C for tag '", location_tag, "' loot '", loot_tag, "' mission '", GameState.active_mission_id, "' map '", map_id, "'")
			continue
		for n: int in range(count):
			var spawner: Dictionary = _find_distinct_quest_spawner(candidates, used_spawners, seed_value, loot_tag, item_index * 8 + n)
			if spawner.is_empty():
				push_error("[mission_controller] quest item spawn: only ", n, " distinct spawner(s) for tag '", location_tag, "' loot '", loot_tag, "' mission '", GameState.active_mission_id, "' map '", map_id, "' (requested ", count, ")")
				break
			var objective_id: String = "set_item_%d" % item_index if kind == "set" else "vault_main"
			var rec: Dictionary = _spawn_quest_loot_at(spawner, item, objective_id, item_index)
			if not rec.is_empty():
				out.append(rec)
	return out


func _find_distinct_quest_spawner(candidates: Array[Dictionary], used: Dictionary, seed_value: int, loot_tag: String, index: int) -> Dictionary:
	var pool: Array[Dictionary] = candidates.duplicate()
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _spawner_key(a) < _spawner_key(b))
	var start: int = posmod(LevelLoaderScript._sv_fnv1a("%d|%s|%d" % [seed_value, loot_tag, index]), pool.size())
	for offset: int in range(pool.size()):
		var rec: Dictionary = pool[(start + offset) % pool.size()]
		var key: String = _spawner_key(rec)
		if used.has(key):
			continue
		used[key] = true
		return rec
	return {}


func _spawn_quest_loot_at(spawner: Dictionary, item: Dictionary, objective_id: String, item_index: int) -> Dictionary:
	var display_name: String = str(item.get("display_name", ""))
	var loot_tag: String = str(item.get("loot_tag", ""))
	var actor_class: String = str(item.get("actor_class", ""))
	var q := LootScript.new()
	q.is_quest_item = true
	q.loot_tier = "quest"
	q.item_name = display_name
	q.display_name = display_name
	q.value = int(item.get("value", 0))
	var qactors: Dictionary = loot_tables.get("quest_actors", {})
	var qactor_v: Variant = qactors.get(actor_class)
	if qactor_v is Dictionary:
		q.mesh_path = str((qactor_v as Dictionary).get("mesh_res", ""))
	elif actor_class != "":
		push_error("[mission_controller] quest item spawn: authored actor class '", actor_class, "' has no mesh row in loot_actors.json (item '", display_name, "')")
	q.set("authored_actor_class", actor_class)
	q.set("clue_location_text", str(spawner.get("clue_location_text", "")))
	q.set("objective_id", objective_id)
	q.set("loot_tag", loot_tag)
	var fact_ids: Array[String] = []
	var actions_v: Variant = spawner.get("spawn_actions", [])
	if actions_v is Array:
		for action_v: Variant in (actions_v as Array):
			if not (action_v is Dictionary):
				continue
			var action: Dictionary = action_v as Dictionary
			for fid: String in GameData.get_fact_ids_for_tag(str(action.get("clue_fact_tag", ""))):
				if not fact_ids.has(fid):
					fact_ids.append(fid)
	var pickup: Dictionary = GameData.get_pickup_clue(str(item.get("loot_row", "")))
	var pickup_facts_v: Variant = pickup.get("fact_ids", [])
	if pickup_facts_v is Array:
		for fid_v: Variant in (pickup_facts_v as Array):
			var fid2: String = str(fid_v)
			if fid2 != "" and not fact_ids.has(fid2):
				fact_ids.append(fid2)
	q.set("fact_ids", fact_ids)
	q.set("fact_params", {
		"item": display_name,
		"Location": str(spawner.get("clue_location_text", "")),
		"loot_tag": loot_tag,
	})
	q.set("fact_source", "loot")
	q.set("fact_source_item_tag", loot_tag)
	q.set("fact_source_index", item_index)
	q.transform = _spawner_transform(spawner)
	add_child(q)
	return {
		"node": q,
		"loot_tag": loot_tag,
		"display_name": display_name,
		"actor_class": actor_class,
		"location_text": str(spawner.get("clue_location_text", "")),
		"objective_id": objective_id,
		"spawner": spawner,
		"fact_ids": fact_ids,
		"fact_params": q.get("fact_params"),
	}


## Deterministic weighted pick from a bucket class list (duplicates carry the
## designer weight): a pure function of marker position + order, no RNG, so
## every run spawns the same actor on the same marker.
## P2 bucket-hash duplication: loot_container.bucket_index is the single
## source of truth (same formula, one home). This wrapper keeps call sites
## stable and pins parity: any drift between the two fails loud.
static func _loot_bucket_index(pos: Vector3, order: int, size: int) -> int:
	var shared: int = LootContainerScript.bucket_index(pos, order, size)
	var h: int = int(absf(pos.x * 12.9898 + pos.y * 78.233 + pos.z * 37.719 + float(order) * 0.731))
	var local: int = posmod(h, size) if size > 0 else 0
	if shared != local:
		push_error("[mission_controller] loot bucket hash drift vs loot_container.bucket_index (UE loot wave parity)")
		assert(false, "loot bucket hash drift")
	return shared


func _spawn_loot_entries(entries: Array, tier: String) -> void:
	var buckets: Dictionary = loot_tables.get("buckets", {})
	var bucket: Array = (buckets.get(tier, {}) as Dictionary).get("classes", [])
	var actors: Dictionary = loot_tables.get("actors", {})
	var order := 0
	for e_var in entries:
		if not (e_var is Dictionary):
			continue
		var e: Dictionary = e_var
		var pos: Vector3 = e.get("pos", Vector3.ZERO) as Vector3
		var l := LootScript.new()
		l.loot_tier = tier
		l.is_quest_item = false
		var resolved := false
		if not bucket.is_empty():
			var cls := str(bucket[_loot_bucket_index(pos, order, bucket.size())])
			var a: Variant = actors.get(cls, null)
			if a is Dictionary:
				l.item_name = str((a as Dictionary).get("name", "Noble Relic"))
				l.display_name = l.item_name
				l.value = int((a as Dictionary).get("value", 75))
				l.mesh_path = str((a as Dictionary).get("mesh_res", ""))
				resolved = true
		if not resolved:
			# Labelled fallback (JSON unreadable or class unmapped): same
			# tier-entry pool as the old spawner, legacy note mesh.
			var entry: Dictionary = LootScript.tier_entry(tier, order)
			l.item_name = str(entry.get("name", "Noble Relic #%d" % (order + 1)))
			l.display_name = l.item_name
			l.value = int(entry.get("value", 75))
		l.mesh_rotation_deg = e.get("rotation", Vector3.ZERO) as Vector3
		# P2 ground loot: the authored marker is a floor/shelf point; the mesh
		# AABB bottom (built in LootScript._ready) rests on the raycast floor.
		l.position = pos
		add_child(l)
		_ground_spawn_node(l, pos)
		order += 1


## Real loot wave tables (loot_actors.json from tools/parse_loot.py): bucket
## class lists (duplicates = designer weight), actor meshes + names/values,
## quest tag mapping. When the JSON is unreadable the spawns fall back to the
## tier-entry pool with legacy meshes (labelled fallback, counts unchanged).
func _load_loot_tables() -> void:
	if not loot_tables.is_empty():
		return
	loot_tables = {
		"buckets": {"minor": {"classes": []}, "major": {"classes": []}},
		"actors": {},
		"quest_actors": {},
		"tag_to_actor": {},
		"fallback_quest_actor": "",
	}
	if not FileAccess.file_exists("res://data/generated/gameplay/loot_actors.json"):
		return
	var f := FileAccess.open("res://data/generated/gameplay/loot_actors.json", FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		return
	loot_tables["buckets"] = (data as Dictionary).get("buckets", loot_tables["buckets"])
	loot_tables["actors"] = (data as Dictionary).get("actors", {})
	loot_tables["quest_actors"] = (data as Dictionary).get("quest_actors", {})
	loot_tables["tag_to_actor"] = (data as Dictionary).get("tag_to_actor", {})
	var fb: Variant = (data as Dictionary).get("fallback", {})
	if fb is Dictionary:
		loot_tables["fallback_quest_actor"] = str((fb as Dictionary).get("generic_quest_actor", ""))


## P1 spawner/eco check vs the unified loot_goal (Phase-1 T3 single source of
## truth): sums every spawned loot value after the wave + containers and
## fails loud when the map cannot pay the goal. Data-driven, so no assert —
## the error log is the signal (UE loot_actors.json values vs loot_goal).
func _audit_loot_economy() -> void:
	if GameState.loot_goal <= 0:
		return
	var total: int = 0
	for n in get_tree().get_nodes_in_group("loot"):
		var lv: Variant = n.get("value")
		if lv != null:
			total += int(lv)
	if total < GameState.loot_goal:
		push_error("[mission_controller] loot economy shortfall: spawned value ", total, " < loot_goal ", GameState.loot_goal, " (UE loot_actors.json vs unified goal)")
	else:
		print("TAT-2 loot economy: ", total, " >= loot_goal ", GameState.loot_goal)


## Openable loot containers (tools/parse_containers.py): one trigger-only Area3D
## per container marker, placed at the marker transform. Container meshes are
## level geometry and are never spawned here. Skipped for the Thieves' Den hub
## by the caller, like the loot wave.
func _spawn_loot_containers(stats: Dictionary) -> void:
	var order := 0
	for e_var in stats.get("loot_containers", []):
		if not (e_var is Dictionary):
			continue
		var e: Dictionary = e_var
		var c := LootContainerScript.new()
		c.configure(str(e.get("class", "")), e, order)
		add_child(c)
		order += 1
	print("TAT-2 loot containers: ", order)


## Real swinging doors (tools/parse_tables.py swinging_doors): one
## SwingingDoorScript node per pivot entry, built from the authored pivot
## transform + template leaf meshes. Skipped when the map has no doors; no
## extra meshes are ever spawned here (leaves were excluded from the static
## batches at parse time).
func _spawn_swinging_doors(stats: Dictionary) -> void:
	var doors: Array = stats.get("swinging_doors", [])
	var door_records: Array = stats.get("door_spawn_records", [])
	var count := 0
	for d_var in doors:
		if not (d_var is Dictionary):
			continue
		var dd: Dictionary = d_var as Dictionary
		var door := SwingingDoorScript.new()
		# W6b: stable authored-order name so host and client resolve the same
		# world-event target (auto names depend on tree history, not the map).
		door.name = "SwingingDoor_%d" % count
		door.configure(dd, level_loader)
		# Lock high-security/vault/prison swinging doors on missions (never index 0 or Thieves' Den).
		# A SceneVariant Locks.Doors override with an exact authored tag wins.
		if not _is_thieves_den and count > 0:
			var sv_locked: Variant = dd.get("scene_locked", null)
			if sv_locked is bool:
				door.set_locked(bool(sv_locked), 3 if bool(sv_locked) else 0)
			elif not door.locked:
				var hi_sec: bool = false
				for lf_v: Variant in (dd.get("leaves", []) as Array):
					if lf_v is Dictionary:
						var m_file: String = str((lf_v as Dictionary).get("mesh", "")).get_file().to_lower()
						if m_file.find("prison") >= 0 or m_file.find("vault") >= 0 or m_file.find("cell") >= 0 or m_file.find("security") >= 0 or m_file.find("safe") >= 0:
							hi_sec = true
							break
				if hi_sec:
					door.set_locked(true, 3 + (count % 2))
				elif count % 12 == 5:
					door.set_locked(true, 1 + (count % 3))
		add_child(door)
		count += 1
	for rec_var in door_records:
		if not (rec_var is Dictionary):
			continue
		var rec: Dictionary = rec_var as Dictionary
		var leaf_mesh: String = str(rec.get("leaf_mesh", "/Game/Art/Environment/Props/Doors/SM_DoorInaccessibleA"))
		var entry: Dictionary = {
			"pos": rec.get("pos", [0.0, 0.0, 0.0]),
			"basis": rec.get("basis", [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]),
			"leaves": [{
				"mesh": leaf_mesh,
				"rel_pos": rec.get("leaf_rel_pos", [-1.22, 0.0, 0.0]),
				"rel_basis": rec.get("leaf_rel_basis", [-1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, -1.0]),
				"rel_scale": rec.get("leaf_rel_scale", [1.0, 0.8925, 1.0]),
			}],
		}
		var exit_door := SwingingDoorScript.new()
		exit_door.name = "ThievesDenExitDoor"
		exit_door.configure(entry, level_loader)
		add_child(exit_door)
		count += 1
	if count > 0:
		print("TAT-2 swinging doors: ", count)


## Authored device runtime layer (tools/parse_devices.py output). Spawns one
## node per device of the active map after the real doors; the layer owns its
## own 10 Hz tick and power/action graph resolution. Data-only families stay
## deterministic markers until their wave lands.
func _spawn_devices() -> void:
	var layer: Node3D = DeviceLayerScript.new() as Node3D
	layer.name = "DeviceLayer"
	add_child(layer)
	var count: int = int(layer.call("spawn_for_map", GameState.active_map_id, player, GameState.difficulty))
	if count > 0:
		var parts: Array[String] = []
		var counts_v: Variant = layer.get("family_counts")
		if counts_v is Dictionary:
			var counts: Dictionary = counts_v as Dictionary
			var keys: Array = counts.keys()
			keys.sort()
			for key: Variant in keys:
				parts.append("%s=%d" % [str(key), int(counts[key])])
		print("TAT-2 authored devices: ", count, " (", ", ".join(parts), ")")


## P2 escape grounding: explicit floor raycast with a hit flag (unlike
## _ground_position's fail-soft fallback, which is indistinguishable from a hit).
func _ground_escape_position(raw: Vector3) -> Vector3:
	var w3d: World3D = get_world_3d()
	if w3d == null:
		push_warning("[mission_controller] escape grounding without a world; keeping authored marker (UE escape path)")
		return raw
	var phys: PhysicsDirectSpaceState3D = w3d.direct_space_state
	var hit: Dictionary = phys.intersect_ray(PhysicsRayQueryParameters3D.create(raw + Vector3(0.0, 8.0, 0.0), raw + Vector3(0.0, -30.0, 0.0), 1))
	if hit.is_empty():
		push_warning("[mission_controller] escape marker has no floor below; keeping authored pos (UE escape marker): ", raw)
		return raw
	var hp: Variant = hit.get("position", null)
	if hp is Vector3:
		return (hp as Vector3) + Vector3(0.0, 0.15, 0.0)
	push_warning("[mission_controller] escape raycast hit without a position; keeping authored marker (UE escape path)")
	return raw


func _spawn_escape(ue_escapes: Array, anchor: Vector3) -> void:
	# P2 escape not floor-grounded: guards/loot raycast to the floor, the gate
	# used the raw authored marker (a floating marker = a floating gate, UE
	# escape marker path). Ground it; keep the authored pos with a loud warning
	# when no floor is found instead of silently floating.
	var eg := EscapeScript.new()
	var epos := anchor + Vector3(0, 0.2, 6)
	if not ue_escapes.is_empty():
		var raw: Vector3 = ue_escapes[0]
		epos = _ground_escape_position(raw)
	eg.apply_escape_config(EscapeScript.escape_config())
	eg.position = epos
	eg.extracted.connect(_on_extracted)
	add_child(eg)


## Real spawner content (BP_MissionSpawner_Throwable/AmmoRefill/Health/
## Civilian markers): 529 bottles + 143 ammo + 12 health + 5 civilians on
## the shipped maps. Meshes come from spawners.json (existence-checked at
## parse time); hardcoded paths below are the same extracted values and
## apply only when the JSON is unreadable. Pickups are trigger-only Area3Ds
## (no static physics bodies); meshes are distance-culled at ~45 m.
func _load_spawner_tables() -> void:
	if not spawner_meshes.is_empty():
		return
	spawner_meshes = {
		"throwable": [
			"res://assets/ue/Content/Art/Environment/Props/Dining/Food/Wine/SM_BottleWineB.glb",
			"res://assets/ue/Content/Art/Environment/Props/Dining/Food/Wine/SM_BottleWineA.glb",
		],
		"ammo": ["res://assets/ue/Content/Art/Environment/Props/Containers/Toolbox/SM_Toolbox.glb"],
		"health": ["res://assets/ue/Content/Art/Gameplay/Health/SM_HealthPackA.glb"],
	}
	# One source for civilian body/head meshes: GameData reads the generated
	# spawners.json (and keeps the parse-time fallback pair).
	spawner_civilians = GameData.get_civilian_meshes()
	if not FileAccess.file_exists("res://data/generated/gameplay/spawners.json"):
		return
	var f := FileAccess.open("res://data/generated/gameplay/spawners.json", FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		return
	var by_kind: Dictionary = {"throwable": [], "ammo": [], "health": []}
	for e_var in (data as Dictionary).get("buckets", []):
		if not (e_var is Dictionary):
			continue
		var e: Dictionary = e_var
		var k := str(e.get("kind", ""))
		if by_kind.has(k) and str(e.get("mesh_res_path", "")) != "":
			(by_kind[k] as Array).append(str(e["mesh_res_path"]))
	for k2 in by_kind.keys():
		if not (by_kind[k2] as Array).is_empty():
			spawner_meshes[k2] = by_kind[k2]


func _spawn_spawner_content(stats: Dictionary) -> void:
	_load_spawner_tables()
	var n_throw := _spawn_pickups(stats.get("throwable_spawns", []), WorldPickupScript.Kind.THROWABLE, spawner_meshes.get("throwable", []))
	var n_ammo := _spawn_pickups(stats.get("ammo_spawns", []), WorldPickupScript.Kind.AMMO, spawner_meshes.get("ammo", []))
	var n_hp := _spawn_pickups(stats.get("health_spawns", []), WorldPickupScript.Kind.HEALTH, spawner_meshes.get("health", []))
	var n_civ := _spawn_civilians(stats.get("civilian_spawns", []))
	print("TAT-2 spawners: throwable=", n_throw, " ammo=", n_ammo, " health=", n_hp, " civilian=", n_civ)


func _spawn_pickups(spawns: Array, kind: int, meshes: Array) -> int:
	if meshes.is_empty():
		return 0
	var count: int = 0
	for pos_var in spawns:
		if not (pos_var is Vector3):
			continue
		var p := WorldPickupScript.new()
		p.setup(kind, str(meshes[count % meshes.size()]))
		p.position = (pos_var as Vector3) + Vector3(0.0, 0.35, 0.0)
		add_child(p)
		count += 1
	return count


func _spawn_civilians(spawns: Array) -> int:
	var count: int = 0
	for pos_var in spawns:
		if not (pos_var is Vector3):
			continue
		var variant: Dictionary = spawner_civilians[count % spawner_civilians.size()] if not spawner_civilians.is_empty() else {}
		var c := CivilianScript.new()
		c.setup(str(variant.get("body", "")), str(variant.get("head", "")), pos_var as Vector3)
		c.position = pos_var as Vector3
		add_child(c)
		_ground_spawn_node(c, pos_var as Vector3)
		count += 1
	return count


## Real UE values (BP_SmokeBomb_Bomb_Tool 1 charge;
## BP_SmokeBomb_WorldActor BoxExtent {250, 250, 200} cm, InitialLifeSpan 25.0):
## the smoke volume is a 5 x 5 x 4 m axis-aligned box, not a sphere.
const SMOKE_HALF_EXTENTS: Vector3 = Vector3(2.5, 2.0, 2.5)
const SMOKE_TTL: float = 25.0
## P1 timer-during-letter grace: run clock holds this long after the start
## letter is requested (retained tuning, no UE source; HUD letter is read-only).
const LETTER_GRACE_SEC: float = 6.0


func spawn_smoke(pos: Vector3, ttl: float = SMOKE_TTL) -> void:
	# P1 smoke visual/gameplay desync: the old bookkeeping stored node:null
	# while the visual lived on VfxManager's own lifetime, so expiry bookkeeping
	# and the visual could disagree. Gameplay occlusion is authoritative here
	# (single 5x5x4 m box over SMOKE_TTL); the visual is cosmetic. Callers pass
	# the same 25.0 (thrown_bottle IMPACT path, thief fallback path); any other
	# TTL fails loud so the two can never drift silently.
	if absf(ttl - SMOKE_TTL) > 0.001:
		push_error("[mission_controller] non-standard smoke TTL ", ttl, "; expected SMOKE_TTL ", SMOKE_TTL, " (gameplay/visual parity)")
		assert(false, "smoke TTL drift vs SMOKE_TTL")
	VfxManager.spawn_smoke_cloud(self, pos, SMOKE_HALF_EXTENTS, SMOKE_TTL)
	var half: Vector3 = SMOKE_HALF_EXTENTS
	smokes.append({"min": pos - half, "max": pos + half, "ttl": SMOKE_TTL})


func is_blocked_by_smoke(a: Vector3, b: Vector3) -> bool:
	for s in smokes:
		if _segment_hits_aabb(a, b, s["min"], s["max"]):
			return true
	return false


## Segment-vs-AABB slab test (t in [0, 1] along a->b).
func _segment_hits_aabb(a: Vector3, b: Vector3, mn: Vector3, mx: Vector3) -> bool:
	var t_min: float = 0.0
	var t_max: float = 1.0
	var origins: Array[float] = [a.x, a.y, a.z]
	var ends: Array[float] = [b.x, b.y, b.z]
	var mins: Array[float] = [mn.x, mn.y, mn.z]
	var maxs: Array[float] = [mx.x, mx.y, mx.z]
	for i in range(3):
		var d: float = ends[i] - origins[i]
		if absf(d) < 0.000001:
			if origins[i] < mins[i] or origins[i] > maxs[i]:
				return false
		else:
			var t0: float = (mins[i] - origins[i]) / d
			var t1: float = (maxs[i] - origins[i]) / d
			if t0 > t1:
				var tmp: float = t0
				t0 = t1
				t1 = tmp
			t_min = maxf(t_min, t0)
			t_max = minf(t_max, t1)
			if t_min > t_max:
				return false
	return true


func _process(delta: float) -> void:
	if GameState.state == "playing":
		# P1 timer-during-letter: the mission-start letter (HUD-side, read-only)
		# never stopped elapsed_sec, so the run clock ate the read time and
		# _on_time_expired could fire mid-letter. Hold the clock for a short
		# grace after the letter is requested (retained tuning
		# LETTER_GRACE_SEC; the lockpick minigame still runs the clock by
		# design — that time is player action, not forced UI).
		if _letter_grace_sec > 0.0:
			_letter_grace_sec = maxf(0.0, _letter_grace_sec - delta)
		else:
			GameState.elapsed_sec += delta
			if GameState.run_time_limit > 0.0 and GameState.elapsed_sec >= GameState.run_time_limit:
				_on_time_expired()
				return
		light_probe.tick(GameState.elapsed_sec)
		for i in range(smokes.size() - 1, -1, -1):
			smokes[i]["ttl"] -= delta
			if smokes[i]["ttl"] <= 0.0:
				smokes.remove_at(i)
		if _is_thieves_den:
			_refresh_den_lookat_card(false)
		# P2 rain-on-result-screens: snap ran every frame including
			# victory/failed panels. Frozen weather on end screens.
		if rain_node != null:
			WeatherVisuals.snap_rain_to(rain_node, player)
			WeatherVisuals.update_rain_occlusion(rain_node, player)


func _on_extracted() -> void:
	GameState.state = "victory"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var final_score := int(round(GameState.loot_value * GameState.compute_stealth_bonus_multiplier()))
	# Free play has no active contract and is not a currency farm: neither the
	# completion record (it would corrupt the hosting order's campaign, order 2
	# is "Into the Lion's Den") nor the payout is banked. The result panel still
	# shows the run score.
	if not GameState.free_play:
		SaveSystem.add_currency(final_score)
		SaveSystem.record_contract_complete(GameState.active_contract_order, final_score, not GameState.ever_spotted)
	if hud.has_method("show_result"):
		hud.show_result(true, final_score, contract_info)


func _on_player_downed_started(seconds: float) -> void:
	# Downed is a 10 s bleed-out window (GE_GrantPlayerDowned_Duration), not
	# instant failure: show the countdown and fail only when `downed` fires.
	if hud != null and hud.has_method("set_downed_display"):
		hud.set_downed_display(true, seconds)


func _on_player_downed() -> void:
	GameState.state = "failed"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hud.has_method("show_result"):
		hud.show_result(false, GameState.loot_value, contract_info)


## Match timer ran out: fail the run with a TIME EXPIRED reason, reusing the
## standard result panel (no new GameState.state value).
func _on_time_expired() -> void:
	if GameState.state != "playing":
		return
	GameState.state = "failed"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	contract_info["timed_out"] = true
	contract_info["timeout_reason"] = "TIME EXPIRED"
	if hud != null and hud.has_method("show_result"):
		hud.show_result(false, GameState.loot_value, contract_info)


## Releases the process-lifetime caches owned by level/weather/VFX/animation
## systems when a mission leaves the tree. Without this the last mission's
## textures, LUTs and retarget caches survive shutdown as leaked resources.
func _exit_tree() -> void:
	# Godot 4.7.2 holds the Den reflection probe atlas (7 texture RIDs) until the
	# node itself is deleted; queue_free() alone leaves it to the tree teardown.
	# Stop updates and free it now so the leak verifier sees a clean exit.
	# 4.7.2 only exposes UPDATE_ONCE/UPDATE_ALWAYS (no UPDATE_NEVER), so the
	# stop is "hide so no capture can start"; free() is what releases the atlas.
	if _den_reflection_probe != null and is_instance_valid(_den_reflection_probe):
		if ClassDB.class_has_integer_constant("ReflectionProbe", "UPDATE_NEVER"):
			_den_reflection_probe.set("update_mode", ClassDB.class_get_integer_constant("ReflectionProbe", "UPDATE_NEVER"))
		else:
			_den_reflection_probe.visible = false
		if _den_reflection_probe.get_parent() != null:
			_den_reflection_probe.get_parent().remove_child(_den_reflection_probe)
		_den_reflection_probe.free()
	_den_reflection_probe = null
	# Stop scene-owned beds/gramophone immediately. Their fade tweens otherwise
	# survive the mission and hold the last rain/roomtone players through quit.
	var am: Node = get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("stop_all_beds"):
		am.call("stop_all_beds", 0.0)
	VfxManager.cleanup_static_caches()
	GuardAnimationLibrary.cleanup_static_caches()
	ArtNouveauTheme.cleanup_static_caches()
	XrayOverlay.clear_static_caches()
	(load("res://src/core/weather_profile.gd") as GDScript).cleanup_static_caches()
	(load("res://src/core/weather_visuals.gd") as GDScript).cleanup_static_caches()
	(load("res://src/ai/guard_ai.gd") as GDScript).cleanup_static_caches()
