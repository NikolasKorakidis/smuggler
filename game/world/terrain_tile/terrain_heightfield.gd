class_name TerrainHeightfield
extends RefCounted
## One square terrain tile as a regular height grid. The same grid drives the
## physics (JSBSim ground contact) and the visuals (vertex shader), so wheels
## meet exactly the ground you see. Between samples the ground is the two
## triangles of each cell, split along the same diagonal as the render mesh.
## Outside the tile the ground is a flat plain.

var size_m: float
var cell_m: float
var n: int  # samples per side
var min_x: float
var min_z: float
var plain_height: float
var heights := PackedFloat32Array()

var _inv_cell: float
var _hills := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _fine := FastNoiseLite.new()


func _init(tile_size_m := 16000.0, cell_size_m := 10.0, plain_m := 150.0, noise_seed := 1979) -> void:
	size_m = tile_size_m
	cell_m = cell_size_m
	_inv_cell = 1.0 / cell_m
	n = int(round(size_m / cell_m)) + 1
	min_x = -size_m * 0.5
	min_z = -size_m * 0.5
	plain_height = plain_m
	for nz in [_hills, _ridge, _detail, _fine]:
		nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		nz.seed = noise_seed
	_hills.frequency = 0.00032
	_hills.fractal_octaves = 4
	_ridge.seed = noise_seed + 1
	_ridge.frequency = 0.00021
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 4
	_detail.seed = noise_seed + 2
	_detail.frequency = 0.0032
	_detail.fractal_octaves = 2
	_fine.seed = noise_seed + 3
	_fine.frequency = 0.013
	_fine.fractal_octaves = 1


## Undisturbed landscape: rolling hills, a broad valley through the middle
## (along valley_dir), a ridge line to the north, flattening into the plain
## at the tile edge.
func natural_height(x: float, z: float, valley_dir: Vector2) -> float:
	var p := Vector2(x, z)
	var along := p.dot(valley_dir)
	var across := p.dot(Vector2(-valley_dir.y, valley_dir.x)) + 350.0 * sin(along / 1900.0)
	var valley := exp(-pow(across / 1300.0, 2.0))
	var hills := _hills.get_noise_2d(x, z)
	# Mountains build up toward the north, away from the valley.
	var ridge_mask := smoothstep(-3000.0, 5000.0, -z * 0.8 - x * 0.35) * (1.0 - valley)
	var h := 215.0 + hills * 150.0 * (1.0 - 0.65 * valley) - 75.0 * valley
	if ridge_mask > 0.001:
		var ridge := (_ridge.get_noise_2d(x, z) + 1.0) * 0.5
		h += ridge * ridge * 330.0 * ridge_mask
	h += _detail.get_noise_2d(x, z) * 6.0 + _fine.get_noise_2d(x, z) * 1.2
	# Ragged edge into the plain; every sample on the tile border is plain.
	var edge := smoothstep(5200.0, 7400.0, p.length() + 400.0 * hills)
	return lerpf(h, plain_height, edge)


func generate(valley_dir: Vector2) -> void:
	var rows := []
	rows.resize(n)
	var task := WorkerThreadPool.add_group_task(_natural_row.bind(rows, valley_dir), n)
	WorkerThreadPool.wait_for_group_task_completion(task)
	heights = PackedFloat32Array()
	for r in rows:
		heights.append_array(r)


func _natural_row(j: int, rows: Array, valley_dir: Vector2) -> void:
	var z := min_z + j * cell_m
	var row := PackedFloat32Array()
	row.resize(n)
	for i in n:
		row[i] = natural_height(min_x + i * cell_m, z, valley_dir)
	rows[j] = row


## Mean natural height along a line: used to level a strip into the terrain.
func mean_height_along(a: Vector2, b: Vector2) -> float:
	var total := 0.0
	var steps := 24
	for k in steps + 1:
		var p := a.lerp(b, float(k) / steps)
		total += height_at(p.x, p.y)
	return total / (steps + 1)


## Levels an oriented rectangle to `elevation`, blending into the
## surrounding ground over `falloff` metres. dir = unit vector along the
## rectangle's length; half = (half length, half width).
func flatten(centre: Vector2, dir: Vector2, half: Vector2, elevation: float, falloff: float) -> void:
	var side := Vector2(-dir.y, dir.x)
	var b := _bounds(centre, half.length() + falloff)
	for j in range(b.position.y, b.end.y + 1):
		for i in range(b.position.x, b.end.x + 1):
			var d := Vector2(min_x + i * cell_m, min_z + j * cell_m) - centre
			var dx := maxf(absf(d.dot(dir)) - half.x, 0.0)
			var dz := maxf(absf(d.dot(side)) - half.y, 0.0)
			var dist := sqrt(dx * dx + dz * dz)
			if dist < falloff:
				var k := j * n + i
				heights[k] = lerpf(heights[k], elevation, 1.0 - smoothstep(0.0, falloff, dist))


## Cuts terrain that sticks up into a strip's approach and climb-out paths
## (about a 3 degree slope from each end, out to 4 km), so both ends are flyable.
func clear_approaches(centre: Vector2, dir: Vector2, half_len: float, elevation: float) -> void:
	var side := Vector2(-dir.y, dir.x)
	var b := _bounds(centre, half_len + 4000.0)
	for j in range(b.position.y, b.end.y + 1):
		for i in range(b.position.x, b.end.x + 1):
			var d := Vector2(min_x + i * cell_m, min_z + j * cell_m) - centre
			var t := absf(d.dot(dir)) - half_len
			if t <= 0.0 or t >= 4000.0:
				continue
			var k := j * n + i
			var excess := heights[k] - (elevation + 6.0 + 0.055 * t)
			if excess <= 0.0:
				continue
			var hw := 80.0 + 0.12 * t
			var w := (1.0 - smoothstep(hw, hw + 350.0, absf(d.dot(side)))) \
				* (1.0 - smoothstep(3000.0, 4000.0, t))
			heights[k] -= excess * w


# Sample index bounds (inclusive) of a square around centre.
func _bounds(centre: Vector2, reach: float) -> Rect2i:
	var i0 := clampi(int(floor((centre.x - reach - min_x) * _inv_cell)), 0, n - 1)
	var i1 := clampi(int(ceil((centre.x + reach - min_x) * _inv_cell)), 0, n - 1)
	var j0 := clampi(int(floor((centre.y - reach - min_z) * _inv_cell)), 0, n - 1)
	var j1 := clampi(int(ceil((centre.y + reach - min_z) * _inv_cell)), 0, n - 1)
	return Rect2i(i0, j0, i1 - i0, j1 - j0)


## Ground height at a local position (metres).
func height_at(x: float, z: float) -> float:
	var fx := (x - min_x) * _inv_cell
	var fz := (z - min_z) * _inv_cell
	if fx < 0.0 or fz < 0.0 or fx >= n - 1 or fz >= n - 1:
		return plain_height
	var i := int(fx)
	var j := int(fz)
	var u := fx - i
	var v := fz - j
	var k := j * n + i
	if u + v <= 1.0:
		var h00 := heights[k]
		return h00 + (heights[k + 1] - h00) * u + (heights[k + n] - h00) * v
	var h11 := heights[k + n + 1]
	return h11 + (heights[k + n] - h11) * (1.0 - u) + (heights[k + 1] - h11) * (1.0 - v)


## Vector4(height, normal.x, normal.y, normal.z) of the ground triangle under p.
func ground_at(p: Vector3) -> Vector4:
	var fx := (p.x - min_x) * _inv_cell
	var fz := (p.z - min_z) * _inv_cell
	if fx < 0.0 or fz < 0.0 or fx >= n - 1 or fz >= n - 1:
		return Vector4(plain_height, 0.0, 1.0, 0.0)
	var i := int(fx)
	var j := int(fz)
	var u := fx - i
	var v := fz - j
	var k := j * n + i
	var h: float
	var dhdx: float
	var dhdz: float
	if u + v <= 1.0:
		var h00 := heights[k]
		dhdx = heights[k + 1] - h00
		dhdz = heights[k + n] - h00
		h = h00 + dhdx * u + dhdz * v
	else:
		var h11 := heights[k + n + 1]
		dhdx = h11 - heights[k + n]
		dhdz = h11 - heights[k + 1]
		h = h11 - dhdx * (1.0 - u) - dhdz * (1.0 - v)
	var nrm := Vector3(-dhdx * _inv_cell, 1.0, -dhdz * _inv_cell).normalized()
	return Vector4(h, nrm.x, nrm.y, nrm.z)


func normal_at(x: float, z: float) -> Vector3:
	var g := ground_at(Vector3(x, 0.0, z))
	return Vector3(g.y, g.z, g.w)


## Lowest and highest sample inside a local rectangle.
func height_range(r: Rect2) -> Vector2:
	var lo := INF
	var hi := -INF
	var i0 := clampi(int(floor((r.position.x - min_x) * _inv_cell)), 0, n - 1)
	var i1 := clampi(int(ceil((r.end.x - min_x) * _inv_cell)), 0, n - 1)
	var j0 := clampi(int(floor((r.position.y - min_z) * _inv_cell)), 0, n - 1)
	var j1 := clampi(int(ceil((r.end.y - min_z) * _inv_cell)), 0, n - 1)
	for j in range(j0, j1 + 1):
		var row := j * n
		for i in range(i0, i1 + 1):
			var h := heights[row + i]
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return Vector2(lo, hi)


## The grid as a 32-bit float texture for the terrain shader.
func make_texture() -> ImageTexture:
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RF, heights.to_byte_array())
	return ImageTexture.create_from_image(img)
