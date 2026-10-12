class_name WeatherAudio
extends Node
## Rain on the airframe and thunder, synthesised once at start (on a worker
## thread) and then played: rain loops follow the rain rate and airspeed,
## thunder arrives distance / 343 m/s after the flash, a sharp crack when close
## and a low rumble far away.

const RATE := 32000
const SPEED_OF_SOUND := 343.0

var weather: Weather
var world: Node3D
var _rain_light: AudioStreamPlayer
var _rain_heavy: AudioStreamPlayer
var _thunder_near: Array[AudioStreamWAV] = []
var _thunder_far: Array[AudioStreamWAV] = []
var _pending: Array[Dictionary] = []  # thunder on its way: {t, dist, power}
var _task := -1
var _streams := {}


func _init(w: Weather, wld: Node3D) -> void:
	weather = w
	world = wld
	name = "WeatherAudio"


func _ready() -> void:
	weather.lightning.connect(_on_lightning)
	_task = WorkerThreadPool.add_task(_synthesise)


func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _process(delta: float) -> void:
	if _task != -1:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_rain_light = _loop_player(_streams.rain_light)
		_rain_heavy = _loop_player(_streams.rain_heavy)
		_thunder_near = [_streams.near0, _streams.near1]
		_thunder_far = [_streams.far0, _streams.far1]
	if _rain_light == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Rain: louder in heavier rain and when flying into it; drumming in the cabin.
	var rate := weather.rain_at(cam.global_position)
	var ac = world.get("aircraft")
	var kias := 0.0
	var cockpit := false
	if ac and ac.fdm:
		kias = ac.fdm.prop_get("velocities/vc-kts")
		cockpit = cam.global_position.distance_to(ac.eyepoint().global_position) < 0.5
	var k := clampf(log(1.0 + rate) / log(51.0), 0.0, 1.0) * (1.0 + clampf(kias / 120.0, 0.0, 0.6))
	var cabin := 3.0 if cockpit else 0.0
	_set_level(_rain_light, k * (1.0 - smoothstep(0.5, 0.9, k)) + 0.3 * k, cabin)
	_set_level(_rain_heavy, smoothstep(0.35, 0.9, k), cabin + 2.0)
	_rain_light.pitch_scale = 1.0 + clampf(kias / 300.0, 0.0, 0.3)
	# Thunder arriving.
	for i in range(_pending.size() - 1, -1, -1):
		var p: Dictionary = _pending[i]
		p.t -= delta
		if p.t <= 0.0:
			_play_thunder(p.dist, p.power, cockpit)
			_pending.remove_at(i)


func _set_level(player: AudioStreamPlayer, level: float, boost_db: float) -> void:
	if level < 0.01:
		player.volume_db = -80.0
		return
	player.volume_db = linear_to_db(level) - 6.0 + boost_db


func _loop_player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -80.0
	add_child(p)
	p.play()
	return p


func _on_lightning(at: Vector3, _to_ground: bool, power: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var d := cam.global_position.distance_to(at)
	if d > 25000.0:
		return  # thunder is rarely heard beyond ~25 km
	_pending.append({"t": d / SPEED_OF_SOUND, "dist": d, "power": power})


func _play_thunder(dist: float, power: float, cockpit: bool) -> void:
	if _thunder_near.is_empty():
		return
	var near := dist < 2500.0
	var pool: Array[AudioStreamWAV] = _thunder_near if near else _thunder_far
	var p := AudioStreamPlayer.new()
	p.stream = pool[randi() % pool.size()]
	# Loudness falls off with distance (spherical spreading, a bit of air absorption).
	var db := 20.0 * log(clampf(800.0 / maxf(dist, 50.0), 0.02, 4.0)) / log(10.0) + linear_to_db(clampf(power, 0.3, 1.5))
	p.volume_db = clampf(db - (4.0 if cockpit else 0.0), -40.0, 6.0)
	p.pitch_scale = randf_range(0.85, 1.08) * (1.0 if near else 0.92)
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


# --- synthesis (worker thread) -------------------------------------------------

func _synthesise() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1984
	_streams.rain_light = _wav(_rain(3.0, 450.0, 0.25, 0.6, rng), true)
	_streams.rain_heavy = _wav(_rain(3.0, 2600.0, 0.6, 0.25, rng), true)
	_streams.near0 = _wav(_thunder(7.0, true, rng), false)
	_streams.near1 = _wav(_thunder(6.0, true, rng), false)
	_streams.far0 = _wav(_thunder(9.0, false, rng), false)
	_streams.far1 = _wav(_thunder(10.0, false, rng), false)


# Pitter-patter: random drop clicks (Poisson, `per_s`) over a hiss; looped.
func _rain(seconds: float, per_s: float, hiss: float, click_len_ms: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var hp_prev := 0.0
	for i in n:
		var w := rng.randf() * 2.0 - 1.0
		lp += (w - lp) * 0.35
		var h := lp - hp_prev * 0.97  # gentle high-pass: a hiss, not a roar
		hp_prev = lp
		out[i] = h * hiss
	var drops := int(seconds * per_s)
	for k in drops:
		var at := rng.randi() % n
		var amp := pow(rng.randf(), 3.0) * 0.9
		var len := int(RATE * click_len_ms * 0.001 * rng.randf_range(2.0, 6.0))
		var freq := rng.randf_range(900.0, 4000.0) / RATE * TAU
		for j in len:
			var idx := (at + j) % n
			out[idx] += amp * exp(-6.0 * j / len) * sin(j * freq)
	# Seamless loop: blend the end into the start.
	var fade := int(0.1 * RATE)
	for j in fade:
		var a := float(j) / fade
		out[j] = out[j] * a + out[n - fade + j] * (1.0 - a)
	out.resize(n - fade)
	return out


# Thunder: a crack (close), then rumbling bursts of low brown noise.
func _thunder(seconds: float, near: bool, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var brown := 0.0
	var lp1 := 0.0
	var lp2 := 0.0
	var cut := (260.0 if near else 90.0) / RATE * TAU
	# Rumble envelope: a few overlapping bumps (echoes off clouds and ground).
	var bumps: Array[Vector3] = []  # start s, length s, height
	var t := 0.0 if near else 0.4
	while t < seconds * 0.7:
		bumps.append(Vector3(t, rng.randf_range(0.6, 2.2), rng.randf_range(0.4, 1.0) * exp(-t / (seconds * 0.45))))
		t += rng.randf_range(0.3, 1.4)
	for i in n:
		var s := float(i) / RATE
		var w := rng.randf() * 2.0 - 1.0
		brown = clampf(brown * 0.995 + w * 0.08, -1.0, 1.0)
		lp1 += (brown - lp1) * cut
		lp2 += (lp1 - lp2) * cut
		var env := 0.0
		for b in bumps:
			var x := (s - b.x) / b.y
			if x > 0.0 and x < 1.0:
				env += b.z * sin(PI * x) * (0.7 + 0.3 * sin(s * 23.0 + b.x * 7.0))
		var v := lp2 * env * (3.0 if near else 4.5)
		if near and s < 0.25:  # the crack: broadband, very fast attack
			v += w * exp(-s * 18.0) * 0.9 + sin(s * 2300.0) * exp(-s * 30.0) * 0.2
		out[i] = v
	var fade := int(0.3 * RATE)
	for j in fade:
		out[n - fade + j] *= 1.0 - float(j) / fade
	return out


func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var peak := 0.0001
	for v in samples:
		peak = maxf(peak, absf(v))
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	var g := 0.9 / peak
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i] * g, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = samples.size()
	return wav
