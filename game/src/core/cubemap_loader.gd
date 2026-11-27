extends RefCounted
## Stage-1 IBL: authored sky cubemap -> diffuse ambient colour + energy.
##
## The shipped SkyLight is a specified TextureCube, not the dark display-space
## sky shader:
##   Gloomy  -> /Game/MaterialLibrary/Utility/Cubemap_GroundFloor_01 (512^2,
##              PF_FloatRGBA, TC_HDR, SRGB=false -> linear)
##   DenseFog_OldManor -> /Engine/MapTemplates/daylight
##   Base    -> /Game/ThirdParty/FluidNinjaLive/UseCases/007_SmallWater/T_FakeSpecular1
## `tools/tat-extract` exports their six faces (`cubemaps` command) and
## `tools/parse_cubemap.py` writes `game/data/generated/ibl/cubemaps.json`.
##
## This loader computes a CPU cosine-weighted irradiance from the six face
## images and turns it into `Environment.ambient_light_color` / `_energy`:
##   E(n) = (1/pi) * sum_texels L(d) * max(0, n.d) * domega
## so a uniform cube returns exactly its radiance. One global stage-1 choice:
## the ambient normal is world UP (the authored SkyLight samples the upper
## hemisphere); there is NO authored rotation, and no per-room grade.
##
## `TAT2_IBL=off|ambient` (default off). `off` returns available=false and the
## caller keeps today's authored ambient colour/energy byte-for-byte. Energy is
## the raw irradiance luminance — deliberately NOT clamped to
## WeatherProfile.AMBIENT_ENERGY_MAX: a stage-1 measurement must not be hidden
## by a stage-2 tuning ceiling.
##
## Face order is explicit and never guessed: the extractor names the files
## px/nx/py/ny/pz/nz from UE's TextureCube slice order (ECubeFace:
## PosX, NegX, PosY, NegY, PosZ, NegZ). `cubemaps.json` carries the same order.

const MODE_OFF := "off"
const MODE_AMBIENT := "ambient"
const MODES: Array[String] = [MODE_OFF, MODE_AMBIENT]

const INDEX_PATH := "res://data/generated/ibl/cubemaps.json"
const FACE_NAMES: Array[String] = ["px", "nx", "py", "ny", "pz", "nz"]
## Face name -> unit axis (see header; Godot/UE/D3D standard layout).
const FACE_AXES: Array[Vector3] = [
	Vector3(1, 0, 0), Vector3(-1, 0, 0),
	Vector3(0, 1, 0), Vector3(0, -1, 0),
	Vector3(0, 0, 1), Vector3(0, 0, -1),
]
## Samples per cube-face edge for the CPU integral (6 * 24^2 = 3,456 samples).
## Coarse on purpose: diffuse irradiance is a low-frequency integral.
const SAMPLES_PER_EDGE := 24

static var _index: Dictionary = {}
static var _index_loaded: bool = false
static var _ambient_cache: Dictionary = {}
static var _mode_warned: bool = false
static var _load_warned: Dictionary = {}


## `TAT2_IBL=off|ambient`. Unset/unknown -> off (today's look).
static func mode() -> String:
	var raw: String = OS.get_environment("TAT2_IBL").strip_edges().to_lower()
	if raw == "":
		return MODE_OFF
	if MODES.has(raw):
		return raw
	if not _mode_warned:
		_mode_warned = true
		push_warning("TAT2_IBL='%s' is not one of %s; using off" % [raw, str(MODES)])
	return MODE_OFF


static func load_index() -> Dictionary:
	if _index_loaded:
		return _index
	_index_loaded = true
	var f: FileAccess = FileAccess.open(INDEX_PATH, FileAccess.READ)
	if f == null:
		return _index
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_index = parsed as Dictionary
	return _index


## Test hook: forget the cached index (TAT2_IBL probes flip env vars).
static func reset_cache() -> void:
	_index = {}
	_index_loaded = false
	_ambient_cache.clear()
	_load_warned.clear()


## Ambient for the preset's authored SkyLight cubemap. `available=false` means
## the caller must keep today's ambient values (off / no converted cubemap /
## unreadable faces). Never throws.
static func ambient_for_preset(preset: Dictionary) -> Dictionary:
	var sky_v: Variant = preset.get("sky", {})
	var sky: Dictionary = sky_v as Dictionary if sky_v is Dictionary else {}
	return ambient_for_ue_path(str(sky.get("cubemap", "")))


## Ambient for one authored UE cubemap path (e.g.
## `/Game/MaterialLibrary/Utility/Cubemap_GroundFloor_01`).
static func ambient_for_ue_path(ue_path: String) -> Dictionary:
	var m: String = mode()
	if m == MODE_OFF:
		return {"available": false, "mode": m, "reason": "TAT2_IBL=off"}
	if ue_path == "":
		return {"available": false, "mode": m, "reason": "preset authors no sky cubemap"}
	var idx: Dictionary = load_index()
	var by_path_v: Variant = idx.get("by_ue_path", {})
	var by_path: Dictionary = by_path_v as Dictionary if by_path_v is Dictionary else {}
	var id: String = str(by_path.get(ue_path, ""))
	if id == "":
		return {
			"available": false,
			"mode": m,
			"reason": "no converted cubemap for %s (run the cubemaps extract + parse_cubemap)" % ue_path,
		}
	var cubes_v: Variant = idx.get("cubemaps", {})
	var cubes: Dictionary = cubes_v as Dictionary if cubes_v is Dictionary else {}
	var rec_v: Variant = cubes.get(id, {})
	var rec: Dictionary = rec_v as Dictionary if rec_v is Dictionary else {}
	var cached_v: Variant = _ambient_cache.get(id, null)
	if cached_v is Dictionary:
		return cached_v as Dictionary
	var faces: Array = _load_faces(rec)
	if faces.size() != 6:
		return {"available": false, "mode": m, "reason": "cubemap %s: faces missing/unreadable" % id}
	var transfer: String = str(rec.get("transfer", "linear"))
	var amb: Dictionary = ambient(faces, transfer)
	amb["available"] = true
	amb["mode"] = m
	amb["cubemap"] = id
	amb["ue_path"] = ue_path
	_ambient_cache[id] = amb
	return amb


## CPU cosine irradiance for world UP, normalised to (hue, luminance) so the
## caller can set `ambient_light_color` + `ambient_light_energy` without
## squaring the magnitude. `transfer` is "linear" (TC_HDR / float formats) or
## "srgb" (8-bit DXT/BC faces); the PNG keeps the decoder's stored values.
static func ambient(faces: Array, transfer: String = "linear") -> Dictionary:
	var e: Color = irradiance(faces, Vector3.UP, transfer)
	var lum: float = 0.2126 * e.r + 0.7152 * e.g + 0.0722 * e.b
	if lum <= 0.0:
		return {"color": Color(0, 0, 0, 1), "energy": 0.0, "lum": 0.0, "irradiance": e}
	var hue: Color = Color(e.r / lum, e.g / lum, e.b / lum, 1.0)
	return {"color": hue, "energy": lum, "lum": lum, "irradiance": e}


## Cosine-weighted diffuse irradiance / pi for `normal` (a uniform cube returns
## exactly its radiance). Each sample cell's EXACT solid angle is used (the
## spherical-quad formula), so a constant-radiance face integrates exactly and
## the result does not depend on the sampling step for a uniform cube.
static func irradiance(faces: Array, normal: Vector3, transfer: String = "linear") -> Color:
	if faces.size() != 6:
		return Color(0, 0, 0, 1)
	var n: Vector3 = normal.normalized() if normal.length_squared() > 0.0 else Vector3.UP
	var acc: Color = Color(0, 0, 0, 1)
	var total_weight: float = 0.0
	for face: int in range(6):
		var img_v: Variant = faces[face]
		if not (img_v is Image):
			continue
		var img: Image = img_v as Image
		var w: int = img.get_width()
		var h: int = img.get_height()
		if w <= 0 or h <= 0:
			continue
		var step: int = maxi(1, int(ceil(float(maxi(w, h)) / float(SAMPLES_PER_EDGE))))
		var nu: int = int(ceil(float(w) / float(step)))
		var nv: int = int(ceil(float(h) / float(step)))
		if nu <= 0 or nv <= 0:
			continue
		for iy: int in range(nv):
			var v0: float = float(iy * step) / float(h)
			var v1: float = minf(1.0, float((iy + 1) * step) / float(h))
			for ix: int in range(nu):
				var u0: float = float(ix * step) / float(w)
				var u1: float = minf(1.0, float((ix + 1) * step) / float(w))
				var u: float = (u0 + u1) * 0.5
				var v: float = (v0 + v1) * 0.5
				var d: Vector3 = direction_for_face_uv(face, u, v)
				var cos_t: float = d.dot(n)
				if cos_t <= 0.0:
					continue
				var omega: float = cell_solid_angle(2.0 * u0 - 1.0, 2.0 * u1 - 1.0, 2.0 * v0 - 1.0, 2.0 * v1 - 1.0)
				var c: Color = _texel(img, u, v, transfer)
				acc.r += c.r * cos_t * omega
				acc.g += c.g * cos_t * omega
				acc.b += c.b * cos_t * omega
				total_weight += cos_t * omega
	if total_weight <= 0.0:
		return Color(0, 0, 0, 1)
	return Color(acc.r / PI, acc.g / PI, acc.b / PI, 1.0)


## Exact solid angle (steradians) of a rectangle on the cube face plane z=1:
## two spherical triangles from the origin (van Oosterom–Strackee).
static func cell_solid_angle(x0: float, x1: float, y0: float, y1: float) -> float:
	var a: Vector3 = Vector3(x0, y0, 1.0).normalized()
	var b: Vector3 = Vector3(x1, y0, 1.0).normalized()
	var c: Vector3 = Vector3(x1, y1, 1.0).normalized()
	var d: Vector3 = Vector3(x0, y1, 1.0).normalized()
	return _triangle_solid_angle(a, b, c) + _triangle_solid_angle(a, c, d)


static func _triangle_solid_angle(a: Vector3, b: Vector3, c: Vector3) -> float:
	var num: float = absf(a.dot(b.cross(c)))
	var den: float = 1.0 + a.dot(b) + b.dot(c) + c.dot(a)
	return 2.0 * atan2(num, den)


## Unit direction for a face texel. `u` is left->right, `v` is top->bottom
## (image space). Face order = FACE_AXES. Standard cube layout: +X looks at
## -Z on its left, +Y has -Z at the top of the image, +Z has -Y down.
static func direction_for_face_uv(face: int, u: float, v: float) -> Vector3:
	var s: float = 2.0 * u - 1.0
	var t: float = 2.0 * v - 1.0
	var d: Vector3
	match face:
		0: d = Vector3(1.0, -t, -s)   # +X
		1: d = Vector3(-1.0, -t, s)   # -X
		2: d = Vector3(s, 1.0, t)     # +Y (image top -> -Z)
		3: d = Vector3(s, -1.0, -t)   # -Y
		4: d = Vector3(s, -t, 1.0)    # +Z
		5: d = Vector3(-s, -t, -1.0)  # -Z
		_: d = Vector3(0, 1, 0)
	return d.normalized()


## Face index whose centre direction is the dominant axis of `axis`
## (0..5 in FACE_AXES order; -1 only for a zero vector).
static func face_index(axis: Vector3) -> int:
	if axis.length_squared() <= 0.0:
		return -1
	var a: Vector3 = axis.abs()
	if a.x >= a.y and a.x >= a.z:
		return 0 if axis.x > 0.0 else 1
	if a.y >= a.x and a.y >= a.z:
		return 2 if axis.y > 0.0 else 3
	return 4 if axis.z > 0.0 else 5


static func _texel(img: Image, u: float, v: float, transfer: String) -> Color:
	var x: int = clampi(int(u * float(img.get_width())), 0, img.get_width() - 1)
	var y: int = clampi(int(v * float(img.get_height())), 0, img.get_height() - 1)
	var c: Color = img.get_pixel(x, y)
	if transfer == "srgb":
		c = c.srgb_to_linear()
	return c


## Six face images from one generated record, or [] when anything is missing.
## A missing face is a data error, never filled with a guessed colour.
static func _load_faces(rec: Dictionary) -> Array:
	var faces_v: Variant = rec.get("faces", {})
	var faces: Dictionary = faces_v as Dictionary if faces_v is Dictionary else {}
	var out: Array = []
	for name: String in FACE_NAMES:
		var path: String = str(faces.get(name, ""))
		if path == "":
			_warn_once("cubemap face '%s' has no path" % name, path)
			return []
		var img: Image = _load_image(path)
		if img == null:
			_warn_once("cubemap face '%s' did not load" % name, path)
			return []
		out.append(img)
	return out


static func _load_image(res_path: String) -> Image:
	if ResourceLoader.exists(res_path):
		var tex: Texture2D = load(res_path) as Texture2D
		if tex != null:
			return tex.get_image()
	var abs_path: String = ProjectSettings.globalize_path(res_path)
	var img: Image = Image.load_from_file(abs_path)
	return img


static func _warn_once(msg: String, key: String) -> void:
	if _load_warned.has(key):
		return
	_load_warned[key] = true
	push_warning("TAT-2 IBL: " + msg)
