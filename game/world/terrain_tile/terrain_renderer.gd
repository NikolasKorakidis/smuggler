extends Node3D
## Draws a TerrainHeightfield as square chunks with distance LODs. All chunks
## of one LOD share a single flat grid mesh; the shader lifts each vertex to
## the height grid, so nothing is rebuilt on the CPU. Skirts hide the small
## gaps where neighbouring chunks use different LODs. Outside the tile a flat
## ring reaches to the horizon.

const CHUNK_M := 800.0
## Grid spacing per LOD (multiples of the height grid cell) and the distance
## (to the chunk centre) at which each LOD hands over to the next.
const LOD_SPACING := [1, 2, 4, 8, 16]
const LOD_END_M := [1300.0, 2600.0, 5200.0, 10400.0, 0.0]
const FAR_M := 120000.0

@export var material: ShaderMaterial

var chunk_count := 0


func build(hf: TerrainHeightfield, material: ShaderMaterial) -> void:
	var per_side := int(round(hf.size_m / CHUNK_M))
	var meshes: Array[ArrayMesh] = []
	for spacing in LOD_SPACING:
		var step_m: float = spacing * hf.cell_m
		meshes.append(_grid_mesh(int(round(CHUNK_M / step_m)), step_m, 3.0 + step_m * 0.4))
	for cj in per_side:
		for ci in per_side:
			var origin := Vector3(hf.min_x + ci * CHUNK_M, 0.0, hf.min_z + cj * CHUNK_M)
			var hr := hf.height_range(Rect2(origin.x, origin.z, CHUNK_M, CHUNK_M))
			var skirt := 3.0 + LOD_SPACING[-1] * hf.cell_m * 0.4
			var aabb := AABB(Vector3(0.0, hr.x - skirt, 0.0), Vector3(CHUNK_M, hr.y - hr.x + skirt, CHUNK_M))
			for lod in meshes.size():
				var mi := MeshInstance3D.new()
				mi.name = "C%d_%d_L%d" % [ci, cj, lod]
				mi.mesh = meshes[lod]
				mi.material_override = material
				mi.position = origin
				mi.custom_aabb = aabb
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.visibility_range_begin = 0.0 if lod == 0 else LOD_END_M[lod - 1]
				mi.visibility_range_end = LOD_END_M[lod]
				add_child(mi)
			chunk_count += 1
	_build_far_ring(hf, material)


## Flat grid of q x q quads, spacing s, with a skirt hanging `skirt` metres
## down from the edge. Each quad splits along the (i+1, j)-(i, j+1) diagonal,
## the same split TerrainHeightfield uses for physics.
func _grid_mesh(q: int, s: float, skirt: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var row := q + 1
	for j in row:
		for i in row:
			verts.append(Vector3(i * s, 0.0, j * s))
			uv2.append(Vector2.ZERO)
	for j in q:
		for i in q:
			var a := j * row + i
			idx.append_array([a, a + 1, a + row, a + 1, a + row + 1, a + row])
	# Skirt: walk the perimeter, drop a copy of each edge vertex.
	var ring: Array[int] = []
	for i in q:
		ring.append(i)
	for j in q:
		ring.append(j * row + q)
	for i in range(q, 0, -1):
		ring.append(q * row + i)
	for j in range(q, 0, -1):
		ring.append(j * row)
	var base := verts.size()
	for k in ring.size():
		verts.append(verts[ring[k]])
		uv2.append(Vector2(skirt, 0.0))
	for k in ring.size():
		var t0: int = ring[k]
		var t1: int = ring[(k + 1) % ring.size()]
		var b0 := base + k
		var b1 := base + (k + 1) % ring.size()
		# Both windings so the skirt shows from either side.
		idx.append_array([t0, t1, b0, t1, b1, b0, t0, b0, t1, t1, b0, b1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# Eight big flat quads around the tile, out to FAR_M. The shader clamps to
# the tile edge, which is exactly the plain height.
func _build_far_ring(hf: TerrainHeightfield, material: ShaderMaterial) -> void:
	var edges := [-FAR_M, hf.min_x, hf.min_x + hf.size_m, FAR_M]
	var verts := PackedVector3Array()
	var uv2 := PackedVector2Array()
	for j in 3:
		for i in 3:
			if i == 1 and j == 1:
				continue
			var x0: float = edges[i]
			var x1: float = edges[i + 1]
			var z0: float = edges[j]
			var z1: float = edges[j + 1]
			verts.append_array([Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x0, 0, z1),
				Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)])
	for v in verts.size():
		uv2.append(Vector2.ZERO)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "FarRing"
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-FAR_M, hf.plain_height - 1.0, -FAR_M), Vector3(2.0 * FAR_M, 2.0, 2.0 * FAR_M))
	add_child(mi)
