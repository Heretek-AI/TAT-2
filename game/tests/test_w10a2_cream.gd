extends SceneTree
## W10-A2/P0b CREAM PROOF — registered as suite 119 by the W10-P2 data wave.
##
##   flock /tmp/opencode/tat2-godot.lock -c \
##     'tools/godot --headless --path game --script res://tests/test_w10a2_cream.gd'
##
## The shipped `1m_Plane_Reverse` moon cards (122 instances, all authored
## `hidden_in_game: true`) and their `MI_EmisLight_Moonlight` material have no
## albedo/opacity/emissive vector. The loader's `_apply_ue_emissive()` used to
## invent WHITE whenever a material authored an emissive strength but no
## EmissiveColor and no emissive map (`col` stayed (1,1,1)); that is the
## cream-slab class.
##
## W10-P2 fixed it: no authored colour + no authored emissive map => no
## emission, counted in the loader's `tat_invented_white` census
## (`_invented_white_count` / `invented_white_count()` / the
## `invented_white_count` + `invented_white_materials` result keys). This suite
## is now GREEN and fails on any regression:
##   * an invented white emission for a strength-only material;
##   * a missing/never-incrementing counter;
##   * over-suppression: an authored EmissiveColor must still emit.
##
## Prints `CREAM_PROOF: GREEN passes=N expected_fail=0` and exits 0; any failure
## prints `CREAM_FAIL` and exits 1.

const LevelLoaderScript := preload("res://src/core/level_loader.gd")
const LEVELS_ROOT := "res://data/generated/levels/"
const MOON_CARD_MESH := "1m_plane_reverse"
const MOON_MAT := "/Game/MaterialLibrary/Environment/Lights/MI_EmisLight_Moonlight"

var _fails: int = 0
var _passes: int = 0
var _ldr: Node = null


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	if ok:
		_passes += 1
		print("CREAM_CHECK PASS ", msg)
	else:
		_fails += 1
		printerr("CREAM_FAIL ", msg)


func _prop_names(obj: Object) -> Array[String]:
	var out: Array[String] = []
	for p: Dictionary in obj.get_property_list():
		out.append(str(p.get("name", "")))
	return out


func _near_white(c: Color) -> bool:
	return c.r >= 0.95 and c.g >= 0.95 and c.b >= 0.95


func _collect_levels(dir_path: String, out: Array[String]) -> void:
	var da: DirAccess = DirAccess.open(dir_path)
	if da == null:
		return
	da.list_dir_begin()
	var name: String = da.get_next()
	while name != "":
		if name.begins_with("."):
			name = da.get_next()
			continue
		var full: String = dir_path.path_join(name)
		if da.current_is_dir():
			_collect_levels(full, out)
		elif name.ends_with(".tatlevel.json"):
			out.append(full)
		name = da.get_next()
	da.list_dir_end()


func _run() -> void:
	await process_frame
	_ldr = LevelLoaderScript.new()
	_ldr.name = "CreamProbeLoader"
	root.add_child(_ldr)
	await process_frame

	# 1. Authored moon cards: every instance is hidden in the generated payload.
	var files: Array[String] = []
	_collect_levels(LEVELS_ROOT, files)
	var cards: int = 0
	var visible: int = 0
	for f: String in files:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(f))
		if not (parsed is Dictionary):
			continue
		var meshes_v: Variant = (parsed as Dictionary).get("meshes", [])
		if not (meshes_v is Array):
			continue
		for m_v: Variant in (meshes_v as Array):
			var m: Dictionary = m_v as Dictionary
			if str(m.get("mesh", "")).to_lower().find(MOON_CARD_MESH) < 0:
				continue
			cards += 1
			if not bool(m.get("hidden_in_game", false)):
				visible += 1
	_check(cards >= 60 and visible == 0,
		"moon cards authored hidden: total=%d visible=%d (want >=60 / 0)" % [cards, visible])

	# 2. The cream material must not resolve to a white/emissive surface.
	var mat: Material = _ldr.call("get_material_for_ue", MOON_MAT) as Material
	var sm: StandardMaterial3D = mat as StandardMaterial3D
	var white_albedo: bool = sm != null and sm.albedo_texture == null and _near_white(sm.albedo_color)
	var white_emission: bool = sm != null and sm.emission_enabled and _near_white(sm.emission) \
		and sm.emission_texture == null
	_check(mat != null and not white_albedo and not white_emission,
		"MI_EmisLight_Moonlight resolves without invented white (class=%s)" % (
			mat.get_class() if mat != null else "null"))

	# 3. GREEN: a material that authors EmissiveStrength and no EmissiveColor /
	# emissive map must not receive an emission at all.
	var synth := StandardMaterial3D.new()
	_ldr.call("_apply_ue_emissive", synth, {
		"path": "/Game/Test/EmissiveNoColour",
		"texs": {},
		"params": {"EmissiveStrength": 2.0},
		"vectors": {},
		"switches": {},
	})
	var invented_white: bool = synth.emission_enabled and _near_white(synth.emission) \
		and synth.emission_texture == null and synth.emission_energy_multiplier > 0.0
	_check(not invented_white and not synth.emission_enabled,
		"_apply_ue_emissive invents no white for EmissiveStrength-only material (enabled=%s colour=%s energy=%.2f)" % [
			str(synth.emission_enabled), str(synth.emission), synth.emission_energy_multiplier
		])

	# 4. The census must be exposed AND must have counted case 3.
	var names: Array[String] = _prop_names(_ldr)
	var has_counter: bool = names.has("_invented_white_count") \
		or _ldr.has_method("invented_white_count") \
		or _ldr.has_meta("tat_invented_white")
	var count: int = int(_ldr.call("invented_white_count")) if _ldr.has_method("invented_white_count") else -1
	_check(has_counter and count >= 1,
		"loader exposes a tat_invented_white counter and counted the suppression (count=%d, %d properties)" % [
			count, names.size()
		])

	# 5. Negative control: an authored EmissiveColor still emits (the fix must
	# suppress only the invented tint, never authored emission).
	var authored := StandardMaterial3D.new()
	_ldr.call("_apply_ue_emissive", authored, {
		"path": "/Game/Test/EmissiveColour",
		"texs": {},
		"params": {"EmissiveStrength": 2.0},
		"vectors": {"EmissiveColor": [1.0, 0.5, 0.2, 1.0]},
		"switches": {},
	})
	_check(authored.emission_enabled and authored.emission.r > 0.9 \
			and authored.emission.g < 0.7 and not _near_white(authored.emission),
		"authored EmissiveColor still emits (enabled=%s colour=%s)" % [
			str(authored.emission_enabled), str(authored.emission)
		])

	if _ldr != null:
		_ldr.queue_free()
	await process_frame
	if _fails > 0:
		printerr("CREAM_PROOF: UNEXPECTED_FAIL passes=%d unexpected=%d" % [_passes, _fails])
		quit(1)
		return
	print("CREAM_PROOF: GREEN passes=%d expected_fail=0" % _passes)
	quit(0)
