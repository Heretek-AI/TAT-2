extends SceneTree
## P1 Lane T — street / car / gate / MACLEOD probe (S13–S20, KF15/16/18/23).
##
## Real Contract 02 Guildhall mission (same boot as E2E tier a2), then measures:
##   1. the KF16 car + its authored interaction: `[F] INTERACT`, the authored
##      horn event, the authored alarm flash (key times/values + 50 lm), and the
##      authored AI.Stim.Hearing.CarAlarm noise record;
##   2. KF15 alley dressing that IS authored: crates, truck ladder, weeds, and
##      the KF15 wall light. Barrels have no KF15 placement record and the
##      BARRON'S DEMOLITION banner has no extracted asset -> HARD_LIMIT lines;
##   3. KF16/KF18 gate: SM_Guildhall_Sign (4-surface letter band), two
##      SM_StatueGriffonA, and the white 10-bolt electrical plate texture;
##   4. KF23 MACLEOD: authored SM_SignMacleod placement at (116.6284, 53.2895,
##      22.6352), authored M_Crystal_Glow tint (1.0/0.361/0.078) and the
##      restored gold emission;
##   5. the authored wet path: gloomy preset ground_wetness=1.0, Guildhall
##      landscape Puddle layers, tat_landscape material present; the car beams
##      point down the wet gate approach.
##
## Run:
##   flock /tmp/opencode/tat2-godot.lock -c \
##     'tools/godot --headless --path game --script res://tests/probe_p1_street.gd'
##
## Prints P1_STREET PASS/FAIL; exits 1 on failure.

const CONTRACT_ORDER := 2
const MACLEOD_KF23_POS := Vector3(116.6284, 53.2895, 22.6352)
const MACLEOD_MAT := "/Game/Art/Effects/HotWire_Ride/M_Crystal_Glow"
const MACLEOD_TINT := Color(1.0, 0.361, 0.078)
const MACLEOD_ENERGY := 4.0
const ALLEY_CENTER := Vector3(-5.6, 24.46, 73.5)
const CAR_LENS_TARGET := Vector3(17.93, 19.88, 66.41)
const CAR_ROOT := Vector3(19.0, 18.5304, 66.3382)
const GATE_SIGN_POS := Vector3(10.04, 25.27, 48.6854)
const CRATE_MIN := 16
const WEED_MIN := 5

var _checks: int = 0
var _fails: int = 0
var _hard_limits: int = 0
var _noise_records: Array[Dictionary] = []
var _helpers: RefCounted
var _authored_cache: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, id: String, detail: String = "") -> bool:
	_checks += 1
	if ok:
		print("P1_STREET CHECK PASS ", id, " ", detail)
	else:
		_fails += 1
		printerr("P1_STREET CHECK FAIL ", id, " ", detail)
	return ok


func _hard_limit(id: String, detail: String) -> void:
	_hard_limits += 1
	print("P1_STREET HARD_LIMIT ", id, " ", detail)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var txt: String = FileAccess.get_file_as_string(path)
	if txt == "":
		return {}
	var parsed: Variant = JSON.parse_string(txt)
	return parsed as Dictionary if parsed is Dictionary else {}


func _geo_nodes(root: Node) -> Array:
	# Walk the tree instead of find_children(type=GeometryInstance3D): the
	# batched MultiMeshInstance3D nodes must be included too (crates, weeds,
	# ladders and the griffins are all MultiMesh batches in the real load).
	var out: Array = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children():
			stack.append(c)
			if c is GeometryInstance3D:
				out.append(c)
	return out


func _instances(gi: GeometryInstance3D) -> Array:
	var out: Array = []
	if gi is MultiMeshInstance3D:
		var mmi: MultiMeshInstance3D = gi as MultiMeshInstance3D
		if mmi.multimesh != null:
			for i: int in range(mmi.multimesh.instance_count):
				out.append(mmi.global_transform * mmi.multimesh.get_instance_transform(i).origin)
	elif gi is MeshInstance3D:
		out.append((gi as MeshInstance3D).global_position)
	return out


func _mesh_of(gi: GeometryInstance3D) -> Mesh:
	if gi is MeshInstance3D:
		return (gi as MeshInstance3D).mesh
	if gi is MultiMeshInstance3D:
		var mmi: MultiMeshInstance3D = gi as MultiMeshInstance3D
		if mmi.multimesh != null:
			return mmi.multimesh.mesh
	return null


func _nodes_with(root: Node, needle: String) -> Array:
	var out: Array = []
	for gi: GeometryInstance3D in _geo_nodes(root):
		if str(gi.get_meta("ue_mesh", "")).find(needle) >= 0:
			out.append(gi)
	return out


func _count_near(root: Node, needle: String, center: Vector3, radius: float) -> int:
	var count: int = 0
	for gi: GeometryInstance3D in _nodes_with(root, needle):
		for p: Vector3 in _instances(gi):
			if p.distance_to(center) <= radius:
				count += 1
	return count


func _find_nearest_node(root: Node, needle: String, center: Vector3, radius: float) -> Array:
	var best_gi: GeometryInstance3D = null
	var best_p: Vector3 = Vector3.ZERO
	var best_d: float = radius
	for gi: GeometryInstance3D in _nodes_with(root, needle):
		for p: Vector3 in _instances(gi):
			var d: float = p.distance_to(center)
			if d <= best_d:
				best_d = d
				best_p = p
				best_gi = gi
	return [best_gi, best_p, best_d]


## Headless limitation (measured): a MultiMesh keeps its instance buffer in the
## RenderingServer, and the dummy renderer returns identity transforms for it
## (see probe_niagara.gd). Placement checks for batched families therefore read
## the authored record from the generated level, and separately prove the real
## load built the family with the expected instance count. Plain MeshInstance3D
## families (car lenses, gate sign, MACLEOD) still use their runtime position.
func _authored_meshes(level_path: String) -> Array:
	if _authored_cache.has(level_path):
		return _authored_cache[level_path] as Array
	var d: Dictionary = _read_json(level_path)
	var m: Array = d.get("meshes", []) as Array
	_authored_cache[level_path] = m
	return m


func _authored_count_near(level_path: String, needle: String, center: Vector3, radius: float) -> int:
	var n: int = 0
	for m_var: Variant in _authored_meshes(level_path):
		if not (m_var is Dictionary):
			continue
		var m: Dictionary = m_var as Dictionary
		if str(m.get("mesh", "")).find(needle) < 0:
			continue
		var p_v: Variant = m.get("pos", null)
		if not (p_v is Array) or (p_v as Array).size() < 3:
			continue
		var pa: Array = p_v as Array
		var p := Vector3(float(pa[0]), float(pa[1]), float(pa[2]))
		if p.distance_to(center) <= radius:
			n += 1
	return n


func _loaded_instance_count(root: Node, needle: String) -> int:
	var n: int = 0
	for gi: GeometryInstance3D in _nodes_with(root, needle):
		if gi is MultiMeshInstance3D:
			var mmi: MultiMeshInstance3D = gi as MultiMeshInstance3D
			if mmi.multimesh != null:
				n += mmi.multimesh.instance_count
		elif gi is MeshInstance3D:
			n += 1
	return n


func _loaded_node_count(root: Node, needle: String) -> int:
	return _nodes_with(root, needle).size()


func _approx_color(a: Color, b: Color, eps: float = 0.02) -> bool:
	return absf(a.r - b.r) <= eps and absf(a.g - b.g) <= eps and absf(a.b - b.b) <= eps


func _on_noise(record: Dictionary) -> void:
	_noise_records.append(record)


func _run() -> void:
	await process_frame
	var helpers_scr: GDScript = load("res://tests/e2e/e2e_helpers.gd") as GDScript
	if helpers_scr == null:
		printerr("P1_STREET FAIL cannot load e2e_helpers.gd")
		print("P1_STREET FAIL checks=0 fails=1")
		quit(1)
		return
	_helpers = helpers_scr.new(self)
	var missing: Array = _helpers.call("boot_problems") as Array
	if not missing.is_empty():
		for m: Variant in missing:
			printerr("P1_STREET BOOT missing ", str(m))
		print("P1_STREET FAIL checks=0 fails=1")
		quit(1)
		return
	_helpers.call("snapshot_state")
	var res: Dictionary = await _helpers.call("instantiate_mission", CONTRACT_ORDER, 900, 1)
	var mission: Node = res.get("mission") as Node
	var timed_out: bool = bool(res.get("timed_out", true))
	if not _check(mission != null and not timed_out, "BOOT", "real Contract 02 Guildhall mission loaded timed_out=%s" % str(timed_out)):
		_helpers.call("restore_state")
		print("P1_STREET FAIL checks=%d fails=%d" % [_checks, _fails])
		quit(1)
		return

	var gs: Node = _helpers.call("game_state") as Node
	var map_id: String = str(gs.get("active_map_id")) if gs != null else ""
	_check(map_id == "guildhall", "MAP", "active_map_id=%s" % map_id)

	# --- KF15 alley: authored dressing present ------------------------------
	# Authored records: game/data/generated/levels/Guildhall/Guildhall_PeripheryA.
	var periph: String = "res://data/generated/levels/Guildhall/Guildhall_PeripheryA.tatlevel.json"
	var crates: int = _authored_count_near(periph, "/Props/Containers/Crates/", ALLEY_CENTER, 10.0)
	var loaded_crates: int = _loaded_instance_count(mission, "/Props/Containers/Crates/")
	_check(crates >= CRATE_MIN and loaded_crates >= crates, "KF15-CRATES", "authored_near_alley=%d min=%d loaded_map_instances=%d" % [crates, CRATE_MIN, loaded_crates])
	var ladders: int = _authored_count_near(periph, "SM_Automobile_Truck_Ladder", Vector3(-1.7, 22.9, 69.2), 3.0)
	var loaded_ladders: int = _loaded_instance_count(mission, "SM_Automobile_Truck_Ladder")
	_check(ladders == 2 and loaded_ladders >= ladders, "KF15-LADDER", "authored_near_alley=%d expected=2 loaded_map_instances=%d" % [ladders, loaded_ladders])
	var weeds_spike: int = _authored_count_near(periph, "SM_SpikeFlowerA", Vector3(-0.5, 24.8, 75.0), 8.0)
	var weeds_burdock: int = _authored_count_near(periph, "SM_sf2_burdock_02", Vector3(-0.5, 24.8, 75.0), 8.0)
	var loaded_weeds: int = _loaded_instance_count(mission, "SM_SpikeFlowerA") + _loaded_instance_count(mission, "SM_sf2_burdock_02")
	var weeds: int = weeds_spike + weeds_burdock
	_check(weeds >= WEED_MIN and loaded_weeds >= weeds, "KF15-WEEDS", "authored_near_alley=%d (spike=%d burdock=%d) min=%d loaded_map_instances=%d" % [weeds, weeds_spike, weeds_burdock, WEED_MIN, loaded_weeds])
	var wall_light: int = _authored_count_near(periph, "SM_LightSmC_Iron", Vector3(-6.18, 21.19, 75.05), 1.5)
	var loaded_wall_lights: int = _loaded_instance_count(mission, "SM_LightSmC_Iron")
	_check(wall_light >= 1 and loaded_wall_lights >= 1, "KF15-WALLLIGHT", "authored_near_alley=%d loaded_map_instances=%d" % [wall_light, loaded_wall_lights])

	# HARD_LIMIT: drums have no authored placement in the KF15 alley.
	var drums_alley: int = _authored_count_near(periph, "/Props/Containers/Barrels/", ALLEY_CENTER, 12.0)
	drums_alley += _authored_count_near(periph, "/Props/Containers/Casks/", ALLEY_CENTER, 12.0)
	var drums_map: int = _loaded_instance_count(mission, "SM_Metal_Barrel")
	if drums_alley == 0:
		_hard_limit("drums", "alley_records=0 authored_assets=SM_Metal_BarrelA/B/C (loaded_map_instances=%d) query=Containers/Barrels+Containers/Casks within 12 m of %s" % [drums_map, ALLEY_CENTER])

	# HARD_LIMIT: BARRON'S DEMOLITION has no extracted mesh/material/texture.
	var barron_hits: int = 0
	var barron_search: Array[String] = [
		"res://data/generated/levels/Guildhall/Guildhall_PeripheryA.tatlevel.json",
		"res://data/generated/levels/Guildhall/Guildhall_Geometry.tatlevel.json",
		"res://data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json",
		"res://data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI.tatlevel.json",
		"res://data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI_3rdFloor.tatlevel.json",
		"res://data/generated/levels/Guildhall/Guildhall_P.tatlevel.json",
		"res://data/generated/levels/Guildhall/Guildhall_Contract_02.tatlevel.json",
		"res://data/generated/levels/Guildhall/Facade_Apartment_CarUnderpass.tatlevel.json",
		"res://data/generated/levels/Guildhall/Facade_Storefront_Cluster.tatlevel.json",
	]
	for p: String in barron_search:
		if not FileAccess.file_exists(p):
			continue
		var low: String = FileAccess.get_file_as_string(p).to_lower()
		if low.find("barron") >= 0 or low.find("demolition") >= 0:
			barron_hits += 1
	var banners: int = _loaded_instance_count(mission, "SM_BannerB")
	banners += _loaded_instance_count(mission, "SM_BannerWall_IronBeam")
	if barron_hits == 0:
		_hard_limit("banner", "BARRON'S DEMOLITION absent: 0 name hits in 9 Guildhall level JSONs, banners_in_map=%d (SM_BannerB/SM_BannerWall_IronBeam are the KILCAIRN heraldic T_BannerSet_D set)" % banners)

	# --- KF16 car + authored interaction -----------------------------------
	var lens: Array = _find_nearest_node(mission, "SM_Automobile_Lights_B", CAR_LENS_TARGET, 1.0)
	var lens_ok: bool = not lens.is_empty() and lens[0] != null
	_check(lens_ok, "KF16-CAR-LENS", "SM_Automobile_Lights_B dist=%s" % (("%.3f" % float(lens[2])) if lens_ok else "missing"))
	var cabin: Array = _find_nearest_node(mission, "SM_Automobile_Cabin_A", Vector3(18.79, 20.15, 66.35), 1.0)
	_check(not cabin.is_empty() and cabin[0] != null, "KF16-CAR-BODY", "SM_Automobile_Cabin_A dist=%s" % (("%.3f" % float(cabin[2])) if not cabin.is_empty() and cabin[0] != null else "missing"))
	var cars: Array = get_nodes_in_group("street_car")
	var car: Node = (cars[0] as Node) if cars.size() == 1 else null
	_check(car != null, "KF16-CAR-INTERACT", "street_car nodes=%d expected=1" % cars.size())
	if car != null:
		var prompt: String = str(car.call("get_interact_prompt"))
		_check(prompt == "[F] INTERACT", "KF16-CAR-PROMPT", "prompt=%s" % prompt)
		_check(int(car.call("get_headlight_count")) == 2, "KF16-CAR-LIGHTS", "headlight_count=%d" % int(car.call("get_headlight_count")))
		# Authored key sampling (CurveFloat_2) without waiting 10 s.
		var f05: float = float(car.call("flash_value_at", 0.5))
		var f15: float = float(car.call("flash_value_at", 1.5))
		var f00: float = float(car.call("flash_value_at", 0.0))
		_check(absf(f05 - 1.0) <= 0.001 and absf(f15) <= 0.001 and absf(f00) <= 0.001, "KF16-FLASH-CURVE", "curve 0.0=%.2f 0.5=%.2f 1.5=%.2f authored keys 0@0/1@0.2..1.0/0@1.1" % [f00, f05, f15])
		_check(float(car.call("get_flash_energy")) > 1.6, "KF16-FLASH-LEVEL", "flash_energy=%.3f authored 50 lm via light_energy_for_intensity" % float(car.call("get_flash_energy")))
		var rest_lens: float = float(car.call("get_lens_emission_energy"))
		_check(rest_lens <= 0.001, "KF16-LENS-OFF", "lens emission at rest=%.3f" % rest_lens)
		var base_l: float = float(car.call("get_headlight_energy", 0))
		var nb: Node = _helpers.call("noise_bus") as Node
		_noise_records.clear()
		if nb != null and nb.has_signal("noise_record_emitted"):
			nb.connect("noise_record_emitted", Callable(self, "_on_noise"))
		car.call("interact", null)
		await create_timer(0.5).timeout
		var horn_ok: bool = false
		var am: Node = _helpers.call("audio_manager") as Node
		if am != null and am.has_method("has_real_clip"):
			horn_ok = bool(am.call("has_real_clip", "car_horn"))
		var horn_played: bool = bool(car.get_meta("horn_played", false))
		_check(horn_ok and horn_played, "KF16-HORN-CLIP", "has_real_clip(car_horn)=%s play_car_horn=%s authored event=%s" % [str(horn_ok), str(horn_played), str(car.get_meta("last_horn_event", ""))])
		_check(int(car.call("get_honk_count")) == 1, "KF16-HONK-COUNT", "honk_count=%d" % int(car.call("get_honk_count")))
		var stim_ok: bool = false
		for rec: Dictionary in _noise_records:
			if str(rec.get("tag", "")) == "car_alarm" and str(rec.get("stim_tag", "")) == "AI.Stim.Hearing.CarAlarm":
				stim_ok = true
		_check(stim_ok, "KF16-CAR-STIM", "noise records=%d authored StimTag=AI.Stim.Hearing.CarAlarm" % _noise_records.size())
		var hd_scr: GDScript = load("res://src/ai/hearing_data.gd") as GDScript
		var stim_range: float = -1.0
		if hd_scr != null:
			stim_range = float(hd_scr.call("max_range_m", "car_alarm"))
		_check(absf(stim_range - 50.0) <= 0.01, "KF16-CAR-STIM-RANGE", "HearingData.max_range_m(car_alarm)=%.2f authored 50.0" % stim_range)
		if nb != null and nb.has_signal("noise_record_emitted"):
			nb.disconnect("noise_record_emitted", Callable(self, "_on_noise"))
		var lit_l: float = float(car.call("get_headlight_energy", 0))
		var lit_lens: float = float(car.call("get_lens_emission_energy"))
		_check(float(car.call("get_last_flash")) > 0.9, "KF16-FLASH-ON", "flash=%.3f after 0.5 s" % float(car.call("get_last_flash")))
		_check(lit_l > base_l + 1.6, "KF16-HEADLIGHT-LIT", "spot energy %.3f -> %.3f" % [base_l, lit_l])
		_check(lit_lens > 1.9, "KF16-LENS-FLASH", "lens emission %.3f -> %.3f authored 2.0" % [rest_lens, lit_lens])
		car.call("stop_alarm")
		_check(float(car.call("get_headlight_energy", 0)) <= base_l + 0.001 and float(car.call("get_lens_emission_energy")) <= 0.001 and not bool(car.call("is_alarm_active")), "KF16-FLASH-OFF", "alarm stopped, base restored")
		# The two authored-placement beams must point down the gate approach.
		var aim_ok: bool = true
		var spots: Array = car.get("headlight_spots") as Array
		for i: int in range(spots.size()):
			var sp: SpotLight3D = spots[i] as SpotLight3D
			var target: Vector3 = Vector3(11.0, 18.6, 54.0) if i == 0 else Vector3(9.0, 18.6, 57.0)
			var fwd: Vector3 = -sp.global_transform.basis.z
			var to: Vector3 = (target - sp.global_position).normalized()
			if fwd.dot(to) < 0.8:
				aim_ok = false
		_check(aim_ok, "KF16-BEAM-AIM", "both wet-cobble beams point at the gate approach")

	# --- KF16/KF18 gate -----------------------------------------------------
	var gate: Array = _find_nearest_node(mission, "SM_Guildhall_Sign", GATE_SIGN_POS, 1.0)
	var gate_ok: bool = not gate.is_empty() and gate[0] != null
	var gate_surfaces: int = -1
	if gate_ok:
		var gmesh: Mesh = _mesh_of(gate[0] as GeometryInstance3D)
		if gmesh != null:
			gate_surfaces = gmesh.get_surface_count()
	_check(gate_ok and gate_surfaces == 4, "KF16-GATE-SIGN", "SM_Guildhall_Sign dist=%s surfaces=%d expected 4 (letters+crest)" % [("%.3f" % float(gate[2])) if gate_ok else "missing", gate_surfaces])
	var griffins: int = _authored_count_near(periph, "SM_StatueGriffonA", Vector3(10.1, 23.45, 24.75), 6.0)
	var loaded_griffins: int = _loaded_instance_count(mission, "SM_StatueGriffonA")
	_check(griffins == 2 and loaded_griffins >= 2, "KF18-GRIFFINS", "authored SM_StatueGriffonA=%d expected=2 loaded_map_instances=%d at x5.65/14.55 z24.75" % [griffins, loaded_griffins])
	var transformers: int = _count_near(mission, "SM_ElectricalTransformer_Main", Vector3.ZERO, 100000.0)
	var mats: Dictionary = _read_json("res://data/generated/materials.json")
	var xf_v: Variant = mats.get("/Game/Art/Gameplay/ElectricPowerSource/ElectricalTransformer/MI_ElectricalTransformer", null)
	var xf: Dictionary = {}
	if xf_v is Dictionary:
		xf = xf_v as Dictionary
	var xf_texs_v: Variant = xf.get("texs", {})
	var xf_texs: Dictionary = {}
	if xf_texs_v is Dictionary:
		xf_texs = xf_texs_v as Dictionary
	var xf_tex: String = str(xf_texs.get("albedo", ""))
	_check(transformers > 0 and xf_tex.ends_with("T_ElectricalTransformer_D.png"), "KF18-GEAR-PLATE", "SM_ElectricalTransformer_Main=%d plate_albedo=%s" % [transformers, xf_tex])

	# --- KF23 MACLEOD -------------------------------------------------------
	var mac: Array = _find_nearest_node(mission, "SM_SignMacleod", MACLEOD_KF23_POS, 2.0)
	var mac_ok: bool = not mac.is_empty() and mac[0] != null
	_check(mac_ok, "KF23-MACLEOD-PLACE", "SM_SignMacleod dist=%s authored KF23 pos=%s" % [("%.3f" % float(mac[2])) if mac_ok else "missing", MACLEOD_KF23_POS])
	var mac_emission: bool = false
	var mac_color: Color = Color.BLACK
	var mac_energy: float = -1.0
	if mac_ok:
		var gi: GeometryInstance3D = mac[0] as GeometryInstance3D
		var mat: Material = null
		if gi is MultiMeshInstance3D:
			mat = (gi as MultiMeshInstance3D).material_override
		elif gi is MeshInstance3D:
			var mmi: MeshInstance3D = gi as MeshInstance3D
			mat = mmi.get_surface_override_material(0)
			if mat == null:
				mat = mmi.get_active_material(0)
		if mat is StandardMaterial3D:
			var sm: StandardMaterial3D = mat as StandardMaterial3D
			mac_emission = sm.emission_enabled
			mac_color = sm.emission
			mac_energy = sm.emission_energy_multiplier
	_check(mac_emission and _approx_color(mac_color, MACLEOD_TINT) and mac_energy >= MACLEOD_ENERGY - 0.01, "KF23-MACLEOD-EMISSIVE", "emission=%s colour=%s energy=%.2f authored tint=M_Crystal_Glow/Emissive Amount 2" % [str(mac_emission), str(mac_color), mac_energy])

	# --- Authored wet path --------------------------------------------------
	var gloom: Dictionary = _read_json("res://data/generated/weather/gloomy.json")
	var wet: Variant = (gloom.get("rain", {}) as Dictionary).get("ground_wetness", null)
	_check(wet is float and absf(float(wet) - 1.0) <= 0.001, "WET-PRESET", "gloomy ground_wetness=%s authored" % str(wet))
	var land: Dictionary = _read_json("res://data/generated/levels/Guildhall/Guildhall_Landscape.tatlevel.json")
	var puddle_components: int = 0
	for comp: Variant in (land.get("landscapes", []) as Array):
		for layer: Variant in ((comp as Dictionary).get("layers", []) as Array):
			if str((layer as Dictionary).get("layer", "")) == "Puddle":
				puddle_components += 1
	_check(puddle_components > 0, "WET-PUDDLE-LAYERS", "Guildhall landscape Puddle layer bindings=%d" % puddle_components)
	var landscape_mats: int = 0
	for gi: GeometryInstance3D in _geo_nodes(mission):
		if gi is MeshInstance3D:
			var mi: MeshInstance3D = gi as MeshInstance3D
			if mi.mesh == null:
				continue
			for s: int in range(mi.mesh.get_surface_count()):
				var m: Material = mi.get_active_material(s)
				if m is ShaderMaterial:
					var sh: Shader = (m as ShaderMaterial).shader
					if sh != null and (str(sh.resource_path).contains("tat_landscape") or sh.code.contains("groundwet")):
						landscape_mats += 1
	_check(landscape_mats > 0, "WET-SHADER", "tat_landscape material instances=%d" % landscape_mats)

	# --- summary ------------------------------------------------------------
	var mission_free: Node = mission
	mission_free.queue_free()
	await process_frame
	_helpers.call("restore_state")
	print("P1_STREET SUMMARY checks=%d fails=%d hard_limits=%d" % [_checks, _fails, _hard_limits])
	if _fails == 0:
		print("P1_STREET PASS")
		quit(0)
	else:
		print("P1_STREET FAIL fails=%d" % _fails)
		quit(1)
