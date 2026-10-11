extends Node
## Renders the aircraft sounds to WAV files and checks them: levels, clipping,
## clicks at buffer boundaries and CPU cost.
##   godot --headless --path game --fixed-fps 60 res://dev/audio_render.tscn -- [--out=DIR]
## Part 1 drives the synth directly through fixed states (both views).
## Part 2 runs the real FDM and engine systems: start, run-up, mag check,
## carb heat, full power, take-off roll, lean-out shutdown, spool-down.
## Files land in DIR (default user://audio_render) as <model>_states.wav and
## <model>_sequence.wav, with a matching .txt listing the segment times.

const RATE := AircraftSynth.RATE
const BLOCK := 368  # frames per render call, about one 60 fps frame

var world: Node3D
var failures := 0
var out_dir := "user://audio_render"
var _labels: Array = []  # [start_frame, label]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	FlightInput.joysticks_enabled = false
	var defs: Array[AircraftDefinition] = [
		load("res://aircraft/J3Cub/j3cub.tres"), load("res://aircraft/c172p/c172p.tres")]
	for def in defs:
		_render_states(def)
	world = load("res://world/test_world.tscn").instantiate()
	add_child(world)
	await _sequence(1)
	await _sequence(0)
	await _live_cost()
	print("files in ", ProjectSettings.globalize_path(out_dir))
	print("AUDIO RENDER: ", "PASS" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(failures)


# --- part 1: fixed states ---------------------------------------------------------

func _render_states(def: AircraftDefinition) -> void:
	var p: AircraftSound = def.sound
	var synth := AircraftSynth.new(p)
	var idle := p.idle_rpm
	var full := 2350.0 if p.rated_hp > 100.0 else 2100.0
	var cruise := 2400.0 if p.rated_hp > 100.0 else 2150.0
	var cruise_kt := 105.0 if p.rated_hp > 100.0 else 70.0
	var tip_full := 0.70 if p.rated_hp > 100.0 else 0.62
	var states := []
	if def.has_starter:
		states.append(["cranking (cockpit)", 2.5, {"rpm": 210.0, "cranking": 1.0, "view": 1.0}])
		states.append(["cranking with coughs (cockpit)", 2.5, {"rpm": 220.0, "cranking": 1.0, "cough_chance": 0.12, "view": 1.0}])
	else:
		states.append(["prop swing, no catch (cockpit)", 1.5, {"rpm": 300.0, "view": 1.0}])
	states.append(["idle (cockpit)", 4.0, {"rpm": idle, "firing": true, "load": 0.02, "tip_mach": 0.19, "view": 1.0, "roughness": p.wear}])
	states.append(["idle (chase)", 3.0, {"rpm": idle, "firing": true, "load": 0.02, "tip_mach": 0.19, "view": 0.0, "roughness": p.wear}])
	states.append(["idle, cold and lumpy (cockpit)", 3.0, {"rpm": idle * 0.9, "firing": true, "load": 0.02, "tip_mach": 0.17, "view": 1.0, "roughness": 0.15}])
	states.append(["1700 rpm run-up (cockpit)", 3.0, {"rpm": 1700.0, "firing": true, "load": 0.35, "tip_mach": 0.5, "thrust": 0.5, "view": 1.0}])
	states.append(["full power static (cockpit)", 4.0, {"rpm": full, "firing": true, "load": 0.85, "tip_mach": tip_full, "thrust": 1.0, "view": 1.0}])
	states.append(["full power static (chase)", 4.0, {"rpm": full, "firing": true, "load": 0.85, "tip_mach": tip_full, "thrust": 1.0, "view": 0.0}])
	states.append(["take-off roll on grass (cockpit)", 4.0, {"rpm": full, "firing": true, "load": 0.85, "tip_mach": tip_full, "thrust": 0.9, "view": 1.0, "on_ground": true, "ground_speed_kt": 30.0, "airspeed_kt": 30.0, "surface": &"grass_strip"}])
	states.append(["cruise (cockpit)", 4.0, {"rpm": cruise, "firing": true, "load": 0.65, "tip_mach": tip_full + 0.05, "thrust": 0.45, "view": 1.0, "airspeed_kt": cruise_kt}])
	states.append(["cruise (chase)", 4.0, {"rpm": cruise, "firing": true, "load": 0.65, "tip_mach": tip_full + 0.05, "thrust": 0.45, "view": 0.0, "airspeed_kt": cruise_kt}])
	states.append(["glide, throttle closed (cockpit)", 4.0, {"rpm": idle * 2.0, "firing": true, "load": 0.0, "tip_mach": 0.35, "thrust": 0.0, "view": 1.0, "airspeed_kt": cruise_kt * 0.7}])
	states.append(["lean misfire (cockpit)", 3.0, {"rpm": 1200.0, "firing": true, "load": 0.15, "tip_mach": 0.35, "thrust": 0.2, "view": 1.0, "roughness": 0.4}])
	states.append(["slow flight near stall (cockpit)", 4.0, {"rpm": 1500.0, "firing": true, "load": 0.3, "tip_mach": 0.45, "thrust": 0.3, "view": 1.0, "airspeed_kt": 48.0, "alpha_deg": p.buffet_alpha_deg + 1.0, "horn": def.stall_warning_alpha_deg > 0.0}])
	states.append(["engine off, windmilling glide (cockpit)", 3.0, {"rpm": 700.0, "tip_mach": 0.25, "view": 1.0, "airspeed_kt": cruise_kt * 0.7}])
	var buf := PackedVector2Array()
	var all := PackedFloat32Array()
	var boundaries := PackedInt32Array()
	_labels.clear()
	print("%s states:" % def.jsbsim_model)
	var defaults := {"rpm": 0.0, "firing": false, "load": 0.0, "roughness": 0.0, "cranking": 0.0,
			"cough_chance": 0.0, "tip_mach": 0.0, "thrust": 0.0, "airspeed_kt": 0.0, "alpha_deg": 2.0,
			"on_ground": false, "ground_speed_kt": 0.0, "surface": &"paved", "horn": false, "view": 1.0}
	for st in states:
		var vals: Dictionary = defaults.duplicate()
		vals.merge(st[2], true)
		for key in vals:
			synth.set(key, vals[key])
		synth.prop_rpm = synth.rpm
		var start := all.size()
		_labels.append([start, st[0]])
		var usec := 0
		var n := int(st[1] * RATE)
		var done := 0
		while done < n:
			var frames := mini(BLOCK, n - done)
			boundaries.append(all.size())
			var t0 := Time.get_ticks_usec()
			synth.render(frames, buf)
			usec += Time.get_ticks_usec() - t0
			for f in buf:
				all.append(f.x)
			done += frames
		_report(st[0], all, start, all.size(), float(usec) / n)
	_check_boundaries(def.jsbsim_model + " states", all, boundaries)
	_write(def.jsbsim_model + "_states", all)


# --- part 2: real FDM sequence ------------------------------------------------------

func _sequence(index: int) -> void:
	world._spawn_aircraft(index)
	var ac: Aircraft = world.aircraft
	var e: EngineSystems = ac.engine
	var audio = ac.get_node_or_null("Audio")
	if audio == null:
		_fail("no Audio node on " + ac.definition.jsbsim_model)
		return
	audio.capture = true
	audio.force_view = 1.0
	audio.captured.clear()
	_labels.clear()
	var model := ac.definition.jsbsim_model
	FlightInput.parking_brake = true
	FlightInput.set_throttle_keyboard(0.08)
	await _seg(audio, "cold and dark", 1.0)
	if ac.definition.has_starter:
		e.set_master(true)
		for i in 3:
			e.stroke_primer()
		e.set_magnetos(3)
		_mark(audio, "cranking")
		e.click_starter = true
		for i in int(8.0 * Engine.physics_ticks_per_second):
			await get_tree().physics_frame
			if e.running():
				break
		await _secs(0.4)
		e.click_starter = false
	else:
		e.set_magnetos(0)
		_mark(audio, "pulling the prop through, switch off")
		for i in 4:
			await _swing(e)
		e.set_magnetos(3)
		_mark(audio, "contact: swinging the prop")
		for i in 8:
			await _swing(e)
			if e.running():
				break
	if not e.running():
		_fail(model + " sequence: engine did not start")
	await _seg(audio, "warm-up idle", 5.0)
	FlightInput.set_throttle_keyboard(0.55)
	await _seg(audio, "run-up rpm", 3.0)
	e.set_magnetos(1)
	await _seg(audio, "mag check: right", 2.0)
	e.set_magnetos(2)
	await _seg(audio, "mag check: left", 2.0)
	e.set_magnetos(3)
	e.set_carb_heat(true)
	await _seg(audio, "carb heat on", 2.5)
	e.set_carb_heat(false)
	FlightInput.set_throttle_keyboard(0.0)
	await _seg(audio, "idle", 3.0)
	FlightInput.set_throttle_keyboard(1.0)
	await _seg(audio, "full power, brakes on", 4.0)
	audio.force_view = 0.0
	await _seg(audio, "full power, chase camera", 3.0)
	audio.force_view = 1.0
	FlightInput.parking_brake = false
	await _seg(audio, "take-off roll", 9.0)
	FlightInput.set_throttle_keyboard(0.0)
	FlightInput.parking_brake = true
	await _seg(audio, "throttle closed, braking", 6.0)
	if ac.definition.has_mixture:
		_mark(audio, "leaning out to cut-off")
		for i in int(4.0 * Engine.physics_ticks_per_second):
			e.set_mixture(1.0 - float(i) / (4.0 * Engine.physics_ticks_per_second))
			await get_tree().physics_frame
	else:
		e.set_magnetos(0)
		_mark(audio, "magnetos off")
	await _seg(audio, "spool-down", 4.0)
	if e.running():
		_fail(model + " sequence: engine still running after shutdown")
	var mono := PackedFloat32Array()
	mono.resize(audio.captured.size())
	for i in audio.captured.size():
		mono[i] = audio.captured[i].x
	print("%s sequence (real FDM, synth %.2f us/sample):" % [model, audio.cost_us_per_sample])
	for i in _labels.size():
		var end: int = _labels[i + 1][0] if i + 1 < _labels.size() else mono.size()
		_report(_labels[i][1], mono, _labels[i][0], end, -1.0)
	_write(model + "_sequence", mono)
	FlightInput.parking_brake = false


## Part 3: the node as it runs in game (worker thread), to measure what it
## costs the main thread.
func _live_cost() -> void:
	world._spawn_aircraft(1)
	var ac: Aircraft = world.aircraft
	ac.engine.auto_start()
	FlightInput.set_throttle_keyboard(1.0)
	FlightInput.parking_brake = true
	await _secs(8.0)
	var audio = ac.get_node("Audio")
	audio.main_us_per_frame = 0.0
	audio.frames_rendered = 0
	var t0 := Time.get_ticks_msec()
	await _secs(4.0)
	print("live (172, full power, worker thread): synth %.2f us/sample, main thread %.0f us/frame, %d frames in %.1f s wall" % [
		audio.cost_us_per_sample, audio.main_us_per_frame, audio.frames_rendered, (Time.get_ticks_msec() - t0) / 1000.0])
	FlightInput.set_throttle_keyboard(0.0)
	FlightInput.parking_brake = false


func _swing(e: EngineSystems) -> void:
	e.click_starter = true
	await _secs(0.1)
	e.click_starter = false
	await _secs(1.0)


func _seg(audio, label: String, t: float) -> void:
	_mark(audio, label)
	await _secs(t)


func _mark(audio, label: String) -> void:
	_labels.append([audio.captured.size(), label])


func _secs(t: float) -> void:
	for i in int(t * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


# --- checks and output ----------------------------------------------------------------

func _report(label: String, a: PackedFloat32Array, from: int, to: int, us: float) -> void:
	var sum := 0.0
	var peak := 0.0
	var clips := 0
	for i in range(from, to):
		var v := a[i]
		if is_nan(v):
			_fail("NaN in " + label)
			return
		sum += v * v
		peak = maxf(peak, absf(v))
		if absf(v) > 0.995:
			clips += 1
	var n := maxi(to - from, 1)
	var rms_db := 10.0 * log(maxf(sum / n, 1e-12)) / log(10.0)
	var line := "  %-42s rms %6.1f dB  peak %5.2f  clipped %d" % [label, rms_db, peak, clips]
	if us >= 0.0:
		line += "  cost %.2f us/sample" % us
	print(line)


## A click at a render-block boundary shows as a sample-to-sample jump much
## bigger than the ones inside blocks.
func _check_boundaries(name: String, a: PackedFloat32Array, boundaries: PackedInt32Array) -> void:
	var inside := 0.0
	for i in range(1, a.size()):
		inside += absf(a[i] - a[i - 1])
	inside /= maxi(a.size() - 1, 1)
	var at := 0.0
	var count := 0
	for b in boundaries:
		if b > 0:
			at += absf(a[b] - a[b - 1])
			count += 1
	at /= maxi(count, 1)
	var ratio := at / maxf(inside, 1e-9)
	var ok := ratio < 2.0
	print("  %s: boundary jump / average jump = %.2f %s" % [name, ratio, "ok" if ok else "CLICKS"])
	if not ok:
		failures += 1


func _write(base: String, a: PackedFloat32Array) -> void:
	var f := FileAccess.open(out_dir.path_join(base + ".wav"), FileAccess.WRITE)
	var bytes := a.size() * 2
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + bytes)
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)  # PCM
	f.store_16(1)  # mono
	f.store_32(int(RATE))
	f.store_32(int(RATE) * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(bytes)
	var pcm := PackedByteArray()
	pcm.resize(bytes)
	for i in a.size():
		pcm.encode_s16(i * 2, int(clampf(a[i], -1.0, 1.0) * 32767.0))
	f.store_buffer(pcm)
	f.close()
	var txt := FileAccess.open(out_dir.path_join(base + ".txt"), FileAccess.WRITE)
	for l in _labels:
		txt.store_line("%7.2f s  %s" % [float(l[0]) / RATE, l[1]])
	txt.close()


func _fail(msg: String) -> void:
	print("  FAIL ", msg)
	failures += 1
