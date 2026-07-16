@tool
extends Path3D
class_name SplinePathProfile3D

@export_group("Road")
@export_subgroup("Width")
@export_range(0.2, 50.0, 0.1) var default_width := 6.0
@export var point_widths := PackedFloat32Array()
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

@export_group("Weld")
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
const ROAD_ORIENTATION_CURVE_UP := 0
const ROAD_ORIENTATION_WORLD_UP := 1
const ROAD_ORIENTATION_BANK_INTO_CURVE := 2
const HANDLE_SCRIPT: Script = preload("res://addons/scripts/spline_road/spline_width_handle.gd")

var _last_signature := ""
var _syncing_selected_fields := false
var _normal_handle_material: StandardMaterial3D
var _selected_handle_material: StandardMaterial3D


func _ready() -> void:
	set_process(true)
	if not Engine.is_editor_hint():
		return
	_sync_point_widths()
	_refresh_selected_point_fields()
	_rebuild_preview()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var moved_curve_points := _apply_selected_handle_transforms_to_curve()
	_sync_point_widths()
	if auto_pick_selected_handle:
		_pull_selected_from_editor_selection()

	var sig := _build_signature()
	if moved_curve_points:
		_last_signature = ""
	if sig == _last_signature:
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
	_syncing_selected_fields = false
	_last_signature = ""


func _validate_property(property: Dictionary) -> void:
	var count := _point_count()
	if count <= 0 and (
		property.name == "selected_point_index"
		or property.name == "selected_point_width"
		or property.name == "selected_point_tilt"
		or property.name == "selected_point_prev"
		or property.name == "selected_point_next"
	):
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
	var length = max(0.001, curve.get_baked_length())
	var ratio = clamp(offset / length, 0.0, 1.0)
	return get_width_at_ratio(ratio)


func get_width_at_ratio(ratio: float) -> float:
	var count := _point_count()
	if count <= 0:
		return max(MIN_WIDTH, default_width)
	if count == 1:
		return _get_point_width(0)

	var t = clamp(ratio, 0.0, 1.0) * float(count - 1)
	var i0 := int(floor(t))
	var i1 = min(i0 + 1, count - 1)
	var a = t - float(i0)
	return lerpf(_get_point_width(i0), _get_point_width(i1), a)


func get_width_profile_signature() -> String:
	var parts: Array[String] = [str(default_width), str(point_widths.size())]
	for w in point_widths:
		parts.append(str(w))
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


func _point_count() -> int:
	if curve == null:
		return 0
	return curve.point_count


func _get_point_width(index: int) -> float:
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


func _refresh_selected_point_fields() -> void:
	var count := _point_count()
	_syncing_selected_fields = true
	if count <= 0:
		selected_point_index = 0
		selected_point_width = max(MIN_WIDTH, default_width)
		_syncing_selected_fields = false
		if Engine.is_editor_hint():
			notify_property_list_changed()
		return

	selected_point_index = clamp(selected_point_index, 0, count - 1)
	selected_point_width = _get_point_width(selected_point_index)
	selected_point_tilt = _get_point_tilt(selected_point_index)
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
			_syncing_selected_fields = false
			_last_signature = ""
		return


func _rebuild_preview() -> void:
	if not Engine.is_editor_hint():
		return
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


func _update_handle_node(handle: MeshInstance3D, index: int, count: int) -> void:
	if handle.get_script() != HANDLE_SCRIPT:
		handle.set_script(HANDLE_SCRIPT)

	var center := curve.get_point_position(index) + Vector3.UP * preview_height
	var basis := _compute_handle_basis(index, count)

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
		handle.call("sync_from_profile", index, width, _get_point_tilt(index))


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


func _apply_selected_handle_transforms_to_curve() -> bool:
	if curve == null:
		return false

	var count := _point_count()
	if count <= 0:
		return false

	var root := get_node_or_null(HANDLES_NODE_NAME)
	if root == null:
		return false

	var selection := EditorInterface.get_selection()
	if selection == null:
		return false

	var selected: Dictionary = {}
	for n in selection.get_selected_nodes():
		if not (n is Node):
			continue
		if n.get_parent() != root:
			continue
		selected[n.get_instance_id()] = true
	if selected.is_empty():
		return false

	var changed := false
	var changed_index := -1
	for child in root.get_children():
		var handle := child as Node3D
		if handle == null:
			continue
		if not selected.has(handle.get_instance_id()):
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
			curve.set_point_position(idx, actual - Vector3.UP * preview_height)
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
	parts.append(str(auto_pick_selected_handle))
	parts.append(str(preview_height))
	parts.append(str(preview_strip_width))
	parts.append(str(preview_thickness))
	parts.append(str(preview_color))
	parts.append(str(selected_preview_color))
	parts.append(str(point_widths.size()))
	for w in point_widths:
		parts.append(str(w))

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
