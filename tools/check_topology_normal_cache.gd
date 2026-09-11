extends SceneTree
const NORMALS = preload("../addons/scripts/spline_road/topology_normal_cache.gd")
const OUTPUT = preload("../addons/scripts/spline_road/topology_output_cache.gd")
var failed := false
var checks := 0
var output := OUTPUT.new()
var direct := NORMALS.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var cache := NORMALS.new()
	var arrays := _grid()
	_compare(cache, arrays, "cold native normal pass")
	_check(cache.stats.full_calls == 1, "cold build uses the complete native normal pass")
	_compare(cache, arrays, "warm unchanged normals")
	_check(cache.stats.full_calls == 0 and cache.stats.patch_calls == 0 and cache.stats.vertices_reused > 0, "warm replay skips partitioning and native normal work")
	var old := arrays.duplicate(true)
	for edit in range(12):
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in range(vertices.size()):
			if vertices[i].x == 30 and vertices[i].z == 30:
				vertices[i].y += 0.125
		arrays[Mesh.ARRAY_VERTEX] = vertices
		_compare(cache, arrays, "local shared-corner edit " + str(edit))
		_check(cache.stats.patch_calls == 1 and cache.stats.full_calls == 0 and cache.stats.vertices_reused > 0 and cache.stats.vertices_rebuilt > 0,
			"local native stencil retains normals outside the complete dirty-vertex stars")
	var changed_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	changed_uvs[0] += Vector2.ONE
	arrays[Mesh.ARRAY_TEX_UV] = changed_uvs
	_compare(cache, arrays, "UV-only edit")
	_check(cache.stats.full_calls == 0 and cache.stats.patch_calls == 0, "UV changes do not alter smooth-group-zero normals")
	arrays[Mesh.ARRAY_VERTEX] = arrays[Mesh.ARRAY_VERTEX].slice(3)
	arrays[Mesh.ARRAY_TEX_UV] = arrays[Mesh.ARRAY_TEX_UV].slice(3)
	_compare(cache, arrays, "removed triangle and its former neighbours")
	_check(cache.stats.patch_calls == 1 and cache.stats.vertices_reused > 0, "triangle removal invalidates normals at old shared vertices")
	# Restore exact old positions, then regroup global triangle order while
	# preserving each cell's own triangle subsequence. Geometry alone cannot prove
	# that floating-point smoothing order stayed the same.
	arrays = old
	_compare(cache, arrays, "restore geometry")
	var grouped: Dictionary = output._partition_data(arrays, 16, true).cells
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	for cell: Vector2i in grouped:
		vertices.append_array(grouped[cell][Mesh.ARRAY_VERTEX])
		uvs.append_array(grouped[cell][Mesh.ARRAY_TEX_UV])
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	_compare(cache, arrays, "cross-cell triangle reordering")
	_check(cache.stats.full_calls == 1 and cache.stats.fallback == "unchanged_triangle_reordering", "changed global accumulation order cannot reuse unchanged cell normals")
	var result := cache.prepare(_surface(arrays), arrays, 16, output._partition_data)
	result[result.keys()[0]][Mesh.ARRAY_NORMAL][0] = Vector3(8, 9, 10)
	_compare(cache, arrays, "mutating returned cells cannot poison retained normals")
	cache.clear()
	_check(cache._cells.is_empty() and cache._order.is_empty() and cache._input.is_empty(), "clear releases every retained normal dependency")
	var oversized := arrays.duplicate(true)
	var many := PackedVector3Array()
	many.resize(cache.MAX_VERTICES + 3)
	oversized[Mesh.ARRAY_VERTEX] = many
	_check(cache.prepare(SurfaceTool.new(), oversized, 16, output._partition_data).is_empty() and cache.stats.fallback == "vertex_limit", "oversized raw inputs bypass normal retention")
	_compare(cache, _grid(), "recovery after capacity fallback")
	var random := RandomNumberGenerator.new()
	random.seed = 180321
	var patches := 0
	for scenario in range(6):
		arrays = _grid()
		vertices = arrays[Mesh.ARRAY_VERTEX]
		var offset := Vector3(scenario * 100, 0, -scenario * 75)
		for i in range(vertices.size()):
			vertices[i] += offset
		arrays[Mesh.ARRAY_VERTEX] = vertices
		_compare(cache, arrays, "translated seed " + str(scenario))
		for edit in range(8):
			vertices = arrays[Mesh.ARRAY_VERTEX]
			var index := random.randi_range(0, vertices.size() - 1)
			var target := vertices[index]
			var delta := Vector3(random.randf_range(-3, 3), random.randf_range(-2, 2), random.randf_range(-3, 3))
			for i in range(vertices.size()):
				if i == index or (edit % 2 == 0 and vertices[i] == target):
					vertices[i] += delta
			arrays[Mesh.ARRAY_VERTEX] = vertices
			_compare(cache, arrays, "random merged/split corner %d/%d" % [scenario, edit])
			patches += int(cache.stats.patch_calls > 0)
	_check(patches >= 30, "randomized translated split/merged vertices exercise actual native patches")
	vertices = arrays[Mesh.ARRAY_VERTEX]
	uvs = arrays[Mesh.ARRAY_TEX_UV]
	vertices.append_array(vertices.slice(0, 3))
	uvs.append_array(uvs.slice(0, 3))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	_compare(cache, arrays, "duplicate triangle contribution multiplicity")
	vertices.append_array(PackedVector3Array([vertices[0], vertices[0], vertices[1]]))
	uvs.append_array(PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ONE]))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	_compare(cache, arrays, "degenerate triangle alongside valid shared normals")
	print("TOPOLOGY_NORMAL_CACHE_%s checks=%d" % ["FAILED" if failed else "OK", checks])
	quit(1 if failed else 0)


func _compare(cache: RefCounted, arrays: Array, label: String) -> void:
	var actual: Dictionary = cache.prepare(_surface(arrays), arrays, 16, output._partition_data)
	var reference := _surface(arrays)
	reference.generate_normals()
	var expected: Dictionary = output._partition(reference.commit_to_arrays(), 16)
	_check(not actual.is_empty() and var_to_bytes(actual) == var_to_bytes(expected), "byte-exact native position/UV/normal cells: " + label)
	var lazy: Dictionary = direct.prepare(null, arrays, 16, output._partition_data)
	_check(var_to_bytes(lazy) == var_to_bytes(expected), "direct raw arrays preserve native normals: " + label)
	_check(direct.stats.source_surface_builds == direct.stats.full_calls,
		"direct arrays construct a complete SurfaceTool only for full native normal work: " + label)
	print("TOPOLOGY_NORMAL_CASE ", label, " ", cache.stats)


func _surface(arrays: Array) -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.create_from_arrays(arrays, Mesh.PRIMITIVE_TRIANGLES)
	return surface


func _grid() -> Array:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	for x in range(8):
		for z in range(8):
			var a := _point(x, z)
			var b := _point(x + 1, z)
			var c := _point(x, z + 1)
			var d := _point(x + 1, z + 1)
			vertices.append_array(PackedVector3Array([a, b, c, b, d, c]))
	for p: Vector3 in vertices:
		uvs.append(Vector2(p.x, p.z) * 0.05)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	return arrays


func _point(x: int, z: int) -> Vector3:
	return Vector3(x * 10, sin(float(x) * 0.23) * cos(float(z) * 0.43) * 3, z * 10)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)
