extends Node
## Renders a set of weather views into one contact sheet, for judging clouds.
## godot --path game --resolution 1280x720 res://dev/cloud_gallery.tscn -- --out=sheet.png [--set=day|storm|all]
## Each view: weather preset, time, camera height above the field, look azimuth/elevation, optional storm.

const VIEWS := {
	"day": [
		["toward sun", 2, 12.0, 3.0, 175.0, 14.0, ""],
		["away from sun", 2, 12.0, 3.0, 355.0, 14.0, ""],
		["climbing 1500 m", 2, 12.0, 1500.0, 90.0, 2.0, ""],
		["above, 3200 m", 2, 12.0, 3200.0, 90.0, -8.0, ""],
		["late afternoon", 1, 17.3, 600.0, 280.0, 6.0, ""],
		["sunset", 2, 18.55, 3.0, 290.0, 6.0, ""],
		["storm 12 km", 9, 15.0, 3.0, 120.0, 10.0, "12000,120"],
		["rain overcast", 8, 13.0, 3.0, 60.0, 8.0, ""],
	],
	"close": [
		["beside cumulus, sun behind", 3, 15.0, 1700.0, 70.0, 4.0, ""],
		["beside cumulus, backlit", 3, 15.0, 1700.0, 250.0, 4.0, ""],
		["towering cumulus from ground", 3, 15.0, 3.0, 70.0, 22.0, ""],
		["above the tops", 2, 15.0, 3400.0, 70.0, -6.0, ""],
		["inside a cloud", 8, 13.0, 900.0, 60.0, 0.0, ""],
		["sunset at 1500 m", 1, 18.45, 1500.0, 280.0, 2.0, ""],
		["stratus deck from above", 7, 11.0, 1600.0, 60.0, -10.0, ""],
		["overcast underside", 8, 13.0, 3.0, 60.0, 35.0, ""],
	],
	"debug": [
		["calm + storm", 0, 15.0, 3.0, 120.0, 10.0, "12000,120"],
		["preset 9, no storm", 9, 15.0, 3.0, 120.0, 10.0, "none"],
		["preset 2", 2, 15.0, 3.0, 120.0, 10.0, ""],
		["preset 9 + storm", 9, 15.0, 3.0, 120.0, 10.0, "12000,120"],
	],
	"storm": [
		["storm ground", 9, 15.0, 3.0, 120.0, 12.0, "14000,120"],
		["storm 2000 m", 9, 15.0, 2000.0, 120.0, 4.0, "16000,120"],
		["storm sunset", 9, 18.4, 3.0, 110.0, 10.0, "15000,110"],
		["under storm", 9, 15.0, 3.0, 120.0, 25.0, "3000,120"],
		["squall", 10, 16.0, 3.0, 230.0, 8.0, "9000,230"],
		["low overcast", 7, 11.0, 3.0, 60.0, 8.0, ""],
		["night moon", 4, 21.5, 3.0, 160.0, 15.0, ""],
		["hazy summer", 5, 14.0, 800.0, 140.0, 0.0, ""],
	],
}
const TILE := Vector2i(640, 360)
const SETTLE := 40

var world: Node3D
var args := {}
var views: Array = []
var sheet: Image
var i := 0
var wait := 0


func _ready() -> void:
	FlightInput.joysticks_enabled = false
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else true
	var set: String = args.get("set", "day")
	views = VIEWS.day + VIEWS.storm + VIEWS.close if set == "all" else VIEWS[set]
	world = load("res://world/terrain_tile/terrain_tile.tscn").instantiate()
	add_child(world)
	world._spawn_aircraft(1)
	world.time_of_day.time_scale = 0.0
	sheet = Image.create(TILE.x * 4, TILE.y * int(ceil(views.size() / 4.0)), false, Image.FORMAT_RGB8)
	wait = 90  # the cloud map is built on a thread at start
	_setup(0)


func _setup(k: int) -> void:
	var v: Array = views[k]
	var w: Weather = world.weather
	w.set_preset(v[1], true)
	w.cells.clear()
	if v[6] != "" and v[6] != "none":
		var sb: PackedStringArray = String(v[6]).split(",")
		w.spawn_storm(float(sb[0]), float(sb[1]), 0.45)
	world.time_of_day.set_hours(v[2])
	for ui in get_tree().root.find_children("*", "CanvasLayer", true, false):
		ui.visible = false


func _process(_d: float) -> void:
	var v: Array = views[i]
	var cam: Camera3D = world.get_node("CameraRig")
	cam.target = null
	var az := deg_to_rad(v[4])
	var el := deg_to_rad(v[5])
	var dir := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	var at: Vector3 = world.aircraft.global_position + Vector3(0, v[3], 0)
	cam.global_position = at
	cam.look_at(at + dir, Vector3.UP)
	cam.fov = 75.0
	wait -= 1
	if wait > 0:
		return
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.resize(TILE.x, TILE.y, Image.INTERPOLATE_BILINEAR)
	sheet.blit_rect(img, Rect2i(Vector2i.ZERO, TILE), Vector2i((i % 4) * TILE.x, (i / 4) * TILE.y))
	print("view %d: %s" % [i, v[0]])
	i += 1
	if i >= views.size():
		sheet.save_png(args.get("out", "user://gallery.png"))
		get_tree().quit()
		return
	_setup(i)
	wait = SETTLE
