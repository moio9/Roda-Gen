@tool
extends Node3D
class_name SplineMeshDeformer3D

## Deforms a Mesh vertex-by-vertex along a Path3D, similarly to Blender's
## Curve modifier. Use it for continuous walls, fences, guard rails and pipes.
##
## The source mesh keeps its cross-section while its longitudinal coordinate is
## converted to a distance along the curve. Triangles are sliced automatically
## before deformation, so even a low-poly box can follow tight bends smoothly.

@export_group("Sources")
@export var source_path: NodePath
@export var use_parent_path_if_empty := true
@export var source_mesh: Mesh:
	set(value):
		var callback := Callable(self, "_on_source_mesh_changed")
		if source_mesh != null and source_mesh.changed.is_connected(callback):
			source_mesh.changed.disconnect(callback)
		source_mesh = value
		if source_mesh != null and not source_mesh.changed.is_connected(callback):
			source_mesh.changed.connect(callback)
		_queue_regenerate()
## Optional RoadNetworkCreator3D. When empty, the closest compatible ancestor
## of the source path is discovered automatically.
@export var road_network_source: NodePath

@export_group("Curve Span")
## Repeat is the practical default for fences, barriers and wall modules because
## it preserves the source mesh proportions instead of stretching one copy.
@export_enum("Stretch One Mesh", "Repeat Mesh") var length_mode := 1
@export_range(0.0, 100000.0, 0.05, "or_greater", "suffix:m") var start_offset := 0.0
## Total generated distance from Start Offset. Zero uses all remaining curve.
@export_range(0.0, 100000.0, 0.05, "or_greater", "suffix:m") var span_length := 0.0
@export_range(0.0, 100000.0, 0.05, "or_greater", "suffix:m") var end_trim := 0.0
## Slightly rescales every repeat so the selected span ends without a gap.
@export var fit_repeats_to_span := true

@export_group("Span Handles")
## Shows draggable StartHandle and EndHandle markers in the 3D editor.
@export var show_span_handles := true
## Projects dragged handles back onto the source curve.
@export var snap_span_handles_to_path := true

@export_group("Placement")
@export_enum("Center", "Left Edge", "Right Edge", "Both Edges") var placement_mode := 0
@export_range(0.0, 100.0, 0.1, "or_greater", "suffix:m") var fallback_road_width := 6.0
@export var edge_uses_total_road_width := true
@export_range(-100.0, 100.0, 0.01, "or_greater", "or_less", "suffix:m") var lateral_offset := 0.0
@export_range(-100.0, 100.0, 0.01, "or_greater", "or_less", "suffix:m") var outward_offset := 0.0
@export_range(-100.0, 100.0, 0.01, "or_greater", "or_less", "suffix:m") var vertical_offset := 0.0
## At a road edge, lift the mesh base onto an existing sidewalk surface.
@export var add_sidewalk_height_at_edges := true
## Uses RoadNetworkCreator3D's exact frame when one is available.
@export var follow_road_surface := true
## Follow the final welded outline, accounting for this mesh's thickness.
## Requires Follow Road Surface and Edge Uses Total Road Width; center placement is unchanged.
@export var follow_generated_road_edge := true

@export_group("Deformation")
## Pick the source mesh axis that represents its length. Local +X is the common
## convention for walls and fence panels; Godot-forward assets often use -Z.
@export_enum("Local +X", "Local -X", "Local +Z", "Local -Z") var deform_axis := 0
## Maximum distance between generated bend slices along the final curve.
@export_range(0.05, 20.0, 0.05, "suffix:m") var curve_subdivision_step := 0.5
@export var auto_subdivide_mesh := true
@export_range(0.01, 10.0, 0.01, "suffix:m") var tangent_sample_distance := 0.15
@export var align_with_curve_up := true
## Natural longitudinal size multiplier used by Repeat Mesh mode.
@export_range(0.01, 100.0, 0.01, "or_greater") var repeat_length_scale := 1.0
@export_range(0.001, 100.0, 0.001, "or_greater") var lateral_scale := 1.0
@export_range(0.001, 100.0, 0.001, "or_greater") var height_scale := 1.0

@export_group("Output")
@export var material_override: Material
@export var cast_shadow := true
@export var generate_collision := false

@export_group("Workflow")
@export var generate_in_editor := true
@export var auto_regenerate_in_editor := true
## Heavy meshes rebuild once the mouse is released unless this is enabled.
@export var regenerate_while_dragging_handles := false
@export_range(0.0, 2.0, 0.01, "suffix:s") var editor_regenerate_debounce_seconds := 0.2
@export var persist_generated_in_scene := false
@export_range(1000, 5000000, 1000, "or_greater") var max_generated_vertices := 1000000
@export_tool_button("Regenerate Curved Mesh") var regenerate_action := _regenerate_from_button
@export_tool_button("Clear Generated") var clear_generated_action := _clear_generated_from_button
@export var debug_logs := false

const GENERATED_ROOT_NAME := "GeneratedSplineMeshes"
const GENERATED_OWNER_META := "spline_mesh_deformer_owner_path"
const LENGTH_MODE_STRETCH := 0
const LENGTH_MODE_REPEAT := 1
const PLACEMENT_CENTER := 0
const PLACEMENT_LEFT := 1
const PLACEMENT_RIGHT := 2
const PLACEMENT_BOTH := 3
const AXIS_POSITIVE_X := 0
const AXIS_NEGATIVE_X := 1
const AXIS_POSITIVE_Z := 2
const AXIS_NEGATIVE_Z := 3
const EPS := 0.00001
const MAX_SUBDIVISION_SLICES := 4096
const START_HANDLE_NAME := "StartHandle"
const END_HANDLE_NAME := "EndHandle"
## Ignore sub-millimetre projection residue so releasing a handle cannot start
## an endless editor regeneration loop.
const HANDLE_SYNC_EPSILON := 0.001

var _last_signature := ""
var _last_lane_layout_signature := ""
var _last_dependent_width_signature := ""
var _pending_signature := ""
var _pending_time_left := 0.0
var _last_generated_vertex_count := 0
var _warned_vertex_limit := false
var _warned_subdivision_limit := false
var _last_handle_source_signature := ""
var _last_start_handle_position := Vector3(INF, INF, INF)
var _last_end_handle_position := Vector3(INF, INF, INF)
var _syncing_span_handles := false
var _road_edge := preload("./prop_road_edge_query.gd").new()
var _source_lateral_bounds := Vector2.ZERO
var _source_min_y := 0.0


func _ready() -> void:
	set_process(true)
	if Engine.is_editor_hint():
		_ensure_span_handles()
		_update_span_handles_from_values()
		_queue_regenerate()
	elif generate_in_editor or not Engine.is_editor_hint():
		regenerate()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		var path := _get_source_path()
		if source_mesh != null and path != null and path.curve != null and path.curve.point_count >= 2 \
				and _uses_final_edge() and not _lane_edge_update_deferred(path) \
				and _road_edge.changed(_resolve_road_network(path) as Node3D):
			regenerate()
		return
	_sync_span_handles()
	if not generate_in_editor or not auto_regenerate_in_editor:
		return
	var signature := _build_signature()
	if signature == _last_signature:
		_pending_signature = ""
		_pending_time_left = 0.0
		return
	if signature != _pending_signature:
		_pending_signature = signature
		_pending_time_left = maxf(0.0, editor_regenerate_debounce_seconds)
		if _should_defer_editor_regenerate() or _pending_time_left > EPS:
			return
	else:
		if _should_defer_editor_regenerate():
			_pending_time_left = maxf(0.0, editor_regenerate_debounce_seconds)
			return
		_pending_time_left = maxf(0.0, _pending_time_left - delta)
		if _pending_time_left > EPS:
			return
	_pending_signature = ""
	_pending_time_left = 0.0
	regenerate()


func _regenerate_from_button() -> void:
	_queue_regenerate()
	regenerate()


func _clear_generated_from_button() -> void:
	_clear_generated()
	_queue_regenerate()


func _on_source_mesh_changed() -> void:
	_queue_regenerate()


func regenerate() -> void:
	if Engine.is_editor_hint() and not generate_in_editor:
		return
	var path := _get_source_path()
	_last_lane_layout_signature = _source_lane_layout_signature(path)
	_last_dependent_width_signature = str(path.get_dependent_width_profile_signature()) \
		if path != null and path.has_method("get_dependent_width_profile_signature") else ""
	if path == null:
		_debug_log("Set source_path, place this node under a Path3D, or beside a Path3D under RoadNetworkCreator3D.")
		_clear_generated()
		_last_signature = _build_signature()
		return
	if path.curve == null or path.curve.point_count < 2:
		_debug_log("The source Path3D needs a Curve3D with at least 2 points.")
		_clear_generated()
		_last_signature = _build_signature()
		return
	if source_mesh == null:
		_debug_log("Set source_mesh before generating.")
		_clear_generated()
		_last_signature = _build_signature()
		return
	_road_edge.configure(_resolve_road_network(path) as Node3D if _uses_final_edge() else null)

	var bounds := _get_source_longitudinal_bounds()
	var source_length := bounds.y - bounds.x
	if source_length <= EPS:
		push_warning("SplineMeshDeformer3D: source_mesh has no measurable length on the selected deform axis.")
		_clear_generated()
		_last_signature = _build_signature()
		return

	var curve_span := _resolve_curve_span(path)
	var begin := curve_span.x
	var end := curve_span.y
	var resolved_span_length := end - begin
	if resolved_span_length <= EPS:
		_debug_log("Start Offset, Span Length and End Trim leave no usable curve span.")
		_clear_generated()
		_last_signature = _build_signature()
		return

	var repeat_info := _resolve_repeat_info(source_length, resolved_span_length)
	var repeat_count := int(repeat_info.get("count", 1))
	var distance_scale := float(repeat_info.get("distance_scale", resolved_span_length / source_length))
	var sides := _build_sides_for_mode()
	_clear_generated()
	_last_generated_vertex_count = 0
	_warned_vertex_limit = false
	_warned_subdivision_limit = false

	var root := Node3D.new()
	root.name = GENERATED_ROOT_NAME
	root.set_meta(GENERATED_OWNER_META, _generated_owner_key())
	add_child(root)
	_assign_generated_owner(root)

	var generated_meshes := 0
	for side in sides:
		var deformed := _build_deformed_mesh(
			path,
			bounds,
			begin,
			end,
			int(side),
			repeat_count,
			distance_scale
		)
		if deformed == null or deformed.get_surface_count() <= 0:
			continue
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = _generated_mesh_name(path, int(side))
		mesh_instance.mesh = deformed
		mesh_instance.material_override = material_override
		mesh_instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if cast_shadow
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		mesh_instance.set_meta(GENERATED_OWNER_META, _generated_owner_key())
		root.add_child(mesh_instance)
		_assign_generated_owner(mesh_instance)
		if generate_collision:
			mesh_instance.create_trimesh_collision()
			for child in mesh_instance.get_children():
				_assign_generated_owner_recursive(child)
		generated_meshes += 1

	if generated_meshes <= 0:
		_clear_generated()
		_debug_log("No triangle surfaces were generated from source_mesh.")
	else:
		_debug_log(
			"Generated curved mesh: outputs=%d repeats=%d vertices=%d"
			% [generated_meshes, repeat_count, _last_generated_vertex_count]
		)
	_last_signature = _build_signature()


## Export validation uses actual lane values without changing the deliberately
## deferred editor regeneration signature used by heavy edge consumers.
func is_generated_output_current() -> bool:
	return _last_signature == _build_signature() and _last_lane_layout_signature == _source_lane_layout_signature(_get_source_path())


func _source_lane_layout_signature(path: Path3D) -> String:
	if path != null and path.has_method("_build_live_lane_signature") and path.get("lane_profile_enabled"):
		return str(path.call("_build_live_lane_signature"))
	return ""


func _lane_edge_update_deferred(path: Path3D) -> bool:
	if path == null or not path.has_method("get_dependent_width_profile_signature") \
			or not path.get("lane_profile_enabled") or path.get("live_lane_regeneration"):
		return false
	# Raw PackedArray edits can precede the profile's editor polling. Compare the
	# live layout and applied revision so runtime and immediate bake agree too.
	return _last_lane_layout_signature != _source_lane_layout_signature(path) \
		and _last_dependent_width_signature == str(path.get_dependent_width_profile_signature())


func _build_deformed_mesh(
	path: Path3D,
	bounds: Vector2,
	begin: float,
	end: float,
	side: int,
	repeat_count: int,
	distance_scale: float
) -> ArrayMesh:
	var result := ArrayMesh.new()
	var frame_cache: Dictionary = {}
	for surface_index in range(source_mesh.get_surface_count()):
		if (
			source_mesh is ArrayMesh
			and (source_mesh as ArrayMesh).surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES
		):
			push_warning(
				"SplineMeshDeformer3D: surface %d is not a triangle surface and was skipped."
				% surface_index
			)
			continue
		var source_arrays := source_mesh.surface_get_arrays(surface_index)
		var output_arrays := _deform_surface(
			source_arrays,
			path,
			bounds,
			begin,
			end,
			side,
			repeat_count,
			distance_scale,
			frame_cache
		)
		if output_arrays.size() < Mesh.ARRAY_MAX:
			continue
		var output_vertices: PackedVector3Array = output_arrays[Mesh.ARRAY_VERTEX]
		if output_vertices.is_empty():
			continue
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, output_arrays)
		var output_surface_index := result.get_surface_count() - 1
		result.surface_set_material(output_surface_index, source_mesh.surface_get_material(surface_index))
	return result


func _deform_surface(
	arrays: Array,
	path: Path3D,
	bounds: Vector2,
	begin: float,
	end: float,
	side: int,
	repeat_count: int,
	distance_scale: float,
	frame_cache: Dictionary
) -> Array:
	var output: Array = []
	output.resize(Mesh.ARRAY_MAX)
	var source_vertices: PackedVector3Array = (
		arrays[Mesh.ARRAY_VERTEX]
		if arrays[Mesh.ARRAY_VERTEX] != null
		else PackedVector3Array()
	)
	if source_vertices.size() < 3:
		output[Mesh.ARRAY_VERTEX] = PackedVector3Array()
		return output

	var source_normals: PackedVector3Array = (
		arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	)
	var source_tangents: PackedFloat32Array = (
		arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	)
	var source_colors: PackedColorArray = (
		arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	)
	var source_uvs: PackedVector2Array = (
		arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	)
	var source_uv2s: PackedVector2Array = (
		arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	)
	var source_indices: PackedInt32Array = (
		arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	)
	var has_normals := source_normals.size() == source_vertices.size()
	var has_tangents := source_tangents.size() == source_vertices.size() * 4
	var has_colors := source_colors.size() == source_vertices.size()
	var has_uvs := source_uvs.size() == source_vertices.size()
	var has_uv2s := source_uv2s.size() == source_vertices.size()

	var out_vertices := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var out_tangents := PackedFloat32Array()
	var out_colors := PackedColorArray()
	var out_uvs := PackedVector2Array()
	var out_uv2s := PackedVector2Array()
	var out_indices := PackedInt32Array()
	var source_length := bounds.y - bounds.x
	var source_slice_step := _resolve_source_slice_step(source_length, distance_scale)
	var triangle_index_count := source_indices.size() if not source_indices.is_empty() else source_vertices.size()
	triangle_index_count -= triangle_index_count % 3

	for triangle_offset in range(0, triangle_index_count, 3):
		var triangle: Array[Dictionary] = []
		var valid_triangle := true
		for corner in range(3):
			var vertex_index := (
				int(source_indices[triangle_offset + corner])
				if not source_indices.is_empty()
				else triangle_offset + corner
			)
			if vertex_index < 0 or vertex_index >= source_vertices.size():
				valid_triangle = false
				break
			triangle.append(_read_source_vertex(
				vertex_index,
				source_vertices,
				source_normals,
				source_tangents,
				source_colors,
				source_uvs,
				source_uv2s,
				has_normals,
				has_tangents,
				has_colors,
				has_uvs,
				has_uv2s
			))
		if not valid_triangle:
			continue

		var subdivided_triangles := _subdivide_triangle(triangle, bounds, source_slice_step)
		for repeat_index in range(repeat_count):
			for split_triangle in subdivided_triangles:
				if _last_generated_vertex_count + out_vertices.size() + 3 > max_generated_vertices:
					if not _warned_vertex_limit:
						push_warning(
							"SplineMeshDeformer3D: max_generated_vertices reached; increase the limit or use a larger subdivision step."
						)
						_warned_vertex_limit = true
					_last_generated_vertex_count += out_vertices.size()
					return _pack_output_arrays(
						out_vertices, out_normals, out_tangents, out_colors,
						out_uvs, out_uv2s, out_indices,
						has_tangents, has_colors, has_uvs, has_uv2s
					)

				var deformed_positions: Array[Vector3] = []
				var deformed_normals: Array[Vector3] = []
				var deformed_tangent_vectors: Array[Vector3] = []
				var first_distance := INF
				var last_distance := -INF
				for vertex_data in split_triangle:
					var source_position: Vector3 = vertex_data.get("position", Vector3.ZERO)
					var q := _axis_coordinate(source_position)
					var distance := begin + float(repeat_index) * source_length * distance_scale
					distance += (q - bounds.x) * distance_scale
					distance = clampf(distance, begin, end)
					first_distance = minf(first_distance, distance)
					last_distance = maxf(last_distance, distance)
					var frame := _sample_frame_cached(path, distance, frame_cache, side)
					deformed_positions.append(_deform_position(source_position, path, distance, side, frame))
					if has_normals:
						var source_normal: Vector3 = vertex_data.get("normal", Vector3.UP)
						deformed_normals.append(_deform_normal(source_normal, frame, distance_scale))
					if has_tangents:
						var source_tangent: Vector3 = vertex_data.get("tangent", Vector3.RIGHT)
						deformed_tangent_vectors.append(
							_deform_direction(source_tangent, frame, distance_scale).normalized()
						)

				if deformed_positions.size() != 3:
					continue
				if not _edge_span_clear(path, first_distance, last_distance, side, frame_cache):
					continue
				var face_cross := (
					(deformed_positions[1] - deformed_positions[0])
					.cross(deformed_positions[2] - deformed_positions[0])
				)
				if face_cross.length_squared() <= EPS * EPS:
					continue
				if not has_normals:
					var face_normal := face_cross.normalized()
					deformed_normals = [face_normal, face_normal, face_normal]

				for corner in range(3):
					var output_index := out_vertices.size()
					var vertex_data: Dictionary = split_triangle[corner]
					out_vertices.append(deformed_positions[corner])
					out_normals.append(deformed_normals[corner])
					if has_tangents:
						var tangent := deformed_tangent_vectors[corner]
						out_tangents.append(tangent.x)
						out_tangents.append(tangent.y)
						out_tangents.append(tangent.z)
						out_tangents.append(float(vertex_data.get("tangent_w", 1.0)))
					if has_colors:
						out_colors.append(vertex_data.get("color", Color.WHITE))
					if has_uvs:
						out_uvs.append(vertex_data.get("uv", Vector2.ZERO))
					if has_uv2s:
						out_uv2s.append(vertex_data.get("uv2", Vector2.ZERO))
					out_indices.append(output_index)

	_last_generated_vertex_count += out_vertices.size()
	return _pack_output_arrays(
		out_vertices, out_normals, out_tangents, out_colors,
		out_uvs, out_uv2s, out_indices,
		has_tangents, has_colors, has_uvs, has_uv2s
	)


func _read_source_vertex(
	index: int,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	tangents: PackedFloat32Array,
	colors: PackedColorArray,
	uvs: PackedVector2Array,
	uv2s: PackedVector2Array,
	has_normals: bool,
	has_tangents: bool,
	has_colors: bool,
	has_uvs: bool,
	has_uv2s: bool
) -> Dictionary:
	var result := {"position": vertices[index]}
	if has_normals:
		result["normal"] = normals[index]
	if has_tangents:
		var tangent_offset := index * 4
		result["tangent"] = Vector3(
			tangents[tangent_offset],
			tangents[tangent_offset + 1],
			tangents[tangent_offset + 2]
		)
		result["tangent_w"] = tangents[tangent_offset + 3]
	if has_colors:
		result["color"] = colors[index]
	if has_uvs:
		result["uv"] = uvs[index]
	if has_uv2s:
		result["uv2"] = uv2s[index]
	return result


func _subdivide_triangle(
	triangle: Array[Dictionary],
	bounds: Vector2,
	source_slice_step: float
) -> Array:
	if not auto_subdivide_mesh or source_slice_step <= EPS:
		return [triangle]
	var min_q := INF
	var max_q := -INF
	for vertex_data in triangle:
		var q := _axis_coordinate(vertex_data.get("position", Vector3.ZERO))
		min_q = minf(min_q, q)
		max_q = maxf(max_q, q)
	if max_q - min_q <= source_slice_step + EPS:
		return [triangle]

	var first_slice := maxi(1, int(floor((min_q - bounds.x) / source_slice_step)) + 1)
	var last_slice := int(ceil((max_q - bounds.x) / source_slice_step)) - 1
	var polygons: Array = [triangle]
	for slice_index in range(first_slice, last_slice + 1):
		var plane := bounds.x + float(slice_index) * source_slice_step
		if plane <= min_q + EPS or plane >= max_q - EPS:
			continue
		var next_polygons: Array = []
		for polygon in polygons:
			var low := _clip_polygon_at_axis(polygon, plane, true)
			var high := _clip_polygon_at_axis(polygon, plane, false)
			if low.size() >= 3:
				next_polygons.append(low)
			if high.size() >= 3:
				next_polygons.append(high)
		polygons = next_polygons

	var triangles: Array = []
	for polygon in polygons:
		for i in range(1, polygon.size() - 1):
			triangles.append([polygon[0], polygon[i], polygon[i + 1]])
	return triangles


func _clip_polygon_at_axis(polygon: Array, plane: float, keep_low: bool) -> Array:
	var result: Array = []
	if polygon.is_empty():
		return result
	var previous: Dictionary = polygon[polygon.size() - 1]
	var previous_q := _axis_coordinate(previous.get("position", Vector3.ZERO))
	var previous_inside := previous_q <= plane + EPS if keep_low else previous_q >= plane - EPS
	for current_value in polygon:
		var current: Dictionary = current_value
		var current_q := _axis_coordinate(current.get("position", Vector3.ZERO))
		var current_inside := current_q <= plane + EPS if keep_low else current_q >= plane - EPS
		if current_inside != previous_inside:
			var denominator := current_q - previous_q
			if absf(denominator) > EPS:
				var weight := clampf((plane - previous_q) / denominator, 0.0, 1.0)
				result.append(_interpolate_vertex(previous, current, weight))
		if current_inside:
			result.append(current)
		previous = current
		previous_q = current_q
		previous_inside = current_inside
	return _clean_polygon(result)


func _clean_polygon(polygon: Array) -> Array:
	var cleaned: Array = []
	for vertex_data in polygon:
		var position: Vector3 = vertex_data.get("position", Vector3.ZERO)
		if not cleaned.is_empty():
			var previous_position: Vector3 = cleaned[cleaned.size() - 1].get("position", Vector3.ZERO)
			if position.distance_squared_to(previous_position) <= EPS * EPS:
				continue
		cleaned.append(vertex_data)
	if cleaned.size() >= 2:
		var first_position: Vector3 = cleaned[0].get("position", Vector3.ZERO)
		var last_position: Vector3 = cleaned[cleaned.size() - 1].get("position", Vector3.ZERO)
		if first_position.distance_squared_to(last_position) <= EPS * EPS:
			cleaned.pop_back()
	return cleaned


func _interpolate_vertex(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var result := {
		"position": (a.get("position", Vector3.ZERO) as Vector3).lerp(
			b.get("position", Vector3.ZERO) as Vector3,
			weight
		)
	}
	if a.has("normal") and b.has("normal"):
		result["normal"] = (a.get("normal", Vector3.UP) as Vector3).lerp(
			b.get("normal", Vector3.UP) as Vector3,
			weight
		).normalized()
	if a.has("tangent") and b.has("tangent"):
		result["tangent"] = (a.get("tangent", Vector3.RIGHT) as Vector3).lerp(
			b.get("tangent", Vector3.RIGHT) as Vector3,
			weight
		).normalized()
		result["tangent_w"] = lerpf(
			float(a.get("tangent_w", 1.0)),
			float(b.get("tangent_w", 1.0)),
			weight
		)
	if a.has("color") and b.has("color"):
		result["color"] = (a.get("color", Color.WHITE) as Color).lerp(
			b.get("color", Color.WHITE) as Color,
			weight
		)
	if a.has("uv") and b.has("uv"):
		result["uv"] = (a.get("uv", Vector2.ZERO) as Vector2).lerp(
			b.get("uv", Vector2.ZERO) as Vector2,
			weight
		)
	if a.has("uv2") and b.has("uv2"):
		result["uv2"] = (a.get("uv2", Vector2.ZERO) as Vector2).lerp(
			b.get("uv2", Vector2.ZERO) as Vector2,
			weight
		)
	return result


func _pack_output_arrays(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	tangents: PackedFloat32Array,
	colors: PackedColorArray,
	uvs: PackedVector2Array,
	uv2s: PackedVector2Array,
	indices: PackedInt32Array,
	has_tangents: bool,
	has_colors: bool,
	has_uvs: bool,
	has_uv2s: bool
) -> Array:
	var output: Array = []
	output.resize(Mesh.ARRAY_MAX)
	output[Mesh.ARRAY_VERTEX] = vertices
	output[Mesh.ARRAY_NORMAL] = normals
	if has_tangents:
		output[Mesh.ARRAY_TANGENT] = tangents
	if has_colors:
		output[Mesh.ARRAY_COLOR] = colors
	if has_uvs:
		output[Mesh.ARRAY_TEX_UV] = uvs
	if has_uv2s:
		output[Mesh.ARRAY_TEX_UV2] = uv2s
	output[Mesh.ARRAY_INDEX] = indices
	return output


func _deform_position(
	source_position: Vector3,
	path: Path3D,
	distance: float,
	side: int,
	frame: Dictionary
) -> Vector3:
	var center: Vector3 = frame.get("center", path.global_position)
	var right: Vector3 = frame.get("right", Vector3.RIGHT)
	var up: Vector3 = frame.get("up", Vector3.UP)
	var vertical_axis: Vector3 = frame.get("vertical", up)
	var lateral := _axis_lateral_coordinate(source_position) * lateral_scale
	var height := source_position.y * height_scale
	var side_offset := 0.0 if frame.get("final_edge", false) else _compute_side_offset(path, distance, side)
	side_offset += lateral_offset + float(side) * outward_offset
	var sidewalk_raise := 0.0 if frame.get("final_edge", false) else _compute_sidewalk_raise(path, distance, side)
	var world_position := center
	world_position += right * (side_offset + lateral)
	world_position += vertical_axis * sidewalk_raise
	world_position += up * (vertical_offset + height)
	return global_transform.affine_inverse() * world_position


func _deform_direction(
	source_direction: Vector3,
	frame: Dictionary,
	longitudinal_scale: float
) -> Vector3:
	var tangent: Vector3 = frame.get("tangent", Vector3.FORWARD)
	var right: Vector3 = frame.get("right", Vector3.RIGHT)
	var up: Vector3 = frame.get("up", Vector3.UP)
	var world_direction := (
		tangent * _axis_longitudinal_component(source_direction) * longitudinal_scale
		+ right * _axis_lateral_component(source_direction) * lateral_scale
		+ up * source_direction.y * height_scale
	)
	var local_direction := global_transform.basis.inverse() * world_direction
	return local_direction.normalized()


func _deform_normal(
	source_normal: Vector3,
	frame: Dictionary,
	longitudinal_scale: float
) -> Vector3:
	var tangent: Vector3 = frame.get("tangent", Vector3.FORWARD)
	var right: Vector3 = frame.get("right", Vector3.RIGHT)
	var up: Vector3 = frame.get("up", Vector3.UP)
	var world_normal := (
		tangent * _axis_longitudinal_component(source_normal) / maxf(EPS, longitudinal_scale)
		+ right * _axis_lateral_component(source_normal) / maxf(EPS, lateral_scale)
		+ up * source_normal.y / maxf(EPS, height_scale)
	)
	var local_normal := global_transform.basis.transposed() * world_normal
	return local_normal.normalized()


func _sample_frame_cached(path: Path3D, distance: float, cache: Dictionary, side := 0) -> Dictionary:
	var key := "frame:%d:%s" % [side, snappedf(distance, 0.00001)]
	if cache.has(key):
		return cache[key]
	var frame := _edge_frame_origin(path, distance, side, cache).duplicate()
	if frame.get("final_edge", false):
		var probe := maxf(0.01, tangent_sample_distance)
		var before := _edge_frame_origin(path, maxf(0.0, distance - probe), side, cache)
		var after := _edge_frame_origin(path, minf(path.curve.get_baked_length(), distance + probe), side, cache)
		var tangent: Vector3 = after.center - before.center
		if tangent.length_squared() > EPS * EPS:
			tangent = tangent.normalized()
			var right := (frame.up as Vector3).cross(tangent).normalized()
			if right.length_squared() > EPS:
				frame.tangent = tangent
				frame.right = right
				frame.up = tangent.cross(right).normalized()
	cache[key] = frame
	return frame


func _uses_final_edge() -> bool:
	return follow_generated_road_edge and follow_road_surface and edge_uses_total_road_width and placement_mode != PLACEMENT_CENTER


func _edge_frame_origin(path: Path3D, distance: float, side: int, cache: Dictionary) -> Dictionary:
	var key := "origin:%d:%s" % [side, snappedf(distance, 0.00001)]
	if cache.has(key):
		return cache[key]
	var frame := _sample_frame(path, distance)
	if side != 0 and _uses_final_edge() and _road_edge.active():
		var edge: Dictionary = _road_edge.edge_at(frame.center, frame.right * float(side))
		if not edge.is_empty():
			var right: Vector3 = frame.right
			var up: Vector3 = edge.up
			if up.y > EPS:
				right.y = -(up.x * right.x + up.z * right.z) / up.y
			right = right.normalized()
			var clearance := maxf(0.0, _source_lateral_bounds.y if side < 0 else -_source_lateral_bounds.x)
			frame.center = edge.position + right * float(side) * clearance
			frame.right = right
			frame.up = up
			frame.tangent = right.cross(up).normalized()
			frame.vertical = up
			frame.final_edge = true
	cache[key] = frame
	return frame


func _edge_span_clear(path: Path3D, begin: float, end: float, side: int, cache: Dictionary) -> bool:
	if side == 0 or not _uses_final_edge() or not _road_edge.active() or end - begin < EPS:
		return true
	var key := "clear:%d:%s:%s" % [side, snappedf(begin, 0.00001), snappedf(end, 0.00001)]
	if cache.has(key):
		return cache[key]
	var a := _sample_frame_cached(path, begin, cache, side)
	var b := _sample_frame_cached(path, end, cache, side)
	if not a.get("final_edge", false) or not b.get("final_edge", false):
		return true
	var corners := PackedVector3Array()
	for pair in [[a, _source_lateral_bounds.x], [a, _source_lateral_bounds.y],
			[b, _source_lateral_bounds.y], [b, _source_lateral_bounds.x]]:
		var frame: Dictionary = pair[0]
		corners.append(frame.center + frame.right * (float(pair[1]) + lateral_offset + float(side) * outward_offset)
			+ frame.up * (_source_min_y * height_scale + vertical_offset))
	var clear := not _road_edge.overlaps_footprint(corners)
	cache[key] = clear
	return clear


func _sample_frame(path: Path3D, distance: float) -> Dictionary:
	var curve := path.curve
	var length := curve.get_baked_length()
	var dist := clampf(distance, 0.0, length)
	if follow_road_surface:
		var road_network := _resolve_road_network(path)
		if road_network != null and road_network.has_method("get_path_surface_frame"):
			var raw = road_network.call("get_path_surface_frame", path, dist)
			if raw is Dictionary and not raw.is_empty():
				var road_frame: Dictionary = raw
				var right: Vector3 = road_frame.get("right", Vector3.RIGHT)
				var up: Vector3 = road_frame.get("up", Vector3.UP)
				if right.length_squared() > EPS and up.length_squared() > EPS:
					right = right.normalized()
					up = up.normalized()
					var tangent := right.cross(up).normalized()
					if tangent.length_squared() > EPS:
						up = tangent.cross(right).normalized()
						return {
							"center": road_frame.get("center", path.to_global(curve.sample_baked(dist, true))),
							"right": right,
							"up": up,
							"tangent": tangent,
							"vertical": (road_frame.get("vertical", up) as Vector3).normalized(),
						}

	var center := path.to_global(curve.sample_baked(dist, true))
	var tangent := _sample_curve_tangent_world(path, dist, length)
	var up := _sample_curve_up_world(path, dist) if align_with_curve_up else Vector3.UP
	var right := up.cross(tangent).normalized()
	if right.length_squared() <= EPS:
		right = Vector3.UP.cross(tangent).normalized()
	if right.length_squared() <= EPS:
		right = Vector3.RIGHT
	up = tangent.cross(right).normalized()
	if up.length_squared() <= EPS:
		up = Vector3.UP
	return {
		"center": center,
		"right": right,
		"up": up,
		"tangent": tangent,
		"vertical": up,
	}


func _sample_curve_tangent_world(path: Path3D, distance: float, length: float) -> Vector3:
	var probe := maxf(0.01, tangent_sample_distance)
	var previous_distance := maxf(0.0, distance - probe)
	var next_distance := minf(length, distance + probe)
	if is_equal_approx(previous_distance, next_distance):
		if next_distance < length:
			next_distance = minf(length, next_distance + probe)
		elif previous_distance > 0.0:
			previous_distance = maxf(0.0, previous_distance - probe)
	var previous := path.to_global(path.curve.sample_baked(previous_distance, true))
	var next := path.to_global(path.curve.sample_baked(next_distance, true))
	var tangent := (next - previous).normalized()
	if tangent.length_squared() <= EPS:
		tangent = (path.global_transform.basis * Vector3.FORWARD).normalized()
	if tangent.length_squared() <= EPS:
		tangent = Vector3.FORWARD
	return tangent


func _sample_curve_up_world(path: Path3D, distance: float) -> Vector3:
	if path.curve.has_method("sample_baked_up_vector"):
		var local_up: Vector3 = path.curve.sample_baked_up_vector(distance, true)
		var world_up := (path.global_transform.basis * local_up).normalized()
		if world_up.length_squared() > EPS:
			return world_up
	return Vector3.UP


func _resolve_repeat_info(source_length: float, span_length: float) -> Dictionary:
	if length_mode == LENGTH_MODE_STRETCH:
		return {"count": 1, "distance_scale": span_length / source_length}
	var nominal_piece_length := source_length * maxf(0.01, repeat_length_scale)
	var count := maxi(1, int(floor(span_length / nominal_piece_length + EPS)))
	var distance_scale := maxf(0.01, repeat_length_scale)
	if fit_repeats_to_span or nominal_piece_length > span_length:
		count = maxi(1, int(round(span_length / nominal_piece_length)))
		distance_scale = span_length / (source_length * float(count))
	return {"count": count, "distance_scale": distance_scale}


func _resolve_source_slice_step(source_length: float, distance_scale: float) -> float:
	if not auto_subdivide_mesh:
		return source_length
	var requested_slices := maxi(1, int(ceil(source_length * distance_scale / maxf(0.05, curve_subdivision_step))))
	if requested_slices > MAX_SUBDIVISION_SLICES:
		requested_slices = MAX_SUBDIVISION_SLICES
		if not _warned_subdivision_limit:
			push_warning(
				"SplineMeshDeformer3D: subdivision was capped at %d slices; use Repeat Mesh for very long spans."
				% MAX_SUBDIVISION_SLICES
			)
			_warned_subdivision_limit = true
	return source_length / float(requested_slices)


func _axis_coordinate(value: Vector3) -> float:
	match deform_axis:
		AXIS_POSITIVE_X:
			return value.x
		AXIS_NEGATIVE_X:
			return -value.x
		AXIS_POSITIVE_Z:
			return value.z
		AXIS_NEGATIVE_Z:
			return -value.z
		_:
			return value.x


func _axis_lateral_coordinate(value: Vector3) -> float:
	match deform_axis:
		AXIS_POSITIVE_X:
			return -value.z
		AXIS_NEGATIVE_X:
			return value.z
		AXIS_POSITIVE_Z:
			return value.x
		AXIS_NEGATIVE_Z:
			return -value.x
		_:
			return -value.z


func _axis_longitudinal_component(value: Vector3) -> float:
	return _axis_coordinate(value)


func _axis_lateral_component(value: Vector3) -> float:
	return _axis_lateral_coordinate(value)


func _get_source_longitudinal_bounds() -> Vector2:
	var minimum := INF
	var maximum := -INF
	_source_lateral_bounds = Vector2(INF, -INF)
	_source_min_y = INF
	for surface_index in range(source_mesh.get_surface_count()):
		var arrays := source_mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = (
			arrays[Mesh.ARRAY_VERTEX]
			if arrays[Mesh.ARRAY_VERTEX] != null
			else PackedVector3Array()
		)
		for vertex in vertices:
			var q := _axis_coordinate(vertex)
			minimum = minf(minimum, q)
			maximum = maxf(maximum, q)
			var lateral := _axis_lateral_coordinate(vertex) * lateral_scale
			_source_lateral_bounds.x = minf(_source_lateral_bounds.x, lateral)
			_source_lateral_bounds.y = maxf(_source_lateral_bounds.y, lateral)
			_source_min_y = minf(_source_min_y, vertex.y)
	if not is_finite(minimum) or not is_finite(maximum):
		return Vector2.ZERO
	return Vector2(minimum, maximum)


func _compute_side_offset(path: Path3D, distance: float, side: int) -> float:
	if side == 0:
		return 0.0
	var length := maxf(EPS, path.curve.get_baked_length())
	var lane_width := _resolve_path_component(
		path, distance, length, "get_width_at_offset", "get_width_at_ratio",
		"road_width", fallback_road_width
	)
	var lane_extents := _resolve_path_lane_extents(path, distance, length, lane_width)
	var lane_side := lane_extents.x if side < 0 else lane_extents.y
	if not edge_uses_total_road_width:
		return lane_side * float(side)
	if side < 0:
		var shoulder_left := _resolve_path_component(
			path, distance, length, "get_shoulder_left_at_offset", "get_shoulder_left_at_ratio",
			"shoulder_left_width", 0.0
		)
		var sidewalk_left := _resolve_path_component(
			path, distance, length, "get_sidewalk_left_at_offset", "get_sidewalk_left_at_ratio",
			"sidewalk_left_width", 0.0
		)
		return -(lane_side + shoulder_left + sidewalk_left)
	var shoulder_right := _resolve_path_component(
		path, distance, length, "get_shoulder_right_at_offset", "get_shoulder_right_at_ratio",
		"shoulder_right_width", 0.0
	)
	var sidewalk_right := _resolve_path_component(
		path, distance, length, "get_sidewalk_right_at_offset", "get_sidewalk_right_at_ratio",
		"sidewalk_right_width", 0.0
	)
	return lane_side + shoulder_right + sidewalk_right


func _resolve_path_lane_extents(path: Path3D, distance: float, length: float, width: float) -> Vector2:
	var fallback := Vector2(width * 0.5, width * 0.5)
	var raw_value: Variant
	if path.has_method("get_lane_extents_at_offset"):
		raw_value = path.call("get_lane_extents_at_offset", distance)
	elif path.has_method("get_lane_extents_at_ratio"):
		raw_value = path.call("get_lane_extents_at_ratio", clampf(distance / maxf(length, EPS), 0.0, 1.0))
	else:
		return fallback
	if raw_value is Vector2:
		var pair: Vector2 = raw_value
		return Vector2(maxf(0.0, pair.x), maxf(0.0, pair.y))
	return fallback


func _compute_sidewalk_raise(path: Path3D, distance: float, side: int) -> float:
	if not add_sidewalk_height_at_edges or side == 0 or not edge_uses_total_road_width:
		return 0.0
	var length := maxf(EPS, path.curve.get_baked_length())
	var sidewalk_width := _resolve_path_component(
		path,
		distance,
		length,
		"get_sidewalk_left_at_offset" if side < 0 else "get_sidewalk_right_at_offset",
		"get_sidewalk_left_at_ratio" if side < 0 else "get_sidewalk_right_at_ratio",
		"sidewalk_left_width" if side < 0 else "sidewalk_right_width",
		0.0
	)
	if sidewalk_width <= EPS:
		return 0.0
	return _resolve_path_component(
		path, distance, length, "get_sidewalk_height_at_offset", "get_sidewalk_height_at_ratio",
		"sidewalk_height", 0.0
	)


func _resolve_path_component(
	path: Path3D,
	distance: float,
	length: float,
	offset_method: String,
	ratio_method: String,
	road_property: String,
	fallback: float
) -> float:
	if path.has_method(offset_method):
		return maxf(0.0, float(path.call(offset_method, distance)))
	if path.has_method(ratio_method):
		return maxf(0.0, float(path.call(ratio_method, clampf(distance / length, 0.0, 1.0))))
	var road_network := _resolve_road_network(path)
	if road_network != null:
		var value = road_network.get(road_property)
		if value != null:
			return maxf(0.0, float(value))
	return maxf(0.0, fallback)


func _resolve_curve_span(path: Path3D) -> Vector2:
	if path == null or path.curve == null:
		return Vector2.ZERO
	var curve_length := maxf(0.0, path.curve.get_baked_length())
	var begin := clampf(start_offset, 0.0, curve_length)
	var end := clampf(curve_length - maxf(0.0, end_trim), begin, curve_length)
	if span_length > EPS:
		end = minf(end, begin + span_length)
	return Vector2(begin, end)


func _sync_span_handles() -> void:
	if _syncing_span_handles:
		return
	_ensure_span_handles()
	_set_span_handles_visible(show_span_handles)
	if not show_span_handles:
		_last_handle_source_signature = ""
		_remember_span_handle_positions()
		return
	var path := _get_source_path()
	if path == null or path.curve == null or path.curve.point_count < 2:
		return
	var source_signature := _build_span_handle_source_signature(path)
	if source_signature != _last_handle_source_signature:
		_update_span_handles_from_values()
	elif _span_handles_were_moved():
		_update_span_values_from_handles()


func _ensure_span_handles() -> void:
	if get_node_or_null(START_HANDLE_NAME) == null:
		var start := Marker3D.new()
		start.name = START_HANDLE_NAME
		add_child(start)
		_assign_editor_owner(start)
	if get_node_or_null(END_HANDLE_NAME) == null:
		var end := Marker3D.new()
		end.name = END_HANDLE_NAME
		add_child(end)
		_assign_editor_owner(end)


func _find_span_handle(handle_name: String) -> Marker3D:
	return get_node_or_null(handle_name) as Marker3D


func _set_span_handles_visible(value: bool) -> void:
	var start := _find_span_handle(START_HANDLE_NAME)
	var end := _find_span_handle(END_HANDLE_NAME)
	if start != null:
		start.visible = value
	if end != null:
		end.visible = value


func _update_span_handles_from_values() -> void:
	if _syncing_span_handles:
		return
	var path := _get_source_path()
	if path == null or path.curve == null or path.curve.point_count < 2:
		return
	var start := _find_span_handle(START_HANDLE_NAME)
	var end := _find_span_handle(END_HANDLE_NAME)
	if start == null or end == null:
		return
	var curve_span := _resolve_curve_span(path)
	_syncing_span_handles = true
	start.global_position = _curve_offset_to_world(path, curve_span.x)
	end.global_position = _curve_offset_to_world(path, curve_span.y)
	_syncing_span_handles = false
	_remember_span_handle_positions()
	_last_handle_source_signature = _build_span_handle_source_signature(path)


func _update_span_values_from_handles() -> void:
	if _syncing_span_handles:
		return
	var start := _find_span_handle(START_HANDLE_NAME)
	var end := _find_span_handle(END_HANDLE_NAME)
	if start == null or end == null:
		return
	if not snap_span_handles_to_path:
		_remember_span_handle_positions()
		return
	var path := _get_source_path()
	if path == null or path.curve == null or path.curve.point_count < 2:
		return
	var curve_length := maxf(0.0, path.curve.get_baked_length())
	var start_projection := clampf(_world_to_curve_offset(path, start.global_position), 0.0, curve_length)
	var end_projection := clampf(_world_to_curve_offset(path, end.global_position), 0.0, curve_length)
	var new_start := minf(start_projection, end_projection)
	var new_end := maxf(start_projection, end_projection)
	var minimum_span := 0.05
	if new_end - new_start < minimum_span:
		if new_end >= curve_length - HANDLE_SYNC_EPSILON:
			new_start = maxf(0.0, new_end - minimum_span)
		else:
			new_end = minf(curve_length, new_start + minimum_span)

	var resolved := _resolve_curve_span(path)
	var start_changed := absf(new_start - resolved.x) > HANDLE_SYNC_EPSILON
	var end_changed := absf(new_end - resolved.y) > HANDLE_SYNC_EPSILON
	if not start_changed and not end_changed:
		_remember_span_handle_positions()
		return

	_syncing_span_handles = true
	start_offset = new_start
	span_length = maxf(minimum_span, new_end - new_start)
	end_trim = 0.0
	start.global_position = _curve_offset_to_world(path, new_start)
	end.global_position = _curve_offset_to_world(path, new_end)
	_syncing_span_handles = false
	_remember_span_handle_positions()
	_last_handle_source_signature = _build_span_handle_source_signature(path)


func _span_handles_were_moved() -> bool:
	var start := _find_span_handle(START_HANDLE_NAME)
	var end := _find_span_handle(END_HANDLE_NAME)
	if start == null or end == null:
		return false
	var epsilon_squared := HANDLE_SYNC_EPSILON * HANDLE_SYNC_EPSILON
	return (
		start.global_position.distance_squared_to(_last_start_handle_position) > epsilon_squared
		or end.global_position.distance_squared_to(_last_end_handle_position) > epsilon_squared
	)


func _remember_span_handle_positions() -> void:
	var start := _find_span_handle(START_HANDLE_NAME)
	var end := _find_span_handle(END_HANDLE_NAME)
	if start != null:
		_last_start_handle_position = start.global_position
	if end != null:
		_last_end_handle_position = end.global_position


func _world_to_curve_offset(path: Path3D, world_position: Vector3) -> float:
	if path == null or path.curve == null:
		return 0.0
	var local_position := path.to_local(world_position)
	if path.curve.has_method("get_closest_offset"):
		return float(path.curve.get_closest_offset(local_position))
	var curve_length := maxf(0.0, path.curve.get_baked_length())
	var best_offset := 0.0
	var best_distance_squared := INF
	var offset := 0.0
	while offset <= curve_length + EPS:
		var distance_squared := local_position.distance_squared_to(path.curve.sample_baked(offset, true))
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_offset = offset
		offset += 0.5
	return best_offset


func _curve_offset_to_world(path: Path3D, distance: float) -> Vector3:
	if path == null or path.curve == null:
		return global_position
	var length := maxf(0.0, path.curve.get_baked_length())
	return path.to_global(path.curve.sample_baked(clampf(distance, 0.0, length), true))


func _build_span_handle_source_signature(path: Path3D) -> String:
	if path == null or path.curve == null:
		return "no_path"
	var resolved := _resolve_curve_span(path)
	var parts: Array[String] = [
		str(path.get_instance_id()),
		str(path.global_transform if path.is_inside_tree() else path.transform),
		str(snappedf(resolved.x, HANDLE_SYNC_EPSILON)),
		str(snappedf(resolved.y, HANDLE_SYNC_EPSILON)),
		str(path.curve.point_count),
	]
	for point_index in range(path.curve.point_count):
		parts.append(str(path.curve.get_point_position(point_index)))
		parts.append(str(path.curve.get_point_in(point_index)))
		parts.append(str(path.curve.get_point_out(point_index)))
		parts.append(str(path.curve.get_point_tilt(point_index)))
	return "|".join(parts)


func _get_source_path() -> Path3D:
	if not source_path.is_empty():
		return get_node_or_null(source_path) as Path3D
	if not use_parent_path_if_empty:
		return null
	var parent := get_parent()
	if parent is Path3D:
		return parent as Path3D
	# Road-side generators are commonly children of RoadNetworkCreator3D, next
	# to its Path3D. Prefer that direct road path before searching more broadly.
	if parent != null:
		for sibling in parent.get_children():
			if sibling is Path3D and not _path_is_terrain_influence_only(sibling):
				return sibling as Path3D
		var grandparent := parent.get_parent()
		if grandparent != null:
			for nearby in grandparent.get_children():
				if nearby is Path3D and not _path_is_terrain_influence_only(nearby):
					return nearby as Path3D
	return null


func _path_is_terrain_influence_only(path: Path3D) -> bool:
	return (
		path != null
		and path.has_method("is_terrain_influence_path")
		and bool(path.call("is_terrain_influence_path"))
	)


func _resolve_road_network(path: Path3D) -> Node:
	if not road_network_source.is_empty():
		var explicit := get_node_or_null(road_network_source)
		if explicit != null and explicit.has_method("get_path_surface_frame"):
			return explicit
	var current: Node = path
	while current != null:
		if current.has_method("get_path_surface_frame"):
			return current
		current = current.get_parent()
	return null


func _build_sides_for_mode() -> Array[int]:
	match placement_mode:
		PLACEMENT_CENTER:
			return [0]
		PLACEMENT_LEFT:
			return [-1]
		PLACEMENT_RIGHT:
			return [1]
		PLACEMENT_BOTH:
			return [-1, 1]
		_:
			return [0]


func _generated_mesh_name(path: Path3D, side: int) -> String:
	var suffix := "Center"
	if side < 0:
		suffix = "Left"
	elif side > 0:
		suffix = "Right"
	return "CurvedMesh_%s_%s" % [path.name, suffix]


func _generated_owner_key() -> String:
	return str(get_path()) if is_inside_tree() else str(get_instance_id())


func _clear_generated() -> void:
	var old := get_node_or_null(GENERATED_ROOT_NAME)
	if old != null:
		remove_child(old)
		old.free()


func _assign_generated_owner(node: Node) -> void:
	if not persist_generated_in_scene or not Engine.is_editor_hint():
		return
	_assign_editor_owner(node)


func _assign_editor_owner(node: Node) -> void:
	if not Engine.is_editor_hint() or node == null or not is_inside_tree():
		return
	var edited_root := get_tree().edited_scene_root
	if edited_root != null and edited_root.is_ancestor_of(node):
		node.owner = edited_root


func _assign_generated_owner_recursive(node: Node) -> void:
	_assign_generated_owner(node)
	for child in node.get_children():
		_assign_generated_owner_recursive(child)


func _queue_regenerate() -> void:
	_last_signature = ""
	_pending_signature = ""
	_pending_time_left = 0.0


func _should_defer_editor_regenerate() -> bool:
	return (
		Engine.is_editor_hint()
		and not regenerate_while_dragging_handles
		and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	)


func _build_signature() -> String:
	var parts: Array[String] = [
		str(source_path), str(use_parent_path_if_empty), str(source_mesh), str(road_network_source),
		str(length_mode), str(start_offset), str(span_length), str(end_trim), str(repeat_length_scale),
		str(fit_repeats_to_span), str(placement_mode), str(fallback_road_width),
		str(edge_uses_total_road_width), str(lateral_offset), str(outward_offset),
		str(vertical_offset), str(add_sidewalk_height_at_edges), str(follow_road_surface),
		str(follow_generated_road_edge),
		str(deform_axis), str(curve_subdivision_step), str(auto_subdivide_mesh),
		str(tangent_sample_distance), str(align_with_curve_up), str(lateral_scale),
		str(height_scale), str(material_override), str(cast_shadow), str(generate_collision),
		str(persist_generated_in_scene), str(max_generated_vertices),
		str(global_transform if is_inside_tree() else transform),
	]
	if source_mesh != null:
		parts.append(str(source_mesh.get_instance_id()))
		parts.append(str(source_mesh.get_surface_count()))
		parts.append(str(source_mesh.get_aabb()))
	var path := _get_source_path()
	if path != null:
		parts.append(str(path.get_instance_id()))
		parts.append(str(path.global_transform if path.is_inside_tree() else path.transform))
		if path.has_method("get_dependent_width_profile_signature"):
			parts.append(str(path.call("get_dependent_width_profile_signature")))
		elif path.has_method("get_width_profile_signature"):
			parts.append(str(path.call("get_width_profile_signature")))
		if path.has_method("get_edge_profile_signature"):
			parts.append(str(path.call("get_edge_profile_signature")))
		if path.curve != null:
			parts.append(str(path.curve.point_count))
			parts.append(str(path.curve.get_baked_length()))
			for point_index in range(path.curve.point_count):
				parts.append(str(path.curve.get_point_position(point_index)))
				parts.append(str(path.curve.get_point_in(point_index)))
				parts.append(str(path.curve.get_point_out(point_index)))
				parts.append(str(path.curve.get_point_tilt(point_index)))
		var road_network := _resolve_road_network(path)
		if road_network != null:
			parts.append(str(road_network.get_instance_id()))
			if _uses_final_edge() and road_network.has_method("get_terrain_surface_revision"):
				# Preserve deferred lane editing until Rebuild Lane Dependents is applied.
				var defer_lanes := _lane_edge_update_deferred(path)
				parts.append(str(_road_edge._revision if defer_lanes else road_network.get_terrain_surface_revision()))
			if road_network is Node3D:
				parts.append(str((road_network as Node3D).global_transform))
			for property_name in [
				"road_width", "shoulder_left_width", "shoulder_right_width",
				"sidewalk_left_width", "sidewalk_right_width", "sidewalk_height",
				"y_offset", "road_orientation_mode", "road_bank_max_degrees",
				"road_bank_strength", "road_bank_sample_distance"
			]:
				parts.append(str(road_network.get(property_name)))
	return "|".join(parts)


func _debug_log(message: String) -> void:
	if debug_logs:
		print("[SplineMeshDeformer3D] ", message)
