class_name Windshield
extends MeshInstance3D
## The windshield glass with rain on it. Placed from the aircraft definition
## (relative to the pilot's eye). Water builds up in rain and in cloud, is
## blown up and back at flying speed, runs down when slow, and dries off
## after a while once out of the rain.

var aircraft: Aircraft
var _mat := ShaderMaterial.new()
var _wet := 0.0
var _bead_clock := 0.0
var _sweep := 0.0
var _run_clock := 0.0


func setup(ac: Aircraft) -> void:
	aircraft = ac
	var def := ac.definition
	var quad := QuadMesh.new()
	quad.size = def.windshield_size
	mesh = quad
	_mat.shader = preload("res://aircraft/windshield.gdshader")
	_mat.set_shader_parameter("glass_size", def.windshield_size)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var eye := ac.eyepoint()
	eye.add_child(self)
	# Quad faces +Z; tilt it back by the rake (top towards the pilot).
	position = def.windshield_center
	rotation = Vector3(deg_to_rad(90.0 - def.windshield_rake_deg), 0.0, 0.0)


func _process(delta: float) -> void:
	if aircraft == null or aircraft.fdm == null or aircraft.world == null or not aircraft.world.get("weather"):
		return
	var w: Weather = aircraft.world.weather
	var pos := global_position
	var rain := w.rain_at(pos)
	var rain01 := clampf(log(1.0 + rain) / log(51.0), 0.0, 1.0)  # 0 dry .. 1 at 50 mm/h
	if w.in_cloud(pos):
		rain01 = maxf(rain01, 0.3)  # cloud droplets wet the glass too
	var v := maxf(aircraft.fdm.prop_get("velocities/vc-fps") * 0.3048, 0.0)
	var flow := clampf((v - 12.0) / 30.0, 0.0, 1.0)
	# Flying forward sweeps up more rain; out of the rain the glass dries,
	# faster in a strong airflow.
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
	var tod = aircraft.world.get("time_of_day")
	if tod:
		var env: Environment = tod.environment
		_mat.set_shader_parameter("light_color", Color(0.7, 0.75, 0.8) * clampf(1.0 / env.tonemap_exposure, 0.15, 1.0))
	visible = _wet > 0.002 or film > 0.0
