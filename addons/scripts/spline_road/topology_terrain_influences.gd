@tool
extends RefCounted
## Frozen source profiles for the standalone terrain's height/sampling stages.
const BUILDER = preload("./road_terrain_influence_builder.gd")
var sampler := BUILDER.new()
var strips: Array = []
var resolution_points := PackedVector2Array()
var bounds := Rect2()
var has_continuation := false

static func is_influence(path: Node) -> bool:
	return path != null and path.has_method("is_terrain_influence_path") and path.is_terrain_influence_path()

func prepare(terrain: Node3D) -> void:
	strips.clear()
	resolution_points.clear()
	bounds = Rect2()
	has_continuation = false
	for path: Path3D in collect_paths(terrain):
		if path.curve == null or path.curve.point_count < 2:
			continue
		var length := path.curve.get_baked_length()
		if length <= 0.001:
			continue
		var transform_: Transform3D = terrain.global_transform.affine_inverse() * path.global_transform
		var step := maxf(0.1, terrain.path_sample_step)
		var count := maxi(1, int(ceil(length / step)))
		var points := PackedVector3Array()
		var widths := PackedFloat32Array()
		var max_half := 0.0
		var heights := PackedFloat32Array()
		var blend: float = path.get_terrain_influence_flatten_blend()
		var bands: int = path.get_terrain_influence_band_count()
		for i in range(count + 1):
			var distance := length * i / count
			var point := transform_ * path.curve.sample_baked(distance, true)
			var half: float = path.get_terrain_influence_width_at_offset(distance) * 0.5
			points.append(point)
			widths.append(half)
			max_half = maxf(max_half, half)
			heights.append(path.get_terrain_influence_profile_height_at_offset(distance))
			var center := Vector2(point.x, point.z)
			var radius := half + blend
			var rect := Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2)
			bounds = rect if strips.is_empty() and i == 0 else bounds.merge(rect)
			resolution_points.append(center)
			# Cross sections and end caps resolve the authored profile without
			# creating a second influence surface or a road mask.
			var before := transform_ * path.curve.sample_baked(maxf(0, distance-step*0.5), true)
			var after := transform_ * path.curve.sample_baked(minf(length, distance+step*0.5), true)
			var direction := Vector2(after.x-before.x, after.z-before.z).normalized()
			var right := Vector2(-direction.y, direction.x)
			for band in range(1, bands+1):
				var offset := radius * band / bands
				resolution_points.append(center + right * offset)
				resolution_points.append(center - right * offset)
				if i == 0 or i == count:
					for sector in range(12):
						resolution_points.append(center + Vector2.from_angle(TAU * sector / 12.0) * offset)
		var strip := {"points": points, "half_widths": widths, "profile_heights": heights,
			"left_continuation": path.terrain_left_continuation,
			"right_continuation": path.terrain_right_continuation,
			"half_width": path.get_terrain_influence_width()*0.5, "max_half_width": max_half,
			"blend": blend, "strength": path.get_terrain_influence_flatten_strength(),
			"profile_curve": path.get_terrain_influence_profile_curve(),
			"profile_height": path.get_terrain_influence_profile_height(),
			"profile_graph_samples": path.get_terrain_influence_profile_graph_samples()}
		strip.segment_lookup = sampler._build_terrain_influence_segment_lookup(strip)
		if path.curve.closed:
			var polygon := PackedVector2Array()
			var signed_area := 0.0
			for point: Vector3 in points:
				polygon.append(Vector2(point.x, point.z))
			for i in range(polygon.size()):
				signed_area += polygon[i].cross(polygon[(i + 1) % polygon.size()])
			strip.closed_polygon = polygon
			strip.interior_left = signed_area > 0.0
		strips.append(strip)
		has_continuation = has_continuation or path.terrain_left_continuation != 0 or path.terrain_right_continuation != 0

func active() -> bool:
	return not strips.is_empty()

func sample_height(point: Vector2, height: float, road_distance := INF) -> float:
	var local_height := sampler.sample_prepared_height(Vector3(point.x, height, point.y), strips)
	if not has_continuation:
		return local_height
	# Nearest source owns the region, including local-only sources. Extending
	# individual segments independently would incorrectly fill both sides of loops.
	var best_distance := INF
	var best_strip: Dictionary = {}
	var best_index := 0
	var best_t := 0.0
	var best_left := false
	for strip: Dictionary in strips:
		var points: PackedVector3Array = strip.points
		for i in range(points.size() - 1):
			var a := Vector2(points[i].x, points[i].z)
			var b := Vector2(points[i + 1].x, points[i + 1].z)
			var direction := b - a
			if direction.length_squared() < 0.000001:
				continue
			var t := clampf((point - a).dot(direction) / direction.length_squared(), 0.0, 1.0)
			var distance := point.distance_to(a.lerp(b, t))
			if distance < best_distance:
				best_distance = distance
				best_strip = strip
				best_index = i
				best_t = t
				best_left = direction.cross(point - a) >= 0.0
	if best_strip.is_empty():
		return local_height
	if best_strip.has("closed_polygon"):
		# At convex corners, the nearest segment's endpoint has ambiguous side.
		# Classify the entire loop so exterior wedges never become interior fill.
		var inside := Geometry2D.is_point_in_polygon(point, best_strip.closed_polygon)
		best_left = inside == bool(best_strip.interior_left)
	if int(best_strip.get("left_continuation" if best_left else "right_continuation", 0)) == 0:
		return local_height
	var points: PackedVector3Array = best_strip.points
	var widths: PackedFloat32Array = best_strip.half_widths
	var heights: PackedFloat32Array = best_strip.profile_heights
	var half := lerpf(widths[best_index], widths[best_index + 1], best_t)
	var profile_height := lerpf(heights[best_index], heights[best_index + 1], best_t)
	var span := maxf(0.001, half + float(best_strip.blend))
	var peak: float = sampler._terrain_influence_cross_profile(clampf(best_distance / span, 0, 1),
		best_strip.profile_curve, best_strip.profile_graph_samples)
	var target := lerpf(points[best_index].y, points[best_index + 1].y, best_t) + profile_height * peak
	# Fade back to the original terrain at road ownership boundaries.
	var ownership := 1.0
	if is_finite(road_distance):
		ownership = smoothstep(0.0, maxf(1.0, best_strip.blend), road_distance - best_distance)
	return lerpf(local_height, lerpf(height, target, best_strip.strength), ownership)


func collect_paths(terrain: Node3D) -> Array[Path3D]:
	var paths: Array[Path3D] = []
	for np: NodePath in terrain.source_paths + terrain.height_modifiers:
		var node := terrain.get_node_or_null(np)
		if is_influence(node) and not paths.has(node):
			paths.append(node)
	if terrain.auto_find_height_modifiers:
		var pending: Array[Node] = []
		pending.assign(terrain.get_children())
		while not pending.is_empty():
			var node := pending.pop_back()
			if is_influence(node) and not paths.has(node):
				paths.append(node)
			if terrain.search_modifier_children_recursively:
				pending.append_array(node.get_children())
	return paths

func get_signature(terrain: Node3D) -> String:
	var parts: Array = []
	for path: Path3D in collect_paths(terrain):
		parts.append([path.get_instance_id(), path.global_transform,
			path.get_terrain_influence_width_profile_signature(), path.get_terrain_influence_profile_signature(),
			path.influence_blend, path.influence_strength, path.influence_band_count])
		if path.curve != null:
			parts.append(path.curve.closed)
			for i in range(path.curve.point_count):
				parts.append([path.curve.get_point_position(i), path.curve.get_point_in(i),
					path.curve.get_point_out(i), path.curve.get_point_tilt(i)])
	return str(parts)
