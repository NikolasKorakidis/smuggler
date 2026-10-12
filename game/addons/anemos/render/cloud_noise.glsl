#[compute]
#version 450
// Anemos - weather and cloud system for Godot.
// Copyright (c) 2026 Nikolas Korakidis. All rights reserved. See addons/anemos/LICENSE.md.
// Tileable 3D noise for the clouds, generated once at start.
// mode 0 (shape, 128^3): R = Perlin-Worley, G/B/A = Worley fBm at 4/8/16 cells
// mode 1 (detail, 32^3):  R/G/B = Worley fBm at 4/8/16 cells
// (Schneider 2015 / Hillaire's tileable volume noise.)

layout(local_size_x = 4, local_size_y = 4, local_size_z = 4) in;
layout(rgba8, set = 0, binding = 0) uniform restrict writeonly image3D out_tex;

layout(push_constant, std430) uniform Push {
	int size;
	int mode;
	int pad0;
	int pad1;
} pc;

uint hash3(uvec3 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * v.z;
	v.y += v.z * v.x;
	v.z += v.x * v.y;
	v ^= v >> 16u;
	v.x += v.y * v.z;
	v.y += v.z * v.x;
	v.z += v.x * v.y;
	return v.x ^ v.y ^ v.z;
}

vec3 rand3(ivec3 c, int seed) {
	uint h = hash3(uvec3(c + ivec3(seed * 101, seed * 37, seed * 211)));
	uint h2 = hash3(uvec3(h, h * 3u + 1u, h * 7u + 5u));
	return vec3(float(h & 1023u), float((h >> 10) & 1023u), float(h2 & 1023u)) / 1023.0;
}

// Worley (cellular) noise, tiling every `cells`: 1 at feature points, 0 far away.
float worley(vec3 p, int cells, int seed) {
	vec3 q = p * float(cells);
	ivec3 base = ivec3(floor(q));
	float best = 1e9;
	for (int z = -1; z <= 1; z++)
	for (int y = -1; y <= 1; y++)
	for (int x = -1; x <= 1; x++) {
		ivec3 c = base + ivec3(x, y, z);
		ivec3 w = ((c % cells) + cells) % cells;  // wrap for tiling
		vec3 f = vec3(c) + rand3(w, seed);
		vec3 d = q - f;
		best = min(best, dot(d, d));
	}
	return 1.0 - clamp(sqrt(best), 0.0, 1.0);
}

float worley_fbm(vec3 p, int cells, int seed) {
	return worley(p, cells, seed) * 0.625 + worley(p, cells * 2, seed + 1) * 0.25 + worley(p, cells * 4, seed + 2) * 0.125;
}

vec3 grad3(ivec3 c, int period, int seed) {
	ivec3 w = ((c % period) + period) % period;
	return normalize(rand3(w, seed + 50) * 2.0 - 1.0 + vec3(1e-4));
}

// Gradient (Perlin) noise tiling every `period`, roughly -1..1.
float perlin(vec3 p, int period, int seed) {
	vec3 q = p * float(period);
	ivec3 i = ivec3(floor(q));
	vec3 f = fract(q);
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float n000 = dot(grad3(i + ivec3(0, 0, 0), period, seed), f - vec3(0, 0, 0));
	float n100 = dot(grad3(i + ivec3(1, 0, 0), period, seed), f - vec3(1, 0, 0));
	float n010 = dot(grad3(i + ivec3(0, 1, 0), period, seed), f - vec3(0, 1, 0));
	float n110 = dot(grad3(i + ivec3(1, 1, 0), period, seed), f - vec3(1, 1, 0));
	float n001 = dot(grad3(i + ivec3(0, 0, 1), period, seed), f - vec3(0, 0, 1));
	float n101 = dot(grad3(i + ivec3(1, 0, 1), period, seed), f - vec3(1, 0, 1));
	float n011 = dot(grad3(i + ivec3(0, 1, 1), period, seed), f - vec3(0, 1, 1));
	float n111 = dot(grad3(i + ivec3(1, 1, 1), period, seed), f - vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y), mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}

float perlin_fbm(vec3 p, int period, int octaves, int seed) {
	float sum = 0.0;
	float amp = 1.0;
	float norm = 0.0;
	for (int o = 0; o < octaves; o++) {
		sum += perlin(p, period, seed + o) * amp;
		norm += amp;
		amp *= 0.5;
		period *= 2;
	}
	return sum / norm;
}

float remap(float v, float a, float b, float c, float d) {
	return c + (v - a) * (d - c) / (b - a);
}

void main() {
	ivec3 id = ivec3(gl_GlobalInvocationID);
	if (any(greaterThanEqual(id, ivec3(pc.size)))) return;
	vec3 p = (vec3(id) + 0.5) / float(pc.size);
	vec4 o;
	if (pc.mode == 0) {
		float pn = clamp(perlin_fbm(p, 4, 6, 3) * 0.7 + 0.5, 0.0, 1.0);
		float w0 = worley_fbm(p, 4, 10);
		float pw = remap(pn, 0.0, 1.0, w0, 1.0);  // Perlin-Worley: billowy, connected
		o = vec4(pw, w0, worley_fbm(p, 8, 20), worley_fbm(p, 16, 30));
	} else {
		o = vec4(worley_fbm(p, 4, 40), worley_fbm(p, 8, 50), worley_fbm(p, 16, 60), 1.0);
	}
	imageStore(out_tex, id, o);
}
