@tool
class_name FogEffect
extends CompositorEffect
## Runs fog.glsl on the rendered frame (after sky and clouds, before rain
## streaks and glass; right after the sky so refracting glass sees the fog). WeatherFX fills the parameters every frame from the
## Weather and the sky.

const MAX_CELLS := 8
## Floats in the parameter buffer (must match fog.glsl).
const PARAM_FLOATS := 16 + 16 + 4 * 12 + MAX_CELLS * 4 * 2

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _sampler: RID
var _buffer: RID
var _mutex := Mutex.new()
var _params := PackedFloat32Array()  # everything after the two matrices


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_SKY
	_params.resize(PARAM_FLOATS - 32)
	RenderingServer.call_on_render_thread(_init_compute)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd:
		for rid in [_pipeline, _shader, _sampler, _buffer]:
			if rid.is_valid():
				_rd.free_rid(rid)


## Weather parameters from the main thread (see fog.glsl for the layout).
func set_params(values: PackedFloat32Array) -> void:
	_mutex.lock()
	_params = values
	_mutex.unlock()


func _init_compute() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return
	var file: RDShaderFile = load("res://world/weather_fx/fog.glsl")
	_shader = _rd.shader_create_from_spirv(file.get_spirv())
	if not _shader.is_valid():
		push_error("fog.glsl failed to compile")
		return
	_pipeline = _rd.compute_pipeline_create(_shader)
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	_sampler = _rd.sampler_create(ss)
	_buffer = _rd.storage_buffer_create(PARAM_FLOATS * 4)


func _render_callback(type: int, render_data: RenderData) -> void:
	if type != effect_callback_type or not _pipeline.is_valid():
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene := render_data.get_render_scene_data()
	if buffers == null or scene == null:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	_mutex.lock()
	var params := _params
	_mutex.unlock()
	var cam := scene.get_cam_transform()
	for view in buffers.get_view_count():
		var data := PackedFloat32Array()
		data.resize(32)
		# Already the GPU projection (0..1 reversed depth), as SunshineClouds uses it.
		var inv := scene.get_view_projection(view).inverse()
		for c in 4:
			for r in 4:
				data[c * 4 + r] = inv[c][r]
		var cols := [cam.basis.x, cam.basis.y, cam.basis.z]
		for c in 3:
			data[16 + c * 4] = cols[c].x
			data[16 + c * 4 + 1] = cols[c].y
			data[16 + c * 4 + 2] = cols[c].z
			data[16 + c * 4 + 3] = 0.0
		data[28] = cam.origin.x
		data[29] = cam.origin.y
		data[30] = cam.origin.z
		data[31] = 1.0
		data.append_array(params)
		var bytes := data.to_byte_array()
		_rd.buffer_update(_buffer, 0, bytes.size(), bytes)

		var u_color := RDUniform.new()
		u_color.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_color.binding = 0
		u_color.add_id(buffers.get_color_layer(view))
		var u_depth := RDUniform.new()
		u_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		u_depth.binding = 1
		u_depth.add_id(_sampler)
		u_depth.add_id(buffers.get_depth_layer(view))
		var u_params := RDUniform.new()
		u_params.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u_params.binding = 2
		u_params.add_id(_buffer)
		var uset := UniformSetCacheRD.get_cache(_shader, 0, [u_color, u_depth, u_params])

		var push := PackedFloat32Array([size.x, size.y, 0.0, 0.0]).to_byte_array()
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _pipeline)
		_rd.compute_list_bind_uniform_set(list, uset, 0)
		_rd.compute_list_set_push_constant(list, push, push.size())
		_rd.compute_list_dispatch(list, ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
		_rd.compute_list_end()
