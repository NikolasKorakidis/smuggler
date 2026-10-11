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
	&"dirt": {"rolling": 1.8, "static": 0.8, "bumpiness": 0.2},
	&"rough": {"rolling": 6.0, "static": 0.55, "bumpiness": 0.6},
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
	_connect_ground()
	var g := geo.to_geo(local_pos)
	prop("ic/lat-geod-deg", g.x)
	prop("ic/long-gc-deg", g.y)
	prop("ic/terrain-elevation-ft", terrain_m / FT)
	prop("ic/h-agl-ft", _gear_height_ft())
	prop("ic/psi-true-deg", heading_deg)
	var tilt := _ground_tilt_deg(local_pos, heading_deg)
	prop("ic/theta-deg", tilt.x)
	prop("ic/phi-deg", tilt.y)
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


# Real terrain under every contact point when the world provides it.
func _connect_ground() -> void:
	if not jsb.has_method("set_ground_callback"):
		if geo.terrain.is_valid():
			push_warning("JSBSim bridge is out of date: run scripts/build_extension.sh. Ground will be flat.")
		return
	jsb.set_ground_callback(_ground_query if geo.terrain.is_valid() else Callable())


# (pitch, roll) in degrees that lay the aircraft parallel to the ground at a
# spawn point, so no wheel starts buried on a slope. Level without terrain.
func _ground_tilt_deg(local_pos: Vector3, heading_deg: float) -> Vector2:
	if not geo.terrain.is_valid():
		return Vector2.ZERO
	var g: Vector4 = geo.terrain.call(local_pos)
	var n := Vector3(g.y, g.z, g.w)
	var h := deg_to_rad(heading_deg)
	var fwd := Vector3(sin(h), 0.0, -cos(h))
	var right := Vector3(cos(h), 0.0, sin(h))
	# Ground rising ahead = nose up; rising to the right = right wing up (negative roll).
	return Vector2(rad_to_deg(atan(-n.dot(fwd) / n.y)), -rad_to_deg(atan(-n.dot(right) / n.y)))


# Called by JSBSim for each ground contact. Returns elevation (m) and the
# surface normal as (east, north, up).
func _ground_query(lat_deg: float, lon_deg: float) -> Vector4:
	var g: Vector4 = geo.terrain.call(geo.to_local(lat_deg, lon_deg, 0.0))
	return Vector4(g.x, g.y, -g.w, g.z)


# CG height above ground with the lowest wheel just touching.
func _gear_height_ft() -> float:
	var lowest := INF
	for w in wheels():
		lowest = minf(lowest, w.pos.z)
	if lowest == INF:
		return 5.0
	return (prop_get("inertia/cg-z-in") - lowest) / 12.0
