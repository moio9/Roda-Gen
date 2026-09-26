@tool
extends Node3D
## Editor proxy. Authoritative shape/settings live on the parent modifier.
@export_storage var point_index := 0
@export var modifier_custom_radius: bool:
	get:
		var profile := _get_profile()
		return profile != null and profile._point_value(profile.point_radii, point_index, -1.0) >= 0.0
	set(value):
		_set_profile_value("selected_point_custom_radius", value)
@export_range(0.1, 1000.0, 0.1, "or_greater", "suffix:m") var modifier_radius: float:
	get:
		var profile := _get_profile()
		return profile._point_radius(point_index) if profile != null else 35.0
	set(value):
		_set_profile_value("selected_point_radius", value)
@export_range(0.0, 10.0, 0.01, "or_greater") var modifier_strength_scale: float:
	get:
		var profile := _get_profile()
		return profile._point_value(profile.point_strength_scales, point_index, 1.0) if profile != null else 1.0
	set(value):
		_set_profile_value("selected_point_strength_scale", value)
@export_range(-500.0, 500.0, 0.01, "or_greater", "or_less", "suffix:m") var modifier_height_offset: float:
	get:
		var profile := _get_profile()
		return profile._point_value(profile.point_height_offsets, point_index, 0.0) if profile != null else 0.0
	set(value):
		_set_profile_value("selected_point_height_offset", value)

var _syncing := true
var _synced_transform := Transform3D.IDENTITY
var _synced_points: Array = []


func _ready() -> void:
	_synced_transform = transform
	set_notify_local_transform(Engine.is_editor_hint())
	_syncing = false


func _validate_property(property: Dictionary) -> void:
	if str(property.name).begins_with("modifier_"):
		property.usage = int(property.usage) & ~PROPERTY_USAGE_STORAGE


func _get_profile() -> Node:
	var container := get_parent()
	if container == null:
		return null
	var profile := container.get_parent()
	return profile if profile != null and profile.has_method("_point_radius") else null


func _set_profile_value(property: String, value: Variant) -> void:
	if _syncing:
		return
	var profile := _get_profile()
	if profile == null:
		return
	profile.select_point_index(point_index)
	profile.set(property, value)


func sync_from_profile(index: int, frame: Transform3D) -> void:
	_syncing = true
	point_index = index
	var profile := _get_profile()
	var points: Array = _curve_point_state(profile)
	if points != _synced_points:
		if transform != frame:
			transform = frame
		_synced_transform = frame
		_synced_points = points
	_syncing = false


func _notification(what: int) -> void:
	if what != NOTIFICATION_LOCAL_TRANSFORM_CHANGED or _syncing or not Engine.is_editor_hint():
		return
	var profile := _get_profile()
	if profile == null or profile.curve == null or point_index >= profile.curve.point_count:
		return
	if transform == _synced_transform:
		return
	var original: Array = [profile.curve.get_point_position(point_index), profile.curve.get_point_in(point_index), profile.curve.get_point_out(point_index)]
	_syncing = true
	profile.apply_point_editor_transform(point_index, _synced_transform, transform, original)
	_synced_transform = transform
	_synced_points = _curve_point_state(profile)
	_syncing = false


func _curve_point_state(profile: Node) -> Array:
	if profile == null or profile.curve == null or point_index < 0 or point_index >= profile.curve.point_count:
		return []
	return [profile.curve.get_point_position(point_index), profile.curve.get_point_in(point_index), profile.curve.get_point_out(point_index)]
