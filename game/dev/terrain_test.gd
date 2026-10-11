extends Node
## Checks that JSBSim sees the same ground as the terrain you see.
## godot --headless --path game --fixed-fps 120 res://dev/terrain_test.tscn [-- --aircraft=1]
##  1. JSBSim's terrain elevation under the aircraft = the rendered terrain.
##  2. Parked with brakes on gentle slopes (across and along the slope),
##     every wheel is on the ground and touches the terrain under it.
##  3. Surfaces: paved, dirt, mown grass, open grass and rough are all found.
## "-- --flat-contact" shows the old behaviour (level ground at the CG height):
## expected to fail on slopes.

const SETTLE_TICKS := 600  # 5 s at 120 Hz
const MAX_GAP_M := 0.06

var world: Node3D
var failures := 0


func _ready() -> void:
	FlightInput.joysticks_enabled = false
	world = load("res://world/terrain_tile/terrain_tile.tscn").instantiate()
	add_child(world)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--aircraft="):
			world._spawn_aircraft(int(a.trim_prefix("--aircraft=")))
	print("aircraft: ", world.aircraft.definition.display_name)
	if "--flat-contact" in OS.get_cmdline_user_args():
		world.geo.terrain = Callable()
	_check_surfaces()
	var spots := _find_slopes(3)
	if spots.size() < 3:
		_fail("found only %d slope test spots" % spots.size())
	FlightInput.parking_brake = true
	for spot in spots:
		var n: Vector3 = world.heightfield.normal_at(spot.x, spot.z)
		var downhill := Vector2(n.x, n.z).normalized()
		var down_hdg := rad_to_deg(atan2(downhill.x, -downhill.y))
		var slope := rad_to_deg(acos(n.y))
		for case in [["across", down_hdg + 90.0], ["nose uphill", down_hdg + 180.0]]:
			await _park(spot, wrapf(case[1], 0.0, 360.0), "%.1f deg slope, %s" % [slope, case[0]])
	FlightInput.parking_brake = false
	print("TERRAIN TEST: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(1 if failures else 0)


func _park(spot: Vector3, heading: float, label: String) -> void:
	var ac: Aircraft = world.aircraft
	world.spawn_override = {"position": spot, "heading_deg": heading}
	ac.respawn()
	FlightInput.parking_brake = true
	var start := ac.global_position
	for i in SETTLE_TICKS:
		await get_tree().physics_frame
	var f := ac.fdm
	# 1. JSBSim's own terrain elevation under the CG vs the rendered ground.
	var jsb_ground := f.prop_get("position/terrain-elevation-asl-ft") * FDM.FT
	var our_ground: float = world.terrain_height(ac.global_position)
	if absf(jsb_ground - our_ground) > 0.01:
		_fail("%s: JSBSim ground %.3f m vs terrain %.3f m" % [label, jsb_ground, our_ground])
	# 2. Each wheel: weight on it, and its contact point on the terrain.
	var gaps := []
	var up := ac.global_basis.y
	for k in ac.airframe._wheels.size():
		var w: MeshInstance3D = ac.airframe._wheels[k]
		var unit: int = ac.airframe._wheel_units[k]
		var radius: float = (w.mesh as CylinderMesh).top_radius
		var contact: Vector3 = w.global_position - up * radius
		var gap: float = contact.y - world.terrain_height(contact)
		gaps.append("%+.3f" % gap)
		if f.prop_get("gear/unit[%d]/WOW" % unit) < 0.5:
			_fail("%s: wheel %d carries no weight (gap %.3f m)" % [label, unit, gap])
		elif absf(gap) > MAX_GAP_M:
			_fail("%s: wheel %d is %.3f m off the ground" % [label, unit, gap])
	var slid := ac.global_position.distance_to(start)
	print("%-28s roll %5.1f pitch %5.1f  wheel gaps %s m  moved %.2f m  surface %s" % [
		label, f.prop_get("attitude/phi-deg"), f.prop_get("attitude/theta-deg"),
		" ".join(gaps), slid, f.surface])
	if slid > 1.5:
		_fail("%s: rolled %.2f m with the brakes on" % [label, slid])


# Gentle, fairly even slopes away from the strips. (Steeper than ~9 deg, the
# 172 parked nose-uphill sits back on its tail: a real 172 does that too.)
func _find_slopes(count: int) -> Array[Vector3]:
	var hf: TerrainHeightfield = world.heightfield
	var out: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for attempt in 20000:
		var p := Vector2(rng.randf_range(-5000.0, 5000.0), rng.randf_range(-5000.0, 5000.0))
		if world._tree_blocked(p):
			continue
		var n := hf.normal_at(p.x, p.y)
		if n.y < 0.9915 or n.y > 0.9962:  # about 5 to 7.5 degrees
			continue
		var even := true
		for o in [Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6), Vector2(4, 4), Vector2(-4, -4)]:
			if hf.normal_at(p.x + o.x, p.y + o.y).dot(n) < 0.9995:
				even = false
		if even:
			out.append(Vector3(p.x, hf.height_at(p.x, p.y), p.y))
			if out.size() >= count:
				break
	return out


func _check_surfaces() -> void:
	var found := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for s in world.strips:
		found[world.surface_at(Vector3(s.centre.x, 0.0, s.centre.y))] = true
		var shoulder: Vector2 = s.centre + s.side * (s.width_m * 0.5 + 5.0)
		found[world.surface_at(Vector3(shoulder.x, 0.0, shoulder.y))] = true
	for i in 4000:
		found[world.surface_at(Vector3(rng.randf_range(-7000, 7000), 0.0, rng.randf_range(-7000, 7000)))] = true
	print("surfaces found: ", found.keys())
	for want in [&"paved", &"dirt", &"grass_strip", &"grass_rough", &"rough"]:
		if not found.has(want):
			_fail("surface %s never found" % want)
		elif not FDM.SURFACES.has(want):
			_fail("surface %s has no friction data in FDM.SURFACES" % want)


func _fail(msg: String) -> void:
	failures += 1
	print("FAIL: ", msg)
