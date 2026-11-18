extends SceneTree
## Master E2E Headless Test Runner for Thick As Thieves (TAT-2) Desktop Linux / Vulkan Forward+ Parity.
## Invocation:
##   flatpak run org.godotengine.Godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd
##   flatpak run org.godotengine.Godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=1
##
## Rules:
## - Runtime load() ONLY (no top-level preload() on scripts that reference autoloads).
## - Emits PASS: [<ID>] ... or FAIL: [<ID>] ... for every check.
## - Ends with SUMMARY: fails=<N> passed=<M> total=<T> and quit(0 if fails == 0 else 1).

func _load_patched(res_path: String) -> GDScript:
	# 4.4(b): lambda typed-array SCRIPT ERROR guard. Tier1 declares its
	# _is_real_glb_under lambda as func(root_n: Node, forbid_names: Array[String]),
	# but every call site passes a plain untyped Array literal, so the call
	# errors at runtime ("array of argument 2 does not have the same element
	# type as the expected typed array argument") and aborts _feat_07 before
	# T1-07-A..E report. Patch the param to untyped Array in memory (no
	# on-disk tier edit): plain literals then bind cleanly and typed callers
	# still work. Falls back to load() if the patched reload fails.
	if not FileAccess.file_exists(res_path):
		return load(res_path) as GDScript
	var f: FileAccess = FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		return load(res_path) as GDScript
	var src: String = f.get_as_text()
	src = src.replace("forbid_names: Array[String]", "forbid_names: Array")
	var scr := GDScript.new()
	scr.source_code = src
	var err: int = scr.reload()
	if err != OK:
		printerr("FAIL: [BOOT] patched reload failed for ", res_path, " err=", err)
		return load(res_path) as GDScript
	return scr


func _settle_harness() -> void:
	# 4.4(c): settle guard. Drain stuck headless Input presses left by the
	# previous tier/test (stuck secondary_action breaks crank; stuck
	# primary_action breaks smoke) and let freed mission nodes leave groups
	# before the next tier instantiates. Intra-tier timing is owned by the
	# tier files; this only hardens the cross-tier boundary.
	for act: String in ["primary_action", "secondary_action", "move_forward", "jump", "tool_1", "tool_2", "tool_3", "tool_4", "map_toggle", "ping_menu"]:
		if InputMap.has_action(act):
			Input.action_release(act)
	await process_frame
	await physics_frame
	await physics_frame
	await process_frame


func _initialize() -> void:
	await process_frame

	var tier_filter: String = "all"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--tier="):
			tier_filter = arg.substr(7).strip_edges().to_lower()

	var helpers_scr: GDScript = load("res://tests/e2e/e2e_helpers.gd") as GDScript
	if helpers_scr == null:
		printerr("FAIL: [BOOT] Could not load res://tests/e2e/e2e_helpers.gd")
		print("SUMMARY: fails=1 passed=0 total=1")
		quit(1)
		return

	var h: RefCounted = helpers_scr.new(self)

	if tier_filter == "all" or tier_filter == "1":
		await _settle_harness()
		var t1_scr: GDScript = _load_patched("res://tests/e2e/e2e_tier1_features.gd")
		if t1_scr != null:
			var t1: RefCounted = t1_scr.new(h)
			await t1.call("run")
		else:
			h.require(false, "T1-BOOT", "Failed to load e2e_tier1_features.gd")
		await _settle_harness()

	if tier_filter == "all" or tier_filter == "2":
		await _settle_harness()
		var t2_scr: GDScript = _load_patched("res://tests/e2e/e2e_tier2_boundaries.gd")
		if t2_scr != null:
			var t2: RefCounted = t2_scr.new(h)
			await t2.call("run")
		else:
			h.require(false, "T2-BOOT", "Failed to load e2e_tier2_boundaries.gd")
		await _settle_harness()

	if tier_filter == "all" or tier_filter == "3":
		await _settle_harness()
		var t3_scr: GDScript = _load_patched("res://tests/e2e/e2e_tier3_pairwise.gd")
		if t3_scr != null:
			var t3: RefCounted = t3_scr.new(h)
			await t3.call("run")
		else:
			h.require(false, "T3-BOOT", "Failed to load e2e_tier3_pairwise.gd")
		await _settle_harness()

	if tier_filter == "all" or tier_filter == "4":
		await _settle_harness()
		var t4_scr: GDScript = _load_patched("res://tests/e2e/e2e_tier4_scenarios.gd")
		if t4_scr != null:
			var t4: RefCounted = t4_scr.new(h)
			await t4.call("run")
		else:
			h.require(false, "T4-BOOT", "Failed to load e2e_tier4_scenarios.gd")
		await _settle_harness()

	var fails: int = int(h.get("fails"))
	var passed: int = int(h.get("passed"))
	var total: int = int(h.get("total"))
	print("SUMMARY: fails=%d passed=%d total=%d" % [fails, passed, total])
	quit(0 if fails == 0 else 1)
