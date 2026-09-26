@tool
extends RefCounted
const SPAN = preload("./road_lane_appearance_span.gd")
const CONTAINER := "__LaneAppearanceHandles"


func sync(profile: Path3D, geometry_signature: String) -> void:
	var container := profile.get_node_or_null(CONTAINER)
	if not profile.show_lane_appearance_handles or profile.lane_appearance_overrides.is_empty():
		if container != null:
			container.hide()
			if profile.lane_appearance_overrides.is_empty():
				for span in container.get_children():
					_retire(span)
		return
	if container == null:
		container = Node3D.new()
		container.name = CONTAINER
		profile.add_child(container)
		container.owner = profile.get_tree().edited_scene_root
	container.show()
	var remaining := container.get_children()
	var selected: Array = EditorInterface.get_selection().get_selected_nodes()
	var inspected: Object = EditorInterface.get_inspector().get_edited_object()
	for index in range(profile.lane_appearance_overrides.size()):
		var appearance: Resource = profile.lane_appearance_overrides[index]
		if appearance == null:
			continue
		var span: Node3D
		for node in remaining:
			if node.get_script() == SPAN and node.appearance == appearance:
				span = node
				remaining.erase(node)
				break
		if span == null:
			span = SPAN.new()
			span.name = "Range_%03d" % (index + 1)
			span.appearance = appearance
			container.add_child(span, true)
		span.owner = container.owner
		var highlighted := selected.has(profile) or selected.has(span) or inspected == appearance
		for node in selected:
			highlighted = highlighted or span.is_ancestor_of(node)
		span.sync(profile, geometry_signature, highlighted)
	for unused in remaining:
		_retire(unused)


func _retire(span: Node3D) -> void:
	# Keep native transform history targets alive if a removed array entry is
	# restored by Undo. Retired proxies are hidden and excluded from saved scenes.
	span.hide()
	span.owner = null
	for child in span.get_children():
		child.owner = null
