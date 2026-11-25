shader_type spatial;
// APPROX_SHADER / REFERENCE_MATCHED (HL-1, KF28): faceted purple crystalline
// arcane ward sealing the foyer archway. The cooked material graph was NOT
// decompiled; facets are procedural hash cells over object space, so the veil
// reads as clustered crystal shards rather than a flat purple plane.
// `edge_fade` feathers the archway veil; shard meshes keep full coverage so
// their box faces stay crisp.
//
// T08 arithmetic fix (adjudication C-2). The old transfer was
//   col = ward_color.rgb * energy * facet,  facet in [0.5, 1.0]
// so with the authored energy (1.6 on the ward-zone box, 2.0 in the VFX veil
// and shards) EVERY facet sat above ~1.0 in blue and most above 0.8 in red:
// the tone curve compressed the whole intended 2:1 facet range into a flat
// pane (measured sd 0.031 over a 700x600 region of the capture). The same
// energy*alpha pairing put ALPHA at 0.6-0.86 - a solid panel instead of a
// veil. The transfer now keeps the facet range UNDER the curve (dark seams,
// a 0.08..1.0 body, energy as a modest peak gain) and opens the alpha with
// the same body, so the cluster reads and the ward reads through.
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

	// Shard lattice: quantised object-space cells (0.18 m on the 3.5 m ward
	// box at facet_scale 5.5, matching the authored facet pitch). Cells are
	// purely object-space: the old + floor(NORMAL * 2.0) keyed the hash on the
	// VIEW-space normal, so every facet re-rolled as the camera turned.
	vec3 p = obj_pos * facet_scale;
	float cell = hash31(floor(p));
	float facet = 0.08 + 0.92 * pow(cell, 1.35);
	float shimmer = 0.92 + 0.08 * sin(TIME * shimmer_speed * 6.2831853 + cell * 6.2831853);

	// Dark gaps between shards: distance to the cell border in cell space.
	// No screen-space derivative is used, so the seam is distance-stable and
	// the shader stays valid on every renderer/back-end.
	vec3 f = fract(p);
	vec3 d = min(f, 1.0 - f);
	float edge = min(min(d.x, d.y), d.z);
	float seam = smoothstep(0.0, 0.11, edge);

	// energy is a peak gain now, not a multiplier on every facet: peak ~1.2
	// at the authored 1.6/2.0, so only the brightest shards cross 1.0 and
	// keep a bloom core while the rest of the lattice stays below the curve.
	float gain = clamp(energy * 0.75, 0.15, 2.4);
	vec3 col = ward_color.rgb * mix(0.20, 1.05, facet) * gain * shimmer;
	col *= mix(0.28, 1.0, seam);
	// Lit shard cores: the near-black gaps plus a bright core is the
	// "clustered crystal column" read of the reference frame.
	float core = smoothstep(0.72, 1.0, facet) * seam;
	col += vec3(0.95, 0.84, 1.0) * core * (0.30 + 0.22 * gain);
	col = mix(col, vec3(0.92, 0.80, 1.0) * gain * 0.62, pow(rim, 2.0) * 0.45);

	float edge_mask = smoothstep(0.0, 0.08, UV.x) * smoothstep(1.0, 0.92, UV.x)
		* smoothstep(0.0, 0.06, UV.y) * smoothstep(1.0, 0.94, UV.y);
	float coverage = mix(1.0, edge_mask, clamp(edge_fade, 0.0, 1.0));
	ALBEDO = col;
	// Authored alpha is the maximum, not the pane opacity: at the ward-zone
	// box's 0.55 this yields 0.10..0.44, at the VFX veil's 0.40 0.07..0.32
	// and at the solid shard boxes' 0.90 0.16..0.72.
	ALPHA = clamp(ward_color.a * coverage * seam * (0.18 + 0.62 * facet) * shimmer, 0.0, 1.0);
}
