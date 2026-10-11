extends CanvasLayer
## F1: key reference.

const TEXT := """KEYBOARD
W / S or Up / Down     pitch (S = nose up)
A / D or Left / Right  roll
Q / E                  rudder (also steers the tailwheel)
R / F                  throttle up / down
Space                  brakes (hold)
[ / ]                  trim nose down / up
M                      engine off / on
C                      chase / cockpit camera
Right mouse            look around    Wheel: zoom    Middle: recentre
Backspace              back to the start of the strip
F2  axis tester and HOTAS/pedal binding
F3  flight data (dev builds)
F1  this help"""

var _panel: PanelContainer


func _ready() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	var label := Label.new()
	label.text = TEXT
	label.add_theme_font_size_override("font_size", 18)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	margin.add_child(label)
	_panel.add_child(margin)
	add_child(_panel)
	_panel.position = Vector2(60, 80)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("help"):
		visible = not visible
