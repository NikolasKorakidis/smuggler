extends Node
## Flies the whole tutorial with a scripted pilot and checks the checklist
## completes: start, take off, tower, back, land, taxi, shut down.
##   godot --headless --path game --fixed-fps 120 res://dev/tutorial_flight_test.tscn -- --aircraft=1 [--world=terrain]

const P := {
	"c172p": {"rotate": 55.0, "climb_kias": 70.0, "app_kias": 65.0, "flare_pitch": 6.0, "rot_pitch": 9.0, "cruise_thr": 0.75},
	"J3Cub": {"rotate": 33.0, "climb_kias": 42.0, "app_kias": 42.0, "flare_pitch": 11.0, "rot_pitch": 8.0, "cruise_thr": 0.85},
}

var world: Node3D
var cl
var ac: Aircraft
var p: Dictionary
var phase := "start"
var t := 0.0
var phase_t := 0.0
var log_t := 0.0
var pitch_trim := 4.0
# Land opposite to the takeoff direction, coming back from the tower side.
var takeoff_dir: Vector3
var land_heading: float
var threshold: Vector3
var final_start: Vector3


func _ready() -> void:
	process_physics_priority = -50  # after FlightInput, before the aircraft
	FlightInput.joysticks_enabled = false
	var idx := 0
	var scene := "res://world/test_world.tscn"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--aircraft="):
			idx = int(a.trim_prefix("--aircraft="))
		if a == "--world=terrain":
			scene = "res://world/terrain_tile/terrain_tile.tscn"
	world = load(scene).instantiate()
	add_child(world)
	world._spawn_aircraft(idx)
	ac = world.aircraft
	cl = world.get_node("Checklist")
	p = P[ac.definition.jsbsim_model]
	var h := deg_to_rad(world.strip_heading())
	takeoff_dir = Vector3(sin(h), 0, -cos(h))
	land_heading = fposmod(world.strip_heading() + 180.0, 360.0)
	var centre: Vector3 = world.point("strip")
	threshold = centre + takeoff_dir * world.strip_length() * 0.5
	final_start = centre + takeoff_dir * (world.strip_length() * 0.5 + 3000.0)
	print("world %s, strip heading %.0f, landing heading %.0f" % [world.name, world.strip_heading(), land_heading])


func _prop(n: String) -> float:
	return ac.fdm.prop_get(n)


func _go(next: String) -> void:
	print("  t=%5.1f  %-10s -> %s   (checklist: %s)" % [t, phase, next, _next_item()])
	phase = next
	phase_t = 0.0


func _next_item() -> String:
	var n = cl._items.filter(func(i): return not i.done)
	return (n[0].item + " " + n[0].state) if n else "complete"


func _physics_process(delta: float) -> void:
	t += delta
	phase_t += delta
	var e := ac.engine
	var o := {}
	var kias := _prop("velocities/vc-kts")
	var agl := _prop("position/h-agl-ft")
	match phase:
		"start":
			FlightInput.parking_brake = true
			e.auto_start()
			_go("warmup")
		"warmup":
			o = {"throttle": 0.05}
			if e.running() and phase_t > 6.0:
				for i in cl._items:
					if i.cond == "manual":
						cl._tick_manual(i)
				if not ac.definition.flap_detents.is_empty():
					ac.set_flap_notch(1)
				FlightInput.parking_brake = false
				_go("roll")
		"roll":
			o = {"throttle": 1.0}
			o.merge(_ground_steer(world.strip_heading()))
			if kias > p.rotate:
				_go("climb")
		"climb", "to_tower", "back":
			var target: Vector3
			if phase == "climb" or phase == "to_tower":
				target = world.point("tower")
			else:
				target = final_start  # on the extended centreline, well out
			o = _fly(_bearing(target), p.climb_kias if agl < 950 else -1.0, 1000.0)
			if phase == "climb" and agl > 300 and not ac.definition.flap_detents.is_empty():
				ac.set_flap_notch(0)
			if phase == "climb" and agl > 900:
				_go("to_tower")
			elif phase == "to_tower" and _dist(world.point("tower")) < 500:
				_go("turn_back")
			elif phase == "back" and _dist(target) < 350:
				_go("final")
		"turn_back":
			o = _fly(_bearing(world.point("strip")), -1.0, 1000.0)
			if cl._heading_error(_bearing(world.point("strip"))) < 10.0:
				_go("back")
		"final":
			e.set_carb_heat(true)
			if not ac.definition.flap_detents.is_empty() and kias < 85:
				ac.set_flap_notch(3)
			o = _approach()
			if agl < 18:
				_go("flare")
		"flare":
			o = _approach()
			o.throttle = 0.0
			o.pitch = _pitch_cmd(p.flare_pitch)
			if cl._on_ground():
				_go("rollout")
		"rollout":
			o = {"throttle": 0.0, "pitch": 0.5 if ac.definition.jsbsim_model == "J3Cub" else 0.0}
			o.merge(_ground_steer(land_heading))
			if kias < 40:
				o.brake_left = 0.7
				o.brake_right = 0.7
			if _gs() < 6.0:
				e.set_carb_heat(false)
				if not ac.definition.flap_detents.is_empty():
					ac.set_flap_notch(0)
				_go("taxi")
		"taxi":
			var park: Vector3 = world.point("parking")
			var d := _dist(park)
			# Taxi along the strip to abeam the parking spot, then turn in.
			var centre: Vector3 = world.point("strip")
			var abeam := centre + takeoff_dir * (park - centre).dot(takeoff_dir)
			var target := abeam if _dist(abeam) > 20.0 and d > 40.0 else park
			var want_gs := 8.0 if d > 30 else 3.0
			o = {"throttle": clampf(0.25 + 0.08 * (want_gs - _gs()), 0.0, 0.65), "pitch": 0.5 if ac.definition.jsbsim_model == "J3Cub" else 0.0}
			o.merge(_ground_steer(_bearing(target)))
			if _gs() > want_gs + 2:
				o.brake_left = 0.5
				o.brake_right = 0.5
			if d < 4.0:
				o.throttle = 0.0
				o.brake_left = 1.0
				o.brake_right = 1.0
				if _gs() < 0.5:
					_go("shutdown")
		"shutdown":
			o = {"throttle": 0.0}
			FlightInput.parking_brake = true
			if phase_t > 1.0:
				e.set_carb_heat(false)
				if not ac.definition.flap_detents.is_empty():
					ac.set_flap_notch(0)
				if e.definition.has_mixture:
					e.set_mixture(0.0)
				else:
					e.set_magnetos(0)
			if phase_t > 3.0 and not e.running() and _prop("propulsion/engine/engine-rpm") < 50:
				e.set_magnetos(0)
				e.set_master(false)
				if ac.definition.jsbsim_model == "J3Cub":
					e.set_fuel_selector(0)
			if phase_t > 25.0:
				_finish()
	FlightInput.override = o
	if t - log_t > 15.0:
		log_t = t
		print("  t=%5.1f %-10s kias %5.1f agl %6.0f hdg %5.1f pos (%.0f, %.0f) gs %.1f rpm %.0f thr %.2f %s" % [
			t, phase, kias, agl, fposmod(_prop("attitude/psi-deg"), 360), ac.global_position.x, ac.global_position.z, _gs(),
			_prop("propulsion/engine/engine-rpm"), FlightInput.throttle, world.surface_at(ac.global_position)])
	if t > 700.0:
		print("  timeout in phase ", phase)
		_finish()


func _finish() -> void:
	var done: Array = cl._items.filter(func(i): return i.done and not i.skipped)
	var skipped: Array = cl._items.filter(func(i): return i.skipped)
	var left: Array = cl._items.filter(func(i): return not i.done)
	print("  ticked %d, skipped %d, left %d" % [done.size(), skipped.size(), left.size()])
	for i in skipped:
		print("    skipped: %s %s" % [i.item, i.state])
	for i in left:
		print("    LEFT:    %s %s" % [i.item, i.state])
	print("TUTORIAL FLIGHT: ", "PASS" if left.is_empty() else "FAIL")
	get_tree().quit(0 if left.is_empty() else 1)


# --- scripted pilot -----------------------------------------------------------------

func _pitch_cmd(theta_t: float) -> float:
	return clampf(0.08 * (theta_t - _prop("attitude/theta-deg")) - 0.05 * rad_to_deg(_prop("velocities/q-rad_sec")), -1, 1)


func _roll_cmd(phi_t: float) -> float:
	return clampf(0.05 * (phi_t - _prop("attitude/phi-deg")) - 0.02 * rad_to_deg(_prop("velocities/p-rad_sec")), -1, 1)


# Heading via bank; speed via pitch (kias_t > 0) or altitude via pitch (kias_t < 0).
func _fly(hdg: float, kias_t: float, alt_ft: float) -> Dictionary:
	var err := wrapf(hdg - _prop("attitude/psi-deg"), -180.0, 180.0)
	var bank := clampf(err * 1.0, -25.0, 25.0)
	var theta_t: float
	var thr := 1.0
	if kias_t > 0.0:
		pitch_trim += 0.002 * (_prop("velocities/vc-kts") - kias_t)
		theta_t = clampf(pitch_trim + 0.5 * (_prop("velocities/vc-kts") - kias_t), -5.0, 14.0)
	else:
		var alt_err := alt_ft - _prop("position/h-agl-ft")
		theta_t = clampf(2.0 + 0.02 * alt_err - 0.15 * _prop("velocities/h-dot-fps"), -6.0, 10.0)
		thr = p.cruise_thr
	return {"pitch": _pitch_cmd(theta_t), "roll": _roll_cmd(bank), "throttle": thr,
		"rudder": clampf(-0.3 * rad_to_deg(_prop("velocities/r-rad_sec")) * 0.0 + _prop("accelerations/Ny") * -4.0, -0.5, 0.5)}


# Final onto the strip: track the centreline, 3.5° glide to 100 m past the threshold.
func _approach() -> Dictionary:
	var land_dir := -takeoff_dir
	var aim := threshold + land_dir * 100.0
	var hr := deg_to_rad(land_heading)
	var right := Vector3(cos(hr), 0, sin(hr))
	var off_right := (ac.global_position - aim).dot(right)
	var hdg_t := land_heading - clampf(off_right * 0.3, -35.0, 35.0)
	var err := wrapf(hdg_t - _prop("attitude/psi-deg"), -180.0, 180.0)
	var dist := maxf((aim - ac.global_position).dot(land_dir), 0.0)
	var glide_ft := tan(deg_to_rad(3.5)) * dist / 0.3048
	var strip_y: float = world.point("strip").y
	var agl := (ac.global_position.y - strip_y) / 0.3048 - 4.0
	var theta_t := clampf(-1.0 + 0.03 * (glide_ft - agl) - 0.1 * (_prop("velocities/h-dot-fps") + 6.0), -8.0, 8.0)
	var thr := clampf(0.35 + 0.05 * (p.app_kias - _prop("velocities/vc-kts")), 0.0, 1.0)
	return {"pitch": _pitch_cmd(theta_t), "roll": _roll_cmd(clampf(err * 1.2, -20.0, 20.0)), "throttle": thr,
		"rudder": clampf(_prop("accelerations/Ny") * -4.0, -0.5, 0.5)}


func _ground_steer(hdg: float) -> Dictionary:
	var err := wrapf(hdg - _prop("attitude/psi-deg"), -180.0, 180.0)
	var r := rad_to_deg(_prop("velocities/r-rad_sec"))
	return {"rudder": clampf(0.08 * err - 0.1 * r, -1, 1), "roll": 0.0}


func _bearing(target: Vector3) -> float:
	return cl._bearing_to(target)


func _dist(target: Vector3) -> float:
	return cl._horizontal_distance(target)


func _gs() -> float:
	return _prop("velocities/vg-fps") * 0.5925
