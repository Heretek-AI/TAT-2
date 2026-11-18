shader_type spatial;
// Authored UE HDR "Color" values (e.g. MI_Neon 50, 4.109, 0.521) are linear
// HDR emissive colours. StandardMaterial3D colour parameters are sRGB-
// converted and diffuse albedo clamps at 1.0, which destroys the authored
// ratio. This unshaded pass carries the authored linear values into the HDR
// buffer so ACES/glow compress them the way the UE tonemapper does.
render_mode unshaded, cull_back, depth_draw_opaque;

// R3 APPROXIMATE Fresnel / flicker / HDR boost stand-in for cooked neon shader graphs.
// Preserves hdr_color & hdr_scale uniforms for Suite 37 regression checks.
uniform vec3 hdr_color = vec3(1.0);
uniform float hdr_scale = 1.0;
uniform float hdr_boost = 1.0;
uniform float fresnel_power = 0.0;
uniform float fresnel_min = 1.0;
uniform float flicker_speed = 0.0;
uniform float flicker_amp = 0.0;

void fragment() {
	float ndv = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float tube = (fresnel_power > 0.001) ? mix(fresnel_min, 1.25, pow(ndv, fresnel_power)) : 1.0;
	float flick = 1.0;
	if (flicker_amp > 0.001 && flicker_speed > 0.001) {
		float w1 = sin(TIME * flicker_speed * 6.2831853);
		float w2 = sin(TIME * (flicker_speed * 1.37 + 0.13) * 6.2831853);
		flick = 1.0 - flicker_amp * clamp(0.5 + 0.35 * w1 + 0.15 * w2, 0.0, 1.0);
	}
	ALBEDO = hdr_color * hdr_scale * hdr_boost * tube * flick;
}
