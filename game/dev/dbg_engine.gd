extends Node
var world: Node3D
func _ready() -> void:
	FlightInput.joysticks_enabled = false
	world = load("res://world/test_world.tscn").instantiate()
	world.start_engine_running = true
	add_child(world)
	world._spawn_aircraft(1)
	var ac: Aircraft = world.aircraft
	var f := ac.fdm
	world.weather.set_preset(4)
	FlightInput.parking_brake = true
	var p0 := ac.global_position
	for k in 20:
		for i in 120: await get_tree().physics_frame
		print("t=%2d moved=%5.1f m  gs=%4.1f kt  hdg=%5.1f pitch=%5.1f roll=%5.1f  wow=%d%d%d  brakeL=%.1f  alpha=%6.1f beta=%6.1f  vc=%5.1f  Fx=%6.0f Fy=%6.0f Fz=%6.0f  gearFx=%6.0f" % [k + 1,
			ac.global_position.distance_to(p0), f.prop_get("velocities/vg-fps") * 0.5925, f.prop_get("attitude/psi-deg"),
			f.prop_get("attitude/theta-deg"), f.prop_get("attitude/phi-deg"),
			f.prop_get("gear/unit[0]/WOW"), f.prop_get("gear/unit[1]/WOW"), f.prop_get("gear/unit[2]/WOW"),
			f.prop_get("fcs/left-brake-cmd-norm"), f.prop_get("aero/alpha-deg"), f.prop_get("aero/beta-deg"), f.prop_get("velocities/vc-kts"),
			f.prop_get("forces/fbx-aero-lbs"), f.prop_get("forces/fby-aero-lbs"), f.prop_get("forces/fbz-aero-lbs"), f.prop_get("forces/fbx-gear-lbs")])
	get_tree().quit()
