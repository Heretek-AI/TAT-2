extends SceneTree
## P1-W lane probe (S25/S26, V6-04 / G5-03 / G5-04 / V1-07, KF28/KF29).
##
## Proves, headlessly and without a GPU:
##   1. the flat violet ward pane is gone: the blocker ward builds a faceted
##      crystal-shard cluster and, on the loaded Guildhall, adopts the authored
##      `SM_BlockerWard_*` shards (one visual, hidden until active);
##   2. the beam's existing `beam_triggered` contract still fires and activates
##      the ward and the green door ward (BP_OneWayBarrier reproduction);
##   3. the green door ward uses the authored MI_DoorWard_OneSided_Green tint
##      and the authored 2.6 x 3.4 m plane / BlockerBox, and shatters;
##   4. the ward shatter clears the blocker layer, hides the shards and emits
##      `ward_shattered`;
##   5. the KF29 alarm eye spawns the crimson spotlight with the authored cone
##      and range (15 deg / 15.33 m) and the documented KF29 colour/energy;
##   6. the HUD exposes the jaw-trap status icon above the Light Gem.
##
## Run (one Godot at a time, shared lock):
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "timeout 900 tools/godot --headless --path game \
##       --script res://tests/probe_p1_ward.gd"
##
## Output: `P1_WARD PASS checks=<n>` / `P1_WARD FAIL fails=<n> checks=<n>`.

const WARD_SCRIPT := "res://src/devices/ward_zone.gd"
const VINE_SCRIPT := "res://src/devices/vine_lock.gd"
const BEAM_SCRIPT := "res://src/devices/security_beam.gd"
const ALARM_SCRIPT := "res://src/devices/alarm_eye.gd"
const LAYER_SCRIPT := "res://src/devices/device_layer.gd"
const HUD_SCRIPT := "res://src/ui/hud.gd"
const STATUS_ICON_SCRIPT := "res://src/ui/status_icon.gd"
const MISSION_SCRIPT := "res://src/missions/mission_controller.gd"
const RUNTIME_PATH := "res://data/generated/gameplay/devices_runtime.json"
const MATERIALS_PATH := "res://data/generated/materials.json"
const LEVEL_PATH := "res://data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json"

const WARD_ID := "guildhall/Guildhall_Gameplay:BP_WardZone_Blocker_C_31"
const BEAM_ID := "guildhall/Guildhall_Gameplay:BP_Detector_LightBeam_C_117"
const ALARM_ID := "guildhall/Guildhall_Gameplay:BP_MagicAlarm_LongRange_Narrow_C_38"

## Authored values (from devices_runtime.json / materials.json).
const AUTHORED_WARD_POS := Vector3(31.1979, 28.0, -41.9796)
const AUTHORED_WARD_ZONE_M := Vector3(0.3, 3.93638, 1.6526434)
const AUTHORED_WARD_SHARDS := 7
const AUTHORED_BEAM_LENGTH_M := 9.71770508
const AUTHORED_ALARM_CONE_DEG := 15.0
const AUTHORED_ALARM_RANGE_M := 15.32772
const AUTHORED_BLOCKER_EMISSIVE := Color(1.0, 0.1307, 0.7967)
const AUTHORED_VINE_TINT := Color(0.1334, 1.0, 0.0, 1.0)
const AUTHORED_VINE_PLANE := Vector2(2.6, 3.4)
## KF29 documented approximation (vfx_manager.spawn_crimson_alarm).
const KF29_ALARM_COLOR := Color(1.0, 0.07, 0.05)
const KF29_ALARM_ENERGY := 4.5

var fails: int = 0
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, ok: String, fail: String = "") -> bool:
	checks += 1
	if cond:
		print("PASS: [p1-ward] ", ok)
		return true
	fails += 1
	printerr("FAIL: [p1-ward] ", fail if fail != "" else ok)
	return false


func _run() -> void:
	await process_frame
	var ward_scr: GDScript = load(WARD_SCRIPT) as GDScript
	var vine_scr: GDScript = load(VINE_SCRIPT) as GDScript
	var beam_scr: GDScript = load(BEAM_SCRIPT) as GDScript
	var alarm_scr: GDScript = load(ALARM_SCRIPT) as GDScript
	var layer_scr: GDScript = load(LAYER_SCRIPT) as GDScript
	var status_scr: GDScript = load(STATUS_ICON_SCRIPT) as GDScript
	_check(ward_scr != null and vine_scr != null and beam_scr != null and alarm_scr != null and layer_scr != null and status_scr != null,
		"scripts load (ward, vine, beam, alarm, device layer, status icon)",
		"a P1-W script failed to load")

	var doc: Dictionary = _load_json(RUNTIME_PATH)
	var rec_by_id: Dictionary = {}
	var maps: Dictionary = doc.get("maps", {}) as Dictionary
	var guild: Dictionary = maps.get("guildhall", {}) as Dictionary
	for rec_v: Variant in (guild.get("devices", []) as Array):
		if rec_v is Dictionary:
			rec_by_id[str((rec_v as Dictionary).get("id", ""))] = rec_v
	var defaults: Dictionary = ((doc.get("stats", {}) as Dictionary).get("family_defaults", {})) as Dictionary
	var ward_rec: Dictionary = rec_by_id.get(WARD_ID, {}) as Dictionary
	var beam_rec: Dictionary = rec_by_id.get(BEAM_ID, {}) as Dictionary
	var alarm_rec: Dictionary = rec_by_id.get(ALARM_ID, {}) as Dictionary
	_check(not ward_rec.is_empty() and not beam_rec.is_empty() and not alarm_rec.is_empty(),
		"authored foyer ward / beam / alarm records present",
		"missing foyer records in devices_runtime.json")
	if ward_rec.is_empty() or beam_rec.is_empty() or alarm_rec.is_empty():
		_finish()
		return

	# ---- 1. Ward: flat pane replaced by a faceted shard cluster ------------
	var ward: Node3D = ward_scr.new() as Node3D
	get_root().add_child(ward)
	ward.call("configure", ward_rec, defaults, 1)
	await process_frame
	var zone: Vector3 = ward.get("zone_size_m") as Vector3
	var zone_ok: bool = absf(zone.x - AUTHORED_WARD_ZONE_M.x) < 0.001 \
		and absf(zone.y - AUTHORED_WARD_ZONE_M.y) < 0.001 \
		and absf(zone.z - AUTHORED_WARD_ZONE_M.z) < 0.001
	_check(zone_ok, "ward zone is the authored (X, Z, Y) box 0.30 x 3.936 x 1.653 m", "ward zone=%s" % zone)
	_check(str(ward.get("mode")) == "blocker" and not bool(ward.get("active")),
		"ward is a blocker and starts inactive (WardInitiallyActive=false)",
		"ward mode/active wrong")
	var cluster: Node = ward.get("_fallback_cluster") as Node
	var shard_children: int = cluster.get_child_count() if cluster != null else 0
	_check(shard_children >= 5, "fallback ward visual is a %d-shard crystal cluster" % shard_children,
		"fallback cluster has %d children" % shard_children)
	var facet_ok: bool = true
	if cluster != null:
		for c: Node in cluster.get_children():
			var mi: MeshInstance3D = c as MeshInstance3D
			if mi == null or not (mi.mesh is BoxMesh):
				facet_ok = false
				break
			var box: BoxMesh = mi.mesh as BoxMesh
			if box.size.y < 2.0 * maxf(box.size.x, box.size.z):
				facet_ok = false
				break
			var mat: ShaderMaterial = mi.material_override as ShaderMaterial
			if mat == null or mat.shader == null or mat.shader.resource_path != "res://src/core/tat_ward_shard.gdshader":
				facet_ok = false
				break
	_check(facet_ok, "every fallback shard is a tall faceted crystal with the shard material (no flat pane)",
		"fallback shard shape/material failed")
	var shard_mat: ShaderMaterial = ward_scr.call("shard_material") as ShaderMaterial
	var ward_color: Color = shard_mat.get_shader_parameter("ward_color") as Color if shard_mat != null else Color.BLACK
	_check(shard_mat != null and absf(ward_color.g - (77.0 / 255.0)) < 0.01 and ward_color.b > 0.95 and ward_color.r > 0.99,
		"ward active tint is authored base WardColor #FF4DFD (purple), not the flat violet pane",
		"ward tint=%s" % ward_color)
	var shard_emissive: float = float(shard_mat.get_shader_parameter("emissive_energy")) if shard_mat != null else -1.0
	_check(absf(shard_emissive - 1.0) < 0.001, "ward emissive energy = authored MI_BlockerWard 1.0",
		"ward emissive=%s" % shard_emissive)
	var mats_doc: Dictionary = _load_json(MATERIALS_PATH)
	var blocker_mat: Dictionary = mats_doc.get("/Game/Art/Gameplay/Wards/MI_BlockerWard", {}) as Dictionary
	var blocker_vecs: Dictionary = blocker_mat.get("vectors", {}) as Dictionary
	var blocker_emissive: Array = blocker_vecs.get("EmissiveColor", []) as Array
	var authored_emissive_ok: bool = blocker_emissive.size() >= 3 \
		and absf(float(blocker_emissive[0]) - AUTHORED_BLOCKER_EMISSIVE.r) < 0.001 \
		and absf(float(blocker_emissive[1]) - AUTHORED_BLOCKER_EMISSIVE.g) < 0.001 \
		and absf(float(blocker_emissive[2]) - AUTHORED_BLOCKER_EMISSIVE.b) < 0.001
	_check(authored_emissive_ok, "materials.json MI_BlockerWard EmissiveColor is the authored magenta (1.0, 0.1307, 0.7967)",
		"MI_BlockerWard EmissiveColor=%s" % str(blocker_emissive))

	# ---- 2. Ward activate / adopt / shatter state --------------------------
	var adopted_a: MeshInstance3D = _dummy_shard("AdoptedA")
	var adopted_b: MeshInstance3D = _dummy_shard("AdoptedB")
	get_root().add_child(adopted_a)
	get_root().add_child(adopted_b)
	ward.call("adopt_ward_shards", [adopted_a, adopted_b])
	_check(int(ward.get("authored_shards").size()) == 2, "ward adopts authored level shards (one visual)",
		"adopt count wrong")
	_check(not adopted_a.visible and not adopted_b.visible, "adopted shards start hidden while the ward is inactive",
		"adopted shards visible before activation")
	var shattered_count: Array = [0]
	ward.connect("ward_shattered", func(_s: Node) -> void: shattered_count[0] += 1)
	ward.call("activate")
	await process_frame
	var blocked_layer: int = 0
	var body: StaticBody3D = ward.get("blocker_body") as StaticBody3D
	if body != null:
		blocked_layer = body.collision_layer
	_check(bool(ward.get("active")) and blocked_layer == 16, "activate: ward active and blocker layer = bit4 (16)",
		"active=%s layer=%d" % [bool(ward.get("active")), blocked_layer])
	_check(adopted_a.visible and adopted_b.visible, "activate: authored shards become visible (the ward seals the archway)",
		"adopted shards stayed hidden after activation")
	ward.call("shatter", ward)
	await process_frame
	blocked_layer = body.collision_layer if body != null else -1
	_check(not bool(ward.get("active")) and bool(ward.get("shattered")) and blocked_layer == 0,
		"shatter: ward inactive, blocker layer cleared",
		"active=%s shattered=%s layer=%d" % [bool(ward.get("active")), bool(ward.get("shattered")), blocked_layer])
	_check(not adopted_a.visible and not adopted_b.visible, "shatter: authored shards hidden",
		"adopted shards visible after shatter")
	_check(shattered_count[0] == 1, "shatter emits ward_shattered exactly once", "ward_shattered count=%d" % shattered_count[0])

	# ---- 3. Beam trip -> ward + vine (existing beam_triggered contract) ----
	var vine: Node3D = vine_scr.new() as Node3D
	get_root().add_child(vine)
	vine.call("configure", Vector3(30.70, 28.0, -47.1), -PI * 0.5)
	await process_frame
	var plane_ok: bool = false
	var vine_visual: MeshInstance3D = vine.get("_visual") as MeshInstance3D
	if vine_visual != null and vine_visual.mesh is PlaneMesh:
		var pm: PlaneMesh = vine_visual.mesh as PlaneMesh
		plane_ok = absf(pm.size.x - AUTHORED_VINE_PLANE.x) < 0.001 and absf(pm.size.y - AUTHORED_VINE_PLANE.y) < 0.001
	_check(plane_ok, "green door ward uses the authored 2.6 x 3.4 m Plane", "vine plane size wrong")
	var vine_mat: ShaderMaterial = vine.get("_material") as ShaderMaterial
	var vine_tint: Color = vine_mat.get_shader_parameter("vine_color") as Color if vine_mat != null else Color.BLACK
	_check(vine_mat != null and absf(vine_tint.r - AUTHORED_VINE_TINT.r) < 0.001 \
		and absf(vine_tint.g - AUTHORED_VINE_TINT.g) < 0.001 and absf(vine_tint.b - AUTHORED_VINE_TINT.b) < 0.001,
		"vine tint is authored MI_DoorWard_OneSided_Green Color (0.1334, 1.0, 0.0)",
		"vine tint=%s" % vine_tint)
	var vine_blocker: StaticBody3D = vine.get("_blocker") as StaticBody3D
	var vine_box_ok: bool = false
	if vine_blocker != null:
		var cs: CollisionShape3D = vine_blocker.get_node_or_null("VineBox") as CollisionShape3D
		if cs != null and cs.shape is BoxShape3D:
			var b: BoxShape3D = cs.shape as BoxShape3D
			vine_box_ok = absf(b.size.x - 2.56) < 0.01 and absf(b.size.y - 3.36) < 0.01 and absf(b.size.z - 0.16) < 0.01
	_check(vine_box_ok, "vine BlockerBox matches authored BoxExtent (4, 128, 168) cm on the plane axes", "vine blocker box wrong")
	_check(not bool(vine.get("active")) and vine_blocker != null and vine_blocker.collision_layer == 0,
		"vine starts hidden and non-solid", "vine initial state wrong")

	var beam: Area3D = beam_scr.new() as Area3D
	get_root().add_child(beam)
	beam.call("configure", beam_rec, defaults, 1)
	beam.transform = _record_transform(beam_rec)
	await process_frame
	# Fresh ward for the wire test: the first instance is already shattered.
	var ward2: Node3D = ward_scr.new() as Node3D
	get_root().add_child(ward2)
	ward2.call("configure", ward_rec, defaults, 1)
	ward2.transform = _record_transform(ward_rec)
	var vine2: Node3D = vine_scr.new() as Node3D
	get_root().add_child(vine2)
	vine2.call("configure", Vector3(30.70, 28.0, -47.1), -PI * 0.5)
	await process_frame
	var beam_len: float = float(beam.get("beam_length_m"))
	_check(absf(beam_len - AUTHORED_BEAM_LENGTH_M) < 0.001, "beam 117 keeps the authored 9.718 m length",
		"beam length=%.4f" % beam_len)
	var trip_count: Array = [0]
	beam.connect("beam_triggered", func(_s: Node) -> void: trip_count[0] += 1)
	beam.call("set_action_targets", [ward2, vine2])
	beam.call("_fire")
	await process_frame
	_check(trip_count[0] == 1, "beam_triggered contract still fires once per trip", "beam_triggered count=%d" % trip_count[0])
	_check(bool(ward2.get("active")) and bool(vine2.get("active")),
		"beam trip activates the ward and seals the green door ward (G5-03)",
		"ward active=%s vine active=%s" % [bool(ward2.get("active")), bool(vine2.get("active"))])
	var vine_blocker2: StaticBody3D = vine2.get("_blocker") as StaticBody3D
	_check(vine_blocker2 != null and vine_blocker2.collision_layer == 16,
		"sealed vine blocks on bit4 (player-only ward layer)", "vine layer=%d" % (vine_blocker2.collision_layer if vine_blocker2 != null else -1))
	var vine_shattered: Array = [0]
	vine2.connect("shattered", func(_s: Node) -> void: vine_shattered[0] += 1)
	vine2.call("shatter", vine2)
	await process_frame
	_check(vine_shattered[0] == 1 and not bool(vine2.get("active")) and vine_blocker2.collision_layer == 0,
		"vine shatter opens the door ward and emits shattered once (G5-04)",
		"vine shattered count=%d active=%s" % [vine_shattered[0], bool(vine2.get("active"))])

	# ---- 4. KF29 crimson alarm spotlight ----------------------------------
	var alarm: Node3D = alarm_scr.new() as Node3D
	get_root().add_child(alarm)
	alarm.call("configure", alarm_rec, defaults, 1)
	alarm.transform = _record_transform(alarm_rec)
	await process_frame
	var cone: float = float(alarm.get("cone_deg"))
	var alarm_range: float = float(alarm.get("light_range_m"))
	_check(absf(cone - AUTHORED_ALARM_CONE_DEG) < 0.001 and absf(alarm_range - AUTHORED_ALARM_RANGE_M) < 0.01,
		"alarm eye keeps the authored OuterConeAngle 15 deg / AttenuationRadius 15.33 m",
		"cone=%.2f range=%.3f" % [cone, alarm_range])
	alarm.call("trigger_alarm")
	await process_frame
	var spot: SpotLight3D = alarm.get_node_or_null("CrimsonAlarmSpot") as SpotLight3D
	_check(spot != null, "alarm spawns the crimson spotlight node (V1-07)",
		"no CrimsonAlarmSpot under the authored stairwell alarm eye")
	if spot != null:
		var col: Color = spot.light_color
		var spot_dir: Vector3 = -spot.global_transform.basis.z
		var authored_down_ok: bool = absf(spot_dir.y + 1.0) < 0.01
		_check(absf(col.r - KF29_ALARM_COLOR.r) < 0.001 and absf(col.g - KF29_ALARM_COLOR.g) < 0.001 and absf(col.b - KF29_ALARM_COLOR.b) < 0.001,
			"crimson colour = (1.0, 0.07, 0.05) [KF29 approximation]", "alarm colour=%s" % col)
		_check(absf(spot.light_energy - KF29_ALARM_ENERGY) < 0.001,
			"crimson energy = 4.5 [KF29 approximation, capped]", "alarm energy=%.2f" % spot.light_energy)
		_check(spot.spot_range >= AUTHORED_ALARM_RANGE_M - 0.01 and absf(spot.spot_angle - 32.0) < 0.001,
			"spot range uses the authored 15.33 m; angle is the documented KF29 32 deg wash",
			"spot range=%.2f angle=%.1f" % [spot.spot_range, spot.spot_angle])
		_check(authored_down_ok, "spot aims along the authored alarm-eye forward (straight down)",
			"spot dir=%s" % spot_dir)
	alarm.call("reset_alarm")
	await process_frame
	_check(alarm.get_node_or_null("CrimsonAlarmSpot") == null, "alarm reset frees the crimson spotlight",
		"spot survived reset_alarm")

	# ---- 5. HUD status icon (UI5-06) --------------------------------------
	var hud_scr: GDScript = load(HUD_SCRIPT) as GDScript
	var hud_has_api: bool = hud_scr != null \
		and hud_scr.can_instantiate() \
		and _has_method(hud_scr, "set_status_icon") \
		and _has_method(hud_scr, "clear_status_icon") \
		and _has_method(hud_scr, "status_icon_state")
	_check(hud_has_api, "HUD exposes set/clear/status_icon_state (UI5-06)",
		"HUD status icon API missing")
	var icon: Control = status_scr.new() as Control
	get_root().add_child(icon)
	await process_frame
	icon.call("show_icon", "jaw_trap", 8.0)
	var icon_state: Dictionary = icon.call("state") as Dictionary
	_check(bool(icon_state.get("active", false)) and bool(icon_state.get("visible", false)) \
		and absf(float(icon_state.get("duration", 0.0)) - 8.0) < 0.001 \
		and str(icon_state.get("kind", "")) == "jaw_trap",
		"status icon raises with the jaw-trap kind and an 8 s countdown ring",
		"status icon state=%s" % str(icon_state))
	icon.call("clear_icon")
	_check(not bool((icon.call("state") as Dictionary).get("active", true)), "status icon clears",
		"status icon did not clear")

	# ---- 6. Mission wiring presence ---------------------------------------
	var mission_scr: GDScript = load(MISSION_SCRIPT) as GDScript
	var mission_ok: bool = mission_scr != null \
		and _has_method(mission_scr, "_spawn_foyer_lockdown") \
		and _has_method(mission_scr, "_tick_foyer_lockdown") \
		and _has_method(mission_scr, "_complete_foyer_lockdown_break") \
		and str(mission_scr.get_script_constant_map().get("FOYER_WARD_ID", "")) == WARD_ID \
		and str(mission_scr.get_script_constant_map().get("FOYER_BEAM_ID", "")) == BEAM_ID \
		and str(mission_scr.get_script_constant_map().get("FOYER_ALARM_ID", "")) == ALARM_ID
	_check(mission_ok, "mission controller wires the authored ward/beam/alarm ids and lockdown hooks",
		"mission lockdown wiring missing")

	# ---- 7. Authored shards on the loaded Guildhall ------------------------
	var loader_scr: GDScript = load("res://src/core/level_loader.gd") as GDScript
	var ll: Node = loader_scr.new()
	get_root().add_child(ll)
	var level_root: Node3D = Node3D.new()
	get_root().add_child(level_root)
	var expected_shards: int = _count_ward_shards_in_level(LEVEL_PATH)
	var load_res: Dictionary = await ll.call("load_sublevels_async", [LEVEL_PATH], level_root, null, 96, true)
	var ward_shards: Array = get_nodes_in_group("ward_shards")
	var hidden_count: int = 0
	for s_v: Variant in ward_shards:
		if s_v is Node3D and not (s_v as Node3D).visible:
			hidden_count += 1
	_check(expected_shards > 0 and ward_shards.size() == expected_shards,
		"Guildhall_Gameplay loads all %d authored SM_BlockerWard shard instances" % expected_shards,
		"ward_shards group=%d expected=%d (load spawned=%d)" % [ward_shards.size(), expected_shards, int(load_res.get("ward_shard_spawned", -1))])
	_check(hidden_count == ward_shards.size(),
		"every authored ward shard starts hidden (no always-on ward)",
		"hidden=%d/%d" % [hidden_count, ward_shards.size()])
	# Pair the loaded shards through the real device layer.
	var layer: Node3D = layer_scr.new() as Node3D
	get_root().add_child(layer)
	var spawned: int = int(layer.call("spawn_for_map", "guildhall", null, 1))
	var total_shards: int = int(layer.get("ward_shards_total"))
	var adopted_shards: int = int(layer.get("ward_shards_adopted"))
	_check(spawned == 903 and int(layer.call("family_count", "ward_blocker")) == 36,
		"device census unchanged: 903 devices, 36 ward blockers",
		"spawned=%d ward_blocker=%d" % [spawned, int(layer.call("family_count", "ward_blocker"))])
	_check(total_shards == expected_shards and adopted_shards == total_shards,
		"device layer pairs every loaded shard: %d/%d" % [adopted_shards, expected_shards],
		"paired=%d/%d loaded=%d" % [adopted_shards, total_shards, expected_shards])
	var foyer_ward: Node = layer.call("get_device", WARD_ID) as Node
	var foyer_shards: int = (foyer_ward.get("authored_shards") as Array).size() if foyer_ward != null else -1
	_check(foyer_shards == AUTHORED_WARD_SHARDS,
		"foyer archway ward (C_31) owns its authored %d-shard cluster" % AUTHORED_WARD_SHARDS,
		"foyer ward shards=%d" % foyer_shards)
	if foyer_ward != null:
		var any_visible: bool = false
		for s_v: Variant in (foyer_ward.get("authored_shards") as Array):
			if s_v is Node3D and (s_v as Node3D).visible:
				any_visible = true
		_check(not any_visible, "foyer ward shards stay hidden before the beam trip (KF28 gate)",
			"foyer ward shards visible before activation")
		foyer_ward.call("activate")
		await process_frame
		var visible_after: int = 0
		for s_v: Variant in (foyer_ward.get("authored_shards") as Array):
			if s_v is Node3D and (s_v as Node3D).visible:
				visible_after += 1
		_check(visible_after == AUTHORED_WARD_SHARDS,
			"beam/activation shows the foyer ward's authored shard cluster",
			"visible=%d/%d" % [visible_after, AUTHORED_WARD_SHARDS])
		foyer_ward.call("shatter", foyer_ward)
		await process_frame
		var visible_shatter: int = 0
		for s_v: Variant in (foyer_ward.get("authored_shards") as Array):
			if s_v is Node3D and (s_v as Node3D).visible:
				visible_shatter += 1
		_check(visible_shatter == 0, "foyer ward shatter hides the authored cluster (G5-04)",
			"visible after shatter=%d" % visible_shatter)
	layer.call("clear_spawned")
	level_root.queue_free()
	ll.queue_free()

	_finish()


func _finish() -> void:
	await process_frame
	if fails == 0:
		print("P1_WARD PASS checks=", checks)
		quit(0)
	else:
		printerr("P1_WARD FAIL fails=", fails, " checks=", checks)
		quit(1)


func _has_method(scr: GDScript, name: String) -> bool:
	for m: Dictionary in scr.get_script_method_list():
		if str(m.get("name", "")) == name:
			return true
	return false


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("[p1-ward] missing ", path)
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _record_transform(rec: Dictionary) -> Transform3D:
	var geo: GDScript = load("res://src/devices/device_geometry.gd") as GDScript
	if geo == null:
		return Transform3D.IDENTITY
	return geo.call("transform_from_record", rec) as Transform3D


## Count the authored SM_BlockerWard instances in the generated level payload
## (the loader's own input), not a hardcoded number.
func _count_ward_shards_in_level(path: String) -> int:
	var level: Dictionary = _load_json(path)
	var n: int = 0
	for m_v: Variant in (level.get("meshes", []) as Array):
		if m_v is Dictionary:
			var mp: String = str((m_v as Dictionary).get("mesh", "")).to_lower()
			if mp.contains("/sm_blockerward_"):
				n += 1
	return n


func _dummy_shard(name: String) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = name
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(0.2, 3.0, 0.2)
	mi.mesh = mesh
	mi.visible = false
	return mi
