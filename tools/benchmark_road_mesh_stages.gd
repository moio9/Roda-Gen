extends "./check_road_source_cache.gd"
## Run in isolation. Compare native normal/surface work after cached source rows.
const TRACE = preload("./fixtures/road_mesh_stage_profile.gd")


func _run() -> void:
	var expected: Array = []
	for incremental in [false, true]:
		var road := ROAD.new()
		road.name = "StageProfileRoad"
		road.threaded_generation_enabled = false
		road.debug_generation_logs = false
		road.adaptive_sampling_enabled = false
		road.allow_endpoint_to_midpath = false
		road.incremental_generation_enabled = incremental
		road.output_mode = 1
		road.output_chunk_size = 64
		road.output_generate_collision = true
		road.sample_step = 0.5
		road.markings_enabled = "--markings" in OS.get_cmdline_user_args()
		road._marking_builder.cache_enabled = not "--full-markings" in OS.get_cmdline_user_args()
		if "--lanes" in OS.get_cmdline_user_args():
			var lane_material := StandardMaterial3D.new()
			road.left_lane_material_overrides.assign([lane_material])
			road.right_lane_material_overrides.assign([lane_material])
		road._lane_overlay_cache.cache_enabled = not "--full-lanes" in OS.get_cmdline_user_args()
		var trace := TRACE.new()
		trace.force_full_normals = "--full-normals" in OS.get_cmdline_user_args()
		trace.direct_output_enabled = not "--full-mesh-upload" in OS.get_cmdline_user_args()
		road._mesh_builder = trace
		road._path_sampler.assembly_cache_enabled = not "--full-source-assembly" in OS.get_cmdline_user_args()
		road._runtime_output.incremental_partition_enabled = not "--full-partition" in OS.get_cmdline_user_args()
		for index in range(10):
			road.add_child(_path("Route" + str(index), 9, Vector3(index * 100, 0, 0)))
		root.add_child(road)
		road.regenerate()
		var path: Path3D = road.get_node("Route0")
		var original := path.curve.get_point_position(5)
		var totals: Array[float] = []
		var sources: Array[float] = []
		var sampling: Array[float] = []
		var assembly: Array[float] = []
		var meshes: Array[float] = []
		var normals: Array[float] = []
		var partitions: Array[float] = []
		var publications: Array[float] = []
		var markings: Array[float] = []
		var lanes: Array[float] = []
		for edit in range(5):
			path.curve.set_point_position(5, original + Vector3(0.2 * (edit + 1), 0.03 * (edit + 1), 0))
			trace.reset_times()
			var started := Time.get_ticks_usec()
			road.regenerate()
			totals.append(float(Time.get_ticks_usec() - started) / 1000.0)
			var stats: Dictionary = road.get_source_rebuild_stats()
			sources.append(stats.source_ms)
			sampling.append(stats.sampling_ms)
			assembly.append(stats.assembly_ms)
			meshes.append(trace.mesh_ms)
			normals.append(trace.normal_ms)
			partitions.append(road.get_output_rebuild_stats().partition_ms)
			publications.append(road.get_output_rebuild_stats().publish_ms)
			if road._has_lane_material_overrides():
				var lane_stats: Dictionary = road.get_lane_overlay_stats()
				lanes.append(lane_stats.build_ms)
				if incremental and road._lane_overlay_cache.cache_enabled:
					_check(lane_stats.rows_reused > lane_stats.rows_rebuilt and lane_stats.rows_rebuilt > 0,
						"local edit retains most lane-overlay row construction")
				print("ROAD_LANE_OVERLAY_SAMPLE ", lane_stats)
			if road.markings_enabled:
				var paint: Dictionary = road.get_marking_stats()
				markings.append(paint.build_ms)
				_check(paint.center_triangles + paint.line_triangles > 100,
					"benchmark includes nontrivial actual road paint")
				if incremental and road._marking_builder.cache_enabled:
					_check(paint.blocks_reused > paint.blocks_rebuilt and paint.blocks_rebuilt > 0,
						"local edit retains most paint blocks")
				print("ROAD_MARKING_SAMPLE ", paint)
			var geometry := _chunk_geometry(road)
			_check(geometry.size() > 20, "benchmark observes actual chunk meshes and collisions")
			if incremental:
				_check(road.get_output_rebuild_stats().source_surface_uploads == (0 if trace.direct_output_enabled else 3),
					"spatial output omits temporary whole-mesh uploads only when enabled")
				_check(geometry == expected[edit], "ten-road local edit matches full geometry " + str(edit))
				_check(stats.paths_reused == 9 and stats.rows_reused > stats.rows_rebuilt,
					"most source rows are reused during normal-stage profiling")
				if road._path_sampler.assembly_cache_enabled:
					_check(stats.assembly.paths_reused == 9 and stats.assembly.paths_rebuilt == 1
						and stats.assembly.rows_reused > stats.assembly.rows_rebuilt,
						"local edit retains complete assembly of nine unchanged paths")
				if road._runtime_output.incremental_partition_enabled:
					_check(road.get_output_rebuild_stats().partition_surfaces.size() == 3,
						"all three surfaces use incremental partitioning")
					for surface: Dictionary in road.get_output_rebuild_stats().partition_surfaces:
						_check(surface.fallback.is_empty() and surface.cells_reused > surface.cells_rebuilt
							and surface.cells_rebuilt > 0 and surface.centroids_rebuilt < surface.triangles_checked / 5,
							"local partition rebuilds only affected cells and centroids")
				if not trace.force_full_normals:
					for surface: Dictionary in trace.normal_cache_stats:
						_check(surface.patch_calls == 1 and surface.vertices_reused > surface.vertices_rebuilt,
							"native indexed surface retains most normals on local edits")
			else:
				expected.append(geometry)
			print("ROAD_MESH_STAGES_SAMPLE incremental=", incremental, " edit=", edit,
				" normal_vertices=", trace.normal_vertices, " source_rows_reused=", stats.rows_reused,
				" source_rows_rebuilt=", stats.rows_rebuilt, " normal_cache=", trace.normal_cache_stats,
				" partition=", road.get_output_rebuild_stats().partition_surfaces)
			print("ROAD_SOURCE_ASSEMBLY_SAMPLE ", stats.assembly)
		for values: Array in [totals, sources, sampling, assembly, meshes, normals, partitions, publications, markings, lanes]:
			values.sort()
		print("ROAD_MESH_STAGES_MEDIAN incremental=", incremental, " full_normals=", trace.force_full_normals,
			" full_partition=", not road._runtime_output.incremental_partition_enabled,
			" full_source_assembly=", not road._path_sampler.assembly_cache_enabled,
			" direct_output=", trace.direct_output_enabled, " total_ms=", totals[2],
			" source_ms=", sources[2], " mesh_ms=", meshes[2], " normal_ms=", normals[2],
			" sampling_ms=", sampling[2], " assembly_ms=", assembly[2],
			" partition_ms=", partitions[2], " publish_ms=", publications[2])
		if not markings.is_empty():
			print("ROAD_MARKING_MEDIAN incremental=", incremental,
				" full_markings=", not road._marking_builder.cache_enabled, " marking_ms=", markings[2])
		if not lanes.is_empty():
			print("ROAD_LANE_OVERLAY_MEDIAN incremental=", incremental,
				" full_lanes=", not road._lane_overlay_cache.cache_enabled, " overlay_ms=", lanes[2])
		road.free()
	print("ROAD_MESH_STAGES_%s checks=%d" % ["FAILED" if _failed else "OK", _checks])
	quit(1 if _failed else 0)


func _chunk_geometry(road: Node3D) -> Dictionary:
	# The root mesh is deliberately null in Spatial Chunks mode. Compare the
	# generated chunks themselves, including shape faces and stable node paths.
	var result: Dictionary = {"marking_rows": var_to_bytes(road._marking_rows)}
	var overlay := road.get_node_or_null("GeneratedLaneMaterialOverlays") as MeshInstance3D
	if road._has_lane_material_overrides():
		_check(overlay != null and overlay.mesh != null and overlay.mesh.get_surface_count() == 2,
			"benchmark observes actual left/right lane-overlay surfaces")
	if overlay != null and overlay.mesh != null:
		var surfaces: Array = [overlay.transform]
		for index in range(overlay.mesh.get_surface_count()):
			var material := overlay.mesh.surface_get_material(index) as StandardMaterial3D
			surfaces.append([var_to_bytes(overlay.mesh.surface_get_arrays(index)), material.albedo_color])
		result["GeneratedLaneMaterialOverlays"] = surfaces
	var paint := road.get_node_or_null("GeneratedRoadMarkings") as MeshInstance3D
	if road.markings_enabled:
		_check(paint != null and paint.mesh != null, "actual generated paint mesh exists")
	if paint != null and paint.mesh != null:
		var surfaces: Array = [paint.transform, paint.visible, paint.layers]
		for index in range(paint.mesh.get_surface_count()):
			var material := paint.mesh.surface_get_material(index) as StandardMaterial3D
			surfaces.append([paint.mesh.surface_get_name(index),
				var_to_bytes(paint.mesh.surface_get_arrays(index)), material.albedo_color])
		result["GeneratedRoadMarkings"] = surfaces
	var container: Node = road.get_node("GeneratedRoadChunks")
	for node: Node in container.find_children("*", "", true, false):
		if node is MeshInstance3D and node.mesh != null:
			var surfaces: Array = [node.transform]
			for surface in range(node.mesh.get_surface_count()):
				surfaces.append(var_to_bytes(node.mesh.surface_get_arrays(surface)))
			result[str(road.get_path_to(node))] = surfaces
		if node is CollisionShape3D and node.shape is ConcavePolygonShape3D:
			result[str(road.get_path_to(node))] = [node.transform, var_to_bytes(node.shape.get_faces())]
	return result
