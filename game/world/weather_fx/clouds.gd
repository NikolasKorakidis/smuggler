class_name Clouds
extends Node
## Our volumetric clouds (clouds.glsl through AtmosphereEffect), driven by the
## Weather: a low layer (cumulus .. stratus, storm towers with anvils) and a
## thin mid layer, drifting and leaning with the wind, lit by the same sun,
## moon and sky as everything else, lightning glowing inside.
##
## The 2D weather map (where clouds are) is generated once on a worker
## thread; its histogram turns "cover 0.3" into a threshold that really covers
## 30% of the sky. The same map answers "is this point in cloud?" on the CPU.

const MAP_SIZE := 512
const MAP_TILE_M := 51200.0  # one map tile spans 51.2 km, then repeats
const SHAPE_TILE_M := 4500.0
const DETAIL_TILE_M := 380.0
const PLANET_R := 6360000.0
const STORM_TOP_ABOVE_BASE := 9500.0

var weather: Weather
var tod: TimeOfDay
var atmosphere: AtmosphereEffect
## Sky radiance near the horizon and overhead (set by WeatherFX).
var horizon := Vector3(0.5, 0.6, 0.8)
var zenith := Vector3(0.1, 0.2, 0.5)
## Ray-march steps (quality).
var steps := 96

var _map: Image
var _map_tex: ImageTexture
var _task := -1
# Sorted samples of the three coverage fields (cumulus, stratus, mid) for quantiles.
var _q_cu := PackedFloat32Array()
var _q_st := PackedFloat32Array()
var _q_mid := PackedFloat32Array()
var _shape_off := Vector2.ZERO
var _detail_off := Vector2.ZERO
var _map_off := Vector2.ZERO
var _flashes: Array[Dictionary] = []


func _init(w: Weather, t: TimeOfDay, effect: AtmosphereEffect) -> void:
	weather = w
	tod = t
	atmosphere = effect
	name = "Clouds"


func _ready() -> void:
	weather.lightning.connect(_on_lightning)
	weather.cloud_probe = density_at
	_task = WorkerThreadPool.add_task(_build_map)


func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


# Weather map: R cumulus cells, G regional patchiness, B mid-scale, A fine.
func _build_map() -> void:
	var cells := FastNoiseLite.new()
	cells.noise_type = FastNoiseLite.TYPE_CELLULAR
	cells.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	cells.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	cells.frequency = 0.045  # cells ~2.2 km apart (100 m per pixel)
	cells.cellular_jitter = 1.0
	cells.seed = 11
	var regional := FastNoiseLite.new()
	regional.noise_type = FastNoiseLite.TYPE_PERLIN
	regional.fractal_type = FastNoiseLite.FRACTAL_FBM
	regional.fractal_octaves = 3
	regional.frequency = 0.006
	regional.seed = 23
	var mid := FastNoiseLite.new()
	mid.noise_type = FastNoiseLite.TYPE_PERLIN
	mid.fractal_type = FastNoiseLite.FRACTAL_FBM
	mid.fractal_octaves = 4
	mid.frequency = 0.02
	mid.seed = 37
	var fine := FastNoiseLite.new()
	fine.noise_type = FastNoiseLite.TYPE_CELLULAR
	fine.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	fine.frequency = 0.12
	fine.seed = 41
	var imgs := []
	for n in [cells, regional, mid, fine]:
		var im: Image = n.get_seamless_image(MAP_SIZE, MAP_SIZE, false, false, 0.1, true)
		im.convert(Image.FORMAT_L8)
		imgs.append(im)
	var data := PackedByteArray()
	data.resize(MAP_SIZE * MAP_SIZE * 4)
	var c_data: PackedByteArray = imgs[0].get_data()
	var r_data: PackedByteArray = imgs[1].get_data()
	var m_data: PackedByteArray = imgs[2].get_data()
	var f_data: PackedByteArray = imgs[3].get_data()
	var n := MAP_SIZE * MAP_SIZE
	var cu := PackedFloat32Array()
	var st := PackedFloat32Array()
	var md := PackedFloat32Array()
	cu.resize(n / 16)
	st.resize(n / 16)
	md.resize(n / 16)
	for i in n:
		# Cellular distance is small at the cell centre: invert so centres are high.
		var r := 255 - c_data[i]
		var a := 255 - f_data[i]
		data[i * 4] = r
		data[i * 4 + 1] = r_data[i]
		data[i * 4 + 2] = m_data[i]
		data[i * 4 + 3] = a
		if i % 16 == 0:
			var k := i / 16
			cu[k] = (r * 0.65 + a * 0.2 + r_data[i] * 0.15) / 255.0
			st[k] = (r_data[i] * 0.55 + m_data[i] * 0.35 + a * 0.1) / 255.0
			md[k] = (m_data[i] * 0.5 + a * 0.3 + r_data[i] * 0.2) / 255.0
	cu.sort()
	st.sort()
	md.sort()
	_q_cu = cu
	_q_st = st
	_q_mid = md
	_map = Image.create_from_data(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8, data)


static func _quantile(sorted: PackedFloat32Array, q: float) -> float:
	if sorted.is_empty():
		return 0.5
	return sorted[clampi(int(q * (sorted.size() - 1)), 0, sorted.size() - 1)]


func _process(delta: float) -> void:
	if _task != -1:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_map_tex = ImageTexture.create_from_image(_map)
		atmosphere.weather_texture = _map_tex
	if _map_tex == null:
		return
	var w := weather
	var field := w.field_elevation_m
	var cumulus := 1.0 - w.cloud_type
	# Wind: clouds drift with the wind at their height; detail churns faster.
	var wind := w.air_velocity(w.cloud_base_m)
	var wind2 := Vector2(wind.x, wind.z)
	_map_off = _wrap2(_map_off - wind2 * delta, MAP_TILE_M)
	_shape_off = _wrap2(_shape_off - wind2 * delta * 1.05, SHAPE_TILE_M)
	_detail_off = _wrap2(_detail_off - wind2 * delta * 1.4 - Vector2(0.6, 0.3) * delta, DETAIL_TILE_M)
	# Lean downwind with height (the tops are blown further).
	var aloft := w.air_velocity(w.cloud_top_m)
	var lean := Vector2(aloft.x - wind.x, aloft.z - wind.z) * 0.02

	var base_y := field + w.cloud_base_m
	var top_y := field + maxf(w.cloud_top_m, w.cloud_base_m + 250.0)
	var cover := clampf(w.cloud_cover, 0.0, 1.0)
	var tau := lerpf(_quantile(_q_st, 1.0 - cover), _quantile(_q_cu, 1.0 - cover), cumulus)
	if cover >= 0.999:
		tau = -1.0
	var any_storm := not w.cells.is_empty()
	var density := 1.0 if cover > 0.005 or any_storm else 0.0
	if cover <= 0.005:
		tau = 2.0  # no layer cloud, storms only (the shader skips the layer)
	var out := PackedFloat32Array()
	# low: bottom, top, extinction, type (0.5 cumulus .. 0 stratus)
	out.append_array([base_y, top_y, lerpf(0.035, 0.07, cumulus), 0.5 * cumulus])
	# cov: threshold, softness, edge erosion, density
	out.append_array([tau, lerpf(0.09, 0.07, cumulus), lerpf(0.3, 0.5, cumulus), density])
	# mid layer
	if w.mid_cover > 0.01:
		out.append_array([field + w.mid_base_m, field + w.mid_top_m, _quantile(_q_mid, 1.0 - w.mid_cover), 0.02])
	else:
		out.append_array([0.0, 0.0, 2.0, 0.0])
	out.append_array([_shape_off.x, _shape_off.y, _detail_off.x, _detail_off.y])
	out.append_array([_map_off.x, _map_off.y, lean.x, lean.y])
	out.append_array([SHAPE_TILE_M, DETAIL_TILE_M, MAP_TILE_M, PLANET_R])
	# Sun, or the moon once the sun is down.
	var sun := tod.sun
	var light := sun
	if tod._moon and tod._moon.light_energy > sun.light_energy:
		light = tod._moon
	var ld := light.global_transform.basis.z.normalized()
	var e := light.light_energy if light.visible else 0.0
	var lc := light.light_color * e * 1.1
	out.append_array([ld.x, ld.y, ld.z, 0.5])
	out.append_array([lc.r, lc.g, lc.b, 0.0])
	# Sky light on the tops; from below the ground bounce (sunlit grass and soil).
	var top_amb := zenith * 1.1 + horizon * 0.12
	var sun_e := sun.light_energy if sun.visible else 0.0
	var sun_up := maxf(sun.global_transform.basis.z.y, 0.0)
	var ground := sun.light_color * sun_e * sun_up * 0.035
	var bottom_amb := horizon * 0.12 + Vector3(ground.r, ground.g * 0.95, ground.b * 0.8)
	# Under or inside a deck the light is grey, not sky blue.
	var deck := smoothstep(0.5, 1.0, cover) * (0.5 + 0.5 * w.cloud_type)
	top_amb = top_amb.lerp(Vector3.ONE * (top_amb.x + top_amb.y + top_amb.z) / 3.0, deck)
	bottom_amb = bottom_amb.lerp(Vector3.ONE * (bottom_amb.x + bottom_amb.y + bottom_amb.z) / 3.0, deck * 0.7)
	out.append_array([top_amb.x, top_amb.y, top_amb.z, 0.0])
	out.append_array([bottom_amb.x, bottom_amb.y, bottom_amb.z, 0.0])
	_step_flashes(delta)
	var n_storms := mini(w.cells.size(), 8)
	out.append_array([float(n_storms), float(mini(_flashes.size(), 4)), 0.0, float(steps)])
	out.append_array([field, 60000.0, 0.12, 6.0])
	var storms := PackedFloat32Array()
	var storms_b := PackedFloat32Array()
	for i in 8:
		if i < n_storms:
			var c := w.cells[i]
			var k := c.cloud_k()
			storms.append_array([c.pos.x, c.pos.y, c.radius * 1.7 * (0.5 + 0.5 * k), base_y + STORM_TOP_ABOVE_BASE * (0.3 + 0.7 * k)])
			storms_b.append_array([clampf(k * (0.6 + 0.4 * c.strength), 0.0, 1.0), 1.5 * c.mature_k() + 0.3, 0.0, 0.0])
		else:
			storms.append_array([0.0, 0.0, 1.0, 0.0])
			storms_b.append_array([0.0, 0.0, 0.0, 0.0])
	out.append_array(storms)
	out.append_array(storms_b)
	for i in 4:
		if i < _flashes.size():
			var f: Dictionary = _flashes[i]
			out.append_array([f.pos.x, f.pos.y, f.pos.z, f.level])
		else:
			out.append_array([0.0, 0.0, 0.0, 0.0])
	atmosphere.set_cloud_params(out, shadow_rect())


## Square of the cloud-shadow map (origin x, origin z, size m) around the
## camera, snapped to its texels so shadows don't crawl as you move.
func shadow_rect() -> Vector4:
	var cam := get_viewport().get_camera_3d()
	var c := cam.global_position if cam else Vector3.ZERO
	var size := 24000.0
	var texel := size / AtmosphereEffect.SHADOW_SIZE
	var x0 := floorf((c.x - size * 0.5) / texel) * texel
	var z0 := floorf((c.z - size * 0.5) / texel) * texel
	return Vector4(x0, z0, size, weather.field_elevation_m + weather.cloud_base_m - 100.0)


func _step_flashes(delta: float) -> void:
	for i in range(_flashes.size() - 1, -1, -1):
		var f: Dictionary = _flashes[i]
		f.t += delta
		if f.t > f.len:
			_flashes.remove_at(i)
			continue
		# A few return strokes in a fraction of a second.
		f.level = f.power * (1.0 - f.t / f.len) * (0.55 + 0.45 * sin(f.t * 90.0 + f.seed)) * 6.0


func _on_lightning(at: Vector3, to_ground: bool, power: float) -> void:
	var h := maxf(at.y, weather.field_elevation_m + weather.cloud_base_m + (300.0 if to_ground else 2500.0))
	_flashes.append({"pos": Vector3(at.x, h, at.z), "power": power * (1.4 if to_ground else 1.0), "t": 0.0,
		"len": randf_range(0.3, 0.7), "seed": randf() * 10.0, "level": 0.0})


## How much cloud there is at a world point (0 clear .. 1 thick), from the
## weather map (no fine noise): for in-cloud flying (whiteout, turbulence, wet glass).
func density_at(at: Vector3) -> float:
	if _map == null:
		return 0.0
	var w := weather
	var h := (at.y - w.field_elevation_m - w.cloud_base_m) / maxf(w.cloud_top_m - w.cloud_base_m, 1.0)
	var storm := 0.0
	for c in w.cells:
		var r := c.radius * 1.7 * (0.5 + 0.5 * c.cloud_k())
		var top := STORM_TOP_ABOVE_BASE * (0.3 + 0.7 * c.cloud_k())
		var hs := (at.y - w.field_elevation_m - w.cloud_base_m) / top
		if hs > 0.0 and hs < 1.0:
			storm = maxf(storm, (1.0 - smoothstep(0.45 * r, r, Vector2(at.x, at.z).distance_to(c.pos))) * c.cloud_k())
	if h <= 0.0 or h >= 1.0 or w.cloud_cover <= 0.005:
		return storm
	var uv := (Vector2(at.x, at.z) + _map_off) / MAP_TILE_M
	var px := _map.get_pixel(posmod(int(uv.x * MAP_SIZE), MAP_SIZE), posmod(int(uv.y * MAP_SIZE), MAP_SIZE))
	var cumulus := 1.0 - w.cloud_type
	var f := lerpf(px.g * 0.55 + px.b * 0.35 + px.a * 0.1, px.r * 0.65 + px.a * 0.2 + px.g * 0.15, cumulus)
	var tau := lerpf(_quantile(_q_st, 1.0 - w.cloud_cover), _quantile(_q_cu, 1.0 - w.cloud_cover), cumulus)
	if w.cloud_cover >= 0.999:
		tau = -1.0
	var cov := smoothstep(tau - 0.05, tau + 0.05, f)
	var prof := smoothstep(0.0, 0.1, h) * (1.0 - smoothstep(lerpf(0.55, 0.3, cumulus), 1.0, h))
	return maxf(cov * prof, storm)


static func _wrap2(v: Vector2, tile: float) -> Vector2:
	return Vector2(fposmod(v.x, tile), fposmod(v.y, tile))
