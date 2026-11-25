class_name AnimNotifyClock
extends RefCounted
## Polls an AnimationPlayer against the authored UE notify windows that the
## extractor recovered into `anims_meta.json` (RE-F-06/RE-F-12).
##
## UE fires FAnimNotifyEvents from the montage timeline. Godot cannot: the
## notifies are not in the GLB, and every animated state in the port is a
## hand-written AnimationPlayer state machine. The clock keeps the authored
## timing instead of a hand-coded constant: the owner arms it with the clip it
## just played, calls `poll(player.current_animation_position)` once per frame,
## and applies the gameplay effect when a window is returned. Nothing fires on
## arming, so an attack cannot damage on frame 0 (the RE-F-12 defect).
##
## Data source: GuardAnimationLibrary.load_meta()/get_notifies() (the single
## parsed copy of anims_meta.json). This helper only turns notify entries into
## [start, end] windows and tracks the crossing.
##
## Usage:
##   var clock := AnimNotifyClock.new()
##   clock.arm("AN_GuardEnforcer_Club_Attack_Light_A_Montage")
##   # every frame while that clip plays:
##   var window := clock.poll(player.current_animation_position)
##   if window != Vector2.ZERO and in_reach: apply_damage()

const HITBOX_CLASS := "AnimNotifyState_CombatHitbox"
## Authored foot-contact events: the only per-foot timing the extract carries.
const FOOTSTEP_CLASSES: Array[String] = [
	"AnimNotify_Footstep_Previewable_C", "AnimNotify_Footstep",
]

var clip: String = ""
## Windows this clock watches, sorted by start. Empty when the clip has none.
var windows: Array[Vector2] = []

var _next: int = 0
var _last_pos: float = -1.0


## Authored length in seconds for a clip basename from anims_meta.json, or
## -1.0 when the clip has no metadata entry.
static func authored_length(clip_name: String) -> float:
	var meta: Dictionary = GuardAnimationLibrary.get_clip_meta(clip_name)
	if meta.is_empty():
		return -1.0
	return float(meta.get("length", -1.0))


## Windows of `notify_class` for a clip, clipped to the authored length and
## sorted by start. A montage whose own notify list carries no window falls
## back to the same-named sequence (UE authors combat hitboxes on the
## AnimSequence; the `_Montage` wrapper repeats only the audio/VO events --
## e.g. AN_GuardEnforcer_Club_Attack_Light_A* carries 9 hitbox states while
## its _Montage sibling has none).
static func windows_for(clip_name: String, notify_class: String = HITBOX_CLASS) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if clip_name == "":
		return out
	var found := _windows_once(clip_name, notify_class)
	if found.is_empty() and clip_name.ends_with("_Montage"):
		found = _windows_once(clip_name.trim_suffix("_Montage"), notify_class)
	found.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	return found


static func _windows_once(clip_name: String, notify_class: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var length: float = authored_length(clip_name)
	for n: Variant in GuardAnimationLibrary.get_notifies(clip_name):
		if not (n is Dictionary):
			continue
		var notify: Dictionary = n as Dictionary
		if str(notify.get("class", "")) != notify_class:
			continue
		var start: float = float(notify.get("time", 0.0))
		var dur: float = maxf(0.0, float(notify.get("duration", 0.0)))
		var end: float = start + dur
		if length > 0.0:
			start = clampf(start, 0.0, length)
			end = clampf(end, start, length)
		out.append(Vector2(start, end))
	return out


## The window's contact instant: midpoint between the first hitbox start and
## the last hitbox end. -1.0 when the clip authors no hitbox.
static func hit_time(clip_name: String) -> float:
	var w := windows_for(clip_name, HITBOX_CLASS)
	if w.is_empty():
		return -1.0
	var last_end: float = 0.0
	for win: Vector2 in w:
		last_end = maxf(last_end, win.y)
	return 0.5 * (w[0].x + last_end)


## Full hitbox span [first start, last end], or Vector2.ZERO when unauthored.
static func hit_span(clip_name: String) -> Vector2:
	var w := windows_for(clip_name, HITBOX_CLASS)
	if w.is_empty():
		return Vector2.ZERO
	var last_end: float = 0.0
	for win: Vector2 in w:
		last_end = maxf(last_end, win.y)
	return Vector2(w[0].x, last_end)


## Arms the clock for `clip_name`. Returns the number of windows it will watch
## (0 means the caller must keep its non-animated fallback).
func arm(clip_name: String, notify_class: String = HITBOX_CLASS) -> int:
	clip = clip_name
	windows = windows_for(clip_name, notify_class)
	_next = 0
	_last_pos = -1.0
	return windows.size()


func is_armed() -> bool:
	return not windows.is_empty()


## Advances to `position` (seconds into the armed clip) and returns the window
## whose start was crossed since the previous poll, or Vector2.ZERO. Loops are
## handled: a position that moves backwards rewinds the cursor. Overlapping
## windows (the club authors 9 concurrent hitbox states) collapse into one
## return per poll, earliest start first.
func poll(position: float) -> Vector2:
	if windows.is_empty():
		return Vector2.ZERO
	if position < _last_pos:
		_next = 0
	_last_pos = position
	if _next >= windows.size():
		return Vector2.ZERO
	var hit := Vector2.ZERO
	while _next < windows.size() and position >= windows[_next].x:
		if hit == Vector2.ZERO:
			hit = windows[_next]
		_next += 1
	return hit


func reset() -> void:
	clip = ""
	windows = []
	_next = 0
	_last_pos = -1.0
