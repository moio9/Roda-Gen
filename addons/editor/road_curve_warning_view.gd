@tool
extends RefCounted
## Displays cached generation diagnostics only for the selected source paths.
var button: Button
var timer: Timer
var overlay: MeshInstance3D
var regions: Array[Dictionary] = []
var _paths: Array[Path3D] = []
var _roads: Dictionary = {}
var _signature := ""
const NEAR_COLOR := Color(1.0, 0.68, 0.06, 1.0)
const FOLD_COLOR := Color(1.0, 0.12, 0.15, 1.0)


func setup(plugin: EditorPlugin, toolbar: HBoxContainer) -> void:
	button = Button.new()
	button.text = "Curve Check"
	button.toggle_mode = true
	button.button_pressed = true
	button.toggled.connect(func(_active: bool): refresh(true))
	toolbar.add_child(button)
	timer = Timer.new()
	timer.wait_time = 0.4
	timer.timeout.connect(refresh)
	plugin.add_child(timer)
	timer.start()


func cleanup() -> void:
	_clear_overlay()
	timer.stop()
	timer.queue_free()


func select_paths(paths: Array[Path3D], roads: Dictionary) -> void:
	_paths = paths.duplicate()
	_roads = roads.duplicate()
	refresh(true)


func refresh(force := false) -> void:
	var keys: Array = []
	for path in _paths:
		if not is_instance_valid(path) or not path.is_inside_tree():
			continue
		var road: Node3D = _roads.get(path.get_instance_id())
		if is_instance_valid(road) and road.has_method("get_curve_width_report"):
			keys.append([path.get_instance_id(), road.get_instance_id(), road.get_curve_width_revision(), road.global_transform])
	var signature := str(keys)
	if not force and signature == _signature:
		return
	_signature = signature
	_clear_overlay()
	regions.clear()
	var line_vertices := PackedVector3Array()
	var line_colors := PackedColorArray()
	var fills := PackedVector3Array()
	var fill_colors := PackedColorArray()
	var checked := 0
	for path in _paths:
		if not is_instance_valid(path) or not path.is_inside_tree():
			continue
		var road: Node3D = _roads.get(path.get_instance_id())
		if not is_instance_valid(road) or not road.has_method("get_curve_width_report"):
			continue
		var report: Dictionary = road.get_curve_width_report()
		var ids: Array = report.get("path_ids", [])
		var path_id := ids.find(path.get_instance_id())
		if path_id < 0:
			continue
		checked += 1
		for region: Dictionary in report.get("regions", []):
			if region.path_id == path_id:
				var displayed := region.duplicate()
				displayed["path_name"] = str(path.name)
				regions.append(displayed)
		if not button.button_pressed:
			continue
		for segment: Dictionary in report.get("segments", []):
			if segment.path_id != path_id:
				continue
			var color := FOLD_COLOR if segment.folded else NEAR_COLOR
			var lift: Vector3 = segment.up * 0.08
			var c0: Vector3 = road.global_transform * (segment.center0 + lift)
			var c1: Vector3 = road.global_transform * (segment.center1 + lift)
			var e0: Vector3 = road.global_transform * (segment.edge0 + lift)
			var e1: Vector3 = road.global_transform * (segment.edge1 + lift)
			for point in [e0, e1, c0, e0]:
				line_vertices.append(point)
				line_colors.append(color)
			color.a = 0.18
			for point in [c0, e0, c1, c1, e0, e1]:
				fills.append(point)
				fill_colors.append(color)
	var folded := 0
	var lines := PackedStringArray(["Asphalt width versus local curve shape (last road generation)."])
	for region in regions:
		folded += int(region.folded)
		if lines.size() <= 12:
			lines.append("%s · %s · %.1f–%.1f m: %s" % [region.path_name,
				"left" if region.side < 0 else "right", region.start, region.end,
				"folded / collapsed" if region.folded else "close to folding"])
	if regions.size() > 12:
		lines.append("… %d more intervals" % (regions.size() - 12))
	if checked == 0:
		button.text = "Curve Check: regenerate road"
		button.remove_theme_color_override("font_color")
	elif regions.is_empty():
		button.text = "Curve Check: OK"
		button.remove_theme_color_override("font_color")
	else:
		button.text = "Curve Check: %d folded, %d close" % [folded, regions.size() - folded]
		button.add_theme_color_override("font_color", FOLD_COLOR if folded > 0 else NEAR_COLOR)
	lines.append("Yellow: inner strip below 20% of center advance. Red: folded or collapsed.")
	lines.append("Reduce the inside width or open the curve using its points/tangents, then regenerate.")
	lines.append("Click to show/hide. Source asphalt only: not a check of crossings, terrain or final junction trimming.")
	button.tooltip_text = "\n".join(lines)
	if line_vertices.is_empty() or EditorInterface.get_edited_scene_root() == null:
		return
	var mesh := ArrayMesh.new()
	_surface(mesh, Mesh.PRIMITIVE_TRIANGLES, fills, fill_colors)
	_surface(mesh, Mesh.PRIMITIVE_LINES, line_vertices, line_colors)
	overlay = MeshInstance3D.new()
	overlay.name = "__RoadCurveWarnings"
	overlay.mesh = mesh
	overlay.top_level = true
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay.set_meta("_edit_lock_", true)
	# Independent of a hidden source profile; internal and ownerless, never saved.
	EditorInterface.get_edited_scene_root().add_child(overlay, false, Node.INTERNAL_MODE_BACK)
	overlay.global_transform = Transform3D.IDENTITY


func _surface(mesh: ArrayMesh, primitive: Mesh.PrimitiveType, vertices: PackedVector3Array, colors: PackedColorArray) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(primitive, arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)


func _clear_overlay() -> void:
	if is_instance_valid(overlay):
		overlay.queue_free()
	overlay = null
