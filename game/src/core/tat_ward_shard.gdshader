shader_type spatial;
// APPROX_SHADER (HL-1, KF28): authored purple crystalline ward surface.
//
// The geometry is the shipped `SM_BlockerWard_4m_A/B` / `8m_A/B/C` shard
// cluster (376 instances in the Guildhall level): the cooked
// `M_BlockerWard` graph itself was not decompiled, so this shader carries the
// authored parameters that ARE recovered from the dump:
//   * colour   — BP_WardZone_Base.WardColor = #FF4DFD (255, 77, 253) and the
//                MI_BlockerWard EmissiveColor vector (1.0, 0.1307, 0.7967).
//                The per-instance MID override saved in the level is #7DFFB2
//                (green); the reference KF28 ward is purple, so the active
//                tint uses the base purple. `WardColor` green is kept as
//                `idle_tint` for the probe/report, not for the active look.
//   * emissive — MI_BlockerWard "Emissive Intensity" 1.0 (master M 2.0).
//   * fresnel  — M_BlockerWard Fresnel_Parameter (1.0, 0.04, 2.0, 0.0);
//                base 0.04, exponent 2.0.
//   * blend    — EBlendMode::BLEND_TranslucentGreyTransmittance, unlit,
//                two-sided-ish crystal facets.
// The M_BlockerWard normal-wave scroll (T_GlassWavesA_N, BaseX 0.0075 /
// BaseY -0.01) is represented by a low-amplitude object-space shimmer rather
// than a second sampler, so the shader stays valid on every backend and the
// facet read comes from the authored geometry, not from a texture guess.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform vec4 ward_color : source_color = vec4(1.0, 0.302, 0.992, 1.0);
uniform float emissive_energy = 1.0;
uniform float fresnel_base = 0.04;
uniform float fresnel_power = 2.0;
uniform float alpha_base = 0.78;
uniform float shimmer_speed = 0.7;
uniform float facet_gain = 0.55;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	float ndv = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float rim = pow(1.0 - ndv, fresnel_power);
	float shimmer = 0.94 + 0.06 * sin(TIME * shimmer_speed * 6.2831853 + obj_pos.y * 2.1);
	// Object-space band gives neighbouring shards distinct brightness without
	// re-rolling as the camera turns (the T08 lesson on view-space hashing).
	float band = 0.5 + 0.5 * sin(obj_pos.y * 7.0 + obj_pos.z * 4.0);
	vec3 body = ward_color.rgb * emissive_energy * (0.72 + facet_gain * band) * shimmer;
	// Authored fresnel base + rim: bright facet edges.
	body += mix(ward_color.rgb, vec3(1.0), 0.55) * (fresnel_base + rim) * emissive_energy;
	ALBEDO = body;
	ALPHA = clamp(alpha_base * (0.62 + 0.30 * band) * (0.85 + 0.25 * rim), 0.0, 1.0);
}
