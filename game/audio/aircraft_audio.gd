extends Node
## Aircraft sounds, synthesised live (audio/aircraft_synth.gd). This node reads
## the FDM, engine systems and camera every frame, turns them into synth
## inputs and streams the result. Replaced by recorded sounds later; the
## inputs (rpm, load, roughness, speed) stay.

const MIX_RATE := AircraftSynth.RATE
const CATCH_S := 1.6  # rough running right after the engine catches

var fdm: FDM
var definition: AircraftDefinition
var engine: EngineSystems
var synth: AircraftSynth
## Dev: render into `captured` at the game clock instead of playing.
var capture := false
var captured := PackedVector2Array()
## Dev: force the listening position (0 chase, 1 cockpit), -1 = follow camera.
var force_view := -1.0
## Measured synth cost, microseconds per sample (running average, worker).
var cost_us_per_sample := 0.0
## Measured main-thread cost of this node, microseconds per frame.
var main_us_per_frame := 0.0
var frames_rendered := 0

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _buf := PackedVector2Array()
var _capture_frac := 0.0
var _task := -1  # synth rendering on a worker thread
var _task_frames := 0

var _rpm := 0.0
var _load := 0.0
var _thrust := 0.0
var _kias := 0.0
var _view := 0.0
var _was_on_ground := true
var _was_firing := false
var _was_cranking := false
var _catch_t := 99.0
var _spun := false


func _ready() -> void:
	synth = AircraftSynth.new(definition.sound if definition else null)
	if capture:
		return
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = 0.1
	_player = AudioStreamPlayer.new()
	_player.stream = stream
	_player.volume_db = -3.0
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()


func _process(delta: float) -> void:
	if fdm == null or fdm.jsb == null or synth == null:
		return
	if capture:
		# Dev: render in step with the game clock, on this thread.
		_finish_task()
		_update_inputs(delta)
		_capture_frac += delta * MIX_RATE
		_task_frames = int(_capture_frac)
		_capture_frac -= _task_frames
		_render()
		captured.append_array(_buf)
		return
	if _playback == null:
		return
	var t0 := Time.get_ticks_usec()
	# The synth renders on a worker thread while the frame goes on; its
	# output is pushed next frame (one frame of extra latency).
	if _finish_task():
		_playback.push_buffer(_buf)
	_update_inputs(delta)
	_task_frames = _playback.get_frames_available()
	if _task_frames > 0:
		frames_rendered += _task_frames
		_task = WorkerThreadPool.add_task(_render, false, "aircraft audio")
	main_us_per_frame = lerpf(main_us_per_frame, float(Time.get_ticks_usec() - t0), 0.05)


func _exit_tree() -> void:
	_finish_task()


func _finish_task() -> bool:
	if _task < 0:
		return false
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	return true


func _render() -> void:
	if _task_frames <= 0:
		_buf.resize(0)
		return
	var t0 := Time.get_ticks_usec()
	synth.render(_task_frames, _buf)
	var us := float(Time.get_ticks_usec() - t0) / _task_frames
	cost_us_per_sample = us if cost_us_per_sample == 0.0 else lerpf(cost_us_per_sample, us, 0.02)


func _update_inputs(delta: float) -> void:
	var s := synth
	var p := s.profile
	var k := 1.0 - exp(-delta / 0.06)
	var rpm := fdm.prop_get("propulsion/engine/engine-rpm")
	_rpm = lerpf(_rpm, rpm, 1.0 - exp(-delta / 0.03))
	s.rpm = _rpm
	s.prop_rpm = _rpm * _gear_ratio()
	var running := fdm.engine_running()
	var mags := engine.magnetos if engine else 3
	var firing := running and mags != 0
	s.firing = firing
	_load = lerpf(_load, clampf(fdm.prop_get("propulsion/engine/power-hp") / p.rated_hp, 0.0, 1.2) if firing else 0.0, k)
	s.load = _load

	# Catching, spool-down clunk.
	if firing and not _was_firing:
		_catch_t = 0.0
	_catch_t += delta
	if firing and rpm > 300.0:
		_spun = true
	if not firing and _spun and rpm < 45.0:
		_spun = false
		s.clunk(0.5)
	_was_firing = firing

	s.roughness = _roughness(firing)

	# Starter.
	var cranking := engine != null and engine.cranking() and definition.has_starter
	if cranking != _was_cranking:
		s.clunk(0.35 if cranking else 0.12)
	_was_cranking = cranking
	s.cranking = 1.0 if cranking else 0.0
	s.cough_chance = 0.0
	if engine and engine.cranking() and not firing and engine.magnetos != 0 \
			and engine.fuel_line_fraction() > 0.0 and engine.mixture > 0.4:
		s.cough_chance = 0.1 * engine.start_quality()

	# Propeller.
	s.tip_mach = fdm.prop_get("propulsion/engine/helical-tip-Mach")
	var static_thrust := p.rated_hp * 2.8  # lbf, rough static thrust of a fixed-pitch single
	_thrust = lerpf(_thrust, clampf(fdm.prop_get("propulsion/engine/thrust-lbs") / static_thrust, 0.0, 1.0), k)
	s.thrust = _thrust

	# Airflow.
	_kias = lerpf(_kias, maxf(fdm.prop_get("velocities/vc-kts"), 0.0), k)
	s.airspeed_kt = _kias
	s.alpha_deg = fdm.prop_get("aero/alpha-deg")
	s.slip_deg = fdm.prop_get("aero/beta-deg")
	s.flaps = fdm.prop_get("fcs/flap-pos-norm") if fdm.jsb.has_property("fcs/flap-pos-norm") else 0.0

	# Ground.
	var on_ground := false
	for i in int(fdm.prop_get("gear/num-units")):
		if fdm.jsb.has_property("gear/unit[%d]/WOW" % i) and fdm.prop_get("gear/unit[%d]/WOW" % i) > 0.5:
			on_ground = true
	s.on_ground = on_ground
	s.surface = fdm.surface
	s.ground_speed_kt = fdm.prop_get("velocities/vg-fps") * 0.5925
	if on_ground and not _was_on_ground:
		var sink := absf(fdm.prop_get("velocities/v-down-fps")) if fdm.jsb.has_property("velocities/v-down-fps") else 0.0
		s.touchdown(clampf(0.25 + sink / 8.0, 0.25, 1.0))
	_was_on_ground = on_ground

	var warn := definition.stall_warning_alpha_deg
	s.horn = warn > 0.0 and not on_ground and s.alpha_deg > warn

	# Listening position.
	var target := force_view
	var dist := 12.0
	if target < 0.0:
		target = 0.0
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			if cam.get("mode") == 1:  # camera_rig.gd Mode.COCKPIT
				target = 1.0
			var d = cam.get("chase_distance")
			if d != null:
				dist = d
	_view = move_toward(_view, target, delta / 0.15)
	s.view = _view
	s.distance_m = dist


## How badly the engine is running, 0..1 (about the chance of a misfire).
func _roughness(firing: bool) -> float:
	if not firing:
		return 0.0
	var p := synth.profile
	var r := p.wear * lerpf(1.0, 0.25, clampf(_load, 0.0, 1.0))
	var afr := fdm.prop_get("propulsion/engine/AFR")
	if is_finite(afr):
		r += 0.85 * smoothstep(15.0, 18.8, afr)  # too lean: misfiring
		r += 0.3 * smoothstep(10.0, 7.5, afr)  # too rich: rough, sooty
	if engine:
		if engine.magnetos == 1 or engine.magnetos == 2:
			r += 0.04  # one magneto: slower burn, a worn plug shows up
		r += 0.06 * (1.0 - engine.warmth) * lerpf(1.0, 0.3, clampf(_load, 0.0, 1.0))  # cold engine
		if engine.carb_heat:
			r += 0.03
		r += 0.9 * smoothstep(0.3, 0.0, engine.fuel_line_fraction())  # fuel starvation
	if _catch_t < CATCH_S:
		r += 0.5 * (1.0 - _catch_t / CATCH_S)
	if _rpm < p.idle_rpm * 0.85:
		r += 0.15 * smoothstep(p.idle_rpm * 0.85, p.idle_rpm * 0.5, _rpm)
	return clampf(r, 0.0, 1.0)


func _gear_ratio() -> float:
	var e := fdm.prop_get("propulsion/engine/engine-rpm")
	if e < 50.0:
		return 1.0
	return fdm.prop_get("propulsion/engine/propeller-rpm") / e
