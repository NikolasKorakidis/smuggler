extends Node
## Weather reaches JSBSim and the visuals: godot --headless --path game --fixed-fps 120 res://dev/weather_test.tscn
var world: Node3D
var failures := 0


func _ready() -> void:
	FlightInput.joysticks_enabled = false
	world = load("res://world/test_world.tscn").instantiate()
	world.start_engine_running = true
	add_child(world)
	world._spawn_aircraft(1)
	await _run()
	print("WEATHER TEST: ", "PASS" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(failures)


func _check(name: String, ok: bool, detail := "") -> void:
	print(("  ok   " if ok else "  FAIL ") + name + ("   " + detail if detail else ""))
	if not ok:
		failures += 1


func _s(t: float) -> void:
	for i in int(t * 120):
		await get_tree().physics_frame


func _run() -> void:
	var w: Weather = world.weather
	var ac: Aircraft = world.aircraft
	var f := ac.fdm
	# Wind into JSBSim. Light breeze from 060: ahead of a plane facing north,
	# so the ground tailwind guard leaves it alone.
	w.set_preset(1, true)
	await _s(1.0)
	var n := f.prop_get("atmosphere/wind-north-fps")
	var e := f.prop_get("atmosphere/wind-east-fps")
	var from := fposmod(rad_to_deg(atan2(-e, -n)), 360.0)
	_check("JSBSim wind direction near the ground", absf(wrapf(from - 60.0, -180, 180)) < 10.0, "%.0f°" % from)
	w.set_preset(2, true)  # gusty crosswind, from 150°
	await _s(1.0)
	# Stronger and veered aloft.
	var low := w.mean_wind(10.0)
	var high := w.mean_wind(900.0)
	_check("wind strengthens and veers with height", high.y > low.y * 1.5 and high.x > low.x + 15.0,
		"10 m %.0f kt/%.0f°, 900 m %.0f kt/%.0f°" % [low.y, low.x, high.y, high.x])
	# Gusts over a minute stay between the mean and mean + gust.
	var lo := INF
	var hi := 0.0
	for i in 60 * 4:
		await _s(0.25)
		var v := w.air_velocity(10.0)
		var kt := Vector2(v.x, v.z).length() / 0.514444
		lo = minf(lo, kt)
		hi = maxf(hi, kt)
	_check("gusts come and go", hi - lo > 4.0 and hi <= w.wind_kt + w.gust_kt + 0.5 and lo >= w.wind_kt - 0.5,
		"%.1f..%.1f kt (mean %d, gusts +%d)" % [lo, hi, int(w.wind_kt), int(w.gust_kt)])
	# Windsock tail points the way the air blows (towards 330° for wind from 150°).
	var sock: Node3D = world.find_child("Windsock", true, false)
	var tail: Vector3 = -sock.get_child(1).global_basis.z
	var tail_dir := fposmod(rad_to_deg(atan2(tail.x, -tail.z)), 360.0)
	_check("windsock points downwind", absf(wrapf(tail_dir - 330.0, -180, 180)) < 25.0, "tail towards %.0f°" % tail_dir)
	# Low pressure: altimeter at 29.92 reads high on the ground until set.
	var alt: AltimeterGauge = ac.airframe.find_child("Altimeter", true, false)
	ac.altimeter_setting_inhg = 29.92
	await _s(0.5)
	var wrong := alt._read()
	ac.altimeter_setting_inhg = snappedf(w.qnh_hpa * 0.02953, 0.01)
	await _s(0.5)
	var right := alt._read()
	_check("QNH 1006: altimeter reads ~200 ft high until set", wrong > 150.0 and absf(right) < 30.0,
		"at 29.92: %.0f ft, at %.2f: %.0f ft (field 0)" % [wrong, ac.altimeter_setting_inhg, right])
	# Hot day: density altitude well above the field.
	w.set_preset(3, true)
	await _s(0.5)
	_check("hot afternoon: density altitude high", f.prop_get("atmosphere/density-altitude") > 2000.0,
		"%.0f ft at a sea-level field" % f.prop_get("atmosphere/density-altitude"))
	# Parked in strong gusty wind with brakes: stays put.
	w.set_preset(4, true)
	FlightInput.parking_brake = true
	var p0 := ac.global_position
	await _s(20.0)
	var upright := absf(f.prop_get("attitude/phi-deg")) < 15.0 and absf(f.prop_get("attitude/theta-deg")) < 15.0
	_check("parked with brakes in 20 kt gusting 32: stays put and upright",
		ac.global_position.distance_to(p0) < 2.0 and upright,
		"moved %.2f m, pitch %.1f roll %.1f" % [ac.global_position.distance_to(p0), f.prop_get("attitude/theta-deg"), f.prop_get("attitude/phi-deg")])
