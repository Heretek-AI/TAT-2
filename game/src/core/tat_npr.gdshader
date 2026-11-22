shader_type spatial;
// C1 OSE.NPR + OSE.SNN screen-space pass.
//
// NPR: depth + normal Sobel edge ink. The authored game implements ink through
//      material layers; this is the documented post-process approximation.
// SNN: edge-preserving (depth-aware) painterly blur + HSV/quantization.
//      Authored defaults come from /Game/MaterialLibrary/Utility/PainterlyEffects/
//      MPC_Painterly: HSV 0.65, Depth 1.25, Hue 0.55, Effect 0.0 (off by
//      default), distance thresholds 1250/3500 cm -> 12.5/35 m.
render_mode unshaded, cull_disabled, depth_test_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D normal_texture : hint_normal_roughness_texture, filter_nearest;

uniform bool npr_enabled = false;
uniform bool snn_enabled = false;
uniform float ink_strength = 1.0;
uniform vec4 ink_color : source_color = vec4(0.015, 0.018, 0.026, 1.0);
uniform float edge_threshold = 0.055;
uniform float normal_edge_weight = 0.45;
uniform float snn_effect = 0.0;
uniform float snn_hsv = 0.65;
uniform float snn_depth = 1.25;
uniform float snn_hue = 0.55;
uniform vec2 snn_distance = vec2(12.5, 35.0);

// Godot 4.7 spatial fragment does not expose INV_PROJECTION_MATRIX in this
// pipeline; use the raw depth buffer for relative edge detection. This is an
// APPROXIMATE linearization-free path, documented in the C1 report.
float linear_depth(vec2 uv) {
	return texture(depth_texture, uv).r;
}

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec3 base = texture(screen_texture, uv).rgb;
	float center_d = linear_depth(uv);
	vec3 center_n = texture(normal_texture, uv).rgb;

	vec2 offs[4] = vec2[4](vec2(px.x, 0.0), vec2(-px.x, 0.0), vec2(0.0, px.y), vec2(0.0, -px.y));
	float depth_edge = 0.0;
	float normal_edge = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 o = uv + offs[i];
		float nd = linear_depth(o);
		vec3 nn = texture(normal_texture, o).rgb;
		// Relative depth discontinuity: a 5 cm step at 1 m is an edge, while
		// the same step at 40 m is not.
		depth_edge += abs(nd - center_d) / max(center_d, 0.25);
		normal_edge += length(nn - center_n);
	}
	float distance_scale = 1.0 + center_d * 2.0;
	float edge = step(edge_threshold * distance_scale, depth_edge * 0.25 + normal_edge * normal_edge_weight * 0.25);
	vec3 color = base;
	if (npr_enabled) {
		color = mix(color, ink_color.rgb, clamp(edge * ink_strength, 0.0, 0.85));
	}

	if (snn_enabled && snn_effect > 0.001) {
		// Joint bilateral: average the neighbour with the closest depth to the
		// center so paint strokes stop at silhouettes instead of bleeding.
		vec3 painterly = base;
		float wsum = 1.0;
		for (int j = 0; j < 4; j++) {
			vec2 o2 = uv + offs[j] * 2.5;
			float nd2 = linear_depth(o2);
			float w = 1.0 / (1.0 + abs(nd2 - center_d) * 8.0);
			painterly += texture(screen_texture, o2).rgb * w;
			wsum += w;
		}
		painterly /= wsum;
		// Raw depth normalized to the authored 35 m far threshold (no inverse
		// projection matrix available in this fragment stage).
		float depth_fade = smoothstep(snn_distance.x, snn_distance.y, center_d * 35.0);
		float amt = clamp(snn_effect * (0.35 + 0.65 * (1.0 - depth_fade)), 0.0, 1.0);
		vec3 hsv = rgb2hsv(painterly);
		hsv.x = fract(hsv.x + snn_hue * 0.06);
		hsv.y = clamp(hsv.y * (1.0 + snn_hsv * 0.35), 0.0, 1.0);
		// Quantized value bands read as paint blocks rather than a blur.
		hsv.z = floor(hsv.z * 7.0 + 0.5) / 7.0;
		painterly = hsv2rgb(hsv);
		painterly = mix(painterly, base, clamp(1.0 - snn_depth * 0.15, 0.0, 0.5));
		color = mix(color, painterly, amt * 0.75);
	}
	ALBEDO = color;
	ALPHA = 1.0;
}
