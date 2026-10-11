extends Node3D
## Box-and-cylinder stand-in for an aircraft, sized from its JSBSim data
## (wing, tail areas, gear, thruster, eyepoint). Lives in the structural frame
## so it lines up with the physics exactly. Replaced by real models later.

const IN := 0.0254

var _fdm: FDM
var _wheels: Array[Node3D] = []
var _wheel_rest: Array[Vector3] = []
var _wheel_units: Array[int] = []
var _prop: Node3D
var _flaps: Array[Node3D] = []
var _blades: Array[Node3D] = []
var _disc: MeshInstance3D


func build(fdm: FDM, def: AircraftDefinition) -> void:
	_fdm = fdm
	var body := _mat(def.body_color, 0.75)
	var trim := _mat(def.trim_color, 0.6)
	var dark := _mat(Color(0.08, 0.08, 0.08), 0.9)

	var span := fdm.prop_get("metrics/bw-ft") * 12.0
	var chord := fdm.prop_get("metrics/cbarw-ft") * 12.0
	var rp := Vector3(fdm.prop_get("metrics/aero-rp-x-in"), 0, fdm.prop_get("metrics/aero-rp-z-in"))
	var nose_x := fdm.prop_get("propulsion/engine/x-position")
	var nose_z := fdm.prop_get("propulsion/engine/z-position")
	var htail_x := rp.x + fdm.prop_get("metrics/lh-ft") * 12.0
	var vtail_x := rp.x + fdm.prop_get("metrics/lv-ft") * 12.0
	var sh := fdm.prop_get("metrics/Sh-sqft") * 144.0
	var sv := fdm.prop_get("metrics/Sv-sqft") * 144.0

	# Fuselage: cabin box from the nose to the wing trailing edge, then a tapered boom.
	var cabin_top := rp.z
	var cabin_bottom := nose_z - 16.0
	var cabin_end := rp.x + 0.9 * chord
	var cabin_h := cabin_top - cabin_bottom
	_box(Vector3(nose_x + 6.0, 0, cabin_bottom), Vector3(cabin_end, 0, cabin_top), 28.0, body)
	var tail_end := htail_x + 0.5 * sqrt(sh / 3.5)
	var tail_z := nose_z
	var front := _p(cabin_end, 0, 0.5 * (cabin_top + cabin_bottom))
	var back := _p(tail_end, 0, tail_z + 4.0)
	var boom := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.radial_segments = 4
	cyl.rings = 1
	cyl.bottom_radius = 0.6 * cabin_h * IN
	cyl.top_radius = 4.0 * IN
	cyl.height = front.distance_to(back)
	boom.mesh = cyl
	boom.material_override = body
	# Cylinder axis (+Y, small end) points aft along the boom; flat sides up.
	boom.transform = Transform3D(
		Basis.looking_at(back - front) * Basis(Vector3.RIGHT, -PI / 2) * Basis(Vector3.UP, PI / 4),
		(front + back) * 0.5)
	add_child(boom)
	# Cowling
	_box(Vector3(nose_x, 0, nose_z - 12.0), Vector3(nose_x + 14.0, 0, nose_z + 12.0), 26.0, trim)

	# Wing (quarter chord on the aero reference point)
	_box(Vector3(rp.x - 0.25 * chord, 0, rp.z), Vector3(rp.x + 0.75 * chord, 0, rp.z + 5.0), span, body)
	# Flaps: inboard trailing-edge panels hinged at their front edge.
	if not def.flap_detents.is_empty():
		var flap_chord := 0.25 * chord
		var hinge_x := rp.x + 0.75 * chord - flap_chord
		for side in [-1.0, 1.0]:
			var hinge := Node3D.new()
			hinge.position = _p(hinge_x, side * span * 0.21, rp.z)
			add_child(hinge)
			var panel := MeshInstance3D.new()
			var pb := BoxMesh.new()
			pb.size = Vector3(span * 0.3, 2.5, flap_chord) * IN
			panel.mesh = pb
			panel.material_override = trim
			panel.position = Vector3(0, -0.6 * IN, flap_chord * 0.5 * IN + 0.01)
			hinge.add_child(panel)
			_flaps.append(hinge)
	for side in [-1.0, 1.0]:
		_rod(Vector3(rp.x, side * 12.0, cabin_bottom + 4.0), Vector3(rp.x, side * span * 0.3, rp.z), 1.5, trim)

	# Tail
	var hspan := sqrt(sh * 3.5)
	var hchord := sh / hspan
	_box(Vector3(htail_x - 0.25 * hchord, 0, tail_z), Vector3(htail_x + 0.75 * hchord, 0, tail_z + 2.0), hspan, trim)
	var vh := sqrt(sv * 1.4)
	var vchord := sv / vh
	_box(Vector3(vtail_x - 0.25 * vchord, 0, tail_z), Vector3(vtail_x + 0.75 * vchord, 0, tail_z + vh), 2.0, trim)

	# Gear
	var fuselage_bottom := cabin_bottom
	for wheel_data in fdm.wheels():
		var w: Vector3 = wheel_data.pos
		var r := 10.0 if absf(w.y) > 1.0 else 4.0
		var wheel := MeshInstance3D.new()
		var tyre := CylinderMesh.new()
		tyre.top_radius = r * IN
		tyre.bottom_radius = r * IN
		tyre.height = (5.0 if r > 5.0 else 2.5) * IN
		wheel.mesh = tyre
		wheel.material_override = dark
		wheel.rotation = Vector3(0, 0, PI / 2)
		var centre := Vector3(w.x, w.y, w.z + r)
		wheel.position = _p(centre.x, centre.y, centre.z)
		add_child(wheel)
		_wheels.append(wheel)
		_wheel_rest.append(wheel.position)
		_wheel_units.append(wheel_data.index)
		var top_z := fuselage_bottom if absf(w.x - rp.x) < chord else tail_z
		_rod(centre, Vector3(w.x + (6.0 if r > 5.0 else 0.0), w.y * 0.3, top_z), 1.5, dark)

	# Propeller: spinner + two blades, spun from JSBSim propeller rpm
	_prop = Node3D.new()
	_prop.position = _p(nose_x - 2.0, 0, nose_z)
	add_child(_prop)
	var radius := def.prop_diameter_m * 0.5
	for a in [0.0, PI]:
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(radius, 0.1, 0.02)
		blade.mesh = bm
		blade.material_override = dark
		blade.basis = Basis(Vector3.BACK, a)
		blade.position = Vector3(cos(a), sin(a), 0) * radius * 0.5
		_prop.add_child(blade)
		_blades.append(blade)
	# At running rpm a real prop reads as a faint disc, not a visible blade.
	_disc = MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = radius
	disc_mesh.bottom_radius = radius
	disc_mesh.height = 0.005
	disc_mesh.radial_segments = 48
	_disc.mesh = disc_mesh
	var disc_mat := _mat(Color(0.1, 0.1, 0.1, 0.08), 0.5)
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_disc.material_override = disc_mat
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_disc.rotation.x = PI / 2
	_disc.visible = false
	_prop.add_child(_disc)
	var spinner := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.25
	spinner.mesh = sm
	spinner.material_override = trim
	spinner.rotation = Vector3(PI / 2, 0, 0)
	_prop.add_child(spinner)

	# Cockpit: eyepoint marker for the camera and a plain panel ahead of it.
	var eye := Vector3(fdm.prop_get("metrics/eyepoint-x-in"), fdm.prop_get("metrics/eyepoint-y-in"),
		fdm.prop_get("metrics/eyepoint-z-in"))
	var marker := Marker3D.new()
	marker.name = "Eyepoint"
	marker.position = _p(eye.x, eye.y, eye.z)
	add_child(marker)
	if def.panel_scene:
		var panel := def.panel_scene.instantiate()
		panel.position = marker.position
		add_child(panel)
	else:
		_box(Vector3(eye.x - 40.0, 0, eye.z - 15.0), Vector3(eye.x - 38.0, 0, eye.z - 8.0), 22.0,
			_mat(Color(0.12, 0.11, 0.10), 0.8))


func _process(delta: float) -> void:
	if _fdm == null or _fdm.jsb == null:
		return
	var flap_deg := _fdm.prop_get("fcs/flap-pos-deg") if not _flaps.is_empty() else 0.0
	for h in _flaps:
		h.rotation.x = deg_to_rad(flap_deg)  # trailing edge (aft, +Z) down
	var rpm := _fdm.prop_get("propulsion/engine/propeller-rpm")
	var spinning := rpm > 350.0
	_disc.visible = spinning
	for b in _blades:
		b.visible = not spinning
	if not spinning:
		_prop.rotate_object_local(Vector3.BACK, rpm / 60.0 * TAU * delta)
	for i in _wheels.size():
		var c := _fdm.prop_get("gear/unit[%d]/compression-ft" % _wheel_units[i]) * 12.0
		_wheels[i].position = _wheel_rest[i] + Vector3(0, c * IN, 0)


# --- helpers ----------------------------------------------------------------

func _p(x_in: float, y_in: float, z_in: float) -> Vector3:
	return Geo.struct_to_local(x_in, y_in, z_in)


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


# Box spanning structural x and z ranges, centred on y with the given width (inches).
func _box(a: Vector3, b: Vector3, width_in: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width_in, absf(b.z - a.z), absf(b.x - a.x)) * IN
	mi.mesh = bm
	mi.material_override = mat
	mi.position = _p(0.5 * (a.x + b.x), 0.5 * (a.y + b.y), 0.5 * (a.z + b.z))
	add_child(mi)
	return mi


# Thin rod between two structural points (inches).
func _rod(a: Vector3, b: Vector3, thick_in: float, mat: Material) -> void:
	var pa := _p(a.x, a.y, a.z)
	var pb := _p(b.x, b.y, b.z)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(thick_in * IN, thick_in * IN, pa.distance_to(pb))
	mi.mesh = bm
	mi.material_override = mat
	add_child(mi)
	var mid := (pa + pb) * 0.5
	var up := Vector3.UP if absf((pb - pa).normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	mi.transform = Transform3D(Basis.looking_at(pb - pa, up), mid)
