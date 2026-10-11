extends Node
## Placeholder aircraft sounds, synthesised live from the FDM: piston engine
## (firing pulses + prop), wind, tyre rumble, touchdown thump and stall horn.
## Replaced by recorded sounds later; the inputs (rpm, power, speed) stay.

const MIX_RATE := 22050.0

var fdm: FDM
var definition: AircraftDefinition

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _rng := RandomNumberGenerator.new()

# Smoothed inputs (updated per frame, used per sample)
var _rpm := 0.0
var _power := 0.0
var _throttle := 0.0
var _wind := 0.0
var _roll := 0.0
var _horn := 0.0

# Oscillator / filter state
var _fire_phase := 0.0
var _pulse_gain := 1.0
var _engine_lp := 0.0
var _wind_lp := 0.0
var _wind_lp2 := 0.0
var _rumble_lp := 0.0
var _horn_phase := 0.0
var _thump := 0.0
var _thump_phase := 0.0
var _was_on_ground := true


func _ready() -> void:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = 0.1
	_player = AudioStreamPlayer.new()
	_player.stream = stream
	_player.volume_db = -6.0
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()


func _process(delta: float) -> void:
	if fdm == null or fdm.jsb == null or _playback == null:
		return
	var k := 1.0 - exp(-delta / 0.08)
	_rpm = lerpf(_rpm, fdm.prop_get("propulsion/engine/engine-rpm"), k)
	_power = lerpf(_power, clampf(fdm.prop_get("propulsion/engine/power-hp") / 160.0, 0.0, 1.2), k)
	_throttle = lerpf(_throttle, fdm.prop_get("fcs/throttle-pos-norm"), k)
	var kias := maxf(fdm.prop_get("velocities/vc-kts"), 0.0)
	_wind = lerpf(_wind, clampf(pow(kias / 110.0, 2.0), 0.0, 1.5), k)

	var on_ground := false
	for i in int(fdm.prop_get("gear/num-units")):
		if fdm.jsb.has_property("gear/unit[%d]/WOW" % i) and fdm.prop_get("gear/unit[%d]/WOW" % i) > 0.5:
			on_ground = true
	var gs_kt := fdm.prop_get("velocities/vg-fps") * 0.5925
	_roll = lerpf(_roll, clampf(gs_kt / 35.0, 0.0, 1.0) if on_ground else 0.0, k)
	if on_ground and not _was_on_ground:
		var sink := -fdm.prop_get("velocities/v-down-fps") if fdm.jsb.has_property("velocities/v-down-fps") else 0.0
		_thump = clampf(0.4 + absf(sink) / 8.0, 0.4, 1.0)
		_thump_phase = 0.0
	_was_on_ground = on_ground

	var warn := definition.stall_warning_alpha_deg
	var horn_on := warn > 0.0 and not on_ground and fdm.prop_get("aero/alpha-deg") > warn
	_horn = lerpf(_horn, 1.0 if horn_on else 0.0, 1.0 - exp(-delta / 0.05))

	_fill(_playback.get_frames_available())


func _fill(frames: int) -> void:
	var dt := 1.0 / MIX_RATE
	# Four-cylinder four-stroke: two firing pulses per crank revolution.
	var fire_hz := _rpm / 30.0
	var running := _rpm > 200.0
	var engine_gain := (0.25 + 0.55 * _power + 0.2 * _throttle) if running else 0.0
	var brightness := clampf(0.08 + 0.35 * _throttle + 0.2 * _power, 0.05, 0.6)
	var wind_cut := clampf(0.02 + 0.12 * _wind, 0.02, 0.25)
	for i in frames:
		var s := 0.0
		# Engine: decaying exhaust pulse per firing, slightly uneven per cylinder.
		if running:
			_fire_phase += fire_hz * dt
			if _fire_phase >= 1.0:
				_fire_phase -= 1.0
				_pulse_gain = 0.8 + 0.4 * _rng.randf()
			var p := 1.0 - _fire_phase
			var pulse := (p * p * p * p * 2.0 - 0.4) * _pulse_gain + (_rng.randf() - 0.5) * 0.25 * p
			_engine_lp += brightness * (pulse - _engine_lp)
			s += _engine_lp * engine_gain
		# Wind: band-limited noise rising with airspeed.
		var n := _rng.randf() * 2.0 - 1.0
		_wind_lp += wind_cut * (n - _wind_lp)
		_wind_lp2 += wind_cut * (_wind_lp - _wind_lp2)
		s += _wind_lp2 * 2.2 * _wind
		# Tyres: low rumble on the ground.
		if _roll > 0.001:
			_rumble_lp += 0.01 * ((_rng.randf() * 2.0 - 1.0) - _rumble_lp)
			s += _rumble_lp * 6.0 * _roll
		# Touchdown thump: short low sine burst.
		if _thump > 0.001:
			_thump_phase += 55.0 * dt
			s += sin(TAU * _thump_phase) * _thump
			_thump *= 0.9993
		# Stall horn: reedy tone.
		if _horn > 0.001:
			_horn_phase = fmod(_horn_phase + 950.0 * dt, 1.0)
			s += (_horn_phase * 2.0 - 1.0) * 0.18 * _horn
		s = clampf(s * 0.6, -1.0, 1.0)
		_playback.push_frame(Vector2(s, s))
