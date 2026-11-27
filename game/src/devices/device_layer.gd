extends Node3D
## Authored runtime device layer.
##
## Loads game/data/generated/gameplay/devices_runtime.json once per process and
## spawns one node per authored device for the active map, in stable id order.
## The JSON is producer output (tools/parse_devices.py): 2,095 loaded-map
## devices, 6,005 detector->action edges and 1,475 device->power edges. Values
## come from each record's params merged over stats.family_defaults; only the
## documented runtime-only values (breakable health, cull radius, tick rate)
## are constants here.
##
## One _physics_process ticks every device at 10 Hz. Detectors, turrets and
## cameras are distance-culled at 60 m from the player and wake on proximity;
## supplies, wards and data-only markers stay resident but do no per-frame work.

signal layer_spawned(map_id: String, count: int)

const RUNTIME_PATH := "res://data/generated/gameplay/devices_runtime.json"
const Geometry := preload("res://src/devices/device_geometry.gd")
const BeamScript := preload("res://src/devices/security_beam.gd")
const PlateScript := preload("res://src/devices/pressure_plate.gd")
const NoiseAlarmScript := preload("res://src/devices/noise_alarm.gd")
const PowerSourceScript := preload("res://src/devices/power_source.gd")
const TurretScript := preload("res://src/devices/security_turret.gd")
const AlarmEyeScript := preload("res://src/devices/alarm_eye.gd")
const WardZoneScript := preload("res://src/devices/ward_zone.gd")

const TICK_HZ: float = 10.0
const TICK_STEP: float = 1.0 / TICK_HZ
const CULL_DISTANCE_M: float = 60.0
## Every authored family gets a node so the spawn census stays complete;
## families without a script below become deterministic data-only markers. The
## deferred list is recorded in the wave report and docs/HANDOFF.
const CULLED_FAMILIES: Array[String] = ["light_beam", "pressure_plate", "turret", "alarm_eye"]
const ACTION_FAMILIES: Array[String] = [
	"noise_alarm", "turret", "ward_slow", "ward_blocker", "vault_door",
	"goo_pipe", "magnetic_lock", "junction",
]

static var _doc_cache: Dictionary = {}
static var _doc_loaded: bool = false

var map_id: String = ""
var player: Node3D = null
var difficulty: int = -1
var devices: Dictionary = {}
var device_order: Array[String] = []
var family_counts: Dictionary = {}
var unresolved_power: Array[String] = []
var unresolved_actions: Array[String] = []
var spawn_count: int = 0
## Authored SM_LightBeam cards paired to their detector (one visual per beam).
var beam_cards_adopted: int = 0
## Authored SM_BlockerWard shard clusters paired to their ward (one visual per
## ward); shards stay at their authored transforms and follow ward state.
## `AddMeshesAlongVolume` spreads a cluster along the authored zone depth, so a
## component's origin can sit up to ~5.2 m from the actor origin (measured on
## Guildhall_Gameplay). Nearest-ward assignment with a 6 m cap covers every
## loaded shard; a shard is never shared by two wards.
const WARD_SHARD_PAIR_RADIUS_M: float = 6.0
var ward_shards_total: int = 0
var ward_shards_adopted: int = 0

var _accum: float = 0.0
var _tick_enabled: bool = true
var _record_by_id: Dictionary = {}


static func runtime_document() -> Dictionary:
	if _doc_loaded:
		return _doc_cache
	_doc_loaded = true
	if not FileAccess.file_exists(RUNTIME_PATH):
		push_error("[device_layer] missing ", RUNTIME_PATH)
		return {}
	var f: FileAccess = FileAccess.open(RUNTIME_PATH, FileAccess.READ)
	if f == null:
		push_error("[device_layer] could not open ", RUNTIME_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		push_error("[device_layer] ", RUNTIME_PATH, " is not a JSON object")
		return {}
	_doc_cache = parsed as Dictionary
	return _doc_cache


func _ready() -> void:
	# The layer ticks in one place; individual device scripts have no process
	# callbacks. Mission spawns it after the swinging doors and before the
	# loading screen closes.
	set_physics_process(true)


## Spawn the active map's authored devices. Returns the record count. Safe to
## call on a layer that is already inside the tree; tests also call it on a
## free-standing layer for deterministic census checks.
func spawn_for_map(map_id_value: String, player_value: Node3D = null, difficulty_value: int = -1) -> int:
	if not device_order.is_empty():
		clear_spawned()
	_accum = 0.0
	map_id = map_id_value
	player = player_value
	difficulty = difficulty_value if difficulty_value >= 0 else int(GameState.difficulty)
	var doc: Dictionary = runtime_document()
	if doc.is_empty():
		return 0
	var maps_v: Variant = doc.get("maps", {})
	if not (maps_v is Dictionary):
		return 0
	var maps: Dictionary = maps_v as Dictionary
	var map_v: Variant = maps.get(map_id, null)
	if not (map_v is Dictionary):
		push_warning("[device_layer] no authored devices for map '", map_id, "'")
		return 0
	var map_data: Dictionary = map_v as Dictionary
	var records_v: Variant = map_data.get("devices", [])
	if not (records_v is Array):
		return 0
	var records: Array = (records_v as Array).duplicate()
	records.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ai: String = str((a as Dictionary).get("id", "")) if a is Dictionary else ""
		var bi: String = str((b as Dictionary).get("id", "")) if b is Dictionary else ""
		return ai < bi
	)
	var defaults_v: Variant = (doc.get("stats", {}) as Dictionary).get("family_defaults", {})
	var family_defaults: Dictionary = defaults_v as Dictionary if defaults_v is Dictionary else {}
	var index: int = 0
	for rec_v: Variant in records:
		if not (rec_v is Dictionary):
			continue
		var rec: Dictionary = rec_v as Dictionary
		var id: String = str(rec.get("id", ""))
		if id.is_empty() or devices.has(id):
			push_warning("[device_layer] duplicate/empty device id '", id, "'")
			continue
		var node: Node3D = _make_device(rec, family_defaults)
		node.name = "Dev_%04d" % index
		node.set_meta("device_id", id)
		node.set_meta("device_family", str(rec.get("family", "")))
		node.transform = Geometry.transform_from_record(rec)
		add_child(node)
		devices[id] = node
		device_order.append(id)
		_record_by_id[id] = rec
		var family: String = str(rec.get("family", ""))
		family_counts[family] = int(family_counts.get(family, 0)) + 1
		index += 1
	spawn_count = device_order.size()
	_resolve_graph()
	_adopt_beam_cards()
	_adopt_ward_shards()
	_apply_player()
	_update_awake(false)
	layer_spawned.emit(map_id, spawn_count)
	return spawn_count


## Drop a previous pass (the layer is safe to re-spawn on the same instance).
func clear_spawned() -> void:
	for id: String in device_order:
		var node: Node = devices.get(id) as Node
		if node != null and is_instance_valid(node):
			if node.has_method("release_beam_card"):
				node.call("release_beam_card")
			if node.has_method("release_ward_shards"):
				node.call("release_ward_shards")
			node.free()
	devices.clear()
	device_order.clear()
	family_counts.clear()
	_record_by_id.clear()
	beam_cards_adopted = 0
	ward_shards_total = 0
	ward_shards_adopted = 0
	spawn_count = 0


func _make_device(rec: Dictionary, family_defaults: Dictionary) -> Node3D:
	var family: String = str(rec.get("family", ""))
	var script: GDScript = null
	var node: Node3D = null
	match family:
		"light_beam":
			script = BeamScript
		"pressure_plate":
			script = PlateScript
		"noise_alarm":
			script = NoiseAlarmScript
		"power_wall", "power_switch":
			script = PowerSourceScript
		"turret":
			script = TurretScript
		"alarm_eye":
			script = AlarmEyeScript
		"ward_slow", "ward_blocker":
			script = WardZoneScript
		_:
			script = null
	if script != null:
		node = script.new() as Node3D
		node.call("configure", rec, family_defaults, difficulty)
	else:
		# Deferred family: keep the authored record visible in the census
		# without inventing behaviour. The producer data stays authoritative.
		node = Node3D.new()
		node.set_meta("device_deferred", true)
	if node != null:
		if not node.is_in_group("devices"):
			node.add_to_group("devices")
		if ACTION_FAMILIES.has(family) and not node.is_in_group("device_action"):
			node.add_to_group("device_action")
	return node


func _resolve_graph() -> void:
	unresolved_power.clear()
	unresolved_actions.clear()
	for id: String in device_order:
		var node: Node = devices.get(id) as Node
		var rec: Dictionary = _record_by_id.get(id, {}) as Dictionary
		var actions_v: Variant = rec.get("actions", [])
		var actions: Array = actions_v as Array if actions_v is Array else []
		var targets: Array = []
		for action_v: Variant in actions:
			var action_id: String = str(action_v)
			if devices.has(action_id):
				targets.append(devices[action_id])
			else:
				unresolved_actions.append(action_id)
				push_warning("[device_layer] ", id, ": unresolved action target '", action_id, "'")
		if node.has_method("set_action_targets"):
			node.call("set_action_targets", targets)
		var power_v: Variant = rec.get("power", {})
		var power: Dictionary = power_v as Dictionary if power_v is Dictionary else {}
		var source_id: String = str(power.get("source", "")) if power.get("source", null) != null else ""
		if not source_id.is_empty():
			if devices.has(source_id):
				var source: Node = devices[source_id] as Node
				if node.has_method("set_power_source"):
					node.call("set_power_source", source)
				if source != null:
					node.set_meta("power_source_id", source_id)
					if not source.has_meta("device_consumers"):
						source.set_meta("device_consumers", [])
					var consumers: Array = source.get_meta("device_consumers") as Array
					consumers.append(node)
					source.set_meta("device_consumers", consumers)
			else:
				unresolved_power.append(source_id)
				push_warning("[device_layer] ", id, ": unresolved power source '", source_id, "'")


func _apply_player() -> void:
	for id: String in device_order:
		var node: Node = devices.get(id) as Node
		if node != null and node.has_method("set_player"):
			node.call("set_player", player)


## Pair each light-beam detector with the loader's authored SM_LightBeam card
## at the same authored position (both records carry the same pos). The card
## becomes the detector's only visual; a detector without one keeps the cheap
## stand-in cylinder. Positions are exact (same record), so 0.02 m is a safe
## pairing radius and a card is never shared by two detectors.
func _adopt_beam_cards() -> void:
	beam_cards_adopted = 0
	if not is_inside_tree():
		return
	var cards: Array = get_tree().get_nodes_in_group("lightbeam_cards")
	if cards.is_empty():
		return
	var used: Dictionary = {}
	for id: String in device_order:
		var node: Node = devices.get(id) as Node
		if node == null or not node.has_method("adopt_beam_card"):
			continue
		var best: Node3D = null
		var best_d: float = 0.02
		for c_var: Variant in cards:
			if not (c_var is Node3D):
				continue
			var card: Node3D = c_var as Node3D
			if used.has(card) or not card.is_inside_tree():
				continue
			var d: float = card.global_position.distance_to(node.global_position)
			if d <= best_d:
				best_d = d
				best = card
		if best != null:
			node.call("adopt_beam_card", best)
			used[best] = true
			beam_cards_adopted += 1


## Pair each authored `SM_BlockerWard_*` shard cluster with its nearest ward
## blocker. The cluster is the BP's seven StaticMeshComponents, but
## `AddMeshesAlongVolume` spreads them along the authored zone depth, so a
## component can be up to ~5.2 m from the actor origin (measured on the loaded
## Guildhall_Gameplay). Nearest-device assignment with a 6 m cap therefore
## covers every loaded shard and keeps a shard from being adopted twice when
## two wards sit close together. Slow wards keep the authored translucent glyph
## quad and take no shards.
func _adopt_ward_shards() -> void:
	ward_shards_total = 0
	ward_shards_adopted = 0
	if not is_inside_tree():
		return
	var shards: Array = get_tree().get_nodes_in_group("ward_shards")
	if shards.is_empty():
		return
	var ward_nodes: Array[Node3D] = []
	for id: String in device_order:
		var node: Node = devices.get(id) as Node
		if node == null or not (node is Node3D) or not node.has_method("adopt_ward_shards"):
			continue
		if str(node.get("mode")) != "blocker":
			continue
		ward_nodes.append(node as Node3D)
	if ward_nodes.is_empty():
		return
	var per_ward: Dictionary = {}
	for s_var: Variant in shards:
		if not (s_var is Node3D):
			continue
		var shard: Node3D = s_var as Node3D
		if not shard.is_inside_tree():
			continue
		var best: Node3D = null
		var best_d: float = WARD_SHARD_PAIR_RADIUS_M
		for ward: Node3D in ward_nodes:
			var d: float = shard.global_position.distance_to(ward.global_position)
			if d <= best_d:
				best_d = d
				best = ward
		if best != null:
			if not per_ward.has(best):
				per_ward[best] = []
			(per_ward[best] as Array).append(shard)
			ward_shards_total += 1
	for ward_v: Variant in per_ward.keys():
		var ward: Node = ward_v as Node
		ward.call("adopt_ward_shards", per_ward[ward_v] as Array)
		ward_shards_adopted += (per_ward[ward_v] as Array).size()


func _physics_process(delta: float) -> void:
	if not _tick_enabled:
		return
	_accum += delta
	if _accum + 0.000001 < TICK_STEP:
		return
	var step: float = _accum
	_accum = 0.0
	tick_devices(step)


## One deterministic 10 Hz pass. Public so the suite can step the layer without
## waiting on real physics time.
func tick_devices(delta: float) -> void:
	_update_awake(false)
	for id: String in device_order:
		var node: Node = devices.get(id) as Node
		if node != null and node.has_method("tick"):
			node.call("tick", delta)


func set_tick_enabled(enabled: bool) -> void:
	_tick_enabled = enabled
	set_physics_process(enabled)


func _update_awake(force: bool) -> void:
	var target: Node3D = player
	if target == null or not is_instance_valid(target):
		if is_inside_tree():
			var found: Node = get_tree().get_first_node_in_group("player")
			if found is Node3D:
				target = found as Node3D
				player = target
	var player_pos: Vector3 = target.global_position if target != null and is_instance_valid(target) else Vector3.ZERO
	var have_player: bool = target != null and is_instance_valid(target)
	for id: String in device_order:
		var node: Node = devices.get(id) as Node
		if node == null or not node.has_method("set_awake"):
			continue
		var family: String = str(node.get_meta("device_family", ""))
		var awake: bool = true
		if have_player and CULLED_FAMILIES.has(family):
			awake = (node as Node3D).global_position.distance_to(player_pos) <= CULL_DISTANCE_M
		elif force:
			awake = true
		node.call("set_awake", awake)


func get_device(id: String) -> Node:
	return devices.get(id) as Node


func family_count(family: String) -> int:
	return int(family_counts.get(family, 0))


func deferred_families() -> Array[String]:
	var out: Array[String] = []
	for id: String in device_order:
		var node: Node = devices.get(id) as Node
		if node != null and node.get_meta("device_deferred", false) == true:
			var family: String = str(node.get_meta("device_family", ""))
			if not out.has(family):
				out.append(family)
	return out
