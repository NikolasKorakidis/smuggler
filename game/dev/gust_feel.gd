extends Node
## How hard wind throws the aircraft around, hands off after trimming.
##   godot --headless --path game --fixed-fps 120 res://dev/gust_feel.tscn -- --aircraft=1 --weather=2
var world: Node3D
var ac: Aircraft
var t := 0.0
var theta := 2.0
var h0 := 0.0
var trim := {}
var rec := {"bank": [], "pitch": [], "p": [], "q": [], "nz": [], "kias": [], "psi": []}
var weather := 2


func _ready() -> void:
	process_physics_priority = -50
	FlightInput.joysticks_enabled = false
	var idx := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--aircraft="):
			idx = int(a.trim_prefix("--aircraft="))
		if a.begins_with("--weather="):
			weather = int(a.trim_prefix("--weather="))
	world = load("res://world/test_world.tscn").instantiate()
	world.start_engine_running = true
	add_child(world)
	world._spawn_aircraft(idx)
	ac = world.aircraft
	world.weather.set_preset(weather, true)  # trim in the wind itself
	# Start in the air at 1500 ft
	var f := ac.fdm
	f.prop("ic/h-agl-ft", 1500.0)
	f.prop("ic/vc-kts", 90.0 if idx == 1 else 60.0)
	f.prop("ic/psi-true-deg", 60.0)
	f.jsb.run_ic()
	f.start_engines()
	h0 = f.prop_get("position/h-sl-ft")


func _p(n: String) -> float:
	return ac.fdm.prop_get(n)


func _physics_process(delta: float) -> void:
	t += delta
	var o := {}
	if true:  # gentle pilot: loose wings-level and altitude hold throughout
		theta += delta * 0.02 * (h0 - _p("position/h-sl-ft"))
		var pitch := clampf(0.04 * (theta + 0.03 * (h0 - _p("position/h-sl-ft")) - 0.1 * _p("velocities/h-dot-fps") - _p("attitude/theta-deg")) - 0.05 * rad_to_deg(_p("velocities/q-rad_sec")), -1, 1)
		var roll := clampf(0.025 * (0.0 - _p("attitude/phi-deg")) - 0.01 * rad_to_deg(_p("velocities/p-rad_sec")), -1, 1)
		o = {"pitch": pitch, "roll": roll, "throttle": 0.7, "rudder": 0.0}
		trim = o
	if t > 42.0:
			rec.bank.append(_p("attitude/phi-deg"))
			rec.pitch.append(_p("attitude/theta-deg"))
			rec.p.append(rad_to_deg(_p("velocities/p-rad_sec")))
			rec.q.append(rad_to_deg(_p("velocities/q-rad_sec")))
			rec.nz.append(_p("accelerations/n-pilot-z-norm"))
			rec.kias.append(_p("velocities/vc-kts"))
	FlightInput.override = o
	if t > 72.0:
		print("%s in '%s' (30 s, gentle pilot):" % [ac.definition.display_name, world.weather.preset_name()])
		for k in ["bank", "pitch", "p", "q", "nz", "kias"]:
			var a: Array = rec[k]
			var m: float = a.reduce(func(x, y): return x + y) / a.size()
			var rms := sqrt(a.map(func(x): return (x - m) * (x - m)).reduce(func(x, y): return x + y) / a.size())
			var pk: float = a.map(func(x): return absf(x - m)).max()
			print("  %-6s rms %6.2f   peak %6.2f" % [k, rms, pk])
		get_tree().quit()
