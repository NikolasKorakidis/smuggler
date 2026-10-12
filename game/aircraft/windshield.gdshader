shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;
// Rain on the windshield. Three layers of water, all procedural:
//   beads   drops that land and sit; at flying speed they are swept up and
//           back and stretch into streaks
//   runners big drops that run down the glass when slow (with a cleared
//           trail), and race upwards when the air pushes them
//   film    a rippling sheet of water in heavy rain
// Water refracts (lens) and blurs the view behind, and catches light at its
// edges. Windshield.gd drives the uniforms from rain, airspeed and cloud.
// UV: u across the glass (left to right), v from the bottom edge up.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec2 glass_size = vec2(1.1, 0.55);  // metres
uniform float wet = 0.0;        // how much water is on the glass, 0..1
uniform float film = 0.0;       // water sheet, 0..1
uniform float flow = 0.0;       // airflow: 0 = drops obey gravity, 1 = blown up hard
uniform float bead_clock = 0.0; // beads re-roll with this (faster in heavier rain)
uniform float sweep = 0.0;      // metres the beads have been blown up the glass
uniform float run_clock = 0.0;  // runners' clock
uniform vec3 light_color = vec3(1.0);
uniform float glint = 0.35;
uniform int debug_mode = 0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float noise2(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

// One drop as a lens: returns (offset.xy, coverage, rim).
vec4 lens(vec2 d) {
	float r2 = dot(d, d);
	if (r2 >= 1.0) return vec4(0.0);
	float h = sqrt(1.0 - r2);
	float cover = smoothstep(1.0, 0.8, sqrt(r2));
	return vec4(-d * (1.0 - h) * 1.6, cover, pow(1.0 - h, 2.5) * cover);
}

// Beads in a grid of cells (size `cell` m); each cell's drop comes and goes.
vec4 beads(vec2 p, float cell, float density, float seed, inout float hl) {
	vec2 q = p / cell;
	vec2 id = floor(q);
	vec2 f = fract(q) - 0.5;
	vec4 acc = vec4(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 cid = id + o;
			float epoch = floor(bead_clock * (0.5 + hash12(cid + seed)) + hash12(cid * 1.7 + seed));
			float live = hash12(cid + epoch * 13.1 + seed);
			if (live > density) continue;
			vec2 c = o + (hash22(cid + epoch + seed) - 0.5) * 0.7;
			float r = mix(0.12, 0.42, pow(hash12(cid * 3.3 + epoch), 2.0));
			vec2 d = (f - c) / r;
			d.y /= 1.0 + 3.0 * flow;  // stretched by the airflow
			vec4 l = lens(d);
			hl = max(hl, smoothstep(0.3, 0.0, length(d - vec2(-0.3, 0.35))) * l.z);
			acc.xy += l.xy * r;
			acc.z = max(acc.z, l.z);
			acc.w = max(acc.w, l.w);
		}
	}
	return acc;
}

// Runners: one per column of width `w`, sliding down (gravity) or up (air).
vec4 runners(vec2 p, float w, float density, inout float hl) {
	float col = floor(p.x / w);
	float h = hash12(vec2(col, 7.0));
	if (h > density) return vec4(0.0);
	float speed_down = mix(0.03, 0.08, hash12(vec2(col, 3.0)));   // m/s
	float speed_up = mix(1.2, 2.6, hash12(vec2(col, 5.0)));
	float len = glass_size.y + 0.3;
	float y_down = len - fract(run_clock * speed_down / len + h) * len;
	float y_up = fract(sweep / len * (speed_up / 1.8) + h) * len - 0.15;
	float y = mix(y_down, y_up, smoothstep(0.15, 0.4, flow));
	float wobble = sin(p.y * 40.0 + h * 20.0) * 0.004 * (1.0 - flow);
	float cx = (col + 0.5) * w + (hash12(vec2(col, 9.0)) - 0.5) * w * 0.5 + wobble;
	float r = mix(0.006, 0.011, hash12(vec2(col, 11.0)));
	vec2 d = (p - vec2(cx, y)) / r;
	d.y *= mix(0.8, 0.35, flow);  // long streaks when blown
	vec4 acc = lens(d);
	hl = max(hl, smoothstep(0.3, 0.0, length(d - vec2(-0.3, 0.35))) * acc.z);
	acc.xy *= r * 25.0;
	// Trail of tiny droplets behind a falling drop.
	float behind = flow < 0.3 ? p.y - y : y - p.y;
	if (behind > 0.0 && behind < 0.12 && abs(p.x - cx) < r * 0.6) {
		float bead = step(0.7, hash12(floor(vec2(p.x, p.y) / 0.003)));
		acc.z = max(acc.z, bead * 0.6 * (1.0 - behind / 0.12));
	}
	return acc;
}

void fragment() {
	vec2 p = UV * glass_size;
	vec4 w = vec4(0.0);
	float hl = 0.0;
	if (wet > 0.001) {
		// Beads ride up the glass with the airflow.
		vec2 pb = p - vec2(0.0, sweep);
		vec4 b1 = beads(pb, 0.016, wet * 0.75, 1.0, hl);
		vec4 b2 = beads(pb * 1.7 + 3.1, 0.016, wet * 0.5, 7.0, hl);
		vec4 rn = runners(p, 0.035, wet * 0.55, hl);
		w.xy = b1.xy + b2.xy * 0.6 + rn.xy;
		w.z = max(max(b1.z, b2.z * 0.8), rn.z);
		w.w = max(max(b1.w, b2.w), rn.w);
	}
	// Water film: moving ripples, blown up when flying.
	float fn = 0.0;
	if (film > 0.001) {
		vec2 q = p * vec2(9.0, 5.0) + vec2(0.0, -sweep * 4.0 + run_clock * 0.4);
		float n0 = noise2(q);
		vec2 grad = vec2(noise2(q + vec2(0.08, 0.0)) - n0, noise2(q + vec2(0.0, 0.08)) - n0) / 0.08;
		w.xy += grad * 0.004 * film;
		fn = film;
	}
	float cover = clamp(w.z + fn * 0.7, 0.0, 1.0);
	// Lens offset and blur: water bends and softens the view behind.
	vec2 uv = SCREEN_UV + w.xy * 0.045;
	float lod = cover * 1.5 + fn * 2.5;
	vec3 col = textureLod(screen_tex, uv, lod).rgb;
	col *= mix(1.0, 0.85, w.z);  // a drop shows a slightly darker, inverted view
	col *= 1.0 - 0.6 * w.w;  // dark outline: light reflects inside the drop's edge
	col += light_color * glint * (hl * 2.5 + 0.15 * fn);  // highlight from the sky
	float edge = smoothstep(0.0, 0.02, min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y)));
	if (debug_mode == 1) col = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;  // unbent view
	if (debug_mode == 2) col = vec3(w.xy * 20.0 + 0.5, 0.0);  // lens offsets
	ALBEDO = col;
	ALPHA = cover * edge;
}
