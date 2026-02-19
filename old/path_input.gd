@tool
extends Path3D

@export_group("Sources")
@export var builder_path: NodePath

@export_group("Road")
@export var use_overrides := false: set = _set_use_overrides
@export_subgroup("Geometry")
@export_range(0.2, 30.0, 0.1) var road_width := 6.0: set = _set_road_width
@export_range(0.1, 50.0, 0.1) var sample_step := 6.0: set = _set_sample_step
@export_range(-5.0, 5.0, 0.01) var y_offset := 0.02: set = _set_y_offset
@export_subgroup("Edges")
@export_range(0.0, 15.0, 0.1) var shoulder_left_width := 0.0: set = _set_shoulder_left_width
@export_range(0.0, 15.0, 0.1) var shoulder_right_width := 0.0: set = _set_shoulder_right_width
@export_range(0.0, 15.0, 0.1) var sidewalk_left_width := 0.0: set = _set_sidewalk_left_width
@export_range(0.0, 15.0, 0.1) var sidewalk_right_width := 0.0: set = _set_sidewalk_right_width
@export_subgroup("Profiles")
@export var use_per_point_profiles := false: set = _set_use_per_point_profiles
@export var per_point_widths: PackedFloat32Array = PackedFloat32Array(): set = _set_per_point_widths
@export var per_point_bank_degrees: PackedFloat32Array = PackedFloat32Array(): set = _set_per_point_bank_degrees

@export_group("Workflow")
@export var regenerate_button := false: set = _set_regenerate_button

# Compatibility fields kept for older scene files.
var regenerate_now := false
var profile_point_index := 0
var profile_point_position := 0.0
var profile_point_count := 0
var profile_point_width := 6.0
var profile_point_bank_deg := 0.0
var profile_prev_point_now := false
var profile_next_point_now := false
var sync_profile_count_now := false
var copy_curve_tilt_to_bank_now := false
var intersection_radius := 5.0
var snap_radius := 0.8
var intersection_snap_radius := 1.4
var split_margin := 0.15

var _suppress_profile_setters := false


func get_road_builder_settings() -> Dictionary:
	if not use_overrides:
		return {}
	return {
		"road_width": road_width,
		"sample_step": sample_step,
		"y_offset": y_offset,
		"shoulder_left_width": shoulder_left_width,
		"shoulder_right_width": shoulder_right_width,
		"sidewalk_left_width": sidewalk_left_width,
		"sidewalk_right_width": sidewalk_right_width,
		"use_per_point_profiles": use_per_point_profiles,
		"per_point_widths": per_point_widths,
		"per_point_bank_degrees": per_point_bank_degrees,
	}


func _set_use_overrides(v: bool) -> void:
	use_overrides = v
	_maybe_regenerate()


func _set_road_width(v: float) -> void:
	road_width = v
	_maybe_regenerate()


func _set_sample_step(v: float) -> void:
	sample_step = v
	_maybe_regenerate()


func _set_y_offset(v: float) -> void:
	y_offset = v
	_maybe_regenerate()


func _set_shoulder_left_width(v: float) -> void:
	shoulder_left_width = maxf(0.0, v)
	_maybe_regenerate()


func _set_shoulder_right_width(v: float) -> void:
	shoulder_right_width = maxf(0.0, v)
	_maybe_regenerate()


func _set_sidewalk_left_width(v: float) -> void:
	sidewalk_left_width = maxf(0.0, v)
	_maybe_regenerate()


func _set_sidewalk_right_width(v: float) -> void:
	sidewalk_right_width = maxf(0.0, v)
	_maybe_regenerate()


func _set_use_per_point_profiles(v: bool) -> void:
	use_per_point_profiles = v
	_ensure_profile_arrays()
	_maybe_regenerate()


func _set_per_point_widths(v: PackedFloat32Array) -> void:
	per_point_widths = v
	if _suppress_profile_setters:
		return
	_ensure_profile_arrays()
	_maybe_regenerate()


func _set_per_point_bank_degrees(v: PackedFloat32Array) -> void:
	per_point_bank_degrees = v
	if _suppress_profile_setters:
		return
	_ensure_profile_arrays()
	_maybe_regenerate()


func _set_regenerate_button(v: bool) -> void:
	regenerate_button = false
	if v:
		_trigger_regenerate()


func _maybe_regenerate() -> void:
	if Engine.is_editor_hint() and is_inside_tree() and get_tree() != null:
		_trigger_regenerate()


func _curve_point_count() -> int:
	if curve == null:
		return 0
	return curve.point_count


func _ensure_profile_arrays() -> void:
	var n := _curve_point_count()
	profile_point_count = n
	if n <= 0:
		return
	if profile_point_index >= n:
		profile_point_index = n - 1

	if per_point_widths.size() != n:
		var old_w := per_point_widths
		_suppress_profile_setters = true
		per_point_widths = PackedFloat32Array()
		per_point_widths.resize(n)
		for i in range(n):
			per_point_widths[i] = old_w[i] if i < old_w.size() else road_width
		_suppress_profile_setters = false

	if per_point_bank_degrees.size() != n:
		var old_b := per_point_bank_degrees
		_suppress_profile_setters = true
		per_point_bank_degrees = PackedFloat32Array()
		per_point_bank_degrees.resize(n)
		for i in range(n):
			per_point_bank_degrees[i] = old_b[i] if i < old_b.size() else 0.0
		_suppress_profile_setters = false


func _trigger_regenerate() -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	var builder = _find_road_builder()
	if builder and builder.has_method("regenerate"):
		builder.call_deferred("regenerate")


func _find_road_builder():
	if not is_inside_tree() or get_tree() == null:
		return null
	if builder_path != NodePath():
		var linked = get_node_or_null(builder_path)
		if linked and linked.has_method("regenerate"):
			return linked

	var parent := get_parent()
	while parent:
		if parent.has_method("regenerate") and parent.has_method("_get_path_settings"):
			return parent
		parent = parent.get_parent()

	var grouped = get_tree().get_nodes_in_group("custom_mesh_road_builder")
	if grouped.size() > 0:
		return grouped[0]

	var root := get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	if root == null:
		root = get_tree().root
	return _find_in_tree(root)


func _find_in_tree(node: Node):
	if node == null:
		return null
	if node.has_method("regenerate") and node.has_method("_get_path_settings"):
		return node
	for c in node.get_children():
		var hit = _find_in_tree(c)
		if hit:
			return hit
	return null
