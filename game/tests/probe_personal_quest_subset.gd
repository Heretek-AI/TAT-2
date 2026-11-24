extends SceneTree
## W2P: subset real-map probe for the Spider personal chain (01 -> 04).
##
## Loads a subset of the chain's authored sublevels through the real
## LevelLoader (one call per map, 160-light desktop budget, collision on)
## instead of a whole mission map, then walks the shipping runtime path: the
## same PersonalQuest deploy / hub / read / take / talk transitions the mission
## drives, the same `personal_quest_spawner.gd` seam the mission controller
## calls (plan, grounding, authored fallbacks, dedupe, Owl -> courier), the
## real ClueItem / LootItem / NpcClueActor nodes and the real NpcClueDialogue
## modal.
##
## Sublevels per map (default "support" subset):
##   Guildhall : Building_Guildhall_POI + Guildhall_Gameplay + Guildhall_MissionClues
##   Old Manor : OldManor_P              + OldManor_Gameplay  + OldManor_Clues
##
## The two named gameplay/clue sublevels are the chain's own pins, but they do
## not carry the walkable floors: the Library table / Lounge floor are authored
## meshes in `Building_Guildhall_POI` and the Old Manor courtyard is the
## `OldManor_P` landscape. Without those two, every floor ray under a pin misses
## and the shipping spawner (correctly) refuses to invent a position. Run
## `-- --subset=strict` to load only the four named sublevels and observe that
## (see docs/reports/w2p-subset-probe.md).
##
## Every pin is checked on the loaded world: the floor ray under the authored
## point hits, the surface is flat within +/-0.05 m around the pin, a standing
## capsule (r 0.30 / h 1.75) fits, and a player-eye LOS ray to the interaction
## point is clear. For an NPC that capsule stands at the pin on its floor. For
## a prop (`readable`, `quest_item`) the ray under the pin hits the table /
## pedestal the prop rests on, so the capsule is stood on the walk floor found
## on a short XZ ring around the pin instead (never on the furniture top); LOS
## still targets the pinned interaction point. Placement is per kind (W3O): the
## Library note and the Vault Owl keep the authored pin y (the pin is their
## authored surface: the Library table and the `SM_Manor_BookcasePedestal` top
## at ~36.4645), while the courier/informant feet rest on the floor with the
## shipping 0.02 m clearance. `y_source` is asserted from the spawner record,
## never inferred from the kind. The Owl is gated on its pedestal surface: a pin
## with no surface within 36.4645 +/- 0.1 fails. NPC feet are accepted anywhere
## in [floor, floor + clearance + tol] because the body settles with gravity
## after it is spawned. Authored `yaw_deg` (courier/04 informant) is printed and
## checked against the node's global facing.
##
## QA only: run alone under the thermal rule (one Godot process, never beside
## another), with an isolated save home so the developer save is untouched:
##
##   XDG_DATA_HOME=/tmp/opencode/w2p-data \
##     tools/godot --headless --path game \
##     --script res://tests/probe_personal_quest_subset.gd
##
## Exits non-zero on the first failed expectation and restores the save file
## plus the GameState fields it borrows before quitting.

const LevelLoaderScript := preload("res://src/core/level_loader.gd")
const LightProbeScript := preload("res://src/stealth/light_probe.gd")
const PersonalQuestScript := preload("res://src/quests/personal_quest.gd")
## Loaded at runtime after boot: the spawner and the classes it preloads
## (clue_item / loot_item) name the `GameState` autoload directly, and a
## `--script` SceneTree script is parsed before the autoloads exist. A
## `preload()` here fails to resolve `GameState`; `load()` in `_run()` does not
## (same pattern as tests/test_personal_quest_spawner.gd, commit 8018a83).
## level_loader / light_probe / personal_quest are preload-safe: none of them
## name an autoload at parse time (personal_quest resolves it at runtime).
var PersonalQuestSpawnerScript: GDScript

## Named pins + the floor-bearing support sublevel. The support entries are
## required for a real floor under every pin (static AABB scan, see report).
const SUBSET_LEVELS := {
	"guildhall": [
		"res://data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI.tatlevel.json",
		"res://data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json",
		"res://data/generated/levels/Guildhall/Guildhall_MissionClues.tatlevel.json",
	],
	"old_manor": [
		"res://data/generated/levels/OldManor/OldManor_P.tatlevel.json",
		"res://data/generated/levels/OldManor/OldManor_Gameplay.tatlevel.json",
		"res://data/generated/levels/OldManor/OldManor_Clues.tatlevel.json",
	],
}

## Literal four-sublevel list from the W2P brief (`--subset=strict`).
const STRICT_LEVELS := {
	"guildhall": [
		"res://data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json",
		"res://data/generated/levels/Guildhall/Guildhall_MissionClues.tatlevel.json",
	],
	"old_manor": [
		"res://data/generated/levels/OldManor/OldManor_Gameplay.tatlevel.json",
		"res://data/generated/levels/OldManor/OldManor_Clues.tatlevel.json",
	],
}

## Desktop shipping budget (MobileProfile.DESKTOP_MAX_LIGHTS).
const LIGHT_BUDGET: int = 160
## Authored pins (producer positions; must equal the expansion anchors).
const PIN_NOTE := Vector3(-26.8541, 28.0021, -9.4431)
const PIN_OWL := Vector3(-31.6286, 36.4655, -43.9759)
const PIN_COURIER := Vector3(35.9, 27.0019, -22.728)
const PIN_INFORMANT := Vector3(1.5, 10.1096, 13.0)
## Probe tolerances.
const PIN_XZ_TOL_M: float = 0.001
## Authored-pin placement (readable/quest_item) keeps y to this tolerance.
const PIN_Y_TOL_M: float = 0.01
## The authored support (table/pedestal) must be this close to the pin or the
## mesh bottom when one is found at the pin.
const AUTHORED_SURFACE_TOL_M: float = 0.10
## Local authored-surface search window around the pin (the Vault floor sits
## 0.965 m below the Owl pin, so it is deliberately outside this window).
const AUTHORED_SURFACE_WINDOW_M: float = 0.35
## Vault Owl support: `SM_Manor_BookcasePedestal` in Guildhall_Gameplay sits at
## (-32, 35.5, -43.997) with a measured world top of ~36.4645 m (RE evidence).
## The pin (36.4655) rests 1 mm over it. The probe gates the Owl on a surface in
## this band at the pin XZ; if it is absent the placement is a failure, not a
## "none passes" notice.
const PEDESTAL_TOP_Y: float = 36.4645
const PEDESTAL_TOL_M: float = 0.10
const SURFACE_FLAT_TOL_M: float = 0.02
const SURFACE_SAMPLE_M: float = 0.05
const GROUND_CLEARANCE_M: float = 0.02
const GROUND_TOL_M: float = 0.01
const STAND_RADIUS_M: float = 0.30
const STAND_HEIGHT_M: float = 1.75
const PLAYER_EYE_M: float = 1.6
const LOS_STANDOFF_M: float = 1.4
## Prop capsule ring (m): a player stands beside a table/pedestal, never on it.
## Radii stay inside the shipped 1.75 m interaction range.
const STAND_RING_M := [0.6, 0.9, 1.2]
## A surface this far below the prop's support is a walk level, not the
## furniture top (Library table 28.000 over floor 27.000; Vault pedestal 36.4645
## over floor 35.500). The upper bound keeps a ray that fell through a decorative
## floor tile from calling the ground floor 15 m down a "walk floor".
const WALK_FLOOR_MIN_DROP_M: float = 0.5
const WALK_FLOOR_MAX_DROP_M: float = 1.5

## Authored lines (expansion record, not code literals).
const LINE_COURIER := "Aye, it's a Langnacht night tonight. I'll take the goods."
const LINE_INFORMANT := "I heard you're looking for dirt on Mallick. This might help. If anyone asks, you didn't get it from me."
const LINE_INFORMANT_CLOSE := "We're done here. I have nothing else for you."


## Minimal HUD host: the real NPC dialogue only needs set_npc_dialogue() /
## is_npc_dialogue_open() and the "hud" group. Toasts are recorded so the probe
## can assert the letter read reached the HUD path.
class StubHud extends CanvasLayer:
	var toasts: Array[Dictionary] = []
	var npc_dialogue: Node = null

	func _ready() -> void:
		name = "ProbeHud"
		add_to_group("hud")

	func set_npc_dialogue(node: Node) -> void:
		npc_dialogue = node

	func is_npc_dialogue_open() -> bool:
		if npc_dialogue == null or not is_instance_valid(npc_dialogue):
			return false
		if not npc_dialogue.has_method("is_open"):
			return false
		return bool(npc_dialogue.call("is_open"))

	func show_clue_toast(title: String, body: String) -> void:
		toasts.append({"title": title, "body": body})


## Minimal mission host: `loot_item.gd` (Owl take) and `npc_clue_actor.gd`
## (HUD lookup) both go through the first node in the "mission" group. In play
## that node is `MissionController`: it owns `hud`, and its
## `on_personal_quest_owl_taken()` forwards to the spawner's
## `on_owl_taken(GameState.thief_id)`. The probe reproduces exactly that seam.
##
## The spawner is deliberately NOT the group member: it has `hud` but no Owl
## hook, so a group lookup landing on it silently drops the courier (the W4P
## probe failure). One node owns both, as in play.
##
## The thief id is read at runtime through the tree, so this nested class never
## names the `GameState` autoload at parse time (the probe is a `--script`
## SceneTree entry parsed before the autoloads exist).
class StubMission extends Node:
	var hud: Node = null
	var spawner: Node = null

	func _ready() -> void:
		name = "ProbeMission"
		add_to_group("mission")

	func on_personal_quest_owl_taken() -> void:
		if spawner == null or not is_instance_valid(spawner):
			return
		if not spawner.has_method("on_owl_taken"):
			return
		var gs: Node = get_node_or_null("/root/GameState")
		var thief: String = str(gs.get("thief_id")) if gs != null else ""
		spawner.call("on_owl_taken", thief)


var fails: int = 0
var checks: int = 0
var strict_subset: bool = false


func _init() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--subset=") and arg.substr("--subset=".length()) == "strict":
			strict_subset = true
	call_deferred("_run")


func _check(cond: bool, ok: String, fail: String = "") -> bool:
	checks += 1
	if cond:
		print("PASS: [pq-subset] ", ok)
		return true
	fails += 1
	printerr("FAIL: [pq-subset] ", fail if fail != "" else ok)
	return false


func _wait_tree(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame


func _journal_ids(gs: Node) -> Array:
	var out: Array = []
	for entry_v: Variant in gs.get("clue_facts") as Array:
		if entry_v is Dictionary:
			out.append(str((entry_v as Dictionary).get("id", "")))
	return out


func _levels_for(map_id: String) -> Array[String]:
	var table: Dictionary = STRICT_LEVELS if strict_subset else SUBSET_LEVELS
	var out: Array[String] = []
	for p_v: Variant in table.get(map_id, []) as Array:
		out.append(str(p_v))
	return out


## Load one map subset through the real loader: one call, 160 lights, collision
## on. Returns {world, loader, probe, stats, hud}.
func _load_subset(map_id: String) -> Dictionary:
	var world := Node3D.new()
	world.name = "SubsetWorld_" + map_id
	root.add_child(world)
	var hud := StubHud.new()
	world.add_child(hud)
	var light_probe := LightProbeScript.new()
	light_probe.name = "LightProbe"
	world.add_child(light_probe)
	var loader := LevelLoaderScript.new()
	loader.name = "LevelLoader"
	world.add_child(loader)
	var paths: Array[String] = _levels_for(map_id)
	if paths.size() < 2:
		_check(false, "%s subset path list" % map_id, "config error: %s" % str(paths))
		return {}
	print("PQ-SUBSET mode=", "strict" if strict_subset else "support", " map=", map_id, " sublevels=", paths.size())
	for p: String in paths:
		print("PQ-SUBSET   ", p.get_file())
	var stats_v: Variant = loader.call("load_sublevels", paths, world, light_probe, LIGHT_BUDGET, true)
	var stats: Dictionary = stats_v as Dictionary
	print("PQ-SUBSET loaded ", map_id,
		" meshes=", stats.get("mesh_instances", 0),
		" lights=", stats.get("light_count", 0),
		" bodies=", stats.get("collision_bodies", 0),
		" shapes=", stats.get("collision_shapes", 0))
	# Static bodies need a physics tick before rays/shape queries see them.
	await physics_frame
	await physics_frame
	return {"world": world, "loader": loader, "probe": light_probe, "stats": stats, "hud": hud}


## The shipping spawn seam, hosted by the subset world. A `StubMission` in the
## "mission" group stands in for the mission controller (HUD + Owl hook); the
## spawner itself is not in the group, so the lookup can only find the host.
func _make_spawner(world: Node3D, hud: Node) -> Node:
	var mission := StubMission.new()
	mission.name = "ProbeMission"
	world.add_child(mission)
	mission.hud = hud
	var spawner: Node = PersonalQuestSpawnerScript.new()
	spawner.name = "PersonalQuestSpawner"
	world.add_child(spawner)
	spawner.call("setup", world, hud)
	mission.spawner = spawner
	return spawner


func _standing_overlap(world: Node3D, surface: Vector3) -> int:
	var cap := CapsuleShape3D.new()
	cap.radius = STAND_RADIUS_M
	cap.height = STAND_HEIGHT_M
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, surface + Vector3(0.0, STAND_HEIGHT_M * 0.5 + 0.05, 0.0))
	q.collision_mask = 1
	return world.get_world_3d().direct_space_state.intersect_shape(q, 16).size()


## Standing point beside a prop: the walk floor **near** the authored pin, never
## the support (`readable` / `quest_item` pins rest on a table or pedestal, and
## the ray straight down hits that top). A short XZ ring is sampled and the first
## point whose floor ray lands in the walk band right below the support and
## whose capsule is free wins. Returns {ok, y, point, overlaps, radius,
## angle_deg, reason}; on failure it carries the candidate with the fewest
## overlaps plus a list of everything sampled, so the failure line is evidence
## rather than a bare count.
func _walk_floor_stand(world: Node3D, pin: Vector3, support_y: float) -> Dictionary:
	var best: Dictionary = {}
	var tried: Array[String] = []
	for radius_v: Variant in STAND_RING_M:
		var radius: float = float(radius_v)
		for i: int in range(8):
			var ang: float = TAU * float(i) / 8.0
			var off := Vector3(cos(ang) * radius, 0.0, sin(ang) * radius)
			var xz := Vector3(pin.x + off.x, pin.y, pin.z + off.z)
			var hit: Dictionary = PersonalQuestSpawnerScript.floor_hit(world, xz)
			if hit.is_empty():
				tried.append("%.1fm/%.0fdeg:miss" % [radius, rad_to_deg(ang)])
				continue
			var hy: float = (hit.get("position", Vector3.ZERO) as Vector3).y
			var drop: float = support_y - hy
			if drop < WALK_FLOOR_MIN_DROP_M or drop > WALK_FLOOR_MAX_DROP_M:
				# The table / pedestal top, or a level too far down to be the
				# floor the player stands on next to this prop.
				tried.append("%.1fm/%.0fdeg:support" % [radius, rad_to_deg(ang)])
				continue
			var point := Vector3(xz.x, hy, xz.z)
			var overlaps: int = _standing_overlap(world, point + Vector3.UP * GROUND_CLEARANCE_M)
			if overlaps == 0:
				return {"ok": true, "y": hy, "point": point, "overlaps": 0,
					"radius": radius, "angle_deg": rad_to_deg(ang), "reason": ""}
			tried.append("%.1fm/%.0fdeg:%d" % [radius, rad_to_deg(ang), overlaps])
			if best.is_empty() or overlaps < int(best.get("overlaps", 99)):
				best = {"ok": false, "y": hy, "point": point, "overlaps": overlaps,
					"radius": radius, "angle_deg": rad_to_deg(ang)}
	if best.is_empty():
		return {"ok": false, "y": pin.y, "point": pin, "overlaps": 1,
			"radius": 0.0, "angle_deg": 0.0,
			"reason": "no walk floor %.1f-%.1f m below the support within %.1f m: %s" % [
				WALK_FLOOR_MIN_DROP_M, WALK_FLOOR_MAX_DROP_M,
				float(STAND_RING_M[STAND_RING_M.size() - 1]), ",".join(tried)]}
	best["reason"] = ",".join(tried)
	return best


## Player-eye LOS to the interaction point, from the first of eight directions
## where a standing capsule also fits. Returns {ok, dir, reason}.
func _los_from_open_side(world: Node3D, surface: Vector3, target: Vector3) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var tried: Array[String] = []
	for i: int in range(8):
		var ang: float = TAU * float(i) / 8.0
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var stand: Vector3 = surface + dir * LOS_STANDOFF_M
		if _standing_overlap(world, stand) > 0:
			tried.append("%.0fdeg:blocked" % rad_to_deg(ang))
			continue
		var eye: Vector3 = stand + Vector3.UP * PLAYER_EYE_M
		var q := PhysicsRayQueryParameters3D.create(eye, target, 1)
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			return {"ok": true, "dir": dir, "reason": ""}
		tried.append("%.0fdeg:wall" % rad_to_deg(ang))
	return {"ok": false, "dir": Vector3.ZERO, "reason": ",".join(tried)}


## Local authored support at the pin itself (the table/pedestal a readable or
## quest item is authored on), searched only +/- `window` around the pin so the
## walk floor far below cannot masquerade as the item's surface.
func _authored_surface_at(world: Node3D, pin: Vector3, window: float) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	if space == null:
		return {}
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		pin + Vector3.UP * window,
		pin + Vector3.DOWN * window, 1)
	return space.intersect_ray(q)


## Floor ray under the authored pin: hit + flatness at +/-0.05 m in X/Z.
func _surface_under(world: Node3D, pin: Vector3) -> Dictionary:
	var hit: Dictionary = PersonalQuestSpawnerScript.floor_hit(world, pin)
	if hit.is_empty():
		return {}
	var hy: float = (hit.get("position", Vector3.ZERO) as Vector3).y
	var max_delta: float = 0.0
	for off: Vector3 in [
		Vector3(SURFACE_SAMPLE_M, 0, 0), Vector3(-SURFACE_SAMPLE_M, 0, 0),
		Vector3(0, 0, SURFACE_SAMPLE_M), Vector3(0, 0, -SURFACE_SAMPLE_M),
	]:
		var h: Dictionary = PersonalQuestSpawnerScript.floor_hit(world, pin + off)
		if h.is_empty():
			return {"y": hy, "flat": false, "delta": 999.0}
		var oy: float = (h.get("position", Vector3.ZERO) as Vector3).y
		max_delta = maxf(max_delta, absf(oy - hy))
	return {"y": hy, "flat": max_delta <= SURFACE_FLAT_TOL_M, "delta": max_delta}


## Full placement proof for one pin. Returns the record's node for the chain
## walk, or null when the actor did not spawn.
func _check_pin(label: String, rec: Dictionary, expect: Vector3, world: Node3D, prompt: String) -> Node:
	if not _check(not rec.is_empty(), label + " spawned", label + " missing from the spawn plan (no grounded authored pin)"):
		return null
	var node: Node3D = rec.get("node", null) as Node3D
	if not _check(node != null and is_instance_valid(node), label + " has a live node", label + " node invalid"):
		return null
	_check(str(rec.get("source", "")) == "primary", label + " uses the primary authored pin",
		"%s used source=%s (a fallback means the authored pin did not ground)" % [label, str(rec.get("source", ""))])
	var pos: Vector3 = node.global_position
	_check(absf(pos.x - expect.x) <= PIN_XZ_TOL_M and absf(pos.z - expect.z) <= PIN_XZ_TOL_M,
		label + " at authored XZ (%.4f, %.4f)" % [expect.x, expect.z],
		"%s XZ=(%.4f, %.4f) expected (%.4f, %.4f)" % [label, pos.x, pos.z, expect.x, expect.z])
	var surf: Dictionary = _surface_under(world, expect)
	if not _check((not surf.is_empty()) and float(surf.get("delta", 999.0)) < 999.0,
			label + " floor ray hits under the authored pin",
			label + " floor ray missed / sampled edge at " + str(expect)):
		return node
	var hy: float = float(surf.get("y", 0.0))
	_check(bool(surf.get("flat", false)),
		label + " surface flat within +/-%.2f m (max delta %.3f)" % [SURFACE_SAMPLE_M, float(surf.get("delta", 0.0))],
		"%s surface not flat: delta %.3f" % [label, float(surf.get("delta", 0.0))])
	# The authored pin is the spawner origin, not the floor (the Library note
	# sits on a table at its pin; the Owl pin rests on the Vault pedestal).
	print("PQ-SUBSET pin ", label, " authored_y=%.4f surface_y=%.4f offset=%.3f" % [expect.y, hy, expect.y - hy])
	var kind: String = str(rec.get("kind", ""))
	var y_source: String = str(rec.get("y_source", ""))
	var foot: float = pos.y + node.global_transform.basis.y.y * PersonalQuestSpawnerScript.mesh_bottom(node)
	var yaw_v: Variant = rec.get("yaw_deg", null)
	var yaw_text: String = ("%.1f" % float(yaw_v)) if (yaw_v is float or yaw_v is int) and is_finite(float(yaw_v)) else "none"
	print("PQ_PLACE kind=", kind, " y=", y_source, " label=", label, " yaw=", yaw_text,
		" pin_y=%.4f floor_y=%.4f pos_y=%.4f foot_y=%.4f" % [expect.y, hy, pos.y, foot])
	if kind == "npc" or kind == "info_npc":
		_check(y_source == "floor", label + " records y_source=floor",
			"%s y_source=%s (expected floor)" % [label, y_source])
		# The NPC settles with gravity after spawn, so its feet may sit
		# anywhere between the floor and the shipping clearance.
		_check(foot >= hy - GROUND_TOL_M and foot <= hy + GROUND_CLEARANCE_M + GROUND_TOL_M,
			label + " mesh rests on the surface (foot in [floor, floor + %.2f m])" % GROUND_CLEARANCE_M,
			"%s foot=%.4f surface=%.4f clearance=%.4f" % [label, foot, hy, foot - hy])
		if yaw_v is float or yaw_v is int:
			var want_yaw: float = deg_to_rad(float(yaw_v))
			var got_yaw: float = node.global_rotation.y
			_check(absf(angle_difference(got_yaw, want_yaw)) <= 0.01,
				label + " node yaw matches the authored record (%.1f deg)" % float(yaw_v),
				"%s yaw=%.1f deg expected %.1f deg" % [label, rad_to_deg(got_yaw), float(yaw_v)])
		else:
			_check(true, label + " has no authored yaw (left at 0)")
	else:
		# W3O/W4O: readables and quest items keep the authored pin exactly.
		_check(y_source == "pin", label + " records y_source=pin",
			"%s y_source=%s (expected pin)" % [label, y_source])
		_check(absf(pos.y - expect.y) <= PIN_Y_TOL_M,
			label + " keeps the authored pin y (%.4f, no floor drop)" % expect.y,
			"%s y=%.4f expected authored pin y=%.4f (walk floor is %.4f)" % [label, pos.y, expect.y, hy])
		_check(foot >= hy - GROUND_TOL_M,
			label + " mesh bottom is not sunk into the walk surface (foot %.4f >= floor %.4f)" % [foot, hy],
			"%s foot=%.4f is below the walk surface %.4f" % [label, foot, hy])
		_check(not is_finite(float(yaw_v)) if (yaw_v is float or yaw_v is int) else true,
			label + " is not rotated by an authored yaw",
			"%s yaw_deg=%s but props keep their authored orientation" % [label, str(yaw_v)])
		# The authored support is required, never optional.
		var window: float = PEDESTAL_TOL_M if kind == "quest_item" else AUTHORED_SURFACE_WINDOW_M
		var authored: Dictionary = _authored_surface_at(world, expect, window)
		if not _check(not authored.is_empty(),
				label + " has authored support within +/-%.2f m of its pin" % window,
				label + " has NO authored surface within +/-%.2f m of the pin (pin %.3f m over the walk surface)" % [
					window, expect.y - hy]):
			return node
		var ay: float = float((authored.get("position", Vector3.ZERO) as Vector3).y)
		var ap: Vector3 = authored.get("position", Vector3.ZERO) as Vector3
		print("PQ-SUBSET authored surface ", label, " y=%.4f lateral=%.3f pin_offset=%.4f foot_offset=%.4f" % [
			ay, Vector2(ap.x, ap.z).distance_to(Vector2(expect.x, expect.z)),
			expect.y - ay, foot - ay])
		_check(absf(pos.y - ay) <= AUTHORED_SURFACE_TOL_M or absf(foot - ay) <= AUTHORED_SURFACE_TOL_M,
			label + " rests on its authored surface y=%.4f" % ay,
			"%s pin=%.4f foot=%.4f authored surface=%.4f" % [label, pos.y, foot, ay])
		if kind == "quest_item":
			_check(absf(ay - PEDESTAL_TOP_Y) <= PEDESTAL_TOL_M,
				label + " support is the BookcasePedestal top (%.4f +/- %.2f m)" % [PEDESTAL_TOP_Y, PEDESTAL_TOL_M],
				"%s authored support y=%.4f, expected %.4f +/- %.2f (SM_Manor_BookcasePedestal)" % [
					label, ay, PEDESTAL_TOP_Y, PEDESTAL_TOL_M])
	var stand_y: float = hy
	var stand_overlaps: int = 0
	var stand_note: String = "at the pin"
	var stand_reason: String = ""
	if kind == "npc" or kind == "info_npc":
		stand_overlaps = _standing_overlap(world, Vector3(expect.x, hy + GROUND_CLEARANCE_M, expect.z))
	else:
		# A prop pin is a table/pedestal top. Stand the capsule where a player
		# would: the walk floor on a short ring around the pin.
		var walk: Dictionary = _walk_floor_stand(world, expect, hy)
		stand_y = float(walk.get("y", hy))
		stand_overlaps = int(walk.get("overlaps", 1))
		stand_note = "on the walk floor (offset %.1f m @ %.0f deg)" % [
			float(walk.get("radius", 0.0)), float(walk.get("angle_deg", 0.0))]
		stand_reason = str(walk.get("reason", ""))
		print("PQ-SUBSET stand ", label, " walk_floor_y=%.4f overlaps=%d %s" % [
			stand_y, stand_overlaps, stand_note])
	_check(stand_overlaps == 0, label + " standing capsule (r0.30/h1.75) free " + stand_note,
		"%s standing capsule overlaps %d shape(s) %s" % [
			label, stand_overlaps, stand_reason if stand_reason != "" else stand_note])
	if node.has_method("get_interact_point"):
		var los: Dictionary = _los_from_open_side(world, Vector3(expect.x, stand_y, expect.z), node.call("get_interact_point") as Vector3)
		_check(bool(los.get("ok", false)), label + " interaction LOS clear",
			"%s LOS blocked: %s" % [label, str(los.get("reason", ""))])
	if node.has_method("get_interact_prompt"):
		_check(str(node.call("get_interact_prompt")) == prompt, label + " prompt '" + prompt + "'",
			"%s prompt=%s" % [label, str(node.call("get_interact_prompt"))])
	return node


func _run() -> void:
	PersonalQuestSpawnerScript = load("res://src/quests/personal_quest_spawner.gd") as GDScript
	if PersonalQuestSpawnerScript == null:
		printerr("PERSONAL QUEST SUBSET FAIL: cannot load personal_quest_spawner.gd")
		quit(1)
		return
	var gs: Node = root.get_node_or_null("/root/GameState")
	var ss: Node = root.get_node_or_null("/root/SaveSystem")
	if gs == null or ss == null:
		printerr("PERSONAL QUEST SUBSET FAIL: autoloads missing")
		quit(1)
		return

	var save_path: String = "user://tat2_save.json"
	var had_file: bool = FileAccess.file_exists(save_path)
	var file_backup: String = FileAccess.get_file_as_string(save_path) if had_file else ""
	var live_backup: Dictionary = (ss.get("data") as Dictionary).duplicate(true)
	var gs_thief: String = str(gs.get("thief_id"))
	var gs_map: String = str(gs.get("active_map_id"))
	var gs_order: int = int(gs.get("active_contract_order"))
	var gs_free: bool = bool(gs.get("free_play"))
	var gs_free_pending: bool = bool(gs.get("free_play_pending"))
	var gs_facts: Array = (gs.get("clue_facts") as Array).duplicate(true)
	var loot_before: int = int(gs.get("loot_collected"))
	var value_before: int = int(gs.get("loot_value"))
	var currency_before: int = int((ss.get("data") as Dictionary).get("currency", 0))
	var objectives_before: int = (gs.get("mission_objectives") as Array).size()
	var completed_before: Dictionary = ((ss.get("data") as Dictionary).get("completed_contracts", {}) as Dictionary).duplicate(true)
	var item_before: bool = bool(gs.get("quest_item_acquired"))

	ss.call("reset_personal_quest", "spider")
	ss.call("reset_personal_quest", "chameleon")
	gs.clue_facts.clear()
	gs.set("thief_id", "spider")
	gs.set("active_map_id", "guildhall")
	gs.set("active_contract_order", 4)
	gs.set("quest_item_acquired", false)

	# ---- Guildhall subset: intro deploy -> note -> letter ------------------
	var deploy_intro: Dictionary = PersonalQuestScript.on_deploy("guildhall")
	_check(str(PersonalQuestScript.stage_for("spider")) == "intro", "first Guildhall deploy starts intro", str(deploy_intro))
	var guildhall: Dictionary = await _load_subset("guildhall")
	if guildhall.is_empty():
		await _cleanup(ss, live_backup, save_path, had_file, file_backup, gs, gs_thief, gs_map, gs_order, gs_free, gs_free_pending, gs_facts, item_before)
		quit(1)
		return
	var gh_world: Node3D = guildhall.get("world") as Node3D
	var gh_hud: Node = guildhall.get("hud") as Node
	var gh_spawner: Node = _make_spawner(gh_world, gh_hud)
	gh_spawner.call("spawn_for_map", "guildhall", "spider")
	var note_rec: Dictionary = gh_spawner.call("find", "library_note") as Dictionary
	var note: Node = _check_pin("letter", note_rec, PIN_NOTE, gh_world, "[E] Read")
	_check(note != null and note.is_in_group("interactables"), "letter is interactable")
	if note != null:
		note.call("interact", null)
		await _wait_tree(2)
	_check(str(PersonalQuestScript.stage_for("spider")) == "letter", "reading the letter advances to letter")
	_check(_journal_ids(gs).has("DT_ClueFacts_Personal_Spider_01:FoundLetter"), "FoundLetter journaled")
	_check(not (gh_hud.get("toasts") as Array).is_empty(), "letter read reaches the HUD toast path")

	# Den return, then the next Guildhall deploy pins the Owl.
	var hub: Dictionary = PersonalQuestScript.on_hub_enter()
	_check(str(PersonalQuestScript.stage_for("spider")) == "electrotype", "Den return delivers the pending messages", str(hub))
	var deploy_located: Dictionary = PersonalQuestScript.on_deploy("guildhall")
	_check(str(PersonalQuestScript.stage_for("spider")) == "located", "next Guildhall deploy locates the Owl", str(deploy_located))
	gh_spawner.call("spawn_for_map", "guildhall", "spider")
	var owl_rec: Dictionary = gh_spawner.call("find", "owl") as Dictionary
	var owl: Node = _check_pin("Owl", owl_rec, PIN_OWL, gh_world, "[E] Take Theban Owl")
	_check(owl != null and not owl.is_in_group("loot"), "Owl is not in the loot group")
	if owl != null:
		owl.call("interact", null)
		await _wait_tree(3)
	_check(str(PersonalQuestScript.stage_for("spider")) == "carrying" and str(PersonalQuestScript.owl_for("spider")) == "held", "Owl pickup -> carrying/held")
	_check(int(gs.get("loot_collected")) == loot_before and int(gs.get("loot_value")) == value_before, "Owl pickup adds no loot")
	_check(int((ss.get("data") as Dictionary).get("currency", 0)) == currency_before, "Owl pickup adds no currency")
	_check(not bool(gs.get("quest_item_acquired")), "Owl pickup sets no quest_item_acquired")

	var courier_rec: Dictionary = gh_spawner.call("find", "courier") as Dictionary
	var courier: Node = _check_pin("courier", courier_rec, PIN_COURIER, gh_world, "[E] Talk")
	if courier != null:
		courier.call("interact", null)
		await _wait_tree(2)
	_check(str(PersonalQuestScript.stage_for("spider")) == "delivered" and str(PersonalQuestScript.owl_for("spider")) == "delivered", "courier hand-off -> delivered")
	_check(_journal_ids(gs).has("DT_ClueFacts_Personal_Spider_03:HandedOff"), "03:HandedOff journaled")
	var dlg: Node = gh_hud.get_node_or_null("NpcClueDialogue")
	_check(dlg != null and bool(dlg.call("is_open")), "courier opens the real dialogue modal")
	_check(dlg != null and str(dlg.call("body_text")) == LINE_COURIER, "courier shows the shipped 03 line",
		"courier line=%s" % (str(dlg.call("body_text")) if dlg != null else "<no modal>"))
	if dlg != null:
		dlg.call("close")
	await _free_world(gh_world)

	# ---- Old Manor subset: 04 informant, first line then follow-up --------
	gs.set("active_map_id", "old_manor")
	gs.set("active_contract_order", 3)
	PersonalQuestScript.on_deploy("old_manor")
	var manor: Dictionary = await _load_subset("old_manor")
	if manor.is_empty():
		await _cleanup(ss, live_backup, save_path, had_file, file_backup, gs, gs_thief, gs_map, gs_order, gs_free, gs_free_pending, gs_facts, item_before)
		quit(1)
		return
	var om_world: Node3D = manor.get("world") as Node3D
	var om_hud: Node = manor.get("hud") as Node
	var om_spawner: Node = _make_spawner(om_world, om_hud)
	om_spawner.call("spawn_for_map", "old_manor", "spider")
	var inf_rec: Dictionary = om_spawner.call("find", "informant") as Dictionary
	var informant: Node = _check_pin("informant", inf_rec, PIN_INFORMANT, om_world, "[E] Talk")
	if informant != null:
		informant.call("interact", null)
		await _wait_tree(2)
	_check(str(PersonalQuestScript.stage_for("spider")) == "info", "informant first talk -> info")
	_check(_journal_ids(gs).has("DT_ClueFacts_Personal_Spider_04:GotInfo"), "04:GotInfo journaled")
	var dlg2: Node = om_hud.get_node_or_null("NpcClueDialogue")
	_check(dlg2 != null and str(dlg2.call("body_text")) == LINE_INFORMANT, "informant shows the shipped 04 line",
		"informant line=%s" % (str(dlg2.call("body_text")) if dlg2 != null else "<no modal>"))
	if dlg2 != null:
		dlg2.call("close")
	# The closing press and the next talk are never in one frame in play
	# (npc_clue_actor ignores the frame that closed the panel), so wait a frame
	# before the follow-up interaction.
	await _wait_tree(2)
	if informant != null:
		informant.call("interact", null)
		await _wait_tree(2)
	_check(str(PersonalQuestScript.stage_for("spider")) == "complete", "informant follow-up closes the chain")
	var dlg3: Node = om_hud.get_node_or_null("NpcClueDialogue")
	_check(dlg3 != null and str(dlg3.call("body_text")) == LINE_INFORMANT_CLOSE, "follow-up is the shipped 04 close",
		"close line=%s" % (str(dlg3.call("body_text")) if dlg3 != null else "<no modal>"))
	if dlg3 != null:
		dlg3.call("close")
	await _free_world(om_world)

	# ---- Chain invariants ------------------------------------------------
	var facts: Array = PersonalQuestScript.facts_for("spider")
	_check(str(PersonalQuestScript.owl_for("spider")) == "delivered", "Owl ends delivered")
	_check(facts.size() == 7, "seven chain facts persisted", str(facts))
	for bad: String in [
		"DT_ClueFacts_Personal_Spider_01:ObjectiveComplete_Clue",
		"DT_ClueFacts_Personal_Spider_01:ObjectiveComplete_Electrogram",
		"DT_ClueFacts_Personal_Spider_03:Reminder",
		"DT_ClueFacts_Personal_Spider_04:Renegade",
	]:
		_check(not facts.has(bad) and not gs.call("has_clue_fact", bad), "suppressed fact absent: " + bad)
	_check(int(gs.get("loot_collected")) == loot_before and int(gs.get("loot_value")) == value_before, "chain banks no loot")
	_check(int((ss.get("data") as Dictionary).get("currency", 0)) == currency_before, "chain banks no currency")
	_check((gs.get("mission_objectives") as Array).size() == objectives_before, "chain adds no objective")
	_check(((ss.get("data") as Dictionary).get("completed_contracts", {}) as Dictionary) == completed_before, "chain completes no contract")
	var cham: Dictionary = ss.call("get_personal_quest", "chameleon") as Dictionary
	_check(str(cham.get("stage", "")) == "" and (cham.get("facts", []) as Array).is_empty() and str(cham.get("owl", "none")) == "none",
		"Chameleon record untouched (none)", str(cham))

	# ---- Save persistence ------------------------------------------------
	ss.call("write_save")
	var on_disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	var disk_spider: Dictionary = {}
	if on_disk is Dictionary:
		var pq: Variant = (on_disk as Dictionary).get("personal_quest", {})
		if pq is Dictionary:
			var sv: Variant = (pq as Dictionary).get("spider", {})
			if sv is Dictionary:
				disk_spider = sv as Dictionary
	_check(str(disk_spider.get("stage", "")) == "complete", "save file persists stage=complete")
	_check((disk_spider.get("facts", []) as Array).size() == 7 and str(disk_spider.get("owl", "")) == "delivered",
		"save file persists the seven facts and delivered Owl", str(disk_spider))
	ss.call("load_save")
	var reloaded: Dictionary = ss.call("get_personal_quest", "spider") as Dictionary
	_check(str(reloaded.get("stage", "")) == "complete" and (reloaded.get("facts", []) as Array).size() == 7,
		"reloaded save keeps the completed chain", str(reloaded))

	_print_chain()
	await _cleanup(ss, live_backup, save_path, had_file, file_backup, gs, gs_thief, gs_map, gs_order, gs_free, gs_free_pending, gs_facts, item_before)
	print("PERSONAL QUEST SUBSET ", "PASS" if fails == 0 else "FAIL", " checks=", checks, " fails=", fails)
	quit(0 if fails == 0 else 1)


func _print_chain() -> void:
	print("PQ-SUBSET stage=", PersonalQuestScript.stage_for("spider"), " owl=", PersonalQuestScript.owl_for("spider"))
	for fact_v: Variant in PersonalQuestScript.facts_for("spider"):
		print("PQ-SUBSET fact=", str(fact_v))


func _free_world(world: Node3D) -> void:
	if world != null and is_instance_valid(world):
		world.queue_free()
	await _wait_tree(8)


func _cleanup(ss: Node, live_backup: Dictionary, save_path: String, had_file: bool, file_backup: String, gs: Node, thief: String, map_id: String, order: int, free: bool, free_pending: bool, facts: Array, item_acquired: bool) -> void:
	ss.set("data", live_backup)
	if had_file:
		var f: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
		if f != null:
			f.store_string(file_backup)
			f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	gs.set("thief_id", thief)
	gs.set("active_map_id", map_id)
	gs.set("active_contract_order", order)
	gs.set("free_play", free)
	gs.set("free_play_pending", free_pending)
	gs.set("quest_item_acquired", item_acquired)
	gs.clue_facts.clear()
	for fact_v: Variant in facts:
		if fact_v is Dictionary:
			(gs.get("clue_facts") as Array).append(fact_v as Dictionary)
