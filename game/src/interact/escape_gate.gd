extends Area3D
## Extraction gate: the magic door summoned when the objectives complete.
## W7E gates extraction on the endgame phase AND on this marker being
## activated: an authored BP_EscapePoint stands dormant during the main window,
## opens for the endgame window (BP_EscapePoint open lifetime 240 s) and can be
## used multiple times while it is open.
##
## R10 re-arm contract: `BP_EscapePoint._escapeOpenDuration` (240 s) is the
## portal's open cycle, not the endgame window. `expire()` closes one cycle and
## the summoner re-arms it while the endgame is still live, so a 1200 s endgame
## never runs out of exits after four minutes. `collapse()` is the terminal
## state (the endgame window closed / "MAGIC DOOR COLLAPSED") and no activation
## can revive a collapsed marker. Dormancy is unchanged: only `activate()`
## clears `activated`, and only the endgame phase may extract.

signal extracted()
signal gate_activated()
signal gate_expired()
signal gate_rearmed(rearm_count: int)
signal gate_collapsed()

const INTERACTABLES_PATH := "res://data/generated/gameplay/interactables.json"
const PORTAL_SHADER_PATH := "res://src/core/tat_escape_portal.gdshader"
## Fallbacks mirror BP_EscapePoint (_escapeOpenDuration 240,
## _canBeUsedMultipleTimes true); the JSON above is authoritative.
const FALLBACK_OPEN_DURATION_SEC := 240.0

## Visual portal slot (wall outline). Kept as a named child so QA/tests can
## identify the marker without a floating Label3D.
const PORTAL_NODE_NAME := "EscapePortalVisual"
const PORTAL_SIZE: Vector2 = Vector2(2.6, 3.0)

var portal_visual: MeshInstance3D = null

## Seconds the escape stays usable once opened (BP_EscapePoint).
var open_duration_sec: float = FALLBACK_OPEN_DURATION_SEC
## BP_EscapePoint._canBeUsedMultipleTimes: the gate keeps working after a use.
var can_be_used_multiple_times: bool = true
var use_count: int = 0

## W7E phase activation. `activated` is the one-way "summoned" latch; `active`
## is false again after `expired` (one 240 s open cycle closed) and is cleared
## for good by `collapsed` (the endgame window closed).
var activated: bool = false
var active: bool = false
var expired: bool = false
## Terminal state: the endgame window closed. `activate()` refuses forever.
var collapsed: bool = false
## QA/provenance: how many authored 240 s cycles ran in this endgame.
var rearm_count: int = 0
var open_elapsed: float = 0.0
## Index into the map's authored BP_EscapePoint array (QA provenance).
var marker_index: int = -1


static func escape_config() -> Dictionary:
	if FileAccess.file_exists(INTERACTABLES_PATH):
		var f: FileAccess = FileAccess.open(INTERACTABLES_PATH, FileAccess.READ)
		if f != null:
			var data: Variant = JSON.parse_string(f.get_as_text())
			if data is Dictionary and (data as Dictionary).has("escape"):
				var esc: Variant = (data as Dictionary)["escape"]
				if esc is Dictionary:
					return (esc as Dictionary).duplicate()
	return {}


func apply_escape_config(cfg: Dictionary) -> void:
	if cfg.is_empty():
		return
	open_duration_sec = float(cfg.get("open_duration_s", open_duration_sec))
	can_be_used_multiple_times = bool(cfg.get("can_be_used_multiple_times", can_be_used_multiple_times))


func _ready() -> void:
	add_to_group("escape_points")
	collision_mask = 2
	apply_escape_config(escape_config())
	body_entered.connect(_on_body_entered)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 3.0, 3.0)
	col.shape = box
	col.position = Vector3(0, 1.5, 0)
	add_child(col)

	# Wall-outline portal: a thin vertical ring on a QuadMesh in the gate's
	# local XY plane (green core + violet rim shader), so the marker reads as a
	# doorway on the wall instead of the flat green floor cylinder + floating
	# "ESCAPE GATE" label the first port shipped.
	var mi := MeshInstance3D.new()
	mi.name = PORTAL_NODE_NAME
	var quad := QuadMesh.new()
	quad.size = PORTAL_SIZE
	mi.mesh = quad
	var mat := ShaderMaterial.new()
	if ResourceLoader.exists(PORTAL_SHADER_PATH):
		mat.shader = ResourceLoader.load(PORTAL_SHADER_PATH) as Shader
	mi.material_override = mat
	mi.position = Vector3(0, 1.5, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = active
	add_child(mi)
	portal_visual = mi
	set_process(active)


## Summon this door for the endgame window. `duration_sec` <= 0 keeps the
## authored BP_EscapePoint lifetime (240 s). A marker whose 240 s cycle closed
## re-arms (the door re-forms while the endgame is still live); a collapsed
## marker (the endgame window closed) refuses forever.
func activate(duration_sec: float = -1.0) -> bool:
	if collapsed:
		return false
	if duration_sec > 0.0:
		open_duration_sec = duration_sec
	if expired:
		expired = false
		rearm_count += 1
		gate_rearmed.emit(rearm_count)
	if not activated:
		activated = true
		gate_activated.emit()
	active = true
	open_elapsed = 0.0
	if portal_visual != null:
		portal_visual.visible = true
	set_process(true)
	return true


## Close one authored 240 s open cycle. Not terminal: the endgame summoner
## re-arms it while the endgame window is live (see the R10 contract above).
func expire() -> void:
	if expired or collapsed:
		return
	active = false
	expired = true
	if portal_visual != null:
		portal_visual.visible = false
	set_process(false)
	gate_expired.emit()


## Terminal close: the endgame window closed and the magic door is gone for
## the rest of the run. Only this state can never be re-armed.
func collapse() -> void:
	if collapsed:
		return
	collapsed = true
	active = false
	expired = true
	activated = false
	if portal_visual != null:
		portal_visual.visible = false
	set_process(false)
	gate_collapsed.emit()


func is_available() -> bool:
	return activated and active and not expired and not collapsed


func _process(delta: float) -> void:
	if not active or expired:
		return
	open_elapsed += delta
	if open_duration_sec > 0.0 and open_elapsed >= open_duration_sec:
		expire()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if GameState.state != "playing":
		return
	# W7E: dormant during the main window; only a summoned, still-open door in
	# the endgame phase extracts. Objectives are complete by definition once
	# the endgame starts, but the check keeps the legacy safety contract.
	if not is_available():
		return
	if GameState.phase != GameState.PHASE_ENDGAME:
		return
	if GameState.are_all_objectives_complete():
		if can_be_used_multiple_times or use_count == 0:
			use_count += 1
			extracted.emit()
