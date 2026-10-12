# Anemos - weather and cloud system for Godot.
# Copyright (c) 2026 Nikolas Korakidis. All rights reserved. See addons/anemos/LICENSE.md.
class_name AnemosLightning
extends Node3D
## Lightning you can see: cloud-to-ground bolts (jagged, branching, a few
## return strokes), and the flash lighting the ground, the sky and (through
## AnemosClouds) the inside of the storm. In-cloud flashes only light things up.

const FLICKER := [[0.0, 0.05, 1.0], [0.09, 0.05, 0.8], [0.18, 0.09, 1.0], [0.33, 0.18, 0.6]]  # start, length, level

var anemos: Anemos
var weather: AnemosWeather
var _bolts: Array[Dictionary] = []  # {node, light, t, power, cg}
var _sky_flash := 0.0
## Dev: keep bolts lit at full strength (screenshots).
var hold := false


func _init(a: Anemos) -> void:
	anemos = a
	weather = a.weather
	name = "Lightning"


func _ready() -> void:
	weather.lightning.connect(strike)


## A flash at `at` (world). Cloud-to-ground draws a bolt down from the cloud base.
func strike(at: Vector3, to_ground: bool, power: float) -> void:
	var b := {"t": 0.0, "power": power, "cg": to_ground, "node": null}
	var light := OmniLight3D.new()
	light.shadow_enabled = false
	light.light_color = Color(0.82, 0.86, 1.0)
	light.omni_range = 7000.0 if to_ground else 4500.0
	light.omni_attenuation = 1.2
	light.light_energy = 0.0
	add_child(light)
	var base_y := weather.field_elevation_m + weather.cloud_base_m
	if to_ground:
		var ground_y := at.y
		var mesh := MeshInstance3D.new()
		mesh.mesh = _bolt_mesh(Vector3(at.x, base_y, at.z), ground_y, power)
		# Very bright emission so the channel blooms; drawn as a transparent
		# glow after the fog (a bolt shines through rain). One material per
		# bolt to flicker it.
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.disable_fog = true
		mat.emission_enabled = true
		mat.emission = Color(0.82, 0.86, 1.0)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.vertex_color_use_as_albedo = false
		mat.disable_receive_shadows = true
		mesh.material_override = mat
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
		b.node = mesh
		light.global_position = Vector3(at.x, lerpf(ground_y, base_y, 0.4), at.z)
	else:
		light.global_position = Vector3(at.x, maxf(at.y, base_y + 800.0), at.z)
	b.light = light
	_bolts.append(b)


func _process(delta: float) -> void:
	_sky_flash = 0.0
	for i in range(_bolts.size() - 1, -1, -1):
		var b: Dictionary = _bolts[i]
		b.t += delta
		var level := 0.0
		for f in FLICKER:
			var x: float = (b.t - f[0]) / f[1]
			if x >= 0.0 and x <= 1.0:
				level = maxf(level, f[2] * (1.0 - x * 0.6))
		if hold:
			level = 1.0
		elif b.t > 0.6:
			b.light.queue_free()
			if b.node:
				b.node.queue_free()
			_bolts.remove_at(i)
			continue
		var p: float = b.power
		b.light.light_energy = level * p * (60.0 if b.cg else 25.0)
		if b.node:
			b.node.visible = level > 0.05
			var m: StandardMaterial3D = (b.node as MeshInstance3D).material_override
			# Against the eye's night adaptation, or the bloom swallows the channel.
			var eye: float = anemos.sky.anemos_exposure()
			m.emission_energy_multiplier = level * p * 60.0 / pow(eye, 1.6)
		var cam := anemos.view_camera()
		var d := cam.global_position.distance_to(b.light.global_position) if cam else 5000.0
		_sky_flash = maxf(_sky_flash, level * p * clampf(6000.0 / maxf(d, 500.0), 0.0, 1.5) * (1.0 if b.cg else 0.6))
	if anemos.sky.has_method("anemos_flash"):
		anemos.sky.anemos_flash(_sky_flash)


# Jagged channel from the cloud base to the ground (midpoint displacement),
# with a few branches; drawn as two crossed glowing ribbons.
func _bolt_mesh(top: Vector3, ground_y: float, power: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pts := [top, Vector3(top.x, ground_y, top.z)]
	var rough := (top.y - ground_y) * 0.18
	for level in 6:
		var next := [pts[0]]
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var c: Vector3 = pts[i + 1]
			var m := (a + c) * 0.5 + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 0.2), rng.randf_range(-1, 1)) * rough
			next.append(m)
			next.append(c)
		pts = next
		rough *= 0.55
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var width := 14.0 * clampf(power, 0.5, 1.5)
	_ribbon(st, pts, width)
	# Branches: shorter, fainter forks off the upper part.
	for k in rng.randi_range(2, 4):
		var start: int = rng.randi_range(4, pts.size() / 2)
		var branch := [pts[start]]
		var dir := Vector3(rng.randf_range(-1, 1), -1.0, rng.randf_range(-1, 1)).normalized()
		var p: Vector3 = pts[start]
		for s in rng.randi_range(6, 12):
			p += (dir + Vector3(rng.randf_range(-0.6, 0.6), 0.0, rng.randf_range(-0.6, 0.6))) * rng.randf_range(40.0, 110.0)
			branch.append(p)
		_ribbon(st, branch, width * 0.5)
	return st.commit()


func _ribbon(st: SurfaceTool, pts: Array, width: float) -> void:
	for axis in [Vector3.RIGHT, Vector3.BACK]:
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var off: Vector3 = axis * width * 0.5
			st.add_vertex(a - off)
			st.add_vertex(a + off)
			st.add_vertex(b + off)
			st.add_vertex(a - off)
			st.add_vertex(b + off)
			st.add_vertex(b - off)
