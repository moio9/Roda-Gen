extends "./check_lateral_joins.gd"

# Regression for the authored six-degree branch, including its intersection
# overrides and a requested transition longer than the available main road.
func _run() -> void:
	var road := ROAD.new()
	road.threaded_generation_enabled = false
	road.incremental_generation_enabled = true
	road.debug_generation_logs = false
	road.adaptive_sampling_enabled = false
	road.sample_step = 1.25
	road.invert_faces = true
	road.markings_enabled = true
	road.junction_geometry_mode = 1
	road.endpoint_snap_distance = 0.1
	road.allow_endpoint_to_midpath = false
	road.road_material_override = StandardMaterial3D.new()
	road.shoulder_material_override = StandardMaterial3D.new()
	road.sidewalk_material_override = StandardMaterial3D.new()
	var main := _path("Main",0,-40,40,1)
	var extra := _path("Extra",0,-22,22,0)
	extra.curve.set_point_position(0,Vector3(0.6671448,0,-24.495342))
	extra.curve.set_point_position(1,Vector3(5.511175,0,21.091831))
	for path in [main,extra]:
		path.curve.bake_interval = 2.0
		path.intersection_override_enabled = true
		path.shoulder_left_width = 0.35
		path.shoulder_right_width = 0.35
		path.sidewalk_left_width = 1.2
		path.sidewalk_right_width = 1.2
		path.outer_wall_height = 0.0
	extra.weld_endpoint_snap_distance = 4.5
	extra.lateral_join_start_transition_length = 194.0
	extra.lateral_join_end_transition_length = 200.0
	var authored := var_to_bytes([extra.curve.get_point_position(0),extra.curve.get_point_position(1),extra.point_lane_widths,extra.weld_endpoint_snap_distance])
	road.add_child(main)
	road.add_child(extra)
	root.add_child(road)
	_check_merge(road)
	var mesh: Mesh = road.get_node("GeneratedSplineRoadWelded").mesh
	var area := _area(mesh,road.road_material_override)
	var digest := _digest(road)
	road.regenerate()
	_check(digest == _digest(road),"Angled merge warm-cache parity")
	road.threaded_generation_enabled = true
	road.regenerate()
	while road.is_road_generation_pending():
		await process_frame
	_check(digest == _digest(road),"Angled merge threaded parity")
	road.threaded_generation_enabled = false
	road.move_child(extra,0)
	road.regenerate()
	_check_merge(road)
	_check(absf(_area(road.get_node("GeneratedSplineRoadWelded").mesh,road.road_material_override)-area)<0.03,"Angled asphalt union is independent of source order")
	_check(authored == var_to_bytes([extra.curve.get_point_position(0),extra.curve.get_point_position(1),extra.point_lane_widths,extra.weld_endpoint_snap_distance]),"Authored angle, lane widths and intersection overrides preserved")
	# Reverse the authored travel direction while retaining the same footprint.
	var start := extra.curve.get_point_position(0)
	extra.curve.set_point_position(0,extra.curve.get_point_position(1))
	extra.curve.set_point_position(1,start)
	extra.point_lanes_left = PackedInt32Array([1,1])
	extra.point_lanes_right = PackedInt32Array([0,0])
	road.regenerate()
	_check_merge(road)
	_check(absf(_area(road.get_node("GeneratedSplineRoadWelded").mesh,road.road_material_override)-area)<0.03,"Reversed spline direction preserves the angled asphalt union")
	extra.point_lanes_left = PackedInt32Array([0,0])
	extra.point_lanes_right = PackedInt32Array([1,1])
	# A pair without a valid edge contact must not silently bypass overlap limits.
	extra.curve.set_point_position(0,Vector3(1,0,-22))
	extra.curve.set_point_position(1,Vector3(1,0,22))
	extra.intersection_override_enabled = false
	main.intersection_override_enabled = false
	extra.lateral_join_start_transition_length = 0.0
	extra.lateral_join_end_transition_length = 0.0
	road.regenerate()
	_check(road.get_source_rebuild_stats().lateral_joins.contacts == 0,"Isolated deep parallel overlap still obeys max-overlap setting")
	road.free()
	print("LATERAL MERGE ANGLES ","OK" if failures == 0 else "FAILED"," failures=",failures)
	quit(0 if failures == 0 else 1)

func _check_merge(road: Node) -> void:
	var stats: Dictionary = road.get_source_rebuild_stats()
	_check(stats.contour_junctions.is_empty(),"Shallow grouped merge is not also welded as a classic junction")
	_check(stats.lateral_joins.length > 35.0,"Merge covers the deep overlap and entry")
	_check(stats.lateral_joins.transitions.size() == 1,"Only the contacting endpoint receives a smooth extension")
	if stats.lateral_joins.transitions.size() == 1:
		_check(stats.lateral_joins.transitions[0].limited,"Entry length is capped by the host")
	var mesh: Mesh = road.get_node("GeneratedSplineRoadWelded").mesh
	var asphalt := _polygons(mesh,road.road_material_override)
	var sidewalks := _polygons(mesh,road.sidewalk_material_override)
	var shoulders := _polygons(mesh,road.shoulder_material_override)
	_check(_overlap_area(asphalt,asphalt,true) < 0.01,"No duplicate coplanar asphalt at the angled overlap")
	_check(_overlap_area(asphalt,sidewalks) < 0.01,"No sidewalks intrude into either lane")
	_check(_overlap_area(asphalt,shoulders) < 0.01,"No shoulders intrude into either lane")
	_check(_overlap_area(sidewalks,sidewalks,true) < 0.01,"No duplicate sidewalks at the separating branch")
	_check(_covers(mesh,road.sidewalk_material_override,Vector2(3.9,-35)),"Continuous exterior sidewalk follows the generated entry")
	_check(_covers(mesh,road.sidewalk_material_override,Vector2(-4,-10)),"Opposite exterior sidewalk preserved")
	_check(not _covers(mesh,road.sidewalk_material_override,Vector2(4.4,8)),"Branch sidewalk is cut at the real angled asphalt edge")

func _polygons(mesh: Mesh, material: Material) -> Array:
	var result: Array = []
	for triangle: PackedVector3Array in _triangles(mesh,material):
		var points := PackedVector2Array()
		for p in triangle:
			points.append(Vector2(p.x,p.z))
		if _polygon_area(points) > 0.000001:
			var bounds := Rect2(points[0],Vector2.ZERO).expand(points[1]).expand(points[2])
			result.append({"points":points,"bounds":bounds})
	return result

func _polygon_area(points: PackedVector2Array) -> float:
	var result := 0.0
	for i in range(points.size()):
		result += points[i].cross(points[(i+1)%points.size()])
	return absf(result)*0.5

func _overlap_area(a: Array, b: Array, self_test := false) -> float:
	var result := 0.0
	for i in range(a.size()):
		for j in range(i+1 if self_test else 0,b.size()):
			if not a[i].bounds.intersects(b[j].bounds):
				continue
			for polygon: PackedVector2Array in Geometry2D.intersect_polygons(a[i].points,b[j].points):
				result += _polygon_area(polygon)
	return result
