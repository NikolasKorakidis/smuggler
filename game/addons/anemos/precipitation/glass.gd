# Anemos - weather and cloud system for Godot.
# Copyright (c) 2026 Nikolas Korakidis. All rights reserved. See addons/anemos/LICENSE.md.
class_name AnemosGlass
extends MeshInstance3D
## Rain on a pane of glass (glass.gdshader): drops land and bead, run down
## when slow, are blown up and back at speed, a water film forms in heavy
## rain; cloud wets it too; it dries off after leaving the rain. Put it where
## the glass is (a quad facing the viewer, UV v from the bottom edge up) and
## call update_glass() every frame.

var _mat := ShaderMaterial.new()
var _wet := 0.0
var _bead_clock := 0.0
var _sweep := 0.0
var _run_clock := 0.0


## A glass quad `size` metres (width, height).
func setup_glass(size: Vector2) -> void:
	var quad := QuadMesh.new()
	quad.size = size
	mesh = quad
	_mat.shader = preload("res://addons/anemos/precipitation/glass.gdshader")
	_mat.set_shader_parameter("glass_size", size)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## `airspeed` in m/s (air flowing over the glass), `exposure` the camera's
## exposure (glints are dimmer when the eye is dark-adapted).
func update_glass(delta: float, weather: AnemosWeather, airspeed: float, exposure := 1.0) -> void:
	var pos := global_position
	var rain := weather.rain_at(pos)
	var rain01 := clampf(log(1.0 + rain) / log(51.0), 0.0, 1.0)  # 0 dry .. 1 at 50 mm/h
	if weather.in_cloud(pos):
		rain01 = maxf(rain01, 0.3)  # cloud droplets wet the glass too
	var v := maxf(airspeed, 0.0)
	var flow := clampf((v - 12.0) / 30.0, 0.0, 1.0)
	# Moving forward sweeps up more rain; out of it the glass dries, faster in
	# a strong airflow.
	if rain01 > 0.01:
		_wet = minf(_wet + delta * rain01 * (0.25 + v / 60.0), maxf(rain01 * 1.1, _wet))
	else:
		_wet = maxf(_wet - delta * (0.01 + 0.04 * flow), 0.0)
	_bead_clock += delta * (0.15 + rain01 * 1.2) * (1.0 + flow * 2.0)
	_sweep += delta * flow * 1.8
	_run_clock += delta
	var film := smoothstep(0.55, 1.0, rain01)
	_mat.set_shader_parameter("wet", _wet)
	_mat.set_shader_parameter("film", film)
	_mat.set_shader_parameter("flow", flow)
	_mat.set_shader_parameter("bead_clock", _bead_clock)
	_mat.set_shader_parameter("sweep", _sweep)
	_mat.set_shader_parameter("run_clock", _run_clock)
	_mat.set_shader_parameter("light_color", Color(0.7, 0.75, 0.8) * clampf(1.0 / maxf(exposure, 1e-3), 0.15, 1.0))
	visible = _wet > 0.002 or film > 0.0
