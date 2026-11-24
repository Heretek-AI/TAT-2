extends Area3D
## Map pickup spawned from BP_MissionSpawner_* markers (throwable bottles,
## ammo/tool refills, health packs). Real mesh from spawners.json, Area3D
## trigger only — no StaticBody3D is created for pickups.
##
## Interaction effects (documented approximations — the cooked UE graphs
## serialize no heal/refill amounts):
##   throwable -> +1 bottle charge on the player ("bottle" charges key)
##   ammo      -> refill every tool charge key to its documented max
##   health    -> restore the player to full HP (InteractDuration 1.0 s is
##                the real extracted BP_Health_Pickup value; the hold-to-use
##                timing itself is instant here like the other pickups)

enum Kind { THROWABLE, AMMO, HEALTH }

## Distance at which pickup meshes are culled (matches TINY_PROP policy).
const VISIBILITY_RANGE_END_M: float = 45.0

## Documented approximation: cooked graphs carry no refill amounts, so ammo
## restores every charge key to its extracted/initial max (see
## thief_character.gd SLITHERSAP_CHARGES/SMOKE_CHARGES and the infinite
## fairy display value).
const AMMO_REFILL_MAX: Dictionary = {
	"slithersap": 4,
	"smoke_bomb": 1,
	"pickpocket_fairy": 999,
	"grapple": 4,
	"bottle": 99,
}

var kind: int = Kind.THROWABLE
var mesh_res_path: String = ""
var collected: bool = false


static func kind_name(k: int) -> String:
	match k:
		Kind.THROWABLE:
			return "throwable"
		Kind.AMMO:
			return "ammo"
		Kind.HEALTH:
			return "health"
	return "unknown"


## Must be called before add_child (visuals are built in _ready).
func setup(p_kind: int, p_mesh_path: String) -> void:
	kind = p_kind
	mesh_res_path = p_mesh_path


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("spawner_pickup")
	add_to_group("thief_vision_highlight")
	add_to_group("xray_target")
	set_meta("collected", false)
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = true
	var col := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	# Ammo trigger radius is the real extracted InteractionSphereTrigger
	# value (35 cm); bottles/health use the same reach for consistency.
	sph.radius = 0.35
	col.shape = sph
	add_child(col)
	var visual := Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	_attach_mesh(visual)


func _attach_mesh(visual: Node3D) -> void:
	var added: bool = false
	if mesh_res_path != "" and ResourceLoader.exists(mesh_res_path):
		var packed := ResourceLoader.load(mesh_res_path) as PackedScene
		if packed != null:
			var inst := packed.instantiate() as Node3D
			if inst != null:
				visual.add_child(inst)
				added = true
	if added:
		for mi in visual.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			m.visibility_range_end = VISIBILITY_RANGE_END_M
			m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	else:
		# Fallback only when the extracted mesh file is missing; never a
		# substitute for a resolvable mesh.
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.3, 0.3, 0.3)
		var mat := StandardMaterial3D.new()
		match kind:
			Kind.HEALTH:
				mat.albedo_color = Color(0.9, 0.25, 0.25)
			Kind.AMMO:
				mat.albedo_color = Color(0.75, 0.6, 0.2)
			_:
				mat.albedo_color = Color(0.3, 0.7, 0.3)
		box.material = mat
		mi.mesh = box
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = VISIBILITY_RANGE_END_M
		visual.add_child(mi)


func get_interact_prompt() -> String:
	match kind:
		Kind.THROWABLE:
			return "[E] Take Bottle"
		Kind.AMMO:
			return "[E] Refill Tools"
		Kind.HEALTH:
			return "[E] Use Health Pack"
	return "[E] Take"


## Interaction LOS point (W2): grounded pickups can have their origin inside
## the prop; +0.4 m is the readable top of a bottle/toolbox/health pack.
func get_interact_point() -> Vector3:
	return global_position + Vector3.UP * 0.4


## Applies the kind effect to the interacting actor. Single-use: the node
## frees itself after a successful pickup.
func interact(actor: Node) -> void:
	if collected or actor == null:
		return
	match kind:
		Kind.THROWABLE:
			var ch: Variant = actor.get("charges")
			if ch is Dictionary:
				(ch as Dictionary)["bottle"] = int((ch as Dictionary).get("bottle", 0)) + 1
			else:
				return
		Kind.AMMO:
			var ch2: Variant = actor.get("charges")
			if not (ch2 is Dictionary):
				return
			for key in AMMO_REFILL_MAX.keys():
				(ch2 as Dictionary)[key] = int(AMMO_REFILL_MAX[key])
			if actor.has_signal("tool_used"):
				actor.emit_signal("tool_used", "ammo_refill", -1)
		Kind.HEALTH:
			if actor.get("health") == null or actor.get("max_health") == null:
				return
			# Documented approximation: no heal amount survives cooking, so
			# a health pack restores full HP.
			actor.set("health", actor.get("max_health"))
			if actor.has_signal("health_changed"):
				actor.emit_signal("health_changed", actor.get("health"), actor.get("max_health"))
	collected = true
	set_meta("collected", true)
	queue_free()


func set_highlighted(on: bool) -> void:
	var vis := get_node_or_null("Visual") as Node3D
	if vis == null:
		return
	XrayOverlay.set_xray_highlight(vis, on, "loot")


func set_xray_highlight(on: bool, _category: String = "") -> void:
	set_highlighted(on)


func _apply_highlight_recursive(node: Node, on: bool) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if on:
			if mi.get_meta("had_overlay", false) == false:
				mi.set_meta("had_overlay", mi.material_overlay != null)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.3, 0.85, 1.0, 0.35)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.emission_enabled = true
			mat.emission = Color(0.3, 0.85, 1.0)
			mat.emission_energy_multiplier = 1.2
			mi.material_overlay = mat
		else:
			if not mi.get_meta("had_overlay", false):
				mi.material_overlay = null
	for c in node.get_children():
		_apply_highlight_recursive(c, on)
