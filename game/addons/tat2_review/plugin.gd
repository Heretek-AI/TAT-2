@tool
extends EditorPlugin
## Editor entry point for the TAT-2 map review dock.
##
## Enable once per checkout in Project > Project Settings > Plugins
## ("TAT-2 Review"), or the checked-in `[editor_plugins]` entry in
## game/project.godot does it on open. Dock code lives in dock.gd; bake/open
## commands there call tools/bake_review_map.gd through OS.execute.

const DockScript: GDScript = preload("res://addons/tat2_review/dock.gd")

var _dock: Control


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
	_dock = DockScript.new() as Control
	_dock.plugin = self
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
