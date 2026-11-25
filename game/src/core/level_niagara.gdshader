shader_type spatial;
// Level Niagara billboard (T12-VFX).
//
// One instanced quad per authored placement, one MultiMesh per (system, 32 m
// chunk). Per instance:
//   * translation from the authored placement,
//   * XY scale from the authored placement scale x the authored User.Scale
//     parameter (default 1,1),
//   * tint from the authored user colour (candle Color1, turret EffectColor,
//     beam EffectColor...) packed into the MultiMesh custom data.
// The renderer samples the resolved authored sprite when the measured mask table
// says it is a usable soft mask (sprite_masks.gd); otherwise the procedural
// radial falloff is the fallback. No branch of this shader guesses a colour from
// the system's name.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform sampler2D sprite_tex : source_color, filter_linear, repeat_disable;
uniform bool use_sprite = false;
// Per-system authored material tint (or the counted family fallback). The
// per-instance custom data multiplies it.
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float base_size : hint_range(0.005, 4.0) = 0.12;
uniform float pulse_speed : hint_range(0.0, 8.0) = 2.4;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.35;
// Single global additive HDR lift so authored linear colours survive the tonemap.
uniform float hdr_gain : hint_range(0.5, 4.0) = 2.0;

varying float phase;
varying vec4 inst_tint;

void vertex() {
	// Authored per-instance XY scale is carried by the instance basis; read it
	// before the camera-facing basis replaces it.
	vec2 inst_scale = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	// Godot 4 has no `billboard` render mode: build the camera-facing basis
	// while keeping the instance translation from MODEL_MATRIX.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]
	);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	phase = float(INSTANCE_ID) * 0.6180339;
	inst_tint = INSTANCE_CUSTOM;
	float pulse = 1.0 + pulse_amount * sin(TIME * pulse_speed + phase * 6.28318);
	VERTEX.xy *= base_size * inst_scale * pulse;
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float core = clamp(1.0 - d, 0.0, 1.0);
	vec4 c = tint * inst_tint;
	float mask = core * core;
	vec3 sprite_rgb = vec3(1.0);
	if (use_sprite) {
		vec4 s = texture(sprite_tex, UV);
		mask = s.a;
		sprite_rgb = s.rgb;
	}
	float shimmer = 0.82 + 0.18 * sin(TIME * pulse_speed * 1.7 + phase * 6.28318);
	ALBEDO = c.rgb * hdr_gain * sprite_rgb * shimmer;
	ALPHA = mask * c.a;
}
