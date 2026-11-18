shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

// UE M_EmissiveBase CustomPrimitiveData mapping (MSM_Unlit, BLEND_Opaque, TwoSided = false):
//   Data[0] = UseMoonlight
//   Data[1] = EmisMultiply
//   Data[2..4] = CPDEmissiveColor (R, G, B)
// Packed into MultiMesh INSTANCE_CUSTOM as vec4(R, G, B, EmisMultiply).

varying vec4 v_cpd;

void vertex() {
	v_cpd = INSTANCE_CUSTOM;
}

void fragment() {
	if (v_cpd.a <= 0.001) {
		discard;
	}
	ALBEDO = v_cpd.rgb * v_cpd.a;
}
