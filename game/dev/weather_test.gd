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
	var w: AnemosWeather = world.weather
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
	FlightInput.parking_brake = false
	await _run_phase2(w, ac, f)


# Phase 2 weather: visibility, storms, carb ice, wet ground, fog, METAR.
func _run_phase2(w: AnemosWeather, ac: Aircraft, f: FDM) -> void:
	# Rain visibility ~ 12 km x R^-0.65 (moderate rain ~3 km, violent < 1 km).
	var v10 := AnemosWeather.KOSCHMIEDER / AnemosWeather.rain_extinction(10.0)
	var v75 := AnemosWeather.KOSCHMIEDER / AnemosWeather.rain_extinction(75.0)
	_check("rain visibility: 10 mm/h ~2.7 km, 75 mm/h < 1 km", absf(v10 - 2690.0) < 50.0 and v75 < 1000.0,
		"%.0f m, %.0f m" % [v10, v75])

	# Microburst (Vicroy): down at the core, out at the rim, calm at the ground.
	var cell := AnemosStormCell.new(Vector2.ZERO, Vector2.ZERO, 1.0, 0.0, 2000.0, 1500.0)
	cell.age = 0.5 * cell.life
	cell.step(0.0)
	var core := cell.wind_at(Vector3(0, 0, 0), 600.0)
	var rim := cell.wind_at(Vector3(2000, 0, 0), AnemosStormCell.ZM)
	var ground := cell.wind_at(Vector3(2000, 0, 0), 0.0)
	_check("microburst: downdraft at the core, outflow at the rim, calm at the ground",
		core.y < -5.0 and rim.x > 0.8 * cell.outflow_ms() and ground.length() < 0.1,
		"core %.1f m/s down, rim %.1f m/s out (peak %.1f), ground %.2f" % [-core.y, rim.x, cell.outflow_ms(), ground.length()])

	# JSBSim gets the downdraft: fly through a mature cell's core.
	w.set_preset(0, true)
	w.cells.clear()
	ac.teleport_air(ac.global_position + Vector3(0, 0, -3000), 0.0, w.field_elevation_m + 450.0, 90.0)
	await _s(0.5)
	var over := ac.global_position
	var c2 := w.spawn_storm(0.0, 0.0, 0.5, 1.2)
	c2.pos = Vector2(over.x, over.z)
	await _s(0.5)
	var down := f.prop_get("atmosphere/wind-down-fps")
	_check("storm core: JSBSim feels the downdraft", down > 15.0, "%.0f ft/s down (%.0f fpm)" % [down, down * 60.0])
	w.cells.clear()

	# Carb ice: humid 15 °C at cruise ices up; carb heat clears it, rough first.
	w.set_preset(0, true)
	w._target = {}
	w.temp_c = 15.0
	w.dewpoint_c = 13.0
	ac.teleport_air(ac.global_position, 0.0, w.field_elevation_m + 900.0, 75.0)
	ac.engine.carb_ice = 0.0
	FlightInput.override["throttle"] = 0.6
	await _s(240.0)
	var iced := ac.engine.carb_ice
	ac.engine.set_carb_heat(true)
	var rough := 0.0
	for i in 50:
		await _s(1.0)
		rough = maxf(rough, ac.engine.melt_rough)
	_check("carb ice: humid 15 °C (RH 88%) at cruise ices up; carb heat clears it (rough while melting)",
		iced > 0.2 and ac.engine.carb_ice < 0.05 and rough > 0.05,
		"ice %.2f after 240 s, %.2f after 50 s of heat, roughness up to %.2f" % [iced, ac.engine.carb_ice, rough])
	ac.engine.set_carb_heat(false)
	w.temp_c = 15.0
	w.dewpoint_c = 5.0
	ac.engine.carb_ice = 0.0
	await _s(240.0)
	_check("carb ice: dry 15 °C (RH 51%) stays clear", ac.engine.carb_ice < 0.03, "ice %.3f" % ac.engine.carb_ice)
	FlightInput.override.erase("throttle")

	# Wet runway: less grip.
	f.set_surface(&"paved", 0.0)
	var dry := f.prop_get("ground/static-friction-factor")
	f.set_surface(&"paved", 1.0)
	var soaked := f.prop_get("ground/static-friction-factor")
	_check("wet runway: grip falls", soaked < dry * 0.7, "static factor %.2f dry, %.2f soaked" % [dry, soaked])
	f.set_surface(&"paved", 0.0)

	# Ground soaks in steady rain.
	w.set_preset(8, true)
	w.wetness = 0.0
	w.focus = ac.global_position
	await _s(60.0)
	_check("steady rain soaks the ground", w.wetness > 0.05, "wetness %.2f after 60 s" % w.wetness)

	# Valley fog burns off by noon; METAR reads it.
	w.set_preset(6, true)
	var tod: TimeOfDay = world.time_of_day
	tod.set_hours(5.9)
	var dawn := w.fog_now()
	var metar_fog := w.metar()
	tod.set_hours(12.0)
	var noon := w.fog_now()
	_check("valley fog at dawn, gone by noon", dawn.y > 0.9 and noon.y < 0.01, "%s / %s" % [dawn, noon])
	_check("METAR shows fog", metar_fog.contains("FG"), metar_fog)
	w.set_preset(9, true)
	w.cells.clear()
	var c3 := w.spawn_storm(5000.0, 90.0, 0.5)
	_check("METAR shows a thunderstorm nearby", w.metar().contains("TS") and w.metar().contains("CB"), w.metar())
