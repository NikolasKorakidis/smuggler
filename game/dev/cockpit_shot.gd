extends Node
## Cold-and-dark cockpit screenshot: godot --path game res://dev/cockpit_shot.tscn -- --aircraft=1 --out=x.png
var world: Node3D
var f := 0
var out := "user://cockpit.png"
func _ready() -> void:
	FlightInput.joysticks_enabled = false
	world = load("res://world/test_world.tscn").instantiate()
	add_child(world)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--aircraft="):
			world._spawn_aircraft(int(a.trim_prefix("--aircraft=")))
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var cam = world.get_node("CameraRig")
	cam.mode = cam.Mode.COCKPIT
	cam.recentre()
	cam.look_pitch = deg_to_rad(-14.0)
func _process(_d: float) -> void:
	f += 1
	if f == 20 and "--primer-step" in OS.get_cmdline_user_args():
		FlightInput.parking_brake = true
		world.aircraft.engine.set_master(true)
	if f == 40:
		get_viewport().get_texture().get_image().save_png(out)
		get_tree().quit()
