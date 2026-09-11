extends SceneTree
## Reproduces a known native reference defect, not a successful local-cache gate.
## Exact float32 input is stored as a Variant byte sequence, not rounded text.

const FIXTURE := "res://tools/fixtures/native_delaunay_overlap.json"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var points: PackedVector2Array = bytes_to_var(String(fixture.points_variant_hex).hex_decode())
	var indices := Geometry2D.triangulate_delaunay(points)
	var overlap := _maximum_overlap(points, indices)
	print("NATIVE_OVERLAP_REPRO points=", points, " indices=", indices, " max_area=", overlap,
		" triangles=", indices.size() / 3, " planar_max=", 2 * points.size() - 5)
	var reproduced := points.size() == 7 and overlap > 60.0 and indices.size() / 3 > 2 * points.size() - 5
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	for variant in ["translated", "normalized", "scaled"]:
		var conditioned := PackedVector2Array()
		for point: Vector2 in points:
			var value: Vector2 = point - bounds.get_center() if variant != "scaled" else point
			if variant != "translated":
				value /= maxf(bounds.size.x, bounds.size.y)
			conditioned.append(value)
		var candidate := Geometry2D.triangulate_delaunay(conditioned)
		print("NATIVE_OVERLAP_CONDITIONING variant=", variant, " triangles=", candidate.size() / 3,
			" world_overlap=", _maximum_overlap(points, candidate))
	if not reproduced:
		push_error("Recorded native overlap did not reproduce; re-evaluate the baseline on this engine build")
	print("NATIVE_OVERLAP_%s" % ["REPRODUCED" if reproduced else "NOT_REPRODUCED"])
	quit(0 if reproduced else 1)


func _maximum_overlap(points: PackedVector2Array, indices: PackedInt32Array) -> float:
	var triangles: Array[PackedVector2Array] = []
	for i in range(0, indices.size(), 3):
		triangles.append(PackedVector2Array([points[indices[i]], points[indices[i + 1]], points[indices[i + 2]]]))
	var maximum := 0.0
	for i in range(triangles.size()):
		for j in range(i + 1, triangles.size()):
			var area := 0.0
			for polygon: PackedVector2Array in Geometry2D.intersect_polygons(triangles[i], triangles[j]):
				var twice_area := 0.0
				for k in range(polygon.size()):
					twice_area += polygon[k].cross(polygon[(k + 1) % polygon.size()])
				area += absf(twice_area) * 0.5
			maximum = maxf(maximum, area)
	return maximum
