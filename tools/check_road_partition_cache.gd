extends SceneTree
const CACHE = preload("../addons/scripts/spline_road/road_partition_cache.gd")
const OUTPUT = preload("../addons/scripts/spline_road/road_runtime_output.gd")
var checks := 0
var failed := false
var output := OUTPUT.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var source: Array = []
	source.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for cell in range(20):
		for vertex in [Vector3(0, 0, 0), Vector3(3, 0.2, 0), Vector3(1, 0, 4), Vector3(0, 0, 0)]:
			vertices.append(vertex + Vector3(cell * 16 - 100, 0, cell % 3 * 16))
			normals.append(Vector3(0.1, 1, 0.2).normalized())
			uvs.append(Vector2(vertex.x * 0.1, vertex.z * 0.1))
		indices.append_array(PackedInt32Array([cell * 4, cell * 4 + 1, cell * 4 + 2,
			cell * 4 + 3, cell * 4 + 2, cell * 4 + 1]))
	source[Mesh.ARRAY_VERTEX] = vertices
	source[Mesh.ARRAY_NORMAL] = normals
	source[Mesh.ARRAY_TEX_UV] = uvs
	source[Mesh.ARRAY_INDEX] = indices
	var cache := CACHE.new()
	_compare(cache, source, 16.0, "cold")
	_compare(cache, source, 16.0, "warm")
	_check(cache.stats.cells_rebuilt == 0 and cache.stats.cells_reused > 10, "warm partition retains every cell")
	for edit in range(12):
		vertices[1] += Vector3(0.15, 0.03, 0)
		source[Mesh.ARRAY_VERTEX] = vertices
		_compare(cache, source, 16.0, "local edit " + str(edit))
		_check(cache.stats.cells_reused > cache.stats.cells_rebuilt and cache.stats.centroids_rebuilt == 2,
			"only triangles using changed source indices need new centroids")
	normals[1] = Vector3.RIGHT
	source[Mesh.ARRAY_NORMAL] = normals
	_compare(cache, source, 16.0, "normal-only edit")
	_check(cache.stats.centroids_rebuilt == 0 and cache.stats.cells_rebuilt > 0, "normal edit does not recompute positions")
	uvs[2] += Vector2(0.25, -0.5)
	source[Mesh.ARRAY_TEX_UV] = uvs
	_compare(cache, source, 16.0, "UV-only edit")
	_check(cache.stats.centroids_rebuilt == 0 and cache.stats.cells_rebuilt > 0, "UV edit invalidates the owning cells")
	# Remove the original cell and create distant positive/negative cells.
	for offset in [Vector3(320, 16, 0), Vector3(-640, -32, -48)]:
		for vertex in range(4):
			vertices[vertex] += offset
		source[Mesh.ARRAY_VERTEX] = vertices
		_compare(cache, source, 16.0, "cell migration " + str(offset))
	for size in [4.0, 7.3, 64.0, 16.0]:
		_compare(cache, source, size, "changed fractional cell size " + str(size))
	indices.reverse()
	source[Mesh.ARRAY_INDEX] = indices
	_compare(cache, source, 16.0, "reordered triangles")
	indices.resize(indices.size() - 6)
	source[Mesh.ARRAY_INDEX] = indices
	_compare(cache, source, 16.0, "removed triangles")
	indices.append_array(PackedInt32Array([0, 1, 2, 5]))
	source[Mesh.ARRAY_INDEX] = indices
	_compare(cache, source, 16.0, "inserted triangle with ignored incomplete tail")
	vertices[0] = Vector3(-0.0, 0.0, 0.0)
	source[Mesh.ARRAY_VERTEX] = vertices
	uvs[0] = Vector2(-0.0, 0.0)
	source[Mesh.ARRAY_TEX_UV] = uvs
	_compare(cache, source, 16.0, "signed zero")
	var delivered: Dictionary = cache.partition(source, 16.0)
	delivered.cells[delivered.cells.keys()[0]][Mesh.ARRAY_VERTEX].fill(Vector3.INF)
	_compare(cache, source, 16.0, "returned arrays cannot mutate retained cells")
	cache.clear()
	_compare(cache, source, 16.0, "explicit clear")
	_check(cache.stats.cells_reused == 0, "clear removes partition reuse")
	vertices[0] = Vector3.INF
	source[Mesh.ARRAY_VERTEX] = vertices
	_check(cache.partition(source, 16.0).is_empty() and cache._cells.is_empty(), "nonfinite geometry bypasses and clears storage")
	vertices[0] = Vector3.ZERO
	source[Mesh.ARRAY_VERTEX] = vertices
	_compare(cache, source, 16.0, "finite geometry after bypass")
	indices[0] = -1
	source[Mesh.ARRAY_INDEX] = indices
	_check(cache.partition(source, 16.0).is_empty(), "invalid indices bypass before indexing")
	vertices.resize(CACHE.MAX_VERTICES + 1)
	source[Mesh.ARRAY_VERTEX] = vertices
	_check(cache.partition(source, 16.0).is_empty() and cache.stats.fallback == "capacity", "vertex limit bypasses allocation")
	source[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	source[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	source[Mesh.ARRAY_TEX_UV] = PackedVector2Array()
	source[Mesh.ARRAY_INDEX] = PackedInt32Array()
	_compare(cache, source, 16.0, "empty surface")
	_compare(cache, source, 16.0, "empty warm surface")
	_check_limits_and_slots()
	print("ROAD_PARTITION_CACHE_%s checks=%d" % ["FAILED" if failed else "OK", checks])
	quit(1 if failed else 0)


func _check_limits_and_slots() -> void:
	var cache := CACHE.new()
	var small := _isolated_cells(2)
	for size in [0.0, -1.0, INF, NAN]:
		_check(cache.partition(small, size).is_empty(), "invalid cell size bypasses")
	var bad := small.duplicate(true)
	bad[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	_check(cache.partition(bad, 16.0).is_empty(), "attribute length mismatch bypasses")
	bad = small.duplicate(true)
	var indices := PackedInt32Array()
	indices.resize((CACHE.MAX_TRIANGLES + 1) * 3)
	indices.fill(0)
	bad[Mesh.ARRAY_INDEX] = indices
	_check(cache.partition(bad, 16.0).is_empty() and cache.stats.fallback == "capacity", "triangle cap bypasses")
	indices.resize(105000 * 3)
	bad[Mesh.ARRAY_INDEX] = indices
	_check(cache.partition(bad, 16.0).is_empty() and cache.stats.fallback == "capacity", "byte cap bypasses below triangle cap")
	var at_limit := _isolated_cells(CACHE.MAX_CELLS)
	_compare(cache, at_limit, 16.0, "cell capacity boundary")
	var boundary_vertices: PackedVector3Array = at_limit[Mesh.ARRAY_VERTEX]
	for index in [255, 256, 257, boundary_vertices.size() - 1]:
		boundary_vertices[index].y += 0.25
		at_limit[Mesh.ARRAY_VERTEX] = boundary_vertices
		_compare(cache, at_limit, 16.0, "changed comparison-block boundary " + str(index))
		_check(cache.stats.centroids_rebuilt == 1, "block-boundary change touches one centroid")
	var over_limit := _isolated_cells(CACHE.MAX_CELLS + 1)
	_check(cache.partition(over_limit, 16.0).is_empty() and cache.stats.fallback == "capacity"
		and cache._cells.is_empty() and cache._words.is_empty(), "cell overflow drops retained storage")
	_compare(cache, small, 16.0, "small surface recovers after pressure")
	var merged := small.duplicate(true)
	var merged_vertices: PackedVector3Array = merged[Mesh.ARRAY_VERTEX]
	for vertex in range(3):
		merged_vertices[vertex].x += 32
	merged[Mesh.ARRAY_VERTEX] = merged_vertices
	_compare(cache, merged, 16.0, "first cell merges into existing cell")
	_check(cache._cells.size() == 1, "merged cell removes old key")
	_compare(cache, small, 16.0, "cell split restores original insertion order")
	merged = small.duplicate(true)
	var signed_uvs: PackedVector2Array = merged[Mesh.ARRAY_TEX_UV]
	var negative_zero := PackedInt32Array([-2147483648]).to_byte_array().decode_float(0)
	signed_uvs[0] = Vector2(negative_zero, 0.0)
	_check(signed_uvs.to_byte_array().to_int32_array()[0] == -2147483648, "fixture really changes the sign bit of zero")
	merged[Mesh.ARRAY_TEX_UV] = signed_uvs
	_compare(cache, merged, 16.0, "positive-to-negative zero attribute bits")
	_check(cache.stats.cells_rebuilt == 1 and cache.stats.centroids_rebuilt == 0, "signed-zero-only UV edit invalidates exactly one cell")
	var mesh := ArrayMesh.new()
	mesh.set_meta("_roda_direct_output", true)
	mesh.set_meta("_roda_output_arrays", [small, small, small, small, small])
	output._partition_active = true
	for pass_index in range(2):
		_check(var_to_bytes(output._partition(mesh, 16.0)) == var_to_bytes(output._partition_native(mesh, 16.0)),
			"five-surface slot ordering matches native " + str(pass_index))
	_check(output._partition_caches.size() == 5, "at most five stores are retained")
	mesh.set_meta("_roda_output_arrays", [small])
	output._partition(mesh, 16.0)
	_check(output._partition_caches.size() == 1, "removed surface stores are released")
	mesh.set_meta("_roda_output_arrays", [small, over_limit])
	_check(var_to_bytes(output._partition(mesh, 16.0)) == var_to_bytes(output._partition_native(mesh, 16.0)),
		"later surface overflow uses exact whole native fallback")
	_check(output._partition_caches.is_empty() and output._partition_stats[0].cells_reused == 0
		and output._partition_stats[0].native_fallback, "fallback releases stores and does not claim partial reuse")
	mesh.set_meta("_roda_output_arrays", [small, small, small, small, small, small])
	_check(var_to_bytes(output._partition(mesh, 16.0)) == var_to_bytes(output._partition_native(mesh, 16.0))
		and output._partition_caches.is_empty(), "six surfaces use uncached native output")
	mesh.set_meta("_roda_output_arrays", [small])
	output._partition(mesh, 16.0)
	output._partition_active = false
	_check(var_to_bytes(output._partition(mesh, 16.0)) == var_to_bytes(output._partition_native(mesh, 16.0))
		and output._partition_caches.is_empty(), "disabled partition releases stores and uses native output")
	output._partition_active = true
	output._partition(mesh, 16.0)
	output.clear_partition_cache()
	_check(output._partition_caches.is_empty() and output._partition_stats.is_empty(), "public partition clear releases all state")


func _isolated_cells(count: int) -> Array:
	var source: Array = []
	source.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for cell in range(count):
		for corner in [Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD]:
			indices.append(vertices.size())
			vertices.append(Vector3(cell * 32, 1, 2) + corner)
			normals.append(Vector3.UP)
			uvs.append(Vector2.ZERO)
	source[Mesh.ARRAY_VERTEX] = vertices
	source[Mesh.ARRAY_NORMAL] = normals
	source[Mesh.ARRAY_TEX_UV] = uvs
	source[Mesh.ARRAY_INDEX] = indices
	return source


func _compare(cache: RefCounted, source: Array, size: float, label: String) -> void:
	var mesh := ArrayMesh.new()
	mesh.set_meta("_roda_direct_output", true)
	mesh.set_meta("_roda_output_arrays", [source])
	mesh.set_meta("_roda_output_materials", [null])
	var expected: Dictionary = output._partition_native(mesh, size)
	var result: Dictionary = cache.partition(source, size)
	_check(not result.is_empty(), "cache admits " + label)
	if result.is_empty():
		return
	var actual: Dictionary = {}
	for cell in result.cells:
		actual[cell] = [result.cells[cell]]
	_check(var_to_bytes(actual) == var_to_bytes(expected), "native partition bytes and order match: " + label)
	_check(cache.stats.payload_bound <= CACHE.MAX_BYTES, "bounded snapshot: " + label)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(label)
