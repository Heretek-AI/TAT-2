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
		var t1_scr: GDScript = load("res://tests/e2e/e2e_tier1_features.gd") as GDScript
		if t1_scr != null:
			var t1: RefCounted = t1_scr.new(h)
			await t1.call("run")
		else:
			h.require(false, "T1-BOOT", "Failed to load e2e_tier1_features.gd")

	if tier_filter == "all" or tier_filter == "2":
		var t2_scr: GDScript = load("res://tests/e2e/e2e_tier2_boundaries.gd") as GDScript
		if t2_scr != null:
			var t2: RefCounted = t2_scr.new(h)
			await t2.call("run")
		else:
			h.require(false, "T2-BOOT", "Failed to load e2e_tier2_boundaries.gd")

	if tier_filter == "all" or tier_filter == "3":
		var t3_scr: GDScript = load("res://tests/e2e/e2e_tier3_pairwise.gd") as GDScript
		if t3_scr != null:
			var t3: RefCounted = t3_scr.new(h)
			await t3.call("run")
		else:
			h.require(false, "T3-BOOT", "Failed to load e2e_tier3_pairwise.gd")

	if tier_filter == "all" or tier_filter == "4":
		var t4_scr: GDScript = load("res://tests/e2e/e2e_tier4_scenarios.gd") as GDScript
		if t4_scr != null:
			var t4: RefCounted = t4_scr.new(h)
			await t4.call("run")
		else:
			h.require(false, "T4-BOOT", "Failed to load e2e_tier4_scenarios.gd")

	var fails: int = int(h.get("fails"))
	var passed: int = int(h.get("passed"))
	var total: int = int(h.get("total"))
	print("SUMMARY: fails=%d passed=%d total=%d" % [fails, passed, total])
	quit(0 if fails == 0 else 1)
