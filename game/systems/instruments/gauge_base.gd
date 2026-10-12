class_name GaugeBase
extends Node3D
## A panel instrument: bezel + face(s) drawn by 2D Controls into textures,
## plus 3D needles. The gauge faces +Z (towards the pilot). Reads values from
## the JSBSim FDM of the Aircraft it sits in.

const FACE_PX := 320

## Instrument size; 0.08 m is the standard 3 1/8" hole, 0.057 m is 2 1/4".
@export var diameter_m := 0.08
## Worn 1940s look: aged black face, cream numerals, tapered cream needles and a
## glass cover. The bezel and mounting flange come from the aircraft's 3D model.
@export var vintage := false

const CREAM := Color(0.9, 0.82, 0.62)

var aircraft: Aircraft
var _face_mats: Array[StandardMaterial3D] = []


func _ready() -> void:
	aircraft = _find_aircraft()
	if vintage:
		_build_glass()
	else:
		_build_bezel()
	_build()
	if aircraft:
		aircraft.panel_lighting.connect(_on_panel_lighting)


## Subclasses build their faces and needles here.
func _build() -> void:
	pass


func prop(name: String) -> float:
	if aircraft == null or aircraft.fdm == null or aircraft.fdm.jsb == null:
		return 0.0
	return aircraft.fdm.prop_get(name)


## Electrical bus has power (always true for aircraft without a master switch).
func powered() -> bool:
	return aircraft == null or aircraft.engine == null or aircraft.engine.powered()


## Engine-driven vacuum pump turning: gyros spin.
func vacuum() -> bool:
	return prop("propulsion/engine/engine-rpm") > 500.0


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
	if vintage:  # painted, not backlit: a touch of glow keeps it readable in the shade
		mat.roughness = 0.75
		mat.emission_energy_multiplier = 0.08
	quad.material_override = mat
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.position.z = z
	_face_mats.append(mat)
	add_child(quad)
	return quad


# Backlit faces: bright by day, dark at night unless the panel lights are on.
func _on_panel_lighting(level: float) -> void:
	for m in _face_mats:
		m.emission_energy_multiplier = (0.08 if vintage else 0.3) * level


## A needle pivoting at the centre. Rotate the returned node with set_angle().
func add_needle(length_frac := 0.8, width_m := 0.0028, color := Color(0.95, 0.95, 0.9), z := 0.002) -> Node3D:
	var pivot := Node3D.new()
	pivot.position.z = z
	add_child(pivot)
	var length := diameter_m * 0.5 * length_frac
	if vintage:
		pivot.add_child(_tapered_needle(length, width_m * 1.3))
		return pivot
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


# Old-style needle: tapers to a point, short counterweight tail, black hub cap.
func _tapered_needle(length: float, width: float) -> Node3D:
	var root := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tail := length * 0.22
	var pts := [Vector3(-width * 0.5, 0, 0), Vector3(width * 0.5, 0, 0), Vector3(width * 0.12, length, 0),
		Vector3(-width * 0.12, length, 0), Vector3(-width * 0.7, -tail, 0), Vector3(width * 0.7, -tail, 0)]
	for tri in [[0, 1, 2], [0, 2, 3], [4, 5, 1], [4, 1, 0]]:
		for i in tri:
			st.set_normal(Vector3.BACK)
			st.add_vertex(pts[i])
	var needle := MeshInstance3D.new()
	needle.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = CREAM
	m.roughness = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	needle.material_override = m
	needle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(needle)
	var hub := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = width * 1.1
	cyl.bottom_radius = width * 1.3
	cyl.height = 0.0025
	hub.mesh = cyl
	hub.rotation.x = PI / 2
	hub.position.z = 0.0008
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.06, 0.06, 0.06)
	hm.roughness = 0.35
	hub.material_override = hm
	root.add_child(hub)
	return root


# Cover glass: faint reflections and a film of dust over the face.
func _build_glass() -> void:
	var glass := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(diameter_m, diameter_m) * 0.98
	glass.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.83, 0.75, 0.10)
	var dust := NoiseTexture2D.new()
	dust.width = 128
	dust.height = 128
	var n := FastNoiseLite.new()
	n.frequency = 0.05
	n.seed = hash(name)
	dust.noise = n
	m.albedo_texture = dust
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.12
	m.metallic_specular = 0.9
	glass.material_override = m
	glass.position.z = 0.0045
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass)


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


## Aged face: faded patches, specks of dirt and a darker rim, the same each time for one gauge.
static func draw_wear(ci: CanvasItem, c: Vector2, r: float, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in 10:
		var p := c + Vector2.from_angle(rng.randf() * TAU) * r * sqrt(rng.randf()) * 0.85
		ci.draw_circle(p, r * rng.randf_range(0.08, 0.22), Color(0.35, 0.3, 0.22, rng.randf_range(0.01, 0.03)))
	for i in 30:
		var p := c + Vector2.from_angle(rng.randf() * TAU) * r * sqrt(rng.randf()) * 0.95
		ci.draw_circle(p, r * rng.randf_range(0.003, 0.008), Color(0.6, 0.55, 0.42, rng.randf_range(0.08, 0.22)))
	for k in 6:
		ci.draw_arc(c, r * (0.97 - k * 0.012), 0, TAU, 64, Color(0, 0, 0, 0.12), r * 0.014)


## Direction for an angle clockwise from 12 o'clock, in 2D screen space.
static func dir_cw(deg_cw: float) -> Vector2:
	var a := deg_to_rad(deg_cw - 90.0)
	return Vector2(cos(a), sin(a))
