extends SceneTree
## T07 RENDER probe — lighting budget / exposure / IBL / weather contract.
##
## Headless, no GPU, no Vulkan, no frame capture. It re-derives the authored
## light list from the generated level data with the loader's *own* acceptance
## and dedupe rule (LevelLoader.light_record_accepted / light_record_key) and the
## loader's *own* allocation plan (LevelLoader.plan_light_selection), then applies
## each shipped night preset to a throwaway Environment and asserts the authored
## values. Run:
##
##   tools/godot --headless --path game --script res://tests/probe_render_t07.gd
##
## Exit code 0 = every assertion passed. This is the S3 red proof (before the
## fix: Guildhall room coverage 48.1 %, gloom exposure 1.00) and the S6 green
## proof (after: coverage >= 75 %, exposure 1.15).

const LevelLoader := preload("res://src/core/level_loader.gd")
const WeatherProfile := preload("res://src/core/weather_profile.gd")
const WeatherVisuals := preload("res://src/core/weather_visuals.gd")
const MobileProfile := preload("res://src/core/mobile_profile.gd")
## Loaded lazily: mission_controller.gd references the GameState/GameData
## autoload globals, which are not registered yet while this script is parsed.
const MISSION_SCRIPT_PATH := "res://src/missions/mission_controller.gd"

## A room bubble is COVERED when at least this many authored lights from it are
## instanced. 1 is the fair-allocation promise itself: no authored room may end
## up with zero lights while another room takes many.
const ROOM_MIN_LIGHTS := 1
## Fine bubble used for the second coverage column (a real room is 6-12 m wide,
## so an 8 m bubble is one room and a 16 m bubble is 1-2 rooms).
const BUBBLE_M := 8.0

var fails: int = 0


func _check(cond: bool, title: String, detail: String) -> void:
	if cond:
		print("PASS: ", title, " (", detail, ")")
	else:
		printerr("FAIL: ", title, " (", detail, ")")
		fails += 1


func _initialize() -> void:
	call_deferred("_run")


func _sublevels_for(map_id: String, order: int) -> Array[String]:
	var script: Script = load(MISSION_SCRIPT_PATH) as Script
	var out: Array[String] = []
	if script == null:
		return out
	var mc: Node = script.new() as Node
	if mc == null:
		return out
	var raw: Variant = mc.call("_map_id_to_sublevels", map_id, order)
	if raw is Array:
		for p: Variant in (raw as Array):
			out.append(str(p))
	mc.free()
	return out


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


## Authored light records exactly as the loader collects them: acceptance rule,
## then the integer-metre cross-sublevel dedupe.
func _authored_lights(sublevels: Array[String], owner: Dictionary) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for path: String in sublevels:
		var d: Dictionary = _read_json(path)
		for l_v: Variant in (d.get("lights", []) as Array):
			if not (l_v is Dictionary):
				continue
			var l: Dictionary = l_v as Dictionary
			if not LevelLoader.light_record_accepted(l):
				continue
			var key: String = LevelLoader.light_record_key(l)
			if seen.has(key):
				continue
			seen[key] = true
			owner[key] = path.get_file()
			out.append(l)
	return out


func _spawn_points(sublevels: Array[String]) -> Array:
	var out: Array = []
	for path: String in sublevels:
		var d: Dictionary = _read_json(path)
		for m_v: Variant in (d.get("markers", []) as Array):
			if not (m_v is Dictionary):
				continue
			var m: Dictionary = m_v as Dictionary
			if "PlayerStart" not in str(m.get("class", "")):
				continue
			var p: Array = m.get("pos", [0, 0, 0]) as Array
			out.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	return out


func _active_rect_lights(sublevels: Array[String]) -> int:
	var n: int = 0
	for path: String in sublevels:
		var d: Dictionary = _read_json(path)
		for r_v: Variant in (d.get("rect_lights", []) as Array):
			if not (r_v is Dictionary):
				continue
			var r: Dictionary = r_v as Dictionary
			if float(r.get("intensity", 0.0)) > float(LevelLoader.RECT_LIGHT_OFF_THRESHOLD):
				n += 1
	return n


func _intensity(l: Dictionary) -> float:
	var v: Variant = l.get("intensity")
	return 10.0 if v == null else float(v)


func _radius(l: Dictionary) -> float:
	var v: Variant = l.get("radius")
	return 0.0 if v == null else float(v)


func _cell_of(l: Dictionary, cell: float) -> Vector3i:
	return LevelLoader.light_room_cell(l, cell)


## The pre-T07 rule, kept here so the defect stays reproducible on any tree:
## rank every accepted light by authored energy (`_light_score` via
## _prioritize_lights), keep the global top (budget - forced), then append the
## gate heroes. Identical to `_select_lights` at 38e7b03
## (`git show 38e7b03:game/src/core/level_loader.gd`).
func _legacy_global_cut(ordered: Array, budget: int, map_hint: String, ll: Node) -> Array:
	var forced: Array = []
	var head: Array = []
	for l_v: Variant in ordered:
		if not (l_v is Dictionary):
			continue
		var l: Dictionary = l_v as Dictionary
		if bool(ll.call("_is_gate_hero_light", l, map_hint)):
			forced.append(l)
			continue
		if head.size() < budget:
			head.append(l)
	var keep: int = clampi(budget - forced.size(), 0, head.size())
	var out: Array = []
	for i: int in range(keep):
		out.append(head[i])
	for f: Variant in forced:
		if out.size() >= budget:
			break
		out.append(f)
	return out


## Covered count for one selection: how many authored bubbles hold at least
## ROOM_MIN_LIGHTS of the selected lights.
func _covered_cells(auth: Dictionary, lights: Array, cell: float) -> int:
	var kept: Dictionary = {}
	for l: Dictionary in lights:
		var k: Vector3i = _cell_of(l, cell)
		kept[k] = int(kept.get(k, 0)) + 1
	var n: int = 0
	for k: Vector3i in auth.keys():
		if int(kept.get(k, 0)) >= ROOM_MIN_LIGHTS:
			n += 1
	return n


func _cell_counts(lights: Array, cell: float) -> Dictionary:
	var out: Dictionary = {}
	for l: Dictionary in lights:
		var k: Vector3i = _cell_of(l, cell)
		out[k] = int(out.get(k, 0)) + 1
	return out


func _poi_count(lights: Array, owner: Dictionary) -> int:
	var n: int = 0
	for l: Dictionary in lights:
		if "Building_Guildhall" in str(owner.get(LevelLoader.light_record_key(l), "")):
			n += 1
	return n


func _audit_map(map_id: String, ll: Node, order: int) -> void:
	var sublevels: Array[String] = _sublevels_for(map_id, order)
	if sublevels.is_empty():
		_check(false, "%s load set" % map_id, "no sublevels resolved")
		return
	var owner: Dictionary = {}
	var authored: Array = _authored_lights(sublevels, owner)
	var spawns: Array = _spawn_points(sublevels)
	var map_hint: String = LevelLoader._map_hint_from_paths(sublevels)
	var rect_live: int = _active_rect_lights(sublevels)
	var budget_total: int = int(MobileProfile.max_lights())
	var generic_budget: int = maxi(budget_total - rect_live, 0)
	# Same two steps as load_sublevels_async: spawn-area preference, then the
	# fair per-room allocation.
	var ordered: Array = ll.call("_prioritize_lights", authored, spawns)
	var plan: Dictionary = ll.call("plan_light_selection", ordered, generic_budget, map_hint)
	var selection: Array = plan["selection"] as Array
	var stats: Dictionary = plan["stats"] as Dictionary
	var kept: Array = []
	for sel_v: Variant in selection:
		kept.append((sel_v as Dictionary)["info"] as Dictionary)
	var legacy: Array = _legacy_global_cut(ordered, generic_budget, map_hint, ll)

	# Per-room coverage on the allocation grid and on the finer 8 m bubble grid.
	var coarse: float = float(LevelLoader.LIGHT_ROOM_CELL_M)
	var cells_auth: Dictionary = _cell_counts(authored, coarse)
	var bubbles_auth: Dictionary = _cell_counts(authored, BUBBLE_M)
	var covered: int = _covered_cells(cells_auth, kept, coarse)
	var covered_bubbles: int = _covered_cells(bubbles_auth, kept, BUBBLE_M)
	var covered_legacy: int = _covered_cells(cells_auth, legacy, coarse)
	var covered_bubbles_legacy: int = _covered_cells(bubbles_auth, legacy, BUBBLE_M)
	var poi_auth: int = _poi_count(authored, owner)
	var poi_kept: int = _poi_count(kept, owner)
	var poi_legacy: int = _poi_count(legacy, owner)

	# Kept-lights authored intensity distribution: the old global cut kept only
	# the map's brightest fixtures.
	var kept_intensity: Array[float] = []
	var kept_radius_ge6: int = 0
	for l: Dictionary in kept:
		kept_intensity.append(_intensity(l))
		if _radius(l) >= 6.0:
			kept_radius_ge6 += 1
	kept_intensity.sort()

	print("")
	print("== %s ==" % map_id)
	print("load_set_files=%d map_hint=%s rect_live=%d budget_total=%d generic_budget=%d"
		% [sublevels.size(), map_hint, rect_live, budget_total, generic_budget])
	print("authored_records=%d (after acceptance+integer-position dedupe) instanced=%d (%.1f %%) spawn_points=%d"
		% [authored.size(), kept.size(), 100.0 * float(kept.size()) / maxf(float(authored.size()), 1.0), spawns.size()])
	print("rooms %d m: authored=%d (%d non-protected + %d protected-only, see plan stats) | fair covered=%d (%.1f %%) | pre-T07 covered=%d (%.1f %%)"
		% [int(coarse), cells_auth.size(), int(stats.get("cells", 0)), cells_auth.size() - int(stats.get("cells", 0)),
		covered, 100.0 * float(covered) / maxf(float(cells_auth.size()), 1.0),
		covered_legacy, 100.0 * float(covered_legacy) / maxf(float(cells_auth.size()), 1.0)])
	print("rooms %.0f m: authored=%d | fair covered=%d (%.1f %%) | pre-T07 covered=%d (%.1f %%)"
		% [BUBBLE_M, bubbles_auth.size(), covered_bubbles, 100.0 * float(covered_bubbles) / maxf(float(bubbles_auth.size()), 1.0),
		covered_bubbles_legacy, 100.0 * float(covered_bubbles_legacy) / maxf(float(bubbles_auth.size()), 1.0)])
	print("POI building: authored=%d | fair=%d | pre-T07=%d" % [poi_auth, poi_kept, poi_legacy])

	# Per-sublevel table (the before/after the report quotes): authored count,
	# lights kept by each rule, and how many room bubbles each rule covers.
	var sources: Array[String] = []
	for l: Dictionary in authored:
		var src: String = str(owner.get(LevelLoader.light_record_key(l), "?"))
		if not sources.has(src):
			sources.append(src)
	sources.sort()
	print("per-sublevel                authored  fair  pre-T07 | rooms  fair  pre-T07")
	for src: String in sources:
		var a_src: Array = []
		var f_src: Array = []
		var l_src: Array = []
		for l: Dictionary in authored:
			if str(owner.get(LevelLoader.light_record_key(l), "?")) == src:
				a_src.append(l)
		for l: Dictionary in kept:
			if str(owner.get(LevelLoader.light_record_key(l), "?")) == src:
				f_src.append(l)
		for l: Dictionary in legacy:
			if str(owner.get(LevelLoader.light_record_key(l), "?")) == src:
				l_src.append(l)
		var src_auth: Dictionary = _cell_counts(a_src, coarse)
		print("  %-26s %8d %5d %8d | %5d %5d %8d"
			% [src.replace(".tatlevel.json", ""), a_src.size(), f_src.size(), l_src.size(),
			src_auth.size(), _covered_cells(src_auth, f_src, coarse), _covered_cells(src_auth, l_src, coarse)])
	print("kept: shadows=%d forced=%d | authored intensity p10/p50/p90=%.2f/%.2f/%.2f | kept radius>=6m=%d"
		% [int(stats.get("hero_shadows", 0)), int(stats.get("forced", 0)),
		kept_intensity[int(0.1 * (kept_intensity.size() - 1))] if not kept_intensity.is_empty() else -1.0,
		kept_intensity[int(0.5 * (kept_intensity.size() - 1))] if not kept_intensity.is_empty() else -1.0,
		kept_intensity[int(0.9 * (kept_intensity.size() - 1))] if not kept_intensity.is_empty() else -1.0,
		kept_radius_ge6])

	if map_id == "guildhall":
		# 976 authored records in the 15-file load set; the loader's integer-
		# position dedupe drops 62 duplicates -> 914. (RE-D's "915 deduped" does
		# not reproduce; the undeduped sum of the 15 files is 976, not 999.)
		_check(authored.size() == 914, "Guildhall authored light records", "records=%d expected 914" % authored.size())
		_check(kept.size() + rect_live == budget_total, "budget is fully spent", "kept=%d + rect=%d == %d" % [kept.size(), rect_live, budget_total])
		_check(float(covered) >= 0.75 * float(cells_auth.size()), "room coverage >= 75 % of 16 m cells",
			"covered=%d/%d" % [covered, cells_auth.size()])
		_check(int(stats.get("cells", 0)) > 0 and int(stats.get("covered", 0)) >= int(0.75 * float(stats.get("cells", 1))),
			"loader plan stats agree on >= 75 % non-protected bubble coverage",
			"plan covered=%d/%d" % [int(stats.get("covered", 0)), int(stats.get("cells", 0))])
		_check(covered > covered_legacy, "fair allocation beats the pre-T07 global cut",
			"fair=%d pre-T07=%d" % [covered, covered_legacy])
		_check(covered_bubbles > covered_bubbles_legacy, "8 m bubbles beat the pre-T07 global cut",
			"fair=%d pre-T07=%d" % [covered_bubbles, covered_bubbles_legacy])
		_check(poi_kept >= 40, "POI building keeps its authored interior lamps", "poi=%d/%d (pre-T07 %d)" % [poi_kept, poi_auth, poi_legacy])
		# Protected lights: the six KF16 gate lights and the contract-2 safe-room
		# wall spot must be in the selection regardless of the fair share.
		var gate: int = 0
		var safe_room: bool = false
		for l: Dictionary in kept:
			var p: Array = l.get("pos", [0, 0, 0]) as Array
			var gp: Vector3 = Vector3(float(p[0]), float(p[1]), float(p[2]))
			if gp.distance_to(LevelLoader.HERO_LIGHT_POINT) <= 10.0:
				gate += 1
			if gp.distance_to(Vector3(126.2758, 27.1426, -2.4736)) <= 1.0:
				safe_room = true
		_check(gate == 6, "six KF16 gate hero lights survive the fair share", "gate=%d" % gate)
		_check(safe_room, "contract-2 safe-room wall spot survives the fair share",
			"forced=%d" % int(stats.get("forced", 0)))
		_check(int(stats.get("hero_shadows", 0)) == 6, "six hero shadow casters", "shadows=%d" % int(stats.get("hero_shadows", 0)))
	elif map_id == "thieves_den":
		_check(kept.size() == authored.size(), "Den keeps every authored practical (budget not binding)",
			"kept=%d authored=%d" % [kept.size(), authored.size()])


func _preset_of(map_id: String) -> Dictionary:
	return WeatherProfile.preset_for_map(map_id)


func _audit_presets() -> void:
	print("")
	print("== presets / exposure / grade ==")
	var gh: Dictionary = _preset_of("guildhall")
	var den: Dictionary = _preset_of("thieves_den")
	var lobby: Dictionary = _preset_of("main_menu")
	_check(str(gh.get("preset", "")) == "gloomy", "Guildhall preset", "preset=%s" % str(gh.get("preset", "")))
	_check(WeatherProfile.is_night_preset(gh), "gloomy is a night preset", "is_night=%s" % str(WeatherProfile.is_night_preset(gh)))
	_check(not WeatherProfile.is_night_preset(_preset_of("old_manor")), "Old Manor (dense_fog_old_manor) is not re-graded",
		"preset=%s" % str(_preset_of("old_manor").get("preset", "")))

	for entry: Array in [["guildhall", gh], ["thieves_den", den], ["main_menu", lobby]]:
		var map_id: String = str(entry[0])
		var preset: Dictionary = entry[1]
		var env := Environment.new()
		var moon := DirectionalLight3D.new()
		var ok: bool = WeatherProfile.apply_environment(env, moon, preset)
		var ibl: Dictionary = WeatherProfile.sky_ibl_state(preset)
		print("%s: preset=%s applied=%s tonemap=%d exposure=%.3f ambient_energy=%.3f ambient_color=%s sky_contribution=%.2f fog_density=%.5f fog_height_density=%.5f fog_sky_affect=%.2f moon_energy=%.3f moon_angle=%.1f ssil=%s ssao=%s sdfgi=%s"
			% [map_id, str(preset.get("preset", "")), str(ok), env.tonemap_mode, env.tonemap_exposure,
			env.ambient_light_energy, str(env.ambient_light_color), env.ambient_light_sky_contribution,
			env.fog_density, env.fog_height_density, env.fog_sky_affect, moon.light_energy,
			moon.light_angular_distance, str(env.ssil_enabled), str(env.ssao_enabled), str(env.sdfgi_enabled)])
		print("   authored cubemap=%s converted=%s available=%s (TextureCube 512x512 PF_FloatRGBA in the source dump)"
			% [str(ibl.get("cubemap_ue_path", "")), str(ibl.get("cubemap_res_path", "")), str(ibl.get("available", false))])
		var pp: Dictionary = preset.get("postprocess", {})
		print("   grade: white_temp=%s vignette=%s film_slope=%s film_toe=%s gain_shadows=%s gain_highlights=%s gamma_highlights=%s bloom=%.3f bias=%s"
			% [str(pp.get("white_temp")), str(pp.get("vignette_intensity")), str(pp.get("film_slope")),
			str(pp.get("film_toe")), str(pp.get("gain_shadows")), str(pp.get("gain_highlights")),
			str(pp.get("gamma_highlights")), float(pp.get("bloom_intensity", 0.0)), str(pp.get("auto_exposure_bias"))])
		if map_id == "guildhall":
			_check(env.tonemap_mode == Environment.TONE_MAPPER_AGX, "Guildhall tonemapper is AGX", "mode=%d" % env.tonemap_mode)
			_check(env.tonemap_exposure >= WeatherProfile.NIGHT_EXPOSURE - 0.0001,
				"Guildhall takes the authored night exposure anchor",
				"exposure=%.3f anchor=%.2f" % [env.tonemap_exposure, WeatherProfile.NIGHT_EXPOSURE])
			_check(is_equal_approx(env.ambient_light_energy, 0.16), "Guildhall ambient energy is authored 2.0 x 0.08",
				"ambient=%.3f" % env.ambient_light_energy)
			_check(is_equal_approx(env.fog_density, 0.16 * WeatherProfile.FOG_DENSITY_SCALE),
				"Guildhall fog density is authored gloom x calibration",
				"fog=%.5f" % env.fog_density)
			_check(env.fog_height_density > 0.0, "Guildhall consumes the authored fog height falloff",
				"fog_height_density=%.5f" % env.fog_height_density)
			_check(is_equal_approx(moon.light_angular_distance, 25.0), "moon takes the authored LightSourceAngle",
				"angular_distance=%.1f" % moon.light_angular_distance)
			_check(env.ambient_light_sky_contribution == 0.0,
				"sky contribution stays 0 until the authored cubemap is loadable",
				"sky_contribution=%.2f available=%s" % [env.ambient_light_sky_contribution, str(ibl.get("available", false))])
			_check(str(ibl.get("cubemap_ue_path", "")) != "", "Guildhall preset authors a SkyLight cubemap",
				"cubemap=%s" % str(ibl.get("cubemap_ue_path", "")))
			_check(env.ssil_enabled and not env.sdfgi_enabled, "GI stand-in is SSIL by default, SDFGI opt-in",
				"ssil=%s sdfgi=%s" % [str(env.ssil_enabled), str(env.sdfgi_enabled)])
		if map_id == "thieves_den":
			_check(env.fog_height_density == 0.0, "Den keeps uniform fog (indoor preset)", "fog_height_density=%.5f" % env.fog_height_density)
			_check(is_equal_approx(moon.light_angular_distance, 5.0), "Den moon takes the authored 5 deg angle",
				"angular_distance=%.1f" % moon.light_angular_distance)
		moon.free()

	# Authored EV compensation curve + the prep-stage grade hand-off for T05.
	_check(is_equal_approx(WeatherProfile.ev_curve_bias(-3.0), -4.0), "authored EV curve saturates at -4 EV",
		"bias(-3.0)=%.2f" % WeatherProfile.ev_curve_bias(-3.0))
	_check(is_equal_approx(WeatherProfile.ev_curve_bias(-10.1), -2.0), "authored EV curve midpoint",
		"bias(-10.1)=%.2f" % WeatherProfile.ev_curve_bias(-10.1))
	var stage: Dictionary = WeatherProfile.stage_grade_values(gh)
	print("stage_grade(gloomy)=%s" % str(stage))
	_check(is_equal_approx(float(stage.get("tonemap_exposure", -1.0)), WeatherProfile.NIGHT_EXPOSURE),
		"prep-stage hand-off uses the gameplay exposure anchor", "exposure=%.2f" % float(stage.get("tonemap_exposure", -1.0)))
	_check(is_equal_approx(float(stage.get("ambient_light_energy", -1.0)), 0.16),
		"prep-stage hand-off uses the gameplay ambient (not 1.8)", "ambient=%.2f" % float(stage.get("ambient_light_energy", -1.0)))

	# Sky: the authored night calibration must reach the Guildhall preset.
	var sky_moon := DirectionalLight3D.new()
	var sky: Sky = WeatherVisuals.make_sky(gh, sky_moon)
	var sm: ShaderMaterial = sky.sky_material as ShaderMaterial
	var haze_amt: float = float(sm.get_shader_parameter("haze_amount"))
	var den_sm: ShaderMaterial = WeatherVisuals.make_sky(den, sky_moon).sky_material as ShaderMaterial
	print("sky(gloomy): haze_amount=%.2f cloud_haze=%.3f cloud_coverage=%.3f star_amount=%.3f | den haze_amount=%.2f"
		% [haze_amt, float(sm.get_shader_parameter("cloud_haze")), float(sm.get_shader_parameter("cloud_coverage")),
		float(sm.get_shader_parameter("star_amount")), float(den_sm.get_shader_parameter("haze_amount"))])
	_check(haze_amt > 0.0, "Guildhall gets the documented warm sky haze (was dead code)",
		"haze_amount=%.2f" % haze_amt)
	_check(float(den_sm.get_shader_parameter("haze_amount")) == 0.0, "Den keeps zero warm sky haze",
		"den=%.2f" % float(den_sm.get_shader_parameter("haze_amount")))
	_check(float(den_sm.get_shader_parameter("cloud_coverage")) == 0.0,
		"Den authors no volumetric clouds (dead field now consumed)",
		"cloud_coverage=%.2f" % float(den_sm.get_shader_parameter("cloud_coverage")))
	sky_moon.free()


func _run() -> void:
	print("T07 render probe — headless, no GPU")
	var ll: Node = (LevelLoader as Script).new()
	_audit_map("guildhall", ll, 2)
	_audit_map("thieves_den", ll, 1)
	_audit_presets()
	ll.free()
	print("")
	print("T07_SUMMARY: fails=%d" % fails)
	quit(0 if fails == 0 else 1)
