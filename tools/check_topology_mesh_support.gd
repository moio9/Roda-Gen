extends SceneTree

const CACHE = preload("../addons/scripts/spline_road/topology_stage_cache.gd")
const BUILDER = preload("../addons/scripts/spline_road/terrain_topology_builder.gd")
var checks := 0
var failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var cache := CACHE.new()
	cache.configure(true, false)
	var segments: Array = [{"a": Vector2.ZERO, "b": Vector2(2, 0)}]
	var cells := {Vector2i.ZERO: [0]}
	var edges: Array = [[Vector2.ZERO, Vector2(2, 0)]]
	cache.prepare_segments(cells, segments)
	cache.prepare_edges(cells, edges)
	cache.begin_mesh_scope()
	cache.nearest_query(Vector2.ZERO, 8, 2, 1, [])
	cache.crossing_query(Vector2.ZERO, Vector2(8, 0), Vector2(0, 8), 8)
	var proof: Dictionary = cache.end_mesh_scope()
	_check(cache.validate_mesh_scope(proof), "cold captured proof validates")
	cache.prepare_segments(cells, segments)
	cache.prepare_edges(cells, edges)
	_check(cache.validate_mesh_scope(proof), "identical rebuilt spatial context preserves proof")
	segments[0].b = Vector2(3, 0)
	cache.prepare_segments(cells, segments)
	_check(not cache.validate_mesh_scope(proof), "in-place segment change invalidates memoized proof")
	segments[0].b = Vector2(2, 0)
	cache.prepare_segments(cells, segments)
	_check(cache.validate_mesh_scope(proof), "restored exact source values validate")
	edges[0][1] = Vector2(3, 0)
	cache.prepare_edges(cells, edges)
	_check(not cache.validate_mesh_scope(proof), "in-place edge change invalidates memoized proof")
	edges[0][1] = Vector2(2, 0)
	cache.prepare_edges(cells, edges)
	var incoming := cells.duplicate(true)
	incoming[Vector2i(1, 1)] = [0]
	cache.prepare_segments(incoming, segments)
	_check(not cache.validate_mesh_scope(proof), "previously empty nearest cell becoming occupied invalidates")
	cache.prepare_segments(cells, segments)
	cache.prepare_edges(incoming, edges)
	_check(not cache.validate_mesh_scope(proof), "previously empty crossing cell becoming occupied invalidates")
	incoming = cells.duplicate(true)
	incoming[Vector2i(20, 20)] = [0]
	cache.prepare_segments(incoming, segments)
	cache.prepare_edges(incoming, edges)
	_check(cache.validate_mesh_scope(proof), "outside-support cells do not invalidate spatial proof")
	cache.begin_mesh_scope()
	cache.nearest_query(Vector2.ZERO, 8, 2, 1, [])
	cache.crossing_query(Vector2.ZERO, Vector2(8, 0), Vector2(0, 8), 8)
	_check(cache.end_mesh_scope() == proof, "warm region query hits still capture full proof")
	cache.remember_nearest(Vector2.ZERO, 8, 1)
	cache.begin_mesh_scope()
	cache.capture_nearest_hint(Vector2.ZERO, 8)
	_check(cache.end_mesh_scope().segments == proof.segments, "point memo hits retain nearest support")
	cache.begin_mesh_scope()
	cache.capture_nearest_hint(Vector2(99, 99), 8)
	_check(cache.end_mesh_scope().is_empty(), "missing or evicted hint disables group retention")
	cache.begin_mesh_scope()
	cache.capture_bounds(Vector4i(0, 0, 63, 63))
	_check(not cache.end_mesh_scope().is_empty(), "4096 support cells accepted")
	cache.begin_mesh_scope()
	cache.capture_bounds(Vector4i(0, 0, 64, 63))
	_check(cache.end_mesh_scope().is_empty(), "oversized proof falls back")
	cache.begin_mesh_scope()
	cache.capture_bounds(Vector4i(1, 1, 0, 0))
	_check(cache.end_mesh_scope().is_empty(), "malformed bounds cannot yield vacuous proof")
	cache.begin_mesh_scope()
	cache.capture_bounds(Vector4i.ZERO)
	cache.prepare_segments(cells, segments)
	_check(cache.end_mesh_scope().is_empty(), "spatial rebuild during capture invalidates scope")
	cache.begin_mesh_scope()
	cache.capture_bounds(Vector4i.ZERO, true)
	cache.prepare_edges(cells, edges)
	_check(cache.end_mesh_scope().is_empty(), "edge rebuild during capture invalidates scope")
	var snapshot := proof.duplicate(true)
	cache.begin_mesh_scope()
	cache.capture_bounds(Vector4i(-3, -3, 3, 3))
	cache.end_mesh_scope()
	_check(proof == snapshot, "later captures cannot mutate previous proof")
	for i in range(300):
		cache.begin_mesh_scope()
		cache.capture_bounds(Vector4i(i, 0, i, 0))
		cache.end_mesh_scope()
	_check(cache._mesh_support.size() <= 256, "transient proof memo is bounded")
	cache.clear()
	_check(not cache.validate_mesh_scope(proof) and cache._mesh_support.is_empty(), "clear releases support and rejects old proof")
	_check_builder_capture()
	_check_noise_dependencies()
	_check_search_certificates()
	print("TOPOLOGY_MESH_SUPPORT_%s checks=%d" % ["FAILED" if failed else "OK", checks])
	quit(1 if failed else 0)


func _check_search_certificates() -> void:
	var cache := CACHE.new()
	cache.configure(true, false)
	cache.prepare_segments({}, [], 7.0)
	cache.prepare_edges({}, [])
	cache.begin_mesh_scope()
	cache.capture_search_test(PackedFloat64Array([0, 16.0, 4.0, 0]))
	cache.capture_search_radius(8.0, 1.0, 3)
	var proof: Dictionary = cache.end_mesh_scope()
	for width in [0.0, 7.0, 7.0000413, 11.999999999, 12.0, 12.000000001, 16.0]:
		cache.prepare_segments({}, [], width)
		var expected: bool = 16.0 - width >= 4.0 and maxi(0, int(ceil(maxf(0.0, width + 1.0) / 8.0)) + 1) <= 3
		_check(cache.validate_mesh_scope(proof) == expected, "native nearest inequality at width " + str(width))
	cache.begin_mesh_scope()
	cache.capture_search_radius(8.0, -2.0, 2)
	proof = cache.end_mesh_scope()
	for width in [0.0, 2.0, 7.69994767904282, 7.69998898506165, 10.0, 10.000000001, 30.0]:
		cache.prepare_segments({}, [], width)
		var expected: bool = maxi(0, int(ceil(maxf(0.0, width - 2.0) / 8.0)) + 1) <= 2
		_check(cache.validate_mesh_scope(proof) == expected, "native radius threshold at width " + str(width))
	cache.begin_mesh_scope()
	for index in range(CACHE.MAX_MESH_SEARCH_TESTS):
		cache.capture_search_test(PackedFloat64Array([0, 64, 0, 0]))
	proof = cache.end_mesh_scope()
	_check(cache.validate_mesh_scope(proof), "actual search-certificate limit is admitted")
	cache.begin_mesh_scope(proof.duplicate(true))
	cache.capture_search_test(PackedFloat64Array([0, 64, 0, 0]))
	_check(cache.end_mesh_scope().is_empty(), "search-certificate overflow disables retention")
	for test in [PackedFloat64Array([0, INF, 0, 0]), PackedFloat64Array([1, 0, 1, 2]),
		PackedFloat64Array([9, 0, 0, 0]), PackedFloat64Array([0, 1])]:
		_check(not cache._validate_search_tests(test), "malformed certificate cannot validate")
	var builder := BUILDER.new()
	builder.far_grid_step = 16
	var segments: Array = []
	for index in range(2):
		segments.append({"a": Vector2(index * 80, -20), "b": Vector2(index * 80, 20),
			"path_id": index, "left_half_xz_a": 2.0, "left_half_xz_b": 2.0,
			"right_half_xz_a": 2.0, "right_half_xz_b": 2.0})
	builder._source_cache.configure(true, false)
	builder._build_road_spatial_index(segments, [])
	var point := Vector2(8, 6)
	builder._source_cache.begin_mesh_scope()
	var original: Dictionary = builder._nearest_road_info(point, segments)
	proof = builder._source_cache.end_mesh_scope()
	_check(original.path_id == 0 and builder._source_cache.validate_mesh_scope(proof), "native nearest proof is initially valid")
	for width in [2.0000413, 80.0]:
		for key in ["left_half_xz_a", "left_half_xz_b", "right_half_xz_a", "right_half_xz_b"]:
			segments[1][key] = width
		builder._build_road_spatial_index(segments, [])
		var valid: bool = builder._source_cache.validate_mesh_scope(proof)
		var current: Dictionary = builder._nearest_road_info(point, segments)
		_check(valid == (width < 3.0), "outside-source widening reuses only while search region is safe")
		_check(var_to_bytes(current) == var_to_bytes(builder._nearest_road_info_linear(point, segments)),
			"outside-source widening matches native complete search")
		_check(current.path_id == (0 if valid else 1), "large widening really changes the winning road")
	builder.free()


func _check_builder_capture() -> void:
	var builder := BUILDER.new()
	var cache = builder._source_cache
	cache.configure(true, false)
	var segments: Array = [{"a": Vector2.ZERO, "b": Vector2(10, 0)}]
	var cells := {Vector2i.ZERO: [0]}
	cache.prepare_segments(cells, segments, 2.0)
	builder._road_spatial_cells = cells
	builder._road_spatial_segment_count = 1
	builder._road_spatial_cell_size = 8.0
	builder._road_max_half_width = 2.0
	cache.begin_mesh_scope()
	var nearest: Dictionary = builder._nearest_road_info(Vector2(4, 3), segments)
	var nearest_proof: Dictionary = cache.end_mesh_scope()
	_check(not nearest.is_empty() and not nearest_proof.is_empty(), "native nearest miss captures safe stopping region")
	cache.begin_mesh_scope()
	_check(builder._nearest_road_info(Vector2(4, 3), segments) == nearest, "native nearest cache hit preserves result")
	_check(cache.end_mesh_scope() == nearest_proof, "native nearest hit captures same safe stopping region")
	var hint: Dictionary = cache.nearest_hint(Vector2(4, 3), 8)
	cache.remember_nearest(Vector2(4, 3), 8, hint.ring, 99999.0, -99999.0)
	cache.begin_mesh_scope()
	builder._nearest_road_info(Vector2(4, 3), segments)
	_check(cache.end_mesh_scope() == nearest_proof, "cached result refreshes certificate rather than trusting a replaced hint")
	cache.begin_mesh_scope()
	builder._has_road_edge_within(Vector2.ZERO, segments, 0.0, false)
	var proof: Dictionary = cache.end_mesh_scope()
	_check(proof.segments == Vector4i(-2, -2, 2, 2), "interior test captures entire search square before early return")
	cache.remember_nearest(Vector2.ZERO, 8, 1)
	cache.begin_mesh_scope()
	builder._get_cached_road_info(0, Vector2.ZERO, segments, {0: {"distance": 0}})
	_check(cache.end_mesh_scope().segments == Vector4i(-1, -1, 1, 1), "builder point-cache hit captures dependency")
	builder._road_spatial_cells = {}
	cache.begin_mesh_scope()
	builder._has_road_edge_within(Vector2.ZERO, segments, 0.0, false)
	_check(cache.end_mesh_scope().is_empty(), "linear interior fallback cannot certify spatial proof")
	cache.begin_mesh_scope()
	builder._triangle_crosses_road_edges(Vector2.ZERO, Vector2.ONE, Vector2(1, 0), [])
	_check(cache.end_mesh_scope().is_empty(), "polygon crossing fallback cannot certify spatial proof")
	builder.free()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(label)


func _check_noise_dependencies() -> void:
	var builder := BUILDER.new()
	builder._source_cache.configure(true, false)
	builder._configure_noise()
	builder.noise_enabled = true
	builder.noise_amplitude = 8.0
	builder.noise_start_distance_from_road = 0.0
	builder.noise_fade_distance = 1.0
	var input: PackedByteArray = builder._noise_parameters()
	var height: float = builder._sample_height_from_road_info(Vector2(5, 8), {})
	builder._noise.offset = Vector3(20, 30, 40)
	_check(input != builder._noise_parameters(), "noise offset changes exact cached parameter snapshot")
	var changed: float = builder._sample_height_from_road_info(Vector2(5, 8), {})
	_check(changed == builder._sample_height_from_road_info_uncached(Vector2(5, 8), {}) and changed != height,
		"height cache cannot replay old values after a non-exported noise parameter edit")
	input = builder._noise_parameters()
	builder._noise.domain_warp_enabled = true
	_check(input != builder._noise_parameters(), "domain warp settings participate in height and triangle dependencies")
	var previous: FastNoiseLite = builder._noise
	builder._noise = FastNoiseLite.new()
	builder._noise_parameters()
	_check(not previous.changed.is_connected(builder._noise_changed) and builder._noise.changed.is_connected(builder._noise_changed),
		"replacing noise resource disconnects old dependency signal and observes current resource")
	_check(builder._sample_height_from_road_info(Vector2(5, 8), {}) == builder._sample_height_from_road_info_uncached(Vector2(5, 8), {}),
		"replaced noise resource preserves uncached height parity")
	builder.free()
