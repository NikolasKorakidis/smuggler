extends Node
var world: Node3D
func _ready() -> void:
	FlightInput.joysticks_enabled = false
	world = load("res://world/test_world.tscn").instantiate()
	add_child(world)
	world._spawn_aircraft(1)
	var e: EngineSystems = world.aircraft.engine
	var f: FDM = world.aircraft.fdm
	FlightInput.set_throttle_keyboard(0.05)
	e.set_master(true); e.set_magnetos(3)
	e.click_starter = true  # no prime: cranks without catching
	var t := []
	for k in 6:
		for i in 60: await get_tree().physics_frame
		t.append("%.0f" % f.prop_get("propulsion/engine/engine-rpm"))
	print("cranking, unprimed (rpm every 0.5 s): ", " ".join(t), "  running=", e.running())
	e.click_starter = false
	await get_tree().create_timer(0.1).timeout
	e.prime = 3.0
	e.click_starter = true
	t = []
	for k in 10:
		for i in 30: await get_tree().physics_frame
		t.append("%.0f%s" % [f.prop_get("propulsion/engine/engine-rpm"), "*" if e.running() else ""])
	e.click_starter = false
	for i in 240: await get_tree().physics_frame
	print("primed (rpm every 0.25 s, * = firing): ", " ".join(t), "  idle after release: %.0f running=%s" % [f.prop_get("propulsion/engine/engine-rpm"), e.running()])
	get_tree().quit()
