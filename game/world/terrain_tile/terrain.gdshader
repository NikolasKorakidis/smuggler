shader_type spatial;
// Terrain tile. Vertices take their height straight from the physics height
// grid (exact match with JSBSim's ground). Strips, aprons and mown shoulders
// are painted from the same rectangles the physics uses for surface types.

render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform vec2 tile_min;
uniform float cell_size = 10.0;
uniform int tile_samples = 1601;

uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;

// Painted rectangles: a = (centre x, centre z, dir x, dir z), b = (half length, half width, kind, 0).
// kind: 0 paved strip, 1 dirt strip, 2 dirt apron, 3 mown grass. Later entries draw on top.
uniform vec4 rect_a[12];
uniform vec4 rect_b[12];
uniform int rect_count = 0;
// Ground steeper than this (normal.y below) is rock and scrub ("rough" in physics).
uniform float rough_normal_y = 0.94;
// Towards the sun (world axes). Hills shadow the ground beyond the shadow-map range.
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
// Weather from Anemos: rain-soaked ground (darker soil and grass, glossy
// asphalt, puddles once soaked) and cloud shadows.
#include "res://addons/anemos/ground/anemos_ground.gdshaderinc"

uniform vec3 grass_dry : source_color = vec3(0.50, 0.46, 0.27);
uniform vec3 grass_green : source_color = vec3(0.27, 0.32, 0.13);
uniform vec3 scrub : source_color = vec3(0.17, 0.21, 0.10);
uniform vec3 rock : source_color = vec3(0.47, 0.40, 0.32);
uniform vec3 field_fallow : source_color = vec3(0.45, 0.36, 0.25);
uniform vec3 field_crop : source_color = vec3(0.33, 0.40, 0.16);
uniform vec3 field_straw : source_color = vec3(0.62, 0.56, 0.36);
uniform vec3 mown : source_color = vec3(0.34, 0.40, 0.17);
uniform vec3 dirt : source_color = vec3(0.55, 0.43, 0.30);
uniform vec3 asphalt : source_color = vec3(0.21, 0.21, 0.22);
uniform vec3 paint : source_color = vec3(0.80, 0.80, 0.76);

varying vec3 world_pos;
varying float hill_shadow;  // 1 lit .. 0 behind a hill, from the heightmap

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Voronoi fields: x = random value per field, y = distance to the field edge.
vec2 fields(vec2 x) {
	vec2 cell = floor(x);
	vec2 f = fract(x);
	float best = 8.0;
	vec2 best_r = vec2(0.0);
	vec2 best_g = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + 0.15 + 0.7 * hash2(cell + g) - f;
			float d = dot(r, r);
			if (d < best) {
				best = d;
				best_r = r;
				best_g = g;
			}
		}
	}
	float edge = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + 0.15 + 0.7 * hash2(cell + g) - f;
			vec2 dr = r - best_r;
			if (dot(dr, dr) > 1e-5) {
				edge = min(edge, dot(0.5 * (best_r + r), normalize(dr)));
			}
		}
	}
	return vec2(hash2(cell + best_g + 17.0).x, edge);
}

float height_texel(ivec2 ij) {
	ij = clamp(ij, ivec2(0), ivec2(tile_samples - 1));
	return texelFetch(heightmap, ij, 0).r;
}

float height_smooth(vec2 xz) {
	vec2 uv = ((xz - tile_min) / cell_size + 0.5) / float(tile_samples);
	return texture(heightmap, uv).r;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ivec2 ij = ivec2(floor((wp.xz - tile_min) / cell_size + 0.5));
	float h = height_texel(ij);
	VERTEX.y = h - UV2.x; // UV2.x = skirt depth
	float hx = height_texel(ij + ivec2(1, 0)) - height_texel(ij - ivec2(1, 0));
	float hz = height_texel(ij + ivec2(0, 1)) - height_texel(ij - ivec2(0, 1));
	NORMAL = normalize(vec3(-hx, 2.0 * cell_size, -hz));
	world_pos = vec3(wp.x, h, wp.z);
}

void fragment() {
	vec2 xz = world_pos.xz;
	float c = cell_size;
	float hx = height_smooth(xz + vec2(c, 0.0)) - height_smooth(xz - vec2(c, 0.0));
	float hz = height_smooth(xz + vec2(0.0, c)) - height_smooth(xz - vec2(0.0, c));
	vec3 n = normalize(vec3(-hx, 2.0 * c, -hz));

	float macro = texture(macro_noise, xz / 2400.0).r;
	float macro2 = texture(macro_noise, xz / 700.0 + vec2(0.37, 0.71)).r;
	float detail = texture(detail_noise, xz / 37.0).r;
	float detail2 = texture(detail_noise, xz / 9.0 + vec2(0.5)).r;

	// Natural ground: dry and green grass, darker scrub patches, rock on steep slopes.
	vec3 col = mix(grass_green, grass_dry, smoothstep(0.25, 0.8, macro));
	col = mix(col, scrub, smoothstep(0.55, 0.8, macro2) * (0.3 + 0.4 * (1.0 - n.y) * 10.0));
	// Farm fields on flat, lower ground.
	float flat_low = smoothstep(0.985, 0.995, n.y) * (1.0 - smoothstep(230.0, 300.0, world_pos.y));
	if (flat_low > 0.0) {
		// Long plots, rotated off north. Only on flat, lower ground.
		vec2 fxz = mat2(vec2(0.94, 0.34), vec2(-0.34, 0.94)) * xz / vec2(420.0, 240.0);
		vec2 fv = fields(fxz);
		vec3 field = fv.x < 0.2 ? field_fallow : (fv.x < 0.4 ? field_crop : field_straw);
		float has_field = step(fv.x, 0.55) * flat_low;
		col = mix(col, field * (0.92 + 0.16 * detail2), has_field * 0.8);
		// Fence lines and scrubby hedges along field edges (faded with distance).
		float w = fwidth(fv.y);
		float hedge = 1.0 - smoothstep(0.004, 0.004 + 1.5 * w, fv.y);
		col = mix(col, scrub, hedge * flat_low * 0.7 * (1.0 - smoothstep(0.004, 0.02, w)));
	}
	float rough = smoothstep(rough_normal_y + 0.02, rough_normal_y - 0.02, n.y);
	col = mix(col, mix(rock, scrub, smoothstep(0.4, 0.7, detail) * 0.6), rough);
	col *= 0.8 + 0.4 * detail * (0.7 + 0.3 * detail2);
	float rough_px = mix(0.95, 0.9, rough);
	// How each surface takes the rain: darkening and gloss (natural ground first).
	float wet_dark = mix(0.7, 0.8, rough);
	float wet_gloss = 0.12;
	float puddle_ok = 0.0;

	for (int i = 0; i < rect_count; i++) {
		vec2 d = xz - rect_a[i].xy;
		vec2 dir = rect_a[i].zw;
		float along = dot(d, dir);
		float across = dot(d, vec2(-dir.y, dir.x));
		vec2 half_size = rect_b[i].xy;
		int kind = int(rect_b[i].z + 0.5);
		// Slightly ragged edges on everything but the paved strip.
		float edge = kind == 0 ? 0.15 : 1.2;
		float jitter = kind == 0 ? 0.0 : (detail - 0.5) * 2.0;
		float inside = (1.0 - smoothstep(half_size.y - edge, half_size.y + edge, abs(across) + jitter))
			* (1.0 - smoothstep(half_size.x - edge, half_size.x + edge, abs(along) + jitter));
		if (inside <= 0.0) {
			continue;
		}
		vec3 s;
		if (kind == 0) {
			s = asphalt * (0.85 + 0.25 * detail2) * (0.9 + 0.2 * macro2);
			float m = 0.0;
			// Edge lines, centreline dashes, threshold bars; faded paint.
			m = max(m, step(half_size.y - 0.9, abs(across)) * step(abs(across), half_size.y - 0.4));
			float from_end = half_size.x - abs(along);
			m = max(m, step(abs(across), 0.3) * step(20.0, from_end) * step(fract(along / 50.0), 0.6));
			float bar = step(fract((across + half_size.y) / 1.8), 0.55)
				* step(1.5, abs(across) + 0.0) * step(abs(across), half_size.y - 1.5);
			m = max(m, bar * step(6.0, from_end) * step(from_end, 36.0));
			s = mix(s, paint, m * (0.55 + 0.3 * detail));
			rough_px = mix(rough_px, 0.85, inside);
			wet_dark = mix(wet_dark, 0.72, inside);
			wet_gloss = mix(wet_gloss, 0.8, inside);
			puddle_ok = mix(puddle_ok, 0.5, inside);
		} else if (kind == 1 || kind == 2) {
			s = dirt * (0.85 + 0.3 * detail2) * (0.9 + 0.2 * macro2);
			wet_dark = mix(wet_dark, 0.55, inside);
			wet_gloss = mix(wet_gloss, 0.4, inside);
			puddle_ok = mix(puddle_ok, 1.0, inside);
			if (kind == 1) {
				// Worn wheel tracks either side of the centreline.
				float tracks = 1.0 - smoothstep(0.6, 1.6, abs(abs(across) - 1.4));
				s *= 1.0 - 0.18 * tracks;
				// A little grass growing along the edges.
				s = mix(s, mown, smoothstep(half_size.y - 3.0, half_size.y, abs(across)) * detail * 0.7);
			}
		} else {
			// Mown grass with faint mowing stripes.
			s = mown * (0.85 + 0.25 * detail) * (0.95 + 0.08 * step(0.5, fract(across / 6.0)));
			wet_dark = mix(wet_dark, 0.8, inside);
			wet_gloss = mix(wet_gloss, 0.1, inside);
		}
		col = mix(col, s, inside);
	}

	// Hill shadows: march the heightmap towards the sun (out to ~4 km).
	hill_shadow = 1.0;
	if (sun_dir.y > -0.05) {
		vec2 sdir = normalize(sun_dir.xz + vec2(1e-5));
		float slope = sun_dir.y / max(length(sun_dir.xz), 1e-4);
		float h0 = world_pos.y + 1.5;
		float t = 15.0;
		float vis = 1.0;
		for (int i = 0; i < 20; i++) {
			float above = h0 + t * slope - height_smooth(xz + sdir * t);
			vis = min(vis, clamp(above / (t * 0.035) + 0.5, 0.0, 1.0));
			t *= 1.33;
		}
		hill_shadow = vis;
		hill_shadow *= anemos_cloud_sunlight(world_pos);  // clouds
	}
	// Ambient occlusion from the terrain shape: hollows and valley floors
	// see less sky than ridges.
	float ring = 0.0;
	for (int k = 0; k < 6; k++) {
		float a = float(k) * 1.0472 + 0.5;
		vec2 o = vec2(cos(a), sin(a));
		ring += max(height_smooth(xz + o * 120.0) - world_pos.y, 0.0) / 120.0;
	}
	AO = clamp(1.0 - ring * 0.6, 0.35, 1.0);
	AO_LIGHT_AFFECT = 0.0;

	float spec = 0.25;
	if (anemos_wetness > 0.001) {
		col *= mix(1.0, wet_dark, anemos_wetness);
		rough_px = mix(rough_px, mix(rough_px, 0.18, wet_gloss), anemos_wetness);
		spec = mix(spec, 0.5, anemos_wetness * wet_gloss);
		// Puddles in hollows of dirt and (fewer) on the asphalt once soaked.
		float pn = texture(detail_noise, xz / 23.0 + vec2(0.21, 0.63)).r * 0.6 + macro2 * 0.4;
		float puddle = smoothstep(0.62, 0.68, pn) * puddle_ok * smoothstep(0.4, 1.0, anemos_wetness);
		col = mix(col, col * 0.6, puddle);
		rough_px = mix(rough_px, 0.03, puddle);
		spec = mix(spec, 0.6, puddle);
	}
	ALBEDO = col;
	ROUGHNESS = rough_px;
	SPECULAR = spec;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}


// Lambert (Burley-like) diffuse with the hill shadow on the sun only.
void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float sh = LIGHT_IS_DIRECTIONAL ? hill_shadow : 1.0;
	DIFFUSE_LIGHT += ndl * ATTENUATION * LIGHT_COLOR * sh / PI;
	vec3 h = normalize(VIEW + LIGHT);
	float spec = pow(clamp(dot(NORMAL, h), 0.0, 1.0), mix(8.0, 64.0, 1.0 - ROUGHNESS)) * (1.0 - ROUGHNESS);
	SPECULAR_LIGHT += spec * ndl * ATTENUATION * LIGHT_COLOR * sh * 0.08;
}
