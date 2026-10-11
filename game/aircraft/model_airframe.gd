extends Node3D
## Root of an imported aircraft model (AircraftDefinition.visual_scene), driven
## by the FDM. The model is authored in the JSBSim structural frame converted to
## Godot axes (Geo.struct_to_local). Node names it looks for, all optional:
##   Hinge_aileron_L/R, Hinge_elevator, Hinge_rudder, Hinge_flap_L/R:
##       turn about their local X axis; positive JSBSim deflection = positive
##       rotation (trailing edge down; author the rudder hinge with local X down).
##   Prop: spins about local Z. Prop/Blades shown when slow, Prop/Disc when fast.
##   Wheel_*: at the axle; matched to the nearest JSBSim gear unit, spins and
##       follows the strut compression.
##   Steer_*: turns about local Y with the matching gear unit's steering angle.

const SURFACES := {
	"Hinge_aileron_L": "fcs/left-aileron-pos-rad",
	"Hinge_aileron_R": "fcs/right-aileron-pos-rad",
	"Hinge_elevator": "fcs/elevator-pos-rad",
	"Hinge_rudder": "fcs/rudder-pos-rad",
	"Hinge_flap_L": "fcs/flap-pos-rad",
	"Hinge_flap_R": "fcs/flap-pos-rad",
}

var _fdm: FDM
var _surfaces: Array[Dictionary] = []  # {node, rest, prop}
var _wheels: Array[Dictionary] = []  # {node, rest, unit, radius}
var _steers: Array[Dictionary] = []  # {node, rest, unit}
var _prop: Node3D
var _blades: Node3D
var _disc: Node3D


func _ready() -> void:
	var aircraft := get_parent()
	if aircraft == null or not "fdm" in aircraft:
		return
	_fdm = aircraft.fdm
	var def: AircraftDefinition = aircraft.definition
	for node_name in SURFACES:
		var n := find_child(node_name, true, false) as Node3D
		if n and _fdm.jsb.has_property(SURFACES[node_name]):
			_surfaces.append({"node": n, "rest": n.basis, "prop": SURFACES[node_name]})
	_prop = find_child("Prop", true, false) as Node3D
	if _prop:
		_blades = _prop.find_child("Blades", true, false) as Node3D
		_disc = _prop.find_child("Disc", true, false) as Node3D
	var gear := _fdm.wheels()
	for n in find_children("Wheel_*", "Node3D", true, false):
		var g := _nearest_gear(n, gear)
		if not g.is_empty():
			var contact: Vector3 = Geo.struct_to_local(g.pos.x, g.pos.y, g.pos.z)
			_wheels.append({"node": n, "rest": n.position, "unit": g.index,
				"radius": maxf(to_local(n.global_position).y - contact.y, 0.02)})
	for n in find_children("Steer_*", "Node3D", true, false):
		var g := _nearest_gear(n, gear)
		if not g.is_empty():
			_steers.append({"node": n, "rest": n.basis, "unit": g.index})
	_add_cockpit(def)


func _process(delta: float) -> void:
	if _fdm == null or _fdm.jsb == null:
		return
	for s in _surfaces:
		s.node.basis = s.rest * Basis(Vector3.RIGHT, _fdm.prop_get(s.prop))
	if _prop:
		var rpm := _fdm.prop_get("propulsion/engine/propeller-rpm")
		var spinning := rpm > 350.0
		if _disc:
			_disc.visible = spinning
		if _blades:
			_blades.visible = not spinning
		if not spinning:
			_prop.rotate_object_local(Vector3.BACK, -rpm / 60.0 * TAU * delta)
	for w in _wheels:
		var base := "gear/unit[%d]/" % w.unit
		w.node.position = w.rest + Vector3(0, _fdm.prop_get(base + "compression-ft") * 0.3048, 0)
		var fps := _fdm.prop_get(base + "wheel-speed-fps")
		w.node.rotate_object_local(Vector3.RIGHT, -fps * 0.3048 / w.radius * delta)
	for s in _steers:
		var deg := _fdm.prop_get("gear/unit[%d]/steering-angle-deg" % s.unit)
		s.node.basis = s.rest * Basis(Vector3.UP, -deg_to_rad(deg))


## Bottom of each wheel in world space: [{unit, point}]. Shared with placeholder_airframe.gd.
func wheel_contacts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for w in _wheels:
		out.append({"unit": w.unit, "point": w.node.global_position - global_basis.y * w.radius})
	return out


func _nearest_gear(n: Node3D, gear: Array[Dictionary]) -> Dictionary:
	var p := to_local(n.global_position)
	var best := {}
	var best_d := INF
	for g in gear:
		var c: Vector3 = Geo.struct_to_local(g.pos.x, g.pos.y, g.pos.z)
		var d := Vector2(p.x - c.x, p.z - c.z).length()
		if d < best_d:
			best_d = d
			best = g
	return best


# Eyepoint marker for the cockpit camera and the instrument panel, as the
# placeholder airframe does.
func _add_cockpit(def: AircraftDefinition) -> void:
	var marker := Marker3D.new()
	marker.name = "Eyepoint"
	marker.position = Geo.struct_to_local(_fdm.prop_get("metrics/eyepoint-x-in"),
		_fdm.prop_get("metrics/eyepoint-y-in"), _fdm.prop_get("metrics/eyepoint-z-in"))
	add_child(marker)
	if def.panel_scene:
		var panel := def.panel_scene.instantiate()
		panel.position = marker.position
		add_child(panel)
