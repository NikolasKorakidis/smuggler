extends Node
var world: Node3D
func _ready() -> void:
	FlightInput.joysticks_enabled = false
	world = load("res://world/test_world.tscn").instantiate()
	add_child(world)
	var e: EngineSystems = world.aircraft.engine
	var f: FDM = world.aircraft.fdm
	e.prime = 3.0
	e.set_magnetos(3)
	FlightInput.set_throttle_keyboard(0.05)
	e.click_starter = true
	for k in 120:
		if k == 12: e.click_starter = false
		await get_tree().physics_frame
		if k % 10 == 0:
			print("t=%.2f rpm=%.0f running=%s spark=%s swing=%.2f starter_cmd=%s" % [k / 120.0, f.prop_get("propulsion/engine/engine-rpm"), e.running(), e._spark_allowed, e._swing_t, f.prop_get("propulsion/starter_cmd")])
	get_tree().quit()
