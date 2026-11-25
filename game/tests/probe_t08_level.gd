extends SceneTree
## T08 spawn-filter probe: loads ONE generated sublevel through the real
## LevelLoader and prints the debug-primitive census.
##
## Proves the filter added for L2-03: `/Game/Test/Art/Primitives/SM_Shape_*`
## instances that still bind MI_Default_White and carry NO authored override are
## editor debris and are skipped (counted, never spawned), while the 163
## override-carrying emissive shapes (moon disc, MI_EmissiveShape light bulbs)
## keep spawning.
##
## Run:
##   tools/godot --headless --path game --script res://tests/probe_t08_level.gd -- \
##     --level=res://data/generated/levels/OldManor/OldManor_Geo.tatlevel.json
##   ... Guildhall/Guildhall_LightingNoGameplay.tatlevel.json  (11 overrides, 0 hidden)

const LOADER_PATH := "res://src/core/level_loader.gd"
const DEFAULT_LEVEL := "res://data/generated/levels/OldManor/OldManor_Geo.tatlevel.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var level: String = DEFAULT_LEVEL
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			level = arg.substr("--level=".length())
	var ll: Node = (load(LOADER_PATH) as GDScript).new()
	get_root().add_child(ll)
	var root: Node3D = Node3D.new()
	get_root().add_child(root)
	var result: Dictionary = await ll.call("load_sublevels_async", [level], root, null, 96, false)
	print("T08_LEVEL level=", level.get_file(),
		" debug_shape_hidden=", int(result.get("debug_shape_hidden", 0)),
		" ward_box_hidden=", int(result.get("ward_box_hidden", 0)),
		" mesh_instances=", int(result.get("mesh_instances", 0)),
		" flat_colour_materials=", int(result.get("flat_colour_material_count", 0)),
		" slot_name_fallbacks=", int(result.get("slot_name_fallback_count", 0)))
	root.queue_free()
	ll.queue_free()
	await process_frame
	quit(0)
