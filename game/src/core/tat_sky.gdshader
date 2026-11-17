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
uniform vec3 moon_direction = vec3(0.0, 1.0, 0.0);
uniform float moon_angular_radius = 0.0524;
uniform float moon_visible = 1.0;
uniform sampler2D moon_texture : source_color;
uniform vec3 moon_color = vec3(1.0, 1.0, 1.0);
uniform float moon_energy = 1.0;
uniform float star_amount = 0.0;
uniform vec3 cloud_color = vec3(0.2, 0.2, 0.25);
uniform float cloud_haze = 0.0;

float _hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = dir.y;
	float grad_t = pow(clamp(1.0 - max(up, 0.0), 0.0, 1.0), 1.4);
	vec3 col = mix(zenith_color, horizon_color, grad_t);
	if (up < 0.0) {
		col = mix(horizon_color, horizon_color * 0.12, clamp(-up * 5.0, 0.0, 1.0));
	}
	// Cloud haze tint hugging the horizon; strength from sky.cloud_opacity.
	float band = pow(clamp(1.0 - abs(up), 0.0, 1.0), 3.0);
	col = mix(col, cloud_color, band * cloud_haze);

	float cos_r = cos(moon_angular_radius);
	float cos_a = dot(dir, normalize(moon_direction));
	bool disc = moon_visible > 0.5 && cos_a > cos_r;
	// Hoisted out of the `if (disc)` branch: derivatives under non-uniform
	// control flow are undefined exactly at the boundary pixels the AA is for.
	float aa_w = max(fwidth(cos_a) * 1.5, (1.0 - cos_r) * 0.02);
	if (disc) {
		vec3 fwd = normalize(moon_direction);
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
		col += vec3(0.9, 0.93, 1.0) * s * clamp(up * 3.0, 0.0, 1.0);
	}

	COLOR = col;
}
