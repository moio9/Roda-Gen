extends SceneTree
const BUILDER = preload("../addons/scripts/spline_road/terrain_topology_builder.gd")
const CACHE = preload("../addons/scripts/spline_road/topology_point_cache.gd")
class CollisionCache extends "../addons/scripts/spline_road/topology_point_cache.gd":
	func _query_key(_input: PackedByteArray) -> String:
		return "forced_collision"
var checks := 0
var failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_grid_coordinates()
	_check_near_coordinates()
	var cached := BUILDER.new()
	var full := BUILDER.new()
	var segments: Array = [{"a": Vector2(-8, 0), "b": Vector2(12, 0)}]
	var rows: Array = []
	for i in range(80):
		rows.append({"path_id": i / 40, "dist": float(i % 40) * 0.7,
			"center2": Vector2(i % 40 - 12, (i / 40) * 15), "right2": Vector2(0, -1),
			"left_half_xz": 3.0, "right_half_xz": 4.0})
	rows[10].right2 = Vector2.ZERO
	var data := {"rows": rows, "segments": segments}
	for builder: Node in [cached, full]:
		builder.near_road_width = 10
		builder.near_road_step = 2.3
		builder.far_grid_step = 3.1
		builder._source_cache.configure(builder == cached, false)
		builder._point_cache.configure(builder == cached, false)
		builder._build_road_spatial_index(segments, [])
	for mode in range(3):
		for budget in [1, 2, 3, 7, 16, 33, 64, 65, 127, 256, 9999]:
			for warm in range(2):
				var actual := _points(cached, data, budget, mode)
				var expected := _points(full, data, budget, mode)
				_check(var_to_bytes(actual) == var_to_bytes(expected),
					"point order/dedup/budget exact mode=%d budget=%d warm=%d" % [mode, budget, warm])
	_check(cached._point_cache.stats.candidates_reused > 0, "budget tests exercise real cached proposal replay")
	for edit in range(4):
		if edit == 0:
			segments[0].a.y += 10
			segments[0].b.y += 10
		elif edit == 1:
			segments.append({"a": Vector2(20, -15), "b": Vector2(20, 25)})
		elif edit == 2:
			segments[0].left_half_xz_a = 12.0
			segments[0].left_half_xz_b = 12.0
		else:
			rows.reverse()
		for builder: Node in [cached, full]:
			builder._build_road_spatial_index(segments, [])
		_check(var_to_bytes(_points(cached, data, 9999, 2)) == var_to_bytes(_points(full, data, 9999, 2)),
			"point dependencies invalidate on road move/incoming width/order edit " + str(edit))
	var before := _points(cached, data, 9999, 2)
	before[0] = Vector2(99, 99)
	_check(var_to_bytes(_points(cached, data, 9999, 2)) == var_to_bytes(_points(full, data, 9999, 2)),
		"returned point mutation cannot poison retained proposals")
	_check_helper(cached, data)
	cached.clear_source_generation_cache()
	_check(cached._point_cache._entries.is_empty(), "public source clear releases retained point blocks")
	cached.free()
	full.free()
	print("TOPOLOGY_POINT_CACHE_%s checks=%d" % ["FAILED" if failed else "OK", checks])
	quit(1 if failed else 0)


func _points(builder: Node, data: Dictionary, budget: int, mode: int) -> PackedVector2Array:
	builder._generation_point_budget = budget
	var points := PackedVector2Array([Vector2.ZERO])
	var keys := {Vector2i.ZERO: true}
	if mode != 1:
		builder._add_near_road_points(points, keys, data, data.segments)
	if mode != 0:
		builder._add_far_grid_points(points, keys, Rect2(-20.25, -10.75, 60.5, 40.5), data.segments)
	return points


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(label)


func _check_helper(builder: Node, data: Dictionary) -> void:
	var source = builder._source_cache
	var predicate := func(point: Vector2, clearance: float) -> bool: return builder._is_inside_road_mask(point, data.segments, clearance)
	var cache := CollisionCache.new()
	cache.configure(true, false)
	var a := PackedVector2Array([Vector2(-90, -90)])
	var b := PackedVector2Array([Vector2(-80, -80)])
	_check(cache.filter(a, 0, [], source, predicate) == a and cache.filter(b, 0, [], source, predicate) == b
		and cache.filter(a, 0, [], source, predicate) == a and cache.stats.groups_rebuilt == 3,
		"forced hash collisions cannot alias exact candidate inputs")
	var exposed := cache.filter(a, 0, [], source, predicate)
	exposed[0] = Vector2.ZERO
	_check(cache.filter(a, 0, [], source, predicate) == a, "direct returned proposal mutation cannot alter retained results")
	var unbounded := PackedVector2Array()
	unbounded.resize(cache.BLOCK_SIZE + 1)
	cache.configure(true, true)
	cache.filter(unbounded, 0, [], source, predicate)
	_check(cache._entries.is_empty(), "oversized candidate block bypasses retention")
	var bounded := CACHE.new()
	bounded.configure(true, false)
	for i in range(bounded.MAX_ENTRIES + 1):
		bounded.filter(PackedVector2Array([Vector2(i * 8, -90)]), 0, [], source, predicate)
	_check(bounded._entries.size() == bounded.MAX_ENTRIES and bounded.stats.evicted == 1,
		"actual 16384 point-block entry limit evicts one oldest record")
	bounded.configure(true, true)
	var large := PackedByteArray()
	large.resize(128 * 1024)
	for i in range(600):
		bounded.filter(PackedVector2Array([Vector2(i * 8, -90)]), 0, [large], source, predicate)
	var exact_bytes := 0
	for entry: Dictionary in bounded._entries.values():
		exact_bytes += entry.input.size() + var_to_bytes(entry.result).size()
	_check(exact_bytes == bounded._payload_bytes and exact_bytes <= bounded.MAX_PAYLOAD_BYTES and bounded._entries.size() < 600,
		"actual 64 MiB payload pressure preserves exact accounting and bounded snapshots")


func _check_near_coordinates() -> void:
	var reference := BUILDER.new()
	var cache := CACHE.new()
	cache.configure(true, false)
	var rows: Array = []
	var negative_zero := -float(checks) * 0.0
	for i in range(83):
		rows.append({"path_id": i / 40, "dist": float(i % 40) * 0.73,
			"center2": Vector2(i * 0.17, negative_zero), "right2": Vector2(0.33, -0.71),
			"left_half_xz": 1.000000000001, "right_half_xz": 5.333333333333})
	rows[2].right2 = Vector2.ZERO
	rows[5].right2 = Vector2(0.0009, 0)
	rows[7].erase("left_half_xz")
	rows[7].erase("right_half_xz")
	rows[7].width = 9.123456789
	rows[12].erase("left_half_xz")
	var bands := PackedFloat32Array([0.13, 2.73, 17.21])
	for edit in range(6):
		if edit == 1:
			rows[33].dist += 0.700000000001
		elif edit == 2:
			rows[34].center2 += Vector2(0.03125, 0.0625)
			rows[34].right_half_xz += 1.000000000001
		elif edit == 3:
			for i in range(rows.size()):
				rows[i].path_id = i % 3
		elif edit == 4:
			rows.reverse()
		elif edit == 5:
			reference.fallback_road_width += 3.25
		for step in [0.5, 1.1, 2.3]:
			for warm in range(2):
				var actual := PackedVector2Array()
				var expected := PackedVector2Array()
				for distance in bands:
					var last: Dictionary = {}
					for row: Dictionary in rows:
						var path_id := int(row.get("path_id", -1))
						var dist := float(row.get("dist", 0.0))
						if dist - float(last.get(path_id, -INF)) < step and dist > 0.0001:
							continue
						last[path_id] = dist
						expected.append_array(_native_row_coordinates(row, distance, reference.fallback_road_width))
					last = {}
					var cursor := 0
					while cursor < rows.size():
						var path_id := int(rows[cursor].get("path_id", -1))
						var block: Dictionary = cache.near_block(rows, cursor, float(last.get(path_id, -INF)), step, reference.fallback_road_width)
						last[path_id] = block.last_dist
						cursor = block.next
						actual.append_array(cache.near_coordinates(block.frames, distance))
				_check(var_to_bytes(actual) == var_to_bytes(expected), "near selection/coordinates preserve native bits on dist/frame/path/order/default changes " + str([edit, step, warm]))
	_check(cache.stats.near_rows_reused > 0 and cache.stats.near_rows_rebuilt > 0
		and cache.stats.near_coordinates_reused > 0 and cache.stats.near_coordinates_rebuilt > 0, "near fixtures exercise retained row selection and coordinate construction")
	var block: Dictionary = cache.near_block(rows, 0, -INF, 0.5, reference.fallback_road_width)
	var snapshot := var_to_bytes(block)
	block.frames[0][0] = Vector2(99, 99)
	block.last_dist = 99
	_check(var_to_bytes(cache.near_block(rows, 0, -INF, 0.5, reference.fallback_road_width)) == snapshot,
		"mutable frame and double-precision cursor results cannot poison retained selection")
	block = cache.near_block(rows, 0, -INF, 0.5, reference.fallback_road_width)
	var coordinates: PackedVector2Array = cache.near_coordinates(block.frames, 0.13)
	var coordinate_bytes := var_to_bytes(coordinates)
	coordinates[0] = Vector2(99, 99)
	_check(var_to_bytes(cache.near_coordinates(block.frames, 0.13)) == coordinate_bytes, "returned near coordinates are isolated")
	var shifted := rows.duplicate(true)
	shifted.push_front({"path_id": 99})
	var rebuilt_before: int = cache.stats.near_rows_rebuilt
	var shifted_block: Dictionary = cache.near_block(shifted, 1, -INF, 0.5, reference.fallback_road_width)
	_check(cache.stats.near_rows_rebuilt == rebuilt_before and shifted_block.next == block.next + 1
		and var_to_bytes(shifted_block.frames) == var_to_bytes(block.frames), "global row index changes do not invalidate identical path-local geometry")
	var collision := CollisionCache.new()
	collision.configure(true, false)
	var first: Dictionary = collision.near_block(rows, 0, -INF, 0.5, reference.fallback_road_width)
	collision.near_block(rows, 0, 1000.0, 0.5, reference.fallback_road_width)
	_check(var_to_bytes(collision.near_block(rows, 0, -INF, 0.5, reference.fallback_road_width)) == var_to_bytes(first)
		and collision.stats.near_rows_reused == 0, "selection hash collisions verify exact incoming cursor")
	var a: PackedVector2Array = collision.near_coordinates(first.frames, 0.13)
	collision.near_coordinates(first.frames, 0.14)
	_check(var_to_bytes(collision.near_coordinates(first.frames, 0.13)) == var_to_bytes(a)
		and collision.stats.near_coordinates_reused == 0, "coordinate hash collisions verify exact ring distance")
	cache.configure(true, true)
	var oversized: Array = []
	for i in range(cache.NEAR_ROWS + 1):
		oversized.append([Vector2.ZERO, Vector2.RIGHT, 1.0, 2.0])
	cache.near_coordinates(oversized, 1)
	_check(cache._entries.is_empty(), "oversized near coordinate arrays do not enter bounded retention")
	var endpoint_rows: Array = [{"dist": 0.0}, {"dist": 5.0, "center2": Vector2(0, 5)}]
	var endpoint_block: Dictionary = cache.near_block(endpoint_rows, 0, -INF, 1, 6)
	var endpoint_coordinates: PackedVector2Array = cache.near_coordinates(endpoint_block.frames, 2)
	endpoint_rows[1].dist = 5.25
	var changed_endpoint: Dictionary = cache.near_block(endpoint_rows, 0, -INF, 1, 6)
	var coordinate_reuse: int = cache.stats.near_coordinates_reused
	_check(changed_endpoint.last_dist == 5.25 and cache.near_coordinates(changed_endpoint.frames, 2) == endpoint_coordinates
		and cache.stats.near_coordinates_reused == coordinate_reuse + 4,
		"changed baked endpoint distance reevaluates selection but retains identical ring geometry")
	reference.free()


func _native_row_coordinates(row: Dictionary, distance: float, fallback_width: float) -> PackedVector2Array:
	# Original individual-row coordinate formula, independent of cache helpers.
	var center: Vector2 = row.get("center2", Vector2.ZERO)
	var right: Vector2 = row.get("right2", Vector2.RIGHT)
	if right.length() < 0.001:
		return PackedVector2Array()
	right = right.normalized()
	var left_half := float(row.get("left_half_xz", float(row.get("width", fallback_width)) * 0.5))
	var right_half := float(row.get("right_half_xz", float(row.get("width", fallback_width)) * 0.5))
	return PackedVector2Array([center - right * (left_half + distance), center + right * (right_half + distance)])


func _check_grid_coordinates() -> void:
	var cache := CACHE.new()
	cache.configure(true, false)
	var negative_zero := -float(Time.get_ticks_usec()) * 0.0
	var cases: Array = [Rect2(-20.25, -10.75, 60.5, 40.5), Rect2(12345.67, -3456.78, 8.31, 9.55),
		Rect2(0, 0, 0, 0), Rect2(-3, -4, 0, 4.3), Rect2(0, 0, -1, 4), Rect2(0, 0, 4, -1),
		Rect2(Vector2(negative_zero, negative_zero), Vector2(1, 1))]
	for bounds: Rect2 in cases:
		for step in [0.3, 1.1, 3.1, 20.0]:
			var expected := PackedVector2Array()
			var x := bounds.position.x
			while x <= bounds.position.x + bounds.size.x + 0.0001:
				var z := bounds.position.y
				while z <= bounds.position.y + bounds.size.y + 0.0001:
					expected.append(Vector2(x, z))
					z += step
				x += step
			for warm in range(2):
				var actual := PackedVector2Array()
				var cursor_x := bounds.position.x
				var cursor_z := bounds.position.y
				while true:
					var block: Dictionary = cache.grid_block(cursor_x, cursor_z, bounds, step, 0.0001)
					actual.append_array(block.points)
					if block.done:
						break
					cursor_x = block.x
					cursor_z = block.z
				_check(var_to_bytes(actual) == var_to_bytes(expected), "grid block cursor preserves native coordinate bits, bounds/step/warm " + str([bounds, step, warm]))
	_check(cache.stats.grid_coordinates_reused > 0 and cache.stats.grid_coordinates_rebuilt > 0, "grid fixtures exercise real construction and replay")
	var input := Rect2(-4, -3, 10, 10)
	var exposed: Dictionary = cache.grid_block(-4, -3, input, 0.3, 0.0001)
	var snapshot := var_to_bytes(exposed)
	exposed.points[0] = Vector2(99, 99)
	exposed.x = 99
	_check(var_to_bytes(cache.grid_block(-4, -3, input, 0.3, 0.0001)) == snapshot, "mutating exposed coordinates or continuation cannot poison the grid cache")
