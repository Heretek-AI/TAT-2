extends SceneTree

func _initialize() -> void:
	var parent: Node3D = Node3D.new()
	get_root().add_child(parent)
	var ll_scr: GDScript = load("res://src/core/level_loader.gd") as GDScript
	var ll: Node = ll_scr.new()
	parent.add_child(ll)
	var paths: Array[String] = ["res://data/generated/levels/Guildhall/Guildhall_P.tatlevel.json"]
	var res: Dictionary = ll.call("load_sublevels", paths, parent, null, 32, false)
	var esc: Array = res.get("escape_points", [])
	print("ESCAPE_COUNT ", esc.size())
	for p: Variant in esc:
		print("ESCAPE ", p)
	quit(0)
