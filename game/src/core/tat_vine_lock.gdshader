shader_type spatial;
// APPROX_SHADER (HL-1, KF28 #5): green arcane door ward.
//
// Authored inputs (extracted/json + materials.json):
//   * MI_DoorWard_OneSided_Green Color (0.1334, 1.0, 0.0, 1.0),
//     BLEND_TranslucentGreyTransmittance, unlit, two-sided parent (the
//     "OneSided" instance switches the outside face off).
//   * T_DoorWard_Glyph_Hand.png  — hand/eye glyph
//   * T_DoorWard_Lines.png       — white vertical line network on black
//     (opaque alpha; use luminance, not alpha, for the mask)
//   * MaskMultiply 0.6, MaskPower 1.0, GlyphMultiply 1.0, InnerMaskDensity
//     0.49, DepthFade 10.0.
// The cooked graph is not decompiled: the composition below (glyph x line
// network, with the authored tint and the translucent feel of the reference
// frame) is the documented approximation. The "thorny vine" read comes from
// the authored line network + glyph, never from invented vine geometry.
//
// The authored T_DoorWard_Mask.png (archway mask) is NOT bound: it is a 2048 px
// uncapped texture and `make audit` fails closed on a new over-cap reference
// (texture-cap-check). A soft rectangular frame is used instead; binding the
// mask needs `make desktop-texture-cap`, which is an integrator/data action.
render_mode unshaded, blend_mix, cull_back, depth_draw_never;

uniform sampler2D glyph_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D lines_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec4 vine_color : source_color = vec4(0.1334, 1.0, 0.0, 1.0);
uniform float energy = 2.2;
uniform float mask_multiply = 0.6;
uniform float inner_density = 0.49;
uniform float scroll_speed = 0.06;

void fragment() {
	vec2 uv = UV;
	// Authored line network: white lines on black, so luminance is the mask.
	float lines_a = 1.0 - dot(texture(lines_tex, uv).rgb, vec3(0.3333));
	float lines_b = 1.0 - dot(texture(lines_tex, uv * 1.7 + vec2(TIME * scroll_speed, 0.0)).rgb, vec3(0.3333));
	float lines = clamp(max(lines_a, lines_b * 0.6), 0.0, 1.0);
	// Authored hand/eye glyph, two scrolled samples so the ward reads alive.
	float glyph_a = dot(texture(glyph_tex, uv * 1.15 - vec2(0.0, TIME * scroll_speed * 0.35)).rgb, vec3(0.3333));
	float glyph_b = dot(texture(glyph_tex, uv * 1.15 - vec2(0.0, TIME * scroll_speed * 0.35 + 0.37)).rgb, vec3(0.3333));
	float glyph = clamp(glyph_a + glyph_b * 0.55, 0.0, 1.0);
	// Soft rectangular door frame (the authored arch mask is not bound).
	float frame = smoothstep(0.0, 0.035, uv.x) * smoothstep(1.0, 0.965, uv.x)
		* smoothstep(0.0, 0.03, uv.y) * smoothstep(1.0, 0.97, uv.y);
	float body = clamp((lines * 0.9 + glyph * 0.7) * frame * mask_multiply + inner_density * 0.10, 0.0, 1.0);
	vec3 col = vine_color.rgb * energy * (0.25 + 2.1 * body);
	// Slight white-hot core on the densest line/glyph crossings.
	col += vec3(0.55, 1.0, 0.55) * smoothstep(0.55, 0.95, body) * energy * 0.35;
	ALBEDO = col;
	ALPHA = clamp(body * 1.35 + 0.06, 0.0, 1.0);
}
