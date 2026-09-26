@tool
extends Path3D
class_name TerrainInfluencePath3D

@export_group("Terrain Influence")
@export_subgroup("Width")
@export_range(0.2, 100.0, 0.1, "or_greater", "suffix:m") var influence_width := 6.0
@export var point_widths := PackedFloat32Array()
@export_subgroup("Terrain Continuation")
## Requires TerrainTopologyBuilder3D. Extends this side to the generated bounds
## or another nearer source. Choose the inward side to fill a closed loop.
@export_enum("Local Band", "Continue To Terrain Bounds") var terrain_left_continuation := 0
@export_enum("Local Band", "Continue To Terrain Bounds") var terrain_right_continuation := 0
@export_subgroup("Flatten")
@export_range(0.0, 100.0, 0.1, "or_greater", "suffix:m") var influence_blend := 3.0
@export_range(0.0, 1.0, 0.01) var influence_strength := 1.0
@export_range(1, 16, 1) var influence_band_count := 4
@export_subgroup("Cross Profile")
@export_range(0.2, 4.0, 0.01) var influence_profile_curve := 1.0
@export_range(-20.0, 20.0, 0.01, "or_greater", "or_less", "suffix:m") var influence_profile_height := 0.5
@export var point_profile_heights := PackedFloat32Array()
@export var influence_use_profile_graph := false: set = _set_influence_use_profile_graph
@export var influence_profile_graph: Curve
@export_range(2, 256, 1) var influence_profile_graph_samples := 33
@export_subgroup("Surface Mesh")
@export var generate_influence_surface := true
@export_subgroup("Road Snap")
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:m") var over_road_edge_snap_band := 0.0
@export var clip_base_terrain_by_influence_loop := true
@export_group("Adaptive Sampling Override")
@export var adaptive_override_enabled := false: set = _set_adaptive_override_enabled
@export var adaptive_sampling_enabled := true
@export_subgroup("Adaptive Sampling", "adaptive_sampling_")
@export var adaptive_sampling_advanced := false: set = _set_adaptive_sampling_advanced
@export_range(0.1, 4.0, 0.01) var adaptive_sampling_step_scale := 1.0
@export_range(0.1, 4.0, 0.01) var adaptive_sampling_radius_scale := 1.0
@export_range(-10.0, 10.0, 0.01, "or_greater", "or_less", "suffix:m") var adaptive_sampling_offset := 0.0


func _set_adaptive_override_enabled(value: bool) -> void:
	adaptive_override_enabled = value
	if Engine.is_editor_hint():
		notify_property_list_changed()


func _set_influence_use_profile_graph(value: bool) -> void:
	influence_use_profile_graph = value
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
	if (
		property.name == "influence_profile_graph"
		or property.name == "influence_profile_graph_samples"
	) and not influence_use_profile_graph:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name == "clip_base_terrain_by_influence_loop" and not generate_influence_surface:
		property.usage = PROPERTY_USAGE_NO_EDITOR


func is_terrain_influence_path() -> bool:
	return true


func get_terrain_influence_width() -> float:
	return maxf(0.2, influence_width)


func get_terrain_influence_width_at_offset(offset: float) -> float:
	if curve == null or curve.point_count <= 0:
		return maxf(0.2, influence_width)
	var length := maxf(0.001, curve.get_baked_length())
	var ratio := clampf(offset / length, 0.0, 1.0)
	return get_terrain_influence_width_at_ratio(ratio)


func get_terrain_influence_width_at_ratio(ratio: float) -> float:
	var count := _point_count()
	if count <= 0:
		return maxf(0.2, influence_width)
	if count == 1:
		return _get_point_width(0)
	var t := clampf(ratio, 0.0, 1.0) * float(count - 1)
	var i0 := int(floor(t))
	var i1 = min(i0 + 1, count - 1)
	var a := t - float(i0)
	return maxf(0.2, lerpf(_get_point_width(i0), _get_point_width(i1), a))


func get_terrain_influence_width_profile_signature() -> String:
	var parts: Array[String] = [str(influence_width), str(point_widths.size())]
	for w in point_widths:
		parts.append(str(w))
	return "|".join(parts)


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


func get_terrain_influence_profile_height_at_offset(offset: float) -> float:
	if curve == null or curve.point_count <= 0:
		return influence_profile_height
	var length := maxf(0.001, curve.get_baked_length())
	var ratio := clampf(offset / length, 0.0, 1.0)
	return get_terrain_influence_profile_height_at_ratio(ratio)


func get_terrain_influence_profile_height_at_ratio(ratio: float) -> float:
	var count := _point_count()
	if count <= 0:
		return influence_profile_height
	if count == 1:
		return _get_point_profile_height(0)
	var t := clampf(ratio, 0.0, 1.0) * float(count - 1)
	var i0 := int(floor(t))
	var i1 = min(i0 + 1, count - 1)
	var a := t - float(i0)
	return lerpf(_get_point_profile_height(i0), _get_point_profile_height(i1), a)


func get_terrain_influence_height_profile_signature() -> String:
	var parts: Array[String] = [str(influence_profile_height), str(point_profile_heights.size())]
	for h in point_profile_heights:
		parts.append(str(h))
	return "|".join(parts)


func has_terrain_influence_profile_graph() -> bool:
	return influence_use_profile_graph and influence_profile_graph != null


func get_terrain_influence_profile_graph_samples() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if not has_terrain_influence_profile_graph():
		return out
	var sample_count := clampi(influence_profile_graph_samples, 2, 256)
	out.resize(sample_count)
	for i in range(sample_count):
		var t := float(i) / float(sample_count - 1)
		out[i] = clampf(float(influence_profile_graph.sample_baked(t)), 0.0, 1.0)
	return out


func get_terrain_influence_profile_signature() -> String:
	var parts: Array[String] = [
		str(influence_profile_curve),
		str(influence_profile_height),
		str(point_profile_heights.size()),
		str(influence_use_profile_graph),
		str(influence_profile_graph_samples),
		str(terrain_left_continuation),
		str(terrain_right_continuation),
	]
	for h in point_profile_heights:
		parts.append(str(h))
	var samples := get_terrain_influence_profile_graph_samples()
	parts.append(str(samples.size()))
	for v in samples:
		parts.append(str(v))
	return "|".join(parts)


func should_generate_terrain_influence_surface() -> bool:
	return generate_influence_surface


func get_over_road_edge_snap_band() -> float:
	return maxf(0.0, over_road_edge_snap_band)


func should_clip_base_terrain_by_influence_loop() -> bool:
	if not generate_influence_surface:
		return false
	return clip_base_terrain_by_influence_loop


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


func _point_count() -> int:
	if curve == null:
		return 0
	return curve.point_count


func _get_point_width(index: int) -> float:
	if index >= 0 and index < point_widths.size():
		return maxf(0.2, float(point_widths[index]))
	return maxf(0.2, influence_width)


func _get_point_profile_height(index: int) -> float:
	if index >= 0 and index < point_profile_heights.size():
		return float(point_profile_heights[index])
	return influence_profile_height
