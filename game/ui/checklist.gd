extends CanvasLayer
## Start-up / before-takeoff checklist, top right. Items come from the
## aircraft's checklist.txt and tick themselves in order as the pilot does
## them. An optional aid (K toggles), not part of the no-HUD flying view.

const C_BG := Color(0.07, 0.08, 0.09, 0.82)
const C_DONE := Color(0.5, 0.82, 0.5)
const C_NEXT := Color(0.98, 0.78, 0.35)
const C_TODO := Color(1, 1, 1, 0.55)
const C_DIM := Color(1, 1, 1, 0.45)

var aircraft: Aircraft
var _items: Array[Dictionary] = []  # {section, cond, param, item, state, hint, done, row, mark, labels}
var _box: VBoxContainer
var _title: Label
var _hint: Label
var _seen := {}  # run-up / control-check memory


func _ready() -> void:
	layer = 5
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = C_BG
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -400
	panel.offset_right = -16
	panel.offset_top = 16
	add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 2)
	panel.add_child(root)
	_title = _label("", 17, Color.WHITE)
	root.add_child(_title)
	root.add_child(_label("Ticks itself as you go · K hides", 12, C_DIM))
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 1)
	root.add_child(_box)
	_hint = _label("", 14, C_NEXT)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hint.custom_minimum_size = Vector2(360, 0)
	root.add_child(_hint)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("checklist"):
		visible = not visible


## Load the aircraft's checklist and start from the top.
func set_aircraft(a: Aircraft) -> void:
	aircraft = a
	reset()


func reset() -> void:
	for c in _box.get_children():
		c.queue_free()
	_items.clear()
	_seen.clear()
	if aircraft == null:
		return
	_title.text = "%s — checklist" % aircraft.definition.display_name.replace(" (placeholder)", "")
	var path := aircraft.definition.checklist
	var f := FileAccess.open(path, FileAccess.READ) if path != "" else null
	if f == null:
		_title.text = "No checklist for this aircraft"
		return
	var section := ""
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line.begins_with("=="):
			section = line.trim_prefix("==").strip_edges()
			var h := _label(section, 13, C_NEXT.darkened(0.15))
			_box.add_child(_pad(h, 6))
			continue
		var parts := line.split("|")
		if parts.size() < 3:
			continue
		var cond := parts[0].strip_edges()
		var item := {"section": section, "cond": cond.get_slice(":", 0), "param": cond.get_slice(":", 1) if ":" in cond else "",
			"item": parts[1].strip_edges(), "state": parts[2].strip_edges(),
			"hint": parts[3].strip_edges() if parts.size() > 3 else "", "done": false}
		_add_row(item)
		_items.append(item)
	# Skip what's already true at spawn with the engine running (e.g. test flights).
	if aircraft.engine.running():
		for it in _items:
			if it.section != "BEFORE TAKEOFF":
				it.done = true


func _process(_delta: float) -> void:
	if aircraft == null or aircraft.engine == null or _items.is_empty():
		return
	_remember()
	var next := -1
	for i in _items.size():
		var it: Dictionary = _items[i]
		if not it.done and next < 0:
			if it.cond != "manual" and _met(it):
				it.done = true
			else:
				next = i
	for i in _items.size():
		var it: Dictionary = _items[i]
		var color: Color = C_DONE if it.done else (C_NEXT if i == next else C_TODO)
		it.mark.text = "✓" if it.done else ("▶" if i == next else "·")
		for l in [it.mark, it.name_label, it.state_label]:
			l.add_theme_color_override("font_color", color)
	_hint.text = ("→ " + _items[next].hint) if next >= 0 else "✓ Checklist complete. Have a good flight."
	_hint.add_theme_color_override("font_color", C_NEXT if next >= 0 else C_DONE)


# --- conditions ---------------------------------------------------------------

func _met(it: Dictionary) -> bool:
	var e := aircraft.engine
	var f := aircraft.fdm
	var rpm := f.prop_get("propulsion/engine/engine-rpm")
	var thr := FlightInput.throttle
	match it.cond:
		"fuel":
			return e.definition.fuel_positions[e.fuel_selector] == it.param
		"mixture_rich":
			return not e.definition.has_mixture or e.mixture > 0.95
		"carb_heat_off":
			return not e.carb_heat
		"master_on":
			return e.master or not e.definition.has_master
		"primed":
			return e.prime >= 2.0 or e.warmth > 0.5
		"pulled_through":
			return e.prime >= 2.0 or e.warmth > 0.5
		"throttle_closed":
			return thr < 0.04
		"throttle_cracked":
			return thr >= 0.03 and thr <= 0.25
		"magnetos_off":
			return e.magnetos == 0
		"magnetos_both":
			return e.magnetos == 3
		"brakes_held":
			return FlightInput.brake_left > 0.5 and FlightInput.brake_right > 0.5
		"engine_running":
			return e.running()
		"oil_pressure":
			return e.running() and f.prop_get("propulsion/engine/oil-pressure-psi") > 25.0
		"idle":
			return e.running() and rpm < float(it.param) and rpm > 600.0
		"runup":
			return e.running() and rpm >= float(it.param) - 50.0
		"controls_checked":
			return _seen.get("pitch+", false) and _seen.get("pitch-", false) and _seen.get("roll+", false) \
				and _seen.get("roll-", false) and _seen.get("rudder+", false) and _seen.get("rudder-", false)
		"flaps":
			return aircraft.flap_notch <= int(it.param)
		"trim_takeoff":
			return absf(aircraft.trim) < 0.25
		"mag_check":
			return _seen.get("mag_L", false) and _seen.get("mag_R", false) and e.magnetos == 3
		"carb_heat_check":
			return _seen.get("carb_heat", false) and not e.carb_heat
	return false


# Things that must have happened at some point, not just be true now.
func _remember() -> void:
	var e := aircraft.engine
	var i := FlightInput
	for axis in ["pitch", "roll", "rudder"]:
		var v: float = i.get(axis)
		if v > 0.8:
			_seen[axis + "+"] = true
		if v < -0.8:
			_seen[axis + "-"] = true
	var rpm := aircraft.fdm.prop_get("propulsion/engine/engine-rpm")
	if rpm > 1400.0 and e.running():
		if e.magnetos == 2:
			_seen["mag_L"] = true
		if e.magnetos == 1:
			_seen["mag_R"] = true
	if e.carb_heat and e.running() and rpm > 1300.0:
		_seen["carb_heat"] = true


# --- layout ---------------------------------------------------------------------

func _add_row(it: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var mark := _label("·", 15, C_TODO)
	mark.custom_minimum_size = Vector2(16, 0)
	row.add_child(mark)
	var name_label := _label(it.item, 15, C_TODO)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var state_label := _label(it.state, 15, C_TODO)
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(state_label)
	if it.cond == "manual":
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_tick_manual(it))
	_box.add_child(row)
	it.mark = mark
	it.name_label = name_label
	it.state_label = state_label


func _tick_manual(it: Dictionary) -> void:
	# Only the current step can be ticked by hand.
	for other in _items:
		if not other.done:
			if other == it:
				it.done = true
			return


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 3)
	return l


func _pad(c: Control, top: int) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", top)
	m.add_child(c)
	return m
