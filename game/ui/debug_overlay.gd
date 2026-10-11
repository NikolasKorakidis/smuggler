extends CanvasLayer
## Dev-only flight data (F3). Not part of the game: no HUD in flight.

var aircraft: Aircraft
var _label: Label
var _accum := 0.0


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_overlay") and OS.is_debug_build():
		visible = not visible


func _process(delta: float) -> void:
	_accum += delta
	if not visible or aircraft == null or aircraft.fdm.jsb == null or _accum < 0.1:
		return
	_accum = 0.0
	var f := aircraft.fdm
	var i := FlightInput
	_label.text = "\n".join([
		"KIAS %5.1f    ALT %6.0f ft   AGL %6.0f ft   VS %+5.0f fpm" % [
			f.prop_get("velocities/vc-kts"), f.prop_get("position/h-sl-ft"),
			f.prop_get("position/h-agl-ft"), f.prop_get("velocities/h-dot-fps") * 60.0],
		"AoA %5.1f°    HDG %03.0f°   GS %5.1f kt" % [
			f.prop_get("aero/alpha-deg"), fposmod(f.prop_get("attitude/psi-deg"), 360.0),
			f.prop_get("velocities/vg-fps") * 0.592484],
		"RPM %5.0f    THR %3.0f%%   TRIM %+.2f   ENGINE %s" % [
			f.prop_get("propulsion/engine/engine-rpm"), i.throttle * 100.0, aircraft.trim,
			"ON" if f.engine_running() else "OFF"],
		"STICK p%+.2f r%+.2f  RUD %+.2f  BRK %.1f/%.1f" % [i.pitch, i.roll, i.rudder, i.brake_left, i.brake_right],
		"FLAPS %2.0f°   FUEL %3.0f lb   WEIGHT %4.0f lb" % [
			f.prop_get("fcs/flap-pos-deg"), f.prop_get("propulsion/total-fuel-lbs"), f.prop_get("inertia/weight-lbs")],
		"%s   SURFACE %s   FPS %d" % [aircraft.definition.display_name, f.surface, Engine.get_frames_per_second()],
	])
