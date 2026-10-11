extends Node
## Normalised flight controls from keyboard, joysticks (HOTAS, pedals) and
## gamepads. Joystick bindings are made in the axis tester (F2) and stored
## per device GUID in user://input_bindings.cfg.

signal bindings_changed

const SAVE_PATH := "user://input_bindings.cfg"
const PROFILES_PATH := "res://systems/input_profiles.cfg"
## Controllers in a mode macOS can't read fully: "vendor:product" -> how to fix.
const WRONG_MODE := {
	"1103:46715": "HOTAS is in PlayStation mode (blue LED). Hold MODE 3 s, press MODE until the LED is green.",
}
const AXES := ["pitch", "roll", "rudder", "throttle", "mixture", "brake_left", "brake_right"]
const BIPOLAR := ["pitch", "roll", "rudder"]
const BUTTONS := ["brakes", "trim_up", "trim_down", "flaps_up", "flaps_down", "camera_next", "starter"]
## Bound joystick buttons that fire a one-shot action (like a key press).
const PULSE_BUTTONS := ["flaps_up", "flaps_down", "camera_next"]
const LABELS := {
	"pitch": "Pitch (stick back = +)", "roll": "Roll (right = +)", "rudder": "Rudder (right pedal = +)",
	"throttle": "Throttle", "brake_left": "Left toe brake", "brake_right": "Right toe brake",
	"brakes": "Both brakes", "trim_up": "Trim nose up", "trim_down": "Trim nose down",
	"flaps_up": "Flaps up (one notch)", "flaps_down": "Flaps down (one notch)",
	"camera_next": "Next camera", "mixture": "Mixture", "starter": "Starter / swing prop",
}

const KEYS := {
	"pitch_back": [KEY_S, KEY_DOWN], "pitch_fwd": [KEY_W, KEY_UP],
	"roll_left": [KEY_A, KEY_LEFT], "roll_right": [KEY_D, KEY_RIGHT],
	"rudder_left": [KEY_Q], "rudder_right": [KEY_E],
	"throttle_up": [KEY_R], "throttle_down": [KEY_F],
	"brakes": [KEY_SPACE], "trim_up": [KEY_BRACKETRIGHT], "trim_down": [KEY_BRACKETLEFT],
	"camera_next": [KEY_C], "reset_aircraft": [KEY_BACKSPACE],
	"magnetos_up": [KEY_M], "magnetos_down": [KEY_M | KEY_MASK_SHIFT], "starter": [KEY_ENTER],
	"primer": [KEY_P], "mixture_rich": [KEY_X], "mixture_lean": [KEY_Z], "carb_heat": [KEY_V],
	"fuel_selector": [KEY_B], "master": [KEY_O], "auto_start": [KEY_E | KEY_MASK_CTRL],
	"flaps_up": [KEY_T], "flaps_down": [KEY_G], "next_aircraft": [KEY_N],
	"debug_overlay": [KEY_F3, KEY_I], "axis_tester": [KEY_F2, KEY_J], "help": [KEY_F1, KEY_H],
}

const KEY_RATE := 3.0  # how fast keyboard stick/pedal inputs move, per second
const THROTTLE_KEY_RATE := 0.5
const MIXTURE_KEY_RATE := 0.4

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

## False ignores all joysticks (headless tests with hardware plugged in).
var joysticks_enabled := true

var _seen_axes := {}  # Vector2i(device, axis) that have reported real movement
var _user_axes := {}  # bindings the player made (saved); the rest come from profiles
var _user_buttons := {}
var _profiles := ConfigFile.new()
var _kb := {"pitch": 0.0, "roll": 0.0, "rudder": 0.0}
var _kb_throttle := 0.0


func _ready() -> void:
	process_physics_priority = -100  # read inputs before the aircraft steps
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key & KEY_CODE_MASK
			ev.shift_pressed = key & KEY_MASK_SHIFT != 0
			ev.ctrl_pressed = key & KEY_MASK_CTRL != 0
			InputMap.action_add_event(action, ev)
	_profiles.load(PROFILES_PATH)
	load_bindings()
	Input.joy_connection_changed.connect(func(_d, _c): _apply_profiles())


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
	# macOS reports axes as centred until they first move; trust them after that.
	if event is InputEventJoypadMotion:
		_seen_axes[Vector2i(event.device, event.axis)] = true
	if event is InputEventJoypadButton and event.pressed:
		for action in PULSE_BUTTONS:
			var b = button_bindings.get(action)
			if b and event.button_index == b.button and Input.get_joy_guid(event.device) == b.guid:
				var ev := InputEventAction.new()
				ev.action = action
				ev.pressed = true
				Input.parse_input_event(ev)


## Mixture lever from a bound axis, or null when not bound (keys/clicks set it).
func mixture_axis():
	return _axis("mixture") if _bound("mixture") else null


## Keyboard mixture change per second (-1 lean .. +1 rich).
func mixture_key_rate() -> float:
	return (Input.get_action_strength("mixture_rich") - Input.get_action_strength("mixture_lean")) * MIXTURE_KEY_RATE


func starter_held() -> bool:
	return Input.is_action_pressed("starter") or _button("starter")


func set_throttle_keyboard(value: float) -> void:
	_kb_throttle = clampf(value, 0.0, 1.0)


# --- bindings --------------------------------------------------------------

func bind_axis(control: String, device: int, axis: int) -> void:
	_user_axes[control] = {
		"guid": Input.get_joy_guid(device), "device_name": Input.get_joy_name(device),
		"axis": axis, "invert": false, "deadzone": 0.04 if control in BIPOLAR else 0.02,
	}
	save_bindings()


func bind_button(action: String, device: int, button: int) -> void:
	_user_buttons[action] = {
		"guid": Input.get_joy_guid(device), "device_name": Input.get_joy_name(device), "button": button,
	}
	save_bindings()


func set_invert(control: String, invert: bool) -> void:
	if control in axis_bindings:
		var b: Dictionary = axis_bindings[control].duplicate()
		b.erase("profile")
		b.invert = invert
		_user_axes[control] = b
		save_bindings()


func clear_binding(name: String) -> void:
	_user_axes.erase(name)
	_user_buttons.erase(name)
	save_bindings()


func save_bindings() -> void:
	var cfg := ConfigFile.new()
	for c in _user_axes:
		cfg.set_value("axes", c, _user_axes[c])
	for a in _user_buttons:
		cfg.set_value("buttons", a, _user_buttons[a])
	cfg.save(SAVE_PATH)
	_apply_profiles()


func load_bindings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		for c in cfg.get_section_keys("axes") if cfg.has_section("axes") else []:
			_user_axes[c] = cfg.get_value("axes", c)
		for a in cfg.get_section_keys("buttons") if cfg.has_section("buttons") else []:
			_user_buttons[a] = cfg.get_value("buttons", a)
	_apply_profiles()


## "vendor:product" USB id of a connected device, e.g. "1103:10244".
func usb_id(device: int) -> String:
	var info := Input.get_joy_info(device)
	return "%s:%s" % [info.get("vendor_id", ""), info.get("product_id", "")]


## Fix-it hint when a controller is in a mode we can't use, else "".
func mode_warning(device: int) -> String:
	return WRONG_MODE.get(usb_id(device), "")


# Effective bindings = player's own, plus profile defaults for connected
# controllers covering anything the player hasn't bound.
func _apply_profiles() -> void:
	axis_bindings = _user_axes.duplicate(true)
	button_bindings = _user_buttons.duplicate(true)
	for d in Input.get_connected_joypads():
		var id := usb_id(d)
		var warning := mode_warning(d)
		if warning:
			push_warning(warning)
		if not _profiles.has_section(id):
			continue
		for key in _profiles.get_section_keys(id):
			if key == "name":
				continue
			var p: Dictionary = _profiles.get_value(id, key)
			var b := {"guid": Input.get_joy_guid(d), "device_name": Input.get_joy_name(d), "profile": true}
			if "axis" in p and key not in axis_bindings and key in AXES:
				b.merge({"axis": p.axis, "invert": p.get("invert", false),
					"deadzone": 0.04 if key in BIPOLAR else 0.02})
				axis_bindings[key] = b
			elif "button" in p and key not in button_bindings and key in BUTTONS:
				b.button = p.button
				button_bindings[key] = b
	bindings_changed.emit()


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
	if not joysticks_enabled or control not in axis_bindings:
		return false
	var d := device_for_guid(axis_bindings[control].guid)
	return d >= 0 and _seen_axes.has(Vector2i(d, axis_bindings[control].axis))


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
	if b == null or not joysticks_enabled:
		return false
	var d := device_for_guid(b.guid)
	return d >= 0 and Input.is_joy_button_pressed(d, b.button)


# Gamepads (PS4/PS5 etc.) work without binding: left stick flies, triggers
# are rudder, right stick moves the throttle, cross/A brakes.
func _pad_axis(axis: JoyAxis) -> float:
	var total := 0.0
	if not joysticks_enabled:
		return total
	for d in Input.get_connected_joypads():
		if Input.is_joy_known(d) and not _device_has_bindings(d):
			var v := Input.get_joy_axis(d, axis)
			total += 0.0 if absf(v) < 0.08 else v
	return total


func _pad_button(button: JoyButton) -> bool:
	if not joysticks_enabled:
		return false
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
	# Ctrl+E is auto-start, not right rudder.
	var ctrl := Input.is_key_pressed(KEY_CTRL)
	_kb.rudder = _approach(_kb.rudder, 0.0 if ctrl else
		Input.get_action_strength("rudder_right") - Input.get_action_strength("rudder_left"), delta)
	var t := Input.get_action_strength("throttle_up") - Input.get_action_strength("throttle_down")
	_kb_throttle = clampf(_kb_throttle + t * THROTTLE_KEY_RATE * delta, 0.0, 1.0)


func _approach(current: float, target: float, delta: float) -> float:
	return move_toward(current, target, KEY_RATE * delta)
