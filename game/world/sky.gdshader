shader_type sky;
render_mode use_half_res_pass, use_quarter_res_pass;
// Physically based sky (single scattering, Rayleigh + Mie + ozone tint, plus
// an approximate multiple-scattering glow that carries twilight to -18°),
// computed at half resolution, with the sun disc, moon (with phase), stars,
// Milky Way, horizon airglow and a fair-weather cloud layer added at full
// resolution. TimeOfDay feeds the uniforms each frame.

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float sun_intensity = 22.0;
uniform float moon_intensity = 0.0;   // includes phase (illuminated fraction)
uniform float moon_phase = 0.5;       // 0 new, 0.5 full
uniform float star_intensity = 0.0;
uniform float camera_altitude = 200.0;
uniform float cloud_cover = 0.25;     // 0 clear .. 1 overcast
uniform float cloud_time = 0.0;
uniform vec3 sun_color = vec3(1.0);   // sunlight after the atmosphere (for clouds)
uniform vec3 ambient_color = vec3(0.4, 0.5, 0.7);
// NASA SVS Deep Star Maps 2020 "milkyway" layer (public domain), plate carrée
// in celestial coordinates, centred on RA 0h, RA increasing to the left.
// Encoded as linear = pow(texel, 2.2) * MILKYWAY_SCALE.
uniform sampler2D milkyway : source_color, filter_linear_mipmap, repeat_enable;
uniform mat3 celestial_to_world = mat3(1.0);
uniform float milkyway_intensity = 0.0;
// Light scattered more than once: keeps the sky glowing through twilight long
// after single scattering has gone dark (TimeOfDay sets the level from the
// sun's depression). night_glow is the moonless night sky (airglow, starlight).
uniform float twilight_level = 0.0;
uniform float night_glow = 6.0e-4;
const float MILKYWAY_SCALE = 0.40457495;

const float RE = 6360e3;
const float RA = 6420e3;
const vec3 BETA_R = vec3(5.8e-6, 13.5e-6, 33.1e-6);
const float BETA_M = 21e-6;
const vec3 BETA_OZONE = vec3(0.65e-6, 1.88e-6, 0.085e-6);
const float HR = 8000.0;
const float HM = 1200.0;
const float G = 0.76;

float ray_sphere(vec3 o, vec3 d, float r) {
	float b = dot(o, d);
	float c = dot(o, o) - r * r;
	float h = b * b - c;
	if (h < 0.0) return -1.0;
	return -b + sqrt(h);
}

vec3 scatter(vec3 dir, vec3 light, float intensity) {
	vec3 origin = vec3(0.0, RE + max(camera_altitude, 1.0), 0.0);
	float t_max = ray_sphere(origin, dir, RA);
	float t_ground = -1.0;
	{
		float b = dot(origin, dir);
		float c = dot(origin, origin) - RE * RE;
		float h = b * b - c;
		if (h >= 0.0 && -b - sqrt(h) > 0.0) t_ground = -b - sqrt(h);
	}
	if (t_ground > 0.0) t_max = t_ground;
	const int N = 14;
	const int L = 5;
	float seg = t_max / float(N);
	float mu = dot(dir, light);
	float phase_r = 3.0 / (16.0 * PI) * (1.0 + mu * mu);
	float phase_m = 3.0 / (8.0 * PI) * ((1.0 - G * G) * (1.0 + mu * mu)) / ((2.0 + G * G) * pow(1.0 + G * G - 2.0 * G * mu, 1.5));
	vec3 sum_r = vec3(0.0);
	vec3 sum_m = vec3(0.0);
	float od_r = 0.0;
	float od_m = 0.0;
	for (int i = 0; i < N; i++) {
		vec3 p = origin + dir * (seg * (float(i) + 0.5));
		float h = length(p) - RE;
		float hr = exp(-h / HR) * seg;
		float hm = exp(-h / HM) * seg;
		od_r += hr;
		od_m += hm;
		float tl = ray_sphere(p, light, RA);
		float sl = tl / float(L);
		float odl_r = 0.0;
		float odl_m = 0.0;
		bool lit = true;
		for (int j = 0; j < L; j++) {
			vec3 q = p + light * (sl * (float(j) + 0.5));
			float hq = length(q) - RE;
			if (hq < 0.0) { lit = false; break; }
			odl_r += exp(-hq / HR) * sl;
			odl_m += exp(-hq / HM) * sl;
		}
		if (lit) {
			vec3 tau = BETA_R * (od_r + odl_r) + BETA_M * 1.1 * (od_m + odl_m) + BETA_OZONE * (od_r + odl_r) * 1.5;
			vec3 att = exp(-tau);
			sum_r += att * hr;
			sum_m += att * hm;
		}
	}
	return intensity * (sum_r * BETA_R * phase_r + sum_m * BETA_M * phase_m);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float v = 0.0;
	for (int i = 0; i < 5; i++) {
		v += a * noise2(p);
		p = p * 2.03 + vec2(17.1, 9.3);
		a *= 0.5;
	}
	return v;
}

vec3 milky_way(vec3 d) {
	vec3 c = transpose(celestial_to_world) * d;  // world -> celestial
	float ra = atan(c.y, c.x);
	float dec = asin(clamp(c.z, -1.0, 1.0));
	vec2 uv = vec2(fract(0.5 - ra / (2.0 * PI)), 0.5 - dec / PI);
	// The sRGB hint already decodes the 2.2 gamma. One mip down smooths the
	// pixel-level grain of the faint Gaia stars into a glow.
	return textureLod(milkyway, uv, 1.0).rgb * MILKYWAY_SCALE;
}

// Keep twilight_sky() and night_sky() in step with TimeOfDay.
vec3 twilight_sky(vec3 d) {
	float depr = clamp(-degrees(asin(clamp(sun_dir.y, -1.0, 1.0))), 0.0, 18.0);
	float deep = depr / 14.0;
	vec3 fs = vec3(sun_dir.x, 0.0, sun_dir.z);
	fs = length(fs) > 1e-4 ? normalize(fs) : vec3(1.0, 0.0, 0.0);
	vec3 fd = vec3(d.x, 0.0, d.z);
	fd = length(fd) > 1e-4 ? normalize(fd) : fs;
	float toward = clamp(dot(fd, fs) * 0.5 + 0.5, 0.0, 1.0);
	float y = clamp(d.y, 0.0, 1.0);
	// Blue dome, a little paler low down, darker over the Earth's shadow.
	vec3 dome = vec3(0.32, 0.48, 1.0) * (0.75 + 0.5 * pow(1.0 - y, 3.0)) * mix(0.6, 1.0, toward);
	// Glow over where the sun went down, sinking and narrowing as it goes deeper.
	float spread = mix(0.35, 0.08, clamp(deep, 0.0, 1.0));
	float glow = pow(toward, mix(2.0, 6.0, clamp(deep, 0.0, 1.0))) * exp(-y / spread);
	vec3 glow_col = mix(vec3(1.0, 0.5, 0.22), vec3(0.75, 0.75, 0.85), clamp(depr / 12.0, 0.0, 1.0));
	float day_fade = 1.0 - smoothstep(0.0, 0.07, sun_dir.y);  // daylight already has its own glow
	return twilight_level * (dome + glow_col * glow * 3.0 * day_fade);
}

vec3 night_sky(vec3 d) {
	// Airglow is brighter towards the horizon (longer path through the glowing layer).
	return night_glow * vec3(0.55, 0.75, 1.0) * (1.0 + 1.5 * pow(clamp(1.0 - d.y, 0.0, 1.0), 4.0));
}

vec4 clouds(vec3 d, vec3 sky_col) {
	if (d.y <= 0.015 || cloud_cover <= 0.001) return vec4(0.0);
	// Project onto a layer 1.8 km above the camera.
	float t = (1800.0) / d.y;
	vec2 p = d.xz * t / 2600.0 + vec2(cloud_time * 0.004, cloud_time * 0.0015);
	float n = fbm(p) * 0.65 + fbm(p * 3.1 + 4.0) * 0.35;
	float cov = mix(0.72, 0.28, cloud_cover);
	float dens = smoothstep(cov, cov + 0.18, n);
	if (dens <= 0.0) return vec4(0.0);
	// Lit tops towards the sun, grey undersides, warm at low sun.
	float toward = pow(max(dot(normalize(vec3(d.x, 0.0, d.z)), normalize(vec3(sun_dir.x, 0.0, sun_dir.z))), 0.0), 2.0);
	float thick = smoothstep(cov, cov + 0.45, n);
	vec3 lit = sun_color * (0.65 + 0.35 * toward) * (1.0 - 0.55 * thick) + ambient_color * 0.55;
	float fade = smoothstep(0.015, 0.12, d.y);
	vec3 col = mix(sky_col, lit, 0.85);
	return vec4(col, dens * fade);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	if (AT_QUARTER_RES_PASS || AT_CUBEMAP_PASS) {
		// The atmosphere is a smooth gradient: quarter resolution is enough.
		// Below the horizon (past the edge of the map) show distant land in
		// haze: the horizon colour, a little darker looking further down.
		// Single scattering under-lights the last couple of degrees (real
		// horizons are pale from multiple scattering), so the lowest band
		// takes the colour of the sky just above it.
		vec3 dd = normalize(vec3(d.x, max(d.y, 0.035), d.z));
		vec3 c = scatter(dd, sun_dir, sun_intensity);
		c += scatter(dd, moon_dir, moon_intensity);  // moonlit sky
		c += twilight_sky(dd) + night_sky(dd);
		if (d.y < 0.0) c *= mix(1.0, 0.6, clamp(-d.y * 10.0, 0.0, 1.0));
		if (AT_CUBEMAP_PASS) {
			vec4 cl = clouds(d, c);
			c = mix(c, cl.rgb, cl.a);
		}
		COLOR = c;
		ALPHA = 1.0;
	} else if (AT_HALF_RES_PASS) {
		vec3 c = QUARTER_RES_COLOR.rgb;
		vec4 cl = clouds(d, c);  // soft, so half resolution is plenty
		COLOR = mix(c, cl.rgb, cl.a);
		ALPHA = 1.0;
	} else {
		vec3 c = HALF_RES_COLOR.rgb;
		float h = d.y;
		// Sun disc with limb darkening.
		float s = dot(d, sun_dir);
		float disc = smoothstep(0.99996, 0.99999, s);
		float limb = sqrt(max(1.0 - (1.0 - s) / (1.0 - 0.99996), 0.0));
		c += sun_color * sun_intensity * 30.0 * disc * (0.6 + 0.4 * limb) * step(0.0, h + 0.005);
		// Moon disc with phase (lit from the sun side) and faint earthshine.
		float m = dot(d, moon_dir);
		if (m > 0.99996 && h > -0.005) {
			vec3 right = normalize(cross(moon_dir, vec3(0.0, 1.0, 0.0)));
			vec3 up = cross(right, moon_dir);
			vec2 uv = vec2(dot(d - moon_dir, right), dot(d - moon_dir, up)) / 0.0089;
			float r2 = dot(uv, uv);
			if (r2 < 1.0) {
				vec3 nrm = vec3(uv, sqrt(1.0 - r2));
				vec3 to_sun = normalize(vec3(dot(sun_dir, right), dot(sun_dir, up), dot(sun_dir, moon_dir) * -1.0));
				float lit_m = smoothstep(-0.05, 0.1, dot(nrm, to_sun));
				float maria = 0.75 + 0.25 * fbm(uv * 3.0 + 5.0);
				c += vec3(0.95, 0.93, 0.88) * (lit_m * 1.2 * maria + 0.015) * step(0.001, moon_intensity + star_intensity);
			}
		}
		if (milkyway_intensity > 0.001 && h > -0.01) {
			float behind_cloud = clouds(d, vec3(0.0)).a;
			// Faint and grey-white to the eye (photos exaggerate the colour and
			// contrast): its brightest clouds are a few times the dark-sky glow
			// around them. Dimmer through the thick air low down.
			vec3 mw = milky_way(d);
			mw = mix(vec3(dot(mw, vec3(0.3, 0.5, 0.2))), mw, 0.35) * vec3(0.9, 0.93, 1.0);
			float ext = smoothstep(-0.01, 0.25, h);
			c += mw * milkyway_intensity * 0.012 * ext * (1.0 - behind_cloud);
		}
		COLOR = c;
	}
}
