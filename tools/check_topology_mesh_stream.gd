extends SceneTree
const STREAM = preload("../addons/scripts/spline_road/topology_mesh_stream.gd")
class SmallStream extends "../addons/scripts/spline_road/topology_mesh_stream.gd":
	func _vertex_limit() -> int:
		return 9
var checks := 0
var failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for stream in [STREAM.new(), SmallStream.new()]:
		for enabled in [false, true]:
			for flipped in [false, true]:
				var target := SurfaceTool.new()
				target.begin(Mesh.PRIMITIVE_TRIANGLES)
				var reference := SurfaceTool.new()
				reference.begin(Mesh.PRIMITIVE_TRIANGLES)
				stream.begin(target, enabled)
				for i in range(7):
					var a := Vector3(i, 0, 0)
					var b := Vector3(i + 1, 0, 0)
					var c := Vector3(i, i * 0.3, 1)
					var vertices := PackedVector3Array([c, b, a] if flipped else [a, b, c])
					var uvs := PackedVector2Array()
					for v: Vector3 in vertices:
						uvs.append(Vector2(v.x * 0.05, v.z * 0.05))
					var buffered := false
					if i % 2 == 0:
						buffered = stream.append_triangle(target, a, b, c, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z), flipped)
					else:
						buffered = stream.append_block(target, vertices, uvs)
					for j in range(3):
						reference.set_uv(uvs[j])
						reference.add_vertex(vertices[j])
						if not buffered:
							target.set_uv(uvs[j])
							target.add_vertex(vertices[j])
				stream.flush()
				_check(var_to_bytes(target.commit_to_arrays()) == var_to_bytes(reference.commit_to_arrays()), "raw vertex/UV order matches individual emission")
				target.generate_normals()
				reference.generate_normals()
				_check(var_to_bytes(target.commit_to_arrays()) == var_to_bytes(reference.commit_to_arrays()), "native smooth normals remain byte-identical")
				_check(stream.target == null and stream._vertices.is_empty() and stream._uvs.is_empty(), "flush releases transient stream")
				if enabled and stream is SmallStream:
					_check(stream.stats.capacity_fallback, "capacity pressure flushes prefix and continues native emission")
	_boundaries()
	_direct_arrays()
	print("TOPOLOGY_MESH_STREAM_%s checks=%d" % ["FAILED" if failed else "OK", checks])
	quit(1 if failed else 0)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(label)


func _boundaries() -> void:
	var stream := STREAM.new()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var foreign := SurfaceTool.new()
	foreign.begin(Mesh.PRIMITIVE_TRIANGLES)
	stream.begin(surface, true)
	_check(not stream.append_vertex(foreign, Vector3.ZERO, Vector2.ZERO), "another SurfaceTool cannot enter this job's stream")
	_check(not stream.append_block(surface, PackedVector3Array([Vector3.ZERO]), PackedVector2Array()), "mismatched blocks are not appended")
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(stream.MAX_VERTICES)
	uvs.resize(stream.MAX_VERTICES)
	for i in range(vertices.size()):
		vertices[i] = Vector3(i % 3, i / 3, i % 2)
		uvs[i] = Vector2(i * 0.05, i % 3)
	_check(stream.append_block(surface, vertices, uvs) and stream._vertices.size() == stream.MAX_VERTICES,
		"actual 393216-vertex buffer limit accepts complete prefix")
	var negative_zero := -float(checks) * 0.0
	var extra := Vector3(negative_zero, 3, negative_zero)
	var extra_uv := Vector2(negative_zero, negative_zero)
	_check(not stream.append_vertex(surface, extra, extra_uv) and stream.stats.capacity_fallback,
		"first vertex beyond actual limit flushes prefix and selects native fallback")
	surface.set_uv(extra_uv)
	surface.add_vertex(extra)
	vertices.append(extra)
	uvs.append(extra_uv)
	# Complete the triangle on the native path after the overflow.
	for i in range(2):
		surface.set_uv(Vector2.ZERO)
		surface.add_vertex(Vector3(i, 4, 0))
		vertices.append(Vector3(i, 4, 0))
		uvs.append(Vector2.ZERO)
	stream.flush()
	var actual := surface.commit_to_arrays()
	_check(var_to_bytes(actual[Mesh.ARRAY_VERTEX]) == var_to_bytes(vertices) and var_to_bytes(actual[Mesh.ARRAY_TEX_UV]) == var_to_bytes(uvs),
		"actual capacity fallback preserves complete coordinates, UVs and signed zero")
	stream.begin(foreign, true)
	_check(stream._vertices.is_empty() and stream.target == foreign, "next job starts with a fresh stream")
	stream.append_vertex(foreign, extra, extra_uv)
	stream.clear()
	_check(stream.target == null and stream._vertices.is_empty() and stream.stats.is_empty(), "clear releases an unfinished stream")


func _direct_arrays() -> void:
	var stream := STREAM.new()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var foreign := SurfaceTool.new()
	foreign.begin(Mesh.PRIMITIVE_TRIANGLES)
	stream.begin(surface, true)
	_check(stream.take_arrays(surface).is_empty(), "empty stream has no direct transfer")
	var negative_zero := -float(checks) * 0.0
	var vertices := PackedVector3Array([Vector3(negative_zero, 0, negative_zero), Vector3.RIGHT, Vector3.FORWARD])
	var uvs := PackedVector2Array([Vector2(negative_zero, negative_zero), Vector2.RIGHT, Vector2.DOWN])
	stream.append_block(surface, vertices, uvs)
	_check(stream.take_arrays(foreign).is_empty() and stream._vertices.size() == 3,
		"foreign surface cannot take or discard a pending raw stream")
	var raw := stream.take_arrays(surface)
	_check(var_to_bytes(raw[Mesh.ARRAY_VERTEX]) == var_to_bytes(vertices) and var_to_bytes(raw[Mesh.ARRAY_TEX_UV]) == var_to_bytes(uvs),
		"direct transfer preserves raw vertex/UV bits including signed zero")
	_check(stream.target == null and stream._vertices.is_empty() and stream._uvs.is_empty()
		and stream.stats.direct_arrays and stream.stats.flushes == 1, "direct transfer releases the job and is counted once")
	_check(stream.take_arrays(surface).is_empty(), "direct transfer cannot be consumed twice")
	# The original SurfaceTool remains empty and begun, not populated and closed.
	for i in range(3):
		surface.set_uv(uvs[i])
		surface.add_vertex(vertices[i])
	_check(var_to_bytes(surface.commit_to_arrays()) == var_to_bytes(raw), "direct transfer does not materialize the source SurfaceTool")
	stream.begin(foreign, true)
	stream.append_vertex(foreign, Vector3(99, 99, 99), Vector2.ONE)
	_check(raw[Mesh.ARRAY_VERTEX] == vertices and raw[Mesh.ARRAY_TEX_UV] == uvs, "next job cannot mutate transferred packed arrays")
	stream.clear()
