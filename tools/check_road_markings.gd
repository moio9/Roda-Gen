extends SceneTree

const DEMO := preload("../addons/scenes/road_markings_demo.tscn")
const MARKINGS := preload("../addons/scripts/spline_road/road_marking_builder.gd")
var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := DEMO.instantiate()
	root.add_child(scene)
	var road: Node3D = scene.get_node("Road")
	var path := road.get_node("Route") as Path3D
	var paint := road.get_node_or_null(MARKINGS.NODE_NAME) as MeshInstance3D
	_check(paint != null and paint.mesh != null, "demo generates paint")
	if paint == null or paint.mesh == null:
		scene.free()
		quit(1)
		return
	var original_road := _mesh_bytes(road.get_node("GeneratedSplineRoadWelded").mesh)
	var initial_stats: Dictionary = road.get_marking_stats()
	_check(int(initial_stats.get("center_triangles", 0)) > 0, "double center lines exist")
	_check(int(initial_stats.get("line_triangles", 0)) > 0, "lane and edge lines exist")
	_check(int(initial_stats.get("hatch_triangles", 0)) > 0, "entry and exit hatching exists")
	_check(paint.get_child_count() == 0 and paint.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "paint has no collision or cast shadows")
	_check_conformity(road, paint.mesh)
	var hatch := _surface(paint.mesh, "Hatching")
	var hatch_uvs: PackedVector2Array = hatch[Mesh.ARRAY_TEX_UV]
	var offsets: PackedFloat32Array = path._control_point_offsets()
	var entry_count := 0
	var exit_count := 0
	for uv in hatch_uvs:
		_check(uv.x >= 3.5, "hatching stays on the added/removed right lane, not the opposite lane")
		entry_count += int(uv.y <= offsets[1] + 0.001)
		exit_count += int(uv.y >= offsets[2] - 0.001)
	_check(entry_count > 0 and exit_count > 0, "hatching covers both entry and exit transitions")
	var bake_path := "/tmp/roda-markings-%s.tscn" % Time.get_ticks_usec()
	_check(road.bake_runtime_scene(bake_path) == OK, "paint is included in bake")
	var baked: Node = load(bake_path).instantiate()
	_check(baked.has_node(MARKINGS.NODE_NAME), "baked scene retains paint")
	_check(_mesh_bytes(baked.get_node(MARKINGS.NODE_NAME).mesh) == _mesh_bytes(paint.mesh), "baked paint attributes match")
	baked.free()
	# Isolate the center line to check exact style coverage in road-distance UVs.
	road.markings_lane_style = MARKINGS.OFF
	road.markings_edge_style = MARKINGS.OFF
	road.markings_hatching_enabled = false
	var areas: Array[float] = []
	for style in [MARKINGS.SOLID, MARKINGS.DASHED, MARKINGS.DOUBLE_SOLID, MARKINGS.DOUBLE_DASHED]:
		road.markings_center_style = style
		road.regenerate()
		paint = road.get_node(MARKINGS.NODE_NAME)
		areas.append(_parameter_area(paint.mesh))
		if style == MARKINGS.DASHED:
			_check(_covers(paint.mesh, Vector2(0, 1.5)), "dash includes painted interval")
			_check(not _covers(paint.mesh, Vector2(0, 5.0)), "dash gap is actually empty")
		if style in [MARKINGS.DOUBLE_SOLID, MARKINGS.DOUBLE_DASHED]:
			_check(not _covers(paint.mesh, Vector2(0, 1.5)), "double line keeps its center gap")
			_check(_covers(paint.mesh, Vector2(0.12, 1.5)), "double line includes positive stripe")
			_check(_covers(paint.mesh, Vector2(-0.12, 1.5)), "double line includes negative stripe")
	_check(absf(areas[2] - 2.0 * areas[0]) < 0.01, "double solid has two full-width stripes")
	_check(absf(areas[3] - 2.0 * areas[1]) < 0.01, "double dashed keeps dash coverage on both stripes")
	_check(areas[1] < areas[0] * 0.7, "dashed style does not accidentally fill its gaps")
	_check(_mesh_bytes(road.get_node("GeneratedSplineRoadWelded").mesh) == original_road, "paint settings never change the road mesh")
	road.markings_center_style = MARKINGS.DASHED
	road.markings_dash_offset = -2.0
	road.regenerate()
	paint = road.get_node(MARKINGS.NODE_NAME)
	_check(not _covers(paint.mesh, Vector2(0, 1.0)) and _covers(paint.mesh, Vector2(0, 3.0)), "negative dash phase keeps distance-based gaps")
	road.markings_dash_offset = 0.0
	road.markings_hatching_enabled = true
	road.markings_lane_style = MARKINGS.DASHED
	road.markings_edge_style = MARKINGS.SOLID
	path.point_lanes_left = PackedInt32Array([1, 2, 2, 1])
	path.point_lanes_right = PackedInt32Array([1, 1, 1, 1])
	road.regenerate()
	var mirrored_hatch := _surface(road.get_node(MARKINGS.NODE_NAME).mesh, "Hatching")
	_check(not mirrored_hatch.is_empty(), "left-hand transitions produce hatching")
	if not mirrored_hatch.is_empty():
		for uv: Vector2 in mirrored_hatch[Mesh.ARRAY_TEX_UV]:
			_check(uv.x <= -3.5, "left-hand hatching stays on the left")
	path.point_lanes_left = PackedInt32Array([2, 2, 2, 2])
	path.point_lanes_right = PackedInt32Array([2, 2, 2, 2])
	path.point_lane_widths = PackedFloat32Array([3.5, 4.25, 3.25, 4.0])
	road.regenerate()
	_check(int(road.get_marking_stats().get("hatch_triangles", -1)) == 0, "lane-width-only changes do not create false merge hatching")
	path.point_lanes_left = PackedInt32Array([0, 0, 0, 0])
	road.regenerate()
	_check(int(road.get_marking_stats().get("center_triangles", -1)) == 0, "one-way road has no opposing center divider")
	path.point_lanes_left = PackedInt32Array([1, 1, 1, 1])
	path.point_lanes_right = PackedInt32Array([1, 2, 2, 1])
	path.point_lane_widths = PackedFloat32Array([3.5, 3.5, 3.5, 3.5])
	road.transform = Transform3D(Basis.from_euler(Vector3(0.1, 0.2, 0.05)).scaled(Vector3(-1.1, 0.9, 1.2)), Vector3(-15, 3, 20))
	road.regenerate()
	_check_conformity(road, road.get_node(MARKINGS.NODE_NAME).mesh)
	road.transform = Transform3D.IDENTITY
	# Endpoint welding produces explicit no-paint intervals on both source paths.
	var branch := Path3D.new()
	branch.name = "Branch"
	branch.curve = Curve3D.new()
	branch.curve.add_point(Vector3(-35, 0, 0))
	branch.curve.add_point(Vector3.ZERO)
	road.add_child(branch)
	road.regenerate()
	var exclusions: Dictionary = road.get("_marking_exclusions")
	_check(exclusions.has(0) and exclusions.has(1), "junction sockets produce per-path exclusions")
	var rows: Array = road.get("_marking_rows")
	var builder := MARKINGS.new()
	builder.configure(road)
	var source_mesh: Mesh = road.get_node("GeneratedSplineRoadWelded").mesh
	var only_first := builder.build(source_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], [rows[0]], {0: exclusions.get(0, [])})
	for interval: Vector2 in exclusions.get(0, []):
		for surface in range(only_first.get_surface_count()):
			var uvs: PackedVector2Array = only_first.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]
			for uv in uvs:
				_check(uv.y <= interval.x + 0.001 or uv.y >= interval.y - 0.001, "paint stops at the welded intersection")
	var before_thread := _mesh_bytes(road.get_node(MARKINGS.NODE_NAME).mesh)
	path.outer_wall_height = 0.3
	road.threaded_generation_enabled = true
	road.regenerate()
	var deadline := Time.get_ticks_msec() + 10000
	while road._is_generation_thread_active() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not road._is_generation_thread_active(), "threaded road generation completes")
	_check(_mesh_bytes(road.get_node(MARKINGS.NODE_NAME).mesh) == before_thread, "worker completion keeps paint identical")
	var previous_color: Color = road.markings_line_color
	road.regenerate()
	road.threaded_generation_enabled = false
	road.markings_line_color = Color(0.9, 0.25, 0.5)
	road.regenerate()
	_check(road._marking_builder._settings["line_color"] == previous_color, "turning threading off does not overwrite an active job's snapshot")
	deadline = Time.get_ticks_msec() + 10000
	while road._is_generation_thread_active() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not road._is_generation_thread_active(), "cancelled worker joins before synchronous regeneration")
	_check(road._marking_builder._settings["line_color"] == road.markings_line_color, "queued synchronous regeneration applies the new settings")
	road.output_mode = 1
	road.regenerate()
	var chunk_bake := bake_path.get_basename() + "-chunks.tscn"
	var bake_result: Error = road.bake_runtime_scene(chunk_bake)
	_check(bake_result == OK, "chunked roads also bake their paint")
	if bake_result != OK:
		scene.free()
		quit(1)
		return
	var baked_chunks: Node = load(chunk_bake).instantiate()
	_check(baked_chunks.has_node("GeneratedRoadChunks") and baked_chunks.has_node(MARKINGS.NODE_NAME), "chunked bake includes road and paint")
	_check(_mesh_bytes(baked_chunks.get_node(MARKINGS.NODE_NAME).mesh) == before_thread, "chunked baked paint attributes match")
	baked_chunks.free()
	road.markings_enabled = false
	road.regenerate()
	_check(road.get_node_or_null(MARKINGS.NODE_NAME) == null, "disabling paint removes generated output")
	scene.free()
	print("ROAD_MARKINGS_%s stats=%s areas=%s entry=%s exit=%s" % ["FAILED" if _failed else "OK", initial_stats, areas, entry_count, exit_count])
	quit(1 if _failed else 0)


func _check_conformity(road: Node, paint: Mesh) -> void:
	var rows: Array = road.get("_marking_rows")[0]
	var road_mesh: Mesh = road.get_node("GeneratedSplineRoadWelded").mesh
	var source: PackedVector3Array = road_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var max_error := 0.0
	var tilted := 0
	for surface in range(paint.get_surface_count()):
		var arrays := paint.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for vertex in range(vertices.size()):
			var point := Vector2(uvs[vertex].y, uvs[vertex].x)
			var best_error := INF
			for row_index in range(rows.size() - 1):
				var a: Dictionary = rows[row_index]
				var b: Dictionary = rows[row_index + 1]
				if point.x < float(a["distance"]) - 0.0001 or point.x > float(b["distance"]) + 0.0001:
					continue
				var extent_a: Vector2 = a["lane_extents"]
				var extent_b: Vector2 = b["lane_extents"]
				var domain := [Vector2(a["distance"], -extent_a.x), Vector2(a["distance"], extent_a.y), Vector2(b["distance"], -extent_b.x), Vector2(b["distance"], extent_b.y)]
				var positions := [source[a["row_edges"][2]], source[a["row_edges"][3]], source[b["row_edges"][2]], source[b["row_edges"][3]]]
				for corners in [[0, 1, 2], [2, 1, 3]]:
					var weights := _barycentric(point, domain[corners[0]], domain[corners[1]], domain[corners[2]])
					if minf(weights.x, minf(weights.y, weights.z)) < -0.0002:
						continue
					var expected: Vector3 = positions[corners[0]] * weights.x + positions[corners[1]] * weights.y + positions[corners[2]] * weights.z
					var unlifted := vertices[vertex] - normals[vertex] * float(road.get("markings_surface_lift"))
					best_error = minf(best_error, unlifted.distance_to(expected))
			max_error = maxf(max_error, best_error)
			tilted += int(absf(normals[vertex].x) > 0.05 or absf(normals[vertex].z) > 0.05)
	_check(max_error < 0.0003, "paint conforms to actual triangles including banking: error=%s" % max_error)
	_check(tilted > 100, "fixture exercises tilted road paint")
	print("ROAD_MARKINGS_CONFORM max_error=%s tilted_vertices=%s" % [max_error, tilted])


func _surface(mesh: Mesh, surface_name: String) -> Array:
	for index in range(mesh.get_surface_count()):
		if mesh.surface_get_name(index) == surface_name:
			return mesh.surface_get_arrays(index)
	return []


func _barycentric(point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var denominator := (b - a).cross(c - a)
	if absf(denominator) < 0.0000001:
		return Vector3(-1, -1, -1)
	var wb := (point - a).cross(c - a) / denominator
	var wc := (b - a).cross(point - a) / denominator
	return Vector3(1.0 - wb - wc, wb, wc)


func _covers(mesh: Mesh, point: Vector2) -> bool:
	for surface in range(mesh.get_surface_count()):
		var uvs: PackedVector2Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]
		for i in range(0, uvs.size(), 3):
			var weights := _barycentric(point, uvs[i], uvs[i + 1], uvs[i + 2])
			if minf(weights.x, minf(weights.y, weights.z)) >= -0.00001:
				return true
	return false


func _parameter_area(mesh: Mesh) -> float:
	var area := 0.0
	for surface in range(mesh.get_surface_count()):
		var uvs: PackedVector2Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]
		for i in range(0, uvs.size(), 3):
			area += absf((uvs[i + 1] - uvs[i]).cross(uvs[i + 2] - uvs[i])) * 0.5
	return area


func _mesh_bytes(mesh: Mesh) -> PackedByteArray:
	var arrays: Array = []
	for surface in range(mesh.get_surface_count()):
		arrays.append(mesh.surface_get_arrays(surface))
	return var_to_bytes(arrays)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("ROAD_MARKINGS: " + message)
