extends SceneTree

const ROAD = preload("../addons/scripts/spline_road/road_network_creator.gd")
const PROFILE = preload("../addons/scripts/spline_road/spline_path_profile.gd")
const PROPS = preload("../addons/scripts/spline_road/spline_prop_array.gd")
const SPAN = preload("../addons/scripts/spline_road/spline_prop_span.gd")
var _failed := false
var _checks := 0
var _block_suite_completed := false
var _block_benchmark_completed := false


class DynamicGround:
	extends Node3D
	var height := 3.0
	var calls := 0
	func get_terrain_height_at_world(point: Vector3) -> Dictionary:
		calls += 1
		if int(point.z) % 17 == 0:
			return {}
		var normal := Vector3(1, 0.1, 0).normalized() if int(point.z) % 3 == 0 else Vector3.UP
		return {"hit": true, "normal": normal, "y": height + sin(point.z)}


class DynamicPath:
	extends Path3D
	var width := 8.0
	func get_width_at_offset(_offset: float) -> float:
		return width


class DynamicProps:
	extends PROPS
	var extra_offset := 1.0
	func _compute_side_offset(path: Path3D, dist: float, length: float, side: int) -> float:
		return super._compute_side_offset(path, dist, length, side) + extra_offset


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	if DisplayServer.get_name() != "headless":
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		scene.add_child(environment)
		var light := DirectionalLight3D.new()
		scene.add_child(light)
	var road := ROAD.new()
	road.name = "Road"
	road.threaded_generation_enabled = false
	road.debug_generation_logs = false
	road.auto_regenerate_in_editor = false
	road.incremental_generation_enabled = true
	scene.add_child(road)
	var first := _path("First", Vector3.ZERO)
	var second := _path("Second", Vector3(500, 0, 0))
	road.add_child(first)
	road.add_child(second)
	var props := PROPS.new()
	props.name = "Props"
	props.road_network_source = NodePath("../Road")
	props.source_paths = [NodePath("../Road/First"), NodePath("../Road/Second")]
	props.item_mesh = BoxMesh.new()
	props.item_material_override = StandardMaterial3D.new()
	props.placement_mode = 3
	props.spacing = 3.0
	props.random_seed = 475
	props.longitudinal_jitter = 0.4
	props.lateral_jitter = 0.25
	props.vertical_jitter = 0.1
	props.yaw_jitter_degrees = 12
	props.random_uniform_scale_min = 0.7
	props.random_uniform_scale_max = 1.6
	props.ranges_mode = 0
	props.avoid_intersections = false
	props.transform = Transform3D(Basis.from_euler(Vector3(0.1, -0.2, 0.04)).scaled(Vector3(-1.2, 0.8, 1.4)), Vector3(3, 2, 1))
	scene.add_child(props)
	var cold: Dictionary = props.get_placement_rebuild_stats()
	_check(cold.paths_rebuilt == 2 and cold.placements_rebuilt > 100, "cold placement calculation")
	var initial := _snapshot(props)
	props.regenerate()
	var warm: Dictionary = props.get_placement_rebuild_stats()
	_check(warm.paths_reused == 2 and warm.sampling_steps == 0, "warm paths skip placement loop")
	_check(warm.placements_reused == cold.placements_rebuilt, "reused placement count is real")
	_check(warm.rng_final_state == cold.rng_final_state, "replay preserves RNG end state")
	_check(_snapshot(props) == initial, "warm transforms and shared resources unchanged")
	first.curve.set_point_position(1, first.curve.get_point_position(1) + Vector3(0.2, 0.1, 0))
	props.regenerate()
	_check(props.get_placement_rebuild_stats().paths_reused == 1, "unchanged path survives interior edit with same RNG draw count")
	_assert_full_equal(road, props, "interior CP edit")
	var span := SPAN.new()
	span.name = "OnlyFirst"
	span.target_path = NodePath("../../Road/First")
	span.start_offset = 20
	span.end_offset = 90
	span.show_preview = false
	props.add_child(span)
	props.ranges_mode = 1
	props.range_source_mode = 1
	props.regenerate()
	span.end_offset = 50
	props.regenerate()
	_check(props.get_placement_rebuild_stats().paths_reused == 0, "range rejection changes incoming RNG of next path")
	_assert_full_equal(road, props, "span rejection and downstream RNG")
	props.ranges_mode = 0
	props.avoid_intersections = true
	props.regenerate()
	second.curve.set_point_position(0, Vector3(-3, 0, 20))
	props.regenerate()
	_check(props.get_placement_rebuild_stats().paths_reused == 0, "endpoint avoidance invalidates other path")
	_assert_full_equal(road, props, "moved endpoint rejection")
	second.curve.set_point_position(0, Vector3(500, 0, 0))
	first.lane_profile_enabled = true
	first.point_lanes_left = PackedInt32Array([1, 1, 1])
	first.point_lanes_right = PackedInt32Array([1, 2, 1])
	first.point_lane_widths = PackedFloat32Array([3.5, 3.5, 3.5])
	first.point_lane_transition_curves.resize(3)
	var ease := Curve.new()
	ease.add_point(Vector2.ZERO)
	ease.add_point(Vector2.ONE)
	first.point_lane_transition_curves[1] = ease
	props.regenerate()
	ease.set_point_right_tangent(0, 2)
	props.regenerate()
	_assert_full_equal(road, props, "in-place lane easing resource")
	for mode in range(3):
		road.road_orientation_mode = mode
		road.road_bank_strength = 0.7
		road.rotation = Vector3(0.1, 0.2, 0.03)
		first.curve.set_point_tilt(1, 0.3)
		props.regenerate()
		_assert_full_equal(road, props, "road frame mode %s" % mode)
	props.source_paths.reverse()
	props.regenerate()
	_assert_full_equal(road, props, "source path RNG order")
	props.use_parent_as_generated_root = true
	props.regenerate()
	_assert_full_equal(road, props, "parent output root")
	props.use_parent_as_generated_root = false
	props.regenerate()
	var replacement := BoxMesh.new()
	replacement.size = Vector3(2, 4, 1)
	props.item_mesh = replacement
	props.item_material_override = StandardMaterial3D.new()
	props.item_material_override.albedo_color = Color(0.8, 0.2, 0.1)
	props.regenerate()
	_check(props.get_placement_rebuild_stats().paths_reused == 2, "mesh/material changes keep source placements")
	_assert_full_equal(road, props, "replacement mesh/material resources")
	# Scene instantiation remains uncached, retaining node and collision lifecycle.
	var item := Node3D.new()
	var body := StaticBody3D.new()
	body.collision_layer = 8
	item.add_child(body)
	body.owner = item
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	body.add_child(collision)
	collision.owner = item
	var packed := PackedScene.new()
	_check(packed.pack(item) == OK, "pack collider fixture")
	item.free()
	props.item_scene = packed
	props.regenerate()
	_check(props.get_placement_rebuild_stats().bypass_reasons.get("item_scene", 0) == 2, "Item Scene is explicitly bypassed")
	_check(_count_collisions(props) > 100, "scene output keeps collisions")
	_assert_full_equal(road, props, "scene and collision fallback")
	props.item_scene = null
	var ground := DynamicGround.new()
	ground.name = "Ground"
	scene.add_child(ground)
	props.snap_to_ground_enabled = true
	props.terrain_height_source = NodePath("../Ground")
	props.snap_to_ground_slope_mode = 1
	props.regenerate()
	var ground_calls := ground.calls
	ground.height = 7
	props.regenerate()
	_check(ground.calls > ground_calls, "dynamic ground queried after changing height")
	_check(props.get_placement_rebuild_stats().bypass_reasons.get("ground_snap", 0) == 2, "ground snap explicitly bypassed")
	_assert_full_equal(road, props, "ground rejection and last-valid-height state")
	props.snap_to_ground_enabled = false
	props.randomize_seed_each_regenerate = true
	props.regenerate()
	_check(props.get_placement_rebuild_stats().bypass_reasons.get("randomized_seed", 0) == 2, "randomized seeds bypass cache")
	props.randomize_seed_each_regenerate = false
	var custom := DynamicPath.new()
	custom.name = "Custom"
	custom.curve = first.curve.duplicate()
	road.add_child(custom)
	props.source_paths.append(NodePath("../Road/Custom"))
	props.regenerate()
	custom.width = 13
	props.regenerate()
	_check(props.get_placement_rebuild_stats().bypass_reasons.get("custom_path", 0) == 1, "custom width provider bypassed")
	_assert_full_equal(road, props, "dynamic width provider")
	props.source_paths.pop_back()
	custom.free()
	props.regenerate()
	var custom_props := DynamicProps.new()
	custom_props.name = "CustomProps"
	custom_props.road_network_source = NodePath("../Road")
	custom_props.source_paths = [NodePath("../Road/First")]
	custom_props.item_mesh = props.item_mesh
	scene.add_child(custom_props)
	var custom_before := _snapshot(custom_props)
	custom_props.extra_offset = 5
	custom_props.regenerate()
	_check(custom_props.get_placement_rebuild_stats().bypass_reasons.get("custom_props", 0) == 1, "custom scatter implementation bypassed")
	_check(_snapshot(custom_props) != custom_before, "custom scatter reads dynamic offset")
	custom_props.free()
	if DisplayServer.get_name() != "headless":
		props.render_mode = 1
		props.multimesh_chunk_size = 35
		props.regenerate()
		var batch_cold := _snapshot(props)
		props.regenerate()
		_check(props.get_placement_rebuild_stats().paths_reused == 2, "MultiMesh uses unchanged source placements")
		_check(_snapshot(props) == batch_cold, "GPU MultiMesh transforms and bounds retained exactly")
		_assert_full_equal(road, props, "GPU MultiMesh output")
	else:
		print("PROP_SOURCE_CACHE_GPU_SKIPPED dummy renderer does not retain MultiMesh transforms")
	_test_blocks()
	_check(_block_suite_completed and _block_benchmark_completed, "all block fixtures and timing complete without an early script return")
	props._clear_generated_from_button()
	_check(props._placement_cache._entries.is_empty(), "manual clear drops cache")
	scene.free()
	print("PROP_SOURCE_CACHE_%s checks=%s" % ["FAILED" if _failed else "OK", _checks])
	quit(1 if _failed else 0)


func _test_blocks() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var road := ROAD.new()
	road.name = "Road"
	road.auto_regenerate_in_editor = false
	road.debug_generation_logs = false
	road.threaded_generation_enabled = false
	road.incremental_generation_enabled = true
	road.road_orientation_mode = 1
	scene.add_child(road)
	var path := PROFILE.new()
	path.name = "Long"
	path.show_width_preview = false
	path.curve = Curve3D.new()
	for i in range(9):
		path.curve.add_point(Vector3(0, 0, i * 120), Vector3(0, 0, -40), Vector3(0, 0, 40))
	road.add_child(path)
	var props := PROPS.new()
	props.name = "Props"
	props.road_network_source = NodePath("../Road")
	props.source_paths = [NodePath("../Road/Long")]
	props.item_mesh = BoxMesh.new()
	props.placement_mode = 3
	props.spacing = 2.3
	props.longitudinal_jitter = 9.5
	props.lateral_jitter = 0.3
	props.vertical_jitter = 0.2
	props.yaw_jitter_degrees = 15
	props.random_uniform_scale_min = 0.7
	props.random_uniform_scale_max = 1.3
	props.avoid_intersections = false
	props.ranges_mode = 0
	scene.add_child(props)
	var cold: Dictionary = props.get_placement_rebuild_stats()
	_check(cold.blocks_rebuilt > 10 and cold.candidates_rebuilt == cold.sampling_steps, "long path has real candidate blocks")
	var entry: Dictionary = props._placement_cache.previous(path)
	var has_float64 := false
	for d: float in entry.blocks[0].distances:
		has_float64 = has_float64 or d != PackedFloat32Array([d])[0]
	_check(has_float64, "fixture tests unrounded float64 jitter queries")
	path.curve.set_point_position(4, Vector3(12, 4, 480))
	props.regenerate()
	var local: Dictionary = props.get_placement_rebuild_stats()
	_check_partial_blocks(props, "interior position edit with large jitter")
	_check(props._placement_cache.previous(path).blocks[0] == entry.blocks[0], "prefix block retained after interior edit")
	_check(local.sampling_steps < cold.sampling_steps and local.dependency_rows_checked > 0, "placement work skipped while native support checks remain counted")
	_assert_full_equal(road, props, "local blocks, fractional spacing and jitter")
	road.road_orientation_mode = 0
	props.regenerate()
	entry = props._placement_cache.previous(path)
	path.curve.set_point_tilt(4, 0.3)
	props.regenerate()
	_check_partial_blocks(props, "local tilt")
	_check(props._placement_cache.previous(path).blocks.back() == entry.blocks.back(), "suffix block retained after local tilt")
	_assert_full_equal(road, props, "tilt blocks and transported up")
	for mode in [1, 2]:
		road.road_orientation_mode = mode
		props.regenerate()
		path.curve.set_point_position(3, path.curve.get_point_position(3) + Vector3(1, 0.2, 0))
		props.regenerate()
		_check_partial_blocks(props, "frame mode %s" % mode)
		_assert_full_equal(road, props, "block frame mode %s" % mode)
	path.curve.set_point_position(8, Vector3(0, 0, 985))
	props.regenerate()
	_check_partial_blocks(props, "length extension and jitter tail clamp")
	_assert_full_equal(road, props, "length extension, repeated-addition tail")
	props.ranges_mode = 1
	props.range_source_mode = 0
	props.distance_ranges = PackedVector2Array([Vector2(0, 10000)])
	props.regenerate()
	path.curve.set_point_position(8, Vector3(0, 0, 1000))
	props.regenerate()
	_check_partial_blocks(props, "whole-range clamped to extended path")
	_assert_full_equal(road, props, "range tail extension")
	props.distance_ranges = PackedVector2Array([Vector2(0, 450)])
	props.regenerate()
	props.distance_ranges = PackedVector2Array([Vector2(0, 470)])
	props.regenerate()
	_check_partial_blocks(props, "local manual range edit and rejected suffix")
	_assert_full_equal(road, props, "range rejection propagates RNG between blocks")
	props.ranges_mode = 2
	props.regenerate()
	props.distance_ranges = PackedVector2Array([Vector2(0, 480)])
	props.regenerate()
	_check_partial_blocks(props, "exclude mode, empty leading blocks")
	_assert_full_equal(road, props, "exclude ranges and empty block replay")
	props.distance_ranges = PackedVector2Array()
	props.regenerate()
	_assert_full_equal(road, props, "empty effective ranges are unrestricted")
	props.ranges_mode = 0
	path.lane_profile_enabled = true
	path.point_lanes_right = PackedInt32Array([1, 1, 1, 1, 2, 1, 1, 1, 1])
	props.regenerate()
	path.point_lanes_right[4] = 3
	props.regenerate()
	_check_partial_blocks(props, "local directional lane width")
	_assert_full_equal(road, props, "lane support within path")
	var easing := Curve.new()
	easing.add_point(Vector2.ZERO)
	easing.add_point(Vector2.ONE)
	path.point_lane_transition_curves.resize(9)
	path.point_lane_transition_curves[4] = easing
	props.regenerate()
	easing.set_point_right_tangent(0, 2)
	props.regenerate()
	_check_partial_blocks(props, "local in-place easing")
	_assert_full_equal(road, props, "transition resource block support")
	path.lane_profile_enabled = false
	path.point_widths = PackedFloat32Array([7, 8, 7, 9, 7, 8, 7, 8, 7])
	props.regenerate()
	path.curve.set_point_position(8, Vector3(0, 0, 1030))
	props.regenerate()
	_check(props.get_placement_rebuild_stats().blocks_reused == 0, "nonuniform legacy widths depend on total length")
	_assert_full_equal(road, props, "global legacy width dependency")
	path.point_widths = PackedFloat32Array()
	var endpoint := _path("Endpoint", Vector3(1000, 0, 0))
	road.add_child(endpoint)
	props.source_paths.append(NodePath("../Road/Endpoint"))
	props.avoid_intersections = true
	props.intersection_clear_radius = 12
	props.regenerate()
	entry = props._placement_cache.previous(path)
	endpoint.curve.set_point_position(0, Vector3(-4, 0, 440))
	props.regenerate()
	_check_partial_blocks(props, "nearby endpoint rejection")
	_check(props._placement_cache.previous(path).blocks[0] == entry.blocks[0], "distant block survives endpoint move")
	_check(props.get_placement_rebuild_stats().endpoint_queries_checked > 0, "endpoint validation is counted")
	_assert_full_equal(road, props, "endpoint decision support and downstream RNG")
	# Deterministic mixed edits exercise reuse after earlier blocks change their
	# draw count, rather than only comparing a warm cache with itself.
	var edit_rng := RandomNumberGenerator.new()
	edit_rng.seed = 98342
	for i in range(12):
		var point := edit_rng.randi_range(2, 6)
		path.curve.set_point_position(point, path.curve.get_point_position(point) + Vector3(edit_rng.randf_range(-3, 3), edit_rng.randf_range(-0.3, 0.3), 0))
		props.regenerate()
		_assert_full_equal(road, props, "mixed block edit %s" % i)
	if DisplayServer.get_name() != "headless":
		props.render_mode = 1
		props.multimesh_chunk_size = 180
		props.regenerate()
		path.curve.set_point_position(5, path.curve.get_point_position(5) + Vector3(1, 0, 0))
		props.regenerate()
		_check_partial_blocks(props, "MultiMesh local edit")
		_assert_full_equal(road, props, "mixed cached/rebuilt blocks share exact MultiMesh cells and order")
	_benchmark_blocks(road, props, path)
	if DisplayServer.get_name() != "headless" and "--benchmark-individual" in OS.get_cmdline_user_args():
		props.render_mode = 0
		props.regenerate()
		_benchmark_blocks(road, props, path)
	print("PROP_BLOCK_LOCAL_STATS ", local)
	scene.free()
	_block_suite_completed = true


func _benchmark_blocks(road: Node, props: Node, path: Path3D) -> void:
	road.road_orientation_mode = 0
	props.avoid_intersections = false
	props.source_paths.assign([NodePath("../Road/Long")])
	var full: Array[float] = []
	var local: Array[float] = []
	var warm: Array[float] = []
	for enabled in [false, true]:
		road.incremental_generation_enabled = enabled
		path.curve.set_point_tilt(4, 0.3)
		props.regenerate()
		for i in range(7):
			path.curve.set_point_tilt(4, 0.1 if i % 2 == 0 else 0.3)
			var started := Time.get_ticks_usec()
			props.regenerate()
			var elapsed := (Time.get_ticks_usec() - started) / 1000.0
			if enabled:
				local.append(elapsed)
			else:
				full.append(elapsed)
	var local_stats: Dictionary = props.get_placement_rebuild_stats()
	_check_partial_blocks(props, "timed local tilt edit")
	_assert_full_equal(road, props, "timed local edit output")
	for i in range(7):
		var started := Time.get_ticks_usec()
		props.regenerate()
		warm.append((Time.get_ticks_usec() - started) / 1000.0)
	full.sort()
	local.sort()
	warm.sort()
	print("PROP_BLOCK_TIMING renderer=%s mode=%s full_ms=%s local_ms=%s warm_ms=%s local_stats=%s" % [
		DisplayServer.get_name(), props.render_mode, full[3], local[3], warm[3], local_stats])
	if "--profile-output" in OS.get_cmdline_user_args():
		print("PROP_OUTPUT_PROPERTIES ", props._output_cache._entries.values()[0].properties)
		print("PROP_OUTPUT_WARM_STATS ", props.get_placement_rebuild_stats())
	_block_benchmark_completed = true


func _check_partial_blocks(props: Node, label: String) -> void:
	var stats: Dictionary = props.get_placement_rebuild_stats()
	_check(stats.blocks_reused > 0 and stats.blocks_rebuilt > 0, "within-path reuse and rebuild: " + label)
	_check(stats.candidates_reused > 0 and stats.candidates_rebuilt == stats.sampling_steps,
		"candidate counters cover actual work: " + label)


func _path(label: String, offset: Vector3) -> Path3D:
	var path := PROFILE.new()
	path.name = label
	path.show_width_preview = false
	path.curve = Curve3D.new()
	path.curve.add_point(offset, Vector3.ZERO, Vector3(0, 0, 20))
	path.curve.add_point(offset + Vector3(10, 2, 65), Vector3(0, 0, -20), Vector3(0, 0, 20))
	path.curve.add_point(offset + Vector3(0, 0, 130), Vector3(0, 0, -20))
	path.shoulder_left_width = 0.5
	return path


func _assert_full_equal(road: Node, props: Node, label: String) -> void:
	var actual := _snapshot(props)
	_check(not actual.is_empty(), "comparison includes actual generated props: " + label)
	var rng_state: int = props.get_placement_rebuild_stats().rng_final_state
	road.incremental_generation_enabled = false
	props.regenerate()
	_check(actual == _snapshot(props), "full/cached transform/resource/collision parity: " + label)
	_check(props.get_placement_rebuild_stats().rng_final_state == rng_state, "full/cached RNG parity: " + label)
	road.incremental_generation_enabled = true
	props.regenerate()
	props.regenerate()


func _snapshot(props: Node) -> Array:
	var generation_root: Node = props.get_parent() if props.use_parent_as_generated_root else props.get_node_or_null("GeneratedSplineProps")
	var result: Array = []
	if generation_root == null:
		return result
	for child in generation_root.get_children():
		if not child is Node3D or not props._is_generated_node_for_this_array(child):
			continue
		result.append([child.name, child.transform])
		if child is MeshInstance3D:
			result.append([child.mesh, child.material_override, child.cast_shadow])
		elif child is MultiMeshInstance3D:
			result.append([child.multimesh.mesh, child.material_override, child.cast_shadow, child.multimesh.custom_aabb])
			for i in range(child.multimesh.instance_count):
				result.append(child.multimesh.get_instance_transform(i))
		else:
			_append_collisions(child, result)
	return result


func _append_collisions(node: Node, result: Array) -> void:
	for child in node.get_children():
		if child is StaticBody3D:
			result.append([child.transform, child.collision_layer, child.collision_mask])
		if child is CollisionShape3D:
			result.append([child.transform, child.shape, child.disabled])
		_append_collisions(child, result)


func _count_collisions(node: Node) -> int:
	var count := 1 if node is CollisionShape3D else 0
	for child in node.get_children():
		count += _count_collisions(child)
	return count


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		push_error(message)
