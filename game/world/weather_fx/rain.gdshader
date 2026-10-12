shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled, world_vertex_coords;
// Falling rain around the camera. Every quad is one drop with a random place
// in a box (VERTEX = 0..1 box coordinates, COLOR.r = random). The box wraps
// around the camera, so the rain is equally dense at any speed. Each drop is
// drawn as the streak it makes during one exposure, from its motion relative
// to the aircraft (slanted and long when flying fast). Lit by the sky and by
// the landing light.

uniform vec3 box = vec3(36.0, 28.0, 36.0);
uniform vec3 offset = vec3(0.0);       // how far the rain has moved (wrapped), m
uniform vec3 rel_velocity = vec3(0.0, -7.0, 0.0);  // rain relative to the aircraft, m/s
uniform float exposure_s = 0.04;  // the eye smears a falling drop over ~1/25 s
uniform float density = 0.0;           // share of drops shown, 0..1
uniform float min_dist = 0.6;          // keep drops out of the cockpit
uniform vec3 ambient = vec3(0.3);
uniform float opacity = 0.4;
uniform vec3 spot_pos = vec3(0.0);
uniform vec3 spot_dir = vec3(0.0, 0.0, -1.0);
uniform vec3 spot_color = vec3(0.0);   // colour x energy, 0 = off
uniform float spot_cos = 0.95;
uniform float spot_range = 320.0;

varying vec3 v_light;
varying float v_alpha;

void vertex() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 origin = cam - box * 0.5;
	vec3 rel = mod(VERTEX * box + offset - origin, box);
	vec3 head = origin + rel;
	vec3 streak = rel_velocity * exposure_s;
	float len = max(length(streak), 0.04);
	vec3 axis = len > 0.0 ? streak / max(length(streak), 1e-4) : vec3(0.0, -1.0, 0.0);
	vec3 tail = head - axis * len;
	vec3 to_cam = head - cam;
	float dist = length(to_cam);
	vec3 side = normalize(cross(axis, to_cam / max(dist, 1e-3)) + vec3(1e-5));
	float shown = step(COLOR.r, density) * step(min_dist, dist);
	float width = max(0.0015, dist * 0.0016) * shown;  // a pixel and a half wide
	VERTEX = mix(head, tail, UV.y) + side * (UV.x * 2.0 - 1.0) * width;
	// Fade at the box edges so drops don't pop in and out.
	vec3 e = min(rel, box - rel) / (box * 0.15);
	v_alpha = clamp(min(min(e.x, e.y), e.z), 0.0, 1.0) * shown;
	// Landing light: drops in the beam light up.
	vec3 to = head - spot_pos;
	float d = length(to);
	float in_cone = smoothstep(spot_cos, mix(spot_cos, 1.0, 0.3), dot(to / max(d, 1e-3), spot_dir));
	v_light = spot_color * in_cone / (1.0 + d * d * 0.004) * step(d, spot_range);
}

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	float along = smoothstep(0.0, 0.2, UV.y) * smoothstep(1.0, 0.6, UV.y);
	ALBEDO = ambient + v_light;
	ALPHA = (1.0 - across) * along * v_alpha * (opacity + clamp(length(v_light), 0.0, 1.0) * 0.5);
}
