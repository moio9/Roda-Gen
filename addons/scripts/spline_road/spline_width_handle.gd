@tool
extends MeshInstance3D

@export_range(0, 2048, 1) var point_index := 0: set = _set_point_index
@export_range(0.1, 50.0, 0.1) var point_width := 6.0: set = _set_point_width
@export_range(-3.14159, 3.14159, 0.01) var point_tilt := 0.0: set = _set_point_tilt
@export_group("Directional Lanes")
## Compatibility storage for scenes saved with the old duplicated global toggle.
@export_storage var lane_profile_enabled := false
@export_tool_button("Enable Directional Lanes For Road") var enable_lane_profile_action := _enable_lane_profile
@export_range(0, 12, 1) var lanes_left := 1: set = _set_lanes_left
@export_range(0, 12, 1) var lanes_right := 1: set = _set_lanes_right
@export_range(1.5, 20.0, 0.05, "suffix:m") var lane_width := 3.5: set = _set_lane_width
@export_range(0.0, 1000.0, 0.5, "suffix:m") var lane_transition_length := 0.0: set = _set_lane_transition_length
## Easing used by the segment entering this point.
@export var lane_transition: Curve: set = _set_lane_transition
@export_tool_button("Apply Lane Changes") var apply_lane_changes_action := _apply_lane_changes
@export_tool_button("Rebuild Road + Terrain") var rebuild_lane_terrain_action := _rebuild_lane_terrain
@export_tool_button("Rebuild Lane Dependents (Slow)") var rebuild_lane_dependents_action := _rebuild_lane_dependents
@export_group("")
@export var select_point_now := false: set = _set_select_point_now

var _syncing_from_profile := false
var _lane_profile_active := false


func _set_point_index(value: int) -> void:
	point_index = max(0, value)
	if _syncing_from_profile:
		return
	var profile := _get_profile()
	if profile != null and profile.has_method("select_point_index"):
		profile.call("select_point_index", point_index)


func _set_point_width(value: float) -> void:
	point_width = max(0.1, value)
	if _syncing_from_profile:
		return
	var profile := _get_profile()
	if profile != null and profile.has_method("set_point_width_at_index"):
		profile.call("set_point_width_at_index", point_index, point_width)


func _set_point_tilt(value: float) -> void:
	point_tilt = value
	if _syncing_from_profile:
		return
	var profile := _get_profile()
	if profile != null and profile.has_method("set_point_tilt_at_index"):
		profile.call("set_point_tilt_at_index", point_index, point_tilt)


func _enable_lane_profile() -> void:
	var profile := _get_profile()
	if profile != null:
		profile.call("enable_lane_profile_with_undo")
	_lane_profile_active = true
	notify_property_list_changed()


func _set_lanes_left(value: int) -> void:
	lanes_left = clampi(value, 0, 12)
	if _syncing_from_profile:
		return
	var profile := _get_profile()
	if profile != null and profile.has_method("set_point_lane_count_at_index"):
		profile.call("set_point_lane_count_at_index", point_index, true, lanes_left)


func _set_lanes_right(value: int) -> void:
	lanes_right = clampi(value, 0, 12)
	if _syncing_from_profile:
		return
	var profile := _get_profile()
	if profile != null and profile.has_method("set_point_lane_count_at_index"):
		profile.call("set_point_lane_count_at_index", point_index, false, lanes_right)


func _set_lane_width(value: float) -> void:
	lane_width = maxf(1.5, value)
	if _syncing_from_profile:
		return
	var profile := _get_profile()
	if profile != null and profile.has_method("set_point_lane_width_at_index"):
		profile.call("set_point_lane_width_at_index", point_index, lane_width)


func _set_lane_transition_length(value: float) -> void:
	lane_transition_length = maxf(0.0, value)
	if _syncing_from_profile:
		return
	var profile := _get_profile()
	if profile != null and profile.has_method("set_point_lane_transition_length_at_index"):
		profile.call("set_point_lane_transition_length_at_index", point_index, lane_transition_length)


func _set_lane_transition(value: Curve) -> void:
	lane_transition = value
	if _syncing_from_profile:
		return
	var profile := _get_profile()
	if profile != null and profile.has_method("set_point_lane_transition_at_index"):
		profile.call("set_point_lane_transition_at_index", point_index, lane_transition)


func _apply_lane_changes() -> void:
	var profile := _get_profile()
	if profile != null and profile.has_method("apply_lane_changes"):
		profile.call("apply_lane_changes")


func _rebuild_lane_terrain() -> void:
	var profile := _get_profile()
	if profile != null and profile.has_method("rebuild_lane_terrain"):
		profile.call("rebuild_lane_terrain")


func _rebuild_lane_dependents() -> void:
	var profile := _get_profile()
	if profile != null and profile.has_method("rebuild_lane_dependents"):
		profile.call("rebuild_lane_dependents")


func _set_select_point_now(value: bool) -> void:
	select_point_now = false
	if not value:
		return
	var profile := _get_profile()
	if profile != null and profile.has_method("select_point_index"):
		profile.call("select_point_index", point_index)


func _validate_property(property: Dictionary) -> void:
	if property.name == "enable_lane_profile_action" and _lane_profile_active:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name in ["lanes_left", "lanes_right", "lane_width", "lane_transition_length", "lane_transition"] and not _lane_profile_active:
		property.usage = PROPERTY_USAGE_NO_EDITOR


func sync_from_profile(
	index: int,
	width: float,
	tilt: float,
	left_lane_count: int,
	right_lane_count: int,
	profile_lane_width: float,
	transition_length: float,
	transition: Curve,
	lane_profile_active: bool
) -> void:
	var lane_visibility_changed := _lane_profile_active != lane_profile_active
	_syncing_from_profile = true
	point_index = max(0, index)
	point_width = max(0.1, width)
	point_tilt = tilt
	lane_profile_enabled = lane_profile_active
	lanes_left = clampi(left_lane_count, 0, 12)
	lanes_right = clampi(right_lane_count, 0, 12)
	lane_width = maxf(1.5, profile_lane_width)
	lane_transition_length = maxf(0.0, transition_length)
	lane_transition = transition
	_lane_profile_active = lane_profile_active
	_syncing_from_profile = false
	if lane_visibility_changed:
		notify_property_list_changed()


func _get_profile() -> Node:
	var p := get_parent()
	if p == null:
		return null
	return p.get_parent()
