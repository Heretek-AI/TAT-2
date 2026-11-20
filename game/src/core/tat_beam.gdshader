shader_type spatial;
// APPROX_SHADER / REFERENCE_MATCHED (HL-1, KF27): crisp horizontal white
// security beams spanning the foyer. UE renders these as volumetric beam
// cards; the cooked shader was NOT decompiled. This stand-in makes a cylinder
// read volumetric: the view-facing core is bright and the silhouette feathers
// to zero, with a slow energy flow along the beam axis.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4 beam_color : source_color = vec4(1.0, 1.0, 1.0, 0.55);
uniform float energy = 2.0;
uniform float core_power = 2.2;
uniform float flow_strength = 0.16;
uniform float flow_speed = 0.35;

void fragment() {
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float core = pow(ndv, core_power);
	float flow = 0.5 + 0.5 * sin(UV.y * 6.2831853 - TIME * flow_speed * 6.2831853);
	float a = core * (1.0 - flow_strength + flow_strength * flow);
	ALBEDO = beam_color.rgb * energy;
	ALPHA = clamp(beam_color.a * a, 0.0, 1.0);
}
