shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// UE-faithful masked discard: the storefront decal albedo is mostly black
// texels (the lit magenta interior reads through the scrollwork), so cut the
// black background out with an alpha scissor and keep only the gold emission
// on the scrollwork lines. The lit interior behind the frame shows through.
uniform sampler2D albedo_tex : source_color, filter_linear, repeat_disable;
uniform vec3 gold_lin = vec3(1.0, 0.327, 0.106); // authored linear tint
uniform float luma_lo = 0.50;
uniform float luma_hi = 0.85;
uniform float line_energy = 0.9;
// Retained for loader compatibility (the loader still sets these); unused.
uniform vec3 bg_color = vec3(1.0, 0.97, 0.94);
uniform float bg_gold = 0.008;
uniform float em_floor = 0.0;
uniform float em_scroll = 0.60;

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	float luma = dot(t.rgb, vec3(0.2126, 0.7152, 0.0722));
	float mask = smoothstep(luma_lo, luma_hi, luma);
	ALBEDO = vec3(0.0);
	METALLIC = mix(0.0, 0.85, mask);
	ROUGHNESS = mix(0.70, 0.20, mask);
	SPECULAR = mix(0.0, 0.20, mask);
	EMISSION = gold_lin * line_energy * mask;
	ALPHA = smoothstep(0.03, 0.20, luma);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
