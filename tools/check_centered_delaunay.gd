extends SceneTree

const GEOMETRY = preload("../addons/scripts/spline_road/delaunay_geometry.gd")
const TERRAIN = preload("../addons/scripts/spline_road/terrain_topology_builder.gd")
var checks := 0
var failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/native_delaunay_overlap.json"))
	var points: PackedVector2Array = bytes_to_var(String(fixture.points_variant_hex).hex_decode())
	var before := var_to_bytes(points)
	var legacy := GEOMETRY.triangulate(points)
	_check(legacy == Geometry2D.triangulate_delaunay(points), "default preserves exact native indices")
	var prepared := GEOMETRY.prepare_points(points, true)
	_check(prepared != points and prepared.size() == points.size(), "conditioning changes only calculation coordinates")
	var centered := GEOMETRY.triangulate(points, true)
	_check(var_to_bytes(points) == before, "original vertex positions are not mutated")
	_check(centered == Geometry2D.triangulate_delaunay(prepared), "indices address original point order")
	_check(_overlap(points, legacy) > 60.0, "fixture reproduces original overlapping triangles")
	_check(_overlap(points, centered) < 0.0001, "centering removes overlap in original geometry coordinates")
	_check(centered.size() == 27, "seven-point fixture has nine non-overlapping triangles")
	var extreme := PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2(1e15, 1e15)])
	_check(GEOMETRY.prepare_points(extreme, true) == extreme, "centering cannot collapse distinct source points")
	_check(GEOMETRY.prepare_points(PackedVector2Array(), true).is_empty(), "empty input")
	var repeated := PackedVector2Array([Vector2(1, 2), Vector2(1, 2), Vector2(3, 4), Vector2(5, 1)])
	_check(GEOMETRY.prepare_points(repeated, true).size() == repeated.size(), "existing duplicates do not renumber input")
	var worker := Thread.new()
	_check(worker.start(TERRAIN._triangulate_points_thread.bind(points.duplicate(), true)) == OK, "real worker starts")
	var result: PackedInt32Array = worker.wait_to_finish()
	_check(result == centered, "worker uses the captured centering mode")
	var terrain := TERRAIN.new()
	_check(not terrain.centered_triangulation_enabled, "existing scenes keep centering disabled by default")
	terrain.centered_triangulation_enabled = true
	var scene := PackedScene.new()
	_check(scene.pack(terrain) == OK, "centering setting can be serialized")
	var restored := scene.instantiate()
	_check(restored.centered_triangulation_enabled, "centering setting survives scene reload")
	restored.free()
	terrain.free()
	print("CENTERED_DELAUNAY_%s checks=%d" % ["FAILED" if failed else "OK", checks])
	quit(1 if failed else 0)


func _overlap(points: PackedVector2Array, indices: PackedInt32Array) -> float:
	var result := 0.0
	for i in range(0, indices.size(), 3):
		var a := PackedVector2Array([points[indices[i]], points[indices[i + 1]], points[indices[i + 2]]])
		for j in range(i + 3, indices.size(), 3):
			var b := PackedVector2Array([points[indices[j]], points[indices[j + 1]], points[indices[j + 2]]])
			for polygon: PackedVector2Array in Geometry2D.intersect_polygons(a, b):
				var twice_area := 0.0
				for k in range(polygon.size()):
					twice_area += polygon[k].cross(polygon[(k + 1) % polygon.size()])
				result = maxf(result, absf(twice_area) * 0.5)
	return result


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(label)
