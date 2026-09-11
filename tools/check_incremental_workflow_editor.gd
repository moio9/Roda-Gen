@tool
extends RefCounted
## Actual editor propagation: no manual regeneration between a curve edit and
## its road/terrain/ground-prop outputs. Source demo files are never saved.
const ROAD = preload("../addons/scripts/spline_road/road_network_creator.gd")
const PROFILE = preload("../addons/scripts/spline_road/spline_path_profile.gd")
const TERRAIN = preload("../addons/scripts/spline_road/terrain_topology_builder.gd")
const PROPS = preload("../addons/scripts/spline_road/spline_prop_array.gd")
var tree: SceneTree
var checks := 0
var failed := false
var capture_viewport: SubViewport
var edited_image: Image


func run(plugin: EditorPlugin) -> void:
	tree = plugin.get_tree()
	var scene: Node
	for frame in range(240):
		scene = EditorInterface.get_edited_scene_root()
		if scene != null and scene.name == "RoadMarkingsDemo":
			break
		await tree.process_frame
	if scene == null or scene.name != "RoadMarkingsDemo":
		push_error("Open addons/scenes/road_markings_demo.tscn for the integrated editor workflow test")
		tree.quit(2)
		return
	var road: Node3D = scene.get_node("Road")
	road.auto_regenerate_in_editor = false
	road.threaded_generation_enabled = "--workflow-threaded" in OS.get_cmdline_user_args()
	road.incremental_generation_enabled = true
	road.output_mode = 1
	road.output_chunk_size = 48
	road.output_generate_collision = true
	road.editor_regenerate_debounce_seconds = 0.1
	if "--workflow-lanes" in OS.get_cmdline_user_args():
		road.left_lane_material_overrides.assign([_material(Color(0.26, 0.17, 0.12))])
		road.right_lane_material_overrides.assign([_material(Color(0.12, 0.18, 0.29)), _material(Color(0.24, 0.28, 0.32))])
	var path: Path3D = road.get_node("Route")
	var far := PROFILE.new()
	far.name = "FarRoute"
	_copy_settings(path, far)
	far.curve = path.curve.duplicate(true)
	far.position.x = 350
	far.show_width_preview = false
	road.add_child(far)
	far.owner = scene
	road.source_paths.assign([NodePath("Route"), NodePath("FarRoute")])
	var junctions := "--workflow-junctions" in OS.get_cmdline_user_args()
	if junctions:
		road.allow_endpoint_to_midpath = false
		for center: Vector3 in [Vector3.ZERO, Vector3(350, 0, 0)]:
			for arm in range(2):
				var branch := PROFILE.new()
				branch.name = "%sArm%d" % ["Near" if center.x == 0 else "Far", arm]
				branch.show_width_preview = false
				branch.curve = Curve3D.new()
				var offset := Vector3(-40, 0, -20) if arm == 0 else Vector3(35, 0, -30)
				branch.curve.add_point(center, Vector3.ZERO, offset / 3.0)
				branch.curve.add_point(center + offset, -offset / 3.0)
				road.add_child(branch)
				branch.owner = scene
				road.source_paths.append(NodePath(branch.name))
	var terrain := TERRAIN.new()
	terrain.name = "WorkflowTerrain"
	terrain.generate_in_editor = false
	terrain.auto_regenerate_in_editor = false
	terrain.threaded_triangulation_enabled = true
	terrain.incremental_generation_enabled = true
	terrain.centered_triangulation_enabled = true
	terrain.local_triangulation_enabled = true
	terrain.output_mode = 1
	terrain.output_chunk_size = 48
	terrain.road_network_source = NodePath("../Road")
	terrain.source_paths.assign([NodePath("../Road/Route"), NodePath("../Road/FarRoute")])
	if junctions:
		for np: NodePath in road.source_paths.slice(2):
			terrain.source_paths.append(NodePath("../Road/" + str(np)))
	terrain.path_sample_step = 4
	terrain.adaptive_path_sampling = false
	terrain.bounds_mode = 1
	terrain.manual_center_xz = Vector2(220, 80)
	terrain.manual_size_xz = Vector2(700, 260)
	terrain.far_grid_step = 16
	terrain.near_road_step = 8
	terrain.near_road_width = 8
	terrain.generate_collision = true
	terrain.invert_faces = true
	scene.add_child(terrain)
	terrain.owner = scene
	var props := PROPS.new()
	props.name = "WorkflowProps"
	props.generate_in_editor = false
	props.auto_regenerate_in_editor = false
	props.road_network_source = NodePath("../Road")
	props.terrain_height_source = NodePath("../WorkflowTerrain")
	props.source_paths.assign([NodePath("../Road/Route"), NodePath("../Road/FarRoute")])
	props.item_mesh = BoxMesh.new()
	props.item_mesh.size = Vector3(0.5, 2, 0.5)
	if "--workflow-multimesh" in OS.get_cmdline_user_args():
		props.render_mode = 1
		props.multimesh_chunk_size = 48
	props.ranges_mode = 0
	props.avoid_intersections = false
	props.spacing = 8
	props.outward_offset = 2
	props.snap_to_ground_enabled = true
	props.snap_to_ground_max_angle_deg = 89
	props.snap_to_ground_y_offset = 1
	if "--workflow-capture" in OS.get_cmdline_user_args():
		road.road_material_override = _material(Color(0.14, 0.16, 0.18))
		road.shoulder_material_override = _material(Color(0.65, 0.45, 0.2))
		terrain.terrain_material_override = _material(Color(0.16, 0.32, 0.13))
		props.item_material_override = _material(Color(0.6, 0.85, 1.0))
		_setup_capture(scene)
	scene.add_child(props)
	props.owner = scene
	if "--workflow-reverse-order" in OS.get_cmdline_user_args():
		scene.move_child(terrain, 0)
		scene.move_child(props, 0)
	var nodes: Array = [road, terrain, props]
	props.generate_in_editor = true
	for node: Node in nodes:
		node.auto_regenerate_in_editor = true
	if not await _settle(nodes, "initial automatic generation"):
		tree.quit(1)
		return
	var initial := _geometry(nodes)
	_check(road.markings_enabled and road.get_node_or_null("GeneratedRoadMarkings") != null,
		"editor workflow includes actual generated paint geometry")
	_check(road.get_output_rebuild_stats().source_surface_uploads == 0,
		"automatic spatial output does not upload a temporary complete road mesh")
	var initial_image := await _capture("initial")
	var far_ids := _far_ids(nodes)
	_check(initial.size() == 3 and not initial[0].is_empty() and not initial[1].is_empty() and not initial[2].is_empty(),
		"automatic editor setup produces road, terrain and grounded props")
	_check(far_ids.size() > 10, "fixture has independently identifiable distant mesh/shape/prop resources")
	for node: Node in nodes:
		var count := 0
		for key: String in far_ids:
			count += int(key.begins_with(str(node.name) + "/"))
		_check(count > 0, "distant identity snapshot covers " + str(node.name))
	if junctions:
		_check(road.get_source_rebuild_stats().junction_geometry.clusters_rebuilt == 2,
			"automatic setup generates two spatially separated junction fans")
	var point_index := 0 if junctions else 1
	var old_point := path.curve.get_point_position(point_index)
	var point_delta := Vector3(1.5, 0.5, 0) if junctions else Vector3(5, 1, 0)
	var history := plugin.get_undo_redo()
	history.create_action("Workflow curve edit", UndoRedo.MERGE_DISABLE, path)
	history.add_do_method(path.curve, "set_point_position", point_index, old_point + point_delta)
	history.add_undo_method(path.curve, "set_point_position", point_index, old_point)
	var started := Time.get_ticks_usec()
	history.commit_action()
	_check(road.is_road_generation_pending(), "road exposes queued editor edit before a worker starts")
	_check(terrain.is_terrain_generation_pending(), "terrain exposes queued edit before its process callback")
	_check(terrain.get_terrain_height_at_world(Vector3.ZERO).get("pending", false),
		"ground queries cannot consume a queued terrain edit")
	if not await _settle(nodes, "automatic propagation after curve edit"):
		tree.quit(1)
		return
	var edit_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var edited := _geometry(nodes)
	var marking_stats: Dictionary = road.get_marking_stats()
	_check(marking_stats.incremental and marking_stats.blocks_reused > 0 and marking_stats.blocks_rebuilt > 0,
		"automatic local edit retains unchanged paint blocks and rebuilds affected paint")
	print("WORKFLOW_MARKING_CACHE ", marking_stats)
	if "--workflow-lanes" in OS.get_cmdline_user_args():
		var lane_stats: Dictionary = road.get_lane_overlay_stats()
		_check(road.get_node_or_null("GeneratedLaneMaterialOverlays") != null,
			"workflow includes actual per-lane material mesh")
		_check(lane_stats.blocks_reused > 0 and lane_stats.blocks_rebuilt > 0,
			"local editor curve edit reuses unaffected lane-material geometry")
		print("WORKFLOW_LANE_OVERLAY_CACHE ", lane_stats)
	edited_image = await _capture("edited")
	if capture_viewport != null:
		var changed := _changed_pixels(initial_image, edited_image)
		_check(changed > 20, "native editor curve edit changes visible output")
		print("WORKFLOW_RENDER_EDIT changed_pixels=", changed)
	for index in range(3):
		_check(edited[index] != initial[index], "curve edit automatically updates dependent output " + str(index))
	_check(_far_ids(nodes) == far_ids, "local editor edit retains all distant road/terrain/prop mesh and collision identities")
	if junctions:
		var stats: Dictionary = road.get_source_rebuild_stats().junction_geometry
		_check(stats.clusters_rebuilt == 1 and stats.clusters_reused == 1,
			"automatic edit rebuilds nearby junction geometry and reuses the distant junction")
		var local_stats: Dictionary = terrain.get_source_rebuild_stats().local_triangulation
		_check(local_stats.fallback.is_empty() and local_stats.triangles_reused > 0
			and local_stats.triangles_rebuilt > 0 and local_stats.external_ties > 0,
			"automatic junction edit resolves external circle ties without full triangulation")
	print("INCREMENTAL_WORKFLOW_LOCAL edit_ms=", edit_ms, " road=", road.get_source_rebuild_stats(),
		" terrain=", terrain.get_source_rebuild_stats(), " props=", props.get_placement_rebuild_stats())
	var undo := history.get_history_undo_redo(history.get_object_history_id(path))
	undo.undo()
	await _settle(nodes, "automatic propagation after Undo")
	_compare_geometry(_geometry(nodes), initial, "Undo")
	if capture_viewport != null:
		_check(_images_equal(initial_image, await _capture("undo")), "Undo restores the rendered image bytes")
	undo.redo()
	await _settle(nodes, "automatic propagation after Redo")
	_compare_geometry(_geometry(nodes), edited, "Redo")
	if capture_viewport != null:
		_check(_images_equal(edited_image, await _capture("redo")), "Redo restores the rendered image bytes")
	for node: Node in nodes:
		node.auto_regenerate_in_editor = false
	await _compare_full(scene, nodes, edited)
	path.curve.set_point_position(point_index, old_point)
	_check(not road.is_road_generation_pending() and not terrain.is_terrain_generation_pending(),
		"manual-only generators do not promise an automatic rebuild")
	print("INCREMENTAL_WORKFLOW_EDITOR_%s checks=%d" % ["FAILED" if failed else "OK", checks])
	tree.quit(1 if failed else 0)


func _settle(nodes: Array, label: String) -> bool:
	# Mesh assembly is intentionally spread across editor frames. Unfocused
	# editors may pace those frames slowly; this is a correctness timeout, not
	# the separately measured regeneration benchmark.
	var started := Time.get_ticks_msec()
	var deadline := started + 60000
	var stable_since := 0
	var frames := 0
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame
		frames += 1
		var road: Node = nodes[0]
		var terrain: Node = nodes[1]
		var props: Node = nodes[2]
		var pending: bool = road._is_generation_thread_active() or terrain.is_terrain_generation_pending() or props._terrain_regeneration_pending
		var dirty := false
		for node: Node in nodes:
			dirty = dirty or node._last_signature != node._build_signature()
		if pending or dirty:
			stable_since = 0
		elif stable_since == 0:
			stable_since = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - stable_since >= 500:
			_check(true, label + " settles without manual regeneration")
			print("WORKFLOW_SETTLED ", label, " frames=", frames, " elapsed_ms=", Time.get_ticks_msec() - started)
			return true
	_check(false, label + " timed out")
	for node: Node in nodes:
		print("INCREMENTAL_WORKFLOW_PENDING ", node.name, " dirty=", node._last_signature != node._build_signature())
	print("WORKFLOW_PENDING_DETAILS road_worker=", nodes[0]._is_generation_thread_active(),
		" terrain_pending=", nodes[1].is_terrain_generation_pending(),
		" mesh_state_keys=", nodes[1]._mesh_build_state.keys(),
		" props_pending=", nodes[2]._terrain_regeneration_pending,
		" terrain_stages=", nodes[1].get_source_rebuild_stats().get("stage_ms", {}))
	return false


func _compare_full(scene: Node, nodes: Array, expected: Array) -> void:
	var reference := Node3D.new()
	reference.name = "WorkflowFullReference"
	reference.visible = false
	scene.add_child(reference)
	var road := ROAD.new()
	_copy_settings(nodes[0], road)
	road.name = "Road"
	road.generate_in_editor = false
	road.auto_regenerate_in_editor = false
	road.incremental_generation_enabled = false
	road.threaded_generation_enabled = false
	for np: NodePath in nodes[0].source_paths:
		var original: Path3D = nodes[0].get_node(np)
		var path := PROFILE.new()
		_copy_settings(original, path)
		path.name = original.name
		path.transform = original.transform
		path.curve = original.curve.duplicate(true)
		road.add_child(path)
	reference.add_child(road)
	road.regenerate()
	var terrain := TERRAIN.new()
	_copy_settings(nodes[1], terrain)
	terrain.name = "WorkflowTerrain"
	terrain.generate_in_editor = false
	terrain.auto_regenerate_in_editor = false
	terrain.incremental_generation_enabled = false
	terrain.threaded_triangulation_enabled = false
	reference.add_child(terrain)
	terrain.regenerate()
	var deadline := Time.get_ticks_msec() + 60000
	while terrain.is_terrain_generation_pending() and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	_check(not terrain.is_terrain_generation_pending(), "full reference completes within deadline")
	var props := PROPS.new()
	_copy_settings(nodes[2], props)
	props.name = "WorkflowProps"
	props.auto_regenerate_in_editor = false
	reference.add_child(props)
	props.regenerate()
	var actual := _geometry([road, terrain, props])
	_check(road.get_output_rebuild_stats().source_surface_uploads > 0,
		"full reference exercises the native uploaded source mesh")
	_compare_geometry(actual, expected, "fresh full reference")
	if capture_viewport != null:
		for node: Node3D in nodes:
			node.visible = false
		reference.visible = true
		var full_image := await _capture("full-reference")
		var difference := _changed_pixels(edited_image, full_image)
		_check(_images_equal(edited_image, full_image), "automatic local junction/terrain/prop render matches fresh full generation bytes")
		print("WORKFLOW_RENDER_FULL changed_pixels=", difference)
		for node: Node3D in nodes:
			node.visible = true
	reference.free()


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _setup_capture(scene: Node3D) -> void:
	capture_viewport = SubViewport.new()
	capture_viewport.name = "WorkflowCapture"
	capture_viewport.size = Vector2i(960, 720)
	capture_viewport.world_3d = scene.get_world_3d()
	capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	scene.add_child(capture_viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 580
	camera.far = 1500
	capture_viewport.add_child(camera)
	camera.position = Vector3(190, 430, 260)
	camera.look_at(Vector3(190, 0, 60))
	camera.current = true


func _capture(label: String) -> Image:
	if capture_viewport == null:
		return null
	for frame in range(3):
		await tree.process_frame
	await RenderingServer.frame_post_draw
	var result := capture_viewport.get_texture().get_image()
	_check(result != null and not result.is_empty(), "editor subviewport produces " + label)
	_check(result.save_png("/tmp/roda-workflow-junction-" + label + ".png") == OK, "save " + label + " image")
	return result


func _images_equal(a: Image, b: Image) -> bool:
	return a != null and b != null and a.get_size() == b.get_size() and a.get_format() == b.get_format() \
		and a.get_data() == b.get_data()


func _changed_pixels(a: Image, b: Image) -> int:
	if a == null or b == null or a.get_size() != b.get_size():
		return 9999999
	var changed := 0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var left := a.get_pixel(x, y)
			var right := b.get_pixel(x, y)
			changed += int(maxf(absf(left.r - right.r), maxf(absf(left.g - right.g), absf(left.b - right.b))) > 0.02)
	return changed


func _compare_geometry(actual: Array, expected: Array, label: String) -> void:
	for index in range(3):
		_check(actual[index] == expected[index], label + " geometry " + str(index))
		if actual[index] == expected[index]:
			continue
		print("WORKFLOW_DIFF ", label, " output=", index, " counts=", actual[index].size(), "/", expected[index].size())
		var differences := 0
		for key in expected[index]:
			if actual[index].get(key) == expected[index][key]:
				continue
			print("WORKFLOW_DIFF key=", key, " actual_transform=", actual[index].get(key, []).slice(0, 1),
				" expected_transform=", expected[index][key].slice(0, 1))
			differences += 1
			if differences >= 3:
				break


func _copy_settings(source: Node, target: Node) -> void:
	for property: Dictionary in source.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(property.usage) & PROPERTY_USAGE_STORAGE:
			if target.get(property.name) != source.get(property.name):
				target.set(property.name, source.get(property.name))


func _geometry(nodes: Array) -> Array:
	var result: Array = []
	for root: Node in nodes:
		var values: Dictionary = {}
		for child: Node in root.get_children():
			if str(child.name).begins_with("Generated"):
				_walk_geometry(root, child, values)
		result.append(values)
	return result


func _walk_geometry(root: Node, node: Node, result: Dictionary) -> void:
	var values: Array = [node.transform] if node is Node3D else []
	if node is MultiMeshInstance3D and node.multimesh != null:
		values.append([node.multimesh.instance_count, node.multimesh.visible_instance_count,
			var_to_bytes(node.multimesh.buffer), node.multimesh.custom_aabb])
		if node.multimesh.mesh != null:
			for surface in range(node.multimesh.mesh.get_surface_count()):
				values.append(var_to_bytes(node.multimesh.mesh.surface_get_arrays(surface)))
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			values.append(var_to_bytes(node.mesh.surface_get_arrays(surface)))
	if node is CollisionShape3D and node.shape is ConcavePolygonShape3D:
		values.append(var_to_bytes(node.shape.get_faces()))
	result[str(root.get_path_to(node))] = values
	for child: Node in node.get_children():
		_walk_geometry(root, child, result)


func _far_ids(nodes: Array) -> Dictionary:
	var result: Dictionary = {}
	for root: Node in nodes:
		for node: Node in root.find_children("*", "", true, false):
			if node is MultiMeshInstance3D and node.multimesh != null:
				if (node.global_transform * node.multimesh.get_aabb().get_center()).x > 250:
					result[str(root.name) + "/" + str(root.get_path_to(node))] = [node.get_instance_id(),
						node.multimesh.get_instance_id(), node.multimesh.mesh.get_instance_id()]
			if node is MeshInstance3D and node.mesh != null:
				if (node.global_transform * node.mesh.get_aabb().get_center()).x > 250:
					result[str(root.name) + "/" + str(root.get_path_to(node))] = [node.get_instance_id(), node.mesh.get_instance_id()]
			if node is CollisionShape3D and node.shape is ConcavePolygonShape3D:
				var faces: PackedVector3Array = node.shape.get_faces()
				var far := not faces.is_empty()
				for vertex: Vector3 in faces:
					far = far and (node.global_transform * vertex).x > 250
				if far:
					result[str(root.name) + "/" + str(root.get_path_to(node))] = [node.get_instance_id(), node.shape.get_instance_id()]
	return result


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)
