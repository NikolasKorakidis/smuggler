#[compute]
#version 450
// Volumetric clouds, ray-marched at half resolution with temporal reprojection.
// Shapes after Schneider (Nubis, SIGGRAPH 2015): a weather map places the
// clouds (cumulus cells with blue sky between, stratus sheets, storm towers),
// a height profile per cloud type shapes them (flat base and dome, sheet,
// tower with anvil), Perlin-Worley noise builds the billows and Worley detail
// erodes their edges. Lighting after Hillaire (Frostbite 2016): light marched
// towards the sun (self-shadowing), multiple scattering by octaves, dual-lobe
// phase (silver lining), powder (dark edges), sky light from above and
// ground bounce from below, lightning glowing inside; energy-conserving
// integration. Output: in-scattered light (rgb), transmittance (a), and the
// cloud's mean distance (for haze in front of it and reprojection).

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict writeonly image2D out_color;
layout(rg32f, set = 0, binding = 1) uniform restrict writeonly image2D out_depth;
layout(set = 0, binding = 2) uniform sampler2D hist_color;
layout(set = 0, binding = 3) uniform sampler2D hist_depth;
layout(set = 0, binding = 4) uniform sampler2D scene_depth;
layout(set = 0, binding = 5) uniform sampler3D shape_tex;
layout(set = 0, binding = 6) uniform sampler3D detail_tex;
layout(set = 0, binding = 7) uniform sampler2D weather_tex;
layout(r16f, set = 0, binding = 9) uniform restrict writeonly image2D shadow_img;  // sunlight through the clouds

const int MAX_STORMS = 8;
const int MAX_FLASHES = 4;

layout(set = 0, binding = 8, std430) restrict readonly buffer Params {
	mat4 inv_proj;
	mat4 cam;        // camera to world
	mat4 prev_vp;    // world to previous frame's clip
	vec4 low;        // bottom y, top y, extinction (1/m), cumulus(0.5)..stratus(0) type
	vec4 cov;        // coverage threshold, softness, edge erosion, overall density
	vec4 mid;        // bottom y, top y, coverage threshold, extinction
	vec4 offs;       // shape offset xz, detail offset xz (m, wind)
	vec4 offs2;      // weather map offset xz, wind shear xz (m of drift per m of height)
	vec4 scales;     // shape tile, detail tile, weather tile (m), planet radius
	vec4 sun_dir;    // towards the sun, w = multiple-scattering strength
	vec4 sun_col;    // sunlight reaching the clouds (rgb), w = moon/sun lobe g
	vec4 amb_top;    // sky light on cloud tops
	vec4 amb_bottom; // light from below (ground bounce, horizon)
	vec4 counts;     // storms, flashes, frame, max steps
	vec4 misc;       // field y, max distance, history weight, light steps
	vec4 storms[MAX_STORMS];    // x, z, radius, top y
	vec4 storms_b[MAX_STORMS];  // growth 0..1, anvil spread, unused, unused
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
	if (r < rb) {           // below the layer: from the inner sphere out to the outer one
		return vec2(inner.y, outer.y);
	} else if (r <= rt) {   // inside: until leaving the top or reaching the bottom
		float exit = outer.y;
		if (inner.x > 0.0) exit = min(exit, inner.x);
		return vec2(0.0, exit);
	} else {                // above: enter at the top
		if (outer.x < 0.0) return vec2(-1.0);
		float exit = inner.x > 0.0 ? inner.x : outer.y;
		return vec2(outer.x, exit);
	}
}

// Height profiles (0 at base .. 1 at top of the layer) by type:
// 0 stratus sheet, 0.5 cumulus (flat base, dome), 1 cumulonimbus (tower).
float profile(float h, float t) {
	float st = smoothstep(0.0, 0.12, h) * (1.0 - smoothstep(0.55, 1.0, h));
	float cu = smoothstep(0.0, 0.07, h) * (1.0 - smoothstep(0.3, 1.0, h));
	float cb = smoothstep(0.0, 0.012, h) * (1.0 - smoothstep(0.8, 1.0, h));  // flat dark base
	return t < 0.5 ? mix(st, cu, t * 2.0) : mix(cu, cb, (t - 0.5) * 2.0);
}

vec3 planet_c;  // planet centre (below the camera)

// Height above sea level on the curved planet (equals y near the camera).
float height_of(vec3 q) {
	return length(q - planet_c) - p.scales.w;
}

// Billowy cloud from coverage and a height profile: Perlin-Worley base,
// carved by coverage, edges eroded by Worley detail (Schneider 2015).
float cloud_shape(vec3 q, float hy, float h, float cov, float t, bool detail) {
	vec3 sp = q + vec3(p.offs2.z, 0.0, p.offs2.w) * (hy - p.low.x);  // lean with the wind shear
	vec4 s = textureLod(shape_tex, (sp + vec3(p.offs.x, 0.0, p.offs.y)) / p.scales.x, 0.0);
	float low_fbm = s.g * 0.625 + s.b * 0.25 + s.a * 0.125;
	float base = remap(s.r, -(1.0 - low_fbm), 1.0, 0.0, 1.0);
	base *= profile(h, t);
	float c = clamp(remap(base, 1.0 - cov, 1.0, 0.0, 1.0), 0.0, 1.0) * cov;
	if (detail && c > 0.0) {
		vec3 dn = textureLod(detail_tex, (sp + vec3(p.offs.z, 0.0, p.offs.w)) / p.scales.y, 0.0).rgb;
		float hf = dn.r * 0.625 + dn.g * 0.25 + dn.b * 0.125;
		// Wispy at the base, billowy higher up.
		float m = mix(hf, 1.0 - hf, clamp(h * 6.0, 0.0, 1.0));
		c = clamp(remap(c, m * p.cov.z, 1.0, 0.0, 1.0), 0.0, 1.0);
	}
	return pow(c, 0.85);
}

// Cloud density at a point of the low layer (0..~1): the layer's clouds and
// any storm towers (each with its own height), whichever is denser.
float density_low(vec3 q, bool detail, out float hfrac) {
	float hy = height_of(q);
	hfrac = 0.0;
	float dens = 0.0;
	// Layer clouds. The base undulates (more for stratus sheets).
	vec4 bn = textureLod(shape_tex, (q + vec3(p.offs.x, 0.0, p.offs.y)) / (p.scales.x * 2.3) + 0.61, 0.0);
	float base_y = p.low.x + (bn.g - 0.5) * mix(220.0, 70.0, p.low.w * 2.0);
	float t_cu = p.low.w;  // 0.5 cumulus .. 0 stratus
	// Warp the map lookup with 3D noise so cloud sides bulge instead of
	// being the 2D map pulled straight up.
	vec3 wn = textureLod(shape_tex, (q + vec3(p.offs.x, 0.0, p.offs.y)) / (p.scales.x * 1.7) + 0.37, 0.0).gba;
	vec2 warp = (wn.xy - 0.5) * mix(150.0, 520.0, t_cu * 2.0);
	vec4 wm = textureLod(weather_tex, (q.xz + warp + p.offs2.xy) / p.scales.z, 0.0);
	// Sheet tops billow in cells (seen from above: a lumpy white surface).
	float top_y = p.low.y + ((bn.b - 0.5) * 0.5 + (wm.r - 0.5) * 0.9) * mix(320.0, 0.0, t_cu * 2.0);
	float h = (hy - base_y) / max(top_y - base_y, 1.0);
	if (h > 0.0 && h < 1.0 && p.cov.x < 1.5) {
		float field = mix(wm.g * 0.55 + wm.b * 0.35 + wm.a * 0.1, wm.r * 0.65 + wm.a * 0.2 + wm.g * 0.15, t_cu * 2.0);
		// Cumulus narrow towards the top (domes) and round off at the base.
		float shrink = t_cu * 2.0 * (0.14 * smoothstep(0.25, 1.0, h) + 0.04 * (1.0 - smoothstep(0.0, 0.12, h)));
		float cov = smoothstep(p.cov.x - p.cov.y + shrink, p.cov.x + p.cov.y + shrink, field);
		if (cov > 0.001) {
			dens = cloud_shape(q, hy, h, cov, t_cu, detail);
			// Sheets vary in thickness: darker and lighter patches underneath.
			dens *= mix(mix(0.35, 1.45, smoothstep(0.2, 0.8, wm.b * 0.6 + wn.z * 0.4)), 1.0, t_cu * 2.0);
			hfrac = h;
		}
	}
	// Storm towers: narrow as they climb, anvil spreading under the tropopause.
	for (int i = 0; i < int(p.counts.x); i++) {
		vec4 s = p.storms[i];
		float hs = (hy - p.low.x) / max(s.w - p.low.x, 1.0);
		if (hs <= 0.0 || hs >= 1.0) continue;
		float r = s.z * (1.0 - 0.3 * smoothstep(0.1, 0.75, hs) + p.storms_b[i].y * smoothstep(0.72, 0.92, hs));
		// Turrets: the outline bulges in and out, differently at every height.
		vec4 tn = textureLod(shape_tex, (q + vec3(p.offs.x, 0.0, p.offs.y)) / (p.scales.x * 0.9) + float(i) * 0.13, 0.0);
		r *= 0.62 + 0.62 * tn.g;
		float c = (1.0 - smoothstep(0.3 * r, r, distance(q.xz, s.xy))) * p.storms_b[i].x;
		if (c <= 0.001) continue;
		c = pow(c, mix(1.0, 0.5, smoothstep(0.7, 0.85, hs)));  // anvil fills out
		float ds = min(cloud_shape(q, hy, hs, c, 1.0, detail) * 2.5, 1.5);  // storm cloud is very dense
		if (ds > dens) {
			dens = ds;
			hfrac = hs;
		}
	}
	return dens * p.cov.w;
}

// Thin mid-level layer (altocumulus/altostratus): cheaper, flatter.
float density_mid(vec3 q) {
	float hy = height_of(q);
	float h = (hy - p.mid.x) / max(p.mid.y - p.mid.x, 1.0);
	if (h <= 0.0 || h >= 1.0) return 0.0;
	vec4 wm = textureLod(weather_tex, (q.xz * 0.7 + p.offs2.xy * 1.3 + vec2(9000.0, 4000.0)) / p.scales.z, 0.0);
	float field = wm.b * 0.5 + wm.a * 0.3 + wm.g * 0.2;
	float cov = smoothstep(p.mid.z - 0.06, p.mid.z + 0.06, field);
	if (cov <= 0.001) return 0.0;
	vec4 s = textureLod(shape_tex, (q + vec3(p.offs.x, 0.0, p.offs.y) * 1.5) / (p.scales.x * 0.5), 0.0);
	float base = remap(s.r, -(1.0 - s.b), 1.0, 0.0, 1.0) * smoothstep(0.0, 0.3, h) * (1.0 - smoothstep(0.5, 1.0, h));
	return clamp(remap(base, 1.0 - cov, 1.0, 0.0, 1.0), 0.0, 1.0) * cov;
}

float hg(float mu, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (12.5663706 * pow(1.0 + g2 - 2.0 * g * mu, 1.5));
}

// Dual-lobe phase: strong forward scatter (silver lining) and a little back.
float phase(float mu, float k) {
	return mix(hg(mu, 0.8 * k), hg(mu, -0.25 * k), 0.25);
}

// Light reaching a point of the low layer from the sun (self-shadowed,
// multiple scattering by octaves) plus sky light and ground bounce.
vec3 light_at(vec3 q, float dens, float h, float mu) {
	float tau = 0.0;
	float step_l = 40.0;
	vec3 lq = q;
	int ls = int(p.misc.w);
	for (int i = 0; i < ls; i++) {
		lq += p.sun_dir.xyz * step_l;
		float hh;
		tau += density_low(lq, i < 2, hh) * step_l;
		step_l *= 1.9;
	}
	tau *= p.low.z;
	// Multiple scattering (Hillaire 2016): each octave scatters more, is
	// attenuated less and spreads wider.
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
	// Powder: the edges of dense cloud turned away from the sun are darker.
	float powder = 1.0 - exp(-dens * p.low.z * 220.0);
	powder = mix(1.0, powder, 0.75 * (0.5 - 0.5 * mu) + 0.2);
	vec3 sun = p.sun_col.rgb * ms * powder * 12.5663706;
	// Sky light: much stronger on the tops; the base sees mostly the darker ground.
	vec3 amb = mix(p.amb_bottom.rgb, p.amb_top.rgb, smoothstep(0.0, 0.8, h)) * (1.0 - 0.5 * dens);
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

// Shadow map: for each point of the cloud-base plane, how much sunlight
// gets through the clouds above it (towards the sun).
void shadow_map(ivec2 px) {
	vec2 xz = pc.shadow.xy + (vec2(px) + 0.5) / pc.size * pc.shadow.z;
	vec3 s = p.sun_dir.xyz;
	if (s.y < 0.03) {
		imageStore(shadow_img, px, vec4(1.0));
		return;
	}
	vec3 b = vec3(xz.x, p.low.x - 100.0, xz.y);
	planet_c = vec3(b.x, -p.scales.w, b.z);  // flat here: height = y
	float top = p.low.y;
	for (int i = 0; i < int(p.counts.x); i++) top = max(top, p.storms[i].w);
	float len = (top - b.y) / s.y;
	float dt = len / 16.0;
	float tau = 0.0;
	for (int i = 0; i < 16; i++) {
		float h;
		tau += density_low(b + s * dt * (float(i) + 0.5), false, h) * dt;
	}
	imageStore(shadow_img, px, vec4(exp(-tau * p.low.z * 0.6)));
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

	// Low layer (and storm towers above it).
	float top = p.low.y;
	for (int i = 0; i < int(p.counts.x); i++) top = max(top, p.storms[i].w);
	vec2 seg = shell(oc, d, R + p.low.x, R + top);
	if (seg.y > 0.0 && seg.x < t_max && p.cov.w > 0.0) {
		float t0 = max(seg.x, 0.0);
		float t1 = min(seg.y, t_max);
		float mu = dot(d, p.sun_dir.xyz);
		int steps = int(p.counts.w);
		float span = t1 - t0;
		float dt = clamp(span / float(steps), 30.0, 260.0);
		// Steps start fine near the camera (inside a cloud light dies within
		// tens of metres) and grow with distance.
		float t = t0 + clamp(t0 * 0.04, 10.0, dt) * jitter;
		int empty = 0;
		for (int i = 0; i < 220; i++) {
			if (t >= t1 || T < 0.01) break;
			vec3 q = o + d * t;
			float h;
			// Cheap look first; full detail and a finer step once inside a cloud.
			float coarse = density_low(q, false, h);
			float step_now = clamp(t * 0.04, 10.0, dt) * (coarse > 0.0 ? 0.5 : 1.0) * (1.0 + t / 30000.0);
			if (coarse > 0.0) {
				float dens = density_low(q, true, h);
				if (dens > 0.002) {
					float sig = dens * p.low.z;
					vec3 S = (light_at(q, dens, h, mu) + flash_light(q)) * sig;
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
	// Mid layer: a thin sheet, a few samples, lit simply (no self-shadow march).
	if (p.mid.y > p.mid.x && T > 0.01) {
		vec2 sm = shell(oc, d, R + p.mid.x, R + p.mid.y);
		if (sm.y > 0.0 && sm.x < t_max) {
			float t0 = max(sm.x, 0.0);
			float t1 = min(sm.y, t_max);
			float dt = (t1 - t0) / 12.0;
			float mu = dot(d, p.sun_dir.xyz);
			for (int i = 0; i < 12; i++) {
				float t = t0 + dt * (float(i) + jitter);
				vec3 q = o + d * t;
				float dens = density_mid(q);
				if (dens > 0.002) {
					float sig = dens * p.mid.w;
					vec3 S = (p.sun_col.rgb * phase(mu, 0.7) * 12.5663706 * 0.8 + p.amb_top.rgb * 0.9) * sig;
					float ts = exp(-sig * dt);
					L += T * (S - S * ts) / sig;
					float w = T * (1.0 - ts);
					dsum += w * t;
					wsum += w;
					T *= ts;
				}
			}
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
		vec4 h = textureLod(hist_color, puv, 0.0);
		float hd = textureLod(hist_depth, puv, 0.0).r;
		float agree = 1.0 - smoothstep(0.25, 0.8, abs(hd - cdepth) / max(cdepth, 150.0));
		float w = mix(1.0, p.misc.z, agree);
		outc = mix(h, cur, w);
	}
	imageStore(out_color, px, outc);
	imageStore(out_depth, px, vec4(cdepth, t_scene, 0.0, 0.0));
}
