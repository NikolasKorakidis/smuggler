#[compute]
#version 450
// Atmospheric fog for every pixel, integrated analytically along the view ray
// (exact for these density profiles, no ray marching):
//   haze      clear-air haze thinning with height (exponential)
//   fog deck  dense below its top, soft edge above (valleys fill, hills poke out)
//   rain      steady rain below the cloud base
//   shafts    rain curtains under storm cells (Gaussian columns, closed form with erf)
// Light: sky-lit in-scatter per medium plus forward scatter towards the sun.
// Runs on the HDR colour before transparents (rain streaks and glass stay sharp).

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_texture;

const int MAX_CELLS = 8;

layout(set = 0, binding = 2, std430) restrict readonly buffer Params {
	mat4 inv_proj;
	mat4 cam;           // camera to world
	vec4 haze;          // extinction at ref height (1/m), scale height (m), ref height y, sky distance (m)
	vec4 fog;           // extinction (1/m), full-density top y, zero-density top y, top undulation (m)
	vec4 rain;          // extinction (1/m), full-density top y, zero top y, unused
	vec4 haze_color;    // sky-lit in-scatter radiance: horizon towards the sun
	vec4 haze_color_away;  // ... and away from it
	vec4 fog_color;
	vec4 rain_color;
	vec4 shaft_color;
	vec4 sun_dir;       // xyz towards the sun, w = phase g
	vec4 sun_color;     // rgb forward-scatter scale, w unused
	vec4 fog_sun;       // rgb sunlight on the fog top, w unused
	vec4 counts;        // x = cells, y = debug mode, z = share of haze to add to the sky
	vec4 cells[MAX_CELLS];      // x, z, radius, peak extinction
	vec4 cell_tops[MAX_CELLS];  // x = shaft top y (cloud base)
} p;

layout(set = 0, binding = 3) uniform sampler2D cloud_color;  // half res: light, transmittance
layout(set = 0, binding = 4) uniform sampler2D cloud_depth;  // half res: cloud distance, scene distance

layout(push_constant, std430) uniform Push {
	vec2 size;
	float clouds_on;
	float pad;
} pc;

float hash12(vec2 q) {
	vec3 p3 = fract(vec3(q.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

float erf_approx(float x) {
	// Abramowitz & Stegun 7.1.26 (|error| < 1.5e-7)
	float s = sign(x);
	x = abs(x);
	float t = 1.0 / (1.0 + 0.3275911 * x);
	float y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-x * x);
	return s * y;
}

// The sky already contains clean-air haze: only the extra is added to sky pixels.
float haze_share = 1.0;

// Haze: sigma(y) = s0 exp(-(y - ref) / H)
float haze_tau(vec3 o, vec3 d, float t) {
	float s0 = p.haze.x * exp(clamp(-(o.y - p.haze.z) / p.haze.y, -60.0, 20.0)) * haze_share;
	float k = d.y / p.haze.y;
	if (abs(k * t) < 1e-3) {
		return s0 * t;
	}
	return s0 * (1.0 - exp(clamp(-k * t, -60.0, 20.0))) / k;
}

// Antiderivative of a slab profile (1 below a, falling linearly to 0 at b).
float slab_g(float y, float a, float b) {
	if (y <= a) return y;
	if (y >= b) return a + 0.5 * (b - a);
	float u = y - a;
	return a + u - u * u / (2.0 * (b - a));
}

float slab_profile(float y, float a, float b) {
	return 1.0 - clamp((y - a) / max(b - a, 1e-3), 0.0, 1.0);
}

float slab_tau(vec4 s, vec3 o, vec3 d, float t) {
	if (s.x <= 0.0) return 0.0;
	float dy = d.y * t;
	if (abs(dy) < 0.5) {
		return s.x * slab_profile(o.y + 0.5 * dy, s.y, s.z) * t;
	}
	return s.x * (slab_g(o.y + dy, s.y, s.z) - slab_g(o.y, s.y, s.z)) / d.y;
}

// Gaussian rain column, from the ground up to the cloud base.
float cell_tau(vec4 c, float top, vec3 o, vec3 d, float t) {
	float s0 = 0.0;
	float s1 = t;
	if (abs(d.y) > 1e-5) {
		float sb = (top - o.y) / d.y;
		if (d.y > 0.0) s1 = min(s1, sb); else s0 = max(s0, sb);
	} else if (o.y > top) {
		return 0.0;
	}
	if (s1 <= s0) return 0.0;
	float R = c.z;
	vec2 p0 = o.xz - c.xy;
	vec2 dh = d.xz;
	float L = length(dh);
	if (L < 1e-4) {
		return c.w * exp(-dot(p0, p0) / (R * R)) * (s1 - s0);
	}
	vec2 u = dh / L;
	float b = dot(p0, u);
	float c2 = max(dot(p0, p0) - b * b, 0.0);
	float k = exp(-c2 / (R * R)) * R * 0.88622693 / L;
	return c.w * k * (erf_approx((b + L * s1) / R) - erf_approx((b + L * s0) / R));
}

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(pc.size);
	if (px.x >= size.x || px.y >= size.y) return;
	vec2 uv = (vec2(px) + 0.5) / pc.size;
	float depth = texture(depth_texture, uv).r;
	bool sky = depth <= 0.0;  // reverse-Z: cleared sky is 0
	vec4 v = p.inv_proj * vec4(uv * 2.0 - 1.0, sky ? 1e-6 : depth, 1.0);
	vec3 vp = v.xyz / v.w;
	float t = length(vp);
	vec3 d = normalize(mat3(p.cam) * (vp / t));
	vec3 o = p.cam[3].xyz;
	float t_scene = sky ? 1e9 : t;
	if (sky) {
		t = p.haze.w;
		haze_share = p.counts.z;
	}

	// Clouds (half resolution): pick the samples whose scene depth matches
	// this pixel, so terrain edges stay sharp against cloud behind them.
	vec4 cloud = vec4(0.0, 0.0, 0.0, 1.0);
	float cloud_t = 0.0;
	if (pc.clouds_on > 0.5) {
		ivec2 hs = textureSize(cloud_color, 0);
		vec2 hp = uv * vec2(hs) - 0.5;
		ivec2 h0 = ivec2(floor(hp));
		vec2 f = fract(hp);
		vec4 acc = vec4(0.0);
		float dacc = 0.0;
		float wacc = 0.0;
		for (int j = 0; j < 2; j++) {
			for (int i = 0; i < 2; i++) {
				ivec2 c = clamp(h0 + ivec2(i, j), ivec2(0), hs - 1);
				vec2 dd = texelFetch(cloud_depth, c, 0).rg;
				float bw = (i == 0 ? 1.0 - f.x : f.x) * (j == 0 ? 1.0 - f.y : f.y);
				float rel = abs(dd.g - t_scene) / max(min(dd.g, t_scene), 1.0);
				float w = bw / (0.02 + rel * rel * 50.0) + 1e-6;
				acc += w * texelFetch(cloud_color, c, 0);
				dacc += w * dd.r;
				wacc += w;
			}
		}
		cloud = acc / wacc;
		cloud_t = dacc / wacc;
		if (sky && cloud.a < 0.999) t = max(t, cloud_t);
	}

	// Fog top undulates gently: shift it by noise where this ray meets it.
	vec4 fog = p.fog;
	float lumps = 1.0;  // sunlit and shaded bulges on the fog top
	if (fog.x > 0.0 && fog.w > 0.0) {
		float top = 0.5 * (fog.y + fog.z);
		float s_top = abs(d.y) > 1e-4 ? clamp((top - o.y) / d.y, 0.0, t) : 0.0;
		vec2 q = (o.xz + d.xz * s_top) / 450.0;
		float n = noise2(q) * 0.65 + noise2(q * 3.1 + 7.0) * 0.35;
		fog.yz += (n - 0.5) * 2.0 * fog.w;
		// Slope of the bulges towards the sun from the noise gradient.
		vec2 e = vec2(0.05, 0.0);
		vec2 grad = vec2(noise2(q + e.xy) - noise2(q - e.xy), noise2(q + e.yx) - noise2(q - e.yx)) / 0.1;
		vec2 sun_h = normalize(p.sun_dir.xz + 1e-4);
		float detail = noise2(q * 9.0 + 3.0);
		lumps = clamp(1.0 + 0.5 * dot(grad, sun_h) * (1.0 - 0.5 * p.sun_dir.y) + 0.25 * (detail - 0.5), 0.55, 1.45);
	}

	// Rain curtains under storm cells: each is composited as a layer at its
	// closest approach along the ray, so haze in front of it veils it and haze
	// behind it is hidden by it.
	float cs[MAX_CELLS + 1];
	float ct[MAX_CELLS + 1];  // curtain optical depth, or -1 for the cloud layer
	int nc = 0;
	for (int i = 0; i < int(p.counts.x); i++) {
		float tau = cell_tau(p.cells[i], p.cell_tops[i].x, o, d, t);
		if (tau < 1e-3) continue;
		vec2 p0 = o.xz - p.cells[i].xy;
		float L = max(length(d.xz), 1e-4);
		float sc = clamp(-dot(p0, d.xz / L) / L, 0.0, t);
		// insertion sort, far to near
		int j = nc;
		while (j > 0 && cs[j - 1] < sc) {
			cs[j] = cs[j - 1];
			ct[j] = ct[j - 1];
			j--;
		}
		cs[j] = sc;
		ct[j] = tau;
		nc++;
	}
	if (cloud.a < 0.999) {
		float sc = clamp(cloud_t, 0.0, t);
		int j = nc;
		while (j > 0 && cs[j - 1] < sc) {
			cs[j] = cs[j - 1];
			ct[j] = ct[j - 1];
			j--;
		}
		cs[j] = sc;
		ct[j] = -1.0;
		nc++;
	}

	vec4 col = imageLoad(color_image, px);
	if (p.counts.y > 0.5) {
		float th = haze_tau(o, d, t);
		float tf = slab_tau(fog, o, d, t);
		float tc = 0.0;
		for (int i = 0; i < nc; i++) tc += max(ct[i], 0.0);
		if (p.counts.y > 1.5) {  // debug 2: shafts, haze, fog deck amounts
			imageStore(color_image, px, vec4(1.0 - exp(-tc), 1.0 - exp(-th), 1.0 - exp(-tf), 1.0));
		} else {  // debug 1: distance thresholds 100 m / 1 km / 10 km
			imageStore(color_image, px, vec4(step(100.0, t), step(1000.0, t), step(10000.0, t), 1.0));
		}
		return;
	}

	// Fog is lit from above: bright white on top in sunshine, dimmer deep inside.
	vec3 fog_lit = p.fog_color.rgb;
	if (fog.x > 0.0) {
		float s_in = min(t, 1.0 / max(fog.x, 1e-5));  // most light comes from ~1 optical depth in
		float below = max(0.5 * (fog.y + fog.z) - (o.y + d.y * s_in), 0.0);
		float k = exp(-fog.x * below * 0.35);
		fog_lit = (p.fog_color.rgb * (0.55 + 0.45 * k) + p.fog_sun.rgb * k) * (o.y > fog.y ? lumps : 1.0);
	}
	// Forward scatter towards the sun (Henyey-Greenstein, relative to isotropic):
	// the bright glow in fog and haze around the sun. Rain scatters less.
	float g = p.sun_dir.w;
	float mu = dot(d, p.sun_dir.xyz);
	float hg = (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * mu, 1.5);

	// Haze takes the colour of the horizon sky in the direction you look.
	vec3 dh = vec3(d.x, 0.0, d.z);
	vec3 sh = vec3(p.sun_dir.x, 0.0, p.sun_dir.z);
	float towards = (length(dh) > 1e-4 && length(sh) > 1e-4) ? dot(normalize(dh), normalize(sh)) * 0.5 + 0.5 : 0.5;
	vec3 haze_col = mix(p.haze_color_away.rgb, p.haze_color.rgb, towards * towards);

	// March the breakpoints from far to near: haze/fog/rain segment, then a curtain.
	float far_t = t;
	float h_far = haze_tau(o, d, far_t);
	float f_far = slab_tau(fog, o, d, far_t);
	float r_far = slab_tau(p.rain, o, d, far_t);
	for (int i = 0; i <= nc; i++) {
		float near_t = i < nc ? cs[i] : 0.0;
		float h_near = near_t > 0.0 ? haze_tau(o, d, near_t) : 0.0;
		float f_near = near_t > 0.0 ? slab_tau(fog, o, d, near_t) : 0.0;
		float r_near = near_t > 0.0 ? slab_tau(p.rain, o, d, near_t) : 0.0;
		float th = max(h_far - h_near, 0.0);
		float tf = max(f_far - f_near, 0.0);
		float tr = max(r_far - r_near, 0.0);
		float seg = th + tf + tr;
		if (seg > 1e-5) {
			vec3 lit = (th * haze_col + tf * fog_lit + tr * p.rain_color.rgb) / seg;
			lit += p.sun_color.rgb * hg * (th + tf + 0.5 * tr) / seg;
			float trans = exp(-seg);
			col.rgb = col.rgb * trans + lit * (1.0 - trans);
		}
		if (i < nc) {
			if (ct[i] < 0.0) {
				col.rgb = col.rgb * cloud.a + cloud.rgb;  // the clouds, at their distance
			} else {
				float tc = exp(-ct[i]);
				col.rgb = col.rgb * tc + p.shaft_color.rgb * (1.0 - tc);
			}
		}
		h_far = h_near;
		f_far = f_near;
		r_far = r_near;
	}
	imageStore(color_image, px, col);
}
