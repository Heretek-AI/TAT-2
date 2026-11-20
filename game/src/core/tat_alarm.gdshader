shader_type spatial;
// APPROX_SHADER / REFERENCE_MATCHED (HL-1, KF29): crimson alarm wash over the
// slate stairs (S26, 03:38.20-03:39.60). UE renders the wall fixture as a
// spotlight plus volumetric beam cards; the cooked graph was NOT decompiled.
// This stand-in makes an open cone read as a strobing volume: view-facing body,
// axial falloff from the fixture to the floor, and a 2.2 Hz alarm pulse.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4 alarm_color : source_color = vec4(1.0, 0.07, 0.05, 0.12);
uniform float energy = 2.2;
uniform float strobe_hz = 2.2;
uniform float strobe_depth = 0.55;
uniform float body_power = 1.6;
uniform float axial_floor = 0.35;

void fragment() {
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float body = pow(ndv, body_power);
	float axial = mix(1.0, axial_floor, clamp(UV.y, 0.0, 1.0));
	float strobe = 1.0 - strobe_depth * (0.5 + 0.5 * sin(TIME * strobe_hz * 6.2831853));
	ALBEDO = alarm_color.rgb * energy;
	ALPHA = clamp(alarm_color.a * body * axial * strobe, 0.0, 1.0);
}
