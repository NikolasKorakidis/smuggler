extends Node
## Measures how the picture changes through a day/night transition, to find
## jumps and plateaus. Steps the clock, renders a west view (sunset side) and
## an east view (dark side), and logs on-screen brightness of sky and ground.
## godot --path game --resolution 1280x720 res://dev/dusk_sweep.tscn -- --from=18 --to=21 --step=2 [--day=166] [--year=1983] --out=dir
## Writes <out>/sweep.csv and <out>/sheet_west.png / sheet_east.png (one tile per 10 game minutes).

const SETTLE := 14  # frames for the sky radiance to catch up after a clock change
const TILE := Vector2i(256, 144)

var world: Node3D
var args := {}
var hours := 0.0
var to := 0.0
var step_h := 0.0
var out := ""
var csv: FileAccess
var phase := 0
var wait := 0
var row := {}
var sheets := {}
var tiles := 0
var last_tile_min := -999


func _ready() -> void:
	FlightInput.joysticks_enabled = false
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else true
	hours = float(args.get("from", "18"))
	to = float(args.get("to", "21"))
	step_h = float(args.get("step", "2")) / 60.0
	out = args.get("out", "user://sweep")
	DirAccess.make_dir_recursive_absolute(out)
	world = load("res://world/terrain_tile/terrain_tile.tscn").instantiate()
	add_child(world)
	world._spawn_aircraft(1)
	var tod: TimeOfDay = world.time_of_day
	tod.time_scale = 0.0
	tod.day_of_year = int(args.get("day", "166"))
	tod.year = int(args.get("year", "1983"))
	var dev := world.get_node_or_null("DevMenu")
	if dev:
		dev.queue_free()
	var cols := int(ceil((to - hours) * 6.0)) + 1
	for k in ["west", "east"]:
		sheets[k] = Image.create(TILE.x * mini(cols, 8), TILE.y * int(ceil(cols / 8.0)), false, Image.FORMAT_RGB8)
	csv = FileAccess.open(out.path_join("sweep.csv"), FileAccess.WRITE)
	csv.store_line("hours,sun_el,exposure,saturation,sun_energy,moon_energy,mlim,milkyway,darkness,sky_w,ground_w,sky_e,ground_e")
	print("moon illumination %.2f" % tod.moon_illumination())
	_set_clock()


func _set_clock() -> void:
	for ui in get_tree().root.find_children("*", "CanvasLayer", true, false):
		ui.visible = false
	world.time_of_day.set_hours(hours)
	phase = 0
	wait = SETTLE
	_aim(270.0, 8.0)


func _aim(az_deg: float, el_deg: float) -> void:
	var cam: Camera3D = world.get_node("CameraRig")
	cam.target = null
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	var dir := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	var at: Vector3 = world.aircraft.global_position + Vector3(0, 3, 0)
	cam.global_position = at
	cam.look_at(at + dir, Vector3.UP)
	cam.fov = 80.0


func _process(_d: float) -> void:
	if world.time_of_day.hours != hours:  # keep the clock pinned
		world.time_of_day.set_hours(hours)
	wait -= 1
	if wait > 0:
		return
	var img := get_viewport().get_texture().get_image()
	var key := "west" if phase == 0 else "east"
	row["sky_" + key[0]] = _mean(img, 0.05, 0.40)
	row["ground_" + key[0]] = _mean(img, 0.62, 0.95)
	if row["sky_" + key[0]] < 1e-5:
		img.save_png(out.path_join("black_%s_%.4f.png" % [key, hours]))
		print("black frame at %.4f %s exposure %s" % [hours, key, world.time_of_day.environment.tonemap_exposure])
	var minute := int(round(hours * 60.0))
	if minute - last_tile_min >= 10 or phase == 1 and minute == last_tile_min:
		if phase == 0:
			last_tile_min = minute
		_tile(img, key)
	if phase == 0:
		phase = 1
		wait = 3
		_aim(90.0, 25.0)
		return
	tiles += 1 if minute == last_tile_min else 0
	_log()
	hours += step_h
	if hours > to + 1e-6:
		csv.close()
		for k in sheets:
			sheets[k].save_png(out.path_join("sheet_%s.png" % k))
		print("SWEEP DONE")
		get_tree().quit()
		return
	_set_clock()


func _log() -> void:
	var tod: TimeOfDay = world.time_of_day
	var env: Environment = tod.environment
	var sky: ShaderMaterial = env.sky.sky_material
	csv.store_line("%.4f,%.2f,%.3f,%.3f,%.4f,%.5f,%.4f,%.4f,%.3f,%.4f,%.4f,%.4f,%.4f" % [
		hours, tod.sun_elevation_deg(), env.tonemap_exposure, env.adjustment_saturation,
		tod.sun.light_energy, tod._moon.light_energy, tod.limiting_magnitude,
		float(sky.get_shader_parameter("milkyway_intensity")), tod.darkness(),
		row.sky_w, row.ground_w, row.sky_e, row.ground_e])


func _mean(img: Image, y0: float, y1: float) -> float:
	var sum := 0.0
	var n := 0
	var w := img.get_width()
	var h := img.get_height()
	for y in range(int(h * y0), int(h * y1), 8):
		for x in range(0, w, 8):
			var c := img.get_pixel(x, y)
			sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return sum / maxf(n, 1)


func _tile(img: Image, key: String) -> void:
	var small := img.duplicate()
	small.convert(Image.FORMAT_RGB8)
	small.resize(TILE.x, TILE.y, Image.INTERPOLATE_BILINEAR)
	var i := tiles
	var dst := Vector2i((i % 8) * TILE.x, (i / 8) * TILE.y)
	var sheet: Image = sheets[key]
	if dst.x + TILE.x <= sheet.get_width() and dst.y + TILE.y <= sheet.get_height():
		sheet.blit_rect(small, Rect2i(Vector2i.ZERO, TILE), dst)
