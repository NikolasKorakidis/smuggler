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
var _objective: Label  # name + distance at the objective while "look" is held
var _look_blend := 0.0  # 0 = pilot's own view, 1 = looking at the objective


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
	_objective = Label.new()
	_objective.add_theme_font_size_override("font_size", 22)
	_objective.add_theme_color_override("font_color", Color(1.0, 0.8, 0.35))
	_objective.add_theme_color_override("font_outline_color", Color.BLACK)
	_objective.add_theme_constant_override("outline_size", 6)
	_objective.visible = false
	layer.add_child(_objective)


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
	var objective := _objective_point()
	var looking := FlightInput.look_target_held() and objective != Vector3.INF
	_look_blend = move_toward(_look_blend, 1.0 if looking else 0.0, delta * 4.0)
	if mode == Mode.CHASE:
		var t := target.get_global_transform_interpolated()
		var fwd := -t.basis.z
		var heading := atan2(-fwd.x, -fwd.z)
		_heading = lerp_angle(_heading, heading, 1.0 - exp(-3.0 * delta))
		var yaw := _heading + orbit_yaw
		if _look_blend > 0.0 and objective != Vector3.INF:
			# Swing round behind the aircraft so it sits between camera and objective.
			var to_obj := objective - t.origin
			yaw = lerp_angle(yaw, atan2(-to_obj.x, -to_obj.z), _smooth(_look_blend))
		var offset := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -orbit_pitch) \
			* Vector3(0, 0, chase_distance)
		var focus := t.origin + Vector3(0, CHASE_HEIGHT, 0)
		global_position = focus + offset
		# Stay above the ground on hilly terrain.
		var floor_y: float = target.world.terrain_height(global_position) + 0.5
		if global_position.y < floor_y:
			global_position.y = floor_y
		look_at(focus, Vector3.UP)
	else:
		var eye := target.eyepoint().get_global_transform_interpolated()
		var yaw := look_yaw
		var pitch := look_pitch
		if _look_blend > 0.0 and objective != Vector3.INF:
			# Turn the pilot's head towards the objective (as far as a neck turns).
			var local := eye.affine_inverse() * objective
			var want_yaw := clampf(atan2(-local.x, -local.z), deg_to_rad(-160.0), deg_to_rad(160.0))
			var want_pitch := clampf(atan2(local.y, Vector2(local.x, local.z).length()), deg_to_rad(-60.0), deg_to_rad(60.0))
			yaw = lerp_angle(yaw, want_yaw, _smooth(_look_blend))
			pitch = lerpf(pitch, want_pitch, _smooth(_look_blend))
		global_transform = eye * Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), Vector3.ZERO)
	_update_objective_label(objective)
	_update_hover()


func _smooth(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


# The checklist's current objective as a world point (a little above the
# ground so the label sits on the tower / strip / hangar), or INF if none.
func _objective_point() -> Vector3:
	var checklist = target.world.get_node_or_null("Checklist")
	if checklist == null or not checklist.has_method("current_target"):
		return Vector3.INF
	var name: String = checklist.current_target()
	if name == "":
		return Vector3.INF
	var lift := 60.0 if name == "tower" else 8.0
	return target.world.point(name) + Vector3(0, lift, 0)


func _update_objective_label(objective: Vector3) -> void:
	_objective.visible = _look_blend > 0.5 and objective != Vector3.INF
	if not _objective.visible:
		return
	var checklist = target.world.get_node("Checklist")
	var d := Vector2(objective.x - target.global_position.x, objective.z - target.global_position.z).length()
	var dist := "%.1f km" % (d / 1000.0) if d >= 1000.0 else "%d m" % int(round(d / 10.0) * 10)
	var names := {"tower": "RADIO TOWER", "strip": "STRIP", "parking": "HANGAR / PARKING"}
	var text: String = "%s  ·  %s" % [names.get(checklist.current_target(), "OBJECTIVE"), dist]
	var vp := get_viewport().get_visible_rect().size
	var on_screen := not is_position_behind(objective)
	var p := unproject_position(objective) if on_screen else Vector2(-1, -1)
	if on_screen and Rect2(Vector2.ZERO, vp).has_point(p):
		_objective.text = "▼  " + text
		_objective.position = p - Vector2(30, 40)
	else:
		# Off screen: pin it to the nearest edge with an arrow pointing the way.
		var c := vp * 0.5
		var dir := (p - c).normalized() if on_screen else (c - unproject_position(objective)).normalized()
		_objective.text = ("◀  " if dir.x < 0 else "") + text + ("  ▶" if dir.x >= 0 else "")
		var edge := c + dir * minf(c.x / maxf(absf(dir.x), 0.01), c.y / maxf(absf(dir.y), 0.01)) * 0.85
		_objective.position = edge - Vector2(_objective.size.x * 0.5, 12)


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
