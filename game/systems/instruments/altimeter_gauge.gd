class_name AltimeterGauge
extends DialGauge
## Barometric altimeter: reads pressure altitude corrected by the setting in
## the Kollsman window (inches of mercury). Set it to the local QNH (or so
## it shows field elevation on the ground) or it reads wrong.

var _window: KollsmanFace


class KollsmanFace extends Control:
	var setting := 29.92
	var ink := Color.WHITE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.05))
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color(0.85, 0.84, 0.78), false, 2.0)
		GaugeBase.draw_text_centered(self, size * 0.5, "%.2f" % setting, int(size.y * 0.62), ink)


func _build() -> void:
	super._build()
	_window = KollsmanFace.new()
	_window.ink = GaugeBase.CREAM if vintage else Color.WHITE
	var quad := add_face(_window, true, 0.0012, Vector2(diameter_m * 0.3, diameter_m * 0.12))
	quad.position.x = diameter_m * 0.2


func _read() -> float:
	var setting := aircraft.altimeter_setting_inhg if aircraft else 29.92
	# ~1000 ft per inch of mercury near sea level.
	return prop("atmosphere/pressure-altitude") + (setting - 29.92) * 1000.0


func _process(delta: float) -> void:
	super._process(delta)
	if aircraft and not is_equal_approx(_window.setting, aircraft.altimeter_setting_inhg):
		_window.setting = aircraft.altimeter_setting_inhg
		_window.queue_redraw()
