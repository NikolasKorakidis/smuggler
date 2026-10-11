extends Node
## Walks the 172 checklist like a pilot: godot --headless --path game --fixed-fps 120 res://dev/checklist_test.tscn
var world: Node3D
var cl


func _ready() -> void:
	FlightInput.joysticks_enabled = false
	world = load("res://world/test_world.tscn").instantiate()
	add_child(world)
	world._spawn_aircraft(1)
	cl = world.get_node("Checklist")
	await _s(0.2)
	var e: EngineSystems = world.aircraft.engine
	_report("spawn")
	e.set_carb_heat(false); e.set_master(true)
	await _s(0.2); _report("before start done")
	e.stroke_primer(); e.stroke_primer(); e.stroke_primer()
	FlightInput.set_throttle_keyboard(0.1)
	await _s(0.2)
	cl._tick_manual(cl._items.filter(func(i): return i.cond == "manual")[0])
	e.set_magnetos(3)
	e.click_starter = true
	await _s(6.0)
	e.click_starter = false
	FlightInput.set_throttle_keyboard(0.03)
	await _s(8.0); _report("engine started")
	for a in ["pitch_back", "pitch_fwd", "roll_left", "roll_right", "rudder_left", "rudder_right"]:
		Input.action_press(a); await _s(0.6); Input.action_release(a); await _s(0.4)
	Input.action_press("brakes")
	FlightInput.set_throttle_keyboard(0.72)
	await _s(5.0)
	e.set_magnetos(2); await _s(2.0); e.set_magnetos(1); await _s(2.0); e.set_magnetos(3); await _s(1.0)
	e.set_carb_heat(true); await _s(2.0); e.set_carb_heat(false); await _s(1.0)
	_report("run-up rpm %.0f" % world.aircraft.fdm.prop_get("propulsion/engine/engine-rpm"))
	FlightInput.set_throttle_keyboard(0.03)
	await _s(6.0)
	Input.action_release("brakes")
	_report("final")
	var done: int = cl._items.filter(func(i): return i.done).size()
	print("CHECKLIST TEST: ", "PASS" if done == cl._items.size() else "FAIL %d/%d" % [done, cl._items.size()])
	get_tree().quit()


func _s(t: float) -> void:
	for i in int(t * 120):
		await get_tree().physics_frame


func _report(tag: String) -> void:
	var done: int = cl._items.filter(func(i): return i.done).size()
	var nxt = cl._items.filter(func(i): return not i.done)
	print("%-22s %2d/%d done   next: %s" % [tag, done, cl._items.size(), (nxt[0].item + " " + nxt[0].state) if nxt else "-"])
