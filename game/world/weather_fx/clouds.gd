class_name Clouds
extends Node
## Volumetric clouds (SunshineClouds 2 compositor effect, MIT) driven by the
## Weather: cover, base and top, cumulus/stratus shape, drift with the wind
## aloft, storm towers from the storm cells, lightning glowing inside them.
## Lit by the same sun, moon and sky as everything else.
##
## Drives the effect directly instead of through the addon's driver node, so
## light levels change smoothly (the driver rounds them) and an extra soft
## light from overhead keeps clouds lit by the sky at twilight.

const RESOURCE := "res://addons/SunshineClouds2/SunshineCloudsGDTestResource.tres"
## Storm tower: heights above the cloud base (m) and radius factors.
const TOWER := [[500.0, 2.4], [1800.0, 2.3], [3300.0, 2.1], [4900.0, 1.9], [6500.0, 1.8], [8000.0, 2.2], [9300.0, 3.6]]
const STORM_TOP := 10500.0

var effect: SunshineCloudsGD
var weather: Weather
var tod: TimeOfDay
## Sky radiance near the horizon and overhead (set by WeatherFX).
var horizon := Vector3(0.5, 0.6, 0.8)
var zenith := Vector3(0.1, 0.2, 0.5)

var _gradient := Gradient.new()
var _gradient_tex := GradientTexture1D.new()
var _shape_key := Vector2(-1, -1)
var _pos := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]  # extra large, large, medium, small
var _flashes: Array[Dictionary] = []  # lightning glowing in the cloud


func _init(w: Weather, t: TimeOfDay) -> void:
	weather = w
	tod = t
	effect = (load(RESOURCE) as SunshineCloudsGD).duplicate()
	effect.resolution_scale = 2  # quarter resolution, upscaled (soft clouds)
	# Right after the sky (not before transparents) so refracting glass sees the clouds.
	effect.effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_SKY
	effect.max_step_count = 64
	effect.max_lighting_steps = 12
	effect.min_step_distance = 90.0
	effect.max_step_distance = 220.0
	effect.lighting_travel_distance = 3000.0
	effect.extra_large_noise_scale = 60000.0
	effect.large_noise_scale = 14000.0
	effect.medium_noise_scale = 4200.0
	effect.small_noise_scale = 1300.0
	effect.curl_noise_strength = 450.0
	effect.clouds_density = 1.0
	effect.atmospheric_density = 0.0  # our fog effect does the haze
	effect.fog_effect_ground = 0.0
	effect.use_environment_fog = 0.0
	_gradient_tex.width = 128
	_gradient_tex.gradient = _gradient
	effect.height_gradient = _gradient_tex
	weather.lightning.connect(_on_lightning)


func _process(delta: float) -> void:
	var w := weather
	var field := w.field_elevation_m
	var storms := not w.cells.is_empty()
	var floor_y := field + w.cloud_base_m
	var top_y := field + maxf(w.cloud_top_m, w.cloud_base_m + 200.0)
	var ceiling := maxf(top_y, field + w.cloud_base_m + STORM_TOP) if storms else top_y
	effect.cloud_floor = floor_y
	effect.cloud_ceiling = ceiling
	_update_shape((top_y - floor_y) / maxf(ceiling - floor_y, 1.0), w.cloud_type)
	effect.clouds_coverage = _coverage_param(w.cloud_cover)
	effect.clouds_detail_power = lerpf(1.1, 0.5, w.cloud_type)
	effect.clouds_sharpness = lerpf(0.75, 0.45, w.cloud_type)
	effect.lighting_density = lerpf(1.0, 1.6, w.cloud_type)

	# Drift with the wind at cloud height (detail churns a little faster).
	var wind := w.air_velocity(w.cloud_base_m)
	var speeds := [0.6, 1.0, 1.15, 1.4]
	var domains := [effect.extra_large_noise_scale, effect.large_noise_scale, effect.medium_noise_scale, effect.small_noise_scale]
	for i in 4:
		_pos[i] = _wrap(_pos[i] + wind * speeds[i] * delta, domains[i] * 0.5)
	effect.extra_large_scale_clouds_position = _pos[0]
	effect.large_scale_clouds_position = _pos[1]
	effect.medium_scale_clouds_position = _pos[2]
	effect.detail_clouds_position = _pos[3] + Vector3.UP * 0.4 * Time.get_ticks_msec() / 1000.0
	effect.wind_direction = wind.normalized() if wind.length() > 0.1 else Vector3.RIGHT
	effect.current_time = wrapf(effect.current_time + delta * effect.dither_speed, 0.0, effect.dither_speed * 64.0)

	# Light. The effect raises colour x energy to the power 2.2, so hand it the
	# 1/2.2 root to keep brightness proportional to the real light.
	var dir_data: Array[Vector4] = []
	_add_light(dir_data, tod.sun, 10, 0.55)
	if tod._moon:
		_add_light(dir_data, tod._moon, 6, 0.55)
	# Soft light from overhead: the sky dome (keeps twilight clouds lit).
	var sky := (zenith * 0.6 + horizon * 0.4) * 0.9
	var sky_e := maxf(maxf(sky.x, sky.y), maxf(sky.z, 1e-6))
	dir_data.append(Vector4(0.0, 1.0, 0.0, 3.0))
	dir_data.append(Vector4(pow(sky.x / sky_e, 1.0 / 2.2), pow(sky.y / sky_e, 1.0 / 2.2), pow(sky.z / sky_e, 1.0 / 2.2), pow(sky_e, 1.0 / 2.2)))
	# Ambient is scaled by the summed light energies inside the effect: divide it out.
	var total := 0.0
	for i in range(1, dir_data.size(), 2):
		var up := smoothstep(-0.03, 0.07, dir_data[i - 1].y)
		total += dir_data[i].w * up
	var amb := (zenith + horizon) * 0.35 / maxf(total, 1e-4)
	effect.cloud_ambient_color = Color(amb.x, amb.y, amb.z)
	effect.ambient_occlusion_color = Color(0.35, 0.38, 0.45, 0.7)  # darker undersides
	effect.atmosphere_color = Color(horizon.x, horizon.y, horizon.z)

	var point_data: Array[Vector4] = []
	for i in range(_flashes.size() - 1, -1, -1):
		var f: Dictionary = _flashes[i]
		f.t += delta
		if f.t > f.len:
			_flashes.remove_at(i)
			continue
		# Flicker: a few return strokes in a fraction of a second.
		var k: float = (1.0 - f.t / f.len) * (0.6 + 0.4 * sin(f.t * 90.0 + f.seed))
		point_data.append(Vector4(f.pos.x, f.pos.y, f.pos.z, f.range))
		point_data.append(Vector4(0.85, 0.88, 1.0, pow(f.power * k * 40.0, 1.0 / 2.2)))

	var eff_data: Array[Vector4] = []
	for c in w.cells:
		var k := c.cloud_k()
		if k <= 0.01:
			continue
		for level in TOWER:
			if eff_data.size() >= 128:
				break
			var h: float = level[0] * (0.35 + 0.65 * k)  # the tower grows upward
			eff_data.append(Vector4(c.pos.x, floor_y + h, c.pos.y, c.radius * level[1] * (0.6 + 0.4 * k)))
			eff_data.append(Vector4(2.2 * k * c.strength, 0.0, 0.0, 0.0))
	RenderingServer.call_on_render_thread(_hand_over.bind(dir_data, point_data, eff_data))


func _hand_over(dir_data: Array[Vector4], point_data: Array[Vector4], eff_data: Array[Vector4]) -> void:
	effect.directional_lights_data = dir_data
	effect.point_lights_data = point_data
	effect.point_effector_data = eff_data
	effect.lights_updated = true


func _add_light(out: Array[Vector4], light: DirectionalLight3D, steps: int, scale: float) -> void:
	var e := light.light_energy * scale if light.visible else 0.0
	var c := light.light_color
	var d := light.global_transform.basis.z.normalized()
	out.append(Vector4(d.x, d.y, d.z, steps))
	out.append(Vector4(pow(c.r, 1.0 / 2.2), pow(c.g, 1.0 / 2.2), pow(c.b, 1.0 / 2.2), pow(e, 1.0 / 2.2)))


# Cumulus: flat base, puffy rounded tops, curling. Stratus: a flat sheet.
# `f` = fraction of the effect's height range the layer fills (storm towers
# use the rest).
func _update_shape(f: float, kind: float) -> void:
	var key := Vector2(snappedf(f, 0.01), snappedf(kind, 0.02))
	if key == _shape_key:
		return
	_shape_key = key
	var cu := [[0.0, 0.0, 0.4, 1.0, 1.0], [0.06, 1.0, 0.6, 1.0, 1.0], [0.45, 1.0, 0.9, 1.0, 0.7], [0.8, 0.55, 1.0, 1.0, 0.4], [1.0, 0.0, 1.0, 1.0, 0.3]]
	var st := [[0.0, 0.0, 0.3, 1.0, 1.0], [0.12, 1.0, 0.35, 1.0, 1.0], [0.5, 1.0, 0.4, 1.0, 1.0], [0.88, 1.0, 0.45, 1.0, 1.0], [1.0, 0.0, 0.5, 1.0, 1.0]]
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in cu.size():
		offsets.append(clampf(lerpf(cu[i][0], st[i][0], kind) * f, 0.0, 1.0))
		colors.append(Color(lerpf(cu[i][1], st[i][1], kind), lerpf(cu[i][2], st[i][2], kind),
			lerpf(cu[i][3], st[i][3], kind), lerpf(cu[i][4], st[i][4], kind)))
	if f < 0.98:  # above the layer: only storm towers (effectors)
		offsets.append(minf(f + 0.01, 1.0))
		colors.append(Color(0.0, 1.0, 1.0, 0.5))
		offsets.append(1.0)
		colors.append(Color(0.0, 1.0, 1.0, 0.5))
	_gradient.offsets = offsets
	_gradient.colors = colors


# Cover 0..1 to the effect's coverage parameter (calibrated by eye).
func _coverage_param(cover: float) -> float:
	if cover <= 0.01:
		return 0.0
	return lerpf(0.28, 0.9, pow(clampf(cover, 0.0, 1.0), 0.8))


func _on_lightning(at: Vector3, to_ground: bool, power: float) -> void:
	var h := maxf(at.y, weather.field_elevation_m + weather.cloud_base_m + 1500.0)
	_flashes.append({"pos": Vector3(at.x, h, at.z), "range": 5000.0 if to_ground else 3500.0,
		"power": power, "t": 0.0, "len": randf_range(0.25, 0.6), "seed": randf() * 10.0})


static func _wrap(v: Vector3, half: float) -> Vector3:
	return Vector3(wrapf(v.x, -half, half), wrapf(v.y, -half, half), wrapf(v.z, -half, half))
