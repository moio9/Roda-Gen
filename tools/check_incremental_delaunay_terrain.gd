extends SceneTree

const ROAD = preload("../addons/scripts/spline_road/road_network_creator.gd")
const PROFILE = preload("../addons/scripts/spline_road/spline_path_profile.gd")
const TOPOLOGY = preload("../addons/scripts/spline_road/terrain_topology_builder.gd")
const LOCAL = preload("./fixtures/incremental_delaunay_probe.gd")
const CAVITY = preload("./fixtures/local_delaunay_cavity_probe.gd")

class CaptureTerrain extends TOPOLOGY:
	var captured := PackedVector2Array()
	var native := PackedInt32Array()
	func _finalize_triangulation(points: PackedVector2Array, indices: PackedInt32Array,
			_segments: Array, _polygons: Array, _data: Dictionary) -> void:
		captured = points.duplicate()
		native = indices.duplicate()

var failed := false
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := Node3D.new()
	var road := ROAD.new()
	road.name = "Road"
	road.threaded_generation_enabled = false
	road.debug_generation_logs = false
	road.generate_in_editor = false
	var path := PROFILE.new()
	path.name = "Path"
	path.curve = Curve3D.new()
	for p in [Vector3(-35, 0, -30), Vector3(-20, 2, 0), Vector3(0, 4, 30), Vector3(20, 0, 60)]:
		path.curve.add_point(p, Vector3(0, 0, -10), Vector3(0, 0, 10))
	road.add_child(path)
	scene.add_child(road)
	var terrain := CaptureTerrain.new()
	terrain.name = "Terrain"
	terrain.generate_in_editor = false
	terrain.threaded_triangulation_enabled = false
	terrain.road_network_source = NodePath("../Road")
	terrain.source_paths.assign([NodePath("../Road/Path")])
	terrain.path_sample_step = 4
	terrain.adaptive_path_sampling = false
	terrain.bounds_mode = 1
	terrain.manual_center_xz = Vector2(0, 20)
	terrain.manual_size_xz = Vector2(160, 160)
	terrain.near_road_width = 12
	terrain.near_road_step = 6
	terrain.far_grid_step = 12
	if OS.get_cmdline_user_args().has("--large"):
		for i in range(1, 10):
			var other := PROFILE.new()
			other.name = "Path" + str(i)
			other.curve = path.curve.duplicate(true)
			other.position.x = i * 85
			road.add_child(other)
			terrain.source_paths.append(NodePath("../Road/" + str(other.name)))
		terrain.manual_center_xz = Vector2(350, 20)
		terrain.manual_size_xz = Vector2(950, 220)
	scene.add_child(terrain)
	root.add_child(scene)
	var cavity_mode := OS.get_cmdline_user_args().has("--cavity")
	var conditioned := OS.get_cmdline_user_args().has("--conditioned")
	var cache: RefCounted = CAVITY.new() if cavity_mode else LOCAL.new()
	if cavity_mode:
		cache.condition_native = conditioned
	var full_times: Array[float] = []
	var local_times: Array[float] = []
	var patched_edits := 0
	for i in range(8):
		if i >= 2:
			path.curve.set_point_position(2, path.curve.get_point_position(2) + Vector3(0.25, 0.1, 0))
		terrain.regenerate()
		if i == 0:
			print("PROBE_TOPOLOGY_INPUT_HASH ", hash(terrain.captured))
		var started := Time.get_ticks_usec()
		var native := _reference(terrain.captured, conditioned)
		var full_ms := float(Time.get_ticks_usec() - started) / 1000.0
		if i == 0 and OS.get_cmdline_user_args().has("--inspect-overlap"):
			print("NATIVE_TERRAIN_OVERLAP ", _overlap_at(terrain.captured, native, Vector2(-17, -54)))
		if i == 0 and OS.get_cmdline_user_args().has("--reduce-overlap"):
			_reduce_overlap(terrain.captured, Vector2(-17, -54))
			scene.free()
			quit(0)
			return
		started = Time.get_ticks_usec()
		var actual: PackedInt32Array = cache.triangulate(terrain.captured)
		var local_ms := float(Time.get_ticks_usec() - started) / 1000.0
		checks += 1
		var same: bool = _canonical(actual) == _canonical(native) if cavity_mode else actual == native
		if not same or (not conditioned and native != terrain.native):
			failed = true
			push_error("Real terrain point sequence differs from native at edit " + str(i))
		if i >= 2:
			full_times.append(full_ms)
			local_times.append(local_ms)
			if cavity_mode and cache.stats.full_calls == 0:
				patched_edits += 1
		print("LOCAL_DELAUNAY_TERRAIN edit=", i, " points=", terrain.captured.size(),
			" native_ms=", full_ms, " local_ms=", local_ms, " stats=", cache.stats)
	full_times.sort()
	local_times.sort()
	print("LOCAL_DELAUNAY_TERRAIN_MEDIAN native_ms=", full_times[full_times.size() / 2],
		" local_ms=", local_times[local_times.size() / 2], " patched_edits=", patched_edits,
		" mode=", "cavity" if cavity_mode else "ordered", " conditioned=", conditioned)
	if cavity_mode:
		checks += 1
		if patched_edits == 0:
			failed = true
			push_error("Cavity terrain probe never exercised actual local triangulation")
	scene.free()
	print("LOCAL_DELAUNAY_TERRAIN_%s checks=%d" % ["FAILED" if failed else "OK", checks])
	quit(1 if failed else 0)


func _canonical(indices: PackedInt32Array) -> Array:
	var triangles: Array = []
	for i in range(0, indices.size(), 3):
		var triangle := [indices[i], indices[i + 1], indices[i + 2]]
		triangle.sort()
		triangles.append(str(triangle))
	triangles.sort()
	return triangles


func _reference(points: PackedVector2Array, conditioned: bool) -> PackedInt32Array:
	if not conditioned:
		return Geometry2D.triangulate_delaunay(points)
	var bounds := Rect2(points[0], Vector2.ZERO)
	for p: Vector2 in points:
		bounds = bounds.expand(p)
	var shifted := PackedVector2Array()
	for p: Vector2 in points:
		shifted.append(p - bounds.get_center())
	return Geometry2D.triangulate_delaunay(shifted)


func _overlap_at(points: PackedVector2Array, indices: PackedInt32Array, point: Vector2) -> Dictionary:
	var incident: Array[PackedVector2Array] = []
	for i in range(0, indices.size(), 3):
		var triangle := PackedVector2Array([points[indices[i]], points[indices[i + 1]], points[indices[i + 2]]])
		if triangle.has(point):
			incident.append(triangle)
	var maximum := 0.0
	var pair: Array = []
	for i in range(incident.size()):
		for j in range(i + 1, incident.size()):
			var area := 0.0
			for polygon: PackedVector2Array in Geometry2D.intersect_polygons(incident[i], incident[j]):
				var twice_area := 0.0
				for k in range(polygon.size()):
					twice_area += polygon[k].cross(polygon[(k + 1) % polygon.size()])
				area += absf(twice_area) * 0.5
			if area > maximum:
				maximum = area
				pair = [incident[i], incident[j]]
	return {"point": point, "incident_triangles": incident.size(), "max_overlap_area": maximum, "pair": pair}


func _reduce_overlap(input: PackedVector2Array, point: Vector2) -> void:
	var points := input.duplicate()
	var partitions := 2
	var calls := 0
	while partitions <= points.size() and calls < 600:
		var chunk := ceili(float(points.size()) / partitions)
		var reduced := false
		for start in range(0, points.size(), chunk):
			var candidate := points.slice(0, start)
			candidate.append_array(points.slice(mini(start + chunk, points.size())))
			if candidate.size() < 4 or not candidate.has(point):
				continue
			calls += 1
			var indices := Geometry2D.triangulate_delaunay(candidate)
			if _overlap_at(candidate, indices, point).max_overlap_area > 1.0:
				points = candidate
				partitions = maxi(2, partitions - 1)
				reduced = true
				break
		if not reduced:
			if partitions == points.size():
				break
			partitions = mini(points.size(), partitions * 2)
	print("NATIVE_OVERLAP_REDUCED points=", points.size(), " calls=", calls,
		" detail=", _overlap_at(points, Geometry2D.triangulate_delaunay(points), point))
	print("NATIVE_OVERLAP_POINTS_HEX ", var_to_bytes(points).hex_encode())
