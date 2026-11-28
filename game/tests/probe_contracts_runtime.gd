extends SceneTree
## Phase 3 §2.5.5 runtime-contract holes (gate integrity, headless).
##
## Five contracts the audits found untested, each pinned against the real
## implementation (never against a copy of its constants):
##
##   1. `xray_target` membership. Instantiated real actors load their own
##      `_ready` path: `guard_ai.gd`, `loot_item.gd`, `world_pickup.gd` and
##      `clue_item.gd` must join the authored group; the overlay then gets a
##      highlight on -> off cycle and must restore every mesh's ORIGINAL
##      `material_overlay` / `material_override` (including a pre-set non-null
##      overlay) and leave no `_xray_on` / `_xray_prev_overlay` meta behind.
##   2. `TAT2_NAV` resolution through `nav_runtime.is_enabled()` / `setup()`:
##      unset and every unknown spelling resolve off (setup refuses and reports
##      `disabled`); only the documented truthy spellings enable it.
##   3. `TAT2_ROUGH_BAKE` resolution through `level_loader`: unset keeps the
##      full-resolution L8 `low + g * (high - low)` bake; `off` is the
##      documented `rough_high` scalar fallback with NO roughness texture and
##      NO bake allocation. Measured on the authored MI_ConcreteB range
##      0.2..0.6 (materials.json), not a synthetic info dict.
##   4. Endgame timeout: driving the real `mission_controller._process` clock in
##      PHASE_ENDGAME banks the stashed haul exactly once, loses the carried
##      haul, and reports `MAGIC DOOR COLLAPSED`; a main-phase expiry still
##      reports `TIME EXPIRED` (control). Suite 91 already pins the direct
##      `_on_door_collapsed()` call; this pins the clock branch that reaches it.
##   5. Door aperture is folded into `probe_p1_doors.gd` (section 0) instead of
##      duplicating it here.
##
## Run (never beside another Godot; thermal rule):
##   tools/godot --headless --path game --script res://tests/probe_contracts_runtime.gd
##
## Exit 0 only when every check passes; prints `CONTRACTS_PROBE: fails=N`.

const LOADER_SCRIPT := "res://src/core/level_loader.gd"
const NAV_SCRIPT := "res://src/ai/nav_runtime.gd"
const GUARD_SCRIPT := "res://src/ai/guard_ai.gd"
const LOOT_SCRIPT := "res://src/interact/loot_item.gd"
const PICKUP_SCRIPT := "res://src/interact/world_pickup.gd"
const CLUE_SCRIPT := "res://src/interact/clue_item.gd"
const MISSION_SCRIPT := "res://src/missions/mission_controller.gd"

## Authored material with a real non-trivial roughness range and an ORM map.
const CONCRETE_MAT := "/Game/MaterialLibrary/Environment/Concrete/MI_ConcreteB"
const CONCRETE_LOW := 0.2
const CONCRETE_HIGH := 0.6

const DOOR_COLLAPSED_REASON := "MAGIC DOOR COLLAPSED"
const TIME_EXPIRED_REASON := "TIME EXPIRED"

var checks: int = 0
var fails: int = 0
var _gs: Node = null
var _ss: Node = null
var _phase_main: String = "main"
var _phase_endgame: String = "endgame"
var _phase_resolved: String = "resolved"
var _save_snap: Dictionary = {}
var _gs_snap: Dictionary = {}
var _nav_env_present: bool = false
var _nav_env: String = ""
var _rough_env_present: bool = false
var _rough_env: String = ""


func _initialize() -> void:
	await process_frame
	var root: Window = get_root()
	_gs = root.get_node_or_null("GameState")
	_ss = root.get_node_or_null("SaveSystem")
	if _gs == null or _ss == null:
		printerr("CONTRACTS_PROBE: FAIL autoloads missing")
		quit(1)
		return
	var gs_consts: Dictionary = (_gs.get_script() as GDScript).get_script_constant_map()
	_phase_main = str(gs_consts.get("PHASE_MAIN", _phase_main))
	_phase_endgame = str(gs_consts.get("PHASE_ENDGAME", _phase_endgame))
	_phase_resolved = str(gs_consts.get("PHASE_RESOLVED", _phase_resolved))
	_snapshot_env()
	_snapshot_state()
	_check_nav()
	_check_rough_bake()
	await _check_xray()
	_check_endgame_timeout()
	_restore_state()
	_restore_env()
	print("CONTRACTS_PROBE checks=%d fails=%d" % [checks, fails])
	if fails == 0:
		print("CONTRACTS_PROBE: fails=0")
		quit(0)
	else:
		printerr("CONTRACTS_PROBE: fails=%d" % fails)
		quit(1)


# ----------------------------------------------------------------- helpers ---
func _check(cond: bool, msg: String, detail: String = "") -> void:
	checks += 1
	if cond:
		print("  ok: ", msg)
	else:
		fails += 1
		if detail == "":
			print("  FAIL: ", msg)
		else:
			print("  FAIL: ", msg, " :: ", detail)


func _snapshot_env() -> void:
	_nav_env_present = OS.has_environment("TAT2_NAV")
	if _nav_env_present:
		_nav_env = OS.get_environment("TAT2_NAV")
	_rough_env_present = OS.has_environment("TAT2_ROUGH_BAKE")
	if _rough_env_present:
		_rough_env = OS.get_environment("TAT2_ROUGH_BAKE")


func _restore_env() -> void:
	if _nav_env_present:
		OS.set_environment("TAT2_NAV", _nav_env)
	else:
		OS.unset_environment("TAT2_NAV")
	if _rough_env_present:
		OS.set_environment("TAT2_ROUGH_BAKE", _rough_env)
	else:
		OS.unset_environment("TAT2_ROUGH_BAKE")


# ------------------------------------------------------- 1. TAT2_NAV default ---
func _check_nav() -> void:
	print("--- TAT2_NAV resolver (nav_runtime.gd) ---")
	var nav_scr: GDScript = load(NAV_SCRIPT) as GDScript
	if nav_scr == null:
		_check(false, "nav_runtime.gd loads")
		return
	var nav: Node = nav_scr.new()
	_check(nav != null, "nav_runtime.gd instantiates")
	if nav == null:
		return

	# Default: the feature must be OFF with no variable set, and the consumer
	# must refuse to build anything (state `disabled`).
	OS.unset_environment("TAT2_NAV")
	_check(not bool(nav.call("is_enabled")), "unset TAT2_NAV resolves off")
	var setup_off: bool = bool(nav.call("setup", "guildhall"))
	_check(not setup_off and str(nav.get("_state")) == "disabled",
		"unset TAT2_NAV: setup() refuses and state=disabled",
		"setup=%s state=%s" % [str(setup_off), str(nav.get("_state"))])

	# Explicit off.
	OS.set_environment("TAT2_NAV", "off")
	_check(not bool(nav.call("is_enabled")), "TAT2_NAV=off resolves off")

	# The documented truthy spellings only.
	for truthy: String in ["on", "1", "true", "yes", "  ON  "]:
		OS.set_environment("TAT2_NAV", truthy)
		_check(bool(nav.call("is_enabled")), "TAT2_NAV=%s resolves on" % truthy.strip_edges())

	# Unknown values fail closed: the resolver is false AND the consumer keeps
	# the straight-line-steering degradation.
	for unknown: String in ["banana", "onn", "2", "patrol", "offf", "no"]:
		OS.set_environment("TAT2_NAV", unknown)
		_check(not bool(nav.call("is_enabled")), "unknown TAT2_NAV=%s fails closed to off" % unknown)
	OS.set_environment("TAT2_NAV", "banana")
	var setup_unknown: bool = bool(nav.call("setup", "guildhall"))
	_check(not setup_unknown and str(nav.get("_state")) == "disabled",
		"unknown TAT2_NAV: setup() refuses and state=disabled",
		"setup=%s state=%s" % [str(setup_unknown), str(nav.get("_state"))])

	OS.unset_environment("TAT2_NAV")
	nav.free()


# -------------------------------------------------- 2. TAT2_ROUGH_BAKE=off ---
func _check_rough_bake() -> void:
	print("--- TAT2_ROUGH_BAKE resolver (level_loader.gd) ---")
	var loader_scr: GDScript = load(LOADER_SCRIPT) as GDScript
	if loader_scr == null:
		_check(false, "level_loader.gd loads")
		return

	# Default: no variable -> the full-resolution L8 bake (the shipped path).
	OS.unset_environment("TAT2_ROUGH_BAKE")
	loader_scr.set("_roughness_mode", "")
	loader_scr.set("_roughness_global_cache", {})
	loader_scr.set("_roughness_live_loaders", 0)
	var ll: Node = loader_scr.new()
	if ll == null:
		_check(false, "level_loader.gd instantiates")
		return
	root.add_child(ll)
	var default_enabled: bool = bool(ll.call("_roughness_bake_enabled"))
	_check(default_enabled, "unset TAT2_ROUGH_BAKE keeps the full bake (default)")
	var mat: StandardMaterial3D = ll.call("get_material_for_ue", CONCRETE_MAT) as StandardMaterial3D
	_check(mat != null, "default: %s resolves to StandardMaterial3D" % CONCRETE_MAT.get_file())
	if mat != null:
		var remap_v: Variant = mat.get_meta("ue_roughness_remap", null)
		_check(remap_v is Vector2 and (remap_v as Vector2).is_equal_approx(Vector2(CONCRETE_LOW, CONCRETE_HIGH)),
			"default: authored range 0.2..0.6 reaches the bake metadata",
			"remap=%s" % str(remap_v))
		_check(not mat.has_meta("ue_roughness_flat"),
			"default: the rough_high fallback meta is absent")
		var rough_tex: Texture2D = mat.roughness_texture
		var ao_tex: Texture2D = mat.ao_texture
		_check(rough_tex != null, "default: a baked roughness texture is bound")
		_check(rough_tex != null and ao_tex != null
				and rough_tex.get_width() == ao_tex.get_width()
				and rough_tex.get_height() == ao_tex.get_height(),
			"default: baked roughness texture is full ORM resolution",
			"rough=%s orm=%s" % [_tex_size(rough_tex), _tex_size(ao_tex)])
		_check(is_equal_approx(mat.roughness, 1.0),
			"default: scalar stays 1.0 so the baked map is the value",
			"roughness=%s" % str(mat.roughness))
		var bake_count: int = int(ll.get("_roughness_bake_count"))
		var bake_px: int = int(ll.get("_roughness_bake_px"))
		var expect_px: int = rough_tex.get_width() * rough_tex.get_height() if rough_tex != null else -1
		_check(bake_count >= 1 and bake_px == expect_px,
			"default: bake accounting equals the full base plane (no half-res path)",
			"count=%d px=%d expect=%d" % [bake_count, bake_px, expect_px])
		var img: Image = rough_tex.get_image() if rough_tex != null else null
		_check(img != null and img.get_format() == Image.FORMAT_L8,
			"default: the bake is a single-channel L8 texture",
			"format=%s" % (str(img.get_format()) if img != null else "<null>"))
	ll.free()

	# Off: documented diagnostic fallback -> rough_high scalar, no texture.
	OS.set_environment("TAT2_ROUGH_BAKE", "off")
	loader_scr.set("_roughness_mode", "")
	loader_scr.set("_roughness_global_cache", {})
	loader_scr.set("_roughness_live_loaders", 0)
	var ll_off: Node = loader_scr.new()
	root.add_child(ll_off)
	var off_enabled: bool = bool(ll_off.call("_roughness_bake_enabled"))
	_check(not off_enabled, "TAT2_ROUGH_BAKE=off resolves to the documented fallback")
	var mat_off: StandardMaterial3D = ll_off.call("get_material_for_ue", CONCRETE_MAT) as StandardMaterial3D
	_check(mat_off != null, "off: %s still resolves" % CONCRETE_MAT.get_file())
	if mat_off != null:
		_check(mat_off.roughness_texture == null,
			"off: no roughness texture is bound (ORM green is never re-multiplied)")
		_check(is_equal_approx(mat_off.roughness, CONCRETE_HIGH),
			"off: scalar is the authored high end %.2f" % CONCRETE_HIGH,
			"roughness=%s" % str(mat_off.roughness))
		_check(mat_off.has_meta("ue_roughness_flat")
				and is_equal_approx(float(mat_off.get_meta("ue_roughness_flat")), CONCRETE_HIGH),
			"off: the ue_roughness_flat meta records the high end",
			"meta=%s" % str(mat_off.get_meta("ue_roughness_flat", null)))
		_check(not mat_off.has_meta("ue_roughness_remap"),
			"off: no remap range is registered")
		_check(mat_off.ao_texture != null and mat_off.metallic_texture != null,
			"off: AO and metallic still bind the authored ORM map")
		_check(int(ll_off.get("_roughness_bake_count")) == 0
				and int(ll_off.get("_roughness_bake_px")) == 0,
			"off: no L8 bake was allocated",
			"count=%d px=%d" % [int(ll_off.get("_roughness_bake_count")), int(ll_off.get("_roughness_bake_px"))])
	ll_off.free()

	# Leave the process in the shipped default for the remaining checks.
	OS.unset_environment("TAT2_ROUGH_BAKE")
	loader_scr.set("_roughness_mode", "")
	loader_scr.set("_roughness_global_cache", {})


func _tex_size(tex: Texture2D) -> String:
	if tex == null:
		return "<null>"
	return "%dx%d" % [tex.get_width(), tex.get_height()]


# --------------------------------------- 3. xray_target membership + restore ---
func _check_xray() -> void:
	print("--- xray_target membership + highlight restore ---")
	var loader_scr: GDScript = load(LOADER_SCRIPT) as GDScript
	var loader: Node = loader_scr.new()
	root.add_child(loader)

	var actors: Array = []
	var guard: Node3D = (load(GUARD_SCRIPT) as GDScript).new() as Node3D
	guard.name = "ContractXrayGuard"
	guard.position = Vector3.ZERO
	var guard_points: Array[Vector3] = [Vector3.ZERO]
	guard.set("patrol_points", guard_points)
	root.add_child(guard)
	actors.append(["guard_ai", guard])
	var loot: Node3D = (load(LOOT_SCRIPT) as GDScript).new() as Node3D
	loot.name = "ContractXrayLoot"
	loot.set("item_name", "Silver Candlestick")
	loot.set("value", 75)
	loot.set("loot_tier", "minor")
	root.add_child(loot)
	actors.append(["loot_item", loot])
	var pickup: Node3D = (load(PICKUP_SCRIPT) as GDScript).new() as Node3D
	pickup.name = "ContractXrayPickup"
	pickup.call("setup", 0, "")  # Kind.THROWABLE, fallback mesh
	root.add_child(pickup)
	actors.append(["world_pickup", pickup])
	var clue: Node3D = (load(CLUE_SCRIPT) as GDScript).new() as Node3D
	clue.name = "ContractXrayClue"
	root.add_child(clue)
	actors.append(["clue_item", clue])
	await process_frame
	await process_frame

	for pair: Array in actors:
		var label: String = str(pair[0])
		var actor: Node = pair[1] as Node
		_check(actor.is_in_group("xray_target"),
			"%s joins the authored xray_target group (real instantiated actor)" % label)

	# A highlight on -> off cycle must restore the exact prior material state.
	var restored_all: bool = true
	for pair: Array in actors:
		var label: String = str(pair[0])
		var actor: Node = pair[1] as Node
		var visual: Node3D = null
		var visual_v: Variant = actor.get("visual_root")
		if visual_v is Node3D:
			visual = visual_v as Node3D
		if visual == null:
			visual = actor.get_node_or_null("Visual") as Node3D
		_check(visual != null, "%s exposes a visual subtree" % label)
		if visual == null:
			restored_all = false
			continue
		var meshes: Array = _geometry_list(visual)
		_check(not meshes.is_empty(), "%s visual subtree has geometry to highlight" % label)
		if meshes.is_empty():
			restored_all = false
			continue

		# Pre-set a non-null overlay on the first mesh: an off cycle that just
		# nulls the overlay (the pre-W10 helper) would lose this material.
		var original := StandardMaterial3D.new()
		original.albedo_color = Color(0.12, 0.34, 0.56, 1.0)
		var first: GeometryInstance3D = meshes[0] as GeometryInstance3D
		first.material_overlay = original
		var overlays_before: Dictionary = _overlay_snapshot(meshes)
		var overrides_before: Dictionary = _override_snapshot(meshes)

		actor.call("set_highlighted", true)
		var on_ok: bool = first.material_overlay != null
		var on_shader: bool = first.material_overlay is ShaderMaterial
		var on_resource: String = ""
		if on_shader:
			on_resource = ((first.material_overlay as ShaderMaterial).shader.resource_path
				if (first.material_overlay as ShaderMaterial).shader != null else "")
		for gi_v: Variant in meshes:
			if not ((gi_v as GeometryInstance3D).material_overlay is ShaderMaterial):
				on_ok = false
		_check(on_ok and on_shader and on_resource.ends_with("tat_xray.gdshader"),
			"%s highlight on binds the depth-disabled xray shader on every mesh" % label,
			"resource=%s" % on_resource)
		_check(first.material_overlay != original,
			"%s highlight on replaces the pre-set overlay" % label)

		actor.call("set_highlighted", false)
		var cycle_ok: bool = true
		for gi_v: Variant in meshes:
			var gi: GeometryInstance3D = gi_v as GeometryInstance3D
			var id: int = gi.get_instance_id()
			if gi.material_overlay != overlays_before.get(id):
				cycle_ok = false
			if gi.material_override != overrides_before.get(id):
				cycle_ok = false
			if gi.has_meta("_xray_on") or gi.has_meta("_xray_prev_overlay"):
				cycle_ok = false
		_check(cycle_ok, "%s highlight off restores every original overlay/override and meta" % label)
		_check(first.material_overlay == original,
			"%s highlight off restores the exact pre-set material instance" % label)
		if not cycle_ok or first.material_overlay != original:
			restored_all = false

	_check(restored_all, "all four authored xray categories restore a clean on -> off cycle")

	XrayOverlay.clear_static_caches()
	for pair: Array in actors:
		(pair[1] as Node).queue_free()
	loader.queue_free()
	await process_frame
	await process_frame


func _geometry_list(node: Node) -> Array:
	var out: Array = []
	if node is GeometryInstance3D:
		out.append(node)
	for child: Node in node.find_children("*", "GeometryInstance3D", true, false):
		out.append(child)
	return out


func _overlay_snapshot(meshes: Array) -> Dictionary:
	var out: Dictionary = {}
	for gi_v: Variant in meshes:
		var gi: GeometryInstance3D = gi_v as GeometryInstance3D
		out[gi.get_instance_id()] = gi.material_overlay
	return out


func _override_snapshot(meshes: Array) -> Dictionary:
	var out: Dictionary = {}
	for gi_v: Variant in meshes:
		var gi: GeometryInstance3D = gi_v as GeometryInstance3D
		out[gi.get_instance_id()] = gi.material_override
	return out


# --------------------------------------------- 4. endgame timeout banking ---
func _check_endgame_timeout() -> void:
	print("--- endgame timeout banking (real mission clock) ---")
	var mission_scr: GDScript = load(MISSION_SCRIPT) as GDScript
	if mission_scr == null:
		_check(false, "mission_controller.gd loads")
		return
	var mc: Node = mission_scr.new()
	mc.set("contract_info", {})
	mc.set("hud", null)
	mc.set("_payout_applied", false)

	var run_id: String = "contracts-endgame-%d" % Time.get_ticks_usec()
	_stage_run(750, 1000, run_id, _phase_endgame, 0.0, 10.0)
	var before: int = _currency()
	# One real clock tick past the 10 s endgame window: the PHASE_ENDGAME
	# branch must call _on_door_collapsed(), not the main TIME EXPIRED path.
	mc.call("_process", 10.5)
	var after: int = _currency()
	var last: Dictionary = _ss.call("get_last_match") as Dictionary
	var info: Dictionary = mc.get("contract_info") as Dictionary
	_check(after - before == 750,
		"endgame expiry banks the stashed 750 exactly once",
		"delta=%d" % (after - before))
	_check(str(last.get("match_id", "")) == run_id,
		"endgame expiry records the run's match_id",
		"match_id=%s want=%s" % [str(last.get("match_id", "")), run_id])
	_check(int(last.get("original", -1)) == 1750 and int(last.get("stashed", -1)) == 750,
		"the payout records 1750 gross / 750 stashed (carried tracked but not kept)",
		"original=%s stashed=%s" % [str(last.get("original", "")), str(last.get("stashed", ""))])
	_check(int(last.get("kept", -1)) == 0 and int(last.get("reward", -1)) == 0
			and int(last.get("money_taken", -1)) == 750,
		"the 1000 carried haul is lost (kept=0, reward=0, money_taken=750)",
		"kept=%s reward=%s money=%s" % [str(last.get("kept", "")), str(last.get("reward", "")), str(last.get("money_taken", ""))])
	_check(bool(info.get("timed_out", false)) and str(info.get("timeout_reason", "")) == DOOR_COLLAPSED_REASON,
		"the endgame expiry reports MAGIC DOOR COLLAPSED",
		"timed_out=%s reason=%s" % [str(info.get("timed_out", null)), str(info.get("timeout_reason", ""))])
	_check(str(_gs.get("state")) == "failed" and str(_gs.get("phase")) == _phase_resolved,
		"the run resolves failed/resolved",
		"state=%s phase=%s" % [str(_gs.get("state")), str(_gs.get("phase"))])
	var mirrored: Dictionary = _gs.get("last_payout") as Dictionary
	_check(bool(mirrored.get("applied", false)) and int(mirrored.get("banked", -1)) == 750,
		"last_payout mirrors the banked record (applied=true, banked=750)",
		"applied=%s banked=%s" % [str(mirrored.get("applied", null)), str(mirrored.get("banked", null))])
	_check(float(_gs.get("endgame_elapsed")) >= 10.0,
		"the endgame clock advanced by the tick",
		"endgame_elapsed=%s" % str(_gs.get("endgame_elapsed")))

	# Exactly once: a second tick and a direct handler call must be inert.
	mc.call("_process", 10.5)
	mc.call("_on_door_collapsed")
	_check(_currency() == after, "a repeated endgame tick/DoorCollapsed banks nothing")
	_check(str((_ss.call("get_last_match") as Dictionary).get("match_id", "")) == run_id,
		"a repeated tick does not rewrite the recorded match")
	mc.free()

	# Control: the main-phase expiry still reports TIME EXPIRED (so the two
	# reasons are genuinely distinct and the endgame test cannot pass on a
	# mis-wired shared branch).
	var control: Node = mission_scr.new()
	control.set("contract_info", {})
	control.set("hud", null)
	control.set("_payout_applied", false)
	var run2: String = "contracts-main-%d" % Time.get_ticks_usec()
	_stage_run(500, 1000, run2, _phase_main, 10.0, 0.0)
	var before2: int = _currency()
	control.call("_process", 10.5)
	var after2: int = _currency()
	var info2: Dictionary = control.get("contract_info") as Dictionary
	_check(after2 - before2 == 500,
		"main-phase expiry banks its stashed 500",
		"delta=%d" % (after2 - before2))
	_check(str(info2.get("timeout_reason", "")) == TIME_EXPIRED_REASON,
		"main-phase expiry keeps the TIME EXPIRED reason",
		"reason=%s" % str(info2.get("timeout_reason", "")))
	control.free()


func _stage_run(stashed: int, carried_value: int, run_id: String, phase: String,
		main_limit: float, endgame_limit: float) -> void:
	_gs.call("reset_run", 2, "guildhall")
	_gs.set("state", "playing")
	_gs.set("difficulty", 1)
	_gs.set("free_play", false)
	_gs.set("free_play_pending", false)
	_gs.set("pending_mission_id", "")
	_gs.set("active_mission_id", "")
	_gs.set("loot_run_id", run_id)
	_gs.set("stashed_loot_value", stashed)
	var carried: Array[Dictionary] = []
	if carried_value > 0:
		carried.append({
			"name": "Purse",
			"value": carried_value,
			"tier": "major",
			"slot_cost": 3,
			"is_quest_item": false,
		})
	_gs.set("carried_loot", carried)
	_gs.set("carried_tracking_active", true)
	_gs.set("loot_value", stashed + carried_value)
	_gs.set("loot_goal", 0)
	_gs.set("loot_needed", 0)
	var empty_objectives: Array[Dictionary] = []
	_gs.set("mission_objectives", empty_objectives)
	_gs.set("quest_item_acquired", true)
	_gs.set("ever_spotted", false)
	_gs.set("ever_chased", false)
	_gs.set("phase", phase)
	_gs.set("elapsed_sec", 0.0)
	_gs.set("run_time_limit", main_limit)
	_gs.set("endgame_elapsed", 0.0)
	_gs.set("endgame_time_limit", endgame_limit)
	var empty_markers: Array[Dictionary] = []
	var empty_players: Array[int] = []
	_gs.set("escape_markers", empty_markers)
	_gs.set("extracted_players", empty_players)


func _currency() -> int:
	return int((_ss.get("data") as Dictionary).get("currency", 0))


func _snapshot_state() -> void:
	_save_snap = (_ss.get("data") as Dictionary).duplicate(true)
	_gs_snap = {
		"state": _gs.get("state"),
		"phase": _gs.get("phase"),
		"elapsed": _gs.get("elapsed_sec"),
		"run_limit": _gs.get("run_time_limit"),
		"endgame_limit": _gs.get("endgame_time_limit"),
		"endgame_elapsed": _gs.get("endgame_elapsed"),
		"markers": (_gs.get("escape_markers") as Array).duplicate(true),
		"extracted": (_gs.get("extracted_players") as Array).duplicate(),
		"collected": _gs.get("loot_collected"),
		"needed": _gs.get("loot_needed"),
		"value": _gs.get("loot_value"),
		"goal": _gs.get("loot_goal"),
		"carried": (_gs.get("carried_loot") as Array).duplicate(true),
		"tracking": _gs.get("carried_tracking_active"),
		"stashed": _gs.get("stashed_loot_value"),
		"run_id": _gs.get("loot_run_id"),
		"last_payout": (_gs.get("last_payout") as Dictionary).duplicate(true),
		"objectives": (_gs.get("mission_objectives") as Array).duplicate(true),
		"quest_item": _gs.get("quest_item_acquired"),
		"free_play": _gs.get("free_play"),
		"free_play_pending": _gs.get("free_play_pending"),
		"pending_mission": _gs.get("pending_mission_id"),
		"order": _gs.get("active_contract_order"),
		"map": _gs.get("active_map_id"),
		"mission": _gs.get("active_mission_id"),
		"difficulty": _gs.get("difficulty"),
		"spotted": _gs.get("ever_spotted"),
		"chased": _gs.get("ever_chased"),
		"seed": _gs.get("active_map_seed"),
		"variants": (_gs.get("active_scene_variants") as Array).duplicate(),
	}


func _restore_state() -> void:
	_gs.set("state", str(_gs_snap.get("state", "menu")))
	_gs.set("phase", str(_gs_snap.get("phase", _phase_main)))
	_gs.set("elapsed_sec", float(_gs_snap.get("elapsed", 0.0)))
	_gs.set("run_time_limit", float(_gs_snap.get("run_limit", 0.0)))
	_gs.set("endgame_time_limit", float(_gs_snap.get("endgame_limit", 0.0)))
	_gs.set("endgame_elapsed", float(_gs_snap.get("endgame_elapsed", 0.0)))
	_gs.set("escape_markers", _gs_snap.get("markers", []) as Array[Dictionary])
	_gs.set("extracted_players", _gs_snap.get("extracted", []) as Array[int])
	_gs.set("loot_collected", int(_gs_snap.get("collected", 0)))
	_gs.set("loot_needed", int(_gs_snap.get("needed", 0)))
	_gs.set("loot_value", int(_gs_snap.get("value", 0)))
	_gs.set("loot_goal", int(_gs_snap.get("goal", 0)))
	_gs.set("carried_loot", _gs_snap.get("carried", []) as Array[Dictionary])
	_gs.set("carried_tracking_active", bool(_gs_snap.get("tracking", false)))
	_gs.set("stashed_loot_value", int(_gs_snap.get("stashed", 0)))
	_gs.set("loot_run_id", str(_gs_snap.get("run_id", "")))
	_gs.set("last_payout", _gs_snap.get("last_payout", {}) as Dictionary)
	_gs.set("mission_objectives", _gs_snap.get("objectives", []) as Array[Dictionary])
	_gs.set("quest_item_acquired", bool(_gs_snap.get("quest_item", false)))
	_gs.set("free_play", bool(_gs_snap.get("free_play", false)))
	_gs.set("free_play_pending", bool(_gs_snap.get("free_play_pending", false)))
	_gs.set("pending_mission_id", str(_gs_snap.get("pending_mission", "")))
	_gs.set("active_contract_order", int(_gs_snap.get("order", 2)))
	_gs.set("active_map_id", str(_gs_snap.get("map", "old_manor")))
	_gs.set("active_mission_id", str(_gs_snap.get("mission", "")))
	_gs.set("difficulty", int(_gs_snap.get("difficulty", 1)))
	_gs.set("ever_spotted", bool(_gs_snap.get("spotted", false)))
	_gs.set("ever_chased", bool(_gs_snap.get("chased", false)))
	_gs.set("active_map_seed", int(_gs_snap.get("seed", 0)))
	_gs.set("active_scene_variants", _gs_snap.get("variants", []) as Array[String])
	_ss.set("data", _save_snap)
	_ss.call("write_save")
