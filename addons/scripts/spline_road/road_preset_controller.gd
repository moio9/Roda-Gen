@tool
extends RefCounted
## One-shot templates with scene-local resources and a single editor history action.

const PRESET = preload("./road_preset.gd")
const BARRIER_MESH = preload("./road_preset_barrier_mesh.gd")
const DEFORMER = preload("./spline_mesh_deformer.gd")
const HISTORY = preload("./road_editor_history.gd")
const BUILTINS := [preload("../../presets/mountain.tres"), preload("../../presets/urban.tres"), preload("../../presets/highway.tres")]
const NODE_NAME := "PresetBarriers"
const OWNED_META := "roda_preset_owned"
const EDGES := ["shoulder_left_width", "shoulder_right_width", "sidewalk_left_width", "sidewalk_right_width", "sidewalk_height"]


func apply(road: Node3D, requested: Resource = null) -> Error:
	var preset: Resource = requested
	if preset == null:
		preset = BUILTINS[road.preset_selection] if road.preset_selection in range(3) else road.custom_preset
	if not preset is PRESET or not preset.is_valid():
		return ERR_INVALID_PARAMETER
	if not road.is_inside_tree() or road._is_generation_thread_active():
		return ERR_BUSY
	var paths: Array[Path3D] = road._resolve_paths()
	if paths.is_empty():
		return ERR_DOES_NOT_EXIST
	var old_container: Node = road.get_node_or_null(NODE_NAME)
	if road.preset_replace_barriers and old_container != null and not old_container.get_meta(OWNED_META, false):
		return ERR_ALREADY_EXISTS
	var copies: Dictionary = {}
	var values: Dictionary = preset.road_values()
	if not road.preset_replace_lane_layout:
		values.erase("road_width")
	var before := {"road": _capture(road, values.keys()), "profiles": [], "replace_barriers": road.preset_replace_barriers,
		"container": old_container, "owners": _capture_owners(old_container)}
	var after := {"road": _copy_values(values, copies), "profiles": [], "replace_barriers": road.preset_replace_barriers,
		"container": old_container, "owners": before.owners}
	for path in paths:
		if not path.has_method("restore_preset_properties"):
			continue
		var profile_values: Dictionary = {}
		if road.preset_apply_path_settings:
			for property in EDGES:
				profile_values[property] = preset.get(property)
			profile_values["road_orientation_override_enabled"] = false
		if road.preset_replace_lane_layout:
			profile_values.merge(_lane_values(path, preset))
		if profile_values.is_empty():
			continue
		profile_values["_lane_fast_preview_active"] = false
		profile_values["_lane_changes_pending"] = false
		before.profiles.append({"node": path, "values": _capture(path, profile_values.keys())})
		after.profiles.append({"node": path, "values": profile_values})
	if road.preset_replace_barriers:
		var container := Node3D.new()
		container.name = NODE_NAME
		container.set_meta(OWNED_META, true)
		after.container = container
		after.owners = []
		# Freeze the template, not the generated Nodes. Redo restores those exact Nodes.
		after.pending_preset = preset.duplicate(true)
	var history: Object = HISTORY.manager if Engine.is_editor_hint() else null
	if is_instance_valid(history):
		history.create_action("Apply %s road preset" % preset.display_name, UndoRedo.MERGE_DISABLE, road)
		history.add_do_method(road, "_apply_road_preset_state", after)
		history.add_undo_method(road, "_apply_road_preset_state", before)
		if road.preset_replace_barriers:
			history.add_do_reference(after.container)
			if old_container != null:
				history.add_undo_reference(old_container)
		history.commit_action()
	else:
		apply_state(road, after)
		if road.preset_replace_barriers and is_instance_valid(old_container):
			old_container.free()
	return OK


func apply_state(road: Node3D, state: Dictionary) -> void:
	# An Undo can arrive during a later threaded rebuild. Do not mutate its snapshots.
	road._cancel_thread_job()
	road._join_generation_thread()
	road._thread_regenerate_requested = false
	road._pending_regenerate_signature = ""
	var current: Node = road.get_node_or_null(NODE_NAME)
	if state.replace_barriers and current != null and current != state.container:
		if not current.get_meta(OWNED_META, false):
			push_warning("Roda-Gen: unrelated PresetBarriers node blocks history restore.")
			return
		# Include user details added after the action was first committed. Removing
		# a subtree clears external owners; restore the latest list when reattached.
		current.set_meta("_roda_preset_detached_owners", _capture_owners(current))
		road.remove_child(current)
	for property in state.road:
		road.set(property, _copy_array(state.road[property]))
	for entry in state.profiles:
		if is_instance_valid(entry.node):
			entry.node.restore_preset_properties(entry.values)
	# Explicit preset application finishes synchronously so junction clearances use
	# the new road dimensions, and immediate bake cannot omit unfinished barriers.
	var threaded: bool = road.threaded_generation_enabled
	road.threaded_generation_enabled = false
	road.regenerate()
	road.threaded_generation_enabled = threaded
	road._last_signature = road._build_signature()
	if state.replace_barriers and is_instance_valid(state.container):
		var container: Node = state.container
		if container.get_parent() == null:
			road.add_child(container)
		if state.has("pending_preset"):
			_populate_barriers(road, container, state.pending_preset)
			_assign_source_owners(road, container)
			state.owners = _capture_owners(container)
			state.erase("pending_preset")
		else:
			var owners: Array = container.get_meta("_roda_preset_detached_owners", state.owners)
			if container.has_meta("_roda_preset_detached_owners"):
				container.remove_meta("_roda_preset_detached_owners")
			for entry in owners:
				if is_instance_valid(entry.node) and is_instance_valid(entry.owner) and entry.owner.is_ancestor_of(entry.node):
					entry.node.owner = entry.owner
	refresh_barriers(road, true)
	if Engine.is_editor_hint():
		road.notify_property_list_changed()


func refresh_barriers(road: Node3D, force := false) -> void:
	var container := owned_container(road)
	if container == null:
		return
	for child in container.get_children():
		if not child is DEFORMER:
			continue
		if not force and Engine.is_editor_hint() and not child.auto_regenerate_in_editor:
			continue
		if force or child._last_signature != child._build_signature():
			child.regenerate()


func outputs_are_current(road: Node3D) -> bool:
	var container := owned_container(road)
	if container != null:
		for child in container.get_children():
			if child is DEFORMER and not child.is_generated_output_current():
				return false
	return true


func owned_container(road: Node3D) -> Node:
	var container := road.get_node_or_null(NODE_NAME)
	return container if container != null and container.get_meta(OWNED_META, false) else null


func _populate_barriers(road: Node3D, container: Node, preset: Resource) -> void:
	var source: Mesh = preset.barrier_mesh
	if source == null:
		source = BARRIER_MESH.build(preset.barrier_style)
	else:
		source = source.duplicate(true)
	if source == null:
		return
	var material: Material = preset.barrier_material.duplicate(true) if preset.barrier_material != null else null
	var paths: Array[Path3D] = road._resolve_paths()
	for index in range(paths.size()):
		var path := paths[index]
		if path.curve == null or path.curve.point_count < 2 or road._path_is_terrain_influence_only(path):
			continue
		var length := path.curve.get_baked_length()
		var spans := allowed_spans(length, preset.barrier_end_clearance, road._marking_exclusions.get(index, []))
		for span: Vector2 in spans:
			for placement in [3, 0]:
				if (placement == 3 and not preset.barrier_outer_edges) or (placement == 0 and not preset.barrier_center):
					continue
				var deformer := DEFORMER.new()
				deformer.name = "%s_%s_%d" % ["Edge" if placement == 3 else "Center", path.name, container.get_child_count()]
				deformer.source_path = NodePath("../../" + str(road.get_path_to(path)))
				deformer.road_network_source = NodePath("../..")
				deformer.source_mesh = source
				deformer.deform_axis = 2
				deformer.placement_mode = placement
				deformer.start_offset = span.x
				deformer.span_length = span.y - span.x
				deformer.outward_offset = preset.barrier_outward_offset if placement == 3 else 0.0
				deformer.vertical_offset = preset.barrier_vertical_offset
				deformer.curve_subdivision_step = preset.barrier_subdivision_step
				deformer.generate_collision = preset.barrier_generate_collision
				deformer.material_override = material
				container.add_child(deformer)


static func allowed_spans(length: float, clearance: float, exclusions: Array) -> Array[Vector2]:
	var spans: Array[Vector2] = []
	if length > clearance * 2.0 + 0.05:
		spans.append(Vector2(clearance, length - clearance))
	for exclusion: Vector2 in exclusions:
		var next: Array[Vector2] = []
		for span in spans:
			if exclusion.y <= span.x or exclusion.x >= span.y:
				next.append(span)
				continue
			if exclusion.x - span.x > 0.05:
				next.append(Vector2(span.x, minf(span.y, exclusion.x)))
			if span.y - exclusion.y > 0.05:
				next.append(Vector2(maxf(span.x, exclusion.y), span.y))
		spans = next
	return spans


func _lane_values(path: Path3D, preset: Resource) -> Dictionary:
	var count := path.curve.point_count if path.curve != null else 0
	var left := PackedInt32Array()
	var right := PackedInt32Array()
	var widths := PackedFloat32Array()
	var transitions := PackedFloat32Array()
	var total_widths := PackedFloat32Array()
	var curves: Array[Curve] = []
	for i in range(count):
		left.append(preset.lanes_left)
		right.append(preset.lanes_right)
		widths.append(preset.lane_width)
		transitions.append(preset.lane_transition_length)
		total_widths.append((preset.lanes_left + preset.lanes_right) * preset.lane_width)
		curves.append(preset.lane_transition_curve.duplicate(true) if preset.lane_transition_curve != null else null)
	return {"lane_profile_enabled": true, "default_width": (preset.lanes_left + preset.lanes_right) * preset.lane_width,
		"point_widths": total_widths, "default_lanes_left": preset.lanes_left, "default_lanes_right": preset.lanes_right,
		"default_lane_width": preset.lane_width, "point_lanes_left": left, "point_lanes_right": right,
		"point_lane_widths": widths, "point_lane_transition_lengths": transitions, "point_lane_transition_curves": curves}


func _capture(object: Object, properties: Array) -> Dictionary:
	var values: Dictionary = {}
	for property in properties:
		values[property] = _copy_array(object.get(property))
	return values


func _copy_values(values: Dictionary, copies: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for property in values:
		var value: Variant = values[property]
		if value is Resource:
			if not copies.has(value):
				copies[value] = value.duplicate(true)
			value = copies[value]
		result[property] = _copy_array(value)
	return result


func _copy_array(value: Variant) -> Variant:
	return value.duplicate() if value is Array or value is PackedFloat32Array or value is PackedInt32Array else value


func _capture_owners(node: Node) -> Array:
	var owners: Array = []
	if node == null:
		return owners
	if node.owner != null:
		owners.append({"node": node, "owner": node.owner})
	for child in node.get_children():
		owners.append_array(_capture_owners(child))
	return owners


func _assign_source_owners(road: Node, container: Node) -> void:
	var scene: Node = road.get_tree().edited_scene_root if Engine.is_editor_hint() else road.owner
	if scene == null or not scene.is_ancestor_of(container):
		return
	container.owner = scene
	for child in container.get_children():
		child.owner = scene
		if child is DEFORMER:
			child._ensure_span_handles()
			for handle in child.get_children():
				if handle is Marker3D:
					handle.owner = scene
