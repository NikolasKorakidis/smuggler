class_name WeatherAudio
extends Node
## Weather sounds, synthesised (no recordings):
## - Thunder from the physics of the channel: every short piece of the jagged
##   lightning channel sends out a shock pulse (N-wave) that arrives distance /
##   343 m/s later, loudest from pieces broadside to the listener; summed they
##   give the crack and crackle of a close strike and the rolling rumble of a
##   far one. Distance strips the highs, the ground and cloud base add echoes.
##   Each strike's thunder is made on a worker thread from its own geometry.
## - Rain: stereo loops of drops ringing on Perspex and aluminium, a hiss, and
##   the roar of flying into rain, mixed by rain rate and airspeed.
## - Turbulence: airframe thumps and rattles on sudden jolts.

const RATE := 32000
const SPEED_OF_SOUND := 343.0

var weather: Weather
var world: Node3D
var _rain_patter: AudioStreamPlayer
var _rain_heavy: AudioStreamPlayer
var _rain_roar: AudioStreamPlayer
var _thumps: Array[AudioStreamWAV] = []
var _loops_task := -1
var _loops := {}
var _thunder_jobs: Array[Dictionary] = []  # {task, result, delay_left, dist}
var _last_nz := 1.0
var _thump_cooldown := 0.0


func _init(w: Weather, wld: Node3D) -> void:
	weather = w
	world = wld
	name = "WeatherAudio"


func _ready() -> void:
	weather.lightning.connect(_on_lightning)
	_loops_task = WorkerThreadPool.add_task(_synth_loops)


func _exit_tree() -> void:
	if _loops_task != -1:
		WorkerThreadPool.wait_for_task_completion(_loops_task)
	for j in _thunder_jobs:
		if j.task != -1:
			WorkerThreadPool.wait_for_task_completion(j.task)


func _process(delta: float) -> void:
	if _loops_task != -1 and WorkerThreadPool.is_task_completed(_loops_task):
		WorkerThreadPool.wait_for_task_completion(_loops_task)
		_loops_task = -1
		_rain_patter = _loop_player(_loops.patter)
		_rain_heavy = _loop_player(_loops.heavy)
		_rain_roar = _loop_player(_loops.roar)
		_thumps = _loops.thumps
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var ac = world.get("aircraft")
	var kias := 0.0
	var cockpit := false
	if ac and ac.fdm:
		kias = maxf(ac.fdm.prop_get("velocities/vc-kts"), 0.0)
		cockpit = cam.global_position.distance_to(ac.eyepoint().global_position) < 0.5
	if _rain_patter:
		_mix_rain(cam, kias, cockpit)
	if ac and ac.fdm and _thumps.size() > 0:
		_turbulence_thumps(ac, delta, cockpit)
	_step_thunder(delta, cockpit)


# --- rain ------------------------------------------------------------------------

func _mix_rain(cam: Camera3D, kias: float, cockpit: bool) -> void:
	var rate := weather.rain_at(cam.global_position)
	if weather.in_cloud(cam.global_position):
		rate = maxf(rate, 1.5)  # cloud droplets hiss on the glass too
	var r := clampf(log(1.0 + rate) / log(51.0), 0.0, 1.0)  # 0 dry .. 1 at 50 mm/h
	var speed := clampf(kias / 110.0, 0.0, 1.0)
	var cabin := 4.0 if cockpit else -2.0  # rain drums on the cabin roof
	_level(_rain_patter, r * (1.0 - 0.6 * speed) * (1.0 - smoothstep(0.6, 1.0, r) * 0.5), cabin)
	_level(_rain_heavy, smoothstep(0.35, 0.95, r) * (1.0 - 0.4 * speed), cabin + 1.0)
	_level(_rain_roar, r * speed * (0.6 + 0.4 * r), cabin - 1.0)
	_rain_patter.pitch_scale = 1.0 + 0.25 * speed
	_rain_roar.pitch_scale = 0.8 + 0.4 * speed


func _level(p: AudioStreamPlayer, k: float, boost_db: float) -> void:
	p.volume_db = -80.0 if k < 0.005 else linear_to_db(k) - 8.0 + boost_db


func _loop_player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -80.0
	add_child(p)
	p.play()
	return p


# --- turbulence ------------------------------------------------------------------

func _turbulence_thumps(ac, delta: float, cockpit: bool) -> void:
	_thump_cooldown -= delta
	var nz: float = ac.fdm.prop_get("accelerations/Nz")
	var jolt := absf(nz - _last_nz) / maxf(delta, 1e-3)  # g per second
	_last_nz = nz
	if jolt > 6.0 and _thump_cooldown <= 0.0 and not ac._on_ground():
		var p := AudioStreamPlayer.new()
		p.stream = _thumps[randi() % _thumps.size()]
		p.volume_db = clampf(linear_to_db(clampf((jolt - 6.0) / 20.0, 0.05, 1.0)) - (2.0 if cockpit else 10.0), -40.0, 0.0)
		p.pitch_scale = randf_range(0.85, 1.15)
		add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
		_thump_cooldown = randf_range(0.12, 0.3)


# --- thunder ---------------------------------------------------------------------

func _on_lightning(at: Vector3, to_ground: bool, power: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var listener := cam.global_position
	if listener.distance_to(at) > 25000.0 or _thunder_jobs.size() > 6:
		return
	var base_y := weather.field_elevation_m + weather.cloud_base_m
	var job := {"task": -1, "result": null, "delay": 0.0, "listener": listener}
	var seed := randi()
	job.task = WorkerThreadPool.add_task(_synth_thunder.bind(job, at, to_ground, power, base_y, listener, seed))
	_thunder_jobs.append(job)


func _step_thunder(delta: float, cockpit: bool) -> void:
	for i in range(_thunder_jobs.size() - 1, -1, -1):
		var j: Dictionary = _thunder_jobs[i]
		if j.task != -1:
			if not WorkerThreadPool.is_task_completed(j.task):
				j.delay -= delta  # time is passing while we synthesise
				continue
			WorkerThreadPool.wait_for_task_completion(j.task)
			j.task = -1
			j.delay += j.first_arrival
		j.delay -= delta
		if j.delay <= 0.0:
			var p := AudioStreamPlayer.new()
			p.stream = j.result
			p.volume_db = clampf(j.db - (5.0 if cockpit else 0.0), -50.0, 6.0)
			add_child(p)
			p.play()
			p.finished.connect(p.queue_free)
			_thunder_jobs.remove_at(i)


# Lightning channel: a jagged path, finely tortuous (every few metres).
static func _channel(at: Vector3, to_ground: bool, base_y: float, rng: RandomNumberGenerator) -> PackedVector3Array:
	var a: Vector3
	var b: Vector3
	if to_ground:
		a = Vector3(at.x + rng.randf_range(-300, 300), base_y + rng.randf_range(200, 900), at.z + rng.randf_range(-300, 300))
		b = at
	else:  # in-cloud "spider": long and mostly horizontal
		var ang := rng.randf() * TAU
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var half := dir * rng.randf_range(1500.0, 4000.0)
		a = at - half + Vector3(0, rng.randf_range(-400, 400), 0)
		b = at + half + Vector3(0, rng.randf_range(-400, 400), 0)
	var pts := PackedVector3Array([a, b])
	var rough := a.distance_to(b) * 0.15
	while pts[0].distance_to(pts[1]) > 6.0 and pts.size() < 4096:
		var next := PackedVector3Array([pts[0]])
		for i in pts.size() - 1:
			var m := (pts[i] + pts[i + 1]) * 0.5 + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * rough
			next.append(m)
			next.append(pts[i + 1])
		pts = next
		rough *= 0.56
	return pts


func _synth_thunder(job: Dictionary, at: Vector3, to_ground: bool, power: float, base_y: float,
		listener: Vector3, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pts := _channel(at, to_ground, base_y, rng)
	# Arrival time, loudness and pulse width of every piece.
	var n := pts.size() - 1
	var times := PackedFloat32Array()
	var amps := PackedFloat32Array()
	var widths := PackedFloat32Array()
	times.resize(n)
	amps.resize(n)
	widths.resize(n)
	var t_min := INF
	var t_max := 0.0
	var d_sum := 0.0
	for i in n:
		var mid := (pts[i] + pts[i + 1]) * 0.5
		var seg := pts[i + 1] - pts[i]
		var to_l := listener - mid
		var d := maxf(to_l.length(), 30.0)
		# Shock pulses beam out sideways from each piece of channel.
		var side := 1.0 - absf(seg.normalized().dot(to_l / d))
		times[i] = d / SPEED_OF_SOUND
		amps[i] = (0.15 + pow(side, 3.0)) * seg.length() / d
		# N-waves lengthen as they travel (and high frequencies die in the air).
		widths[i] = 0.003 * pow(d / 100.0, 0.35) * rng.randf_range(0.7, 1.4)
		t_min = minf(t_min, times[i])
		t_max = maxf(t_max, times[i])
		d_sum += d
	var d_mean := d_sum / n
	var length := t_max - t_min + 4.0 + d_mean / 2500.0
	var total := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(total)
	for i in n:
		var start := int((times[i] - t_min) * RATE)
		var w := maxi(int(widths[i] * RATE), 3)
		var a := amps[i]
		# N-wave: a sudden rise, a linear fall through zero, a sudden return.
		for k in w:
			var idx := start + k
			if idx >= total:
				break
			out[idx] += a * (1.0 - 2.0 * float(k) / w)
	# Echoes off the ground, hills and the cloud base: delayed, softer copies,
	# coming in later and longer the further away the strike is.
	var echo := out.duplicate()
	var spread := 1.0 + d_mean / 3000.0
	for k in 7:
		var delay := 0.05 + spread * pow(float(k + 1) / 7.0, 1.5) * rng.randf_range(0.7, 1.2)
		var gain := 0.45 * pow(0.72, k)
		var off := int(delay * RATE)
		for i in range(total - 1, off, -1):
			out[i] += echo[i - off] * gain
	# Rumble: the energy rings on as low, filtered noise following the pulses
	# (longer for distant strikes: rolling thunder).
	var env := 0.0
	var lp := 0.0
	var lp2 := 0.0
	var decay := exp(-1.0 / (RATE * (0.7 + d_mean / 4000.0)))
	for i in total:
		env = maxf(env * decay, absf(out[i]))
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.02
		out[i] += lp * env * 2.6
	# Air absorption: further away, only the low rumble is left.
	var cut := clampf(9000.0 * exp(-d_mean / 2500.0) + 120.0, 120.0, 9000.0)
	var c := 1.0 - exp(-TAU * cut / RATE)
	lp = 0.0
	lp2 = 0.0
	var peak := 1e-6
	for i in total:
		lp += (out[i] - lp) * c
		lp2 += (lp - lp2) * c
		out[i] = lp2
		peak = maxf(peak, absf(lp2))
	var fade := int(0.4 * RATE)
	for k in fade:
		out[total - fade + k] *= 1.0 - float(k) / fade
	job.result = _wav_mono(out, peak)
	job.first_arrival = t_min
	# Loudness from distance (and the strike's power), set after normalising.
	job.db = clampf(20.0 * log(clampf(900.0 / maxf(d_mean, 60.0), 0.02, 6.0)) / log(10.0)
		+ linear_to_db(clampf(power, 0.3, 1.5)), -45.0, 6.0)


# --- loops (worker thread) ------------------------------------------------------

func _synth_loops() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1984
	_loops.patter = _rain_loop(8.0, 700.0, 0.12, rng)
	_loops.heavy = _rain_loop(8.0, 4500.0, 0.35, rng)
	_loops.roar = _roar_loop(6.0, rng)
	var th: Array[AudioStreamWAV] = []
	for k in 4:
		th.append(_thump(rng))
	_loops.thumps = th


# Drops ringing on Perspex and aluminium (two resonances) over a soft hiss; stereo.
func _rain_loop(seconds: float, per_s: float, hiss: float, rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var ch := [PackedFloat32Array(), PackedFloat32Array()]
	for c in 2:
		var buf: PackedFloat32Array = ch[c]
		buf.resize(n)
		var lp := 0.0
		var prev := 0.0
		for i in n:
			var w := rng.randf_range(-1.0, 1.0)
			lp += (w - lp) * 0.5
			buf[i] = (lp - prev * 0.9) * hiss
			prev = lp
		var drops := int(seconds * per_s * 0.5)
		for k in drops:
			var at := rng.randi() % n
			var amp := pow(rng.randf(), 4.0) * 0.8
			var f1 := rng.randf_range(900.0, 1800.0) / RATE * TAU
			var f2 := rng.randf_range(2600.0, 5200.0) / RATE * TAU
			var len := int(RATE * rng.randf_range(0.004, 0.018))
			for j in len:
				var e := exp(-5.0 * float(j) / len)
				buf[(at + j) % n] += amp * e * (sin(j * f1) * 0.6 + sin(j * f2) * 0.4 + (rng.randf() - 0.5) * 0.4 * exp(-40.0 * j / len))
	return _wav_stereo(_loop_blend(ch[0]), _loop_blend(ch[1]), true)


# The roar of flying into rain: dense broadband noise, a little low rumble.
func _roar_loop(seconds: float, rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var ch := [PackedFloat32Array(), PackedFloat32Array()]
	for c in 2:
		var buf: PackedFloat32Array = ch[c]
		buf.resize(n)
		var lp := 0.0
		var low := 0.0
		var mod := 0.0
		for i in n:
			var w := rng.randf_range(-1.0, 1.0)
			lp += (w - lp) * 0.35
			low += (w - low) * 0.01
			if i % 64 == 0:
				mod = lerpf(mod, rng.randf(), 0.3)
			buf[i] = lp * (0.7 + 0.3 * mod) + low * 2.0
	return _wav_stereo(_loop_blend(ch[0]), _loop_blend(ch[1]), true)


# Turbulence: a low thud of the airframe and a short rattle of loose things.
func _thump(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(0.5 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var f := rng.randf_range(45.0, 80.0) / RATE * TAU
	for i in n:
		var t := float(i) / RATE
		buf[i] = sin(i * f) * exp(-t * 14.0) * 0.9
		if t > 0.01 and t < 0.2 and rng.randf() < 0.02:
			var amp := rng.randf_range(0.1, 0.35) * exp(-t * 10.0)
			for k in mini(120, n - i):
				buf[i + k] += amp * sin(k * 2.2) * exp(-k / 20.0)
	var peak := 1e-6
	for v in buf:
		peak = maxf(peak, absf(v))
	return _wav_mono(buf, peak)


func _loop_blend(buf: PackedFloat32Array) -> PackedFloat32Array:
	var n := buf.size()
	var fade := int(0.15 * RATE)
	for j in fade:
		var a := float(j) / fade
		buf[j] = buf[j] * a + buf[n - fade + j] * (1.0 - a)
	buf.resize(n - fade)
	return buf


static func _wav_mono(samples: PackedFloat32Array, peak: float) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	var g := 0.9 / peak
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i] * g, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = bytes
	return wav


static func _wav_stereo(l: PackedFloat32Array, r: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var n := mini(l.size(), r.size())
	var peak := 1e-6
	for i in n:
		peak = maxf(peak, maxf(absf(l[i]), absf(r[i])))
	var g := 0.9 / peak
	var bytes := PackedByteArray()
	bytes.resize(n * 4)
	for i in n:
		bytes.encode_s16(i * 4, int(clampf(l[i] * g, -1.0, 1.0) * 32767.0))
		bytes.encode_s16(i * 4 + 2, int(clampf(r[i] * g, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = true
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = n
	return wav
