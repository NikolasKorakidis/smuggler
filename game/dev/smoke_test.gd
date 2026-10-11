extends Node
## Headless check that the world loads and the aircraft takes off in Godot.
## godot --headless --path game --fixed-fps 60 res://dev/smoke_test.tscn [-- --aircraft=1 --world=terrain]

const WORLDS := {
	"test": "res://world/test_world.tscn",
	"terrain": "res://world/terrain_tile/terrain_tile.tscn",
}

var world: Node3D
var frames := 0
var takeoff_frame := -1
var rotate_kias := 30.0
var runway_heading := 0.0


func _ready() -> void:
	FlightInput.joysticks_enabled = false
	var world_path: String = WORLDS.test
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--world="):
			world_path = WORLDS.get(a.trim_prefix("--world="), world_path)
	world = load(world_path).instantiate()
	world.start_engine_running = true
	add_child(world)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--aircraft="):
			world._spawn_aircraft(int(a.trim_prefix("--aircraft=")))
	if world.aircraft.definition.jsbsim_model != "J3Cub":
		rotate_kias = 55.0
	runway_heading = world.spawn_point().heading_deg
	print("aircraft: ", world.aircraft.definition.display_name, "  world: ", world_path)


func _process(_delta: float) -> void:
	frames += 1
	var ac: Aircraft = world.aircraft
	if ac == null or ac.fdm.jsb == null:
		print("FAIL: aircraft not loaded")
		get_tree().quit(1)
		return
	var f := ac.fdm
	if frames == 2:
		var lowest := INF
		for w in ac.airframe.wheel_contacts():
			lowest = minf(lowest, w.point.y - world.terrain_height(w.point))
		print("at rest: CG y=%.2f m, lowest wheel bottom above ground=%.3f m, pitch=%.1f, surface=%s" % [
			ac.global_position.y, lowest, f.prop_get("attitude/theta-deg"), f.surface])
		FlightInput.set_throttle_keyboard(1.0)
	var hdg := wrapf(f.prop_get("attitude/psi-deg") - runway_heading, -180.0, 180.0)
	var r := clampf(-0.15 * hdg - 0.1 * rad_to_deg(f.prop_get("velocities/r-rad_sec")), -1.0, 1.0)
	Input.action_release("rudder_left")
	Input.action_release("rudder_right")
	if r > 0.0:
		Input.action_press("rudder_right", r)
	elif r < 0.0:
		Input.action_press("rudder_left", -r)
	var kias := f.prop_get("velocities/vc-kts")
	Input.action_release("pitch_back")
	if kias > rotate_kias:
		Input.action_press("pitch_back", 0.35)
	if frames % 120 == 0:
		print("t=%4.1f KIAS=%5.1f AGL=%6.1f ft HDG=%6.1f pos=(%.0f, %.1f, %.0f) %s rpm=%.0f fps=%d" % [
			frames / 60.0, kias, f.prop_get("position/h-agl-ft"), hdg,
			ac.global_position.x, ac.global_position.y, ac.global_position.z, f.surface,
			f.prop_get("propulsion/engine/engine-rpm"), Engine.get_frames_per_second()])
	_shots()
	if takeoff_frame < 0 and f.prop_get("position/h-agl-ft") > 30.0:
		takeoff_frame = frames
	if frames >= 60 * 45:
		print("RESULT: " + ("PASS airborne at t=%.1f s" % (takeoff_frame / 60.0) if takeoff_frame > 0 else "FAIL never climbed"))
		get_tree().quit(0 if takeoff_frame > 0 else 1)


# Pass "-- --shots=<dir>" (non-headless) to save screenshots along the way.
func _shots() -> void:
	var dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			dir = a.trim_prefix("--shots=")
	if dir == "":
		return
	var cam = world.get_node("CameraRig")
	var plan := {90: "rest_chase", 100: "", 160: "rest_cockpit", 170: "", 1500: "climb_chase", 1800: "", 1850: "climb_cockpit"}
	if frames in plan:
		if plan[frames] == "":
			cam.mode = 1 - cam.mode
			cam.fov = 70.0
			return
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, plan[frames]])
		if plan[frames] == "climb_cockpit":
			get_tree().quit()
