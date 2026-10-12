extends Node
## Close-up screenshot of the aircraft model from any point, with controls held:
##   godot --path game res://dev/model_shot.tscn -- --aircraft=0 --cam=2,0.3,-1 --look=0.9,-1.4,-0.3
##       [--rudder=-1..1] [--pitch=-1..1] [--roll=-1..1] [--fov=50] [--out=x.png]
## --cam / --look are metres in the model frame (+X right, +Y up, +Z aft; origin = JSBSim structural origin).
var world: Node3D
var cam := Camera3D.new()
var f := 0
var out := "user://model.png"
var eye := Vector3(3, 0.5, -1)
var look := Vector3.ZERO
var controls := {}


func _ready() -> void:
	FlightInput.joysticks_enabled = false
	world = load("res://world/terrain_tile/terrain_tile.tscn").instantiate()
	add_child(world)
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"aircraft": world._spawn_aircraft(int(kv[1]))
			"out": out = kv[1]
			"cam": eye = _vec(kv[1])
			"look": look = _vec(kv[1])
			"fov": cam.fov = float(kv[1])
			"rudder", "pitch", "roll": controls[kv[0]] = float(kv[1])
	if world.has_node("Checklist"):
		world.get_node("Checklist").visible = false
	add_child(cam)
	cam.current = true


func _vec(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _hold(neg: String, pos: String, v: float) -> void:
	Input.action_release(neg)
	Input.action_release(pos)
	if v > 0.0:
		Input.action_press(pos, v)
	elif v < 0.0:
		Input.action_press(neg, -v)


func _process(_d: float) -> void:
	f += 1
	_hold("rudder_left", "rudder_right", controls.get("rudder", 0.0))
	_hold("pitch_fwd", "pitch_back", controls.get("pitch", 0.0))
	_hold("roll_left", "roll_right", controls.get("roll", 0.0))
	var ac: Node3D = world.aircraft
	var t: Transform3D = ac.airframe.global_transform
	cam.global_position = t * eye
	cam.look_at(t * look, t.basis.y)
	if f == 150:
		get_viewport().get_texture().get_image().save_png(out)
		get_tree().quit()
