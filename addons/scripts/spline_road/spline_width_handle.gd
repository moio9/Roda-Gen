@tool
extends MeshInstance3D

@export_range(0, 2048, 1) var point_index := 0: set = _set_point_index
@export_range(0.1, 50.0, 0.1) var point_width := 6.0: set = _set_point_width
@export_range(-3.14159, 3.14159, 0.01) var point_tilt := 0.0: set = _set_point_tilt
@export var select_point_now := false: set = _set_select_point_now

var _syncing_from_profile := false


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


func _set_select_point_now(value: bool) -> void:
	select_point_now = false
	if not value:
		return
	var profile := _get_profile()
	if profile != null and profile.has_method("select_point_index"):
		profile.call("select_point_index", point_index)


func sync_from_profile(index: int, width: float, tilt: float) -> void:
	_syncing_from_profile = true
	point_index = max(0, index)
	point_width = max(0.1, width)
	point_tilt = tilt
	_syncing_from_profile = false


func _get_profile() -> Node:
	var p := get_parent()
	if p == null:
		return null
	return p.get_parent()
