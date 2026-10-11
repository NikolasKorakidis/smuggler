class_name TimeOfDay
extends Node
## Game clock (local solar time, compressed) driving the sun, moon, sky,
## ambient light, fog colour and exposure. Y jumps between times of day.
## darkness() (0 day .. 1 night) is what cockpit lights and lamps follow.

signal changed

## Times Y steps through, hours (local solar time).
const PRESETS := [5.5, 9.0, 13.0, 17.5, 18.75, 22.0]

## Game seconds per real second.
@export var time_scale := 4.0
@export_range(0.0, 24.0) var hours := 13.0
@export_range(1, 365) var day_of_year := 166  # mid June
@export var latitude_deg := 25.0

var sun: DirectionalLight3D
var environment: Environment
var _moon: DirectionalLight3D
var _sky: ShaderMaterial
var _base_fog_density := 0.0
var _sun_dir := Vector3.UP


## Call once the world has its Sun and WorldEnvironment.
func setup(sun_light: DirectionalLight3D, env: Environment, lat_deg: float) -> void:
	sun = sun_light
	environment = env
	latitude_deg = lat_deg
	_base_fog_density = env.fog_density
	_sky = ShaderMaterial.new()
	_sky.shader = preload("res://world/sky.gdshader")
	env.sky.sky_material = _sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.fog_sun_scatter = 0.25
	_moon = DirectionalLight3D.new()
	_moon.name = "Moon"
	_moon.light_color = Color(0.62, 0.7, 0.95)
	_moon.shadow_enabled = false
	_moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sun.add_sibling(_moon)
	_update()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("time_next"):
		var next := PRESETS[0]
		for h in PRESETS:
			if h > hours + 0.05:
				next = h
				break
		set_hours(next)


func set_hours(h: float) -> void:
	hours = fposmod(h, 24.0)
	_update()
	changed.emit()


func _process(delta: float) -> void:
	if sun == null:
		return
	hours = fposmod(hours + delta * time_scale / 3600.0, 24.0)
	_update()


func clock_text() -> String:
	return "%02d:%02d" % [int(hours), int(fmod(hours, 1.0) * 60.0)]


func sun_elevation_deg() -> float:
	return rad_to_deg(asin(clampf(_sun_dir.y, -1.0, 1.0)))


## 0 in daylight, 1 at full night (sun 12° below the horizon).
func darkness() -> float:
	return clampf(-(sun_elevation_deg() - 2.0) / 14.0, 0.0, 1.0)


## Unit vector towards the sun in world axes (x east, y up, -z north).
func sun_direction() -> Vector3:
	return _sun_dir


func _update() -> void:
	_sun_dir = _body_direction(hours)
	var el := sun_elevation_deg()
	# Sun: fades through civil twilight, warms and reddens near the horizon.
	sun.basis = Basis.looking_at(-_sun_dir, Vector3.UP if absf(_sun_dir.y) < 0.99 else Vector3.BACK)
	var day := clampf((el + 1.0) / 8.0, 0.0, 1.0)
	sun.light_energy = 1.15 * day
	var warm := clampf(1.0 - el / 25.0, 0.0, 1.0)
	sun.light_color = Color(1.0, 0.97, 0.92).lerp(Color(1.0, 0.62, 0.38), warm * 0.85)
	sun.shadow_enabled = day > 0.05
	sun.visible = day > 0.0
	# A full moon opposite the sun lights the night a little.
	var moon_dir := _body_direction(hours + 12.0)
	_moon.basis = Basis.looking_at(-moon_dir, Vector3.UP if absf(moon_dir.y) < 0.99 else Vector3.BACK)
	var night := darkness()
	_moon.light_energy = 0.08 * night * clampf(moon_dir.y * 4.0, 0.0, 1.0)
	_moon.visible = _moon.light_energy > 0.001
	# Sky colours: day blue, warm low sun, deep blue night. Fog matches the horizon.
	var high := clampf(el / 20.0, 0.0, 1.0)
	var zenith := Color(0.2, 0.22, 0.42).lerp(Color(0.16, 0.36, 0.76), high).lerp(Color(0.004, 0.007, 0.02), night)
	var horizon := Color(0.88, 0.5, 0.3).lerp(Color(0.68, 0.77, 0.88), high).lerp(Color(0.02, 0.03, 0.06), night)
	_sky.set_shader_parameter("sun_dir", _sun_dir)
	_sky.set_shader_parameter("moon_dir", moon_dir)
	_sky.set_shader_parameter("zenith_color", zenith)
	_sky.set_shader_parameter("horizon_color", horizon)
	_sky.set_shader_parameter("ground_color", horizon * 0.45)
	_sky.set_shader_parameter("glow_color", Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.5, 0.22), warm))
	_sky.set_shader_parameter("glow_strength", 0.45 * clampf((el + 6.0) / 6.0, 0.0, 1.0))
	_sky.set_shader_parameter("sun_brightness", 25.0 * day)
	_sky.set_shader_parameter("star_intensity", 1.4 * night * night)
	_sky.set_shader_parameter("moon_brightness", 1.6 * night)
	environment.ambient_light_energy = lerpf(1.0, 0.22, night)
	var fog := horizon
	environment.fog_light_energy = lerpf(1.0, 0.25, night)
	environment.fog_sun_scatter = 0.25 * day  # no moonlit haze glow
	environment.tonemap_exposure = lerpf(1.0, 1.7, night)


# Direction to the sun (or the moon, 12 hours on) for the date and latitude.
func _body_direction(h: float) -> Vector3:
	var decl := deg_to_rad(23.44) * sin(TAU * (284.0 + day_of_year) / 365.0)
	var hour_angle := deg_to_rad(15.0 * (h - 12.0))
	var lat := deg_to_rad(latitude_deg)
	var east := -cos(decl) * sin(hour_angle)
	var north := sin(decl) * cos(lat) - cos(decl) * cos(hour_angle) * sin(lat)
	var up := sin(decl) * sin(lat) + cos(decl) * cos(hour_angle) * cos(lat)
	return Vector3(east, up, -north).normalized()
