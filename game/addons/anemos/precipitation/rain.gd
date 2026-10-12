# Anemos - weather and cloud system for Godot.
# Copyright (c) 2026 Nikolas Korakidis. All rights reserved. See addons/anemos/LICENSE.md.
class_name AnemosRain
extends MeshInstance3D
## Falling rain around the camera (rain.gdshader): as dense as the rain at
## the camera, slanted by the wind and by the vehicle's speed, lit by the
## sky and the vehicle's landing light.

const DROPS := 24000
const BOX := Vector3(36.0, 28.0, 36.0)

var anemos: Anemos
var weather: AnemosWeather
var _mat := ShaderMaterial.new()
var _offset := Vector3.ZERO


func _init(a: Anemos) -> void:
	anemos = a
	weather = a.weather
	mesh = _build_mesh()
	_mat.shader = preload("res://addons/anemos/precipitation/rain.gdshader")
	_mat.set_shader_parameter("box", BOX)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0  # the vertices move with the camera
	name = "Rain"


func _build_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1979
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(DROPS * 4)
	uvs.resize(DROPS * 4)
	cols.resize(DROPS * 4)
	idx.resize(DROPS * 6)
	var corners := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in DROPS:
		var p := Vector3(rng.randf(), rng.randf(), rng.randf())
		var c := Color(rng.randf(), 0, 0)
		for k in 4:
			verts[i * 4 + k] = p
			uvs[i * 4 + k] = corners[k]
			cols[i * 4 + k] = c
		var b := i * 4
		idx[i * 6] = b
		idx[i * 6 + 1] = b + 1
		idx[i * 6 + 2] = b + 2
		idx[i * 6 + 3] = b
		idx[i * 6 + 4] = b + 2
		idx[i * 6 + 5] = b + 3
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _process(delta: float) -> void:
	var cam := anemos.view_camera()
	if cam == null:
		return
	var rate := weather.rain_at(cam.global_position)
	var density := clampf(pow(rate / 40.0, 0.6), 0.0, 1.0)
	visible = density > 0.002
	if not visible:
		return
	global_transform = Transform3D.IDENTITY
	# Drops fall at ~7 m/s (big drops ~9), carried by the wind.
	var fall := Vector3(0.0, -lerpf(4.5, 9.0, clampf(rate / 30.0, 0.0, 1.0)), 0.0)
	var agl := cam.global_position.y - weather.field_elevation_m
	var air := weather.air_velocity(maxf(agl, 2.0)) + fall
	_offset = Vector3(fposmod(_offset.x + air.x * delta, BOX.x), fposmod(_offset.y + air.y * delta, BOX.y),
		fposmod(_offset.z + air.z * delta, BOX.z))
	var vel := anemos.vehicle_velocity()
	var cockpit := anemos.inside_vehicle()
	var v = anemos.vehicle
	var spot: SpotLight3D = v.anemos_beam_light() if v and v.has_method("anemos_beam_light") else null
	if spot and spot.is_visible_in_tree() and spot.light_energy > 0.0:
		_mat.set_shader_parameter("spot_pos", spot.global_position)
		_mat.set_shader_parameter("spot_dir", -spot.global_basis.z)
		var sc := spot.light_color * spot.light_energy * 0.08
		_mat.set_shader_parameter("spot_color", Vector3(sc.r, sc.g, sc.b))
		_mat.set_shader_parameter("spot_cos", cos(deg_to_rad(spot.spot_angle)))
		_mat.set_shader_parameter("spot_range", spot.spot_range)
	else:
		_mat.set_shader_parameter("spot_color", Vector3.ZERO)
	_mat.set_shader_parameter("offset", _offset)
	_mat.set_shader_parameter("rel_velocity", air - vel)
	_mat.set_shader_parameter("density", density)
	_mat.set_shader_parameter("min_dist", 2.2 if cockpit else 0.6)
	# Rain looks pale grey, lit by the sky.
	var dome := (anemos.horizon + anemos.zenith) * 0.5
	var g := 0.2126 * dome.x + 0.7152 * dome.y + 0.0722 * dome.z
	_mat.set_shader_parameter("ambient", Vector3(g, g, g * 1.05) * 0.9)
