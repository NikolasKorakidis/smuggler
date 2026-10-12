extends Node
## Day/night and weather screenshots: godot --path game res://dev/daynight_shot.tscn -- --hours=19 [--lights] [--panel] [--cockpit]
## [--weather=N] [--storm=dist_m,bearing] [--look=az,el] [--alt=m] [--fogdebug] [--hideui] --out=x.png
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
	if args.has("weather"):  # --weather=<preset index>
		world.weather.set_preset(int(args.weather), true)
	if args.has("fogdebug"):
		world.get_node("WeatherFX").debug_fog = 1 if String(args.fogdebug) == "true" else int(args.fogdebug)
	if args.has("storm"):  # --storm=dist_m,bearing: a mature cell there
		var sb: PackedStringArray = String(args.storm).split(",")
		world.weather.spawn_storm(float(sb[0]), float(sb[1]), 0.45)
	if args.has("nofx"):  # --nofx=fog|clouds|all: switch weather effects off (A/B)
		var env_node: WorldEnvironment = world.get_node("WorldEnvironment")
		for e in env_node.compositor.compositor_effects:
			var off := String(args.nofx)
			if off == "all" or (off == "fog" and e is FogEffect) or (off == "clouds" and e is SunshineCloudsGD):
				e.enabled = false
	if args.has("wet"):  # --wet=0..1 ground wetness
		world.weather.wetness = float(args.wet)
		world.weather.set_physics_process(false)  # hold it
	if args.has("glassdebug"):
		var g: MeshInstance3D = world.aircraft.find_child("Windshield", true, false)
		g.material_override.set_shader_parameter("debug_mode", int(args.glassdebug))
	if args.has("nomw"):
		world.time_of_day.milkyway_brightness = 0.0
	if args.has("hideui"):
		for ui in get_tree().root.find_children("*", "CanvasLayer", true, false):
			ui.visible = false
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
	if args.has("look"):  # --look=az,el (degrees): free camera looking at the sky
		var cam: Camera3D = world.get_node("CameraRig")
		cam.target = null
		var ae: PackedStringArray = String(args.look).split(",")
		var az := deg_to_rad(float(ae[0]))
		var el := deg_to_rad(float(ae[1]))
		var dir := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
		var at: Vector3 = world.aircraft.global_position + Vector3(0, float(args.get("alt", "3")), 0)
		cam.global_position = at
		cam.look_at(at + dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.BACK)
		cam.fov = float(args.get("fov", "80"))
	if f == 57 and args.has("strike"):  # --strike=dist_m,bearing: a bolt 3 frames before the shot
		var sb: PackedStringArray = String(args.strike).split(",")
		var b := deg_to_rad(float(sb[1]))
		var at: Vector3 = world.aircraft.global_position + Vector3(sin(b), 0.0, -cos(b)) * float(sb[0])
		at.y = world.terrain_height(at) if world.has_method("terrain_height") else 0.0
		world.get_node("WeatherFX/Lightning").hold = true
		world.weather.lightning.emit(at, true, 1.0)
	if f == 60:
		get_viewport().get_texture().get_image().save_png(args.get("out", "user://dn.png"))
		get_tree().quit()
