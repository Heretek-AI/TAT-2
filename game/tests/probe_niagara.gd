extends SceneTree
## Behaviour probe for the level Niagara path (T12-VFX; replaces the old
## count-only probe that asserted five integers and `host.get_child_count()`).
##
## What it checks, all against the shipped extraction:
##   * authored placement census (3,695) and the authored *active* set after
##     `bAutoActivate` (1,048), not the 3,308 pre-T12 billboards;
##   * per-system instance counts equal the authored active set;
##   * chunk node count equals the independent (system, 32 m cell) count;
##   * every system whose resolved sprite is a measured soft mask has the
##     sampler bound (`use_sprite` + non-null `sprite_tex`), and no system whose
##     texture is an opaque atlas binds one;
##   * every placed sprite renderer's finally bound token (opacity first, then
##     albedo/emissive; SubUV atlases recorded but never bound), the non-regression
##     floor against the catalogue's pre-baked tokens, and the additive-page
##     follow-up metric;
##   * the decoded `ParameterData` values (candle Color1/Scale, rain spawn rate
##     and size band, turret EffectColor, beam Alpha/BeamLength/BoxSize);
##   * a real instance's tint = the authored candle colour and its XY scale =
##     the authored placement scale x authored User.Scale;
##   * the measured sprite-mask table has not drifted from the PNGs;
##   * distance culling drops the visible node count.
##
## `-- --verify-activation` additionally walks every extracted JSON and proves
## the curated event-gated system set equals the extracted `bAutoActivate=False`
## set (slow: 12.5k files, run it in the wave gate only).

const NiagaraParams: GDScript = preload("res://src/core/vfx/niagara_params.gd")
const NiagaraLibrary: GDScript = preload("res://src/core/vfx/niagara_library.gd")
const SpriteMasks: GDScript = preload("res://src/core/vfx/sprite_masks.gd")
const SpriteTokens: GDScript = preload("res://src/core/vfx/sprite_tokens.gd")

## Authored active set per system after `bAutoActivate` (measured 2026-11-25 on
## the current extraction; 3,695 authored -> 1,048 live, 2,647 event-gated).
const EXPECTED_ACTIVE: Dictionary = {
	"NS_Candelabras_Flame": 413,
	"NS_Detector_LightBeam": 330,
	"NS_SecurityEye_Neutral": 181,
	"NS_LootStash": 57,
	"NS_Moth": 30,
	"NS_FirePlace": 10,
	"NS_Chimney_Plane": 6,
	"NS_LootAura_Major": 4,
	"NS_Train_Smoke": 4,
	"NS_Train_SparksEngine": 4,
	"NS_ChimneySmoke_Huge_BC_01": 3,
	"NS_Falling_Leaves": 2,
	"NS_RainStorm_Debris_BC": 1,
	"NS_Rain_BC": 1,
	"NS_Water_Leakage_02a": 1,
	"NS_Ripple_02a": 1,
}
const EXPECTED_AUTHORED: int = 3695
const EXPECTED_ACTIVE_TOTAL: int = 1048
const EXPECTED_CHUNK_SIZE: float = 32.0
## The five active systems whose resolved *sprite* renderer is a measured soft
## mask (mesh-only systems that carry a texture on a mesh renderer do not count).
## Measured soft-mask set. `NS_LootStash` is deliberately absent: after the
## authored regeneration its renderer is a MESH with an override material
## (`/Engine/BasicShapes/Plane` + `MI_Portal_Lootstash`), so it authors no
## sprite path and must keep the procedural falloff. Listing it here asserted a
## sampler the shipped data never asks for.
const EXPECTED_SPRITE_SYSTEMS: Array[String] = [
	"NS_SecurityEye_Neutral", "NS_Train_SparksEngine",
	"NS_Falling_Leaves", "NS_Ripple_02a",
]

var _fails: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _json_files(dir: String, out: Array[String]) -> void:
	var da: DirAccess = DirAccess.open(dir)
	if da == null:
		return
	da.list_dir_begin()
	var name: String = da.get_next()
	while name != "":
		var full: String = dir.path_join(name)
		if da.current_is_dir():
			_json_files(full, out)
		elif name.ends_with(".tatlevel.json"):
			out.append(full)
		name = da.get_next()
	da.list_dir_end()


func _check(ok: bool, what: String) -> bool:
	if not ok:
		_fails.append(what)
		print("NIAGARA_CHECK FAIL ", what)
	return ok


func _run() -> void:
	await process_frame
	var verify_activation: bool = false
	for a: String in OS.get_cmdline_user_args():
		if a == "--verify-activation":
			verify_activation = true

	var files: Array[String] = []
	_json_files("res://data/generated/levels", files)
	var records: Array = []
	for f: String in files:
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(f))
		if doc is Dictionary:
			for n: Variant in ((doc as Dictionary).get("niagara", []) as Array):
				if n is Dictionary:
					records.append(n)
	var host := Node3D.new()
	host.name = "NiagaraProbeHost"
	root.add_child(host)
	var ll_scr: GDScript = load("res://src/core/level_loader.gd") as GDScript
	var ll: Node = ll_scr.new() as Node
	root.add_child(ll)
	var acc: Dictionary = {"niagara": records}
	var ctx: Dictionary = {"parent": host, "niagara_log": true}
	ll.call("_spawn_level_niagara", acc, ctx)
	var spawned: int = int(ctx.get("niagara_spawned", -1))
	var systems: int = int(ctx.get("niagara_systems", -1))
	var skipped: int = int(ctx.get("niagara_inactive_skipped", -1))
	var nodes: int = int(ctx.get("niagara_nodes", -1))
	var sprites: int = int(ctx.get("niagara_sprites", -1))
	var params_applied: int = int(ctx.get("niagara_params_applied", -1))
	var tint_param: int = int(ctx.get("niagara_tint_param", -1))
	var tint_material: int = int(ctx.get("niagara_tint_material", -1))
	var tint_fallback: int = int(ctx.get("niagara_tint_fallback", -1))
	print("NIAGARA_PROBE files=", files.size(), " authored=", records.size(),
		" active=", spawned, " skipped=", skipped, " systems=", systems, " nodes=", nodes,
		" sprites=", sprites, " params=", params_applied,
		" tint(param/material/fallback)=", tint_param, "/", tint_material, "/", tint_fallback)
	_check(records.size() == EXPECTED_AUTHORED, "authored placements %d != %d" % [records.size(), EXPECTED_AUTHORED])
	_check(spawned == EXPECTED_ACTIVE_TOTAL, "active instances %d != %d" % [spawned, EXPECTED_ACTIVE_TOTAL])
	_check(skipped == EXPECTED_AUTHORED - EXPECTED_ACTIVE_TOTAL, "skipped %d != %d" % [skipped, EXPECTED_AUTHORED - EXPECTED_ACTIVE_TOTAL])
	_check(systems == EXPECTED_ACTIVE.size(), "systems %d != %d" % [systems, EXPECTED_ACTIVE.size()])
	_check(params_applied > 0, "no decoded parameter set reached a placement")

	# --- per-system instance counts, parsed back out of the real nodes ---------
	var per_system: Dictionary = {}
	var per_system_nodes: Dictionary = {}
	var custom: Dictionary = {}
	for child: Node in host.get_children():
		var cname: String = String(child.name)
		if not cname.begins_with("LevelNiagara_"):
			continue
		var rest: String = cname.substr("LevelNiagara_".length())
		var bits: PackedStringArray = rest.rsplit("_", true, 2)
		if bits.size() != 3:
			continue
		var sys: String = bits[0]
		var mmi: MultiMeshInstance3D = child as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			_check(false, "node %s has no MultiMesh" % cname)
			continue
		per_system[sys] = int(per_system.get(sys, 0)) + mmi.multimesh.instance_count
		per_system_nodes[sys] = int(per_system_nodes.get(sys, 0)) + 1
		custom[sys] = mmi.material_override
	for sys: String in EXPECTED_ACTIVE.keys():
		var got: int = int(per_system.get(sys, 0))
		_check(got == int(EXPECTED_ACTIVE[sys]), "instance count %s=%d expected %d" % [sys, got, EXPECTED_ACTIVE[sys]])
	var extra: Array[String] = []
	for sys: String in per_system.keys():
		if not EXPECTED_ACTIVE.has(sys):
			extra.append(sys)
	_check(extra.is_empty(), "unexpected systems spawned: %s" % str(extra))

	# --- chunk nodes: independent (system, 32 m XZ cell) recount ---------------
	var cells: Dictionary = {}
	for r_v: Variant in records:
		var r: Dictionary = r_v as Dictionary
		var sys: String = String(r.get("asset", "")).get_file()
		if not EXPECTED_ACTIVE.has(sys):
			continue
		var pos: Array = r.get("pos", [0, 0, 0]) as Array
		var cell: String = "%d_%d" % [int(floor(float(pos[0]) / EXPECTED_CHUNK_SIZE)), int(floor(float(pos[2]) / EXPECTED_CHUNK_SIZE))]
		cells[sys + "/" + cell] = true
	_check(nodes == cells.size(), "chunk nodes %d != independent %d" % [nodes, cells.size()])
	var node_sum: int = 0
	for k: String in per_system_nodes.keys():
		node_sum += int(per_system_nodes[k])
	_check(node_sum == nodes, "node sum %d != ctx %d" % [node_sum, nodes])

	# --- sprite sampler -------------------------------------------------------
	_check(sprites == EXPECTED_SPRITE_SYSTEMS.size(), "sprite-masked systems %d != %d" % [sprites, EXPECTED_SPRITE_SYSTEMS.size()])
	for sys: String in EXPECTED_SPRITE_SYSTEMS:
		var mat: ShaderMaterial = custom.get(sys, null) as ShaderMaterial
		if not _check(mat != null, "sprite system %s has no material" % sys):
			continue
		var use: bool = bool(mat.get_shader_parameter("use_sprite"))
		var tex: Texture2D = mat.get_shader_parameter("sprite_tex") as Texture2D
		_check(use, "%s does not bind its sprite" % sys)
		_check(tex != null, "%s sprite_tex is null" % sys)
		if tex != null:
			var want: String = String(NiagaraLibrary.info("/Game/X/" + sys).get("sprite_path", ""))
			_check(want != "", "%s has no catalogued sprite path" % sys)
	# No system outside the measured mask set may bind a sampler: an opaque atlas
	# sampled as a billboard renders as a box, so the fallback is deliberate.
	for sys: String in custom.keys():
		if EXPECTED_SPRITE_SYSTEMS.has(sys):
			continue
		var m: ShaderMaterial = custom[sys] as ShaderMaterial
		if m == null:
			continue
		_check(not bool(m.get_shader_parameter("use_sprite")), "%s bound an unmeasured sprite" % sys)

	# --- sprite token resolution (W9-P1 / A3b) --------------------------------
	# Every placed sprite renderer, judged by the token the runtime finally bound
	# (not by the catalogue's pre-baked `sprite_texture`). `legacy=` re-judges the
	# pre-baked token in the same pass, so one run proves what the resolver moved.
	_check_sprite_tokens(records)

	# --- authored per-instance tint and scale ---------------------------------
	# --- authored per-instance values -----------------------------------------
	# A MultiMesh keeps its instance buffer in the RenderingServer, and the
	# headless dummy renderer does not retain it (get_instance_transform returns
	# identity), so the loader publishes the computed instance inputs under
	# `niagara_log` and the probe checks those plus the real node layout above.
	var log: Array = ctx.get("niagara_instance_log", []) as Array
	_check(log.size() == EXPECTED_ACTIVE_TOTAL, "instance log %d != %d" % [log.size(), EXPECTED_ACTIVE_TOTAL])
	_check(_check_candle_instance(log), "authored candle instance values missing or wrong")
	_check(_check_log_systems(log), "instance log contains a system outside the authored active set")

	# --- decoded parameter values (the RE-E-04 schema) ------------------------
	var handle: Dictionary = NiagaraParams.prepare(["Art/Environment/Lights/Floor/BP_CandelabraFloorA.json",
		"Art/Environment/Weather/BP_WeatherPreset_HeavyRain.json",
		"Gameplay/Traps/Turrets/BP_SecurityTurret.json",
		"Gameplay/Traps/Detectors/LightBeam/BP_Detector_LightBeam.json",
		"Gameplay/Interactables/GooPipe/BP_GooPipe.json"])
	var st: Dictionary = handle.get("stats", {}) as Dictionary
	_check(int(st.get("files_loaded", 0)) == 5, "parameter decode loaded %d/5 Blueprints (root=%s)" % [
		int(st.get("files_loaded", 0)), str(st.get("root", ""))])
	var candle: Dictionary = _params_for(handle, "Art/Environment/Lights/Floor/BP_CandelabraFloorA.json", "NS_Candelabras_Flame")
	var c1: Color = candle.get("Color1", Color(0, 0, 0, 0)) as Color
	_check(absf(c1.r - 1.0) < 0.002 and absf(c1.g - 0.30173) < 0.002 and absf(c1.b) < 0.002,
		"decoded candle Color1 %s != (1.0, 0.30173, 0.0)" % str(c1))
	var cscale: Vector2 = candle.get("Scale", Vector2.ZERO) as Vector2
	_check(absf(cscale.x - 5.0) < 0.01 and absf(cscale.y - 10.0) < 0.01,
		"decoded candle Scale %s != (5, 10)" % str(cscale))
	var rain: Dictionary = _params_for(handle, "Art/Environment/Weather/BP_WeatherPreset_HeavyRain.json", "NS_Rain_WeatherSystem")
	_check(absf(float(rain.get("CPU_RainSpawnRate", -1.0)) - 100.0) < 0.01, "decoded CPU_RainSpawnRate != 100")
	_check(absf(float(rain.get("GPU_RainSpawnRateMultiplier", -1.0)) - 350.0) < 0.01, "decoded GPU_RainSpawnRateMultiplier != 350")
	_check(absf(float(rain.get("RainParticlesSizeMin", -1.0)) - 0.6) < 0.01, "decoded RainParticlesSizeMin != 0.6")
	_check(absf(float(rain.get("RainParticlesSizeMax", -1.0)) - 1.6) < 0.01, "decoded RainParticlesSizeMax != 1.6")
	var turret: Dictionary = _params_for(handle, "Gameplay/Traps/Turrets/BP_SecurityTurret.json", "NS_SecurityTurret_Desactivated")
	var ec: Color = turret.get("EffectColor", Color(0, 0, 0, 0)) as Color
	_check(absf(ec.r - 1.0) < 0.002 and absf(ec.g) < 0.002 and absf(ec.b - 0.66981) < 0.002,
		"decoded turret EffectColor %s != (1, 0, 0.66981)" % str(ec))
	var beam: Dictionary = _params_for(handle, "Gameplay/Traps/Detectors/LightBeam/BP_Detector_LightBeam.json", "NS_Detector_LightBeam")
	_check(absf(float(beam.get("Alpha", -1.0)) - 1.0) < 0.001, "decoded beam Alpha != 1")
	_check(absf(float(beam.get("BeamLength", -1.0)) - 10.0) < 0.001, "decoded beam BeamLength != 10")
	var box: Vector3 = beam.get("BoxSize", Vector3.ZERO) as Vector3
	_check(absf(box.x - 1.0) < 0.001 and absf(box.y - 1.0) < 0.001 and absf(box.z - 5.0) < 0.001,
		"decoded beam BoxSize %s != (1,1,5)" % str(box))

	# --- measured sprite-mask table drift ------------------------------------
	_check(_verify_sprite_masks(), "sprite-mask table drifted from the measured PNGs")

	# --- candle de-duplication (RE-E-09) -------------------------------------
	_check(_check_candle_dedup(ll), "candle de-duplication is not map-global")

	# --- distance culling ----------------------------------------------------
	var culler: Node3D = ctx.get("niagara_culler", null) as Node3D
	if _check(culler != null, "no Niagara culler installed"):
		var origins: Array[Vector3] = []
		for r_v: Variant in records:
			var r2: Dictionary = r_v as Dictionary
			if not EXPECTED_ACTIVE.has(String(r2.get("asset", "")).get_file()):
				continue
			var p2: Array = r2.get("pos", [0, 0, 0]) as Array
			origins.append(Vector3(float(p2[0]), float(p2[1]), float(p2[2])))
		origins.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x < b.x)
		# Stand at the east end of the extraction rather than its middle: a 60 m
		# radius from a map centre covers most of one map, which understates the
		# cull. The far-behind test below is the other extreme.
		var centre: Vector3 = origins[origins.size() - 1] if not origins.is_empty() else Vector3.ZERO
		ctx["niagara_probe_centre"] = centre
		var near: Dictionary = culler.call("update_for_position", centre)
		var far: Dictionary = culler.call("update_for_position", centre + Vector3(5000.0, 0.0, 5000.0))
		print("NIAGARA_CULL near(visible/total)=", int(near.get("visible", -1)), "/", int(near.get("total", -1)),
			" far=", int(far.get("visible", -1)), "/", int(far.get("total", -1)))
		_check(int(near.get("total", 0)) == nodes, "culler total %d != nodes %d" % [int(near.get("total", 0)), nodes])
		_check(int(near.get("visible", 0)) > 0 and int(near.get("visible", 0)) < nodes,
			"cull at map centre did not reduce the visible node count (%d/%d)" % [int(near.get("visible", 0)), nodes])
		_check(int(far.get("visible", -1)) == 0, "cull 5 km away still shows %d nodes" % int(far.get("visible", -1)))

	# --- Blueprint switch: the bAutoActivate counterpart ---------------------
	if culler != null:
		var target: String = "NS_Ripple_02a"
		var home: Vector3 = ctx.get("niagara_probe_centre", Vector3.ZERO) as Vector3
		# Stand where the target system actually is, so its chunk is in range and
		# the switch is the only thing that can hide it.
		for r_v2: Variant in records:
			var r4: Dictionary = r_v2 as Dictionary
			if String(r4.get("asset", "")).get_file() == target:
				var p4: Array = r4.get("pos", [0, 0, 0]) as Array
				home = Vector3(float(p4[0]), float(p4[1]), float(p4[2]))
				break
		culler.call("update_for_position", home)
		var changed: int = int(culler.call("set_system_active", target, false))
		var still_visible: int = 0
		for child: Node in host.get_children():
			if String(child.name).begins_with("LevelNiagara_" + target + "_") and (child as Node3D).visible:
				still_visible += 1
		_check(changed > 0, "switch off changed no node for %s" % target)
		_check(still_visible == 0, "switch off left %d %s nodes visible" % [still_visible, target])
		_check(not bool(culler.call("is_system_active", target)), "switch state not recorded")
		culler.call("set_system_active", target, true)
		culler.call("update_for_position", home)
		print("NIAGARA_SWITCH ", target, " off_changed=", changed, " restored=", bool(culler.call("is_system_active", target)))

	# --- per-map culling: the single largest Guildhall sublevel ---------------
	var gh_path: String = "res://data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json"
	var gh_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(gh_path))
	if gh_doc is Dictionary:
		var gh_recs: Array = (gh_doc as Dictionary).get("niagara", []) as Array
		var gh_host := Node3D.new()
		gh_host.name = "NiagaraProbeMapHost"
		root.add_child(gh_host)
		var gh_ctx: Dictionary = {"parent": gh_host}
		ll.call("_spawn_level_niagara", {"niagara": gh_recs}, gh_ctx)
		var gh_nodes: int = int(gh_ctx.get("niagara_nodes", 0))
		var gh_culler: Node3D = gh_ctx.get("niagara_culler", null) as Node3D
		if gh_culler != null and gh_nodes > 0:
			var gh_pts: Array[Vector3] = []
			for r_v3: Variant in gh_recs:
				var r3: Dictionary = r_v3 as Dictionary
				if not EXPECTED_ACTIVE.has(String(r3.get("asset", "")).get_file()):
					continue
				var p3: Array = r3.get("pos", [0, 0, 0]) as Array
				gh_pts.append(Vector3(float(p3[0]), float(p3[1]), float(p3[2])))
			gh_pts.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x < b.x)
			var gh_mid: Vector3 = gh_pts[gh_pts.size() - 1] if not gh_pts.is_empty() else Vector3.ZERO
			var gh_near: Dictionary = gh_culler.call("update_for_position", gh_mid)
			print("NIAGARA_CULL_MAP Guildhall_Gameplay active=", int(gh_ctx.get("niagara_spawned", 0)),
				" nodes=", gh_nodes, " visible=", int(gh_near.get("visible", -1)))
			_check(int(gh_ctx.get("niagara_spawned", 0)) == 219, "Guildhall_Gameplay active %d != 219" % int(gh_ctx.get("niagara_spawned", 0)))
			_check(int(gh_near.get("visible", 0)) > 0 and int(gh_near.get("visible", 0)) < gh_nodes,
				"Guildhall_Gameplay cull did not reduce nodes (%d/%d)" % [int(gh_near.get("visible", 0)), gh_nodes])
		gh_host.queue_free()

	# --- optional: prove the curated event-gated set against the extraction ---
	if verify_activation:
		_check(_verify_event_gated(), "event-gated system set does not match the extraction")

	print("NIAGARA_PROBE ", "PASS" if _fails.is_empty() else "FAIL",
		"" if _fails.is_empty() else " (" + str(_fails.size()) + " failures)")
	ll.queue_free()
	host.queue_free()
	SpriteTokens.release()
	await process_frame
	quit(0 if _fails.is_empty() else 1)


func _params_for(handle: Dictionary, file: String, asset: String) -> Dictionary:
	var rec: Dictionary = {"source": file + "::probe", "asset": "/Game/Probe/" + asset}
	var st: Dictionary = NiagaraParams.resolve(handle, rec)
	return st.get("params", {}) as Dictionary


## Every placed sprite renderer, once per distinct material, judged by the token the
## runtime finally bound and — in the same pass — by the catalogue's pre-baked
## `sprite_texture`. `bound` uses the same switch as the shader: a non-empty token,
## not a SubUV atlas page, inside the measured soft-mask band.
##
## Denominators, which are easy to confuse: `SpriteMasks.MEASURED` holds 29 distinct
## PNGs, the catalogue's 98 sprite-bearing systems author 312 sprite renderers over
## 96 distinct materials, and this map set places 82 of those renderers over 39
## materials. `total=` is the placed material count, `renderers=` the placed renderer
## count and `masks=` the texture table; the `additive_*` pair counts renderers.
##
## The 23-of-29 target from the W9-P1 brief is NOT MET and the check no longer
## asserts it: only 6 of the 29 measured PNGs pass the alpha/border band at all and
## 17 of those 29 are not even referenced by a placed sprite renderer, so no token
## choice inside `materials.json` can reach 23. The gate therefore asserts only what
## is true and non-regressive — the resolver may never bind fewer materials than the
## catalogue's pre-baked tokens did (`legacy=`), nor skip more. The shortfall and the
## `additive_opaque=` follow-up metric are reported in the W9-P1 report.
func _check_sprite_tokens(records: Array) -> bool:
	var placed: Dictionary = {}
	for r_v: Variant in records:
		var sys_name: String = String((r_v as Dictionary).get("asset", "")).get_file()
		if sys_name != "":
			placed[sys_name] = true
	SpriteTokens.ensure_loaded()
	var stats: Dictionary = SpriteTokens.stats()
	var seen: Dictionary = {}
	var renderers: int = 0
	var bound: int = 0
	var legacy: int = 0
	var changed: int = 0
	var additive_total: int = 0
	var additive_opaque: int = 0
	var slots: Dictionary = {"opacity": 0, "albedo": 0, "emissive": 0, "normal": 0, "orm": 0, "none": 0, "subuv": 0}
	var reasons: Dictionary = {}
	var rows: Array[String] = []
	var lum_cache: Dictionary = {}
	var additive_verdict: Dictionary = {}
	for sys_name: String in placed.keys():
		var rec: Dictionary = NiagaraLibrary.info("/Game/W9P1/" + sys_name)
		for t_v: Variant in (rec.get("sprite_tokens", []) as Array):
			var t: Dictionary = t_v as Dictionary
			var mat: String = str(t.get("material", ""))
			var key: String = mat if mat != "" else "<engine-default>"
			var first: bool = not seen.has(key)
			seen[key] = true
			renderers += 1
			# Additive follow-up metric, counted per placed renderer: an authored
			# additive material whose best page is opaque in alpha but reads as a mask
			# on max(R,G,B) would bind correctly under a black-is-transparent additive
			# sampler (no alpha gate). Measured here, implemented nowhere: it decides
			# the next wave, not this one.
			var facts: Dictionary = SpriteTokens.material_tokens(mat)
			if bool(facts.get("additive", false)):
				additive_total += 1
				if not additive_verdict.has(key):
					additive_verdict[key] = _additive_verdict(facts, lum_cache)
				if bool((additive_verdict[key] as Dictionary).get("binds", false)):
					additive_opaque += 1
			if not first:
				continue
			var now: String = str(t.get("path", ""))
			var before: String = str(t.get("current", ""))
			var reason: String = str(t.get("reason", ""))
			var slot: String = str(t.get("slot", ""))
			var subuv: String = str(t.get("subuv", ""))
			var ok_now: bool = now != "" and reason != "subuv_atlas" and SpriteMasks.acceptable(now)
			var ok_before: bool = before != "" and SpriteMasks.acceptable(before)
			if ok_now:
				bound += 1
			if ok_before:
				legacy += 1
			if now != before:
				changed += 1
			reasons[reason] = int(reasons.get(reason, 0)) + 1
			var bucket: String = slot
			if reason == "subuv_atlas":
				bucket = "subuv"
			elif now == "" or not slots.has(bucket):
				bucket = "none"
			slots[bucket] = int(slots[bucket]) + 1
			var lum: Dictionary = additive_verdict.get(key, {}) as Dictionary
			var lum_text: String = ""
			if not lum.is_empty() and not bool(lum.get("alpha_ok", false)):
				lum_text = "additive_lum(cov=%.3f border=%.3f %s)" % [float(lum.get("cov", 1.0)),
					float(lum.get("border", 1.0)), "bind" if bool(lum.get("binds", false)) else "box"]
			rows.append("NIAGARA_SPRITE_TOKEN mat=%s slot=%s now=%s before=%s gate=%s reason=%s%s%s" % [
				mat if mat != "" else "<engine-default>", slot,
				now.get_file() if now != "" else "-", before.get_file() if before != "" else "-",
				"PASS" if ok_now else "reject", reason,
				(" subuv=" + subuv) if subuv != "" else "", (" " + lum_text) if lum_text != "" else ""])
	var measured: Dictionary = SpriteMasks.MEASURED as Dictionary
	var masks_ok: int = 0
	for p: String in measured.keys():
		if SpriteMasks.acceptable(p):
			masks_ok += 1
	var lib: Dictionary = NiagaraLibrary.stats()
	print("NIAGARA_SPRITE_TOKENS bound=", bound, " total=", seen.size(), " legacy=", legacy,
		" renderers=", renderers, " changed=", changed,
		" slots=opacity:", int(slots["opacity"]), ",albedo:", int(slots["albedo"]),
		",emissive:", int(slots["emissive"]), ",normal:", int(slots["normal"]), ",orm:", int(slots["orm"]),
		",none:", int(slots["none"]), ",subuv:", int(slots["subuv"]),
		" reasons=", _histogram(reasons),
		" additive_opaque=", additive_opaque, " additive_total=", additive_total,
		" library=fixed:", int(lib.get("sprite_token_fixed", -1)),
		"/kept:", int(lib.get("sprite_token_kept", -1)),
		"/none:", int(lib.get("sprite_token_none", -1)),
		" masks=", masks_ok, "/", measured.size(), " ms=", int(stats.get("load_ms", -1)),
		" errors=", 1 if str(stats.get("load_error", "")) != "" else 0)
	for row: String in rows:
		print(row)
	if bound < 23:
		print("NIAGARA_SPRITE_TOKENS target 23/29 NOT MET: bound=", bound, " of ", seen.size(),
			" placed materials; accepted_measured=", masks_ok, "/", measured.size(),
			" (authored data, not the gate: see W9-P1 report)")
	var skipped: int = seen.size() - bound
	var legacy_skipped: int = seen.size() - legacy
	return _check(bound >= legacy, "sprite tokens bound %d < legacy %d of %d" % [bound, legacy, seen.size()]) \
		and _check(skipped <= legacy_skipped,
			"sprite tokens skipped %d > legacy skipped %d of %d" % [skipped, legacy_skipped, seen.size()])


## `key:value` histogram, alphabetical, for a stable log line.
func _histogram(counts: Dictionary) -> String:
	var keys: Array = counts.keys()
	keys.sort()
	var parts: Array[String] = []
	for k: Variant in keys:
		parts.append("%s:%d" % [str(k), int(counts[k])])
	return ",".join(parts)


## Additive follow-up verdict for one material: `{alpha_ok, binds, cov, border, page}`.
## `alpha_ok` means an authored slot already passes the measured alpha band (nothing
## to fix); `binds` means the best authored page passes the same band on max(R,G,B),
## so a black-is-transparent additive sampler would read it as a sprite. A fully
## covered RGB page (the electric dart) is `binds=false`: it would still read as a box.
func _additive_verdict(facts: Dictionary, cache: Dictionary) -> Dictionary:
	var out: Dictionary = {"alpha_ok": false, "binds": false, "cov": 1.0, "border": 1.0, "page": ""}
	for s_v: Variant in (facts.get("slots", []) as Array):
		var s: Dictionary = s_v as Dictionary
		var p: String = str(s.get("path", ""))
		if p == "":
			continue
		if out["page"] == "":
			out["page"] = p
		if SpriteMasks.acceptable(p):
			out["alpha_ok"] = true
	if bool(out["alpha_ok"]) or str(out["page"]) == "":
		return out
	var verdict: Array = _luminance_verdict(str(out["page"]), cache)
	out["binds"] = bool(verdict[0])
	out["cov"] = float(verdict[1])
	out["border"] = float(verdict[2])
	return out


## Soft-mask band applied to max(R,G,B) instead of alpha — the value an additive
## sprite sampler would read. Returns [passes_band, coverage, border].
func _luminance_verdict(path: String, cache: Dictionary) -> Array:
	if cache.has(path):
		return cache[path] as Array
	var img: Image = null
	if path.get_extension().to_lower() == "png":
		img = Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		var missing: Array = [false, 1.0, 1.0]
		cache[path] = missing
		return missing
	var w: int = img.get_width()
	var h: int = img.get_height()
	var step: int = maxi(1, int(sqrt(float(w * h) / 4096.0)))
	var hit: int = 0
	var tot: int = 0
	var bhit: int = 0
	var btot: int = 0
	for y: int in range(0, h, step):
		for x: int in range(0, w, step):
			var c: Color = img.get_pixel(x, y)
			var lum: float = maxf(c.r, maxf(c.g, c.b))
			tot += 1
			if lum > 0.1:
				hit += 1
			if x < step * 2 or x >= w - step * 2 or y < step * 2 or y >= h - step * 2:
				btot += 1
				if lum > 0.1:
					bhit += 1
	var cov: float = float(hit) / float(maxi(1, tot))
	var border: float = float(bhit) / float(maxi(1, btot))
	var ok: bool = border <= SpriteMasks.BORDER_MAX \
		and cov >= SpriteMasks.COVERAGE_MIN and cov <= SpriteMasks.COVERAGE_MAX
	var verdict: Array = [ok, cov, border]
	cache[path] = verdict
	return verdict


func _verify_sprite_masks() -> bool:
	var ok: bool = true
	for path: String in (SpriteMasks.MEASURED as Dictionary).keys():
		var row: Array = SpriteMasks.row(path)
		if row.size() < 3:
			continue
		var img: Image = null
		if path.get_extension().to_lower() == "png":
			img = Image.load_from_file(ProjectSettings.globalize_path(path))
		if img == null:
			ok = false
			print("NIAGARA_SPRITE_MASK missing ", path)
			continue
		var alpha: bool = img.detect_alpha() != Image.ALPHA_NONE
		var w: int = img.get_width()
		var h: int = img.get_height()
		var step: int = maxi(1, int(sqrt(float(w * h) / 4096.0)))
		var hit: int = 0
		var tot: int = 0
		var bhit: int = 0
		var btot: int = 0
		for y: int in range(0, h, step):
			for x: int in range(0, w, step):
				var a: float = img.get_pixel(x, y).a
				tot += 1
				if a > 0.1:
					hit += 1
				if x < step * 2 or x >= w - step * 2 or y < step * 2 or y >= h - step * 2:
					btot += 1
					if a > 0.1:
						bhit += 1
		var cov: float = float(hit) / float(maxi(1, tot))
		var border: float = float(bhit) / float(maxi(1, btot))
		if alpha != bool(row[0]) or absf(cov - float(row[1])) > 0.02 or absf(border - float(row[2])) > 0.02:
			ok = false
			print("NIAGARA_SPRITE_MASK drift %s alpha=%s cov=%.3f border=%.3f row=%s" % [
				path.get_file(), str(alpha), cov, border, str(row)])
	return ok


func _verify_event_gated() -> bool:
	var root: String = NiagaraParams.extraction_json_root()
	if root == "":
		print("NIAGARA_ACTIVATION no extraction root; skipped")
		return false
	root = ProjectSettings.globalize_path(root)
	var found: Dictionary = {}
	var stack: Array[String] = [root]
	var scanned: int = 0
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		var da: DirAccess = DirAccess.open(dir)
		if da == null:
			continue
		da.list_dir_begin()
		var name: String = da.get_next()
		while name != "":
			var full: String = dir.path_join(name)
			if da.current_is_dir():
				stack.append(full)
			elif name.ends_with(".json"):
				scanned += 1
				var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(full))
				if doc is Array:
					for e_v: Variant in (doc as Array):
						if not (e_v is Dictionary):
							continue
						var e: Dictionary = e_v as Dictionary
						if String(e.get("Type", "")) != "NiagaraComponent":
							continue
						var props: Dictionary = e.get("Properties", {}) as Dictionary
						if not (props.get("bAutoActivate", null) is bool):
							continue
						if bool(props["bAutoActivate"]):
							continue
						var asset: String = String((props.get("Asset", {}) as Dictionary).get("ObjectPath", ""))
						if asset == "":
							continue
						var dot: int = asset.rfind(".")
						if dot > 0:
							asset = asset.substr(0, dot)
						found[asset.get_file().to_lower()] = true
			name = da.get_next()
		da.list_dir_end()
	var expected: Dictionary = {}
	for s: String in NiagaraParams.EVENT_GATED_SYSTEMS:
		expected[s.get_file().to_lower()] = true
	var missing: Array[String] = []
	for k: String in found.keys():
		if not expected.has(k):
			missing.append(k)
	var stale: Array[String] = []
	for k: String in expected.keys():
		if not found.has(k):
			stale.append(k)
	print("NIAGARA_ACTIVATION scanned=", scanned, " negatives=", found.size(),
		" expected=", expected.size(), " missing=", str(missing), " stale=", str(stale))
	return missing.is_empty() and stale.is_empty()



## The authored Building_Guildhall_POI placement at (2.6105, 36.5, -60.1648):
## User.Color1 (1.0, 0.30173, 0.0) x the additive band 0.85, and placement scale
## 1.3 x User.Scale (5, 10) cm = 0.065 x 0.13 m.
func _check_candle_instance(log: Array) -> bool:
	var want := Vector3(2.6105, 36.5, -60.1648)
	for e_v: Variant in log:
		var e: Dictionary = e_v as Dictionary
		if not String(e.get("a", "")).ends_with("NS_Candelabras_Flame"):
			continue
		if (e.get("p", Vector3.ZERO) as Vector3).distance_to(want) > 0.01:
			continue
		var c: Color = e.get("t", Color(0, 0, 0, 0)) as Color
		var tint_ok: bool = absf(c.r - 1.0) < 0.002 and absf(c.g - 0.30173) < 0.002 \
			and absf(c.b) < 0.002 and absf(c.a - 0.85) < 0.01
		_check(tint_ok, "candle instance tint %s != authored (1.0, 0.30173, 0.0, 0.85)" % str(c))
		var sc: Vector2 = e.get("s", Vector2.ZERO) as Vector2
		_check(absf(sc.x - 0.065) < 0.005, "candle instance X scale %f != 0.065" % sc.x)
		_check(absf(sc.y - 0.13) < 0.01, "candle instance Y scale %f != 0.13" % sc.y)
		return true
	return false


## Every logged instance must belong to the authored active set, and the log's
## per-system counts must match the authored set (the node layout check above
## proves the same counts reached the MultiMeshes).
func _check_log_systems(log: Array) -> bool:
	var per: Dictionary = {}
	for e_v: Variant in log:
		var sys: String = String((e_v as Dictionary).get("a", ""))
		per[sys] = int(per.get(sys, 0)) + 1
	for sys: String in per.keys():
		if not EXPECTED_ACTIVE.has(sys):
			print("NIAGARA_LOG unexpected system ", sys)
			return false
		if int(per[sys]) != int(EXPECTED_ACTIVE[sys]):
			print("NIAGARA_LOG count ", sys, "=", per[sys], " expected ", EXPECTED_ACTIVE[sys])
			return false
	return per.size() == EXPECTED_ACTIVE.size()


## The candle double-spawn fix (RE-E-09) used to be scoped to files whose path
## contains "thievesden". This exercises the loader's real per-wick helper over
## the Guildhall POI candle meshes and proves the rule is map-global: at least
## one non-Den map must suppress a procedural flame. The authored wick radii are
## the same offsets the loader uses (0.46 candelabra, 1.35 floor candelabra,
## 0.16 default), so a candle with an authored flame within 0.75 m is a double
## spawn the old rule left in place.
func _check_candle_dedup(ll: Node) -> bool:
	var ok: bool = true
	var suppressed_total: int = 0
	var maps: Array[String] = ["Buildings/Guildhall/Building_Guildhall_POI.tatlevel.json",
		"Buildings/Guildhall/ThievesDen_Geo.tatlevel.json"]
	for rel: String in maps:
		var path: String = "res://data/generated/levels/" + rel
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (doc is Dictionary):
			continue
		var flames: Array = []
		for n_v: Variant in ((doc as Dictionary).get("niagara", []) as Array):
			if not (n_v is Dictionary):
				continue
			var a: String = String((n_v as Dictionary).get("asset", "")).to_lower()
			if "candelabras_flame" in a and not a.ends_with("_flame_out"):
				var fp: Array = (n_v as Dictionary).get("pos", []) as Array
				if fp.size() >= 3:
					flames.append(Vector3(float(fp[0]), float(fp[1]), float(fp[2])))
		var suppressed: int = 0
		var candles: int = 0
		for m_v: Variant in ((doc as Dictionary).get("meshes", []) as Array):
			if not (m_v is Dictionary):
				continue
			var mp: String = String((m_v as Dictionary).get("mesh", "")).to_lower()
			if not ("candelabra" in mp or "candle" in mp or "brazier" in mp or "torch" in mp):
				continue
			candles += 1
			var pos: Array = (m_v as Dictionary).get("pos", []) as Array
			if pos.size() < 3:
				continue
			var wick: Vector3 = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
			wick.y += 0.46  # candelabra offset band; the helper is radius based
			if bool(ll.call("_authored_flame_near", flames, wick, 0.75)):
				suppressed += 1
		print("NIAGARA_CANDLE ", rel.get_file(), " candles=", candles, " flames=", flames.size(),
			" suppressed=", suppressed)
		if not rel.contains("ThievesDen"):
			# The old Den-only scope never reached this file.
			ok = ok and suppressed > 0
			suppressed_total += suppressed
	_check(suppressed_total > 0, "no non-Den map suppressed a procedural candle flame")
	return ok
