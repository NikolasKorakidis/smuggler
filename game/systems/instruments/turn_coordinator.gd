class_name TurnCoordinator
extends GaugeBase
## Turn coordinator: aircraft symbol tilts with rate of turn (standard rate,
## 3°/s, on the L/R marks) and an inclinometer ball shows slip/skid.

const STANDARD_RATE_TILT := 18.0  # degrees of symbol tilt at 3°/s

var _face: TurnFace
var _ball := 0.0


class TurnFace extends Control:
	var tilt_deg := 0.0
	var ball := 0.0  # -1..1, + = right

	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.49
		draw_circle(c, r, Color(0.07, 0.07, 0.07))
		for side in [-1.0, 1.0]:
			for deg in [0.0, STANDARD_RATE_TILT]:
				var a := deg_to_rad(side * deg)
				var d := Vector2(side * cos(a), sin(a))
				draw_line(c + d * r * 0.72, c + d * r * 0.88, Color.WHITE, r * 0.03)
		GaugeBase.draw_text_centered(self, c + Vector2(-r * 0.62, r * 0.42), "L", int(r * 0.16))
		GaugeBase.draw_text_centered(self, c + Vector2(r * 0.62, r * 0.42), "R", int(r * 0.16))
		GaugeBase.draw_text_centered(self, c + Vector2(0, -r * 0.55), "TURN COORDINATOR", int(r * 0.09), Color(1, 1, 1, 0.7))
		GaugeBase.draw_text_centered(self, c + Vector2(0, r * 0.78), "2 MIN", int(r * 0.09), Color(1, 1, 1, 0.7))
		# Inclinometer tube and ball
		var tube_y := r * 0.5
		draw_line(c + Vector2(-r * 0.42, tube_y), c + Vector2(r * 0.42, tube_y), Color(0.85, 0.8, 0.6), r * 0.13)
		draw_line(c + Vector2(-r * 0.08, tube_y - r * 0.08), c + Vector2(-r * 0.08, tube_y + r * 0.08), Color.BLACK, r * 0.02)
		draw_line(c + Vector2(r * 0.08, tube_y - r * 0.08), c + Vector2(r * 0.08, tube_y + r * 0.08), Color.BLACK, r * 0.02)
		draw_circle(c + Vector2(ball * r * 0.34, tube_y), r * 0.055, Color(0.05, 0.05, 0.05))
		# Aircraft symbol
		draw_set_transform(c, deg_to_rad(tilt_deg))
		draw_line(Vector2(-r * 0.62, 0), Vector2(r * 0.62, 0), Color.WHITE, r * 0.05)
		draw_circle(Vector2.ZERO, r * 0.08, Color.WHITE)
		draw_line(Vector2(0, -r * 0.18), Vector2(0, 0), Color.WHITE, r * 0.04)
		draw_set_transform(Vector2.ZERO, 0.0)


func _build() -> void:
	_face = TurnFace.new()
	add_face(_face, true)


func _process(delta: float) -> void:
	# Electric gyro: runs down to level when the master is off.
	var rate := rad_to_deg(prop("velocities/psidot-rad_sec")) if powered() else 0.0
	_face.tilt_deg = lerpf(_face.tilt_deg, clampf(rate / 3.0 * STANDARD_RATE_TILT, -35.0, 35.0),
		1.0 - exp(-delta / (0.15 if powered() else 3.0)))
	_ball = lerpf(_ball, clampf(prop("accelerations/Ny") * 4.0, -1.0, 1.0), 1.0 - exp(-delta / 0.25))
	_face.ball = _ball
	_face.queue_redraw()
