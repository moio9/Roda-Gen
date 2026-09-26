@tool
extends Resource
class_name RoadLaneAppearance
## Appearance of one lane on one source path. Lanes count from the center out.
@export var enabled := true
@export_enum("Left:-1", "Right:1") var side := 1
@export_range(1, 12, 1) var lane := 2
@export_range(0.0, 100000.0, 0.1, "or_greater", "suffix:m") var start_offset := 0.0
## Zero means the end of the source path. Distances follow its authored direction.
@export_range(0.0, 100000.0, 0.1, "or_greater", "suffix:m") var end_offset := 0.0
@export_group("Markings")
## Shared separators are drawn once. The outer lane's inner override takes priority.
@export_enum("Inherit:-1", "Off:0", "Solid:1", "Dashed:2", "Double Solid:3", "Double Dashed:4") var inner_line_style := -1
## Applies to the outside separator, or the road edge while this is the outer lane.
@export_enum("Inherit:-1", "Off:0", "Solid:1", "Dashed:2", "Double Solid:3", "Double Dashed:4") var outer_line_style := -1
## Transition hatching only; this does not fill the full lane with diagonal stripes.
@export_enum("Inherit:-1", "Off:0", "On:1") var transition_hatching := -1
@export_subgroup("Stop Lines")
## Optional transverse line across this lane, inside the configured range.
@export var stop_line_at_start := false
@export var stop_line_at_end := false
@export_range(0.05, 2.0, 0.05, "suffix:m") var stop_line_width := 0.4
@export_group("Surface")
## Optional asphalt material for this lane and interval. Empty inherits the road.
@export var surface_material: Material


func snapshot() -> Dictionary:
	if not enabled or not is_finite(start_offset) or not is_finite(end_offset):
		return {}
	var start := maxf(0.0, start_offset)
	var end := end_offset if end_offset > 0.0 else INF
	if end <= start:
		return {}
	return {"side": -1 if side < 0 else 1, "lane": clampi(lane, 1, 12),
		"start": start, "end": end,
		"inner_line_style": clampi(inner_line_style, -1, 4),
		"outer_line_style": clampi(outer_line_style, -1, 4),
		"transition_hatching": clampi(transition_hatching, -1, 1),
		"stop_line_at_start": stop_line_at_start, "stop_line_at_end": stop_line_at_end,
		"stop_line_width": clampf(stop_line_width, 0.05, 2.0),
		"surface_material": surface_material}


static func intervals(rules: Array, start: float, end: float) -> PackedFloat64Array:
	var offsets := PackedFloat64Array([start, end])
	for rule: Dictionary in rules:
		for value: float in [rule.start, rule.end]:
			if value > start and value < end and not offsets.has(value):
				offsets.append(value)
	offsets.sort()
	return offsets


static func paint_rules(rules: Array) -> Array:
	var result: Array = []
	for rule: Dictionary in rules:
		if rule.inner_line_style < 0 and rule.outer_line_style < 0 and rule.transition_hatching < 0 and not rule.stop_line_at_start and not rule.stop_line_at_end:
			continue
		var paint := rule.duplicate()
		paint.erase("surface_material")
		result.append(paint)
	return result


static func in_range(rules: Array, start: float, end: float) -> Array:
	var result: Array = []
	for rule: Dictionary in rules:
		if rule.start < end and rule.end > start:
			result.append(rule)
	return result


static func value_at(rules: Array, side_: int, lane_: int, distance: float, field: String, fallback: Variant) -> Variant:
	for i in range(rules.size() - 1, -1, -1):
		var rule: Dictionary = rules[i]
		if rule.side != side_ or rule.lane != lane_ or distance < rule.start or distance >= rule.end:
			continue
		var value: Variant = rule.get(field)
		if value != null and not (value is int and value == -1):
			return value
	return fallback
