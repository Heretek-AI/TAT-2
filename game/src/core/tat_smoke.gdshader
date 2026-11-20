shader_type spatial;
// APPROX_SHADER / REFERENCE_MATCHED (HL-1, KF20): opaque grey-white billowing
// smoke puffs on the grand stairs. The compiled Niagara system (NS_SmokeBomb)
// was NOT decompiled; this is a procedural soft-puff stand-in: view-facing
// body mask keeps the puff core opaque and feathers the silhouette so layered
// GPUParticles3D spheres read as one billowing cloud instead of hard balls.
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert;

uniform vec4 smoke_tint : source_color = vec4(0.86, 0.88, 0.91, 1.0);
uniform float body_power = 1.7;
uniform float density = 0.92;
uniform float glow = 0.07;
uniform float lump_scale = 3.1;
uniform float drift_speed = 0.32;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float body = pow(ndv, body_power);
	// Slow internal lumpiness so the layered spheres do not read as copies.
	float lump_a = sin(obj_pos.x * lump_scale + TIME * drift_speed);
	float lump_b = sin(obj_pos.y * (lump_scale * 0.73) - TIME * drift_speed * 0.7);
	float lump = 0.84 + 0.16 * lump_a * lump_b;
	float particle_alpha = clamp(COLOR.a, 0.0, 1.0);
	ALBEDO = smoke_tint.rgb * lump;
	ALPHA = clamp(smoke_tint.a * density * body * particle_alpha, 0.0, 1.0);
	EMISSION = smoke_tint.rgb * glow * particle_alpha;
}
