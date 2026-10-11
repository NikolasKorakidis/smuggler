extends Node3D
## Exterior and cockpit lights for aircraft with electrics: landing light in
## the nose, red/green wingtip and white tail nav lights with a flashing red
## beacon, and a red cockpit flood for the panel. Positions come from the
## JSBSim data (structural frame), like the placeholder airframe.

var aircraft: Aircraft
var _landing: SpotLight3D
var _nav: Array[Node3D] = []
var _beacon: Node3D
var _beacon_light: OmniLight3D
var _flood: OmniLight3D
var _t := 0.0


func build(ac: Aircraft) -> void:
	aircraft = ac
	var f := ac.fdm
	var span := f.prop_get("metrics/bw-ft") * 12.0
	var chord := f.prop_get("metrics/cbarw-ft") * 12.0
	var rp := Vector3(f.prop_get("metrics/aero-rp-x-in"), 0, f.prop_get("metrics/aero-rp-z-in"))
	var nose := Vector3(f.prop_get("propulsion/engine/x-position"), 0, f.prop_get("propulsion/engine/z-position"))
	var tail_x := rp.x + f.prop_get("metrics/lv-ft") * 12.0
	var fin_h := sqrt(f.prop_get("metrics/Sv-sqft") * 144.0 * 1.4)

	_landing = SpotLight3D.new()
	_landing.name = "LandingLight"
	_landing.position = _p(nose.x + 10.0, 0.0, nose.z - 10.0)
	_landing.rotation.x = deg_to_rad(-5.0)  # aimed down so it lights the strip ahead
	_landing.spot_range = 320.0
	_landing.spot_angle = 18.0
	_landing.spot_attenuation = 0.8
	_landing.light_energy = 22.0
	_landing.light_color = Color(1.0, 0.95, 0.85)
	_landing.shadow_enabled = false
	add_child(_landing)

	_nav.append(_bulb(_p(rp.x, -span * 0.5, rp.z + 2.0), Color(1.0, 0.1, 0.08)))  # left red
	_nav.append(_bulb(_p(rp.x, span * 0.5, rp.z + 2.0), Color(0.1, 1.0, 0.25)))  # right green
	_nav.append(_bulb(_p(tail_x + 0.6 * sqrt(f.prop_get("metrics/Sv-sqft") * 144.0 / 1.4), 0.0, nose.z + fin_h * 0.6), Color(1, 1, 1)))
	_beacon = _bulb(_p(tail_x, 0.0, nose.z + fin_h + 1.5), Color(1.0, 0.1, 0.05))
	_beacon_light = _beacon.get_child(1)

	var eye := Vector3(f.prop_get("metrics/eyepoint-x-in"), f.prop_get("metrics/eyepoint-y-in"), f.prop_get("metrics/eyepoint-z-in"))
	_flood = OmniLight3D.new()
	_flood.name = "PanelFlood"
	_flood.position = _p(eye.x - 14.0, eye.y + 14.0, eye.z + 6.0)
	_flood.omni_range = 0.9
	_flood.light_color = Color(1.0, 0.35, 0.25)  # red cockpit light keeps night vision
	_flood.light_energy = 0.0
	add_child(_flood)
	_update()


func _process(delta: float) -> void:
	_t += delta
	_update()


func _update() -> void:
	if aircraft == null:
		return
	_landing.visible = aircraft.light_on("landing")
	var nav := aircraft.light_on("nav")
	for b in _nav:
		b.visible = nav
	# Beacon: a red flash about once a second.
	_beacon.visible = nav and fmod(_t, 1.1) < 0.12
	_flood.light_energy = 0.9 if aircraft.light_on("panel") else 0.0


func _bulb(pos: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var mesh := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.05
	s.height = 0.1
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 8.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s.material = m
	mesh.mesh = s
	root.add_child(mesh)
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = 1.2
	light.light_energy = 0.35
	light.shadow_enabled = false
	root.add_child(light)
	return root


func _p(x_in: float, y_in: float, z_in: float) -> Vector3:
	return Geo.struct_to_local(x_in, y_in, z_in)
