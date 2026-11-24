shader_type spatial;
// Wall-outline escape portal: a thin vertical ring with a green core and a
// violet rim, drawn on a QuadMesh in the gate's local XY plane (the gate's own
// transform orients it; no billboard). Additive/unshaded so it reads as an
// extraction marker without lighting the wall behind it.

render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 core_color : source_color = vec4(0.36, 1.0, 0.58, 1.0);
uniform vec4 edge_color : source_color = vec4(0.62, 0.34, 1.0, 1.0);
uniform float glow : hint_range(0.2, 4.0) = 1.8;
uniform float ring_radius : hint_range(0.2, 0.94) = 0.82;
uniform float ring_width : hint_range(0.01, 0.2) = 0.05;

void fragment() {
	// UV 0..1 across the quad; a circular radius in UV space becomes a tall
	// oval on the 2.6 x 3.0 wall quad, and the whole ring stays inside the
	// quad instead of being cut by its top/bottom edge.
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);

	// Green core ring and a thinner violet rim just outside it.
	float core = 1.0 - smoothstep(ring_width * 0.45, ring_width, abs(r - ring_radius));
	float rim = 1.0 - smoothstep(0.012, 0.036, abs(r - (ring_radius + ring_width * 1.15)));
	// Faint interior wash keeps the doorway readable against dark walls.
	float inner = (1.0 - smoothstep(0.0, ring_radius, r)) * 0.08;
	// Soft outer halo (no hard quad edge).
	float halo = (1.0 - smoothstep(ring_radius, 1.0, r)) * 0.06;

	vec3 col = core_color.rgb * core + edge_color.rgb * rim + core_color.rgb * (inner + halo);
	float alpha = clamp(core + rim + inner + halo, 0.0, 1.0);
	ALBEDO = col * glow;
	ALPHA = alpha;
}
