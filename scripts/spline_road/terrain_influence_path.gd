@tool
extends Path3D

@export_group("Terrain Influence")
@export_range(0.2, 100.0, 0.1) var influence_width := 6.0
@export_range(0.0, 100.0, 0.1) var influence_blend := 3.0
@export_range(0.0, 1.0, 0.01) var influence_strength := 1.0
@export_range(1, 16, 1) var influence_band_count := 4
@export_range(0.2, 4.0, 0.01) var influence_profile_curve := 1.0
@export_range(-20.0, 20.0, 0.01) var influence_profile_height := 0.5
@export_group("Adaptive Sampling Override")
@export var adaptive_override_enabled := false: set = _set_adaptive_override_enabled
@export var adaptive_sampling_enabled := true
@export_subgroup("Adaptive Sampling", "adaptive_sampling_")
@export var adaptive_sampling_advanced := false: set = _set_adaptive_sampling_advanced
@export_range(0.1, 4.0, 0.01) var adaptive_sampling_step_scale := 1.0
@export_range(0.1, 4.0, 0.01) var adaptive_sampling_radius_scale := 1.0
@export_range(-10.0, 10.0, 0.01) var adaptive_sampling_offset := 0.0


func _set_adaptive_override_enabled(value: bool) -> void:
	adaptive_override_enabled = value
	if Engine.is_editor_hint():
		notify_property_list_changed()


func _set_adaptive_sampling_advanced(value: bool) -> void:
	adaptive_sampling_advanced = value
	if Engine.is_editor_hint():
		notify_property_list_changed()


func _validate_property(property: Dictionary) -> void:
	if (
		property.name == "adaptive_sampling_enabled"
		or property.name == "adaptive_sampling_advanced"
		or property.name == "adaptive_sampling_step_scale"
		or property.name == "adaptive_sampling_radius_scale"
		or property.name == "adaptive_sampling_offset"
	) and not adaptive_override_enabled:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if (
		property.name == "adaptive_sampling_radius_scale"
		or property.name == "adaptive_sampling_offset"
	) and (not adaptive_override_enabled or not adaptive_sampling_advanced):
		property.usage = PROPERTY_USAGE_NO_EDITOR


func is_terrain_influence_path() -> bool:
	return true


func get_terrain_influence_width() -> float:
	return maxf(0.2, influence_width)


func get_terrain_influence_flatten_blend() -> float:
	return maxf(0.0, influence_blend)


func get_terrain_influence_flatten_strength() -> float:
	return clampf(influence_strength, 0.0, 1.0)


func get_terrain_influence_band_count() -> int:
	return clampi(influence_band_count, 1, 16)


func get_terrain_influence_profile_curve() -> float:
	return clampf(influence_profile_curve, 0.2, 4.0)


func get_terrain_influence_profile_height() -> float:
	return influence_profile_height


func has_adaptive_sampling_overrides() -> bool:
	return adaptive_override_enabled


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
