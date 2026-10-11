extends Node3D
## Windsock: swings downwind and fills out with the wind (limp when calm,
## straight out at ~15 kt), gusts included. Reads the world's Weather.

const POLE_M := 6.0

var weather: Weather
var _sock: Node3D
var _t := 0.0


func _ready() -> void:
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.6, 0.6, 0.58)
	grey.metallic = 0.5
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.07
	cyl.height = POLE_M
	cyl.material = grey
	pole.mesh = cyl
	pole.position.y = POLE_M * 0.5
	add_child(pole)
	_sock = Node3D.new()
	_sock.position.y = POLE_M - 0.2
	add_child(_sock)
	# Three orange/white bands tapering away from the hoop along -Z.
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(0.95, 0.4, 0.1)
	orange.cull_mode = BaseMaterial3D.CULL_DISABLED
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.94, 0.9)
	white.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 3:
		var band := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.42 - i * 0.1
		c.bottom_radius = 0.32 - i * 0.1
		c.height = 1.0
		c.cap_top = false
		c.cap_bottom = false
		c.material = orange if i % 2 == 0 else white
		band.mesh = c
		band.rotation.x = -PI / 2
		band.position.z = -0.5 - i * 1.0
		_sock.add_child(band)


func _process(delta: float) -> void:
	if weather == null:
		return
	_t += delta
	var v := weather.air_velocity(POLE_M)
	var speed_kt := Vector2(v.x, v.z).length() / 0.514444
	var fill := clampf(speed_kt / 15.0, 0.0, 1.0)
	if speed_kt > 0.3:
		# Point the sock's tail (-Z) the way the air goes.
		_sock.rotation.y = atan2(-v.x, -v.z)
	var droop := lerpf(deg_to_rad(80.0), deg_to_rad(4.0), fill)
	droop += sin(_t * (3.0 + fill * 6.0)) * deg_to_rad(2.0 + 4.0 * fill)
	_sock.rotation.x = -droop
