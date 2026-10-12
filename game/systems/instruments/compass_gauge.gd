class_name CompassGauge
extends GaugeBase
## Magnetic ("whiskey") compass on the glare shield: a card seen through a
## window, swinging with a little overshoot. Turning errors come later.

const SPRING := 6.0
const DAMPING := 2.6

var _face: CompassFace
var _card := 0.0
var _rate := 0.0


class CompassFace extends Control:
	var heading := 0.0
	var vintage := false

	func _draw() -> void:
		var c := size * 0.5
		var ink := GaugeBase.CREAM if vintage else Color.BLACK
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.045) if vintage else Color(0.88, 0.86, 0.8))
		var px_per_deg := size.x / 70.0
		# Seen from behind, so higher headings sit to the left.
		for deg in range(-40, 400, 5):
			var x := c.x - wrapf(deg - heading, -180.0, 180.0) * px_per_deg
			if x < -20 or x > size.x + 20:
				continue
			var major := deg % 10 == 0
			draw_line(Vector2(x, size.y * 0.62), Vector2(x, size.y * (0.4 if major else 0.5)), ink, 2.0)
			if posmod(deg, 30) == 0:
				var names := {0: "N", 90: "E", 180: "S", 270: "W"}
				var d := posmod(deg, 360)
				GaugeBase.draw_text_centered(self, Vector2(x, size.y * 0.25), names.get(d, str(d / 10)),
					int(size.y * 0.28), ink)
		draw_line(Vector2(c.x, 0), Vector2(c.x, size.y), Color(0.85, 0.1, 0.1), 3.0)


func _build() -> void:
	_face = CompassFace.new()
	_face.vintage = vintage
	add_face(_face, true, 0.0, Vector2(diameter_m, diameter_m * 0.45))
	if vintage:
		_build_drum()
	_card = prop("attitude/psi-deg")


func _build_bezel() -> void:
	var housing := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(diameter_m * 1.25, diameter_m * 0.8, diameter_m * 0.8)
	housing.mesh = box
	housing.position.z = -diameter_m * 0.41
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.05)
	housing.material_override = mat
	add_child(housing)


# The card window is part of the drum; no flat cover glass.
func _build_glass() -> void:
	pass


# Round compass drum with the card window towards the pilot, on a mounting foot.
func _build_drum() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.05, 0.05)
	m.roughness = 0.3
	var drum := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = diameter_m * 0.55
	cyl.bottom_radius = diameter_m * 0.6
	cyl.height = diameter_m * 0.65
	drum.mesh = cyl
	drum.material_override = m
	drum.position = Vector3(0, -diameter_m * 0.02, -diameter_m * 0.63)
	add_child(drum)
	var cap := MeshInstance3D.new()
	var cc := CylinderMesh.new()
	cc.top_radius = diameter_m * 0.18
	cc.bottom_radius = diameter_m * 0.25
	cc.height = diameter_m * 0.12
	cap.mesh = cc
	cap.material_override = m
	cap.position = Vector3(0, diameter_m * 0.36, -diameter_m * 0.63)
	add_child(cap)


func _process(delta: float) -> void:
	var err := wrapf(prop("attitude/psi-deg") - _card, -180.0, 180.0)
	_rate += (SPRING * err - DAMPING * _rate) * delta
	_card = wrapf(_card + _rate * delta, 0.0, 360.0)
	_face.heading = _card
	_face.queue_redraw()
