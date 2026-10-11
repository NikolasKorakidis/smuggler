class_name DialGauge
extends GaugeBase
## Needle-on-a-dial instrument: airspeed, altimeter, VSI, tachometer, oil,
## fuel. Everything about the dial is set in the inspector (panel scenes).

@export var title := ""
@export var unit_label := ""
## JSBSim property shown, multiplied by value_scale.
@export var property := ""
@export var value_scale := 1.0
@export var min_value := 0.0
@export var max_value := 100.0
## Needle angles in degrees clockwise from 12 o'clock.
@export var min_angle := -135.0
@export var max_angle := 135.0
## Value wraps round the dial (altimeter hundreds needle).
@export var wrap := false
@export var major_step := 10.0
@export var minor_step := 5.0
@export var label_step := 20.0
## Labels show value / label_divisor (e.g. tach "25" for 2500 rpm).
@export var label_divisor := 1.0
## No labels below this value (airspeed dials skip 0 and 20).
@export var label_from := -1.0e9
## Labels without sign (VSI shows 5 above and below zero).
@export var label_abs := false
## Coloured arcs: arc_from[i]..arc_to[i] in arc_colors[i].
@export var arc_from: PackedFloat32Array = []
@export var arc_to: PackedFloat32Array = []
@export var arc_colors: PackedColorArray = []
## Red radial line value; negative = none.
@export var redline := -1.0
## First-order lag on the needle, seconds (VSI ~1.5 s).
@export var lag_s := 0.0
## Altimeter thousands needle: short needle at value / ratio. 0 = none.
@export var second_needle_ratio := 0.0

var _needle: Node3D
var _needle2: Node3D
var _shown := 0.0


class DialFace extends Control:
	var g: DialGauge

	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.49
		draw_circle(c, r, Color(0.07, 0.07, 0.07))
		for i in mini(g.arc_from.size(), mini(g.arc_to.size(), g.arc_colors.size())):
			var a0 := deg_to_rad(g.angle_for(g.arc_from[i], true) - 90.0)
			var a1 := deg_to_rad(g.angle_for(g.arc_to[i], true) - 90.0)
			draw_arc(c, r * 0.87, a0, a1, 48, g.arc_colors[i], r * 0.07)
		var ticks := int(round((g.max_value - g.min_value) / g.minor_step))
		var per_major := maxi(1, int(round(g.major_step / g.minor_step)))
		for i in ticks + 1:
			if g.wrap and i == ticks:
				break
			var major := i % per_major == 0
			var d := GaugeBase.dir_cw(g.angle_for(g.min_value + i * g.minor_step, true))
			var inner := r * (0.76 if major else 0.83)
			draw_line(c + d * inner, c + d * r * 0.93, Color(0.93, 0.93, 0.9), r * (0.025 if major else 0.012))
		if g.label_step > 0.0:
			var labels := int(round((g.max_value - g.min_value) / g.label_step))
			for i in labels + 1:
				if g.wrap and i == labels:
					break
				var v := g.min_value + i * g.label_step
				if v < g.label_from:
					continue
				var d := GaugeBase.dir_cw(g.angle_for(v, true))
				GaugeBase.draw_text_centered(self, c + d * r * 0.60, str(int(round((absf(v) if g.label_abs else v) / g.label_divisor))), int(r * 0.19))
		if g.redline >= 0.0:
			var d := GaugeBase.dir_cw(g.angle_for(g.redline, true))
			draw_line(c + d * r * 0.72, c + d * r * 0.95, Color(0.9, 0.1, 0.1), r * 0.035)
		GaugeBase.draw_text_centered(self, c + Vector2(0, -r * 0.28), g.title, int(r * 0.13), Color(1, 1, 1, 0.85))
		GaugeBase.draw_text_centered(self, c + Vector2(0, r * 0.34), g.unit_label, int(r * 0.11), Color(1, 1, 1, 0.7))


func _build() -> void:
	var face := DialFace.new()
	face.g = self
	add_face(face)
	_needle = add_needle(0.82)
	if second_needle_ratio > 0.0:
		_needle2 = add_needle(0.5, 0.0045, Color(0.95, 0.95, 0.9), 0.0015)
	_shown = _read()


func _process(delta: float) -> void:
	var v := _read()
	_shown = v if lag_s <= 0.0 else lerpf(_shown, v, 1.0 - exp(-delta / lag_s))
	GaugeBase.set_angle(_needle, angle_for(_shown))
	if _needle2:
		GaugeBase.set_angle(_needle2, angle_for(_shown / second_needle_ratio))


func angle_for(v: float, exact := false) -> float:
	var span := max_value - min_value
	if wrap:
		v = fposmod(v - min_value, span) + min_value
	elif not exact:
		v = clampf(v, min_value - span * 0.02, max_value + span * 0.02)
	return remap(v, min_value, max_value, min_angle, max_angle)


func _read() -> float:
	return prop(property) * value_scale if property != "" else 0.0
