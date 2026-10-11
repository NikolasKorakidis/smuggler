class_name HeadingGauge
extends GaugeBase
## Heading indicator (directional gyro): a compass card that turns behind a
## fixed aircraft symbol. No gyro drift yet.

var _card: MeshInstance3D


class CardFace extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.49
		draw_circle(c, r, Color(0.07, 0.07, 0.07))
		var names := {0: "N", 90: "E", 180: "S", 270: "W"}
		for deg in range(0, 360, 5):
			var d := GaugeBase.dir_cw(deg)
			var major := deg % 10 == 0
			draw_line(c + d * r * (0.8 if major else 0.86), c + d * r * 0.94, Color.WHITE, r * (0.02 if major else 0.012))
			if deg % 30 == 0:
				var text: String = names.get(deg, str(deg / 10))
				draw_set_transform(c + d * r * 0.64, deg_to_rad(deg))
				GaugeBase.draw_text_centered(self, Vector2.ZERO, text, int(r * 0.2))
				draw_set_transform(Vector2.ZERO, 0.0)


class OverlayFace extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.49
		var orange := Color(0.95, 0.6, 0.15)
		draw_line(c + Vector2(0, -r * 0.35), c + Vector2(0, r * 0.3), orange, r * 0.04)
		draw_line(c + Vector2(-r * 0.25, -r * 0.05), c + Vector2(r * 0.25, -r * 0.05), orange, r * 0.04)
		draw_line(c + Vector2(-r * 0.1, r * 0.25), c + Vector2(r * 0.1, r * 0.25), orange, r * 0.03)
		for deg in range(0, 360, 45):
			var d := GaugeBase.dir_cw(deg)
			draw_line(c + d * r * 0.95, c + d * r * 1.0, orange, r * 0.04)


func _build() -> void:
	_card = add_face(CardFace.new())
	add_face(OverlayFace.new(), false, 0.002)


func _process(_delta: float) -> void:
	if vacuum():  # vacuum gyro: card stays where it was when the engine stops
		_card.rotation.z = deg_to_rad(prop("attitude/psi-deg"))
