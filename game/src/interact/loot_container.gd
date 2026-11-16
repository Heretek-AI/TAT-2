extends Area3D
## Openable placed loot container (chest / display case / secret stash).
##
## One node is spawned per UE container marker by mission_controller. The
## container MESH is level geometry (spawned by the level loader) and is never
## duplicated here: this node is an Area3D trigger only, with no mesh children
## and no per-frame work.
##
## Opening is one-shot and instant (no Interact duration is authored on the
## container Blueprints). Major/minor containers spawn exactly one loot item
## from their mapped bucket, picked deterministically from the marker
## position; the secret stash (kind "none", no spawn bucket) opens with no
## loot — its loot arrives as separately placed actors.

const LootScript := preload("res://src/interact/loot_item.gd")

const CONTAINERS_PATH := "res://data/generated/gameplay/containers.json"
const LOOT_ACTORS_PATH := "res://data/generated/gameplay/loot_actors.json"

## Raw UE centimetres -> Godot metres (UE X-fwd/Y-right/Z-up becomes
## Godot X-right/Y-up/Z-back: the same Y/Z swap the level extractor applies).
const CM_TO_M := 0.01

static var _containers: Dictionary = {}
static var _loot_tables: Dictionary = {}


static func containers() -> Dictionary:
	if _containers.is_empty():
		if FileAccess.file_exists(CONTAINERS_PATH):
			var f: FileAccess = FileAccess.open(CONTAINERS_PATH, FileAccess.READ)
			if f != null:
				var data: Variant = JSON.parse_string(f.get_as_text())
				if data is Dictionary:
					_containers = (data as Dictionary).get("classes", {})
	return _containers


static func loot_tables() -> Dictionary:
	if _loot_tables.is_empty():
		if FileAccess.file_exists(LOOT_ACTORS_PATH):
			var f: FileAccess = FileAccess.open(LOOT_ACTORS_PATH, FileAccess.READ)
			if f != null:
				var data: Variant = JSON.parse_string(f.get_as_text())
				if data is Dictionary:
					_loot_tables = {
						"buckets": (data as Dictionary).get("buckets", {}),
						"actors": (data as Dictionary).get("actors", {}),
					}
	return _loot_tables


## Deterministic weighted pick from a bucket class list (duplicates carry the
## designer weight): pure function of marker position + order, no RNG. Same
## formula as mission_controller._loot_bucket_index so both waves agree.
static func bucket_index(pos: Vector3, order: int, size: int) -> int:
	if size <= 0:
		return 0
	var h: float = absf(pos.x * 12.9898 + pos.y * 78.233 + pos.z * 37.719 + float(order) * 0.731)
	return posmod(int(h), size)


## Raw UE slot offset (cm, X-fwd/Y-right/Z-up) -> Godot metres (Y/Z swapped,
## like the level extractor).
static func ue_offset_to_godot(offset_cm: Vector3) -> Vector3:
	return Vector3(offset_cm.x * CM_TO_M, offset_cm.z * CM_TO_M, offset_cm.y * CM_TO_M)


## Slot FRotator (degrees, UE frame: Pitch about Y, Yaw about Z, Roll about X)
## combined with the marker orientation -> Godot euler degrees for the loot
## visual. The UE rotation is conjugated by the extractor's Y/Z swap (P) into
## Godot space, then composed with the marker basis.
static func slot_world_rotation(marker: Basis, pitch: float, yaw: float, roll: float) -> Vector3:
	var b_ue: Basis = Basis(Vector3(0, 0, 1), deg_to_rad(yaw)) * Basis(Vector3(0, 1, 0), deg_to_rad(pitch)) * Basis(Vector3(1, 0, 0), deg_to_rad(roll))
	var swap := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))
	var b_godot: Basis = swap * b_ue * swap
	var e: Vector3 = (marker * b_godot).get_euler()
	return Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z))


## Marker transform for the Area: position + orientation only. Marker scale is
## recorded on the entry but never applied to the trigger (it would distort
## the interaction sphere).
static func marker_transform(entry: Dictionary) -> Transform3D:
	var pos: Vector3 = entry.get("pos", Vector3.ZERO)
	var b: Array = entry.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1])
	var basis := Basis.IDENTITY
	if b.size() >= 9:
		basis = Basis(
			Vector3(float(b[0]), float(b[3]), float(b[6])),
			Vector3(float(b[1]), float(b[4]), float(b[7])),
			Vector3(float(b[2]), float(b[5]), float(b[8]))
		).orthonormalized()
	return Transform3D(basis, pos)


var container_class: String = ""
var loot_tier: String = ""
var marker_pos: Vector3 = Vector3.ZERO
var marker_basis: Basis = Basis.IDENTITY
var slot_offset_cm: Vector3 = Vector3.ZERO
var slot_rotation_deg: Vector3 = Vector3.ZERO
var spawn_index: int = 0
var opened: bool = false


## Must be called before add_child (like world_pickup.setup). Resolves the
## loot tier and first slot entry from containers.json; unknown classes and
## unreadable JSON fail closed to kind "none" (openable, no loot, nothing
## invented).
func configure(p_class: String, entry: Dictionary, p_index: int) -> void:
	container_class = p_class
	spawn_index = p_index
	marker_pos = entry.get("pos", Vector3.ZERO)
	var tr := marker_transform(entry)
	marker_basis = tr.basis
	transform = tr
	var rec: Variant = containers().get(p_class, null)
	if rec is Dictionary:
		var kind := str((rec as Dictionary).get("kind", "none"))
		if kind == "major" or kind == "minor":
			loot_tier = kind
			var slots: Array = (rec as Dictionary).get("slot_entries", [])
			if not slots.is_empty() and slots[0] is Dictionary:
				var off: Array = (slots[0] as Dictionary).get("offset_cm", [0, 0, 0])
				var rot: Array = (slots[0] as Dictionary).get("rotation_deg", [0, 0, 0])
				if off.size() >= 3:
					slot_offset_cm = Vector3(float(off[0]), float(off[1]), float(off[2]))
				if rot.size() >= 3:
					slot_rotation_deg = Vector3(float(rot[0]), float(rot[1]), float(rot[2]))
	# Name-based fallback when containers.json is unreadable: tier only, the
	# loot itself still resolves from loot_actors.json (or its tier pool).
	if loot_tier == "" and (p_class.find("MajorLoot") >= 0):
		loot_tier = "major"
	elif loot_tier == "" and (p_class.find("MinorLoot") >= 0):
		loot_tier = "minor"


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("loot_containers")
	set_meta("opened", false)
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = true
	var col := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.0
	col.shape = sph
	add_child(col)
	# No meshes: container visuals are level geometry. No _process: Area3D
	# triggers cost nothing per frame.


func get_interact_prompt() -> String:
	if opened:
		return "[Opened]"
	return "[F] OPEN"


## One-shot open. Major/minor containers spawn exactly one loot item at the
## marker position plus the slot offset; kind "none" (secret stash) only marks
## itself opened.
func interact(_actor: Node) -> void:
	if opened:
		return
	opened = true
	set_meta("opened", true)
	if loot_tier != "major" and loot_tier != "minor":
		return
	var tables := loot_tables()
	var buckets: Dictionary = tables.get("buckets", {})
	var bucket: Array = (buckets.get(loot_tier, {}) as Dictionary).get("classes", [])
	var actors: Dictionary = tables.get("actors", {})
	var l := LootScript.new()
	l.loot_tier = loot_tier
	l.is_quest_item = false
	var resolved := false
	if not bucket.is_empty():
		var cls := str(bucket[bucket_index(marker_pos, spawn_index, bucket.size())])
		var a: Variant = actors.get(cls, null)
		if a is Dictionary:
			l.item_name = str((a as Dictionary).get("name", "Noble Relic"))
			l.display_name = l.item_name
			l.value = int((a as Dictionary).get("value", 75))
			l.mesh_path = str((a as Dictionary).get("mesh_res", ""))
			resolved = true
	if not resolved:
		# Labelled fallback (same policy as the mission loot wave): the
		# tier-entry pool with the legacy note mesh, counts unchanged.
		var entry: Dictionary = LootScript.tier_entry(loot_tier, spawn_index)
		l.item_name = str(entry.get("name", "Noble Relic #%d" % (spawn_index + 1)))
		l.display_name = l.item_name
		l.value = int(entry.get("value", 75))
	l.mesh_rotation_deg = slot_world_rotation(marker_basis, slot_rotation_deg.x, slot_rotation_deg.y, slot_rotation_deg.z)
	var host: Node = get_parent()
	if host == null:
		return
	host.add_child(l)
	l.global_position = marker_pos + marker_basis * ue_offset_to_godot(slot_offset_cm)
