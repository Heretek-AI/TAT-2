shader_type spatial;
// APPROX_SHADER / REFERENCE_MATCHED (HL-1, KF28): faceted purple crystalline
// arcane ward sealing the foyer archway. The cooked material graph was NOT
// decompiled; facets are procedural hash cells over object space plus a rim
// vein, so the veil reads as clustered crystal shards rather than a flat
// purple plane. `edge_fade` feathers the archway veil; shard meshes keep full
// coverage so their box faces stay crisp.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 ward_color : source_color = vec4(0.62, 0.28, 1.0, 0.86);
uniform float energy = 2.4;
uniform float facet_scale = 5.5;
uniform float shimmer_speed = 0.8;
uniform float rim_power = 1.6;
uniform float edge_fade = 0.0;

varying vec3 obj_pos;

float hash31(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	float ndv = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float rim = pow(1.0 - ndv, rim_power);
	// Faceted crystal cells: flat hash per quantised object-space cell.
	vec3 cell_pos = floor(obj_pos * facet_scale) + floor(NORMAL * 2.0);
	float cell = hash31(cell_pos);
	float facet = 0.50 + 0.50 * cell;
	float shimmer = 0.88 + 0.12 * sin(TIME * shimmer_speed * 6.2831853 + cell * 6.2831853);
	vec3 col = ward_color.rgb * energy * facet * shimmer;
	col = mix(col, vec3(0.92, 0.80, 1.0) * energy * 0.62, pow(rim, 2.0) * 0.45);
	float edge_mask = smoothstep(0.0, 0.08, UV.x) * smoothstep(1.0, 0.92, UV.x)
		* smoothstep(0.0, 0.06, UV.y) * smoothstep(1.0, 0.94, UV.y);
	float coverage = mix(1.0, edge_mask, clamp(edge_fade, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(ward_color.a * coverage * (0.70 + 0.30 * facet) * shimmer, 0.0, 1.0);
}
