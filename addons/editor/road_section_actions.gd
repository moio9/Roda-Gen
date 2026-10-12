@tool
extends RefCounted
const APPEARANCE = preload("../scripts/spline_road/road_lane_appearance.gd")
const SECTION = preload("../scripts/spline_road/road_lane_section.gd")
const HISTORY = preload("../scripts/spline_road/road_editor_history.gd")


func apply(profile: Path3D, context: Dictionary, action: String) -> String:
	if not is_instance_valid(profile) or not profile.is_inside_tree() or profile.curve == null:
		return "Select a road section first."
	var start := clampf(float(context.start), 0.0, profile.curve.get_baked_length())
	var end := clampf(float(context.end), 0.0, profile.curve.get_baked_length())
	if end - start < 0.1:
		return "This section is too short."
	var geometry := action in ["lane", "bay", "remove"]
	var road: Node = context.get("road")
	var before := _capture(profile, road, geometry)
	var rules: Array = profile.lane_appearance_overrides.duplicate()
	if action.begins_with("line:"):
		context = _marking_target(profile, context, rules, start, end)
	var index := int(context.get("appearance_index", -1))
	var old: Resource = rules[index] if index >= 0 and index < rules.size() else null
	var rule: Resource
	if action == "remove":
		if not old is SECTION:
			return "Select the extra lane or stopping bay to remove it."
		rules.remove_at(index)
	elif action in ["lane", "bay"]:
		if old is SECTION:
			rule = old.duplicate()
		else:
			if not profile.lane_profile_enabled:
				profile.lane_profile_enabled = true
			var layout: Dictionary = profile.get_lane_layout_at_offset((start + end) * 0.5)
			var extent: float = layout.left_extent if context.side < 0 else layout.right_extent
			var lane := ceili(extent / maxf(0.01, layout.lane_width) - 0.0001) + 1
			if lane > 12:
				profile.restore_editor_state(before.profile)
				profile._lane_fast_preview_active = before.fast_preview
				return "This side already has the maximum 12 lanes."
			rule = SECTION.new()
			rule.side = context.side
			rule.lane = lane
			rule.start_offset = start
			rule.end_offset = end
			index = -1 # Preserve the clicked original lane's appearance.
		# A section targets a fixed outer lane. Do not fill missing intermediate
		# lanes on an existing variable-width merge or across another bay taper.
		if not old is SECTION:
			for sample in range(17):
				var layout: Dictionary = profile.get_lane_layout_at_offset(lerpf(start, end, sample / 16.0))
				var extent: float = layout.left_extent if context.side < 0 else layout.right_extent
				if absf(extent / maxf(0.01, layout.lane_width) - (rule.lane - 1)) > 0.01:
					profile.restore_editor_state(before.profile)
					profile._lane_fast_preview_active = before.fast_preview
					return "The selected side already changes width here. Choose a section with a constant lane count."
		rule.resource_name = "Stopping bay" if action == "bay" else "Additional lane"
		rule.enabled = true
		rule.inner_line_style = 2
		rule.outer_line_style = 1
		rule.transition_hatching = 0 if action == "bay" else 1
		rule.taper_length = minf(12.0 if action == "bay" else 25.0, (end - start) * 0.25)
	else:
		if old != null:
			rule = old.duplicate()
		else:
			rule = APPEARANCE.new()
			rule.side = context.side
			rule.lane = context.lane
			rule.start_offset = start
			rule.end_offset = end
			rule.resource_name = "Section markings"
		if action.begins_with("line:"):
			rule.set(context.get("field", "outer_line_style"), int(action.get_slice(":", 1)))
		elif action in ["stop_start", "stop_end"]:
			var property := "stop_line_at_start" if action == "stop_start" else "stop_line_at_end"
			rule.set(property, not rule.get(property))
		else:
			return "Unknown section action."
	if rule != null:
		if index >= 0:
			rules[index] = rule
		else:
			rules.append(rule)
	profile.lane_appearance_overrides.assign(rules)
	if is_instance_valid(road) and action != "remove":
		road.markings_enabled = true
	var after := _capture(profile, road, geometry)
	var history: Object = HISTORY.manager
	history.create_action("Road section: " + action, UndoRedo.MERGE_DISABLE, profile)
	history.add_do_method(self, "restore", profile, road, after, geometry)
	history.add_undo_method(self, "restore", profile, road, before, geometry)
	history.commit_action(false)
	_refresh(profile, road, geometry)
	return ""


func _capture(profile: Path3D, road: Node, geometry: bool) -> Dictionary:
	return {"profile": profile.capture_editor_state() if geometry else {},
		"rules": profile.lane_appearance_overrides.duplicate(),
		"fast_preview": profile._lane_fast_preview_active,
		"markings": road.markings_enabled if is_instance_valid(road) else false}


func restore(profile: Path3D, road: Node, state: Dictionary, geometry: bool) -> void:
	if not is_instance_valid(profile) or not profile.is_inside_tree():
		return
	profile.lane_appearance_overrides.assign(state.rules)
	if geometry:
		profile.restore_editor_state(state.profile)
		profile._lane_fast_preview_active = state.fast_preview
	if is_instance_valid(road):
		road.markings_enabled = state.markings
	_refresh(profile, road, geometry)


func _refresh(profile: Path3D, road: Node, geometry: bool) -> void:
	if geometry:
		var fast_preview: bool = profile._lane_fast_preview_active
		profile.rebuild_lane_dependents()
		profile._lane_fast_preview_active = fast_preview
	profile.notify_property_list_changed()
	profile._appearance_controls.sync(profile, profile._build_signature())
	if is_instance_valid(road):
		road.call_deferred("regenerate")


func _marking_target(profile: Path3D, selected: Dictionary, rules: Array, start: float, end: float) -> Dictionary:
	var target := selected.duplicate()
	var layout: Dictionary = profile.get_lane_layout_at_offset(selected.get("offset", (start + end) * 0.5))
	var extent: float = layout.left_extent if target.side < 0 else layout.right_extent
	if target.field == "inner_line_style" and target.lane == 1:
		# The right lane owns the shared center divider in the paint builder.
		target.side = 1
	elif target.field == "outer_line_style" and profile.lane_profile_enabled and target.lane * layout.lane_width < extent - 0.001:
		# The outer lane's inner override owns a shared separator.
		target.lane += 1
		target.field = "inner_line_style"
	target.appearance_index = -1
	for i in range(rules.size() - 1, -1, -1):
		var rule: Resource = rules[i]
		if rule == null or not rule.enabled or rule.side != target.side or rule.lane != target.lane:
			continue
		var rule_end: float = rule.end_offset if rule.end_offset > 0.0 else profile.curve.get_baked_length()
		if is_equal_approx(rule.start_offset, start) and is_equal_approx(rule_end, end):
			target.appearance_index = i
			break
	return target
