extends Node
## Anemos works on its own (no Smuggler world, aircraft, terrain or JSBSim):
## a bare scene with a stub sky. Run in a window to also exercise rendering:
## godot --path game --resolution 640x360 res://dev/anemos_standalone_test.tscn

class StubSky:
	var sun := DirectionalLight3D.new()
	func anemos_sun() -> DirectionalLight3D: return sun
	func anemos_moon() -> DirectionalLight3D: return null
	func anemos_sun_direction() -> Vector3: return Vector3(0.3, 0.8, -0.5).normalized()
	func anemos_sun_elevation_deg() -> float: return 53.0
	func anemos_sky_colors() -> Array[Vector3]: return [Vector3(0.8, 0.9, 1.0), Vector3(0.2, 0.35, 0.8), Vector3(1.0, 1.0, 1.0), Vector3(0.6, 0.7, 0.9)]
	func anemos_transmittance(_d: Vector3, _a: float) -> Vector3: return Vector3(0.95, 0.92, 0.88)
	func anemos_exposure() -> float: return 1.0
	func anemos_hours() -> float: return 14.0

var failures := 0


func _check(name: String, ok: bool, detail := "") -> void:
	print(("  ok   " if ok else "  FAIL ") + name + ("   " + detail if detail else ""))
	if not ok:
		failures += 1


func _ready() -> void:
	var env_node := WorldEnvironment.new()
	env_node.environment = Environment.new()
	add_child(env_node)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 50, 0)
	add_child(cam)
	cam.make_current()
	var sky := StubSky.new()
	add_child(sky.sun)
	var weather := AnemosWeather.new()
	add_child(weather)
	var anemos := Anemos.new()
	anemos.weather = weather
	anemos.sky = sky
	anemos.environment_node = env_node
	add_child(anemos)
	weather.set_preset(9, true)  # afternoon thunderstorms
	var cell := weather.spawn_storm(0.0, 0.0, 0.5)
	for i in 240:  # ~2 s: cloud map is built on a thread, clouds start
		await get_tree().process_frame
	_check("weather runs and storms live", weather.cells.size() >= 1 and cell.age > 0.5, "%d cells" % weather.cells.size())
	_check("air movement includes the storm", weather.air_velocity(300.0, Vector3(cell.pos.x, 300.0, cell.pos.y)).y < -1.0)
	_check("rain under the storm", weather.rain_at(Vector3(cell.pos.x, 10.0, cell.pos.y)) > 10.0)
	_check("cloud engine is up (map, layers, types)", anemos.clouds.types.size() >= 9 and anemos.atmosphere.weather_texture != null,
		"%d types" % anemos.clouds.types.size())
	_check("METAR reads the weather", weather.metar().contains("TS"), weather.metar())
	print("ANEMOS STANDALONE TEST: ", "PASS" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(failures)
