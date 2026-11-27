extends SceneTree
## P1-SAFE probe: the Contract-02 safe-room subjects from S12 / KF14.
##
## Rows covered:
##   * V6-01 escape-portal wall outline - the authored emerald/violet
##     chromatic contour on the safe-room wall (BP_EscapePoint OpenColor /
##     ClosedColor, SummonBox size, Door_Light).
##   * G1-05 safe-room lantern toggle - `[F] TURN ON` / `[F] TURN OFF`, the
##     authored 5.0 / #FFC277 / 80 deg / 4.5 m spot, the glass emission and the
##     emissive flame shape (BP_ToggleableLanternA).
##   * V1-04 lantern warm bounce - the authored spot carries the warm colour
##     and energy the reference bounce comes from (the indirect bounce itself
##     is HL-7 lighting, not measured here).
##   * Safe-room dressing - brick wall + oval sconce (already authored in
##     Guildhall_PeripheryA) and the `"SPIDER"` flyer (SM_PosterWantedA).
##
## What this probe measures, per section:
##   A. Builds the real `safe_room_dressing.gd` through a live level loader
##      (the same `_get_mesh_and_shape` / `get_material_for_ue` path the map
##      uses) and asserts node presence, the portal QuadMesh/shader/params, the
##      lantern prompt/toggle/light/emission state machine and the flyer mesh +
##      material + authored UV window.
##   B. Instantiates a real `escape_gate.gd` and asserts the endgame contract is
##      untouched: the same portal visual, the authored light, activate /
##      expire / collapse visibility, 3x3x3 trigger, no floating Label3D.
##   C. Re-reads the authored JSON dumps (read-only) and asserts every constant
##      the dressing hardcodes still matches the shipped data: BP_EscapePoint,
##      BP_ToggleableLanternA, ST_Interactables prompts, the PeripheryA safe-room
##      wall/sconce rows, the Contract-02 spawn pose and the mesh material join.
##
## Prints `P1_SAFE PASS` / `P1_SAFE FAIL fails=<n>` and exits 0 / 1.
##
## Run (one Godot at a time):
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "timeout 900 tools/godot --headless --path game --script res://tests/probe_p1_safe.gd"

const LevelLoaderScript: GDScript = preload("res://src/core/level_loader.gd")
## Runtime-loaded, NOT preloaded: both scripts reference the `GameState`
## autoload, and in a `--script` SceneTree run a preload compiles them before
## the autoloads exist ("Identifier not found: GameState", see
## probe_guard_positions.gd:209). Loading after `_initialize` has booted the
## autoloads is the supported pattern.
var DressingScript: GDScript = null
var EscapeScript: GDScript = null

const LEVELS := "res://data/generated/levels/"
## The extracted UE dumps live beside the Godot project (game/), not inside
## res://; globalize the project root and step out one level.
var _extracted_root: String = ProjectSettings.globalize_path("res://").path_join("../extracted/json")

var fails: int = 0
var checks: int = 0
var skips: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("  ok: ", msg)
	else:
		fails += 1
		print("  FAIL: ", msg)


func _skip(msg: String) -> void:
	skips += 1
	print("  skip: ", msg)


func _json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed


func _near(a: float, b: float, eps: float = 0.0005) -> bool:
	return absf(a - b) <= eps


func _near_color(c: Color, r: float, g: float, b: float, eps: float = 0.0005) -> bool:
	return _near(c.r, r, eps) and _near(c.g, g, eps) and _near(c.b, b, eps)


## BP_EscapePoint dump `Properties` with the given class type.
func _bp_props(dump: Variant, type_name: String) -> Array:
	var out: Array = []
	if dump is Array:
		for o: Variant in dump:
			if o is Dictionary and str((o as Dictionary).get("Type", "")) == type_name:
				var p: Variant = (o as Dictionary).get("Properties", {})
				if p is Dictionary:
					out.append(p)
	return out


func _run() -> void:
	print("P1_SAFE probe: safe room / portal / lantern (S12, KF14)")
	EscapeScript = load("res://src/interact/escape_gate.gd") as GDScript
	DressingScript = load("res://src/missions/safe_room_dressing.gd") as GDScript
	_check(EscapeScript != null and EscapeScript.can_instantiate(), "escape_gate.gd compiles")
	_check(DressingScript != null and DressingScript.can_instantiate(), "safe_room_dressing.gd compiles")
	var loader: Node = LevelLoaderScript.new()
	root.add_child(loader)
	await process_frame

	print("A. safe-room dressing build (authored meshes through the live loader)")
	var dressing: Node3D = DressingScript.new() as Node3D
	dressing.set("level_loader", loader)
	root.add_child(dressing)
	await process_frame

	_check(dressing != null and is_instance_valid(dressing), "dressing node instantiated")
	_check(str(dressing.name) == "SafeRoomDressing", "dressing node is named SafeRoomDressing (%s)" % str(dressing.name))
	_check(dressing.position.is_equal_approx(DressingScript.WALL_ANCHOR),
		"dressing anchored on the authored sconce wall face %s" % str(dressing.position))
	print("  report: ", str(dressing.call("report")))

	# --- 1. Portal wall outline ------------------------------------------------
	var portal: MeshInstance3D = dressing.get_node_or_null("SafeRoomPortalOutline") as MeshInstance3D
	_check(portal != null, "SafeRoomPortalOutline node exists")
	if portal != null:
		_check(portal.visible and portal.is_visible_in_tree(), "portal outline visible in the safe room")
		_check(portal.mesh is QuadMesh, "portal outline is a QuadMesh wall card")
		var quad: QuadMesh = portal.mesh as QuadMesh
		_check(quad != null and quad.size.is_equal_approx(EscapeScript.PORTAL_SIZE),
			"portal quad uses the authored SummonBox size %s" % str(EscapeScript.PORTAL_SIZE))
		_check(_near(portal.global_position.y - EscapeScript.PORTAL_SIZE.y * 0.5, DressingScript.WALL_ANCHOR.y),
			"portal base sits on the authored safe-room floor line (y=%.3f)" % (portal.global_position.y - EscapeScript.PORTAL_SIZE.y * 0.5))
		var mat: ShaderMaterial = portal.material_override as ShaderMaterial
		_check(mat != null, "portal has a ShaderMaterial override")
		if mat != null:
			_check(mat.shader != null and mat.shader.resource_path.find("tat_escape_portal") >= 0,
				"portal shader is tat_escape_portal (%s)" % (mat.shader.resource_path if mat.shader != null else "null"))
			var core: Variant = mat.get_shader_parameter("core_color")
			var edge: Variant = mat.get_shader_parameter("edge_color")
			_check(core is Color and _near_color(core as Color, 0.207843, 1.0, 0.329412),
				"portal core_color is BP_EscapePoint OpenColor #7EFF9B (%s)" % str(core))
			_check(edge is Color and _near_color(edge as Color, 0.561445, 0.083097, 1.0),
				"portal edge_color is BP_EscapePoint ClosedColor #C651FF (%s)" % str(edge))

	# --- 2. Lantern station ----------------------------------------------------
	var lantern: Node3D = dressing.get_node_or_null("SafeRoomLanternStation") as Node3D
	_check(lantern != null, "SafeRoomLanternStation node exists")
	var station_missing_meshes: int = int(lantern.get("missing_meshes")) if lantern != null else -1
	var station_missing_materials: int = int(lantern.get("missing_materials")) if lantern != null else -1
	_check(station_missing_meshes == 0, "lantern resolved every authored mesh (missing=%d)" % station_missing_meshes)
	_check(station_missing_materials == 0, "lantern resolved every authored material (missing=%d)" % station_missing_materials)
	if lantern != null:
		_check(lantern.is_in_group("interactables"), "lantern keeps the interactables group contract")
		var cage: MeshInstance3D = lantern.get("cage") as MeshInstance3D
		var flame: MeshInstance3D = lantern.get("flame") as MeshInstance3D
		var lamp: SpotLight3D = lantern.get("flame_light") as SpotLight3D
		var glass: Material = lantern.get("glass_material") as Material
		_check(cage != null and cage.mesh != null and cage.mesh.get_surface_count() == 2,
			"cage mesh SM_LanternGuardA bound with its 2 authored surfaces")
		if cage != null and cage.mesh != null and cage.mesh.get_surface_count() == 2:
			_check(cage.get_active_material(0) != null, "cage surface 0 material present (MI_LanternGuardA)")
			_check(cage.get_active_material(1) != null, "glass surface 1 material present (MI_LanternGuard_Glass_Yellow)")
		_check(flame != null and flame.mesh != null, "emissive flame shape resolved (SM_Sphere2Count)")
		_check(glass != null, "duplicated glass surface material present for the emission toggle")
		_check(lamp != null, "authored spot light present")
		if lamp != null:
			var want_energy: float = LevelLoaderScript.light_energy_for_intensity(5.0)
			_check(_near_color(lamp.light_color, 1.0, 0.539479, 0.184475),
				"spot colour is authored #FFC277 (%s)" % str(lamp.light_color))
			_check(_near(lamp.light_energy, want_energy, 0.0005),
				"spot energy maps authored 5.0 through the loader curve (%.4f)" % lamp.light_energy)
			_check(_near(lamp.spot_range, 4.5), "spot range is authored 450 cm (%.2f m)" % lamp.spot_range)
			_check(_near(lamp.spot_angle, 80.0), "spot cone is authored 80 deg (%.1f)" % lamp.spot_angle)
			_check(not lamp.shadow_enabled, "spot shadow off (authored LampCastShadow false)")
		_check(str(lantern.call("get_interact_prompt")) == "[F] TURN ON",
			"unlit prompt is [F] TURN ON (%s)" % str(lantern.call("get_interact_prompt")))
		_check(not bool(lantern.get("lit")) and lamp != null and not lamp.visible,
			"lantern starts unlit: light hidden")
		_check(flame != null and not flame.visible, "lantern starts unlit: flame shape hidden")
		var events: Array = []
		lantern.connect("toggled", func(on: bool) -> void: events.append(on))
		lantern.call("interact", null)
		_check(bool(lantern.get("lit")), "interact #1 lights the lantern")
		_check(lamp != null and lamp.visible, "interact #1 shows the warm spot")
		_check(flame != null and flame.visible, "interact #1 shows the emissive flame")
		_check(str(lantern.call("get_interact_prompt")) == "[F] TURN OFF",
			"lit prompt is [F] TURN OFF (%s)" % str(lantern.call("get_interact_prompt")))
		_check(_glass_emitting(glass), "interact #1 drives the glass emission on")
		lantern.call("interact", null)
		_check(not bool(lantern.get("lit")), "interact #2 turns the lantern off")
		_check(lamp != null and not lamp.visible, "interact #2 hides the warm spot")
		_check(flame != null and not flame.visible, "interact #2 hides the emissive flame")
		_check(not _glass_emitting(glass), "interact #2 drives the glass emission off")
		_check(str(lantern.call("get_interact_prompt")) == "[F] TURN ON",
			"prompt flips back to [F] TURN ON")
		_check(events.size() == 2 and events[0] == true and events[1] == false,
			"toggled signal fired on then off (%s)" % str(events))
		_check((lantern.call("get_interact_point") as Vector3).distance_to(lantern.global_position) >= 0.2,
			"interact point targets the lantern body, not the wall anchor")

	# --- 3. "SPIDER" flyer -----------------------------------------------------
	var flyer: MeshInstance3D = dressing.get_node_or_null("SafeRoomSpiderFlyer") as MeshInstance3D
	_check(flyer != null, "SafeRoomSpiderFlyer node exists")
	if flyer != null:
		_check(flyer.mesh != null, "flyer mesh resolved (SM_PosterWantedA)")
		_check(str(flyer.get_meta("ue_mesh", "")) == DressingScript.POSTER_UE_MESH,
			"flyer carries the authored mesh id (%s)" % str(flyer.get_meta("ue_mesh", "")))
		_check(flyer.get_active_material(0) != null, "flyer material present (MI_PosterWanted)")
		if flyer.mesh != null:
			var uvs: PackedVector2Array = flyer.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] as PackedVector2Array
			var u_max: float = 0.0
			var v_min: float = 1.0
			var v_max: float = 0.0
			for uv: Vector2 in uvs:
				u_max = maxf(u_max, uv.x)
				v_min = minf(v_min, uv.y)
				v_max = maxf(v_max, uv.y)
			_check(u_max > 0.30 and u_max < 0.34,
				"flyer UV window is the SPIDER column of T_PosterWanted_DA (umax=%.4f)" % u_max)
			_check(v_max - v_min > 0.40 and v_max - v_min < 0.50,
				"flyer UV window is one atlas row (dv=%.4f)" % (v_max - v_min))

	# --- B. endgame escape-gate contract unchanged ----------------------------
	print("B. escape-gate contract (portal visual + authored light + lifecycle)")
	var gate: Area3D = EscapeScript.new() as Area3D
	root.add_child(gate)
	await process_frame
	var gportal: MeshInstance3D = gate.get("portal_visual") as MeshInstance3D
	var glamp: OmniLight3D = gate.get("portal_light") as OmniLight3D
	_check(gportal != null and gportal.name == EscapeScript.PORTAL_NODE_NAME,
		"gate portal visual node is %s" % EscapeScript.PORTAL_NODE_NAME)
	_check(gportal != null and gportal.mesh is QuadMesh, "gate portal is a QuadMesh")
	_check(gportal != null and gportal.material_override is ShaderMaterial, "gate portal carries the portal shader")
	_check(gportal != null and glamp != null and not gportal.visible and not glamp.visible,
		"gate portal + light are hidden while dormant")
	if glamp != null:
		_check(_near_color(glamp.light_color, 0.7490196, 0.0, 1.0),
			"gate light is authored Door_Light #BF00FF (%s)" % str(glamp.light_color))
		_check(_near(glamp.light_energy, LevelLoaderScript.light_energy_for_intensity(30.0), 0.0005),
			"gate light maps authored 30 lm through the loader curve (%.4f)" % glamp.light_energy)
		_check(_near(glamp.omni_range, 4.5), "gate light range is authored 450 cm (%.2f m)" % glamp.omni_range)
		_check(not glamp.shadow_enabled and _near(glamp.light_volumetric_fog_energy, 0.0),
			"gate light shadow/fog off (authored 0 volumetric)")
	gate.call("activate")
	await process_frame
	_check(bool(gate.get("active")) and gportal.visible and glamp.visible,
		"activate() shows the portal + light")
	gate.call("expire")
	_check(bool(gate.get("expired")) and not gportal.visible and not glamp.visible,
		"expire() hides the portal + light")
	gate.call("activate")
	_check(glamp.visible, "re-arm shows the light again")
	gate.call("collapse")
	_check(bool(gate.get("collapsed")) and not gportal.visible and not glamp.visible,
		"collapse() hides the portal + light for good")
	_check(gate.find_children("*", "Label3D", true, false).is_empty(), "gate has no floating Label3D")
	var gshape: BoxShape3D = null
	for child: Node in gate.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			gshape = (child as CollisionShape3D).shape as BoxShape3D
	_check(gshape != null and gshape.size.is_equal_approx(Vector3(3.0, 3.0, 3.0)),
		"gate 3x3x3 trigger kept")

	# --- C. authored data still matches the hardcoded constants ---------------
	print("C. authored-data pins (read-only)")
	_authored_pins()

	loader.queue_free()
	dressing.queue_free()
	gate.queue_free()
	await process_frame
	print("P1_SAFE %s checks=%d fails=%d skips=%d" % [
		"PASS" if fails == 0 else "FAIL", checks, fails, skips])
	quit(0 if fails == 0 else 1)


func _glass_emitting(mat: Material) -> bool:
	if mat == null:
		return false
	if mat is StandardMaterial3D:
		var smat: StandardMaterial3D = mat as StandardMaterial3D
		return smat.emission_enabled and smat.emission_energy_multiplier > 0.0
	if mat is ShaderMaterial:
		var shmat: ShaderMaterial = mat as ShaderMaterial
		var scale: Variant = shmat.get_shader_parameter("hdr_scale")
		if scale is float:
			return float(scale) > 0.0
		var energy: Variant = shmat.get_shader_parameter("emission_energy")
		if energy is float:
			return float(energy) > 0.0
	return false


func _authored_pins() -> void:
	# BP_EscapePoint: colours, SummonBox size, Door_Light.
	var bp: Variant = _json(_extracted_root.path_join("Gameplay/Interactables/EscapePoints/BP_EscapePoint.json"))
	if bp == null:
		_skip("BP_EscapePoint.json not extracted")
	else:
		var root_props: Array = _bp_props(bp, "BP_EscapePoint_C")
		var found_open: bool = false
		var found_closed: bool = false
		for p: Dictionary in root_props:
			var oc: Variant = p.get("OpenColor")
			var cc: Variant = p.get("ClosedColor")
			if oc is Dictionary and _near_color(Color(float(oc.get("R")), float(oc.get("G")), float(oc.get("B"))), 0.207843, 1.0, 0.329412):
				found_open = true
			if cc is Dictionary and _near_color(Color(float(cc.get("R")), float(cc.get("G")), float(cc.get("B"))), 0.561445, 0.083097, 1.0):
				found_closed = true
		_check(found_open, "BP_EscapePoint.OpenColor is #7EFF9B (matches PORTAL_CORE_COLOR)")
		_check(found_closed, "BP_EscapePoint.ClosedColor is #C651FF (matches PORTAL_EDGE_COLOR)")
		var boxes: Array = _bp_props(bp, "BoxComponent")
		var found_box: bool = false
		for p: Dictionary in boxes:
			var ext: Variant = p.get("BoxExtent")
			if ext is Dictionary and _near(float(ext.get("X", 0.0)), 92.07361, 0.01) and _near(float(ext.get("Z", 0.0)), 119.341095, 0.01):
				found_box = true
		_check(found_box, "BP_EscapePoint.SummonBox Extent is 92.07361 x 119.341095 cm (matches PORTAL_SIZE)")
		var lights: Array = _bp_props(bp, "PointLightComponent")
		var found_light: bool = false
		for p: Dictionary in lights:
			var lc: Variant = p.get("LightColor")
			if lc is Dictionary and _near(int(lc.get("R", 0)), 191) and _near(int(lc.get("B", 0)), 255) \
					and _near(float(p.get("Intensity", 0.0)), 30.0) and _near(float(p.get("AttenuationRadius", 0.0)), 450.0):
				found_light = true
		_check(found_light, "BP_EscapePoint.Door_Light is #BF00FF 30 lm / 450 cm (matches PORTAL_LIGHT_*)")

	# BP_ToggleableLanternA: light + emissive + shadow defaults.
	var bp_lantern: Variant = _json(_extracted_root.path_join("Art/Environment/Lights/Mobile/BP_ToggleableLanternA.json"))
	if bp_lantern == null:
		_skip("BP_ToggleableLanternA.json not extracted")
	else:
		var lantern_props: Array = _bp_props(bp_lantern, "BP_ToggleableLanternA_C")
		var lp: Dictionary = lantern_props[0] if not lantern_props.is_empty() else {}
		_check(not lp.is_empty(), "BP_ToggleableLanternA class defaults present")
		if not lp.is_empty():
			_check(_near(float(lp.get("LightIntensity", 0.0)), 5.0), "authored LightIntensity 5.0")
			_check(_near(float(lp.get("AttenuationRadius", 0.0)), 450.0), "authored AttenuationRadius 450 cm")
			_check(_near(float(lp.get("OuterConeAngle", 0.0)), 80.0), "authored OuterConeAngle 80 deg")
			_check(_near(float(lp.get("EmissiveMaterialStrength", 0.0)), 6.0), "authored EmissiveMaterialStrength 6.0")
			_check(bool(lp.get("LampCastShadow", true)) == false, "authored LampCastShadow false")
			var lc2: Variant = lp.get("LightColor")
			_check(lc2 is Dictionary and _near_color(Color(float(lc2.get("R")), float(lc2.get("G")), float(lc2.get("B"))), 1.0, 0.539479, 0.184475),
				"authored LightColor #FFC277")
			var sc: Variant = lp.get("EmisShapeColor")
			_check(sc is Dictionary and _near_color(Color(float(sc.get("R")), float(sc.get("G")), float(sc.get("B"))), 1.0, 0.626611, 0.270833),
				"authored EmisShapeColor #FFD08E")

	# Prompt strings.
	var st: Variant = _json("res://data/generated/tables/StringTables/ST_Interactables.json")
	if st is Dictionary:
		var entries: Dictionary = (st as Dictionary).get("entries", {})
		_check(str(entries.get("PromptTurnOn", "")) == "Turn On", "ST_Interactables.PromptTurnOn is 'Turn On'")
		_check(str(entries.get("PromptTurnOff", "")) == "Turn Off", "ST_Interactables.PromptTurnOff is 'Turn Off'")
	else:
		_skip("ST_Interactables.json missing")

	_authored_pin_safe_room()


## The safe room's brick wall + oval sconce and the Contract-02 spawn pose are
## authored level rows. They are not spawned by the dressing (the loader builds
## them), so pin the rows the probe's anchors depend on.
func _authored_pin_safe_room() -> void:
	var periph: Variant = _json(LEVELS + "Guildhall/Guildhall_PeripheryA.tatlevel.json")
	if periph is Dictionary:
		var meshes: Array = (periph as Dictionary).get("meshes", [])
		var wall: bool = false
		var sconce: bool = false
		for m_v: Variant in meshes:
			if not (m_v is Dictionary):
				continue
			var m: Dictionary = m_v as Dictionary
			var mesh_path: String = str(m.get("mesh", ""))
			var ov: Variant = m.get("override_material")
			var pos: Variant = m.get("pos", [])
			if mesh_path.ends_with("SM_WallLightB") and ov is String and str(ov).ends_with("MI_LightsSetD"):
				if pos is Array and (pos as Array).size() >= 3 \
						and _near(float((pos as Array)[0]), 126.29, 0.01) \
						and _near(float((pos as Array)[1]), 27.14, 0.01) \
						and _near(float((pos as Array)[2]), -2.28, 0.01):
					sconce = true
			if mesh_path.ends_with("SM_Urban_Ext_Wall_4x6"):
				if pos is Array and (pos as Array).size() >= 3 and _near(float((pos as Array)[2]), -2.02, 0.01):
					wall = true
		_check(wall, "authored brick wall panel on the safe-room south wall (SM_Urban_Ext_Wall_4x6 at z=-2.02)")
		_check(sconce, "authored oval sconce at 126.29, 27.14, -2.28 (SM_WallLightB + MI_LightsSetD)")
		var lantern_bp: int = 0
		for a_v: Variant in (periph as Dictionary).get("actors", []):
			if a_v is Dictionary and str((a_v as Dictionary).get("class", "")) == "BP_ToggleableLanternA_C":
				lantern_bp += 1
		_check(lantern_bp >= 1, "authored BP_ToggleableLanternA instances present in PeripheryA (%d)" % lantern_bp)
		# The mesh/material join the lantern and flyer rely on.
		var mm: Variant = _json("res://data/generated/mesh_materials.json")
		if mm is Dictionary:
			var wall_slots: Variant = (mm as Dictionary).get("/Game/Art/Environment/Urban/Walls/SM_Urban_Ext_Wall_4x6")
			_check(wall_slots is Array and (wall_slots as Array).size() >= 1 \
					and str((wall_slots as Array)[0]).ends_with("MI_Urban_Ext_Stone"),
				"SM_Urban_Ext_Wall_4x6 slot 0 is the brick MI_Urban_Ext_Stone")
			var sconce_slots: Variant = (mm as Dictionary).get("/Game/Art/Environment/Lights/Wall/SM_WallLightB")
			_check(sconce_slots is Array and (sconce_slots as Array).size() == 1 \
					and str((sconce_slots as Array)[0]).ends_with("MI_LightsSetA"),
				"SM_WallLightB authors MI_LightsSetA (instance overrides to MI_LightsSetD)")
			var lantern_slots: Variant = (mm as Dictionary).get("/Game/Art/Environment/Lights/Mobile/SM_LanternGuardA")
			_check(lantern_slots is Array and (lantern_slots as Array).size() == 2,
				"SM_LanternGuardA authors 2 material slots (cage + glass)")
			var poster_slots: Variant = (mm as Dictionary).get(DressingScript.POSTER_UE_MESH)
			_check(poster_slots is Array and (poster_slots as Array).size() == 1 \
					and str((poster_slots as Array)[0]).ends_with("MI_PosterWanted"),
				"SM_PosterWantedA authors MI_PosterWanted")
		else:
			_skip("mesh_materials.json missing")
	else:
		_skip("Guildhall_PeripheryA.tatlevel.json missing")
	var gameplay: Variant = _json(LEVELS + "Guildhall/Guildhall_Gameplay.tatlevel.json")
	if gameplay is Dictionary:
		var spawn: bool = false
		for m_v: Variant in (gameplay as Dictionary).get("markers", []):
			if m_v is Dictionary and str((m_v as Dictionary).get("name", "")) == "TATSafeRoomPlayerStart_0":
				var pos: Variant = (m_v as Dictionary).get("pos", [])
				if pos is Array and (pos as Array).size() >= 3 \
						and _near(float((pos as Array)[0]), 127.2747, 0.01) \
						and _near(float((pos as Array)[1]), 25.4694, 0.01) \
						and _near(float((pos as Array)[2]), -5.3296, 0.01):
					spawn = true
		_check(spawn, "Contract-02 spawn pose TATSafeRoomPlayerStart_0 at 127.2747, 25.4694, -5.3296")
	else:
		_skip("Guildhall_Gameplay.tatlevel.json missing")
