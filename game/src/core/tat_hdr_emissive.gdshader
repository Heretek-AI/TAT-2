shader_type spatial;
// Authored UE HDR "Color" values (e.g. MI_Neon 50, 4.109, 0.521) are linear
// HDR emissive colours. StandardMaterial3D colour parameters are sRGB-
// converted and diffuse albedo clamps at 1.0, which destroys the authored
// ratio. This unshaded pass carries the authored linear values into the HDR
// buffer so ACES/glow compress them the way the UE tonemapper does.
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec3 hdr_color = vec3(1.0);
uniform float hdr_scale = 1.0;

void fragment() {
	ALBEDO = hdr_color * hdr_scale;
}
