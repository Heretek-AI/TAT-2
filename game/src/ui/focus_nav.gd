class_name FocusNav
extends RefCounted
## Gamepad focus navigation for every menu (RE-L-13, W9-P3-C3).
##
## The shipped frontend is CommonUI: `BPUI_MainMenu` implements
## `BP_GetDesiredFocusTarget` and `BPUI_GamepadButton` renders the active
## device's glyph (`extracted/json/UI/Frontend/BPUI_MainMenu.json`,
## `Buttons/BPUI_GamepadButton.json`). The port had zero `grab_focus` /
## `focus_neighbor` calls, so a controller-only setup could not leave the first
## control even though Godot's built-in `ui_up/ui_down/ui_left/ui_right` are
## bound to the D-pad and left stick.
##
## Two pieces are needed and both live here:
##   1. `install(root)` links every focusable, visible, enabled Control in tree
##      order into a wrap-around ring on all four axes. A ring cannot dead-end;
##      `tests/test_focus_walk.gd` asserts that property per menu.
##   2. `install_and_focus(root)` also grabs the first control, and
##      `remember()`/`restore()` put the focus back on the opener when a modal
##      closes so focus is never trapped behind a hidden panel.
##
## Port decision (labelled): the authored focus graph is per-widget
## (`BP_GetDesiredFocusTarget` on the menu and tabs) and is not extractable as a
## neighbour table; tree-order ring linking is the port's reconstruction, not
## authored data. The authored *behaviour* - pad-only navigation with a visible
## focus - is what is reproduced.

## Focus is drawn by the theme ("focus" stylebox). This constant is only the
## shared name so screens do not each invent one.
const FOCUS_STYLEBOX: String = "focus"

static var _remembered: Control = null


## Every focusable descendant of `root` in tree order, skipping hidden subtrees
## and disabled buttons.
static func focusable_controls(root: Node) -> Array[Control]:
	var out: Array[Control] = []
	if root == null:
		return out
	_collect(root, out)
	return out


static func _collect(node: Node, out: Array[Control]) -> void:
	if node is Control:
		var c: Control = node as Control
		# is_visible_in_tree() is false for a control behind a hidden modal, so
		# a closed panel can never take part in navigation.
		if not c.is_visible_in_tree():
			return
		if c.focus_mode != Control.FOCUS_NONE:
			var disabled: bool = c is BaseButton and (c as BaseButton).disabled
			if not disabled:
				out.append(c)
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	for child: Node in node.get_children():
		_collect(child, out)


## Link `controls` into a wrap-around ring. Both axes share the ring so every
## D-pad direction moves (a one-column menu should still respond to left/right
## rather than drop the press).
static func link_ring(controls: Array[Control]) -> void:
	var n: int = controls.size()
	if n == 0:
		return
	for i: int in range(n):
		var c: Control = controls[i]
		if c == null or not is_instance_valid(c):
			continue
		c.focus_mode = Control.FOCUS_ALL
		var prev: Control = controls[(i - 1 + n) % n]
		var next: Control = controls[(i + 1) % n]
		if prev == c or next == c:
			# A single control: never point a neighbour at itself (Godot would
			# report a focus dead end); leave the ring empty and rely on the
			# default traversal, which cannot move either.
			continue
		c.focus_neighbor_top = c.get_path_to(prev)
		c.focus_neighbor_bottom = c.get_path_to(next)
		c.focus_neighbor_left = c.get_path_to(prev)
		c.focus_neighbor_right = c.get_path_to(next)


## Link a grid: left/right inside a row (wrap), up/down inside a column (wrap).
## Rows may have different lengths; a short row wraps inside itself.
static func link_grid(rows: Array) -> void:
	var grid: Array[Control] = []
	for row_v: Variant in rows:
		if not (row_v is Array):
			continue
		var row: Array[Control] = []
		for c_v: Variant in (row_v as Array):
			if c_v is Control:
				var c: Control = c_v as Control
				if c != null and is_instance_valid(c):
					row.append(c)
		if row.is_empty():
			continue
		var n: int = row.size()
		for i: int in range(n):
			var c: Control = row[i]
			c.focus_mode = Control.FOCUS_ALL
			if n > 1:
				c.focus_neighbor_left = c.get_path_to(row[(i - 1 + n) % n])
				c.focus_neighbor_right = c.get_path_to(row[(i + 1) % n])
		grid.append_array(row)
	if grid.is_empty():
		return
	# Column links: index within each row, wrapping the column's own length.
	# For ragged rows the shortest legal link is to the nearest column index in
	# the next row, so a down press always lands on a real control.
	var rows_clean: Array = []
	for row_v: Variant in rows:
		if not (row_v is Array):
			continue
		var row: Array[Control] = []
		for c_v: Variant in (row_v as Array):
			if c_v is Control and is_instance_valid(c_v as Control):
				row.append(c_v as Control)
		if not row.is_empty():
			rows_clean.append(row)
	var row_count: int = rows_clean.size()
	if row_count < 2:
		return
	for r: int in range(row_count):
		var row: Array = rows_clean[r]
		var above: Array = rows_clean[(r - 1 + row_count) % row_count]
		var below: Array = rows_clean[(r + 1) % row_count]
		for i: int in range(row.size()):
			var c: Control = row[i]
			var a: Control = above[clampi(i, 0, above.size() - 1)]
			var b: Control = below[clampi(i, 0, below.size() - 1)]
			c.focus_neighbor_top = c.get_path_to(a)
			c.focus_neighbor_bottom = c.get_path_to(b)


## Ring-link every focusable control under `root` (adapts to rows added after a
## refresh because it is called after the rebuild).
static func install(root: Node) -> Array[Control]:
	var controls: Array[Control] = focusable_controls(root)
	link_ring(controls)
	return controls


## Link and grab the first control. Returns the linked list (empty when the
## root has no focusable control).
static func install_and_focus(root: Node) -> Array[Control]:
	var controls: Array[Control] = install(root)
	if not controls.is_empty():
		controls[0].grab_focus()
	return controls


static func focus_first(root: Node) -> bool:
	var controls: Array[Control] = focusable_controls(root)
	if controls.is_empty():
		return false
	controls[0].grab_focus()
	return controls[0].has_focus()


## Remember the current focus owner before opening a modal.
static func remember() -> void:
	_remembered = null
	var loop: MainLoop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return
	var tree: SceneTree = loop as SceneTree
	if tree == null or tree.root == null:
		return
	var owner_ctl: Control = tree.root.gui_get_focus_owner()
	if owner_ctl != null and is_instance_valid(owner_ctl):
		_remembered = owner_ctl


## Restore the remembered control if it is still inside the tree and visible.
## Returns true when focus was restored (false means the caller should focus its
## own first control).
static func restore() -> bool:
	if _remembered == null or not is_instance_valid(_remembered):
		return false
	if not _remembered.is_inside_tree() or not _remembered.is_visible_in_tree():
		return false
	_remembered.grab_focus()
	return _remembered.has_focus()


static func remembered() -> Control:
	return _remembered


## Release focus if the current owner is hidden or inside `closing`. Called by
## screens on close so focus is never trapped behind a hidden panel.
static func release_if_inside(node: Node) -> void:
	var loop: MainLoop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return
	var tree: SceneTree = loop as SceneTree
	if tree == null or tree.root == null:
		return
	var owner_ctl: Control = tree.root.gui_get_focus_owner()
	if owner_ctl == null or not is_instance_valid(owner_ctl):
		return
	if node != null and (node == owner_ctl or node.is_ancestor_of(owner_ctl)):
		owner_ctl.release_focus()


## Diagnostic used by tests and the debug overlay: the neighbour ring of every
## focusable control, as {name: {top, bottom, left, right}} paths.
static func ring_map(root: Node) -> Dictionary:
	var out: Dictionary = {}
	for c: Control in focusable_controls(root):
		out[c.name] = {
			"top": c.focus_neighbor_top,
			"bottom": c.focus_neighbor_bottom,
			"left": c.focus_neighbor_left,
			"right": c.focus_neighbor_right,
		}
	return out


## True when every focusable control has all four neighbours and each path
## resolves to another focusable control (the "no dead end" contract).
static func ring_is_complete(root: Node) -> bool:
	var controls: Array[Control] = focusable_controls(root)
	if controls.size() <= 1:
		return true
	var valid: Dictionary = {}
	for c: Control in controls:
		valid[c] = true
	for c: Control in controls:
		var paths: Array[NodePath] = [
			c.focus_neighbor_top, c.focus_neighbor_bottom,
			c.focus_neighbor_left, c.focus_neighbor_right,
		]
		for path: NodePath in paths:
			if path == NodePath():
				return false
			var target: Node = c.get_node_or_null(path)
			if target == null or not valid.has(target):
				return false
	return true
