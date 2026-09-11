extends SceneTree
const OUTPUT = preload("../addons/scripts/spline_road/topology_output_cache.gd")
var failed := false
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var cache := OUTPUT.new()
	var arrays := _triangles(cache.MAX_CHUNKS)
	_check(cache._partition(arrays, 8).size() == cache.MAX_CHUNKS, "actual maximum chunk count remains supported")
	_check(cache._partition(_triangles(cache.MAX_CHUNKS + 1), 8).is_empty(), "excessive partition count falls back before publication")
	arrays = _triangles(1)
	var invalid := arrays.duplicate(true)
	invalid[Mesh.ARRAY_NORMAL] = null
	_check(cache._partition(invalid, 8).is_empty(), "missing normals use full-output fallback")
	invalid = arrays.duplicate(true)
	invalid[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])
	_check(cache._partition(invalid, 8).is_empty(), "unsupported vertex streams are never silently dropped")
	invalid = arrays.duplicate(true)
	invalid[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 99])
	_check(cache._partition(invalid, 8).is_empty(), "out-of-range indices cannot access invalid vertices")
	invalid = arrays.duplicate(true)
	invalid[Mesh.ARRAY_VERTEX][0] = Vector3(INF, 0, 0)
	_check(cache._partition(invalid, 8).is_empty(), "nonfinite coordinates fall back before cell conversion")
	var builder := Node3D.new()
	root.add_child(builder)
	_check(cache.publish(builder, arrays, 8, false, true, null), "uncached spatial output still publishes valid mesh/collision")
	_check(cache._records.is_empty() and cache.stats.snapshot_bytes == 0, "disabled reuse retains no geometry snapshots")
	_check(cache.publish(builder, arrays, 8, true, true, null), "enabling retention seeds live validation")
	var instance: MeshInstance3D = builder.get_node("GeneratedTopologyTerrain").get_child(0)
	var shape: CollisionShape3D = builder.get_node("GeneratedTopologyTerrainCollision").get_child(0)
	var ids := [instance.get_instance_id(), instance.mesh.get_instance_id(), shape.get_instance_id(), shape.shape.get_instance_id()]
	cache.publish(builder, arrays, 8, true, true, null)
	instance = builder.get_node("GeneratedTopologyTerrain").get_child(0)
	shape = builder.get_node("GeneratedTopologyTerrainCollision").get_child(0)
	_check(ids == [instance.get_instance_id(), instance.mesh.get_instance_id(), shape.get_instance_id(), shape.shape.get_instance_id()], "direct warm publication retains exact resources")
	cache.clear()
	_check(cache._records.is_empty() and cache._roots.is_empty(), "public clear releases geometry and root validation")
	builder.free()
	_raw_publication()
	print("TOPOLOGY_OUTPUT_BOUNDS_%s checks=%d" % ["FAILED" if failed else "OK", checks])
	quit(1 if failed else 0)


func _triangles(count: int) -> Array:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in range(count):
		vertices.append_array(PackedVector3Array([Vector3(i * 16, 0, 0), Vector3(i * 16 + 1, 0, 0), Vector3(i * 16, 0, 1)]))
		for j in range(3):
			normals.append(Vector3.UP)
			uvs.append(Vector2.ZERO)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	return arrays


func _raw_publication() -> void:
	var cache := OUTPUT.new()
	var builder := Node3D.new()
	root.add_child(builder)
	var raw := _triangles(1)
	raw[Mesh.ARRAY_NORMAL] = null
	var before := var_to_bytes(raw)
	var surface := SurfaceTool.new()
	surface.create_from_arrays(raw, Mesh.PRIMITIVE_TRIANGLES)
	surface.generate_normals()
	var reference := surface.commit()
	_check(cache.publish_raw(builder, raw, 8, true, true, null, true) and cache.stats.source_surface_builds == 1,
		"cold raw publication materializes a full source for native normals")
	var instance: MeshInstance3D = builder.get_node("GeneratedTopologyTerrain").get_child(0)
	_check(var_to_bytes(instance.mesh.surface_get_arrays(0)) == var_to_bytes(reference.surface_get_arrays(0)),
		"raw publication matches decoded native full mesh attributes")
	_check(cache.publish_raw(builder, raw, 8, true, true, null, true) and cache.stats.source_surface_builds == 0,
		"warm raw publication creates no full source SurfaceTool")
	_check(cache.publish_raw(builder, raw, 8, true, true, null, false) and cache.stats.source_surface_builds == 1
		and cache.stats.normals.full_calls == 1, "disabled local normals use lazy native full fallback")
	_check(var_to_bytes(raw) == before, "native fallback cannot mutate caller-owned raw arrays")
	var too_many := _triangles(cache.MAX_CHUNKS + 1)
	too_many[Mesh.ARRAY_NORMAL] = null
	_check(not cache.publish_raw(builder, too_many, 8, true, true, null, true)
		and cache.stats.fallback == "unsupported_or_excessive_chunks" and cache.stats.source_surface_builds == 1
		and builder.get_node("GeneratedTopologyTerrain").get_child(0) == instance,
		"actual excessive raw partition falls back without deleting the last complete output")
	builder.free()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)
