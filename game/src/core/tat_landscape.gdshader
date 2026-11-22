shader_type spatial;
// Real TAT landscape layer blend. Each LandscapeComponent has up to two
// weightmaps and WeightmapLayerAllocations parsed from the cooked UE map; the
// runtime maps each layer name to the extracted layer texture and blends by
// channel. Layers without a recovered texture are skipped, and the remaining
// weights are normalized. LandscapeVisibilityLayerInfo is used to discard
// authored holes instead of inventing geometry.
render_mode cull_back, diffuse_burley;

uniform sampler2D weightmap : filter_linear, repeat_disable;
uniform sampler2D weightmap_1 : filter_linear, repeat_disable;
uniform sampler2D layer_tex_0 : source_color, repeat_enable;
uniform sampler2D layer_tex_1 : source_color, repeat_enable;
uniform sampler2D layer_tex_2 : source_color, repeat_enable;
uniform sampler2D layer_tex_3 : source_color, repeat_enable;
uniform sampler2D layer_tex_4 : source_color, repeat_enable;
uniform int layer_channel_0 = -1;
uniform int layer_channel_1 = -1;
uniform int layer_channel_2 = -1;
uniform int layer_channel_3 = -1;
uniform int layer_channel_4 = -1;
uniform int layer_tex_idx_0 = 0;
uniform int layer_tex_idx_1 = 0;
uniform int layer_tex_idx_2 = 0;
uniform int layer_tex_idx_3 = 0;
uniform int layer_tex_idx_4 = 0;
uniform int visibility_tex_idx = -1;
uniform int visibility_channel = -1;
uniform int puddle_tex_idx = 0;
uniform int puddle_channel = -1;
uniform int groundwet_tex_idx = 0;
uniform int groundwet_channel = -1;
uniform sampler2D puddle_normal : hint_normal, repeat_enable;
uniform sampler2D puddle_opacity : filter_linear, repeat_enable;
uniform float discard_holes = 1.0;
uniform float uv_scale = 12.0;
uniform vec3 fallback_color : source_color = vec3(0.42, 0.42, 0.40);

float channel_value(vec4 w, int channel) {
	if (channel == 0) {
		return w.r;
	}
	if (channel == 1) {
		return w.g;
	}
	if (channel == 2) {
		return w.b;
	}
	if (channel == 3) {
		return w.a;
	}
	return 0.0;
}

// Explicit index mapping: only the two extracted weightmaps are bound.
// Unknown indices (2, 3, negatives) yield zero weight rather than silently
// reading a wrong weightmap.
vec4 weight_at(int tex_idx, vec2 uv) {
	if (tex_idx == 0) {
		return texture(weightmap, uv);
	}
	if (tex_idx == 1) {
		return texture(weightmap_1, uv);
	}
	return vec4(0.0);
}

void fragment() {
	// UE LandscapeVisibilityLayerInfo stores 1 = hole/invisible. The old test
	// was inverted (vis < 0.5), and Guildhall forced discard_holes=0 to hide
	// the resulting solid elevated shell. Fail safe to 0 (no discard) when a
	// component has no mask; discard only authored holes (vis > 0.5).
	float vis = 0.0;
	if (discard_holes > 0.5 && visibility_tex_idx >= 0 && visibility_channel >= 0) {
		vis = channel_value(weight_at(visibility_tex_idx, UV), visibility_channel);
	}
	vec3 col = vec3(0.0);
	float total = 0.0;

	if (layer_channel_0 >= 0) {
		float wt = channel_value(weight_at(layer_tex_idx_0, UV), layer_channel_0);
		col += texture(layer_tex_0, UV * uv_scale).rgb * wt;
		total += wt;
	}
	if (layer_channel_1 >= 0) {
		float wt = channel_value(weight_at(layer_tex_idx_1, UV), layer_channel_1);
		col += texture(layer_tex_1, UV * uv_scale).rgb * wt;
		total += wt;
	}
	if (layer_channel_2 >= 0) {
		float wt = channel_value(weight_at(layer_tex_idx_2, UV), layer_channel_2);
		col += texture(layer_tex_2, UV * uv_scale).rgb * wt;
		total += wt;
	}
	if (layer_channel_3 >= 0) {
		float wt = channel_value(weight_at(layer_tex_idx_3, UV), layer_channel_3);
		col += texture(layer_tex_3, UV * uv_scale).rgb * wt;
		total += wt;
	}
	if (layer_channel_4 >= 0) {
		float wt = channel_value(weight_at(layer_tex_idx_4, UV), layer_channel_4);
		col += texture(layer_tex_4, UV * uv_scale).rgb * wt;
		total += wt;
	}

	if (discard_holes > 0.5 && vis > 0.5) {
		discard;
	}
	float puddle = 0.0;
	float groundwet = 0.0;
	if (puddle_channel >= 0) {
		float pw = channel_value(weight_at(puddle_tex_idx, UV), puddle_channel);
		if (pw > 0.001) {
			float op = texture(puddle_opacity, UV * uv_scale).r;
			puddle = clamp(pw * op, 0.0, 1.0);
			col = mix(col, vec3(0.035, 0.045, 0.060) * max(total, 1.0), puddle * 0.85);
			NORMAL_MAP = texture(puddle_normal, UV * uv_scale).rgb;
			NORMAL_MAP_DEPTH = puddle * 0.25;
		}
	}
	if (groundwet_channel >= 0) {
		groundwet = channel_value(weight_at(groundwet_tex_idx, UV), groundwet_channel);
		col *= (1.0 - groundwet * 0.18);
	}
	ALBEDO = total > 0.001 ? col / total : fallback_color;
	float base_rough = mix(0.9, 0.42, groundwet);
	ROUGHNESS = mix(base_rough, 0.04, puddle);
	SPECULAR = mix(0.5, 0.85, max(puddle, groundwet * 0.4));
}
