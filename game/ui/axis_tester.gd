extends CanvasLayer
## J / F2: joystick setup. "Flight controls" tab binds each control by moving
## it; "Controller test" tab shows every raw axis and button.

const MAX_AXES := 10
const CAPTURE_DELTA := 0.5

const GROUPS := [
	["STICK", ["pitch", "roll"]],
	["THROTTLE", ["throttle", "mixture"]],
	["PEDALS", ["rudder", "brake_left", "brake_right"]],
	["BUTTONS", ["trim_up", "trim_down", "flaps_down", "flaps_up", "starter", "camera_next", "look_target", "brakes", "parking_brake", "landing_light", "nav_lights", "panel_lights"]],
]
const NAMES := {
	"pitch": "Pitch", "roll": "Roll", "throttle": "Throttle", "rudder": "Rudder",
	"brake_left": "Left toe brake", "brake_right": "Right toe brake", "brakes": "Both brakes",
	"trim_up": "Trim nose up", "trim_down": "Trim nose down", "flaps_up": "Flaps up",
	"flaps_down": "Flaps down", "camera_next": "Next camera", "mixture": "Mixture",
	"starter": "Starter", "parking_brake": "Parking brake", "look_target": "Look at objective",
	"landing_light": "Landing light", "nav_lights": "Nav lights", "panel_lights": "Panel lights",
}
const HINTS := {
	"pitch": "Pull back → bar moves right", "roll": "Stick right → bar moves right",
	"throttle": "Lever forward → bar full", "rudder": "Right pedal → bar moves right",
	"brake_left": "Press → bar full", "brake_right": "Press → bar full",
	"brakes": "Hold to brake", "trim_up": "Press and hold", "trim_down": "Press and hold",
	"flaps_up": "One notch per press", "flaps_down": "One notch per press",
	"camera_next": "Chase / cockpit", "mixture": "Forward → rich (optional)", "starter": "Hold to crank", "parking_brake": "Press to set / release", "look_target": "Hold: view turns to where to go",
	"landing_light": "On / off (needs master)", "nav_lights": "On / off (needs master)", "panel_lights": "On / off (needs master)",
}
const KEYBOARD := {
	"pitch": "W / S", "roll": "A / D", "throttle": "R / F", "rudder": "Q / E",
	"brakes": "Space", "trim_up": "]", "trim_down": "[", "flaps_up": "T", "flaps_down": "G",
	"camera_next": "C", "mixture": "X / Z", "starter": "Enter", "parking_brake": ".", "look_target": "L",
	"landing_light": "Ctrl+L", "nav_lights": "Ctrl+N", "panel_lights": "Ctrl+P",
}

const COL_NAME := 230
const COL_BOUND := 230
const COL_LIVE := 230
const COL_ACTIONS := 150
const COL_INVERT := 90

const C_BG := Color(0.07, 0.08, 0.09, 0.95)
const C_ROW := Color(1, 1, 1, 0.03)
const C_ROW_ALT := Color(1, 1, 1, 0.07)
const C_CAPTURE := Color(0.95, 0.65, 0.2, 0.28)
const C_DIM := Color(1, 1, 1, 0.5)
const C_ACCENT := Color(0.95, 0.7, 0.3)
const C_OK := Color(0.55, 0.85, 0.55)

var _rows := {}  # control -> {style, base, bound, bar, value, invert}
var _status: Label
var _devices_box: VBoxContainer
var _device_bars := {}  # device -> Array[AxisBar]
var _device_values := {}  # device -> Array[Label]
var _device_buttons := {}  # device -> Label
var _capturing := ""
var _capture_rest := {}  # Vector2i(device, axis) -> value at capture start


class AxisBar extends Control:
	## Bipolar bars fill from the centre; unipolar from the left.
	var value := 0.0:
		set(v):
			value = v
			queue_redraw()
	var bipolar := true
	var active := true

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.1))
		var fill := Color(0.55, 0.8, 1.0) if active else Color(1, 1, 1, 0.25)
		if bipolar:
			var mid := size.x * 0.5
			var x := mid + clampf(value, -1.0, 1.0) * mid
			draw_rect(Rect2(minf(mid, x), 0, absf(x - mid), size.y), fill)
			draw_line(Vector2(mid, -2), Vector2(mid, size.y + 2), Color(1, 1, 1, 0.6), 1.0)
		else:
			draw_rect(Rect2(0, 0, size.x * clampf(value, 0.0, 1.0), size.y), fill)


func _ready() -> void:
	layer = 10
	_build()
	visible = false
	Input.joy_connection_changed.connect(func(_d, _c): _rebuild_devices())
	FlightInput.bindings_changed.connect(_refresh_bindings)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("axis_tester"):
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	visible = not visible
	if visible:
		_rebuild_devices()
		_refresh_bindings()
	_cancel_capture("")


func _input(event: InputEvent) -> void:
	if not visible or _capturing == "":
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		_cancel_capture("Cancelled.")
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed and _capturing in FlightInput.BUTTONS:
		var name := _capturing
		FlightInput.bind_button(name, event.device, event.button_index)
		_finish_capture("%s → button %d. Done." % [NAMES[name], event.button_index])
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible:
		return
	for d in _device_bars:
		for a in MAX_AXES:
			var v := Input.get_joy_axis(d, a)
			_device_bars[d][a].value = v
			_device_values[d][a].text = "%+.2f" % v
		var pressed := []
		for b in 128:
			if Input.is_joy_button_pressed(d, b):
				pressed.append(str(b))
		_device_buttons[d].text = "Buttons held: " + (", ".join(pressed) if pressed else "none")
	for name in FlightInput.AXES:
		var v := FlightInput.axis_value(name)
		_rows[name].bar.value = v
		if name in FlightInput.BIPOLAR:
			_rows[name].value.text = "%+.2f" % v
		else:
			_rows[name].value.text = "%3.0f%%" % (v * 100.0)
	for name in FlightInput.BUTTONS:
		_rows[name].bar.value = 1.0 if _button_down(name) else 0.0
	if _capturing in FlightInput.AXES:
		for key in _capture_rest:
			if absf(Input.get_joy_axis(key.x, key.y) - _capture_rest[key]) > CAPTURE_DELTA:
				var name := _capturing
				FlightInput.bind_axis(name, key.x, key.y)
				_finish_capture("%s → axis %d. Check the bar: %s. Tick Invert if it goes the other way." % [
					NAMES[name], key.y, HINTS[name].to_lower()])
				break


func _button_down(name: String) -> bool:
	var b = FlightInput.button_bindings.get(name)
	if b == null:
		return false
	var d := FlightInput.device_for_guid(b.guid)
	return d >= 0 and Input.is_joy_button_pressed(d, b.button)


# --- capture ----------------------------------------------------------------

func _start_capture(name: String) -> void:
	_cancel_capture("")
	_capturing = name
	_capture_rest.clear()
	for d in Input.get_connected_joypads():
		for a in MAX_AXES:
			_capture_rest[Vector2i(d, a)] = Input.get_joy_axis(d, a)
	_rows[name].style.bg_color = C_CAPTURE
	_rows[name].bound.text = "Move it now…" if name in FlightInput.AXES else "Press it now…"
	_rows[name].bound.add_theme_color_override("font_color", C_ACCENT)
	var how := "move the control through its full range" if name in FlightInput.AXES else "press the button"
	_set_status("Binding %s: %s. Esc cancels." % [NAMES[name], how], C_ACCENT)


func _finish_capture(message: String) -> void:
	_end_capture()
	_set_status(message, C_OK)


func _cancel_capture(message: String) -> void:
	_end_capture()
	if message != "":
		_set_status(message, C_DIM)


func _end_capture() -> void:
	if _capturing != "":
		_rows[_capturing].style.bg_color = _rows[_capturing].base
	_capturing = ""
	_refresh_bindings()


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


# --- layout -----------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_BG
	ps.set_corner_radius_all(10)
	ps.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	titles.add_child(_label("Joystick setup", 26))
	titles.add_child(_label(
		"Click Bind, then move the control (or press the button). Bindings save automatically.", 15, C_DIM))
	var close := Button.new()
	close.text = "  Close (J)  "
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(_toggle)
	header.add_child(close)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(COL_NAME + COL_BOUND + COL_LIVE + COL_ACTIONS + COL_INVERT + 60, 735)
	root.add_child(tabs)
	tabs.add_child(_build_controls_tab())
	tabs.add_child(_build_devices_tab())

	_status = _label("", 17)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.custom_minimum_size = Vector2(0, 26)
	root.add_child(_status)
	_set_status("Gamepads work without binding. The T.Flight Hotas 5 has default bindings (shown as 'default').", C_DIM)


func _build_controls_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Flight controls"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var head := HBoxContainer.new()
	head.add_child(_cell(_label("CONTROL", 13, C_DIM), COL_NAME))
	head.add_child(_cell(_label("BOUND TO", 13, C_DIM), COL_BOUND))
	head.add_child(_cell(_label("LIVE", 13, C_DIM), COL_LIVE))
	head.add_child(_cell(Control.new(), COL_ACTIONS))
	head.add_child(_cell(_label("INVERT", 13, C_DIM), COL_INVERT))
	list.add_child(_pad(head, 12, 8))

	for group in GROUPS:
		list.add_child(_pad(_label(group[0], 14, C_ACCENT), 12, 8))
		var alt := false
		for name in group[1]:
			list.add_child(_build_row(name, alt))
			alt = not alt
	return scroll


func _build_row(name: String, alt: bool) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = C_ROW_ALT if alt else C_ROW
	style.set_corner_radius_all(4)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	panel.add_child(row)

	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 0)
	name_box.add_child(_label(NAMES[name], 18))
	if name in FlightInput.AXES:  # buttons need no direction hint; keeps the list on one screen
		name_box.add_child(_label(HINTS[name], 13, C_DIM))
	row.add_child(_cell(name_box, COL_NAME))

	var bound := _label("", 16)
	bound.clip_text = true
	bound.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bound.custom_minimum_size = Vector2(COL_BOUND - 10, 0)
	row.add_child(_cell(bound, COL_BOUND))

	var live := HBoxContainer.new()
	var bar := AxisBar.new()
	bar.bipolar = name in FlightInput.BIPOLAR
	bar.custom_minimum_size = Vector2(150, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	live.add_child(bar)
	var value := _label("", 14, C_DIM)
	value.custom_minimum_size = Vector2(60, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	live.add_child(value)
	row.add_child(_cell(live, COL_LIVE))

	var actions := HBoxContainer.new()
	var bind := Button.new()
	bind.text = "Bind"
	bind.custom_minimum_size = Vector2(64, 0)
	bind.pressed.connect(_start_capture.bind(name))
	actions.add_child(bind)
	var clear := Button.new()
	clear.text = "Clear"
	clear.custom_minimum_size = Vector2(64, 0)
	clear.pressed.connect(func():
		FlightInput.clear_binding(name)
		_set_status("%s cleared." % NAMES[name], C_DIM))
	actions.add_child(clear)
	row.add_child(_cell(actions, COL_ACTIONS))

	# Buttons have nothing to invert; the cell keeps its width so columns line up.
	var invert := CheckBox.new()
	invert.visible = name in FlightInput.AXES
	invert.toggled.connect(func(on): FlightInput.set_invert(name, on))
	row.add_child(_cell(invert, COL_INVERT))

	_rows[name] = {"style": style, "base": style.bg_color, "bound": bound, "bar": bar,
		"value": value, "invert": invert}
	return panel


func _build_devices_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Controller test"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_devices_box = VBoxContainer.new()
	_devices_box.add_theme_constant_override("separation", 6)
	_devices_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_pad(_devices_box, 12, 12))
	return scroll


func _rebuild_devices() -> void:
	for c in _devices_box.get_children():
		c.queue_free()
	_device_bars.clear()
	_device_values.clear()
	_device_buttons.clear()
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		_devices_box.add_child(_label("No controllers connected. Plug in the HOTAS / pedals.", 17, C_DIM))
		return
	_devices_box.add_child(_label(
		"Move each control to see which axis it is. Axes that never move are unused.", 15, C_DIM))
	for d in pads:
		var title := "%s%s" % [Input.get_joy_name(d), "   (gamepad)" if Input.is_joy_known(d) else ""]
		_devices_box.add_child(_pad(_label(title, 20, C_ACCENT), 0, 10))
		var warning := FlightInput.mode_warning(d)
		if warning:
			var w := _label(warning, 16, Color(1.0, 0.55, 0.35))
			w.autowrap_mode = TextServer.AUTOWRAP_WORD
			_devices_box.add_child(w)
		var bars: Array = []
		var values: Array = []
		for a in MAX_AXES:
			var line := HBoxContainer.new()
			line.add_child(_cell(_label("Axis %d" % a, 16), 90))
			var bar := AxisBar.new()
			bar.custom_minimum_size = Vector2(420, 14)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(bar)
			var v := _label("", 14, C_DIM)
			v.custom_minimum_size = Vector2(70, 0)
			v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			line.add_child(v)
			_devices_box.add_child(line)
			bars.append(bar)
			values.append(v)
		var buttons := _label("", 16)
		_devices_box.add_child(_pad(buttons, 0, 6))
		_device_bars[d] = bars
		_device_values[d] = values
		_device_buttons[d] = buttons


func _refresh_bindings() -> void:
	for name in _rows:
		var row: Dictionary = _rows[name]
		var b = FlightInput.axis_bindings.get(name, FlightInput.button_bindings.get(name))
		var bar: AxisBar = row.bar
		if b == null:
			row.bound.text = ("Keyboard  " + KEYBOARD[name]) if name in KEYBOARD else "Not bound"
			row.bound.add_theme_color_override("font_color", C_DIM)
			bar.active = false
		else:
			var what := ("Axis %d" % b.axis) if "axis" in b else ("Button %d" % b.button)
			var device := "default" if b.get("profile") else String(b.device_name).trim_prefix("Thrustmaster ")
			row.bound.text = "%s  ·  %s" % [what, device]
			row.bound.remove_theme_color_override("font_color")
			bar.active = true
		row.bound.tooltip_text = row.bound.text
		row.invert.set_pressed_no_signal(b != null and b.get("invert", false))
		bar.queue_redraw()


# --- helpers ----------------------------------------------------------------

func _label(text: String, font_size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	if color != Color.WHITE:
		l.add_theme_color_override("font_color", color)
	return l


# Fixed-width column cell; keeps its width even when its content is hidden.
func _cell(child: Control, width: int) -> Control:
	var box := MarginContainer.new()
	box.custom_minimum_size = Vector2(width, 0)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(child)
	return box


func _pad(child: Control, left := 0, top := 0) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_top", top)
	m.add_child(child)
	return m
