extends SceneTree

const CACHE = preload("../addons/scripts/spline_road/topology_collar_cache.gd")
const SOURCE = preload("../addons/scripts/spline_road/topology_stage_cache.gd")
var checks := 0
var failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var cache := CACHE.new()
	var source := SOURCE.new()
	cache.configure(true, false)
	source.configure(true, false)
	source.prepare_segments({Vector2i.ZERO: [0]}, [{"height": 1.0}])
	source.prepare_edges({}, [])
	var input := var_to_bytes([Vector2.ONE, 8.0])
	_record(cache, source, Vector2i.ZERO, input)
	_check(not cache.recording and cache._pending.is_empty() and source._mesh_scope.is_empty(), "finished collar group releases transient capture and source scope")
	var warm: Dictionary = cache.lookup(Vector2i.ZERO, input, source, {})
	_check(not warm.is_empty() and warm.triangles == 1, "complete collar group can be replayed")
	var negative_coordinate := -float(checks) * 0.0
	_check(var_to_bytes(warm.points[0]) != var_to_bytes(Vector2.ZERO)
		and var_to_bytes(warm.points[0]) == var_to_bytes(Vector2(negative_coordinate, negative_coordinate)), "actual signed-zero UV inputs survive replay")
	_check(cache.lookup(Vector2i.ZERO, var_to_bytes([Vector2.ONE, 9.0]), source, {}).is_empty(), "changed row or settings bytes invalidate group")
	_check(cache.lookup(Vector2i.ZERO, input, source, {Vector2i.ZERO: 2.0}).is_empty(), "new exact edge-height value invalidates formerly absent lookup")
	_check(not cache.lookup(Vector2i.ZERO, input, source, {Vector2i(90, 90): 2.0}).is_empty(), "unconsumed edge-height entry does not invalidate group")
	warm.vertices[0] = Vector3(99, 99, 99)
	warm.uvs[0] = Vector2(99, 99)
	warm.edge_heights[Vector2i.ZERO] = 99.0
	warm.scope.segment_values[0] = 99999
	var fresh: Dictionary = cache.lookup(Vector2i.ZERO, input, source, {})
	_check(not fresh.is_empty() and fresh.vertices[0] == Vector3.ZERO, "returned geometry and dependency mutation cannot poison stored result")
	_check(var_to_bytes(fresh.uvs[0]) == var_to_bytes(Vector2(negative_coordinate * 0.05, negative_coordinate * 0.05)),
		"captured UVs preserve native signed-zero arithmetic and are isolated from returned mutation")
	cache._records[Vector2i.ZERO].erase("uvs")
	_check(cache.lookup(Vector2i.ZERO, input, source, {}).is_empty(), "pre-stream collar snapshots rebuild instead of reading missing UV data")
	_record(cache, source, Vector2i.ZERO, input)
	source.prepare_segments({Vector2i.ZERO: [0]}, [{"height": 2.0}])
	_check(cache.lookup(Vector2i.ZERO, input, source, {}).is_empty(), "nearby road height change invalidates unchanged collar shape")
	cache.begin(Vector2i.ONE, input, source)
	cache.capture_vertex(Vector3.ZERO, Vector2.ZERO)
	_check(cache.lookup(Vector2i.ONE, input, source, {}).is_empty(), "partly recorded collar is not reusable")
	cache.finish(1, source)
	_check(not cache._records.has(Vector2i.ONE) and cache.stats.uncertified == 1, "incomplete emitted triangle stream is not retained")
	cache.begin(Vector2i.ONE, input, source)
	source.invalidate_mesh_scope()
	cache.finish(0, source)
	_check(not cache._records.has(Vector2i.ONE), "linear or unsupported dependencies prevent empty-group retention too")
	cache.begin(Vector2i.ONE, input, source)
	cache.finish(0, source)
	_check(not cache.lookup(Vector2i.ONE, input, source, {}).is_empty(), "certified empty collar block can skip repeated rejected quads")
	cache.begin(Vector2i(2, 0), input, source)
	# Produce the sign at runtime: constant pooling can merge +0.0 and -0.0.
	var negative_zero := -float(checks) * 0.0
	_check(var_to_bytes([negative_zero]) != var_to_bytes([0.0]), "signed-zero fixture contains distinct serialized values")
	cache.capture_height(Vector2i.ZERO, negative_zero)
	cache.finish(0, source)
	_check(cache.lookup(Vector2i(2, 0), input, source, {Vector2i.ZERO: 0.0}).is_empty(),
		"edge-height signed zero is an exact value dependency, not numerical equality")
	cache.configure(true, true)
	for i in range(cache.MAX_GROUPS):
		_record(cache, source, Vector2i(i, 0), input)
	_check(cache._records.size() == cache.MAX_GROUPS, "actual 4096 retained entry boundary is reachable")
	cache.lookup(Vector2i.ZERO, input, source, {})
	_record(cache, source, Vector2i(cache.MAX_GROUPS, 0), input)
	_check(cache._records.size() == cache.MAX_GROUPS and cache._records.has(Vector2i.ZERO)
		and not cache._records.has(Vector2i(1, 0)), "entry pressure evicts oldest unrefreshed collar block")
	cache.configure(true, true)
	var large_input := PackedByteArray()
	large_input.resize(128 * 1024)
	for i in range(600):
		_record(cache, source, Vector2i(i, 0), large_input)
	var exact_bytes := 0
	for record: Dictionary in cache._records.values():
		exact_bytes += var_to_bytes(record).size()
	_check(exact_bytes == cache._payload_bytes and exact_bytes <= cache.MAX_PAYLOAD_BYTES,
		"actual 64 MiB pressure accounts complete serialized records")
	_check(cache._records.size() < 600 and cache._records.has(Vector2i(599, 0)) and not cache._records.has(Vector2i.ZERO),
		"payload pressure retains newest collar groups")
	cache.configure(true, true)
	cache.begin(Vector2i.ZERO, input, source)
	for i in range(cache.MAX_VERTICES + 1):
		cache.capture_vertex(Vector3(i, 0, 0), Vector2(i, 0))
	_check(cache._vertices.size() == cache.MAX_VERTICES and not cache.recording, "single group capture stops at actual vertex ceiling")
	cache.finish(cache.MAX_VERTICES / 3, source)
	_check(cache._records.is_empty() and cache._vertices.is_empty(), "overflow falls back and releases partial geometry")
	cache.begin(Vector2i.ZERO, input, source)
	for i in range(cache.MAX_VERTICES + 1):
		cache.capture_height(Vector2i(i, 0), null)
	_check(cache._edge_heights.size() == cache.MAX_VERTICES and not cache.recording, "edge-height proof has its own actual entry bound")
	cache.finish(0, source)
	_check(cache._records.is_empty() and cache._edge_heights.is_empty(), "proof overflow cannot be replayed")
	_record(cache, source, Vector2i.ZERO, input)
	_check(not cache.lookup(Vector2i.ZERO, input, source, {}).is_empty(), "recording recovers after capacity fallback")
	cache.configure(false, false)
	_check(cache._records.is_empty() and cache.lookup(Vector2i.ZERO, input, source, {}).is_empty(), "disabled mode releases snapshots and cannot replay")
	print("TOPOLOGY_COLLAR_CACHE_%s checks=%d" % ["FAILED" if failed else "OK", checks])
	quit(1 if failed else 0)


func _record(cache: RefCounted, source: RefCounted, key: Vector2i, input: PackedByteArray) -> void:
	cache.begin(key, input, source)
	source.capture_bounds(Vector4i.ZERO)
	cache.capture_height(Vector2i.ZERO, null)
	var negative_zero := -float(key.x + 1) * 0.0
	cache.capture_vertex(Vector3.ZERO, Vector2(negative_zero, negative_zero))
	cache.capture_vertex(Vector3.RIGHT, Vector2.RIGHT)
	cache.capture_vertex(Vector3.FORWARD, Vector2.DOWN)
	cache.finish(1, source)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(label)
