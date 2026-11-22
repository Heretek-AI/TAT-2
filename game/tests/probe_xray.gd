extends SceneTree
## C2 OSEXray probe: authored category colours, depth-disabled shader, toggle.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var host: Node3D = Node3D.new()
	root.add_child(host)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	host.add_child(mi)

	XrayOverlay.set_xray_highlight(host, true, "guard")
	var guard_mat: ShaderMaterial = mi.material_overlay as ShaderMaterial
	var guard_ok: bool = guard_mat != null and guard_mat.shader != null \
		and guard_mat.shader.resource_path.ends_with("tat_xray.gdshader") \
		and guard_mat.shader.code.contains("depth_test_disabled")
	var guard_col: Color = XrayOverlay.category_color("guard")
	var loot_col: Color = XrayOverlay.category_color("loot")
	var clue_col: Color = XrayOverlay.category_color("clue")
	var colors_ok: bool = guard_col != loot_col and loot_col != clue_col and guard_col != clue_col
	var cache_ok: bool = XrayOverlay.material_for("guard") == XrayOverlay.material_for("guard")

	XrayOverlay.set_xray_highlight(host, false, "guard")
	var off_ok: bool = mi.material_overlay == null

	XrayOverlay.set_xray_highlight(host, true, "loot")
	var loot_mat: ShaderMaterial = mi.material_overlay as ShaderMaterial
	var loot_ok: bool = loot_mat != null and loot_mat.get_shader_parameter("xray_color") is Color \
		and (loot_mat.get_shader_parameter("xray_color") as Color).is_equal_approx(loot_col)
	XrayOverlay.set_xray_highlight(host, false, "loot")

	if not guard_ok or not colors_ok or not cache_ok or not off_ok or not loot_ok:
		printerr("XRAY_PROBE FAIL guard=", guard_ok, " colors=", colors_ok, " cache=", cache_ok, " off=", off_ok, " loot=", loot_ok)
		quit(1)
		return
	print("XRAY_PROBE PASS guard=", guard_col, " loot=", loot_col, " clue=", clue_col, " depth_disabled=true")
	XrayOverlay.clear_static_caches()
	host.queue_free()
	quit(0)
