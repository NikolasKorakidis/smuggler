#[compute]
#version 450
// Anemos - weather and cloud system for Godot.
// Copyright (c) 2026 Nikolas Korakidis. All rights reserved. See addons/anemos/LICENSE.md.
// The cloud engine: volumetric clouds ray-marched at half resolution with
// temporal reprojection.
//
// Up to three layers, each of its own CloudType (world/clouds/types): a
// weather map places them (heaps with blue sky between, or continuous sheets),
// a profile curve shapes them vertically, Perlin-Worley noise builds the
// billows and Worley detail erodes the edges (Schneider, Nubis 2015). Storm
// towers rise through the layers as cumulonimbus with anvils. Cells slowly
// grow and dissolve. Lighting after Hillaire (Frostbite 2016): light marched
// towards the sun (self-shadowing), multiple scattering by octaves, dual-lobe
// phase (silver lining), powder (dark edges), sky light from above and ground
// bounce below, lightning glowing inside; energy-conserving integration.
// Mode 1 renders the cloud shadow map instead (sunlight through the clouds).

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict writeonly image2D out_color;
layout(rg32f, set = 0, binding = 1) uniform restrict writeonly image2D out_depth;
layout(set = 0, binding = 2) uniform sampler2D hist_color;
layout(set = 0, binding = 3) uniform sampler2D hist_depth;
layout(set = 0, binding = 4) uniform sampler2D scene_depth;
layout(set = 0, binding = 5) uniform sampler3D shape_tex;
layout(set = 0, binding = 6) uniform sampler3D detail_tex;
layout(set = 0, binding = 7) uniform sampler2D weather_tex;
layout(r16f, set = 0, binding = 9) uniform restrict writeonly image2D shadow_img;
layout(set = 0, binding = 10) uniform sampler2D profile_tex;  // rows: layers 0-2, storm

const int LAYERS = 3;
const int MAX_STORMS = 8;
const int MAX_FLASHES = 4;

layout(set = 0, binding = 8, std430) restrict readonly buffer Params {
	mat4 inv_proj;
	mat4 cam;        // camera to world
	mat4 prev_vp;    // world to previous frame's clip
	vec4 offs;       // shape offset xz, detail offset xz (m, wind)
	vec4 offs2;      // weather map offset xz, lean xz (m per m of height)
	vec4 scales;     // shape tile, detail tile, weather tile (m), planet radius
	vec4 sun_dir;    // towards the sun (or moon), w = multiple-scattering strength
	vec4 sun_col;    // that light at cloud height (rgb)
	vec4 amb_top;    // sky light on cloud tops
	vec4 amb_bottom; // light from below (ground bounce, horizon)
	vec4 counts;     // storms, flashes, frame, max steps
	vec4 misc;       // field y, max distance, history weight, light steps
	vec4 evolve;     // evolution time, evolution strength
	vec4 lay_geo[LAYERS];  // bottom y, top y, coverage threshold, enabled
	vec4 lay_a[LAYERS];    // softness, erosion, billow (m), density
	vec4 lay_b[LAYERS];    // extinction, heaps (1) .. sheet (0), narrowing, base wobble (m)
	vec4 lay_c[LAYERS];    // top wobble (m), patchiness, scale, unused
	vec4 storm_a;          // the storm type, same packing
	vec4 storm_b;
	vec4 storm_c;
	vec4 storms[MAX_STORMS];    // x, z, radius, top y
	vec4 storms_b[MAX_STORMS];  // growth 0..1, anvil spread, base y, unused
	vec4 flashes[MAX_FLASHES];  // x, y, z, energy
} p;

layout(push_constant, std430) uniform Push {
	vec2 size;     // half-res output size (mode 0) or shadow map size (mode 1)
	vec2 full;     // full-res size
	vec4 shadow;   // shadow map: origin x, origin z, size (m), mode (0 view, 1 shadow map)
} pc;

float remap(float v, float a, float b, float c, float d) {
	return c + (v - a) * (d - c) / max(b - a, 1e-5);
}

float hash12(vec2 q) {
	vec3 p3 = fract(vec3(q.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Ray against a sphere centred at the origin: (near, far), far < 0 = miss.
vec2 sphere(vec3 o, vec3 d, float r) {
	float b = dot(o, d);
	float c = dot(o, o) - r * r;
	float h = b * b - c;
	if (h < 0.0) return vec2(-1.0, -1.0);
	h = sqrt(h);
	return vec2(-b - h, -b + h);
}

// Interval of the ray inside the shell between radii rb and rt.
vec2 shell(vec3 oc, vec3 d, float rb, float rt) {
	float r = length(oc);
	vec2 outer = sphere(oc, d, rt);
	vec2 inner = sphere(oc, d, rb);
	if (outer.y < 0.0) return vec2(-1.0);
	if (r < rb) {
		return vec2(inner.y, outer.y);
	} else if (r <= rt) {
		float exit = outer.y;
		if (inner.x > 0.0) exit = min(exit, inner.x);
		return vec2(0.0, exit);
	} else {
		if (outer.x < 0.0) return vec2(-1.0);
		float exit = inner.x > 0.0 ? inner.x : outer.y;
		return vec2(outer.x, exit);
	}
}

vec3 planet_c;  // planet centre (below the camera)

// Height above sea level on the curved planet (equals y near the camera).
float height_of(vec3 q) {
	return length(q - planet_c) - p.scales.w;
}

float profile(float h, int row) {
	return textureLod(profile_tex, vec2(clamp(h, 0.0, 1.0), (float(row) + 0.5) / 4.0), 0.0).r;
}

// Billowy cloud from coverage and a profile value: Perlin-Worley base,
// carved by coverage, edges eroded by Worley detail.
float cloud_shape(vec3 q, float above_base, float h, float cov, float prof, float erosion, float scale, bool detail) {
	vec3 sp = q + vec3(p.offs2.z, 0.0, p.offs2.w) * above_base;  // lean with the wind shear
	vec4 s = textureLod(shape_tex, (sp + vec3(p.offs.x, 0.0, p.offs.y)) / (p.scales.x * scale), 0.0);
	float low_fbm = s.g * 0.625 + s.b * 0.25 + s.a * 0.125;
	float base = remap(s.r, -(1.0 - low_fbm), 1.0, 0.0, 1.0) * prof;
	float c = clamp(remap(base, 1.0 - cov, 1.0, 0.0, 1.0), 0.0, 1.0) * cov;
	if (detail && c > 0.0) {
		vec3 dn = textureLod(detail_tex, (sp + vec3(p.offs.z, 0.0, p.offs.w)) / (p.scales.y * scale), 0.0).rgb;
		float hf = dn.r * 0.625 + dn.g * 0.25 + dn.b * 0.125;
		float m = mix(hf, 1.0 - hf, clamp(h * 6.0, 0.0, 1.0));  // wispy base, billowy top
		c = clamp(remap(c, m * erosion, 1.0, 0.0, 1.0), 0.0, 1.0);
	}
	return pow(c, 0.85);
}

// One layer's extinction (1/m) at a point.
float layer_sigma(int i, vec3 q, float hy, bool detail, inout float hfrac) {
	vec4 g = p.lay_geo[i];
	if (g.w < 0.5 || hy < g.x - 400.0 || hy > g.y + 400.0) return 0.0;
	vec4 a = p.lay_a[i];
	vec4 b = p.lay_b[i];
	vec4 c = p.lay_c[i];
	float heaps = b.y;
	vec3 o3 = vec3(p.offs.x, 0.0, p.offs.y);
	vec4 bn = textureLod(shape_tex, (q + o3) / (p.scales.x * 2.3) + 0.61 + float(i) * 0.17, 0.0);
	float base_y = g.x + (bn.g - 0.5) * b.w;
	// Warp the map lookup with 3D noise so sides bulge instead of being the
	// 2D map pulled straight up.
	vec3 wn = textureLod(shape_tex, (q + o3) / (p.scales.x * 1.7) + 0.37 + float(i) * 0.11, 0.0).gba;
	vec2 warp = (wn.xy - 0.5) * a.z;
	vec2 wuv = (q.xz * (1.0 - 0.25 * float(i)) + warp + p.offs2.xy + float(i) * vec2(9000.0, 4000.0)) / p.scales.z;
	vec4 wm = textureLod(weather_tex, wuv, 0.0);
	float top_y = g.y + ((bn.b - 0.5) * 0.5 + (wm.r - 0.5) * 0.9) * c.x;
	float h = (hy - base_y) / max(top_y - base_y, 1.0);
	if (h <= 0.0 || h >= 1.0) return 0.0;
	float field = mix(wm.g * 0.55 + wm.b * 0.35 + wm.a * 0.1, wm.r * 0.65 + wm.a * 0.2 + wm.g * 0.15, heaps);
	// Cells grow and dissolve slowly.
	float ev = textureLod(shape_tex, vec3((q.x + p.offs2.x) / 21000.0, p.evolve.x + float(i) * 0.31, (q.z + p.offs2.y) / 21000.0), 0.0).g;
	field += (ev - 0.5) * p.evolve.y * heaps;
	// Heaps narrow towards the top (domes) and round off at the base.
	float shrink = heaps * (b.z * smoothstep(0.25, 1.0, h) + 0.04 * (1.0 - smoothstep(0.0, 0.12, h)));
	float cov = smoothstep(g.z - a.x + shrink, g.z + a.x + shrink, field);
	if (cov <= 0.001) return 0.0;
	float dens = cloud_shape(q, hy - base_y, h, cov, profile(h, i), a.y, c.z, detail) * a.w;
	// Sheets thicker and thinner in patches: darker and lighter underneath.
	dens *= mix(1.0, mix(0.35, 1.45, smoothstep(0.2, 0.8, wm.b * 0.6 + wn.z * 0.4)), c.y);
	if (dens > 0.0) hfrac = h;
	return dens * b.x;
}

// Storm towers: narrow as they climb, turrets bulging, an anvil spreading
// under the tropopause.
float storm_sigma(vec3 q, float hy, bool detail, inout float hfrac) {
	float best = 0.0;
	for (int i = 0; i < int(p.counts.x); i++) {
		vec4 s = p.storms[i];
		float base_y = p.storms_b[i].z;
		float hs = (hy - base_y) / max(s.w - base_y, 1.0);
		if (hs <= 0.0 || hs >= 1.0) continue;
		float r = s.z * (1.0 - 0.3 * smoothstep(0.1, 0.75, hs) + p.storms_b[i].y * smoothstep(0.72, 0.92, hs));
		vec4 tn = textureLod(shape_tex, (q + vec3(p.offs.x, 0.0, p.offs.y)) / (p.scales.x * 0.9) + float(i) * 0.13, 0.0);
		r *= 0.62 + 0.62 * tn.g;
		float c = (1.0 - smoothstep(0.3 * r, r, distance(q.xz, s.xy))) * p.storms_b[i].x;
		if (c <= 0.001) continue;
		c = pow(c, mix(1.0, 0.5, smoothstep(0.7, 0.85, hs)));
		float d = min(cloud_shape(q, hy - base_y, hs, c, profile(hs, 3), p.storm_a.y, p.storm_c.z, detail) * p.storm_a.w, 1.5);
		if (d > best) {
			best = d;
			hfrac = hs;
		}
	}
	return best * p.storm_b.x;
}

// Extinction of all clouds at a point (1/m), and the height within its cloud.
float sigma_at(vec3 q, bool detail, out float hfrac) {
	float hy = height_of(q);
	hfrac = 0.5;
	float s = 0.0;
	for (int i = 0; i < LAYERS; i++) s = max(s, layer_sigma(i, q, hy, detail, hfrac));
	if (p.counts.x > 0.5) s = max(s, storm_sigma(q, hy, detail, hfrac));
	return s;
}

float hg(float mu, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (12.5663706 * pow(1.0 + g2 - 2.0 * g * mu, 1.5));
}

// Dual-lobe phase: strong forward scatter (silver lining) and a little back.
float phase(float mu, float k) {
	return mix(hg(mu, 0.8 * k), hg(mu, -0.25 * k), 0.25);
}

// Light at a cloud point: sun (self-shadowed, multiple scattering by
// octaves) plus sky light from above and ground bounce from below.
vec3 light_at(vec3 q, float sig, float h, float mu) {
	float tau = 0.0;
	float step_l = 40.0;
	vec3 lq = q;
	int ls = int(p.misc.w);
	for (int i = 0; i < ls; i++) {
		lq += p.sun_dir.xyz * step_l;
		float hh;
		tau += sigma_at(lq, i < 2, hh) * step_l;
		step_l *= 1.9;
	}
	float ms = 0.0;
	float a = 1.0;
	float b = 1.0;
	float c = 1.0;
	for (int k = 0; k < 3; k++) {
		ms += a * phase(mu, c) * exp(-tau * b);
		a *= p.sun_dir.w;
		b *= 0.5;
		c *= 0.5;
	}
	// Powder: the edges of dense cloud turned away from the light are darker.
	float powder = 1.0 - exp(-sig * 220.0);
	powder = mix(1.0, powder, 0.75 * (0.5 - 0.5 * mu) + 0.2);
	vec3 sun = p.sun_col.rgb * ms * powder * 12.5663706;
	float dn = clamp(sig / 0.07, 0.0, 1.0);
	vec3 amb = mix(p.amb_bottom.rgb, p.amb_top.rgb, smoothstep(0.0, 0.8, h)) * (1.0 - 0.5 * dn);
	return sun + amb;
}

vec3 flash_light(vec3 q) {
	vec3 l = vec3(0.0);
	for (int i = 0; i < int(p.counts.y); i++) {
		vec3 d = q - p.flashes[i].xyz;
		l += vec3(0.75, 0.8, 1.0) * p.flashes[i].w / (1.0 + dot(d, d) / (900.0 * 900.0));
	}
	return l;
}

float clouds_bottom() {
	float b = 1e9;
	for (int i = 0; i < LAYERS; i++) if (p.lay_geo[i].w > 0.5) b = min(b, p.lay_geo[i].x - p.lay_b[i].w);
	for (int i = 0; i < int(p.counts.x); i++) b = min(b, p.storms_b[i].z);
	return b;
}

float clouds_top() {
	float t = -1e9;
	for (int i = 0; i < LAYERS; i++) if (p.lay_geo[i].w > 0.5) t = max(t, p.lay_geo[i].y + p.lay_c[i].x);
	for (int i = 0; i < int(p.counts.x); i++) t = max(t, p.storms[i].w);
	return t;
}

// Shadow map: for each point of the plane just below the lowest cloud, how
// much sunlight gets through the clouds above it (towards the sun).
void shadow_map(ivec2 px) {
	vec2 xz = pc.shadow.xy + (vec2(px) + 0.5) / pc.size * pc.shadow.z;
	vec3 s = p.sun_dir.xyz;
	float bottom = clouds_bottom();
	float top = clouds_top();
	if (s.y < 0.03 || top < bottom) {
		imageStore(shadow_img, px, vec4(1.0));
		return;
	}
	vec3 b = vec3(xz.x, bottom - 50.0, xz.y);
	planet_c = vec3(b.x, -p.scales.w, b.z);  // flat here: height = y
	float len = min((top - b.y) / s.y, 20000.0);
	float dt = len / 20.0;
	float tau = 0.0;
	for (int i = 0; i < 20; i++) {
		float h;
		tau += sigma_at(b + s * dt * (float(i) + 0.5), false, h) * dt;
	}
	imageStore(shadow_img, px, vec4(exp(-tau * 0.6)));
}

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= int(pc.size.x) || px.y >= int(pc.size.y)) return;
	if (pc.shadow.w > 0.5) {
		shadow_map(px);
		return;
	}
	vec2 uv = (vec2(px) + 0.5) / pc.size;
	float depth = textureLod(scene_depth, uv, 0.0).r;
	bool sky = depth <= 0.0;
	vec4 v = p.inv_proj * vec4(uv * 2.0 - 1.0, sky ? 1e-6 : depth, 1.0);
	vec3 vp = v.xyz / v.w;
	float t_scene = sky ? 1e9 : length(vp);
	vec3 d = normalize(mat3(p.cam) * (vp / length(vp)));
	vec3 o = p.cam[3].xyz;
	float R = p.scales.w;
	planet_c = vec3(o.x, -R, o.z);
	vec3 oc = o - planet_c;
	float t_max = min(t_scene, p.misc.y);
	float jitter = fract(hash12(vec2(px)) + p.counts.z * 0.6180339);

	vec3 L = vec3(0.0);
	float T = 1.0;
	float dsum = 0.0;
	float wsum = 0.0;
	float bottom = clouds_bottom();
	float top = clouds_top();
	vec2 seg = top > bottom ? shell(oc, d, R + bottom, R + top) : vec2(-1.0);
	if (seg.y > 0.0 && seg.x < t_max) {
		float t0 = max(seg.x, 0.0);
		float t1 = min(seg.y, t_max);
		float mu = dot(d, p.sun_dir.xyz);
		float dt = clamp((t1 - t0) / p.counts.w, 30.0, 260.0);
		// Steps start fine near the camera (inside a cloud light dies within
		// tens of metres) and grow with distance.
		float t = t0 + clamp(t0 * 0.04, 10.0, dt) * jitter;
		for (int i = 0; i < 256; i++) {
			if (t >= t1 || T < 0.01) break;
			vec3 q = o + d * t;
			float h;
			float coarse = sigma_at(q, false, h);
			float step_now = clamp(t * 0.04, 10.0, dt) * (coarse > 0.0 ? 0.5 : 1.0) * (1.0 + t / 30000.0);
			if (coarse > 0.0) {
				float sig = sigma_at(q, true, h);
				if (sig > 1e-4) {
					vec3 S = (light_at(q, sig, h, mu) + flash_light(q)) * sig;
					float ts = exp(-sig * step_now);
					L += T * (S - S * ts) / sig;
					float w = T * (1.0 - ts);
					dsum += w * t;
					wsum += w;
					T *= ts;
				}
			}
			t += step_now;
		}
	}

	float cdepth = wsum > 1e-4 ? dsum / wsum : min(t_max, p.misc.y);
	vec4 cur = vec4(L, T);
	// Temporal reprojection: where was this cloud point last frame?
	vec3 world = o + d * cdepth;
	vec4 pc_prev = p.prev_vp * vec4(world, 1.0);
	vec2 puv = pc_prev.xy / pc_prev.w * 0.5 + 0.5;
	vec4 outc = cur;
	if (pc_prev.w > 0.0 && all(greaterThan(puv, vec2(0.0))) && all(lessThan(puv, vec2(1.0)))) {
		vec4 hcol = textureLod(hist_color, puv, 0.0);
		float hd = textureLod(hist_depth, puv, 0.0).r;
		float agree = 1.0 - smoothstep(0.25, 0.8, abs(hd - cdepth) / max(cdepth, 150.0));
		outc = mix(hcol, cur, mix(1.0, p.misc.z, agree));
	}
	imageStore(out_color, px, outc);
	imageStore(out_depth, px, vec4(cdepth, t_scene, 0.0, 0.0));
}
