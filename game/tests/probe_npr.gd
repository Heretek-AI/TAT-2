extends SceneTree
## C1 OSE.NPR/SNN probe: camera quad, authored defaults, toggles.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var cam := Camera3D.new()
	cam.fov = 75.0
	root.add_child(cam)
	cam.current = true
	var renderer_script: GDScript = load("res://src/core/ose_renderer.gd") as GDScript
	var renderer: Node = renderer_script.call("attach", cam) as Node
	await process_frame
	var mat: ShaderMaterial = renderer.call("get_post_material") as ShaderMaterial
	var quad: MeshInstance3D = renderer.get_node_or_null("PostQuad") as MeshInstance3D
	var base_ok: bool = renderer != null and mat != null and mat.shader != null \
		and mat.shader.resource_path.ends_with("tat_npr.gdshader") \
		and quad != null and not quad.visible
	var npr_off: bool = not bool(renderer.call("is_npr_active"))
	renderer.call("set_npr", true)
	var npr_on: bool = bool(renderer.call("is_npr_active")) and quad.visible \
		and bool(mat.get_shader_parameter("npr_enabled"))
	renderer.call("set_snn", true, 0.65)
	var snn_ok: bool = bool(renderer.call("is_snn_active")) and absf(float(mat.get_shader_parameter("snn_effect")) - 0.65) < 0.001
	renderer.call("set_npr", false)
	renderer.call("set_snn", false)
	var off_ok: bool = not quad.visible and not bool(renderer.call("is_npr_active")) and not bool(renderer.call("is_snn_active"))
	if not base_ok or not npr_off or not npr_on or not snn_ok or not off_ok:
		printerr("NPR_PROBE FAIL base=", base_ok, " npr_off=", npr_off, " npr_on=", npr_on, " snn=", snn_ok, " off=", off_ok)
		quit(1)
		return
	print("NPR_PROBE PASS camera_quad=true authored_default_off=true npr_toggle=true snn_toggle=true")
	cam.queue_free()
	quit(0)
