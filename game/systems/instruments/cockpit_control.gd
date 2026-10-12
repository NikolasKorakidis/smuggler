class_name CockpitControl
extends Node3D
## A clickable cockpit control bound to the aircraft's EngineSystems.
## Left click operates it (Shift+click goes the other way), the mouse wheel
## turns knobs. Faces +Z like the instruments. Hit-tested by the camera rig
## in aircraft space (not physics), so it stays exact at any airspeed.

enum Style { ROTARY, TOGGLE, PUSH_PULL }

## magnetos, master, primer, mixture, carb_heat, fuel_selector, parking_brake, flaps, kollsman,
## landing_light, nav_lights, panel_lights
@export var control := "magnetos"
@export var label := ""
@export var knob_color := Color(0.12, 0.12, 0.12)
@export var size_m := 0.03
## Period hardware instead of plain shapes: bakelite knobs, brass and chrome,
## position marks engraved on the escutcheon, label in dark ink for a placard.
@export var vintage := false

var aircraft: Aircraft
var _style := Style.ROTARY
var _moving: Node3D
var _labels: Array[Label3D] = []
var _highlight: StandardMaterial3D
var _hover := false
var _pull := 0.0  # primer animation
var _model_meshes: Array[MeshInstance3D] = []  # knob from the aircraft's 3D model, if it has one
var _hover_overlay: StandardMaterial3D


func _ready() -> void:
	var n := get_parent()
	while n != null and not (n is Aircraft):
		n = n.get_parent()
	aircraft = n
	match control:
		"magnetos", "fuel_selector":
			_style = Style.ROTARY
		"master", "flaps", "landing_light", "nav_lights", "panel_lights":
			_style = Style.TOGGLE
		"kollsman":
			_style = Style.ROTARY
		_:
			_style = Style.PUSH_PULL
	_build()


func _engine() -> EngineSystems:
	return aircraft.engine if aircraft else null


# --- interaction (called by the camera rig) ---------------------------------

## Distance along a ray given in this control's local space, or -1 on a miss.
func hit(from: Vector3, dir: Vector3) -> float:
	var box := AABB(Vector3(-size_m * 0.8, -size_m * 0.8, -size_m * 0.3), Vector3(size_m * 1.6, size_m * 1.6, size_m * 1.4))
	var p = box.intersects_ray(from, dir)
	return -1.0 if p == null else from.distance_to(p)


const LIGHTS := {"landing_light": "landing", "nav_lights": "nav", "panel_lights": "panel"}


func press(reverse: bool) -> void:
	if control in LIGHTS:
		aircraft.toggle_light(LIGHTS[control])
		return
	if control == "parking_brake":
		FlightInput.parking_brake = not FlightInput.parking_brake
		return
	if control == "flaps":
		aircraft.set_flap_notch(aircraft.flap_notch + (-1 if reverse else 1))
		return
	if control == "kollsman":
		_turn_kollsman(-0.01 if reverse else 0.01)
		return
	var e := _engine()
	if e == null:
		return
	match control:
		"magnetos":
			if reverse:
				e.set_magnetos(e.magnetos - 1)
			elif e.magnetos == 3 and e.definition.has_starter:
				e.click_starter = true  # spring-loaded START while held
			elif e.magnetos == 3:
				e.set_starter(true)  # no key: swing the prop
			else:
				e.set_magnetos(e.magnetos + 1)
		"master":
			e.set_master(not e.master)
		"primer":
			e.stroke_primer()
			_pull = 1.0
		"mixture":
			e.set_mixture(0.0 if e.mixture > 0.5 else 1.0)
		"carb_heat":
			e.set_carb_heat(not e.carb_heat)
		"fuel_selector":
			var n := e.definition.fuel_positions.size()
			e.set_fuel_selector(posmod(e.fuel_selector + (-1 if reverse else 1), n))


func release() -> void:
	var e := _engine()
	if e:
		e.click_starter = false


func scroll(dir: int) -> void:
	if control == "kollsman":
		_turn_kollsman(0.01 * dir * (10.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0))
		return
	if control == "flaps":
		aircraft.set_flap_notch(aircraft.flap_notch - dir)  # wheel up = flaps up
		return
	var e := _engine()
	if e == null:
		return
	match control:
		"mixture":
			e.set_mixture(e.mixture + 0.05 * dir)
		"magnetos":
			e.set_magnetos(e.magnetos + dir)
		"fuel_selector":
			e.set_fuel_selector(clampi(e.fuel_selector + dir, 0, e.definition.fuel_positions.size() - 1))
		_:
			press(dir < 0)


func _turn_kollsman(step: float) -> void:
	aircraft.altimeter_setting_inhg = clampf(snappedf(aircraft.altimeter_setting_inhg + step, 0.01), 28.0, 31.0)
	_moving.rotation.z -= step * 30.0


func set_hover(on: bool) -> void:
	_hover = on
	_highlight.emission_enabled = on
	for mi in _model_meshes:
		mi.material_overlay = _hover_overlay if on else null


func tooltip() -> String:
	if control in LIGHTS:
		var on: bool = aircraft.lights[LIGHTS[control]]
		var keys := {"landing_light": "Ctrl+L", "nav_lights": "Ctrl+N", "panel_lights": "Ctrl+P"}
		var power := "" if aircraft.engine.powered() else "   — no power: MASTER is off"
		return "%s: %s   (click, or %s)%s" % [label, "ON" if on else "OFF", keys[control], power]
	if control == "parking_brake":
		return "%s: %s   (click, or press .)" % [label, "SET (pulled)" if FlightInput.parking_brake else "RELEASED"]
	if control == "kollsman":
		return "%s: %.2f inHg   (wheel: ±0.01 · shift+wheel: ±0.10)" % [label, aircraft.altimeter_setting_inhg]
	if control == "flaps":
		return "%s: %d°   (click: down · shift+click: up · or G / T)" % [label, aircraft.flap_notch_degrees(aircraft.flap_notch)]
	var e := _engine()
	if e == null:
		return label
	match control:
		"magnetos":
			var pos: String = "START" if e.starter or e.click_starter else EngineSystems.MAGNETO_NAMES[e.magnetos]
			if e.cranking() and not e.running():
				return "%s: START — cranking… not firing yet (keep holding; cold engine needs primer)" % label
			if e.running() and (e.starter or e.click_starter):
				return "%s: START — ENGINE RUNNING, let go now" % label
			var hint := "click: next · shift+click: back"
			if e.magnetos == 3:
				hint = "hold click: START" if e.definition.has_starter else "click: swing the prop"
			elif e.magnetos == 0 and not e.definition.has_starter:
				hint = "click: switch on · Enter with switch OFF pulls the prop through"
			return "%s: %s   (%s)" % [label, pos, hint]
		"master":
			return "%s: %s" % [label, "ON" if e.master else "OFF"]
		"primer":
			return "%s: %.1f strokes in   (click: one stroke)" % [label, e.prime]
		"mixture":
			var m := "RICH" if e.mixture > 0.95 else ("CUT-OFF" if e.mixture < 0.05 else "%d%%" % int(e.mixture * 100))
			return "%s: %s   (wheel: lean/enrich · click: rich/cut-off)" % [label, m]
		"carb_heat":
			return "%s: %s" % [label, "ON (pulled)" if e.carb_heat else "OFF"]
		"fuel_selector":
			return "%s: %s" % [label, e.definition.fuel_positions[e.fuel_selector]]
	return label


# --- visuals ----------------------------------------------------------------

func _process(delta: float) -> void:
	var e := _engine()
	if e == null or _moving == null:
		return
	match control:
		"magnetos":
			var step := 4 if (e.starter or e.click_starter) else e.magnetos
			_moving.rotation.z = -deg_to_rad(_magneto_angle(step))
		"fuel_selector":
			_moving.rotation.z = -deg_to_rad(_rotary_angle(e.fuel_selector, e.definition.fuel_positions.size()))
		"master":
			_moving.rotation.x = deg_to_rad(-20.0 if e.master else 20.0)
		"landing_light", "nav_lights", "panel_lights":
			_moving.rotation.x = deg_to_rad(-20.0 if aircraft.lights[LIGHTS[control]] else 20.0)
		"mixture":
			_moving.position.z = size_m * 0.4 + (1.0 - e.mixture) * size_m * 1.2
		"carb_heat":
			_moving.position.z = size_m * 0.4 + (size_m * 1.2 if e.carb_heat else 0.0)
		"flaps":
			var n := maxi(aircraft.definition.flap_detents.size() - 1, 1)
			_moving.position.y = size_m * (0.6 - 1.2 * aircraft.flap_notch / float(n))
		"parking_brake":
			_moving.position.z = size_m * 0.4 + (size_m * 1.2 if FlightInput.parking_brake else 0.0)
		"primer":
			_pull = maxf(_pull - delta * 3.0, 0.0)
			_moving.position.z = size_m * 0.4 + sin(_pull * PI) * size_m * 1.5


func _rotary_angle(i: int, n: int) -> float:
	return -90.0 + 180.0 * i / maxf(n - 1, 1)


func _magneto_angle(i: int) -> float:
	return -80.0 + 40.0 * i


func _build() -> void:
	_highlight = StandardMaterial3D.new()
	_highlight.albedo_color = knob_color
	_highlight.roughness = 0.5
	_highlight.emission = Color(0.9, 0.7, 0.3)
	_highlight.emission_energy_multiplier = 0.6
	_moving = Node3D.new()
	add_child(_moving)
	if vintage and _adopt_model_knob():
		return
	if vintage:
		_build_vintage()
		return
	var r := size_m * 0.5
	match _style:
		Style.ROTARY:
			var knob := _mesh_cyl(r * 0.7, r * 0.6)
			knob.position.z = r * 0.3
			_moving.add_child(knob)
			var pointer := MeshInstance3D.new()
			var pb := BoxMesh.new()
			pb.size = Vector3(r * 0.22, r * 1.5, r * 0.4)
			pointer.mesh = pb
			pointer.material_override = _highlight
			pointer.position = Vector3(0, r * 0.35, r * 0.7)
			_moving.add_child(pointer)
			var names: PackedStringArray
			if control == "kollsman":
				names = PackedStringArray()
			elif control == "magnetos":
				names = PackedStringArray(EngineSystems.MAGNETO_NAMES)
				if _engine() and _engine().definition.has_starter:
					names.append("START")
			else:
				names = _engine().definition.fuel_positions if _engine() else PackedStringArray()
			for i in names.size():
				var a := _magneto_angle(i) if control == "magnetos" else _rotary_angle(i, names.size())
				_add_label(names[i], GaugeBase.dir_cw(a) * Vector2(1, -1) * r * 2.1, r * 0.42)
		Style.TOGGLE:
			var base := _mesh_box(Vector3(r * 1.2, r * 1.8, r * 0.3), Color(0.08, 0.08, 0.08))
			add_child(base)
			var lever := MeshInstance3D.new()
			var lb := BoxMesh.new()
			lb.size = Vector3(r * 0.9, r * 1.4, r * 0.6)
			lever.mesh = lb
			lever.material_override = _highlight
			lever.position.z = r * 0.4
			_moving.add_child(lever)
			if control == "flaps":
				var n := aircraft.definition.flap_detents.size() if aircraft else 1
				for i in n:
					var y := r * (1.2 - 2.4 * i / float(maxi(n - 1, 1)))
					_add_label("%d" % (aircraft.flap_notch_degrees(i) if aircraft else 0), Vector2(r * 1.6, y), r * 0.45)
			else:
				_add_label("ON", Vector2(0, r * 1.5), r * 0.55)
				_add_label("OFF", Vector2(0, -r * 1.5), r * 0.55)
		Style.PUSH_PULL:
			var shaft := _mesh_cyl(r * 0.2, size_m * 1.6, Color(0.6, 0.6, 0.6))
			shaft.position.z = size_m * 0.8
			add_child(shaft)
			var knob := _mesh_cyl(r * 0.8, r * 0.7)
			_moving.add_child(knob)
			_moving.position.z = size_m * 0.4
	_add_label(label, Vector2(0, -r * 1.9), r * 0.5)


# The aircraft model can supply the knob (a node named Knob_<control>, pivot on the panel
# face, pointing at 12 o'clock) with its own placard: then this node only animates it.
func _adopt_model_knob() -> bool:
	if aircraft == null or aircraft.airframe == null:
		return false
	var knob := aircraft.airframe.find_child("Knob_" + control, true, false) as Node3D
	if knob == null:
		return false
	if _style == Style.PUSH_PULL:
		_moving.position.z = size_m * 0.4  # rest offset the animation adds to
	knob.reparent(_moving, true)
	for mi in knob.find_children("*", "MeshInstance3D", true, false):
		_model_meshes.append(mi)
	_hover_overlay = StandardMaterial3D.new()
	_hover_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hover_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hover_overlay.albedo_color = Color(1.0, 0.8, 0.4, 0.25)
	return true


func _build_vintage() -> void:
	var r := size_m * 0.5
	_highlight.roughness = 0.3  # bakelite
	var brass := _metal(Color(0.62, 0.5, 0.28), 0.45)
	var chrome := _metal(Color(0.7, 0.7, 0.68), 0.3)
	var mark := Color(0.16, 0.13, 0.1)
	match control:
		"magnetos":
			# Brass escutcheon with engraved positions; black key knob with a pointer bar.
			add_child(_part(_cyl_mesh(r * 1.25, r * 0.12, 32), brass, Vector3(0, 0, r * 0.06)))
			_moving.add_child(_part(_cyl_mesh(r * 0.6, r * 0.5, 24), _highlight, Vector3(0, 0, r * 0.35)))
			var bar := BoxMesh.new()
			bar.size = Vector3(r * 0.42, r * 1.7, r * 0.7)
			_moving.add_child(_part(bar, _highlight, Vector3(0, 0, r * 0.8), false))
			var tip := BoxMesh.new()
			tip.size = Vector3(r * 0.12, r * 0.7, r * 0.05)
			_moving.add_child(_part(tip, _metal(GaugeBase.CREAM, 0.6), Vector3(0, r * 0.45, r * 1.16), false))
			var names := PackedStringArray(EngineSystems.MAGNETO_NAMES)
			if _engine() and _engine().definition.has_starter:
				names.append("START")
			for i in names.size():
				_add_label(names[i], GaugeBase.dir_cw(_magneto_angle(i)) * Vector2(1, -1) * r * 0.98, r * 0.22, mark, r * 0.13)
		"fuel_selector":
			# Brass valve body, lever handle pointing at ON or OFF.
			add_child(_part(_cyl_mesh(r * 0.55, r * 0.6, 16), brass, Vector3(0, 0, r * 0.3)))
			var lever := BoxMesh.new()
			lever.size = Vector3(r * 0.35, r * 2.0, r * 0.25)
			_moving.add_child(_part(lever, _highlight, Vector3(0, r * 0.75, r * 0.7), false))
			var names := _engine().definition.fuel_positions if _engine() else PackedStringArray()
			for i in names.size():
				_add_label(names[i], GaugeBase.dir_cw(_rotary_angle(i, names.size())) * Vector2(1, -1) * r * 2.1, r * 0.4, GaugeBase.CREAM)
		"kollsman":
			var knob := _cyl_mesh(r * 0.7, r * 0.9, 20)  # knurled setting knob
			_moving.add_child(_part(knob, _highlight, Vector3(0, 0, r * 0.45)))
		_:
			# Push-pull: chrome hex nut and shaft, black bakelite pull knob.
			add_child(_part(_cyl_mesh(r * 0.55, r * 0.35, 6), chrome, Vector3(0, 0, r * 0.18)))
			add_child(_part(_cyl_mesh(r * 0.16, size_m * 1.6, 12), chrome, Vector3(0, 0, size_m * 0.8)))
			var knob := SphereMesh.new()
			knob.radius = r * 0.85
			knob.height = r * 1.1
			_moving.add_child(_part(knob, _highlight, Vector3.ZERO))
			_moving.position.z = size_m * 0.4
	_add_label(label, Vector2(0, -r * 2.2), r * 0.42, mark, 0.004)  # on the placard


func _cyl_mesh(radius: float, height: float, segments: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segments
	return c


# A mesh part facing the pilot (+Z); cylinders and spheres are turned to lie along Z.
func _part(mesh: Mesh, mat: Material, at: Vector3, along_z := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	if along_z:
		mi.rotation.x = PI / 2
	mi.position = at
	return mi


func _metal(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.85
	m.roughness = rough
	return m


func _mesh_cyl(radius: float, height: float, color := Color(-1, 0, 0)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	mi.mesh = c
	mi.rotation.x = PI / 2
	if color.r < 0.0:
		mi.material_override = _highlight
	else:
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.metallic = 0.6
		mi.material_override = m
	return mi


func _mesh_box(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	mi.material_override = m
	return mi


func _add_label(text: String, at: Vector2, height_m: float, color := Color(0.92, 0.92, 0.88), z := 0.001) -> void:
	if text == "":
		return
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = height_m / 48.0
	l.modulate = color
	l.outline_size = 0
	l.position = Vector3(at.x, at.y, z)
	l.shaded = false
	l.double_sided = false
	add_child(l)
	_labels.append(l)
