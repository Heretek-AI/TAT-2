shader_type spatial;
// Authored UE HDR "Color" values (e.g. MI_Neon 50, 4.109, 0.521) are linear
// HDR emissive colours. StandardMaterial3D colour parameters are sRGB-
// converted and diffuse albedo clamps at 1.0, which destroys the authored
// ratio. This unshaded pass carries the authored linear values into the HDR
// buffer so ACES/glow compress them the way the UE tonemapper does.
render_mode unshaded, cull_back, depth_draw_opaque;

// R3 APPROXIMATE Fresnel / flicker / HDR boost stand-in for cooked neon shader graphs.
// Preserves hdr_color & hdr_scale uniforms for Suite 37 regression checks.
// Flicker cadence is REFERENCE_MATCHED to KF01 (S01): the magenta
// Mac Neish / Jeweller tube visibly dims (~00:00.10), returns full-lit
// (~00:01.00), then drops its left half (~00:02.05) over ~2.1 s, so the slow
// envelope runs at ~2.99 rad/s with a spatial phase that lets tube sections
// dip at different times. Only materials with authored FlickerSpeed
// (MI_Neon_MacNeish) flicker; steady tubes (MI_Neon) keep flick=1.
// The tube core is desaturated toward pale gold (KF01 residual fix): UE's
// neon reads warm white-gold at the center, not saturated red-orange.
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
	vec3 col = hdr_color * hdr_scale * hdr_boost * tube;
	float core_mask = smoothstep(0.70, 0.98, ndv);
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 pale_gold = vec3(1.0, 0.84, 0.58) * lum;
	col = mix(col, pale_gold, core_mask * 0.55);
	float flick = 1.0;
	if (flicker_amp > 0.001 && flicker_speed > 0.001) {
		float slow = sin(TIME * 2.99 + NODE_POSITION_WORLD.x * 0.45 + NODE_POSITION_WORLD.z * 0.25);
		float fast = sin(TIME * (flicker_speed * 6.2831853 * 2.0 + 0.7) + NODE_POSITION_WORLD.z * 9.0 + NODE_POSITION_WORLD.y * 5.0);
		float dip = clamp(0.5 + 0.35 * slow + 0.15 * fast, 0.0, 1.0);
		flick = 1.0 - flicker_amp * dip;
	}
	ALBEDO = col * flick;
}
