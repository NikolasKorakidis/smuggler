# Anemos - weather and cloud system for Godot.
# Copyright (c) 2026 Nikolas Korakidis. All rights reserved. See addons/anemos/LICENSE.md.
class_name AnemosClouds
extends Node
## The cloud engine's controller: turns the Weather into up to three cloud
## layers (each a CloudType from world/clouds/types) plus storm towers, and
## feeds clouds.glsl (through AtmosphereEffect) every frame: placement, wind
## drift and lean, slow growth and decay of cells, the sun (or moon) as seen at
## cloud height, sky light, lightning flashes.
##
## The 2D weather map (where clouds are) is generated once on a worker
## thread; its histogram turns "cover 0.3" into a threshold that really covers
## 30% of the sky. The same map answers "is this point in cloud?" on the CPU.
## The dev menu's Clouds tab can take over a layer (designer).

const MAP_SIZE := 512
const MAP_TILE_M := 51200.0  # one map tile spans 51.2 km, then repeats
const SHAPE_TILE_M := 4500.0
const DETAIL_TILE_M := 380.0
const PLANET_R := 6360000.0
const STORM_TOP_ABOVE_BASE := 9500.0
const TYPES_DIR := "res://addons/anemos/clouds/types/"


## One cloud layer. Heights are above the airfield.
class Layer:
	var enabled := false
	var type_id := ""
	var type: AnemosCloudType
	var cover := 0.0
	var base_m := 1500.0
	var top_m := 2000.0
	## Set by the designer: the Weather no longer drives this layer.
	var manual := false


var weather: AnemosWeather
var anemos: Anemos
var sky: Object
var atmosphere: AnemosAtmosphere
## Quality: ray-march steps and sun-march steps.
var steps := 96
var light_steps := 6
## How fast cells grow and dissolve (1 = about 20 minutes per cell).
var evolution := 1.0
## The cloud type library, by id (file name).
var types := {}
var layers: Array[Layer] = [Layer.new(), Layer.new(), Layer.new()]

var _map: Image
var _map_tex: ImageTexture
var _profile_img := Image.create(64, 4, false, Image.FORMAT_RF)
var _profile_tex: ImageTexture
var _profile_key := ""
var _task := -1
var _q_cu := PackedFloat32Array()
var _q_st := PackedFloat32Array()
var _shape_off := Vector2.ZERO
var _detail_off := Vector2.ZERO
var _map_off := Vector2.ZERO
var _evolve_t := 0.0
var _flashes: Array[Dictionary] = []


func _init(a: Anemos) -> void:
	anemos = a
	weather = a.weather
	sky = a.sky
	atmosphere = a.atmosphere
	name = "Clouds"
	for f in DirAccess.get_files_at(TYPES_DIR):
		var file := f.trim_suffix(".remap")
		if file.ends_with(".tres"):
			types[file.trim_suffix(".tres")] = load(TYPES_DIR + file)


func _ready() -> void:
	weather.lightning.connect(_on_lightning)
	weather.cloud_probe = density_at
	_task = WorkerThreadPool.add_task(_build_map)


func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## Give a layer to the designer (or back to the weather).
func set_manual(i: int, on: bool) -> void:
	layers[i].manual = on
	if on and layers[i].type:
		layers[i].type = layers[i].type.duplicate(true)  # tweak a copy, not the library


func set_layer_type(i: int, id: String) -> void:
	layers[i].type_id = id
	layers[i].type = types[id].duplicate(true) if layers[i].manual else types[id]
	_profile_key = ""


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
	cu.resize(n / 16)
	st.resize(n / 16)
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
	cu.sort()
	st.sort()
	_q_cu = cu
	_q_st = st
	_map = Image.create_from_data(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8, data)


static func _quantile(sorted: PackedFloat32Array, q: float) -> float:
	if sorted.is_empty():
		return 0.5
	return sorted[clampi(int(q * (sorted.size() - 1)), 0, sorted.size() - 1)]


## The coverage threshold that makes `cover` of the sky cloudy for this type.
func threshold(cover: float, heaps: float) -> float:
	if cover >= 0.999:
		return -1.0
	if cover <= 0.005:
		return 2.0
	return lerpf(_quantile(_q_st, 1.0 - cover), _quantile(_q_cu, 1.0 - cover), heaps)


# The Weather's cloud fields as layers (unless the designer owns a layer).
func _layers_from_weather() -> void:
	var w := weather
	var low := layers[0]
	if not low.manual:
		var depth := w.cloud_top_m - w.cloud_base_m
		var id := "cumulus_mediocris"
		if w.cloud_type >= 0.75:
			id = "nimbostratus" if w.rain_mmh >= 2.0 else "stratus"
		elif w.cloud_type >= 0.3:
			id = "stratocumulus"
		elif depth < 700.0:
			id = "cumulus_humilis"
		elif depth > 1800.0:
			id = "cumulus_congestus"
		if id != low.type_id:
			set_layer_type(0, id)
		low.enabled = w.cloud_cover > 0.005
		low.cover = w.cloud_cover
		low.base_m = w.cloud_base_m
		low.top_m = maxf(w.cloud_top_m, w.cloud_base_m + 250.0)
		# Fair-weather cumulus build with the day's heating: few and flat in
		# the morning, most and deepest mid-afternoon, fading in the evening.
		if w.cloud_type < 0.3 and w.cells.is_empty():
			var hr: float = sky.anemos_hours()
			var heat := smoothstep(8.0, 14.5, hr) * (1.0 - smoothstep(17.5, 21.0, hr))
			low.cover = w.cloud_cover * (0.5 + 0.55 * heat)
			low.top_m = low.base_m + (low.top_m - low.base_m) * (0.65 + 0.45 * heat)
	var mid := layers[1]
	if not mid.manual:
		var id := "altostratus" if w.mid_cover >= 0.6 else "altocumulus"
		if id != mid.type_id:
			set_layer_type(1, id)
		mid.enabled = w.mid_cover > 0.01
		mid.cover = w.mid_cover
		mid.base_m = w.mid_base_m
		mid.top_m = maxf(w.mid_top_m, w.mid_base_m + 150.0)
	if not layers[2].manual:
		layers[2].enabled = false
		if layers[2].type == null:
			set_layer_type(2, "altocumulus")


# Profile curves into a small texture (rows: layers 0-2, storm).
func _update_profiles() -> void:
	var key := ""
	for l in layers:
		key += "%s:%d;" % [l.type_id, l.type.profile.get_instance_id() if l.type else 0]
		if l.type and l.type.profile:
			key += str(l.type.profile.get_point_count()) + str(l.type.profile.get_point_position(1))
	if key == _profile_key and _profile_tex:
		return
	_profile_key = key
	var cb: AnemosCloudType = types.get("cumulonimbus")
	for row in 4:
		var t: AnemosCloudType = layers[row].type if row < 3 else cb
		for x in 64:
			var v := 0.0
			if t and t.profile:
				v = clampf(t.profile.sample(x / 63.0), 0.0, 1.0)
			_profile_img.set_pixel(x, row, Color(v, 0, 0))
	if _profile_tex == null:
		_profile_tex = ImageTexture.create_from_image(_profile_img)
		atmosphere.profile_texture = _profile_tex
	else:
		_profile_tex.update(_profile_img)


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
	_layers_from_weather()
	_update_profiles()
	# Wind: clouds drift with the wind at their height; detail churns faster.
	var wind := w.air_velocity(layers[0].base_m)
	var wind2 := Vector2(wind.x, wind.z)
	_map_off = _wrap2(_map_off - wind2 * delta, MAP_TILE_M)
	_shape_off = _wrap2(_shape_off - wind2 * delta * 1.05, SHAPE_TILE_M)
	_detail_off = _wrap2(_detail_off - wind2 * delta * 1.4 - Vector2(0.6, 0.3) * delta, DETAIL_TILE_M)
	_evolve_t = fposmod(_evolve_t + delta * 2.1e-4 * evolution, 1.0)
	var aloft := w.air_velocity(layers[0].top_m)
	var lean := Vector2(aloft.x - wind.x, aloft.z - wind.z) * 0.02

	var out := PackedFloat32Array()
	out.append_array([_shape_off.x, _shape_off.y, _detail_off.x, _detail_off.y])
	out.append_array([_map_off.x, _map_off.y, lean.x, lean.y])
	out.append_array([SHAPE_TILE_M, DETAIL_TILE_M, MAP_TILE_M, PLANET_R])
	var light := _cloud_light()
	out.append_array([light[0].x, light[0].y, light[0].z, 0.5])
	out.append_array([light[1].x, light[1].y, light[1].z, 0.0])
	# Sky light on the tops; from below the ground bounce (sunlit grass and soil).
	var top_amb := anemos.zenith * 1.1 + anemos.horizon * 0.12
	var sun: DirectionalLight3D = sky.anemos_sun()
	var sun_e := sun.light_energy if sun.visible else 0.0
	var sun_up := maxf(sun.global_transform.basis.z.y, 0.0)
	var ground := sun.light_color * sun_e * sun_up * 0.035
	var bottom_amb := anemos.horizon * 0.12 + Vector3(ground.r, ground.g * 0.95, ground.b * 0.8)
	# Under or inside a deck the light is grey, not sky blue.
	var deck := smoothstep(0.5, 1.0, w.cloud_cover) * (0.5 + 0.5 * w.cloud_type)
	top_amb = top_amb.lerp(Vector3.ONE * (top_amb.x + top_amb.y + top_amb.z) / 3.0, deck)
	bottom_amb = bottom_amb.lerp(Vector3.ONE * (bottom_amb.x + bottom_amb.y + bottom_amb.z) / 3.0, deck * 0.7)
	out.append_array([top_amb.x, top_amb.y, top_amb.z, 0.0])
	out.append_array([bottom_amb.x, bottom_amb.y, bottom_amb.z, 0.0])
	_step_flashes(delta)
	var n_storms := mini(w.cells.size(), 8)
	out.append_array([float(n_storms), float(mini(_flashes.size(), 4)), 0.0, float(steps)])
	out.append_array([field, 60000.0, 0.12, float(light_steps)])
	out.append_array([_evolve_t, 0.25, 0.0, 0.0])
	var geo := PackedFloat32Array()
	var pa := PackedFloat32Array()
	var pb := PackedFloat32Array()
	var pcc := PackedFloat32Array()
	for l in layers:
		var t := l.type
		if t == null or not l.enabled:
			geo.append_array([0.0, 0.0, 2.0, 0.0])
			pa.append_array([0.1, 0.0, 0.0, 0.0])
			pb.append_array([0.0, 0.0, 0.0, 0.0])
			pcc.append_array([0.0, 0.0, 1.0, 0.0])
			continue
		var pk := t.packed()
		geo.append_array([field + l.base_m, field + l.top_m, threshold(l.cover, t.heaps), 1.0])
		pa.append_array([pk[0].x, pk[0].y, pk[0].z, pk[0].w])
		pb.append_array([pk[1].x, pk[1].y, pk[1].z, pk[1].w])
		pcc.append_array([pk[2].x, pk[2].y, pk[2].z, pk[2].w])
	out.append_array(geo)
	out.append_array(pa)
	out.append_array(pb)
	out.append_array(pcc)
	var cb: AnemosCloudType = types.get("cumulonimbus")
	for v in cb.packed():
		out.append_array([v.x, v.y, v.z, v.w])
	var storms := PackedFloat32Array()
	var storms_b := PackedFloat32Array()
	for i in 8:
		if i < n_storms:
			var c := w.cells[i]
			var k := c.cloud_k()
			var sb := field + c.base_m
			storms.append_array([c.pos.x, c.pos.y, c.radius * 1.7 * (0.5 + 0.5 * k), sb + STORM_TOP_ABOVE_BASE * (0.3 + 0.7 * k)])
			storms_b.append_array([clampf(k * (0.6 + 0.4 * c.strength), 0.0, 1.0), 1.5 * c.mature_k() + 0.3, sb, 0.0])
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


# The light the clouds get: the sun as seen at cloud height (it sets later up
# there and isn't dimmed by the clouds themselves), or the moon at night.
func _cloud_light() -> Array[Vector3]:
	var alt := weather.field_elevation_m + 0.5 * (layers[0].base_m + layers[0].top_m)
	var sd: Vector3 = sky.anemos_sun_direction()
	var dip := rad_to_deg(sqrt(2.0 * maxf(alt, 0.0) / PLANET_R))
	var el: float = sky.anemos_sun_elevation_deg() + dip
	var tr: Vector3 = sky.anemos_transmittance(sd, alt)
	var tl := (tr.x + tr.y + tr.z) / 3.0
	var col := tr / maxf(maxf(tr.x, maxf(tr.y, tr.z)), 1e-4)
	var e := 2.0 * clampf(tl / 0.75, 0.0, 1.0) * smoothstep(-1.0, 5.0, el) * 1.1
	var moon: DirectionalLight3D = sky.anemos_moon()
	if moon and moon.light_energy * 1.1 > e:
		var md := moon.global_transform.basis.z.normalized()
		var mc := moon.light_color * moon.light_energy * 1.1
		return [md, Vector3(mc.r, mc.g, mc.b)]
	return [sd, col * e]


## Square of the cloud-shadow map (origin x, origin z, size m, plane y) around
## the camera, snapped to its texels so shadows don't crawl as you move.
func shadow_rect() -> Vector4:
	var cam := anemos.view_camera()
	var c := cam.global_position if cam else Vector3.ZERO
	var size := 24000.0
	var texel := size / AnemosAtmosphere.SHADOW_SIZE
	var x0 := floorf((c.x - size * 0.5) / texel) * texel
	var z0 := floorf((c.z - size * 0.5) / texel) * texel
	var bottom := 1e9
	for l in layers:
		if l.enabled and l.type:
			bottom = minf(bottom, weather.field_elevation_m + l.base_m - l.type.base_wobble)
	for cell in weather.cells:
		bottom = minf(bottom, weather.field_elevation_m + cell.base_m)
	if bottom > 1e8:
		bottom = weather.field_elevation_m + weather.cloud_base_m
	return Vector4(x0, z0, size, bottom - 50.0)


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
	var best := 0.0
	for c in w.cells:
		var r := c.radius * 1.7 * (0.5 + 0.5 * c.cloud_k())
		var hs := (at.y - w.field_elevation_m - c.base_m) / (STORM_TOP_ABOVE_BASE * (0.3 + 0.7 * c.cloud_k()))
		if hs > 0.0 and hs < 1.0:
			best = maxf(best, (1.0 - smoothstep(0.45 * r, r, Vector2(at.x, at.z).distance_to(c.pos))) * c.cloud_k())
	for i in layers.size():
		var l := layers[i]
		if not l.enabled or l.type == null:
			continue
		var h := (at.y - w.field_elevation_m - l.base_m) / maxf(l.top_m - l.base_m, 1.0)
		if h <= 0.0 or h >= 1.0:
			continue
		var p := Vector2(at.x, at.z) * (1.0 - 0.25 * i) + _map_off + Vector2(9000.0, 4000.0) * i
		var uv := p / MAP_TILE_M
		var px := _map.get_pixel(posmod(int(uv.x * MAP_SIZE), MAP_SIZE), posmod(int(uv.y * MAP_SIZE), MAP_SIZE))
		var heaps := l.type.heaps
		var f := lerpf(px.g * 0.55 + px.b * 0.35 + px.a * 0.1, px.r * 0.65 + px.a * 0.2 + px.g * 0.15, heaps)
		var tau := threshold(l.cover, heaps)
		var cov := smoothstep(tau - l.type.softness, tau + l.type.softness, f)
		best = maxf(best, cov * clampf(l.type.profile.sample(h), 0.0, 1.0))
	return best


static func _wrap2(v: Vector2, tile: float) -> Vector2:
	return Vector2(fposmod(v.x, tile), fposmod(v.y, tile))
