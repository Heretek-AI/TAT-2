extends SceneTree
## Wave-1 Vulkan probe (build/qa/capture_w1_trim_neon.gd, gitignored).
## Compiles EVERY touched shader/material path on a real Vulkan Forward+
## renderer (headless dummy never compiles GLSL):
##  1. Startscreen main_menu (trim specular post-pass + tat_hdr_emissive).
##  2. All five new VfxManager spawners (GPUParticles3D + unshaded mats).
##  3. Window godray (teal-cyan retune).
## Pass gate: SHADER ERROR = 0 and SCRIPT ERROR = 0 in the log.

const OUT_DIR: String = "/home/john/Projects/TAT-2/build/qa"


func _init() -> void:
	call_deferred("_run")


func _wait_frames(n: int) -> void:
	for _i: int in range(n):
		await process_frame


func _save_shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null and not img.is_empty():
		var err: int = img.save_png(OUT_DIR + "/" + fname)
		print("QA CAPTURE: ", fname, " size=", img.get_width(), "x", img.get_height(), " err=", err)
	else:
		printerr("QA CAPTURE FAILED (empty image): ", fname)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _wait_frames(3)
	# Another wave may leave tat2/debug_autostart_contract != 0 in the
	# working-tree project.godot; neutralize it in-process so the probe's
	# main_menu does not scene-change mid-probe. File untouched.
	ProjectSettings.set_setting("tat2/debug_autostart_contract", 0)

	# 1. Startscreen: exercises _apply_startscreen_trim_specular + neon shader.
	var mm: Control = (load("res://src/ui/main_menu.gd") as GDScript).new() as Control
	mm.size = Vector2(1280, 720)
	root.add_child(mm)
	await _wait_frames(20)
	await _save_shot("w1_startscreen_trim_neon.png")
	var mm_env: Environment = null
	var stack: Array[Node] = [mm]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is WorldEnvironment:
			mm_env = (n as WorldEnvironment).environment
		for c: Node in n.get_children():
			stack.push_back(c)
	print("W1 PROBE: startscreen env=", mm_env != null, " ssr=", mm_env.ssr_enabled if mm_env != null else false)
	mm.queue_free()
	await _wait_frames(4)

	# 2. VFX arena: compile every new spawner on Vulkan.
	var arena: Node3D = Node3D.new()
	arena.name = "W1VfxArena"
	root.add_child(arena)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.light_energy = 0.4
	arena.add_child(sun)
	var cam: Camera3D = Camera3D.new()
	cam.position = Vector3(0, 3, 9)
	cam.look_at(Vector3(0, 1, 0), Vector3.UP)
	cam.current = true
	arena.add_child(cam)
	var vfx: GDScript = load("res://src/core/vfx_manager.gd") as GDScript
	vfx.call("spawn_smoke_plume", arena, Vector3(-4, 0.5, 0), Vector3(2.5, 2.0, 2.5), 25.0)
	vfx.call("spawn_foyer_security_beam", arena, Vector3(-1, 1.8, -2), Vector3(3, 1.8, -2), 0.7, 0.0)
	vfx.call("spawn_arcane_ward", arena, Vector3(4, 0, 0), 0.0, 3.2, 2.6, 0.0)
	vfx.call("spawn_vine_lock", arena, Vector3(0, 0, -3), 0.0, 2.0, 2.4, 0.0)
	vfx.call("spawn_crimson_alarm", arena, Vector3(2, 3.4, 1), Vector3(2, 0, 1), 0.0)
	vfx.call("spawn_window_godray", arena, Vector3(-2, 3, -1), Vector3(-2, 0, 1))
	await _wait_frames(25)
	var names: Array[String] = []
	for c: Node in arena.find_children("*", "Node3D", true, false):
		names.append(c.name)
	print("W1 PROBE: vfx nodes=", names.size, " smoke=", names.has("SmokePlume"), " beam=", names.has("FoyerSecurityBeam"), " ward=", names.has("ArcaneWard"), " vine=", names.has("VineLock"), " alarm=", names.has("CrimsonAlarm"), " godray=", names.has("WindowGodray"))
	await _save_shot("w1_vfx_arena.png")
	arena.queue_free()
	await _wait_frames(4)

	print("W1 PROBE DONE")
	quit(0)
