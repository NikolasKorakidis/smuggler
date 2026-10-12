shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
// Catalogue stars as constant-size screen points on a far sphere. Per star:
// COLOR = colour from B-V, INSTANCE_CUSTOM = (brightness, size px, twinkle
// phase, -). Brightness fades with the sky (star_intensity) and near the
// horizon (more air), and stars twinkle more low down.

uniform float star_intensity = 1.0;
uniform float time = 0.0;
uniform float pixel_scale = 1.0;

varying vec4 star;
varying float horizon;
varying vec3 tint;

void vertex() {
	star = INSTANCE_CUSTOM;
	tint = COLOR.rgb;
	vec3 world_dir = normalize((MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz - CAMERA_POSITION_WORLD);
	horizon = world_dir.y;
	vec4 view_c = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	POSITION = PROJECTION_MATRIX * view_c;
	// Twinkle: fast flicker in size and brightness, stronger near the horizon.
	float air = 1.0 / max(horizon + 0.05, 0.05);
	float tw = sin(time * 9.0 + star.z * 6.283) * sin(time * 13.7 + star.z * 17.0);
	float size = star.y * pixel_scale * (1.0 + 0.15 * tw * clamp(air * 0.2, 0.0, 1.0));
	POSITION.xy += VERTEX.xy * size * 2.0 / VIEWPORT_SIZE * POSITION.w;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r2 = dot(p, p);
	if (r2 > 1.0) discard;
	float core = exp(-r2 * 7.0);
	// Extinction: about a magnitude dimmer near the horizon, gone below it.
	float ext = smoothstep(-0.01, 0.08, horizon) * mix(0.35, 1.0, smoothstep(0.0, 0.35, horizon));
	float air = 1.0 / max(horizon + 0.05, 0.05);
	float tw = 1.0 + 0.25 * sin(TIME * 11.0 + star.z * 40.0) * clamp(air * 0.15, 0.0, 1.0);
	ALBEDO = tint * star.x * core * ext * tw * star_intensity;
}
