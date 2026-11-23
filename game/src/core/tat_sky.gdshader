shader_type sky;
// TAT-2 real night sky. Gradient + moon disc + sparse stars + horizon cloud
// haze, all driven by the extracted BP_WeatherPreset_* JSON values (see
// weather_visuals.gd for the UE -> Godot value mapping).
//
// APPROXIMATIONS (labelled, no fake art): the star field is a procedural hash
// sparkle (no star catalogue was recovered from cooking); the cloud term is a
// horizon haze tinted by sky.cloud_color (the volumetric cloud materials were
// not recovered, only their color/opacity scalars); the moon disc projects the
// real T_Moon_D lunar panorama onto the visible hemisphere (equirectangular
// atan/acos UV with nz >= 0, which keeps atan inside [-pi/2, pi/2] so there is
// no seam), and anti-aliases the disc edge over about 2% of the disc radius
// (the AA band is max(1.5 pixel-widths, (1 - cos_r) * 0.02), so the relative
// floor survives the small 2.1 degree preset instead of being swamped).
//
// Moon constants extracted from the cooked MI_Moon_Base material:
//   Fresnel Base Reflect Fraction 0.22, Fresnel Exponent In 2.9,
//   Light Brighness 1.5, Light/Shadow Contrast -0.51,
//   Light X Position 0.26, Light Y Position -0.476.
// Constants chosen by us, not extracted:
//   the 0.6 limb-darkening weight (the extracted Fresnel Opacity is 1.0 and is
//   the material's opacity, not a darkening weight); the 0.65 phase mix; the
//   1.2 z component of the light vector; and the sign convention of the X/Y
//   light positions, which is inferred from UV-space positions and NOT
//   verified against the cooked graph.
// The phase vector may place the highlight low on the disc; confirm this in
// the visual QA capture.

uniform vec3 horizon_color = vec3(0.02, 0.03, 0.06);
uniform vec3 zenith_color = vec3(0.005, 0.008, 0.02);
uniform float sky_radiance_scale = 1.0;
uniform vec3 moon_direction = vec3(0.0, 1.0, 0.0);
uniform float moon_angular_radius = 0.0524;
uniform float moon_visible = 1.0;
uniform sampler2D moon_texture : source_color;
uniform vec3 moon_color = vec3(1.0, 1.0, 1.0);
uniform float moon_energy = 1.0;
uniform float moon_halo_strength = 0.0;
uniform float star_amount = 0.0;
uniform vec3 cloud_color = vec3(0.2, 0.2, 0.25);
uniform float cloud_haze = 0.0;
uniform float cloud_coverage = 0.45;
// APPROXIMATE warm SkyAtmosphere/fog veil. LINEAR radiance, uploaded before
// Environment.background_energy_multiplier; deliberately NOT multiplied by
// sky_radiance_scale (that scale belongs to the authored M_Sky gradient only).
uniform vec3 haze_color = vec3(0.0520, 0.0400, 0.0280);
uniform float haze_amount = 0.0;
uniform float haze_height_falloff = 0.0;

float _hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float _hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float _vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = _hash12(i);
	float b = _hash12(i + vec2(1.0, 0.0));
	float c = _hash12(i + vec2(0.0, 1.0));
	float d = _hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// R3 APPROXIMATE stand-in for cooked MI_VolumetricCloud_* (expressionless cooked graph).
float _fbm4(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
	for (int i = 0; i < 4; i++) {
		v += a * _vnoise2(p);
		p = rot * p * 2.03 + vec2(17.1, 31.7);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 moon_fwd = normalize(moon_direction);
	float up = dir.y;
	float grad_t = pow(clamp(1.0 - max(up, 0.0), 0.0, 1.0), 1.4);
	// Scale authored overall_color-crushed gradient for visual parity while keeping
	// WeatherVisuals.horizon_color_of / zenith_color_of untouched.
	vec3 h_scaled = horizon_color * sky_radiance_scale;
	vec3 z_scaled = zenith_color * sky_radiance_scale;
	if (sky_radiance_scale > 1.5) {
		z_scaled = max(z_scaled, h_scaled * vec3(0.08, 0.14, 0.32));
	}
	vec3 col = mix(z_scaled, h_scaled, grad_t);
	if (up < 0.0) {
		col = mix(h_scaled, h_scaled * 0.12, clamp(-up * 5.0, 0.0, 1.0));
	}

	// R3 APPROXIMATE procedural 4-octave FBM cloud wisps + horizon haze band
	// (cooked MI_VolumetricCloud_* materials have no recoverable shader graph).
	float cloud_alpha = 0.0;
	if (cloud_haze > 0.001 && up > -0.05) {
		vec2 cuv = dir.xz / (max(up, 0.0) + 0.18) * 0.45 + vec2(TIME * 0.003, TIME * 0.0015);
		vec2 warp = vec2(_fbm4(cuv * 0.7 + vec2(3.1, 7.4)), _fbm4(cuv * 0.7 + vec2(11.3, 2.9)));
		float n = _fbm4(cuv + (warp - 0.5) * 0.65);
		float lo = clamp(1.0 - cloud_coverage, 0.05, 0.92);
		float hi = clamp(1.05 - cloud_coverage * 0.5, lo + 0.08, 1.05);
		float horizon_fade = smoothstep(-0.02, 0.14, up);
		cloud_alpha = smoothstep(lo, hi, n) * horizon_fade * clamp(cloud_haze * 1.35, 0.0, 0.85);
		float moon_scatter = (moon_visible > 0.5) ? pow(max(dot(dir, moon_fwd), 0.0), 4.0) * 1.4 : 0.0;
		vec3 lit_cloud = cloud_color * (1.0 + moon_color * moon_scatter);
		col = mix(col, lit_cloud, cloud_alpha);
	}
	float band = pow(clamp(1.0 - abs(up), 0.0, 1.0), 3.0);
	col = mix(col, cloud_color, band * cloud_haze * 0.35);

	if (haze_amount > 0.001) {
		float hz = haze_amount * smoothstep(-0.06, 0.02, up);
		hz *= mix(1.0, 1.0 - clamp(up, 0.0, 1.0), clamp(haze_height_falloff, 0.0, 1.0));
		col = mix(col, haze_color, clamp(hz, 0.0, 1.0));
	}

	float cos_r = cos(moon_angular_radius);
	float cos_a = dot(dir, moon_fwd);
	bool disc = moon_visible > 0.5 && cos_a > cos_r;
	// Hoisted out of the `if (disc)` branch: derivatives under non-uniform
	// control flow are undefined exactly at the boundary pixels the AA is for.
	float aa_w = max(fwidth(cos_a) * 1.5, (1.0 - cos_r) * 0.02);
	if (moon_visible > 0.5 && moon_halo_strength > 0.0) {
		// R3 APPROXIMATE radial atmospheric moon halo + cloud edge scatter.
		// Applied before disc mix so the anti-aliased disc rim blends seamlessly into the halo.
		float ang = acos(clamp(cos_a, -1.0, 1.0));
		float halo = (exp(-ang * 11.0) * 0.32 + exp(-ang * 3.0) * 0.07) * moon_halo_strength;
		col += halo * moon_color * (0.75 + 0.65 * cloud_alpha);
	}
	if (disc) {
		vec3 fwd = moon_fwd;
		vec3 ref_up = abs(fwd.y) > 0.99 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
		vec3 tx = normalize(cross(fwd, ref_up));
		vec3 ty = cross(tx, fwd);
		float sin_r = max(sin(moon_angular_radius), 0.0001);
		vec2 off = vec2(dot(dir, tx), dot(dir, ty)) / sin_r;
		float r2 = clamp(dot(off, off), 0.0, 1.0);
		float nz = sqrt(max(1.0 - r2, 0.0));
		vec3 n = vec3(off, nz);
		float u = atan(n.x, max(n.z, 1e-6)) / 6.28318530718 + 0.5;
		vec2 muv = vec2(u, acos(clamp(n.y, -1.0, 1.0)) / 3.14159265359);
		vec3 alb = texture(moon_texture, muv).rgb;
		float fresnel = 0.22 + 0.78 * pow(1.0 - nz, 2.9);
		alb *= 1.0 - fresnel * 0.6;
		vec3 light_dir = normalize(vec3(0.26, -0.476, 1.2));
		float ndl = clamp((dot(n, light_dir) + 0.51) / 1.51, 0.0, 1.0);
		alb *= mix(1.0, ndl, 0.65) * 1.5;
		float edge = smoothstep(cos_r, cos_r + aa_w, cos_a);
		col = mix(col, alb * moon_color * moon_energy, edge);
	}

	if (star_amount > 0.001 && up > 0.0) {
		vec3 g = dir * 160.0;
		vec3 cell = floor(g);
		float h = _hash13(cell);
		float star = step(1.0 - star_amount * 0.08, h);
		vec3 f = fract(g) - 0.5;
		float tw = 0.75 + 0.25 * sin(TIME * (2.0 + h * 4.0) + h * 40.0);
		float s = star * smoothstep(0.25, 0.0, length(f)) * tw;
		if (disc) {
			s = 0.0;
		}
		float cloud_atten = (1.0 - clamp(cloud_alpha * 1.2, 0.0, 0.9)) * 0.38;
		col += vec3(0.9, 0.93, 1.0) * s * clamp(up * 3.0, 0.0, 1.0) * cloud_atten;
	}

	COLOR = col;
}
