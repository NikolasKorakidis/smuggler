extends Node
## Frame-time check of the terrain tile from typical views (needs a window):
## godot --path game --resolution 1920x1080 res://dev/terrain_bench.tscn [-- --shots=<dir>] [--weather=N] [--storm]
## Vsync is switched off so the numbers show real headroom.

const WARMUP_FRAMES := 90
const MEASURE_FRAMES := 300

var world: Node3D
var cam: Camera3D


func _ready() -> void:
	FlightInput.joysticks_enabled = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	world = load("res://world/terrain_tile/terrain_tile.tscn").instantiate()
	add_child(world)
	cam = world.get_node("CameraRig")
	world.get_node("Checklist").visible = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weather="):  # weather preset for the whole run
			world.weather.set_preset(int(a.trim_prefix("--weather=")), true)
		if a == "--storm":  # a mature storm 3 km away
			world.weather.spawn_storm(3000.0, 45.0, 0.45)
		if a.begins_with("--nofx="):  # clouds, fog, rain: switch one off to see its cost
			var fx: WeatherFX = world.get_node("WeatherFX")
			match a.trim_prefix("--nofx="):
				"clouds": fx.atmosphere.clouds_enabled = false
				"fog": fx.atmosphere.fog_enabled = false
				"rain": fx.get_node("Rain").process_mode = Node.PROCESS_MODE_DISABLED
		if a.begins_with("--cloudsteps="):
			world.get_node("WeatherFX").clouds.steps = int(a.trim_prefix("--cloudsteps="))
	await _run()
	get_tree().quit()


func _run() -> void:
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.trim_prefix("--shots=")
	print("viewport: ", get_viewport().get_visible_rect().size, "  window: ", DisplayServer.window_get_size())
	var valley: Dictionary = world.strips[0]
	var ridge: Dictionary = world.strips[1]
	await _measure("chase_on_paved_strip", shots)
	cam.target = null
	var v0: Vector3 = world.spawn_point().position
	var fwd := Vector3(valley.dir.x, 0.0, valley.dir.y)
	_place(v0 - fwd * 20.0 + Vector3(0, 3.0, 0), v0 + fwd * 600.0)
	await _measure("ground_down_paved_strip", shots)
	var r0 := Vector3(ridge.centre.x, ridge.elevation, ridge.centre.y)
	var rfwd := Vector3(ridge.dir.x, 0.0, ridge.dir.y)
	_place(r0 - rfwd * 2000.0 + Vector3(0, 120.0, 0), r0)
	await _measure("approach_to_dirt_strip", shots)
	_place(r0 - rfwd * 330.0 + Vector3(0, 2.5, 0), r0 + rfwd * 300.0)
	await _measure("ground_on_dirt_strip", shots)
	var hangar: Vector3 = world.get_node("Hangar").global_position
	_place(hangar + Vector3(valley.side.x, 0, valley.side.y) * 60.0 + fwd * 25.0 + Vector3(0, 2.0, 0), hangar + Vector3(0, 3, 0))
	await _measure("apron_and_hangar", shots)
	_place(Vector3(-2500, 450.0, 2500), Vector3(500, 150.0, -500))
	await _measure("low_over_valley_300m", shots)
	_place(Vector3(-6000, 2000.0, 6000), Vector3(0, 150.0, -1000))
	await _measure("high_overview_2000m", shots)


func _place(from: Vector3, to: Vector3) -> void:
	cam.global_position = from
	cam.look_at(to, Vector3.UP)


func _measure(label: String, shots: String) -> void:
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in WARMUP_FRAMES:
		await get_tree().process_frame
	var gpu := 0.0
	var cpu := 0.0
	var t0 := Time.get_ticks_usec()
	var worst := 0
	var last := t0
	for i in MEASURE_FRAMES:
		await get_tree().process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
	var avg_ms := (Time.get_ticks_usec() - t0) / 1000.0 / MEASURE_FRAMES
	print("%-26s avg %5.2f ms (%3.0f fps)  gpu %5.2f  render-cpu %5.2f  worst %5.2f ms  draws %d  prims %dk" % [label, avg_ms, 1000.0 / avg_ms,
		gpu / MEASURE_FRAMES, cpu / MEASURE_FRAMES, worst / 1000.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000])
	if shots != "":
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shots, label])

