extends Camera3D
## Chase and cockpit cameras. C (or a bound HOTAS button) switches.
## Hold right mouse to look around, wheel to zoom, middle click to recentre.

enum Mode { CHASE, COCKPIT }

const CHASE_HEIGHT := 1.2

var target: Aircraft
var mode := Mode.CHASE
var chase_distance := 12.0
var orbit_yaw := 0.0
var orbit_pitch := deg_to_rad(10.0)
var look_yaw := 0.0
var look_pitch := 0.0
var cockpit_fov := 70.0
var _heading := 0.0
var _looking := false
var _hovered: CockpitControl
var _pressed: CockpitControl
var _tooltip: Label


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	_tooltip = Label.new()
	_tooltip.add_theme_font_size_override("font_size", 16)
	_tooltip.add_theme_color_override("font_outline_color", Color.BLACK)
	_tooltip.add_theme_constant_override("outline_size", 5)
	_tooltip.visible = false
	layer.add_child(_tooltip)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_next"):
		mode = Mode.COCKPIT if mode == Mode.CHASE else Mode.CHASE
		fov = cockpit_fov if mode == Mode.COCKPIT else 70.0
		if mode == Mode.COCKPIT:
			recentre()
	elif event is InputEventMouseButton and mode == Mode.COCKPIT and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _hovered:
			_hovered.press(event.shift_pressed)
			_pressed = _hovered
			get_viewport().set_input_as_handled()
		elif not event.pressed and _pressed:
			_pressed.release()
			_pressed = null
	elif event is InputEventMouseButton and event.pressed and mode == Mode.COCKPIT and _hovered \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_hovered.scroll(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_looking = event.pressed
			MOUSE_BUTTON_MIDDLE:
				if event.pressed:
					recentre()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				var dir := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
				if mode == Mode.CHASE:
					chase_distance = clampf(chase_distance * (1.0 + 0.1 * dir), 4.0, 80.0)
				else:
					cockpit_fov = clampf(cockpit_fov + 4.0 * dir, 30.0, 95.0)
					fov = cockpit_fov
	elif event is InputEventMouseMotion and _looking:
		var d: Vector2 = event.relative * 0.005
		if mode == Mode.CHASE:
			orbit_yaw -= d.x
			orbit_pitch = clampf(orbit_pitch + d.y, deg_to_rad(-30.0), deg_to_rad(80.0))
		else:
			look_yaw = clampf(look_yaw - d.x, deg_to_rad(-160.0), deg_to_rad(160.0))
			look_pitch = clampf(look_pitch - d.y, deg_to_rad(-60.0), deg_to_rad(80.0))


func recentre() -> void:
	orbit_yaw = 0.0
	orbit_pitch = deg_to_rad(10.0)
	look_yaw = 0.0
	look_pitch = deg_to_rad(target.definition.cockpit_look_pitch_deg) if target else 0.0


func _process(delta: float) -> void:
	if target == null or target.airframe == null:
		return
	if mode == Mode.CHASE:
		var t := target.get_global_transform_interpolated()
		var fwd := -t.basis.z
		var heading := atan2(-fwd.x, -fwd.z)
		_heading = lerp_angle(_heading, heading, 1.0 - exp(-3.0 * delta))
		var offset := Basis(Vector3.UP, _heading + orbit_yaw) * Basis(Vector3.RIGHT, -orbit_pitch) \
			* Vector3(0, 0, chase_distance)
		var focus := t.origin + Vector3(0, CHASE_HEIGHT, 0)
		global_position = focus + offset
		look_at(focus, Vector3.UP)
	else:
		var eye := target.eyepoint().get_global_transform_interpolated()
		global_transform = eye * Transform3D(
			Basis(Vector3.UP, look_yaw) * Basis(Vector3.RIGHT, look_pitch), Vector3.ZERO)
	_update_hover()


# Mouse ray against cockpit controls, done in aircraft space so the
# interpolated camera and the controls agree exactly.
func _update_hover() -> void:
	var found: CockpitControl = null
	if mode == Mode.COCKPIT and not _looking:
		var mouse := get_viewport().get_mouse_position()
		var to_aircraft := target.get_global_transform_interpolated().affine_inverse()
		var from := to_aircraft * project_ray_origin(mouse)
		var dir := (to_aircraft.basis * project_ray_normal(mouse)).normalized()
		var aircraft_inv := target.global_transform.affine_inverse()
		var best := INF
		for c in target.find_children("*", "CockpitControl", true, false):
			var local: Transform3D = (aircraft_inv * c.global_transform).affine_inverse()
			var d: float = c.hit(local * from, (local.basis * dir).normalized())
			if d >= 0.0 and d < best:
				best = d
				found = c
	if found != _hovered:
		if _hovered and is_instance_valid(_hovered):
			_hovered.set_hover(false)
		_hovered = found
		if _hovered:
			_hovered.set_hover(true)
	_tooltip.visible = _hovered != null
	if _hovered:
		_tooltip.text = _hovered.tooltip()
		_tooltip.position = get_viewport().get_mouse_position() + Vector2(18, 14)
