extends SceneTree
const ROAD = preload("../addons/scripts/spline_road/road_network_creator.gd")
const PROFILE = preload("../addons/scripts/spline_road/spline_path_profile.gd")
const REFERENCE = preload("./fixtures/road_lane_overlay_reference.gd")
class SmallCache extends "../addons/scripts/spline_road/road_lane_overlay_cache.gd":
	func _entry_limit() -> int: return 2
class TinyCache extends "../addons/scripts/spline_road/road_lane_overlay_cache.gd":
	func _byte_limit() -> int: return 32
class DynamicPath extends Path3D:
	var width := 8.0
	var calls := 0
	func get_width_at_offset(_distance: float) -> float:
		calls += 1
		return width
var road := ROAD.new()
var reference := REFERENCE.new()
var failed := false
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for node in [road, reference]:
		node.generate_in_editor = false
		node.auto_regenerate_in_editor = false
		node.threaded_generation_enabled = false
		node.debug_generation_logs = false
		root.add_child(node)
	road.incremental_generation_enabled = true
	road.sample_step = 2
	road.road_orientation_mode = 1
	var red := StandardMaterial3D.new()
	red.albedo_color = Color.RED
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color.BLUE
	road.left_lane_material_overrides.assign([red])
	road.right_lane_material_overrides.assign([blue, red])
	for p in range(3):
		var path := PROFILE.new()
		path.name = "Route" + str(p)
		path.show_width_preview = false
		path.curve = Curve3D.new()
		for point in range(9):
			path.curve.add_point(Vector3(p * 100, 0, point * 64))
		path.lane_profile_enabled = true
		path.default_lanes_left = 1
		path.default_lanes_right = 2
		road.add_child(path)
		road.source_paths.append(NodePath(path.name))
	_compare("cold")
	var warm := _compare("warm")
	_check(road.get_lane_overlay_stats().rows_rebuilt == 0, "warm retains every lane row")
	warm.clear_surfaces()
	_compare("consumer mesh mutation")
	var path: Path3D = road.get_node("Route0")
	for edit in range(5):
		path.curve.set_point_position(8, Vector3(0.2 * (edit + 1), 0.1 * (edit + 1), 512))
		_compare("local curve edit " + str(edit))
		var stats: Dictionary = road.get_lane_overlay_stats()
		_check(stats.blocks_reused > stats.blocks_rebuilt and stats.blocks_rebuilt > 0,
			"local edit preserves most lane row blocks")
	for mode in range(3):
		road.road_orientation_mode = mode
		path.curve.set_point_tilt(3, 0.27)
		_compare("orientation " + str(mode))
		_compare("warm orientation " + str(mode))
	road.transform = Transform3D(Basis.from_euler(Vector3(0.12, 0.3, -0.08)).scaled(Vector3(-1.2, 0.8, 1.3)), Vector3(12, 4, -8))
	_compare("mirrored nonuniform road transform")
	path.scale = Vector3(0.9, 1.1, 1.0)
	_compare("path transform")
	path.point_lanes_right = PackedInt32Array([2, 2, 1, 3, 2, 1, 0, 2, 2])
	path.point_lane_widths = PackedFloat32Array([3, 3, 3.5, 4, 3, 3, 3, 3, 3])
	var easing := Curve.new()
	easing.add_point(Vector2.ZERO)
	easing.add_point(Vector2.ONE)
	path.point_lane_transition_curves.assign([easing, easing, easing])
	_compare("asymmetric changing lane counts and widths")
	easing.set_point_right_tangent(0, 2.5)
	_compare("in-place easing edit")
	path.lane_profile_enabled = false
	path.point_widths = PackedFloat32Array([8, 9, 10, 11, 9, 8, 10, 8, 9])
	_compare("legacy nonuniform widths")
	path.point_lane_widths[2] += 0.4
	_compare("disabled lane profile still supplies overlay lane width")
	road.invert_faces = not road.invert_faces
	_compare("winding")
	_check(road.get_lane_overlay_stats().rows_rebuilt == 0, "winding reuses rows and rebuilds indices")
	road.lane_material_overlay_lift += 0.003
	_compare("lift")
	road.uv_length_scale += 0.1
	_compare("UV scale")
	road.y_offset += 0.3
	_compare("vertical offset")
	road.sample_step = 1.7
	_compare("sampling step")
	var replacement := StandardMaterial3D.new()
	road.right_lane_material_overrides[0] = replacement
	_compare("material replacement")
	_check(road.get_lane_overlay_stats().rows_rebuilt == 0, "material replacement retains geometry")
	replacement.albedo_color = Color.GREEN
	_compare("material mutation")
	road.right_lane_material_overrides.assign([null, red, blue])
	_compare("sparse material slots")
	road.source_paths.reverse()
	_compare("path reorder")
	_check(road.get_lane_overlay_stats().rows_rebuilt == 0, "path reorder only rebases output indices")
	road.source_paths.remove_at(0)
	_compare("removed source")
	var dynamic := DynamicPath.new()
	dynamic.name = "Dynamic"
	dynamic.curve = path.curve.duplicate(true)
	road.add_child(dynamic)
	road.source_paths.append(NodePath("Dynamic"))
	_compare("custom callback path")
	var calls := dynamic.calls
	dynamic.width = 12
	_compare("custom callback path changed")
	_check(dynamic.calls > calls and road.get_lane_overlay_stats().paths_bypassed > 0,
		"custom paths retain native callback execution")
	for bounded in [SmallCache.new(), TinyCache.new()]:
		road._lane_overlay_cache = bounded
		_compare("capacity cold")
		_compare("capacity warm")
		_check(road.get_lane_overlay_stats().capacity_bypasses > 0, "bounded cache bypasses safely")
	road.clear_source_generation_cache()
	_check(road._lane_overlay_cache._entries.is_empty(), "public clear releases overlay rows")
	road.incremental_generation_enabled = false
	_compare("disabled incremental")
	_check(road._lane_overlay_cache._entries.is_empty(), "disabled mode releases rows")
	road.incremental_generation_enabled = true
	road.left_lane_material_overrides.clear()
	road.right_lane_material_overrides.clear()
	_compare("no materials")
	_check(road._lane_overlay_cache._entries.is_empty(), "empty overlay releases rows")
	road.free()
	reference.free()
	print("LANE_OVERLAY_CACHE_%s checks=%d" % ["FAILED" if failed else "OK", checks])
	quit(1 if failed else 0)


func _compare(label: String) -> ArrayMesh:
	_copy(road, reference)
	reference.uv_length_scale = road.uv_length_scale
	reference.transform = road.transform
	reference.incremental_generation_enabled = false
	# Use the exact same live source inputs. Cloning a profile invokes _ready's
	# synchronization, which can legitimately change raw legacy lane storage.
	reference.source_paths = []
	for np: NodePath in road.source_paths:
		reference.source_paths.append(road.get_node(np).get_path())
	road._mesh_builder.configure(road)
	reference._mesh_builder.configure(reference)
	var actual: ArrayMesh = road._build_lane_material_overlay_mesh()
	var expected: ArrayMesh = reference._build_lane_material_overlay_mesh()
	_check(_snapshot(actual) == _snapshot(expected), "frozen native arrays/material routing: " + label)
	_check(road.get_lane_overlay_stats().payload_bytes <= road._lane_overlay_cache._byte_limit(), "retained payload bound: " + label)
	return actual


func _copy(source: Node, target: Node) -> void:
	for property in source.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(property.usage) & PROPERTY_USAGE_STORAGE:
			if target.get(property.name) != source.get(property.name):
				target.set(property.name, source.get(property.name))
	if source is DynamicPath:
		target.width = source.width


func _snapshot(mesh: ArrayMesh) -> Array:
	var result: Array = []
	if mesh == null:
		return result
	for index in range(mesh.get_surface_count()):
		result.append([var_to_bytes(mesh.surface_get_arrays(index)), mesh.surface_get_material(index)])
	return result


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(label)
