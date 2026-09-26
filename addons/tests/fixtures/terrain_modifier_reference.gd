extends "../../scripts/spline_road/terrain_height_modifier.gd"

# Exhaustive pre-optimization distance search, retained as a parity oracle.
func _nearest_path_info_in_builder_space(builder: Node3D, point_xz: Vector2) -> Dictionary:
	var samples := _sample_centerline_points_in_builder_space(builder, maxf(0.25, distance_sample_step))
	if samples.is_empty():
		return {}

	if samples.size() == 1:
		var p0: Vector2 = samples[0].get("p", Vector2.ZERO)
		return {
			"point": p0,
			"distance": point_xz.distance_to(p0),
			"tangent": Vector2.RIGHT,
			"y": float(samples[0].get("y", 0.0)),
		}

	var best_d := INF
	var best_point := Vector2.ZERO
	var best_tangent := Vector2.RIGHT
	var best_y := 0.0
	for i in range(samples.size() - 1):
		var a: Vector2 = samples[i].get("p", Vector2.ZERO)
		var b: Vector2 = samples[i + 1].get("p", Vector2.ZERO)
		var ay := float(samples[i].get("y", 0.0))
		var by := float(samples[i + 1].get("y", 0.0))
		var ab := b - a
		var len2 := ab.length_squared()
		if len2 < 0.000001:
			continue
		var t := clampf((point_xz - a).dot(ab) / len2, 0.0, 1.0)
		var q := a + ab * t
		var d := point_xz.distance_to(q)
		if d < best_d:
			best_d = d
			best_point = q
			best_tangent = ab.normalized()
			best_y = lerpf(ay, by, t)

	return {
		"point": best_point,
		"distance": best_d,
		"tangent": best_tangent,
		"y": best_y,
	}
