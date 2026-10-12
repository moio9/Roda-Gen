@tool
extends "./road_lane_appearance.gd"
class_name RoadLaneSection
## A tapered outer lane plus its appearance. The authored spline stays intact.
@export_group("Lane Shape")
## Entry and exit taper; automatically limited to half the interval.
@export_range(0.5, 1000.0, 0.5, "suffix:m") var taper_length := 12.0


func snapshot() -> Dictionary:
	var rule := super.snapshot()
	if not rule.is_empty():
		# Transverse lines belong at the full-width ends, not the zero-width
		# tips where the extra lane meets the original road.
		rule.stop_line_inset = maxf(0.5, taper_length)
	return rule


func geometry_snapshot() -> Dictionary:
	if snapshot().is_empty() or not is_finite(taper_length):
		return {}
	return {"side": -1 if side < 0 else 1, "lane": clampi(lane, 1, 12),
		"start": maxf(0.0, start_offset), "end": maxf(0.0, end_offset),
		"taper": maxf(0.5, taper_length)}


func weight_at(distance: float, path_length: float) -> float:
	var end := minf(path_length, end_offset) if end_offset > 0.0 else path_length
	var start := maxf(0.0, start_offset)
	if not enabled or end <= start or distance <= start or distance >= end:
		return 0.0
	var taper := minf(maxf(0.5, taper_length), (end - start) * 0.5)
	return smoothstep(0.0, taper, minf(distance - start, end - distance))


func sample_offsets(path_length: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	if geometry_snapshot().is_empty():
		return result
	var start := clampf(start_offset, 0.0, path_length)
	var end := clampf(end_offset, 0.0, path_length) if end_offset > 0.0 else path_length
	if end <= start:
		return result
	var taper := minf(maxf(0.5, taper_length), (end - start) * 0.5)
	for i in range(5):
		result.append(start + taper * i / 4.0)
		result.append(end - taper * i / 4.0)
	return result
