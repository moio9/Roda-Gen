extends SceneTree


func _initialize() -> void:
	var profile_script := load("res://addons/scripts/spline_road/spline_path_profile.gd")
	var road_script := load("res://addons/scripts/spline_road/road_network_creator.gd")
	var terrain_script := load("res://addons/scripts/spline_road/terrain_topology_builder.gd")
	var prop_script := load("res://addons/scripts/spline_road/spline_prop_array.gd")
	var deformer_script := load("res://addons/scripts/spline_road/spline_mesh_deformer.gd")
	if profile_script == null or road_script == null or terrain_script == null or prop_script == null or deformer_script == null:
		push_error("Lane profile scripts did not parse")
		quit(1)
		return

	var road: Node3D = road_script.new()
	var profile: Path3D = profile_script.new()
	var terrain: Node3D = terrain_script.new()
	if not bool(terrain.call("_road_data_has_directional_lane_profile", {
		"rows": [{"directional_lane_profile": true}],
	})):
		push_error("Terrain did not detect directional lane profiles for automatic edge collars")
		terrain.free()
		quit(1)
		return
	terrain.free()
	profile.name = "LaneProfile"
	var path_curve := Curve3D.new()
	path_curve.bake_interval = 0.25
	path_curve.add_point(Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Vector3(0.0, 0.0, 20.0))
	path_curve.add_point(Vector3(0.0, 0.0, 50.0), Vector3(0.0, 0.0, -20.0), Vector3(20.0, 0.0, 0.0))
	path_curve.add_point(Vector3(50.0, 0.0, 50.0), Vector3(-20.0, 0.0, 0.0), Vector3.ZERO)
	profile.curve = path_curve
	road.add_child(profile)
	profile.point_widths = PackedFloat32Array([10.0, 12.0, 14.0])
	profile.call("_sync_point_widths")
	var legacy_extents: Vector2 = profile.get_lane_extents_at_offset(0.0)
	if not legacy_extents.is_equal_approx(Vector2(5.0, 5.0)):
		push_error("Legacy centered width compatibility failed: %s" % legacy_extents)
		quit(1)
		return
	profile.lane_profile_enabled = true
	var applied_signature_before_edit: String = profile.get_width_profile_signature()
	var dependent_signature_before_edit: String = profile.get_dependent_width_profile_signature()
	var seeded_offsets: PackedFloat32Array = profile.call("_control_point_offsets")
	for i in range(seeded_offsets.size()):
		var seeded_extents: Vector2 = profile.get_lane_extents_at_offset(seeded_offsets[i])
		var expected_width := float(profile.point_widths[i])
		if not is_equal_approx(seeded_extents.x + seeded_extents.y, expected_width):
			push_error("Enabling lanes changed legacy width at point %d: %s vs %.3f" % [i, seeded_extents, expected_width])
			quit(1)
			return
	profile.point_lanes_left = PackedInt32Array([1, 1, 1])
	profile.point_lanes_right = PackedInt32Array([1, 2, 2])
	profile.point_lane_widths = PackedFloat32Array([3.5, 3.5, 3.5])
	profile.call("_sync_lane_profiles")
	var deferred_signature: String = profile.get_width_profile_signature()
	if deferred_signature != applied_signature_before_edit:
		push_error("Lane edits escaped the deferred heavy-generation signature")
		quit(1)
		return
	profile.apply_lane_changes()
	if profile.get_width_profile_signature() == applied_signature_before_edit:
		push_error("Apply Lane Changes did not invalidate the road generator")
		quit(1)
		return
	if profile.get_dependent_width_profile_signature() != dependent_signature_before_edit:
		push_error("Fast lane apply unexpectedly invalidated heavy dependents")
		quit(1)
		return
	profile.rebuild_lane_dependents()
	if profile.get_dependent_width_profile_signature() == dependent_signature_before_edit:
		push_error("Slow dependent rebuild did not invalidate edge consumers")
		quit(1)
		return
	road.set("threaded_generation_enabled", false)
	road.set("debug_generation_logs", false)
	road.set("sample_step", 4.0)
	var source_paths: Array[NodePath] = [NodePath("LaneProfile")]
	road.set("source_paths", source_paths)
	root.add_child(road)
	await process_frame

	var offsets: PackedFloat32Array = profile.call("_control_point_offsets")
	profile.set_point_lane_transition_length_at_index(1, 10.0)
	var before_transition: Vector2 = profile.get_lane_extents_at_offset(maxf(offsets[0], offsets[1] - 15.0))
	if not before_transition.is_equal_approx(Vector2(3.5, 3.5)):
		push_error("Transition length did not preserve the incoming layout: %s" % before_transition)
		quit(1)
		return
	profile.set_point_lane_transition_length_at_index(1, 0.0)
	var start: Vector2 = profile.get_lane_extents_at_offset(offsets[0])
	var middle: Vector2 = profile.get_lane_extents_at_offset(offsets[1])
	var quarter: Vector2 = profile.get_lane_extents_at_offset(lerpf(offsets[0], offsets[1], 0.25))
	if not start.is_equal_approx(Vector2(3.5, 3.5)):
		push_error("Unexpected start extents: %s" % start)
		quit(1)
		return
	if not middle.is_equal_approx(Vector2(3.5, 7.0)):
		push_error("Unexpected middle extents: %s" % middle)
		quit(1)
		return
	var prop: Node3D = prop_script.new()
	var deformer: Node3D = deformer_script.new()
	var prop_left := float(prop.call("_compute_side_offset", profile, offsets[1], path_curve.get_baked_length(), -1))
	var prop_right := float(prop.call("_compute_side_offset", profile, offsets[1], path_curve.get_baked_length(), 1))
	var deformer_left := float(deformer.call("_compute_side_offset", profile, offsets[1], -1))
	var deformer_right := float(deformer.call("_compute_side_offset", profile, offsets[1], 1))
	if not is_equal_approx(prop_left, -3.5) or not is_equal_approx(prop_right, 7.0):
		push_error("Prop edge placement ignored asymmetric lanes: left=%s right=%s" % [prop_left, prop_right])
		quit(1)
		return
	if not is_equal_approx(deformer_left, -3.5) or not is_equal_approx(deformer_right, 7.0):
		push_error("Curved mesh placement ignored asymmetric lanes: left=%s right=%s" % [deformer_left, deformer_right])
		quit(1)
		return
	prop.free()
	deformer.free()
	if quarter.y <= start.y or quarter.y >= middle.y:
		push_error("Bezier transition did not interpolate the entering lane: %s" % quarter)
		quit(1)
		return
	var road_middle: Vector2 = road.call("_resolve_path_lane_extents", profile, offsets[1], path_curve.get_baked_length())
	if not road_middle.is_equal_approx(middle):
		push_error("Road generator did not consume directional lane extents: %s" % road_middle)
		quit(1)
		return
	var generated := road.get_node_or_null("GeneratedSplineRoadWelded") as MeshInstance3D
	if generated == null or generated.mesh == null or generated.mesh.get_surface_count() <= 0:
		push_error("Road generator did not create lane geometry")
		quit(1)
		return

	road.road_orientation_mode = 2
	road.road_bank_max_degrees = 12.0
	road.road_bank_strength = 2.0
	road.road_bank_sample_distance = 12.0
	var handle_basis: Basis = profile.call("_compute_handle_basis", 1, 3)
	var road_frame: Dictionary = road.get_path_surface_frame(profile, offsets[1])
	var expected_right: Vector3 = road_frame.get("right", Vector3.ZERO)
	var expected_up: Vector3 = road_frame.get("up", Vector3.ZERO)
	if handle_basis.x.normalized().dot(expected_right.normalized()) < 0.9999:
		push_error("Handle right axis does not follow the road frame")
		quit(1)
		return
	if handle_basis.y.normalized().dot(expected_up.normalized()) < 0.9999:
		push_error("Handle up axis does not follow the road frame")
		quit(1)
		return

	var second_lane_material := StandardMaterial3D.new()
	var right_lane_materials: Array[Material] = [null, second_lane_material]
	road.set("right_lane_material_overrides", right_lane_materials)
	var lane_overlay: ArrayMesh = road.call("_build_lane_material_overlay_mesh")
	if lane_overlay == null or lane_overlay.get_surface_count() != 1:
		push_error("Second-lane material did not create one overlay surface")
		quit(1)
		return
	if lane_overlay.surface_get_material(0) != second_lane_material:
		push_error("Second-lane overlay lost its assigned material")
		quit(1)
		return
	var overlay_arrays := lane_overlay.surface_get_arrays(0)
	var overlay_vertices: PackedVector3Array = overlay_arrays[Mesh.ARRAY_VERTEX]
	if overlay_vertices.is_empty():
		push_error("Second-lane material overlay has no geometry")
		quit(1)
		return

	print("LANE_PROFILE_OK legacy=%s before_transition=%s start=%s quarter=%s middle=%s bank_up=%s" % [legacy_extents, before_transition, start, quarter, middle, handle_basis.y])
	road.free()
	quit()
