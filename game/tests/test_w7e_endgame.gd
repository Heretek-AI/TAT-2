extends SceneTree
## W7E focused gate: two-phase run clock (main 3300 s mission row, endgame
## 1200 s KF13 override / 480 s QG plan), phase transitions, both timeouts,
## endgame-only extraction, the 240 s door lifetime, all 25 authored escape
## markers, free-play no-bank and the HUD countdown/door strings.
##
## Run:
##   XDG_DATA_HOME=/tmp/opencode/w7e-data tools/godot --headless --path game \
##     --script res://tests/test_w7e_endgame.gd

const OUT_MISSION := "Mission.Guildhall.LootTheRoom"
const VAULT_MISSION := "Mission.Guildhall.VaultHeist"
const ESCAPE_SCRIPT := "res://src/interact/escape_gate.gd"
const MISSION_SCRIPT := "res://src/missions/mission_controller.gd"
const HUD_SCRIPT := "res://src/ui/hud.gd"

const LEVEL_FILES := {
	"guildhall": [
		"res://data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json",
		"res://data/generated/levels/Guildhall/Guildhall_P.tatlevel.json",
	],
	"old_manor": [
		"res://data/generated/levels/OldManor/OldManor_Gameplay.tatlevel.json",
	],
	"ftue": [
		"res://data/generated/levels/FTUE/FTUE_Geometry.tatlevel.json",
	],
}

var fails: int = 0
var gs: Node


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	if cond:
		print("PASS: ", ok_msg)
	else:
		printerr("FAIL: ", fail_msg)
		fails += 1


func _wait(n: int) -> void:
	for _i: int in range(n):
		await process_frame


func _reset_run(map_id: String = "guildhall") -> void:
	gs.call("reset_run", 2, map_id)
	gs.set("state", "playing")
	gs.set("difficulty", 1)
	gs.set("quest_item_acquired", false)
	gs.set("mission_objectives", [])
	gs.set("loot_goal", 0)


func _new_mission() -> Node:
	return (load(MISSION_SCRIPT) as GDScript).new() as Node


func _markers_for_map(map_id: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for path: String in LEVEL_FILES.get(map_id, []) as Array:
		if not FileAccess.file_exists(path):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (data is Dictionary):
			continue
		for mk_v: Variant in ((data as Dictionary).get("markers", []) as Array):
			if not (mk_v is Dictionary):
				continue
			var mk: Dictionary = mk_v as Dictionary
			var cls: String = str(mk.get("class", ""))
			if cls.find("Escape") < 0:
				continue
			var pos_v: Variant = mk.get("pos", null)
			if pos_v is Array and (pos_v as Array).size() >= 3:
				var p: Array = pos_v as Array
				out.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	return out


## Synthetic physics world with a floor slab below every marker, so the real
## _ground_escape_position raycast path (hit flag + 0.15 m clearance) can be
## exercised for all authored markers in one pass.
func _make_marker_world(markers: Array[Vector3]) -> Node3D:
	var arena := Node3D.new()
	arena.name = "W7EMarkerWorld"
	root.add_child(arena)
	for i: int in range(markers.size()):
		var raw: Vector3 = markers[i]
		var body := StaticBody3D.new()
		body.name = "MarkerFloor%d" % i
		body.collision_layer = 1
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		# Narrow column: only this marker's ray hits it (authored duplicates sit
		# >0.2 m apart and share a Y, so a same-height neighbour is harmless).
		box.size = Vector3(0.4, 1.0, 0.4)
		col.shape = box
		body.add_child(col)
		# Box top = raw.y - 0.5, so the 8 m -> -30 m cast always hits it.
		body.position = Vector3(raw.x, raw.y - 1.0, raw.z)
		arena.add_child(body)
	await physics_frame
	await physics_frame
	return arena


func _initialize() -> void:
	await process_frame
	gs = root.get_node_or_null("/root/GameState")
	var gd: Node = root.get_node_or_null("/root/GameData")
	_check(gs != null and gd != null, "S5.0 GameState/GameData autoloads present", "S5.0 autoloads missing")
	if gs == null or gd == null:
		_finish()
		return

	var mc: Node = _new_mission()

	# --- S5.1 main clock: mission row beats the hosting map window -----------
	# R10: the LootTheRoom row is the free-play side mission. A contract deploy
	# is required to run the authored per-map contract row instead (S5.1c), so
	# this fixture states the free-play mode it is testing.
	_reset_run()
	gs.set("free_play", true)
	gs.set("active_mission_id", OUT_MISSION)
	var clock: Dictionary = mc.call("_apply_run_clock", "guildhall") as Dictionary
	_check(absf(float(gs.get("run_time_limit")) - 3300.0) < 0.5 and str(clock.get("main_source", "")) == "mission_row",
		"S5.1a main clock=3300 s from the LootTheRoom mission row (not Guildhall 7200)",
		"S5.1a main clock=%s source=%s (want 3300 mission_row)" % [str(gs.get("run_time_limit")), str(clock.get("main_source", ""))])
	gs.set("active_mission_id", "")
	clock = mc.call("_apply_run_clock", "guildhall") as Dictionary
	_check(absf(float(gs.get("run_time_limit")) - 7200.0) < 0.5 and str(clock.get("main_source", "")) == "map_row",
		"S5.1b legacy path with no mission id falls back to the map row (7200)",
		"S5.1b main clock=%s source=%s (want 7200 map_row)" % [str(gs.get("run_time_limit")), str(clock.get("main_source", ""))])
	# S5.1c: a contract deploy never runs the side-mission row. Contract 2's
	# prep default lands on LootTheRoom positionally; the clock must resolve the
	# authored per-map contract row (VaultHeist, contract-flow.md §3).
	# W9-P1: the endgame window is no longer the bare QG plan. The authored
	# ladder (project_settings project.endgame_durations_by_difficulty =
	# [1200, 600, 300]) is the second precedence level, and GameState.reset_run()
	# publishes the 0-based Novice index 0, so VaultHeist gets 1200 s
	# (source project_settings). The old 300 s assertion recorded the defect
	# (the authored ladder was unread); the QG plan itself stays 300 (S5.2a).
	_reset_run()
	gs.set("free_play", false)
	gs.set("active_mission_id", OUT_MISSION)
	clock = mc.call("_apply_run_clock", "guildhall") as Dictionary
	_check(absf(float(gs.get("run_time_limit")) - 7200.0) < 0.5
		and str(clock.get("main_source", "")) == "mission_row"
		and absf(float(gs.get("endgame_time_limit")) - 1200.0) < 0.5
		and str(clock.get("endgame_source", "")) == "project_settings",
		"S5.1c contract deploy resolves the authored per-map contract row (7200 s main + authored 1200 s Novice endgame)",
		"S5.1c main=%s endgame=%s source=%s (want 7200 mission_row + 1200 project_settings)" % [
			str(gs.get("run_time_limit")), str(gs.get("endgame_time_limit")), str(clock.get("endgame_source", ""))])
	# S5.1d: the OldManor Cleanout row is a side mission too (its plan authors
	# three loot_amount objectives); contract 5 must run the OldManor Vault row.
	# W9-P1: same authored ladder — Novice is 1200 s, not the QG plan's 480 s.
	_reset_run("old_manor")
	gs.set("free_play", false)
	gs.set("active_mission_id", "Mission.OldManor.LootTheRoom")
	clock = mc.call("_apply_run_clock", "old_manor") as Dictionary
	_check(absf(float(gs.get("run_time_limit")) - 7200.0) < 0.5
		and absf(float(gs.get("endgame_time_limit")) - 1200.0) < 0.5
		and str(clock.get("endgame_source", "")) == "project_settings",
		"S5.1d OldManor contract deploy resolves Mission.OldManor.Vault (7200 s main + authored 1200 s Novice endgame)",
		"S5.1d main=%s endgame=%s source=%s (want 7200 + 1200 project_settings)" % [
			str(gs.get("run_time_limit")), str(gs.get("endgame_time_limit")), str(clock.get("endgame_source", ""))])

	# --- S5.2 endgame window: KF13 override 1200, authored QG plan 480 ------
	var plan: Dictionary = gd.call("get_mission_plan", OUT_MISSION) as Dictionary
	_check(int(plan.get("endgame_duration", 0)) == 480,
		"S5.2a QG plan endgame stays 480 s (no silent re-baseline)",
		"S5.2a QG plan endgame=%s (want 480)" % str(plan.get("endgame_duration")))
	_check(absf(float(gd.call("get_mission_endgame_seconds", OUT_MISSION)) - 1200.0) < 0.5
		and str(gd.call("get_mission_endgame_source", OUT_MISSION)) == "KF13",
		"S5.2b runtime endgame=1200 s from the KF13 override",
		"S5.2b runtime endgame=%s source=%s" % [str(gd.call("get_mission_endgame_seconds", OUT_MISSION)), str(gd.call("get_mission_endgame_source", OUT_MISSION))])
	gs.set("active_mission_id", OUT_MISSION)
	gs.set("free_play", true) # the KF13 override belongs to the LootTheRoom row
	clock = mc.call("_apply_run_clock", "guildhall") as Dictionary
	_check(absf(float(gs.get("endgame_time_limit")) - 1200.0) < 0.5 and str(clock.get("endgame_source", "")) == "KF13",
		"S5.2c run clock applies the 1200 s endgame (source KF13)",
		"S5.2c endgame limit=%s source=%s" % [str(gs.get("endgame_time_limit")), str(clock.get("endgame_source", ""))])
	gs.set("active_mission_id", VAULT_MISSION)
	gs.set("free_play", false)
	clock = mc.call("_apply_run_clock", "guildhall") as Dictionary
	# W9-P1: VaultHeist's runtime window is the authored Novice ladder value
	# (1200 s, source project_settings). The old 300 s / quest_graph assertion
	# recorded the defect that project_settings.json had no consumer; the QG
	# plan endgame_duration is still 300 (S5.2a) and the ladder never overrides
	# the KF13 letter (S5.2b/c).
	_check(absf(float(gs.get("endgame_time_limit")) - 1200.0) < 0.5 and str(clock.get("endgame_source", "")) == "project_settings",
		"S5.2d VaultHeist uses the authored 1200 s Novice endgame ladder",
		"S5.2d VaultHeist endgame=%s source=%s (want 1200 project_settings)" % [str(gs.get("endgame_time_limit")), str(clock.get("endgame_source", ""))])

	# --- S5.3 phase transitions: only the active phase ticks ----------------
	_reset_run()
	gs.set("active_mission_id", OUT_MISSION)
	mc.call("_apply_run_clock", "guildhall")
	_check(str(gs.get("phase")) == "main" and gs.call("is_main_phase"),
		"S5.3a a fresh run starts in the main phase",
		"S5.3a fresh phase=%s" % str(gs.get("phase")))
	mc.call("_on_objective_completed")
	_check(str(gs.get("phase")) == "endgame" and absf(float(gs.get("endgame_elapsed"))) < 0.001,
		"S5.3b objective completion starts the endgame at elapsed 0",
		"S5.3b phase=%s endgame_elapsed=%s" % [str(gs.get("phase")), str(gs.get("endgame_elapsed"))])
	mc.call("_process", 10.0)
	_check(absf(float(gs.get("endgame_elapsed")) - 10.0) < 0.001 and absf(float(gs.get("elapsed_sec"))) < 0.001,
		"S5.3c endgame ticks endgame_elapsed and freezes the main clock",
		"S5.3c endgame_elapsed=%s elapsed_sec=%s" % [str(gs.get("endgame_elapsed")), str(gs.get("elapsed_sec"))])
	mc.call("_on_objective_completed")
	_check(absf(float(gs.get("endgame_elapsed")) - 10.0) < 0.001,
		"S5.3d repeated completion does not reset the endgame clock",
		"S5.3d endgame_elapsed=%s (want 10)" % str(gs.get("endgame_elapsed")))

	# --- S5.4 main expiry: existing TIME EXPIRED failure ---------------------
	_reset_run()
	gs.set("active_mission_id", OUT_MISSION)
	mc.call("_apply_run_clock", "guildhall")
	gs.set("run_time_limit", 5.0)
	gs.set("elapsed_sec", 0.0)
	mc.call("_process", 5.1)
	_check(str(gs.get("state")) == "failed" and str(gs.get("phase")) == "resolved"
		and str(mc.get("contract_info").get("timeout_reason", "")) == "TIME EXPIRED",
		"S5.4 main window expiry fails with TIME EXPIRED and resolves the phase",
		"S5.4 state=%s phase=%s reason=%s" % [str(gs.get("state")), str(gs.get("phase")), str(mc.get("contract_info").get("timeout_reason", ""))])

	# --- S5.5 endgame expiry: door collapse, no letter grace ----------------
	_reset_run()
	gs.set("active_mission_id", OUT_MISSION)
	mc.call("_apply_run_clock", "guildhall")
	gs.set("endgame_time_limit", 5.0)
	mc.set("_letter_grace_sec", 6.0)
	mc.set("contract_info", {})
	mc.call("_start_endgame", "test")
	_check(absf(float(mc.get("_letter_grace_sec"))) < 0.001,
		"S5.5a starting the endgame drops the letter grace",
		"S5.5a letter grace=%s (want 0)" % str(mc.get("_letter_grace_sec")))
	mc.call("_process", 1.0)
	_check(absf(float(gs.get("endgame_elapsed")) - 1.0) < 0.001 and absf(float(gs.get("elapsed_sec"))) < 0.001,
		"S5.5b endgame clock ticks immediately after the letter grace is cleared",
		"S5.5b endgame_elapsed=%s elapsed_sec=%s" % [str(gs.get("endgame_elapsed")), str(gs.get("elapsed_sec"))])
	mc.call("_process", 4.1)
	_check(str(gs.get("state")) == "failed" and str(gs.get("phase")) == "resolved"
		and str(mc.get("contract_info").get("timeout_reason", "")) == "MAGIC DOOR COLLAPSED",
		"S5.5c endgame expiry fails with MAGIC DOOR COLLAPSED",
		"S5.5c state=%s phase=%s reason=%s" % [str(gs.get("state")), str(gs.get("phase")), str(mc.get("contract_info").get("timeout_reason", ""))])

	# --- S5.6 extraction is endgame-only and activation-gated --------------
	var arena := Node3D.new()
	arena.name = "W7EGateArena"
	root.add_child(arena)
	await _wait(2)
	var gate: Area3D = (load(ESCAPE_SCRIPT) as GDScript).new() as Area3D
	arena.add_child(gate)
	await _wait(2)
	var emits: Array = []
	gate.connect("extracted", func() -> void: emits.append(1))
	var body := CharacterBody3D.new()
	body.add_to_group("player")
	root.add_child(body)
	_reset_run()
	gs.set("state", "playing")
	gs.set("quest_item_acquired", true)
	gs.set("mission_objectives", [])
	gs.set("loot_goal", 0)
	gs.set("phase", "endgame")
	gate.call("_on_body_entered", body)
	_check(emits.is_empty(), "S5.6a a dormant door does not extract in the endgame",
		"S5.6a dormant door extracted")
	gate.call("activate")
	gate.call("_on_body_entered", body)
	_check(emits.size() == 1 and bool(gate.get("activated")) and bool(gate.get("active")),
		"S5.6b an activated door extracts in the endgame",
		"S5.6b emits=%d activated=%s active=%s" % [emits.size(), str(gate.get("activated")), str(gate.get("active"))])
	gs.set("phase", "main")
	gate.set("use_count", 0)
	gate.call("_on_body_entered", body)
	_check(emits.size() == 1, "S5.6c the main phase cannot extract even from an activated door",
		"S5.6c main-phase extraction fired (emits=%d)" % emits.size())
	body.queue_free()
	gate.queue_free()
	arena.queue_free()
	await _wait(2)

	# --- S5.7 240 s authored door lifetime ----------------------------------
	var life_arena := Node3D.new()
	root.add_child(life_arena)
	await _wait(2)
	var life_gate: Area3D = (load(ESCAPE_SCRIPT) as GDScript).new() as Area3D
	life_arena.add_child(life_gate)
	await _wait(2)
	_check(absf(float(life_gate.get("open_duration_sec")) - 240.0) < 0.01,
		"S5.7a authored BP_EscapePoint open lifetime=240 s",
		"S5.7a open lifetime=%s (want 240)" % str(life_gate.get("open_duration_sec")))
	life_gate.call("activate")
	life_gate.call("_process", 239.0)
	_check(bool(life_gate.get("active")) and not bool(life_gate.get("expired")),
		"S5.7b door stays open through 239 s",
		"S5.7b active=%s expired=%s" % [str(life_gate.get("active")), str(life_gate.get("expired"))])
	life_gate.call("_process", 1.1)
	var portal: MeshInstance3D = life_gate.get("portal_visual") as MeshInstance3D
	_check(bool(life_gate.get("expired")) and not bool(life_gate.get("active")) and portal != null and not portal.visible,
		"S5.7c door expires at 240 s and its portal is hidden",
		"S5.7c expired=%s active=%s portal_visible=%s" % [str(life_gate.get("expired")), str(life_gate.get("active")), str(portal.visible if portal != null else false)])
	life_gate.queue_free()
	life_arena.queue_free()
	await _wait(2)

	# --- S5.11 R10: the authored 240 s cycle re-arms inside the endgame ------
	# The 1200 s endgame must have exits for the whole window: a gate whose
	# 240 s BP_EscapePoint cycle closes is re-summoned while the endgame is
	# live, and the terminal collapse at 1200 s can never be undone.
	var rearm_arena := Node3D.new()
	rearm_arena.name = "W7ERearmArena"
	root.add_child(rearm_arena)
	await _wait(2)
	var rearm_gate: Area3D = (load(ESCAPE_SCRIPT) as GDScript).new() as Area3D
	rearm_arena.add_child(rearm_gate)
	await _wait(2)
	var rearm_emits: Array = []
	rearm_gate.connect("extracted", func() -> void: rearm_emits.append(1))
	_reset_run()
	gs.set("free_play", true)
	gs.set("active_mission_id", OUT_MISSION)
	gs.set("quest_item_acquired", true)
	gs.set("mission_objectives", [])
	gs.set("loot_goal", 0)
	mc.call("_apply_run_clock", "guildhall")
	gs.call("set_escape_markers", [{"gate": rearm_gate, "activated": false, "expired": false, "index": 0}])
	mc.call("_start_endgame", "suite_rearm")
	_check(bool(rearm_gate.get("active")) and bool(rearm_gate.get("activated")),
		"S5.11a the endgame summons the marker",
		"S5.11a active=%s activated=%s" % [str(rearm_gate.get("active")), str(rearm_gate.get("activated"))])
	rearm_gate.call("_process", 240.1)
	_check(bool(rearm_gate.get("expired")) and not bool(rearm_gate.get("active")),
		"S5.11b the authored 240 s cycle closes the portal",
		"S5.11b expired=%s active=%s" % [str(rearm_gate.get("expired")), str(rearm_gate.get("active"))])
	mc.call("_process", 1.0)
	var rearm_rec: Dictionary = (gs.get("escape_markers") as Array)[0] as Dictionary
	_check(bool(rearm_gate.get("active")) and not bool(rearm_gate.get("expired"))
		and int(rearm_gate.get("rearm_count")) == 1 and rearm_rec.get("expired", true) == false,
		"S5.11c the live endgame re-arms the portal (240 s cycle, rearm=1)",
		"S5.11c active=%s expired=%s rearm=%d rec_expired=%s" % [str(rearm_gate.get("active")), str(rearm_gate.get("expired")), int(rearm_gate.get("rearm_count")), str(rearm_rec.get("expired", true))])
	# 16 minutes into a 20 minute endgame the door still extracts.
	gs.set("endgame_elapsed", 1000.0)
	rearm_gate.call("_process", 240.1)
	mc.call("_process", 1.0)
	var body_r := CharacterBody3D.new()
	body_r.add_to_group("player")
	root.add_child(body_r)
	rearm_gate.call("_on_body_entered", body_r)
	_check(rearm_emits.size() == 1 and int(rearm_gate.get("rearm_count")) == 2,
		"S5.11d an extraction at endgame t=1001 s still fires (no 240 s dead window)",
		"S5.11d emits=%d rearm=%d" % [rearm_emits.size(), int(rearm_gate.get("rearm_count"))])
	# Terminal collapse: the endgame window closes, and nothing revives it.
	_reset_run()
	gs.set("free_play", true)
	gs.set("active_mission_id", OUT_MISSION)
	gs.set("quest_item_acquired", true)
	mc.call("_apply_run_clock", "guildhall")
	gs.set("endgame_time_limit", 0.1)
	gs.call("set_escape_markers", [{"gate": rearm_gate, "activated": false, "expired": false, "index": 0}])
	mc.call("_start_endgame", "suite_collapse")
	mc.call("_process", 0.2)
	var revive: bool = bool(rearm_gate.call("activate"))
	rearm_gate.call("_on_body_entered", body_r)
	_check(bool(rearm_gate.get("collapsed")) and not revive and not bool(rearm_gate.call("is_available"))
		and rearm_emits.size() == 1,
		"S5.11e MAGIC DOOR COLLAPSED is terminal: collapse blocks re-arm and extraction",
		"S5.11e collapsed=%s revive=%s available=%s emits=%d" % [str(rearm_gate.get("collapsed")), str(revive), str(rearm_gate.call("is_available")), rearm_emits.size()])
	body_r.queue_free()
	rearm_gate.queue_free()
	rearm_arena.queue_free()
	await _wait(2)
	gs.set("escape_markers", [])

	# --- S5.8 all 25 authored escape markers --------------------------------
	var gh_markers: Array[Vector3] = _markers_for_map("guildhall")
	var om_markers: Array[Vector3] = _markers_for_map("old_manor")
	var ftue_markers: Array[Vector3] = _markers_for_map("ftue")
	_check(gh_markers.size() == 14 and om_markers.size() == 10 and ftue_markers.size() == 1
		and gh_markers.size() + om_markers.size() + ftue_markers.size() == 25,
		"S5.8a authored markers are Guildhall 14 + OldManor 10 + FTUE 1 = 25",
		"S5.8a authored markers Guildhall=%d OldManor=%d FTUE=%d" % [gh_markers.size(), om_markers.size(), ftue_markers.size()])
	var all_markers: Array[Vector3] = []
	all_markers.append_array(gh_markers)
	all_markers.append_array(om_markers)
	all_markers.append_array(ftue_markers)
	var marker_world: Node3D = await _make_marker_world(all_markers)
	var spawn_mc: Node = _new_mission()
	var spawned: int = int(spawn_mc.call("_spawn_escape", all_markers, Vector3.ZERO, marker_world.get_world_3d()))
	var records: Array = gs.get("escape_markers") as Array
	var grounded: int = 0
	var connected: int = 0
	var positioned: int = 0
	for i: int in range(records.size()):
		var rec: Dictionary = records[i] as Dictionary
		if rec.get("grounded", false) == true:
			grounded += 1
		if rec.get("connected", false) == true:
			connected += 1
		var raw: Vector3 = all_markers[i]
		var pos_v: Variant = rec.get("position", null)
		if pos_v is Vector3 and absf((pos_v as Vector3).y - (raw.y - 0.35)) < 0.02 \
			and absf((pos_v as Vector3).x - raw.x) < 0.02 and absf((pos_v as Vector3).z - raw.z) < 0.02:
			positioned += 1
	_check(spawned == 25 and records.size() == 25 and grounded == 25 and connected == 25 and positioned == 25,
		"S5.8b all 25 markers spawned, floor-grounded (+0.15 m) and connected",
		"S5.8b spawned=%d records=%d grounded=%d connected=%d positioned=%d" % [spawned, records.size(), grounded, connected, positioned])
	spawn_mc.free()
	marker_world.queue_free()
	gs.set("escape_markers", [])
	await _wait(2)

	# Live integration: contract 2 with the LootTheRoom mission id spawns the
	# 14 authored Guildhall gates and summons them on the phase boundary.
	var helpers_scr: GDScript = load("res://tests/e2e/e2e_helpers.gd") as GDScript
	var h: RefCounted = helpers_scr.new(self)
	_reset_run()
	gs.set("active_mission_id", OUT_MISSION)
	var miss: Dictionary = await h.instantiate_mission(2, 300, 1)
	var live: Node = miss.get("mission") as Node
	await _wait(3)
	var live_gates: Array[Node] = get_nodes_in_group("escape_points")
	var live_records: Array = gs.get("escape_markers") as Array
	var live_inactive: int = 0
	for g: Node in live_gates:
		if g.get("active") != true and g.get("activated") != true:
			live_inactive += 1
	_check(live != null and live_gates.size() == 14 and live_records.size() == 14 and live_inactive == 14,
		"S5.8c live Guildhall run spawns 14 dormant authored gates (clock %.0f s)" % float(gs.get("run_time_limit")),
		"S5.8c live gates=%d records=%d dormant=%d" % [live_gates.size(), live_records.size(), live_inactive])
	if live != null:
		live.call("_start_endgame", "suite")
		var live_active: int = 0
		for g2: Node in live_gates:
			if g2.get("active") == true and g2.get("activated") == true:
				live_active += 1
		_check(str(gs.get("phase")) == "endgame" and live_active == 14 and int(gs.call("active_escape_count")) == 14,
			"S5.8d objective completion summons all 14 live doors",
			"S5.8d phase=%s active=%d/%d state_active=%d" % [str(gs.get("phase")), live_active, live_gates.size(), int(gs.call("active_escape_count"))])
		await h.free_node(live)
	await _wait(2)
	gs.set("escape_markers", [])

	# --- S5.9 free play banks nothing on extraction -------------------------
	var ss: Node = root.get_node_or_null("/root/SaveSystem")
	var save_data: Dictionary = ss.get("data") as Dictionary
	var before_completed: Dictionary = (save_data.get("completed_contracts", {}) as Dictionary).duplicate(true)
	var before_currency: int = int(save_data.get("currency", 0))
	var before_xp: int = int(save_data.get("xp", 0))
	_reset_run()
	gs.set("free_play", true)
	gs.set("free_play_pending", true)
	gs.set("pending_mission_id", OUT_MISSION)
	gs.set("active_mission_id", OUT_MISSION)
	gs.set("loot_value", 500)
	var hud: Node = (load(HUD_SCRIPT) as GDScript).new() as Node
	root.add_child(hud)
	await _wait(3)
	var bank_mc: Node = _new_mission()
	bank_mc.set("hud", hud)
	bank_mc.set("contract_info", {"title": "Cleanout Heist"})
	bank_mc.call("_on_extracted")
	await _wait(2)
	var no_write: bool = (save_data.get("completed_contracts", {}) as Dictionary) == before_completed \
		and int(save_data.get("xp", 0)) == before_xp
	var no_currency: bool = int(save_data.get("currency", 0)) == before_currency
	_check(no_write and no_currency,
		"S5.9 free-play extraction writes no contract and banks no currency",
		"S5.9 free-play no_contract_write=%s no_currency_bank=%s" % [str(no_write), str(no_currency)])
	bank_mc.free()

	# --- S5.10 HUD countdown + door warning --------------------------------
	_reset_run()
	gs.set("phase", "main")
	gs.set("run_time_limit", 3300.0)
	gs.set("elapsed_sec", 0.0)
	var main_str: String = str(hud.call("phase_countdown_text"))
	var main_warn: String = str(hud.call("door_warning_text"))
	gs.call("begin_endgame", 1200.0)
	gs.set("endgame_elapsed", 0.0)
	var end_str: String = str(hud.call("phase_countdown_text"))
	var end_warn: String = str(hud.call("door_warning_text"))
	hud.call("_update_phase_banner", false)
	var door_lbl: Label = hud.get("door_lbl") as Label
	_check(main_str == "55:00" and main_warn == "",
		"S5.10a main HUD countdown reads 55:00 with no door warning",
		"S5.10a main='%s' warn='%s'" % [main_str, main_warn])
	_check(end_str == "20:00" and end_warn.find("MAGIC DOOR") >= 0 and end_warn.find("20:00") >= 0,
		"S5.10b endgame HUD countdown reads 20:00 with the door warning",
		"S5.10b endgame='%s' warn='%s'" % [end_str, end_warn])
	_check(door_lbl != null and door_lbl.visible and door_lbl.text == end_warn,
		"S5.10c endgame door banner is visible with the warning text",
		"S5.10c banner visible=%s text='%s'" % [str(door_lbl.visible if door_lbl != null else false), str(door_lbl.text if door_lbl != null else "")])
	gs.set("endgame_elapsed", 60.0)
	_check(str(hud.call("phase_countdown_text")) == "19:00",
		"S5.10d endgame countdown ticks down (60 s -> 19:00)",
		"S5.10d endgame='%s'" % str(hud.call("phase_countdown_text")))
	hud.call("_update_phase_banner", true)
	_check(not door_lbl.visible, "S5.10e door banner is hidden on the hub", "S5.10e door banner visible on hub")
	hud.queue_free()
	await _wait(2)

	mc.free()
	_reset_run()
	gs.set("state", "menu")
	_finish()


func _finish() -> void:
	print("W7E_SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)
