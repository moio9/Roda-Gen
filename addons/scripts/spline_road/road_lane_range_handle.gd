@tool
extends MeshInstance3D
## Native transform Undo/Redo moves this proxy and updates the same resource.
@export_storage var at_end := false
@export_range(0.0, 100000.0, 0.1, "or_greater", "suffix:m") var offset: float:
	get:
		var span := get_parent()
		if span == null or span.appearance == null:
			return 0.0
		return span.appearance.end_offset if at_end else span.appearance.start_offset
	set(value):
		var span := get_parent()
		if span != null and span.appearance != null:
			span.set_offset(at_end, value)
var _syncing := true
var _synced_position := Vector3.ZERO
var _offset_at_position: Dictionary = {}


func _ready() -> void:
	set_notify_local_transform(Engine.is_editor_hint())
	_synced_position = position
	_syncing = false
	if not Engine.is_editor_hint():
		hide()


func _validate_property(property: Dictionary) -> void:
	if property.name == "offset":
		property.usage = int(property.usage) & ~PROPERTY_USAGE_STORAGE


func sync_position(value: Vector3) -> void:
	_syncing = true
	position = value
	_synced_position = value
	_offset_at_position[value] = offset
	if _offset_at_position.size() > 512:
		_offset_at_position.erase(_offset_at_position.keys()[0])
	_syncing = false


func _notification(what: int) -> void:
	if what != NOTIFICATION_LOCAL_TRANSFORM_CHANGED or _syncing or not Engine.is_editor_hint():
		return
	if position.distance_squared_to(_synced_position) < 0.000001:
		return
	var span := get_parent()
	if span != null and span.has_method("move_endpoint"):
		if _offset_at_position.has(position):
			span.set_offset(at_end, _offset_at_position[position])
		else:
			span.move_endpoint(at_end, global_position)
			_offset_at_position[position] = offset
	_synced_position = position
