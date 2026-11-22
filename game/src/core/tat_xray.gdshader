shader_type spatial;
// OSEXray port: depth-disabled, unshaded silhouette with the authored
// MI_Xray* category colour + Fresnel Highlight. Values come from
// extracted/json/Graphics/MI_Xray{Guard,Loot,Clue,Player}.json; the
// material is applied as material_overlay so the real PBR pass is unchanged.
render_mode unshaded, cull_disabled, depth_test_disabled, blend_mix, depth_draw_never;

uniform vec4 xray_color : source_color = vec4(1.0, 0.4514, 0.0, 1.0);
uniform vec4 xray_highlight : source_color = vec4(1.0, 0.5775, 0.0, 1.0);
uniform float fresnel_power = 5.0;
uniform float fresnel_intensity = 1.0;
uniform float base_alpha = 0.58;
uniform float max_distance = 25.0;

varying vec3 v_view_normal;

void vertex() {
	v_view_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (max_distance > 0.0 && length(VERTEX) > max_distance) {
		discard;
	}
	float facing = clamp(dot(normalize(v_view_normal), normalize(-VERTEX)), 0.0, 1.0);
	float rim = pow(1.0 - facing, fresnel_power) * fresnel_intensity;
	ALBEDO = mix(xray_color.rgb, xray_highlight.rgb, clamp(rim, 0.0, 1.0));
	ALPHA = clamp(base_alpha + rim * 0.55, 0.0, 1.0);
}
