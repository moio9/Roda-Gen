@tool
extends RefCounted
## Value-only preprocessing: returned indices always address the ORIGINAL points.
## Centering can improve float32 conditioning, but is not a robust-predicate
## solver and can change diagonals. Callers must explicitly opt in.


static func prepare_points(points: PackedVector2Array, centered: bool) -> PackedVector2Array:
	if not centered or points.size() < 3:
		return points
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		if not point.is_finite():
			return points
		bounds = bounds.expand(point)
	var origin := bounds.get_center()
	if not origin.is_finite():
		return points
	var shifted := PackedVector2Array()
	var originals: Dictionary = {}
	for point: Vector2 in points:
		var value := point - origin
		# Translation in float32 must not merge originally distinct samples.
		if not value.is_finite() or (originals.has(value) and originals[value] != point):
			return points
		originals[value] = point
		shifted.append(value)
	return shifted


static func triangulate(points: PackedVector2Array, centered := false) -> PackedInt32Array:
	return Geometry2D.triangulate_delaunay(prepare_points(points, centered))
