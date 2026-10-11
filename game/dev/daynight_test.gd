extends Node
## Day/night: godot --headless --path game --fixed-fps 60 res://dev/daynight_test.tscn
var world: Node3D
var failures := 0


func _ready() -> void:
	FlightInput.joysticks_enabled = false
	world = load("res://world/terrain_tile/terrain_tile.tscn").instantiate()
	add_child(world)
	world._spawn_aircraft(1)
	await _run()
	print("DAYNIGHT TEST: ", "PASS" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(failures)


func _check(name: String, ok: bool, detail := "") -> void:
	print(("  ok   " if ok else "  FAIL ") + name + ("   " + detail if detail else ""))
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	var tod: TimeOfDay = world.time_of_day
	var ac: Aircraft = world.aircraft
	tod.time_scale = 0.0
	tod.set_hours(12.0)
	await _frames(3)
	_check("noon: sun high, full daylight", tod.sun_elevation_deg() > 60.0 and tod.darkness() == 0.0,
		"sun %+.0f°" % tod.sun_elevation_deg())
	tod.set_hours(6.0)
	await _frames(3)
	var east := tod.sun_direction()
	_check("morning sun in the east", east.x > 0.5, "dir %s" % str(east))
	tod.set_hours(22.0)
	await _frames(3)
	_check("22:00: sun well below the horizon, dark", tod.sun_elevation_deg() < -20.0 and tod.darkness() == 1.0,
		"sun %+.0f°" % tod.sun_elevation_deg())
	_check("sun light off at night", not world.get_node("Sun").visible)
	_check("hangar lamp on at night", world._lamps.all(func(l): return l.visible))
	# Clock runs at the compressed rate.
	tod.time_scale = 60.0
	var h0 := tod.hours
	await get_tree().create_timer(1.0).timeout
	var gained := fposmod(tod.hours - h0, 24.0) * 3600.0
	_check("time runs compressed (60x)", gained > 40.0 and gained < 90.0, "%.0f game s in 1 real s" % gained)
	tod.time_scale = 0.0
	# Lights need the master switch.
	var spot: SpotLight3D = ac.find_child("LandingLight", true, false)
	ac.engine.set_master(false)
	ac.lights.landing = true
	await _frames(3)
	_check("landing light dark with master off", not spot.visible)
	ac.engine.set_master(true)
	await _frames(3)
	_check("landing light on with master on", spot.visible)
	# Panel lighting: gauges dim at night, bright with panel lights.
	var alt: GaugeBase = ac.airframe.find_child("Altimeter", true, false)
	await _frames(3)
	var dim: float = alt._face_mats[0].emission_energy_multiplier
	ac.lights.panel = true
	await _frames(3)
	var lit: float = alt._face_mats[0].emission_energy_multiplier
	_check("gauges dark at night, backlit with panel lights", dim < 0.05 and lit > 0.2, "%.3f -> %.3f" % [dim, lit])
	tod.set_hours(12.0)
	ac.lights.panel = false
	await _frames(3)
	_check("gauges normal by day", alt._face_mats[0].emission_energy_multiplier > 0.25)
	_check("hangar lamp off by day", world._lamps.all(func(l): return not l.visible))
