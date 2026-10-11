extends Node
## Headless start-procedure checks for both aircraft:
## godot --headless --path game --fixed-fps 120 res://dev/engine_test.tscn
var world: Node3D
var failures := 0


func _ready() -> void:
	FlightInput.joysticks_enabled = false
	world = load("res://world/test_world.tscn").instantiate()
	add_child(world)
	await _run()
	print("ENGINE TESTS: ", "PASS" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(failures)


func _secs(t: float) -> void:
	for i in int(t * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


func _check(name: String, ok: bool, detail := "") -> void:
	print(("  ok   " if ok else "  FAIL ") + name + ("  " + detail if detail else ""))
	if not ok:
		failures += 1


func _crank(e: EngineSystems, t: float) -> bool:
	e.click_starter = true
	for i in int(t * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
		if e.running():
			break
	e.click_starter = false
	await _secs(1.0)
	return e.running()


func _swings(e: EngineSystems, n: int) -> bool:
	for i in n:
		e.click_starter = true
		await _secs(0.1)
		e.click_starter = false
		await _secs(1.0)
		if e.running():
			return true
	return e.running()


func _run() -> void:
	# --- 172 ---
	world._spawn_aircraft(1)
	var e: EngineSystems = world.aircraft.engine
	FlightInput.set_throttle_keyboard(0.1)
	_check("172 spawns cold and dark", not e.running() and not e.master and e.magnetos == 0)
	e.set_master(true)
	e.set_magnetos(3)
	_check("172 cold, no prime: won't start in 4 s", not await _crank(e, 4.0))
	e.stroke_primer(); e.stroke_primer(); e.stroke_primer()
	_check("172 cold, 3 primes: starts", await _crank(e, 8.0), "rpm %.0f" % world.aircraft.fdm.prop_get("propulsion/engine/engine-rpm"))
	e.set_fuel_selector(0)
	await _secs(10.0)
	_check("172 fuel OFF: still running after 10 s (fuel in lines)", e.running())
	await _secs(15.0)
	_check("172 fuel OFF: stopped after 25 s", not e.running())
	e.set_fuel_selector(2)
	world.aircraft.respawn()
	e.set_master(true)
	e.set_magnetos(3)
	for i in 9:
		e.stroke_primer()
	_check("172 over-primed (9): flooded, won't start", not await _crank(e, 4.0))
	e.set_mixture(0.0)
	FlightInput.set_throttle_keyboard(1.0)
	await _crank(e, 4.0)
	e.set_mixture(1.0)
	FlightInput.set_throttle_keyboard(0.1)
	_check("172 cleared flood, then starts", await _crank(e, 8.0), "prime %.1f" % e.prime)
	e.set_magnetos(0)
	await _secs(3.0)
	_check("172 magnetos OFF stops it", not e.running())
	world.aircraft.respawn()
	e.auto_start()
	await _secs(8.0)
	_check("172 auto-start (Ctrl+E)", e.running())

	# --- Cub (hand-propped) ---
	world._spawn_aircraft(0)
	e = world.aircraft.engine
	FlightInput.set_throttle_keyboard(0.05)
	_check("Cub spawns cold", not e.running())
	e.set_magnetos(3)
	_check("Cub cold, not pulled through: 3 swings fail", not await _swings(e, 3))
	world.aircraft.respawn()
	e.set_magnetos(0)
	await _swings(e, 4)
	_check("Cub pulled through 4 blades, switch off: primed", e.prime > 2.0, "prime %.1f" % e.prime)
	e.set_magnetos(3)
	_check("Cub 'contact': starts within 6 swings", await _swings(e, 6))
	world.aircraft.respawn()
	e.auto_start()
	await _secs(10.0)
	_check("Cub auto-start (Ctrl+E)", e.running())
