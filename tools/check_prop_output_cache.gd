extends "./check_prop_source_cache.gd"

const LIFECYCLE = preload("./fixtures/output_lifecycle_prop.gd")


func _run() -> void:
	await _exercise_mode(0)
	if DisplayServer.get_name() != "headless":
		await _exercise_mode(1)
	else:
		print("PROP_OUTPUT_GPU_SKIPPED dummy renderer cannot verify MultiMesh buffers")
	print("PROP_OUTPUT_CACHE_%s checks=%s" % ["FAILED" if _failed else "OK", _checks])
	quit(1 if _failed else 0)


func _exercise_mode(mode: int) -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	if DisplayServer.get_name() != "headless":
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		scene.add_child(environment)
		scene.add_child(DirectionalLight3D.new())
	var road := ROAD.new()
	road.name = "Road"
	road.threaded_generation_enabled = false
	road.debug_generation_logs = false
	road.incremental_generation_enabled = true
	road.road_orientation_mode = 1
	scene.add_child(road)
	var first := PROFILE.new()
	first.name = "Long"
	first.show_width_preview = false
	first.curve = Curve3D.new()
	for i in range(9):
		first.curve.add_point(Vector3(0, 0, 60 * i), Vector3(0, 0, -20), Vector3(0, 0, 20))
	road.add_child(first)
	var second := _path("Other", Vector3(100, 5, 0))
	road.add_child(second)
	var props := PROPS.new()
	props.name = "Props"
	props.auto_regenerate_in_editor = false
	props.road_network_source = NodePath("../Road")
	props.source_paths.assign([NodePath("../Road/Long"), NodePath("../Road/Other")])
	props.item_mesh = BoxMesh.new()
	props.ranges_mode = 0
	props.avoid_intersections = false
	props.placement_mode = 3
	props.spacing = 4
	props.render_mode = mode
	props.multimesh_chunk_size = 80
	props.yaw_jitter_degrees = 10
	props.random_uniform_scale_min = 0.8
	props.random_uniform_scale_max = 1.2
	scene.add_child(props)
	var original := _snapshot(props)
	var initial_ids := _identities(props)
	var old_root: Node = props.get_node("GeneratedSplineProps")
	_check(not original.is_empty(), "native output fixture contains actual nodes")
	props.regenerate()
	var stats: Dictionary = props.get_placement_rebuild_stats()
	_check(_identities(props) == initial_ids and props.get_node("GeneratedSplineProps") == old_root,
		"warm output retains exact nodes, root and MultiMesh resources")
	_check(stats.output_nodes_reused == initial_ids.size() and stats.output_nodes_created == 0,
		"warm output performs no native node creation")
	_check(_snapshot(props) == original, "warm output preserves exact transforms/resources")
	first.curve.set_point_position(4, Vector3(4, 2, 240))
	props.regenerate()
	stats = props.get_placement_rebuild_stats()
	_check(stats.output_nodes_reused > 0 and stats.output_nodes_updated + stats.output_nodes_created > 0,
		"local edit retains unchanged nodes and updates affected output")
	if mode == 1:
		_check(stats.output_buffers_reused > 0 and stats.output_buffers_rebuilt > 0,
			"local edit retains real MultiMesh resources in unchanged cells")
	print("PROP_OUTPUT_LOCAL mode=%s stats=%s" % [mode, stats])
	_check(_stored_states_match(props), "partial transform state updates match full property reflection")
	var edited_ids := _identities(props)
	props.regenerate()
	_check(_identities(props) == edited_ids and props.get_placement_rebuild_stats().output_nodes_updated == 0,
		"warm pass after local edit preserves native identities without extra updates")
	_assert_full_equal(road, props, "local retained native output")
	var ids := _identities(props)
	props.item_material_override = StandardMaterial3D.new()
	props.item_material_override.albedo_color = Color.RED
	props.mesh_cast_shadows = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	props.regenerate()
	_check(_identities(props) == ids, "material/shadow update retains native nodes and buffers")
	_assert_full_equal(road, props, "retained material/shadow update")
	if DisplayServer.get_name() != "headless":
		var shader := Shader.new()
		shader.code = "shader_type spatial; instance uniform float tint = 1.0; void fragment() { ALBEDO = vec3(tint); }"
		var material := ShaderMaterial.new()
		material.shader = shader
		props.item_material_override = material
		props.regenerate()
		var shader_node: GeometryInstance3D = _nodes(props)[0]
		shader.code = "shader_type spatial; instance uniform float tint = 1.0; instance uniform float extra = 1.0; void fragment() { ALBEDO = vec3(tint * extra); }"
		await process_frame
		shader_node.set_instance_shader_parameter("extra", 0.2)
		props.regenerate()
		_check(not is_instance_valid(shader_node), "new per-instance shader schema invalidates native state snapshot")
		_assert_full_equal(road, props, "in-place shader schema change")
		props.item_material_override = StandardMaterial3D.new()
		props.regenerate()
	ids = _identities(props)
	props.item_mesh.size = Vector3(2, 3, 4)
	props.regenerate()
	_check(_node_ids(props) == _node_ids_from_identities(ids), "in-place mesh resize retains native nodes")
	_assert_full_equal(road, props, "in-place mesh resize updates batch bounds")

	var pristine := _snapshot(props)
	var damaged: Node3D = _nodes(props)[0]
	var damaged_id := damaged.get_instance_id()
	damaged.visible = false
	damaged.set_meta("manual_extra", {"x": [1, 2]})
	props.regenerate()
	_check(not is_instance_valid(damaged) and _nodes(props)[0].get_instance_id() != damaged_id,
		"manual native-state changes trigger replacement rather than stale reuse")
	_check(_nodes(props)[0].visible and _snapshot(props) == pristine, "replacement restores generated defaults and full output")
	var with_child: Node = _nodes(props)[0]
	with_child.add_child(Node3D.new())
	props.regenerate()
	_check(not is_instance_valid(with_child), "unexpected native-node children keep full replacement lifecycle")
	var missing: Node = _nodes(props)[0]
	missing.free()
	props.regenerate()
	_check(_snapshot(props) == pristine, "manually freed output is regenerated safely")
	var renamed: Node = _nodes(props)[0]
	renamed.name = "ManuallyRenamed"
	props.regenerate()
	_check(not is_instance_valid(renamed) and _snapshot(props) == pristine, "native name changes are validated outside storage properties")
	var scene_reference: Node = _nodes(props)[0]
	scene_reference.scene_file_path = "res://manual-output-reference.tscn"
	props.regenerate()
	_check(not is_instance_valid(scene_reference) and _snapshot(props) == pristine,
		"unexpected scene reference cannot be retained on a native mesh node")
	var queued: Node = _nodes(props)[0]
	queued.queue_free()
	props.regenerate()
	_check(not is_instance_valid(queued), "queued output deletion is replaced before it can escape reconciliation")
	await process_frame
	_check(_snapshot(props) == pristine, "queued old deletion cannot remove the replacement on the next frame")
	var hidden_root: Node3D = props.get_node("GeneratedSplineProps")
	hidden_root.visible = false
	props.regenerate()
	_check(not is_instance_valid(hidden_root) and props.get_node("GeneratedSplineProps").visible,
		"manual container visibility does not survive an incremental rebuild")
	_check(_snapshot(props) == pristine, "container replacement preserves full generated output")
	if mode == 1:
		var batch: MultiMeshInstance3D = _nodes(props)[0]
		var resource_id := batch.multimesh.get_instance_id()
		batch.multimesh.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(1000, 1000, 1000)))
		batch.multimesh.visible_instance_count = 0
		props.regenerate()
		_check(is_instance_valid(batch) and batch.multimesh.get_instance_id() != resource_id,
			"manual MultiMesh buffer mutation rebuilds only the resource")
		_check(batch.multimesh.visible_instance_count == -1 and _snapshot(props) == pristine,
			"buffer replacement restores exact transforms and visibility")

	props.source_paths.assign([NodePath("../Road/Other")])
	props.regenerate()
	for node: Node in _nodes(props):
		_check("Other" in str(node.name), "removed path leaves no stale output")
	_assert_full_equal(road, props, "removed source path")
	# A replacement path uses the same public output names but new cache keys.
	road.remove_child(second)
	second.free()
	second = _path("Other", Vector3(100, 5, 0))
	road.add_child(second)
	props.regenerate()
	for node: Node in _nodes(props):
		_check(not str(node.name).begins_with("@"), "replacement path keeps deterministic native names")
	_assert_full_equal(road, props, "replacement source identity")
	props.use_parent_as_generated_root = true
	var unrelated := Node3D.new()
	unrelated.name = "Unrelated"
	scene.add_child(unrelated)
	ids = _identities(props)
	props.regenerate()
	_check(_identities(props) == ids and is_instance_valid(unrelated), "parent output reuses owned nodes only")
	_check(unrelated.get_index() < _nodes(props)[0].get_index(), "output order matches full append semantics")
	_assert_full_equal(road, props, "parent output ownership and order")
	var before_rename: Array[Node] = _nodes(props)
	props.name = "RenamedProps"
	props.regenerate()
	var obsolete := 0
	for node: Node in before_rename:
		obsolete += int(is_instance_valid(node))
	_check(obsolete == 0, "renaming parent-output generator removes its previously owned nodes")
	_assert_full_equal(road, props, "renamed parent-output generator")
	props._clear_generated_from_button()
	_check(_nodes(props).is_empty() and props._output_cache._entries.is_empty() and is_instance_valid(unrelated),
		"manual clear releases output cache without touching unrelated parent children")
	props.regenerate()
	_check(not _nodes(props).is_empty(), "explicit rebuild after clear recreates native output")
	props.use_parent_as_generated_root = false

	var scripted := LIFECYCLE.new()
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	scripted.add_child(body)
	body.add_child(shape)
	body.owner = scripted
	shape.owner = scripted
	var packed := PackedScene.new()
	_check(packed.pack(scripted) == OK, "script/collision lifecycle fixture packs")
	scripted.free()
	props.item_scene = packed
	props.regenerate()
	var ready_before: int = LIFECYCLE.ready_count
	var exit_before: int = LIFECYCLE.exit_count
	var scenes_count := _nodes(props).size()
	props.regenerate()
	_check(not props.get_placement_rebuild_stats().output_reuse_enabled and _count_collisions(props) > 0,
		"Item Scene scripts and collisions bypass native output reuse")
	_check(LIFECYCLE.ready_count == ready_before + scenes_count and LIFECYCLE.exit_count == exit_before + scenes_count,
		"every scene instance keeps its ready/exit lifecycle on regeneration")
	props.item_scene = null
	props.regenerate()
	props.regenerate()
	_check(props.get_placement_rebuild_stats().output_nodes_reused > 0, "native reuse resumes after scene fallback")
	var folder := Node3D.new()
	folder.name = "Folder"
	road.add_child(folder)
	var duplicate := _path("Other", Vector3(100, 5, 0))
	folder.add_child(duplicate)
	props.source_paths.assign([NodePath("../Road/Other"), NodePath("../Road/Folder/Other")])
	props.regenerate()
	_check(not props.get_placement_rebuild_stats().output_reuse_enabled,
		"ambiguous source names preserve legacy native naming lifecycle")
	await process_frame
	scene.free()


func _nodes(props: Node) -> Array[Node]:
	var output: Node = props.get_parent() if props.use_parent_as_generated_root else props.get_node_or_null("GeneratedSplineProps")
	var result: Array[Node] = []
	if output != null:
		for child in output.get_children():
			if props._is_generated_node_for_this_array(child):
				result.append(child)
	return result


func _identities(props: Node) -> Dictionary:
	var result: Dictionary = {}
	for node: Node in _nodes(props):
		result[node.name] = [node.get_instance_id(), node.multimesh.get_instance_id() if node is MultiMeshInstance3D else 0]
	return result


func _node_ids(props: Node) -> Array:
	return _node_ids_from_identities(_identities(props))


func _node_ids_from_identities(values: Dictionary) -> Array:
	var result: Array = []
	for value: Array in values.values():
		result.append(value[0])
	return result


func _stored_states_match(props: Node) -> bool:
	for entry: Dictionary in props._output_cache._entries.values():
		var node: Node = entry.node.get_ref()
		if node == null or props._output_cache._node_state(node, entry.properties) != entry.state:
			return false
	return true
