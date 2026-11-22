extends SceneTree
## Deterministic SceneVariant selection probe (task B4).

func _init() -> void:
	call_deferred("_run")


func _ids(a: Array) -> Array:
	var out: Array = []
	for v: Variant in a:
		out.append(str((v as Dictionary).get("id", "")))
	return out


func _run() -> void:
	await process_frame
	var ll_scr: GDScript = load("res://src/core/level_loader.gd") as GDScript
	var a: Array = ll_scr.call("select_scene_variants", "guildhall", 4242, [] as Array[String]) as Array
	var b: Array = ll_scr.call("select_scene_variants", "guildhall", 4242, [] as Array[String]) as Array
	var c: Array = ll_scr.call("select_scene_variants", "", 9999, [] as Array[String]) as Array
	var all_a: Array = ll_scr.call("select_scene_variants", "", 4242, [] as Array[String]) as Array
	var all_b: Array = ll_scr.call("select_scene_variants", "", 4242, [] as Array[String]) as Array
	var all_guildhall: bool = true
	for v: Variant in a:
		if str((v as Dictionary).get("map_id", "")).find("Guildhall") < 0:
			all_guildhall = false
	var stable: bool = _ids(a) == _ids(b)
	var varies: bool = _ids(all_a) != _ids(c)
	var first_id: String = str((a[0] as Dictionary).get("id", "")) if not a.is_empty() else ""
	var one: Array = ll_scr.call("select_scene_variants", "guildhall", 4242, [first_id] as Array[String]) as Array
	var requested_ok: bool = one.size() == 1 and str((one[0] as Dictionary).get("id", "")) == first_id
	print("SV_PROBE selected=", a.size(), " all_guildhall=", all_guildhall,
		" stable=", stable, " varies_by_seed=", varies, " requested_ok=", requested_ok)
	var ok: bool = a.size() > 0 and all_guildhall and stable and varies and requested_ok
	print("SV_PROBE ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
