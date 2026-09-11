extends SceneTree
const BUILDER = preload("../addons/scripts/spline_road/terrain_topology_builder.gd")
const CACHE = preload("../addons/scripts/spline_road/topology_point_cache.gd")
class CollisionCache extends "../addons/scripts/spline_road/topology_point_cache.gd":
	func _query_key(_input: PackedByteArray) -> String:
		return "collision"
var checks := 0
var failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var cache := CACHE.new()
	cache.configure(true, false)
	var negative_zero := -float(Time.get_ticks_usec()) * 0.0
	for bounds: Rect2 in [Rect2(-20.25, -10.75, 60.5, 40.5), Rect2(12345.67, -3456.78, 8.31, 9.55),
		Rect2(0, 0, -1, 4), Rect2(0, 0, 4, -1), Rect2(Vector2(negative_zero, negative_zero), Vector2.ZERO)]:
		for step in [0.3, 1.1, 20.0]:
			var expected := _native_bounds(bounds, step)
			for warm in range(2):
				var points := PackedVector2Array()
				var axis := 0
				var cursor := bounds.position.x
				while true:
					var block: Dictionary = cache.bounds_block(bounds, step, 0.0001, axis, cursor)
					points.append_array(block.points)
					if block.done:
						break
					axis = block.axis
					cursor = block.cursor
				_check(var_to_bytes(points) == var_to_bytes(expected), "paired bounds order and float64 cursor match native repeated additions")
	for subdivisions in [1, 31, 32, 63, 64, 65, 129]:
		for distances: PackedFloat32Array in [PackedFloat32Array(), PackedFloat32Array([0.13]), PackedFloat32Array([0.13, 2.71, 4.35])]:
			var a := Vector2(negative_zero, negative_zero)
			var b := Vector2(13.73, 17.29)
			var outward := Vector2(0.73, -0.23).normalized()
			var expected := PackedVector2Array()
			for j in range(subdivisions + 1):
				var p := a.lerp(b, float(j) / float(subdivisions))
				if distances.is_empty():
					expected.append(p)
				else:
					for d in distances:
						expected.append(p + outward * float(d))
			for warm in range(2):
				var points := PackedVector2Array()
				var cursor := 0
				while true:
					var block: Dictionary = cache.edge_block(a, b, subdivisions, cursor, outward, distances)
					_check(block.points.size() <= cache.BLOCK_SIZE, "each edge/support result respects the 64-coordinate cap")
					points.append_array(block.points)
					if block.done:
						break
					cursor = block.next
				_check(var_to_bytes(points) == var_to_bytes(expected), "edge/support interpolation preserves sample-then-distance order and exact bits")
	var exposed: Dictionary = cache.edge_block(Vector2.ZERO, Vector2.ONE, 128, 0)
	var before := var_to_bytes(exposed)
	exposed.points[0] = Vector2(99, 99)
	exposed.next = 99
	_check(var_to_bytes(cache.edge_block(Vector2.ZERO, Vector2.ONE, 128, 0)) == before, "returned edge coordinates and cursor cannot mutate retained blocks")
	var collision := CollisionCache.new()
	collision.configure(true, false)
	var old: Dictionary = collision.edge_block(Vector2.ZERO, Vector2.ONE, 128, 0)
	collision.edge_block(Vector2.ZERO, Vector2.ONE, 128, 64)
	_check(var_to_bytes(collision.edge_block(Vector2.ZERO, Vector2.ONE, 128, 0)) == var_to_bytes(old)
		and collision.stats.edge_coordinates_reused == 0, "forced hash collisions validate exact edge cursor")
	var changed: Dictionary = cache.edge_block(Vector2.ZERO, Vector2.ONE, 128, 0, Vector2.RIGHT, PackedFloat32Array([1]))
	_check(var_to_bytes(changed.points) != var_to_bytes(cache.edge_block(Vector2.ZERO, Vector2.ONE, 128, 0, Vector2.LEFT, PackedFloat32Array([1])).points),
		"current outward direction is an exact support-coordinate dependency")
	_budget_checks()
	_contour_checks()
	print("TOPOLOGY_BOUNDARY_POINTS_%s checks=%d" % ["FAILED" if failed else "OK", checks])
	quit(1 if failed else 0)


func _native_bounds(bounds: Rect2, step: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var x := bounds.position.x
	while x <= bounds.position.x + bounds.size.x + 0.0001:
		points.append(Vector2(x, bounds.position.y))
		points.append(Vector2(x, bounds.position.y + bounds.size.y))
		x += step
	var z := bounds.position.y
	while z <= bounds.position.y + bounds.size.y + 0.0001:
		points.append(Vector2(bounds.position.x, z))
		points.append(Vector2(bounds.position.x + bounds.size.x, z))
		z += step
	return points


func _budget_checks() -> void:
	var cached := BUILDER.new()
	var full := BUILDER.new()
	var poly := PackedVector2Array([Vector2(-10, -4), Vector2(12, -4), Vector2(12, 4), Vector2(-10, 4), Vector2(-10, 4)])
	var segments: Array = [{"a": Vector2(-10, 0), "b": Vector2(12, 0)}]
	for builder: Node in [cached, full]:
		builder.far_grid_step = 3.1
		builder._source_cache.configure(builder == cached, false)
		builder._point_cache.configure(builder == cached, false)
		builder._build_road_spatial_index(segments, [poly])
	for stage in range(4):
		for budget in [1, 2, 3, 7, 33, 64, 65, 127, 256, 9999]:
			for warm in range(2):
				_check(var_to_bytes(_points(cached, poly, segments, stage, budget)) == var_to_bytes(_points(full, poly, segments, stage, budget)),
					"native ordered deduplication and budget match for contour/support/bounds stages")
	for edit in range(4):
		if edit == 0:
			segments[0].a.y += 10
			segments[0].b.y += 10
		elif edit == 1:
			segments.append({"a": Vector2(-10, -8), "b": Vector2(12, -8)})
		elif edit == 2:
			segments[0].left_half_xz_a = 12.0
			segments[0].left_half_xz_b = 12.0
		else:
			poly.reverse()
		for builder: Node in [cached, full]:
			builder._build_road_spatial_index(segments, [poly])
		_check(var_to_bytes(_points(cached, poly, segments, 3, 9999)) == var_to_bytes(_points(full, poly, segments, 3, 9999)),
			"current outward probes and support masks reflect moved/incoming/wider/reversed roads")
	_check(cached._point_cache.stats.bounds_coordinates_reused > 0 and cached._point_cache.stats.edge_coordinates_reused > 0
		and cached._point_cache.stats.support_coordinates_reused > 0, "all integrated boundary stages exercise retained coordinates")
	cached.clear_source_generation_cache()
	_check(cached._point_cache._entries.is_empty(), "public cache clear releases contour and support coordinates")
	cached.free()
	full.free()


func _points(builder: Node, poly: PackedVector2Array, segments: Array, stage: int, budget: int) -> PackedVector2Array:
	builder._generation_point_budget = budget
	var points := PackedVector2Array([Vector2.ZERO])
	var keys := {Vector2i.ZERO: true}
	if stage == 0 or stage == 3:
		builder._resample_polygon_points(points, keys, poly, 0.7, segments)
	if stage == 1 or stage == 3:
		builder._add_polygon_boundary_support_points(points, keys, poly, 0.7, segments)
	if stage == 2 or stage == 3:
		builder._add_bounds_points(points, keys, Rect2(-20.25, -10.75, 60.5, 40.5))
	return points


func _contour_checks() -> void:
	var cached := BUILDER.new()
	var full := BUILDER.new()
	cached._point_cache.configure(true, false)
	for count in [2, 16, 17, 32, 35]:
		var polygon := PackedVector2Array()
		for i in range(count):
			polygon.append(Vector2(i * 1.73, sin(i * 0.37) * 3.1))
		for step in [0.7, 20.0]:
			for budget in [1, 2, 63, 64, 65, 9999]:
				for warm in range(2):
					var actual := PackedVector2Array()
					var expected := PackedVector2Array()
					cached._generation_point_budget = budget
					full._generation_point_budget = budget
					cached._resample_polygon_points(actual, {}, polygon, step, [])
					full._resample_polygon_points(expected, {}, polygon, step, [])
					_check(var_to_bytes(actual) == var_to_bytes(expected), "16-edge block transitions and long-edge continuations preserve native polygon order/budget")
	var vertices := PackedVector2Array([Vector2.ZERO, Vector2(100, 10), Vector2(110, 3)])
	var block: Dictionary = cached._point_cache.contour_block(vertices, 0.7, 0, 0)
	var snapshot := var_to_bytes(block)
	block.points[0] = Vector2(99, 99)
	block.sample = 999
	_check(var_to_bytes(cached._point_cache.contour_block(vertices, 0.7, 0, 0)) == snapshot, "contour sample cursor and geometry are isolated on replay")
	var collision := CollisionCache.new()
	collision.configure(true, false)
	var first: Dictionary = collision.contour_block(vertices, 0.7, 0, 0)
	collision.contour_block(vertices, 0.7, 0, 64)
	_check(var_to_bytes(collision.contour_block(vertices, 0.7, 0, 0)) == var_to_bytes(first)
		and collision.stats.edge_coordinates_reused == 0, "contour hash collisions validate exact subdivision continuation")
	cached.free()
	full.free()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(label)
