shader_type canvas_item;
// C3 PPM_RainDropsOnLens overlay. Authored params from
// /Game/Art/VFX/Environment/RainStorm/PostProcessMaterial/PPMI_RainDropsOnLens:
// AnimationSpeed .25, MaskEdge .2, MaskFalloff .1, RainDropsTiling 2.0,
// RainDropsNormalStrength .05. T_RainDropsPacked is the shipped packed drop
// texture; the exact channel meaning is cooked, so this samples B as mask and
// RG as a small screen refraction offset (APPROXIMATE, documented).
uniform sampler2D drop_tex : filter_linear_mipmap;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float intensity = 1.0;
uniform float tiling = 2.0;
uniform float animation_speed = 0.25;
uniform float mask_edge = 0.2;
uniform float mask_falloff = 0.1;
uniform float normal_strength = 0.05;

void fragment() {
	vec2 drop_uv = SCREEN_UV * tiling + vec2(0.0, -TIME * animation_speed);
	vec4 packed = texture(drop_tex, drop_uv);
	vec2 offset = (packed.rg - 0.5) * normal_strength * 0.18;
	vec3 scene = texture(screen_tex, SCREEN_UV + offset).rgb;
	float mask = smoothstep(mask_edge, mask_edge + mask_falloff, packed.b);
	COLOR = vec4(scene, clamp(mask * intensity, 0.0, 1.0));
}
