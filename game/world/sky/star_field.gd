class_name StarField
extends Node3D
## The naked-eye sky: Yale Bright Star Catalogue stars (to magnitude 6.5) on a
## far sphere that follows the camera and turns with sidereal time.
## TimeOfDay sets `celestial_basis` (celestial -> world) every frame.

const RADIUS := 60000.0
const CATALOGUE := "res://world/sky/bsc5_stars.txt"

var camera: Camera3D
var celestial_basis := Basis.IDENTITY
var _mmi: MultiMeshInstance3D
var _mat: ShaderMaterial


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://world/sky/star_field.gdshader")
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var stars := _load()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = stars.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1983
	for i in stars.size():
		var s: Vector4 = stars[i]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, _celestial(s.x, s.y) * RADIUS))
		mm.set_instance_color(i, _bv_to_rgb(s.w))
		# Brightness from magnitude, on a perceptual curve: the eye compresses
		# the range, so 6th-magnitude stars are faint but visible and Sirius
		# doesn't blind (linear flux hid ~90% of the naked-eye stars).
		var flux := pow(10.0, -0.4 * s.z)
		var brightness := 1.7 * pow(flux, 0.55)
		var size := clampf(2.0 + 0.9 * (5.0 - s.z), 1.8, 7.0)
		mm.set_instance_custom_data(i, Color(minf(brightness, 8.0), size, rng.randf(), s.z))
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = mm
	_mmi.material_override = _mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.extra_cull_margin = RADIUS * 2.0
	add_child(_mmi)


## Show stars brighter than `limiting_mag` (each fades in over about a
## magnitude as the sky darkens past it); `clear` dims them all for cloud.
func set_visibility(limiting_mag: float, clear: float) -> void:
	_mat.set_shader_parameter("limiting_magnitude", limiting_mag)
	_mat.set_shader_parameter("star_intensity", clear)
	visible = limiting_mag > -1.8 and clear > 0.002


func _process(_delta: float) -> void:
	if camera:
		global_position = camera.global_position
	basis = celestial_basis
	_mat.set_shader_parameter("time", Time.get_ticks_msec() / 1000.0)
	var vp := get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("pixel_scale", vp.y / 1080.0)


# Equatorial (RA, Dec) to the celestial frame: x towards the vernal
# equinox, y towards RA 6h, z towards the north celestial pole.
static func _celestial(ra_deg: float, dec_deg: float) -> Vector3:
	var ra := deg_to_rad(ra_deg)
	var dec := deg_to_rad(dec_deg)
	return Vector3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))


# B-V colour index to an RGB tint via black-body temperature (Ballesteros 2012).
static func _bv_to_rgb(bv: float) -> Color:
	var t := 4600.0 * (1.0 / (0.92 * bv + 1.7) + 1.0 / (0.92 * bv + 0.62))
	# Approximate black-body colour (normalised), from Tanner Helland's fit.
	var k := t / 100.0
	var r := 1.0 if k <= 66.0 else clampf(329.698727446 * pow(k - 60.0, -0.1332047592) / 255.0, 0.0, 1.0)
	var g := clampf((99.4708025861 * log(k) - 161.1195681661) / 255.0, 0.0, 1.0) if k <= 66.0 \
		else clampf(288.1221695283 * pow(k - 60.0, -0.0755148492) / 255.0, 0.0, 1.0)
	var b := 1.0 if k >= 66.0 else (0.0 if k <= 19.0 else clampf((138.5177312231 * log(k - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0))
	# Stars look much less saturated to the eye than black bodies suggest.
	return Color(r, g, b).lerp(Color(1, 1, 1), 0.45)


func _load() -> Array[Vector4]:
	var out: Array[Vector4] = []
	var f := FileAccess.open(CATALOGUE, FileAccess.READ)
	if f == null:
		push_warning("Star catalogue missing: " + CATALOGUE)
		return out
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("#") or line.strip_edges() == "":
			continue
		var p := line.split(",")
		out.append(Vector4(float(p[0]), float(p[1]), float(p[2]), float(p[3])))
	return out
