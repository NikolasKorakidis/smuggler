class_name TimeOfDay
extends Node
## Game clock (local solar time, compressed) driving the sun, moon, sky,
## exposure and night look. Sun colour comes from the same atmosphere model
## the sky shader uses, so the light reddens with the sky at sunset.
## Y jumps between times of day. darkness() (0 day .. 1 night) is what
## cockpit lights and lamps follow.

signal changed

## Times Y steps through, hours (local solar time).
const PRESETS := [5.5, 9.0, 13.0, 17.5, 18.75, 22.0]
const SYNODIC_DAYS := 29.530588
## New moon reference (2000-01-06 18:14 UTC) as days since 1970-01-01.
const NEW_MOON_EPOCH := 10962.76
const BETA_R := Vector3(5.8e-6, 13.5e-6, 33.1e-6)
const BETA_M := 21e-6
const BETA_OZONE := Vector3(0.65e-6, 1.88e-6, 0.085e-6)

## Game seconds per real second.
@export var time_scale := 4.0
@export_range(0.0, 24.0) var hours := 13.0
@export var year := 1983
@export_range(1, 365) var day_of_year := 166  # mid June
@export var latitude_deg := 25.0
@export var longitude_deg := -99.0
## Milky Way brightness relative to the stars.
@export var milkyway_brightness := 1.0

var sun: DirectionalLight3D
var environment: Environment
var weather: Weather  # optional: cloud cover
var camera: Camera3D  # optional: altitude for the sky
var _moon: DirectionalLight3D
var _sky: ShaderMaterial
var stars: StarField
var _sun_dir := Vector3.UP
var _cloud_time := 0.0


## Call once the world has its Sun and WorldEnvironment.
func setup(sun_light: DirectionalLight3D, env: Environment, lat_deg: float, lon_deg := -99.0) -> void:
	sun = sun_light
	environment = env
	latitude_deg = lat_deg
	longitude_deg = lon_deg
	_sky = ShaderMaterial.new()
	_sky.shader = preload("res://world/sky.gdshader")
	env.sky.sky_material = _sky
	env.sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL  # lighting from the sky updates over a few frames
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# Camera-like rendering: AgX tonemapping, bloom on bright lights, contact
	# shading, haze tinted by the sky behind it.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.4
	env.fog_enabled = true
	env.fog_aerial_perspective = 1.0
	env.fog_sky_affect = 0.0
	env.fog_sun_scatter = 0.0
	env.adjustment_enabled = true
	# Soft sun shadows (the sun is half a degree wide) out to 2.5 km; hills
	# further away are shadowed by the terrain shader itself.
	sun.light_angular_distance = 0.35
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 2500.0
	sun.directional_shadow_blend_splits = true
	_moon = DirectionalLight3D.new()
	_moon.name = "Moon"
	_moon.shadow_enabled = true
	_moon.directional_shadow_max_distance = 400.0
	_moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sun.add_sibling(_moon)
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY  # the sky shader draws its own sun
	_sky.set_shader_parameter("milkyway", preload("res://world/sky/milkyway_4k.webp"))
	stars = StarField.new()
	stars.name = "Stars"
	stars.camera = camera
	sun.add_sibling(stars)
	_update()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("time_next"):
		var next: float = PRESETS[0]
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
	var before := hours
	hours = fposmod(hours + delta * time_scale / 3600.0, 24.0)
	if hours < before:
		day_of_year = day_of_year % 365 + 1
	_cloud_time += delta * maxf(time_scale, 1.0)
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


## Days since 1970-01-01 00:00 UT for the game clock (local mean solar time).
func unix_days() -> float:
	var jan1 := Time.get_unix_time_from_datetime_dict({"year": year, "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0})
	var ut_hours := hours - longitude_deg / 15.0
	return jan1 / 86400.0 + (day_of_year - 1) + ut_hours / 24.0


## 0 new moon, 0.5 full, from the date.
func moon_phase() -> float:
	return fposmod((unix_days() - NEW_MOON_EPOCH) / SYNODIC_DAYS, 1.0)


func moon_illumination() -> float:
	return (1.0 - cos(TAU * moon_phase())) * 0.5


func _update() -> void:
	_sun_dir = _body_direction(hours)
	var el := sun_elevation_deg()
	var cam_alt := camera.global_position.y if camera else 200.0
	var night := darkness()

	# Sunlight after its path through the air: white high up, red at sunset.
	var t := _transmittance(_sun_dir, cam_alt)
	var tl := (t.x + t.y + t.z) / 3.0
	var sun_col := Color(t.x, t.y, t.z) * (1.0 / maxf(maxf(t.x, maxf(t.y, t.z)), 1e-4))
	var day := clampf((el + 1.0) / 6.0, 0.0, 1.0)
	sun.basis = Basis.looking_at(-_sun_dir, Vector3.UP if absf(_sun_dir.y) < 0.99 else Vector3.BACK)
	sun.light_color = sun_col
	sun.light_energy = 2.0 * clampf(tl / 0.75, 0.0, 1.0) * day
	sun.visible = day > 0.0
	sun.shadow_enabled = day > 0.02

	# The moon lags the sun by its phase angle; its light scales with how much is lit.
	var phase := moon_phase()
	var moon_dir := _body_direction(hours - phase * 24.0)
	var lit := moon_illumination()
	_moon.basis = Basis.looking_at(-moon_dir, Vector3.UP if absf(moon_dir.y) < 0.99 else Vector3.BACK)
	_moon.light_color = Color(0.7, 0.78, 1.0)
	_moon.light_energy = 0.11 * lit * night * clampf(moon_dir.y * 5.0, 0.0, 1.0)
	_moon.visible = _moon.light_energy > 0.002

	var cover := weather.cloud_cover if weather else 0.25
	_sky.set_shader_parameter("sun_dir", _sun_dir)
	_sky.set_shader_parameter("moon_dir", moon_dir)
	_sky.set_shader_parameter("sun_intensity", 22.0)
	_sky.set_shader_parameter("moon_intensity", 22.0 * 2.5e-4 * lit * clampf(moon_dir.y * 5.0, 0.0, 1.0))
	_sky.set_shader_parameter("moon_phase", phase)
	# Stars and Milky Way: only once the sky is dark enough, hidden by cloud.
	var star_vis := pow(night, 2.5) * (1.0 - 0.85 * cover)
	var cel := celestial_basis()
	_sky.set_shader_parameter("star_intensity", star_vis)
	_sky.set_shader_parameter("celestial_to_world", cel)
	_sky.set_shader_parameter("milkyway_intensity", star_vis * milkyway_brightness)
	if stars:
		stars.celestial_basis = cel
		stars.set_intensity(star_vis)
	_sky.set_shader_parameter("camera_altitude", cam_alt)
	_sky.set_shader_parameter("cloud_cover", cover)
	_sky.set_shader_parameter("cloud_time", _cloud_time)
	_sky.set_shader_parameter("sun_color", Vector3(sun_col.r, sun_col.g, sun_col.b) * day * 1.6
		+ Vector3(0.25, 0.28, 0.4) * lit * 0.05 * night)
	_sky.set_shader_parameter("ambient_color", Vector3(0.45, 0.55, 0.75) * lerpf(1.0, 0.01, night))

	# Eye adaptation and night vision: brighter exposure, less colour.
	environment.tonemap_exposure = lerpf(1.0, 6.0, night)
	environment.adjustment_saturation = lerpf(1.0, 0.45, night)
	environment.ambient_light_energy = lerpf(1.0, 0.6, night)
	environment.glow_intensity = lerpf(0.5, 0.9, night)


## Local sidereal time in hours (game clock is local mean solar time).
func local_sidereal_hours() -> float:
	var days_since_j2000 := unix_days() - 10957.5  # J2000.0 = 2000-01-01 12:00 UT
	var gmst := 18.697374558 + 24.06570982441908 * days_since_j2000
	return fposmod(gmst + longitude_deg / 15.0, 24.0)


## Turns the celestial frame (x: vernal equinox, z: north pole) into world
## axes (x east, y up, -z north) for the current time and latitude.
func celestial_basis() -> Basis:
	var lst := deg_to_rad(local_sidereal_hours() * 15.0)
	var lat := deg_to_rad(latitude_deg)
	# Hour-angle frame -> horizon: x_h -> (0, cos lat, sin lat), y_h -> east, z_h -> pole.
	var to_world := Basis(Vector3(0.0, cos(lat), sin(lat)), Vector3(1.0, 0.0, 0.0), Vector3(0.0, sin(lat), -cos(lat)))
	return to_world * Basis(Vector3(0, 0, 1), -lst)


# Fraction of sunlight reaching an observer at `alt_m` along `dir`.
func _transmittance(dir: Vector3, alt_m: float) -> Vector3:
	var re := 6360e3
	var ra := 6420e3
	var o := Vector3(0.0, re + maxf(alt_m, 1.0), 0.0)
	# Below the horizon the light grazes the planet; clamp so dusk stays red.
	var d := Vector3(dir.x, maxf(dir.y, -0.02), dir.z).normalized()
	var b := o.dot(d)
	var c := o.dot(o) - ra * ra
	var t := -b + sqrt(maxf(b * b - c, 0.0))
	var steps := 12
	var seg := t / steps
	var od_r := 0.0
	var od_m := 0.0
	for i in steps:
		var p := o + d * (seg * (i + 0.5))
		var h := maxf(p.length() - re, 0.0)
		od_r += exp(-h / 8000.0) * seg
		od_m += exp(-h / 1200.0) * seg
	var tau := BETA_R * od_r + Vector3.ONE * BETA_M * 1.1 * od_m + BETA_OZONE * od_r * 1.5
	return Vector3(exp(-tau.x), exp(-tau.y), exp(-tau.z))


# Direction to the sun (or the moon, phase-shifted) for the date and latitude.
func _body_direction(h: float) -> Vector3:
	var decl := deg_to_rad(23.44) * sin(TAU * (284.0 + day_of_year) / 365.0)
	var hour_angle := deg_to_rad(15.0 * (h - 12.0))
	var lat := deg_to_rad(latitude_deg)
	var east := -cos(decl) * sin(hour_angle)
	var north := sin(decl) * cos(lat) - cos(decl) * cos(hour_angle) * sin(lat)
	var up := sin(decl) * sin(lat) + cos(decl) * cos(hour_angle) * cos(lat)
	return Vector3(east, up, -north).normalized()
