# Anemos - weather and cloud system for Godot.
# Copyright (c) 2026 Nikolas Korakidis. All rights reserved. See addons/anemos/LICENSE.md.
class_name Anemos
extends Node
## Anemos: the weather you see, hear and fly through, all from one
## AnemosWeather state. Volumetric clouds (AnemosClouds, a layered cloud
## engine), fog, haze, rain shafts and god rays (AnemosAtmosphere), falling
## rain, rain on glass, wet ground, storm cells with lightning and physically
## synthesised thunder, rain sounds that follow airspeed.
##
## Set up (see addons/anemos/README.md):
##   var anemos := Anemos.new()
##   anemos.weather = AnemosWeather.new()   # add it to the tree too (it ticks)
##   anemos.sky = <sky provider>            # sun/moon lights, sky colours, time of day
##   anemos.vehicle = <vehicle provider>    # optional: velocity, cockpit view, landing light
##   anemos.environment_node = $WorldEnvironment
##   anemos.field_elevation_m = 0.0         # weather heights are above this
##   add_child(anemos)
## Ground shaders read the global shader parameters anemos_wetness,
## anemos_cloud_shadow and anemos_cloud_shadow_rect (ground/anemos_ground.gdshaderinc).

const VERSION := "1.0.0"
## Global shader parameters Anemos publishes every frame.
const GLOBALS := {
	"anemos_wetness": [RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
	"anemos_cloud_shadow_rect": [RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(0, 0, 1, -1e6)],
	"anemos_sun_direction": [RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.UP],
}
const SHADOW_GLOBAL := "anemos_cloud_shadow"

var weather: AnemosWeather
## Sky provider (duck-typed): anemos_sun(), anemos_moon(), anemos_sun_direction(),
## anemos_sun_elevation_deg(), anemos_sky_colors(), anemos_transmittance(dir, alt),
## anemos_exposure(), anemos_hours(); optional anemos_flash(level), anemos_sky_changed(horizon, zenith).
var sky: Object
## Vehicle provider (duck-typed, optional): anemos_velocity(), anemos_airspeed(),
## anemos_is_inside(camera), anemos_beam_light(), anemos_load_factor(), anemos_on_ground().
var vehicle: Object
var environment_node: WorldEnvironment
var field_elevation_m := 0.0
## Camera to follow (empty: the viewport's camera).
var camera: Camera3D

var atmosphere: AnemosAtmosphere
var clouds: AnemosClouds
var rain: AnemosRain
var lightning: AnemosLightning
var thunder: AnemosThunder
var rain_audio: AnemosRainAudio
## Fog debug view instead of the picture (dev): 0 off, 1 distances, 2 media.
var debug_fog := 0
## Sky radiance: near the horizon (average), overhead, horizon towards and away from the sun.
var horizon := Vector3(0.5, 0.6, 0.8)
var zenith := Vector3(0.1, 0.2, 0.5)
var toward := Vector3(0.7, 0.7, 0.8)
var away := Vector3(0.4, 0.5, 0.8)

var _colors_t := 0.0


func _ready() -> void:
	if weather == null or sky == null:
		push_error("Anemos needs .weather and .sky set before it enters the tree (see addons/anemos/README.md).")
		set_process(false)
		return
	weather.sky = sky
	weather.field_elevation_m = field_elevation_m
	_register_globals()
	atmosphere = AnemosAtmosphere.new()
	clouds = AnemosClouds.new(self)
	rain = AnemosRain.new(self)
	lightning = AnemosLightning.new(self)
	thunder = AnemosThunder.new(self)
	rain_audio = AnemosRainAudio.new(self)
	for n in [clouds, rain, lightning, thunder, rain_audio]:
		add_child(n)
	if environment_node:
		var comp := environment_node.compositor if environment_node.compositor else Compositor.new()
		var effects := comp.compositor_effects
		effects.append(atmosphere)
		comp.compositor_effects = effects
		environment_node.compositor = comp
		environment_node.environment.fog_enabled = false  # replaced by Anemos' fog


## The camera Anemos renders around.
func view_camera() -> Camera3D:
	return camera if camera else get_viewport().get_camera_3d()


## Whether the camera is inside the vehicle (cockpit sounds and glass).
func inside_vehicle() -> bool:
	return vehicle != null and vehicle.has_method("anemos_is_inside") and vehicle.anemos_is_inside(view_camera())


func vehicle_velocity() -> Vector3:
	return vehicle.anemos_velocity() if vehicle and vehicle.has_method("anemos_velocity") else Vector3.ZERO


func vehicle_airspeed() -> float:
	return vehicle.anemos_airspeed() if vehicle and vehicle.has_method("anemos_airspeed") else 0.0


# Globals not set up in Project Settings (the plugin does that) are added at
# run time; shaders that use them should then load after Anemos.
func _register_globals() -> void:
	for k in GLOBALS:
		if not ProjectSettings.has_setting("shader_globals/" + k):
			RenderingServer.global_shader_parameter_add(k, GLOBALS[k][0], GLOBALS[k][1])
	if not ProjectSettings.has_setting("shader_globals/" + SHADOW_GLOBAL):
		RenderingServer.global_shader_parameter_add(SHADOW_GLOBAL, RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, null)


func _process(delta: float) -> void:
	var cam := view_camera()
	if cam:
		weather.focus = cam.global_position
	_colors_t -= delta
	if _colors_t <= 0.0:
		_colors_t = 0.2
		var c: Array = sky.anemos_sky_colors()
		horizon = c[0]
		zenith = c[1]
		toward = c[2]
		away = c[3]
		if sky.has_method("anemos_sky_changed"):
			sky.anemos_sky_changed(horizon, zenith)
	atmosphere.set_fog_params(_fog_params())
	# Ground: wetness and cloud shadows for any shader using anemos_ground.gdshaderinc.
	var on := atmosphere.clouds_enabled and atmosphere.weather_texture != null
	RenderingServer.global_shader_parameter_set("anemos_wetness", weather.wetness)
	RenderingServer.global_shader_parameter_set("anemos_cloud_shadow_rect", clouds.shadow_rect() if on else Vector4(0, 0, 1, -1e6))
	RenderingServer.global_shader_parameter_set("anemos_sun_direction", sky.anemos_sun_direction())
	if atmosphere.shadow_texture.texture_rd_rid.is_valid():
		RenderingServer.global_shader_parameter_set(SHADOW_GLOBAL, atmosphere.shadow_texture.get_rid())


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
	out.append_array([AnemosWeather.rain_extinction(w.rain_mmh), base - 60.0, base + 120.0, 0.0])
	# Haze takes the horizon sky colour; fog and rain are lit by the whole dome
	# (paler, greyer); rain curtains are darker.
	var dome := (horizon + zenith) * 0.5
	var grey := Vector3.ONE * (0.2126 * dome.x + 0.7152 * dome.y + 0.0722 * dome.z)
	var fog_col := dome.lerp(grey, 0.6) * 1.1
	var rain_col := fog_col * 0.55
	var shaft_col := grey * 0.15 * Vector3(0.9, 0.95, 1.05)  # under the storm's dark base
	out.append_array([toward.x, toward.y, toward.z, 0.0])
	out.append_array([away.x, away.y, away.z, 0.0])
	out.append_array([fog_col.x, fog_col.y, fog_col.z, 0.0])
	out.append_array([rain_col.x, rain_col.y, rain_col.z, 0.0])
	out.append_array([shaft_col.x, shaft_col.y, shaft_col.z, 0.0])
	var sd: Vector3 = sky.anemos_sun_direction()
	out.append_array([sd.x, sd.y, sd.z, 0.6])
	var sun_light: DirectionalLight3D = sky.anemos_sun()
	var sun := sun_light.light_color * sun_light.light_energy
	# Forward scatter in the haze; where clouds block the sun the fog pass
	# finds the shadows itself (god rays), so no blanket dimming here.
	var sc := sun * 0.075
	out.append_array([sc.r, sc.g, sc.b, 0.0])
	var fs := sun * 0.22 * clampf(sd.y * 4.0 + 0.3, 0.0, 1.0)
	out.append_array([fs.r, fs.g, fs.b, 0.0])
	var n := mini(w.cells.size(), AnemosAtmosphere.MAX_CELLS)
	# The sky model already holds ~50 km-visibility clean air.
	var sky_share := clampf(1.0 - (AnemosWeather.KOSCHMIEDER / 50000.0) / w.haze_extinction(), 0.0, 1.0)
	out.append_array([float(n), float(debug_fog), sky_share, 0.0])
	for i in AnemosAtmosphere.MAX_CELLS:
		if i < n:
			var c: AnemosStormCell = w.cells[i]
			out.append_array([c.pos.x, c.pos.y, 0.9 * c.radius, AnemosWeather.rain_extinction(60.0 * c.strength * c.rain_k())])
		else:
			out.append_array([0.0, 0.0, 1.0, 0.0])
	for i in AnemosAtmosphere.MAX_CELLS:
		var top := field + (w.cells[i].base_m if i < n else 0.0)
		out.append_array([top, 0.0, 0.0, 0.0])
	var sr := clouds.shadow_rect()
	out.append_array([sr.x, sr.y, sr.z, sr.w if atmosphere.clouds_enabled else -1e6])
	# The vehicle's landing light, for its beam in fog and rain.
	var spot: SpotLight3D = vehicle.anemos_beam_light() if vehicle and vehicle.has_method("anemos_beam_light") else null
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
