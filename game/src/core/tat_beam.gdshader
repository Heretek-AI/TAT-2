shader_type spatial;
// Authored security-beam card material (KF27 / V6-03).
// Source: extracted/json/Gameplay/Traps/Detectors/LightBeam/MI_LightBeam_SM.json
//   BaseColor            = (5.0, 4.3813, 3.5156, 0.5)   [linear HDR]
//   EmissiveMultiplier   = 3.0
//   Center Line Thickness= 0.015 m   (the mesh's own octagonal core is 0.014 m)
//   Center Line Opacity  = 0.5
//   Center Line Falloff  = 0.25
//   Fake Glow Opacity    = 0.06
//   Fake Glow Thickness  = 0.02 m   (the tight core, full width)
//   Fake Glow Center W.  = 0.085 m  (the centre glow radius)
//   Fake Glow Center Pow.= 2.0
//   Fake Glow Power      = 1.1
//   Fake Glow Side Width = 1.0 m    (exposed, not applied: this is the wide
//                                    side lobe; the authored material masks it
//                                    with T_Noise2/T_Noise_01, which this
//                                    shader does not sample. A bare 1 m lobe
//                                    at 6 % is the broad cream slab P1 removed,
//                                    so it waits for a noise-mask lane.)
//   FadeDistance         = 25.0 m
//   Center Line Sphere Mask Radius = 1.0 m  (exposed, not applied: no authored
//                                    sphere centre/space is serialized, so any
//                                    choice would be invented)
//   Sphere Mask Opacity  = 0.25    (exposed, not applied, same reason)
//   Sphere Mask Power    = 2.0     (exposed, not applied, same reason)
//   EdgeFadePower        = 0.5     (exposed, not applied: the centre-line
//                                    model has no visible card silhouette and
//                                    a radial edge term would double-count
//                                    Fake Glow Power)
//   BLEND_Additive, two-sided, MSM_Unlit
//
// The authored SM_LightBeam mesh is a 1 m crossed-card volume with a 14 mm
// octagonal core on its local X axis. The material draws a 1.5 cm centre line
// (the core) plus a 6 % fake glow: a 2 cm authored core inside the 8.5 cm
// centre glow, so the 1 m card reads as a thin crisp line instead of the old
// full-tube bar. The old stand-in used beam_color alpha 0.55 across the whole
// shell; that is why the P0b capture showed broad cream bars. No flow
// animation is authored.
// HDR values are authored linear, so the uniform deliberately has no
// source_color hint (that would sRGB-decode 5.0 to ~34).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 beam_color = vec4(5.0, 4.3813, 3.5156, 0.5);
uniform float emissive_multiplier = 3.0;
uniform float center_line_thickness = 0.015;
uniform float center_line_opacity = 0.5;
uniform float center_line_falloff = 0.25;
uniform float fake_glow_opacity = 0.06;
uniform float fake_glow_thickness = 0.02;
uniform float fake_glow_center_width = 0.085;
uniform float fake_glow_center_power = 2.0;
uniform float fake_glow_power = 1.1;
uniform float fake_glow_side_width = 1.0;
uniform float fade_distance = 25.0;
// Authored terms that are exposed but intentionally not applied (see the
// header): the UE graph is not in the dump and every available reading would
// invent a centre/axis or reintroduce the broad cream slab P1 removed.
uniform float center_line_sphere_mask_radius = 1.0;
uniform float sphere_mask_opacity = 0.25;
uniform float sphere_mask_power = 2.0;
uniform float edge_fade_power = 0.5;
// 0 = card (axis local X, radial YZ); 1 = cylinder (axis local Y, radial XZ);
// 2 = axis local Z, radial XY. The authored card is 0; the security_beam.gd
// fallback cylinder and the QA foyer beams are 1.
uniform int radial_axis = 0;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec2 radial = v_local.yz;
	if (radial_axis == 1) {
		radial = v_local.xz;
	} else if (radial_axis == 2) {
		radial = v_local.xy;
	}
	float radius = length(radial);

	// Centre line: a 1.5 cm band with the authored 0.25 falloff.
	float half_thickness = max(center_line_thickness * 0.5, 0.0005);
	float inner = max(half_thickness * (1.0 - center_line_falloff), 0.0);
	float outer = max(half_thickness * (1.0 + center_line_falloff), inner + 0.0001);
	float line = 1.0 - smoothstep(inner, outer, radius);

	// Fake glow (authored row): a tight core (Fake Glow Thickness) with the
	// centre power, inside the 8.5 cm centre glow (Fake Glow Power), at the
	// authored 6 % peak. The two lobes are summed and clamped to the authored
	// peak so the core can never exceed Fake Glow Opacity. Every value is a
	// uniform fed from materials.json; the fallbacks are the authored values.
	float core_radius = max(fake_glow_thickness * 0.5, 0.0001);
	float center_radius = max(fake_glow_center_width, core_radius + 0.0001);
	float body_t = clamp(1.0 - radius / center_radius, 0.0, 1.0);
	float glow_body = pow(body_t, max(fake_glow_power, 0.001));
	float core_t = clamp(1.0 - radius / core_radius, 0.0, 1.0);
	float glow_core = pow(core_t, max(fake_glow_center_power, 0.001));
	float glow = fake_glow_opacity * min(glow_body + glow_core, 1.0);

	float alpha = clamp(center_line_opacity * line + glow, 0.0, 1.0);
	// Authored 25 m fade distance. Fade only the last quarter so the beam keeps
	// its authored brightness across the foyer and disappears by 25 m.
	float fade_start = fade_distance * 0.75;
	float cam_dist = length(VERTEX);
	alpha *= 1.0 - smoothstep(fade_start, max(fade_distance, fade_start + 0.001), cam_dist);
	alpha = clamp(alpha, 0.0, 1.0);

	ALBEDO = beam_color.rgb * emissive_multiplier;
	ALPHA = alpha;
}
