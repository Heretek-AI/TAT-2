extends Node3D
## Mission & Contract runner: loads the FULL extracted UE5 sublevels
## (OldManor_Geo/Gameplay/Loot, Guildhall_POI/Geometry/Periphery/Gameplay/Loot,
## ThievesDen_Geo, or FTUE_Geometry for Jaspering Hall expansion),
## spawns real Guard & Thief models, loot spawners, lights, and escape gates.

const ThiefScript := preload("res://src/player/thief_character.gd")
const GuardScript := preload("res://src/ai/guard_ai.gd")
const LootScript := preload("res://src/interact/loot_item.gd")
const DoorScript := preload("res://src/interact/lockable_door.gd")
const EscapeScript := preload("res://src/interact/escape_gate.gd")
const LightProbeScript := preload("res://src/stealth/light_probe.gd")
const LevelLoaderScript := preload("res://src/core/level_loader.gd")
const MobileProfile := preload("res://src/core/mobile_profile.gd")
const WeatherProfile := preload("res://src/core/weather_profile.gd")
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
var contract_info: Dictionary = {}
var level_stats: Dictionary = {}


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
	WeatherProfile.apply_for_map(e, moon, GameState.active_map_id)
	MobileProfile.apply_environment(e)
	env.environment = e
	add_child(env)

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
	GameState.reset_run(order, map_id)

	var loading: Node = LoadingScreenScript.new()
	add_child(loading)
	if loading.has_method("start_loading"):
		loading.call("start_loading", str(contract_info.get("title", "Contract")), str(contract_info.get("clue", "")), map_id)

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
	if int(ue_level_data.get("chunk_count", 0)) > 0:
		print("TAT-2 Perf: chunks=", ue_level_data.get("chunk_count", 0), " collision_bodies=", ue_level_data.get("collision_bodies", 0), " collision_shapes=", ue_level_data.get("collision_shapes", 0), " occluders=", ue_level_data.get("occluder_count", 0))

	# Safety floor plane far below map so player never falls into void if stepping outside bounds
	_add_safety_floor()

	_setup_thieves_den_env(map_id)

	_spawn_player(ue_level_data.get("player_spawns", []))
	if player != null and hud != null:
		if player.has_signal("thief_vision_toggled") and hud.has_method("set_thief_vision"):
			player.thief_vision_toggled.connect(hud.set_thief_vision)

	var anchor: Vector3 = player.global_position if player != null else Vector3.ZERO
	if map_id == "thieves_den":
		_setup_thieves_den_hub(anchor, ue_level_data)
	else:
		_spawn_guards(ue_level_data.get("guard_spawns", []), anchor)
		_spawn_loot_and_quest(ue_level_data.get("loot_spawns", []), anchor)
		_spawn_clues(ue_level_data.get("loot_spawns", []), anchor)
		_spawn_escape(ue_level_data.get("escape_points", []), anchor)

	if hud.has_method("set_contract_info"):
		hud.set_contract_info(contract_info)

	if is_instance_valid(loading) and loading.has_method("finish_loading"):
		loading.call("finish_loading")


func _setup_thieves_den_env(map_id: String) -> void:
	if map_id != "thieves_den":
		return
	for child in get_children():
		if child is WorldEnvironment:
			var wenv: WorldEnvironment = child as WorldEnvironment
			if wenv.environment != null:
				wenv.environment.ambient_light_energy = 0.18
				wenv.environment.background_color = Color(0.012, 0.016, 0.032)


func _map_id_to_sublevels(map_id: String, order: int = 2) -> Array[String]:
	match map_id:
		"old_manor":
			return [
				"res://data/generated/levels/OldManor/OldManor_Geo.tatlevel.json",
				"res://data/generated/levels/OldManor/OldManor_Landscape.tatlevel.json",
				"res://data/generated/levels/OldManor/OldManor_Gameplay.tatlevel.json",
				"res://data/generated/levels/OldManor/OldManor_Loot.tatlevel.json",
				"res://data/generated/levels/OldManor/OldManor_PickUps.tatlevel.json",
				"res://data/generated/levels/OldManor/OldManor_Clues.tatlevel.json",
				"res://data/generated/levels/OldManor/OldManor_Contract%02d.tatlevel.json" % order,
				"res://data/generated/levels/OldManor/OldManor_SkyboxGeo.tatlevel.json",
			]
		"guildhall":
			return [
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
				"res://data/generated/levels/Guildhall/Guildhall_Contract_%02d.tatlevel.json" % order,
				"res://data/generated/levels/Guildhall/Guildhall_SkyboxGeo.tatlevel.json",
			]
		"thieves_den":
			return [
				"res://data/generated/levels/ThievesDen/ThievesDen_Geo.tatlevel.json",
				"res://data/generated/levels/ThievesDenTest/ThievesDenTest_P.tatlevel.json",
				"res://data/generated/levels/ThievesDenTest/ThievesDenTest_Periphery.tatlevel.json",
			]
		"jaspering_hall":
			return [
				"res://data/generated/levels/FTUE/FTUE_Geometry.tatlevel.json",
				"res://data/generated/levels/FTUE/FTUE_Building_JewelryStore.tatlevel.json",
				"res://data/generated/levels/FTUE/FTUE_Building_SpawnArea.tatlevel.json",
				"res://data/generated/levels/FTUE/FTUE_Gameplay.tatlevel.json",
			]
	return []


func _setup_thieves_den_hub(anchor: Vector3, ue_level_data: Dictionary = {}) -> void:
	# Cozy warm attic fill + cool window moonlight bounce so the Thieves' Den matches the official mood
	var attic_fill := OmniLight3D.new()
	attic_fill.position = anchor + Vector3(1.5, 2.6, -1.5)
	attic_fill.light_color = Color(1.0, 0.74, 0.42)
	attic_fill.light_energy = 1.4
	attic_fill.omni_range = 13.0
	attic_fill.omni_attenuation = 0.85
	add_child(attic_fill)
	light_probe.register_light(attic_fill)

	# Big arched window moonlight shaft (west wall, pouring diagonally onto the attic floor)
	var win_pos: Vector3 = Vector3(-5.8, 43.0, 271.5)
	var moon_beam := SpotLight3D.new()
	moon_beam.position = win_pos
	moon_beam.light_color = Color(0.55, 0.82, 0.96)
	moon_beam.light_energy = 1.8
	moon_beam.spot_range = 14.0
	moon_beam.spot_angle = 26.0
	moon_beam.shadow_enabled = true
	add_child(moon_beam)
	var beam_target: Vector3 = Vector3(-0.5, 40.1, 271.5)
	moon_beam.look_at(beam_target, Vector3.UP)
	light_probe.register_light(moon_beam)
	VfxManager.spawn_window_godray(self, win_pos, beam_target)

	var desk_positions: Array = ue_level_data.get("desk_positions", [])
	var desk_pos: Vector3 = anchor + Vector3(3.2, 0.8, -2.5)
	if not desk_positions.is_empty() and desk_positions[0] is Vector3:
		desk_pos = desk_positions[0] + Vector3(0.0, 0.75, 0.0)
	VfxManager.spawn_candle_flame(self, desk_pos + Vector3(0.35, 0.45, 0.0))

	# Warm table pool light
	var table_light := OmniLight3D.new()
	table_light.position = desk_pos + Vector3(0.0, 1.1, 0.0)
	table_light.light_color = Color(1.0, 0.76, 0.42)
	table_light.light_energy = 1.6
	table_light.omni_range = 6.5
	add_child(table_light)
	light_probe.register_light(table_light)

	# Interactive Map Table -> opens ContractTableUI (all 18 contracts + Co-op + Deploy)
	var desk_area := Area3D.new()
	desk_area.position = desk_pos
	desk_area.add_to_group("interactables")
	var dcol := CollisionShape3D.new()
	var dsph := SphereShape3D.new()
	dsph.radius = 2.2
	dcol.shape = dsph
	desk_area.add_child(dcol)
	var dlbl := Label3D.new()
	dlbl.position = Vector3(0, 1.0, 0)
	dlbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dlbl.text = "[F] Map Table — Prepare for Mission"
	dlbl.font_size = 24
	dlbl.modulate = Color(1.0, 0.85, 0.45)
	desk_area.add_child(dlbl)
	var desk_script := GDScript.new()
	desk_script.source_code = """extends Area3D
var mission_ctrl: Node = null
func get_interact_prompt() -> String:
\treturn "[F] Prepare for Mission (Map Table)"
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
	var ledger_pos: Vector3 = anchor + Vector3(3.4, 0.95, 1.8)
	if not ledger_positions.is_empty() and ledger_positions[0] is Vector3:
		ledger_pos = (ledger_positions[0] as Vector3) + Vector3(0.0, 0.12, 0.0)
	VfxManager.spawn_blue_wisp(self, ledger_pos + Vector3(-0.35, 0.42, -0.15))
	var ledger_area := Area3D.new()
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

	# Trunk Decoration Pedestal + Gramophone
	_spawn_thieves_den_props(anchor)

	# Interactive Bureau / Wardrobe -> opens WardrobeUI (Thief + Outfit + Headgear + Calling Card)
	var wardrobe_positions: Array = ue_level_data.get("wardrobe_positions", [])
	var wardrobe_pos: Vector3 = anchor + Vector3(-2.6, 0.9, -2.0)
	if not wardrobe_positions.is_empty() and wardrobe_positions[0] is Vector3:
		wardrobe_pos = wardrobe_positions[0] + Vector3(0.0, 0.8, 0.0)
	var ward_light := OmniLight3D.new()
	ward_light.position = wardrobe_pos + Vector3(0.0, 1.1, 0.4)
	ward_light.light_color = Color(1.0, 0.8, 0.5)
	ward_light.light_energy = 1.4
	ward_light.omni_range = 5.5
	add_child(ward_light)
	light_probe.register_light(ward_light)

	var ward_area := Area3D.new()
	ward_area.position = wardrobe_pos
	ward_area.add_to_group("interactables")
	var wcol := CollisionShape3D.new()
	var wsph := SphereShape3D.new()
	wsph.radius = 2.2
	wcol.shape = wsph
	ward_area.add_child(wcol)
	var wlbl := Label3D.new()
	wlbl.position = Vector3(0, 1.1, 0)
	wlbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	wlbl.text = "[F] Bureau — Customize Thief"
	wlbl.font_size = 24
	wlbl.modulate = Color(0.75, 0.9, 1.0)
	ward_area.add_child(wlbl)
	var ward_script := GDScript.new()
	ward_script.source_code = """extends Area3D
var mission_ctrl: Node = null
func get_interact_prompt() -> String:
\treturn "[F] Customize Thief (Bureau)"
func interact(_actor: Node) -> void:
\tif mission_ctrl != null and mission_ctrl.has_method("open_wardrobe_ui"):
\t\tmission_ctrl.open_wardrobe_ui()
"""
	ward_script.reload()
	ward_area.set_script(ward_script)
	ward_area.set("mission_ctrl", self)
	add_child(ward_area)


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
	var miniatures: Array[Dictionary] = [
		{"path": "res://assets/ue/Content/Art/UI/Map/SM_MapBuilding_OldManor.glb", "offset": Vector3(-0.32, 0.16, -0.08), "scale": 0.08},
		{"path": "res://assets/ue/Content/Art/UI/Map/SM_MapBuilding_GuildHall.glb", "offset": Vector3(0.28, 0.16, 0.10), "scale": 0.08},
	]
	for item: Dictionary in miniatures:
		var mpath: String = str(item["path"])
		if ResourceLoader.exists(mpath):
			var packed: PackedScene = load(mpath) as PackedScene
			if packed != null:
				var inst: Node3D = packed.instantiate() as Node3D
				if inst != null:
					inst.position = desk_pos + (item["offset"] as Vector3)
					var s: float = float(item["scale"])
					inst.scale = Vector3(s, s, s)
					add_child(inst)


func _spawn_thieves_den_props(anchor: Vector3) -> void:
	# Trunk Decoration Pedestal -> [F] CHANGE DECORATION
	var deco_pos: Vector3 = anchor + Vector3(-1.8, 0.9, 1.4)
	var deco_area := Area3D.new()
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
\tvar mesh_path: String = ""
\tif key == "faberge_egg":
\t\tmesh_path = "res://assets/ue/Content/Art/Environment/Props/SM_FabergeEggA.glb"
\telif key == "owl_statue":
\t\tmesh_path = "res://assets/ue/Content/Art/Environment/Props/SM_StatueOwlA.glb"
\tif mesh_path != "" and ResourceLoader.exists(mesh_path):
\t\tvar p: PackedScene = load(mesh_path) as PackedScene
\t\tif p != null:
\t\t\tvar inst: Node3D = p.instantiate() as Node3D
\t\t\tif inst != null:
\t\t\t\tinst.scale = Vector3(0.35, 0.35, 0.35)
\t\t\t\tvis.add_child(inst)
\t\t\t\treturn
\tvar mi := MeshInstance3D.new()
\tvar sm := SphereMesh.new()
\tsm.radius = 0.14
\tsm.height = 0.24 if key == "faberge_egg" else 0.22
\tvar mat := StandardMaterial3D.new()
\tif key == "emerald":
\t\tmat.albedo_color = Color(0.15, 0.9, 0.45)
\t\tmat.emission_enabled = true
\t\tmat.emission = Color(0.1, 0.85, 0.4)
\telif key == "owl_statue":
\t\tmat.albedo_color = Color(0.9, 0.72, 0.25)
\t\tmat.metallic = 0.85
\telse:
\t\tmat.albedo_color = Color(0.45, 0.22, 0.72)
\t\tmat.metallic = 0.5
\tsm.material = mat
\tmi.mesh = sm
\tvis.add_child(mi)
"""
	deco_script.reload()
	deco_area.set_script(deco_script)
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
\tif AudioManager != null and AudioManager.has_method("play_sfx"):
\t\tAudioManager.play_sfx("res://assets/ue/audio/chime.wav", global_position)
"""
	gram_script.reload()
	gram_area.set_script(gram_script)
	add_child(gram_area)


func open_contract_table_ui() -> void:
	var ui: CanvasLayer = ContractTableUIScript.new()
	add_child(ui)
	if ui.has_signal("deploy_requested"):
		ui.connect("deploy_requested", func(order_id: int, map_id: String) -> void:
			GameState.reset_run(order_id, map_id)
			get_tree().reload_current_scene()
		)
	if ui.has_method("open_table"):
		ui.call("open_table")


func _spawn_clues(ue_spawns: Array, anchor: Vector3) -> void:
	var clue_title: String = str(contract_info.get("title", "Contract Clue"))
	var clue_body: String = str(contract_info.get("clue", "Locate the target vault and watch the Constabulary patrol timing."))
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


func _spawn_player(ue_spawns: Array) -> void:
	player = ThiefScript.new()
	player.light_probe = light_probe
	player.level_ctrl = self
	var spawn: Vector3 = Vector3(0, 2.0, 0)
	if not ue_spawns.is_empty():
		var chosen: Variant = ue_spawns[0]
		var w3d: World3D = get_world_3d()
		if w3d != null:
			var phys: PhysicsDirectSpaceState3D = w3d.direct_space_state
			for cand: Variant in ue_spawns:
				if cand is Vector3:
					var cp: Vector3 = cand as Vector3
					var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(cp + Vector3(0, 1.0, 0), cp + Vector3(0, -6.0, 0), 1)
					var hit: Dictionary = phys.intersect_ray(q)
					if not hit.is_empty():
						chosen = cand
						break
		if chosen is Vector3:
			spawn = (chosen as Vector3) + Vector3(0, 1.0, 0)
	else:
		spawn = _find_mesh_fallback_spawn()
	player.position = spawn
	player.downed.connect(_on_player_downed)
	add_child(player)
	_snap_player_to_ground()


func _find_mesh_fallback_spawn() -> Vector3:
	var found: Node = _find_first_level_mesh(self)
	if found is MeshInstance3D:
		var mi: MeshInstance3D = found as MeshInstance3D
		return mi.global_position + Vector3(0, 2.0, 0)
	if found is MultiMeshInstance3D:
		var mmi: MultiMeshInstance3D = found as MultiMeshInstance3D
		return mmi.global_position + Vector3(0, 2.0, 0)
	return Vector3(0, 2.0, 0)


func _find_first_level_mesh(n: Node) -> Node:
	for child in n.get_children():
		if child is MeshInstance3D or child is MultiMeshInstance3D:
			return child
		if child == player or child == hud or child == light_probe or child == level_loader:
			continue
		var deep: Node = _find_first_level_mesh(child)
		if deep != null:
			return deep
	return null


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


func _spawn_guards(ue_spawns: Array, anchor: Vector3) -> void:
	var limit := 6 + (2 if GameState.difficulty == GameState.Difficulty.MASTER_THIEF else 0)
	var chosen: Array[Vector3] = []
	for p in ue_spawns:
		if p is Vector3 and p.distance_to(anchor) > 10.0 and p.distance_to(anchor) < 120.0:
			chosen.append(p)
			if chosen.size() >= limit:
				break
	if chosen.is_empty():
		chosen = [anchor + Vector3(12, 0, 0), anchor + Vector3(-12, 0, -10), anchor + Vector3(0, 0, -18), anchor + Vector3(16, 0, -16)]

	for pos in chosen:
		var g := GuardScript.new()
		g.level_ctrl = self
		var pts: Array[Vector3] = [pos, pos + Vector3(6, 0, 0), pos + Vector3(6, 0, 6), pos + Vector3(0, 0, 6)]
		g.patrol_points = pts
		g.position = pos + Vector3(0, 0.5, 0)
		add_child(g)


func _spawn_loot_and_quest(ue_spawns: Array, anchor: Vector3) -> void:
	var nearby: Array[Vector3] = []
	for p in ue_spawns:
		if p is Vector3 and p.distance_to(anchor) < 120.0:
			nearby.append(p)
	if nearby.is_empty():
		nearby = [
			anchor + Vector3(4, 0.8, -6), anchor + Vector3(-6, 0.8, -8),
			anchor + Vector3(10, 0.8, -14), anchor + Vector3(-10, 0.8, -16),
			anchor + Vector3(0, 0.8, -22), anchor + Vector3(8, 0.8, 4),
		]

	var q := LootScript.new()
	q.item_name = str(contract_info.get("quest_item", "Contract Objective"))
	q.is_quest_item = true
	q.loot_tier = "quest"
	var quest_tag: String = str(contract_info.get("loot_tag", ""))
	q.value = LootScript.quest_value_for_tag(quest_tag)
	q.position = nearby[mini(nearby.size() - 1, 4)] + Vector3(0, 0.5, 0)
	add_child(q)

	var count := mini(12, nearby.size())
	for i in range(count):
		# Every 4th spawn is a major piece; the rest cycle the real minor
		# table (names + values straight from DT_LootInfo_Minor/Major).
		var tier: String = "major" if i % 4 == 3 else "minor"
		var entry: Dictionary = LootScript.tier_entry(tier, i / 4 if tier == "major" else i)
		var l := LootScript.new()
		l.loot_tier = tier
		l.item_name = str(entry.get("name", "Noble Relic #%d" % (i + 1)))
		l.value = int(entry.get("value", 75))
		l.position = nearby[i] + Vector3(0, 0.5, 0)
		add_child(l)


func _spawn_escape(ue_escapes: Array, anchor: Vector3) -> void:
	var eg := EscapeScript.new()
	var epos := anchor + Vector3(0, 0.2, 6)
	if not ue_escapes.is_empty():
		epos = ue_escapes[0]
	eg.apply_escape_config(EscapeScript.escape_config())
	eg.position = epos
	eg.extracted.connect(_on_extracted)
	add_child(eg)


func spawn_smoke(pos: Vector3, radius: float, ttl: float) -> void:
	VfxManager.spawn_smoke_cloud(self, pos + Vector3.UP * 1.0, radius, ttl)
	smokes.append({"pos": pos, "radius": radius, "ttl": ttl, "node": null})


func is_blocked_by_smoke(a: Vector3, b: Vector3) -> bool:
	for s in smokes:
		var c: Vector3 = s["pos"]
		var r: float = s["radius"]
		var ab := b - a
		var len_sq := ab.length_squared()
		if len_sq < 0.001:
			continue
		var t := clampf((c - a).dot(ab) / len_sq, 0.0, 1.0)
		var closest := a + ab * t
		if closest.distance_to(c) <= r:
			return true
	return false


func _process(delta: float) -> void:
	if GameState.state == "playing":
		GameState.elapsed_sec += delta
		light_probe.tick(GameState.elapsed_sec)
		for i in range(smokes.size() - 1, -1, -1):
			smokes[i]["ttl"] -= delta
			if smokes[i]["ttl"] <= 0.0:
				var n: Node = smokes[i]["node"]
				if is_instance_valid(n):
					n.queue_free()
				smokes.remove_at(i)


func _on_extracted() -> void:
	GameState.state = "victory"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var final_score := int(round(GameState.loot_value * GameState.compute_stealth_bonus_multiplier()))
	SaveSystem.add_currency(final_score)
	SaveSystem.record_contract_complete(GameState.active_contract_order, final_score, not GameState.ever_spotted)
	if hud.has_method("show_result"):
		hud.show_result(true, final_score, contract_info)


func _on_player_downed() -> void:
	GameState.state = "failed"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hud.has_method("show_result"):
		hud.show_result(false, GameState.loot_value, contract_info)
