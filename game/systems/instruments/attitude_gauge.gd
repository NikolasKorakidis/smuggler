class_name AttitudeGauge
extends GaugeBase
## Artificial horizon: sky/ground ball with pitch ladder, bank scale and a
## fixed miniature aircraft.

const PX_PER_DEG := 0.04  # fraction of the face radius per degree of pitch

var _face: AttitudeFace
var _erect := false


class AttitudeFace extends Control:
	var pitch_deg := 0.0
	var roll_deg := 0.0

	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.49
		var h := pitch_deg * PX_PER_DEG * r
		# Ball, in a frame rotated with the aircraft's bank.
		draw_set_transform(c, deg_to_rad(-roll_deg))
		draw_circle(Vector2.ZERO, r, Color(0.25, 0.5, 0.85))
		var circle := PackedVector2Array()
		for i in 64:
			circle.append(Vector2.from_angle(TAU * i / 64.0) * r)
		var ground := PackedVector2Array([Vector2(-2 * r, h), Vector2(2 * r, h), Vector2(2 * r, 3 * r), Vector2(-2 * r, 3 * r)])
		for poly in Geometry2D.intersect_polygons(circle, ground):
			draw_colored_polygon(poly, Color(0.45, 0.3, 0.15))
		if absf(h) < r:
			var half := sqrt(r * r - h * h)
			draw_line(Vector2(-half, h), Vector2(half, h), Color.WHITE, r * 0.02)
		for p: int in [-20, -10, -5, 5, 10, 20]:
			var y := h - p * PX_PER_DEG * r
			if absf(y) < r * 0.75:
				var w := r * (0.12 if absi(p) == 5 else 0.25)
				draw_line(Vector2(-w, y), Vector2(w, y), Color.WHITE, r * 0.015)
		# Bank pointer turns with the ball.
		draw_colored_polygon(PackedVector2Array([Vector2(0, -r * 0.78), Vector2(-r * 0.06, -r * 0.66),
			Vector2(r * 0.06, -r * 0.66)]), Color.WHITE)
		draw_set_transform(c, 0.0)
		# Fixed bank scale and miniature aircraft.
		for b: int in [-60, -45, -30, -20, -10, 10, 20, 30, 45, 60]:
			var d := GaugeBase.dir_cw(b)
			var long_tick := absi(b) == 30 or absi(b) == 60
			draw_line(d * r * (0.8 if long_tick else 0.85), d * r * 0.95, Color.WHITE, r * 0.02)
		draw_colored_polygon(PackedVector2Array([Vector2(0, -r * 0.95), Vector2(-r * 0.06, -r * 0.82),
			Vector2(r * 0.06, -r * 0.82)]), Color(0.95, 0.6, 0.15))
		var orange := Color(0.95, 0.6, 0.15)
		draw_line(Vector2(-r * 0.5, 0), Vector2(-r * 0.15, 0), orange, r * 0.05)
		draw_line(Vector2(r * 0.15, 0), Vector2(r * 0.5, 0), orange, r * 0.05)
		draw_circle(Vector2.ZERO, r * 0.04, orange)
		draw_arc(Vector2.ZERO, r * 0.97, 0, TAU, 64, Color(0.05, 0.05, 0.05), r * 0.08)


func _build() -> void:
	_face = AttitudeFace.new()
	add_face(_face, true)
	_face.pitch_deg = 8.0
	_face.roll_deg = 25.0


func _process(delta: float) -> void:
	# Vacuum gyro: erects in a few seconds with the engine running, slowly
	# topples when it stops.
	var target_pitch := prop("attitude/theta-deg") if vacuum() else 8.0
	var target_roll := prop("attitude/phi-deg") if vacuum() else 25.0
	var k := 1.0 - exp(-delta / (0.05 if vacuum() and _erect else (3.0 if vacuum() else 40.0)))
	_face.pitch_deg = lerpf(_face.pitch_deg, target_pitch, k)
	_face.roll_deg = lerpf(_face.roll_deg, target_roll, k)
	if not vacuum():
		_erect = false
	elif absf(_face.roll_deg - target_roll) < 1.0 and absf(_face.pitch_deg - target_pitch) < 1.0:
		_erect = true  # stays locked while the vacuum pump turns
	_face.queue_redraw()
