class_name ClockGauge
extends GaugeBase
## Panel clock showing the game time (local solar time).

var _hour: Node3D
var _minute: Node3D


class ClockFace extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.49
		draw_circle(c, r, Color(0.07, 0.07, 0.07))
		for i in 60:
			var d := GaugeBase.dir_cw(i * 6.0)
			var major := i % 5 == 0
			draw_line(c + d * r * (0.78 if major else 0.86), c + d * r * 0.93, Color.WHITE, r * (0.03 if major else 0.012))
		for h in 12:
			GaugeBase.draw_text_centered(self, c + GaugeBase.dir_cw(h * 30.0) * r * 0.6, str(12 if h == 0 else h), int(r * 0.2))


func _build() -> void:
	add_face(ClockFace.new())
	_hour = add_needle(0.5, 0.004)
	_minute = add_needle(0.8, 0.0025, Color(0.95, 0.95, 0.9), 0.0025)


func _process(_delta: float) -> void:
	var tod = aircraft.world.get("time_of_day") if aircraft and aircraft.world else null
	if tod == null:
		return
	var h: float = tod.hours
	GaugeBase.set_angle(_hour, fmod(h, 12.0) * 30.0)
	GaugeBase.set_angle(_minute, fmod(h, 1.0) * 360.0)
