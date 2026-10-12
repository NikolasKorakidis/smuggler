class_name RainAudio
extends Node
## Rain on the airframe. Four layers on a "Rain" bus whose filters follow the
## airspeed:
##   patter  separate drops ticking on the Perspex and aluminium
##   dense   many drops (a recording at res://audio/rain/rain.ogg replaces it)
##   sheet   so many impacts at speed that they merge into a roar
##   drum    big drops thudding on the cabin roof (heavy rain)
## Flying through rain sweeps up drops at sqrt(fall^2 + airspeed^2): at 100 kt
## about seven times as many, hitting harder. So the faster you go the
## denser, brighter and louder it gets. Drops are synthesised once from a bank
## of impact grains (noise burst through plate resonances).

const RATE := 32000
const RECORDING := "res://audio/rain/rain.ogg"
const FALL_MS := 7.0

var weather: Weather
var world: Node3D
var _bus := -1
var _lp: AudioEffectLowPassFilter
var _hp: AudioEffectHighPassFilter
var _players := {}
var _task := -1
var _streams := {}


func _init(w: Weather, wld: Node3D) -> void:
	weather = w
	world = wld
	name = "RainAudio"


func _ready() -> void:
	_bus = AudioServer.get_bus_index("Rain")
	if _bus == -1:
		AudioServer.add_bus()
		_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus, "Rain")
		AudioServer.set_bus_send(_bus, "Master")
		_hp = AudioEffectHighPassFilter.new()
		_lp = AudioEffectLowPassFilter.new()
		AudioServer.add_bus_effect(_bus, _hp)
		AudioServer.add_bus_effect(_bus, _lp)
	else:
		_hp = AudioServer.get_bus_effect(_bus, 0)
		_lp = AudioServer.get_bus_effect(_bus, 1)
	_task = WorkerThreadPool.add_task(_synth)


func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)


func _process(_delta: float) -> void:
	if _task != -1:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		for k in ["patter", "dense", "sheet", "drum"]:
			var stream: AudioStream = _streams[k]
			if k == "dense" and ResourceLoader.exists(RECORDING):
				stream = load(RECORDING)
				if stream is AudioStreamOggVorbis:
					stream.loop = true
			var p := AudioStreamPlayer.new()
			p.stream = stream
			p.bus = "Rain"
			p.volume_db = -80.0
			add_child(p)
			p.play(randf() * 2.0)
			_players[k] = p
	if _players.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var ac = world.get("aircraft")
	var v := 0.0  # airspeed, m/s
	var cockpit := false
	if ac and ac.fdm:
		v = maxf(ac.fdm.prop_get("velocities/vtrue-fps") * 0.3048, 0.0)
		cockpit = cam.global_position.distance_to(ac.eyepoint().global_position) < 0.5
	var rate := weather.rain_at(cam.global_position)
	if weather.in_cloud(cam.global_position):
		rate = maxf(rate, 1.5)  # cloud droplets on the glass
	var r := clampf(log(1.0 + rate) / log(51.0), 0.0, 1.0)  # 0 dry .. 1 at 50 mm/h
	# Drops swept up per second, relative to standing still (1 .. ~7 at 100 kt).
	var sweep := sqrt(FALL_MS * FALL_MS + v * v) / FALL_MS
	var fast := clampf(log(sweep) / log(7.0), 0.0, 1.0)  # 0 parked .. 1 cruising
	_gain(_players.patter, r * (1.0 - 0.7 * fast) * (1.0 - 0.4 * smoothstep(0.5, 1.0, r)), 0.0)
	_gain(_players.dense, r * (0.3 + 0.7 * smoothstep(0.2, 0.9, r)) * (1.0 + 0.8 * fast), 0.0)
	_gain(_players.sheet, r * smoothstep(0.05, 0.7, fast) * (0.6 + 0.4 * r), 0.0)
	_gain(_players.drum, smoothstep(0.45, 1.0, r) * (1.0 - 0.5 * fast) * (1.0 if cockpit else 0.25), 0.0)
	# Faster: drops come quicker (pitch) and hit harder (brighter).
	_players.patter.pitch_scale = 1.0 + 0.45 * fast
	_players.dense.pitch_scale = 1.0 + 0.3 * fast
	_players.sheet.pitch_scale = 0.85 + 0.35 * fast
	# Heard from inside the cabin the highs are softened; outside, more open.
	_lp.cutoff_hz = lerpf(5500.0, 11000.0, fast) if cockpit else 14000.0
	_hp.cutoff_hz = lerpf(80.0, 220.0, fast)
	AudioServer.set_bus_volume_db(_bus, 3.0 if cockpit else -4.0)


func _gain(p: AudioStreamPlayer, k: float, db: float) -> void:
	p.volume_db = -80.0 if k < 0.004 else linear_to_db(k) - 10.0 + db


# --- synthesis (worker thread) ---------------------------------------------------

func _synth() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1983
	var bank: Array[PackedFloat32Array] = []
	for i in 48:
		bank.append(_drop_grain(rng, i % 6 == 0))
	_streams.patter = _layer(bank, 10.0, 260.0, 0.0, 0.0, rng)
	_streams.dense = _layer(bank, 10.0, 2600.0, 0.10, 0.0, rng)
	_streams.sheet = _layer(bank, 6.0, 6000.0, 0.35, 0.0, rng)
	_streams.drum = _layer(bank, 10.0, 0.0, 0.0, 45.0, rng)


# One drop hitting the canopy: a sharp noise burst rung through two plate
# resonances (Perspex/aluminium), big drops with a low body thump.
func _drop_grain(rng: RandomNumberGenerator, big: bool) -> PackedFloat32Array:
	var n := int(RATE * (0.012 if not big else 0.03))
	var g := PackedFloat32Array()
	g.resize(n)
	var burst := int(RATE * rng.randf_range(0.0003, 0.0011))
	var res := [[rng.randf_range(1400.0, 4200.0), rng.randf_range(350.0, 900.0)],
		[rng.randf_range(4800.0, 9500.0), rng.randf_range(900.0, 2200.0)]]
	var state := [[0.0, 0.0], [0.0, 0.0]]
	var coef := []
	for rz in res:
		var r := exp(-PI * rz[1] / RATE)
		coef.append([2.0 * r * cos(TAU * rz[0] / RATE), -r * r, 1.0 - r])
	var body_f := rng.randf_range(140.0, 320.0) / RATE * TAU
	for i in n:
		var x := (rng.randf_range(-1.0, 1.0) * exp(-6.0 * i / maxf(burst, 1.0))) if i < burst * 3 else 0.0
		var y := x * 0.35
		for k in 2:
			var c: Array = coef[k]
			var s: Array = state[k]
			var o: float = c[2] * x + c[0] * s[0] + c[1] * s[1]
			s[1] = s[0]
			s[0] = o
			y += o * (0.8 if k == 0 else 0.5)
		if big:
			y += sin(i * body_f) * exp(-float(i) / (RATE * 0.008)) * 0.6
		g[i] = y
	return g


# A stereo loop of grains at `per_s` (Poisson), over a soft noise bed; `thuds_per_s`
# adds deep drum hits instead (big drops on the roof).
func _layer(bank: Array[PackedFloat32Array], seconds: float, per_s: float, bed: float, thuds_per_s: float,
		rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var ch := [PackedFloat32Array(), PackedFloat32Array()]
	for c in 2:
		var buf: PackedFloat32Array = ch[c]
		buf.resize(n)
		if bed > 0.0:
			var b0 := 0.0
			var b1 := 0.0
			var b2 := 0.0
			for i in n:
				var w := rng.randf_range(-1.0, 1.0)
				# Pinkish noise (Paul Kellet's economy filter).
				b0 = 0.99765 * b0 + w * 0.0990460
				b1 = 0.96300 * b1 + w * 0.2965164
				b2 = 0.57000 * b2 + w * 1.0526913
				buf[i] = (b0 + b1 + b2 + w * 0.1848) * bed * 0.2
		var count := int(seconds * per_s * 0.5)
		for k in count:
			var at := rng.randi() % n
			var gr: PackedFloat32Array = bank[rng.randi() % bank.size()]
			var amp := pow(rng.randf(), 2.5) * (1.0 if per_s < 1000.0 else 0.6)
			for j in gr.size():
				buf[(at + j) % n] += gr[j] * amp
		if thuds_per_s > 0.0:
			for k in int(seconds * thuds_per_s * 0.5):
				var at := rng.randi() % n
				var f := rng.randf_range(70.0, 160.0) / RATE * TAU
				var amp := pow(rng.randf(), 2.0)
				var len := int(RATE * 0.06)
				for j in len:
					buf[(at + j) % n] += sin(j * f) * exp(-float(j) / (RATE * 0.012)) * amp
	return _stereo(_blend(ch[0]), _blend(ch[1]))


func _blend(buf: PackedFloat32Array) -> PackedFloat32Array:
	var n := buf.size()
	var fade := int(0.2 * RATE)
	for j in fade:
		var a := float(j) / fade
		buf[j] = buf[j] * a + buf[n - fade + j] * (1.0 - a)
	buf.resize(n - fade)
	return buf


static func _stereo(l: PackedFloat32Array, r: PackedFloat32Array) -> AudioStreamWAV:
	var n := mini(l.size(), r.size())
	var peak := 1e-6
	for i in n:
		peak = maxf(peak, maxf(absf(l[i]), absf(r[i])))
	var g := 0.9 / peak
	var bytes := PackedByteArray()
	bytes.resize(n * 4)
	for i in n:
		# A little cross-feed so it isn't unnaturally wide in headphones.
		var a := l[i] * 0.85 + r[i] * 0.15
		var b := r[i] * 0.85 + l[i] * 0.15
		bytes.encode_s16(i * 4, int(clampf(a * g, -1.0, 1.0) * 32767.0))
		bytes.encode_s16(i * 4 + 2, int(clampf(b * g, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = true
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = n
	return wav
