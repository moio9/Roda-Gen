@tool
extends Path3D
class_name SplinePathProfile3D

@export_group("Road")
@export_subgroup("Width")
@export_range(0.2, 50.0, 0.1) var default_width := 6.0
@export var point_widths := PackedFloat32Array()
@export_subgroup("Directional Lanes")
## Uses per-point left/right lane counts instead of the legacy centered point width.
@export var lane_profile_enabled := false: set = _set_lane_profile_enabled
@export_range(0, 12, 1) var default_lanes_left := 1
@export_range(0, 12, 1) var default_lanes_right := 1
@export_range(1.5, 20.0, 0.05, "suffix:m") var default_lane_width := 3.5
@export var point_lanes_left := PackedInt32Array()
@export var point_lanes_right := PackedInt32Array()
@export var point_lane_widths := PackedFloat32Array()
## Per-point incoming transition distance. Zero uses the complete previous segment.
@export var point_lane_transition_lengths := PackedFloat32Array()
## Entry i controls the easing from point i - 1 into point i. Curves use a 0..1 domain/range.
@export var point_lane_transition_curves: Array[Curve] = []
## Keeps lane-point editing responsive. The lightweight orange preview updates
## immediately; road meshes and edge-dependent props update only when applied.
@export var live_lane_regeneration := false: set = _set_live_lane_regeneration
@export_range(0.5, 10.0, 0.1, "suffix:m") var lane_edit_preview_step := 2.0
@export_tool_button("Apply Lane Changes") var apply_lane_changes_action := apply_lane_changes
@export_tool_button("Rebuild Road + Terrain") var rebuild_lane_terrain_action := rebuild_lane_terrain
@export_tool_button("Rebuild Lane Dependents (Slow)") var rebuild_lane_dependents_action := rebuild_lane_dependents
@export_subgroup("Edges")
@export_range(0.0, 15.0, 0.1) var shoulder_left_width := 0.0
@export_range(0.0, 15.0, 0.1) var shoulder_right_width := 0.0
@export_range(0.0, 15.0, 0.1) var sidewalk_left_width := 0.0
@export_range(0.0, 15.0, 0.1) var sidewalk_right_width := 0.0
@export_range(0.0, 2.0, 0.01) var sidewalk_height := 0.12
@export_range(0.0, 30.0, 0.1) var outer_wall_height := 0.0
@export_subgroup("Orientation")
@export var road_orientation_override_enabled := false: set = _set_road_orientation_override_enabled
@export_enum("Curve Up", "World Up (Y)", "Bank Into Curve") var road_orientation_mode := 0: set = _set_road_orientation_mode
@export_range(0.0, 45.0, 0.1, "suffix:deg") var road_bank_max_degrees := 8.0
@export_range(0.0, 4.0, 0.01) var road_bank_strength := 1.0
@export_range(0.05, 30.0, 0.05, "suffix:m") var road_bank_sample_distance := 3.0
@export var terrain_override_enabled := false: set = _set_terrain_override_enabled
@export_range(0.0, 50.0, 0.1) var terrain_left_width := 0.0
@export_range(0.0, 50.0, 0.1) var terrain_right_width := 0.0
@export_subgroup("Terrain Height Profile")
## Replaces TerrainTopologyBuilder3D's default height profile for this spline only.
@export var terrain_height_profile_override_enabled := false: set = _set_terrain_height_profile_override_enabled
@export var terrain_left_profile_distances := PackedFloat32Array()
@export var terrain_left_profile_heights := PackedFloat32Array()
@export var terrain_right_profile_distances := PackedFloat32Array()
@export var terrain_right_profile_heights := PackedFloat32Array()
@export_range(0.0, 200.0, 0.5) var terrain_profile_to_base_blend_distance := 30.0
@export_range(0.1, 6.0, 0.01) var terrain_profile_power := 1.0
@export_subgroup("Terrain Profile Continuation")
## These side overrides work even when Terrain Height Profile Override is off.
## Continue Last Height extends the final height instead of returning to base.
@export_enum("Inherit:-1", "Return To Base:0", "Continue Last Height:1") var terrain_left_profile_continuation := -1
@export_enum("Inherit:-1", "Return To Base:0", "Continue Last Height:1") var terrain_right_profile_continuation := -1

@export_group("Weld")
## Independent join channels shown as a layer grid in the Inspector. Two roads
## can join when they share any checked bit; this does not affect physics.
@export_flags_3d_physics var lateral_join_layers := 0
## Nonempty matching groups opt source splines into lateral asphalt joining.
## Legacy string channel for existing scenes. Sources must share a network.
@export var lateral_join_group := ""
## -1 inherits the network length, 0 disables the generated taper at this end.
@export_range(-1.0, 200.0, 0.5, "suffix:m") var lateral_join_start_transition_length := -1.0
@export_range(-1.0, 200.0, 0.5, "suffix:m") var lateral_join_end_transition_length := -1.0
@export var intersection_override_enabled := false: set = _set_intersection_override_enabled
@export_range(0.1, 30.0, 0.1) var weld_endpoint_snap_distance := 2.0
@export var weld_allow_endpoint_to_midpath := true
@export var weld_strip_shoulder_sidewalk_at_intersections := true
@export_range(0.0, 30.0, 0.001) var weld_intersection_strip_length := 0.0
@export var adaptive_sampling_enabled := true
@export_subgroup("Adaptive Sampling", "adaptive_sampling_")
@export var adaptive_sampling_advanced := false: set = _set_adaptive_sampling_advanced
@export_range(0.1, 4.0, 0.01) var adaptive_sampling_step_scale := 1.0
@export_range(0.1, 4.0, 0.01) var adaptive_sampling_radius_scale := 1.0
@export_range(-10.0, 10.0, 0.01) var adaptive_sampling_offset := 0.0

@export_group("Workflow")
@export_subgroup("Profile Sync")
@export var sync_widths_now := false: set = _set_sync_widths_now
@export_subgroup("Selected Point")
@export_range(0, 2048, 1) var selected_point_index := 0: set = _set_selected_point_index
@export_range(0.1, 50.0, 0.1) var selected_point_width := 6.0: set = _set_selected_point_width
@export_range(-3.14159, 3.14159, 0.01) var selected_point_tilt := 0.0: set = _set_selected_point_tilt
@export_subgroup("Selected Point Lanes")
@export_range(0, 12, 1) var selected_point_lanes_left := 1: set = _set_selected_point_lanes_left
@export_range(0, 12, 1) var selected_point_lanes_right := 1: set = _set_selected_point_lanes_right
@export_range(1.5, 20.0, 0.05, "suffix:m") var selected_point_lane_width := 3.5: set = _set_selected_point_lane_width
@export_range(0.0, 1000.0, 0.5, "suffix:m") var selected_point_lane_transition_length := 0.0: set = _set_selected_point_lane_transition_length
## Easing used by the segment entering the selected point.
@export var selected_point_lane_transition: Curve: set = _set_selected_point_lane_transition
@export var selected_point_prev := false: set = _set_selected_point_prev
@export var selected_point_next := false: set = _set_selected_point_next
@export var auto_pick_selected_handle := true

@export_subgroup("Preview")
@export var show_width_preview := true
@export_range(0.0, 5.0, 0.01) var preview_height := 0.05
@export_range(0.02, 2.0, 0.01) var preview_strip_width := 0.08
@export_range(0.005, 0.5, 0.005) var preview_thickness := 0.03
@export var preview_color := Color(1.0, 0.65, 0.2, 0.9)
@export var selected_preview_color := Color(0.2, 0.95, 1.0, 0.95)

const HANDLES_NODE_NAME := "__WidthHandles"
const HANDLE_META_INDEX := "width_point_index"
const HANDLE_META_SYNCED_ORIGIN := "width_handle_synced_origin"
const HANDLE_META_SYNCED_BASIS := "width_handle_synced_basis"
const MIN_WIDTH := 0.1
const MIN_LANE_WIDTH := 1.5
const MAX_LANES_PER_SIDE := 12
const ROAD_ORIENTATION_CURVE_UP := 0
const ROAD_ORIENTATION_WORLD_UP := 1
const ROAD_ORIENTATION_BANK_INTO_CURVE := 2
# Keep this relative to the addon script, so the addon may be installed under
# any directory name in a host project.
const HANDLE_SCRIPT: Script = preload("./spline_width_handle.gd")
const EDITOR_HISTORY: Script = preload("./road_editor_history.gd")
const EDITOR_STATE_PROPERTIES := [
	"default_width", "point_widths", "lane_profile_enabled",
	"default_lanes_left", "default_lanes_right", "default_lane_width",
	"point_lanes_left", "point_lanes_right", "point_lane_widths",
	"point_lane_transition_lengths", "point_lane_transition_curves",
]

var _last_signature := ""
var _syncing_selected_fields := false
var _normal_handle_material: StandardMaterial3D
var _selected_handle_material: StandardMaterial3D
var _lane_generation_revision := 0
var _lane_dependents_revision := 0
var _lane_signature_seen := ""
var _lane_changes_pending := false
var _lane_fast_preview_active := false
var _control_offsets_cache := PackedFloat32Array()
var _control_offsets_cache_curve_id := 0
var _control_offsets_cache_point_count := -1
var _connected_curve_for_offsets: Curve3D
var _restoring_editor_state := false


func capture_editor_state() -> Dictionary:
	var state: Dictionary = {"curve": curve, "curve_points": []}
	for property in EDITOR_STATE_PROPERTIES:
		var value: Variant = get(property)
		if value is Array or value is PackedFloat32Array or value is PackedInt32Array:
			value = value.duplicate()
		state[property] = value
	if curve != null:
		for index in range(curve.point_count):
			state["curve_points"].append([
				curve.get_point_position(index), curve.get_point_in(index),
				curve.get_point_out(index), curve.get_point_tilt(index),
			])
	return state


func restore_editor_state(state: Dictionary) -> void:
	_restoring_editor_state = true
	for property in EDITOR_STATE_PROPERTIES:
		var value: Variant = state[property]
		# Packed arrays are copied as well: subsequent point edits must never
		# mutate values retained by the editor's history.
		if value is Array or value is PackedFloat32Array or value is PackedInt32Array:
			value = value.duplicate()
		set(property, value)
	curve = state["curve"]
	if curve != null:
		curve.clear_points()
		for point in state["curve_points"]:
			curve.add_point(point[0], point[1], point[2])
			curve.set_point_tilt(curve.point_count - 1, point[3])
	_restoring_editor_state = false
	_invalidate_control_point_offsets_cache()
	_lane_generation_revision += 1
	_lane_dependents_revision += 1
	_last_signature = ""
	_refresh_selected_point_fields()
	_rebuild_preview()
	if Engine.is_editor_hint():
		notify_property_list_changed()


func apply_editor_profile_change(before: Dictionary, property: String, value: Variant, index: int, replay: Dictionary = {}) -> void:
	if replay.has("after"):
		# Setters such as first-time lane conversion create Curve resources.
		# Their identities must survive Redo so their own native history stays
		# connected, even after the Inspector first changes its proxy property.
		restore_editor_state(replay["after"])
		if index >= 0:
			select_point_index(index)
		return
	restore_editor_state(before)
	if index >= 0:
		select_point_index(index)
	set(property, value)
	_last_signature = ""
	_refresh_selected_point_fields()
	_rebuild_preview()
	replay["after"] = capture_editor_state()


## Batch preset/history settings without seeding lanes or touching Curve3D points.
func restore_preset_properties(values: Dictionary) -> void:
	_restoring_editor_state = true
	for property in values:
		var value: Variant = values[property]
		if value is Array or value is PackedFloat32Array or value is PackedInt32Array:
			value = value.duplicate()
		set(property, value)
	_restoring_editor_state = false
	_lane_generation_revision += 1
	_lane_dependents_revision += 1
	_lane_signature_seen = _build_live_lane_signature()
	_last_signature = ""
	_refresh_selected_point_fields()
	_rebuild_preview()
	if Engine.is_editor_hint():
		notify_property_list_changed()
		_rebuild_terrain_consumers.call_deferred()


func enable_lane_profile_with_undo() -> void:
	EDITOR_HISTORY.commit_profile_change(self, "Enable directional road lanes", "lane_profile_enabled", true)


func get_point_editor_transform(index: int) -> Transform3D:
	if curve == null or index < 0 or index >= curve.point_count:
		return Transform3D.IDENTITY
	var origin := curve.get_point_position(index) + Vector3.UP * preview_height
	var road_frame := _road_surface_handle_transform(index)
	if not road_frame.is_empty():
		origin = road_frame.get("origin", origin)
	return Transform3D(_compute_handle_basis(index, curve.point_count), origin)


func apply_point_editor_transform(index: int, before: Transform3D, after: Transform3D, original_point: Array) -> void:
	if curve == null or index < 0 or index >= curve.point_count:
		return
	var delta_basis := after.basis * before.basis.inverse()
	curve.set_point_position(index, original_point[0] + after.origin - before.origin)
	curve.set_point_in(index, delta_basis * original_point[1])
	curve.set_point_out(index, delta_basis * original_point[2])
	select_point_index(index)
	_last_signature = ""
	_rebuild_preview()


func _ready() -> void:
	set_process(true)
	_ensure_control_offset_curve_connection()
	if not Engine.is_editor_hint():
		return
	_sync_point_widths()
	if lane_profile_enabled or _has_lane_profile_storage():
		_sync_lane_profiles()
	_lane_signature_seen = _build_live_lane_signature()
	_refresh_selected_point_fields()
	_rebuild_preview()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_ensure_control_offset_curve_connection()
	var moved_curve_points := _apply_handle_transforms_to_curve()
	_sync_point_widths()
	if lane_profile_enabled or _has_lane_profile_storage():
		_sync_lane_profiles()
	_track_lane_changes()
	if auto_pick_selected_handle:
		_pull_selected_from_editor_selection()

	var sig := _build_signature()
	if moved_curve_points:
		_last_signature = ""
	if sig == _last_signature and not _width_preview_needs_rebuild():
		return
	_last_signature = sig
	_refresh_selected_point_fields()
	_rebuild_preview()


func _exit_tree() -> void:
	_clear_preview()


func _set_sync_widths_now(value: bool) -> void:
	sync_widths_now = false
	if not value:
		return
	_sync_point_widths(true)
	_refresh_selected_point_fields()
	_last_signature = ""
	_rebuild_preview()


func _set_selected_point_index(value: int) -> void:
	if _syncing_selected_fields:
		selected_point_index = value
		return
	selected_point_index = value
	_refresh_selected_point_fields()
	_last_signature = ""


func _set_selected_point_width(value: float) -> void:
	if _syncing_selected_fields:
		selected_point_width = max(MIN_WIDTH, value)
		return

	selected_point_width = max(MIN_WIDTH, value)
	var count := _point_count()
	if count <= 0:
		return

	var idx = clamp(selected_point_index, 0, count - 1)
	if point_widths.size() != count:
		_sync_point_widths()
	if idx >= 0 and idx < point_widths.size():
		point_widths[idx] = selected_point_width
	_last_signature = ""


func _set_selected_point_tilt(value: float) -> void:
	if _syncing_selected_fields:
		selected_point_tilt = value
		return
	set_point_tilt_at_index(selected_point_index, value)


func _set_lane_profile_enabled(value: bool) -> void:
	if _restoring_editor_state:
		lane_profile_enabled = value
		return
	var seed_from_legacy := value and not lane_profile_enabled and not _has_lane_profile_storage()
	lane_profile_enabled = value
	if seed_from_legacy:
		_seed_lane_profiles_from_legacy_widths()
	else:
		_sync_lane_profiles()
	if Engine.is_editor_hint():
		notify_property_list_changed()
	_refresh_selected_point_fields()
	_last_signature = ""
	apply_lane_changes()


func _set_live_lane_regeneration(value: bool) -> void:
	live_lane_regeneration = value
	if value:
		apply_lane_changes()


func apply_lane_changes() -> void:
	_lane_signature_seen = _build_live_lane_signature()
	_lane_changes_pending = false
	_lane_fast_preview_active = true
	_lane_generation_revision += 1
	_last_signature = ""


func rebuild_lane_dependents() -> void:
	rebuild_lane_terrain()
	_lane_dependents_revision += 1


func rebuild_lane_terrain() -> void:
	apply_lane_changes()
	_lane_fast_preview_active = false
	# Terrain may intentionally have auto regeneration disabled in large scenes.
	# Explicitly rebuild only terrain consumers of this profile so widened lanes
	# cannot leave the previous road cutout visible as an empty strip.
	call_deferred("_rebuild_terrain_consumers")


func _rebuild_terrain_consumers() -> void:
	if not is_inside_tree():
		return
	var scene_root := get_tree().edited_scene_root
	if scene_root == null:
		scene_root = get_tree().current_scene
	if scene_root == null:
		return
	var pending: Array[Node] = [scene_root]
	while not pending.is_empty():
		var node := pending.pop_back()
		for child in node.get_children():
			pending.push_back(child)
		if node == self or not node.has_method("regenerate"):
			continue
		if not node.has_method("get_terrain_height_at_world"):
			continue
		var sources: Variant = node.get("source_paths")
		if not sources is Array:
			continue
		for source_value in sources:
			var source_path: NodePath = source_value
			if node.get_node_or_null(source_path) == self:
				if node.has_method("invalidate_road_data_cache"):
					node.call("invalidate_road_data_cache")
				node.call("regenerate")
				break


func _set_selected_point_lanes_left(value: int) -> void:
	selected_point_lanes_left = clampi(value, 0, MAX_LANES_PER_SIDE)
	if _syncing_selected_fields:
		return
	_set_selected_lane_value(true, selected_point_lanes_left)


func _set_selected_point_lanes_right(value: int) -> void:
	selected_point_lanes_right = clampi(value, 0, MAX_LANES_PER_SIDE)
	if _syncing_selected_fields:
		return
	_set_selected_lane_value(false, selected_point_lanes_right)


func _set_selected_point_lane_width(value: float) -> void:
	selected_point_lane_width = maxf(MIN_LANE_WIDTH, value)
	if _syncing_selected_fields:
		return
	var count := _point_count()
	if count <= 0:
		return
	_sync_lane_profiles()
	var idx := clampi(selected_point_index, 0, count - 1)
	point_lane_widths[idx] = selected_point_lane_width
	_last_signature = ""


func _set_selected_point_lane_transition_length(value: float) -> void:
	selected_point_lane_transition_length = maxf(0.0, value)
	if _syncing_selected_fields:
		return
	var count := _point_count()
	if count <= 0:
		return
	_sync_lane_profiles()
	var idx := clampi(selected_point_index, 0, count - 1)
	point_lane_transition_lengths[idx] = selected_point_lane_transition_length
	_last_signature = ""


func _set_selected_point_lane_transition(value: Curve) -> void:
	selected_point_lane_transition = value
	if _syncing_selected_fields:
		return
	var count := _point_count()
	if count <= 0:
		return
	_sync_lane_profiles()
	var idx := clampi(selected_point_index, 0, count - 1)
	point_lane_transition_curves[idx] = value if value != null else _make_default_lane_transition_curve()
	selected_point_lane_transition = point_lane_transition_curves[idx]
	_last_signature = ""


func _set_selected_lane_value(left_side: bool, value: int) -> void:
	var count := _point_count()
	if count <= 0:
		return
	_sync_lane_profiles()
	var idx := clampi(selected_point_index, 0, count - 1)
	if left_side:
		point_lanes_left[idx] = value
	else:
		point_lanes_right[idx] = value
	_last_signature = ""


func _set_selected_point_prev(value: bool) -> void:
	selected_point_prev = false
	if not value:
		return
	_move_selected_point_index(-1)


func _set_selected_point_next(value: bool) -> void:
	selected_point_next = false
	if not value:
		return
	_move_selected_point_index(1)


func _set_intersection_override_enabled(value: bool) -> void:
	intersection_override_enabled = value
	if Engine.is_editor_hint():
		notify_property_list_changed()
	_last_signature = ""


func _set_road_orientation_override_enabled(value: bool) -> void:
	road_orientation_override_enabled = value
	if Engine.is_editor_hint():
		notify_property_list_changed()
	_last_signature = ""


func _set_road_orientation_mode(value: int) -> void:
	road_orientation_mode = clampi(value, ROAD_ORIENTATION_CURVE_UP, ROAD_ORIENTATION_BANK_INTO_CURVE)
	if Engine.is_editor_hint():
		notify_property_list_changed()
	_last_signature = ""


func _set_terrain_override_enabled(value: bool) -> void:
	terrain_override_enabled = value
	if Engine.is_editor_hint():
		notify_property_list_changed()
	_last_signature = ""


func _set_terrain_height_profile_override_enabled(value: bool) -> void:
	terrain_height_profile_override_enabled = value
	if Engine.is_editor_hint():
		notify_property_list_changed()
	_last_signature = ""


func _set_adaptive_sampling_advanced(value: bool) -> void:
	adaptive_sampling_advanced = value
	if Engine.is_editor_hint():
		notify_property_list_changed()
	_last_signature = ""


func _move_selected_point_index(delta: int) -> void:
	var count := _point_count()
	if count <= 0:
		return
	var idx = clamp(selected_point_index + delta, 0, count - 1)
	_set_selected_point_index(idx)


func select_point_index(index: int) -> void:
	_set_selected_point_index(index)


func set_point_width_at_index(index: int, width: float) -> void:
	var count := _point_count()
	if count <= 0:
		return

	var idx = clamp(index, 0, count - 1)
	if point_widths.size() != count:
		_sync_point_widths()

	var w = max(MIN_WIDTH, width)
	point_widths[idx] = w
	_syncing_selected_fields = true
	selected_point_index = idx
	selected_point_width = w
	selected_point_tilt = _get_point_tilt(idx)
	selected_point_lanes_left = _get_point_lane_count(idx, true)
	selected_point_lanes_right = _get_point_lane_count(idx, false)
	selected_point_lane_width = _get_point_lane_width(idx)
	selected_point_lane_transition_length = _get_point_lane_transition_length(idx)
	selected_point_lane_transition = _get_point_lane_transition(idx)
	_syncing_selected_fields = false
	_last_signature = ""


func set_point_tilt_at_index(index: int, tilt: float) -> void:
	if curve == null:
		return
	var count := _point_count()
	if count <= 0:
		return
	var idx: int = clamp(index, 0, count - 1)
	curve.set_point_tilt(idx, tilt)
	_syncing_selected_fields = true
	selected_point_index = idx
	selected_point_width = _get_point_width(idx)
	selected_point_tilt = tilt
	selected_point_lanes_left = _get_point_lane_count(idx, true)
	selected_point_lanes_right = _get_point_lane_count(idx, false)
	selected_point_lane_width = _get_point_lane_width(idx)
	selected_point_lane_transition_length = _get_point_lane_transition_length(idx)
	selected_point_lane_transition = _get_point_lane_transition(idx)
	_syncing_selected_fields = false
	_last_signature = ""


func set_point_lane_count_at_index(index: int, left_side: bool, lanes: int) -> void:
	var count := _point_count()
	if count <= 0:
		return
	_sync_lane_profiles()
	var idx := clampi(index, 0, count - 1)
	if left_side:
		point_lanes_left[idx] = clampi(lanes, 0, MAX_LANES_PER_SIDE)
	else:
		point_lanes_right[idx] = clampi(lanes, 0, MAX_LANES_PER_SIDE)
	select_point_index(idx)
	_last_signature = ""


func set_point_lane_width_at_index(index: int, width: float) -> void:
	var count := _point_count()
	if count <= 0:
		return
	_sync_lane_profiles()
	var idx := clampi(index, 0, count - 1)
	point_lane_widths[idx] = maxf(MIN_LANE_WIDTH, width)
	select_point_index(idx)
	_last_signature = ""


func set_point_lane_transition_length_at_index(index: int, length: float) -> void:
	var count := _point_count()
	if count <= 0:
		return
	_sync_lane_profiles()
	var idx := clampi(index, 0, count - 1)
	point_lane_transition_lengths[idx] = maxf(0.0, length)
	select_point_index(idx)
	_last_signature = ""


func set_point_lane_transition_at_index(index: int, transition: Curve) -> void:
	var count := _point_count()
	if count <= 0:
		return
	_sync_lane_profiles()
	var idx := clampi(index, 0, count - 1)
	point_lane_transition_curves[idx] = transition if transition != null else _make_default_lane_transition_curve()
	select_point_index(idx)
	_last_signature = ""


func _validate_property(property: Dictionary) -> void:
	var count := _point_count()
	if count <= 0 and (
		property.name == "selected_point_index"
		or property.name == "selected_point_width"
		or property.name == "selected_point_tilt"
		or property.name == "selected_point_lanes_left"
		or property.name == "selected_point_lanes_right"
		or property.name == "selected_point_lane_width"
		or property.name == "selected_point_lane_transition_length"
		or property.name == "selected_point_lane_transition"
		or property.name == "selected_point_prev"
		or property.name == "selected_point_next"
	):
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name == "selected_point_width" and lane_profile_enabled:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name in [
		"default_lanes_left",
		"default_lanes_right",
		"default_lane_width",
		"point_lanes_left",
		"point_lanes_right",
		"point_lane_widths",
		"point_lane_transition_lengths",
		"point_lane_transition_curves",
		"selected_point_lanes_left",
		"selected_point_lanes_right",
		"selected_point_lane_width",
		"selected_point_lane_transition_length",
		"selected_point_lane_transition",
	] and not lane_profile_enabled:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "road_orientation_mode"
		or property.name == "road_bank_max_degrees"
		or property.name == "road_bank_strength"
		or property.name == "road_bank_sample_distance"
	) and not road_orientation_override_enabled:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "road_bank_max_degrees"
		or property.name == "road_bank_strength"
		or property.name == "road_bank_sample_distance"
	) and (
		not road_orientation_override_enabled
		or road_orientation_mode != ROAD_ORIENTATION_BANK_INTO_CURVE
	):
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "terrain_left_width"
		or property.name == "terrain_right_width"
	) and not terrain_override_enabled:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "terrain_left_profile_distances"
		or property.name == "terrain_left_profile_heights"
		or property.name == "terrain_right_profile_distances"
		or property.name == "terrain_right_profile_heights"
		or property.name == "terrain_profile_to_base_blend_distance"
		or property.name == "terrain_profile_power"
	) and not terrain_height_profile_override_enabled:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "weld_endpoint_snap_distance"
		or property.name == "weld_allow_endpoint_to_midpath"
		or property.name == "weld_strip_shoulder_sidewalk_at_intersections"
		or property.name == "weld_intersection_strip_length"
		or property.name == "adaptive_sampling_enabled"
		or property.name == "adaptive_sampling_advanced"
		or property.name == "adaptive_sampling_step_scale"
		or property.name == "adaptive_sampling_radius_scale"
		or property.name == "adaptive_sampling_offset"
	) and not intersection_override_enabled:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "adaptive_sampling_step_scale"
		or property.name == "adaptive_sampling_radius_scale"
		or property.name == "adaptive_sampling_offset"
	) and (not intersection_override_enabled or not adaptive_sampling_advanced):
		property.usage = PROPERTY_USAGE_NO_EDITOR


func get_width_at_offset(offset: float) -> float:
	if curve == null or curve.point_count <= 0:
		return max(MIN_WIDTH, default_width)
	if lane_profile_enabled:
		var extents := get_lane_extents_at_offset(offset)
		return maxf(MIN_WIDTH, extents.x + extents.y)
	var length = max(0.001, curve.get_baked_length())
	var ratio = clamp(offset / length, 0.0, 1.0)
	return get_width_at_ratio(ratio)


func get_width_at_ratio(ratio: float) -> float:
	if lane_profile_enabled and curve != null:
		return get_width_at_offset(clampf(ratio, 0.0, 1.0) * curve.get_baked_length())
	return _legacy_width_at_ratio(ratio)


func _legacy_width_at_ratio(ratio: float) -> float:
	var count := _point_count()
	if count <= 0:
		return max(MIN_WIDTH, default_width)
	if count == 1:
		return _get_legacy_point_width(0)

	var t = clamp(ratio, 0.0, 1.0) * float(count - 1)
	var i0 := int(floor(t))
	var i1 = min(i0 + 1, count - 1)
	var a = t - float(i0)
	return lerpf(_get_legacy_point_width(i0), _get_legacy_point_width(i1), a)


func get_lane_extents_at_offset(offset: float) -> Vector2:
	if not lane_profile_enabled:
		var legacy_half := get_width_at_offset(offset) * 0.5
		return Vector2(legacy_half, legacy_half)
	var sample := _lane_segment_sample(offset)
	var i0 := int(sample.get("from", 0))
	var i1 := int(sample.get("to", i0))
	var eased := float(sample.get("weight", 0.0))
	var left0 := float(_get_point_lane_count(i0, true)) * _get_point_lane_width(i0)
	var left1 := float(_get_point_lane_count(i1, true)) * _get_point_lane_width(i1)
	var right0 := float(_get_point_lane_count(i0, false)) * _get_point_lane_width(i0)
	var right1 := float(_get_point_lane_count(i1, false)) * _get_point_lane_width(i1)
	return Vector2(
		maxf(0.0, lerpf(left0, left1, eased)),
		maxf(0.0, lerpf(right0, right1, eased))
	)


func get_lateral_join_group() -> String:
	return lateral_join_group


func get_lateral_join_layers() -> int:
	return lateral_join_layers


func get_lateral_transition_length(at_end: bool) -> float:
	return lateral_join_end_transition_length if at_end else lateral_join_start_transition_length


func get_lane_extents_at_ratio(ratio: float) -> Vector2:
	if curve == null:
		var fallback_half := maxf(MIN_WIDTH, default_width) * 0.5
		return Vector2(fallback_half, fallback_half)
	return get_lane_extents_at_offset(clampf(ratio, 0.0, 1.0) * curve.get_baked_length())


func get_lane_layout_at_offset(offset: float) -> Dictionary:
	var extents := get_lane_extents_at_offset(offset)
	var sample := _lane_segment_sample(offset)
	var i0 := int(sample.get("from", 0))
	var i1 := int(sample.get("to", i0))
	var eased := float(sample.get("weight", 0.0))
	return {
		"enabled": lane_profile_enabled,
		"left_extent": extents.x,
		"right_extent": extents.y,
		"left_lanes_from": _get_point_lane_count(i0, true),
		"left_lanes_to": _get_point_lane_count(i1, true),
		"right_lanes_from": _get_point_lane_count(i0, false),
		"right_lanes_to": _get_point_lane_count(i1, false),
		"lane_width": lerpf(_get_point_lane_width(i0), _get_point_lane_width(i1), eased),
		"transition": eased,
	}


func get_width_profile_signature() -> String:
	var parts: Array[String] = [
		str(default_width),
		str(point_widths.size()),
		str(lane_profile_enabled),
	]
	for w in point_widths:
		parts.append(str(w))
	if lane_profile_enabled:
		parts.append(str(_lane_fast_preview_active))
		parts.append(str(lane_edit_preview_step))
		if live_lane_regeneration:
			parts.append(_build_live_lane_signature())
		else:
			parts.append("applied_lane_revision=%d" % _lane_generation_revision)
	return "|".join(parts)


func get_road_generation_sample_step(base_step: float) -> float:
	if lane_profile_enabled and _lane_fast_preview_active:
		return maxf(base_step, lane_edit_preview_step)
	return base_step


## Heavy edge consumers use a separate revision so normal lane editing can
## rebuild the road without recreating every prop and deformed mesh.
func get_dependent_width_profile_signature() -> String:
	var parts: Array[String] = [
		str(default_width),
		str(point_widths.size()),
		str(lane_profile_enabled),
	]
	for w in point_widths:
		parts.append(str(w))
	if lane_profile_enabled:
		if live_lane_regeneration:
			parts.append(_build_live_lane_signature())
		else:
			parts.append("applied_lane_dependents_revision=%d" % _lane_dependents_revision)
	return "|".join(parts)


func has_pending_lane_changes() -> bool:
	return _lane_changes_pending


func _track_lane_changes() -> void:
	var signature := _build_live_lane_signature()
	if _lane_signature_seen.is_empty():
		_lane_signature_seen = signature
		return
	if signature == _lane_signature_seen:
		return
	_lane_signature_seen = signature
	if live_lane_regeneration:
		_lane_generation_revision += 1
	else:
		_lane_changes_pending = true


func _build_live_lane_signature() -> String:
	var parts: Array[String] = [
		str(default_lanes_left),
		str(default_lanes_right),
		str(default_lane_width),
		str(point_lanes_left),
		str(point_lanes_right),
		str(point_lane_widths),
		str(point_lane_transition_lengths),
	]
	for transition in point_lane_transition_curves:
		parts.append(_curve_resource_signature(transition))
	return "|".join(parts)


func get_edge_profile_signature() -> String:
	return "|".join([
		str(shoulder_left_width),
		str(shoulder_right_width),
		str(sidewalk_left_width),
		str(sidewalk_right_width),
		str(sidewalk_height),
		str(outer_wall_height),
		str(terrain_override_enabled),
		str(terrain_left_width),
		str(terrain_right_width),
		str(intersection_override_enabled),
		str(weld_endpoint_snap_distance),
		str(weld_allow_endpoint_to_midpath),
		str(weld_strip_shoulder_sidewalk_at_intersections),
			str(weld_intersection_strip_length),
			str(adaptive_sampling_enabled),
			str(adaptive_sampling_advanced),
			str(adaptive_sampling_step_scale),
			str(adaptive_sampling_radius_scale),
			str(adaptive_sampling_offset),
		])


func get_terrain_height_profile_signature() -> String:
	return "|".join([
		str(terrain_height_profile_override_enabled),
		str(terrain_left_profile_continuation),
		str(terrain_right_profile_continuation),
		str(terrain_left_profile_distances),
		str(terrain_left_profile_heights),
		str(terrain_right_profile_distances),
		str(terrain_right_profile_heights),
		str(terrain_profile_to_base_blend_distance),
		str(terrain_profile_power),
	])


func get_orientation_profile_signature() -> String:
	return "|".join([
		str(road_orientation_override_enabled),
		str(road_orientation_mode),
		str(road_bank_max_degrees),
		str(road_bank_strength),
		str(road_bank_sample_distance),
	])


func has_orientation_overrides() -> bool:
	return road_orientation_override_enabled


func get_road_orientation_mode() -> int:
	return clampi(road_orientation_mode, ROAD_ORIENTATION_CURVE_UP, ROAD_ORIENTATION_BANK_INTO_CURVE)


func get_road_bank_max_degrees() -> float:
	return maxf(0.0, road_bank_max_degrees)


func get_road_bank_strength() -> float:
	return maxf(0.0, road_bank_strength)


func get_road_bank_sample_distance() -> float:
	return maxf(0.05, road_bank_sample_distance)


func has_intersection_overrides() -> bool:
	return intersection_override_enabled


func has_weld_overrides() -> bool:
	return intersection_override_enabled


func get_weld_endpoint_snap_distance() -> float:
	return maxf(0.1, weld_endpoint_snap_distance)


func get_weld_allow_endpoint_to_midpath() -> bool:
	return weld_allow_endpoint_to_midpath


func get_weld_strip_shoulder_sidewalk_at_intersections() -> bool:
	return weld_strip_shoulder_sidewalk_at_intersections


func get_weld_intersection_strip_length() -> float:
	return maxf(0.0, weld_intersection_strip_length)


func has_adaptive_sampling_overrides() -> bool:
	return intersection_override_enabled


func has_terrain_overrides() -> bool:
	return terrain_override_enabled


func get_adaptive_sampling_enabled() -> bool:
	return adaptive_sampling_enabled


func get_adaptive_sampling_advanced() -> bool:
	return adaptive_sampling_advanced


func get_adaptive_sampling_step_scale() -> float:
	return maxf(0.1, adaptive_sampling_step_scale)


func get_adaptive_sampling_radius_scale() -> float:
	return maxf(0.1, adaptive_sampling_radius_scale)


func get_adaptive_sampling_offset() -> float:
	return adaptive_sampling_offset


func get_shoulder_left_at_offset(_offset: float) -> float:
	return maxf(0.0, shoulder_left_width)


func get_shoulder_left_at_ratio(_ratio: float) -> float:
	return maxf(0.0, shoulder_left_width)


func get_shoulder_right_at_offset(_offset: float) -> float:
	return maxf(0.0, shoulder_right_width)


func get_shoulder_right_at_ratio(_ratio: float) -> float:
	return maxf(0.0, shoulder_right_width)


func get_sidewalk_left_at_offset(_offset: float) -> float:
	return maxf(0.0, sidewalk_left_width)


func get_sidewalk_left_at_ratio(_ratio: float) -> float:
	return maxf(0.0, sidewalk_left_width)


func get_sidewalk_right_at_offset(_offset: float) -> float:
	return maxf(0.0, sidewalk_right_width)


func get_sidewalk_right_at_ratio(_ratio: float) -> float:
	return maxf(0.0, sidewalk_right_width)


func get_sidewalk_height_at_offset(_offset: float) -> float:
	return maxf(0.0, sidewalk_height)


func get_sidewalk_height_at_ratio(_ratio: float) -> float:
	return maxf(0.0, sidewalk_height)


func get_outer_wall_height_at_offset(_offset: float) -> float:
	return maxf(0.0, outer_wall_height)


func get_outer_wall_height_at_ratio(_ratio: float) -> float:
	return maxf(0.0, outer_wall_height)


func get_terrain_widths_at_offset(_offset: float) -> Vector2:
	return Vector2(
		maxf(0.0, terrain_left_width),
		maxf(0.0, terrain_right_width)
	)


func get_terrain_widths_at_ratio(_ratio: float) -> Vector2:
	return Vector2(
		maxf(0.0, terrain_left_width),
		maxf(0.0, terrain_right_width)
	)


func get_terrain_left_at_offset(_offset: float) -> float:
	return maxf(0.0, terrain_left_width)


func get_terrain_left_at_ratio(_ratio: float) -> float:
	return maxf(0.0, terrain_left_width)


func get_terrain_right_at_offset(_offset: float) -> float:
	return maxf(0.0, terrain_right_width)


func get_terrain_right_at_ratio(_ratio: float) -> float:
	return maxf(0.0, terrain_right_width)


func has_terrain_height_profile_override() -> bool:
	return terrain_height_profile_override_enabled


func get_terrain_height_profile_override() -> Dictionary:
	return {
		"left_distances": terrain_left_profile_distances,
		"left_heights": terrain_left_profile_heights,
		"right_distances": terrain_right_profile_distances,
		"right_heights": terrain_right_profile_heights,
		"to_base_blend_distance": maxf(0.0, terrain_profile_to_base_blend_distance),
		"power": maxf(0.1, terrain_profile_power),
	}


func get_terrain_continuation_override() -> Dictionary:
	return {
		"left_continuation": terrain_left_profile_continuation,
		"right_continuation": terrain_right_profile_continuation,
	}


func _point_count() -> int:
	if curve == null:
		return 0
	return curve.point_count


func _get_point_width(index: int) -> float:
	if lane_profile_enabled:
		var lane_count := _get_point_lane_count(index, true) + _get_point_lane_count(index, false)
		return maxf(MIN_WIDTH, float(lane_count) * _get_point_lane_width(index))
	return _get_legacy_point_width(index)


func _get_legacy_point_width(index: int) -> float:
	if index >= 0 and index < point_widths.size():
		return max(MIN_WIDTH, float(point_widths[index]))
	return max(MIN_WIDTH, default_width)


func _get_point_tilt(index: int) -> float:
	if curve == null:
		return 0.0
	if index < 0 or index >= curve.point_count:
		return 0.0
	return curve.get_point_tilt(index)


func _sync_point_widths(repeat_last := true) -> void:
	var target := _point_count()
	if target <= 0:
		if not point_widths.is_empty():
			point_widths = PackedFloat32Array()
		return

	if point_widths.size() == target:
		var changed := false
		for i in range(point_widths.size()):
			var clamped = max(MIN_WIDTH, float(point_widths[i]))
			if not is_equal_approx(point_widths[i], clamped):
				point_widths[i] = clamped
				changed = true
		if changed:
			_last_signature = ""
		return

	var old := point_widths
	var next := PackedFloat32Array()
	next.resize(target)
	for i in range(target):
		var w := default_width
		if i < old.size():
			w = old[i]
		elif repeat_last and not old.is_empty():
			w = old[old.size() - 1]
		next[i] = max(MIN_WIDTH, w)
	point_widths = next
	_last_signature = ""


func _sync_lane_profiles(repeat_last := true) -> void:
	var target := _point_count()
	if target <= 0:
		point_lanes_left = PackedInt32Array()
		point_lanes_right = PackedInt32Array()
		point_lane_widths = PackedFloat32Array()
		point_lane_transition_lengths = PackedFloat32Array()
		point_lane_transition_curves = []
		return

	var old_left := point_lanes_left
	var old_right := point_lanes_right
	var old_widths := point_lane_widths
	var old_lengths := point_lane_transition_lengths
	var old_curves := point_lane_transition_curves
	var next_left := PackedInt32Array()
	var next_right := PackedInt32Array()
	var next_widths := PackedFloat32Array()
	var next_lengths := PackedFloat32Array()
	var next_curves: Array[Curve] = []
	next_left.resize(target)
	next_right.resize(target)
	next_widths.resize(target)
	next_lengths.resize(target)
	next_curves.resize(target)
	for i in range(target):
		var left_value := default_lanes_left
		var right_value := default_lanes_right
		var width_value := default_lane_width
		var transition_length := 0.0
		var transition: Curve
		if i < old_left.size():
			left_value = old_left[i]
		elif repeat_last and not old_left.is_empty():
			left_value = old_left[old_left.size() - 1]
		if i < old_right.size():
			right_value = old_right[i]
		elif repeat_last and not old_right.is_empty():
			right_value = old_right[old_right.size() - 1]
		if i < old_widths.size():
			width_value = old_widths[i]
		elif repeat_last and not old_widths.is_empty():
			width_value = old_widths[old_widths.size() - 1]
		if i < old_lengths.size():
			transition_length = old_lengths[i]
		elif repeat_last and not old_lengths.is_empty():
			transition_length = old_lengths[old_lengths.size() - 1]
		if i < old_curves.size():
			transition = old_curves[i]
		if transition == null:
			transition = _make_default_lane_transition_curve()
		next_left[i] = clampi(left_value, 0, MAX_LANES_PER_SIDE)
		next_right[i] = clampi(right_value, 0, MAX_LANES_PER_SIDE)
		next_widths[i] = maxf(MIN_LANE_WIDTH, width_value)
		next_lengths[i] = maxf(0.0, transition_length)
		next_curves[i] = transition

	if (
		point_lanes_left != next_left
		or point_lanes_right != next_right
		or point_lane_widths != next_widths
		or point_lane_transition_lengths != next_lengths
		or point_lane_transition_curves != next_curves
	):
		point_lanes_left = next_left
		point_lanes_right = next_right
		point_lane_widths = next_widths
		point_lane_transition_lengths = next_lengths
		point_lane_transition_curves = next_curves
		_last_signature = ""


func _has_lane_profile_storage() -> bool:
	return (
		not point_lanes_left.is_empty()
		or not point_lanes_right.is_empty()
		or not point_lane_widths.is_empty()
		or not point_lane_transition_lengths.is_empty()
		or not point_lane_transition_curves.is_empty()
	)


func _seed_lane_profiles_from_legacy_widths() -> void:
	var count := _point_count()
	if count <= 0:
		return
	point_lanes_left = PackedInt32Array()
	point_lanes_right = PackedInt32Array()
	point_lane_widths = PackedFloat32Array()
	point_lane_transition_lengths = PackedFloat32Array()
	point_lane_transition_curves = []
	point_lanes_left.resize(count)
	point_lanes_right.resize(count)
	point_lane_widths.resize(count)
	point_lane_transition_lengths.resize(count)
	point_lane_transition_curves.resize(count)
	var preferred_total := maxi(1, default_lanes_left + default_lanes_right)
	var left_ratio := float(default_lanes_left) / float(preferred_total)
	var offsets := _control_point_offsets()
	var curve_length := maxf(0.001, curve.get_baked_length())
	for i in range(count):
		var point_ratio := float(offsets[i]) / curve_length if i < offsets.size() else float(i) / float(maxi(1, count - 1))
		var legacy_width := maxf(MIN_WIDTH, _legacy_width_at_ratio(point_ratio))
		var total_lanes := clampi(roundi(legacy_width / maxf(MIN_LANE_WIDTH, default_lane_width)), 1, MAX_LANES_PER_SIDE * 2)
		var left_lanes := clampi(roundi(float(total_lanes) * left_ratio), 0, mini(total_lanes, MAX_LANES_PER_SIDE))
		var right_lanes := total_lanes - left_lanes
		if right_lanes > MAX_LANES_PER_SIDE:
			var overflow := right_lanes - MAX_LANES_PER_SIDE
			right_lanes = MAX_LANES_PER_SIDE
			left_lanes = mini(MAX_LANES_PER_SIDE, left_lanes + overflow)
		if default_lanes_left > 0 and default_lanes_right > 0 and total_lanes >= 2:
			left_lanes = maxi(1, left_lanes)
			right_lanes = maxi(1, total_lanes - left_lanes)
		point_lanes_left[i] = left_lanes
		point_lanes_right[i] = right_lanes
		point_lane_widths[i] = maxf(MIN_LANE_WIDTH, legacy_width / float(maxi(1, left_lanes + right_lanes)))
		point_lane_transition_lengths[i] = 0.0
		point_lane_transition_curves[i] = _make_default_lane_transition_curve()
	_last_signature = ""


func _make_default_lane_transition_curve() -> Curve:
	var transition := Curve.new()
	transition.min_domain = 0.0
	transition.max_domain = 1.0
	transition.min_value = 0.0
	transition.max_value = 1.0
	transition.add_point(Vector2(0.0, 0.0))
	transition.add_point(Vector2(1.0, 1.0))
	return transition


func _get_point_lane_count(index: int, left_side: bool) -> int:
	var values := point_lanes_left if left_side else point_lanes_right
	var fallback := default_lanes_left if left_side else default_lanes_right
	if index >= 0 and index < values.size():
		return clampi(int(values[index]), 0, MAX_LANES_PER_SIDE)
	return clampi(fallback, 0, MAX_LANES_PER_SIDE)


func _get_point_lane_width(index: int) -> float:
	if index >= 0 and index < point_lane_widths.size():
		return maxf(MIN_LANE_WIDTH, point_lane_widths[index])
	return maxf(MIN_LANE_WIDTH, default_lane_width)


func _get_point_lane_transition_length(index: int) -> float:
	if index >= 0 and index < point_lane_transition_lengths.size():
		return maxf(0.0, point_lane_transition_lengths[index])
	return 0.0


func _get_point_lane_transition(index: int) -> Curve:
	if index >= 0 and index < point_lane_transition_curves.size():
		return point_lane_transition_curves[index]
	return null


func _lane_segment_sample(offset: float) -> Dictionary:
	var count := _point_count()
	if count <= 1 or curve == null:
		return {"from": 0, "to": 0, "weight": 0.0}
	var offsets := _control_point_offsets()
	var clamped_offset := clampf(offset, 0.0, curve.get_baked_length())
	var i1 := count - 1
	for i in range(1, count):
		if clamped_offset <= float(offsets[i]) + 0.0001:
			i1 = i
			break
	var i0 := maxi(0, i1 - 1)
	var segment_start := float(offsets[i0])
	var segment_end := float(offsets[i1])
	var transition_start := segment_start
	var transition_length := _get_point_lane_transition_length(i1)
	if transition_length > 0.0001:
		transition_start = maxf(segment_start, segment_end - transition_length)
	var t := 0.0
	if segment_end > transition_start + 0.0001:
		t = clampf((clamped_offset - transition_start) / (segment_end - transition_start), 0.0, 1.0)
	var transition: Curve
	if i1 >= 0 and i1 < point_lane_transition_curves.size():
		transition = point_lane_transition_curves[i1]
	var eased := t
	if transition != null and transition.point_count > 0:
		var domain_x := lerpf(transition.min_domain, transition.max_domain, t)
		eased = clampf(transition.sample_baked(domain_x), 0.0, 1.0)
	return {"from": i0, "to": i1, "weight": eased}


func _control_point_offsets() -> PackedFloat32Array:
	var count := _point_count()
	if curve == null or count <= 0:
		return PackedFloat32Array()
	_ensure_control_offset_curve_connection()
	var curve_id := curve.get_instance_id()
	if (
		_control_offsets_cache_curve_id == curve_id
		and _control_offsets_cache_point_count == count
		and _control_offsets_cache.size() == count
	):
		return _control_offsets_cache

	var offsets := PackedFloat32Array()
	offsets.resize(count)
	var length := curve.get_baked_length()
	var previous := 0.0
	for i in range(count):
		var point_offset := curve.get_closest_offset(curve.get_point_position(i))
		if i == 0:
			point_offset = 0.0
		elif i == count - 1 and not curve.closed:
			point_offset = length
		point_offset = clampf(point_offset, previous, length)
		offsets[i] = point_offset
		previous = point_offset
	_control_offsets_cache = offsets
	_control_offsets_cache_curve_id = curve_id
	_control_offsets_cache_point_count = count
	return offsets


func _ensure_control_offset_curve_connection() -> void:
	if _connected_curve_for_offsets == curve:
		return
	if _connected_curve_for_offsets != null and _connected_curve_for_offsets.changed.is_connected(_invalidate_control_point_offsets_cache):
		_connected_curve_for_offsets.changed.disconnect(_invalidate_control_point_offsets_cache)
	_connected_curve_for_offsets = curve
	_invalidate_control_point_offsets_cache()
	if _connected_curve_for_offsets != null and not _connected_curve_for_offsets.changed.is_connected(_invalidate_control_point_offsets_cache):
		_connected_curve_for_offsets.changed.connect(_invalidate_control_point_offsets_cache)


func _invalidate_control_point_offsets_cache() -> void:
	_control_offsets_cache = PackedFloat32Array()
	_control_offsets_cache_curve_id = 0
	_control_offsets_cache_point_count = -1


func _curve_resource_signature(value: Curve) -> String:
	if value == null:
		return "null"
	var parts: Array[String] = [
		str(value.min_domain),
		str(value.max_domain),
		str(value.min_value),
		str(value.max_value),
		str(value.point_count),
	]
	for i in range(value.point_count):
		parts.append(str(value.get_point_position(i)))
		parts.append(str(value.get_point_left_tangent(i)))
		parts.append(str(value.get_point_right_tangent(i)))
		parts.append(str(value.get_point_left_mode(i)))
		parts.append(str(value.get_point_right_mode(i)))
	return ":".join(parts)


func _refresh_selected_point_fields() -> void:
	var count := _point_count()
	_syncing_selected_fields = true
	if count <= 0:
		selected_point_index = 0
		selected_point_width = max(MIN_WIDTH, default_width)
		selected_point_lanes_left = clampi(default_lanes_left, 0, MAX_LANES_PER_SIDE)
		selected_point_lanes_right = clampi(default_lanes_right, 0, MAX_LANES_PER_SIDE)
		selected_point_lane_width = maxf(MIN_LANE_WIDTH, default_lane_width)
		selected_point_lane_transition_length = 0.0
		selected_point_lane_transition = null
		_syncing_selected_fields = false
		if Engine.is_editor_hint():
			notify_property_list_changed()
		return

	selected_point_index = clamp(selected_point_index, 0, count - 1)
	selected_point_width = _get_point_width(selected_point_index)
	selected_point_tilt = _get_point_tilt(selected_point_index)
	selected_point_lanes_left = _get_point_lane_count(selected_point_index, true)
	selected_point_lanes_right = _get_point_lane_count(selected_point_index, false)
	selected_point_lane_width = _get_point_lane_width(selected_point_index)
	selected_point_lane_transition_length = _get_point_lane_transition_length(selected_point_index)
	selected_point_lane_transition = _get_point_lane_transition(selected_point_index)
	_syncing_selected_fields = false
	if Engine.is_editor_hint():
		notify_property_list_changed()


func _pull_selected_from_editor_selection() -> void:
	var count := _point_count()
	if count <= 0:
		return

	var root := get_node_or_null(HANDLES_NODE_NAME)
	if root == null:
		return

	var selection := EditorInterface.get_selection()
	if selection == null:
		return

	var nodes := selection.get_selected_nodes()
	for n in nodes:
		if not (n is Node):
			continue
		if n.get_parent() != root:
			continue
		if not n.has_meta(HANDLE_META_INDEX):
			continue
		var idx: int = clamp(int(n.get_meta(HANDLE_META_INDEX)), 0, count - 1)
		if idx != selected_point_index:
			_syncing_selected_fields = true
			selected_point_index = idx
			selected_point_width = _get_point_width(idx)
			selected_point_tilt = _get_point_tilt(idx)
			selected_point_lanes_left = _get_point_lane_count(idx, true)
			selected_point_lanes_right = _get_point_lane_count(idx, false)
			selected_point_lane_width = _get_point_lane_width(idx)
			selected_point_lane_transition_length = _get_point_lane_transition_length(idx)
			selected_point_lane_transition = _get_point_lane_transition(idx)
			_syncing_selected_fields = false
			_last_signature = ""
		return


func _rebuild_preview() -> void:
	if not Engine.is_editor_hint():
		return
	update_gizmos()
	if not show_width_preview or curve == null or curve.point_count < 2:
		_clear_preview()
		return

	var count := _point_count()
	if count < 2:
		_clear_preview()
		return

	var root := _get_or_create_handles_root()
	_assign_editor_owner(root)
	var handles: Array[MeshInstance3D] = []
	for child in root.get_children():
		var mi := child as MeshInstance3D
		if mi != null:
			_assign_editor_owner(mi)
			handles.push_back(mi)

	while handles.size() < count:
		var h := MeshInstance3D.new()
		root.add_child(h)
		_assign_editor_owner(h)
		handles.push_back(h)

	for i in range(handles.size()):
		if i >= count:
			handles[i].queue_free()
			continue
		_update_handle_node(handles[i], i, count)


func _width_preview_needs_rebuild() -> bool:
	if not show_width_preview or curve == null or curve.point_count < 2:
		return get_node_or_null(HANDLES_NODE_NAME) != null

	var root := get_node_or_null(HANDLES_NODE_NAME)
	if root == null:
		return true

	var handle_count := 0
	for child in root.get_children():
		if child is MeshInstance3D:
			handle_count += 1
	return handle_count != _point_count()


func _update_handle_node(handle: MeshInstance3D, index: int, count: int) -> void:
	if handle.get_script() != HANDLE_SCRIPT:
		handle.set_script(HANDLE_SCRIPT)

	var center := curve.get_point_position(index) + Vector3.UP * preview_height
	var basis := _compute_handle_basis(index, count)
	var road_handle_transform := _road_surface_handle_transform(index)
	if not road_handle_transform.is_empty():
		center = road_handle_transform.get("origin", center)

	var width = _get_point_width(index)
	var box := handle.mesh as BoxMesh
	if box == null:
		box = BoxMesh.new()
		handle.mesh = box
	box.size = Vector3(width, max(0.005, preview_thickness), max(0.02, preview_strip_width))

	handle.transform = Transform3D(basis, center)
	handle.name = "Handle_%03d" % index
	handle.set_meta(HANDLE_META_INDEX, index)
	handle.set_meta(HANDLE_META_SYNCED_ORIGIN, center)
	handle.set_meta(HANDLE_META_SYNCED_BASIS, basis)
	handle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	handle.material_override = _get_handle_material(index == selected_point_index)
	handle.visible = true
	if handle.has_method("sync_from_profile"):
		handle.call(
			"sync_from_profile",
			index,
			width,
			_get_point_tilt(index),
			_get_point_lane_count(index, true),
			_get_point_lane_count(index, false),
			_get_point_lane_width(index),
			_get_point_lane_transition_length(index),
			_get_point_lane_transition(index),
			lane_profile_enabled
		)


func _compute_point_forward(index: int, count: int) -> Vector3:
	if curve == null or count <= 1:
		return Vector3.FORWARD

	var forward := Vector3.ZERO
	var is_closed := false
	if curve.has_method("is_closed"):
		is_closed = bool(curve.call("is_closed"))
	elif curve.has_method("get_closed"):
		is_closed = bool(curve.call("get_closed"))

	if is_closed:
		var prev := curve.get_point_position((index - 1 + count) % count)
		var next := curve.get_point_position((index + 1) % count)
		forward = next - prev
	elif index <= 0:
		forward = curve.get_point_position(1) - curve.get_point_position(0)
	elif index >= count - 1:
		forward = curve.get_point_position(count - 1) - curve.get_point_position(count - 2)
	else:
		forward = curve.get_point_position(index + 1) - curve.get_point_position(index - 1)

	if forward.length() < 0.001:
		forward = curve.get_point_out(index) - curve.get_point_in(index)
	if forward.length() < 0.001:
		return Vector3.FORWARD
	return forward.normalized()


func _compute_handle_basis(index: int, count: int) -> Basis:
	var road_handle_transform := _road_surface_handle_transform(index)
	if not road_handle_transform.is_empty():
		var authoritative_basis: Basis = road_handle_transform.get("basis", Basis.IDENTITY)
		return authoritative_basis.orthonormalized()

	var forward := _compute_point_forward(index, count)
	var mode := _get_preview_orientation_mode()
	var up := Vector3.UP

	if mode == ROAD_ORIENTATION_CURVE_UP:
		up = _compute_preview_curve_up(index, count, forward)

	var right := up.cross(forward).normalized()
	if right.length() < 0.001:
		right = Vector3.RIGHT
	up = forward.cross(right).normalized()
	if up.length() < 0.001:
		up = Vector3.UP

	if mode == ROAD_ORIENTATION_BANK_INTO_CURVE:
		var bank_angle := _compute_preview_bank_angle(index, count)
		if absf(bank_angle) > 0.00001:
			var bank_roll := Basis(forward, bank_angle)
			right = (bank_roll * right).normalized()
			up = (bank_roll * up).normalized()

	var tilt := _get_point_tilt(index)
	if absf(tilt) > 0.00001:
		var tilt_roll := Basis(forward, tilt)
		right = (tilt_roll * right).normalized()
		up = (tilt_roll * up).normalized()

	return Basis(right, up, forward).orthonormalized()


func _road_surface_handle_transform(index: int) -> Dictionary:
	if curve == null or index < 0 or index >= curve.point_count:
		return {}
	var road_network: Node = get_parent()
	while road_network != null and not road_network.has_method("get_path_surface_frame"):
		road_network = road_network.get_parent()
	if road_network == null:
		return {}
	var offsets := _control_point_offsets()
	if index >= offsets.size():
		return {}
	var raw_frame: Variant = road_network.call("get_path_surface_frame", self, float(offsets[index]))
	if not raw_frame is Dictionary:
		return {}
	var frame: Dictionary = raw_frame
	var center_world: Vector3 = frame.get("center", global_position)
	var right_world: Vector3 = frame.get("right", Vector3.ZERO)
	var up_world: Vector3 = frame.get("up", Vector3.ZERO)
	var world_to_local := global_transform.basis.inverse()
	var right := (world_to_local * right_world).normalized()
	var up := (world_to_local * up_world).normalized()
	if right.length_squared() < 0.000001 or up.length_squared() < 0.000001:
		return {}
	var forward := right.cross(up).normalized()
	if forward.length_squared() < 0.000001:
		return {}
	up = forward.cross(right).normalized()
	var center_local := global_transform.affine_inverse() * center_world
	center_local += up * preview_height
	return {"basis": Basis(right, up, forward), "origin": center_local}


func _get_preview_orientation_mode() -> int:
	if road_orientation_override_enabled:
		return clampi(road_orientation_mode, ROAD_ORIENTATION_CURVE_UP, ROAD_ORIENTATION_BANK_INTO_CURVE)
	return ROAD_ORIENTATION_CURVE_UP


func _get_preview_bank_max_radians() -> float:
	return deg_to_rad(maxf(0.0, road_bank_max_degrees))


func _get_preview_bank_strength() -> float:
	return maxf(0.0, road_bank_strength)


func _get_preview_bank_sample_distance() -> float:
	return maxf(0.05, road_bank_sample_distance)


func _estimate_distance_at_point_index(index: int, count: int) -> float:
	if curve == null or count <= 1:
		return 0.0
	var idx := clampi(index, 0, count - 1)
	var distance := 0.0
	for i in range(1, idx + 1):
		distance += curve.get_point_position(i - 1).distance_to(curve.get_point_position(i))
	return distance


func _compute_preview_curve_up(index: int, count: int, forward: Vector3) -> Vector3:
	if curve != null and curve.has_method("sample_baked_up_vector"):
		var dist := _estimate_distance_at_point_index(index, count)
		var up: Vector3 = curve.sample_baked_up_vector(dist, false)
		if up.length() > 0.001:
			return up.normalized()

	var fallback_up := Vector3.UP
	var right := fallback_up.cross(forward).normalized()
	if right.length() < 0.001:
		right = Vector3.RIGHT
	var up := forward.cross(right).normalized()
	if up.length() < 0.001:
		up = Vector3.UP
	return up


func _compute_preview_bank_angle(index: int, count: int) -> float:
	if curve == null or count < 3:
		return 0.0

	var prev_idx := maxi(0, index - 1)
	var next_idx := mini(count - 1, index + 1)
	if prev_idx == index or next_idx == index:
		return 0.0

	var prev_pos := curve.get_point_position(prev_idx)
	var curr_pos := curve.get_point_position(index)
	var next_pos := curve.get_point_position(next_idx)

	var prev_dir := curr_pos - prev_pos
	var next_dir := next_pos - curr_pos
	prev_dir.y = 0.0
	next_dir.y = 0.0
	if prev_dir.length_squared() <= 0.000000000001 or next_dir.length_squared() <= 0.000000000001:
		return 0.0

	prev_dir = prev_dir.normalized()
	next_dir = next_dir.normalized()
	var signed_turn := atan2(prev_dir.cross(next_dir).y, prev_dir.dot(next_dir))
	return clampf(
		-signed_turn * _get_preview_bank_strength(),
		-_get_preview_bank_max_radians(),
		_get_preview_bank_max_radians()
	)


func _apply_handle_transforms_to_curve() -> bool:
	if curve == null:
		return false

	var count := _point_count()
	if count <= 0:
		return false

	var root := get_node_or_null(HANDLES_NODE_NAME)
	if root == null:
		return false

	# The editor may undo a handle transform after selection has changed.
	# Apply changes on every handle so the source curve follows that same action.
	var changed := false
	var changed_index := -1
	for child in root.get_children():
		var handle := child as Node3D
		if handle == null:
			continue
		if not handle.has_meta(HANDLE_META_INDEX):
			continue

		var idx := int(handle.get_meta(HANDLE_META_INDEX))
		if idx < 0 or idx >= count:
			continue

		var expected := curve.get_point_position(idx) + Vector3.UP * preview_height
		if handle.has_meta(HANDLE_META_SYNCED_ORIGIN):
			expected = handle.get_meta(HANDLE_META_SYNCED_ORIGIN)
		var expected_basis := _compute_handle_basis(idx, count)
		if handle.has_meta(HANDLE_META_SYNCED_BASIS):
			expected_basis = handle.get_meta(HANDLE_META_SYNCED_BASIS)
		var actual := handle.transform.origin
		var moved := actual.distance_to(expected) > 0.0005
		if moved:
			curve.set_point_position(idx, curve.get_point_position(idx) + (actual - expected))
			changed = true

		var actual_basis := handle.transform.basis.orthonormalized()
		var expected_quat := expected_basis.get_rotation_quaternion()
		var actual_quat := actual_basis.get_rotation_quaternion()
		var rotated := expected_quat.angle_to(actual_quat) > 0.001
		if rotated:
			var delta_basis := actual_basis * expected_basis.inverse()
			curve.set_point_in(idx, delta_basis * curve.get_point_in(idx))
			curve.set_point_out(idx, delta_basis * curve.get_point_out(idx))
			changed = true

		if not moved and not rotated:
			continue

		if changed_index < 0:
			changed_index = idx

	if changed and changed_index >= 0:
		_syncing_selected_fields = true
		selected_point_index = changed_index
		selected_point_width = _get_point_width(changed_index)
		selected_point_tilt = _get_point_tilt(changed_index)
		selected_point_lanes_left = _get_point_lane_count(changed_index, true)
		selected_point_lanes_right = _get_point_lane_count(changed_index, false)
		selected_point_lane_width = _get_point_lane_width(changed_index)
		selected_point_lane_transition_length = _get_point_lane_transition_length(changed_index)
		selected_point_lane_transition = _get_point_lane_transition(changed_index)
		_syncing_selected_fields = false

	return changed


func _get_or_create_handles_root() -> Node3D:
	var root := get_node_or_null(HANDLES_NODE_NAME) as Node3D
	if root != null:
		_assign_editor_owner(root)
		return root
	root = Node3D.new()
	root.name = HANDLES_NODE_NAME
	add_child(root)
	_assign_editor_owner(root)
	return root


func _clear_preview() -> void:
	var root := get_node_or_null(HANDLES_NODE_NAME)
	if root != null:
		root.queue_free()


func _assign_editor_owner(node: Node) -> void:
	if not Engine.is_editor_hint():
		return
	var scene_root := get_tree().edited_scene_root
	if scene_root != null:
		node.owner = scene_root


func _get_handle_material(selected: bool) -> StandardMaterial3D:
	if _normal_handle_material == null:
		_normal_handle_material = StandardMaterial3D.new()
		_normal_handle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_normal_handle_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_normal_handle_material.albedo_color = preview_color
		_normal_handle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	if _selected_handle_material == null:
		_selected_handle_material = StandardMaterial3D.new()
		_selected_handle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_selected_handle_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_selected_handle_material.albedo_color = selected_preview_color
		_selected_handle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_normal_handle_material.albedo_color = preview_color
	_selected_handle_material.albedo_color = selected_preview_color

	if selected:
		return _selected_handle_material
	return _normal_handle_material


func _build_signature() -> String:
	var parts: Array[String] = []
	parts.append(str(show_width_preview))
	parts.append(str(default_width))
	parts.append(str(shoulder_left_width))
	parts.append(str(shoulder_right_width))
	parts.append(str(sidewalk_left_width))
	parts.append(str(sidewalk_right_width))
	parts.append(str(sidewalk_height))
	parts.append(str(outer_wall_height))
	parts.append(str(road_orientation_override_enabled))
	parts.append(str(road_orientation_mode))
	parts.append(str(road_bank_max_degrees))
	parts.append(str(road_bank_strength))
	parts.append(str(road_bank_sample_distance))
	parts.append(str(terrain_override_enabled))
	parts.append(str(terrain_left_width))
	parts.append(str(terrain_right_width))
	parts.append(str(terrain_height_profile_override_enabled))
	parts.append(str(terrain_left_profile_continuation))
	parts.append(str(terrain_right_profile_continuation))
	parts.append(str(terrain_left_profile_distances))
	parts.append(str(terrain_left_profile_heights))
	parts.append(str(terrain_right_profile_distances))
	parts.append(str(terrain_right_profile_heights))
	parts.append(str(terrain_profile_to_base_blend_distance))
	parts.append(str(terrain_profile_power))
	parts.append(str(intersection_override_enabled))
	parts.append(str(weld_endpoint_snap_distance))
	parts.append(str(weld_allow_endpoint_to_midpath))
	parts.append(str(weld_strip_shoulder_sidewalk_at_intersections))
	parts.append(str(weld_intersection_strip_length))
	parts.append(str(adaptive_sampling_enabled))
	parts.append(str(adaptive_sampling_advanced))
	parts.append(str(adaptive_sampling_step_scale))
	parts.append(str(adaptive_sampling_radius_scale))
	parts.append(str(adaptive_sampling_offset))
	parts.append(str(selected_point_index))
	parts.append(str(selected_point_width))
	parts.append(str(selected_point_tilt))
	parts.append(str(lane_profile_enabled))
	parts.append(str(default_lanes_left))
	parts.append(str(default_lanes_right))
	parts.append(str(default_lane_width))
	parts.append(str(selected_point_lanes_left))
	parts.append(str(selected_point_lanes_right))
	parts.append(str(selected_point_lane_width))
	parts.append(str(selected_point_lane_transition_length))
	parts.append(_curve_resource_signature(selected_point_lane_transition))
	parts.append(str(auto_pick_selected_handle))
	parts.append(str(preview_height))
	parts.append(str(preview_strip_width))
	parts.append(str(preview_thickness))
	parts.append(str(preview_color))
	parts.append(str(selected_preview_color))
	parts.append(str(point_widths.size()))
	for w in point_widths:
		parts.append(str(w))
	parts.append(str(point_lanes_left))
	parts.append(str(point_lanes_right))
	parts.append(str(point_lane_widths))
	parts.append(str(point_lane_transition_lengths))
	for transition in point_lane_transition_curves:
		parts.append(_curve_resource_signature(transition))

	if curve == null:
		parts.append("null_curve")
		return "|".join(parts)

	parts.append(str(curve.point_count))
	for i in range(curve.point_count):
		parts.append(str(curve.get_point_position(i)))
		parts.append(str(curve.get_point_in(i)))
		parts.append(str(curve.get_point_out(i)))
		parts.append(str(curve.get_point_tilt(i)))
	return "|".join(parts)
