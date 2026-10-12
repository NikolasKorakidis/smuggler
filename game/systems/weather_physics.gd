class_name WeatherPhysics
extends RefCounted
## The game's link from Anemos' weather to JSBSim: wind (with height, gusts,
## storm outflow and downdrafts), Dryden turbulence, temperature and pressure.

const KT := 1.68781  # ft/s per knot
const HPA_TO_PSF := 2.0885434


## Called by the aircraft before each FDM step.
static func apply(w: AnemosWeather, fdm: FDM, agl_m: float, on_ground := false, at := Vector3.INF) -> void:
	var v := w.air_velocity(agl_m, at) / 0.3048  # ft/s, world axes
	if on_ground:
		v = _no_reverse_flow(fdm, Vector3(v.x, 0.0, v.z))
	fdm.prop("atmosphere/wind-north-fps", -v.z)
	fdm.prop("atmosphere/wind-east-fps", v.x)
	fdm.prop("atmosphere/wind-down-fps", -v.y)
	# Mechanical turbulence: Dryden (MIL-F-8785C) model, severity 0..6.
	var t := w.turbulence_at(at) if at != Vector3.INF else w.turbulence
	fdm.prop("atmosphere/turb-type", 3 if t > 0.01 else 0)
	fdm.prop("atmosphere/turbulence/milspec/severity", clampf(roundf(t * 4.0), 0.0, 6.0))
	fdm.prop("atmosphere/turbulence/milspec/windspeed_at_20ft_AGL-fps", w.mean_wind(6.0).y * KT)
	fdm.prop("atmosphere/delta-T", (w.temp_c - 15.0) * 1.8)
	fdm.prop("atmosphere/P-sl-psf", w.qnh_hpa * HPA_TO_PSF)


# JSBSim aircraft data only covers air arriving from the front. Parked or
# taxiing downwind slower than the wind, the air would come from behind and
# the tables give nonsense (a 172 flips over in 20 kt). On the ground, keep
# the crosswind part but never let the relative wind come from behind.
static func _no_reverse_flow(fdm: FDM, wind_fps: Vector3) -> Vector3:
	var psi := fdm.prop_get("attitude/psi-rad")
	var fwd := Vector3(sin(psi), 0.0, -cos(psi))
	var ground := Vector3(fdm.prop_get("velocities/v-east-fps"), 0.0, -fdm.prop_get("velocities/v-north-fps"))
	var min_headwind := 3.0  # ft/s of air from ahead, at least
	var along := (ground - wind_fps).dot(fwd)  # airspeed along the nose
	if along < min_headwind:
		wind_fps -= fwd * (min_headwind - along)  # now (ground - wind) . fwd == min_headwind
	return wind_fps
