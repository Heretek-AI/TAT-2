shader_type spatial;
// Level Niagara stand-in: one additive billboarded quad per authored placement,
// instanced through a MultiMesh (one node per NS_* system). Tint encodes the
// system family; per-instance phase keeps nearby emitters from pulsing in sync.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.62, 0.22, 1.0);
uniform float base_size : hint_range(0.01, 2.0) = 0.12;
uniform float pulse_speed : hint_range(0.0, 8.0) = 2.4;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.35;

varying float phase;

void vertex() {
	// Godot 4 has no `billboard` render mode: build the camera-facing basis
	// while keeping the instance translation from MODEL_MATRIX.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]
	);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	phase = float(INSTANCE_ID) * 0.6180339;
	float pulse = 1.0 + pulse_amount * sin(TIME * pulse_speed + phase * 6.28318);
	VERTEX.xy *= base_size * pulse;
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float core = clamp(1.0 - d, 0.0, 1.0);
	float shimmer = 0.82 + 0.18 * sin(TIME * pulse_speed * 1.7 + phase * 6.28318);
	ALBEDO = tint.rgb * shimmer;
	ALPHA = core * core * tint.a;
}
