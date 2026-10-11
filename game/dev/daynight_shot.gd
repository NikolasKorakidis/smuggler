extends Node
## Day/night screenshots: godot --path game res://dev/daynight_shot.tscn -- --hours=19 [--lights] [--panel] [--cockpit] --out=x.png
var world: Node3D
var f := 0
var args := {}


func _ready() -> void:
	FlightInput.joysticks_enabled = false
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else true
	world = load("res://world/terrain_tile/terrain_tile.tscn").instantiate()
	world.start_engine_running = true
	add_child(world)
	world._spawn_aircraft(int(args.get("aircraft", "1")))
	world.time_of_day.time_scale = 0.0
	world.time_of_day.set_hours(float(args.get("hours", "13")))
	var ac: Aircraft = world.aircraft
	if args.has("lights"):
		ac.lights.landing = true
		ac.lights.nav = true
	if args.has("panel"):
		ac.lights.panel = true
	var cam = world.get_node("CameraRig")
	if args.has("cockpit"):
		cam.mode = cam.Mode.COCKPIT
		cam.recentre()
		cam.look_pitch = deg_to_rad(-12.0)
	else:
		cam.orbit_yaw = deg_to_rad(float(args.get("yaw", "160")))
		cam.orbit_pitch = deg_to_rad(12.0)
		cam.chase_distance = 14.0


func _process(_d: float) -> void:
	f += 1
	if f == 60:
		get_viewport().get_texture().get_image().save_png(args.get("out", "user://dn.png"))
		get_tree().quit()
