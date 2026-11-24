extends SceneTree
## Headless full-Guildhall structural census probe.
##
## Loads Guildhall exactly like run_tests/contract 4, waits for the async level
## build to finish, then prints the PERF_CENSUS/PERF_MERGE counters the loader
## recorded. No rendering or GPU work: this is the same headless path CI uses.
##
##   tools/godot --headless --path game --script res://tests/probe_perf_census.gd
##   TAT2_MERGE_CELLS=plain tools/godot --headless --path game \
##       --script res://tests/probe_perf_census.gd
##   TAT2_PERIPH_RANGE=100 ... (same command)
##
## Exit code 0 once the level built and the census printed, 1 on timeout.

const TIMEOUT_MS: int = 900000


func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		printerr("PERF_PROBE FAIL: GameState autoload missing")
		quit(1)
		return
	gs.set("active_contract_order", 4)
	# Stale-default regression from run_tests: the contract's guildhall preset
	# must win over whatever map was active before.
	gs.set("active_map_id", "old_manor")
	var scene: Node = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var t0: int = Time.get_ticks_msec()
	var stats: Dictionary = {}
	while Time.get_ticks_msec() - t0 < TIMEOUT_MS:
		await process_frame
		var stats_v: Variant = scene.get("level_stats")
		if stats_v is Dictionary and not (stats_v as Dictionary).is_empty():
			stats = stats_v as Dictionary
			break
	if stats.is_empty():
		printerr("PERF_PROBE FAIL: level_stats never populated (elapsed_ms=", Time.get_ticks_msec() - t0, ")")
		quit(1)
		return
	var census: Dictionary = stats.get("perf_census", {}) as Dictionary
	print("PERF_PROBE elapsed_ms=", Time.get_ticks_msec() - t0)
	print("PERF_PROBE env merge_cells=", OS.get_environment("TAT2_MERGE_CELLS"), " periph_range=", OS.get_environment("TAT2_PERIPH_RANGE"), " light_budget=", OS.get_environment("TAT2_LIGHT_BUDGET"), " shadow_heroes=", OS.get_environment("TAT2_SHADOW_HEROES"))
	print("PERF_PROBE stats meshes=", int(stats.get("mesh_instances", 0)), " chunks=", int(stats.get("chunk_count", 0)), " lights=", int(stats.get("light_count", 0)), " occluders=", int(stats.get("occluder_count", 0)), " collision_bodies=", int(stats.get("collision_bodies", 0)), " collision_shapes=", int(stats.get("collision_shapes", 0)))
	print("PERF_PROBE merge mode=", str(stats.get("merge_mode", "")), " candidates=", int(stats.get("merge_candidates", 0)), " cells=", int(stats.get("merge_cells", 0)), " nodes=", int(stats.get("merge_nodes", 0)), " surfaces_before=", int(stats.get("merge_surfaces_before", 0)), " surfaces_after=", int(stats.get("merge_surfaces_after", 0)), " skipped_visuals=", int(stats.get("merge_skipped_visuals", 0)), " skipped=", str(stats.get("merge_skipped", {})))
	print("PERF_PROBE periph requested=", int(stats.get("periph_range", 0)), " applied=", int(stats.get("periph_range_applied", 0)), " kept_smaller=", int(stats.get("periph_range_kept_smaller", 0)), " skipped_mixed=", int(stats.get("periph_range_skipped_mixed", 0)), " skipped_other=", int(stats.get("periph_range_skipped_other", 0)))
	print("PERF_PROBE census=", census)
	scene.queue_free()
	await process_frame
	quit(0)
