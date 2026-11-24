extends SceneTree
## Editor/`--script` entry point for the W0b fixed-pose perf matrix.
##
## The measurement itself lives in `perf_matrix_runner.gd` (a Node) so the
## release export can start it from `main_menu.gd` with `--perf-matrix`:
## release export templates do not honour `--script`. One implementation, two
## entry points; the wrapper `build/qa/run_perf_matrix.sh` chooses whichever
## binary is available.
##
##   tools/godot --path game --script res://tests/perf/perf_matrix.gd -- \
##     --perf-quality=high --perf-scale=1.0 --perf-scaling=bilinear \
##     --perf-lights=160 --perf-shadows=6 --perf-vsync=off --res=1920x1080
##
## Exit codes: 0 complete (PERF_DONE), 2 bad/unknown config, 3 mission_ready
## timeout or map mismatch, 4 deadline, 5 runtime/config mismatch, 6 truncated
## pose list, 7+ wrapper truncated markers.

const RUNNER_SCRIPT: String = "res://tests/perf/perf_matrix_runner.gd"


func _initialize() -> void:
	var runner_script: GDScript = load(RUNNER_SCRIPT) as GDScript
	if runner_script == null:
		printerr("PERF_ERROR cannot load ", RUNNER_SCRIPT)
		quit(2)
		return
	var runner: Node = runner_script.new()
	runner.name = "PerfMatrixRunner"
	root.add_child(runner)
