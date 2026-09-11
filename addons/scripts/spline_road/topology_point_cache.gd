@tool
extends "./terrain_stage_cache.gd"
## Coordinate blocks and accepted proposals. Deduplication and the point budget are
## applied by the caller in the original order, never stored as block results.

const BLOCK_SIZE := 64
const NEAR_ROWS := 32
const CONTOUR_EDGES := 16


func configure(use_cache: bool, clear_requested: bool) -> void:
	super.configure(use_cache, clear_requested)
	stats.merge({"groups_reused": 0, "groups_rebuilt": 0, "candidates_reused": 0,
		"candidates_rebuilt": 0, "uncertified": 0, "grid_blocks_reused": 0,
		"grid_blocks_rebuilt": 0, "grid_coordinates_reused": 0, "grid_coordinates_rebuilt": 0,
		"near_rows_reused": 0, "near_rows_rebuilt": 0, "near_coordinates_reused": 0, "near_coordinates_rebuilt": 0})
	stats.merge({"bounds_coordinates_reused": 0, "bounds_coordinates_rebuilt": 0,
		"edge_coordinates_reused": 0, "edge_coordinates_rebuilt": 0,
		"support_coordinates_reused": 0, "support_coordinates_rebuilt": 0})


func _query_key(input: PackedByteArray) -> String:
	return str(hash(input))


func _near_reuse_enabled() -> bool:
	return true


func _boundary_reuse_enabled() -> bool:
	return true


func bounds_block(bounds: Rect2, step: float, epsilon: float, axis: int, cursor: float) -> Dictionary:
	var input := query("bounds_coordinates", [bounds, step, epsilon, axis, cursor]) if _boundary_reuse_enabled() else {}
	var old := lookup(input)
	if not old.is_empty():
		stats.bounds_coordinates_reused += old.result.points.size()
		return old.result.duplicate(true)
	var points := PackedVector2Array()
	# Keep native paired X-then-Z order and double-precision repeated additions.
	var x1 := bounds.position.x + bounds.size.x
	var z1 := bounds.position.y + bounds.size.y
	while axis < 2 and points.size() < BLOCK_SIZE:
		var limit := x1 if axis == 0 else z1
		if cursor > limit + epsilon:
			axis += 1
			cursor = bounds.position.y
			continue
		if axis == 0:
			points.append(Vector2(cursor, bounds.position.y))
			points.append(Vector2(cursor, z1))
		else:
			points.append(Vector2(bounds.position.x, cursor))
			points.append(Vector2(x1, cursor))
		cursor += step
	var result := {"points": points, "axis": axis, "cursor": cursor, "done": axis >= 2}
	stats.bounds_coordinates_rebuilt += points.size()
	store(input, result.duplicate(true))
	return result


func edge_block(a: Vector2, b: Vector2, subdivisions: int, first: int,
		outward := Vector2.ZERO, distances := PackedFloat32Array()) -> Dictionary:
	var input := query("boundary_coordinates", [a, b, subdivisions, first, outward, distances]) if _boundary_reuse_enabled() else {}
	var kind := "edge_coordinates" if distances.is_empty() else "support_coordinates"
	var old := lookup(input)
	if not old.is_empty():
		stats[kind + "_reused"] += old.result.points.size()
		return old.result.duplicate(true)
	var points := PackedVector2Array()
	var width := maxi(1, distances.size())
	var total := (subdivisions + 1) * width
	var cursor := first
	while cursor < total and points.size() < BLOCK_SIZE:
		var j := cursor / width
		var t := float(j) / float(subdivisions)
		var point := a.lerp(b, t)
		# Plain contour points must not undergo even an addition of zero: that
		# can change signed-zero bits relative to the native interpolation.
		points.append(point if distances.is_empty() else point + outward * float(distances[cursor % width]))
		cursor += 1
	var result := {"points": points, "next": cursor, "done": cursor >= total}
	stats[kind + "_rebuilt"] += points.size()
	store(input, result.duplicate(true))
	return result


func contour_block(vertices: PackedVector2Array, step: float, edge: int, sample: int) -> Dictionary:
	var input := query("contour_coordinates", [vertices, step, edge, sample]) if _boundary_reuse_enabled() and vertices.size() <= CONTOUR_EDGES + 1 else {}
	var old := lookup(input)
	if not old.is_empty():
		stats.edge_coordinates_reused += old.result.points.size()
		return old.result.duplicate(true)
	var points := PackedVector2Array()
	while edge + 1 < vertices.size() and points.size() < BLOCK_SIZE:
		var a := vertices[edge]
		var b := vertices[edge + 1]
		var n := maxi(1, int(ceil(a.distance_to(b) / maxf(0.05, step))))
		while sample <= n and points.size() < BLOCK_SIZE:
			points.append(a.lerp(b, float(sample) / float(n)))
			sample += 1
		if sample > n:
			edge += 1
			sample = 0
	var result := {"points": points, "edge": edge, "sample": sample, "done": edge + 1 >= vertices.size()}
	stats.edge_coordinates_rebuilt += points.size()
	store(input, result.duplicate(true))
	return result


func near_block(rows: Array, start: int, last_dist: float, step: float, fallback_width: float) -> Dictionary:
	# Path-local consecutive blocks keep other paths stable when rows are added.
	# Only consumed values enter the key; no source objects or global indices do.
	var path_id := int(rows[start].get("path_id", -1))
	var cursor := start
	var values: Array = []
	while cursor < rows.size() and values.size() < NEAR_ROWS and int(rows[cursor].get("path_id", -1)) == path_id:
		var row: Dictionary = rows[cursor]
		var half := float(row.get("width", fallback_width)) * 0.5
		values.append([float(row.get("dist", 0.0)), row.get("center2", Vector2.ZERO), row.get("right2", Vector2.RIGHT),
			float(row.get("left_half_xz", half)), float(row.get("right_half_xz", half))])
		cursor += 1
	var input := query("near_selection", [values, last_dist, step]) if _near_reuse_enabled() else {}
	var old := lookup(input)
	var result: Dictionary
	if not old.is_empty():
		stats.near_rows_reused += values.size()
		result = old.result.duplicate(true)
	else:
		stats.near_rows_rebuilt += values.size()
		var frames: Array = []
		for value: Array in values:
			var dist: float = value[0]
			if dist - last_dist < step and dist > 0.0001:
				continue
			# Invalid frames still advance the path cursor, as in native emission.
			last_dist = dist
			var right: Vector2 = value[2]
			if right.length() < 0.001:
				continue
			frames.append([value[1], right.normalized(), value[3], value[4]])
		result = {"frames": frames, "last_dist": last_dist}
		store(input, result.duplicate(true))
	result["next"] = cursor
	return result


func near_coordinates(frames: Array, distance: float) -> PackedVector2Array:
	var input := query("near_coordinates", [frames, distance]) if _near_reuse_enabled() and frames.size() <= NEAR_ROWS else {}
	var old := lookup(input)
	if not old.is_empty():
		stats.near_coordinates_reused += old.result.size()
		return old.result.duplicate()
	var points := PackedVector2Array()
	for frame: Array in frames:
		var center: Vector2 = frame[0]
		var right: Vector2 = frame[1]
		var left_half: float = frame[2]
		var right_half: float = frame[3]
		points.append(center - right * (left_half + distance))
		points.append(center + right * (right_half + distance))
	stats.near_coordinates_rebuilt += points.size()
	store(input, points.duplicate())
	return points


func grid_block(x: float, z: float, bounds: Rect2, step: float, epsilon: float) -> Dictionary:
	var input := query("grid_coordinates", [x, z, bounds, step, epsilon])
	var old := lookup(input)
	if not old.is_empty():
		stats.grid_blocks_reused += 1
		stats.grid_coordinates_reused += old.result.points.size()
		return old.result.duplicate(true)
	var result := _build_grid_block(x, z, bounds, step, epsilon)
	stats.grid_blocks_rebuilt += 1
	stats.grid_coordinates_rebuilt += result.points.size()
	store(input, result.duplicate(true))
	return result


func _build_grid_block(x: float, z: float, bounds: Rect2, step: float, epsilon: float) -> Dictionary:
	# Preserve the original double-precision repeated additions. Multiplying an
	# integer grid index by step, or saving the cursor as Vector2, changes rounding.
	var x1 := bounds.position.x + bounds.size.x
	var z1 := bounds.position.y + bounds.size.y
	var points := PackedVector2Array()
	while x <= x1 + epsilon:
		if z > z1 + epsilon:
			x += step
			z = bounds.position.y
			continue
		points.append(Vector2(x, z))
		z += step
		if points.size() == BLOCK_SIZE:
			return {"points": points, "x": x, "z": z, "done": false}
	return {"points": points, "x": x, "z": z, "done": true}


func filter(candidates: PackedVector2Array, clearance: float, settings: Array,
		source: RefCounted, is_inside: Callable) -> PackedVector2Array:
	if candidates.is_empty():
		return PackedVector2Array()
	var input: Dictionary = {}
	if enabled and candidates.size() <= BLOCK_SIZE and source.spatial_ready:
		input = query("point_mask", [candidates, clearance, settings])
	var old := lookup(input)
	if not old.is_empty():
		if source.validate_mesh_scope(old.result.scope):
			stats.groups_reused += 1
			stats.candidates_reused += candidates.size()
			return old.result.points.duplicate()
		# Finding the input bucket alone is not a reusable spatial result.
		stats.queries_reused -= 1
		stats.queries_rebuilt += 1
	stats.groups_rebuilt += 1
	stats.candidates_rebuilt += candidates.size()
	if not input.is_empty():
		source.begin_mesh_scope()
	var result := PackedVector2Array()
	for point: Vector2 in candidates:
		if not is_inside.call(point, clearance):
			result.append(point)
	if not input.is_empty():
		var scope: Dictionary = source.end_mesh_scope()
		if not scope.is_empty():
			store(input, {"points": result.duplicate(), "scope": scope})
		else:
			stats.uncertified += 1
	return result
