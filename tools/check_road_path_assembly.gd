extends "./check_road_source_cache.gd"
const SAMPLER = preload("../addons/scripts/spline_road/road_path_sampler.gd")
const REFERENCE = preload("./fixtures/road_path_assembly_reference.gd")
var sampler := SAMPLER.new()
var reference := REFERENCE.new()
var road: Node3D
var paths: Array[Path3D] = []


func _run() -> void:
	road = ROAD.new()
	road.threaded_generation_enabled = false
	road.debug_generation_logs = false
	road.adaptive_sampling_enabled = false
	road.incremental_generation_enabled = true
	road.sample_step = 2.0
	road.markings_enabled = true
	paths.assign([_path("Near", 4, Vector3.ZERO), _path("Far", 4, Vector3(500, 0, 0))])
	for path in paths:
		road.add_child(path)
	root.add_child(road)
	reference.assembly_cache_enabled = false
	_compare("cold")
	var warm := _compare("warm")
	_check(sampler.last_stats.assembly.paths_reused == 2, "warm paths reuse complete assembly")
	warm.verts.fill(Vector3.INF)
	warm.lane_indices.fill(-1)
	warm.path_rows[0][0].row_edges[0] = -1
	warm.path_rows[0][0].marking_layout.clear()
	_compare("output mutation is detached from source and assembly snapshots")
	_check(sampler.last_stats.assembly.paths_reused == 2, "output mutation does not invalidate or poison assembly")
	for edit in range(5):
		paths[0].curve.set_point_position(1, paths[0].curve.get_point_position(1) + Vector3(0.01, 0.01, 0))
		_compare("local edit " + str(edit))
		_check(sampler.last_stats.assembly.paths_reused == 1 and sampler.last_stats.assembly.paths_rebuilt == 1,
			"local source changes reconstruct only one path assembly")
	paths.reverse()
	_compare("path reorder changes global indices and row path IDs")
	_check(sampler.last_stats.assembly.paths_reused == 0, "path order invalidates global assembly")
	_compare("warm after reorder")
	paths[0].curve.add_point(Vector3(600, 3, 200))
	_compare("changed earlier path row count rebases later path")
	_check(sampler.last_stats.paths_reused == 1 and sampler.last_stats.assembly.paths_reused == 0,
		"global vertex-base change invalidates otherwise unchanged path assembly")
	for setting in ["invert_faces", "allow_endpoint_to_midpath", "strip_shoulder_sidewalk_at_intersections"]:
		road.set(setting, not bool(road.get(setting)))
		_compare("assembly-only setting " + setting)
		_check(sampler.last_stats.assembly.paths_reused == 0, "assembly setting invalidates all paths")
	for setting in ["endpoint_snap_distance", "intersection_strip_length"]:
		road.set(setting, float(road.get(setting)) + 1.25)
		_compare("assembly-only setting " + setting)
		_check(sampler.last_stats.assembly.paths_reused == 0, "weld scalar invalidates metadata")
	paths[1].intersection_override_enabled = true
	paths[1].weld_endpoint_snap_distance = 4.25
	_compare("path-specific weld settings")
	_check(sampler.last_stats.assembly.paths_reused == 1, "path weld override does not rebuild other path assembly")
	paths[1].shoulder_left_width = 0.0
	paths[1].sidewalk_left_width = 0.6
	_compare("zero shoulder with sidewalk retains curb-gap triangles")
	road.markings_enabled = false
	_compare("marking metadata removed")
	road.markings_enabled = true
	_compare("marking metadata restored")
	paths[0].position += Vector3(3, 1, 2)
	_compare("path transform")
	road.position += Vector3(-2, 1, 3)
	_compare("creator transform")
	paths.remove_at(0)
	_compare("removed path releases old entry")
	_check(sampler._source_cache._paths.size() == 1, "removed path assembly is not retained")
	sampler.clear_cache()
	_check(sampler._source_cache._paths.is_empty() and sampler._assembly_bytes == 0, "clear releases assembly")
	_compare("clear cold reconstruction")
	_check(sampler.last_stats.assembly.paths_reused == 0, "clear invalidates assembly")
	sampler.assembly_cache_enabled = false
	_compare("benchmark override disables assembly only")
	_check(sampler.last_stats.assembly.payload_bytes == 0 and sampler.last_stats.paths_reused == 1,
		"assembly disabled still allows source sampling reuse")
	sampler.assembly_cache_enabled = true
	road.incremental_generation_enabled = false
	_compare("disabled incremental generation")
	_check(sampler._source_cache._paths.is_empty(), "disabled generation retains no assembly")
	road.incremental_generation_enabled = true
	var custom := CUSTOM.new()
	custom.curve = paths[0].curve.duplicate(true)
	road.add_child(custom)
	paths.assign([custom])
	_compare("custom dynamic provider bypass")
	custom.dynamic_width += 2.0
	_compare("custom provider change")
	_check(sampler._source_cache._paths.is_empty() and sampler.last_stats.assembly.bypassed == 1,
		"custom scripts never gain assembly reuse")
	_check_pressure()
	paths.clear()
	_compare("empty paths")
	_check(sampler.last_stats.assembly.payload_bytes == 0, "empty source releases assembly")
	road.free()
	print("ROAD_PATH_ASSEMBLY_%s checks=%d" % ["FAILED" if _failed else "OK", _checks])
	quit(1 if _failed else 0)


func _check_pressure() -> void:
	road.markings_enabled = false
	road.sample_step = 2.0
	paths.clear()
	for index in range(5):
		var path := PROFILE.new()
		path.show_width_preview = false
		path.curve = Curve3D.new()
		path.curve.add_point(Vector3(index * 100, 0, 0))
		path.curve.add_point(Vector3(index * 100, 0, 29998))
		road.add_child(path)
		paths.append(path)
	_compare("aggregate payload pressure")
	_check(sampler.last_stats.assembly.bypassed > 0 and sampler.last_stats.assembly.payload_bytes > 0,
		"aggregate byte cap keeps some entries and bypasses excess paths")
	_compare("warm aggregate pressure")
	_check(sampler.last_stats.assembly.paths_reused > 0 and sampler.last_stats.assembly.paths_rebuilt > 0,
		"bounded warm store remains useful under pressure")
	var actual_bytes := 0
	for entry: Dictionary in sampler._source_cache._paths.values():
		actual_bytes += int(entry.get("assembly_bytes", 0))
	_check(actual_bytes == sampler.last_stats.assembly.payload_bytes, "reported payload matches retained entries")
	paths.resize(1)
	paths[0].curve.set_point_position(1, Vector3(0, 0, SAMPLER.MAX_ASSEMBLY_ROWS * 2))
	_compare("per-path row cap")
	_check(sampler.last_stats.assembly.bypassed == 1 and sampler.last_stats.assembly.payload_bytes == 0,
		"oversized path does not retain assembly")
	paths[0].curve.set_point_position(1, Vector3(0, 0, 20))
	_compare("small path recovers after pressure")
	_compare("small warm path after pressure")
	_check(sampler.last_stats.assembly.paths_reused == 1, "pressure does not permanently disable cache")


func _compare(label: String) -> Dictionary:
	sampler.configure(road)
	reference.configure(road)
	var actual: Dictionary = sampler.sample_paths(paths, road.global_transform.affine_inverse())
	var expected: Dictionary = reference.sample_paths(paths, road.global_transform.affine_inverse())
	_check(var_to_bytes(actual) == var_to_bytes(expected), "frozen native assembly bytes/order: " + label)
	_check(sampler.last_stats.assembly.payload_bytes <= SAMPLER.MAX_ASSEMBLY_BYTES, "retained payload bound: " + label)
	return actual
