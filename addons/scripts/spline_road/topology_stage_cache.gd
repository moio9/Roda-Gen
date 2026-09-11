@tool
extends "./terrain_stage_cache.gd"
## Main-thread-only source results for TerrainTopologyBuilder3D. The Delaunay
## worker receives points only; it never accesses this cache or scene objects.

const MAX_TOPOLOGY_ENTRIES := 65536

var _revision := 0
var spatial_ready := false
var _cells: Dictionary = {}
var _regions: Dictionary = {}
var _nearest_hints: Dictionary = {}
var _edge_cells: Dictionary = {}
var _edge_regions: Dictionary = {}
var _mesh_scope: Dictionary = {}
var _mesh_support: Dictionary = {}
var _mesh_edge_support: Dictionary = {}
const MAX_MESH_SUPPORT_CELLS := 4096
const MAX_MESH_SEARCH_TESTS := 4096
var _mesh_search_width := 0.0


func _entry_limit() -> int:
	# Topology stores several small queries per point/triangle, unlike the larger
	# polygon/strip records in the base cache. Keep the same 64 MiB payload ceiling
	# while allowing those smaller records to coexist across local edits.
	return MAX_TOPOLOGY_ENTRIES


func _query_key(input: PackedByteArray) -> String:
	# This is a bucket selector, not an identity or persistent content digest.
	# lookup compares the complete serialized input before accepting any result;
	# collisions only replace a bucket or cause a miss. Spatial revision IDs remain
	# monotonically unique even after collisions/eviction.
	return str(hash(input))


func configure(use_cache: bool, clear_requested: bool) -> void:
	super.configure(use_cache, clear_requested)
	spatial_ready = false
	_cells.clear()
	_regions.clear()
	_edge_cells.clear()
	_edge_regions.clear()
	_mesh_scope.clear()
	_mesh_support.clear()
	_mesh_edge_support.clear()
	stats.merge({"nearest_reused": 0, "nearest_rebuilt": 0, "distance_tests": 0,
		"heights_reused": 0, "heights_rebuilt": 0, "height_modifier_bypasses": 0,
		"delaunay_reused": 0, "delaunay_rebuilt": 0, "segments_checked": 0,
		"dependency_cells": 0, "regions_reused": 0,
		"crossings_reused": 0, "crossings_rebuilt": 0, "edge_candidates_tested": 0})


func clear() -> void:
	super.clear()
	spatial_ready = false
	_cells.clear()
	_regions.clear()
	_nearest_hints.clear()
	_edge_cells.clear()
	_edge_regions.clear()
	_mesh_scope.clear()
	_mesh_support.clear()
	_mesh_edge_support.clear()
	# IDs must never alias old queries, even when only stage entries are evicted.


func prepare_segments(cells: Dictionary, segments: Array, search_width := 0.0) -> void:
	invalidate_mesh_scope()
	_mesh_search_width = search_width
	_mesh_support.clear()
	spatial_ready = false
	_cells.clear()
	_regions.clear()
	if not enabled:
		return
	var revisions := PackedInt64Array()
	for segment: Dictionary in segments:
		revisions.append(_value_revision("segment", segment))
		stats.segments_checked += 1
	for cell: Vector2i in cells:
		var ordered := PackedInt64Array()
		for id: int in cells[cell]:
			ordered.append(revisions[id])
		_cells[cell] = _value_revision("segment_cell", ordered)
	spatial_ready = true


func _value_revision(stage: String, value: Variant) -> int:
	var input := query(stage, [value])
	var cached := lookup(input)
	if not cached.is_empty():
		return cached.result
	_revision += 1
	store(input, _revision)
	return _revision


func prepare_edges(cells: Dictionary, edges: Array) -> void:
	invalidate_mesh_scope()
	_mesh_edge_support.clear()
	_edge_cells.clear()
	_edge_regions.clear()
	if not enabled:
		return
	var revisions := PackedInt64Array()
	for edge: Array in edges:
		revisions.append(_value_revision("edge", edge))
	for cell: Vector2i in cells:
		var ordered := PackedInt64Array()
		for id: int in cells[cell]:
			ordered.append(revisions[id])
		_edge_cells[cell] = _value_revision("edge_cell", ordered)


func crossing_query(a: Vector2, b: Vector2, c: Vector2, cell_size: float) -> Dictionary:
	var bounds := Vector4i(floori(minf(a.x, minf(b.x, c.x)) / cell_size),
		floori(minf(a.y, minf(b.y, c.y)) / cell_size),
		floori(maxf(a.x, maxf(b.x, c.x)) / cell_size),
		floori(maxf(a.y, maxf(b.y, c.y)) / cell_size))
	capture_bounds(bounds, true)
	if not _edge_regions.has(bounds):
		var support := PackedInt64Array()
		for x in range(bounds.x, bounds.z + 1):
			for z in range(bounds.y, bounds.w + 1):
				stats.dependency_cells += 1
				var cell := Vector2i(x, z)
				if _edge_cells.has(cell):
					support.append(_edge_cells[cell])
		_edge_regions[bounds] = support
	else:
		stats.regions_reused += 1
	return query("crossing", [a, b, c, cell_size, _edge_regions[bounds]])


func nearest_hint(point: Vector2, cell_size: float) -> Dictionary:
	return _nearest_hints.get(var_to_bytes([point, cell_size]).hex_encode(), {})


func remember_nearest(point: Vector2, cell_size: float, ring: int, distance := INF, best := INF) -> void:
	var key := var_to_bytes([point, cell_size]).hex_encode()
	_nearest_hints.erase(key)
	_nearest_hints[key] = {"ring": ring, "search_test": PackedFloat64Array([0, distance, best, 0])
		if is_finite(distance) and is_finite(best) else PackedFloat64Array([2, _mesh_search_width, 0, 0])}
	while _nearest_hints.size() > MAX_ENTRIES:
		_nearest_hints.erase(_first_key(_nearest_hints))


func nearest_query(point: Vector2, cell_size: float, half_width: float, ring: int, defaults: Array) -> Dictionary:
	return query("nearest", [point, cell_size, half_width, ring, defaults, _region(point, cell_size, ring)])


func _region(point: Vector2, cell_size: float, limit: int) -> PackedInt64Array:
	var center := Vector2i(floori(point.x / cell_size), floori(point.y / cell_size))
	capture_bounds(Vector4i(center.x - limit, center.y - limit, center.x + limit, center.y + limit))
	var key := Vector3i(center.x, center.y, limit)
	if _regions.has(key):
		stats.regions_reused += 1
		return _regions[key]
	var ordered := PackedInt64Array()
	# Preserve original ring/cell/source ordering. Repeated segment IDs across
	# cells are represented by repeated revisions; no persistent scene IDs occur.
	for ring in range(limit + 1):
		for x in range(center.x - ring, center.x + ring + 1):
			for z in range(center.y - ring, center.y + ring + 1):
				if ring > 0 and x != center.x - ring and x != center.x + ring and z != center.y - ring and z != center.y + ring:
					continue
				stats.dependency_cells += 1
				var cell := Vector2i(x, z)
				if _cells.has(cell):
					ordered.append(_cells[cell])
	_regions[key] = ordered
	return ordered


func begin_mesh_scope(previous: Dictionary = {}) -> void:
	_mesh_scope = previous if not previous.is_empty() else {"valid": enabled and spatial_ready,
		"segments": null, "edges": null, "search_tests": PackedFloat64Array()}
	if not enabled or not spatial_ready:
		invalidate_mesh_scope()


func pause_mesh_scope() -> Dictionary:
	var scope := _mesh_scope
	_mesh_scope = {}
	return scope


func invalidate_mesh_scope() -> void:
	if not _mesh_scope.is_empty():
		_mesh_scope.valid = false


func capture_nearest_hint(point: Vector2, cell_size: float) -> void:
	if _mesh_scope.is_empty():
		return
	var hint := nearest_hint(point, cell_size)
	if hint.is_empty():
		invalidate_mesh_scope()
		return
	var center := Vector2i(floori(point.x / cell_size), floori(point.y / cell_size))
	var ring: int = hint.ring
	capture_bounds(Vector4i(center.x - ring, center.y - ring, center.x + ring, center.y + ring))
	capture_search_test(hint.get("search_test", PackedFloat64Array([2, _mesh_search_width, 0, 0])))


func capture_search_test(test: PackedFloat64Array) -> void:
	if _mesh_scope.is_empty() or not _mesh_scope.valid:
		return
	if not _mesh_scope.has("search_tests") or test.size() != 4 or _mesh_scope.search_tests.size() >= MAX_MESH_SEARCH_TESTS * 4:
		invalidate_mesh_scope()
		return
	_mesh_scope.search_tests.append_array(test)


func capture_search_radius(cell_size: float, threshold: float, radius: int) -> void:
	capture_search_test(PackedFloat64Array([1, cell_size, threshold, radius]))


func capture_bounds(bounds: Vector4i, edges := false) -> void:
	if _mesh_scope.is_empty() or not _mesh_scope.valid:
		return
	if bounds.z < bounds.x or bounds.w < bounds.y:
		invalidate_mesh_scope()
		return
	var key := "edges" if edges else "segments"
	if _mesh_scope[key] != null:
		var previous: Vector4i = _mesh_scope[key]
		bounds = Vector4i(mini(bounds.x, previous.x), mini(bounds.y, previous.y), maxi(bounds.z, previous.z), maxi(bounds.w, previous.w))
	if int(bounds.z - bounds.x + 1) * int(bounds.w - bounds.y + 1) > MAX_MESH_SUPPORT_CELLS:
		_mesh_scope.valid = false
		return
	_mesh_scope[key] = bounds


func end_mesh_scope() -> Dictionary:
	var scope := pause_mesh_scope()
	if scope.is_empty() or not scope.valid:
		return {}
	scope.segment_values = _mesh_region_values(scope.segments, false)
	scope.edge_values = _mesh_region_values(scope.edges, true)
	return scope


func validate_mesh_scope(scope: Dictionary) -> bool:
	return enabled and spatial_ready and not scope.is_empty() and scope.get("valid", false) \
		and _validate_search_tests(scope.get("search_tests", PackedFloat64Array([NAN]))) \
		and scope.segment_values == _mesh_region_values(scope.segments, false) \
		and scope.edge_values == _mesh_region_values(scope.edges, true)


func _validate_search_tests(tests: PackedFloat64Array) -> bool:
	if not is_finite(_mesh_search_width) or tests.size() % 4 != 0 or tests.size() > MAX_MESH_SEARCH_TESTS * 4:
		return false
	for offset in range(0, tests.size(), 4):
		var kind := tests[offset]
		var a := tests[offset + 1]
		var b := tests[offset + 2]
		var c := tests[offset + 3]
		if not is_finite(a) or not is_finite(b) or not is_finite(c):
			return false
		if kind == 0:
			# Repeat the native stopping inequality exactly, without rounded widths
			# or algebraically rearranging its floating-point subtraction.
			if not a - _mesh_search_width >= b:
				return false
		elif kind == 1:
			if a <= 0 or maxi(0, int(ceil(maxf(0.0, _mesh_search_width + b) / a)) + 1) > int(c):
				return false
		elif kind == 2:
			if _mesh_search_width > a:
				return false
		else:
			return false
	return true


func _mesh_region_values(bounds: Variant, edges: bool) -> PackedInt64Array:
	if bounds == null:
		return PackedInt64Array()
	var memo := _mesh_edge_support if edges else _mesh_support
	if memo.has(bounds):
		return memo[bounds]
	var cells := _edge_cells if edges else _cells
	var values := PackedInt64Array()
	for x in range(bounds.x, bounds.z + 1):
		for z in range(bounds.y, bounds.w + 1):
			values.append(int(cells.get(Vector2i(x, z), 0)))
	# The per-build proof memo is only an accelerator, never an identity. Bound
	# it independently of persistent source entries (which have their own cap).
	if memo.size() < 256:
		memo[bounds] = values
	return values
