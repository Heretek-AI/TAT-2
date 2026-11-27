shader_type spatial;
// Escape-point wall outline (S12 / KF14 #1, row V6-01).
//
// Authored sources for every constant:
//   * Geometry: BP_EscapePoint `SummonBox` BoxExtent (92.07361, 12.25,
//     119.341095) cm -> a 1.841 x 2.387 m wall quad, not a 2.6 x 3.0 ring.
//   * Colours: BP_EscapePoint `OpenColor` #7EFF9B (0.207843, 1.0, 0.329412)
//     and `ClosedColor` #C651FF (0.561445, 0.083097, 1.0). KF14 shows the
//     open emerald core with the closed violet riding on the chromatic fringe.
//   * Shape: NS_EscapePoint draws `VFXSHAPES_BoxContourGlow` (a rectangular
//     contour) with MI_RespawnPortal_LightBeam, plus MI_EscapePoint_Cubemap for
//     the interior wash and four MI_BurstEmbers edge emitters. The contour is
//     jagged/organic and shimmers (01:15.2-01:16.2); this shader draws that
//     rectangular contour and animates the jag with a noise-warped SDF.
//
// The contour is computed in UV space, so the QuadMesh's own transform orients
// it on the wall and nothing billboards. Additive/unshaded: the "black doorway"
// in the reference is simply where the additive pass contributes nothing.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 core_color : source_color = vec4(0.207843, 1.0, 0.329412, 1.0);
uniform vec4 edge_color : source_color = vec4(0.561445, 0.083097, 1.0, 1.0);
uniform float glow : hint_range(0.2, 6.0) = 2.6;
// Contour line width in UV half-space (0.045 of 1.84 m ~= 8 cm on the wall).
uniform float outline_width : hint_range(0.005, 0.12) = 0.06;
uniform float fringe_width : hint_range(0.004, 0.08) = 0.02;
// Outer frame and inner doorway rectangles in UV half-space (-1..1).
uniform vec2 frame_half = vec2(0.90, 0.92);
uniform vec2 door_half = vec2(0.36, 0.46);
uniform float door_center_y : hint_range(-0.5, 0.5) = -0.06;
// Jagged-edge amount/frequency and the shimmer cadence.
uniform float jag : hint_range(0.0, 1.0) = 0.55;
uniform float jag_scale : hint_range(1.0, 60.0) = 9.0;
uniform float shimmer_hz : hint_range(0.0, 4.0) = 0.9;
uniform float shimmer_amount : hint_range(0.0, 1.0) = 0.28;
uniform float wash : hint_range(0.0, 0.4) = 0.20;
uniform float interior_dark : hint_range(0.0, 1.0) = 0.90;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Signed distance to an axis-aligned rectangle centred on the origin.
float rect_sd(vec2 p, vec2 half_size) {
	vec2 d = abs(p) - half_size;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float t = TIME * shimmer_hz;

	// Two-octave noise warp: the authored contour is torn, not a clean frame.
	float n = vnoise(p * jag_scale + vec2(t * 1.7, -t)) * 0.65
			+ vnoise(p * jag_scale * 2.3 - vec2(t * 2.3, t * 1.1)) * 0.35;
	float n2 = vnoise(p * jag_scale * 1.4 + vec2(7.3, t * 1.3));
	vec2 q = p + (vec2(n, n2) - 0.5) * jag * 0.10;

	float sd_frame = rect_sd(q, frame_half);
	float sd_door = rect_sd(q - vec2(0.0, door_center_y), door_half);

	// Emerald core lines (outer frame + inner doorway).
	float frame_line = 1.0 - smoothstep(outline_width * 0.35, outline_width, abs(sd_frame));
	float door_line = 1.0 - smoothstep(outline_width * 0.35, outline_width, abs(sd_door));
	// Violet chromatic fringe just outside both core lines.
	float frame_fringe = 1.0 - smoothstep(fringe_width * 0.4, fringe_width,
			abs(sd_frame - outline_width * 1.55));
	float door_fringe = 1.0 - smoothstep(fringe_width * 0.4, fringe_width,
			abs(sd_door - outline_width * 1.55));

	// Interior wash: inside the frame, but the doorway itself stays dark (the
	// reference's black opening) so the wall reads through the middle.
	float inside_frame = 1.0 - smoothstep(0.0, 0.06, sd_frame);
	float inside_door = 1.0 - smoothstep(0.0, 0.02, sd_door);
	// Keep the wash off the doorway's own violet fringe line so the chromatic
	// edge stays violet instead of washing to white against the green field.
	float door_band = clamp(door_line + door_fringe, 0.0, 1.0);
	float wash_mask = inside_frame * (1.0 - inside_door * interior_dark) * (1.0 - door_band);
	float vertical = mix(1.0, 0.55, smoothstep(-1.0, 1.0, p.y));

	// Shimmer: the whole outline breathes at the authored cadence and the
	// noise phase keeps left/right edges out of sync.
	float shimmer = 1.0 + shimmer_amount * sin(t * 6.2831853 * 2.0 + n * 12.0);

	vec3 core = core_color.rgb * (frame_line + door_line) * shimmer;
	vec3 edge = edge_color.rgb * (frame_fringe + door_fringe) * (0.75 * shimmer);
	vec3 fill = core_color.rgb * wash_mask * wash * vertical * (0.8 + 0.4 * n);
	vec3 col = core + edge + fill;
	float a = clamp(frame_line + door_line + frame_fringe + door_fringe + wash_mask * wash, 0.0, 1.0);
	ALBEDO = col * glow * a;
	ALPHA = a;
}
