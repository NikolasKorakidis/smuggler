extends Node
## Normalised flight controls from keyboard, joysticks (HOTAS, pedals) and
## gamepads. Joystick bindings are made in the axis tester (F2) and stored
## per device GUID in user://input_bindings.cfg.

signal bindings_changed

const SAVE_PATH := "user://input_bindings.cfg"
const AXES := ["pitch", "roll", "rudder", "throttle", "brake_left", "brake_right"]
const BIPOLAR := ["pitch", "roll", "rudder"]
const BUTTONS := ["brakes", "trim_up", "trim_down", "camera_next"]
const LABELS := {
	"pitch": "Pitch (stick back = +)", "roll": "Roll (right = +)", "rudder": "Rudder (right pedal = +)",
	"throttle": "Throttle", "brake_left": "Left toe brake", "brake_right": "Right toe brake",
	"brakes": "Both brakes", "trim_up": "Trim nose up", "trim_down": "Trim nose down",
	"camera_next": "Next camera",
}

const KEYS := {
	"pitch_back": [KEY_S, KEY_DOWN], "pitch_fwd": [KEY_W, KEY_UP],
	"roll_left": [KEY_A, KEY_LEFT], "roll_right": [KEY_D, KEY_RIGHT],
	"rudder_left": [KEY_Q], "rudder_right": [KEY_E],
	"throttle_up": [KEY_R], "throttle_down": [KEY_F],
	"brakes": [KEY_SPACE], "trim_up": [KEY_BRACKETRIGHT], "trim_down": [KEY_BRACKETLEFT],
	"camera_next": [KEY_C], "reset_aircraft": [KEY_BACKSPACE], "engine_toggle": [KEY_M],
	"debug_overlay": [KEY_F3], "axis_tester": [KEY_F2], "help": [KEY_F1],
}

const KEY_RATE := 3.0  # how fast keyboard stick/pedal inputs move, per second
const THROTTLE_KEY_RATE := 0.5

## Outputs, read by the aircraft every physics tick.
var pitch := 0.0  # +1 full aft stick
var roll := 0.0  # +1 full right
var rudder := 0.0  # +1 full right pedal
var throttle := 0.0  # 0..1
var brake_left := 0.0  # 0..1
var brake_right := 0.0
var trim := 0.0  # -1..1 rate command, +1 nose up

## control -> {guid, device_name, axis, invert, deadzone}
var axis_bindings := {}
## action -> {guid, device_name, button}
var button_bindings := {}

var _kb := {"pitch": 0.0, "roll": 0.0, "rudder": 0.0}
var _kb_throttle := 0.0


func _ready() -> void:
	process_physics_priority = -100  # read inputs before the aircraft steps
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	load_bindings()


func _physics_process(delta: float) -> void:
	_update_keyboard(delta)

	pitch = clampf(_axis("pitch") + _kb.pitch + _pad_axis(JOY_AXIS_LEFT_Y), -1.0, 1.0)
	roll = clampf(_axis("roll") + _kb.roll + _pad_axis(JOY_AXIS_LEFT_X), -1.0, 1.0)
	rudder = clampf(_axis("rudder") + _kb.rudder
		+ _pad_axis(JOY_AXIS_TRIGGER_RIGHT) - _pad_axis(JOY_AXIS_TRIGGER_LEFT), -1.0, 1.0)

	if _bound("throttle"):
		throttle = _axis("throttle")
	else:
		_kb_throttle = clampf(_kb_throttle - _pad_axis(JOY_AXIS_RIGHT_Y) * THROTTLE_KEY_RATE * delta, 0.0, 1.0)
		throttle = _kb_throttle

	var both := 1.0 if (Input.is_action_pressed("brakes") or _button("brakes")
		or _pad_button(JOY_BUTTON_A)) else 0.0
	brake_left = maxf(both, _axis("brake_left"))
	brake_right = maxf(both, _axis("brake_right"))

	trim = 0.0
	if Input.is_action_pressed("trim_up") or _button("trim_up") or _pad_button(JOY_BUTTON_DPAD_DOWN):
		trim += 1.0
	if Input.is_action_pressed("trim_down") or _button("trim_down") or _pad_button(JOY_BUTTON_DPAD_UP):
		trim -= 1.0


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		var b = button_bindings.get("camera_next")
		if b and event.button_index == b.button and Input.get_joy_guid(event.device) == b.guid:
			var ev := InputEventAction.new()
			ev.action = "camera_next"
			ev.pressed = true
			Input.parse_input_event(ev)


func set_throttle_keyboard(value: float) -> void:
	_kb_throttle = clampf(value, 0.0, 1.0)


# --- bindings --------------------------------------------------------------

func bind_axis(control: String, device: int, axis: int) -> void:
	axis_bindings[control] = {
		"guid": Input.get_joy_guid(device), "device_name": Input.get_joy_name(device),
		"axis": axis, "invert": false, "deadzone": 0.04 if control in BIPOLAR else 0.02,
	}
	save_bindings()


func bind_button(action: String, device: int, button: int) -> void:
	button_bindings[action] = {
		"guid": Input.get_joy_guid(device), "device_name": Input.get_joy_name(device), "button": button,
	}
	save_bindings()


func set_invert(control: String, invert: bool) -> void:
	if control in axis_bindings:
		axis_bindings[control].invert = invert
		save_bindings()


func clear_binding(name: String) -> void:
	axis_bindings.erase(name)
	button_bindings.erase(name)
	save_bindings()


func save_bindings() -> void:
	var cfg := ConfigFile.new()
	for c in axis_bindings:
		cfg.set_value("axes", c, axis_bindings[c])
	for a in button_bindings:
		cfg.set_value("buttons", a, button_bindings[a])
	cfg.save(SAVE_PATH)
	bindings_changed.emit()


func load_bindings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for c in cfg.get_section_keys("axes") if cfg.has_section("axes") else []:
		axis_bindings[c] = cfg.get_value("axes", c)
	for a in cfg.get_section_keys("buttons") if cfg.has_section("buttons") else []:
		button_bindings[a] = cfg.get_value("buttons", a)


## Processed value of a bound axis, or 0 when unbound / device missing.
func axis_value(control: String) -> float:
	return _axis(control)


func device_for_guid(guid: String) -> int:
	for d in Input.get_connected_joypads():
		if Input.get_joy_guid(d) == guid:
			return d
	return -1


# --- internals --------------------------------------------------------------

func _bound(control: String) -> bool:
	return control in axis_bindings and device_for_guid(axis_bindings[control].guid) >= 0


func _axis(control: String) -> float:
	if not _bound(control):
		return 0.0
	var b: Dictionary = axis_bindings[control]
	var v := Input.get_joy_axis(device_for_guid(b.guid), b.axis)
	if control in BIPOLAR:
		if b.invert:
			v = -v
		var dz: float = b.deadzone
		return 0.0 if absf(v) < dz else signf(v) * (absf(v) - dz) / (1.0 - dz)
	var u := (v + 1.0) * 0.5
	if b.invert:
		u = 1.0 - u
	return clampf((u - b.deadzone) / (1.0 - b.deadzone), 0.0, 1.0)


func _button(action: String) -> bool:
	var b = button_bindings.get(action)
	if b == null:
		return false
	var d := device_for_guid(b.guid)
	return d >= 0 and Input.is_joy_button_pressed(d, b.button)


# Gamepads (PS4/PS5 etc.) work without binding: left stick flies, triggers
# are rudder, right stick moves the throttle, cross/A brakes.
func _pad_axis(axis: JoyAxis) -> float:
	var total := 0.0
	for d in Input.get_connected_joypads():
		if Input.is_joy_known(d) and not _device_has_bindings(d):
			var v := Input.get_joy_axis(d, axis)
			total += 0.0 if absf(v) < 0.08 else v
	return total


func _pad_button(button: JoyButton) -> bool:
	for d in Input.get_connected_joypads():
		if Input.is_joy_known(d) and not _device_has_bindings(d) and Input.is_joy_button_pressed(d, button):
			return true
	return false


func _device_has_bindings(device: int) -> bool:
	var guid := Input.get_joy_guid(device)
	for b in axis_bindings.values():
		if b.guid == guid:
			return true
	for b in button_bindings.values():
		if b.guid == guid:
			return true
	return false


func _update_keyboard(delta: float) -> void:
	_kb.pitch = _approach(_kb.pitch,
		Input.get_action_strength("pitch_back") - Input.get_action_strength("pitch_fwd"), delta)
	_kb.roll = _approach(_kb.roll,
		Input.get_action_strength("roll_right") - Input.get_action_strength("roll_left"), delta)
	_kb.rudder = _approach(_kb.rudder,
		Input.get_action_strength("rudder_right") - Input.get_action_strength("rudder_left"), delta)
	var t := Input.get_action_strength("throttle_up") - Input.get_action_strength("throttle_down")
	_kb_throttle = clampf(_kb_throttle + t * THROTTLE_KEY_RATE * delta, 0.0, 1.0)


func _approach(current: float, target: float, delta: float) -> float:
	return move_toward(current, target, KEY_RATE * delta)
