extends SceneTree

const GROUPS = preload("../addons/scripts/spline_road/topology_triangle_cache.gd")
const SOURCE = preload("../addons/scripts/spline_road/topology_stage_cache.gd")
const STREAM = preload("../addons/scripts/spline_road/topology_mesh_stream.gd")
class SmallStream extends "../addons/scripts/spline_road/topology_mesh_stream.gd":
	func _vertex_limit() -> int:
		return 6
var failed := false
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var cache := GROUPS.new()
	var source := SOURCE.new()
	cache.configure(true, false)
	source.configure(true, false)
	source.prepare_segments({Vector2i.ZERO: [0]}, [{"height": 1.0}])
	source.prepare_edges({}, [])
	var points := PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2(0, 1),
		Vector2(64, 0), Vector2(65, 0), Vector2(64, 1)])
	var indices := PackedInt32Array([0, 1, 2, 3, 4, 5, 0, 2, 1])
	var prepared: Dictionary = cache.prepare(points, indices)
	_check(prepared.groups.size() == 2 and prepared.ids == PackedInt32Array([0, 1, 0])
		and prepared.slots == PackedInt32Array([0, 0, 1]), "spatial groups preserve interleaved global emission mapping")
	var settings := var_to_bytes([1.0])
	for i in range(3):
		var group: Dictionary = prepared.groups[prepared.ids[i]]
		cache.resolve(group, settings, [], source)
		_check(not group.hit, "cold interleaved triangle is not replayed")
		source.begin_mesh_scope(group.scope)
		source.capture_bounds(Vector4i.ZERO)
		cache.record(group, prepared.slots[i], i != 1, "crossing" if i == 1 else "",
			Vector3(0, i, 0), Vector3(1, i, 0), Vector3(0, i, 1), source)
		if i == 0:
			_check(cache._records.is_empty(), "partly filled group cannot become a persistent result")
	_check(source._mesh_scope.is_empty() and cache._records.size() == 2, "completed interleaved scopes are closed and stored")
	prepared = cache.prepare(points, indices)
	for group: Dictionary in prepared.groups:
		cache.resolve(group, settings, [], source)
		_check(group.hit, "unchanged group replays exact proof")
	_check(prepared.groups[0].vertices[3].y == 2 and prepared.groups[1].reasons[0] == "crossing",
		"recorded slot vertices and rejection reasons preserve original processing order")
	prepared.groups[0].vertices[0] = Vector3(99, 99, 99)
	prepared.groups[0].accepted[0] = 0
	var fresh: Dictionary = cache.prepare(points, indices).groups[0]
	cache.resolve(fresh, settings, [], source)
	_check(fresh.hit and fresh.vertices[0] == Vector3.ZERO and fresh.accepted[0] == 1,
		"mutating resolved group cannot poison persistent result")
	var changed: Dictionary = cache.prepare(points, indices).groups[0]
	cache.resolve(changed, var_to_bytes([2.0]), [], source)
	_check(not changed.hit, "changed height/filter settings invalidate result")
	changed = cache.prepare(points, indices).groups[0]
	cache.resolve(changed, settings, [3.0], source)
	_check(not changed.hit, "changed exact road edge height invalidates result")
	points[1].x += 0.125
	changed = cache.prepare(points, indices).groups[0]
	cache.resolve(changed, settings, [], source)
	_check(not changed.hit, "changed raw coordinates invalidate same spatial group")
	points[1].x -= 0.125
	source.prepare_segments({Vector2i.ZERO: [0]}, [{"height": 2.0}])
	changed = cache.prepare(points, indices).groups[0]
	cache.resolve(changed, settings, [], source)
	_check(not changed.hit, "changed consumed road value invalidates unchanged triangle inputs")
	cache.configure(true, true)
	_check(cache._records.is_empty() and cache.stats.payload_bytes == 0, "explicit clear releases group snapshots")
	prepared = cache.prepare(points, indices)
	var partial: Dictionary = prepared.groups[0]
	cache.resolve(partial, settings, [], source)
	for slot in range(2):
		source.begin_mesh_scope(partial.scope)
		source.invalidate_mesh_scope()
		cache.record(partial, slot, true, "", Vector3.ZERO, Vector3.ONE, Vector3.UP, source)
	_check(cache._records.is_empty() and cache.stats.uncertified == 1, "uncertified group never becomes replayable")
	var repeated := PackedInt32Array()
	for i in range(65):
		repeated.append_array(PackedInt32Array([0, 1, 2]))
	prepared = cache.prepare(points, repeated)
	_check(prepared.groups.size() == 2 and prepared.groups[0].points.size() == 192
		and prepared.groups[1].key.z == 1, "dense spatial cells split at 64 candidate triangles")
	_check(cache.prepare(points, PackedInt32Array([0, 1])).is_empty(), "incomplete triangle stream bypasses grouping")
	_check(cache.prepare(points, PackedInt32Array([0, 1, 99])).is_empty(), "out of range indices bypass grouping")
	var nonfinite := points.duplicate()
	nonfinite[0] = Vector2(INF, 0)
	_check(cache.prepare(nonfinite, indices).is_empty(), "nonfinite points bypass grouping")
	var many_points := PackedVector2Array()
	var many_indices := PackedInt32Array()
	for i in range(cache.MAX_GROUPS + 1):
		var x := i * 64.0
		many_points.append_array(PackedVector2Array([Vector2(x, 0), Vector2(x + 1, 0), Vector2(x, 1)]))
		many_indices.append_array(PackedInt32Array([i * 3, i * 3 + 1, i * 3 + 2]))
	_check(cache.prepare(many_points, many_indices.slice(0, cache.MAX_GROUPS * 3)).groups.size() == cache.MAX_GROUPS,
		"actual 4096 group boundary accepted")
	_check(cache.prepare(many_points, many_indices).is_empty() and cache.stats.fallback == "group_limit",
		"4097 spatial groups fall back")
	_capacity_checks(cache, source, many_points, many_indices)
	var oversized := PackedInt32Array()
	oversized.resize((cache.MAX_TRIANGLES + 1) * 3)
	_check(cache.prepare(points, oversized).is_empty(), "candidate count bound checked before allocating groups")
	cache.configure(false, false)
	_check(cache.prepare(points, indices).is_empty() and cache._records.is_empty(), "disabled cache retains no records")
	_emission_checks()
	print("TOPOLOGY_TRIANGLE_CACHE_%s checks=%d" % ["FAILED" if failed else "OK", checks])
	quit(1 if failed else 0)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(label)


func _capacity_checks(cache: RefCounted, source: RefCounted, points: PackedVector2Array, indices: PackedInt32Array) -> void:
	cache.configure(true, true)
	var groups: Array = cache.prepare(points, indices.slice(0, cache.MAX_GROUPS * 3)).groups
	for group: Dictionary in groups:
		_record_single(cache, source, group, PackedByteArray())
	_check(cache._records.size() == cache.MAX_GROUPS, "actual retained entry limit is reachable")
	var warm: Dictionary = cache.prepare(points, indices.slice(0, 3)).groups[0]
	cache.resolve(warm, PackedByteArray(), [], source)
	_check(warm.hit, "oldest retained entry validates before refreshing LRU order")
	var extra: Dictionary = cache.prepare(points, indices.slice(cache.MAX_GROUPS * 3)).groups[0]
	_record_single(cache, source, extra, PackedByteArray())
	_check(cache._records.size() == cache.MAX_GROUPS and cache._records.has(warm.key)
		and not cache._records.has(groups[1].key), "entry pressure evicts oldest unrefreshed group")
	cache.configure(true, true)
	var settings := PackedByteArray()
	settings.resize(128 * 1024)
	groups = cache.prepare(points, indices.slice(0, 600 * 3)).groups
	for group: Dictionary in groups:
		_record_single(cache, source, group, settings)
	var exact_bytes := 0
	for record: Dictionary in cache._records.values():
		exact_bytes += var_to_bytes(record).size()
	_check(exact_bytes == cache._payload_bytes and exact_bytes <= cache.MAX_PAYLOAD_BYTES,
		"actual 64 MiB pressure accounts complete serialized retained records")
	_check(cache._records.size() < 600 and cache._records.has(groups[-1].key)
		and not cache._records.has(groups[0].key), "payload pressure retains newest results and evicts old snapshots")
	cache.configure(true, true)


func _record_single(cache: RefCounted, source: RefCounted, group: Dictionary, settings: PackedByteArray) -> void:
	cache.resolve(group, settings, [], source)
	source.begin_mesh_scope()
	source.capture_bounds(Vector4i.ZERO)
	cache.record(group, 0, true, "", Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD, source)


func _emission_checks() -> void:
	var cache := GROUPS.new()
	var source := SOURCE.new()
	source.configure(true, false)
	source.prepare_segments({Vector2i.ZERO: [0]}, [{"height": 1.0}])
	source.prepare_edges({}, [])
	var points := PackedVector2Array()
	var indices := PackedInt32Array()
	var original: Array[PackedVector3Array] = []
	var pattern := [0, 0, 1, 0, 0, 1, 1, 0, 0]
	var rejected := {1: "crossing", 3: "area", 4: "", 7: "crossing"}
	var negative_zero := -float(checks) * 0.0
	for i in range(pattern.size()):
		var x: float = pattern[i] * 64.0
		var triangle := PackedVector2Array([Vector2(x, negative_zero), Vector2(x + 1, 0), Vector2(x, 1)])
		if i % 2 == 0:
			triangle.reverse()
		points.append_array(triangle)
		indices.append_array(PackedInt32Array([i * 3, i * 3 + 1, i * 3 + 2]))
		var vertices := PackedVector3Array()
		for p: Vector2 in triangle:
			# Shared edge endpoints receive differently tilted face contributions.
			vertices.append(Vector3(p.x, i * 0.1 if p.y != 0.0 else 0.0, p.y))
		original.append(vertices)
	for inverted in [false, true]:
		cache.configure(true, true)
		var cold: Dictionary = cache.prepare(points, indices)
		_check(cold.ends == PackedInt32Array([2, 2, 3, 5, 5, 7, 7, 9, 9]), "run ends retain interleaved spatial group order")
		for i in range(pattern.size()):
			var group: Dictionary = cold.groups[cold.ids[i]]
			cache.resolve(group, PackedByteArray(), [], source)
			source.begin_mesh_scope(group.scope)
			source.capture_bounds(Vector4i.ZERO)
			cache.record(group, cold.slots[i], not rejected.has(i), rejected.get(i, ""),
				original[i][0], original[i][1], original[i][2], source, inverted)
		for budget in [1, 2, 4, 256]:
			for small in [false, true]:
				var prepared: Dictionary = cache.prepare(points, indices)
				for group: Dictionary in prepared.groups:
					cache.resolve(group, PackedByteArray(), [], source)
				var stream: RefCounted = SmallStream.new() if small else STREAM.new()
				var surface := SurfaceTool.new()
				surface.begin(Mesh.PRIMITIVE_TRIANGLES)
				stream.begin(surface, true)
				var reference := SurfaceTool.new()
				reference.begin(Mesh.PRIMITIVE_TRIANGLES)
				var counters: Dictionary = {}
				var expected_counters: Dictionary = {}
				var fixes := 0
				var expected_fixes := 0
				var triangles := 0
				var expected_triangles := 0
				var last_reason := ""
				var expected_last_reason := ""
				var cursor := 0
				while cursor < pattern.size():
					var end := mini(cursor + budget, pattern.size())
					for i in range(cursor, end):
						if rejected.has(i):
							var reason: String = rejected[i]
							if not reason.is_empty():
								expected_counters[reason] = expected_counters.get(reason, 0) + 1
								expected_last_reason = reason
						else:
							expected_fixes += _emit_reference(reference, original[i], inverted)
							expected_triangles += 1
					while cursor < end:
						var group: Dictionary = prepared.groups[prepared.ids[cursor]]
						var count := mini(prepared.ends[cursor], end) - cursor
						var replay: Dictionary = cache.emit_run(group, prepared.slots[cursor], count, inverted, stream, surface)
						if replay.is_empty():
							# Same continuation contract as the builder: failed bulk
							# append consumes nothing; process one original candidate.
							if rejected.has(cursor):
								var reason: String = rejected[cursor]
								if not reason.is_empty():
									counters[reason] = counters.get(reason, 0) + 1
									last_reason = reason
							else:
								fixes += _emit_reference(surface, original[cursor], inverted)
								triangles += 1
							cursor += 1
						else:
							fixes += replay.winding
							triangles += replay.triangles
							for reason: String in replay.rejections:
								counters[reason] = counters.get(reason, 0) + replay.rejections[reason]
							if not replay.last_reason.is_empty():
								last_reason = replay.last_reason
							cursor += count
					_check(cursor == end and counters == expected_counters and fixes == expected_fixes and triangles == expected_triangles and last_reason == expected_last_reason,
						"frame cutoff preserves exact candidate, rejection and winding counts")
				stream.flush()
				_check(var_to_bytes(surface.commit_to_arrays()) == var_to_bytes(reference.commit_to_arrays()),
					"run slices and capacity continuation preserve raw vertex/UV order and signed zero")
				surface.generate_normals()
				reference.generate_normals()
				_check(var_to_bytes(surface.commit_to_arrays()) == var_to_bytes(reference.commit_to_arrays()),
					"interleaved runs preserve native smooth normals at every frame budget")
				_check(not small or stream.stats.capacity_fallback, "small stream actually exercises overflow continuation")
		var fresh: Dictionary = cache.prepare(points, indices).groups[0]
		cache.resolve(fresh, PackedByteArray(), [], source)
		var stored_bytes := var_to_bytes(fresh.emission)
		fresh.emission.vertices[0] = Vector3(99, 99, 99)
		fresh.emission.offsets[0] = 99
		fresh = cache.prepare(points, indices).groups[0]
		cache.resolve(fresh, PackedByteArray(), [], source)
		_check(var_to_bytes(fresh.emission) == stored_bytes, "run replay snapshots cannot poison retained arrays or offsets")
		var stream := STREAM.new()
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		stream.begin(surface, true)
		_check(cache.emit_run(fresh, 0, 1, not inverted, stream, surface).is_empty() and stream._vertices.is_empty(),
			"changed live face orientation uses original triangle replay without consuming vertices")
		_check(cache.emit_run(fresh, -1, 1, inverted, stream, surface).is_empty()
			and cache.emit_run(fresh, 0, 999, inverted, stream, surface).is_empty(), "invalid run slices consume nothing")
		cache._records[fresh.key].erase("emission")
		fresh = cache.prepare(points, indices).groups[0]
		cache.resolve(fresh, PackedByteArray(), [], source)
		_check(fresh.hit and cache.emit_run(fresh, 0, 1, inverted, stream, surface).is_empty(),
			"old schema retains certified filtering but falls back from packed emission")
		stream.clear()


func _emit_reference(surface: SurfaceTool, vertices: PackedVector3Array, inverted: bool) -> int:
	var flip := (vertices[1] - vertices[0]).cross(vertices[2] - vertices[0]).y < 0.0
	var fixes := int(flip)
	if inverted:
		flip = not flip
	for corner in range(3):
		var vertex := vertices[2 - corner if flip else corner]
		surface.set_uv(Vector2(vertex.x * 0.05, vertex.z * 0.05))
		surface.add_vertex(vertex)
	return fixes
