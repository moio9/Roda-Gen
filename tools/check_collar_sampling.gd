extends "./check_topology_source_cache.gd"

class ReferenceTerrain extends TOPOLOGY:
	var vertex_calls := 0
	var quad_calls := 0
	func _point_to_vertex(p: Vector2, segments: Array) -> Vector3:
		vertex_calls += 1
		return super._point_to_vertex(p, segments)
	func _append_topology_quad(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, d: Vector2, segments: Array, polygons: Array) -> int:
		quad_calls += 1
		return super._append_topology_quad(st, a, b, c, d, segments, polygons)


func _run() -> void:
	var scene := Node3D.new()
	var road := ROAD.new()
	road.name = "Road"
	road.threaded_generation_enabled = false
	road.debug_generation_logs = false
	road.generate_in_editor = false
	var path := _path("Path", Vector3(-20, 0, 0))
	road.add_child(path)
	scene.add_child(road)
	var native := TOPOLOGY.new()
	native.incremental_generation_enabled = true
	var reference := ReferenceTerrain.new()
	for terrain: Node in [native, reference]:
		terrain.generate_in_editor = false
		terrain.threaded_triangulation_enabled = false
		terrain.road_network_source = NodePath("../Road")
		terrain.source_paths.assign([NodePath("../Road/Path")])
		terrain.path_sample_step = 4
		terrain.adaptive_path_sampling = false
		terrain.bounds_mode = 1
		terrain.manual_center_xz = Vector2(0, 40)
		terrain.manual_size_xz = Vector2(160, 120)
		terrain.near_road_width = 12
		terrain.near_road_step = 6
		terrain.far_grid_step = 16
		terrain.generate_collision = true
		scene.add_child(terrain)
	root.add_child(scene)
	for edit in range(8):
		if edit == 1:
			path.curve.set_point_position(1, path.curve.get_point_position(1) + Vector3(3, 2, 1))
		elif edit == 2:
			path.curve.set_point_tilt(1, 0.3)
		elif edit == 3:
			native.noise_seed += 1
			reference.noise_seed = native.noise_seed
		elif edit == 4:
			native.road_edge_collar_lateral_step = 0.2
			reference.road_edge_collar_lateral_step = 0.2
		elif edit == 5:
			native.road_edge_collar_max_width = 4.0
			reference.road_edge_collar_max_width = 4.0
		elif edit == 6:
			native.invert_faces = not native.invert_faces
			reference.invert_faces = native.invert_faces
		elif edit == 7:
			native.road_edge_height_snap_distance += 0.5
			reference.road_edge_height_snap_distance = native.road_edge_height_snap_distance
		_build(native)
		_build(reference)
		_check(_terrain_geometry(native) == _terrain_geometry(reference), "memo/legacy exact mesh attributes and collision, edit " + str(edit))
		var stats: Dictionary = native.get_source_rebuild_stats().collar_samples
		_check(stats.enabled and stats.reused > stats.rebuilt and stats.entries <= 16384, "native collar reuses bounded exact samples")
		_check(not reference.get_source_rebuild_stats().collar_samples.enabled and reference.quad_calls > 0 and reference.vertex_calls > 0, "subclass retains original quad and height dispatch")
		print("COLLAR_SAMPLES edit=", edit, " ", stats)
		_build(native)
		_check(_terrain_geometry(native) == _terrain_geometry(reference), "warm collar replay matches legacy mesh/collision " + str(edit))
		var warm: Dictionary = native.get_source_rebuild_stats()
		_check(warm.collar_groups.triangles_reused > 0 and warm.collar_groups.triangles_rebuilt == 0
			and warm.collar_samples.rebuilt == 0, "warm native collar groups skip quad construction and sampling")
	var modifier := DynamicModifier.new()
	var reference_modifier := DynamicModifier.new()
	native.add_child(modifier)
	reference.add_child(reference_modifier)
	_build(native)
	_build(reference)
	_check(not native.get_source_rebuild_stats().collar_samples.enabled, "arbitrary height modifiers disable memo")
	_check(modifier.calls == reference_modifier.calls and modifier.calls > 0, "modifier callback count matches legacy path exactly")
	_check(_terrain_geometry(native) == _terrain_geometry(reference), "modifier output matches legacy mesh/collision")
	modifier.free()
	native._active_height_modifiers.clear()
	native.noise_enabled = false
	var samples: Dictionary = {}
	for i in range(16390):
		native._collar_vertex(Vector2(i, 0), [], samples)
	_check(samples.size() == 16384, "collar memo cannot exceed its actual capacity")
	_check(native._collar_vertex(Vector2(16389, 0), [], samples) == Vector3(16389, native.base_height, 0), "samples beyond capacity still evaluate the current height")
	var zero_samples: Dictionary = {}
	native._collar_vertex(Vector2.ZERO, [], zero_samples)
	var negative_zero := Vector2(-0.0, -0.0)
	_check(var_to_bytes(native._collar_vertex(negative_zero, [], zero_samples)) == var_to_bytes(native._point_to_vertex(negative_zero, [])), "memo hits preserve original signed-zero coordinates")
	scene.free()
	print("COLLAR_SAMPLING_%s checks=%d" % ["FAILED" if _failed else "OK", _checks])
	quit(1 if _failed else 0)
