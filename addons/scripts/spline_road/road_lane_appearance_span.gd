@tool
extends Node3D
## Editor-only range proxies; the Resource remains the sole appearance storage.
const HANDLE = preload("./road_lane_range_handle.gd")
@export var appearance: Resource
var _signature := ""
var _geometry_signature := ""
var _search_points := PackedVector3Array()
var _search_offsets := PackedFloat32Array()
var _preview: MeshInstance3D
var _road: Node3D
var _profile: Path3D


func _ready() -> void:
	if not Engine.is_editor_hint():
		hide()


func sync(profile: Path3D, geometry_signature: String, selected: bool) -> void:
	_profile = profile
	_road = profile.get_parent() as Node3D
	while _road != null and not _road.has_method("get_path_surface_frame"):
		_road = _road.get_parent() as Node3D
	_ensure_handles()
	if appearance == null or profile.curve == null or profile.curve.point_count < 2:
		hide()
		return
	show()
	var geometry := str([geometry_signature, profile.global_transform, appearance.side, appearance.lane,
		_road.get_terrain_surface_revision() if _road != null else 0])
	var signature := str([geometry, appearance.enabled, appearance.start_offset, appearance.end_offset])
	if signature != _signature:
		_signature = signature
		var length := profile.curve.get_baked_length()
		get_node("StartHandle").sync_position(to_local(_lane_points(clampf(appearance.start_offset, 0.0, length))[2]))
		get_node("EndHandle").sync_position(to_local(_lane_points(_end_offset())[2]))
		_rebuild_preview()
	if geometry != _geometry_signature:
		_geometry_signature = geometry
		_search_points.clear()
		_search_offsets.clear()
		var length := profile.curve.get_baked_length()
		var count := clampi(ceili(length / 2.0), 2, 2048)
		for i in range(count + 1):
			var distance := length * i / count
			_search_offsets.append(distance)
			_search_points.append(_lane_points(distance)[2])
	if _preview != null:
		_preview.visible = selected and appearance.enabled


func _ensure_handles() -> void:
	for ending in [false, true]:
		var label := "EndHandle" if ending else "StartHandle"
		var handle := get_node_or_null(label) as MeshInstance3D
		if handle == null:
			handle = HANDLE.new()
			handle.name = label
			handle.at_end = ending
			add_child(handle)
		handle.owner = owner
		if handle.mesh == null:
			var sphere := SphereMesh.new()
			sphere.radius = 0.3
			sphere.height = 0.6
			handle.mesh = sphere
			handle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = Color(1, 0.6, 0.1) if ending else Color(0.15, 0.9, 1)
			handle.material_override = material


func _end_offset() -> float:
	var length := _profile.curve.get_baked_length()
	return clampf(appearance.end_offset, 0.0, length) if appearance.end_offset > 0 else length


func set_offset(ending: bool, value: float) -> void:
	if appearance == null:
		return
	# Numeric Inspector controls retain the Resource's End=0 convention.
	appearance.set("end_offset" if ending else "start_offset", maxf(0.0, value))
	appearance.emit_changed()
	_signature = ""


func move_endpoint(ending: bool, world_position: Vector3) -> void:
	if appearance == null or _profile == null or _search_points.size() < 2:
		return
	var best := INF
	var segment := 0
	for i in range(_search_points.size() - 1):
		var nearest := Geometry3D.get_closest_point_to_segment(world_position, _search_points[i], _search_points[i + 1])
		var error := nearest.distance_squared_to(world_position)
		if error < best:
			best = error
			segment = i
	var start := float(_search_offsets[segment])
	var end := float(_search_offsets[segment + 1])
	for i in range(22):
		var a := lerpf(start, end, 1.0 / 3.0)
		var b := lerpf(start, end, 2.0 / 3.0)
		if _lane_points(a)[2].distance_squared_to(world_position) < _lane_points(b)[2].distance_squared_to(world_position):
			end = b
		else:
			start = a
	var distance := (start + end) * 0.5
	var length := _profile.curve.get_baked_length()
	if ending:
		distance = clampf(distance, minf(length, appearance.start_offset + 0.01), length)
		if length - distance < 0.001:
			distance = 0.0
	else:
		distance = clampf(distance, 0.0, maxf(0.0, _end_offset() - 0.01))
		if distance < 0.001:
			distance = 0.0
	var previous: float = appearance.end_offset if ending else appearance.start_offset
	if absf(previous - distance) > 0.001:
		set_offset(ending, distance)


func _lane_points(distance: float) -> PackedVector3Array:
	var frame: Dictionary = _road.get_path_surface_frame(_profile, distance) if _road != null else {}
	var center: Vector3 = frame.get("center", _profile.to_global(_profile.curve.sample_baked(distance, true)))
	var up: Vector3 = frame.get("up", Vector3.UP)
	var right: Vector3 = frame.get("right", _profile.global_basis.x)
	var layout: Dictionary = _profile.get_lane_layout_at_offset(distance)
	var width: float = layout.lane_width
	var extent: float = layout.left_extent if appearance.side < 0 else layout.right_extent
	var inner := minf(extent, (appearance.lane - 1) * width)
	var outer := minf(extent, appearance.lane * width)
	center += up * 0.12
	return PackedVector3Array([center + right * appearance.side * inner,
		center + right * appearance.side * outer,
		center + right * appearance.side * (inner + outer) * 0.5])


func _rebuild_preview() -> void:
	if _preview == null:
		_preview = MeshInstance3D.new()
		_preview.name = "__SelectedLane"
		_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_preview) # Transient highlight is never saved into the scene.
	var start := clampf(appearance.start_offset, 0.0, _profile.curve.get_baked_length())
	var end := _end_offset()
	if end <= start:
		_preview.mesh = null
		return
	var count := clampi(ceili((end - start) / 2.0), 1, 512)
	var vertices := PackedVector3Array()
	var previous := _lane_points(start)
	for i in range(1, count + 1):
		var points := _lane_points(lerpf(start, end, float(i) / count))
		for point in [previous[0], previous[1], points[0], points[0], previous[1], points[1]]:
			vertices.append(to_local(point))
		previous = points
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.15, 0.8, 1.0, 0.3)
	mesh.surface_set_material(0, material)
	_preview.mesh = mesh
