// Anemos - weather and cloud system for Godot.
// Copyright (c) 2026 Nikolas Korakidis. All rights reserved. See addons/anemos/LICENSE.md.
//
// Ground integration: include in a terrain/ground spatial shader.
//   anemos_wetness             0 dry .. 1 soaked (rain builds it, sun/wind dry it)
//   anemos_cloud_sunlight(p)   0..1 sunlight getting through the clouds at world point p
//   anemos_wet_surface(...)    darken and gloss a surface by its own wet response
// Anemos sets the globals every frame (register them in Project Settings ->
// Shader Globals, or enable the Anemos plugin which does it).

global uniform float anemos_wetness;
global uniform sampler2D anemos_cloud_shadow;
global uniform vec4 anemos_cloud_shadow_rect;  // origin x, origin z, size m, plane y (w < -1e5: off)
global uniform vec3 anemos_sun_direction;

float anemos_cloud_sunlight(vec3 world_pos) {
	vec4 r = anemos_cloud_shadow_rect;
	vec3 s = anemos_sun_direction;
	if (r.w < -1e5 || s.y < 0.03) return 1.0;
	// Follow the sun ray up to the plane under the clouds and look it up there.
	vec2 at = world_pos.xz + s.xz * (r.w - world_pos.y) / s.y;
	vec2 uv = (at - r.xy) / r.z;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) return 1.0;
	return texture(anemos_cloud_shadow, uv).r;
}

// darken: albedo factor when soaked (0.55 dirt .. 0.8 grass); gloss: how
// shiny it gets (0.1 grass .. 0.8 asphalt). Adjusts albedo, roughness, specular.
void anemos_wet_surface(inout vec3 albedo, inout float roughness, inout float specular, float darken, float gloss) {
	float w = anemos_wetness;
	albedo *= mix(1.0, darken, w);
	roughness = mix(roughness, mix(roughness, 0.18, gloss), w);
	specular = mix(specular, 0.5, w * gloss);
}
