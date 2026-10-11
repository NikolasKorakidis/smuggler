extends Node
var world: Node3D
var f := 0
func _ready() -> void:
	world = load("res://world/test_world.tscn").instantiate()
	add_child(world)
	world._spawn_aircraft(1)
func _process(_d: float) -> void:
	f += 1
	if f < 5:
		return
	var ac: Aircraft = world.aircraft
	var af := ac.airframe
	var eye: Node3D = af.get_node("Eyepoint")
	var fwd := -ac.global_basis.z
	print("eye local ", eye.position, " global ", eye.global_position)
	for n in af.get_children():
		if n is Node3D and (n.name.begins_with("Panel") or n == af._prop):
			print(n.name, " local ", n.position, " ahead of eye: ", (n.global_position - eye.global_position).dot(fwd))
	var board: Node3D = af.find_child("Board", true, false)
	print("board ahead of eye: ", (board.global_position - eye.global_position).dot(fwd))
	get_tree().quit()
