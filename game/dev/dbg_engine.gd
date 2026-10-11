extends Node
var world: Node3D
func _ready() -> void:
	FlightInput.joysticks_enabled = false
	world = load("res://world/terrain_tile/terrain_tile.tscn").instantiate()
	world.start_engine_running = true
	add_child(world)
	world._spawn_aircraft(1)
	var ac: Aircraft = world.aircraft
	ac.lights.landing = true
	for i in 10: await get_tree().process_frame
	var spot: SpotLight3D = ac.find_child("LandingLight", true, false)
	print("spot found=", spot != null)
	if spot:
		print(" visible=", spot.visible, " in_tree=", spot.is_visible_in_tree(), " energy=", spot.light_energy, " range=", spot.spot_range)
		print(" global pos=", spot.global_position, " aircraft pos=", ac.global_position)
		print(" beam dir=", -spot.global_basis.z, " aircraft fwd=", -ac.global_basis.z)
		print(" light_on=", ac.light_on("landing"), " powered=", ac.engine.powered(), " master=", ac.engine.master)
		print(" parent chain=", spot.get_parent().name, " / ", spot.get_parent().get_parent().name)
	get_tree().quit()
