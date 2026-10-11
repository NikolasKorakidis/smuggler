class_name Aircraft
extends Node3D
## A flyable aircraft: JSBSim FDM + visuals. Generic for every aircraft; the
## specifics come from the AircraftDefinition and the JSBSim XML.

signal respawned
## Instrument backlight level changed (0 dark .. 1 bright); gauges listen.
signal panel_lighting(level: float)

const FT := 0.3048
const TRIM_RATE := 0.25  # full trim travel in 4 s

@export var definition: AircraftDefinition

var world: Node3D  # TestWorld (provides geo, spawn_point, surface_at, terrain_height)
var airframe: Node3D
var engine: EngineSystems
var trim := 0.0
var flap_notch := 0
## Altimeter setting in the Kollsman window, inches of mercury.
var altimeter_setting_inhg := 29.92
## Light switches (only aircraft with electrics have them).
var lights := {"landing": false, "nav": false, "panel": false}
var _panel_level := -1.0

@onready var fdm: FDM = $FDM


func setup(world_node: Node3D) -> bool:
	world = world_node
	if not fdm.load_model(definition.jsbsim_model):
		push_error("Could not load JSBSim model '%s'" % definition.jsbsim_model)
		return false
	engine = EngineSystems.new()
	engine.name = "Engine"
	engine.setup(definition, fdm)
	add_child(engine)
	if definition.visual_scene:
		airframe = definition.visual_scene.instantiate()
	else:
		airframe = preload("res://aircraft/placeholder_airframe.gd").new()
		airframe.build(fdm, definition)
	airframe.name = "Airframe"
	add_child(airframe)
	if definition.has_master:
		var exterior := preload("res://aircraft/aircraft_lights.gd").new()
		exterior.name = "Lights"
		airframe.add_child(exterior)  # structural frame, like the airframe itself
		exterior.build(self)
	if not "--no-audio" in OS.get_cmdline_user_args():
		var audio := preload("res://audio/aircraft_audio.gd").new()
		audio.name = "Audio"
		audio.fdm = fdm
		audio.definition = definition
		audio.engine = engine
		add_child(audio)
	respawn()
	return true


func respawn() -> void:
	var sp: Dictionary = world.spawn_point()
	fdm.surface = world.surface_at(sp.position)
	fdm.spawn(world.geo, sp.position, sp.heading_deg, world.terrain_height(sp.position))
	engine.reset(world.start_engine_running)
	trim = 0.0
	flap_notch = 0
	altimeter_setting_inhg = 29.92
	for k in lights:
		lights[k] = false
	FlightInput.parking_brake = false
	FlightInput.set_throttle_keyboard(0.0)
	_place()
	reset_physics_interpolation()
	respawned.emit()


## A light is lit when its switch is on and the electrical bus has power.
func light_on(name: String) -> bool:
	return definition.has_master and lights.get(name, false) and engine.powered()


func toggle_light(name: String) -> void:
	if definition.has_master:
		lights[name] = not lights[name]


func set_flap_notch(n: int) -> void:
	flap_notch = clampi(n, 0, maxi(definition.flap_detents.size() - 1, 0))


func flap_notch_degrees(n: int) -> int:
	# Notch index to the degrees printed on the switch (0/10/20/30 for the 172).
	return int(round(definition.flap_detents[n] * 30.0)) if n < definition.flap_detents.size() else 0


func eyepoint() -> Node3D:
	return airframe.get_node("Eyepoint")


func _physics_process(delta: float) -> void:
	if fdm.jsb == null:
		return
	_apply_controls(delta)
	var here := global_position
	var surface: StringName = world.surface_at(here)
	if surface != fdm.surface:
		fdm.set_surface(surface)
	fdm.prop("position/terrain-elevation-asl-ft", world.terrain_height(here) / FT)
	engine.apply(delta)
	if world.get("weather"):
		world.weather.apply(fdm, maxf(fdm.prop_get("position/h-agl-ft") * FT, 0.0), _on_ground())
	fdm.step()
	if not fdm.is_valid():
		push_warning("FDM diverged, respawning")
		respawn()
		return
	_place()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_aircraft"):
		respawn()
	elif event.is_action_pressed("flaps_down"):
		set_flap_notch(flap_notch + 1)
	elif event.is_action_pressed("flaps_up"):
		set_flap_notch(flap_notch - 1)
	# Exact matches so Shift+M / Ctrl+E don't also fire M / E.
	elif event.is_action_pressed("magnetos_down", false, true):
		engine.set_magnetos(engine.magnetos - 1)
	elif event.is_action_pressed("magnetos_up", false, true):
		engine.set_magnetos(engine.magnetos + 1)
	elif event.is_action_pressed("auto_start", false, true):
		engine.auto_start()
	elif event.is_action_pressed("landing_light", false, true):
		toggle_light("landing")
	elif event.is_action_pressed("nav_lights", false, true):
		toggle_light("nav")
	elif event.is_action_pressed("panel_lights", false, true):
		toggle_light("panel")
	elif event.is_action_pressed("primer", false, true):
		engine.stroke_primer()
	elif event.is_action_pressed("carb_heat"):
		engine.set_carb_heat(not engine.carb_heat)
	elif event.is_action_pressed("fuel_selector"):
		engine.set_fuel_selector((engine.fuel_selector + 1) % definition.fuel_positions.size())
	elif event.is_action_pressed("master"):
		engine.set_master(not engine.master)


func _apply_controls(delta: float) -> void:
	var i := FlightInput
	# JSBSim conventions: negative elevator = nose up, positive rudder = nose left,
	# positive steering = nose right.
	fdm.prop("fcs/elevator-cmd-norm", -i.pitch)
	fdm.prop("fcs/aileron-cmd-norm", i.roll)
	fdm.prop("fcs/rudder-cmd-norm", -i.rudder)
	fdm.prop("fcs/steer-cmd-norm", i.rudder)
	fdm.prop("fcs/throttle-cmd-norm", i.throttle)
	fdm.prop("fcs/left-brake-cmd-norm", i.brake_left * definition.brake_strength)
	fdm.prop("fcs/right-brake-cmd-norm", i.brake_right * definition.brake_strength)
	trim = clampf(trim + i.trim * TRIM_RATE * delta, -1.0, 1.0)
	fdm.prop("fcs/pitch-trim-cmd-norm", -trim)
	if not definition.flap_detents.is_empty():
		fdm.prop("fcs/flap-cmd-norm", definition.flap_detents[flap_notch])


func _on_ground() -> bool:
	for w in fdm.wheels():
		if fdm.prop_get("gear/unit[%d]/WOW" % w.index) > 0.5:
			return true
	return false


func _process(_delta: float) -> void:
	# Daylight lights the panel; at night only the panel lights do (if fitted).
	var dark: float = world.time_of_day.darkness() if world and world.get("time_of_day") else 0.0
	var level := lerpf(1.0, 0.04, dark)
	if light_on("panel"):
		level = maxf(level, 0.75)
	if absf(level - _panel_level) > 0.01:
		_panel_level = level
		panel_lighting.emit(level)


func _place() -> void:
	global_transform = fdm.cg_transform()
	airframe.position = fdm.structure_offset()
