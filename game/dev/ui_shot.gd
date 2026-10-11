extends Node
## Screenshots the joystick setup menu: godot --path game res://dev/ui_shot.tscn -- --out=<file.png>
var world: Node3D
var frames := 0
func _ready() -> void:
	world = load("res://world/test_world.tscn").instantiate()
	add_child(world)
func _process(_d: float) -> void:
	frames += 1
	if frames == 10:
		var ev := InputEventAction.new()
		ev.action = "axis_tester"
		ev.pressed = true
		Input.parse_input_event(ev)
	if frames == 40:
		var out := "user://ui_shot.png"
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--out="):
				out = a.trim_prefix("--out=")
		get_viewport().get_texture().get_image().save_png(out)
		get_tree().quit()
