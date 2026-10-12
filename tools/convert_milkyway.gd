extends SceneTree
## One-off: NASA SVS "Deep Star Maps 2020" milkyway_2020_4k.exr (public domain)
## -> game/world/sky/milkyway_4k.webp, encoded so 8 bits keep the faint glow.
##   godot --headless -s tools/convert_milkyway.gd -- <in.exr> <out.webp>
## The shader decodes: linear = pow(texel, 2.2) * MILKYWAY_SCALE (printed below).

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var img := Image.load_from_file(args[0])
	img.convert(Image.FORMAT_RGBF)
	var w := img.get_width()
	var h := img.get_height()
	# Luminance percentiles from a sample of pixels.
	var lum: Array[float] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in 200000:
		var c := img.get_pixel(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1))
		lum.append(0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b)
	lum.sort()
	var p999: float = lum[int(lum.size() * 0.999)]
	print("luminance median %.6f  p99 %.6f  p99.9 %.6f  max %.6f" % [lum[lum.size() / 2], lum[int(lum.size() * 0.99)], p999, lum[-1]])
	var scale := p999
	var out := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y) / scale
			out.set_pixel(x, y, Color(pow(clampf(c.r, 0.0, 1.0), 1.0 / 2.2), pow(clampf(c.g, 0.0, 1.0), 1.0 / 2.2), pow(clampf(c.b, 0.0, 1.0), 1.0 / 2.2)))
	out.save_webp(args[1], true, 0.92)
	print("MILKYWAY_SCALE = %.8f" % scale)
	quit()
