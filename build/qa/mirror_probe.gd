extends SceneTree
## P4.2 synthetic mirror probe (negative control first).
##
## What it proves
## --------------
## A UE reflected placement (determinant < 0) is authored art. Godot flips the
## cull face for a negative-determinant MeshInstance3D, so a standalone mirror
## renders correctly. A MultiMesh has no per-instance cull state (and no surface
## override in 4.7.2), so its mirrored instances can render inside-out. The port
## fixes that with a baked local-X mesh variant (winding + normal/tangent
## handedness fixed) and a CULL_FRONT clone fast path for single-surface
## BaseMaterial3D meshes.
##
## This probe renders the two engine cases and the port's two fixes against a
## black background with a red unshaded triangle:
##   control_back   positive MeshInstance3D, CULL_BACK  -> red   (readback OK)
##   control_front  positive MeshInstance3D, CULL_FRONT -> black (culling OK)
##   single_native  negative MeshInstance3D             -> Godot compensation
##   mm_native_*    MultiMesh identity + negative       -> per-instance behaviour
##   mm_baked_*     MultiMesh with the baked variant    -> port fix
##   mm_cullfront_* MultiMesh + CULL_FRONT clone        -> port fast path
##   single_baked   standalone with the baked variant   -> port opt-in
##
## Modes
## -----
##   --selftest  headless scene/data checks only; no render (default wrapper)
##   --run       real Vulkan readback (the integrator's run; one Godot at a
##               time, under Xvfb). The wrapper owns the flock/display.
##
## The probe does not change game/ state and writes only build/qa/mirror_probe/.

const VIEW_W: int = 960
const VIEW_H: int = 540
const FLIP_X := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
const POSITIONS: Array[float] = [-6.0, -4.5, -3.0, -1.5, 0.0, 1.5, 3.0, 4.5, 6.0]

var _fails: int = 0
var _checks: int = 0
var _ll: Node = null
var _scene: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, name: String, detail: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		printerr("MIRROR_PROBE FAIL: ", name, " ", detail)


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var selftest: bool = args.has("--selftest")
	var tag: String = "probe"
	for a: String in args:
		if a.begins_with("--tag="):
			tag = a.substr(6)
	_build_scene()
	if selftest:
		_selftest()
		print("MIRROR_PROBE_SELFTEST %s checks=%d fails=%d" % [
			"PASS" if _fails == 0 else "FAIL", _checks, _fails])
		quit(1 if _fails > 0 else 0)
		return
	await _render_and_read(tag)


## Explicit +Z-facing triangle (winding is known, unlike an imported PrimitiveMesh).
func _tri_mesh(mat: Material) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.6, -0.6, 0.0), Vector3(0.6, -0.6, 0.0), Vector3(0.0, 0.6, 0.0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 1.0)])
	arrays[Mesh.ARRAY_TANGENT] = PackedFloat32Array([
		1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(0.5, 0.0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.surface_set_material(0, mat)
	return m


func _build_scene() -> void:
	root.size = Vector2i(VIEW_W, VIEW_H)
	var ll_script: GDScript = load("res://src/core/level_loader.gd") as GDScript
	_ll = ll_script.new() as Node
	root.add_child(_ll)
	var world := Node3D.new()
	world.name = "MirrorProbeWorld"
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.0, 0.0, 0.0)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 10.0
	# Default camera basis looks along -Z, so z=+6 faces the origin.
	cam.position = Vector3(0.0, 0.0, 6.0)
	cam.current = true
	world.add_child(cam)

	var mat_back := StandardMaterial3D.new()
	mat_back.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_back.albedo_color = Color(1.0, 0.0, 0.0)
	mat_back.cull_mode = BaseMaterial3D.CULL_BACK
	var mat_front: StandardMaterial3D = mat_back.duplicate() as StandardMaterial3D
	mat_front.cull_mode = BaseMaterial3D.CULL_FRONT
	var tri_back: ArrayMesh = _tri_mesh(mat_back)
	var tri_front: ArrayMesh = _tri_mesh(mat_front)

	# 1. Readback control: positive, CULL_BACK.
	var control_back := MeshInstance3D.new()
	control_back.name = "control_back"
	control_back.mesh = tri_back
	control_back.position = Vector3(POSITIONS[0], 0.0, 0.0)
	world.add_child(control_back)
	# 2. Negative control: positive, CULL_FRONT (must be background).
	var control_front := MeshInstance3D.new()
	control_front.name = "control_front"
	control_front.mesh = tri_front
	control_front.position = Vector3(POSITIONS[1], 0.0, 0.0)
	world.add_child(control_front)
	# 3. Standalone native negative scale (engine compensation).
	var single_native := MeshInstance3D.new()
	single_native.name = "single_native"
	single_native.mesh = tri_back
	single_native.transform = Transform3D(FLIP_X, Vector3(POSITIONS[2], 0.0, 0.0))
	world.add_child(single_native)
	# 4. MultiMesh: identity + native negative scale.
	var mm_native := MultiMesh.new()
	mm_native.transform_format = MultiMesh.TRANSFORM_3D
	mm_native.mesh = tri_back
	mm_native.instance_count = 2
	mm_native.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(POSITIONS[3], 0.0, 0.0)))
	mm_native.set_instance_transform(1, Transform3D(FLIP_X, Vector3(POSITIONS[4], 0.0, 0.0)))
	var mm_native_node := MultiMeshInstance3D.new()
	mm_native_node.name = "mm_native"
	mm_native_node.multimesh = mm_native
	world.add_child(mm_native_node)
	# 5. MultiMesh with the port's baked mirror variant: both instances use
	#    the baked mesh and a positive-determinant transform (B' = B * S).
	var variant: Dictionary = _ll.call("_get_mirror_variant", tri_back, "probe_baked", false) as Dictionary
	var baked: Mesh = variant.get("mesh", tri_back) as Mesh
	var mm_baked := MultiMesh.new()
	mm_baked.transform_format = MultiMesh.TRANSFORM_3D
	mm_baked.mesh = baked
	mm_baked.instance_count = 2
	mm_baked.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(POSITIONS[5], 0.0, 0.0)))
	mm_baked.set_instance_transform(1, Transform3D(Basis.IDENTITY, Vector3(POSITIONS[6], 0.0, 0.0)))
	var mm_baked_node := MultiMeshInstance3D.new()
	mm_baked_node.name = "mm_baked"
	mm_baked_node.multimesh = mm_baked
	world.add_child(mm_baked_node)
	# 6. MultiMesh + the CULL_FRONT clone fast path (mirrored instances only,
	#    as the port splits the positive instances into their own batch). Force
	#    the fast path on for this control even if the integrator exported
	#    TAT2_MIRROR_FAST=off for the port A/B.
	var prev_fast: String = OS.get_environment("TAT2_MIRROR_FAST")
	OS.set_environment("TAT2_MIRROR_FAST", "on")
	var fast: Dictionary = _ll.call("_get_mirror_variant", tri_back, "probe_fast", true) as Dictionary
	if prev_fast == "":
		OS.unset_environment("TAT2_MIRROR_FAST")
	else:
		OS.set_environment("TAT2_MIRROR_FAST", prev_fast)
	var fast_mat: Material = fast.get("material") as Material
	var mm_fast := MultiMesh.new()
	mm_fast.transform_format = MultiMesh.TRANSFORM_3D
	mm_fast.mesh = tri_back
	mm_fast.instance_count = 2
	mm_fast.set_instance_transform(0, Transform3D(FLIP_X, Vector3(POSITIONS[7], 0.0, 0.0)))
	mm_fast.set_instance_transform(1, Transform3D(FLIP_X, Vector3(POSITIONS[8], 0.0, 0.0)))
	var mm_fast_node := MultiMeshInstance3D.new()
	mm_fast_node.name = "mm_cull_front"
	mm_fast_node.multimesh = mm_fast
	mm_fast_node.material_override = fast_mat
	world.add_child(mm_fast_node)
	# 7. Standalone opt-in bake (TAT2_MIRROR_SINGLE=baked path).
	var single_baked := MeshInstance3D.new()
	single_baked.name = "single_baked"
	single_baked.mesh = baked
	single_baked.position = Vector3(POSITIONS[5] + 6.0, -1.4, 0.0)
	world.add_child(single_baked)

	_scene = {
		"camera": cam,
		"control_back": control_back,
		"control_front": control_front,
		"single_native": single_native,
		"mm_native": mm_native_node,
		"mm_baked": mm_baked_node,
		"mm_cull_front": mm_fast_node,
		"single_baked": single_baked,
		"variant": variant,
		"fast": fast,
		"mat_back": mat_back,
	}


func _selftest() -> void:
	_check(_scene.has("camera") and (_scene["camera"] as Camera3D).current,
		"orthographic camera is current", "scene built")
	_check((_scene["mm_native"] as MultiMeshInstance3D).multimesh.instance_count == 2,
		"native MultiMesh has 2 instances", "count=%d" % (_scene["mm_native"] as MultiMeshInstance3D).multimesh.instance_count)
	_check((_scene["mm_baked"] as MultiMeshInstance3D).multimesh.instance_count == 2,
		"baked MultiMesh has 2 instances", "count=%d" % (_scene["mm_baked"] as MultiMeshInstance3D).multimesh.instance_count)
	var variant: Dictionary = _scene["variant"] as Dictionary
	var baked: Mesh = variant.get("mesh", null) as Mesh
	_check(str(variant.get("mode", "")) == "baked" and baked != null and bool(baked.get_meta("mirror_baked", false)),
		"baked variant came from the loader helper",
		"mode=%s" % str(variant.get("mode", "")))
	if baked != null:
		var a: Array = baked.surface_get_arrays(0)
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] as PackedInt32Array
		_check(idx.size() >= 3 and idx[0] == 0 and idx[1] == 2 and idx[2] == 1,
			"baked triangle winding is [0,2,1]", "idx=%s" % str(idx))
	var fast: Dictionary = _scene["fast"] as Dictionary
	var fast_mat: BaseMaterial3D = fast.get("material") as BaseMaterial3D
	_check(str(fast.get("mode", "")) == "cull_front" and fast_mat != null
		and fast_mat.cull_mode == BaseMaterial3D.CULL_FRONT,
		"cull-front clone is available", "mode=%s" % str(fast.get("mode", "")))
	_check((_scene["mat_back"] as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_BACK,
		"source control material is still CULL_BACK", "shared material untouched")
	_check((_scene["control_front"] as MeshInstance3D).mesh.surface_get_material(0) is BaseMaterial3D
		and ((_scene["control_front"] as MeshInstance3D).mesh.surface_get_material(0) as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_FRONT,
		"negative control is CULL_FRONT", "control_front")
	print("MIRROR_PROBE_GPU_COMMAND build/qa/mirror_probe.sh --run --tag=<tag>")


func _sample(img: Image, cam: Camera3D, world_pos: Vector3) -> Color:
	var screen: Vector2 = cam.unproject_position(world_pos)
	var x: int = clampi(roundi(screen.x), 0, img.get_width() - 1)
	var y: int = clampi(roundi(screen.y), 0, img.get_height() - 1)
	return img.get_pixel(x, y)


func _classify(c: Color) -> String:
	if c.r > 0.25 and c.g < 0.12 and c.b < 0.12:
		return "red"
	if c.r < 0.05 and c.g < 0.05 and c.b < 0.05:
		return "black"
	return "other(%.3f,%.3f,%.3f)" % [c.r, c.g, c.b]


func _render_and_read(tag: String) -> void:
	var cam: Camera3D = _scene["camera"] as Camera3D
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null:
		printerr("MIRROR_PROBE FAIL: no viewport image (is this a real renderer?)")
		quit(1)
		return
	var out_dir: String = OS.get_environment("MIRROR_PROBE_OUT")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://").path_join("../build/qa/mirror_probe")
	out_dir = out_dir.simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var png_path: String = out_dir.path_join("%s.png" % tag)
	img.save_png(png_path)
	print("MIRROR_PROBE_IMAGE path=%s size=%dx%d" % [png_path, img.get_width(), img.get_height()])
	var names: Array[String] = [
		"control_back", "control_front", "single_native",
		"mm_native_identity", "mm_native_mirror",
		"mm_baked_identity", "mm_baked_mirror",
		"mm_cullfront_mirror_a", "mm_cullfront_mirror_b",
	]
	var nodes: Array[Node3D] = [
		_scene["control_back"] as Node3D, _scene["control_front"] as Node3D,
		_scene["single_native"] as Node3D, _scene["mm_native"] as Node3D,
		_scene["mm_native"] as Node3D, _scene["mm_baked"] as Node3D,
		_scene["mm_baked"] as Node3D, _scene["mm_cull_front"] as Node3D,
		_scene["mm_cull_front"] as Node3D,
	]
	var x_offsets: Array = POSITIONS.duplicate()
	var colors: Dictionary = {}
	for i: int in range(names.size()):
		var p := Vector3(x_offsets[i], 0.0, 0.0)
		var c: Color = _sample(img, cam, p)
		colors[names[i]] = _classify(c)
		print("MIRROR_PROBE %s=%s rgb=(%.3f,%.3f,%.3f)" % [
			names[i], colors[names[i]], c.r, c.g, c.b])
	var single_baked_c: Color = _sample(img, cam, (_scene["single_baked"] as Node3D).position)
	print("MIRROR_PROBE single_baked=%s rgb=(%.3f,%.3f,%.3f)" % [
		_classify(single_baked_c), single_baked_c.r, single_baked_c.g, single_baked_c.b])
	# `nodes` is kept for the probe's provenance; sampling is by intended x so
	# a layout regression is visible in the printed colours.
	print("MIRROR_PROBE nodes=%d" % nodes.size())
	var controls_ok: bool = str(colors["control_back"]) == "red" and str(colors["control_front"]) == "black"
	print("MIRROR_PROBE RESULT control_ok=%s native_mm=%s native_single=%s baked_mm=%s cull_front_mm=%s single_baked=%s" % [
		str(controls_ok),
		"compensated" if str(colors["mm_native_mirror"]) == "red" else "not_compensated",
		"compensated" if str(colors["single_native"]) == "red" else "not_compensated",
		"ok" if str(colors["mm_baked_mirror"]) == "red" else "bad",
		"ok" if str(colors["mm_cullfront_mirror_a"]) == "red" and str(colors["mm_cullfront_mirror_b"]) == "red" else "bad",
		"ok" if _classify(single_baked_c) == "red" else "bad",
	])
	quit(0 if controls_ok else 1)
