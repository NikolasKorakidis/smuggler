extends Node
## Renders instrument faces at known values to a PNG for checking.
var f := 0
var face
func _ready() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(320, 320)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	face = AttitudeGauge.AttitudeFace.new()
	face.size = Vector2(320, 320)
	face.pitch_deg = 10.0
	face.roll_deg = 20.0
	vp.add_child(face)
	add_child(vp)
	set_meta("vp", vp)
func _process(_d: float) -> void:
	f += 1
	if f == 5:
		var out := OS.get_cmdline_user_args()[0].trim_prefix("--out=")
		get_meta("vp").get_texture().get_image().save_png(out)
		get_tree().quit()
