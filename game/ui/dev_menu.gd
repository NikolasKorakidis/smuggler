extends CanvasLayer
## Developer menu (` or Fn+F10): every tunable in one place for testing.
## Controls read their live value back a few times a second, so the menu
## always shows the real state. Works in any world that provides weather,
## time_of_day, aircraft and the tutorial interface.

const C_BG := Color(0.06, 0.07, 0.08, 0.93)
const C_DIM := Color(1, 1, 1, 0.55)
const C_HEAD := Color(1.0, 0.78, 0.35)
const WIDTH := 460

var world: Node3D
var _refreshers: Array[Callable] = []
var _refresh_t := 0.0
var _tabs: TabContainer
var _status: Label

# Flight tab inputs
var _air_alt_ft := 1500.0
var _air_kias := 80.0
var _air_heading := -1.0  # -1 = runway heading


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS  # usable while the sim is paused
	world = get_parent()
	visible = false
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("dev_menu"):
		visible = not visible
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_t += delta
	if _refresh_t > 0.25:
		_refresh_t = 0.0
		for r in _refreshers:
			r.call()


# --- shortcuts into the world ------------------------------------------------

func _ac() -> Aircraft:
	return world.aircraft


func _weather() -> Weather:
	return world.weather


func _tod() -> TimeOfDay:
	return world.time_of_day


func _env() -> Environment:
	return world.get_node("WorldEnvironment").environment


func _say(text: String) -> void:
	_status.text = text


# --- layout ------------------------------------------------------------------

func _build() -> void:
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = C_BG
	st.set_corner_radius_all(8)
	st.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", st)
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(WIDTH, 0)
	add_child(panel)
	var root := VBoxContainer.new()
	panel.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var title := _label("Developer menu", 20, Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_button("Close (`)", func(): visible = false))
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(WIDTH, 640)
	root.add_child(_tabs)
	_status = _label("", 13, C_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.custom_minimum_size = Vector2(WIDTH - 20, 20)
	root.add_child(_status)
	_tab_time()
	_tab_weather()
	_tab_sky()
	_tab_clouds()
	_tab_flight()
	_tab_aircraft()
	_tab_engine()
	_tab_rendering()
	_tab_debug()


func _tab(name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	scroll.add_child(box)
	return box


func _section(box: VBoxContainer, text: String) -> void:
	var l := _label(text, 14, C_HEAD)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 8)
	m.add_child(l)
	box.add_child(m)


func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	return b


func _buttons(box: VBoxContainer, items: Array) -> void:
	var row := HFlowContainer.new()
	for it in items:
		row.add_child(_button(it[0], it[1]))
	box.add_child(row)


## A slider row: label, slider, live value text. getter/setter are Callables.
func _slider(box: VBoxContainer, text: String, lo: float, hi: float, step: float, getter: Callable,
		setter: Callable, fmt: Variant = "%.1f") -> void:
	var row := HBoxContainer.new()
	var name := _label(text, 14)
	name.custom_minimum_size = Vector2(150, 0)
	row.add_child(name)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(170, 0)
	row.add_child(s)
	var val := _label("", 14, C_DIM)
	val.custom_minimum_size = Vector2(90, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	box.add_child(row)
	var dragging := [false]
	s.drag_started.connect(func(): dragging[0] = true)
	s.drag_ended.connect(func(_c): dragging[0] = false)
	s.value_changed.connect(func(v):
		setter.call(v)
		val.text = _fmt(fmt, v))
	var refresh := func():
		if not dragging[0]:
			var v: float = getter.call()
			s.set_value_no_signal(v)
			val.text = _fmt(fmt, v)
	refresh.call()
	_refreshers.append(refresh)


func _fmt(fmt: Variant, v: float) -> String:
	return fmt.call(v) if fmt is Callable else fmt % v


func _check(box: VBoxContainer, text: String, getter: Callable, setter: Callable) -> void:
	var c := CheckBox.new()
	c.text = text
	c.add_theme_font_size_override("font_size", 14)
	c.toggled.connect(func(on): setter.call(on))
	box.add_child(c)
	var refresh := func(): c.set_pressed_no_signal(getter.call())
	refresh.call()
	_refreshers.append(refresh)


func _choice(box: VBoxContainer, text: String, options: Array, getter: Callable, setter: Callable) -> void:
	var row := HBoxContainer.new()
	var name := _label(text, 14)
	name.custom_minimum_size = Vector2(150, 0)
	row.add_child(name)
	var o := OptionButton.new()
	for opt in options:
		o.add_item(str(opt))
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.item_selected.connect(func(i): setter.call(i))
	row.add_child(o)
	box.add_child(row)
	var refresh := func():
		var i: int = getter.call()
		if o.selected != i:
			o.select(i)
	refresh.call()
	_refreshers.append(refresh)


func _readout(box: VBoxContainer, getter: Callable) -> void:
	var l := _label("", 13, C_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(l)
	var refresh := func(): l.text = getter.call()
	refresh.call()
	_refreshers.append(refresh)


# --- tabs ----------------------------------------------------------------------

func _tab_time() -> void:
	var b := _tab("Time")
	_section(b, "CLOCK (local solar time)")
	_slider(b, "Time of day", 0.0, 23.99, 1.0 / 60.0, func(): return _tod().hours,
		func(v): _tod().set_hours(v), func(v): return "%02d:%02d" % [int(v), int(fmod(v, 1.0) * 60.0)])
	_slider(b, "Time speed", 0.0, 120.0, 1.0, func(): return _tod().time_scale,
		func(v): _tod().time_scale = v, "%.0fx")
	_buttons(b, [["Dawn 05:45", func(): _tod().set_hours(5.75)], ["Morning", func(): _tod().set_hours(9.0)],
		["Noon", func(): _tod().set_hours(12.5)], ["Golden 17:30", func(): _tod().set_hours(17.5)],
		["Sunset", func(): _tod().set_hours(18.4)], ["Dusk", func(): _tod().set_hours(18.9)],
		["Night", func(): _tod().set_hours(23.0)], ["Freeze", func(): _tod().time_scale = 0.0]])
	_section(b, "DATE")
	_slider(b, "Day of year", 1, 365, 1, func(): return _tod().day_of_year,
		func(v): _tod().day_of_year = int(v), func(v): return _date_text(int(v)))
	_slider(b, "Year", 1978, 1988, 1, func(): return _tod().year, func(v): _tod().year = int(v), "%.0f")
	_readout(b, func():
		var t := _tod()
		return "Sun %+.1f°   Moon phase %.2f (%d%% lit)   Sidereal %.2f h\nEye exposure %.2fx   Stars to magnitude %.1f" % [
			t.sun_elevation_deg(), t.moon_phase(), int(t.moon_illumination() * 100.0), t.local_sidereal_hours(),
			t.environment.tonemap_exposure, t.limiting_magnitude])


func _date_text(doy: int) -> String:
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var days := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	var d := doy
	for m in 12:
		if d <= days[m]:
			return "%d %s" % [d, months[m]]
		d -= days[m]
	return str(doy)


func _tab_weather() -> void:
	var b := _tab("Weather")
	var names := []
	for p in Weather.PRESETS:
		names.append(p.name)
	_choice(b, "Preset", names, func(): return _weather().preset, func(i): _weather().set_preset(i))
	_buttons(b, [["Apply preset now", func(): _weather().set_preset(_weather().preset, true)]])
	_section(b, "WIND (changing a slider stops preset blending)")
	_wslider(b, "Wind from", 0, 359, 1, "wind_dir_deg", "%03.0f°")
	_wslider(b, "Surface wind", 0, 40, 0.5, "wind_kt", "%.1f kt")
	_wslider(b, "Gusts (+kt)", 0, 25, 0.5, "gust_kt", "+%.1f kt")
	_wslider(b, "Wind aloft", 0, 60, 1, "aloft_kt", "%.0f kt")
	_wslider(b, "Veer with height", -45, 45, 1, "veer_deg", "%+.0f°")
	_wslider(b, "Turbulence", 0, 1, 0.01, "turbulence", "%.2f")
	_section(b, "AIR")
	_wslider(b, "Temperature", -10, 45, 0.5, "temp_c", "%.1f °C")
	_wslider(b, "Dew point", -20, 30, 0.5, "dewpoint_c", func(v): return "%.1f °C (RH %d%%)" % [v, int(_weather().relative_humidity() * 100.0)])
	_wslider(b, "QNH", 970, 1040, 0.5, "qnh_hpa", func(v): return "%.1f hPa (%.2f\")" % [v, v * 0.02953])
	_slider(b, "Blend time", 0, 120, 1, func(): return _weather().transition_s,
		func(v): _weather().transition_s = v, "%.0f s")
	_readout(b, func():
		var f := _ac().fdm
		return "%s\nDensity altitude %d ft   Pressure altitude %d ft" % [_weather().summary(),
			int(f.prop_get("atmosphere/density-altitude")), int(f.prop_get("atmosphere/pressure-altitude"))])


func _tab_sky() -> void:
	var b := _tab("Sky & rain")
	_section(b, "VISIBILITY AND FOG")
	_wslider(b, "Visibility (clear air)", 0.5, 60, 0.5, "visibility_km", "%.1f km")
	_wslider(b, "Haze layer depth", 200, 3000, 50, "haze_height_m", "%.0f m")
	_wslider(b, "Fog deck top", 0, 500, 5, "fog_top_m", func(v): return "none" if v < 2.0 else "%.0f m above field" % v)
	_wslider(b, "Visibility in fog", 30, 2000, 10, "fog_visibility_m", "%.0f m")
	_check(b, "Fog burns off after sunrise", func(): return _weather().fog_burns_off, func(on): _weather().fog_burns_off = on)
	_section(b, "CLOUDS")
	_wslider(b, "Cloud cover", 0, 1, 0.01, "cloud_cover", func(v): return "%.2f (%d oktas)" % [v, int(round(v * 8.0))])
	_wslider(b, "Cloud base", 100, 3500, 25, "cloud_base_m", func(v): return "%.0f m (%d ft)" % [v, int(v / 0.3048)])
	_wslider(b, "Cloud top", 200, 6000, 50, "cloud_top_m", "%.0f m")
	_wslider(b, "Cumulus .. stratus", 0, 1, 0.05, "cloud_type", "%.2f")
	_wslider(b, "High cirrus", 0, 1, 0.05, "cirrus", "%.2f")
	_section(b, "RAIN")
	_wslider(b, "Steady rain", 0, 80, 0.5, "rain_mmh", "%.1f mm/h")
	_slider(b, "Ground wetness", 0, 1, 0.01, func(): return _weather().wetness, func(v): _weather().wetness = v, "%.2f")
	_section(b, "THUNDERSTORMS")
	_wslider(b, "New storms per hour", 0, 12, 0.5, "storms_per_hour", "%.1f")
	_wslider(b, "Storm strength", 0.5, 1.5, 0.05, "storm_power", "%.2f")
	_buttons(b, [["Storm 8 km ahead", func(): _weather().spawn_storm(8000.0, _heading(), 0.4)],
		["Storm overhead", func(): _weather().spawn_storm(0.0, 0.0, 0.45)],
		["Growing, 15 km upwind", func(): _weather().spawn_storm(15000.0, _weather().wind_dir_deg, 0.05)],
		["Clear storms", func(): _weather().cells.clear()]])
	_buttons(b, [["Lightning 2 km ahead", func(): _strike(2000.0)], ["Lightning 6 km ahead", func(): _strike(6000.0)]])
	_readout(b, func():
		var w := _weather()
		var here := _ac().global_position
		var near := ""
		var best := INF
		for c in w.cells:
			var d := Vector2(here.x, here.z).distance_to(c.pos)
			if d < best:
				best = d
				var stage := "growing" if c.progress() < 0.25 else ("mature" if c.progress() < 0.7 else "dying")
				near = "nearest %.1f km, %s, outflow %.0f kt" % [d / 1000.0, stage, c.outflow_ms() / 0.514444]
		return "%s\nRain here %.1f mm/h   Storms %d %s" % [w.metar(), w.rain_at(here), w.cells.size(), near])


# --- cloud designer --------------------------------------------------------------

var _cl_layer := 0


func _clouds() -> Clouds:
	return world.get_node("WeatherFX").clouds


func _cl() -> Clouds.Layer:
	return _clouds().layers[_cl_layer]


# The selected layer's type, taken over from the weather so edits stick.
func _ct() -> CloudType:
	if not _cl().manual:
		_clouds().set_manual(_cl_layer, true)
	return _cl().type


func _ct_slider(b: VBoxContainer, text: String, field: String, lo: float, hi: float, step: float, fmt: Variant) -> void:
	_slider(b, text, lo, hi, step, func(): return _cl().type.get(field) if _cl().type else 0.0,
		func(v): _ct().set(field, v), fmt)


func _tab_clouds() -> void:
	var b := _tab("Clouds")
	var ids: Array = _clouds().types.keys()
	ids.sort()
	_section(b, "LAYER (manual = the designer owns it, not the weather)")
	_choice(b, "Layer", ["Low", "Mid", "High"], func(): return _cl_layer, func(i): _cl_layer = i)
	_check(b, "Manual (designer)", func(): return _cl().manual, func(on): _clouds().set_manual(_cl_layer, on))
	_check(b, "Layer on", func(): return _cl().enabled, func(on):
		_clouds().set_manual(_cl_layer, true)
		_cl().enabled = on)
	var names: Array = []
	for id in ids:
		names.append(_clouds().types[id].display_name)
	_choice(b, "Cloud type", names, func(): return maxi(ids.find(_cl().type_id), 0), func(i):
		_clouds().set_manual(_cl_layer, true)
		_clouds().set_layer_type(_cl_layer, ids[i]))
	_slider(b, "Cover", 0, 1, 0.01, func(): return _cl().cover, func(v):
		_clouds().set_manual(_cl_layer, true)
		_cl().cover = v, func(v): return "%.2f (%d oktas)" % [v, int(round(v * 8.0))])
	_slider(b, "Base", 100, 9000, 25, func(): return _cl().base_m, func(v):
		_clouds().set_manual(_cl_layer, true)
		_cl().base_m = v
		_cl().top_m = maxf(_cl().top_m, v + 100.0), func(v): return "%.0f m (%d ft)" % [v, int(v / 0.3048)])
	_slider(b, "Top", 200, 12000, 25, func(): return _cl().top_m, func(v):
		_clouds().set_manual(_cl_layer, true)
		_cl().top_m = maxf(v, _cl().base_m + 100.0), "%.0f m")
	_section(b, "LOOK OF THIS LAYER'S TYPE")
	_ct_slider(b, "Heaps .. sheet", "heaps", 0, 1, 0.05, "%.2f")
	_ct_slider(b, "Edge softness", "softness", 0.01, 0.3, 0.005, "%.3f")
	_ct_slider(b, "Edge erosion (detail)", "erosion", 0, 1, 0.02, "%.2f")
	_ct_slider(b, "Billowing sides", "billow", 0, 1200, 10, "%.0f m")
	_ct_slider(b, "Narrowing to the top", "narrowing", 0, 0.4, 0.01, "%.2f")
	_ct_slider(b, "Density", "density", 0.1, 3, 0.05, "%.2f")
	_ct_slider(b, "Light extinction", "extinction", 0.005, 0.15, 0.005, "%.3f /m")
	_ct_slider(b, "Patchiness", "patchiness", 0, 1, 0.05, "%.2f")
	_ct_slider(b, "Billow size", "scale", 0.3, 3, 0.05, "%.2fx")
	_ct_slider(b, "Base wobble", "base_wobble", 0, 400, 5, "%.0f m")
	_ct_slider(b, "Top wobble", "top_wobble", 0, 500, 5, "%.0f m")
	_section(b, "ENGINE")
	_slider(b, "Ray-march steps", 32, 200, 8, func(): return _clouds().steps, func(v): _clouds().steps = int(v), "%.0f")
	_slider(b, "Sun-march steps", 2, 10, 1, func(): return _clouds().light_steps, func(v): _clouds().light_steps = int(v), "%.0f")
	_slider(b, "Cells grow/fade speed", 0, 20, 0.5, func(): return _clouds().evolution, func(v): _clouds().evolution = v, "%.1fx")
	_buttons(b, [["All layers back to the weather", func():
		for i in 3:
			_clouds().set_manual(i, false)]])
	_readout(b, func():
		var parts := []
		for i in 3:
			var l: Clouds.Layer = _clouds().layers[i]
			parts.append("%s: %s %s %.2f %d-%d m" % [["Low", "Mid", "High"][i], "on" if l.enabled else "off",
				l.type.display_name if l.type else "-", l.cover, int(l.base_m), int(l.top_m)])
		return "\n".join(parts))


func _heading() -> float:
	return _ac().fdm.prop_get("attitude/psi-deg")


func _strike(dist: float) -> void:
	var b := deg_to_rad(_heading())
	var at := _ac().global_position + Vector3(sin(b), 0.0, -cos(b)) * dist
	at.y = world.terrain_height(at)
	_weather().lightning.emit(at, true, 1.0)


func _wslider(b: VBoxContainer, text: String, lo: float, hi: float, step: float, field: String, fmt: Variant) -> void:
	_slider(b, text, lo, hi, step, func(): return _weather().get(field), func(v):
		_weather()._target = {}  # manual control: stop blending towards a preset
		_weather().set(field, v), fmt)


func _tab_flight() -> void:
	var b := _tab("Flight")
	var names := []
	for d in world.aircraft_definitions:
		names.append(d.display_name)
	_choice(b, "Aircraft", names, func(): return world._aircraft_index, func(i): world._spawn_aircraft(i))
	_section(b, "SIMULATION")
	_slider(b, "Sim speed", 0.25, 4.0, 0.25, func(): return Engine.time_scale,
		func(v): Engine.time_scale = v, "%.2fx")
	_check(b, "Paused", func(): return get_tree().paused, func(on): get_tree().paused = on)
	_section(b, "PLACE THE AIRCRAFT")
	_buttons(b, [["Start of strip (cold)", _respawn_cold], ["Start of strip (running)", _respawn_running]])
	_slider(b, "Airborne altitude", 300, 8000, 100, func(): return _air_alt_ft, func(v): _air_alt_ft = v, "%.0f ft AGL")
	_slider(b, "Airborne speed", 40, 130, 1, func(): return _air_kias, func(v): _air_kias = v, "%.0f kt")
	_slider(b, "Heading (-1 = strip)", -1, 359, 1, func(): return _air_heading, func(v): _air_heading = v,
		func(v): return "strip" if v < 0 else "%03.0f°" % v)
	_buttons(b, [["Teleport airborne here", func(): _teleport_air(false)],
		["Final approach (2 km, 600 ft)", func(): _teleport_air(true)]])
	_section(b, "LOAD")
	_slider(b, "Fuel", 0, 100, 1, func(): return _fuel_pct(), func(v): _set_fuel_pct(v), "%.0f %%")
	_slider(b, "Passenger / cargo", 0, 500, 5, func(): return _payload(), func(v): _set_payload(v), "%.0f lb")
	_readout(b, func():
		var f := _ac().fdm
		return "Weight %d lb   CG %.1f in   Fuel %.0f lb" % [int(f.prop_get("inertia/weight-lbs")),
			f.prop_get("inertia/cg-x-in"), f.prop_get("propulsion/total-fuel-lbs")])


func _respawn_cold() -> void:
	world.start_engine_running = false
	_ac().respawn()


func _respawn_running() -> void:
	world.start_engine_running = true
	_ac().respawn()
	world.start_engine_running = false


func _teleport_air(approach: bool) -> void:
	var ac := _ac()
	var centre: Vector3 = world.point("strip")
	var h: float = world.strip_heading()
	var dir := Vector3(sin(deg_to_rad(h)), 0.0, -cos(deg_to_rad(h)))
	if approach:
		# 2 km before the start of the strip, lined up, 600 ft above it, flaps 10.
		var start: Vector3 = centre - dir * float(world.strip_length()) * 0.5
		ac.teleport_air(start - dir * 2000.0, h, centre.y + 600.0 * 0.3048, 70.0)
		ac.set_flap_notch(1)
		FlightInput.set_throttle_keyboard(0.35)
		_say("On final: 2 km out, 600 ft above the strip, 70 kt, flaps 10.")
	else:
		var pos := ac.global_position
		var heading: float = h if _air_heading < 0.0 else _air_heading
		ac.teleport_air(pos, heading, world.terrain_height(pos) + _air_alt_ft * 0.3048, _air_kias)
		_say("Airborne: %d ft AGL, %d kt, heading %03d." % [int(_air_alt_ft), int(_air_kias), int(heading)])


func _tanks() -> Array[int]:
	var out: Array[int] = []
	var i := 0
	while _ac().fdm.jsb.has_property("propulsion/tank[%d]/contents-lbs" % i):
		out.append(i)
		i += 1
	return out


func _fuel_pct() -> float:
	var f := _ac().fdm
	var have := 0.0
	var cap := 0.0
	for i in _tanks():
		var c := f.prop_get("propulsion/tank[%d]/contents-lbs" % i)
		var pct := f.prop_get("propulsion/tank[%d]/pct-full" % i)
		have += c
		cap += c * 100.0 / pct if pct > 0.1 else 0.0
	return have / cap * 100.0 if cap > 0.0 else 0.0


func _set_fuel_pct(v: float) -> void:
	var f := _ac().fdm
	for i in _tanks():
		var c := f.prop_get("propulsion/tank[%d]/contents-lbs" % i)
		var pct := f.prop_get("propulsion/tank[%d]/pct-full" % i)
		var cap := c * 100.0 / pct if pct > 0.1 else (185.0 if _ac().definition.jsbsim_model == "c172p" else 75.0)
		f.prop("propulsion/tank[%d]/contents-lbs" % i, cap * v / 100.0)


func _payload() -> float:
	var f := _ac().fdm
	return f.prop_get("inertia/pointmass-weight-lbs[1]") if f.jsb.has_property("inertia/pointmass-weight-lbs[1]") else 0.0


func _set_payload(v: float) -> void:
	var f := _ac().fdm
	if f.jsb.has_property("inertia/pointmass-weight-lbs[1]"):
		f.prop("inertia/pointmass-weight-lbs[1]", v)
	else:
		_say("This aircraft has no passenger seat in its data.")


func _tab_aircraft() -> void:
	var b := _tab("Aircraft")
	_section(b, "CONTROLS")
	_slider(b, "Flaps notch", 0, 3, 1, func(): return _ac().flap_notch, func(v): _ac().set_flap_notch(int(v)),
		func(v): return "%d°" % _ac().flap_notch_degrees(int(v)) if not _ac().definition.flap_detents.is_empty() else "none")
	_slider(b, "Elevator trim", -1, 1, 0.01, func(): return _ac().trim, func(v): _ac().trim = v, "%+.2f")
	_check(b, "Parking brake", func(): return FlightInput.parking_brake, func(on): FlightInput.parking_brake = on)
	_slider(b, "Altimeter setting", 28.5, 31.0, 0.01, func(): return _ac().altimeter_setting_inhg,
		func(v): _ac().altimeter_setting_inhg = v, "%.2f inHg")
	_buttons(b, [["Altimeter to QNH", func(): _ac().altimeter_setting_inhg = snappedf(_weather().qnh_hpa * 0.02953, 0.01)]])
	_section(b, "LIGHTS (need master)")
	_check(b, "Landing light", func(): return _ac().lights.landing, func(on): _ac().lights.landing = on)
	_check(b, "Nav lights + beacon", func(): return _ac().lights.nav, func(on): _ac().lights.nav = on)
	_check(b, "Panel lights", func(): return _ac().lights.panel, func(on): _ac().lights.panel = on)
	_section(b, "HANDLING")
	_slider(b, "Brake strength", 0, 1, 0.05, func(): return _ac().definition.brake_strength,
		func(v): _ac().definition.brake_strength = v, "%.2f")
	_slider(b, "Stall horn AoA", 0, 20, 0.5, func(): return _ac().definition.stall_warning_alpha_deg,
		func(v): _ac().definition.stall_warning_alpha_deg = v, func(v): return "off" if v <= 0.0 else "%.1f°" % v)
	_readout(b, func():
		var f := _ac().fdm
		return "KIAS %.0f   AoA %.1f°   G %.2f   Pitch %.1f°   Bank %.1f°   VS %+.0f fpm" % [
			f.prop_get("velocities/vc-kts"), f.prop_get("aero/alpha-deg"), f.prop_get("accelerations/n-pilot-z-norm"),
			f.prop_get("attitude/theta-deg"), f.prop_get("attitude/phi-deg"), f.prop_get("velocities/h-dot-fps") * 60.0])


func _tab_engine() -> void:
	var b := _tab("Engine")
	_buttons(b, [["Start (assist)", func(): _ac().engine.auto_start()],
		["Running now", func(): _ac().engine.reset(true)], ["Stop now", func(): _ac().engine.reset(false)]])
	_section(b, "SWITCHES")
	_check(b, "Master", func(): return _ac().engine.master, func(on): _ac().engine.set_master(on))
	_choice(b, "Magnetos", ["OFF", "R", "L", "BOTH"], func(): return _ac().engine.magnetos, func(i): _ac().engine.set_magnetos(i))
	_slider(b, "Mixture", 0, 1, 0.01, func(): return _ac().engine.mixture, func(v): _ac().engine.set_mixture(v), "%.2f")
	_check(b, "Carb heat", func(): return _ac().engine.carb_heat, func(on): _ac().engine.set_carb_heat(on))
	_fuel_choice(b)
	_section(b, "STATE")
	_slider(b, "Primer (strokes in)", 0, 10, 0.5, func(): return _ac().engine.prime, func(v): _ac().engine.prime = v, "%.1f")
	_slider(b, "Engine warmth", 0, 1, 0.05, func(): return _ac().engine.warmth, func(v): _ac().engine.warmth = v,
		func(v): return "warm" if v > 0.5 else "cold")
	_slider(b, "Carburettor ice", 0, 1, 0.01, func(): return _ac().engine.carb_ice, func(v): _ac().engine.carb_ice = v, "%.2f")
	_readout(b, func(): return "Carb icing risk now %d%% (temperature/dew point and throttle)   Meltwater roughness %.2f" % [
		int(_ac().engine.carb_ice_risk() * 100.0), _ac().engine.melt_rough])
	_readout(b, func():
		var f := _ac().fdm
		return "RPM %.0f   Power %.0f hp   Oil %.0f °F / %.0f psi   Fuel flow %.1f gph   %s" % [
			f.prop_get("propulsion/engine/engine-rpm"), f.prop_get("propulsion/engine/power-hp"),
			f.prop_get("propulsion/engine/oil-temperature-degF"), f.prop_get("propulsion/engine/oil-pressure-psi"),
			f.prop_get("propulsion/engine/fuel-flow-rate-gph"), "RUNNING" if _ac().engine.running() else "STOPPED"])


# Fuel selector whose positions follow the current aircraft (Cub OFF/ON, 172 four-way).
func _fuel_choice(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	var name := _label("Fuel selector", 14)
	name.custom_minimum_size = Vector2(150, 0)
	row.add_child(name)
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.item_selected.connect(func(i): _ac().engine.set_fuel_selector(i))
	row.add_child(o)
	box.add_child(row)
	var refresh := func():
		var positions: PackedStringArray = _ac().definition.fuel_positions
		if o.item_count != positions.size():
			o.clear()
			for p in positions:
				o.add_item(p)
		if o.selected != _ac().engine.fuel_selector:
			o.select(_ac().engine.fuel_selector)
	refresh.call()
	_refreshers.append(refresh)


func _tab_rendering() -> void:
	var b := _tab("Render")
	var sun: DirectionalLight3D = world.get_node("Sun")
	_section(b, "LIGHT AND SHADOW")
	_check(b, "Sun shadows", func(): return sun.shadow_enabled, func(on): sun.shadow_enabled = on)
	_slider(b, "Shadow distance", 200, 6000, 100, func(): return sun.directional_shadow_max_distance,
		func(v): sun.directional_shadow_max_distance = v, "%.0f m")
	_check(b, "Ambient occlusion (SSAO)", func(): return _env().ssao_enabled, func(on): _env().ssao_enabled = on)
	_check(b, "Glow / bloom", func(): return _env().glow_enabled, func(on): _env().glow_enabled = on)
	_section(b, "WEATHER EFFECTS")
	var fx: WeatherFX = world.get_node("WeatherFX")
	_check(b, "Volumetric clouds", func(): return fx.atmosphere.clouds_enabled, func(on): fx.atmosphere.clouds_enabled = on)
	_slider(b, "Cloud quality (steps)", 32, 160, 8, func(): return fx.clouds.steps, func(v): fx.clouds.steps = int(v), "%.0f")
	_check(b, "Fog, haze and rain shafts", func(): return fx.atmosphere.fog_enabled, func(on): fx.atmosphere.fog_enabled = on)
	_check(b, "Falling rain", func(): return fx.get_node("Rain").process_mode != Node.PROCESS_MODE_DISABLED,
		func(on): _toggle_node(fx.get_node("Rain"), on))
	_choice(b, "Fog debug view", ["Off", "Distances", "Media"], func(): return fx.debug_fog, func(i): fx.debug_fog = i)
	_section(b, "ATMOSPHERE")
	_slider(b, "Milky Way", 0, 3, 0.05, func(): return _tod().milkyway_brightness,
		func(v): _tod().milkyway_brightness = v, "%.2fx")
	_slider(b, "Night brightness (eye)", 2, 12, 0.5, func(): return _tod().night_exposure,
		func(v): _tod().night_exposure = v, "%.1fx")
	_section(b, "CAMERA")
	var cam: Camera3D = world.get_node("CameraRig")
	_slider(b, "Cockpit field of view", 30, 100, 1, func(): return cam.cockpit_fov, _set_cockpit_fov, "%.0f°")
	_readout(b, func(): return "FPS %d   Draw calls %d" % [Engine.get_frames_per_second(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])


func _toggle_node(n: Node3D, on: bool) -> void:
	n.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	n.visible = on


func _set_cockpit_fov(v: float) -> void:
	var cam: Camera3D = world.get_node("CameraRig")
	cam.cockpit_fov = v
	if cam.mode == cam.Mode.COCKPIT:
		cam.fov = v


func _tab_debug() -> void:
	var b := _tab("Debug")
	_check(b, "Flight data overlay", func(): return world.get_node("DebugOverlay").visible,
		func(on): world.get_node("DebugOverlay").visible = on)
	_check(b, "Checklist", func(): return world.get_node("Checklist").visible, func(on): world.get_node("Checklist").visible = on)
	_check(b, "Key help", func(): return world.get_node("Help").visible, func(on): world.get_node("Help").visible = on)
	_buttons(b, [["Restart checklist", func(): world.get_node("Checklist").reset()],
		["Print state to log", func(): _dump()]])
	_readout(b, func():
		var f := _ac().fdm
		var p := _ac().global_position
		return "Position (%.0f, %.0f, %.0f) m   AGL %.0f ft   Surface %s\nPhysics %d Hz   Engine time scale %.2f" % [
			p.x, p.y, p.z, f.prop_get("position/h-agl-ft"), f.surface, Engine.physics_ticks_per_second, Engine.time_scale])


func _dump() -> void:
	var f := _ac().fdm
	var keys := ["velocities/vc-kts", "position/h-sl-ft", "position/h-agl-ft", "attitude/theta-deg", "attitude/phi-deg",
		"attitude/psi-deg", "aero/alpha-deg", "aero/beta-deg", "propulsion/engine/engine-rpm", "inertia/weight-lbs",
		"atmosphere/wind-north-fps", "atmosphere/wind-east-fps", "atmosphere/density-altitude"]
	var out := "STATE " + _ac().definition.display_name + " " + _tod().clock_text() + " " + _weather().summary()
	for k in keys:
		out += "\n  %s = %.3f" % [k, f.prop_get(k)]
	print(out)
	_say("State printed to the log.")
