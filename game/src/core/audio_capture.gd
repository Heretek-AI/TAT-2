extends Node
## Master-bus audio capture tap (P0b Lane I) — the in-engine RMS/dBFS instrument
## the W9-P0 review named as missing evidence for the AU1–AU6 rows.
##
## What it does
## ------------
## Inserts one `AudioEffectCapture` at the end of the Master bus chain (after the
## authored mastering limiter/EQ, so it samples the signal the player hears),
## drains it every frame into 16-bit little-endian stereo PCM, and writes:
##   <name>.wav   RIFF/WAVE via AudioStreamWAV.save_to_wav()
##   <name>.pcm   raw interleaved s16le, same bytes as the WAV data chunk
##   <name>.json  capture metadata + per-mark RMS/peak dBFS windows
##
## Marks are the route alignment anchors. `mark_beat("S24")` accepts the official
## clip's 27 segment ids (S01..S27); `mark()` accepts arbitrary labels (a fixed
## pose, a UI screen) and never pretends to be a route beat. Each mark's window
## runs from that mark to the next one (the last mark runs to the end), measured
## incrementally during capture — there is no second pass over the PCM. The
## reference levels live in docs/REFERENCE_BASELINE.md §8.2 and are read by
## build/qa/p0b_audio_stats.py; this file records, it does not score.
##
## Headless safety
## ---------------
## There is no audio device under `--headless` (`AudioServer.get_driver_name()`
## is "Dummy"; the Dummy driver even reports frames, but they are silence). The
## tap therefore reports `enabled=false` with a reason and writes only the JSON
## sidecar — no WAV, no PCM, no crash. The same applies to a run with no Master
## bus or a display-less boot. Never treat a disabled tap as a measurement.
##
## Usage
## -----
##   var tap := load("res://src/core/audio_capture.gd").new()
##   root.add_child(tap)
##   tap.start()                       # false when disabled; logs why
##   tap.mark_beat("S24", "foyer approach")
##   var res := tap.stop_to("res://../build/qa/p0b/captures/run", "audio")
##
## The tap is capture-only: it never changes bus volumes, mute states, effects
## or gameplay. It removes only the effect instance it added.

const SCHEMA: String = "tat2.audio_capture/1"
const DEFAULT_BUFFER_S: float = 5.0
## Hard guard against an unattended route filling RAM: 600 s at 48 kHz stereo
## s16 is ~115 MB. Hitting the cap sets `truncated=true` and stops draining; it
## is reported, never silently dropped.
const MAX_SECONDS: float = 600.0
const ROUTE_BEAT_COUNT: int = 27
const CHANNELS: int = 2

## Capture state. `enabled` is the measurement contract: false means every
## numeric field is absent and `reason` says why.
var enabled: bool = false
var reason: String = ""
var driver: String = ""
var sample_rate: int = 0
var frames: int = 0
var dropped_frames: int = 0
var pushed_frames: int = 0
var truncated: bool = false
var marks: Array[Dictionary] = []

var _effect: AudioEffectCapture = null
var _bus: int = -1
var _pcm: PackedByteArray = PackedByteArray()
var _running: bool = false
var _started_msec: int = 0
var _started_utc: String = ""
var _buffer_s: float = DEFAULT_BUFFER_S
var _max_bytes: int = 0
var _total_sum_sq: float = 0.0
var _total_peak: float = 0.0
var _total_zero: int = 0
var _total_samples: int = 0
var _win_sum_sq: float = 0.0
var _win_peak: float = 0.0
var _win_zero: int = 0
var _win_samples: int = 0
var _win_frames: int = 0


## Starts the tap. Returns true only when a real capture is running. A false
## return is not an error: read `enabled`/`reason` and record them.
func start(buffer_s: float = DEFAULT_BUFFER_S) -> bool:
	if _running:
		return enabled
	_started_msec = Time.get_ticks_msec()
	_started_utc = Time.get_datetime_string_from_system(true)
	_buffer_s = maxf(buffer_s, 0.25)
	_pcm = PackedByteArray()
	frames = 0
	dropped_frames = 0
	pushed_frames = 0
	truncated = false
	marks.clear()
	_reset_windows()
	enabled = false
	driver = AudioServer.get_driver_name()
	sample_rate = AudioServer.get_mix_rate()
	_max_bytes = int(MAX_SECONDS * float(maxi(sample_rate, 1)) * float(CHANNELS) * 2.0)
	_bus = AudioServer.get_bus_index("Master")
	reason = ""
	if driver.to_lower() == "dummy":
		reason = "dummy_audio_driver"
	elif DisplayServer.get_name().to_lower() == "headless":
		reason = "display_headless"
	elif _bus < 0:
		reason = "no_master_bus"
	elif sample_rate <= 0:
		reason = "no_mix_rate"
	if reason != "":
		_running = true
		set_process(false)
		print("AUDIO_CAPTURE start enabled=false reason=%s driver=%s rate=%d" % [
			reason, driver, sample_rate,
		])
		return false
	_effect = AudioEffectCapture.new()
	_effect.name = "P0bCaptureTap"
	_effect.buffer_length = _buffer_s
	AudioServer.add_bus_effect(_bus, _effect)
	# Confirm the effect actually landed (a failed add would leave `enabled=true`
	# with no frames, which is exactly the silent lie to avoid).
	var landed: bool = false
	for i: int in range(AudioServer.get_bus_effect_count(_bus)):
		if AudioServer.get_bus_effect(_bus, i) == _effect:
			landed = true
			break
	if not landed:
		_effect = null
		reason = "effect_not_added"
		_running = true
		set_process(false)
		print("AUDIO_CAPTURE start enabled=false reason=%s driver=%s rate=%d" % [
			reason, driver, sample_rate,
		])
		return false
	enabled = true
	_running = true
	set_process(true)
	print("AUDIO_CAPTURE start enabled=true driver=%s rate=%d buffer_s=%.2f buffer_frames=%d bus=%d" % [
		driver, sample_rate, _buffer_s, _effect.get_buffer_length_frames(), _bus,
	])
	return true


func _process(_delta: float) -> void:
	if not _running or not enabled or _effect == null:
		return
	if _pcm.size() >= _max_bytes:
		if not truncated:
			truncated = true
			printerr("AUDIO_CAPTURE truncated at %.1f s (MAX_SECONDS=%.0f)" % [
				float(frames) / float(maxi(sample_rate, 1)), MAX_SECONDS,
			])
		return
	var available: int = _effect.get_frames_available()
	if available <= 0:
		return
	# Bound one drain so a long hitch cannot block a frame for seconds.
	var take: int = mini(available, 8192)
	var chunk: PackedVector2Array = _effect.get_buffer(take)
	var n: int = chunk.size()
	if n <= 0:
		return
	var base: int = _pcm.size()
	_pcm.resize(base + n * 4)
	for i: int in range(n):
		var s: Vector2 = chunk[i]
		var l: int = int(roundf(clampf(s.x, -1.0, 1.0) * 32767.0))
		var r: int = int(roundf(clampf(s.y, -1.0, 1.0) * 32767.0))
		var o: int = base + i * 4
		_pcm[o] = l & 0xFF
		_pcm[o + 1] = (l >> 8) & 0xFF
		_pcm[o + 2] = r & 0xFF
		_pcm[o + 3] = (r >> 8) & 0xFF
		var lf: float = float(l) / 32768.0
		var rf: float = float(r) / 32768.0
		var sq: float = lf * lf + rf * rf
		var pa: float = maxf(absf(lf), absf(rf))
		_total_sum_sq += sq
		_win_sum_sq += sq
		_total_samples += 2
		_win_samples += 2
		if pa > _total_peak:
			_total_peak = pa
		if pa > _win_peak:
			_win_peak = pa
		if l == 0:
			_total_zero += 1
			_win_zero += 1
		if r == 0:
			_total_zero += 1
			_win_zero += 1
	frames += n
	_win_frames += n
	pushed_frames = _effect.get_pushed_frames()
	dropped_frames = _effect.get_discarded_frames()


## Records a generic mark (fixed pose, screen, cue). Its measurement window runs
## from this mark to the next one (or to the end of the capture).
func mark(label: String, beat: String = "") -> void:
	_close_window()
	var t: float = 0.0
	if sample_rate > 0:
		t = float(frames) / float(sample_rate)
	marks.append({
		"label": label,
		"beat": beat,
		"frame": frames,
		"t_s": t,
		"msec": Time.get_ticks_msec() - _started_msec,
		"unix": Time.get_unix_time_from_system(),
		"window": {},
	})
	_win_sum_sq = 0.0
	_win_peak = 0.0
	_win_zero = 0
	_win_samples = 0
	_win_frames = 0


## Records a route beat. Accepts only the official clip's S01..S27 ids so a
## fixed-pose capture cannot accidentally claim a route alignment it lacks.
func mark_beat(beat: String, label: String = "") -> bool:
	var b: String = beat.strip_edges().to_upper()
	if not _valid_beat(b):
		push_warning("AudioCaptureTap.mark_beat: unknown beat %s (expected S01..S27)" % beat)
		return false
	mark(label if label != "" else b, b)
	return true


static func _valid_beat(beat: String) -> bool:
	if beat.length() != 3 or not beat.begins_with("S"):
		return false
	var n: String = beat.substr(1)
	if not n.is_valid_int():
		return false
	var v: int = int(n)
	return v >= 1 and v <= ROUTE_BEAT_COUNT


## Stops the tap, removes only its own Master effect, writes the artifacts and
## returns a manifest fragment. Safe to call on a disabled tap (sidecar only).
func stop_to(dir: String, basename: String) -> Dictionary:
	_running = false
	set_process(false)
	_remove_effect()
	if enabled:
		_close_window()
	var out: Dictionary = to_manifest()
	out["stopped_at_utc"] = Time.get_datetime_string_from_system(true)
	out["truncated"] = truncated
	out["files"] = []
	if not enabled:
		var sidecar0: String = _write_sidecar(dir, basename, out)
		if sidecar0 != "":
			out["sidecar"] = sidecar0
			(out["files"] as Array).append(sidecar0)
		print("AUDIO_CAPTURE stop enabled=false reason=%s frames=%d" % [reason, frames])
		return out
	if frames <= 0 or _pcm.is_empty():
		enabled = false
		reason = "no_frames"
		out = to_manifest()
		out["stopped_at_utc"] = Time.get_datetime_string_from_system(true)
		out["files"] = []
		var sidecar1: String = _write_sidecar(dir, basename, out)
		if sidecar1 != "":
			out["sidecar"] = sidecar1
			(out["files"] as Array).append(sidecar1)
		print("AUDIO_CAPTURE stop enabled=false reason=%s" % reason)
		return out
	if DirAccess.make_dir_recursive_absolute(dir) != OK and not DirAccess.dir_exists_absolute(dir):
		enabled = false
		reason = "output_dir_unwritable"
		out = to_manifest()
		return out
	var pcm_path: String = dir.path_join(basename + ".pcm")
	var f: FileAccess = FileAccess.open(pcm_path, FileAccess.WRITE)
	if f != null:
		f.store_buffer(_pcm)
		f.close()
		(out["files"] as Array).append(pcm_path)
	else:
		push_warning("AudioCaptureTap: cannot write %s" % pcm_path)
	var wav_path: String = dir.path_join(basename + ".wav")
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = true
	wav.data = _pcm
	var err: int = wav.save_to_wav(wav_path)
	if err == OK:
		(out["files"] as Array).append(wav_path)
	else:
		push_warning("AudioCaptureTap: save_to_wav(%s) err=%d" % [wav_path, err])
	out["wav"] = wav_path if err == OK else ""
	out["pcm"] = pcm_path if FileAccess.file_exists(pcm_path) else ""
	out["total"] = _total_stats()
	out["peak_dbfs"] = _dbfs(_total_peak)
	out["seconds"] = float(frames) / float(maxi(sample_rate, 1))
	var sidecar2: String = _write_sidecar(dir, basename, out)
	if sidecar2 != "":
		out["sidecar"] = sidecar2
		(out["files"] as Array).append(sidecar2)
	print("AUDIO_CAPTURE stop enabled=true frames=%d seconds=%.3f rate=%d rms=%.2f peak=%.2f dropped=%d files=%d" % [
		frames, float(out["seconds"]), sample_rate,
		float((out["total"] as Dictionary).get("rms_dbfs", -120.0)),
		float(out.get("peak_dbfs", -120.0)), dropped_frames,
		(out["files"] as Array).size(),
	])
	return out


func to_manifest() -> Dictionary:
	return {
		"schema": SCHEMA,
		"enabled": enabled,
		"reason": reason,
		"driver": driver,
		"sample_rate": sample_rate,
		"channels": CHANNELS,
		"buffer_s": _buffer_s,
		"frames": frames,
		"seconds": float(frames) / float(maxi(sample_rate, 1)) if enabled else 0.0,
		"started_at_utc": _started_utc,
		"pushed_frames": pushed_frames,
		"dropped_frames": dropped_frames,
		"truncated": truncated,
		"marks": marks.duplicate(true),
	}


func _reset_windows() -> void:
	_total_sum_sq = 0.0
	_total_peak = 0.0
	_total_zero = 0
	_total_samples = 0
	_win_sum_sq = 0.0
	_win_peak = 0.0
	_win_zero = 0
	_win_samples = 0
	_win_frames = 0


## Stores the stats of the previous mark's window into that mark's row. The
## window is the stretch that ended at this mark (or at stop).
func _close_window() -> void:
	if marks.is_empty():
		return
	var last: Dictionary = marks[marks.size() - 1]
	var samples: int = _win_samples
	var rms: float = sqrt(_win_sum_sq / float(maxi(samples, 1))) if samples > 0 else 0.0
	last["window"] = {
		"frames": _win_frames,
		"seconds": float(_win_frames) / float(maxi(sample_rate, 1)),
		"rms_dbfs": _dbfs(rms) if samples > 0 else -120.0,
		"peak_dbfs": _dbfs(_win_peak) if samples > 0 else -120.0,
		"zero_fraction": float(_win_zero) / float(maxi(samples, 1)) if samples > 0 else 0.0,
	}


func _total_stats() -> Dictionary:
	var samples: int = _total_samples
	var rms: float = sqrt(_total_sum_sq / float(maxi(samples, 1))) if samples > 0 else 0.0
	return {
		"frames": frames,
		"seconds": float(frames) / float(maxi(sample_rate, 1)),
		"rms_dbfs": _dbfs(rms) if samples > 0 else -120.0,
		"peak_dbfs": _dbfs(_total_peak) if samples > 0 else -120.0,
		"zero_fraction": float(_total_zero) / float(maxi(samples, 1)) if samples > 0 else 0.0,
	}


func _remove_effect() -> void:
	if _effect == null:
		return
	if _bus >= 0:
		for i: int in range(AudioServer.get_bus_effect_count(_bus)):
			if AudioServer.get_bus_effect(_bus, i) == _effect:
				AudioServer.remove_bus_effect(_bus, i)
				break
	_effect = null


func _write_sidecar(dir: String, basename: String, payload: Dictionary) -> String:
	if DirAccess.make_dir_recursive_absolute(dir) != OK and not DirAccess.dir_exists_absolute(dir):
		push_warning("AudioCaptureTap: cannot create %s" % dir)
		return ""
	var path: String = dir.path_join(basename + ".json")
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("AudioCaptureTap: cannot write %s" % path)
		return ""
	f.store_string(JSON.stringify(payload, "  ") + "\n")
	f.close()
	return path


static func _dbfs(linear: float) -> float:
	return 20.0 * log(maxf(linear, 1.0e-9)) / log(10.0)


func _exit_tree() -> void:
	_running = false
	set_process(false)
	_remove_effect()
