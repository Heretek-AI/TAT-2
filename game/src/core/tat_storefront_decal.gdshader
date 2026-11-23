shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear, repeat_disable;
uniform vec3 gold_lin = vec3(1.0, 0.327, 0.106); // authored linear tint
uniform float bg_gold = 0.12;
uniform float em_floor = 0.03;
uniform float em_scroll = 0.80;
uniform float luma_lo = 0.55;
uniform float luma_hi = 0.85;

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	float luma = dot(t.rgb, vec3(0.2126, 0.7152, 0.0722));
	float mask = smoothstep(luma_lo, luma_hi, luma);
	ALBEDO = gold_lin * mix(bg_gold, 1.0, mask);
	METALLIC = mix(0.0, 0.85, mask);
	ROUGHNESS = mix(0.70, 0.20, mask);
	SPECULAR = mix(0.0, 0.20, mask);
	EMISSION = gold_lin * (em_floor + em_scroll * mask);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.3333;
}
