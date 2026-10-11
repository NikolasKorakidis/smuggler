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


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	current = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_next"):
		mode = Mode.COCKPIT if mode == Mode.CHASE else Mode.CHASE
		fov = cockpit_fov if mode == Mode.COCKPIT else 70.0
		if mode == Mode.COCKPIT:
			recentre()
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
