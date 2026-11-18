shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

// Authored translucent glass shader for UE5 MSM_ThinTranslucent / BLEND_Translucent* glass materials.
// Reads authored albedo + grayscale R-channel opacity map (or albedo alpha when no _O map exists),
// optional normal and ORM maps, and authored UE tint/scalar parameters from materials.json.

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D opacity_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float opacity_scale : hint_range(0.0, 8.0) = 1.0;
uniform float roughness_val : hint_range(0.0, 4.0) = 0.25;
uniform float metallic_val : hint_range(0.0, 1.0) = 0.0;
uniform float specular_val : hint_range(0.0, 1.0) = 0.5;
uniform float uv_scale = 1.0;
uniform bool use_albedo_tex = false;
uniform bool use_opacity_tex = false;
uniform bool use_normal_tex = false;
uniform bool use_orm_tex = false;
uniform vec3 emission_color : source_color = vec3(0.0, 0.0, 0.0);
uniform float emission_energy = 0.0;

void fragment() {
	vec2 uv = UV * uv_scale;
	vec4 alb = use_albedo_tex ? texture(albedo_tex, uv) : vec4(1.0);
	ALBEDO = alb.rgb * albedo_tint.rgb;
	float op_sample = use_opacity_tex ? texture(opacity_tex, uv).r : (use_albedo_tex ? alb.a : 1.0);
	ALPHA = clamp(op_sample * opacity_scale, 0.0, 1.0);
	if (use_orm_tex) {
		vec3 orm = texture(orm_tex, uv).rgb;
		AO = orm.r;
		ROUGHNESS = clamp(orm.g * roughness_val, 0.04, 1.0);
		METALLIC = clamp(orm.b * metallic_val, 0.0, 1.0);
	} else {
		ROUGHNESS = clamp(roughness_val, 0.04, 1.0);
		METALLIC = clamp(metallic_val, 0.0, 1.0);
	}
	SPECULAR = specular_val;
	if (use_normal_tex) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
	}
	if (emission_energy > 0.001) {
		EMISSION = emission_color * emission_energy;
	}
}
