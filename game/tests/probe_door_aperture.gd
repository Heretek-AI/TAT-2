extends SceneTree
## Regression probe: door frames must collide as their modelled aperture,
## not as a solid AABB (the old box path sealed opened doorways).

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ll: Node = (load("res://src/core/level_loader.gd") as GDScript).new()
	root.add_child(ll)
	await process_frame
	var paths: Array[String] = [
		"/Game/Art/Environment/Urban/Walls/SM_Urban_ext_Door_4x6",
		"/Game/Art/Environment/OldManor/SM_OldManor_Doorframe_Double_Int_6x8",
	]
	var ok: bool = true
	for p: String in paths:
		var info: Dictionary = ll.call("_get_mesh_and_shape", p) as Dictionary
		var shape: Shape3D = info.get("shape") as Shape3D
		var is_trimesh: bool = shape is ConcavePolygonShape3D
		print("DOOR_APERTURE ", p.get_file(), " mesh=", info.get("mesh") != null, " shape=", shape.get_class() if shape != null else "<null>", " trimesh=", is_trimesh)
		if not is_trimesh:
			ok = false
	if not ok:
		printerr("DOOR_APERTURE PROBE FAIL")
		quit(1)
		return
	print("DOOR_APERTURE PROBE PASS")
	ll.queue_free()
	await process_frame
	quit(0)
