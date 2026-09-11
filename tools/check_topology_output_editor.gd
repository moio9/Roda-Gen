@tool
extends RefCounted
## Uses the real edited scene; only saves a temporary packed copy.
const TOPOLOGY = preload("../addons/scripts/spline_road/terrain_topology_builder.gd")
var failed := false
var checks := 0


func run(plugin: EditorPlugin) -> void:
	var tree := plugin.get_tree()
	var scene: Node
	for i in range(240):
		scene = EditorInterface.get_edited_scene_root()
		if scene != null and scene.name == "RoadMarkingsDemo":
			break
		await tree.process_frame
	if scene == null or scene.name != "RoadMarkingsDemo":
		push_error("Open addons/scenes/road_markings_demo.tscn for topology output ownership checks")
		tree.quit(2)
		return
	var road: Node = scene.get_node("Road")
	road.auto_regenerate_in_editor = false
	road.threaded_generation_enabled = false
	for i in range(20):
		await tree.process_frame
	var terrain := TOPOLOGY.new()
	terrain.name = "RetainedTopology"
	terrain.generate_in_editor = false
	terrain.auto_regenerate_in_editor = false
	terrain.threaded_triangulation_enabled = false
	terrain.incremental_generation_enabled = true
	terrain.output_mode = 1
	terrain.output_chunk_size = 48
	terrain.road_network_source = NodePath("../Road")
	terrain.source_paths.assign([NodePath("../Road/Route")])
	terrain.path_sample_step = 4
	terrain.adaptive_path_sampling = false
	terrain.far_grid_step = 12
	terrain.near_road_step = 6
	terrain.near_road_width = 12
	terrain.generate_collision = true
	scene.add_child(terrain)
	terrain.owner = scene
	_build(terrain)
	var initial := _ids(terrain)
	_check(initial.size() > 2, "edited scene generates multiple native output chunks")
	_build(terrain)
	_check(initial == _ids(terrain), "actual editor warm regeneration preserves mesh and shape resources")
	_check(terrain.get_source_rebuild_stats().path_samples.collection_reused == 1
		and terrain._path_cache.stats.entries > 0, "editor aggregate hits retain native path samples")
	for entry: Dictionary in terrain._path_cache._entries.values():
		_check(entry.result.has("segments") and entry.result.has("polygon")
			and not entry.result.segments.is_empty(), "editor path snapshots retain complete contour and segment assembly")
	_check(terrain.get_source_rebuild_stats().mesh_stream.vertices_bulk > 0 and terrain._mesh_stream.target == null,
		"editor warm output bulk-appends cached geometry and releases its SurfaceTool")
	var triangles: Dictionary = terrain.get_source_rebuild_stats().triangle_groups
	_check(triangles.emission_triangles_reused > 0 and triangles.candidates_bulk == triangles.triangles_reused,
		"actual editor reuses packed triangle runs in original emission order")
	_check(terrain.get_source_rebuild_stats().mesh_stream.direct_arrays
		and terrain.get_source_rebuild_stats().output.source_surface_builds == 0,
		"editor warm output bypasses complete source SurfaceTool materialization")
	_check(terrain.get_source_rebuild_stats().point_groups.grid_coordinates_reused > 0 and terrain.get_source_rebuild_stats().point_groups.grid_coordinates_rebuilt == 0,
		"actual editor warm generation retains grid coordinate blocks")
	var near_points: Dictionary = terrain.get_source_rebuild_stats().point_groups
	_check(near_points.near_rows_reused > 0 and near_points.near_rows_rebuilt == 0
		and near_points.near_coordinates_reused > 0 and near_points.near_coordinates_rebuilt == 0,
		"actual editor warm generation retains near-road selection and coordinates")
	_check(near_points.bounds_coordinates_reused > 0 and near_points.bounds_coordinates_rebuilt == 0
		and near_points.edge_coordinates_reused > 0 and near_points.edge_coordinates_rebuilt == 0,
		"actual editor warm generation retains outer bounds and polygon contour coordinates")
	_check(terrain.get_source_rebuild_stats().point_groups.candidates_reused > 0 and terrain.get_source_rebuild_stats().point_groups.candidates_rebuilt == 0,
		"actual editor warm regeneration skips point-mask evaluation")
	_check(terrain.get_source_rebuild_stats().collar_groups.triangles_reused > 0 and terrain.get_source_rebuild_stats().collar_groups.triangles_rebuilt == 0,
		"actual editor warm regeneration reuses complete collar blocks")
	_check(terrain.get_source_rebuild_stats().output.normals.full_calls == 0 and terrain.get_source_rebuild_stats().output.normals.patch_calls == 0,
		"actual editor warm regeneration also reuses normals and partitioning")
	for root_name in ["GeneratedTopologyTerrain", "GeneratedTopologyTerrainCollision"]:
		var output: Node = terrain.get_node(root_name)
		_check(output.owner == scene, "generated container has actual edited-scene ownership")
		for child: Node in output.get_children():
			_check(child.owner == scene, "retained mesh/collider has actual edited-scene ownership")
	var packed := PackedScene.new()
	_check(packed.pack(scene) == OK, "complete edited scene can be packed")
	var file := "/tmp/roda-topology-chunks-editor.tscn"
	_check(ResourceSaver.save(packed, file) == OK, "temporary edited-scene copy saves successfully")
	var reloaded: PackedScene = ResourceLoader.load(file, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	_check(reloaded != null, "saved chunk scene reloads from disk")
	if reloaded != null:
		var copy := reloaded.instantiate()
		var saved: Node = copy.get_node("RetainedTopology")
		_check(saved.output_mode == 1 and saved.output_chunk_size == 48, "output options survive serialization")
		_check(_geometry(saved) == _geometry(terrain), "saved mesh arrays and collision faces are byte-identical")
		_check(saved._output_cache._records.is_empty(), "runtime validation snapshots are not serialized")
		_check(saved._output_cache._normal_cache._cells.is_empty(), "normal support is not serialized")
		_check(saved._triangle_cache._records.is_empty(), "filtered triangle groups are not serialized")
		_check(saved._collar_cache._records.is_empty(), "collar block snapshots are not serialized")
		_check(saved._point_cache._entries.is_empty(), "point-mask snapshots are not serialized")
		_check(saved._path_cache._entries.is_empty(), "native path samples are not serialized")
		_check(saved._mesh_stream.target == null and saved._mesh_stream.stats.is_empty(), "transient mesh stream is not serialized")
		copy.free()
	terrain.regenerate()
	terrain._process_mesh_build()
	_check(not terrain._mesh_build_state.is_empty() and terrain._mesh_stream.target != null
		and not terrain._mesh_stream._vertices.is_empty(), "editor Clear fixture has an unfinished buffered mesh job")
	_check(initial == _ids(terrain), "pending buffered job keeps the last complete visible and physics output")
	terrain._clear_generated_from_button()
	_check(terrain.get_node_or_null("GeneratedTopologyTerrain") == null and terrain._output_cache._records.is_empty(), "editor Clear removes retained nodes and snapshots")
	_check(terrain._output_cache._normal_cache._order.is_empty() and terrain._output_cache._normal_cache._cells.is_empty(), "editor Clear releases normal support")
	_check(terrain._triangle_cache._records.is_empty(), "editor Clear releases filtered triangle groups")
	_check(terrain._collar_cache._records.is_empty(), "editor Clear releases collar blocks")
	_check(terrain._point_cache._entries.is_empty(), "editor Clear releases point-mask blocks")
	_check(terrain._path_cache._entries.is_empty(), "editor Clear releases native path samples")
	_check(terrain._mesh_stream.target == null and terrain._mesh_stream._vertices.is_empty(), "editor Clear releases unfinished mesh stream state")
	print("TOPOLOGY_OUTPUT_EDITOR_%s checks=%d" % ["FAILED" if failed else "OK", checks])
	tree.quit(1 if failed else 0)


func _build(terrain: Node) -> void:
	terrain.regenerate()
	while not terrain._mesh_build_state.is_empty():
		terrain._process_mesh_build()


func _ids(terrain: Node) -> Dictionary:
	var result: Dictionary = {}
	for node: MeshInstance3D in terrain.get_node("GeneratedTopologyTerrain").get_children():
		var shape: CollisionShape3D = terrain.get_node("GeneratedTopologyTerrainCollision/" + str(node.name))
		result[str(node.name)] = [node.get_instance_id(), node.mesh.get_instance_id(), shape.get_instance_id(), shape.shape.get_instance_id()]
	return result


func _geometry(terrain: Node) -> Dictionary:
	var result: Dictionary = {}
	for node: MeshInstance3D in terrain.get_node("GeneratedTopologyTerrain").get_children():
		var shape: CollisionShape3D = terrain.get_node("GeneratedTopologyTerrainCollision/" + str(node.name))
		result[str(node.name)] = [var_to_bytes(node.mesh.surface_get_arrays(0)), var_to_bytes(shape.shape.get_faces())]
	return result


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)
