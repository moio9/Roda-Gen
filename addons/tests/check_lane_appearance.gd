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
	road.generate_in_editor = false
	road.threaded_generation_enabled = false
	road.debug_generation_logs = false
	road.sample_step = 5.0
	road.adaptive_sampling_enabled = false
	road.incremental_generation_enabled = true
	road.markings_enabled = true
	road.markings_center_style = MARKINGS.OFF
	road.markings_lane_style = MARKINGS.OFF
	road.markings_edge_style = MARKINGS.OFF
	road.markings_hatching_enabled = false
	var path := _path()
	road.add_child(path)
	root.add_child(road)
	var rule := APPEARANCE.new()
	rule.start_offset = 7.3
	rule.end_offset = 22.7
	rule.inner_line_style = MARKINGS.SOLID
	path.lane_appearance_overrides.assign([rule])
	road.regenerate()
	var mesh := _paint(road)
	_check(_covers(mesh, Vector2(3.5, 8.1)), "Selected right lane's inner line is painted")
	_check(not _covers(mesh, Vector2(-3.5, 8.1)), "Opposite side stays unchanged")
	_check(not _covers(mesh, Vector2(3.5, 7.2)) and not _covers(mesh, Vector2(3.5, 22.8)), "Sub-row range bounds are exact")
	_check(absf(_area(mesh) - 15.4 * road.markings_line_width) < 0.001, "Separator drawn exactly once")
	var old_signature: String = road._build_signature()
	rule.inner_line_style = MARKINGS.DASHED
	_check(old_signature != road._build_signature(), "In-place resource changes invalidate road signature")
	road.markings_dash_length = 3.0
	road.markings_dash_gap = 4.0
	road.regenerate()
	mesh = _paint(road)
	_check(_covers(mesh, Vector2(3.5, 8.0)) and not _covers(mesh, Vector2(3.5, 11.0)), "Local dash phase follows source distance")
	road.regenerate()
	_check(road.get_marking_stats().blocks_rebuilt == 0, "Unchanged rules reuse paint cache")
	# Two owners of one separator must still produce only one line.
	var inner := APPEARANCE.new()
	inner.lane = 1
	inner.outer_line_style = MARKINGS.DOUBLE_SOLID
	rule.inner_line_style = MARKINGS.SOLID
	path.lane_appearance_overrides.assign([inner, rule])
	road.regenerate()
	mesh = _paint(road)
	_check(_covers(mesh, Vector2(3.5, 9.0)) and not _covers(mesh, Vector2(3.62, 9.0)), "Outer lane's inner setting wins over neighbour's outer setting")
	_check(not _covers(mesh, Vector2(3.5, 4.0)) and _covers(mesh, Vector2(3.62, 4.0)), "Neighbour's double line remains outside override interval")
	var off := APPEARANCE.new()
	off.start_offset = 10.1
	off.end_offset = 12.3
	off.inner_line_style = MARKINGS.OFF
	path.lane_appearance_overrides.append(off)
	road.regenerate()
	_check(not _covers(_paint(road), Vector2(3.5, 11.0)), "Later explicit rule wins")
	off.inner_line_style = -1
	road.regenerate()
	_check(_covers(_paint(road), Vector2(3.5, 11.0)), "Inherit preserves earlier explicit rule")
	# Optional transverse paint stays within the selected lane and range.
	path.lane_appearance_overrides.assign([rule])
	rule.inner_line_style = MARKINGS.OFF
	rule.stop_line_at_start = true
	rule.stop_line_at_end = true
	road.regenerate()
	mesh = _paint(road)
	_check(_covers(mesh, Vector2(5, 7.5)) and _covers(mesh, Vector2(5, 22.5)), "Both optional transverse lines exist")
	_check(not _covers(mesh, Vector2(2, 7.5)) and not _covers(mesh, Vector2(-5, 7.5)), "Stop paint cannot spill into another lane")
	_check(not _covers(mesh, Vector2(5, 7.2)) and not _covers(mesh, Vector2(5, 22.8)), "Stop paint is inside selected interval")
	var inset: float = maxf(road.markings_edge_inset, road.markings_line_width * 0.5)
	_check(absf(_area(mesh) - 2.0 * rule.stop_line_width * (3.5 - 2 * inset)) < 0.001, "Stop bars cover exactly one lane")
	rule.end_offset = 7.5
	path.lane_appearance_overrides.append(rule.duplicate())
	road.regenerate()
	_check(absf(_area(_paint(road)) - 0.2 * (3.5 - 2 * inset)) < 0.001, "Overlapping start/end bars and duplicate rules do not double paint")
	path.lane_appearance_overrides.assign([rule])
	rule.end_offset = 0.0
	road.regenerate()
	_check(_covers(_paint(road), Vector2(5, 39.8)), "Zero end offset puts stop bar at source end")
	rule.lane = 3
	road.regenerate()
	_check(_area(_paint(road)) < 0.00001, "Missing lane emits no phantom stop bar")
	rule.lane = 2
	rule.end_offset = 22.7
	# Use a second spatially separate path to check path-local ownership.
	var other := _path()
	other.position.x = 30.0
	road.add_child(other)
	road.regenerate()
	mesh = _paint(road)
	_check(_max_x(mesh) < 15.0, "Rules on one source do not paint another source")
	# Material intervals use distance, independent of texture scale.
	rule.stop_line_at_start = false
	rule.stop_line_at_end = false
	var blue := StandardMaterial3D.new()
	var red := StandardMaterial3D.new()
	var green := StandardMaterial3D.new()
	road.right_lane_material_overrides.assign([null, blue])
	rule.surface_material = red
	var nested := APPEARANCE.new()
	nested.start_offset = 10.1
	nested.end_offset = 12.3
	nested.surface_material = green
	path.lane_appearance_overrides.append(nested)
	for scale_ in [0.0, 0.37]:
		road.uv_length_scale = scale_
		road.regenerate()
		var overlay: Mesh = road.get_node("GeneratedLaneMaterialOverlays").mesh
		var areas := _material_areas(overlay)
		_check(absf(float(areas.get(red, 0.0)) - (15.4 - 2.2) * 3.5) < 0.002, "Local material covers exact range, UV scale %s" % scale_)
		_check(absf(float(areas.get(green, 0.0)) - 2.2 * 3.5) < 0.002, "Later local material wins without duplicate overlay")
		_check(absf(float(areas.get(blue, 0.0)) - (80.0 - 15.4) * 3.5) < 0.002, "Global material survives outside range and on second path")
		_check(_material_bounds(overlay, red, 7.3, 22.7) and _material_bounds(overlay, green, 10.1, 12.3), "Material boundaries do not snap to sample rows")
	road.right_lane_material_overrides.clear()
	road.regenerate()
	_check(_material_areas(road.get_node("GeneratedLaneMaterialOverlays").mesh).size() == 2, "Local material works without network material overrides")
	# Builder captures rules before work; later Inspector edits cannot mutate that snapshot.
	rule.inner_line_style = MARKINGS.SOLID
	road.regenerate()
	road.threaded_generation_enabled = true
	road.regenerate()
	rule.inner_line_style = MARKINGS.OFF
	_check(road._marking_builder._path_appearances[0][0].inner_line_style == MARKINGS.SOLID, "Pending worker keeps captured lane rules")
	road.threaded_generation_enabled = false
	road.regenerate()
	var deadline := Time.get_ticks_msec() + 10000
	while road._is_generation_thread_active() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not road._is_generation_thread_active(), "Worker joins before queued regeneration")
	_check(road._marking_builder._path_appearances[0][0].inner_line_style == MARKINGS.OFF, "Queued generation captures updated lane rules")
	# A banked demo also exercises entering/leaving lanes, hatching and baking.
	road.free()
	await _check_demo()
	print("LANE APPEARANCE %s checks=%d" % ["FAIL" if failed else "PASS", checks])
	quit(1 if failed else 0)

func _check_demo() -> void:
	var scene: Node = load("res://addons/scenes/road_markings_demo.tscn").instantiate()
	root.add_child(scene)
	var road: Node = scene.get_node("Road")
	var path: Path3D = road.get_node("Route")
	var rule := APPEARANCE.new()
	rule.transition_hatching = 0
	path.lane_appearance_overrides.assign([rule])
	road.regenerate()
	_check(road.get_marking_stats().hatch_triangles == 0, "Per-lane hatching off removes entry and exit hatching")
	road.markings_hatching_enabled = false
	rule.transition_hatching = 1
	road.regenerate()
	_check(road.get_marking_stats().hatch_triangles > 0, "Per-lane hatching on works with global hatching off")
	rule.start_offset = 7.3
	rule.end_offset = 22.7
	rule.transition_hatching = 0
	road.markings_center_style = MARKINGS.OFF
	road.markings_lane_style = MARKINGS.OFF
	road.markings_edge_style = MARKINGS.OFF
	rule.inner_line_style = MARKINGS.SOLID
	rule.stop_line_at_end = true
	road.regenerate()
	var outside := false
	var paint := _paint(road)
	for surface in range(paint.get_surface_count()):
		for uv: Vector2 in paint.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]:
			outside = outside or uv.y < 7.2999 or uv.y > 22.7001 or uv.x < 3.4
	_check(not outside, "Banked partial lane paint respects exact range and side")
	rule.end_offset = 0
	rule.outer_line_style = MARKINGS.SOLID
	road.regenerate()
	var cached := _mesh_bytes(_paint(road))
	road.output_mode = 1
	road.regenerate()
	_check(cached == _mesh_bytes(_paint(road)), "Chunk output preserves local paint")
	var filename := "/tmp/roda-lane-appearance-baked-%d.tscn" % Time.get_ticks_usec()
	_check(road.bake_runtime_scene(filename) == OK, "Local paint can be baked")
	var baked: Node = load(filename).instantiate()
	_check(cached == _mesh_bytes(_paint(baked)), "Baked paint retains lane-specific styles")
	baked.free()
	# Resource serialization retains explicit off (0), inherit (-1), and ranges.
	var packed := PackedScene.new()
	path.owner = scene
	road.owner = scene
	_check(packed.pack(scene) == OK, "Appearance resource packs with authored path")
	var restored := packed.instantiate()
	var restored_rule: Resource = restored.get_node("Road/Route").lane_appearance_overrides[0]
	_check(restored_rule.stop_line_at_end and restored_rule.transition_hatching == 0 and restored_rule.start_offset == 7.3, "Appearance properties survive scene serialization")
	restored.free()
	scene.free()

func _path() -> Path3D:
	var path := PROFILE.new()
	path.show_width_preview = false
	path.lane_profile_enabled = true
	path.default_lanes_left = 2
	path.default_lanes_right = 2
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -40.0 / 3.0))
	path.curve.add_point(Vector3(0, 0, -40), Vector3(0, 0, 40.0 / 3.0))
	return path

func _paint(road: Node) -> Mesh:
	var node := road.get_node_or_null(MARKINGS.NODE_NAME)
	return node.mesh if node != null else ArrayMesh.new()

func _covers(mesh: Mesh, point: Vector2) -> bool:
	for surface in range(mesh.get_surface_count()):
		var uv: PackedVector2Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]
		for i in range(0, uv.size(), 3):
			if Geometry2D.is_point_in_polygon(point, PackedVector2Array([uv[i], uv[i + 1], uv[i + 2]])):
				return true
	return false

func _area(mesh: Mesh) -> float:
	var area := 0.0
	for surface in range(mesh.get_surface_count()):
		var uv: PackedVector2Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]
		for i in range(0, uv.size(), 3):
			area += absf((uv[i + 1] - uv[i]).cross(uv[i + 2] - uv[i])) * 0.5
	return area

func _max_x(mesh: Mesh) -> float:
	var value := -INF
	for surface in range(mesh.get_surface_count()):
		for p: Vector3 in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			value = maxf(value, p.x)
	return value

func _material_areas(mesh: Mesh) -> Dictionary:
	var result := {}
	for surface in range(mesh.get_surface_count()):
		var arr := mesh.surface_get_arrays(surface)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ids: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var area := 0.0
		for i in range(0, ids.size(), 3):
			area += (v[ids[i + 1]] - v[ids[i]]).cross(v[ids[i + 2]] - v[ids[i]]).length() * 0.5
		result[mesh.surface_get_material(surface)] = area
	return result

func _material_bounds(mesh: Mesh, material: Material, start: float, end: float) -> bool:
	for surface in range(mesh.get_surface_count()):
		if mesh.surface_get_material(surface) != material:
			continue
		for p: Vector3 in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			if p.x > 15.0 or -p.z < start - 0.001 or -p.z > end + 0.001:
				return false
	return true

func _mesh_bytes(mesh: Mesh) -> PackedByteArray:
	var arrays := []
	for surface in range(mesh.get_surface_count()):
		arrays.append(mesh.surface_get_arrays(surface))
	return var_to_bytes(arrays)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error(label)
