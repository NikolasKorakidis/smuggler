extends Node
## Prints effective controller bindings after start-up (non-headless).
var t := 0.0
func _process(delta: float) -> void:
	t += delta
	if t > 2.0:
		for d in Input.get_connected_joypads():
			print("device %d %s usb=%s warning='%s'" % [d, Input.get_joy_name(d), FlightInput.usb_id(d), FlightInput.mode_warning(d)])
		for k in FlightInput.axis_bindings:
			print("axis ", k, " -> ", FlightInput.axis_bindings[k].axis, " profile=", FlightInput.axis_bindings[k].get("profile", false))
		for k in FlightInput.button_bindings:
			print("button ", k, " -> ", FlightInput.button_bindings[k].button)
		get_tree().quit()
