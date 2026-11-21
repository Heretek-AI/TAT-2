extends Node3D
## Mission & Contract runner: loads the FULL extracted UE5 sublevels
## (OldManor_Geo/Gameplay/Loot, Guildhall_POI/Geometry/Periphery/Gameplay/Loot,
## ThievesDen_Geo, or FTUE_Geometry for Jaspering Hall expansion),
## spawns real Guard & Thief models, loot spawners, lights, and escape gates.

const ThiefScript := preload("res://src/player/thief_character.gd")
const GuardScript := preload("res://src/ai/guard_ai.gd")
const LootScript := preload("res://src/interact/loot_item.gd")
const LootContainerScript := preload("res://src/interact/loot_container.gd")
const SwingingDoorScript := preload("res://src/interact/swinging_door.gd")
const WorldPickupScript := preload("res://src/interact/world_pickup.gd")
const CivilianScript := preload("res://src/ai/civilian_npc.gd")
const DoorScript := preload("res://src/interact/lockable_door.gd")
const EscapeScript := preload("res://src/interact/escape_gate.gd")
const LightProbeScript := preload("res://src/stealth/light_probe.gd")
const LevelLoaderScript := preload("res://src/core/level_loader.gd")
const MobileProfile := preload("res://src/core/mobile_profile.gd")
const WeatherProfile := preload("res://src/core/weather_profile.gd")
const WeatherVisuals := preload("res://src/core/weather_visuals.gd")
const VfxManager := preload("res://src/core/vfx_manager.gd")
const HudScript := preload("res://src/ui/hud.gd")
const WardrobeUIScript := preload("res://src/ui/wardrobe_ui.gd")
const ContractTableUIScript := preload("res://src/ui/contract_table_ui.gd")
const ClueItemScript := preload("res://src/interact/clue_item.gd")
const LoadingScreenScript := preload("res://src/ui/loading_screen.gd")
const LedgerUIScript := preload("res://src/ui/ledger_ui.gd")
const MobileTouchUIScript := preload("res://src/ui/mobile_touch_ui.gd")

var light_probe: Node
var level_loader: Node
var player: CharacterBody3D
var hud: CanvasLayer
var smokes: Array[Dictionary] = []
var rain_node: Node3D = null
var contract_info: Dictionary = {}
var level_stats: Dictionary = {}
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
var _active_mission_row: Dictionary = {}


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
	start_contract(GameState.active_contract_order)


func _setup_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	_apply_fallback_environment(e)
	var moon := DirectionalLight3D.new()
	_apply_fallback_moon(moon)
	# Real TAT weather first; hand-tuned values above survive any field the
	# preset does not define, and fully survive when no preset maps the map.
	# The real night sky then replaces the flat fallback color (BG_SKY);
	# MobileProfile's glow override still runs last.
	var wpreset: Dictionary = WeatherProfile.preset_for_map(GameState.active_map_id)
	WeatherProfile.apply_environment(e, moon, wpreset)
	WeatherVisuals.apply_sky(e, wpreset, moon)
	MobileProfile.apply_environment(e)
	env.environment = e
	add_child(env)
	print("TAT-2 environment: bg=", e.background_mode, " ambient_src=", e.ambient_light_source, " ambient_energy=", e.ambient_light_energy, " ambient_color=", e.ambient_light_color, " sky=", e.sky != null, " fog=", e.fog_enabled, " fog_density=", e.fog_density)

	add_child(moon)
	light_probe.register_light(moon)


## Previous hand-tuned night look. Used as the base under real weather data
## and as the full fallback when a map has no weather preset.
func _apply_fallback_environment(e: Environment) -> void:
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.028, 0.055)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.16, 0.21, 0.30)
	e.ambient_light_energy = 0.38
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
	GameState.reset_run(order, map_id)
	# Real match timer from the extracted DT_Missions_* tables (0 = unlimited).
	GameState.run_time_limit = GameData.get_match_duration(map_id, GameState.difficulty)
	_setup_mission_objectives(map_id, order)

	var loading: Node = LoadingScreenScript.new()
	add_child(loading)
	if loading.has_method("start_loading"):
		loading.call("start_loading", str(contract_info.get("title", "Contract")), _contract_clue_text(contract_info, ""), map_id)

	var sublevels: Array[String] = _map_id_to_sublevels(map_id, order)
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
	level_stats = ue_level_data
	_apply_level_atmosphere(ue_level_data)
	if int(ue_level_data.get("chunk_count", 0)) > 0:
		print("TAT-2 Perf: chunks=", ue_level_data.get("chunk_count", 0), " collision_bodies=", ue_level_data.get("collision_bodies", 0), " collision_shapes=", ue_level_data.get("collision_shapes", 0), " occluders=", ue_level_data.get("occluder_count", 0))

	# Safety floor plane far below map so player never falls into void if stepping outside bounds
	_add_safety_floor()

	_setup_thieves_den_env(map_id)

	_spawn_player(ue_level_data.get("player_spawns", []), ue_level_data.get("player_spawn_transforms", []), ue_level_data)
	rain_node = WeatherVisuals.make_rain(self, WeatherProfile.preset_for_map(map_id))
	if player != null and hud != null:
		if player.has_signal("thief_vision_toggled") and hud.has_method("set_thief_vision"):
			player.thief_vision_toggled.connect(hud.set_thief_vision)

	var anchor: Vector3 = player.global_position if player != null else Vector3.ZERO
	if map_id == "thieves_den":
		_setup_thieves_den_hub(anchor, ue_level_data)
	else:
		_spawn_guards(ue_level_data.get("guard_spawns", []), anchor)
		_spawn_loot_and_quest(ue_level_data, anchor)
		_spawn_loot_containers(ue_level_data)
		_audit_loot_economy()
		_spawn_clues(ue_level_data.get("loot_spawns", []), anchor)
		_spawn_escape(ue_level_data.get("escape_points", []), anchor)
	_spawn_spawner_content(ue_level_data)
	_spawn_swinging_doors(ue_level_data)

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


func _setup_thieves_den_env(map_id: String) -> void:
	if map_id != "thieves_den":
		return
	for child in get_children():
		if child is WorldEnvironment:
			var wenv: WorldEnvironment = child as WorldEnvironment
			if wenv.environment != null:
				wenv.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
				wenv.environment.ambient_light_color = Color(0.06, 0.08, 0.12)
				wenv.environment.ambient_light_energy = 0.12
				wenv.environment.background_color = Color(0.012, 0.016, 0.032)


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
				"res://data/generated/levels/Guildhall/Guildhall_PeripheryA.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_Loot.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_MissionClues.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_SkyboxGeo.tatlevel.json",
			]
		"thieves_den":
			base = [
				"res://data/generated/levels/ThievesDen/ThievesDen_Geo.tatlevel.json",
				"res://data/generated/levels/ThievesDenTest/ThievesDenTest_P.tatlevel.json",
				"res://data/generated/levels/ThievesDenTest/ThievesDenTest_Periphery.tatlevel.json",
			]
		"jaspering_hall":
			base = [
				"res://data/generated/levels/FTUE/FTUE_Geometry.tatlevel.json",
				"res://data/generated/levels/FTUE/FTUE_Building_JewelryStore.tatlevel.json",
				"res://data/generated/levels/FTUE/FTUE_Building_SpawnArea.tatlevel.json",
				"res://data/generated/levels/FTUE/FTUE_Gameplay.tatlevel.json",
			]
	if base.is_empty():
		return base
	for sub: String in GameData.get_contract_sublevels(order):
		if not base.has(sub):
			base.append(sub)
	return base


func _setup_thieves_den_hub(anchor: Vector3, ue_level_data: Dictionary = {}) -> void:
	# Subtle hand fill lights totaling <= 2.0 energy (0.35 + 0.65 + 0.35 + 0.25 + 0.30 = 1.90)
	# so authored ThievesDen_Geo spots carry the room with no invented red.
	var attic_fill := OmniLight3D.new()
	attic_fill.name = "DenAtticFill"
	attic_fill.position = anchor + Vector3(1.5, 2.6, -1.5)
	attic_fill.light_color = Color(1.0, 0.78, 0.50)
	attic_fill.light_energy = 0.35
	attic_fill.omni_range = 13.0
	attic_fill.omni_attenuation = 0.85
	attic_fill.add_to_group("den_hand_fills")
	add_child(attic_fill)
	light_probe.register_light(attic_fill)

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
	moon_beam.light_energy = 0.65
	moon_beam.spot_range = 14.0
	moon_beam.spot_angle = 26.0
	moon_beam.shadow_enabled = true
	moon_beam.add_to_group("den_hand_fills")
	add_child(moon_beam)
	var beam_target: Vector3 = Vector3(-0.4317, anchor.y + 0.1, 268.9349)
	moon_beam.look_at(beam_target, Vector3.UP)
	light_probe.register_light(moon_beam)
	VfxManager.spawn_window_godray(self, win_pos, beam_target)
	_spawn_den_window_vista(win_pos, beam_target)

	# Single interior ReflectionProbe for Thieves' Den specular reflections.
	var den_probe: ReflectionProbe = ReflectionProbe.new()
	den_probe.name = "ThievesDenReflectionProbe"
	den_probe.position = Vector3(1.5, 42.0, 271.5)
	den_probe.size = Vector3(20.0, 10.0, 16.0)
	den_probe.interior = true
	den_probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	den_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	den_probe.intensity = 0.8
	add_child(den_probe)

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
	VfxManager.spawn_candle_flame(self, desk_pos + Vector3(0.35, 0.45, 0.0))

	# Warm table pool light
	var table_light := OmniLight3D.new()
	table_light.name = "DenTableLight"
	table_light.position = desk_pos + Vector3(0.0, 1.1, 0.0)
	table_light.light_color = Color(1.0, 0.78, 0.48)
	table_light.light_energy = 0.35
	table_light.omni_range = 6.5
	table_light.add_to_group("den_hand_fills")
	add_child(table_light)
	light_probe.register_light(table_light)

	# Interactive Map Table -> opens ContractTableUI (diegetic HUD prompt, no giant Label3D billboard)
	var desk_area := Area3D.new()
	desk_area.name = "DenMapTableArea"
	desk_area.position = desk_pos
	desk_area.add_to_group("interactables")
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

	# Interactive Bureau / Wardrobe -> opens WardrobeUI (diegetic HUD prompt, no giant Label3D billboard)
	var wardrobe_positions: Array = ue_level_data.get("wardrobe_positions", [])
	var wardrobe_pos: Vector3 = Vector3(anchor.x - 2.6, floor_y, anchor.z - 2.0)
	if not wardrobe_positions.is_empty() and wardrobe_positions[0] is Vector3:
		wardrobe_pos = wardrobe_positions[0] as Vector3
	var ward_light := OmniLight3D.new()
	ward_light.name = "DenWardLight"
	ward_light.position = wardrobe_pos + Vector3(0.0, 1.1, 0.4)
	ward_light.light_color = Color(1.0, 0.82, 0.55)
	ward_light.light_energy = 0.25
	ward_light.omni_range = 5.5
	ward_light.add_to_group("den_hand_fills")
	add_child(ward_light)
	light_probe.register_light(ward_light)

	var ward_area := Area3D.new()
	ward_area.name = "DenWardrobeArea"
	ward_area.position = wardrobe_pos
	ward_area.add_to_group("interactables")
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
		{
			# P1 Jaspering Hall unpreviewable: contracts 17-18 deploy to
			# jaspering_hall but the Den roster was hardcoded to two maps.
			# No SM_MapBuilding_Jasper mesh exists in extracted data, so this
			# entry is a loud procedural fallback (never silent): selection,
			# gaze and card work; the warning names the missing art.
			"name": "MapTokenJasperingHall",
			"map_id": "jaspering_hall",
			"ue_mesh": "",
			"ue_mat": "",
			"offset": Vector3(-0.02, 0.02, 0.32),
			"scale": 0.20,
			"fallback_token": true,
		},
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
					sm.emission_energy_multiplier = 0.85
				else:
					sm.emission = Color.BLACK
					sm.emission_energy_multiplier = 0.0


## P1 Jaspering-Hall-unpreviewable roster: selectable Den maps in one place so
## set_den_selected_map and the gaze path cannot drift (P2 gaze bypass).
static func is_selectable_den_map(map_id: String) -> bool:
	return map_id == "old_manor" or map_id == "guildhall" or map_id == "jaspering_hall"


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
		# S05 rooftop wind swell (KF 00:19.6-00:21.9, peaks -39.5 dBFS RMS
		# = the wind bed trim): opt-in bed, off again on exit.
		if AudioManager != null and AudioManager.has_method("start_bed"):
			AudioManager.start_bed("wind")
		# Log-count proof: exactly one ponder-enter line per F press (the
		# frame guard above collapses the Area + lookat double dispatch).
		print("TAT-2 telescope ponder-enter: cam=", _ponder_cam.name, " current=", _ponder_cam.current, " fov=", _ponder_cam.fov, " eye=", _ponder_cam.global_position)
	else:
		if _ponder_cam != null and is_instance_valid(_ponder_cam):
			_ponder_cam.current = false
		if player != null and is_instance_valid(player):
			var pcam_v: Variant = player.get("cam")
			if pcam_v is Camera3D and is_instance_valid(pcam_v as Node):
				(pcam_v as Camera3D).current = true
		if AudioManager != null and AudioManager.has_method("stop_bed"):
			AudioManager.stop_bed("wind")
		print("TAT-2 telescope ponder-exit")
	_refresh_den_lookat_card(true)


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
			var pending_mission_id: String = GameState.active_mission_id
			var pending_mode: String = GameState.active_mission_mode
			GameState.reset_run(order_id, map_id)
			GameState.active_mission_id = pending_mission_id
			GameState.active_mission_mode = pending_mode
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

	var objs: Array[Dictionary] = []
	var goal_val: int = 0
	if mid.ends_with(".Set") or mid.ends_with(".Multi"):
		if map_id == "guildhall":
			objs = [
				{"id": "set_main", "label": "Steal the components of the Staff of Edinburgh", "done": false, "current": 0, "target": 3},
				{"id": "set_item_0", "label": "Sapphire of Edinburgh", "done": false, "current": 0, "target": 1},
				{"id": "set_item_1", "label": "Ruby of Edinburgh", "done": false, "current": 0, "target": 1},
				{"id": "set_item_2", "label": "Emerald of Edinburgh", "done": false, "current": 0, "target": 1},
			]
		elif map_id == "old_manor":
			objs = [
				{"id": "set_main", "label": "Retrieve the Claymur Urns", "done": false, "current": 0, "target": 3},
				{"id": "set_item_0", "label": "Claymur Urn — North Wing", "done": false, "current": 0, "target": 1},
				{"id": "set_item_1", "label": "Claymur Urn — Gallery", "done": false, "current": 0, "target": 1},
				{"id": "set_item_2", "label": "Claymur Urn — Cellar", "done": false, "current": 0, "target": 1},
			]
		else:
			objs = [
				{"id": "set_main", "label": str(chosen.get("title", "Item Collection Heist")), "done": false, "current": 0, "target": 3},
				{"id": "set_item_0", "label": "Relic Piece I", "done": false, "current": 0, "target": 1},
				{"id": "set_item_1", "label": "Relic Piece II", "done": false, "current": 0, "target": 1},
				{"id": "set_item_2", "label": "Relic Piece III", "done": false, "current": 0, "target": 1},
			]
	elif mid.ends_with(".LootTheRoom"):
		goal_val = 1000 * clampi(GameState.difficulty, 1, 3)
		objs = [
			{"id": "cleanout_loot", "label": "Steal £%d worth of loot" % goal_val, "done": false, "current": 0, "target": goal_val},
		]
	else:
		var target_name: String = str(contract_info.get("quest_item", ""))
		if target_name == "" or target_name == "Objective" or target_name.begins_with("Loot."):
			if map_id == "guildhall":
				target_name = "Warburg Effigy"
			elif map_id == "old_manor":
				target_name = "Book of Truth"
			else:
				target_name = "Contract Objective"
		objs = [
			{"id": "vault_main", "label": "Steal the %s" % target_name, "done": false, "current": 0, "target": 1},
		]
	GameState.set_mission_objectives(objs, goal_val)


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


func _spawn_clues(ue_spawns: Array, anchor: Vector3) -> void:
	var clue_title: String = str(contract_info.get("title", "Contract Clue"))
	var clue_body: String = _contract_clue_text(contract_info, "Locate the target vault and watch the Constabulary patrol timing.")
	if clue_body == "":
		clue_body = "Locate the target vault and watch the Constabulary patrol timing."
	var pos: Vector3 = anchor + Vector3(2.5, 0.85, -3.5)
	if not ue_spawns.is_empty() and ue_spawns[0] is Vector3:
		pos = ue_spawns[0] + Vector3(0.0, 0.8, 0.0)
	var clue: Area3D = ClueItemScript.new()
	clue.set("clue_title", clue_title)
	clue.set("clue_body", clue_body)
	clue.position = pos
	if clue.has_signal("clue_collected") and hud != null and hud.has_method("show_clue_toast"):
		clue.connect("clue_collected", hud.show_clue_toast)
	add_child(clue)


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


func _spawn_guards(ue_spawns: Array, anchor: Vector3) -> void:
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

	var key_pool: Array[Dictionary] = [
		{"id": "key_manor", "name": "Manor Key", "kind": "key", "value": 150, "mesh_path": "res://assets/ue/Content/Art/Gameplay/KeyCabinets/SM_LootableKeys_ManorKey.glb"},
		{"id": "key_locked_room", "name": "Locked Room Key", "kind": "key", "value": 120, "mesh_path": "res://assets/ue/Content/Art/Gameplay/KeyCabinets/SM_LootableKeys_LockedRoomKey.glb"},
		{"id": "key_secret_chest", "name": "Secret Chest Key", "kind": "key", "value": 180, "mesh_path": "res://assets/ue/Content/Art/Gameplay/KeyCabinets/SM_LootableKeys_SecretChestKey.glb"},
		{"id": "key_small_chest", "name": "Small Chest Key", "kind": "key", "value": 90, "mesh_path": "res://assets/ue/Content/Art/Gameplay/KeyCabinets/SM_LootableKeys_SmallChestKey.glb"},
	]

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
		var pts: Array[Vector3] = [
			grounded_pos,
			_ground_position(pos + Vector3(6, 0, 0), 8.0, 30.0, 0.15),
			_ground_position(pos + Vector3(6, 0, 6), 8.0, 30.0, 0.15),
			_ground_position(pos + Vector3(0, 0, 6), 8.0, 30.0, 0.15),
		]
		g.patrol_points = pts
		g.position = grounded_pos
		if idx % 2 == 0 or idx == 1:
			g.set_carried_item(key_pool[idx % key_pool.size()])
		add_child(g)


## Real loot wave from loot_actors.json (tools/parse_loot.py): one LootScript
## per minor/major marker with the bucket actor class picked deterministically
## from the weighted bucket list, the real mesh + table name/value, and the
## marker rotation. The contract quest item occupies the last minor marker
## (last major when there are no minors), so the node count still matches the
## marker count exactly and every position stays unique. Escape gating, groups
## and the Thieves' Den skip in start_contract() are unchanged.
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
	var is_set_mission: bool = mid.ends_with(".Set") or mid.ends_with(".Multi")
	var quest_count: int = 3 if is_set_mission else 1
	var quest_entries: Array[Dictionary] = []
	for _qi: int in range(quest_count):
		if not minor.is_empty():
			quest_entries.append(minor[minor.size() - 1] as Dictionary)
			minor.remove_at(minor.size() - 1)
		elif not major.is_empty():
			quest_entries.append(major[major.size() - 1] as Dictionary)
			major.remove_at(major.size() - 1)
		else:
			quest_entries.append({})
	_spawn_loot_entries(minor, "minor")
	_spawn_loot_entries(major, "major")
	var set_labels: Array[String] = []
	for obj_d: Dictionary in GameState.mission_objectives:
		if str(obj_d.get("id", "")).begins_with("set_item_"):
			set_labels.append(str(obj_d.get("label", "")))
	for qi_idx: int in range(quest_entries.size()):
		var override_name: String = set_labels[qi_idx] if qi_idx < set_labels.size() else ""
		_spawn_quest_loot(quest_entries[qi_idx], anchor + Vector3(float(qi_idx) * 1.5, 0.0, 0.0), override_name)


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
		l.position = pos + Vector3(0, 0.5, 0)
		add_child(l)
		order += 1


func _spawn_quest_loot(quest_entry: Dictionary, anchor: Vector3, override_name: String = "") -> void:
	var q := LootScript.new()
	q.is_quest_item = true
	q.loot_tier = "quest"
	var quest_tag: String = str(contract_info.get("loot_tag", ""))
	var tag_to_actor: Dictionary = loot_tables.get("tag_to_actor", {})
	var qactors: Dictionary = loot_tables.get("quest_actors", {})
	var cls := str(tag_to_actor.get(quest_tag, ""))
	if cls == "":
		# Labelled fallback: generic quest actor (first quest-tier actor
		# with an existing mesh, recorded in loot_actors.json).
		cls = str(loot_tables.get("fallback_quest_actor", ""))
	var qentry: Dictionary = LootScript.quest_entry_for_tag(quest_tag)
	var qname := str(contract_info.get("quest_item", "Contract Objective"))
	if not qentry.is_empty():
		qname = str(qentry.get("name", qname))
	if override_name != "":
		qname = override_name
	q.item_name = qname
	q.display_name = qname
	q.value = LootScript.quest_value_for_tag(quest_tag)
	var qactor: Variant = qactors.get(cls, null)
	if qactor is Dictionary and str((qactor as Dictionary).get("mesh_res", "")) != "":
		q.mesh_path = str((qactor as Dictionary).get("mesh_res", ""))
	# else mesh_path stays "": the legacy calling-card mesh (labelled
	# fallback for tags with no dedicated actor / missing mesh).
	if not quest_entry.is_empty():
		q.position = (quest_entry.get("pos", anchor) as Vector3) + Vector3(0, 0.5, 0)
		q.mesh_rotation_deg = quest_entry.get("rotation", Vector3.ZERO) as Vector3
	else:
		q.position = anchor + Vector3(2.0, 0.85, -2.0)
	_ensure_unique_loot_position(q)
	add_child(q)


## Belt-and-braces: the quest node never shares an exact position with a
## regular loot node (deterministic +Y nudges, capped).
func _ensure_unique_loot_position(q: Area3D) -> void:
	var guard := 0
	while guard < 64:
		var clash := false
		for n in get_tree().get_nodes_in_group("loot"):
			if n != q and n is Node3D and ((n as Node3D).position - q.position).length() < 0.01:
				clash = true
				break
		if not clash:
			return
		q.position += Vector3(0, 0.25, 0)
		guard += 1


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
		door.configure(dd, level_loader)
		# Lock high-security/vault/prison swinging doors on missions (never index 0 or Thieves' Den).
		if not _is_thieves_den and count > 0 and not door.locked:
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
	spawner_civilians = [
		{"body": "res://assets/ue/Content/Art/Animation/CivMale/Skin/Common/SK_CivMale_Common_01.glb", "head": "res://assets/ue/Content/Art/Animation/CivMale/Skin/Heads/SK_CivMale_Head_Adam_Fade01.glb"},
		{"body": "res://assets/ue/Content/Art/Animation/CivFemale/Skin/Common/SK_CivFemale_Common_01C.glb", "head": "res://assets/ue/Content/Art/Animation/CivFemale/Skin/Heads/SK_CivFemale_Head_Abby_Short01.glb"},
	]
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
	var civs: Array = []
	for ckey in (data as Dictionary).get("civilian_meshes", {}).keys():
		var c: Dictionary = (data as Dictionary)["civilian_meshes"][ckey]
		if str(c.get("body_res_path", "")) != "" and str(c.get("head_res_path", "")) != "":
			civs.append({"body": str(c["body_res_path"]), "head": str(c["head_res_path"])})
	if not civs.is_empty():
		spawner_civilians = civs


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
		c.position = (pos_var as Vector3) + Vector3(0.0, 0.5, 0.0)
		add_child(c)
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


func _on_extracted() -> void:
	GameState.state = "victory"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var final_score := int(round(GameState.loot_value * GameState.compute_stealth_bonus_multiplier()))
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
