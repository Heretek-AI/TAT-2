shader_type sky;
// TAT-2 real night sky. Gradient + moon disc + sparse stars + horizon cloud
// haze, all driven by the extracted BP_WeatherPreset_* JSON values (see
// weather_visuals.gd for the UE -> Godot value mapping).
//
// APPROXIMATIONS (labelled, no fake art): the star field is a procedural hash
// sparkle (no star catalogue was recovered from cooking); the cloud term is a
// horizon haze tinted by sky.cloud_color (the volumetric cloud materials were
// not recovered, only their color/opacity scalars); the moon disc samples a
// centered square of the real T_Moon_D lunar panorama because the cooked
// M_Moon / MI_Moon_Base materials kept their texture but no UV framing rect.

uniform vec3 horizon_color : source_color = vec3(0.02, 0.03, 0.06);
uniform vec3 zenith_color : source_color = vec3(0.005, 0.008, 0.02);
uniform vec3 moon_direction = vec3(0.0, 1.0, 0.0);
uniform float moon_angular_radius = 0.0524;
uniform float moon_visible = 1.0;
uniform sampler2D moon_texture : source_color;
uniform vec3 moon_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float moon_energy = 1.0;
uniform float star_amount = 0.0;
uniform vec3 cloud_color : source_color = vec3(0.2, 0.2, 0.25);
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
	if (disc) {
		vec3 fwd = normalize(moon_direction);
		vec3 ref_up = abs(fwd.y) > 0.99 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
		vec3 tx = normalize(cross(ref_up, fwd));
		vec3 ty = cross(fwd, tx);
		float sin_r = max(sin(moon_angular_radius), 0.0001);
		vec2 off = vec2(dot(dir, tx), dot(dir, ty)) / sin_r;
		vec2 uv = vec2(0.5) + off * 0.22;
		vec3 mtex = texture(moon_texture, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
		float edge = smoothstep(cos_r, mix(cos_r, 1.0, 0.92), cos_a);
		col = mix(col, mtex * moon_color * moon_energy, edge);
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
