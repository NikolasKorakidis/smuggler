extends SceneTree
## Prints the sky model's brightness against sun elevation (CPU copy of sky.gdshader).
## godot --headless --path game -s res://dev/sky_curve.gd
func _init() -> void:
	var tod := TimeOfDay.new()
	for i in range(12, -23, -1):
		var el := deg_to_rad(float(i))
		var sun := Vector3(-cos(el), sin(el), 0.0)  # sun in the west
		var z := tod.sky_radiance(Vector3.UP, sun, 22.0, 300.0)
		var w := tod.sky_radiance(Vector3(-0.996, 0.087, 0), sun, 22.0, 300.0)
		var e := tod.sky_radiance(Vector3(0.996, 0.087, 0), sun, 22.0, 300.0)
		var lum := tod.sky_luminance(sun, Vector3.DOWN, 0.0, TimeOfDay.twilight_level(float(i)), 300.0)
		tod._sky_lum = lum
		print("%4d  zen %.6f  west %.6f  east %.6f  lum %.6f  adapt %.2f  mlim %.2f" % [i, _l(z), _l(w), _l(e), lum, tod.night_adaptation(), 6.5 - 2.5 * log(lum / tod._night_lum()) / log(10.0)])
	tod.free()
	quit()
func _l(c: Vector3) -> float:
	return 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
