extends RefCounted
## P0b parity tier "p2": authored-data provenance only, never part of `all`.
##
## Invocation:
##   tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=p2
##
## Every check reads the generated authored payload (or the port material the
## loader builds from it) and records the expected deviation instead of
## weakening the assertion:
##   * PASS checks are the gate and go through h.require();
##   * `P2_EXPECTED_FAIL` records a known authored-data defect (the pants
##     albedo misclassification) and does not fail the tier;
##   * `P2_EXPECTED_DELTA` records a labelled port approximation (the beam
##     material is `PORT_APPROX`) with the measured numbers;
##   * `P2_FIXED` means the data wave fixed a recorded defect: the expectation
##     must then be promoted to a PASS check, not silently dropped.
##
## The stable gate marker is `P2_SUMMARY: … unexpected_fail=0`: an expected
## defect flipping to fixed stays green, a new failure of a PASS check does not.
##
## Checks (from the P0b acceptance report):
##   P2-GUARD-*  guard bucket/layer provenance (116 markers, 116 buckets,
##               113 layer lists, authored bucket census, C_20 Lounge row)
##   P2-CIV-*    authored civilian slots (body 3, head 6), shirt/head albedo,
##               pants albedo EXPECTED_FAIL (BaseColorOpacity misclassified)
##   P2-BEAM-*   authored beam BaseColor/EmissiveMultiplier/additive-unlit
##               flags PASS, port material EXPECTED_DELTA (PORT_APPROX)
##   P2-CENSUS-* turret 229/1,145/0 with 0 missing GLBs; GC 336 hidden
##               components / 166 leaves, 0 visible, 0 unresolved
##   P2-GC-LABEL GC interaction label is the authored
##               ST_Interactables.PromptDestroyDeployable row ("Destroy")

const LevelLoaderScript := preload("res://src/core/level_loader.gd")

const GUILDHALL_GAMEPLAY := "res://data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json"
const GUILDHALL_LOOT := "res://data/generated/levels/Guildhall/Guildhall_Loot.tatlevel.json"
const LEVELS_ROOT := "res://data/generated/levels/"
const MESH_MATERIALS := "res://data/generated/mesh_materials.json"
const MATERIALS := "res://data/generated/materials.json"
const STRINGS_INTERACTABLES := "res://data/generated/tables/StringTables/ST_Interactables.json"

const CIV_BODY := "/Game/Art/Animation/CivFemale/Skin/Common/SK_CivFemale_Common_01C"
const CIV_HEAD := "/Game/Art/Animation/CivFemale/Skin/Heads/SK_CivFemale_Head_Abby_Short01"
const CIV_PANTS := "/Game/Art/Character/CivFemale/Common_01/MI_CivFemale_Common_01_PantsC"
const CIV_SHIRT := "/Game/Art/Character/CivFemale/Common_01/MI_CivFemale_Common_01_ShirtC"
const CIV_HEAD_MAT := "/Game/Art/Character/CivFemale/Base/MI_CivFemale_Base_Head"
const PANTS_ALBEDO_SUFFIX := "T_CivFemale_Common_01_Pants_D.png"

const BEAM_MAT := "/Game/Gameplay/Traps/Detectors/LightBeam/MI_LightBeam_SM"
const TURRET_PREFIX := "bp_securityturret"
const TURRET_MESH_PREFIX := "/game/art/gameplay/turrets/"
const EXPECTED_TURRET_ACTORS := 229
const EXPECTED_TURRET_VISIBLE := 1145

var h: RefCounted
var expected_fail: int = 0
var expected_delta: int = 0
var fixed: int = 0


func _init(helpers: RefCounted) -> void:
	h = helpers


func run() -> void:
	var fails_before: int = int(h.get("fails"))
	_check_guard_provenance()
	_check_civilian_slots()
	await _check_beam()
	_check_census()
	_check_gc_label()
	var self_fails: int = int(h.get("fails")) - fails_before
	print("P2_SUMMARY: expected_fail=%d expected_delta=%d fixed=%d unexpected_fail=%d" % [
		expected_fail, expected_delta, fixed, self_fails
	])


func _expect_fail(ok: bool, id: String, detail: String) -> void:
	expected_fail += 1
	if ok:
		fixed += 1
		print("P2_FIXED: [", id, "] the recorded defect is gone; promote this expectation to a PASS check — ", detail)
	else:
		print("P2_EXPECTED_FAIL: [", id, "] ", detail)


func _expect_delta(unchanged: bool, id: String, detail: String) -> void:
	expected_delta += 1
	if unchanged:
		fixed += 1
		print("P2_FIXED: [", id, "] the port now matches the authored value; promote this delta to a PASS check — ", detail)
	else:
		print("P2_EXPECTED_DELTA: [", id, "] ", detail)


# --- guards ----------------------------------------------------------------

func _check_guard_provenance() -> void:
	var lvl: Dictionary = h.read_json(GUILDHALL_GAMEPLAY) as Dictionary
	var meta: Dictionary = lvl.get("guard_spawn_meta", {}) as Dictionary
	var unresolved: Variant = meta.get("unresolved", [])
	h.require(
		int(meta.get("markers", -1)) == 116 and int(meta.get("with_bucket", -1)) == 116 \
			and int(meta.get("with_layers", -1)) == 113 and int(meta.get("without_layers", -1)) == 3 \
			and unresolved is Array and (unresolved as Array).is_empty(),
		"P2-GUARD-META",
		"guard provenance markers=%d with_bucket=%d with_layers=%d without_layers=%d unresolved=%d" % [
			int(meta.get("markers", -1)), int(meta.get("with_bucket", -1)),
			int(meta.get("with_layers", -1)), int(meta.get("without_layers", -1)),
			(unresolved as Array).size() if unresolved is Array else -1,
		]
	)
	var counts: Dictionary = meta.get("bucket_counts", {}) as Dictionary
	h.require(
		int(counts.get("DA_SpawnBucket_StandardGuards_Lanterns", -1)) == 67 \
			and int(counts.get("DA_SpawnBucket_StandardGuards_Bouncers", -1)) == 35 \
			and int(counts.get("DA_SpawnBucket_Hauntstable", -1)) == 14,
		"P2-GUARD-BUCKETS",
		"authored bucket census Lanterns=67 Bouncers=35 Hauntstable=14 (the selector must exclude Hauntstable)" % []
	)
	var markers: Array = lvl.get("markers", []) as Array
	var c20: Dictionary = {}
	var character_markers: int = 0
	for m_v: Variant in markers:
		var m: Dictionary = m_v as Dictionary
		if "MissionSpawner_Character" not in str(m.get("class", "")):
			continue
		character_markers += 1
		if str(m.get("name", "")).ends_with("_C_20"):
			c20 = m
	var layers: Array = c20.get("spawn_layers", []) as Array
	h.require(
		character_markers == 116 and not c20.is_empty() \
			and str(c20.get("spawn_bucket", "")) == "DA_SpawnBucket_StandardGuards_Bouncers" \
			and layers.size() == 4 and str(layers[0]) == "Security_GroundFloor_Lounge_A",
		"P2-GUARD-C20",
		"Lounge marker C_20 authored bucket=Bouncers layers=%s (MissionSpawner_Character=%d)" % [
			str(layers), character_markers
		]
	)


# --- civilians -------------------------------------------------------------

func _check_civilian_slots() -> void:
	var mm: Dictionary = h.read_json(MESH_MATERIALS) as Dictionary
	var body: Array = mm.get(CIV_BODY, []) as Array
	var head: Array = mm.get(CIV_HEAD, []) as Array
	var body_ok: bool = body.size() == 3 \
		and str(body[0]) == CIV_PANTS and str(body[1]) == CIV_SHIRT \
		and str(body[2]) == "/Game/Art/Character/CivFemale/Base/MI_CivFemale_Base_ArmsLegs"
	var head_ok: bool = head.size() == 6 and str(head[3]) == CIV_HEAD_MAT
	h.require(
		body_ok and head_ok,
		"P2-CIV-SLOTS",
		"authored civilian slots body=%d head=%d (body PantsC/ShirtC/ArmsLegs; head slot 3 Base_Head)" % [
			body.size(), head.size()
		]
	)

	var mats: Dictionary = h.read_json(MATERIALS) as Dictionary
	var shirt: Dictionary = mats.get(CIV_SHIRT, {}) as Dictionary
	var head_mat: Dictionary = mats.get(CIV_HEAD_MAT, {}) as Dictionary
	var shirt_alb: String = str((shirt.get("texs", {}) as Dictionary).get("albedo", ""))
	var head_alb: String = str((head_mat.get("texs", {}) as Dictionary).get("albedo", ""))
	h.require(
		shirt_alb.ends_with("T_CivFemale_Common_01_Shirt_D.png") \
			and head_alb.ends_with("T_CivFemale_Base_Head_D.png"),
		"P2-CIV-ALBEDO",
		"authored shirt/head albedo resolve (shirt=%s head=%s)" % [
			shirt_alb.get_file(), head_alb.get_file()
		]
	)

	# The recorded P0b defect: parse_materials classifies the BaseColorOpacity
	# (_D) companion as `opacity` and the albedo falls back to a male top.
	# Expected authoured pants albedo = T_CivFemale_Common_01_Pants_D.png.
	var pants: Dictionary = mats.get(CIV_PANTS, {}) as Dictionary
	var pants_texs: Dictionary = pants.get("texs", {}) as Dictionary
	var pants_alb: String = str(pants_texs.get("albedo", ""))
	var pants_op: String = str(pants_texs.get("opacity", ""))
	_expect_fail(
		pants_alb.ends_with(PANTS_ALBEDO_SUFFIX),
		"P2-CIV-PANTS-ALBEDO",
		"pants albedo='%s' expected='%s' (opacity slot carries the authored Pants_D: '%s')" % [
			pants_alb.get_file(), PANTS_ALBEDO_SUFFIX, pants_op.get_file()
		]
	)
	h.require(
		pants_op.ends_with(PANTS_ALBEDO_SUFFIX),
		"P2-CIV-PANTS-OPACITY",
		"the authored pants colour map is emitted in the opacity slot (%s) — evidence of the BaseColorOpacity misclassification" % pants_op.get_file()
	)


# --- beam ------------------------------------------------------------------

func _check_beam() -> void:
	var mats: Dictionary = h.read_json(MATERIALS) as Dictionary
	var beam: Dictionary = mats.get(BEAM_MAT, {}) as Dictionary
	var base: Array = (beam.get("vectors", {}) as Dictionary).get("BaseColor", []) as Array
	var params: Dictionary = beam.get("params", {}) as Dictionary
	var render: Dictionary = beam.get("render", {}) as Dictionary
	var base_ok: bool = base.size() >= 4 \
		and absf(float(base[0]) - 5.0) < 0.001 and absf(float(base[1]) - 4.3813) < 0.001 \
		and absf(float(base[2]) - 3.5156) < 0.001 and absf(float(base[3]) - 0.5) < 0.001
	h.require(
		base_ok and absf(float(params.get("EmissiveMultiplier", 0.0)) - 3.0) < 0.001 \
			and str(render.get("blend_mode", "")).ends_with("BLEND_Additive") \
			and bool(render.get("two_sided", false)) \
			and str(render.get("shading_model", "")).ends_with("MSM_Unlit"),
		"P2-BEAM-AUTHORED",
		"authored MI_LightBeam_SM BaseColor=%s EmissiveMultiplier=%s additive=%s two_sided=%s unlit=%s" % [
			str(base), str(params.get("EmissiveMultiplier", "")),
			str(render.get("blend_mode", "")), str(render.get("two_sided", false)),
			str(render.get("shading_model", "")),
		]
	)

	# The port material, built by the real loader from the same authored row.
	var ll: Node = LevelLoaderScript.new()
	ll.name = "P2BeamLoader"
	h.tree.root.add_child(ll)
	await h.step_process(1)
	var mat: Material = ll.call("get_material_for_ue", BEAM_MAT) as Material
	var sm: ShaderMaterial = mat as ShaderMaterial
	var shader_path: String = ""
	var port_color := Color(0.0, 0.0, 0.0, 0.0)
	var port_energy: float = 0.0
	if sm != null and sm.shader != null:
		shader_path = sm.shader.resource_path
		var cv: Variant = sm.get_shader_parameter("beam_color")
		if cv is Color:
			port_color = cv as Color
		port_energy = float(sm.get_shader_parameter("energy"))
	var authored_norm := Vector3(float(base[0]) / 5.0, float(base[1]) / 5.0, float(base[2]) / 5.0) \
		if base.size() >= 3 else Vector3.ZERO
	var authored_energy: float = 3.0 * 0.5
	var dg: float = absf(port_color.g - authored_norm.y)
	var db: float = absf(port_color.b - authored_norm.z)
	var de: float = absf(port_energy - authored_energy)
	h.require(
		sm != null and shader_path.ends_with("tat_beam.gdshader"),
		"P2-BEAM-SHADER",
		"the loader builds the labelled beam stand-in (%s)" % shader_path
	)
	_expect_delta(
		dg <= 0.01 and db <= 0.01 and de <= 0.01,
		"P2-BEAM-PORT-APPROX",
		"PORT_APPROX colour port=(%.3f, %.3f, %.3f) authored_norm=(%.3f, %.3f, %.3f) dG=%.3f dB=%.3f; energy port=%.2f authored=%.2f dE=%.2f" % [
			port_color.r, port_color.g, port_color.b,
			authored_norm.x, authored_norm.y, authored_norm.z, dg, db,
			port_energy, authored_energy, de,
		]
	)
	await h.free_node(ll)


# --- turret / GC census ----------------------------------------------------

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


func _glb_exists(ue_mesh: String) -> bool:
	var clean: String = ue_mesh.split(".")[0]
	if clean.begins_with("/Game/"):
		clean = clean.substr(6)
	return ResourceLoader.exists("res://assets/ue/Content/" + clean + ".glb")


func _check_census() -> void:
	var gameplay: Dictionary = h.read_json(GUILDHALL_GAMEPLAY) as Dictionary
	var actors: int = 0
	for a_v: Variant in (gameplay.get("actors", []) as Array):
		if str((a_v as Dictionary).get("class", "")).to_lower().begins_with(TURRET_PREFIX):
			actors += 1
	var visible_parts: int = 0
	var hidden_parts: int = 0
	var missing: int = 0
	for m_v: Variant in (gameplay.get("meshes", []) as Array):
		var m: Dictionary = m_v as Dictionary
		var mp: String = str(m.get("mesh", "")).to_lower()
		if not mp.begins_with(TURRET_MESH_PREFIX):
			continue
		if bool(m.get("hidden_in_game", false)):
			hidden_parts += 1
			continue
		visible_parts += 1
		if not _glb_exists(str(m.get("mesh", ""))):
			missing += 1
	h.require(
		actors == EXPECTED_TURRET_ACTORS and visible_parts == EXPECTED_TURRET_VISIBLE \
			and hidden_parts == 0 and missing == 0,
		"P2-CENSUS-TURRET",
		"authored turret census actors=%d (want %d) visible=%d (want %d) hidden=%d missing_glb=%d" % [
			actors, EXPECTED_TURRET_ACTORS, visible_parts, EXPECTED_TURRET_VISIBLE,
			hidden_parts, missing,
		]
	)

	var loot: Dictionary = h.read_json(GUILDHALL_LOOT) as Dictionary
	var loot_gc: Dictionary = loot.get("gc_stats", {}) as Dictionary
	h.require(
		int(loot_gc.get("components", -1)) == 95 and int(loot_gc.get("leaves", -1)) == 79 \
			and int(loot_gc.get("visible_emitted", -1)) == 0 and int(loot_gc.get("unresolved", -1)) == 0,
		"P2-CENSUS-GC-LOOT",
		"Guildhall_Loot gc_stats components=%d leaves=%d visible_emitted=%d unresolved=%d" % [
			int(loot_gc.get("components", -1)), int(loot_gc.get("leaves", -1)),
			int(loot_gc.get("visible_emitted", -1)), int(loot_gc.get("unresolved", -1)),
		]
	)

	# Whole-payload census (the probe's contract): every generated level.
	var files: Array[String] = []
	_collect_levels(LEVELS_ROOT, files)
	var sum: Dictionary = {}
	for f: String in files:
		var d: Dictionary = h.read_json(f) as Dictionary
		var gs: Dictionary = d.get("gc_stats", {}) as Dictionary
		for k: Variant in gs.keys():
			# JSON numbers may parse as int or float; both are counts.
			if gs[k] is int or gs[k] is float:
				sum[k] = int(sum.get(k, 0)) + int(gs[k])
	h.require(
		files.size() >= 100 and int(sum.get("components", -1)) == 336 \
			and int(sum.get("hidden", -1)) == 336 and int(sum.get("visible_emitted", -1)) == 0 \
			and int(sum.get("unresolved", -1)) == 0 and int(sum.get("fallback_broken", -1)) == 93 \
			and int(sum.get("sibling_smc", -1)) == 5 and int(sum.get("leaves", -1)) == 166,
		"P2-CENSUS-GC",
		"whole-payload GC census files=%d components=%d hidden=%d visible_emitted=%d unresolved=%d fallback_broken=%d sibling_smc=%d leaves=%d" % [
			files.size(), int(sum.get("components", -1)), int(sum.get("hidden", -1)),
			int(sum.get("visible_emitted", -1)), int(sum.get("unresolved", -1)),
			int(sum.get("fallback_broken", -1)), int(sum.get("sibling_smc", -1)),
			int(sum.get("leaves", -1)),
		]
	)


# --- GC interaction label --------------------------------------------------

func _check_gc_label() -> void:
	var strings: Dictionary = h.read_json(STRINGS_INTERACTABLES) as Dictionary
	var entries: Dictionary = strings.get("entries", {}) as Dictionary
	var label: String = str(entries.get("PromptDestroyDeployable", ""))
	var src: String = h.read_text("res://src/interact/loot_container.gd")
	var uses_authored: bool = src.find('st_upper("ST_Interactables", "PromptDestroyDeployable", "Destroy")') >= 0
	h.require(
		label == "Destroy" and uses_authored,
		"P2-GC-LABEL",
		"GC interaction label is the authored ST_Interactables.PromptDestroyDeployable='%s' row; the \"[F] [HOLD] \" keycap prefix is port copy" % label
	)
