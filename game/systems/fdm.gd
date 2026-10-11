class_name FDM
extends Node
## Owns one JSBSim instance. Steps it once per physics tick (120 Hz) and maps
## its CG position and attitude onto a Node3D. Knows nothing about any
## particular aircraft: everything comes from the JSBSim XML.

const FT := 0.3048
const SETTLE_SECONDS := 2.0

## Ground surface factors applied to JSBSim's ground model.
const SURFACES := {
	&"paved": {"rolling": 1.0, "static": 1.0, "bumpiness": 0.0},
	&"grass_strip": {"rolling": 2.5, "static": 0.75, "bumpiness": 0.1},
	&"grass_rough": {"rolling": 4.0, "static": 0.6, "bumpiness": 0.3},
}

@export_dir var aircraft_dir := "res://aircraft"

var jsb: JSBSimFDM
var geo: Geo
var surface := &"paved"


func load_model(model: String) -> bool:
	jsb = JSBSimFDM.new()
	if not jsb.load_model(ProjectSettings.globalize_path(aircraft_dir), model):
		jsb = null
		return false
	jsb.set_dt(1.0 / Engine.physics_ticks_per_second)
	return true


## Places the aircraft at rest on its gear at a local position and heading,
## engine stopped (EngineSystems decides). Gear settling runs instantly.
func spawn(world_geo: Geo, local_pos: Vector3, heading_deg: float, terrain_m: float) -> void:
	geo = world_geo
	var g := geo.to_geo(local_pos)
	prop("ic/lat-geod-deg", g.x)
	prop("ic/long-gc-deg", g.y)
	prop("ic/terrain-elevation-ft", terrain_m / FT)
	prop("ic/h-agl-ft", _gear_height_ft())
	prop("ic/psi-true-deg", heading_deg)
	prop("ic/theta-deg", 0.0)
	prop("ic/phi-deg", 0.0)
	prop("ic/vc-kts", 0.0)
	jsb.run_ic()
	prop("position/terrain-elevation-asl-ft", terrain_m / FT)
	set_surface(surface)
	stop_engines()
	prop("fcs/left-brake-cmd-norm", 1.0)
	prop("fcs/right-brake-cmd-norm", 1.0)
	jsb.step_n(int(SETTLE_SECONDS * Engine.physics_ticks_per_second))


## Note: "propulsion/set-running" = N *starts* engine N (-1 = all), so
## stopping goes through each engine's own set-running.
func start_engines() -> void:
	prop("propulsion/set-running", -1)


func stop_engines() -> void:
	var i := 0
	while jsb.has_property("propulsion/engine[%d]/set-running" % i):
		prop("propulsion/engine[%d]/set-running" % i, 0)
		i += 1


func engine_running() -> bool:
	return prop_get("propulsion/engine/set-running") > 0.5


func set_surface(kind: StringName) -> void:
	surface = kind
	var s: Dictionary = SURFACES.get(kind, SURFACES[&"paved"])
	prop("ground/rolling_friction-factor", s.rolling)
	prop("ground/static-friction-factor", s.static)
	prop("ground/bumpiness", s.bumpiness)


func step() -> bool:
	return jsb.step()


## Global transform of the CG in Godot space.
func cg_transform() -> Transform3D:
	var pos := geo.to_local(
		prop_get("position/lat-geod-deg"),
		prop_get("position/long-gc-deg"),
		prop_get("position/h-sl-ft") * FT)
	var basis := Basis(Vector3.UP, -prop_get("attitude/psi-rad")) \
		* Basis(Vector3.RIGHT, prop_get("attitude/theta-rad")) \
		* Basis(Vector3.BACK, -prop_get("attitude/phi-rad"))
	return Transform3D(basis, pos)


## Offset from the CG to the structural-frame origin, in aircraft-local metres.
func structure_offset() -> Vector3:
	return -Geo.struct_to_local(
		prop_get("inertia/cg-x-in"), prop_get("inertia/cg-y-in"), prop_get("inertia/cg-z-in"))


func is_valid() -> bool:
	var h := prop_get("position/h-sl-ft")
	return is_finite(h) and is_finite(prop_get("attitude/theta-rad"))


func prop(name: String, value: float) -> void:
	jsb.set_property(name, value)


func prop_get(name: String) -> float:
	return jsb.get_property(name)


## Wheels as {index: gear unit, pos: contact point in the structural frame (inches)}.
func wheels() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in int(prop_get("gear/num-units")):
		var base := "gear/unit[%d]/" % i
		if jsb.has_property(base + "x-position"):
			out.append({"index": i, "pos": Vector3(
				prop_get(base + "x-position"), prop_get(base + "y-position"), prop_get(base + "z-position"))})
	return out


# CG height above ground with the lowest wheel just touching.
func _gear_height_ft() -> float:
	var lowest := INF
	for w in wheels():
		lowest = minf(lowest, w.pos.z)
	if lowest == INF:
		return 5.0
	return (prop_get("inertia/cg-z-in") - lowest) / 12.0
