extends Node3D
## Phase 0 flat test world: one grass strip on open rough grass, scattered
## trees and a hangar for height and speed cues. Ground is flat at sea level.

@export var origin_lat_deg := 24.0
@export var origin_lon_deg := -78.0
@export var strip_length_m := 800.0
@export var strip_width_m := 25.0
## True heading of the strip, degrees.
@export var strip_heading_deg := 0.0
## Spawn with the engine running (true) or cold and dark (false).
@export var start_engine_running := false
## Aircraft available in the test world; N cycles through them.
@export var aircraft_definitions: Array[AircraftDefinition] = []

var geo: Geo
var aircraft: Aircraft
var _aircraft_index := 0


func _ready() -> void:
	geo = Geo.new(origin_lat_deg, origin_lon_deg)
	$Strip.mesh.size = Vector2(strip_width_m, strip_length_m)
	$Strip.rotation.y = -deg_to_rad(strip_heading_deg)
	_build_strip_markers()
	_build_hangar()
	_scatter_trees()

	_spawn_aircraft(0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("next_aircraft") and aircraft_definitions.size() > 1:
		_spawn_aircraft((_aircraft_index + 1) % aircraft_definitions.size())


func _spawn_aircraft(index: int) -> void:
	if aircraft:
		aircraft.queue_free()
		remove_child(aircraft)
	_aircraft_index = index
	aircraft = preload("res://aircraft/aircraft.tscn").instantiate()
	aircraft.definition = aircraft_definitions[index]
	add_child(aircraft)
	if aircraft.setup(self):
		$CameraRig.target = aircraft
		$CameraRig.recentre()
		$DebugOverlay.aircraft = aircraft


## Start of the strip, facing down it.
func spawn_point() -> Dictionary:
	return {"position": -_strip_dir() * (strip_length_m * 0.5 - 30.0), "heading_deg": strip_heading_deg}


func surface_at(p: Vector3) -> StringName:
	var along := p.dot(_strip_dir())
	var across := p.dot(_strip_dir().cross(Vector3.UP))
	if absf(along) <= strip_length_m * 0.5 and absf(across) <= strip_width_m * 0.5:
		return &"grass_strip"
	return &"grass_rough"


func terrain_height(_p: Vector3) -> float:
	return 0.0


func _strip_dir() -> Vector3:
	var h := deg_to_rad(strip_heading_deg)
	return Vector3(sin(h), 0.0, -cos(h))


func _strip_basis() -> Basis:
	return Basis(Vector3.UP, -deg_to_rad(strip_heading_deg))


func _build_strip_markers() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.6, 0.35, 1.2)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.92, 0.88)
	box.material = mat
	var transforms: Array[Transform3D] = []
	var b := _strip_basis()
	var half_w := strip_width_m * 0.5 + 1.0
	var z := -strip_length_m * 0.5
	while z <= strip_length_m * 0.5 + 0.1:
		for side in [-1.0, 1.0]:
			transforms.append(Transform3D(b, b * Vector3(side * half_w, 0.17, z)))
		z += 50.0
	# Threshold bars at both ends
	for end in [-1.0, 1.0]:
		for i in 6:
			var x := -strip_width_m * 0.5 + (i + 0.5) * strip_width_m / 6.0
			transforms.append(Transform3D(b.scaled(Vector3(2.5, 0.4, 2.5)),
				b * Vector3(x, 0.07, end * (strip_length_m * 0.5 - 3.0))))
	_add_multimesh("StripMarkers", box, transforms, false)


func _build_hangar() -> void:
	var b := _strip_basis()
	var hangar := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(18.0, 6.0, 14.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.53, 0.5)
	mat.roughness = 0.6
	mat.metallic = 0.3
	mesh.material = mat
	hangar.mesh = mesh
	hangar.name = "Hangar"
	hangar.transform = Transform3D(b, b * Vector3(-strip_width_m * 0.5 - 30.0, 3.0, strip_length_m * 0.5 - 60.0))
	add_child(hangar)


func _scatter_trees() -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 2.2
	cone.height = 9.0
	cone.radial_segments = 7
	cone.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.2, 0.08)
	mat.roughness = 1.0
	cone.material = mat
	var rng := RandomNumberGenerator.new()
	rng.seed = 1978
	var b := _strip_basis()
	var transforms: Array[Transform3D] = []
	# Clumps of trees out to 4 km, keeping the strip and its approaches clear.
	for clump in 260:
		var centre := Vector2(rng.randf_range(-4000, 4000), rng.randf_range(-4000, 4000))
		var radius := rng.randf_range(20.0, 120.0)
		for t in rng.randi_range(6, 40):
			var p := centre + Vector2.from_angle(rng.randf() * TAU) * radius * sqrt(rng.randf())
			if absf(p.x) < strip_width_m * 0.5 + 60.0 and absf(p.y) < strip_length_m * 0.5 + 700.0:
				continue
			var s := rng.randf_range(0.7, 1.6)
			var pos := b * Vector3(p.x, cone.height * 0.5 * s, p.y)
			transforms.append(Transform3D(Basis.from_scale(Vector3(s, s, s)), pos))
	_add_multimesh("Trees", cone, transforms, true)


func _add_multimesh(node_name: String, mesh: Mesh, transforms: Array[Transform3D], shadows: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
