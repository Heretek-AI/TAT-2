extends CompositorEffect
## P4.1b AEM meter: GPU log-luminance reduction of the rendered frame.
##
## The compositor effect runs at POST_TRANSPARENT on the rendering thread. It
## dispatches `auto_exposure_meter.glsl` (one workgroup per 32x32 tile, 8x8
## threads) into a float storage buffer of per-tile log2(luminance*100)
## averages, then reads the buffer back ASYNCHRONOUSLY (never
## `buffer_get_data`). `read_ev100()` returns the most recent readback, or NAN
## until the first one arrives.
##
## The readback EV100 is the mean of the per-tile averages, not a
## pixel-weighted mean: an edge tile (partial 32x32 block) carries the same
## weight as a full tile. At 1920x1080 the partial row/column is <= 6 % of the
## frame and the bias is constant per resolution, so it is absorbed by the one
## `AEM_CALIBRATION` the integrator measures; it is recorded here so the
## convention is never mistaken for an exact area average.
##
## Headless/testability: `RenderingServer.get_rendering_device()` is null in
## headless mode, so `_render_callback` returns immediately and the pure CPU
## mirror `reduce_log_luminance()` is the part the synthetic harness asserts.
## The shader itself is only compiled by the GPU run the integrator performs
## (`TAT2_AEM=meter`); a headless run never claims the GPU path works.
##
## This file deliberately does not touch `Environment` or the model: the
## controller (`auto_exposure_controller.gd`) owns the policy, the meter owns
## the measurement.

const SHADER_PATH := "res://src/core/auto_exposure_meter.glsl"
const TILE := 32
const LOCAL_X := 8
const LOCAL_Y := 8
const EPS := 1e-6
const SHADER_CALIBRATION := 1.0

var ev100: float = NAN
var readbacks: int = 0
var last_error: String = ""

var _rd: RenderingDevice = null
var _shader: RID = RID()
var _pipeline: RID = RID()
var _sampler: RID = RID()
var _buffer: RID = RID()
var _uniform_set: RID = RID()
var _uniform_texture: RID = RID()
var _buffer_groups: int = 0
var _size: Vector2i = Vector2i.ZERO
var _pending: bool = false
var _failed: bool = false


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	enabled = true


func _render_callback(_effect_callback_type: int, render_data: RenderData) -> void:
	if not enabled or _failed or _pending:
		return
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null:
		return
	var buffers: RenderSceneBuffersRD = render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size: Vector2i = buffers.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return
	var color: RID = buffers.get_texture("render_buffers", "color")
	if not color.is_valid():
		return
	var groups_x: int = int(ceil(float(size.x) / float(TILE)))
	var groups_y: int = int(ceil(float(size.y) / float(TILE)))
	var groups: int = groups_x * groups_y

	_rd = rd
	if not _ensure_pipeline(rd):
		return
	_ensure_buffer(rd, groups)
	_ensure_uniform_set(rd, color, size, groups_x, groups_y)
	if not _pipeline.is_valid() or not _uniform_set.is_valid():
		return

	var params: PackedByteArray = PackedByteArray()
	params.resize(16)
	params.encode_s32(0, size.x)
	params.encode_s32(4, size.y)
	params.encode_u32(8, groups_x)
	params.encode_u32(12, groups_y)
	var list: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, _pipeline)
	rd.compute_list_bind_uniform_set(list, _uniform_set, 0)
	rd.compute_list_set_push_constant(list, params, params.size())
	rd.compute_list_dispatch(list, groups_x, groups_y, 1)
	rd.compute_list_end()
	_pending = true
	var err: Error = rd.buffer_get_data_async(_buffer, _on_readback)
	if err != OK:
		_pending = false
		last_error = "buffer_get_data_async error %d" % int(err)


func _on_readback(data: PackedByteArray) -> void:
	_pending = false
	readbacks += 1
	if data.is_empty() or data.size() % 4 != 0:
		last_error = "meter readback had %d bytes" % data.size()
		return
	var groups: PackedFloat32Array = data.to_float32_array()
	var acc: float = 0.0
	var n: int = 0
	for v: float in groups:
		if is_nan(v) or is_inf(v):
			continue
		acc += v
		n += 1
	if n <= 0:
		last_error = "meter readback had no finite groups"
		return
	ev100 = acc / float(n)


## Last measured scene EV100, or NAN before the first readback.
func read_ev100() -> float:
	return ev100


func has_measurement() -> bool:
	return not is_nan(ev100) and not is_inf(ev100)


## Diagnostic snapshot (no per-frame allocation in the render path).
func state() -> Dictionary:
	return {
		"ev100": ev100,
		"readbacks": readbacks,
		"groups": _buffer_groups,
		"pending": _pending,
		"error": last_error,
	}


# --------------------------------------------------------------------- CPU mirror
## Deterministic CPU copy of the shader reduction: per 32x32 tile, the average
## of log2(max(luminance, EPS) * 100); then the mean of the tile averages.
## `pixels` is one luminance per pixel, row-major. This is what the synthetic
## harness compares against known EV100 values; the GPU shader runs the same
## arithmetic. Returns {ev100, groups, samples, group_avg}.
static func reduce_log_luminance(pixels: PackedFloat32Array, width: int, height: int) -> Dictionary:
	if width <= 0 or height <= 0 or pixels.size() < width * height:
		return {"ev100": NAN, "groups": 0, "samples": 0, "group_avg": PackedFloat32Array()}
	var groups_x: int = int(ceil(float(width) / float(TILE)))
	var groups_y: int = int(ceil(float(height) / float(TILE)))
	var group_avg: PackedFloat32Array = PackedFloat32Array()
	group_avg.resize(groups_x * groups_y)
	var total_samples: int = 0
	for gy: int in range(groups_y):
		for gx: int in range(groups_x):
			var y0: int = gy * TILE
			var x0: int = gx * TILE
			var y1: int = mini(y0 + TILE, height)
			var x1: int = mini(x0 + TILE, width)
			var sum: float = 0.0
			var count: int = 0
			for y: int in range(y0, y1):
				var row: int = y * width
				for x: int in range(x0, x1):
					var lum: float = maxf(pixels[row + x], EPS)
					sum += log(lum * 100.0) / log(2.0)
					count += 1
			group_avg[gy * groups_x + gx] = sum / float(maxi(count, 1))
			total_samples += count
	var acc: float = 0.0
	for v: float in group_avg:
		acc += v
	return {
		"ev100": acc / float(maxi(group_avg.size(), 1)),
		"groups": group_avg.size(),
		"samples": total_samples,
		"group_avg": group_avg,
	}


## Luminance used by the shader and the mirror (Rec.709, matching the GLSL).
static func luminance(rgb: Color) -> float:
	return 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b


func _ensure_pipeline(rd: RenderingDevice) -> bool:
	if not _shader.is_valid():
		var file: RDShaderFile = load(SHADER_PATH) as RDShaderFile
		if file == null:
			_failed = true
			last_error = "cannot load " + SHADER_PATH
			return false
		var spirv: RDShaderSPIRV = file.get_spirv()
		if spirv == null or spirv.compile_error_compute != "":
			_failed = true
			last_error = "shader compile: " + (spirv.compile_error_compute if spirv != null else "no SPIR-V")
			return false
		_shader = rd.shader_create_from_spirv(spirv)
		if not _shader.is_valid():
			_failed = true
			last_error = "shader_create_from_spirv failed"
			return false
	if not _pipeline.is_valid():
		_pipeline = rd.compute_pipeline_create(_shader)
		if not _pipeline.is_valid():
			_failed = true
			last_error = "compute_pipeline_create failed"
			return false
	if not _sampler.is_valid():
		var st := RDSamplerState.new()
		st.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		st.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		st.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		st.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		st.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		_sampler = rd.sampler_create(st)
	return true


func _ensure_buffer(rd: RenderingDevice, groups: int) -> void:
	if _buffer.is_valid() and _buffer_groups == groups:
		return
	if _buffer.is_valid():
		rd.free_rid(_buffer)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(groups * 4)
	_buffer = rd.storage_buffer_create(bytes.size(), bytes)
	_buffer_groups = groups
	_uniform_set = RID()


func _ensure_uniform_set(rd: RenderingDevice, color: RID, _size_now: Vector2i, _gx: int, _gy: int) -> void:
	if _uniform_set.is_valid() and _uniform_texture == color:
		return
	if _uniform_set.is_valid():
		rd.free_rid(_uniform_set)
	var tex_uniform := RDUniform.new()
	tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	tex_uniform.binding = 0
	tex_uniform.add_id(_sampler)
	tex_uniform.add_id(color)
	var buf_uniform := RDUniform.new()
	buf_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	buf_uniform.binding = 1
	buf_uniform.add_id(_buffer)
	var uniforms: Array[RDUniform] = [tex_uniform, buf_uniform]
	_uniform_set = rd.uniform_set_create(uniforms, _shader, 0)
	_uniform_texture = color
	_size = _size_now


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	var rd: RenderingDevice = _rd
	if rd == null:
		return
	for rid: RID in [_uniform_set, _buffer, _pipeline, _sampler, _shader]:
		if rid.is_valid():
			rd.free_rid(rid)
