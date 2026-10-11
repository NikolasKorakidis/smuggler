extends CanvasLayer
## J / F2: shows every connected controller's raw axes and buttons, and binds
## flight controls by moving them ("Bind", then move the stick/pedal/lever).

const MAX_AXES := 10
const CAPTURE_DELTA := 0.5

var _root: PanelContainer
var _devices_box: VBoxContainer
var _bind_rows := {}  # name -> {binding: Label, bar: ProgressBar, invert: CheckBox}
var _status: Label
var _device_bars := {}  # device -> Array[ProgressBar]
var _device_buttons := {}  # device -> Label
var _capturing := ""
var _capture_rest := {}  # Vector2i(device, axis) -> value at capture start


func _ready() -> void:
	layer = 10
	_build()
	visible = false
	Input.joy_connection_changed.connect(func(_d, _c): _rebuild_devices())
	FlightInput.bindings_changed.connect(_refresh_bindings)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("axis_tester"):
		visible = not visible
		if visible:
			_rebuild_devices()
			_refresh_bindings()
		_capturing = ""
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not visible or _capturing == "":
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		_capturing = ""
		_status.text = "Cancelled."
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed and _capturing in FlightInput.BUTTONS:
		FlightInput.bind_button(_capturing, event.device, event.button_index)
		_status.text = "%s -> button %d on %s" % [
			FlightInput.LABELS[_capturing], event.button_index, Input.get_joy_name(event.device)]
		_capturing = ""
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible:
		return
	for d in _device_bars:
		var bars: Array = _device_bars[d]
		for a in bars.size():
			bars[a].value = Input.get_joy_axis(d, a)
		var pressed := []
		for b in 128:
			if Input.is_joy_button_pressed(d, b):
				pressed.append(str(b))
		_device_buttons[d].text = "Buttons: " + (", ".join(pressed) if pressed else "-")
	for name in FlightInput.AXES:
		var bar: ProgressBar = _bind_rows[name].bar
		bar.value = FlightInput.axis_value(name)
	if _capturing in FlightInput.AXES:
		for key in _capture_rest:
			if absf(Input.get_joy_axis(key.x, key.y) - _capture_rest[key]) > CAPTURE_DELTA:
				FlightInput.bind_axis(_capturing, key.x, key.y)
				_status.text = "%s -> axis %d on %s. Tick Invert if it moves the wrong way." % [
					FlightInput.LABELS[_capturing], key.y, Input.get_joy_name(key.x)]
				_capturing = ""
				break


func _start_capture(name: String) -> void:
	_capturing = name
	_capture_rest.clear()
	for d in Input.get_connected_joypads():
		for a in MAX_AXES:
			_capture_rest[Vector2i(d, a)] = Input.get_joy_axis(d, a)
	if name in FlightInput.AXES:
		_status.text = "Move the control for '%s' through its full range... (Esc cancels)" % FlightInput.LABELS[name]
	else:
		_status.text = "Press the button for '%s'... (Esc cancels)" % FlightInput.LABELS[name]


func _build() -> void:
	_root = PanelContainer.new()
	_root.position = Vector2(40, 40)
	_root.custom_minimum_size = Vector2(1100, 0)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_root.add_child(margin)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 32)
	margin.add_child(cols)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(460, 0)
	cols.add_child(left)
	left.add_child(_title("Controllers (raw)"))
	_devices_box = VBoxContainer.new()
	left.add_child(_devices_box)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(580, 0)
	cols.add_child(right)
	right.add_child(_title("Flight controls"))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	right.add_child(grid)
	for name in FlightInput.AXES + FlightInput.BUTTONS:
		var label := Label.new()
		label.text = FlightInput.LABELS[name]
		label.custom_minimum_size = Vector2(190, 0)
		grid.add_child(label)
		var binding := Label.new()
		binding.custom_minimum_size = Vector2(150, 0)
		binding.clip_text = true
		grid.add_child(binding)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(90, 16)
		bar.show_percentage = false
		bar.step = 0.0
		bar.min_value = -1.0 if name in FlightInput.BIPOLAR else 0.0
		bar.max_value = 1.0
		bar.visible = name in FlightInput.AXES
		grid.add_child(bar)
		var bind := Button.new()
		bind.text = "Bind"
		bind.pressed.connect(_start_capture.bind(name))
		var invert := CheckBox.new()
		invert.text = "Invert"
		invert.visible = name in FlightInput.AXES
		invert.toggled.connect(func(on): FlightInput.set_invert(name, on))
		var clear := Button.new()
		clear.text = "Clear"
		clear.pressed.connect(func(): FlightInput.clear_binding(name))
		var buttons := HBoxContainer.new()
		buttons.add_child(bind)
		buttons.add_child(clear)
		grid.add_child(buttons)
		grid.add_child(invert)
		_bind_rows[name] = {"binding": binding, "bar": bar, "invert": invert}
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.custom_minimum_size = Vector2(560, 48)
	right.add_child(_status)
	var hint := Label.new()
	hint.text = "Gamepads work without binding. Bindings are saved per device. J closes."
	hint.modulate = Color(1, 1, 1, 0.6)
	right.add_child(hint)
	add_child(_root)


func _rebuild_devices() -> void:
	for c in _devices_box.get_children():
		c.queue_free()
	_device_bars.clear()
	_device_buttons.clear()
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		var none := Label.new()
		none.text = "No controllers connected. Plug in the HOTAS / pedals."
		_devices_box.add_child(none)
		return
	for d in pads:
		var name := Label.new()
		name.text = "#%d  %s%s" % [d, Input.get_joy_name(d), "  (gamepad)" if Input.is_joy_known(d) else ""]
		_devices_box.add_child(name)
		var warning := FlightInput.mode_warning(d)
		if warning:
			var w := Label.new()
			w.text = warning
			w.autowrap_mode = TextServer.AUTOWRAP_WORD
			w.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
			_devices_box.add_child(w)
		var grid := GridContainer.new()
		grid.columns = 2
		var bars: Array = []
		for a in MAX_AXES:
			var l := Label.new()
			l.text = "axis %d" % a
			grid.add_child(l)
			var bar := ProgressBar.new()
			bar.min_value = -1.0
			bar.max_value = 1.0
			bar.step = 0.0
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(320, 12)
			grid.add_child(bar)
			bars.append(bar)
		_devices_box.add_child(grid)
		var buttons := Label.new()
		_devices_box.add_child(buttons)
		_device_bars[d] = bars
		_device_buttons[d] = buttons


func _refresh_bindings() -> void:
	for name in _bind_rows:
		var row: Dictionary = _bind_rows[name]
		var b = FlightInput.axis_bindings.get(name, FlightInput.button_bindings.get(name))
		if b == null:
			row.binding.text = "keyboard" if name not in ["brake_left", "brake_right"] else "-"
		elif "axis" in b:
			row.binding.text = "axis %d · %s" % [b.axis, "default" if b.get("profile") else b.device_name]
		else:
			row.binding.text = "btn %d · %s" % [b.button, "default" if b.get("profile") else b.device_name]
		row.binding.tooltip_text = row.binding.text
		row.invert.set_pressed_no_signal(b != null and b.get("invert", false))


func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	return l
