extends SceneTree
## W7H surface-resolved hearing + swing-door noise + indoor weather scope.
##
## Run:
##   XDG_DATA_HOME=/tmp/opencode/w7h-data tools/godot --headless --path game \
##     --script res://tests/test_w7h_surface_hearing.gd
##
## What this pins:
##   * the geometric surface resolver: a down-ray onto the authored collider
##     (per-shape `ue_mesh` from the level loader, node overrides, material /
##     mesh-name rules) yields one of the 22 authored DA_LoudnessModifiers rows;
##     an unknown collider is stone, never a crash;
##   * the full hearing matrix: 22 surfaces x {crouch, walk, run} x weather
##     {1.0, 0.9, 0.8} -> radius = min(stim x surface, 25 m x weather) exactly,
##     heard at the radius and silent 0.01 m past it;
##   * the silent faces (carpet, foliage, ivy, grass, dirt -> 0.0), the hard
##     faces (glass/stone/metal/wood 1.5) and the medium faces (lattice/tile 1.0);
##   * an unknown/empty surface stays at 1.0 (never 0);
##   * 3D distance: a sprint 15 m below the guard is heard through the roof
##     plane by 3D distance, and a 21.2 m 3D / 15 m planar sprint is not heard
##     (so no planar-only sum and no invented floor occlusion);
##   * negative controls: astral source, knocked-out guard;
##   * the SEARCH timer refresh on repeated noise (it used to keep decaying);
##   * LockPicking.Picked 3 m vs LockPicking.Jammed 10 m;
##   * exactly one OpeningCreak (5 m) per swing toggle, none double-fired by the
##     lock path;
##   * indoor weather scope: Old Manor/Jaspering interiors use the authored 1.0
##     under a ceiling, 0.9/0.8 in the open (the Den stays indoor everywhere).

const HearingData := preload("res://src/ai/hearing_data.gd")
const WeatherProfile := preload("res://src/core/weather_profile.gd")
const SurfaceResolver := preload("res://src/stealth/surface_resolver.gd")
## The door script references the NoiseBus autoload, which is not registered when
## a `--script` main script is compiled: load it at runtime (repo rule).
var SwingingDoorScript: GDScript = null

const GUARD_SENSE_RANGE_M: float = 25.0
## guard_ai.Alertness: NEUTRAL 0, SUSPICIOUS 1, ALERTED 2, COMBAT 3, SEARCH 4,
## KNOCKED_OUT 5 (the enum declares SEARCH after COMBAT, not before).
const STATE_SEARCH: int = 4
## Emitter loudness per gait: the player's own values (thief_character.gd), which
## NoiseBus.resolve_gait maps to crouch/walk/run when no source flags exist.
const GAIT_LOUDNESS: Dictionary = {"crouch": 1.5, "walk": 3.5, "run": 8.0}
const GAITS: Array[String] = ["crouch", "walk", "run"]
const WEATHER_MAPS: Array[Dictionary] = [
	{"map": "guildhall", "mult": 1.0, "label": "clear 1.0"},
	{"map": "old_manor", "mult": 0.9, "label": "dense fog 0.9"},
	{"map": "jaspering_hall", "mult": 0.8, "label": "heavy rain 0.8"},
]
const SILENT_SURFACES: Array[String] = ["Carpet", "Foliage", "Ivy", "Grass", "Dirt"]
const HARD_SURFACES: Array[String] = ["Stone", "Glass", "GlassHorizontal", "BrokenGlass", "MetalThick", "MetalPipe", "MetalSheet", "MetalGrate", "MetalVehicle", "WoodFloor", "WoodBeam", "WoodObject", "Puddle", "GroundWet", "ElectricalWire"]
const MEDIUM_SURFACES: Array[String] = ["Lattice", "Tile"]

var fails: int = 0
var checks: int = 0
var GuardScript: GDScript = null
var _saved_map_id: String = ""
var _saved_contract: int = 1
var _matrix_cases: int = 0


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	checks += 1
	if cond:
		print("PASS: ", ok_msg)
	else:
		printerr("FAIL: ", fail_msg)
		fails += 1


func _approx(a: float, b: float, eps: float = 0.0005) -> bool:
	return absf(a - b) <= eps


func _initialize() -> void:
	await process_frame
	GuardScript = load("res://src/ai/guard_ai.gd") as GDScript
	SwingingDoorScript = load("res://src/interact/swinging_door.gd") as GDScript
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		_saved_map_id = str(gs.get("active_map_id"))
		_saved_contract = int(gs.get("active_contract_order"))
		gs.set("state", "playing")
	HearingData.reload_cache()
	_test_resolver_names()
	await _test_resolver_geometry()
	await _test_footstep_surface()
	await _test_matrix()
	await _test_boundaries()
	await _test_3d_and_negative_controls()
	await _test_search_refresh()
	await _test_lockpick_split()
	await _test_swing_door_creak()
	await _test_indoor_scope()
	if gs != null:
		gs.set("active_map_id", _saved_map_id)
		gs.set("active_contract_order", _saved_contract)
	_finish()


func _finish() -> void:
	var am: Node = root.get_node_or_null("AudioManager")
	if am != null and am.has_method("cleanup_on_exit"):
		am.call("cleanup_on_exit")
	print("W7H_HEARING_SUMMARY: fails=", fails, " checks=", checks, " matrix_cases=", _matrix_cases)
	quit(0 if fails == 0 else 1)


# ---------------------------------------------------------------- resolver

## All 22 authored surfaces are reachable by name, and every one maps onto one of
## the seven AudioManager pool tokens.
func _test_resolver_names() -> void:
	var names: Array = SurfaceResolver.CANONICAL.values()
	var missing: Array[String] = []
	for n: Variant in names:
		if SurfaceResolver.canonical(str(n)) == "":
			missing.append(str(n))
	var tokens: Array[String] = []
	var bad_token: Array[String] = []
	var audio: Dictionary = SurfaceResolver.AUDIO_TOKEN
	for n2: Variant in names:
		var tok: String = SurfaceResolver.audio_token(str(n2))
		if not (tok in ["wood", "stone", "carpet", "metal", "wet", "earth", "glass"]):
			bad_token.append(str(n2) + "->" + tok)
		if not (tok in tokens):
			tokens.append(tok)
	_check(names.size() == 22 and missing.is_empty(),
		"W7H.1 all 22 authored surfaces resolve by name (%d rows)" % names.size(),
		"W7H.1 unreachable surface names: " + str(missing))
	_check(audio.size() == 22 and bad_token.is_empty() and tokens.size() == 7,
		"W7H.2 every authored surface maps onto one of the 7 AudioManager tokens (%d tokens used)" % tokens.size(),
		"W7H.2 audio token problems: " + str(bad_token) + " used=" + str(tokens))
	var alias_ok: bool = SurfaceResolver.canonical("wood") == "WoodFloor" \
		and SurfaceResolver.canonical("metal") == "MetalThick" \
		and SurfaceResolver.canonical("earth") == "Dirt" \
		and SurfaceResolver.canonical("wet") == "Puddle" \
		and SurfaceResolver.canonical("carpet") == "Carpet"
	_check(alias_ok,
		"W7H.3 the seven port tokens alias to their authored rows (wood->WoodFloor, metal->MetalThick, earth->Dirt, wet->Puddle)",
		"W7H.3 token alias mismatch")
	var rules: Dictionary = {
		"/Game/Art/Environment/Props/Rugs/SM_Rug_A": "Carpet",
		"/Game/Art/Environment/City/Ground/SM_CobbleSlab_A": "Stone",
		"/Game/Art/Environment/City/Ground/SM_GrassPatch_A": "Grass",
		"/Game/Art/Environment/City/Ground/SM_DirtPath_A": "Dirt",
		"/Game/Art/Environment/OldManor/Marble/MarbleFloor_A": "Stone",
		"/Game/Art/Environment/Props/Windows/SM_WindowGlass_A": "Glass",
		"/Game/Art/Environment/City/Roofs/SM_Skylight_A": "GlassHorizontal",
		"/Game/Art/Environment/Props/SM_WoodBeam_A": "WoodBeam",
		"/Game/Art/Environment/Props/SM_Crate_A": "WoodObject",
		"/Game/Art/Environment/Props/SM_MetalGrate_A": "MetalGrate",
		"/Game/Art/Environment/Props/SM_TrellisLattice_A": "Lattice",
		"/Game/Art/Environment/Props/SM_CableRun_A": "ElectricalWire",
		"/Game/Art/Environment/City/Ground/SM_TilePath_A": "Tile",
	}
	var wrong: Array[String] = []
	for path: String in rules.keys():
		var got: String = SurfaceResolver.surface_from_name(path)
		if got != str(rules[path]):
			wrong.append("%s -> %s (want %s)" % [path.get_file(), got, str(rules[path])])
	_check(wrong.is_empty(),
		"W7H.4 mesh/material name rules resolve the authored faces (%d samples)" % rules.size(),
		"W7H.4 name rules wrong: " + str(wrong))
	var fallback_ok: bool = SurfaceResolver.resolve_text("SM_SomethingUnknown") == "Stone" \
		and SurfaceResolver.resolve_text("") == "Stone" \
		and SurfaceResolver.surface_from_name("SM_SomethingUnknown") == "" \
		and SurfaceResolver.audio_token("SM_SomethingUnknown") == "stone"
	_check(fallback_ok,
		"W7H.5 unknown/empty names fall back to stone (never a crash, never a silent 1.0)",
		"W7H.5 fallback wrong")


## A ray onto real collider shapes: the level loader's per-shape `ue_mesh`, an
## explicit override, and a collider with no evidence at all.
func _test_resolver_geometry() -> void:
	var rig := Node3D.new()
	root.add_child(rig)
	rig.global_position = Vector3(0.0, 0.0, 300.0)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	rig.add_child(body)
	# Two shapes in one batched body (the loader's LevelCollision_* shape),
	# distinguished only by the CollisionShape3D `ue_mesh` meta.
	var carpet := BoxShape3D.new()
	carpet.size = Vector3(2.0, 0.4, 2.0)
	var stone := BoxShape3D.new()
	stone.size = Vector3(2.0, 0.4, 2.0)
	var cs_a := CollisionShape3D.new()
	cs_a.shape = carpet
	cs_a.position = Vector3(-5.0, 0.0, 0.0)
	cs_a.set_meta("ue_mesh", "/Game/Art/Environment/Props/Rugs/SM_Rug_A")
	body.add_child(cs_a)
	var cs_b := CollisionShape3D.new()
	cs_b.shape = stone
	cs_b.position = Vector3(5.0, 0.0, 0.0)
	cs_b.set_meta("ue_mesh", "/Game/Art/Environment/City/Ground/SM_CobbleSlab_A")
	body.add_child(cs_b)
	# An override body (the E2E helper contract: meta `surface_type`).
	var over := StaticBody3D.new()
	over.collision_layer = 1
	over.collision_mask = 0
	over.position = Vector3(0.0, 0.0, 15.0)
	over.set_meta("surface_type", "grass")
	var over_cs := CollisionShape3D.new()
	var over_box := BoxShape3D.new()
	over_box.size = Vector3(2.0, 0.4, 2.0)
	over_cs.shape = over_box
	over.add_child(over_cs)
	rig.add_child(over)
	# A collider with no surface evidence at all.
	var bare := StaticBody3D.new()
	bare.collision_layer = 1
	bare.collision_mask = 0
	bare.position = Vector3(0.0, 0.0, 30.0)
	var bare_cs := CollisionShape3D.new()
	var bare_box := BoxShape3D.new()
	bare_box.size = Vector3(2.0, 0.4, 2.0)
	bare_cs.shape = bare_box
	bare.add_child(bare_cs)
	rig.add_child(bare)
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	var r_carpet: Dictionary = SurfaceResolver.resolve_ray(space, rig.to_global(Vector3(-5.0, 3.0, 0.0)), rig.to_global(Vector3(-5.0, -3.0, 0.0)))
	var r_stone: Dictionary = SurfaceResolver.resolve_ray(space, rig.to_global(Vector3(5.0, 3.0, 0.0)), rig.to_global(Vector3(5.0, -3.0, 0.0)))
	var r_over: Dictionary = SurfaceResolver.resolve_ray(space, rig.to_global(Vector3(0.0, 3.0, 15.0)), rig.to_global(Vector3(0.0, -3.0, 15.0)))
	var r_bare: Dictionary = SurfaceResolver.resolve_ray(space, rig.to_global(Vector3(0.0, 3.0, 30.0)), rig.to_global(Vector3(0.0, -3.0, 30.0)))
	_check(str(r_carpet.get("surface")) == "Carpet" and bool(r_carpet.get("known")) and str(r_carpet.get("audio_token")) == "carpet",
		"W7H.6 batched body + per-shape ue_mesh: the rug shape resolves Carpet (audio token carpet)",
		"W7H.6 rug shape resolved " + str(r_carpet))
	_check(str(r_stone.get("surface")) == "Stone" and bool(r_stone.get("known")) and _approx(HearingData.surface_loudness(str(r_stone.get("surface"))), 1.5),
		"W7H.7 the same body's cobble shape resolves Stone (authored 1.5), so the resolver is per-shape",
		"W7H.7 cobble shape resolved " + str(r_stone))
	_check(str(r_over.get("surface")) == "Grass" and bool(r_over.get("known")),
		"W7H.8 explicit `surface_type` override wins over name evidence",
		"W7H.8 override resolved " + str(r_over))
	_check(str(r_bare.get("surface")) == "Stone" and not bool(r_bare.get("known")),
		"W7H.9 a collider with no evidence resolves Stone and reports known=false (never crashes)",
		"W7H.9 bare collider resolved " + str(r_bare))
	var ghost: Dictionary = SurfaceResolver.resolve_ray(space, Vector3(0.0, 50.0, 0.0), Vector3(0.0, 40.0, 0.0))
	_check(str(ghost.get("surface")) == "Stone" and not bool(ghost.get("known")),
		"W7H.10 a ray into the void fails closed to stone",
		"W7H.10 void ray resolved " + str(ghost))
	rig.queue_free()
	await physics_frame


## The player path: standing on a carpet/grass/dirt collider makes the footstep
## stimulus silent, and on stone/wood it is 1.5x. The same ray feeds the audio
## pool token.
func _test_footstep_surface() -> void:
	var nb: Node = root.get_node_or_null("NoiseBus")
	if nb == null:
		_check(false, "", "W7H.11 NoiseBus missing")
		return
	var thief_script: GDScript = load("res://src/player/thief_character.gd") as GDScript
	for rec: Dictionary in [
		{"mesh": "/Game/Art/Environment/Props/Rugs/SM_Rug_A", "surface": "Carpet", "mult": 0.0, "token": "carpet"},
		{"mesh": "/Game/Art/Environment/City/Ground/SM_GrassPatch_A", "surface": "Grass", "mult": 0.0, "token": "earth"},
		{"mesh": "/Game/Art/Environment/City/Ground/SM_DirtPath_A", "surface": "Dirt", "mult": 0.0, "token": "earth"},
		{"mesh": "/Game/Art/Environment/City/Ground/SM_CobbleSlab_A", "surface": "Stone", "mult": 1.5, "token": "stone"},
		{"mesh": "/Game/Art/Environment/Den/Floor/SM_WoodFloorPlank_A", "surface": "WoodFloor", "mult": 1.5, "token": "wood"},
	]:
		var rig := Node3D.new()
		root.add_child(rig)
		rig.global_position = Vector3(0.0, 0.0, 360.0 + float(rec["mesh"].hash() % 60))
		var floor_body := StaticBody3D.new()
		floor_body.collision_layer = 1
		floor_body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(8.0, 0.4, 8.0)
		cs.shape = box
		cs.set_meta("ue_mesh", str(rec["mesh"]))
		floor_body.add_child(cs)
		floor_body.position = Vector3(0.0, -0.2, 0.0)
		rig.add_child(floor_body)
		var thief: CharacterBody3D = thief_script.new() as CharacterBody3D
		thief.set_physics_process(false)
		rig.add_child(thief)
		await process_frame
		thief.global_position = rig.global_position + Vector3(0.0, 0.02, 0.0)
		thief.set_physics_process(true)
		await physics_frame
		await physics_frame
		thief.call("_refresh_audio_surface")
		var resolved: String = str(thief.call("footstep_surface"))
		var token: String = str(thief.call("_audio_surface"))
		var records: Array[Dictionary] = []
		var cb: Callable = func(r: Dictionary) -> void:
			records.append(r)
		nb.connect("noise_record_emitted", cb)
		nb.call("emit_noise", thief.global_position, 3.5, thief, "footstep", resolved)
		nb.disconnect("noise_record_emitted", cb)
		var loud: float = float(records[0].get("loudness_m", -1.0)) if records.size() == 1 else -1.0
		var mult: float = float(records[0].get("surface_multiplier", -1.0)) if records.size() == 1 else -1.0
		_check(resolved == str(rec["surface"]) and token == str(rec["token"]) \
				and _approx(mult, float(rec["mult"])) and _approx(loud, 3.5 * float(rec["mult"])),
			"W7H.11 %s: footstep resolves %s (audio %s, x%.1f, loudness %.2f m)" % [rec["mesh"].get_file(), resolved, token, mult, loud],
			"W7H.11 %s FAILED: surface=%s token=%s mult=%.2f loudness=%.2f" % [rec["mesh"].get_file(), resolved, token, mult, loud])
		rig.queue_free()
		await physics_frame


# ---------------------------------------------------------------- matrix

## 22 surfaces x 3 gaits x 3 weather rows = 198 cases. Every case asserts the
## exact radius and both sides of the boundary (heard at r, silent at r + 0.01).
func _test_matrix() -> void:
	var nb: Node = root.get_node_or_null("NoiseBus")
	if nb == null or GuardScript == null:
		_check(false, "", "W7H.12 matrix prerequisites missing (NoiseBus/guard_ai)")
		return
	for w: Dictionary in WEATHER_MAPS:
		_set_map(str(w["map"]))
		var guard: CharacterBody3D = await _make_guard(Vector3(0.0, 0.0, 420.0))
		guard.call("refresh_weather_sound_carry")
		var weather: float = float(guard.call("hearing_weather_multiplier"))
		var weather_ok: bool = _approx(weather, float(w["mult"]))
		_check(weather_ok,
			"W7H.12 weather row %s reads x%.2f outdoors for guard" % [str(w["label"]), weather],
			"W7H.12 weather %s outdoors=%.3f (expected %.2f)" % [str(w["label"]), weather, float(w["mult"])])
		var surfaces: Array = SurfaceResolver.CANONICAL.values()
		var silent_ok: Array[String] = []
		var hard_ok: int = 0
		var medium_ok: int = 0
		for surface: Variant in surfaces:
			var s_name: String = str(surface)
			var s_mult: float = HearingData.surface_loudness(s_name)
			var row_pass: bool = true
			var row_detail: Array[String] = []
			for gait: String in GAITS:
				_matrix_cases += 1
				var stim_max: float = HearingData.max_range_m("footstep", gait)
				var expected: float = minf(stim_max * s_mult, GUARD_SENSE_RANGE_M * weather)
				var loudness: float = float(GAIT_LOUDNESS[gait])
				var heard_radius: float = _emit_and_radius(nb, guard, expected - 0.02, loudness, "footstep", s_name)
				var heard: bool = str(guard.get("last_heard_stim_tag")) != ""
				# Silent faces: expected radius 0, so a 0.5 m emission must miss.
				if expected <= 0.0001:
					_reset_guard(guard)
					_emit_and_radius(nb, guard, 0.5, loudness, "footstep", s_name)
					var silent: bool = str(guard.get("last_heard_stim_tag")) == ""
					row_pass = row_pass and silent
					row_detail.append("%s:0" % gait)
				else:
					var radius_ok: bool = heard and _approx(heard_radius, expected, 0.001)
					_reset_guard(guard)
					_emit_and_radius(nb, guard, expected + 0.01, loudness, "footstep", s_name)
					var silent2: bool = str(guard.get("last_heard_stim_tag")) == ""
					row_pass = row_pass and radius_ok and silent2
					row_detail.append("%s:%.2f" % [gait, heard_radius])
				_reset_guard(guard)
			if s_mult >= 1.5:
				hard_ok += 1
			elif _approx(s_mult, 1.0):
				medium_ok += 1
			elif s_mult <= 0.0001:
				silent_ok.append(s_name)
			_check(row_pass,
				"W7H.13 %s x %s: %s" % [s_name, str(w["label"]), ", ".join(row_detail)],
				"W7H.13 %s x %s FAILED: %s (surface x%.1f)" % [s_name, str(w["label"]), ", ".join(row_detail), s_mult])
		_check(silent_ok.size() == SILENT_SURFACES.size() and hard_ok == HARD_SURFACES.size() and medium_ok == MEDIUM_SURFACES.size(),
			"W7H.14 %s: %d silent faces, %d hard (1.5) faces, %d medium (1.0) faces" % [str(w["label"]), silent_ok.size(), hard_ok, medium_ok],
			"W7H.14 %s: silent=%s hard=%d medium=%d (expected %d/%d/%d)" % [str(w["label"]), str(silent_ok), hard_ok, medium_ok, SILENT_SURFACES.size(), HARD_SURFACES.size(), MEDIUM_SURFACES.size()])
		guard.free()
		await process_frame
	# Unknown/empty surface: the emitter passes no surface -> multiplier 1.0.
	_set_map("guildhall")
	var g2: CharacterBody3D = await _make_guard(Vector3(0.0, 0.0, 460.0))
	g2.call("refresh_weather_sound_carry")
	_reset_guard(g2)
	var r_unknown: float = _emit_and_radius(nb, g2, 3.98, 8.0, "footstep", "")
	var unknown_heard: bool = str(g2.get("last_heard_stim_tag")) != ""
	_check(unknown_heard and _approx(r_unknown, 20.0),
		"W7H.15 an empty surface keeps the authored 20 m sprint radius (multiplier 1.0, never 0)",
		"W7H.15 empty surface heard=%s radius=%.3f (expected 20.0)" % [str(unknown_heard), r_unknown])
	g2.free()
	await process_frame


## Radius boundary at exact equality and just past it, plus the clip against the
## 25 m authored HearingRange.
func _test_boundaries() -> void:
	var nb: Node = root.get_node_or_null("NoiseBus")
	if nb == null or GuardScript == null:
		return
	_set_map("guildhall")
	var guard: CharacterBody3D = await _make_guard(Vector3(0.0, 0.0, 480.0))
	guard.call("refresh_weather_sound_carry")
	# Stone sprint: min(20 x 1.5, 25) = 25 -> clipped by the authored sense range.
	_reset_guard(guard)
	var r_clip: float = _emit_and_radius(nb, guard, 24.99, 8.0, "footstep", "Stone")
	_check(_approx(r_clip, 25.0),
		"W7H.16 the authored 25 m HearingRange clips a 30 m stone sprint (radius %.2f m)" % r_clip,
		"W7H.16 clip radius=%.3f (expected 25.0)" % r_clip)
	_reset_guard(guard)
	_emit_and_radius(nb, guard, 25.01, 8.0, "footstep", "Stone")
	_check(str(guard.get("last_heard_stim_tag")) == "",
		"W7H.17 25.01 m stone sprint is silent (the clip is a real ceiling)",
		"W7H.17 25.01 m still heard (radius %.2f)" % float(guard.get("last_heard_radius_m")))
	# Tile walk: min(4 x 1.0, 25) = 4 -> exact boundary equality is heard.
	_reset_guard(guard)
	var r_exact: float = _emit_and_radius(nb, guard, 4.0, 3.5, "footstep", "Tile")
	_check(_approx(r_exact, 4.0) and str(guard.get("last_heard_stim_tag")) != "",
		"W7H.18 distance == radius is heard (tile walk at exactly 4.00 m, radius %.2f m)" % r_exact,
		"W7H.18 exact boundary not heard (radius %.3f)" % r_exact)
	_reset_guard(guard)
	_emit_and_radius(nb, guard, 4.01, 3.5, "footstep", "Tile")
	_check(str(guard.get("last_heard_stim_tag")) == "",
		"W7H.19 radius + 0.01 m is silent (tile walk 4.01 m)",
		"W7H.19 radius + 0.01 m still heard (radius %.2f)" % float(guard.get("last_heard_radius_m")))
	guard.free()
	await process_frame


## 3D distance and the two negative controls (astral, knocked out).
func _test_3d_and_negative_controls() -> void:
	var nb: Node = root.get_node_or_null("NoiseBus")
	if nb == null or GuardScript == null:
		return
	_set_map("guildhall")
	var guard: CharacterBody3D = await _make_guard(Vector3(0.0, 0.0, 500.0))
	guard.call("refresh_weather_sound_carry")
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	# A roof plane between the guard and the player (5 m above the guard), so a
	# floor/roof must not be invented as occlusion.
	var roof_rig := Node3D.new()
	root.add_child(roof_rig)
	roof_rig.global_position = Vector3(0.0, 5.0, 500.0)
	var roof_body := StaticBody3D.new()
	roof_body.collision_layer = 1
	roof_body.collision_mask = 0
	var roof_cs := CollisionShape3D.new()
	var roof_box := BoxShape3D.new()
	roof_box.size = Vector3(30.0, 0.4, 30.0)
	roof_cs.shape = roof_box
	roof_cs.set_meta("ue_mesh", "/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_Mid_4x4")
	roof_body.add_child(roof_cs)
	roof_rig.add_child(roof_body)
	await physics_frame
	# Guard 15 m below the player, tile sprint (1.0) -> radius 20 m, 3D 15.8 m.
	# The mock player needs a script: a bare Node3D cannot carry `astral_active`,
	# and the guard reads it with a typed property probe.
	var mock_script := GDScript.new()
	mock_script.source_code = "extends Node3D\nvar astral_active: bool = false\n"
	mock_script.reload()
	var player := Node3D.new()
	player.set_script(mock_script)
	player.add_to_group("player")
	root.add_child(player)
	player.global_position = guard.global_position + Vector3(5.0, 15.0, 0.0)
	await process_frame
	_reset_guard(guard)
	var r_below: float = _emit_and_radius(nb, guard, player.global_position, 8.0, "footstep", "Tile")
	var heard_below: bool = str(guard.get("last_heard_stim_tag")) != ""
	_check(heard_below and _approx(r_below, 20.0),
		"W7H.20 a sprint 15 m below through a roof is heard by 3D distance (15.8 m <= 20 m radius, no floor occlusion)",
		"W7H.20 heard=%s radius=%.2f" % [str(heard_below), r_below])
	# Same height offset, 15 m across: 3D 21.2 m > 20 m, planar 15 m -> must miss.
	_reset_guard(guard)
	_emit_and_radius(nb, guard, guard.global_position + Vector3(15.0, 15.0, 0.0), 8.0, "footstep", "Tile")
	_check(str(guard.get("last_heard_stim_tag")) == "",
		"W7H.21 the same sprint at 21.2 m 3D / 15 m planar is silent (3D distance, not a planar sum)",
		"W7H.21 21.2 m 3D sprint heard (radius %.2f)" % float(guard.get("last_heard_radius_m")))
	# Astral form makes no noise.
	_reset_guard(guard)
	player.set("astral_active", true)
	_emit_and_radius(nb, guard, player.global_position, 8.0, "footstep", "Tile", player)
	_check(str(guard.get("last_heard_stim_tag")) == "",
		"W7H.22 an astral player emits nothing the guard can hear",
		"W7H.22 astral source still heard")
	player.set("astral_active", false)
	# Control: the same source without astral is heard, so the gate is what muted it.
	_reset_guard(guard)
	_emit_and_radius(nb, guard, player.global_position, 8.0, "footstep", "Tile", player)
	_check(str(guard.get("last_heard_stim_tag")) != "",
		"W7H.22b the same mock source is heard once astral is off (the gate, not the mock)",
		"W7H.22b non-astral mock source was not heard")
	# Knocked-out guard hears nothing.
	_reset_guard(guard)
	guard.call("knock_out", 30.0)
	_emit_and_radius(nb, guard, guard.global_position + Vector3(2.0, 0.0, 0.0), 8.0, "footstep", "Tile")
	_check(str(guard.get("last_heard_stim_tag")) == "",
		"W7H.23 a knocked-out guard hears nothing",
		"W7H.23 KO guard still heard (state=%d)" % int(guard.get("state")))
	player.queue_free()
	roof_rig.queue_free()
	guard.free()
	await process_frame


## A repeated stimulus must refresh the authored SEARCH window instead of
## letting the fan-out expire (it used to churn at 4 s regardless).
func _test_search_refresh() -> void:
	var nb: Node = root.get_node_or_null("NoiseBus")
	if nb == null or GuardScript == null:
		return
	_set_map("guildhall")
	var guard: CharacterBody3D = await _make_guard(Vector3(0.0, 0.0, 520.0))
	guard.call("refresh_weather_sound_carry")
	# First stimulus promotes NEUTRAL -> SUSPICIOUS, then the no-sight tick drops
	# it into SEARCH with the authored short window (4 s). The state machine lives
	# in _physics_process, so the guard ticks for a few frames here only.
	_reset_guard(guard)
	_emit_and_radius(nb, guard, guard.global_position + Vector3(2.0, 0.0, 0.0), 3.5, "footstep", "Tile")
	var promoted: bool = int(guard.get("state")) == 1
	guard.set_physics_process(true)
	for _i: int in range(5):
		await physics_frame
	guard.set_physics_process(false)
	var in_search: bool = int(guard.get("state")) == STATE_SEARCH
	var window: float = float(guard.get("investigation_search_seconds"))
	_check(promoted and in_search and _approx(window, 4.0),
		"W7H.24 footstep 2 m away promotes to SUSPICIOUS then SEARCH with the authored 4 s window",
		"W7H.24 promoted=%s state=%d window=%.2f" % [str(promoted), int(guard.get("state")), window])
	# Burn 1.5 s of the window, then hear again: the timer must be refreshed.
	guard.set("state_timer", 1.5)
	_reset_heard(guard)
	_emit_and_radius(nb, guard, guard.global_position + Vector3(2.0, 0.0, 0.0), 3.5, "footstep", "Tile")
	var refreshed: float = float(guard.get("state_timer"))
	var detection: float = float(guard.get("detection"))
	_check(int(guard.get("state")) == STATE_SEARCH and refreshed >= 4.0 - 0.0001 and is_zero_approx(detection),
		"W7H.25 a repeated noise refreshes the SEARCH timer to %.2f s (was burning down from 1.5 s), detection stays 0" % refreshed,
		"W7H.25 state=%d timer=%.2f detection=%.2f" % [int(guard.get("state")), refreshed, detection])
	# A long investigation (8 s) refreshes to 8 s, not 4. Combat.Block is an
	# authored long-behaviour row (7.5 m).
	guard.set("state", STATE_SEARCH)
	guard.set("investigation_search_seconds", 8.0)
	guard.set("state_timer", 2.0)
	_reset_heard(guard)
	_emit_and_radius(nb, guard, guard.global_position + Vector3(2.0, 0.0, 0.0), 10.0, "AI.Stim.Hearing.Combat.Block", "Stone")
	_check(int(guard.get("state")) == STATE_SEARCH and float(guard.get("state_timer")) >= 8.0 - 0.0001 \
			and str(guard.get("last_investigation_kind")) == "long",
		"W7H.26 a repeated long-investigation stim refreshes SEARCH to %.2f s" % float(guard.get("state_timer")),
		"W7H.26 long refresh timer=%.2f kind=%s (expected >= 8, long)" % [float(guard.get("state_timer")), str(guard.get("last_investigation_kind"))])
	guard.free()
	await process_frame


## LockPicking.Picked (3 m) vs LockPicking.Jammed (10 m): the failure is loud,
## the working tick is quiet.
func _test_lockpick_split() -> void:
	var nb: Node = root.get_node_or_null("NoiseBus")
	if nb == null or GuardScript == null:
		return
	_check(_approx(HearingData.max_range_m("lockpick"), 3.0) and _approx(HearingData.max_range_m("lockpick_jammed"), 10.0),
		"W7H.27 port tags split: lockpick -> LockPicking.Picked 3 m, lockpick_jammed -> LockPicking.Jammed 10 m",
		"W7H.27 split ranges: picked=%.2f jammed=%.2f" % [HearingData.max_range_m("lockpick"), HearingData.max_range_m("lockpick_jammed")])
	_set_map("guildhall")
	var guard: CharacterBody3D = await _make_guard(Vector3(0.0, 0.0, 540.0))
	guard.call("refresh_weather_sound_carry")
	_reset_guard(guard)
	_emit_and_radius(nb, guard, guard.global_position + Vector3(2.9, 0.0, 0.0), 4.0, "lockpick", "")
	var picked_heard: bool = str(guard.get("last_heard_stim_tag")) == "AI.Stim.Hearing.LockPicking.Picked"
	_reset_guard(guard)
	_emit_and_radius(nb, guard, guard.global_position + Vector3(3.2, 0.0, 0.0), 4.0, "lockpick", "")
	var picked_silent: bool = str(guard.get("last_heard_stim_tag")) == ""
	_check(picked_heard and picked_silent,
		"W7H.28 a working pick is heard at 2.9 m and silent at 3.2 m (Picked 3 m)",
		"W7H.28 picked heard=%s silent=%s" % [str(picked_heard), str(picked_silent)])
	_reset_guard(guard)
	_emit_and_radius(nb, guard, guard.global_position + Vector3(9.9, 0.0, 0.0), 4.0, "lockpick_jammed", "")
	var jam_heard: bool = str(guard.get("last_heard_stim_tag")) == "AI.Stim.Hearing.LockPicking.Jammed"
	_reset_guard(guard)
	_emit_and_radius(nb, guard, guard.global_position + Vector3(10.2, 0.0, 0.0), 4.0, "lockpick_jammed", "")
	var jam_silent: bool = str(guard.get("last_heard_stim_tag")) == ""
	_check(jam_heard and jam_silent,
		"W7H.29 a jam is heard at 9.9 m and silent at 10.2 m (Jammed 10 m) - the loud outcome",
		"W7H.29 jam heard=%s silent=%s" % [str(jam_heard), str(jam_silent)])
	guard.free()
	await process_frame


## Exactly one OpeningCreak per open/close toggle, and no double-fire when the
## lock path also fires.
func _test_swing_door_creak() -> void:
	var nb: Node = root.get_node_or_null("NoiseBus")
	if nb == null:
		return
	var door: Node3D = SwingingDoorScript.new() as Node3D
	door.name = "W7HDoor"
	door.call("configure", {
		"pos": [0.0, 0.0, 560.0],
		"basis": [1, 0, 0, 0, 1, 0, 0, 0, 1],
		"leaves": [],
		"lock_level": 0,
	}, null)
	root.add_child(door)
	await process_frame
	var creaks: Array[Dictionary] = []
	var cb: Callable = func(r: Dictionary) -> void:
		if str(r.get("tag", "")) == "door":
			creaks.append(r)
	nb.connect("noise_record_emitted", cb)
	door.call("_start_swing_toggle")
	var after_open: int = creaks.size()
	await _wait_sec(0.55)
	door.call("_start_swing_toggle")
	var after_close: int = creaks.size()
	var stim_ok: bool = true
	for r: Dictionary in creaks:
		stim_ok = stim_ok and str(r.get("stim_tag", "")) == "AI.Stim.Hearing.OpeningCreak" \
			and _approx(float((r.get("stim", {}) as Dictionary).get("max_range_m", 0.0)), 5.0)
	_check(after_open == 1 and after_close == 2 and stim_ok,
		"W7H.30 one OpeningCreak (5 m, authored) per swing: open=%d close=%d total=%d" % [after_open, after_close, after_close],
		"W7H.30 swing creaks open=%d close=%d stim_ok=%s (expected 1 then 2)" % [after_open, after_close, str(stim_ok)])
	# Lock path on a closed door: the unlock swings it, so exactly ONE creak.
	await _wait_sec(0.55)
	if bool(door.get("is_open")):
		door.call("_start_swing_toggle")
		await _wait_sec(0.55)
	var before_lock: int = creaks.size()
	door.call("_on_lockpick_finished", true, null)
	var lock_creaks: int = creaks.size() - before_lock
	# Hold-to-lock emits the "lock" tag (OpeningCreak stim) but must not add a
	# "door" tag emission.
	await _wait_sec(0.55)
	var before_hold: int = creaks.size()
	door.call("interact_hold", null)
	var hold_creaks: int = creaks.size() - before_hold
	_check(lock_creaks == 1 and hold_creaks == 0,
		"W7H.31 lock path does not double-fire: unlock+swing emits %d creak, hold-to-lock emits %d" % [lock_creaks, hold_creaks],
		"W7H.31 lock double-fire: unlock+swing=%d (expected 1), hold-to-lock=%d (expected 0)" % [lock_creaks, hold_creaks])
	nb.disconnect("noise_record_emitted", cb)
	door.queue_free()
	await process_frame


## Old Manor/Jaspering interiors use the authored 1.0 under a ceiling; the open
## street keeps 0.9 / 0.8. The Den stays indoor everywhere.
func _test_indoor_scope() -> void:
	var rig := Node3D.new()
	root.add_child(rig)
	rig.global_position = Vector3(0.0, 0.0, 600.0)
	var ceiling := StaticBody3D.new()
	ceiling.collision_layer = 1
	ceiling.collision_mask = 0
	ceiling.position = Vector3(0.0, 6.0, 0.0)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 0.4, 20.0)
	cs.shape = box
	ceiling.add_child(cs)
	rig.add_child(ceiling)
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	var inside: Vector3 = rig.global_position + Vector3(0.0, 1.2, 0.0)
	var outside: Vector3 = rig.global_position + Vector3(40.0, 1.2, 0.0)
	_check(WeatherProfile.is_indoors_at(space, inside) and not WeatherProfile.is_indoors_at(space, outside),
		"W7H.32 ceiling probe: covered point indoors, open point outdoors",
		"W7H.32 probe inside=%s outside=%s" % [str(WeatherProfile.is_indoors_at(space, inside)), str(WeatherProfile.is_indoors_at(space, outside))])
	var cases: bool = _approx(WeatherProfile.sound_carry_multiplier_at("old_manor", space, inside), 1.0) \
		and _approx(WeatherProfile.sound_carry_multiplier_at("old_manor", space, outside), 0.9) \
		and _approx(WeatherProfile.sound_carry_multiplier_at("jaspering_hall", space, inside), 1.0) \
		and _approx(WeatherProfile.sound_carry_multiplier_at("jaspering_hall", space, outside), 0.8) \
		and _approx(WeatherProfile.sound_carry_multiplier_at("thieves_den", space, outside), 1.0)
	_check(cases,
		"W7H.33 indoor scope: Old Manor interior 1.0 / exterior 0.9, Jaspering interior 1.0 / exterior 0.8, Den 1.0 everywhere",
		"W7H.33 scope wrong: om in=%.2f out=%.2f, jas in=%.2f out=%.2f, den out=%.2f" % [
			WeatherProfile.sound_carry_multiplier_at("old_manor", space, inside),
			WeatherProfile.sound_carry_multiplier_at("old_manor", space, outside),
			WeatherProfile.sound_carry_multiplier_at("jaspering_hall", space, inside),
			WeatherProfile.sound_carry_multiplier_at("jaspering_hall", space, outside),
			WeatherProfile.sound_carry_multiplier_at("thieves_den", space, outside)])
	# The guard consumes it: indoors on Old Manor -> 1.0; outside -> 0.9.
	if GuardScript != null:
		_set_map("old_manor")
		var guard: CharacterBody3D = await _make_guard(inside)
		guard.call("refresh_weather_sound_carry")
		var indoor_mult: float = float(guard.call("hearing_weather_multiplier"))
		guard.global_position = outside
		guard.call("refresh_weather_sound_carry")
		var outdoor_mult: float = float(guard.call("hearing_weather_multiplier"))
		_check(_approx(indoor_mult, 1.0) and _approx(outdoor_mult, 0.9),
			"W7H.34 guard scope: Old Manor interior x%.2f, street x%.2f (the authored indoors/outdoors split)" % [indoor_mult, outdoor_mult],
			"W7H.34 guard scope indoor=%.2f outdoor=%.2f" % [indoor_mult, outdoor_mult])
		guard.free()
		await process_frame
	rig.queue_free()
	await process_frame


# ---------------------------------------------------------------- helpers

func _make_guard(pos: Vector3) -> CharacterBody3D:
	var guard: CharacterBody3D = GuardScript.new() as CharacterBody3D
	root.add_child(guard)
	guard.global_position = pos
	await process_frame
	guard.set_physics_process(false)
	await process_frame
	return guard


func _reset_heard(guard: CharacterBody3D) -> void:
	guard.set("last_heard_stim_tag", "")
	guard.set("last_heard_radius_m", -1.0)


func _reset_guard(guard: CharacterBody3D) -> void:
	guard.call("_set_state", 0)
	guard.set("detection", 0.0)
	guard.set("state_timer", 0.0)
	_reset_heard(guard)


## Emits one stimulus at `dist` metres along +X (or at an absolute point) and
## returns the radius the guard recorded (-1 when it did not hear it).
func _emit_and_radius(nb: Node, guard: CharacterBody3D, dist_or_pos: Variant, loudness: float, tag: String, surface: String = "Tile", source: Node = null) -> float:
	var origin: Vector3 = (guard.global_position + Vector3(float(dist_or_pos), 0.0, 0.0)) if (dist_or_pos is float) else (dist_or_pos as Vector3)
	nb.call("emit_noise", origin, loudness, source, tag, surface)
	if str(guard.get("last_heard_stim_tag")) == "":
		return -1.0
	return float(guard.get("last_heard_radius_m"))


func _set_map(map_id: String) -> void:
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		gs.set("active_map_id", map_id)


func _wait_sec(sec: float) -> void:
	var until: int = Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame
