extends CanvasLayer
## F1: key reference.

const TEXT := """KEYBOARD
W / S or Up / Down     pitch (S = nose up)
A / D or Left / Right  roll
Q / E                  rudder (also steers the tailwheel)
R / F                  throttle up / down
Space                  brakes (hold)
.                      parking brake on / off
[ / ]                  trim nose down / up
G / T                  flaps down / up (one notch)
N                      next aircraft (Cub / 172)
Ctrl+E                 automatic engine start (assist)
O                      master switch (172)
M / Shift+M            magnetos up / down (OFF R L BOTH)
Enter (hold)           starter (172) · swing the prop (Cub)
P                      primer stroke (172)
X / Z                  mixture richer / leaner (hold)
V                      carb heat on / off
B                      fuel selector
Left click             cockpit switches · wheel over a knob turns it
C                      chase / cockpit camera
Right mouse            look around    Wheel: zoom    Middle: recentre
Backspace              back to the start of the strip
K                      checklist on / off
J  (or Fn+F2)          joystick setup: bind HOTAS / pedals
I  (or Fn+F3)          flight data (dev builds)
H  (or Fn+F1)          this help"""

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
