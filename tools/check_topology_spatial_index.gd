extends SceneTree
const BUILDER = preload("../addons/scripts/spline_road/terrain_topology_builder.gd")
var failed := false
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var builder := BUILDER.new()
	var segments: Array = []
	var polygons: Array = []
	for path in range(3):
		for index in range([70, 65, 3][path]):
			var a := Vector2(-31.75 + index * 0.75, -11.25 + path * 20)
			segments.append({"a": a, "b": a + Vector2(1.15, 0.35), "path_id": path,
				"left_half_xz_a": 1.25 + path, "right_half_xz_b": 2.75 + path})
		var polygon := PackedVector2Array()
		for index in range([71, 65, 2][path]):
			polygon.append(Vector2(path * 30 + cos(float(index) * 0.1) * 12.75,
				sin(float(index) * 0.1) * 12.25))
		polygons.append(polygon)
	for size in [4.0, 7.3, 16.0, 32.0]:
		builder.far_grid_step = size
		_exercise(builder, segments, polygons, "cell size " + str(size))
	segments[2].a += Vector2(1.0, 0.0)
	polygons[0][2] += Vector2(1.0, 0.0)
	_exercise(builder, segments, polygons, "local endpoints")
	segments[2].left_half_xz_a += 5.0
	_exercise(builder, segments, polygons, "asymmetric width")
	segments[2]["ay"] = 19.0
	_exercise(builder, segments, polygons, "height-only edit")
	segments.insert(0, {"a": Vector2(-40, -20), "b": Vector2(-35, -20), "path_id": 99})
	_exercise(builder, segments, polygons, "inserted source and shifted IDs")
	segments = segments.slice(71) + segments.slice(0, 71)
	polygons.reverse()
	_exercise(builder, segments, polygons, "reordered sources")
	segments.resize(segments.size() - 1)
	polygons.pop_back()
	_exercise(builder, segments, polygons, "removed row and polygon")
	_exercise(builder, [], [], "empty sources")
	# This used to loop forever: no candidate could set a finite best distance.
	builder._source_cache.clear()
	var degenerate: Array = [{"a": Vector2.ZERO, "b": Vector2.ZERO}]
	_exercise(builder, degenerate, [PackedVector2Array([Vector2.ZERO, Vector2.ZERO])], "all-degenerate projections")
	_check(builder._source_cache._nearest_hints.is_empty(), "empty result has no falsely bounded support hint")
	degenerate.append({"a": Vector2(100, 0), "b": Vector2(110, 0), "path_id": 77})
	_exercise(builder, degenerate, [], "valid source arrives outside the prior empty ring")
	_check(builder._nearest_road_info(Vector2.ZERO, degenerate).path_id == 77,
		"a later remote valid source is not hidden by a cached empty result")
	degenerate.pop_back()
	_exercise(builder, degenerate, [], "all valid sources removed after a cached hit")
	degenerate.append({"a": Vector2(120, 0), "b": Vector2(130, 0), "path_id": 78})
	_exercise(builder, degenerate, [], "replacement source after empty query")
	_check(builder._nearest_road_info(Vector2.ZERO, degenerate).path_id == 78,
		"replacement source uses current IDs after a prior valid-to-empty transition")
	builder.free()
	print("TOPOLOGY_SPATIAL_INDEX_%s checks=%d" % ["FAILED" if failed else "OK", checks])
	quit(1 if failed else 0)


func _exercise(builder: Node, segments: Array, polygons: Array, label: String) -> void:
	builder._source_cache.configure(true, false)
	builder._build_road_spatial_index(segments, polygons)
	var expected := _oracle(segments, polygons, builder._road_spatial_cell_size, builder.fallback_road_width)
	_check(var_to_bytes([builder._road_spatial_cells, builder._road_edge_cells, builder._road_polygon_edges, builder._road_max_half_width])
		== var_to_bytes(expected), label + " exact cell and bucket ordering, edges and reach")
	for point: Vector2 in [Vector2(-20, 0), Vector2.ZERO, Vector2(4, 15), Vector2(16, 21)]:
		var linear: Dictionary = builder._nearest_road_info_linear(point, segments)
		var indexed: Dictionary = builder._nearest_road_info(point, segments)
		_check(var_to_bytes(indexed) == var_to_bytes(linear), label + " indexed nearest result matches complete linear search")
		_check(var_to_bytes(builder._nearest_road_info(point, segments)) == var_to_bytes(linear),
			label + " repeated query preserves current result")
	var indexed_crossing: bool = builder._triangle_crosses_road_edges(Vector2(-4, -2), Vector2(14, 18), Vector2(-17, 24), polygons)
	builder._road_edge_cells.clear()
	_check(indexed_crossing == builder._triangle_crosses_road_edges_uncached(Vector2(-4, -2), Vector2(14, 18), Vector2(-17, 24), polygons),
		label + " indexed crossing matches full polygon-edge traversal")


func _oracle(segments: Array, polygons: Array, size: float, width: float) -> Array:
	var segment_cells: Dictionary = {}
	var edge_cells: Dictionary = {}
	var edges: Array = []
	var reach := 0.0
	for index in range(segments.size()):
		var segment: Dictionary = segments[index]
		reach = maxf(reach, maxf(maxf(float(segment.get("left_half_xz_a", width * 0.5)), float(segment.get("left_half_xz_b", width * 0.5))),
			maxf(float(segment.get("right_half_xz_a", width * 0.5)), float(segment.get("right_half_xz_b", width * 0.5)))))
		_index(segment_cells, index, segment.get("a", Vector2.ZERO), segment.get("b", Vector2.ZERO), size)
	for polygon in polygons:
		if polygon.size() < 2:
			continue
		for index in range(polygon.size()):
			var a: Vector2 = polygon[index]
			var b: Vector2 = polygon[(index + 1) % polygon.size()]
			_index(edge_cells, edges.size(), a, b, size)
			edges.append([a, b])
	return [segment_cells, edge_cells, edges, reach]


func _index(cells: Dictionary, id: int, a: Vector2, b: Vector2, size: float) -> void:
	var bounds := Rect2(a, Vector2.ZERO).expand(b)
	for x in range(floori(bounds.position.x / size), floori(bounds.end.x / size) + 1):
		for z in range(floori(bounds.position.y / size), floori(bounds.end.y / size) + 1):
			var cell := Vector2i(x, z)
			if not cells.has(cell):
				cells[cell] = []
			cells[cell].append(id)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)
