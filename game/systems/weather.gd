class_name Weather
extends Node
## The one weather state. Feeds JSBSim (wind with height, gusts, storm
## downdrafts and outflow, turbulence, temperature, pressure) and the visuals
## (windsocks, fog, cloud, rain, lightning, wet ground) from the same numbers,
## so what you see is what you fly in. U cycles presets (dev).
##
## Heights for fog and cloud are above the airfield (field_elevation_m), so
## valleys fill with fog and hills poke out of it.

signal changed
## A lightning flash: where (world), whether it reached the ground, how bright 0..1.
signal lightning(at: Vector3, to_ground: bool, power: float)

const KT := 1.68781  # ft/s per knot
const HPA_TO_PSF := 2.0885434
## Koschmieder: visibility = 3.912 / extinction (2% contrast threshold).
const KOSCHMIEDER := 3.912

## Presets: wind FROM direction (deg true), surface wind and gusts (kt,
## at 10 m), wind aloft (kt at ~3300 ft) and veer with height, turbulence
## 0..1, sea-level temperature and dew point (°C), QNH (hPa), clear-air
## visibility (km), cloud cover 0..1 / base / top (m above the field, base
## "auto" = cumulus base from the dew-point spread) / type (0 cumulus ..
## 1 stratus), high cirrus 0..1, steady rain (mm/h), fog deck top (m above
## the field, 0 none) and visibility inside it (m), whether the fog burns off
## after sunrise, thunderstorm cells: how many to start with and new ones per hour.
const PRESETS := [
	{"name": "Calm", "wind_dir": 0.0, "wind_kt": 0.0, "gust_kt": 0.0, "aloft_kt": 5.0, "veer": 10.0,
		"turbulence": 0.0, "temp_c": 15.0, "dew_c": 5.0, "qnh": 1013.0, "vis_km": 40.0,
		"clouds": 0.1, "cloud_base": "auto", "cloud_top": 600.0, "cloud_type": 0.0, "cirrus": 0.2},
	{"name": "Light breeze", "wind_dir": 60.0, "wind_kt": 7.0, "gust_kt": 0.0, "aloft_kt": 15.0, "veer": 20.0,
		"turbulence": 0.1, "temp_c": 22.0, "dew_c": 12.0, "qnh": 1016.0, "vis_km": 30.0,
		"clouds": 0.3, "cloud_base": "auto", "cloud_top": 900.0, "cloud_type": 0.0, "cirrus": 0.3},
	{"name": "Gusty crosswind", "wind_dir": 150.0, "wind_kt": 14.0, "gust_kt": 10.0, "aloft_kt": 28.0, "veer": 25.0,
		"turbulence": 0.45, "temp_c": 24.0, "dew_c": 14.0, "qnh": 1006.0, "vis_km": 25.0,
		"clouds": 0.5, "cloud_base": "auto", "cloud_top": 1200.0, "cloud_type": 0.0, "cirrus": 0.4},
	{"name": "Hot afternoon", "wind_dir": 110.0, "wind_kt": 9.0, "gust_kt": 6.0, "aloft_kt": 18.0, "veer": 15.0,
		"turbulence": 0.35, "temp_c": 38.0, "dew_c": 14.0, "qnh": 1009.0, "vis_km": 15.0,
		"clouds": 0.2, "cloud_base": "auto", "cloud_top": 1500.0, "cloud_type": 0.0, "cirrus": 0.1},
	{"name": "Low pressure, windy", "wind_dir": 210.0, "wind_kt": 20.0, "gust_kt": 12.0, "aloft_kt": 38.0, "veer": 30.0,
		"turbulence": 0.6, "temp_c": 12.0, "dew_c": 8.0, "qnh": 992.0, "vis_km": 20.0,
		"clouds": 0.7, "cloud_base": 700.0, "cloud_top": 2000.0, "cloud_type": 0.4, "cirrus": 0.0, "rain": 0.0},
	{"name": "Hazy summer", "wind_dir": 140.0, "wind_kt": 6.0, "gust_kt": 0.0, "aloft_kt": 12.0, "veer": 15.0,
		"turbulence": 0.2, "temp_c": 33.0, "dew_c": 21.0, "qnh": 1011.0, "vis_km": 7.0, "haze_h": 2000.0,
		"clouds": 0.25, "cloud_base": "auto", "cloud_top": 1200.0, "cloud_type": 0.0, "cirrus": 0.5},
	{"name": "Morning valley fog", "wind_dir": 0.0, "wind_kt": 0.0, "gust_kt": 0.0, "aloft_kt": 6.0, "veer": 10.0,
		"turbulence": 0.0, "temp_c": 11.0, "dew_c": 11.0, "qnh": 1021.0, "vis_km": 12.0,
		"clouds": 0.0, "cloud_base": 1500.0, "cloud_top": 2000.0, "cloud_type": 1.0, "cirrus": 0.2,
		"fog_top": 140.0, "fog_vis_m": 180.0, "fog_burns_off": true, "haze_h": 350.0},
	{"name": "Low overcast, drizzle", "wind_dir": 300.0, "wind_kt": 8.0, "gust_kt": 0.0, "aloft_kt": 18.0, "veer": 15.0,
		"turbulence": 0.1, "temp_c": 13.0, "dew_c": 12.0, "qnh": 1008.0, "vis_km": 5.0,
		"clouds": 1.0, "cloud_base": 230.0, "cloud_top": 1100.0, "cloud_type": 1.0, "cirrus": 0.0, "rain": 0.6},
	{"name": "Steady rain", "wind_dir": 170.0, "wind_kt": 12.0, "gust_kt": 6.0, "aloft_kt": 30.0, "veer": 25.0,
		"turbulence": 0.3, "temp_c": 16.0, "dew_c": 15.0, "qnh": 1001.0, "vis_km": 10.0,
		"clouds": 1.0, "cloud_base": 450.0, "cloud_top": 3000.0, "cloud_type": 0.8, "cirrus": 0.0, "rain": 6.0},
	{"name": "Afternoon thunderstorms", "wind_dir": 120.0, "wind_kt": 8.0, "gust_kt": 5.0, "aloft_kt": 20.0, "veer": 20.0,
		"turbulence": 0.3, "temp_c": 31.0, "dew_c": 22.0, "qnh": 1008.0, "vis_km": 35.0,
		"clouds": 0.45, "cloud_base": "auto", "cloud_top": 2500.0, "cloud_type": 0.0, "cirrus": 0.3,
		"storms": 2, "storms_per_hour": 3.0},
	{"name": "Squall line", "wind_dir": 230.0, "wind_kt": 15.0, "gust_kt": 12.0, "aloft_kt": 35.0, "veer": 30.0,
		"turbulence": 0.5, "temp_c": 27.0, "dew_c": 21.0, "qnh": 1003.0, "vis_km": 25.0,
		"clouds": 0.75, "cloud_base": 900.0, "cloud_top": 3000.0, "cloud_type": 0.3, "cirrus": 0.6, "rain": 1.0,
		"storms": 4, "storms_per_hour": 6.0, "storm_power": 1.3},
]

@export var preset := 0
@export var wind_dir_deg := 0.0
@export var wind_kt := 0.0
@export var gust_kt := 0.0
@export var aloft_kt := 5.0
@export var veer_deg := 10.0
@export_range(0.0, 1.0) var turbulence := 0.0
@export var temp_c := 15.0
@export var dewpoint_c := 5.0
@export var qnh_hpa := 1013.0
## Horizontal visibility in clear air (haze, mist), km at the surface.
@export var visibility_km := 40.0
## How deep the hazy layer is (m): low under a morning inversion, high on hot days.
@export var haze_height_m := 1200.0
## Main cloud layer: cover 0 clear .. 1 overcast, base and top above the field (m),
## type 0 cumulus (heaps) .. 1 stratus (sheet).
@export_range(0.0, 1.0) var cloud_cover := 0.1
@export var cloud_base_m := 1500.0
@export var cloud_top_m := 2100.0
@export_range(0.0, 1.0) var cloud_type := 0.0
## Thin high cloud (drawn by the sky), 0..1.
@export_range(0.0, 1.0) var cirrus := 0.2
## Steady rain from the cloud layer, mm/h (storms add their own).
@export var rain_mmh := 0.0
## Fog deck: top above the field (m, 0 = none) and visibility inside (m).
@export var fog_top_m := 0.0
@export var fog_visibility_m := 300.0
## Radiation fog: lifts and thins as the sun climbs.
@export var fog_burns_off := false
## New thunderstorm cells per hour near the pilot, and how strong (0.5..1.5).
@export var storms_per_hour := 0.0
@export var storm_power := 1.0
@export var seed := 1985
## Seconds to blend from one weather to the next (wind never jumps).
@export var transition_s := 20.0

## Ground wetness 0 dry .. 1 soaked: builds in rain, dries with sun, wind and heat.
var wetness := 0.0
var cells: Array[StormCell] = []
## Height of the airfield (fog and cloud heights are above it).
var field_elevation_m := 0.0
## Where the pilot is (storms form around here). Set by the world each frame.
var focus := Vector3.ZERO
var time_of_day: TimeOfDay  # optional: radiation fog burns off with the sun

var _rng := RandomNumberGenerator.new()
var _target := {}  # preset being blended towards
var _gust := 0.0  # current gust, 0..1 of gust_kt
var _gust_dir := 0.0  # direction wobble during a gust, degrees
var _gust_phase := 0  # 0 waiting, 1 rising, 2 holding, 3 falling
var _gust_t := 0.0
var _gust_len := 0.0
var _gust_peak := 0.0
var _gust_peak_dir := 0.0
var _lightning_clock := 0.0


func _ready() -> void:
	_rng.seed = seed
	set_preset(preset, true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("weather_next"):
		set_preset((preset + 1) % PRESETS.size())


## Change weather; blends over transition_s unless `instant`.
func set_preset(i: int, instant := false) -> void:
	preset = i
	_target = PRESETS[i].duplicate()
	if typeof(_target.get("cloud_base")) == TYPE_STRING:  # "auto": cumulus base from the spread
		_target.cloud_base = cumulus_base_m(_target.temp_c, _target.get("dew_c", _target.temp_c - 10.0))
	_target.cloud_top = maxf(_target.get("cloud_top", 0.0), _target.cloud_base + 300.0)
	if instant:
		_apply_fields(_target, 1.0)
	fog_burns_off = _target.get("fog_burns_off", false)
	storms_per_hour = _target.get("storms_per_hour", 0.0)
	storm_power = _target.get("storm_power", 1.0)
	cells.clear()
	for n in int(_target.get("storms", 0)):
		spawn_storm(_rng.randf_range(6000.0, 18000.0), _rng.randf_range(0.0, 360.0), _rng.randf_range(0.15, 0.5))
	changed.emit()


## Typical cumulus base above the ground from temperature and dew point
## (~125 m per °C of spread).
static func cumulus_base_m(t_c: float, td_c: float) -> float:
	return clampf(125.0 * (t_c - td_c), 250.0, 3500.0)


func _apply_fields(p: Dictionary, k: float) -> void:
	# Direction blends the short way round.
	wind_dir_deg = fposmod(wind_dir_deg + wrapf(p.wind_dir - wind_dir_deg, -180.0, 180.0) * k, 360.0)
	wind_kt = lerpf(wind_kt, p.wind_kt, k)
	gust_kt = lerpf(gust_kt, p.gust_kt, k)
	aloft_kt = lerpf(aloft_kt, p.aloft_kt, k)
	veer_deg = lerpf(veer_deg, p.veer, k)
	turbulence = lerpf(turbulence, p.turbulence, k)
	temp_c = lerpf(temp_c, p.temp_c, k)
	dewpoint_c = minf(lerpf(dewpoint_c, p.get("dew_c", p.temp_c - 10.0), k), temp_c)
	qnh_hpa = lerpf(qnh_hpa, p.qnh, k)
	# Visibility blends in log space (40 km -> 7 km feels even).
	visibility_km = exp(lerpf(log(maxf(visibility_km, 0.05)), log(maxf(p.get("vis_km", 30.0), 0.05)), k))
	haze_height_m = lerpf(haze_height_m, p.get("haze_h", 1200.0), k)
	cloud_cover = lerpf(cloud_cover, p.get("clouds", 0.2), k)
	cloud_base_m = lerpf(cloud_base_m, p.get("cloud_base", 1500.0), k)
	cloud_top_m = lerpf(cloud_top_m, p.get("cloud_top", 2100.0), k)
	cloud_type = lerpf(cloud_type, p.get("cloud_type", 0.0), k)
	cirrus = lerpf(cirrus, p.get("cirrus", 0.2), k)
	rain_mmh = lerpf(rain_mmh, p.get("rain", 0.0), k)
	fog_top_m = lerpf(fog_top_m, p.get("fog_top", 0.0), k)
	fog_visibility_m = exp(lerpf(log(maxf(fog_visibility_m, 10.0)), log(maxf(p.get("fog_vis_m", 300.0), 10.0)), k))


func preset_name() -> String:
	return PRESETS[preset].name


## A new thunderstorm cell `dist_m` from the pilot on `bearing_deg` (true),
## `stage` 0..1 into its life (0.3 = just mature).
func spawn_storm(dist_m: float, bearing_deg: float, stage := 0.0, power := -1.0) -> StormCell:
	var b := deg_to_rad(bearing_deg)
	var at := Vector2(focus.x, focus.z) + Vector2(sin(b), -cos(b)) * dist_m
	var p := storm_power * _rng.randf_range(0.8, 1.2) if power < 0.0 else power
	var cell := StormCell.new(at, steering_wind(), p, 0.0, _rng.randf_range(1400.0, 2400.0) * clampf(p, 0.7, 1.3),
		maxf(cloud_base_m, 600.0))
	cell.age = stage * cell.life
	cell.step(0.0)
	cells.append(cell)
	changed.emit()
	return cell


## Storms drift with the wind at mid levels (a bit slower than the wind aloft), m/s world x/z.
func steering_wind() -> Vector2:
	var from := deg_to_rad(wind_dir_deg + veer_deg)
	return Vector2(-sin(from), cos(from)) * aloft_kt * 0.514444 * 0.8


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


## Gust strength at a height: gusts come from the air churning near the
## ground, so they are full strength low down and fade with height.
func gust_scale(agl_m: float) -> float:
	return lerpf(1.0, 0.3, clampf((agl_m - 50.0) / 950.0, 0.0, 1.0))


## Air movement (the way the air blows, m/s) in world axes, gusts included.
## With a position, storm outflow, downdrafts and updrafts are added (y up).
func air_velocity(agl_m: float, at := Vector3.INF) -> Vector3:
	var w := mean_wind(agl_m)
	var speed_kt := w.y + _gust * gust_kt * gust_scale(agl_m)
	var from := deg_to_rad(w.x + _gust_dir)
	# FROM north means air moving south (+Z); east = +X.
	var v := Vector3(-sin(from), 0.0, cos(from)) * speed_kt * 0.514444
	if at != Vector3.INF:
		for c in cells:
			v += c.wind_at(at, agl_m)
	return v


## Turbulence 0..1+ at a point: the background plus storms, plus cumulus
## cloud when inside it.
func turbulence_at(at: Vector3) -> float:
	var t := turbulence
	for c in cells:
		t += c.turbulence_at(at)
	if in_cloud(at):
		t += 0.25 * (1.0 - cloud_type)
	return t


## Rain rate at a world point, mm/h (steady rain below the cloud base, plus storms).
func rain_at(at: Vector3) -> float:
	var r := rain_mmh * (1.0 - smoothstep(cloud_base_m, cloud_base_m + 200.0, at.y - field_elevation_m))
	for c in cells:
		r += c.rain_at(at)
	return r


## Roughly inside the main cloud layer (cover decides how often).
func in_cloud(at: Vector3) -> bool:
	var h := at.y - field_elevation_m
	return cloud_cover > 0.95 and h > cloud_base_m and h < cloud_top_m


## Fog deck right now: top above the field (m) and how thick, 0..1 (radiation
## fog lifts and thins after sunrise, gone with the sun ~20° up).
func fog_now() -> Vector2:
	if fog_top_m <= 1.0:
		return Vector2.ZERO
	var k := 1.0
	var top := fog_top_m
	if fog_burns_off and time_of_day:
		var el := time_of_day.sun_elevation_deg()
		k = 1.0 - smoothstep(6.0, 20.0, el)
		top *= 1.0 + 1.5 * smoothstep(4.0, 16.0, el)  # it lifts as it burns off
	return Vector2(top, k)


## Light-scattering strength of clear air (1/m) from the visibility.
func haze_extinction() -> float:
	return KOSCHMIEDER / maxf(visibility_km * 1000.0, 50.0)


## Extinction inside the fog deck (1/m).
func fog_extinction() -> float:
	return KOSCHMIEDER / maxf(fog_visibility_m, 10.0)


## Extinction from rain at a rate (1/m): visibility ~ 12 km x R^-0.65.
static func rain_extinction(mmh: float) -> float:
	if mmh <= 0.01:
		return 0.0
	return KOSCHMIEDER / (12000.0 * pow(mmh, -0.65))


## Relative humidity at the surface, 0..1 (Magnus formula).
func relative_humidity() -> float:
	var a := 17.62
	var b := 243.12
	return clampf(exp(a * dewpoint_c / (b + dewpoint_c) - a * temp_c / (b + temp_c)), 0.0, 1.0)


## Air temperature and dew point at a height above the field (°C): standard
## lapse rates (6.5 and 2 °C per km).
func temp_at(h_m: float) -> float:
	return temp_c - 0.0065 * h_m


func dewpoint_at(h_m: float) -> float:
	return minf(dewpoint_c - 0.002 * h_m, temp_at(h_m))


## Called by the aircraft before each FDM step.
func apply(fdm: FDM, agl_m: float, on_ground := false, at := Vector3.INF) -> void:
	var v := air_velocity(agl_m, at) / 0.3048  # ft/s, world axes
	if on_ground:
		v = _no_reverse_flow(fdm, Vector3(v.x, 0.0, v.z))
	fdm.prop("atmosphere/wind-north-fps", -v.z)
	fdm.prop("atmosphere/wind-east-fps", v.x)
	fdm.prop("atmosphere/wind-down-fps", -v.y)
	# Mechanical turbulence: Dryden (MIL-F-8785C) model, severity 0..6.
	var t := turbulence_at(at) if at != Vector3.INF else turbulence
	fdm.prop("atmosphere/turb-type", 3 if t > 0.01 else 0)
	fdm.prop("atmosphere/turbulence/milspec/severity", clampf(roundf(t * 4.0), 0.0, 6.0))
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
	if not _target.is_empty():
		_apply_fields(_target, clampf(delta * 3.0 / maxf(transition_s, 0.01), 0.0, 1.0))
	_step_gusts(delta)
	_step_storms(delta)
	_step_wetness(delta)


func _step_storms(delta: float) -> void:
	var drift := steering_wind()
	for c in cells:
		c.velocity = drift
		c.step(delta)
	for i in range(cells.size() - 1, -1, -1):
		var far := Vector2(focus.x, focus.z).distance_to(cells[i].pos) > 40000.0
		if cells[i].finished() or far:
			cells.remove_at(i)
	# New cells form around the pilot, mostly upwind so they drift in.
	if storms_per_hour > 0.0 and cells.size() < 8 and _rng.randf() < storms_per_hour * delta / 3600.0:
		var up := rad_to_deg(atan2(-drift.x, drift.y))  # towards where they come from
		spawn_storm(_rng.randf_range(8000.0, 22000.0), up + _rng.randf_range(-70.0, 70.0))
	# Lightning: each cell flashes at its own rate.
	for c in cells:
		if _rng.randf() < c.lightning_rate() * delta:
			var to_ground := _rng.randf() < 0.3
			var off := Vector2.from_angle(_rng.randf() * TAU) * c.radius * sqrt(_rng.randf()) * 1.1
			var h := field_elevation_m + (0.0 if to_ground else c.base_m + _rng.randf_range(500.0, 5000.0))
			lightning.emit(Vector3(c.pos.x + off.x, h, c.pos.y + off.y), to_ground, _rng.randf_range(0.5, 1.0) * c.strength)


func _step_wetness(delta: float) -> void:
	var rain := rain_at(Vector3(focus.x, field_elevation_m + 2.0, focus.z))
	if rain > 0.05:
		# Moderate rain soaks the ground in ~10 minutes.
		wetness = minf(wetness + delta * rain / 5.0 / 600.0 * (1.0 - wetness * 0.5), 1.0)
	else:
		# Dries in ~1 hour on a mild day, faster when hot, sunny and windy.
		var sun := 0.0
		if time_of_day:
			sun = clampf(time_of_day.sun_elevation_deg() / 40.0, 0.0, 1.0) * (1.0 - cloud_cover * 0.8)
		var rate := (0.5 + maxf(temp_c, 0.0) / 30.0 + sun + wind_kt / 20.0) / 3600.0
		wetness = maxf(wetness - delta * rate, 0.0)


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
				_gust_len = _rng.randf_range(1.5, 4.0)
				_gust_peak = _rng.randf_range(0.5, 1.0)
				_gust_peak_dir = _rng.randf_range(-8.0, 8.0)
		1:
			var k := smoothstep(0.0, 1.0, _gust_t / _gust_len)
			_gust = _gust_peak * k
			_gust_dir = _gust_peak_dir * k
			if _gust_t >= _gust_len:
				_gust_phase = 2
				_gust_t = 0.0
				_gust_len = _rng.randf_range(1.0, 3.0)
		2:
			if _gust_t >= _gust_len:
				_gust_phase = 3
				_gust_t = 0.0
				_gust_len = _rng.randf_range(2.5, 5.0)
		3:
			var k := 1.0 - smoothstep(0.0, 1.0, _gust_t / _gust_len)
			_gust = _gust_peak * k
			_gust_dir = _gust_peak_dir * k
			if _gust_t >= _gust_len:
				_gust_phase = 0
				_gust_t = 0.0
				_gust_len = _rng.randf_range(3.0, 12.0)


func summary() -> String:
	var w := mean_wind(10.0)
	var wind := "calm" if w.y < 1.0 else "%03d° %d kt%s" % [int(fposmod(w.x, 360.0)), int(round(w.y)),
		(" gusting %d" % int(round(w.y + gust_kt))) if gust_kt > 0.0 else ""]
	return "%s: wind %s, %d °C, QNH %d (%.2f inHg)" % [preset_name(), wind, int(temp_c), int(qnh_hpa), qnh_hpa * 0.02953]


## The weather as a METAR-style line (as a pilot would read it on the radio).
func metar() -> String:
	var parts: Array[String] = []
	var w := mean_wind(10.0)
	if w.y < 1.0:
		parts.append("00000KT")
	else:
		parts.append("%03d%02d%sKT" % [int(roundf(fposmod(w.x, 360.0) / 10.0) * 10.0) % 360, int(round(w.y)),
			("G%02d" % int(round(w.y + gust_kt))) if gust_kt >= 3.0 else ""])
	var here := Vector3(focus.x, field_elevation_m + 2.0, focus.z)
	var fog := fog_now()
	var vis := visibility_km * 1000.0
	var rain := rain_at(here)
	if rain > 0.0:
		vis = 1.0 / (1.0 / vis + rain_extinction(rain) / KOSCHMIEDER)
	if fog.y > 0.3:
		vis = minf(vis, fog_visibility_m / fog.y)
	parts.append("9999" if vis >= 10000.0 else "%04d" % int(snappedf(vis, 100.0 if vis < 5000.0 else 1000.0)))
	var storm_near := false
	for c in cells:
		if c.mature_k() > 0.2 and Vector2(focus.x, focus.z).distance_to(c.pos) < 15000.0:
			storm_near = true
	var wx := ""
	if rain > 0.0:
		wx = ("+" if rain > 8.0 else ("-" if rain < 2.5 else "")) + ("TSRA" if storm_near else ("DZ" if rain < 1.0 and cloud_type > 0.7 else "RA"))
	elif storm_near:
		wx = "VCTS"
	elif fog.y > 0.3 and vis < 1000.0:
		wx = "FG"
	elif vis < 5000.0:
		wx = "BR" if relative_humidity() > 0.8 else "HZ"
	if wx != "":
		parts.append(wx)
	if fog.y > 0.3 and vis < 1000.0:
		parts.append("VV%03d" % int(fog.x / 30.48))
	elif cloud_cover >= 0.06:
		var okta := cloud_cover * 8.0
		var amount := "FEW" if okta < 2.5 else ("SCT" if okta < 4.5 else ("BKN" if okta < 7.5 else "OVC"))
		parts.append("%s%03d%s" % [amount, int(cloud_base_m / 30.48), "CB" if storm_near else ""])
	else:
		parts.append("SKC" if cirrus < 0.1 else "FEW250")
	parts.append("%s/%s" % [_metar_temp(temp_c), _metar_temp(dewpoint_c)])
	parts.append("Q%04d" % int(round(qnh_hpa)))
	return " ".join(parts)


static func _metar_temp(t: float) -> String:
	var r := int(round(t))
	return ("M%02d" % -r) if r < 0 else "%02d" % r
