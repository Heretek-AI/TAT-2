extends SceneTree
## Absolute Niagara coverage probe (task C4 / sprint target 3,695 authored).
## Feeds every niagara record from all 107 level files through the real
## LevelLoader spawner, which skips NIAGARA_INACTIVE_ASSETS globally.
## Authored 3,695 -> active 3,308 -> 36 systems/36 MultiMesh nodes;
## 387 NS_Candelabras_Flame_Out extinguish puffs are skipped.

func _init() -> void:
	call_deferred("_run")


func _json_files(dir: String, out: Array[String]) -> void:
	var da: DirAccess = DirAccess.open(dir)
	if da == null:
		return
	da.list_dir_begin()
	var name: String = da.get_next()
	while name != "":
		var full: String = dir.path_join(name)
		if da.current_is_dir():
			_json_files(full, out)
		elif name.ends_with(".tatlevel.json"):
			out.append(full)
		name = da.get_next()
	da.list_dir_end()


func _run() -> void:
	await process_frame
	var files: Array[String] = []
	_json_files("res://data/generated/levels", files)
	var records: Array = []
	for f: String in files:
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(f))
		if doc is Dictionary:
			for n: Variant in ((doc as Dictionary).get("niagara", []) as Array):
				if n is Dictionary:
					records.append(n)
	var host := Node3D.new()
	host.name = "NiagaraProbeHost"
	root.add_child(host)
	var ll_scr: GDScript = load("res://src/core/level_loader.gd") as GDScript
	var ll: Node = ll_scr.new() as Node
	root.add_child(ll)
	var acc: Dictionary = {"niagara": records}
	var ctx: Dictionary = {"parent": host}
	ll.call("_spawn_level_niagara", acc, ctx)
	var spawned: int = int(ctx.get("niagara_spawned", -1))
	var systems: int = int(ctx.get("niagara_systems", -1))
	var skipped: int = int(ctx.get("niagara_inactive_skipped", -1))
	var nodes: int = host.get_child_count()
	print("NIAGARA_PROBE files=", files.size(), " authored=", records.size(),
		" active=", spawned, " skipped=", skipped, " systems=", systems, " nodes=", nodes)
	var ok: bool = records.size() == 3695 and spawned == 3308 and skipped == 387 \
		and systems == 36 and nodes == 36
	print("NIAGARA_PROBE ", "PASS" if ok else "FAIL")
	ll.queue_free()
	host.queue_free()
	await process_frame
	quit(0 if ok else 1)
