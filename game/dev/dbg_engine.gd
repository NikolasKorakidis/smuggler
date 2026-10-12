extends Node
## Sky sanity: LST and where known stars end up.
func _ready() -> void:
	var w = load("res://world/test_world.tscn").instantiate()
	add_child(w)
	var t: TimeOfDay = w.time_of_day
	t.time_scale = 0.0
	t.set_hours(23.0)
	print("LST at 23:00 local, 15 Jun 1983, lon -78: %.2f h (expect ~17.4)" % t.local_sidereal_hours())
	var b := t.celestial_basis()
	for s in [["Polaris", 37.95, 89.26], ["Antares", 247.35, -26.43], ["Vega", 279.23, 38.78], ["Arcturus", 213.92, 19.18]]:
		var v: Vector3 = b * StarField._celestial(s[1], s[2])
		var az := fposmod(rad_to_deg(atan2(v.x, -v.z)), 360.0)
		print("  %-9s az %5.1f el %5.1f" % [s[0], az, rad_to_deg(asin(v.y))])
	print("moon phase %.2f (0 new, 0.5 full)" % t.moon_phase())
	get_tree().quit()
