extends Node3D
## Phase 1 terrain tile: 16 x 16 km of rolling backcountry with a paved strip
## on the valley floor and a dirt strip up on a ridge. Ground height and
## surface type come from one heightfield and one list of rectangles, shared
## by JSBSim (wheels, friction) and the visuals.
##
## Same interface as the flat test world: geo, spawn_point(), surface_at(),
## terrain_height(), point()/strip_heading()/strip_length()/on_strip() for the
## tutorial, plus ground_at() for slopes.
## Start on the dirt strip with "-- --spawn=dirt".

const AircraftScene := preload("res://aircraft/aircraft.tscn")

## Strips. centre = local metres (x east, z south); heading = true heading of
## the takeoff direction from the spawn end. apron = buildings area beside the
## strip as Rect2(along, across, length, width) in strip metres (across + = right).
const STRIPS := [
	{"name": "valley", "kind": &"paved", "centre": Vector2(0.0, 0.0), "heading_deg": 75.0,
		"length_m": 900.0, "width_m": 18.0, "apron": Rect2(150.0, -95.0, 120.0, 60.0)},
	{"name": "ridge", "kind": &"dirt", "centre": Vector2(1100.0, -3900.0), "heading_deg": 165.0,
		"length_m": 560.0, "width_m": 14.0, "apron": Rect2(-215.0, 16.0, 50.0, 30.0)},
]
const SHOULDER_M := 12.0  # mown grass beside each strip
const OVERRUN_M := 40.0  # mown grass past each end
## Paint kinds shared with terrain.gdshader.
const PAINT := {&"paved": 0, &"dirt": 1, &"apron": 2, &"mown": 3}

@export var origin_lat_deg := 25.6
@export var origin_lon_deg := -99.2
@export var terrain_seed := 1979
## Spawn with the engine running (true) or cold and dark (false).
@export var start_engine_running := false
## Index into STRIPS where the aircraft starts.
@export var spawn_strip := 0
## Ground steeper than this (normal.y below, about 20 degrees) is "rough":
## rock and scrub, both in the shader and in the physics.
@export var rough_normal_y := 0.94
## Tutorial turning point: distance and true bearing from the spawn strip centre.
@export var tower_distance_m := 2200.0
@export var tower_bearing_deg := 110.0
## Aircraft available here; N cycles through them.
@export var aircraft_definitions: Array[AircraftDefinition] = []

var geo: Geo
var aircraft: Aircraft
var weather: Weather
var time_of_day: TimeOfDay
var _lamps: Array[OmniLight3D] = []
var heightfield: TerrainHeightfield
## Set to {"position": Vector3, "heading_deg": float} to spawn somewhere else (tests).
var spawn_override := {}
var strips: Array[Dictionary] = []  # STRIPS plus derived dir, side, elevation
var _rects: Array[Dictionary] = []  # painted / surface rectangles, bottom to top
var _aircraft_index := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--spawn="):
			var want := a.trim_prefix("--spawn=")
			for i in STRIPS.size():
				if STRIPS[i].name == want or String(STRIPS[i].kind) == want:
					spawn_strip = i
	var t0 := Time.get_ticks_msec()
	geo = Geo.new(origin_lat_deg, origin_lon_deg)
	weather = Weather.new()
	weather.name = "Weather"
	add_child(weather)
	_build_heightfield()
	geo.terrain = heightfield.ground_at
	var t1 := Time.get_ticks_msec()
	_build_rects()
	var mat: ShaderMaterial = $Terrain.material
	_setup_material(mat)
	$Terrain.build(heightfield, mat)
	_build_buildings()
	_build_tutorial_props()
	var hangar: Node3D = get_node("Hangar")
	var door: Node3D = get_node("HangarDoor")
	_add_lamp(door.position + (door.position - hangar.position).normalized() * 0.6 + Vector3(0, 3.5, 0))
	_build_strip_markers()
	_scatter_trees()
	print("terrain tile: heights %d ms, visuals %d ms, %d chunks" % [
		t1 - t0, Time.get_ticks_msec() - t1, $Terrain.chunk_count])
	time_of_day = TimeOfDay.new()
	time_of_day.name = "TimeOfDay"
	add_child(time_of_day)
	time_of_day.setup($Sun, $WorldEnvironment.environment, origin_lat_deg)
	_spawn_aircraft(0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("next_aircraft", false, true) and aircraft_definitions.size() > 1:
		_spawn_aircraft((_aircraft_index + 1) % aircraft_definitions.size())


func _spawn_aircraft(index: int) -> void:
	if aircraft:
		aircraft.queue_free()
		remove_child(aircraft)
	_aircraft_index = index
	aircraft = AircraftScene.instantiate()
	aircraft.definition = aircraft_definitions[index]
	add_child(aircraft)
	if aircraft.setup(self):
		$Checklist.set_aircraft(aircraft)
		aircraft.respawned.connect($Checklist.reset)
		$CameraRig.target = aircraft
		$CameraRig.recentre()
		$DebugOverlay.aircraft = aircraft


## World interface -------------------------------------------------------

## Near end of the chosen strip, facing down it.
func spawn_point() -> Dictionary:
	if not spawn_override.is_empty():
		return spawn_override
	var s: Dictionary = strips[spawn_strip]
	var c := _strip_point(s, -s.length_m * 0.5 + 30.0, 0.0)
	return {"position": c, "heading_deg": s.heading_deg}


func terrain_height(p: Vector3) -> float:
	return heightfield.height_at(p.x, p.z)


## Vector4(height, normal.x, normal.y, normal.z) of the ground under p.
func ground_at(p: Vector3) -> Vector4:
	return heightfield.ground_at(p)


## Named places the tutorial checklist refers to (spawn strip).
func point(name: String) -> Vector3:
	var s: Dictionary = strips[spawn_strip]
	var xz: Vector2
	match name:
		"tower":
			var b := deg_to_rad(tower_bearing_deg)
			xz = s.centre + Vector2(sin(b), -cos(b)) * tower_distance_m
		"parking":
			# In front of the hangar door (valley) / beside the tin shed (ridge).
			xz = _strip_xz(s, 210.0, -57.0) if spawn_strip == 0 else _strip_xz(s, -205.0, 30.0)
		_:
			xz = s.centre
	return Vector3(xz.x, heightfield.height_at(xz.x, xz.y), xz.y)


func strip_heading() -> float:
	return strips[spawn_strip].heading_deg


func strip_length() -> float:
	return strips[spawn_strip].length_m


## On a runway surface itself (any strip), for "lined up" and "landed".
func on_strip(p: Vector3) -> bool:
	var xz := Vector2(p.x, p.z)
	for s in strips:
		var d: Vector2 = xz - s.centre
		if absf(d.dot(s.dir)) <= s.length_m * 0.5 and absf(d.dot(s.side)) <= s.width_m * 0.5:
			return true
	return false


func surface_at(p: Vector3) -> StringName:
	var xz := Vector2(p.x, p.z)
	for k in range(_rects.size() - 1, -1, -1):
		var r: Dictionary = _rects[k]
		var d: Vector2 = xz - r.centre
		if absf(d.dot(r.dir)) <= r.half.x and absf(d.dot(r.side)) <= r.half.y:
			return r.surface
	if heightfield.normal_at(p.x, p.z).y < rough_normal_y:
		return &"rough"
	return &"grass_rough"


## Building the tile -----------------------------------------------------

func _build_heightfield() -> void:
	heightfield = TerrainHeightfield.new(16000.0, 10.0, 150.0, terrain_seed)
	for src in STRIPS:
		var s: Dictionary = src.duplicate()
		var h := deg_to_rad(s.heading_deg)
		s.dir = Vector2(sin(h), -cos(h))
		s.side = Vector2(-s.dir.y, s.dir.x)
		strips.append(s)
	heightfield.generate(strips[0].dir)
	for s in strips:
		var half_len: float = s.length_m * 0.5
		s.elevation = heightfield.mean_height_along(s.centre - s.dir * half_len, s.centre + s.dir * half_len)
	for s in strips:
		heightfield.clear_approaches(s.centre, s.dir, s.length_m * 0.5, s.elevation)
	for s in strips:
		heightfield.flatten(s.centre, s.dir, Vector2(s.length_m * 0.5 + OVERRUN_M + 20.0, s.width_m * 0.5 + SHOULDER_M + 8.0),
			s.elevation, 110.0)
		var apron: Rect2 = s.apron
		heightfield.flatten(_strip_xz(s, apron.get_center().x, apron.get_center().y), s.dir,
			apron.size * 0.5 + Vector2(10.0, 10.0), s.elevation, 60.0)


func _build_rects() -> void:
	for s in strips:
		_rects.append(_rect(s.centre, s.dir, Vector2(s.length_m * 0.5 + OVERRUN_M, s.width_m * 0.5 + SHOULDER_M),
			&"mown", &"grass_strip"))
	for s in strips:
		var apron: Rect2 = s.apron
		_rects.append(_rect(_strip_xz(s, apron.get_center().x, apron.get_center().y), s.dir, apron.size * 0.5,
			&"apron", &"dirt"))
	for s in strips:
		_rects.append(_rect(s.centre, s.dir, Vector2(s.length_m, s.width_m) * 0.5, s.kind, s.kind))


func _rect(centre: Vector2, dir: Vector2, half: Vector2, paint: StringName, surface: StringName) -> Dictionary:
	return {"centre": centre, "dir": dir, "side": Vector2(-dir.y, dir.x), "half": half,
		"paint": PAINT[paint], "surface": surface}


func _setup_material(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("heightmap", heightfield.make_texture())
	mat.set_shader_parameter("tile_min", Vector2(heightfield.min_x, heightfield.min_z))
	mat.set_shader_parameter("cell_size", heightfield.cell_m)
	mat.set_shader_parameter("tile_samples", heightfield.n)
	var a := PackedVector4Array()
	var b := PackedVector4Array()
	for r in _rects:
		a.append(Vector4(r.centre.x, r.centre.y, r.dir.x, r.dir.y))
		b.append(Vector4(r.half.x, r.half.y, r.paint, 0.0))
	a.resize(12)
	b.resize(12)
	mat.set_shader_parameter("rect_a", a)
	mat.set_shader_parameter("rect_b", b)
	mat.set_shader_parameter("rect_count", _rects.size())
	mat.set_shader_parameter("rough_normal_y", rough_normal_y)


# Strip coordinates (along, across) to local XZ.
func _strip_xz(s: Dictionary, along: float, across: float) -> Vector2:
	return s.centre + s.dir * along + s.side * across


func _strip_point(s: Dictionary, along: float, across: float) -> Vector3:
	var xz := _strip_xz(s, along, across)
	return Vector3(xz.x, heightfield.height_at(xz.x, xz.y), xz.y)


# Basis facing down the strip (-Z along the takeoff direction).
func _strip_basis(s: Dictionary) -> Basis:
	return Basis(Vector3.UP, -deg_to_rad(s.heading_deg))


func _material(color: Color, roughness := 0.9, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


func _add_mesh(node_name: String, mesh: Mesh, xform: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.transform = xform
	add_child(mi)
	return mi


func _build_buildings() -> void:
	var valley: Dictionary = strips[0]
	var b := _strip_basis(valley)
	# Basis whose -Z points from the apron toward the strip (doors face the strip).
	var face := b * Basis(Vector3.UP, -PI * 0.5)
	# Quonset hangar: half a corrugated tin tube, axis across the strip.
	var tube := CylinderMesh.new()
	tube.top_radius = 8.0
	tube.bottom_radius = 8.0
	tube.height = 22.0
	tube.radial_segments = 18
	tube.rings = 1
	tube.material = _material(Color(0.58, 0.57, 0.53), 0.55, 0.45)
	var hangar_pos := _strip_point(valley, 210.0, -80.0)
	hangar_pos.y = valley.elevation
	_add_mesh("Hangar", tube, Transform3D(face * Basis(Vector3.RIGHT, PI * 0.5), hangar_pos))
	var door := BoxMesh.new()
	door.size = Vector3(11.0, 6.0, 0.2)
	door.material = _material(Color(0.12, 0.11, 0.1))
	_add_mesh("HangarDoor", door, Transform3D(face, hangar_pos + face * Vector3(0.0, 3.0, -11.05)))
	# Wooden shed with a pitched roof.
	_add_shed("Shed", valley, 160.0, -86.0, Vector3(6.0, 3.0, 5.0), Color(0.45, 0.33, 0.22), Color(0.35, 0.3, 0.27))
	# Fuel tank on legs.
	var tank := CylinderMesh.new()
	tank.top_radius = 1.2
	tank.bottom_radius = 1.2
	tank.height = 4.5
	tank.radial_segments = 14
	tank.material = _material(Color(0.82, 0.8, 0.72), 0.6, 0.2)
	var tank_pos := _strip_point(valley, 258.0, -62.0)
	tank_pos.y = valley.elevation + 2.0
	_add_mesh("FuelTank", tank, Transform3D(b * Basis(Vector3.BACK, PI * 0.5), tank_pos))
	var leg := BoxMesh.new()
	leg.size = Vector3(0.3, 0.9, 2.2)
	leg.material = _material(Color(0.3, 0.28, 0.25))
	for off in [-1.5, 1.5]:
		_add_mesh("TankLeg", leg, Transform3D(b, tank_pos + b * Vector3(off, -1.35, 0.0)))
	_add_drums(valley, 168.0, -78.0, 5)

	var ridge: Dictionary = strips[1]
	_add_shed("TinShed", ridge, -195.0, 36.0, Vector3(4.5, 2.6, 3.5), Color(0.5, 0.42, 0.36), Color(0.48, 0.3, 0.2))
	_add_drums(ridge, -205.0, 24.0, 7)


func _build_tutorial_props() -> void:
	Landmarks.radio_tower(self, point("tower"))
	var s: Dictionary = strips[spawn_strip]
	Landmarks.parking_square(self, Transform3D(_strip_basis(s), point("parking")))
	for st in strips:
		# Beside each strip, a third of the way down, clear of the runway.
		var p: Vector3 = _strip_point(st, -st.length_m * 0.2, st.width_m * 0.5 + SHOULDER_M + 6.0)
		p.y = st.elevation
		Landmarks.windsock(self, p, weather)


func _add_shed(node_name: String, s: Dictionary, along: float, across: float, size: Vector3, wall: Color, roof: Color) -> void:
	var b := _strip_basis(s)
	var pos := _strip_point(s, along, across)
	pos.y = s.elevation
	var box := BoxMesh.new()
	box.size = size
	box.material = _material(wall)
	_add_mesh(node_name, box, Transform3D(b, pos + Vector3(0.0, size.y * 0.5, 0.0)))
	var prism := PrismMesh.new()
	prism.size = Vector3(size.x + 0.6, 1.4, size.z + 0.6)
	prism.material = _material(roof, 0.5, 0.4)
	_add_mesh(node_name + "Roof", prism, Transform3D(b, pos + Vector3(0.0, size.y + 0.7, 0.0)))


func _add_drums(s: Dictionary, along: float, across: float, count: int) -> void:
	var drum := CylinderMesh.new()
	drum.top_radius = 0.3
	drum.bottom_radius = 0.3
	drum.height = 0.9
	drum.radial_segments = 10
	drum.rings = 1
	var colors := [Color(0.55, 0.12, 0.08), Color(0.2, 0.3, 0.45), Color(0.45, 0.42, 0.35)]
	var b := _strip_basis(s)
	var transforms: Array[Transform3D] = []
	var tints: Array[Color] = []
	for i in count:
		var p := _strip_point(s, along + (i % 4) * 0.7, across + floorf(i / 4.0) * 0.7)
		p.y = s.elevation + 0.45
		transforms.append(Transform3D(b, p))
		tints.append(colors[i % colors.size()])
	_add_multimesh("Drums", drum, _material(Color.WHITE, 0.6, 0.3), transforms, tints, true)


# Old tyres painted white along the dirt strip edges, every 60 m.
func _build_strip_markers() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.22
	torus.outer_radius = 0.45
	torus.rings = 12
	torus.ring_segments = 6
	var transforms: Array[Transform3D] = []
	var tints: Array[Color] = []
	for s in strips:
		if s.kind != &"dirt":
			continue
		var along: float = -s.length_m * 0.5
		while along <= s.length_m * 0.5 + 0.1:
			for side in [-1.0, 1.0]:
				var p := _strip_point(s, along, side * (s.width_m * 0.5 + 1.5))
				p.y = s.elevation + 0.08
				transforms.append(Transform3D(Basis.IDENTITY, p))
				tints.append(Color(0.9, 0.9, 0.86))
			along += 60.0
	_add_multimesh("StripTyres", torus, _material(Color.WHITE, 0.8), transforms, tints, false)


func _scatter_trees() -> void:
	var conifer := CylinderMesh.new()
	conifer.top_radius = 0.0
	conifer.bottom_radius = 2.2
	conifer.height = 9.0
	conifer.radial_segments = 7
	conifer.rings = 1
	var broadleaf := SphereMesh.new()
	broadleaf.radius = 3.2
	broadleaf.height = 5.0
	broadleaf.radial_segments = 7
	broadleaf.rings = 4
	var mat := _material(Color.WHITE, 1.0)
	var density := FastNoiseLite.new()
	density.seed = terrain_seed + 10
	density.frequency = 0.0011
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed
	# Trees go into 2 km blocks so distant blocks can be culled.
	var blocks := {}
	for clump in 4200:
		var centre := Vector2(rng.randf_range(-14000.0, 14000.0), rng.randf_range(-14000.0, 14000.0))
		var r := centre.length()
		var on_tile := r < 7800.0
		var chance := 0.12 if not on_tile else 0.2 + 0.8 * clampf(density.get_noise_2d(centre.x, centre.y) + 0.5, 0.0, 1.0)
		if r > 14000.0 or rng.randf() > chance:
			continue
		var radius := rng.randf_range(25.0, 160.0)
		for t in rng.randi_range(6, 50):
			var p := centre + Vector2.from_angle(rng.randf() * TAU) * radius * sqrt(rng.randf())
			if _tree_blocked(p):
				continue
			var h := heightfield.height_at(p.x, p.y)
			var steep := heightfield.normal_at(p.x, p.y).y < 0.9
			var is_conifer := h > 300.0 or steep or rng.randf() < 0.25
			var s := rng.randf_range(0.7, 1.5)
			var key := Vector2i(floori(p.x / 2000.0), floori(p.y / 2000.0))
			if not blocks.has(key):
				blocks[key] = [[], [], [], []]  # conifer xforms, tints, broadleaf xforms, tints
			var g := rng.randf_range(0.75, 1.15)
			if is_conifer:
				blocks[key][0].append(Transform3D(Basis.from_scale(Vector3(s, s * rng.randf_range(0.85, 1.25), s)),
					Vector3(p.x, h + conifer.height * 0.5 * s - 0.4, p.y)))
				blocks[key][1].append(Color(0.1 * g, 0.19 * g, 0.08 * g))
			else:
				blocks[key][2].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)),
					Vector3(p.x, h + broadleaf.height * 0.45 * s, p.y)))
				blocks[key][3].append(Color(0.17 * g, 0.24 * g, 0.09 * g))
	var count := 0
	for key in blocks:
		var arr: Array = blocks[key]
		for kind in 2:
			var xf: Array[Transform3D] = []
			xf.assign(arr[kind * 2])
			var tints: Array[Color] = []
			tints.assign(arr[kind * 2 + 1])
			if xf.is_empty():
				continue
			var mmi := _add_multimesh("Trees", conifer if kind == 0 else broadleaf, mat, xf, tints, true)
			mmi.visibility_range_end = 9000.0
			count += xf.size()
	print("terrain tile: %d trees" % count)


# Keep strips, their approaches and the building areas clear of trees.
func _tree_blocked(p: Vector2) -> bool:
	for s in strips:
		var d: Vector2 = p - s.centre
		var along := absf(d.dot(s.dir))
		var across := d.dot(s.side)
		var half_len: float = s.length_m * 0.5
		if absf(across) < s.width_m * 0.5 + 45.0 and along < half_len + 90.0:
			return true
		var t := along - half_len
		if t > 0.0 and t < 1800.0 and absf(across) < 60.0 + 0.18 * t:
			return true
		var apron: Rect2 = s.apron
		if apron.grow(25.0).has_point(Vector2(d.dot(s.dir), across)):
			return true
	return false


func _add_multimesh(node_name: String, mesh: Mesh, mat: Material, transforms: Array[Transform3D],
		tints: Array[Color], shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, tints[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	(mat as StandardMaterial3D).vertex_color_use_as_albedo = true
	(mat as StandardMaterial3D).vertex_color_is_srgb = true
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi, true)
	return mmi


## A warm lamp (hangar door) that comes on at dusk.
func _add_lamp(pos: Vector3) -> void:
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.position = pos
	lamp.light_color = Color(1.0, 0.72, 0.4)
	lamp.omni_range = 28.0
	lamp.light_energy = 2.5
	lamp.shadow_enabled = false
	add_child(lamp)
	var bulb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	var m := StandardMaterial3D.new()
	m.emission_enabled = true
	m.emission = lamp.light_color
	m.emission_energy_multiplier = 6.0
	m.albedo_color = lamp.light_color
	sphere.material = m
	bulb.mesh = sphere
	lamp.add_child(bulb)
	_lamps.append(lamp)


func _process(_delta: float) -> void:
	var on := time_of_day != null and time_of_day.darkness() > 0.3
	for lamp in _lamps:
		lamp.visible = on
