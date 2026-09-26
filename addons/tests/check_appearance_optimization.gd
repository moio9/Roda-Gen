extends SceneTree
const ROAD = preload("../scripts/spline_road/road_network_creator.gd")
const PROFILE = preload("../scripts/spline_road/spline_path_profile.gd")
const APPEARANCE = preload("../scripts/spline_road/road_lane_appearance.gd")
const MARKINGS = preload("../scripts/spline_road/road_marking_builder.gd")
var failed := false
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var road := ROAD.new()
	road.threaded_generation_enabled = false
	road.debug_generation_logs = false
	road.incremental_generation_enabled = true
	road.output_generate_collision = true
	road.adaptive_sampling_enabled = false
	road.sample_step = 1.0
	var path := PROFILE.new()
	path.show_width_preview = false
	path.lane_profile_enabled = true
	path.default_lanes_right = 2
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -1000.0 / 3.0))
	path.curve.add_point(Vector3(0, 0, -1000), Vector3(0, 0, 1000.0 / 3.0))
	road.add_child(path)
	root.add_child(road)
	var revision: int = road.get_terrain_surface_revision()
	var mesh: Mesh = road.get_node("GeneratedSplineRoadWelded").mesh
	road.markings_enabled = true
	road.regenerate()
	_check(road.get_terrain_surface_revision() == revision, "Initial paint enable reuses disabled-paint road rows")
	_check(road.get_node("GeneratedSplineRoadWelded").mesh == mesh, "Paint enable retains main mesh resource")
	_check(road.get_node_or_null("GeneratedRoadMarkings") != null, "Paint enable produces geometry")
	var rule := APPEARANCE.new()
	rule.start_offset = 101.3
	rule.end_offset = 121.7
	rule.inner_line_style = MARKINGS.SOLID
	path.lane_appearance_overrides.assign([rule])
	road.regenerate()
	_check(road.get_terrain_surface_revision() == revision, "Adding lane style keeps final-road revision")
	_check_native_paint(road)
	rule.inner_line_style = MARKINGS.OFF
	road.regenerate()
	var stats: Dictionary = road.get_marking_stats()
	_check(stats.blocks_rebuilt > 0 and stats.blocks_rebuilt <= 2 and stats.blocks_reused > 10,
		"20 m style edit only rebuilds affected blocks: %s" % stats)
	_check_native_paint(road)
	for bounds in [Vector2(127.5, 128.5), Vector2(500.3, 521.7), Vector2(1001, 1020)]:
		rule.start_offset = bounds.x
		rule.end_offset = bounds.y
		rule.stop_line_at_start = true
		rule.stop_line_at_end = true
		road.regenerate()
		_check_native_paint(road)
	path.lane_appearance_overrides.clear()
	road.regenerate()
	_check_native_paint(road)
	_check(road.get_terrain_surface_revision() == revision, "Moving/removing ranges preserves road geometry")
	rule.start_offset = 101.3
	rule.end_offset = 121.7
	rule.stop_line_at_start = false
	rule.stop_line_at_end = false
	rule.inner_line_style = -1
	rule.surface_material = StandardMaterial3D.new()
	path.lane_appearance_overrides.assign([rule])
	var paint_resource: Mesh = road.get_node("GeneratedRoadMarkings").mesh
	road.regenerate()
	_check(road.get_node("GeneratedRoadMarkings").mesh == paint_resource, "Material-only rule does not rebuild paint")
	var overlay_stats: Dictionary = road.get_lane_overlay_stats()
	_check(overlay_stats.rows_rebuilt < 30 and overlay_stats.rows_rebuilt > 0,
		"Only material-bearing lane and bracketing samples are built: %s" % overlay_stats)
	var overlay: Mesh = road.get_node("GeneratedLaneMaterialOverlays").mesh
	_check(absf(_area(overlay) - 20.4 * 3.5) < 0.002, "Partial source strips retain exact clipped area")
	var second := rule.duplicate()
	second.start_offset = 801.3
	second.end_offset = 821.7
	path.lane_appearance_overrides.append(second)
	road.regenerate()
	_check(absf(_area(road.get_node("GeneratedLaneMaterialOverlays").mesh) - 40.8 * 3.5) < 0.002,
		"Disjoint ranges retain both strips")
	_check(road.get_lane_overlay_stats().rows_rebuilt + road.get_lane_overlay_stats().rows_reused < 60,
		"Disjoint ranges do not sample the gap")
	_check(road.get_terrain_surface_revision() == revision, "Material edits preserve final-road revision")
	var original := _bytes(road.get_node("GeneratedLaneMaterialOverlays").mesh)
	road.clear_source_generation_cache()
	road.regenerate()
	_check(_bytes(road.get_node("GeneratedLaneMaterialOverlays").mesh) == original, "Forced full regeneration matches optimized overlays")
	_check(road.get_terrain_surface_revision() > revision, "Explicit cache clear forces topology refresh")
	revision = road.get_terrain_surface_revision()
	path.point_lanes_right = PackedInt32Array([1, 1])
	road.markings_line_color = Color.RED
	road.regenerate()
	_check(road.get_terrain_surface_revision() > revision, "Unapplied lane edit plus paint edit cannot reuse stale topology")
	# A real worker holds the old snapshots until cancelled/joined.
	path.outer_wall_height = 0.3
	road.threaded_generation_enabled = true
	road.regenerate()
	_check(road._is_generation_thread_active(), "Fixture starts a worker")
	road.markings_lane_style = MARKINGS.DOUBLE_SOLID
	road.regenerate()
	var deadline := Time.get_ticks_msec() + 10000
	while road._is_generation_thread_active() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not road._is_generation_thread_active() and road._output_ready, "Cancelled worker completes newest generation")
	_check_native_paint(road)
	road.free()
	print("APPEARANCE OPTIMIZATION %s checks=%d local_blocks=%d material_rows=%d" %
		["FAIL" if failed else "PASS", checks, stats.blocks_rebuilt, overlay_stats.rows_rebuilt])
	quit(1 if failed else 0)

func _check_native_paint(road: Node) -> void:
	var builder := MARKINGS.new()
	builder.cache_enabled = false
	builder.configure(road)
	var surface: Dictionary = road.get_terrain_surface_data()
	var mesh: Mesh = builder.build(surface.vertices, road._marking_rows, road._marking_exclusions,
		road._lateral_join.marking_cuts, surface.lane_indices)
	var actual := road.get_node_or_null("GeneratedRoadMarkings")
	_check(_bytes(mesh) == (_bytes(actual.mesh) if actual != null else var_to_bytes([])), "Incremental range paint matches uncached arrays")

func _area(mesh: Mesh) -> float:
	var area := 0.0
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var ids: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in range(0, ids.size(), 3):
			area += (v[ids[i + 1]] - v[ids[i]]).cross(v[ids[i + 2]] - v[ids[i]]).length() * 0.5
	return area

func _bytes(mesh: Mesh) -> PackedByteArray:
	var arrays: Array = []
	for surface in range(mesh.get_surface_count()):
		arrays.append(mesh.surface_get_arrays(surface))
	return var_to_bytes(arrays)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error(label)
