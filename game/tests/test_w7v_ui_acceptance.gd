extends SceneTree
## W7V focused structural checks:
##   * Wardrobe defaults (BowlerA / Default / Default, not alphabetic AltA).
##   * Chameleon = authored ThiefCotter body/head; 18/18 Head rows mapped,
##     including the documented TopHatA.MonocleA combined-beard fallback.
##   * Cotter wardrobe idle clip.
##   * KF11 prep: tracked expansion skyline spawns from the JSON, is marked
##     expansion, has no collision, and does not occlude the moon sample ray;
##     moon disc at (0.76, 0.09), thief centre in 0.70-0.84, ridge lower third.
##   * Ledger Black Market: one live 3D tool stage, tool rows show it, non-tool
##     rows fall back to the authored icon, and closing frees the stage.
##
## Run headless:
##   tools/godot --headless --path game --script res://tests/test_w7v_ui_acceptance.gd

## Loaded at runtime (not preloaded): these scripts reference GameState /
## AudioManager autoloads, which do not exist during the SceneTree parse pass.
var WARDROBE_SCRIPT: GDScript = null
var LEDGER_SCRIPT: GDScript = null
var PREP_SCRIPT: GDScript = null
const SKYLINE_PATH: String = "res://data/expansion/prep_skyline.json"
const OUTFITS_PATH: String = "res://data/generated/tables/Character/Player/DT_CharacterOutfitsMetadata.json"

var fails: int = 0
var checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _wait(n: int) -> void:
	for _i: int in range(n):
		await process_frame

func _check(ok: bool, what: String, detail: String = "") -> void:
	checks += 1
	if ok:
		print("PASS: ", what)
	else:
		fails += 1
		printerr("FAIL: ", what, (" | " + detail) if detail != "" else "")

func _rows() -> Dictionary:
	var f: FileAccess = FileAccess.open(OUTFITS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return {}
	var d: Dictionary = parsed as Dictionary
	var r: Variant = d.get("rows", {})
	return r as Dictionary if r is Dictionary else {}

func _run() -> void:
	WARDROBE_SCRIPT = load("res://src/ui/wardrobe_ui.gd") as GDScript
	LEDGER_SCRIPT = load("res://src/ui/ledger_ui.gd") as GDScript
	PREP_SCRIPT = load("res://src/ui/mission_prep_ui.gd") as GDScript
	if WARDROBE_SCRIPT == null or LEDGER_SCRIPT == null or PREP_SCRIPT == null:
		printerr("FAIL: UI scripts did not load")
		quit(1)
		return
	await _wardrobe_checks()
	await _prep_checks()
	await _ledger_checks()
	print("W7V_SUMMARY: fails=%d checks=%d" % [fails, checks])
	quit(1 if fails > 0 else 0)

# --- Wardrobe / Chameleon -------------------------------------------------

func _wardrobe_checks() -> void:
	var save: Node = root.get_node_or_null("/root/SaveSystem")
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("thief_id", "spider")
	var wd: CanvasLayer = WARDROBE_SCRIPT.new() as CanvasLayer
	root.add_child(wd)
	await _wait(4)
	_check(str(wd.get("_thief_id")) == "spider", "W7V.1 wardrobe opens on the Spider",
		"thief=%s" % str(wd.get("_thief_id")))
	_check(str(wd.get("_head")) == "Outfit.Spider.Head.BowlerA",
		"W7V.2 Spider default head is BowlerA, not alphabetic AltA (%s)" % str(wd.get("_head")))
	_check(str(wd.get("_body")) == "Outfit.Spider.Body.Default",
		"W7V.3 Spider default body is Default, not AltA/Tarantula (%s)" % str(wd.get("_body")))
	_check(str(wd.get("_card")) == "Outfit.Spider.CallingCard.Default",
		"W7V.4 Spider default calling card is Default (%s)" % str(wd.get("_card")))
	_check(str(wd.get("_body")).find("AltA") < 0 and str(wd.get("_head")).find("AltA") < 0,
		"W7V.5 neither default is the alphabetic first row")
	var body_path_s: String = str(wd.call("_resolve_body_path", "Outfit.Spider.Body.Default"))
	var head_path_s: String = str(wd.call("_resolve_head_path", "Outfit.Spider.Head.BowlerA"))
	_check(body_path_s.find("ThiefNisha") >= 0 and head_path_s.find("ThiefNisha") >= 0,
		"W7V.6 the Spider still renders on the Nisha meshes",
		"body=%s head=%s" % [body_path_s, head_path_s])

	# Chameleon: authored Contract-3 perk is enough for the panel switcher.
	if save != null:
		var data: Dictionary = save.get("data") as Dictionary
		if data != null:
			var perks: Array = data.get("unlocked_perks", [])
			if not perks.has("chameleon"):
				perks.append("chameleon")
			data["unlocked_perks"] = perks
	wd.call("_cycle_thief", 1)
	await _wait(6)
	_check(str(wd.get("_thief_id")) == "chameleon", "W7V.7 Q/E switches to the Chameleon",
		"thief=%s" % str(wd.get("_thief_id")))
	_check(str(wd.get("_head")) == "Outfit.Chameleon.Head.BowlerA",
		"W7V.8 Chameleon default head is BowlerA (%s)" % str(wd.get("_head")))
	_check(str(wd.get("_body")) == "Outfit.Chameleon.Body.Default",
		"W7V.9 Chameleon default body is Default (%s)" % str(wd.get("_body")))
	_check(str(wd.get("_card")) == "Outfit.Chameleon.CallingCard.Default",
		"W7V.10 Chameleon default calling card is Default (%s)" % str(wd.get("_card")))
	var body_path: String = str(wd.call("_resolve_body_path", "Outfit.Chameleon.Body.Default"))
	var body_alt: String = str(wd.call("_resolve_body_path", "Outfit.Chameleon.Body.AltA"))
	var body_alt_b: String = str(wd.call("_resolve_body_path", "Outfit.Chameleon.Body.AltA.PatternB"))
	_check(body_path.find("ThiefCotter") >= 0 and body_path.find("ThiefNisha") < 0,
		"W7V.11 Chameleon body is ThiefCotter, not Nisha (%s)" % body_path)
	_check(body_alt.find("ThiefCotter_AltA") >= 0 and body_alt_b.find("PatternB") >= 0,
		"W7V.12 Chameleon AltA / PatternB body meshes resolve to Cotter",
		"alt=%s altB=%s" % [body_alt, body_alt_b])
	_check(ResourceLoader.exists(body_path), "W7V.13 Chameleon default body GLB exists on disk (%s)" % body_path)

	var rows: Dictionary = _rows()
	var head_keys: Array[String] = []
	for key_v: Variant in rows.keys():
		var key: String = str(key_v)
		if key.begins_with("Outfit.Chameleon.Head."):
			head_keys.append(key)
	head_keys.sort()
	_check(head_keys.size() == 18, "W7V.14 the authored table has 18 Chameleon Head rows (%d)" % head_keys.size(),
		"%s" % str(head_keys))
	var mapped: int = 0
	var resolved: int = 0
	var missing: Array[String] = []
	for key: String in head_keys:
		var map_v: Variant = WARDROBE_SCRIPT.COTTER_HEAD_MESHES.get(key, null)
		if map_v != null:
			mapped += 1
		else:
			missing.append(key)
			continue
		var path: String = str(wd.call("_resolve_head_path", key))
		if path.find("ThiefCotter") >= 0 and ResourceLoader.exists(path):
			resolved += 1
		else:
			missing.append(key + " -> " + path)
	_check(mapped == 18, "W7V.15 all 18 Chameleon Head rows have a Cotter mapping (%d)" % mapped,
		"missing=%s" % str(missing))
	_check(resolved == 18, "W7V.16 all 18 resolve to an existing Cotter GLB (%d)" % resolved,
		"missing=%s" % str(missing))
	var combined: String = str(WARDROBE_SCRIPT.COTTER_HEAD_MESHES.get("Outfit.Chameleon.Head.TopHatA.MonocleA", ""))
	_check(combined == "SK_ThiefCotter__Head_TopHatA_MonocleA_BeardA.glb",
		"W7V.17 TopHatA.MonocleA uses the documented combined-beard mesh (%s)" % combined)
	_check(str(wd.call("_resolve_head_path", "Outfit.Chameleon.Head.BowlerA")).find("ThiefCotter") >= 0,
		"W7V.18 Chameleon BowlerA head is a Cotter mesh")
	var wd_src: String = FileAccess.get_file_as_string("res://src/ui/wardrobe_ui.gd")
	_check(wd_src.find("AN_ThiefCotter_WardrobeIdle") >= 0,
		"W7V.19 Chameleon preview plays the authored Cotter wardrobe idle")
	var anims: String = FileAccess.get_file_as_string("res://data/generated/anims_meta.json")
	_check(anims.find("AN_ThiefCotter_WardrobeIdle") >= 0,
		"W7V.20 AN_ThiefCotter_WardrobeIdle exists in the animation manifest")
	# KF03 stays a three-column layout with no APPLY button.
	var three_col: bool = false
	for c: Node in wd.find_children("*", "HBoxContainer", true, false):
		var hb: HBoxContainer = c as HBoxContainer
		if hb.get_child_count() == 3 and hb.get_child(0) is VBoxContainer \
				and hb.get_child(1) is VBoxContainer and hb.get_child(2) is PanelContainer:
			three_col = true
			break
	var apply: int = 0
	for b: Node in wd.find_children("*", "Button", true, false):
		if (b as Button).text.strip_edges().to_upper() == "APPLY":
			apply += 1
	_check(three_col and apply == 0, "W7V.21 Wardrobe keeps the 3-column KF03 layout and no APPLY",
		"three_col=%s apply=%d" % [str(three_col), apply])
	wd.queue_free()
	await _wait(3)

# --- KF11 prep stage ------------------------------------------------------

func _load_skyline() -> Dictionary:
	var f: FileAccess = FileAccess.open(SKYLINE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed as Dictionary if parsed is Dictionary else {}

func _screen_frac(cam: Camera3D, p: Vector3) -> Vector2:
	var vp: Vector2 = Vector2(cam.get_viewport().size)
	if vp.x <= 0.0 or vp.y <= 0.0:
		return Vector2(-1, -1)
	return cam.unproject_position(p) / vp

func _prep_checks() -> void:
	var data: Dictionary = _load_skyline()
	_check(not data.is_empty(), "W7V.22 tracked prep skyline JSON loads")
	_check(str(data.get("schema", "")) == "tat2.prep_skyline/1" and bool(data.get("expansion", false)),
		"W7V.23 skyline layout declares schema + expansion:true")
	_check(str(data.get("source", "")).to_lower().find("expansion") >= 0,
		"W7V.24 skyline layout names itself TAT-2 expansion content")
	var pieces: Array = data.get("pieces", []) as Array
	_check(pieces.size() >= 6, "W7V.25 skyline has a full distant-city set (%d pieces)" % pieces.size())
	var shipped: int = 0
	var ids: Dictionary = {}
	for p_v: Variant in pieces:
		var p: Dictionary = p_v as Dictionary
		var mesh: String = str(p.get("mesh", ""))
		if mesh.begins_with("/Game/Art/Environment/Skybox/"):
			shipped += 1
		ids[str(p.get("id", ""))] = true
	_check(shipped == pieces.size(), "W7V.26 every skyline mesh reuses a shipped Skybox asset (%d/%d)" % [shipped, pieces.size()])
	_check(ids.size() == pieces.size(), "W7V.27 skyline piece ids are unique (%d)" % ids.size())

	var mp: Control = PREP_SCRIPT.new() as Control
	mp.size = Vector2(1280, 720)
	root.add_child(mp)
	await _wait(3)
	mp.call("open_prep", "guildhall", 1, "Solo", 0, false)
	var cam: Camera3D = null
	for _i: int in range(900):
		cam = mp.find_child("MissionLobbyCamera", true, false) as Camera3D
		if cam != null:
			break
		await process_frame
	await _wait(20)
	_check(cam != null, "W7V.28 prep stage camera built")
	if cam == null:
		mp.queue_free()
		return
	_check(absf(cam.fov - 20.0) < 0.01 and cam.keep_aspect == Camera3D.KEEP_WIDTH,
		"W7V.29 authored FOV 20 / KEEP_WIDTH kept",
		"fov=%.2f keep=%d" % [cam.fov, cam.keep_aspect])
	var sky_nodes: Array[Node] = mp.find_children("PrepSkyline_*", "MeshInstance3D", true, false)
	_check(sky_nodes.size() == pieces.size(),
		"W7V.30 prep skyline spawns every tracked piece (%d/%d)" % [sky_nodes.size(), pieces.size()])
	var bad_group: int = 0
	var bad_meta: int = 0
	var collision: int = 0
	var shadow: int = 0
	for n: Node in sky_nodes:
		var mi: MeshInstance3D = n as MeshInstance3D
		if not mi.is_in_group("prep_skyline"):
			bad_group += 1
		if not bool(mi.get_meta("expansion", false)):
			bad_meta += 1
		if not mi.get_children().is_empty():
			collision += 1
		if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow += 1
		if mi.mesh == null:
			collision += 1
	_check(bad_group == 0, "W7V.31 every skyline piece is in the prep_skyline group", "bad=%d" % bad_group)
	_check(bad_meta == 0, "W7V.32 every skyline piece carries meta expansion=true", "bad=%d" % bad_meta)
	_check(collision == 0, "W7V.33 skyline pieces are decorative (no children/collision, mesh present)", "bad=%d" % collision)
	_check(shadow == 0, "W7V.34 skyline pieces cast no shadows", "bad=%d" % shadow)
	_check(mp.find_children("PrepSkyline_*", "StaticBody3D", true, false).is_empty()
			and mp.find_children("PrepSkyline_*", "CollisionShape3D", true, false).is_empty(),
		"W7V.35 no StaticBody/CollisionShape under the skyline")

	var env: Environment = null
	for n: Node in mp.find_children("*", "WorldEnvironment", true, false):
		var we: WorldEnvironment = n as WorldEnvironment
		if we.environment != null:
			env = we.environment
			break
	var disc: Vector3 = Vector3.ZERO
	if env != null and env.sky != null and env.sky.sky_material is ShaderMaterial:
		disc = (env.sky.sky_material as ShaderMaterial).get_shader_parameter("moon_direction") as Vector3
	_check(disc.length() > 0.5, "W7V.36 stage sky exposes a moon disc direction")
	var moon_s: Vector2 = _screen_frac(cam, cam.global_position + disc * 1000.0)
	_check(absf(moon_s.x - 0.76) < 0.03 and absf(moon_s.y - 0.09) < 0.03,
		"W7V.37 moon disc lands at KF11 (0.76, 0.09): (%.3f, %.3f)" % [moon_s.x, moon_s.y],
		"screen=(%.3f, %.3f)" % [moon_s.x, moon_s.y])

	# Moon sample ray must not pass through any expansion skyline piece.
	var occluders: Array[String] = []
	for n: Node in sky_nodes:
		var mi: MeshInstance3D = n as MeshInstance3D
		var box: AABB = mi.global_transform * mi.get_aabb()
		if box.has_point(cam.global_position):
			continue
		if box.intersects_ray(cam.global_position, disc) != null:
			occluders.append(mi.name)
	_check(occluders.is_empty(), "W7V.38 skyline does not occlude the moon sample ray",
		"occluders=%s" % str(occluders))

	# Thief framing: body centre 0.70-0.84, feet in the lower third.
	var anchor: Node3D = mp.find_child("MissionLobbyThiefAnchor", true, false) as Node3D
	var body: MeshInstance3D = null
	if anchor != null:
		for n2: Node in anchor.find_children("*", "MeshInstance3D", true, false):
			body = n2 as MeshInstance3D
			if body != null and body.mesh != null:
				break
	_check(body != null, "W7V.39 prep thief body is present")
	if body != null:
		var mb: AABB = body.global_transform * body.get_aabb()
		var mn := Vector2(9, 9)
		var mx := Vector2(-9, -9)
		for i: int in 8:
			var s: Vector2 = _screen_frac(cam, mb.get_endpoint(i))
			mn = Vector2(minf(mn.x, s.x), minf(mn.y, s.y))
			mx = Vector2(maxf(mx.x, s.x), maxf(mx.y, s.y))
		# The skinned rest AABB is a T-pose (arms wide) and is centred on the
		# mesh pivot, not the subject; project the dummy's chest instead.
		var centre: Vector2 = _screen_frac(cam, (mp.find_child("MissionLobbyThiefAnchor", true, false) as Node3D).global_position + Vector3(0.0, 0.9, 0.0))
		var centre_x: float = centre.x
		_check(centre_x >= 0.70 and centre_x <= 0.84,
			"W7V.40 thief centre x in the KF11 band 0.70-0.84 (%.3f)" % centre_x,
			"chest=(%.3f,%.3f) bbox x %.3f..%.3f" % [centre.x, centre.y, mn.x, mx.x])
		_check(mx.y >= 0.66,
			"W7V.41 thief feet/body reach the lower third (bottom %.3f)" % mx.y,
			"bbox y %.3f..%.3f" % [mn.y, mx.y])
	_check(str(FileAccess.get_file_as_string("res://src/ui/mission_prep_ui.gd")).find("midnight_clear_mission_lobby") >= 0,
		"W7V.42 prep stage stays on midnight_clear_mission_lobby")
	mp.queue_free()
	await _wait(3)

# --- Ledger Black Market 3D preview ---------------------------------------

func _ledger_checks() -> void:
	var led: Control = LEDGER_SCRIPT.new() as Control
	led.size = Vector2(1280, 720)
	root.add_child(led)
	await _wait(6)
	var stage: Node3D = led.get("_tool_stage") as Node3D
	var view: SubViewportContainer = led.get("_preview_tool_view") as SubViewportContainer
	var icon: TextureRect = led.get("_preview_icon") as TextureRect
	_check(stage != null and view != null and icon != null,
		"W7V.43 Black Market builds one 3D tool preview stage")
	var stages: int = 0
	for n: Node in led.find_children("*", "ToolPreviewStage", true, false):
		stages += 1
	_check(stages == 1, "W7V.44 exactly one ToolPreviewStage exists (%d)" % stages)
	led.call("_on_item_pressed", "zipwire")
	await _wait(4)
	_check(view != null and view.visible and icon != null and not icon.visible,
		"W7V.45 a tool row shows the live viewport instead of the icon")
	var has_mesh: bool = stage != null and bool(stage.call("has_mesh"))
	var holder: Node3D = null
	if stage != null:
		holder = stage.get("holder") as Node3D
	_check(has_mesh and holder != null and holder.get_child_count() >= 1,
		"W7V.46 Zipwire loads its authored gear mesh into the preview")
	led.call("_on_item_pressed", "novice_difficulty")
	await _wait(4)
	_check(view != null and not view.visible and icon != null and icon.visible,
		"W7V.47 a non-tool row falls back to the authored reward icon")
	_check(stage != null and not bool(stage.call("has_mesh")),
		"W7V.48 the non-tool fallback clears the stale 3D model")
	led.call("_on_item_pressed", "zipwire")
	await _wait(2)
	led.call("_close_ui")
	await _wait(4)
	_check(stage == null or not is_instance_valid(stage),
		"W7V.49 closing the Black Market frees the tool preview stage")
