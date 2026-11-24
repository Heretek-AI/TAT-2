extends RefCounted
## Review tagging for baked `LevelLoader` scenes and the in-game review mode.
##
## The loader adds every draw item flat under its parent and only sets
## `ue_mesh` / `decorative` / `override_materials` metadata. This script is the
## single source of truth for the review vocabulary on top of that:
##
##   review_sublevel : String  source .tatlevel.json stem (group ancestry)
##   review_kind     : mesh | multimesh | landscape | light | decal | niagara |
##                     collision | occluder | fog | bookmark | environment |
##                     group
##   review_issue    : beam_lines | world_label | emissive_plate | collision_only
##   review_role     : door | loot | device (dock convenience filter)
##
## Tags are written on every node, not inherited, so an instanced per-sublevel
## scene keeps its identity when assembled into `review.tscn`.
##
## NOTE: `review_kind = fog` is an extension of the requested vocabulary;
## Guildhall_LocalVolumetric builds FogVolume nodes that the Lighting toggle
## must be able to hide. Documented in docs/reports/review-map-baker.md.

const EMISSIVE_ENERGY_MIN: float = 0.5

const ROLE_TOKENS: Dictionary = {
	"door": ["door", "gate", "shutter", "portal", "archway"],
	"loot": ["loot", "safe", "cabinet", "stash", "chest", "clue"],
	"device": ["device", "security", "detector", "turret", "alarm", "laser", "panel"],
}


## Tags one node and returns the tag dictionary it wrote (handy for tests).
static func classify_node(node: Node, sublevel: String = "") -> Dictionary:
	var tags: Dictionary = {
		"review_sublevel": sublevel,
		"review_kind": _kind_of(node),
		"review_issue": "",
		"review_role": "",
	}
	var ue_path: String = ""
	if node.has_meta("ue_mesh"):
		ue_path = str(node.get_meta("ue_mesh"))
	var low_ue: String = ue_path.to_lower()

	if _is_beam(node, low_ue):
		tags["review_issue"] = "beam_lines"
	elif _is_world_label(node):
		tags["review_issue"] = "world_label"
	elif _is_emissive(node):
		tags["review_issue"] = "emissive_plate"
	elif tags["review_kind"] == "collision" and node is StaticBody3D:
		tags["review_issue"] = "collision_only"

	# The device/loot tokens are matched against the authored UE path first and
	# the Godot node name second (collision bodies are named LevelCollision_*,
	# which must not classify as a door).
	var role_source: String = low_ue if low_ue != "" else str(node.name).to_lower()
	for role: String in ROLE_TOKENS.keys():
		for token: String in ROLE_TOKENS[role]:
			if role_source.find(token) >= 0:
				tags["review_role"] = role
				break
		if str(tags["review_role"]) != "":
			break
	return tags


## Writes the tags from `classify_node` on `node` (only non-empty optional
## keys), then recurses. `sublevel` is threaded down so every node records the
## sublevel it was built from.
static func apply_tags(node: Node, sublevel: String = "") -> void:
	var tags: Dictionary = classify_node(node, sublevel)
	node.set_meta("review_sublevel", tags["review_sublevel"])
	node.set_meta("review_kind", tags["review_kind"])
	if str(tags["review_issue"]) != "":
		node.set_meta("review_issue", tags["review_issue"])
	else:
		node.remove_meta("review_issue")
	if str(tags["review_role"]) != "":
		node.set_meta("review_role", tags["review_role"])
	else:
		node.remove_meta("review_role")
	for child: Node in node.get_children():
		apply_tags(child, sublevel)


## Walks a tagged subtree and returns manifest-safe counts (no Node refs).
## `aabb` is merged from every GeometryInstance3D in world space; MultiMesh
## uses the loader's `custom_aabb`, which is already world-space.
static func collect_stats(root: Node) -> Dictionary:
	var stats: Dictionary = {
		"nodes": 0,
		"kinds": {},
		"issues": {},
		"roles": {},
		"instances": 0,          # mesh/multimesh instance sum
		"draw_instances": 0,     # instances that carry an authored ue_mesh
		"surfaces": 0,
		"lights": 0,
		"loader_lights": 0,     # excludes loader GI fills (SkylightLeakingFill_*)
		"occluders": 0,
		"collision_bodies": 0,
		"collision_shapes": 0,
		"decals": 0,
		"fog_volumes": 0,
		"niagara_nodes": 0,
		"niagara_instances": 0,
		"aabb": AABB(),
		"has_aabb": false,
	}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stats["nodes"] = int(stats["nodes"]) + 1
		var kind: String = str(n.get_meta("review_kind", "")) if n.has_meta("review_kind") else ""
		if kind != "":
			var kinds: Dictionary = stats["kinds"]
			kinds[kind] = int(kinds.get(kind, 0)) + 1
		if n.has_meta("review_issue"):
			var issue: String = str(n.get_meta("review_issue"))
			var issues: Dictionary = stats["issues"]
			issues[issue] = int(issues.get(issue, 0)) + 1
		if n.has_meta("review_role"):
			var role: String = str(n.get_meta("review_role"))
			var roles: Dictionary = stats["roles"]
			roles[role] = int(roles.get(role, 0)) + 1

		match kind:
			"light":
				stats["lights"] = int(stats["lights"]) + 1
				# The loader adds post-process GI fills outside the light budget
				# (SkylightLeakingFill_*). They are real review light nodes but
				# not part of loader `light_count`.
				if not str(n.name).begins_with("SkylightLeakingFill_"):
					stats["loader_lights"] = int(stats["loader_lights"]) + 1
			"occluder":
				stats["occluders"] = int(stats["occluders"]) + 1
			"decal":
				stats["decals"] = int(stats["decals"]) + 1
			"collision":
				if n is StaticBody3D:
					stats["collision_bodies"] = int(stats["collision_bodies"]) + 1
				elif n is CollisionShape3D:
					stats["collision_shapes"] = int(stats["collision_shapes"]) + 1
			"fog":
				stats["fog_volumes"] = int(stats["fog_volumes"]) + 1
			"niagara":
				stats["niagara_nodes"] = int(stats["niagara_nodes"]) + 1

		if n is GeometryInstance3D:
			var gi: GeometryInstance3D = n as GeometryInstance3D
			var mesh: Mesh = null
			var count: int = 1
			if gi is MultiMeshInstance3D:
				var mmi: MultiMeshInstance3D = gi as MultiMeshInstance3D
				if mmi.multimesh != null:
					mesh = mmi.multimesh.mesh
					count = mmi.multimesh.instance_count
					stats["instances"] = int(stats["instances"]) + count
					if kind == "niagara":
						stats["niagara_instances"] = int(stats["niagara_instances"]) + count
			elif gi is MeshInstance3D:
				mesh = (gi as MeshInstance3D).mesh
				stats["instances"] = int(stats["instances"]) + 1
			if mesh != null:
				stats["surfaces"] = int(stats["surfaces"]) + mesh.get_surface_count()
				if n.has_meta("ue_mesh"):
					stats["draw_instances"] = int(stats["draw_instances"]) + count
				stats["has_aabb"] = _merge_aabb(stats, gi, mesh)
		for c: Node in n.get_children():
			stack.push_back(c)
	return stats


static func _merge_aabb(stats: Dictionary, gi: GeometryInstance3D, mesh: Mesh) -> bool:
	var box: AABB
	if gi is MultiMeshInstance3D:
		var mmi: MultiMeshInstance3D = gi as MultiMeshInstance3D
		if mmi.multimesh == null:
			return bool(stats["has_aabb"])
		box = mmi.multimesh.custom_aabb
		if not box.has_volume():
			box = mmi.transform * mmi.multimesh.get_aabb()
	else:
		box = gi.transform * mesh.get_aabb()
	if not bool(stats["has_aabb"]):
		stats["aabb"] = box
		return true
	stats["aabb"] = (stats["aabb"] as AABB).merge(box)
	return true


static func _kind_of(node: Node) -> String:
	if node is Label3D or node is Sprite3D:
		return "mesh"
	if node is FogVolume:
		return "fog"
	if node is Decal:
		return "decal"
	if node is Light3D:
		return "light"
	if node is OccluderInstance3D:
		return "occluder"
	if node is StaticBody3D or node is CollisionShape3D:
		return "collision"
	if node is MultiMeshInstance3D:
		# The loader spawns authored Niagara placements through one
		# MultiMeshInstance3D per NS_* system named LevelNiagara_*.
		if str(node.name).begins_with("LevelNiagara_"):
			return "niagara"
		var mmi: MultiMeshInstance3D = node as MultiMeshInstance3D
		if mmi.material_override is ShaderMaterial:
			var nm: ShaderMaterial = mmi.material_override as ShaderMaterial
			if nm.shader != null and nm.shader.resource_path.find("level_niagara") >= 0:
				return "niagara"
		return "multimesh"
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		# Landscape components are the only unnamed ArrayMesh instances the
		# loader builds (draw items always carry `ue_mesh`; curbs carry it too,
		# and procedural props are primitives).
		if not node.has_meta("ue_mesh") and mi.mesh is ArrayMesh:
			return "landscape"
		return "mesh"
	if node is Marker3D:
		return "bookmark"
	if node is WorldEnvironment:
		return "environment"
	if node is Node3D:
		return "group"
	return "other"


static func _is_world_label(node: Node) -> bool:
	if node is Label3D:
		return true
	if node is Sprite3D:
		return (node as Sprite3D).billboard != BaseMaterial3D.BILLBOARD_DISABLED
	return false


static func _is_beam(node: Node, low_ue: String) -> bool:
	if low_ue.find("lightbeam") >= 0:
		return true
	if node is GeometryInstance3D:
		for mat: Material in _materials_of(node as GeometryInstance3D):
			if _material_path(mat).find("tat_beam") >= 0:
				return true
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null:
				if (mat as ShaderMaterial).shader.resource_path.find("tat_beam") >= 0:
					return true
	return false


static func _is_emissive(node: Node) -> bool:
	if not (node is GeometryInstance3D):
		return false
	for mat: Material in _materials_of(node as GeometryInstance3D):
		if mat is BaseMaterial3D:
			var bm: BaseMaterial3D = mat as BaseMaterial3D
			if bm.emission_enabled and bm.emission_energy_multiplier > EMISSIVE_ENERGY_MIN:
				return true
		elif mat is ShaderMaterial:
			var sm: ShaderMaterial = mat as ShaderMaterial
			var shader_path: String = ""
			if sm.shader != null:
				shader_path = sm.shader.resource_path.to_lower()
			if shader_path.find("emissive") >= 0 or shader_path.find("hdr_") >= 0:
				return true
			var energy_v: Variant = sm.get_shader_parameter("energy")
			if energy_v is float and float(energy_v) > EMISSIVE_ENERGY_MIN:
				return true
			var intensity_v: Variant = sm.get_shader_parameter("intensity")
			if intensity_v is float and float(intensity_v) > EMISSIVE_ENERGY_MIN:
				return true
	return false


static func _materials_of(gi: GeometryInstance3D) -> Array:
	var out: Array = []
	if gi.material_override != null:
		out.append(gi.material_override)
	if gi.material_overlay != null:
		out.append(gi.material_overlay)
	if gi is MeshInstance3D:
		var mi: MeshInstance3D = gi as MeshInstance3D
		if mi.mesh == null:
			return out
		for s: int in range(mi.mesh.get_surface_count()):
			var ov: Material = mi.get_surface_override_material(s)
			if ov != null:
				out.append(ov)
			var sm: Material = mi.mesh.surface_get_material(s)
			if sm != null:
				out.append(sm)
	elif gi is MultiMeshInstance3D:
		var mmi: MultiMeshInstance3D = gi as MultiMeshInstance3D
		if mmi.multimesh == null or mmi.multimesh.mesh == null:
			return out
		var mm: Mesh = mmi.multimesh.mesh
		for s2: int in range(mm.get_surface_count()):
			var sm2: Material = mm.surface_get_material(s2)
			if sm2 != null:
				out.append(sm2)
	return out


static func _material_path(mat: Material) -> String:
	if mat == null:
		return ""
	var p: String = mat.resource_path
	if p == "" and mat is BaseMaterial3D:
		# Authored material names survive in the mesh's metadata-free path only
		# via resource_path; StandardMaterial3D variants share nothing else.
		p = ""
	return p.to_lower()
