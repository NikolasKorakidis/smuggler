extends Node
## Walks both checklists like a pilot: godot --headless --path game --fixed-fps 120 res://dev/checklist_test.tscn
var world: Node3D
var cl
var failures := 0


func _ready() -> void:
	FlightInput.joysticks_enabled = false
	world = load("res://world/test_world.tscn").instantiate()
	add_child(world)
	cl = world.get_node("Checklist")
	await _walk_172()
	await _walk_cub()
	print("CHECKLIST TEST: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(failures)


func _walk_172() -> void:
	world._spawn_aircraft(1)
	await _s(0.2)
	var e: EngineSystems = world.aircraft.engine
	_report("172 spawn")
	_glow_check("ParkingBrake")
	FlightInput.parking_brake = true
	e.set_master(true)
	await _s(0.2); _report("172 before start")
	_glow_check("Primer")
	e.stroke_primer(); e.stroke_primer(); e.stroke_primer()
	FlightInput.set_throttle_keyboard(0.1)
	await _s(0.2)
	cl._tick_manual(cl._items.filter(func(i): return i.cond == "manual")[0])
	e.set_magnetos(3)
	await _s(0.1)
	_glow_check("Ignition")
	e.click_starter = true
	for i in 120 * 8:
		await get_tree().physics_frame
		if e.running(): break
	e.click_starter = false
	FlightInput.set_throttle_keyboard(0.03)
	await _s(8.0); _report("172 engine started")
	await _before_takeoff(e, 0.72)
	world.aircraft.set_flap_notch(1)
	await _s(0.5)
	FlightInput.parking_brake = false
	await _s(0.5)
	_finish("172")


func _walk_cub() -> void:
	world._spawn_aircraft(0)
	await _s(0.2)
	var e: EngineSystems = world.aircraft.engine
	FlightInput.set_throttle_keyboard(0.0)
	FlightInput.parking_brake = true
	await _s(0.2); _report("Cub brakes set")
	for k in 4:
		await _swing(e)
	_report("Cub pulled through")
	FlightInput.set_throttle_keyboard(0.08)
	e.set_magnetos(3)
	for k in 10:
		if e.running(): break
		await _swing(e)
	FlightInput.set_throttle_keyboard(0.0)
	await _s(8.0); _report("Cub engine started")
	await _before_takeoff(e, 0.8)
	_finish("Cub")


func _before_takeoff(e: EngineSystems, runup_throttle: float) -> void:
	for a in ["pitch_back", "pitch_fwd", "roll_left", "roll_right", "rudder_left", "rudder_right"]:
		Input.action_press(a); await _s(0.6); Input.action_release(a); await _s(0.4)
	FlightInput.set_throttle_keyboard(runup_throttle)
	await _s(5.0)
	e.set_magnetos(2); await _s(2.0); e.set_magnetos(1); await _s(2.0); e.set_magnetos(3); await _s(1.0)
	e.set_carb_heat(true); await _s(2.0); e.set_carb_heat(false); await _s(1.0)
	_report("run-up %.0f rpm" % world.aircraft.fdm.prop_get("propulsion/engine/engine-rpm"))
	FlightInput.set_throttle_keyboard(0.0)
	await _s(6.0)
	FlightInput.parking_brake = false
	await _s(0.5)


func _swing(e: EngineSystems) -> void:
	e.click_starter = true
	await _s(0.1)
	e.click_starter = false
	await _s(1.0)


func _finish(tag: String) -> void:
	var done: int = cl._items.filter(func(i): return i.done).size()
	_report(tag + " final")
	# Ground part only: everything up to and including BEFORE TAKEOFF must tick.
	var ground: Array = cl._items.filter(func(i): return i.section in ["BEFORE START", "STARTING ENGINE", "AFTER START", "BEFORE TAKEOFF"])
	var ground_done: int = ground.filter(func(i): return i.done and not i.skipped).size()
	if ground_done != ground.size():
		failures += 1
		print("  FAIL %s: ground steps %d/%d" % [tag, ground_done, ground.size()])
		for i in ground:
			if i.skipped or not i.done:
				print("    not ticked: %s %s" % [i.item, i.state])


func _glow_check(target: String) -> void:
	var ok: bool = cl._glow != null and cl._glow.get_parent() != null and cl._glow.get_parent().name == target
	print("  glow on %s: %s" % [target, "ok" if ok else "FAIL (%s)" % (cl._glow.get_parent().name if cl._glow else "none")])
	if not ok:
		failures += 1


func _s(t: float) -> void:
	for i in int(t * 120):
		await get_tree().physics_frame


func _report(tag: String) -> void:
	var done: int = cl._items.filter(func(i): return i.done).size()
	var nxt = cl._items.filter(func(i): return not i.done)
	print("%-24s %2d/%d done   next: %s" % [tag, done, cl._items.size(), (nxt[0].item + " " + nxt[0].state) if nxt else "-"])
