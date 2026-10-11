extends CanvasLayer
## Checklist and tutorial guide, top right. Items come from the aircraft's
## checklist.txt and tick themselves in order as the pilot does them; the
## cockpit part for the current step glows. A section can say "until:<cond>":
## once that is true, anything left in it (and before it) is marked skipped,
## so taking off without the run-up doesn't leave the list stuck. Shift+click
## the current line skips it. An optional aid (K toggles), not a flight HUD.

const C_BG := Color(0.06, 0.07, 0.08, 0.86)
const C_NOW_BG := Color(0.95, 0.65, 0.2, 0.18)
const C_DONE := Color(0.5, 0.85, 0.5)
const C_SKIP := Color(1, 1, 1, 0.35)
const C_NEXT := Color(1.0, 0.78, 0.35)
const C_TODO := Color(1, 1, 1, 0.6)
const C_DIM := Color(1, 1, 1, 0.5)
const WIDTH := 500

var aircraft: Aircraft
var _items: Array[Dictionary] = []
var _sections: Array[Dictionary] = []  # {title, until, header, rows, items}
var _box: VBoxContainer
var _title: Label
var _now_item: Label
var _now_hint: Label
var _seen := {}  # things that happened at some point (run-up checks, airborne...)
var _current := -2
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _t := 0.0


func _ready() -> void:
	layer = 5
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(C_BG, 16))
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -WIDTH - 16
	panel.offset_right = -16
	panel.offset_top = 16
	add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	panel.add_child(root)
	_title = _label("", 22, Color.WHITE)
	root.add_child(_title)
	root.add_child(_label("Ticks itself · glowing part = next step · Shift+click skips · K hides", 14, C_DIM))
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 2)
	root.add_child(_box)

	var now_panel := PanelContainer.new()
	now_panel.add_theme_stylebox_override("panel", _style(C_NOW_BG, 12))
	root.add_child(_pad(now_panel, 8))
	var now := VBoxContainer.new()
	now_panel.add_child(now)
	now.add_child(_label("NEXT STEP", 14, C_NEXT))
	_now_item = _label("", 24, Color.WHITE)
	now.add_child(_now_item)
	_now_hint = _label("", 18, Color(1, 1, 1, 0.9))
	_now_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_now_hint.custom_minimum_size = Vector2(WIDTH - 60, 0)
	now.add_child(_now_hint)

	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.albedo_color = C_NEXT
	_glow_mat.no_depth_test = true


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
	_sections.clear()
	_seen.clear()
	_current = -2
	_clear_glow()
	if aircraft == null:
		return
	_title.text = "%s — tutorial" % aircraft.definition.display_name.replace(" (placeholder)", "")
	var path := aircraft.definition.checklist
	var f := FileAccess.open(path, FileAccess.READ) if path != "" else null
	if f == null:
		_title.text = "No checklist for this aircraft"
		return
	var section: Dictionary = {}
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line.begins_with("=="):
			var head := line.trim_prefix("==").split("|")
			var title := head[0].strip_edges()
			var until := head[1].strip_edges().trim_prefix("until:") if head.size() > 1 else ""
			var header := _label(title, 17, C_NEXT.darkened(0.1))
			_box.add_child(_pad(header, 8))
			section = {"title": title, "until": _parse_cond(until) if until != "" else {}, "header": header,
				"rows": [], "items": []}
			_sections.append(section)
			continue
		var parts := line.split("|")
		if parts.size() < 3:
			continue
		var item := _parse_cond(parts[0].strip_edges())
		item.merge({"section": section.get("title", ""), "item": parts[1].strip_edges(),
			"state": parts[2].strip_edges(), "hint": parts[3].strip_edges() if parts.size() > 3 else "",
			"target": parts[4].strip_edges() if parts.size() > 4 else "", "done": false, "skipped": false})
		var row := _add_row(item)
		if not section.is_empty():
			section.rows.append(row)
			section.items.append(item)
		_items.append(item)


func _parse_cond(text: String) -> Dictionary:
	var bits := text.split(":")
	return {"cond": bits[0], "args": bits.slice(1)}


func _process(delta: float) -> void:
	_t += delta
	if aircraft == null or aircraft.engine == null or _items.is_empty():
		return
	_remember()
	var next := _advance()
	# Sections whose "until" has happened: what's left in them (and before)
	# counts as done if it's true right now, otherwise it's skipped.
	for si in _sections.size():
		var s: Dictionary = _sections[si]
		if not s.until.is_empty() and s.items.any(func(x): return not x.done) and _met(s.until):
			for sj in si + 1:
				for it in _sections[sj].items:
					if not it.done:
						it.done = true
						it.skipped = it.cond == "manual" or not _met(it)
			next = _advance()
	for i in _items.size():
		var it: Dictionary = _items[i]
		var color: Color = (C_SKIP if it.skipped else C_DONE) if it.done else (C_NEXT if i == next else C_TODO)
		it.mark.text = ("–" if it.skipped else "✓") if it.done else ("▶" if i == next else "·")
		for l in [it.mark, it.name_label, it.state_label]:
			l.add_theme_color_override("font_color", color)
	# Only the current section is open; done and upcoming ones fold to a line.
	var current_section: String = _items[next].section if next >= 0 else ""
	for s in _sections:
		var all_done: bool = s.items.all(func(x): return x.done)
		var open: bool = s.title == current_section
		for r in s.rows:
			r.visible = open
		if all_done:
			s.header.text = "✓  " + s.title
		elif open:
			s.header.text = s.title
		else:
			s.header.text = "%s  (%d steps)" % [s.title, s.items.size()]
		s.header.add_theme_color_override("font_color", C_DONE if all_done else (C_NEXT.darkened(0.1) if open else C_DIM))
	if next != _current:
		_current = next
		_show_step(next)
	if next >= 0:
		_now_hint.text = _fill(_items[next].hint)  # live distances / directions
	if _glow:
		_glow_mat.albedo_color.a = 0.45 + 0.4 * sin(_t * 6.0)
		_glow.scale = Vector3.ONE * (1.0 + 0.08 * sin(_t * 6.0))


# Tick items in order while their conditions hold; returns the current step.
func _advance() -> int:
	for i in _items.size():
		var it: Dictionary = _items[i]
		if not it.done:
			if it.cond != "manual" and _met(it):
				it.done = true
			else:
				return i
	return -1


func _show_step(i: int) -> void:
	_clear_glow()
	if i < 0:
		_now_item.text = "Tutorial complete!"
		_now_hint.text = "Well flown. Backspace starts again; N switches aircraft."
		_now_item.add_theme_color_override("font_color", C_DONE)
		return
	var it: Dictionary = _items[i]
	_now_item.text = "%s  →  %s" % [it.item, it.state]
	_now_item.add_theme_color_override("font_color", Color.WHITE)
	if it.target != "" and aircraft.airframe:
		var node := aircraft.airframe.find_child(it.target, true, false) as Node3D
		if node:
			_glow_at(node)


# "{dist:tower}" and "{clock:tower}" in hints become live values.
func _fill(text: String) -> String:
	if not "{" in text:
		return text
	for name in ["tower", "strip", "parking"]:
		var p: Vector3 = aircraft.world.point(name)
		text = text.replace("{dist:%s}" % name, _distance_text(_horizontal_distance(p)))
		text = text.replace("{clock:%s}" % name, "%d o'clock" % _clock(p))
	return text


# --- conditions ---------------------------------------------------------------

func _met(it: Dictionary) -> bool:
	var e := aircraft.engine
	var f := aircraft.fdm
	var rpm := f.prop_get("propulsion/engine/engine-rpm")
	var thr := FlightInput.throttle
	var a: Array = it.args
	match it.cond:
		"parking_brake_on":
			return FlightInput.parking_brake
		"parking_brake_off":
			return not FlightInput.parking_brake
		"fuel":
			return e.definition.fuel_positions[e.fuel_selector] == a[0]
		"mixture_rich":
			return not e.definition.has_mixture or e.mixture > 0.95
		"mixture_cutoff":
			return not e.definition.has_mixture or e.mixture < 0.05
		"carb_heat_off":
			return not e.carb_heat
		"carb_heat_on":
			return e.carb_heat
		"master_on":
			return e.master or not e.definition.has_master
		"master_off":
			return not e.master
		"primed", "pulled_through":
			return e.prime >= 2.0 or e.warmth > 0.5
		"throttle_closed":
			return thr < 0.04
		"throttle_cracked":
			return thr >= 0.03 and thr <= 0.25
		"throttle_full":
			return thr > 0.9
		"magnetos_off":
			return e.magnetos == 0
		"magnetos_both":
			return e.magnetos == 3
		"brakes_held":
			return FlightInput.brake_left > 0.5 and FlightInput.brake_right > 0.5
		"engine_running":
			return e.running()
		"engine_stopped":
			return not e.running()
		"oil_pressure":
			return e.running() and f.prop_get("propulsion/engine/oil-pressure-psi") > 25.0
		"idle":
			return e.running() and rpm < float(a[0]) and rpm > 500.0
		"runup":
			return e.running() and rpm >= float(a[0]) - 50.0
		"controls_checked":
			return _seen.get("pitch+", false) and _seen.get("pitch-", false) and _seen.get("roll+", false) \
				and _seen.get("roll-", false) and _seen.get("rudder+", false) and _seen.get("rudder-", false)
		"flaps":  # at or below a notch
			return aircraft.flap_notch <= int(a[0])
		"flaps_set":
			return aircraft.flap_notch == int(a[0])
		"flaps_at_least":
			return aircraft.flap_notch >= int(a[0])
		"trim_takeoff":
			return absf(aircraft.trim) < 0.25
		"mag_check":
			return _seen.get("mag_L", false) and _seen.get("mag_R", false) and e.magnetos == 3
		"carb_heat_check":
			return _seen.get("carb_heat", false) and not e.carb_heat
		"moving":
			return _ground_speed_kt() > 3.0
		"lined_up":
			return _on_ground() and aircraft.world.surface_at(aircraft.global_position) == &"grass_strip" \
				and _heading_error(aircraft.world.strip_heading()) < 15.0
		"airborne":
			return _seen.get("airborne", false)
		"agl_above":
			return f.prop_get("position/h-agl-ft") > float(a[0])
		"kias_above":
			return f.prop_get("velocities/vc-kts") > float(a[0])
		"near":  # near:<place>:<metres>
			return _horizontal_distance(aircraft.world.point(a[0])) < float(a[1])
		"heading_to":  # heading_to:<place>:<degrees tolerance>
			return _heading_error(_bearing_to(aircraft.world.point(a[0]))) < float(a[1])
		"landed":
			return _seen.get("airborne", false) and _on_ground() and f.prop_get("velocities/vc-kts") < 35.0 \
				and aircraft.world.surface_at(aircraft.global_position) == &"grass_strip"
		"parked":
			return _horizontal_distance(aircraft.world.point("parking")) < 8.0 and _ground_speed_kt() < 1.0
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
	if not _on_ground() and aircraft.fdm.prop_get("position/h-agl-ft") > 20.0:
		_seen["airborne"] = true


func _on_ground() -> bool:
	var f := aircraft.fdm
	for w in f.wheels():
		if f.prop_get("gear/unit[%d]/WOW" % w.index) > 0.5:
			return true
	return false


func _ground_speed_kt() -> float:
	return aircraft.fdm.prop_get("velocities/vg-fps") * 0.5925


func _horizontal_distance(p: Vector3) -> float:
	var d := p - aircraft.global_position
	return Vector2(d.x, d.z).length()


func _bearing_to(p: Vector3) -> float:
	var d := p - aircraft.global_position
	return fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)


func _heading_error(target_deg: float) -> float:
	return absf(wrapf(target_deg - aircraft.fdm.prop_get("attitude/psi-deg"), -180.0, 180.0))


func _clock(p: Vector3) -> int:
	var rel := wrapf(_bearing_to(p) - aircraft.fdm.prop_get("attitude/psi-deg"), 0.0, 360.0)
	var c := int(round(rel / 30.0)) % 12
	return 12 if c == 0 else c


func _distance_text(m: float) -> String:
	return "%.1f km" % (m / 1000.0) if m >= 1000.0 else "%d m" % int(round(m / 10.0) * 10)


# --- glow -----------------------------------------------------------------------

# A pulsing ring around the cockpit part to use, drawn on top so it is
# never hidden behind the panel.
func _glow_at(node: Node3D) -> void:
	var radius := 0.03
	if node is GaugeBase:
		radius = node.diameter_m * 0.62
	elif node is CockpitControl:
		radius = node.size_m * 1.1
	var torus := TorusMesh.new()
	torus.inner_radius = radius
	torus.outer_radius = radius + 0.006
	torus.rings = 32
	torus.ring_segments = 8
	_glow = MeshInstance3D.new()
	_glow.mesh = torus
	_glow.material_override = _glow_mat
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.rotation.x = PI / 2
	_glow.position.z = 0.004
	node.add_child(_glow)


func _clear_glow() -> void:
	if _glow and is_instance_valid(_glow):
		_glow.queue_free()
	_glow = null


# --- layout ---------------------------------------------------------------------

func _add_row(it: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var mark := _label("·", 20, C_TODO)
	mark.custom_minimum_size = Vector2(22, 0)
	row.add_child(mark)
	var name_label := _label(it.item, 20, C_TODO)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var state_label := _label(it.state, 20, C_TODO)
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(state_label)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_click(it, ev.shift_pressed))
	if it.cond == "manual":
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_box.add_child(row)
	it.mark = mark
	it.name_label = name_label
	it.state_label = state_label
	return row


# Click ticks a manual step; Shift+click skips the current step.
func _click(it: Dictionary, skip: bool) -> void:
	for other in _items:
		if not other.done:
			if other == it and (skip or it.cond == "manual"):
				it.done = true
				it.skipped = skip and it.cond != "manual"
			return


func _tick_manual(it: Dictionary) -> void:
	_click(it, false)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 3)
	return l


func _style(color: Color, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(8)
	s.set_content_margin_all(margin)
	return s


func _pad(c: Control, top: int) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", top)
	m.add_child(c)
	return m
