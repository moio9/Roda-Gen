extends "./check_prop_source_cache.gd"
## Deterministic provider transitions supplement the real-worker ground suite.


class PendingGround:
	extends Node3D
	signal terrain_generation_completed
	var pending := false
	var height := 4.0
	var calls := 0
	var pending_calls := 0
	func is_terrain_generation_pending() -> bool:
		return pending
	func get_terrain_height_at_world(_point: Vector3) -> Dictionary:
		calls += 1
		if pending:
			pending_calls += 1
			return {"hit": false, "pending": true}
		return {"hit": true, "normal": Vector3.UP, "y": height}
	func finish() -> void:
		pending = false
		terrain_generation_completed.emit()


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var road := ROAD.new()
	road.name = "Road"
	road.threaded_generation_enabled = false
	road.debug_generation_logs = false
	road.incremental_generation_enabled = true
	scene.add_child(road)
	var path := _path("Path", Vector3.ZERO)
	road.add_child(path)
	var first := PendingGround.new()
	first.name = "First"
	scene.add_child(first)
	var second := PendingGround.new()
	second.name = "Second"
	second.height = 12.0
	scene.add_child(second)
	var props := PROPS.new()
	props.name = "Props"
	props.road_network_source = NodePath("../Road")
	props.source_paths.assign([NodePath("../Road/Path")])
	props.terrain_height_source = NodePath("../First")
	props.auto_regenerate_in_editor = false
	props.item_mesh = BoxMesh.new()
	props.ranges_mode = 0
	props.avoid_intersections = false
	props.spacing = 12
	props.snap_to_ground_enabled = true
	scene.add_child(props)
	var initial := _snapshot(props)
	_check(not initial.is_empty(), "provider fixture generates actual mesh props")
	_check(props.get_placement_rebuild_stats().bypass_reasons.has("ground_snap"), "custom provider keeps full query lifecycle")
	var calls := first.calls
	props.regenerate()
	_check(first.calls > calls and props.get_placement_rebuild_stats().ground_results_reused == 0,
		"custom provider queries are not memoized even in a warm build")
	first.pending = true
	props.regenerate()
	var saved_root: Node = props.get_node("GeneratedSplineProps")
	_check(props.get_placement_rebuild_stats().pending_terrain, "explicit rebuild waits on first provider")
	props.terrain_height_source = NodePath("../Second")
	props._process(0)
	_check(not props.get_placement_rebuild_stats().pending_terrain and _snapshot(props) != initial,
		"pending retry resolves new ready provider without waiting for old provider")
	_check(not is_instance_valid(saved_root), "successful custom-provider retry follows original output lifecycle")
	_check(not first.is_connected("terrain_generation_completed", props._on_terrain_generation_completed),
		"switch disconnects old provider")
	var second_output := _snapshot(props)
	first.finish()
	_check(not props.get_placement_rebuild_stats().pending_terrain, "stale old completion does not schedule props")
	_check(_snapshot(props) == second_output, "stale completion preserves current provider output")
	_assert_full_equal(road, props, "new provider after deferred switch")

	# Old completion can race a property edit before the retry has rebound signals.
	second.pending = true
	props.regenerate()
	props.terrain_height_source = NodePath("../First")
	first.pending = true
	second.finish()
	props._process(0)
	_check(props.get_placement_rebuild_stats().pending_terrain and _snapshot(props) == second_output,
		"old completion cannot make pending new provider ready")
	first.finish()
	props._process(0)
	_check(not props.get_placement_rebuild_stats().pending_terrain and _snapshot(props) == initial,
		"polling completes new provider even before its listener was bound")

	first.pending = true
	props.regenerate()
	props.snap_to_ground_enabled = false
	props._process(0)
	_check(not props.get_placement_rebuild_stats().pending_terrain and _snapshot(props) != initial,
		"disabling snap cancels the terrain dependency and rebuilds immediately")
	_check(not first.is_connected("terrain_generation_completed", props._on_terrain_generation_completed),
		"disabling snap unbinds completion listener")
	_assert_full_equal(road, props, "snap disabled while provider pending")
	props.snap_to_ground_enabled = true
	props.regenerate()
	props._clear_generated_from_button()
	first.finish()
	props._process(0)
	_check(_snapshot(props).is_empty() and not props.get_placement_rebuild_stats().pending_terrain,
		"manual clear is not undone by later provider completion")
	props.regenerate()
	first.height += 3
	first.finish()
	_check(props.get_placement_rebuild_stats().pending_terrain, "explicit rebuild rebinds automatic runtime completion")
	props._process(0)
	_check(_snapshot(props) != initial, "terrain-only completion updates real node transforms")

	first.pending = true
	props.regenerate()
	var mesh: Mesh = props.item_mesh
	props.item_mesh = null
	props.regenerate()
	_check(_snapshot(props).is_empty() and not props.get_placement_rebuild_stats().pending_terrain,
		"removing item during pending rebuild clears output immediately")
	first.finish()
	_check(not props.get_placement_rebuild_stats().pending_terrain, "invalid item remains disconnected")
	props.item_mesh = mesh
	props.regenerate()
	first.pending = true
	props.regenerate()
	props.source_paths.clear()
	props.regenerate()
	_check(_snapshot(props).is_empty() and not props.get_placement_rebuild_stats().pending_terrain,
		"removing only source during pending rebuild clears output immediately")
	first.finish()
	_check(not props.get_placement_rebuild_stats().pending_terrain, "missing paths remain disconnected")
	props.source_paths.assign([NodePath("../Road/Path")])
	props.regenerate()
	first.pending = true
	props.regenerate()
	_check(first.pending_calls == 0 and second.pending_calls == 0, "busy providers never receive height queries")
	first.free()
	props.terrain_height_source = NodePath("../Second")
	props._process(0)
	_check(not props.get_placement_rebuild_stats().pending_terrain and not _snapshot(props).is_empty(),
		"freed old provider is safely replaced during deferred rebuild")
	_assert_full_equal(road, props, "freed old provider")
	scene.free()
	print("PROP_TERRAIN_LIFECYCLE_%s checks=%s" % ["FAILED" if _failed else "OK", _checks])
	quit(1 if _failed else 0)
