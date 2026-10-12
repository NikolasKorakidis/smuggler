@tool
class_name AtmosphereEffect
extends CompositorEffect
## The sky's weather on the rendered frame, right after the sky (so
## refracting glass sees it, and rain streaks and glass draw on top):
##   1. clouds.glsl  volumetric clouds at half resolution, temporally
##                   accumulated (ping-pong history)
##   2. fog.glsl     full resolution: haze, fog deck, rain and storm rain
##                   shafts, with the clouds composited at their distance
## Noise textures for the clouds are generated once (cloud_noise.glsl).
## WeatherFX / Clouds fill the parameters every frame from the main thread.

const MAX_CELLS := 8
## Floats in the fog parameter buffer (matches fog.glsl).
const FOG_FLOATS := 16 + 16 + 4 * 12 + MAX_CELLS * 4 * 2
## Floats in the cloud parameter buffer after the three matrices (matches clouds.glsl).
const CLOUD_FLOATS := 4 * 12 + 8 * 4 * 2 + 4 * 4
const SHAPE_SIZE := 128
const DETAIL_SIZE := 32

## Clouds on/off (fog keeps running).
var clouds_enabled := true
## Fog, haze and rain shafts on/off (clouds still drawn).
var fog_enabled := true
## The 2D weather map (coverage noise), set by Clouds.
var weather_texture: Texture2D

var _rd: RenderingDevice
var _sh_noise: RID
var _sh_clouds: RID
var _sh_fog: RID
var _pl_noise: RID
var _pl_clouds: RID
var _pl_fog: RID
var _s_nearest: RID
var _s_linear_clamp: RID
var _s_linear_repeat: RID
var _fog_buf: RID
var _cloud_buf: RID
var _shape: RID
var _detail: RID
var _hist_color: Array[RID] = [RID(), RID()]
var _hist_depth: Array[RID] = [RID(), RID()]
var _hist_size := Vector2i.ZERO
var _ping := 0
var _frame := 0
var _prev_vp := Projection.IDENTITY
var _have_prev := false
var _mutex := Mutex.new()
var _fog_params := PackedFloat32Array()
var _cloud_params := PackedFloat32Array()
var _blank: RID  # 1x1 for when clouds are off


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_SKY
	_fog_params.resize(FOG_FLOATS - 32)
	_cloud_params.resize(CLOUD_FLOATS)
	RenderingServer.call_on_render_thread(_init_compute)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd:
		for rid in [_pl_noise, _pl_clouds, _pl_fog, _sh_noise, _sh_clouds, _sh_fog, _s_nearest, _s_linear_clamp,
				_s_linear_repeat, _fog_buf, _cloud_buf, _shape, _detail, _blank] + _hist_color + _hist_depth:
			if rid.is_valid():
				_rd.free_rid(rid)


func set_fog_params(values: PackedFloat32Array) -> void:
	_mutex.lock()
	_fog_params = values
	_mutex.unlock()


func set_cloud_params(values: PackedFloat32Array) -> void:
	_mutex.lock()
	_cloud_params = values
	_mutex.unlock()


func _shader(path: String) -> RID:
	var file: RDShaderFile = load(path)
	var spirv := file.get_spirv()
	if spirv.compile_error_compute != "":
		push_error("%s: %s" % [path, spirv.compile_error_compute])
		return RID()
	return _rd.shader_create_from_spirv(spirv)


func _sampler(filter: int, repeat: int) -> RID:
	var ss := RDSamplerState.new()
	ss.min_filter = filter
	ss.mag_filter = filter
	ss.repeat_u = repeat
	ss.repeat_v = repeat
	ss.repeat_w = repeat
	return _rd.sampler_create(ss)


func _init_compute() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return
	_sh_noise = _shader("res://world/weather_fx/cloud_noise.glsl")
	_sh_clouds = _shader("res://world/weather_fx/clouds.glsl")
	_sh_fog = _shader("res://world/weather_fx/fog.glsl")
	if not (_sh_noise.is_valid() and _sh_clouds.is_valid() and _sh_fog.is_valid()):
		return
	_pl_noise = _rd.compute_pipeline_create(_sh_noise)
	_pl_clouds = _rd.compute_pipeline_create(_sh_clouds)
	_pl_fog = _rd.compute_pipeline_create(_sh_fog)
	_s_nearest = _sampler(RenderingDevice.SAMPLER_FILTER_NEAREST, RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE)
	_s_linear_clamp = _sampler(RenderingDevice.SAMPLER_FILTER_LINEAR, RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE)
	_s_linear_repeat = _sampler(RenderingDevice.SAMPLER_FILTER_LINEAR, RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT)
	_fog_buf = _rd.storage_buffer_create(FOG_FLOATS * 4)
	_cloud_buf = _rd.storage_buffer_create((48 + CLOUD_FLOATS) * 4)
	_shape = _make_noise(SHAPE_SIZE, 0)
	_detail = _make_noise(DETAIL_SIZE, 1)
	_blank = _texture_2d(Vector2i(1, 1), RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)


func _texture_2d(size: Vector2i, fmt_id: int) -> RID:
	var fmt := RDTextureFormat.new()
	fmt.width = size.x
	fmt.height = size.y
	fmt.format = fmt_id
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	return _rd.texture_create(fmt, RDTextureView.new())


# Generate one tileable 3D noise texture on the GPU.
func _make_noise(size: int, mode: int) -> RID:
	var fmt := RDTextureFormat.new()
	fmt.texture_type = RenderingDevice.TEXTURE_TYPE_3D
	fmt.width = size
	fmt.height = size
	fmt.depth = size
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	var tex := _rd.texture_create(fmt, RDTextureView.new())
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = 0
	u.add_id(tex)
	var uset := _rd.uniform_set_create([u], _sh_noise, 0)
	var push := PackedInt32Array([size, mode, 0, 0]).to_byte_array()
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pl_noise)
	_rd.compute_list_bind_uniform_set(list, uset, 0)
	_rd.compute_list_set_push_constant(list, push, push.size())
	_rd.compute_list_dispatch(list, ceili(size / 4.0), ceili(size / 4.0), ceili(size / 4.0))
	_rd.compute_list_end()
	_rd.free_rid(uset)
	return tex


func _ensure_history(size: Vector2i) -> void:
	if size == _hist_size and _hist_color[0].is_valid():
		return
	for i in 2:
		for rid in [_hist_color[i], _hist_depth[i]]:
			if rid.is_valid():
				_rd.free_rid(rid)
		_hist_color[i] = _texture_2d(size, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
		_hist_depth[i] = _texture_2d(size, RenderingDevice.DATA_FORMAT_R32G32_SFLOAT)
		_rd.texture_clear(_hist_color[i], Color(0, 0, 0, 1), 0, 1, 0, 1)
		_rd.texture_clear(_hist_depth[i], Color(1e9, 1e9, 0, 0), 0, 1, 0, 1)
	_hist_size = size
	_have_prev = false


static func _put_mat(out: PackedFloat32Array, m: Projection) -> void:
	for c in 4:
		for r in 4:
			out.append(m[c][r])


static func _put_xform(out: PackedFloat32Array, t: Transform3D) -> void:
	for col in [t.basis.x, t.basis.y, t.basis.z]:
		out.append_array([col.x, col.y, col.z, 0.0])
	out.append_array([t.origin.x, t.origin.y, t.origin.z, 1.0])


func _uniform(type: int, binding: int, ids: Array) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = type
	u.binding = binding
	for id in ids:
		u.add_id(id)
	return u


func _render_callback(type: int, render_data: RenderData) -> void:
	if type != effect_callback_type or not _pl_fog.is_valid():
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene := render_data.get_render_scene_data()
	if buffers == null or scene == null:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	_mutex.lock()
	var fog_params := _fog_params
	var cloud_params := _cloud_params
	_mutex.unlock()
	var cam := scene.get_cam_transform()
	var proj := scene.get_view_projection(0)
	var vp := proj * Projection(cam.affine_inverse())
	var half := Vector2i(maxi(size.x / 2, 1), maxi(size.y / 2, 1))
	_ensure_history(half)
	var depth := buffers.get_depth_layer(0)
	var clouds_on := clouds_enabled and weather_texture != null
	var cur := _ping
	var prev := 1 - _ping

	# 1. Clouds at half resolution.
	if clouds_on:
		var data := PackedFloat32Array()
		_put_mat(data, proj.inverse())
		_put_xform(data, cam)
		_put_mat(data, _prev_vp if _have_prev else vp)
		data.append_array(cloud_params)
		data[48 + 4 * 10 + 2] = float(_frame)  # counts.z: frame index
		if not _have_prev:
			data[48 + 4 * 11 + 2] = 1.0  # misc.z: no history yet
		var bytes := data.to_byte_array()
		_rd.buffer_update(_cloud_buf, 0, bytes.size(), bytes)
		var wtex := RenderingServer.texture_get_rd_texture(weather_texture.get_rid())
		var uset := UniformSetCacheRD.get_cache(_sh_clouds, 0, [
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 0, [_hist_color[cur]]),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 1, [_hist_depth[cur]]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_s_linear_clamp, _hist_color[prev]]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [_s_nearest, _hist_depth[prev]]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 4, [_s_nearest, depth]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 5, [_s_linear_repeat, _shape]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 6, [_s_linear_repeat, _detail]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 7, [_s_linear_repeat, wtex]),
			_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 8, [_cloud_buf]),
		])
		var push := PackedFloat32Array([half.x, half.y, size.x, size.y]).to_byte_array()
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _pl_clouds)
		_rd.compute_list_bind_uniform_set(list, uset, 0)
		_rd.compute_list_set_push_constant(list, push, push.size())
		_rd.compute_list_dispatch(list, ceili(half.x / 8.0), ceili(half.y / 8.0), 1)
		_rd.compute_list_end()
		_prev_vp = vp
		_have_prev = true
		_frame += 1
	else:
		_have_prev = false

	# 2. Fog and composite at full resolution.
	var fdata := PackedFloat32Array()
	_put_mat(fdata, proj.inverse())
	_put_xform(fdata, cam)
	fdata.append_array(fog_params)
	if not fog_enabled:  # keep the clouds, drop haze/fog/rain
		for i in 12:
			fdata[32 + i] = 0.0 if i % 4 == 0 else fdata[32 + i]
		fdata[32 + 4 * 11] = 0.0  # no storm curtains
	var fbytes := fdata.to_byte_array()
	_rd.buffer_update(_fog_buf, 0, fbytes.size(), fbytes)
	var fset := UniformSetCacheRD.get_cache(_sh_fog, 0, [
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 0, [buffers.get_color_layer(0)]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_s_nearest, depth]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2, [_fog_buf]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [_s_nearest, _hist_color[cur] if clouds_on else _blank]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 4, [_s_nearest, _hist_depth[cur] if clouds_on else _blank]),
	])
	var fpush := PackedFloat32Array([size.x, size.y, 1.0 if clouds_on else 0.0, 0.0]).to_byte_array()
	var flist := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(flist, _pl_fog)
	_rd.compute_list_bind_uniform_set(flist, fset, 0)
	_rd.compute_list_set_push_constant(flist, fpush, fpush.size())
	_rd.compute_list_dispatch(flist, ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
	_rd.compute_list_end()
	if clouds_on:
		_ping = 1 - _ping
