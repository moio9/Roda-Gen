@tool
extends Node3D
class_name SplinePropArray3D

@export_group("Sources")
@export var source_paths: Array[NodePath] = []
## Optional RoadNetworkCreator3D used to match banked road shoulders and sidewalks.
@export var road_network_source: NodePath
@export var include_terrain_influence_paths := false

@export_group("Content")
@export var item_scene: PackedScene
@export var item_mesh: Mesh
@export var item_material_override: Material
@export var mesh_cast_shadows := GeometryInstance3D.SHADOW_CASTING_SETTING_ON

@export_group("Rendering")
## Individual nodes can use Forward+ automatic instancing when mesh and material are shared.
## MultiMesh batches Item Mesh only. Item Scene keeps its nodes, scripts and collisions.
@export_enum("Individual Nodes", "MultiMesh (Item Mesh Only)") var render_mode := 0: set = _set_render_mode
## World-space cell size for MultiMesh visibility culling. Smaller cells create more batches.
@export_range(1.0, 1000.0, 1.0, "or_greater", "suffix:m") var multimesh_chunk_size := 100.0

@export_group("Placement")
@export_enum("Center", "Left Edge", "Right Edge", "Both Edges") var placement_mode := 0
## Fit each rigid module between consecutive samples of the chosen road edge.
## Measures the model after Custom Transform rotation/scale; its length must run along local Z.
## Spacing controls sample intervals. Randomization is ignored to keep shared endpoints connected.
@export var fit_segments_to_path := false
## Connected edge segments follow the final welded road outline, including their thickness.
## Uses Road Network Source and Edge Uses Total Road Width; blocked junction spans stay open.
@export var follow_generated_road_edge := true
@export_range(0.1, 200.0, 0.1, "or_greater", "suffix:m") var spacing := 6.0
@export_range(0.0, 200.0, 0.1, "or_greater", "suffix:m") var start_offset := 0.0
@export_range(0.0, 200.0, 0.1, "or_greater", "suffix:m") var end_trim := 0.0
@export_range(0.0, 50.0, 0.1, "or_greater", "suffix:m") var default_lane_width := 6.0
@export var edge_uses_total_road_width := true
@export_range(-50.0, 50.0, 0.1, "or_greater", "or_less", "suffix:m") var lateral_offset := 0.0
@export_range(-50.0, 50.0, 0.1, "or_greater", "or_less", "suffix:m") var outward_offset := 0.0
@export_range(-50.0, 50.0, 0.1, "or_greater", "or_less", "suffix:m") var vertical_offset := 0.0
@export_subgroup("Ground Snap")
@export var snap_to_ground_enabled := false: set = _set_snap_to_ground_enabled
## Optional TerrainTopologyBuilder3D. When empty, the nearest compatible sibling is used.
@export var terrain_height_source: NodePath
@export_range(0.0, 89.0, 0.1, "suffix:deg") var snap_to_ground_max_angle_deg := 45.0
@export_enum("Strict", "Clamp to Last Valid") var snap_to_ground_slope_mode := 0
@export_range(-50.0, 50.0, 0.1, "or_greater", "or_less", "suffix:m") var snap_to_ground_y_offset := 0.0
@export_group("Intersection Avoidance")
@export var avoid_intersections := true
@export var avoid_own_path_endpoints := true
@export var avoid_other_path_endpoints := true
@export var avoid_intersections_in_center_mode := false
@export_range(0.0, 100.0, 0.1, "or_greater", "suffix:m") var intersection_clear_radius := 4.0
@export_group("Road Surface Avoidance")
## Skip whole props/fence segments whose transformed model base overlaps final asphalt.
## Uses Road Network Source, or the source paths' road ancestors when empty.
@export var avoid_road_surface := false
## Maximum vertical gap between the prop base and asphalt. Keeps separate bridge levels independent.
@export_range(0.01, 10.0, 0.05, "or_greater", "suffix:m") var road_avoidance_height_tolerance := 0.75
@export_group("Distance Ranges")
@export_enum("Disabled", "Only In Ranges", "Exclude Ranges") var ranges_mode := 1
@export_enum("Manual Array", "Span Nodes", "Manual + Span Nodes") var range_source_mode := 1
@export var distance_ranges := PackedVector2Array()

@export_group("Orientation")
@export var align_with_path := true
@export var align_with_curve_up := true
@export_range(0.01, 5.0, 0.01, "or_greater", "suffix:m") var tangent_sample_distance := 0.2
@export_range(-180.0, 180.0, 0.1, "or_greater", "or_less", "suffix:deg") var yaw_offset_degrees := 0.0
var _custom_transform := Transform3D.IDENTITY
var _custom_rotation_degrees := Vector3.ZERO
var _custom_scale := Vector3.ONE
## Keep the full transform as scene storage, including transforms saved by older versions.
@export_storage var custom_transform: Transform3D:
	get:
		return _custom_transform
	set(value):
		_custom_transform = value
		_custom_scale = value.basis.get_scale()
		if value.basis.determinant() != 0.0:
			_custom_rotation_degrees = value.basis.get_rotation_quaternion().get_euler() * (180.0 / PI)

@export_group("Custom Transform", "custom_")
## Offset in metres along the aligned prop's local X/Y/Z axes. Applied to every instance.
@export var custom_position: Vector3:
	get:
		return _custom_transform.origin
	set(value):
		_custom_transform.origin = value
## Additional local rotation in degrees, after spline alignment. Uses Node3D's YXZ order.
@export var custom_rotation_degrees: Vector3:
	get:
		return _custom_rotation_degrees
	set(value):
		_custom_rotation_degrees = value
		_update_custom_transform_basis()
## Local X/Y/Z size multipliers for every prop. Use the link icon for uniform scaling.
@export var custom_scale: Vector3:
	get:
		return _custom_scale
	set(value):
		_custom_scale = value
		_update_custom_transform_basis()

@export_group("Randomization")
@export var random_seed := 1337
@export var randomize_seed_each_regenerate := false
@export_range(0.0, 50.0, 0.01, "or_greater", "suffix:m") var longitudinal_jitter := 0.0
@export_range(0.0, 50.0, 0.01, "or_greater", "suffix:m") var lateral_jitter := 0.0
@export_range(0.0, 50.0, 0.01, "or_greater", "suffix:m") var vertical_jitter := 0.0
@export_range(0.0, 180.0, 0.1, "or_greater", "suffix:deg") var yaw_jitter_degrees := 0.0
@export_range(0.01, 20.0, 0.01, "or_greater") var random_uniform_scale_min := 1.0
@export_range(0.01, 20.0, 0.01, "or_greater") var random_uniform_scale_max := 1.0

@export_group("Workflow")
@export var generate_in_editor := true
@export var auto_regenerate_in_editor := true
@export var regenerate_while_dragging_handles := false
@export var persist_generated_in_scene := false
@export var use_parent_as_generated_root := false: set = _set_use_parent_as_generated_root
@export_tool_button("Regenerate Props") var regenerate_action := _regenerate_from_button
@export_tool_button("Clear Generated") var clear_generated_action := _clear_generated_from_button
@export var debug_logs := false

const GENERATED_ROOT_NAME := "GeneratedSplineProps"
const GENERATED_OWNER_META := "spline_prop_array_owner_path"
# Keep this relative to the addon script, so the addon may be installed under
# any directory name in a host project.
const PROP_SPAN_SCRIPT: Script = preload("./spline_prop_span.gd")
const PLACEMENT_CENTER := 0
const PLACEMENT_LEFT := 1
const PLACEMENT_RIGHT := 2
const PLACEMENT_BOTH := 3
const RANGE_SOURCE_MANUAL := 0
const RANGE_SOURCE_SPANS := 1
const RANGE_SOURCE_MANUAL_AND_SPANS := 2
const GROUND_SNAP_SLOPE_STRICT := 0
const GROUND_SNAP_SLOPE_CLAMP_LAST_VALID := 1
const RENDER_MULTIMESH := 1

var _last_signature := ""
var _warned_non_spatial_scene := false
var _warned_non_node3d_parent := false
var _terrain_height_source_cache: Node
var _terrain_regeneration_pending := false
var _connected_terrain_source: Node
var _placement_cache := preload("./prop_placement_cache.gd").new()
var _output_cache := preload("./prop_output_cache.gd").new()
var _segment_fitter := preload("./prop_segment_fitter.gd").new()
var _road_avoidance := preload("./prop_road_avoidance.gd").new()
var _road_avoidance_pending := false


## Source placement and native mesh output reuse. Idle built-in terrain can be
## revalidated; Item Scene and unknown ground providers keep their lifecycle.
func get_placement_rebuild_stats() -> Dictionary:
	var result: Dictionary = _placement_cache.stats.duplicate(true)
	result.merge(_output_cache.stats)
	result["pending_terrain"] = _terrain_regeneration_pending
	result["pending_road"] = _road_avoidance_pending
	result["road_surface_rejected"] = _road_avoidance.rejected
	return result


func _ready() -> void:
	set_process(true)
	_ensure_default_span()
	if _can_generate():
		regenerate()


func _ensure_default_span() -> void:
	var parent_path := get_parent() as Path3D
	if source_paths.is_empty() and parent_path != null:
		source_paths = [NodePath("..")]
	# A full-length include span preserves the default placement. Do not turn a
	# manual range into full coverage, or exclude the whole path in Exclude mode.
	if ranges_mode != 1 or range_source_mode != RANGE_SOURCE_SPANS:
		return
	for child in get_children():
		if child != null and child.has_method("is_spline_prop_span") and bool(child.call("is_spline_prop_span")):
			return
	if source_paths.size() != 1 or source_paths[0].is_empty():
		return
	var path := get_node_or_null(source_paths[0]) as Path3D
	if path == null or path.curve == null or path.curve.point_count < 2:
		return
	if _path_is_terrain_influence_only(path) and not include_terrain_influence_paths:
		return

	var span := PROP_SPAN_SCRIPT.new() as Node3D
	if span == null:
		return
	span.name = "PropSpan"
	# The span is one level below this array, including when Source Paths points
	# to a sibling road instead of the array being a child of that road's path.
	span.set("target_path", NodePath("../" + str(get_path_to(path))))
	span.set("start_offset", 0.0)
	span.set("end_offset", maxf(0.0, path.curve.get_baked_length()))
	add_child(span)
	_assign_editor_owner(span)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		# Source Paths is usually assigned after the new node has entered the tree.
		_ensure_default_span()
	if _road_avoidance_pending:
		if not _can_generate() or (avoid_road_surface and _road_avoidance.pending(self)):
			return
		regenerate()
		return
	if _terrain_regeneration_pending:
		if not _can_generate():
			return
		var provider := _resolve_terrain_height_source()
		if snap_to_ground_enabled and _terrain_source_pending(provider):
			return
		regenerate()
		return
	if not Engine.is_editor_hint():
		if avoid_road_surface and _road_avoidance.changed(self) and _can_generate():
			regenerate()
			return
		if fit_segments_to_path and (item_scene != null or item_mesh != null) and _segment_fitter.road_changed(self) and _can_generate():
			regenerate()
		return
	if not auto_regenerate_in_editor:
		return
	if not _can_generate():
		return
	if _should_defer_editor_regenerate():
		return

	var sig := _build_signature()
	if sig == _last_signature:
		return

	_last_signature = sig
	regenerate()


func _regenerate_from_button() -> void:
	if _can_generate():
		regenerate()


func _set_use_parent_as_generated_root(value: bool) -> void:
	use_parent_as_generated_root = value
	_last_signature = ""
	if not is_inside_tree():
		return
	if _can_generate():
		regenerate()
	else:
		_clear_all_generated_nodes()


func _clear_generated_from_button() -> void:
	_terrain_regeneration_pending = false
	_bind_terrain_source(null)
	_clear_all_generated_nodes()
	_placement_cache.clear()
	_last_signature = _build_signature()


func _set_snap_to_ground_enabled(value: bool) -> void:
	snap_to_ground_enabled = value
	if Engine.is_editor_hint():
		notify_property_list_changed()


func _set_render_mode(value: int) -> void:
	render_mode = value
	if Engine.is_editor_hint():
		notify_property_list_changed()
		update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	if avoid_road_surface and _road_avoidance.sources(self).is_empty():
		return PackedStringArray(["Avoid Road Surface needs a Road Network Source, or source paths under a RoadNetworkCreator3D."])
	if render_mode == RENDER_MULTIMESH and item_scene != null:
		return PackedStringArray([
			"MultiMesh applies to Item Mesh only. Item Scene takes priority and is generated as individual nodes. Clear Item Scene and assign Item Mesh to use MultiMesh.",
		])
	return PackedStringArray()


func _validate_property(property: Dictionary) -> void:
	if property.name in ["custom_position", "custom_rotation_degrees", "custom_scale"]:
		# Inspector aliases share one stored transform, just like Node3D's controls.
		property.usage = PROPERTY_USAGE_EDITOR
		if property.name == "custom_position":
			property.hint = PROPERTY_HINT_RANGE
			property.hint_string = "-99999,99999,0.01,or_greater,or_less,hide_control,suffix:m"
		elif property.name == "custom_rotation_degrees":
			property.hint = PROPERTY_HINT_RANGE
			property.hint_string = "-360,360,0.1,or_greater,or_less,hide_control,suffix:°"
		else:
			property.hint = PROPERTY_HINT_LINK
	if property.name == "multimesh_chunk_size" and render_mode != RENDER_MULTIMESH:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "terrain_height_source"
		or property.name == "snap_to_ground_max_angle_deg"
		or property.name == "snap_to_ground_slope_mode"
		or property.name == "snap_to_ground_y_offset"
	) and not snap_to_ground_enabled:
		property.usage = PROPERTY_USAGE_NO_EDITOR


func _update_custom_transform_basis() -> void:
	_custom_transform.basis = Basis.from_euler(_custom_rotation_degrees * (PI / 180.0)).scaled_local(_custom_scale)


func _property_can_revert(property: StringName) -> bool:
	return property in [&"custom_position", &"custom_rotation_degrees", &"custom_scale"]


func _property_get_revert(property: StringName) -> Variant:
	if property == &"custom_scale":
		return Vector3.ONE
	if property in [&"custom_position", &"custom_rotation_degrees"]:
		return Vector3.ZERO
	return null


func regenerate() -> void:
	if not _can_generate():
		return
	_ensure_default_span()
	_terrain_regeneration_pending = false
	_road_avoidance_pending = false
	if Engine.is_editor_hint():
		update_configuration_warnings()
	if item_scene == null and item_mesh == null:
		_road_avoidance.clear(self)
		_bind_terrain_source(null)
		_debug_log("regenerate skipped: set item_scene or item_mesh first.")
		_clear_all_generated_nodes()
		_placement_cache.clear()
		return
	_terrain_height_source_cache = _resolve_terrain_height_source()
	_bind_terrain_source(_terrain_height_source_cache if snap_to_ground_enabled else null)

	var paths := _resolve_paths()
	if paths.is_empty():
		_road_avoidance.clear(self)
		_bind_terrain_source(null)
		_debug_log("regenerate skipped: no valid Path3D sources.")
		_clear_all_generated_nodes()
		_placement_cache.clear()
		return

	if snap_to_ground_enabled and _terrain_source_pending(_terrain_height_source_cache):
		# Preserve existing nodes, scene lifecycles, batches and RNG while the
		# provider is unavailable. Retry the latest requested configuration on idle.
		_terrain_regeneration_pending = true
		return
	if avoid_road_surface and _road_avoidance.pending(self):
		_road_avoidance_pending = true
		return
	_road_avoidance.prepare(self)
	if fit_segments_to_path and not _segment_fitter.prepare(self):
		push_warning("SplinePropArray3D: connected segments need a mesh with nonzero length along Z after Custom Transform.")
		_last_signature = _build_signature()
		return
	_placement_cache.begin_build(self)
	var root: Node3D = _output_cache.begin_build(self, _placement_cache.can_reuse_output(paths))

	var endpoint_zones := _collect_path_endpoint_zones(paths)
	var span_ranges_by_path := _collect_span_ranges_by_path(paths)
	var created_count := 0
	var rng := _create_rng()
	for path in paths:
		created_count += _scatter_path(path, root, rng, endpoint_zones, span_ranges_by_path)
	_output_cache.finish_build()
	_placement_cache.end_build(rng)

	if created_count <= 0:
		_debug_log("regenerate done: nothing placed.")
		_clear_all_generated_nodes()
	else:
		_debug_log("regenerate done: placed=%s paths=%s" % [created_count, paths.size()])
	_last_signature = _build_signature()


func _scatter_path(
	path: Path3D,
	parent_root: Node3D,
	rng: RandomNumberGenerator,
	endpoint_zones: Array,
	span_ranges_by_path: Dictionary
) -> int:
	if fit_segments_to_path:
		var placements: Array = _segment_fitter.placements(self, path, parent_root, endpoint_zones, span_ranges_by_path)
		var batches: Dictionary = {}
		var use_multimesh := render_mode == RENDER_MULTIMESH and item_scene == null and item_mesh != null
		var count := _emit_recorded_placements(path, parent_root, placements, use_multimesh, batches, 0)
		if use_multimesh:
			_create_multimesh_batches(path, parent_root, batches)
		_placement_cache.stats.placements_rebuilt += count
		_placement_cache.stats.paths_bypassed += 1
		_placement_cache.stats.bypass_reasons["connected_segments"] = _placement_cache.stats.bypass_reasons.get("connected_segments", 0) + 1
		return count
	var key := _placement_cache.key_for(path, parent_root, rng, endpoint_zones, span_ranges_by_path)
	var previous: Dictionary = {}
	if not key.is_empty():
		previous = _placement_cache.previous(path)
		if previous.get("key", PackedByteArray()) == key and _placement_cache.ground_matches(previous):
			var count := _replay_path_placements(path, parent_root, previous.placements)
			rng.state = previous.rng_after
			_placement_cache.stats.paths_reused += 1
			_placement_cache.stats.placements_reused += count
			for block: Dictionary in previous.get("blocks", []):
				_placement_cache.stats.blocks_reused += 1
				_placement_cache.stats.candidates_reused += block.candidate_count
			_placement_cache.retain(path, previous)
			return count
	var placements: Array = []
	var blocks: Array = []
	var reused_before: int = _placement_cache.stats.placements_reused
	var count := _scatter_path_uncached(path, parent_root, rng, endpoint_zones, span_ranges_by_path, placements,
		not key.is_empty(), previous.get("blocks", []), blocks)
	_placement_cache.stats.placements_rebuilt += count - (_placement_cache.stats.placements_reused - reused_before)
	if not key.is_empty():
		_placement_cache.stats.paths_rebuilt += 1
		_placement_cache.retain(path, {"key": key, "placements": placements, "rng_after": rng.state, "blocks": blocks})
	return count


func _scatter_path_uncached(
	path: Path3D,
	parent_root: Node3D,
	rng: RandomNumberGenerator,
	endpoint_zones: Array,
	span_ranges_by_path: Dictionary,
	recorded_placements: Array,
	record_placements: bool,
	previous_blocks: Array = [],
	recorded_blocks: Array = []
) -> int:
	if path == null or path.curve == null or path.curve.point_count < 2:
		return 0
	if _path_is_terrain_influence_only(path) and not include_terrain_influence_paths:
		return 0

	var curve := path.curve
	var length := curve.get_baked_length()
	if length <= 0.001:
		return 0

	var step := maxf(0.1, spacing)
	var begin := clampf(maxf(0.0, start_offset), 0.0, length)
	var end_dist := maxf(begin, length - maxf(0.0, end_trim))
	if end_dist - begin < 0.001:
		return 0

	var sides := _build_sides_for_mode()
	if sides.is_empty():
		return 0

	var path_to_world := path.global_transform
	var world_to_parent := parent_root.global_transform.affine_inverse()
	var dist := begin
	var loop_guard := 0
	var created_count := 0
	var has_last_valid_ground_y_by_side: Dictionary = {}
	var use_multimesh := render_mode == RENDER_MULTIMESH and item_scene == null and item_mesh != null
	var mesh_batches: Dictionary = {}
	# Reuse one Node3D to match individual-node scale decomposition, including
	# mirrored/non-uniform parent transforms, without allocating a node per prop.
	var use_transform_proxy: bool = use_multimesh or _output_cache.enabled
	var batch_transform_node := Node3D.new() if use_transform_proxy else null
	var block_context: Dictionary = {}
	var block: Dictionary = {}
	var block_placement_start := 0
	var block_distances := PackedFloat64Array()
	var block_endpoint_queries: Array = []
	var block_ground_queries: Array = []
	if record_placements:
		block_context = _placement_cache.path_context(path, parent_root, endpoint_zones,
			_build_effective_ranges(path, length, span_ranges_by_path), ranges_mode)

	while dist <= end_dist + 0.0001 and loop_guard < 200000:
		if record_placements and loop_guard % _placement_cache.BLOCK_CANDIDATES == 0:
			if not block.is_empty():
				recorded_blocks.append(_placement_cache.finish_block(path, block_context, block, block_distances,
					block_endpoint_queries, recorded_placements.slice(block_placement_start), rng,
					block_ground_queries, has_last_valid_ground_y_by_side))
			block = _placement_cache.open_block(path, block_context, previous_blocks,
				int(loop_guard / _placement_cache.BLOCK_CANDIDATES), dist, begin, end_dist, step,
				longitudinal_jitter, 200000 - loop_guard, rng, has_last_valid_ground_y_by_side)
			if block.has("placements"):
				var reused := _emit_recorded_placements(path, parent_root, block.placements, use_multimesh, mesh_batches, created_count)
				created_count += reused
				_placement_cache.stats.placements_reused += reused
				recorded_placements.append_array(block.placements)
				rng.state = block.rng_after
				has_last_valid_ground_y_by_side = block.get("ground_state_after", {}).duplicate()
				dist = block.next_dist
				loop_guard += block.candidate_count
				recorded_blocks.append(block)
				block = {}
				continue
			block_placement_start = recorded_placements.size()
			block_distances = PackedFloat64Array()
			block_endpoint_queries = []
			block_ground_queries = []
		loop_guard += 1
		_placement_cache.stats.sampling_steps += 1
		var d := dist + rng.randf_range(-longitudinal_jitter, longitudinal_jitter)
		d = clampf(d, begin, end_dist)
		if not _distance_allowed_by_ranges(path, d, length, span_ranges_by_path):
			dist += step
			continue
		if record_placements:
			block_distances.append(d)
		var center := path_to_world * curve.sample_baked(d, true)
		var tangent := _sample_curve_tangent_world(curve, path_to_world, d, length)
		var up := _sample_curve_up_world(curve, path_to_world, d)
		var right := up.cross(tangent).normalized()
		var road_frame := _get_road_surface_frame(path, d)
		if not road_frame.is_empty():
			center = road_frame.get("center", center)
			right = road_frame.get("right", right)
			up = road_frame.get("up", up)
			tangent = right.cross(up).normalized()
		if right.length() < 0.001:
			right = Vector3.RIGHT

		for side in sides:
			var side_offset := _compute_side_offset(path, d, length, side)
			side_offset += float(side) * outward_offset
			side_offset += lateral_offset
			side_offset += rng.randf_range(-lateral_jitter, lateral_jitter)

			var up_offset := vertical_offset + rng.randf_range(-vertical_jitter, vertical_jitter)
			var world_pos := center + right * side_offset + up * up_offset
			if snap_to_ground_enabled:
				_placement_cache.stats.ground_queries_sampled += 1
				var hit := _placement_cache.sample_ground(
					world_pos,
					clampf(snap_to_ground_max_angle_deg, 0.0, 89.0),
					snap_to_ground_y_offset
				)
				if record_placements:
					# Record missing/steep hits too: a newly accepted candidate
					# changes both per-side clamp state and subsequent RNG draws.
					block_ground_queries.append([world_pos, hit.duplicate(true)])
				var side_key := int(side)
				var has_last_valid := has_last_valid_ground_y_by_side.has(side_key)
				var last_valid_y := float(has_last_valid_ground_y_by_side.get(side_key, world_pos.y))
				if not bool(hit.get("hit", false)):
					continue
				else:
					if bool(hit.get("within_max_angle", false)):
						world_pos.y = float(hit.get("y", world_pos.y))
						has_last_valid_ground_y_by_side[side_key] = world_pos.y
					elif int(snap_to_ground_slope_mode) == GROUND_SNAP_SLOPE_CLAMP_LAST_VALID:
						if has_last_valid:
							world_pos.y = last_valid_y
						else:
							continue
					else:
						# Strict mode: discard props on slopes steeper than max angle.
						continue
			if record_placements and avoid_intersections:
				block_endpoint_queries.append([world_pos, side])
			if _point_blocked_by_intersection_zones(path, world_pos, side, endpoint_zones):
				continue

			var spawn_node := batch_transform_node if use_transform_proxy else _instantiate_spawn_node()
			if spawn_node == null:
				continue

			var basis := _build_spawn_basis(
				tangent,
				up,
				side,
				rng
			)
			var world_xform := Transform3D(basis, world_pos)
			spawn_node.transform = world_to_parent * world_xform * custom_transform

			var uniform_scale := _sample_uniform_scale(rng)
			if not is_equal_approx(uniform_scale, 1.0):
				var placed := spawn_node.transform
				spawn_node.transform = Transform3D(placed.basis.scaled(Vector3.ONE * uniform_scale), placed.origin)
			var final_world_pos := parent_root.global_transform * spawn_node.transform.origin
			if avoid_road_surface and _road_avoidance.blocked(parent_root.global_transform * spawn_node.transform, road_avoidance_height_tolerance):
				if not use_transform_proxy:
					spawn_node.free()
				continue
			if record_placements:
				recorded_placements.append([spawn_node.transform, final_world_pos])
			if use_multimesh:
				var cell_size := maxf(1.0, multimesh_chunk_size)
				var cell := Vector3i(
					floori(final_world_pos.x / cell_size),
					floori(final_world_pos.y / cell_size),
					floori(final_world_pos.z / cell_size)
				)
				if not mesh_batches.has(cell):
					mesh_batches[cell] = []
				mesh_batches[cell].append(spawn_node.transform)
			elif _output_cache.enabled:
				_output_cache.record_mesh(path, created_count, spawn_node.transform)
			else:
				spawn_node.name = "Prop_%s_%06d" % [path.name, created_count]
				spawn_node.set_meta(GENERATED_OWNER_META, str(get_path()))
				parent_root.add_child(spawn_node)
				_assign_generated_owner(spawn_node)
			created_count += 1

		dist += step

	if record_placements and not block.is_empty():
		recorded_blocks.append(_placement_cache.finish_block(path, block_context, block, block_distances,
			block_endpoint_queries, recorded_placements.slice(block_placement_start), rng,
			block_ground_queries, has_last_valid_ground_y_by_side))
	if use_transform_proxy:
		batch_transform_node.free()
	if use_multimesh:
		_create_multimesh_batches(path, parent_root, mesh_batches)
	return created_count


func _replay_path_placements(path: Path3D, parent_root: Node3D, placements: Array) -> int:
	var use_multimesh := render_mode == RENDER_MULTIMESH
	var batches: Dictionary = {}
	var count := _emit_recorded_placements(path, parent_root, placements, use_multimesh, batches, 0)
	if use_multimesh:
		_create_multimesh_batches(path, parent_root, batches)
	return count


func _emit_recorded_placements(path: Path3D, parent_root: Node3D, placements: Array,
		use_multimesh: bool, batches: Dictionary, start_count: int) -> int:
	var count := 0
	for placement: Array in placements:
		var transform_value: Transform3D = placement[0]
		if avoid_road_surface and _road_avoidance.blocked(parent_root.global_transform * transform_value, road_avoidance_height_tolerance):
			continue
		if use_multimesh:
			var world_pos: Vector3 = placement[1]
			var size := maxf(1.0, multimesh_chunk_size)
			var cell := Vector3i(floori(world_pos.x / size), floori(world_pos.y / size), floori(world_pos.z / size))
			if not batches.has(cell):
				batches[cell] = []
			batches[cell].append(transform_value)
		elif _output_cache.enabled:
			_output_cache.record_mesh(path, start_count + count, transform_value)
		else:
			var node := _instantiate_spawn_node()
			node.transform = transform_value
			node.name = "Prop_%s_%06d" % [path.name, start_count + count]
			node.set_meta(GENERATED_OWNER_META, str(get_path()))
			parent_root.add_child(node)
			_assign_generated_owner(node)
		count += 1
	return count


func _create_multimesh_batches(path: Path3D, parent_root: Node3D, batches: Dictionary) -> void:
	var mesh_bounds := item_mesh.get_aabb()
	for cell: Vector3i in batches:
		var transforms: Array = batches[cell]
		if _output_cache.enabled:
			_output_cache.record_batch(path, cell, transforms, mesh_bounds)
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = item_mesh
		multimesh.instance_count = transforms.size()
		var bounds := AABB()
		for index in range(transforms.size()):
			var instance_transform: Transform3D = transforms[index]
			multimesh.set_instance_transform(index, instance_transform)
			var instance_bounds := instance_transform * mesh_bounds
			bounds = instance_bounds if index == 0 else bounds.merge(instance_bounds)
		multimesh.custom_aabb = bounds

		var batch := MultiMeshInstance3D.new()
		batch.name = "Props_%s_%d_%d_%d" % [path.name, cell.x, cell.y, cell.z]
		batch.multimesh = multimesh
		batch.material_override = item_material_override
		batch.cast_shadow = mesh_cast_shadows
		batch.set_meta(GENERATED_OWNER_META, str(get_path()))
		parent_root.add_child(batch)
		_assign_generated_owner(batch)


func _get_road_surface_frame(path: Path3D, distance: float) -> Dictionary:
	if road_network_source.is_empty():
		return {}
	var road_network := get_node_or_null(road_network_source)
	if road_network == null or not road_network.has_method("get_path_surface_frame"):
		return {}
	var result = road_network.call("get_path_surface_frame", path, distance)
	return result if result is Dictionary else {}


func _build_spawn_basis(
	tangent: Vector3,
	up: Vector3,
	_side: int,
	rng: RandomNumberGenerator
) -> Basis:
	var t := tangent.normalized()
	if t.length() < 0.001:
		t = Vector3.FORWARD

	var u := up.normalized() if align_with_curve_up else Vector3.UP
	if u.length() < 0.001:
		u = Vector3.UP

	var basis := Basis.IDENTITY
	if align_with_path:
		# Local -Z follows the path. X must complete a right-handed basis;
		# using the road's lateral direction here reflected every aligned model.
		var right := t.cross(u).normalized()
		if right.length() < 0.001:
			right = t.cross(Vector3.UP).normalized()
		if right.length() < 0.001:
			right = t.cross(Vector3.RIGHT if absf(t.x) < 0.9 else Vector3.FORWARD).normalized()
		u = right.cross(t).normalized()
		if u.length() < 0.001:
			u = Vector3.UP
		basis = Basis(right, u, -t).orthonormalized()

	var yaw := yaw_offset_degrees
	yaw += rng.randf_range(-yaw_jitter_degrees, yaw_jitter_degrees)
	if absf(yaw) > 0.0001:
		var yaw_axis := u if align_with_curve_up else Vector3.UP
		if yaw_axis.length() < 0.001:
			yaw_axis = Vector3.UP
		basis = Basis(yaw_axis.normalized(), deg_to_rad(yaw)) * basis

	return basis.orthonormalized()


func _instantiate_spawn_node() -> Node3D:
	if item_scene != null:
		var n := item_scene.instantiate()
		if n is Node3D:
			return n as Node3D
		if not _warned_non_spatial_scene:
			push_warning("SplinePropArray3D: item_scene root must inherit Node3D.")
			_warned_non_spatial_scene = true
		if n != null:
			n.queue_free()
		return null

	if item_mesh == null:
		return null

	var mi := MeshInstance3D.new()
	mi.mesh = item_mesh
	mi.material_override = item_material_override
	mi.cast_shadow = mesh_cast_shadows
	return mi


func _sample_uniform_scale(rng: RandomNumberGenerator) -> float:
	var min_scale := maxf(0.01, minf(random_uniform_scale_min, random_uniform_scale_max))
	var max_scale := maxf(min_scale, maxf(random_uniform_scale_min, random_uniform_scale_max))
	if is_equal_approx(min_scale, max_scale):
		return min_scale
	return rng.randf_range(min_scale, max_scale)


func _compute_side_offset(path: Path3D, dist: float, length: float, side: int) -> float:
	if side == 0:
		return 0.0

	var lane_width := _resolve_path_component_width(
		path,
		dist,
		length,
		"get_width_at_offset",
		"get_width_at_ratio",
		default_lane_width
	)
	var lane_extents := _resolve_path_lane_extents(path, dist, length, lane_width)
	var lane_side := lane_extents.x if side < 0 else lane_extents.y
	if not edge_uses_total_road_width:
		return lane_side * float(side)

	if side < 0:
		var shoulder_l := _resolve_path_component_width(
			path,
			dist,
			length,
			"get_shoulder_left_at_offset",
			"get_shoulder_left_at_ratio",
			0.0
		)
		var sidewalk_l := _resolve_path_component_width(
			path,
			dist,
			length,
			"get_sidewalk_left_at_offset",
			"get_sidewalk_left_at_ratio",
			0.0
		)
		return -(lane_side + shoulder_l + sidewalk_l)

	var shoulder_r := _resolve_path_component_width(
		path,
		dist,
		length,
		"get_shoulder_right_at_offset",
		"get_shoulder_right_at_ratio",
		0.0
	)
	var sidewalk_r := _resolve_path_component_width(
		path,
		dist,
		length,
		"get_sidewalk_right_at_offset",
		"get_sidewalk_right_at_ratio",
		0.0
	)
	return lane_side + shoulder_r + sidewalk_r


func _resolve_path_lane_extents(path: Path3D, dist: float, length: float, width: float) -> Vector2:
	var fallback := Vector2(width * 0.5, width * 0.5)
	var raw_value: Variant
	if path.has_method("get_lane_extents_at_offset"):
		raw_value = path.call("get_lane_extents_at_offset", dist)
	elif path.has_method("get_lane_extents_at_ratio"):
		raw_value = path.call("get_lane_extents_at_ratio", clampf(dist / maxf(length, 0.0001), 0.0, 1.0))
	else:
		return fallback
	if raw_value is Vector2:
		var pair: Vector2 = raw_value
		return Vector2(maxf(0.0, pair.x), maxf(0.0, pair.y))
	return fallback


func _resolve_path_component_width(
	path: Path3D,
	dist: float,
	length: float,
	offset_method: String,
	ratio_method: String,
	fallback: float
) -> float:
	var value := maxf(0.0, fallback)
	if path != null and path.has_method(offset_method):
		value = float(path.call(offset_method, dist))
	elif path != null and path.has_method(ratio_method):
		var ratio := 0.0
		if length > 0.0001:
			ratio = clampf(dist / length, 0.0, 1.0)
			value = float(path.call(ratio_method, ratio))
	return maxf(0.0, value)


func _sample_terrain_height_hit(world_pos: Vector3, max_angle_deg: float, y_offset_local: float) -> Dictionary:
	var terrain_source := _get_terrain_height_source()
	if terrain_source == null or not terrain_source.has_method("get_terrain_height_at_world"):
		return {}
	var result = terrain_source.call("get_terrain_height_at_world", world_pos)
	if not (result is Dictionary) or not bool(result.get("hit", false)):
		return {}
	var normal: Vector3 = result.get("normal", Vector3.UP)
	if normal.length_squared() <= 0.000000000001:
		normal = Vector3.UP
	else:
		normal = normal.normalized()
	var angle_deg := rad_to_deg(normal.angle_to(Vector3.UP))
	return {
		"hit": true,
		"within_max_angle": angle_deg <= max_angle_deg + 0.0001,
		"angle_deg": angle_deg,
		"y": float(result.get("y", world_pos.y)) + y_offset_local,
	}


func _terrain_source_pending(provider: Node) -> bool:
	return is_instance_valid(provider) and provider.has_method("is_terrain_generation_pending") \
		and bool(provider.call("is_terrain_generation_pending"))


func _bind_terrain_source(provider: Node) -> void:
	if is_instance_valid(_connected_terrain_source) and _connected_terrain_source == provider:
		return
	if is_instance_valid(_connected_terrain_source) and _connected_terrain_source.has_signal("terrain_generation_completed") \
			and _connected_terrain_source.is_connected("terrain_generation_completed", _on_terrain_generation_completed):
		_connected_terrain_source.disconnect("terrain_generation_completed", _on_terrain_generation_completed)
	_connected_terrain_source = provider
	if is_instance_valid(provider) and provider.has_signal("terrain_generation_completed"):
		provider.connect("terrain_generation_completed", _on_terrain_generation_completed)


func _on_terrain_generation_completed() -> void:
	if not snap_to_ground_enabled or not _can_generate() or _connected_terrain_source != _resolve_terrain_height_source():
		return
	if Engine.is_editor_hint() and not auto_regenerate_in_editor and not _terrain_regeneration_pending:
		return
	# Do not regenerate inside the provider's completion stack. Several edits
	# coalesce, and the next process tick checks the latest provider/configuration.
	_terrain_regeneration_pending = true


func _get_terrain_height_source() -> Node:
	if is_instance_valid(_terrain_height_source_cache):
		return _terrain_height_source_cache
	_terrain_height_source_cache = _resolve_terrain_height_source()
	return _terrain_height_source_cache


func _resolve_terrain_height_source() -> Node:
	if not terrain_height_source.is_empty():
		return get_node_or_null(terrain_height_source)
	var path_parent := get_parent()
	var scene_root := path_parent.get_parent() if path_parent != null else null
	if scene_root == null:
		return null
	for sibling in scene_root.get_children():
		if sibling != null and sibling.has_method("get_terrain_height_at_world"):
			return sibling
	return null


func _sample_curve_tangent_world(
	curve: Curve3D,
	path_to_world: Transform3D,
	dist: float,
	length: float
) -> Vector3:
	var delta := maxf(0.01, tangent_sample_distance)
	var prev_dist := maxf(0.0, dist - delta)
	var next_dist := minf(length, dist + delta)
	if is_equal_approx(prev_dist, next_dist):
		if next_dist < length:
			next_dist = minf(length, next_dist + delta)
		elif prev_dist > 0.0:
			prev_dist = maxf(0.0, prev_dist - delta)

	var prev_point := path_to_world * curve.sample_baked(prev_dist, true)
	var next_point := path_to_world * curve.sample_baked(next_dist, true)
	var tangent := (next_point - prev_point).normalized()
	if tangent.length() < 0.001:
		tangent = -path_to_world.basis.z.normalized()
	if tangent.length() < 0.001:
		tangent = Vector3.FORWARD
	return tangent


func _sample_curve_up_world(curve: Curve3D, path_to_world: Transform3D, dist: float) -> Vector3:
	if align_with_curve_up and curve != null and curve.has_method("sample_baked_up_vector"):
		var up_local: Vector3 = curve.sample_baked_up_vector(dist, true)
		var up_world := (path_to_world.basis * up_local).normalized()
		if up_world.length() > 0.001:
			return up_world
	return Vector3.UP


func _build_sides_for_mode() -> Array[int]:
	match placement_mode:
		PLACEMENT_CENTER:
			return [0]
		PLACEMENT_LEFT:
			return [-1]
		PLACEMENT_RIGHT:
			return [1]
		PLACEMENT_BOTH:
			return [-1, 1]
		_:
			return [0]


func _create_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	if randomize_seed_each_regenerate:
		rng.seed = Time.get_ticks_usec()
	else:
		var s := random_seed
		if s == 0:
			s = 1337
		rng.seed = int(s)
	return rng


func _collect_path_endpoint_zones(paths: Array[Path3D]) -> Array:
	var out: Array = []
	for path in paths:
		if path == null or path.curve == null or path.curve.point_count < 2:
			continue
		var curve := path.curve
		var length := curve.get_baked_length()
		if length <= 0.001:
			continue
		var path_to_world := path.global_transform
		var path_id := path.get_instance_id()
		out.push_back({
			"path_id": path_id,
			"position": path_to_world * curve.sample_baked(0.0, true),
		})
		out.push_back({
			"path_id": path_id,
			"position": path_to_world * curve.sample_baked(length, true),
		})
	return out


func _point_blocked_by_intersection_zones(
	path: Path3D,
	world_pos: Vector3,
	side: int,
	endpoint_zones: Array
) -> bool:
	if not avoid_intersections:
		return false
	if endpoint_zones.is_empty():
		return false
	if side == 0 and not avoid_intersections_in_center_mode:
		return false

	var radius := maxf(0.0, intersection_clear_radius)
	if radius <= 0.001:
		return false
	var radius_sq := radius * radius
	var path_id := path.get_instance_id() if path != null else -1

	for zone in endpoint_zones:
		var zone_path_id := int(zone.get("path_id", -1))
		var same_path := zone_path_id == path_id
		if same_path and not avoid_own_path_endpoints:
			continue
		if not same_path and not avoid_other_path_endpoints:
			continue
		var zone_pos: Vector3 = zone.get("position", Vector3.ZERO)
		if world_pos.distance_squared_to(zone_pos) <= radius_sq:
			return true
	return false


func _collect_span_ranges_by_path(paths: Array[Path3D]) -> Dictionary:
	var out: Dictionary = {}
	for path in paths:
		if path == null:
			continue
		out[path.get_instance_id()] = PackedVector2Array()

	for child in get_children():
		if child == null:
			continue
		if not child.has_method("is_spline_prop_span"):
			continue
		if not bool(child.call("is_spline_prop_span")):
			continue
		for path in paths:
			if path == null:
				continue
			if not child.has_method("get_range_for_path"):
				continue
			var result: Dictionary = child.call("get_range_for_path", path)
			if not bool(result.get("ok", false)):
				continue
			var pair: Vector2 = result.get("range", Vector2.ZERO)
			var path_id := path.get_instance_id()
			var arr := PackedVector2Array(out.get(path_id, PackedVector2Array()))
			arr.push_back(pair)
			out[path_id] = arr

	return out


func _build_effective_ranges(path: Path3D, length: float, span_ranges_by_path: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	if range_source_mode == RANGE_SOURCE_MANUAL or range_source_mode == RANGE_SOURCE_MANUAL_AND_SPANS:
		for pair in distance_ranges:
			var a := clampf(minf(pair.x, pair.y), 0.0, length)
			var b := clampf(maxf(pair.x, pair.y), 0.0, length)
			if b <= a + 0.0001:
				continue
			out.push_back(Vector2(a, b))

	if path != null and (range_source_mode == RANGE_SOURCE_SPANS or range_source_mode == RANGE_SOURCE_MANUAL_AND_SPANS):
		var path_id := path.get_instance_id()
		var from_spans := PackedVector2Array(span_ranges_by_path.get(path_id, PackedVector2Array()))
		for pair in from_spans:
			var a := clampf(minf(pair.x, pair.y), 0.0, length)
			var b := clampf(maxf(pair.x, pair.y), 0.0, length)
			if b <= a + 0.0001:
				continue
			out.push_back(Vector2(a, b))

	return out


func _distance_allowed_by_ranges(
	path: Path3D,
	dist: float,
	length: float,
	span_ranges_by_path: Dictionary
) -> bool:
	if ranges_mode == 0:
		return true
	var effective_ranges := _build_effective_ranges(path, length, span_ranges_by_path)
	if effective_ranges.is_empty():
		return true
	var inside := false
	for pair in effective_ranges:
		var a := pair.x
		var b := pair.y
		if dist >= a and dist <= b:
			inside = true
			break
	if ranges_mode == 1:
		return inside
	return not inside


func _resolve_paths() -> Array[Path3D]:
	var out: Array[Path3D] = []
	var seen: Dictionary = {}
	for np in source_paths:
		if np == NodePath():
			continue
		var n := get_node_or_null(np)
		if n is Path3D:
			_push_unique_path(out, seen, n)

	if out.is_empty():
		for child in get_children():
			if child is Path3D:
				_push_unique_path(out, seen, child)

	if out.is_empty():
		var parent := get_parent()
		if parent != null:
			for sibling in parent.get_children():
				if sibling is Path3D:
					_push_unique_path(out, seen, sibling)

	var filtered: Array[Path3D] = []
	for path in out:
		if path == null:
			continue
		if _path_is_terrain_influence_only(path) and not include_terrain_influence_paths:
			continue
		filtered.push_back(path)
	return filtered


func _path_is_terrain_influence_only(path: Path3D) -> bool:
	if path == null:
		return false
	if path.has_method("is_terrain_influence_path"):
		return bool(path.call("is_terrain_influence_path"))
	return false


func _push_unique_path(out: Array[Path3D], seen: Dictionary, path: Path3D) -> void:
	if path == null:
		return
	var key := str(path.get_instance_id())
	if seen.has(key):
		return
	seen[key] = true
	out.push_back(path)


func _get_generation_parent_root() -> Node3D:
	if use_parent_as_generated_root:
		var parent_node := get_parent()
		if parent_node is Node3D:
			return parent_node as Node3D
		if not _warned_non_node3d_parent:
			push_warning("SplinePropArray3D: parent must inherit Node3D when use_parent_as_generated_root is enabled.")
			_warned_non_node3d_parent = true
		return self
	return _get_or_create_generated_root()


func _get_or_create_generated_root() -> Node3D:
	var root := get_node_or_null(GENERATED_ROOT_NAME) as Node3D
	if root == null:
		root = Node3D.new()
		root.name = GENERATED_ROOT_NAME
		add_child(root)
		_assign_generated_owner(root)
	return root


func _clear_all_generated_nodes() -> void:
	_output_cache.discard_output()
	_clear_generated_root()
	_clear_generated_nodes_in_parent(get_parent())
	_clear_generated_nodes_in_parent(self)


func _clear_generated_root() -> void:
	var root := get_node_or_null(GENERATED_ROOT_NAME) as Node3D
	if root == null:
		return
	root.free()


func _clear_generated_nodes_in_parent(parent: Node) -> void:
	if parent == null:
		return
	for child in parent.get_children():
		if _is_generated_node_for_this_array(child):
			child.free()


func _is_generated_node_for_this_array(node: Node) -> bool:
	if node == null:
		return false
	if not node.has_meta(GENERATED_OWNER_META):
		return false
	return str(node.get_meta(GENERATED_OWNER_META, "")) == str(get_path())


func _assign_editor_owner(node: Node) -> void:
	if not Engine.is_editor_hint():
		return
	if node == null:
		return
	var edited_root := get_tree().edited_scene_root
	if edited_root == null:
		return
	if not edited_root.is_ancestor_of(node):
		return
	node.owner = edited_root


func _assign_generated_owner(node: Node) -> void:
	if not persist_generated_in_scene:
		return
	_assign_editor_owner(node)


func _can_generate() -> bool:
	return not Engine.is_editor_hint() or generate_in_editor


func _should_defer_editor_regenerate() -> bool:
	if not Engine.is_editor_hint():
		return false
	if regenerate_while_dragging_handles:
		return false
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _debug_log(message: String) -> void:
	if not debug_logs:
		return
	print("[SplinePropArray3D] " + message)


func _build_signature() -> String:
	var parts: Array[String] = [
		str(source_paths.size()),
		str(include_terrain_influence_paths),
		str(item_scene),
		str(item_mesh),
		str(item_material_override),
		str(mesh_cast_shadows),
		str(render_mode),
		str(multimesh_chunk_size),
		str(placement_mode),
		str(fit_segments_to_path),
		str(follow_generated_road_edge),
		str(spacing),
		str(start_offset),
		str(end_trim),
		str(road_network_source),
		str(default_lane_width),
		str(edge_uses_total_road_width),
		str(lateral_offset),
		str(outward_offset),
		str(vertical_offset),
		str(snap_to_ground_enabled),
		str(terrain_height_source),
		str(snap_to_ground_max_angle_deg),
		str(snap_to_ground_slope_mode),
		str(snap_to_ground_y_offset),
		str(avoid_intersections),
		str(avoid_own_path_endpoints),
		str(avoid_other_path_endpoints),
		str(avoid_intersections_in_center_mode),
		str(intersection_clear_radius),
		str(avoid_road_surface),
		str(road_avoidance_height_tolerance),
		str(ranges_mode),
		str(range_source_mode),
		str(distance_ranges.size()),
		str(align_with_path),
		str(align_with_curve_up),
		str(tangent_sample_distance),
		str(yaw_offset_degrees),
		str(custom_transform),
		str(random_seed),
		str(randomize_seed_each_regenerate),
		str(longitudinal_jitter),
		str(lateral_jitter),
		str(vertical_jitter),
		str(yaw_jitter_degrees),
		str(random_uniform_scale_min),
		str(random_uniform_scale_max),
		str(persist_generated_in_scene),
		str(use_parent_as_generated_root),
		str(regenerate_while_dragging_handles),
	]
	for pair in distance_ranges:
		parts.append(str(pair))
	if avoid_road_surface:
		parts.append(_road_avoidance.signature(self))
	var road_network := get_node_or_null(road_network_source)
	if road_network != null:
		parts.append(str(road_network.global_transform))
		if fit_segments_to_path and follow_generated_road_edge and road_network.has_method("get_terrain_surface_revision"):
			parts.append(str(road_network.get_terrain_surface_revision()))
		for property_name in ["y_offset", "road_orientation_mode", "road_bank_max_degrees", "road_bank_strength", "road_bank_sample_distance"]:
			parts.append(str(road_network.get(property_name)))
	for child in get_children():
		if child == null:
			continue
		if not child.has_method("is_spline_prop_span"):
			continue
		if not bool(child.call("is_spline_prop_span")):
			continue
		parts.append(str(child.get_instance_id()))
		for property_name in ["enabled", "target_path", "start_offset", "end_offset", "snap_handles_to_path", "lateral_offset", "vertical_offset"]:
			var value = child.get(property_name)
			if property_name == "start_offset" or property_name == "end_offset":
				# Span handles are projected against a baked curve. Quantize the
				# insignificant floating-point residue so it cannot recreate every prop.
				parts.append(str(snappedf(float(value), 0.001)))
			else:
				parts.append(str(value))

	var paths := _resolve_paths()
	parts.append(str(paths.size()))
	for path in paths:
		if path == null:
			parts.append("null_path")
			continue
		parts.append(str(path.get_instance_id()))
		parts.append(str(path.global_transform))
		if path.has_method("get_dependent_width_profile_signature"):
			parts.append(str(path.call("get_dependent_width_profile_signature")))
		elif path.has_method("get_width_profile_signature"):
			parts.append(str(path.call("get_width_profile_signature")))
		if path.has_method("get_edge_profile_signature"):
			parts.append(str(path.call("get_edge_profile_signature")))
		if path.curve == null:
			parts.append("null_curve")
			continue
		parts.append(str(path.curve.point_count))
		for i in range(path.curve.point_count):
			parts.append(str(path.curve.get_point_position(i)))
			parts.append(str(path.curve.get_point_in(i)))
			parts.append(str(path.curve.get_point_out(i)))
			parts.append(str(path.curve.get_point_tilt(i)))

	return "|".join(parts)
