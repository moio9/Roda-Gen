extends "./check_lateral_merge_angles.gd"

func _run() -> void:
	var scene := load("res://addons/scenes/examples/lateral_join_playground.tscn").instantiate() as Node3D
	var road := scene.get_node("Joined")
	var main := road.get_node("Main")
	var extra := road.get_node("ExtraLane")
	main.curve = Curve3D.new()
	main.curve.bake_interval = 2.0
	main.curve.add_point(Vector3(0,0,-40))
	main.curve.add_point(Vector3(0,0,40))
	extra.curve = Curve3D.new()
	extra.curve.bake_interval = 2.0
	for p in [Vector3(0.6671448,0,-24.495342),Vector3(5.511175,0,21.091831),Vector3(4.4875717,0,26.540833),Vector3(-2.3533459,0,37.623596)]:
		extra.curve.add_point(p)
	main.intersection_override_enabled = true
	extra.intersection_override_enabled = true
	extra.weld_endpoint_snap_distance = 4.5
	main.lateral_join_group = "lanes"
	extra.lateral_join_group = "lanes"
	extra.point_lanes_left = PackedInt32Array([0,0,0,0])
	extra.point_lanes_right = PackedInt32Array([1,1,1,1])
	extra.point_lane_widths = PackedFloat32Array([3,3,3,3])
	extra.lateral_join_start_transition_length = 194.0
	extra.lateral_join_end_transition_length = 200.0
	road.threaded_generation_enabled = false
	road.junction_geometry_mode = 1
	root.size = Vector2i(900,1100)
	root.add_child(scene)
	var camera := scene.get_node("Camera") as Camera3D
	camera.set_process(false)
	camera.set_process_unhandled_input(false)
	camera.position = Vector3(23,105,2)
	camera.fov = 50
	camera.look_at(Vector3(20,0,0))
	var expected: Dictionary = {}
	for mirrored in [false,true]:
		var side := -1.0 if mirrored else 1.0
		extra.curve.set_point_position(0,Vector3(0.6671448*side,0,-24.495342))
		extra.curve.set_point_position(1,Vector3(5.511175*side,0,21.091831))
		extra.point_lanes_left = PackedInt32Array([1,1,1,1] if mirrored else [0,0,0,0])
		extra.point_lanes_right = PackedInt32Array([0,0,0,0] if mirrored else [1,1,1,1])
		for shape in ["junction","parallel","junction","parallel"]:
			extra.curve.set_point_position(2,Vector3((3.2 if shape == "parallel" else 4.4875717)*side,0,26.540833))
			extra.curve.set_point_position(3,Vector3((3.2 if shape == "parallel" else -2.3533459)*side,0,37.623596))
			var authored := var_to_bytes([extra.curve.get_point_position(0),extra.curve.get_point_position(1),extra.curve.get_point_position(2),extra.curve.get_point_position(3),extra.point_lane_widths,road.junction_corner_radius])
			road.regenerate()
			var stats: Dictionary = road.get_source_rebuild_stats()
			_check(stats.lateral_joins.length > 35.0,"First lateral contact survives edits at the other end")
			if shape == "junction":
				_check(stats.contour_junctions.size() == 1 and stats.contour_junctions[0].ok,"Returning branch creates a contour junction")
				if stats.contour_junctions.size() == 1 and stats.contour_junctions[0].ok:
					_check(stats.contour_junctions[0].arms == 3,"Host continuation is retained as the third arm")
					_check(stats.contour_junctions[0].retreat < 15.0,"Junction stays local instead of consuming the other merge")
				_check(stats.lateral_joins.transitions.size() == 1,"Junction owns only the returning end")
			else:
				_check(stats.contour_junctions.is_empty(),"Moving return parallel restores lateral priority")
				_check(stats.lateral_joins.transitions.size() == 2,"Both ends regain independent lateral transitions")
			var key: String = shape+str(mirrored)
			var digest := _digest(road)
			if expected.has(key):
				_check(expected[key] == digest,"Repeated shape edits restore the same output")
			else:
				expected[key] = digest
				var mesh: Mesh = road.get_node("GeneratedSplineRoadWelded").mesh
				var asphalt := _polygons(mesh,road.road_material_override)
				var sidewalk := _polygons(mesh,road.sidewalk_material_override)
				_check(_overlap_area(asphalt,asphalt,true)<0.02,"Mixed layout has no duplicate asphalt: "+key)
				_check(_overlap_area(asphalt,sidewalk)<0.02,"Mixed layout has no sidewalk over asphalt: "+key+" area="+str(_overlap_area(asphalt,sidewalk)))
				if "--screenshots" in OS.get_cmdline_user_args() and not mirrored:
					await process_frame
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("/tmp/roda-return-"+shape+".png")
			road.regenerate()
			_check(digest == _digest(road),"Mixed layout warm-cache parity")
			_check(authored == var_to_bytes([extra.curve.get_point_position(0),extra.curve.get_point_position(1),extra.curve.get_point_position(2),extra.curve.get_point_position(3),extra.point_lane_widths,road.junction_corner_radius]),"Regeneration leaves authored points, widths and radius intact")
			print("RETURN EDIT ",key," contacts=",stats.lateral_joins.contacts," transitions=",stats.lateral_joins.transitions.size()," junctions=",stats.contour_junctions)
	road.threaded_generation_enabled = true
	road.regenerate()
	while road.is_road_generation_pending():
		await process_frame
	_check(_digest(road) == expected["paralleltrue"],"Edited left-side return has threaded parity")
	scene.free()
	print("LATERAL RETURN EDITS ","OK" if failures == 0 else "FAILED"," failures=",failures)
	quit(0 if failures == 0 else 1)
