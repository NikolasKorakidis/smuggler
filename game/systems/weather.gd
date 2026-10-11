class_name Weather
extends Node
## The one weather state. Feeds JSBSim (wind with height, gusts, turbulence,
## temperature, pressure) and the visuals (windsocks now; fog, rain, sky
## later) from the same numbers, so what you see is what you fly in.
## U cycles presets (dev).

signal changed

const KT := 1.68781  # ft/s per knot
const HPA_TO_PSF := 2.0885434

## Presets: wind FROM direction (deg true), surface wind and gusts (kt,
## at 10 m), wind aloft (kt at ~3300 ft) and veer with height, turbulence
## 0..1, sea-level temperature (°C) and QNH (hPa).
const PRESETS := [
	{"name": "Calm", "wind_dir": 0.0, "wind_kt": 0.0, "gust_kt": 0.0, "aloft_kt": 5.0, "veer": 10.0,
		"turbulence": 0.0, "temp_c": 15.0, "qnh": 1013.0},
	{"name": "Light breeze", "wind_dir": 60.0, "wind_kt": 7.0, "gust_kt": 0.0, "aloft_kt": 15.0, "veer": 20.0,
		"turbulence": 0.1, "temp_c": 22.0, "qnh": 1016.0},
	{"name": "Gusty crosswind", "wind_dir": 150.0, "wind_kt": 14.0, "gust_kt": 10.0, "aloft_kt": 28.0, "veer": 25.0,
		"turbulence": 0.45, "temp_c": 24.0, "qnh": 1006.0},
	{"name": "Hot afternoon", "wind_dir": 110.0, "wind_kt": 9.0, "gust_kt": 6.0, "aloft_kt": 18.0, "veer": 15.0,
		"turbulence": 0.35, "temp_c": 38.0, "qnh": 1009.0},
	{"name": "Low pressure, windy", "wind_dir": 210.0, "wind_kt": 20.0, "gust_kt": 12.0, "aloft_kt": 38.0, "veer": 30.0,
		"turbulence": 0.6, "temp_c": 12.0, "qnh": 992.0},
]

@export var preset := 0
@export var wind_dir_deg := 0.0
@export var wind_kt := 0.0
@export var gust_kt := 0.0
@export var aloft_kt := 5.0
@export var veer_deg := 10.0
@export_range(0.0, 1.0) var turbulence := 0.0
@export var temp_c := 15.0
@export var qnh_hpa := 1013.0
@export var seed := 1985

var _rng := RandomNumberGenerator.new()
var _gust := 0.0  # current gust, 0..1 of gust_kt
var _gust_dir := 0.0  # direction wobble during a gust, degrees
var _gust_phase := 0  # 0 waiting, 1 rising, 2 holding, 3 falling
var _gust_t := 0.0
var _gust_len := 0.0
var _gust_peak := 0.0
var _gust_peak_dir := 0.0


func _ready() -> void:
	_rng.seed = seed
	set_preset(preset)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("weather_next"):
		set_preset((preset + 1) % PRESETS.size())


func set_preset(i: int) -> void:
	preset = i
	var p: Dictionary = PRESETS[i]
	wind_dir_deg = p.wind_dir
	wind_kt = p.wind_kt
	gust_kt = p.gust_kt
	aloft_kt = p.aloft_kt
	veer_deg = p.veer
	turbulence = p.turbulence
	temp_c = p.temp_c
	qnh_hpa = p.qnh
	changed.emit()


func preset_name() -> String:
	return PRESETS[preset].name


## Mean wind (no gusts) blowing FROM, at a height above ground: (dir_deg, kt).
func mean_wind(agl_m: float) -> Vector2:
	var h := maxf(agl_m, 1.0)
	var speed: float
	if h <= 300.0:
		speed = wind_kt * pow(h / 10.0, 0.143)  # open-country boundary layer
	else:
		var at_300 := wind_kt * pow(30.0, 0.143)
		speed = lerpf(at_300, maxf(aloft_kt, at_300), clampf((h - 300.0) / 700.0, 0.0, 1.0))
	var dir := wind_dir_deg + veer_deg * clampf(h / 900.0, 0.0, 1.0)
	return Vector2(dir, speed)


## Air movement (the way the air blows, m/s) in world axes, gusts included.
func air_velocity(agl_m: float) -> Vector3:
	var w := mean_wind(agl_m)
	var scale := w.y / maxf(wind_kt, 0.1) if wind_kt > 0.1 else 1.0
	var speed_kt := w.y + _gust * gust_kt * scale
	var from := deg_to_rad(w.x + _gust_dir)
	# FROM north means air moving south (+Z); east = +X.
	return Vector3(-sin(from), 0.0, cos(from)) * speed_kt * 0.514444


## Called by the aircraft before each FDM step.
func apply(fdm: FDM, agl_m: float, on_ground := false) -> void:
	var v := air_velocity(agl_m) / 0.3048  # ft/s, world axes
	if on_ground:
		v = _no_reverse_flow(fdm, v)
	fdm.prop("atmosphere/wind-north-fps", -v.z)
	fdm.prop("atmosphere/wind-east-fps", v.x)
	fdm.prop("atmosphere/wind-down-fps", 0.0)
	# Mechanical turbulence: Dryden (MIL-F-8785C) model, severity 0..4.
	fdm.prop("atmosphere/turb-type", 3 if turbulence > 0.01 else 0)
	fdm.prop("atmosphere/turbulence/milspec/severity", roundf(turbulence * 4.0))
	fdm.prop("atmosphere/turbulence/milspec/windspeed_at_20ft_AGL-fps", mean_wind(6.0).y * KT)
	fdm.prop("atmosphere/delta-T", (temp_c - 15.0) * 1.8)
	fdm.prop("atmosphere/P-sl-psf", qnh_hpa * HPA_TO_PSF)


# JSBSim aircraft data only covers air arriving from the front. Parked or
# taxiing downwind slower than the wind, the air would come from behind and
# the tables give nonsense (a 172 flips over in 20 kt). On the ground, keep
# the crosswind part but never let the relative wind come from behind.
func _no_reverse_flow(fdm: FDM, wind_fps: Vector3) -> Vector3:
	var psi := fdm.prop_get("attitude/psi-rad")
	var fwd := Vector3(sin(psi), 0.0, -cos(psi))
	var ground := Vector3(fdm.prop_get("velocities/v-east-fps"), 0.0, -fdm.prop_get("velocities/v-north-fps"))
	var min_headwind := 3.0  # ft/s of air from ahead, at least
	var along := (ground - wind_fps).dot(fwd)  # airspeed along the nose
	if along < min_headwind:
		wind_fps -= fwd * (min_headwind - along)  # now (ground - wind) . fwd == min_headwind
	return wind_fps


func _physics_process(delta: float) -> void:
	_step_gusts(delta)


# Gusts come and go: rise over 1-2 s, hold, die away, then a quiet spell.
func _step_gusts(delta: float) -> void:
	if gust_kt <= 0.0:
		_gust = 0.0
		_gust_dir = 0.0
		return
	_gust_t += delta
	match _gust_phase:
		0:
			_gust = move_toward(_gust, 0.0, delta)
			_gust_dir = move_toward(_gust_dir, 0.0, delta * 10.0)
			if _gust_t >= _gust_len:
				_gust_phase = 1
				_gust_t = 0.0
				_gust_len = _rng.randf_range(0.8, 2.0)
				_gust_peak = _rng.randf_range(0.5, 1.0)
				_gust_peak_dir = _rng.randf_range(-15.0, 15.0)
		1:
			var k := _gust_t / _gust_len
			_gust = _gust_peak * k
			_gust_dir = _gust_peak_dir * k
			if _gust_t >= _gust_len:
				_gust_phase = 2
				_gust_t = 0.0
				_gust_len = _rng.randf_range(0.5, 2.5)
		2:
			if _gust_t >= _gust_len:
				_gust_phase = 3
				_gust_t = 0.0
				_gust_len = _rng.randf_range(1.5, 3.0)
		3:
			var k := 1.0 - _gust_t / _gust_len
			_gust = _gust_peak * k
			_gust_dir = _gust_peak_dir * k
			if _gust_t >= _gust_len:
				_gust_phase = 0
				_gust_t = 0.0
				_gust_len = _rng.randf_range(2.0, 9.0)


func summary() -> String:
	var w := mean_wind(10.0)
	var wind := "calm" if w.y < 1.0 else "%03d° %d kt%s" % [int(fposmod(w.x, 360.0)), int(round(w.y)),
		(" gusting %d" % int(round(w.y + gust_kt))) if gust_kt > 0.0 else ""]
	return "%s: wind %s, %d °C, QNH %d (%.2f inHg)" % [preset_name(), wind, int(temp_c), int(qnh_hpa), qnh_hpa * 0.02953]
