class_name Landmarks
extends RefCounted
## Props shared by the worlds: the tutorial's radio tower and parking square.


## Red-and-white radio mast with a blinking light, base at `pos`.
static func radio_tower(parent: Node3D, pos: Vector3) -> Node3D:
	var tower := Node3D.new()
	tower.name = "RadioTower"
	tower.position = pos
	parent.add_child(tower)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.15, 0.1)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.95, 0.92)
	var band := 10.0
	for i in 9:
		var seg := MeshInstance3D.new()
		var box := BoxMesh.new()
		var w := 3.0 - i * 0.2
		box.size = Vector3(w, band, w)
		box.material = red if i % 2 == 0 else white
		seg.mesh = box
		seg.position.y = band * (i + 0.5)
		tower.add_child(seg)
	var lamp := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.2
	sphere.height = 2.4
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1, 0.1, 0.05)
	glow.emission_enabled = true
	glow.emission = Color(1, 0.1, 0.05)
	glow.emission_energy_multiplier = 6.0
	sphere.material = glow
	lamp.mesh = sphere
	lamp.position.y = band * 9 + 1.5
	tower.add_child(lamp)
	var blink := Timer.new()
	blink.wait_time = 0.75
	blink.autostart = true
	blink.timeout.connect(func(): lamp.visible = not lamp.visible)
	tower.add_child(blink)
	return tower


## 12 m yellow parking square, painted flat at `xform` (origin = centre).
static func parking_square(parent: Node3D, xform: Transform3D) -> void:
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color(0.95, 0.8, 0.15)
	yellow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for side in [[Vector3(0, 0, -6), Vector3(12, 0.02, 0.4)], [Vector3(0, 0, 6), Vector3(12, 0.02, 0.4)],
			[Vector3(-6, 0, 0), Vector3(0.4, 0.02, 12)], [Vector3(6, 0, 0), Vector3(0.4, 0.02, 12)]]:
		var line := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = side[1]
		box.material = yellow
		line.mesh = box
		line.name = "ParkingLine"
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		line.transform = xform * Transform3D(Basis.IDENTITY, side[0] + Vector3(0, 0.06, 0))
		parent.add_child(line)


## Windsock on a pole at `pos`, driven by `weather`.
static func windsock(parent: Node3D, pos: Vector3, weather: Weather) -> Node3D:
	var sock: Node3D = preload("res://world/windsock.gd").new()
	sock.name = "Windsock"
	sock.position = pos
	sock.weather = weather
	parent.add_child(sock)
	return sock
