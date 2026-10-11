class_name GaugeBase
extends Node3D
## A panel instrument: bezel + face(s) drawn by 2D Controls into textures,
## plus 3D needles. The gauge faces +Z (towards the pilot). Reads values from
## the JSBSim FDM of the Aircraft it sits in.

const FACE_PX := 320

## Instrument size; 0.08 m is the standard 3 1/8" hole, 0.057 m is 2 1/4".
@export var diameter_m := 0.08

var aircraft: Aircraft


func _ready() -> void:
	aircraft = _find_aircraft()
	_build_bezel()
	_build()


## Subclasses build their faces and needles here.
func _build() -> void:
	pass


func prop(name: String) -> float:
	if aircraft == null or aircraft.fdm == null or aircraft.fdm.jsb == null:
		return 0.0
	return aircraft.fdm.prop_get(name)


func has_prop(name: String) -> bool:
	return aircraft != null and aircraft.fdm.jsb != null and aircraft.fdm.jsb.has_property(name)


## Adds a face rendered from `control`. Faces drawn once are cheap; animated
## faces (attitude, compass) redraw every frame.
func add_face(control: Control, animated := false, z := 0.0, size := Vector2.ZERO) -> MeshInstance3D:
	var quad_size := size if size != Vector2.ZERO else Vector2(diameter_m, diameter_m)
	var px := Vector2i(FACE_PX, int(FACE_PX * quad_size.y / quad_size.x))
	var vp := SubViewport.new()
	vp.size = px
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if animated else SubViewport.UPDATE_ONCE
	control.size = Vector2(px)
	vp.add_child(control)
	add_child(vp)

	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = quad_size
	quad.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = vp.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.roughness = 0.5
	mat.emission_enabled = true
	mat.emission_texture = vp.get_texture()
	mat.emission_energy_multiplier = 0.3
	quad.material_override = mat
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.position.z = z
	add_child(quad)
	return quad


## A needle pivoting at the centre. Rotate the returned node with set_angle().
func add_needle(length_frac := 0.8, width_m := 0.0028, color := Color(0.95, 0.95, 0.9), z := 0.002) -> Node3D:
	var pivot := Node3D.new()
	pivot.position.z = z
	add_child(pivot)
	var length := diameter_m * 0.5 * length_frac
	var needle := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width_m, length * 1.15, 0.0008)
	needle.mesh = box
	needle.position = Vector3(0, length * 0.5 - length * 0.15, 0)
	needle.material_override = _unshaded(color)
	needle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(needle)
	var hub := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = width_m * 1.6
	cyl.bottom_radius = width_m * 1.6
	cyl.height = 0.002
	hub.mesh = cyl
	hub.rotation.x = PI / 2
	hub.material_override = _unshaded(Color(0.1, 0.1, 0.1))
	pivot.add_child(hub)
	return pivot


## Angle in degrees clockwise from 12 o'clock, as seen by the pilot.
static func set_angle(needle: Node3D, deg_cw: float) -> void:
	needle.rotation.z = -deg_to_rad(deg_cw)


func _build_bezel() -> void:
	var bezel := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = diameter_m * 0.56
	cyl.bottom_radius = diameter_m * 0.56
	cyl.height = 0.012
	cyl.radial_segments = 32
	bezel.mesh = cyl
	bezel.rotation.x = PI / 2
	bezel.position.z = -0.0065
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.05)
	mat.roughness = 0.4
	bezel.material_override = mat
	add_child(bezel)


func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _find_aircraft() -> Aircraft:
	var n := get_parent()
	while n != null and not (n is Aircraft):
		n = n.get_parent()
	return n


## Drawing helpers shared by faces.
static func draw_text_centered(ci: CanvasItem, pos: Vector2, text: String, font_size: int, color := Color.WHITE) -> void:
	var font := ThemeDB.fallback_font
	var s := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	ci.draw_string(font, pos + Vector2(-s.x * 0.5, s.y * 0.32), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Direction for an angle clockwise from 12 o'clock, in 2D screen space.
static func dir_cw(deg_cw: float) -> Vector2:
	var a := deg_to_rad(deg_cw - 90.0)
	return Vector2(cos(a), sin(a))
