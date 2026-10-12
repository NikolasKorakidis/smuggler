class_name WeatherFX
extends Node
## Everything you see and hear of the weather, driven from the world's
## Weather and TimeOfDay: clouds, fog, haze and rain shafts (AtmosphereEffect),
## falling rain, lightning, wet ground, thunder and rain sounds.
## Add with WeatherFX.attach(world).

var world: Node3D
var weather: Weather
var tod: TimeOfDay
var camera: Camera3D
var atmosphere: AtmosphereEffect
var clouds: Clouds
## Fog debug view instead of the picture (dev): 0 off, 1 distances, 2 media.
var debug_fog := 0

var _colors_t := 0.0
var _horizon := Vector3(0.5, 0.6, 0.8)
var _zenith := Vector3(0.1, 0.2, 0.5)
var _toward := Vector3(0.7, 0.7, 0.8)
var _away := Vector3(0.4, 0.5, 0.8)


static func attach(w: Node3D) -> WeatherFX:
	var fx := WeatherFX.new()
	fx.name = "WeatherFX"
	fx.world = w
	w.add_child(fx)
	return fx


func _ready() -> void:
	weather = world.weather
	tod = world.time_of_day
	camera = world.get_node("CameraRig")
	weather.time_of_day = tod
	weather.field_elevation_m = world.field_elevation() if world.has_method("field_elevation") else 0.0
	var env_node: WorldEnvironment = world.get_node("WorldEnvironment")
	atmosphere = AtmosphereEffect.new()
	clouds = Clouds.new(weather, tod, atmosphere)
	add_child(clouds)
	add_child(RainField.new(weather, tod, world))
	add_child(Lightning.new(weather, tod))
	add_child(WeatherAudio.new(weather, world))
	add_child(RainAudio.new(weather, world))
	var comp := env_node.compositor if env_node.compositor else Compositor.new()
	var effects := comp.compositor_effects
	effects.append(atmosphere)
	comp.compositor_effects = effects
	env_node.compositor = comp
	env_node.environment.fog_enabled = false  # replaced by the fog effect


func _process(delta: float) -> void:
	weather.focus = camera.global_position
	_colors_t -= delta
	if _colors_t <= 0.0:
		_colors_t = 0.2
		var c := tod.sky_ambient_colors()
		_horizon = c[0]
		_zenith = c[1]
		_toward = c[2]
		_away = c[3]
		clouds.horizon = _horizon
		clouds.zenith = _zenith
		if tod.stars:
			tod.stars.set_sky(_horizon, _zenith)
	atmosphere.set_fog_params(_fog_params())
	_set_wetness(weather.wetness)


## Wet ground on the terrain shader (and screen-space reflections on the
## glossy runway once it's really wet).
func _set_wetness(wet: float) -> void:
	var terrain := world.get_node_or_null("Terrain")
	var mat = terrain.get("material") if terrain else null
	if mat is ShaderMaterial:
		mat.set_shader_parameter("wetness", wet)
		# Cloud shadows on the ground.
		var on := atmosphere.clouds_enabled and atmosphere.weather_texture != null
		mat.set_shader_parameter("cloud_shadow", atmosphere.shadow_texture)
		mat.set_shader_parameter("cloud_shadow_rect", clouds.shadow_rect() if on else Vector4(0, 0, 1, -1e6))


func _fog_params() -> PackedFloat32Array:
	var w := weather
	var field := w.field_elevation_m
	var out := PackedFloat32Array()
	# Haze: denser near the ground, thinning above the haze layer (low on
	# fog mornings under the inversion, high on hot hazy days).
	out.append_array([w.haze_extinction(), w.haze_height_m, field, 30000.0])
	var f := w.fog_now()
	var soft := maxf(15.0, 0.2 * f.x)
	out.append_array([w.fog_extinction() * f.y, field + f.x - soft, field + f.x + soft, 0.25 * f.x])
	var base := field + w.cloud_base_m
	out.append_array([Weather.rain_extinction(w.rain_mmh), base - 60.0, base + 120.0, 0.0])
	# Haze takes the horizon sky colour; fog and rain are lit by the whole dome
	# (paler, greyer); rain curtains are darker.
	var dome := (_horizon + _zenith) * 0.5
	var grey := Vector3.ONE * (0.2126 * dome.x + 0.7152 * dome.y + 0.0722 * dome.z)
	var fog_col := dome.lerp(grey, 0.6) * 1.1
	var rain_col := fog_col * 0.55
	var shaft_col := grey * 0.15 * Vector3(0.9, 0.95, 1.05)  # under the storm's dark base
	out.append_array([_toward.x, _toward.y, _toward.z, 0.0])
	out.append_array([_away.x, _away.y, _away.z, 0.0])
	out.append_array([fog_col.x, fog_col.y, fog_col.z, 0.0])
	out.append_array([rain_col.x, rain_col.y, rain_col.z, 0.0])
	out.append_array([shaft_col.x, shaft_col.y, shaft_col.z, 0.0])
	var sd := tod.sun_direction()
	out.append_array([sd.x, sd.y, sd.z, 0.6])
	var sun := tod.sun.light_color * tod.sun.light_energy
	# Forward scatter in the haze; where clouds block the sun the fog pass
	# finds the shadows itself (god rays), so no blanket dimming here.
	var sc := sun * 0.075
	out.append_array([sc.r, sc.g, sc.b, 0.0])
	var fs := sun * 0.22 * clampf(sd.y * 4.0 + 0.3, 0.0, 1.0)
	out.append_array([fs.r, fs.g, fs.b, 0.0])
	var n := mini(w.cells.size(), AtmosphereEffect.MAX_CELLS)
	# The sky model already holds ~100 km-visibility clean air.
	var sky_share := clampf(1.0 - (Weather.KOSCHMIEDER / 50000.0) / w.haze_extinction(), 0.0, 1.0)
	out.append_array([float(n), float(debug_fog), sky_share, 0.0])
	for i in AtmosphereEffect.MAX_CELLS:
		if i < n:
			var c: StormCell = w.cells[i]
			out.append_array([c.pos.x, c.pos.y, 0.9 * c.radius, Weather.rain_extinction(60.0 * c.strength * c.rain_k())])
		else:
			out.append_array([0.0, 0.0, 1.0, 0.0])
	for i in AtmosphereEffect.MAX_CELLS:
		var top := field + (w.cells[i].base_m if i < n else 0.0)
		out.append_array([top, 0.0, 0.0, 0.0])
	var sr := clouds.shadow_rect()
	out.append_array([sr.x, sr.y, sr.z, sr.w if atmosphere.clouds_enabled else -1e6])
	# The landing light, for its beam in fog and rain.
	var ac = world.get("aircraft")
	var spot: SpotLight3D = ac.find_child("LandingLight", true, false) if ac else null
	if spot and spot.is_visible_in_tree() and spot.light_energy > 0.0:
		var sp := spot.global_position
		var sd2 := -spot.global_basis.z
		var c := spot.light_color * spot.light_energy * 3.0
		out.append_array([sp.x, sp.y, sp.z, minf(spot.spot_range, 400.0)])
		out.append_array([sd2.x, sd2.y, sd2.z, cos(deg_to_rad(spot.spot_angle))])
		out.append_array([c.r, c.g, c.b, 0.0])
	else:
		out.append_array([0.0, 0.0, 0.0, 1.0, 0.0, 0.0, -1.0, 1.0, 0.0, 0.0, 0.0, 0.0])
	return out
