shader_type sky;
// Time-of-day sky driven by TimeOfDay: gradient, sun glow and disc, stars
// that fade in after dusk, and a moon disc. Colours are set per frame.

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform vec3 zenith_color : source_color = vec3(0.15, 0.35, 0.75);
uniform vec3 horizon_color : source_color = vec3(0.65, 0.75, 0.88);
uniform vec3 ground_color : source_color = vec3(0.25, 0.27, 0.3);
uniform vec3 glow_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float glow_strength = 0.4;
uniform float sun_brightness = 25.0;
uniform float star_intensity = 0.0;
uniform float moon_brightness = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col;
	if (h >= 0.0) {
		col = mix(zenith_color, horizon_color, pow(1.0 - h, 4.0));
	} else {
		col = mix(horizon_color, ground_color, clamp(-h * 6.0, 0.0, 1.0));
	}
	float s = max(dot(d, sun_dir), 0.0);
	col += glow_color * glow_strength * (pow(s, 6.0) * 0.5 + pow(s, 48.0) * 1.5);
	float disc = smoothstep(0.99985, 0.99992, s);
	col += glow_color * sun_brightness * disc * step(-0.01, h);
	if (star_intensity > 0.001 && h > 0.0) {
		vec3 g = d * 300.0;
		vec3 cell = floor(g);
		float r = hash(cell);
		if (r > 0.9965) {
			float dist = length(g - (cell + 0.5));
			float b = smoothstep(0.45, 0.0, dist) * (0.35 + 0.65 * (r - 0.9965) / 0.0035);
			col += vec3(b) * star_intensity * smoothstep(0.0, 0.15, h);
		}
	}
	float m = dot(d, moon_dir);
	col += vec3(0.88, 0.9, 1.0) * moon_brightness * smoothstep(0.99975, 0.99985, m) * step(0.0, h);
	COLOR = col;
}
