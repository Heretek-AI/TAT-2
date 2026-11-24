extends SceneTree
## Headless review-map baker.
##
##   tools/godot --headless --path game --script tools/bake_review_map.gd \
##       -- --map=guildhall --out=res://scenes/review/guildhall
##
## Builds one scene per Guildhall/OldManor/Den/MissionLobby sublevel through the
## real LevelLoader, tags it for the tat2_review editor dock, and writes
## world.scn + review.tscn + review_manifest.json under --out.
##
## Exit codes: 0 = every scene packed and saved, 1 = resolution/pack/save
## failure or a failed loader/plugin consistency check. The JSON manifest is
## written in both cases so the failure is inspectable.

const Baker: GDScript = preload("res://addons/tat2_review/review_baker.gd")


func _initialize() -> void:
	var args: Dictionary = _parse_args(OS.get_cmdline_user_args())
	call_deferred("_run", args)


func _run(args: Dictionary) -> void:
	var map_id: String = str(args.get("map", "guildhall"))
	var out_dir: String = str(args.get("out", "res://scenes/review/" + map_id))
	var baker: RefCounted = Baker.new()
	var report: Dictionary = await baker.call("bake", self, map_id, out_dir, {
		"seed": int(args.get("seed", 0)),
		"max_lights": int(args.get("max_lights", 160)),
	})
	var write_err: int = int(baker.call("write_manifest", report, out_dir))
	if write_err != OK:
		printerr("REVIEW_BAKE error=manifest_write err=", write_err, " out=", out_dir)
	var scenes: Array = report.get("scenes", [])
	var total_bytes: int = 0
	for s: Dictionary in scenes:
		total_bytes += int(s.get("bytes", 0))
	var issues: Dictionary = report.get("issues", {})
	var status: String = "ok" if bool(report.get("ok", false)) else "failed"
	print("REVIEW_BAKE summary map=", map_id,
		" status=", status,
		" sublevels=", (report.get("sublevels", []) as Array).size(),
		" scenes=", scenes.size(),
		" bytes=", total_bytes,
		" beams=", int(issues.get("beam_lines", 0)),
		" labels=", int(issues.get("world_label", 0)),
		" emissive=", int(issues.get("emissive_plate", 0)),
		" bake_ms=", int(report.get("bake_ms", 0)),
		" out=", out_dir)
	if status != "ok":
		for e: Variant in report.get("errors", []):
			printerr("REVIEW_BAKE error: ", str(e))
		quit(1)
		return
	quit(0)


func _parse_args(raw: PackedStringArray) -> Dictionary:
	var out: Dictionary = {
		"map": "guildhall",
		"out": "",
		"seed": 0,
		"max_lights": 160,
	}
	for arg: String in raw:
		if arg.begins_with("--map="):
			out["map"] = arg.substr("--map=".length())
		elif arg.begins_with("--out="):
			out["out"] = arg.substr("--out=".length())
		elif arg.begins_with("--seed="):
			out["seed"] = int(arg.substr("--seed=".length()))
		elif arg.begins_with("--max-lights="):
			out["max_lights"] = int(arg.substr("--max-lights=".length()))
		else:
			printerr("REVIEW_BAKE ignore unknown arg: ", arg)
	if str(out["out"]) == "":
		out["out"] = "res://scenes/review/" + str(out["map"])
	return out
