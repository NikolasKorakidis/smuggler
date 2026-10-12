extends Node
## Screenshots each developer menu tab and exercises a few controls.
var world: Node3D
var f := 0
var out := ""
func _ready() -> void:
	FlightInput.joysticks_enabled = false
	out = OS.get_cmdline_user_args()[0].trim_prefix("--out=")
	world = load("res://world/terrain_tile/terrain_tile.tscn").instantiate()
	add_child(world)
func _process(_d: float) -> void:
	f += 1
	var dm = world.get_node("DevMenu")
	if f == 10:
		dm.visible = true
	var tab := (f - 20) / 15
	if f >= 20 and (f - 20) % 15 == 0 and tab < dm._tabs.get_tab_count():
		dm._tabs.current_tab = tab
	if f >= 20 and (f - 20) % 15 == 10 and tab < dm._tabs.get_tab_count():
		get_viewport().get_texture().get_image().save_png("%s/tab_%d.png" % [out, tab])
	if f == 20 + 15 * 7 + 5:
		# exercise: teleport on final, set time, weather
		dm._teleport_air(true)
		world.time_of_day.set_hours(18.5)
		print("after final teleport: agl %.0f ft, kias %.0f, flaps %d, running %s" % [world.aircraft.fdm.prop_get("position/h-agl-ft"),
			world.aircraft.fdm.prop_get("velocities/vc-kts"), world.aircraft.flap_notch, world.aircraft.engine.running()])
	if f == 20 + 15 * 7 + 120:
		print("2 s later: agl %.0f ft, kias %.0f, still flying: %s" % [world.aircraft.fdm.prop_get("position/h-agl-ft"),
			world.aircraft.fdm.prop_get("velocities/vc-kts"), world.aircraft.fdm.prop_get("position/h-agl-ft") > 100.0])
		get_tree().quit()
