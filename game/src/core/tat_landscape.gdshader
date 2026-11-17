shader_type spatial;
// Real TAT landscape layer blend. Each LandscapeComponent has a weightmap and
// WeightmapLayerAllocations parsed from the cooked UE map; the runtime maps
// each layer name to the extracted layer texture and blends by channel.
// Layers without a recovered texture are skipped, and the remaining weights
// are normalized. LandscapeVisibilityLayerInfo is used to discard authored
// holes instead of inventing geometry.
render_mode cull_disabled, diffuse_burley;

uniform sampler2D weightmap : filter_linear, repeat_disable;
uniform sampler2D layer_tex_0 : source_color, repeat_enable;
uniform sampler2D layer_tex_1 : source_color, repeat_enable;
uniform sampler2D layer_tex_2 : source_color, repeat_enable;
uniform sampler2D layer_tex_3 : source_color, repeat_enable;
uniform int layer_channel_0 = -1;
uniform int layer_channel_1 = -1;
uniform int layer_channel_2 = -1;
uniform int layer_channel_3 = -1;
uniform int layer_visibility_0 = 0;
uniform int layer_visibility_1 = 0;
uniform int layer_visibility_2 = 0;
uniform int layer_visibility_3 = 0;
uniform int puddle_channel = -1;
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

void fragment() {
	vec4 w = texture(weightmap, UV);
	float vis = 1.0;
	vec3 col = vec3(0.0);
	float total = 0.0;

	if (layer_channel_0 >= 0) {
		float wt = channel_value(w, layer_channel_0);
		if (layer_visibility_0 == 1) {
			vis = wt;
		} else {
			col += texture(layer_tex_0, UV * uv_scale).rgb * wt;
			total += wt;
		}
	}
	if (layer_channel_1 >= 0) {
		float wt = channel_value(w, layer_channel_1);
		if (layer_visibility_1 == 1) {
			vis = wt;
		} else {
			col += texture(layer_tex_1, UV * uv_scale).rgb * wt;
			total += wt;
		}
	}
	if (layer_channel_2 >= 0) {
		float wt = channel_value(w, layer_channel_2);
		if (layer_visibility_2 == 1) {
			vis = wt;
		} else {
			col += texture(layer_tex_2, UV * uv_scale).rgb * wt;
			total += wt;
		}
	}
	if (layer_channel_3 >= 0) {
		float wt = channel_value(w, layer_channel_3);
		if (layer_visibility_3 == 1) {
			vis = wt;
		} else {
			col += texture(layer_tex_3, UV * uv_scale).rgb * wt;
			total += wt;
		}
	}

	if (discard_holes > 0.5 && vis < 0.5) {
		discard;
	}
	float puddle = 0.0;
	float groundwet = 0.0;
	if (puddle_channel >= 0) {
		float pw = channel_value(w, puddle_channel);
		if (pw > 0.001) {
			float op = texture(puddle_opacity, UV * uv_scale).r;
			puddle = clamp(pw * op, 0.0, 1.0);
			col = mix(col, vec3(0.035, 0.045, 0.060) * max(total, 1.0), puddle * 0.85);
			NORMAL_MAP = texture(puddle_normal, UV * uv_scale).rgb;
			NORMAL_MAP_DEPTH = puddle;
		}
	}
	if (groundwet_channel >= 0) {
		groundwet = channel_value(w, groundwet_channel);
		col *= (1.0 - groundwet * 0.18);
	}
	ALBEDO = total > 0.001 ? col / total : fallback_color;
	ROUGHNESS = mix(mix(0.9, 0.18, puddle), 0.45, groundwet);
}
