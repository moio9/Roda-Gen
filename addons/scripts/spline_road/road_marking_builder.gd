@tool
extends RefCounted
## Paint is clipped in (spline distance, lateral distance) space to each actual
## road triangle, then mapped onto that triangle. It does not float on a second spline.

const NODE_NAME := "GeneratedRoadMarkings"
const CUT := preload("./terrain_road_mesh_cut.gd")
const APPEARANCE := preload("./road_lane_appearance.gd")
const OFF := 0
const SOLID := 1
const DASHED := 2
const DOUBLE_SOLID := 3
const DOUBLE_DASHED := 4
const SETTINGS := [
	"markings_enabled", "markings_center_style", "markings_lane_style", "markings_edge_style",
	"markings_line_width", "markings_double_gap", "markings_dash_length", "markings_dash_gap",
	"markings_dash_offset", "markings_edge_inset", "markings_surface_lift", "markings_junction_clearance",
	"markings_hatching_enabled", "markings_hatch_spacing", "markings_hatch_width", "markings_hatch_angle",
	"markings_center_color", "markings_line_color", "markings_hatch_color", "markings_material_override",
]
var _settings: Dictionary = {}
var _path_appearances: Dictionary = {}
var _path_lengths: Dictionary = {}
var _active_appearances: Array = []
var last_stats: Dictionary = {}
var _buckets: Array = []
var _marking_cuts: Dictionary = {}
var _active_path_id := -1
var _suppress_joining_centerline := false
var _final_asphalt: RefCounted
var _asphalt_signature := 0
const BLOCK_PAIRS := 32
const MAX_CACHE_ENTRIES := 4096
const MAX_CACHE_BYTES := 32 * 1024 * 1024
const MAX_BLOCK_VERTICES := 131072
var cache_enabled := true # Test override; the road's opt-in is still required.
var _incremental := false
var _cache: Dictionary = {}


func configure(road: Node) -> void:
	_incremental = bool(road.get("incremental_generation_enabled")) and cache_enabled
	if not _incremental or not road.get("markings_enabled"):
		clear_cache()
	_settings.clear()
	for property in SETTINGS:
		_settings[property.trim_prefix("markings_")] = road.get(property)
	_path_appearances.clear()
	_path_lengths.clear()
	var paths: Array = road._resolve_paths()
	for index in range(paths.size()):
		_path_lengths[index] = paths[index].curve.get_baked_length() if paths[index].curve != null else 0.0
		if not paths[index].has_method("get_lane_appearance_overrides"):
			continue
		var rules: Array = APPEARANCE.paint_rules(paths[index].get_lane_appearance_overrides())
		_path_appearances[index] = rules


func signature(road: Node) -> String:
	var parts := PackedStringArray()
	for property in SETTINGS:
		parts.append(str(road.get(property)))
	return "|".join(parts)


func clear(road: Node) -> void:
	clear_cache()
	var node := road.get_node_or_null(NODE_NAME)
	if node != null:
		road.remove_child(node)
		node.queue_free()
	last_stats = {}


func assign(road: Node3D, vertices: PackedVector3Array, path_rows: Array, exclusions: Dictionary,
		marking_cuts: Dictionary = {}, lane_indices := PackedInt32Array()) -> void:
	if not bool(_settings.get("enabled", false)):
		clear(road)
		return
	var mesh := build(vertices, path_rows, exclusions, marking_cuts, lane_indices)
	if mesh.get_surface_count() == 0:
		clear(road)
		return
	var node := road.get_node_or_null(NODE_NAME) as MeshInstance3D
	if node == null:
		node = MeshInstance3D.new()
		node.name = NODE_NAME
		road.add_child(node)
		if Engine.is_editor_hint():
			node.owner = road.get_tree().edited_scene_root
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Match the transform of an existing user-adjusted generated mesh.
	var source := road.get_node_or_null("GeneratedSplineRoadWelded") as MeshInstance3D
	if source == null:
		source = road.get_node_or_null("GeneratedSplineRoad") as MeshInstance3D
	if source != null:
		node.transform = source.transform
		node.visible = source.visible
		node.layers = source.layers


func build(vertices: PackedVector3Array, path_rows: Array, exclusions: Dictionary = {},
		marking_cuts: Dictionary = {}, lane_indices := PackedInt32Array()) -> ArrayMesh:
	var started := Time.get_ticks_usec()
	_marking_cuts = marking_cuts
	_final_asphalt = null
	_asphalt_signature = 0
	if not marking_cuts.is_empty() and not lane_indices.is_empty():
		_final_asphalt = CUT.new()
		_final_asphalt.append_surface(vertices, lane_indices, Transform3D.IDENTITY)
		_asphalt_signature = _final_asphalt.geometry_signature()
	_buckets = _empty_buckets()
	var next_cache: Dictionary = {}
	var cache_bytes := 0
	var blocks_reused := 0
	var blocks_rebuilt := 0
	var pairs_reused := 0
	var pairs_rebuilt := 0
	var bypassed := 0
	var geometry_settings := _settings.duplicate()
	for field in ["center_color", "line_color", "hatch_color", "material_override"]:
		geometry_settings.erase(field)
	for path_id in range(path_rows.size()):
		_active_path_id = path_id
		_active_appearances = _path_appearances.get(path_id, [])
		var rows: Array = path_rows[path_id]
		_suppress_joining_centerline = _is_continuous_joining_lane(rows)
		if not _incremental:
			_build_rows(vertices, rows, exclusions.get(path_id, []))
			pairs_rebuilt += maxi(0, rows.size() - 1)
			continue
		for begin in range(0, maxi(0, rows.size() - 1), BLOCK_PAIRS):
			var end := mini(rows.size() - 1, begin + BLOCK_PAIRS)
			var block_rows: Array = rows.slice(begin, end + 1)
			var key := Vector2i(path_id, begin / BLOCK_PAIRS)
			var input := _block_input(vertices, block_rows, exclusions.get(path_id, []), geometry_settings)
			var old: Dictionary = _cache.get(key, {})
			var buckets: Array
			if not input.is_empty() and old.get("input", PackedByteArray()) == input:
				buckets = old.buckets
				blocks_reused += 1
				pairs_reused += end - begin
			else:
				var combined := _buckets
				_buckets = _empty_buckets()
				_build_rows(vertices, block_rows, exclusions.get(path_id, []))
				buckets = _buckets
				_buckets = combined
				blocks_rebuilt += 1
				pairs_rebuilt += end - begin
			_append_buckets(buckets)
			var vertices_count := 0
			for bucket: Dictionary in buckets:
				vertices_count += bucket.vertices.size()
			var bytes := input.size() + vertices_count * 32 + 512
			if not input.is_empty() and vertices_count <= _cache_vertex_limit() and next_cache.size() < _cache_entry_limit() \
					and cache_bytes + bytes <= _cache_byte_limit():
				next_cache[key] = old if old.get("input", PackedByteArray()) == input else {"input": input, "buckets": buckets}
				cache_bytes += bytes
			else:
				bypassed += 1
	_cache = next_cache
	var mesh := ArrayMesh.new()
	var counts: Array[int] = []
	for bucket_id in range(3):
		var bucket: Dictionary = _buckets[bucket_id]
		var out_vertices: PackedVector3Array = bucket["vertices"]
		counts.append(out_vertices.size() / 3)
		if out_vertices.is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = out_vertices
		arrays[Mesh.ARRAY_NORMAL] = bucket["normals"]
		arrays[Mesh.ARRAY_TEX_UV] = bucket["uvs"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_name(mesh.get_surface_count() - 1, ["Center", "Lines", "Hatching"][bucket_id])
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(bucket_id))
	last_stats = {"center_triangles": counts[0], "line_triangles": counts[1], "hatch_triangles": counts[2], "build_ms": float(Time.get_ticks_usec() - started) / 1000.0}
	last_stats.merge({"incremental": _incremental, "blocks_reused": blocks_reused, "blocks_rebuilt": blocks_rebuilt,
		"pairs_reused": pairs_reused, "pairs_rebuilt": pairs_rebuilt, "cache_entries": _cache.size(),
		"cache_bytes": cache_bytes, "bypassed": bypassed})
	_buckets.clear()
	_marking_cuts = {}
	_active_path_id = -1
	_active_appearances = []
	_suppress_joining_centerline = false
	_final_asphalt = null
	return mesh


func clear_cache() -> void:
	_cache.clear()
	last_stats = {}


func _empty_buckets() -> Array:
	var result: Array = []
	for index in range(3):
		result.append({"vertices": PackedVector3Array(), "normals": PackedVector3Array(), "uvs": PackedVector2Array()})
	return result


func _append_buckets(source: Array) -> void:
	for index in range(3):
		for field in ["vertices", "normals", "uvs"]:
			_buckets[index][field].append_array(source[index][field])


func _block_input(vertices: PackedVector3Array, rows: Array, exclusions: Array, settings: Dictionary) -> PackedByteArray:
	var input: Array = []
	var cuts: Array = []
	for row: Dictionary in rows:
		if not row.has("marking_layout"):
			input.append(null)
			continue
		var edges: Array = row.get("row_edges", [])
		if edges.size() < 4 or not row.has("distance") or not row.has("lane_extents"):
			return PackedByteArray()
		if mini(int(edges[2]), int(edges[3])) < 0 or maxi(int(edges[2]), int(edges[3])) >= vertices.size():
			return PackedByteArray()
		input.append([row.distance, row.lane_extents, row.marking_layout, vertices[edges[2]], vertices[edges[3]],
			row.get("lateral_left", []), row.get("lateral_right", []), row.get("lateral_transition", false)])
		var cut = _marking_cuts.get(Vector2i(_active_path_id, int(row.get("row_idx", -1))), null)
		if cut == null:
			cuts.append(null)
		else:
			var geometry: Array = []
			for triangle: Dictionary in cut.get("_triangles"):
				geometry.append(triangle.points)
			cuts.append(geometry)
	return var_to_bytes([settings, exclusions, input, cuts, _asphalt_signature, _suppress_joining_centerline, APPEARANCE.in_range(_active_appearances, rows[0].distance, rows[-1].distance), _path_lengths.get(_active_path_id, 0.0)])


func _is_continuous_joining_lane(rows: Array) -> bool:
	if rows.size() < 3:
		return false
	var first := rows.size()
	var last := -1
	var joined_rows := 0
	for i in range(rows.size()):
		var joined := false
		for side in ["lateral_left", "lateral_right"]:
			for contact: Vector3 in rows[i].get(side, []):
				if contact.z < 0.5:
					joined = true
		if joined:
			first = mini(first, i)
			last = i
			joined_rows += 1
	return first <= 1 and last >= rows.size() - 2 and joined_rows * 5 >= rows.size() * 4


func _cache_entry_limit() -> int:
	return MAX_CACHE_ENTRIES


func _cache_byte_limit() -> int:
	return MAX_CACHE_BYTES


func _cache_vertex_limit() -> int:
	return MAX_BLOCK_VERTICES


func _build_rows(vertices: PackedVector3Array, rows: Array, exclusions: Array) -> void:
	var path_rules := _active_appearances
	for i in range(rows.size() - 1):
		var row0: Dictionary = rows[i]
		var row1: Dictionary = rows[i + 1]
		if not row0.has("marking_layout") or not row1.has("marking_layout"):
			continue
		var s0 := float(row0["distance"])
		var s1 := float(row1["distance"])
		_active_appearances = APPEARANCE.in_range(path_rules, s0, s1)
		if s1 - s0 < 0.00001:
			continue
		var ext0: Vector2 = row0["lane_extents"]
		var ext1: Vector2 = row1["lane_extents"]
		var e0: Array = row0["row_edges"]
		var e1: Array = row1["row_edges"]
		var domain := PackedVector2Array([Vector2(s0, -ext0.x), Vector2(s0, ext0.y), Vector2(s1, -ext1.x), Vector2(s1, ext1.y)])
		var points := PackedVector3Array([vertices[e0[2]], vertices[e0[3]], vertices[e1[2]], vertices[e1[3]]])
		var context := {"domain": domain, "points": points, "exclusions": exclusions,
			"cut": _marking_cuts.get(Vector2i(_active_path_id, int(row0.get("row_idx", i))), null)}
		var layout0: Dictionary = row0["marking_layout"]
		var layout1: Dictionary = row1["marking_layout"]
		if _active_appearances.is_empty():
			_paint_interval(context, s0, s1, ext0, ext1, layout0, layout1, row0, row1)
			continue
		var offsets := APPEARANCE.intervals(_active_appearances, s0, s1)
		var width0 := float(layout0.get("lane_width", 3.5))
		var width1 := float(layout1.get("lane_width", width0))
		# Split where a growing/shrinking lane becomes the outside lane too.
		for side in [0, 1]:
			for lane in range(1, 13):
				var a := ext0[side] - lane * width0
				var b := ext1[side] - lane * width1
				if absf(b - a) > 0.000001:
					var fraction := -a / (b - a)
					if fraction > 0.0 and fraction < 1.0:
						var distance := lerpf(s0, s1, fraction)
						if not offsets.has(distance):
							offsets.append(distance)
		offsets.sort()
		for part in range(offsets.size() - 1):
			var a := float(offsets[part])
			var b := float(offsets[part + 1])
			if b - a < 0.000001:
				continue
			var t0 := (a - s0) / (s1 - s0)
			var t1 := (b - s0) / (s1 - s0)
			var l0 := layout0.duplicate()
			var l1 := layout1.duplicate()
			l0.lane_width = lerpf(width0, width1, t0)
			l1.lane_width = lerpf(width0, width1, t1)
			_paint_interval(context, a, b, ext0.lerp(ext1, t0), ext0.lerp(ext1, t1), l0, l1, row0, row1)
		_paint_stop_lines(context, s0, s1, ext0, ext1, width0, width1)
	_active_appearances = path_rules


func _paint_interval(context: Dictionary, s0: float, s1: float, ext0: Vector2, ext1: Vector2,
		layout0: Dictionary, layout1: Dictionary, row0: Dictionary, row1: Dictionary) -> void:
	var transition := bool(row0.get("lateral_transition", false)) or bool(row1.get("lateral_transition", false))
	# The joining path contributes a lane, not another opposing-traffic
	# centerline. Its interior join boundary is painted by the host edge.
	var joining := transition
	for row: Dictionary in [row0, row1]:
		for side in ["lateral_left", "lateral_right"]:
			for contact: Vector3 in row.get(side, []):
				if contact.z < 0.5:
					joining = true
	# A one-way profile has no opposing center divider.
	if not _suppress_joining_centerline and not joining and minf(ext0.x + ext1.x, ext0.y + ext1.y) > 0.001:
		_line(context, Vector2(s0, 0), Vector2(s1, 0), _center_style((s0 + s1) * 0.5), 0)
	for side in [-1, 1]:
		var extent0 := ext0.x if side < 0 else ext0.y
		var extent1 := ext1.x if side < 0 else ext1.y
		var contact_key := "lateral_left" if side < 0 else "lateral_right"
		var contacts: Array = row0.get(contact_key, [])
		var next_contacts: Array = row1.get(contact_key, [])
		var shared_edge := not contacts.is_empty() or not next_contacts.is_empty()
		# A shared edge belongs to the joined asphalt, so it has no edge stripe.
		# A partial contact must not leave a short lane stripe at the taper.
		if maxf(extent0, extent1) <= 0.001:
			continue
		var inset := maxf(float(_settings["edge_inset"]), float(_settings["line_width"]) * 0.5)
		if not shared_edge and not transition and not _edge_is_internal(context, side):
			_line(context, Vector2(s0, side * maxf(0.0, extent0 - inset)), Vector2(s1, side * maxf(0.0, extent1 - inset)), _outer_style(side, (extent0 + extent1) * 0.5, (float(layout0.get("lane_width", 3.5)) + float(layout1.get("lane_width", 3.5))) * 0.5, (s0 + s1) * 0.5), 1)
		if not bool(layout0.get("enabled", false)):
			continue
		var width0 := maxf(0.01, float(layout0.get("lane_width", 3.5)))
		var width1 := maxf(0.01, float(layout1.get("lane_width", width0)))
		var lanes := ceili(maxf(extent0 / width0, extent1 / width1))
		for lane in range(1, lanes):
			# Clip separators to the painted interior, away from the edge stripe.
			var interior := _side_polygon(s0, s1, side, 0.0, 0.0, maxf(0.0, extent0 - inset * 2.0), maxf(0.0, extent1 - inset * 2.0))
			_line(context, Vector2(s0, side * lane * width0), Vector2(s1, side * lane * width1), _separator_style(side, lane, (s0 + s1) * 0.5), 1, interior)
		if _has_hatching() and not row0.get("lateral_transition",false) and not row1.get("lateral_transition",false):
			_hatching(context, s0, s1, side, extent0, extent1, width0, width1, layout0, layout1, inset)


func _center_style(distance: float) -> int:
	var style := int(APPEARANCE.value_at(_active_appearances, -1, 1, distance, "inner_line_style", _settings.center_style))
	return int(APPEARANCE.value_at(_active_appearances, 1, 1, distance, "inner_line_style", style))


func _separator_style(side: int, boundary: int, distance: float) -> int:
	var style := int(APPEARANCE.value_at(_active_appearances, side, boundary, distance, "outer_line_style", _settings.lane_style))
	return int(APPEARANCE.value_at(_active_appearances, side, boundary + 1, distance, "inner_line_style", style))


func _outer_style(side: int, extent: float, width: float, distance: float) -> int:
	var lane := maxi(1, ceili((extent - 0.000001) / maxf(0.01, width)))
	return int(APPEARANCE.value_at(_active_appearances, side, lane, distance, "outer_line_style", _settings.edge_style))


func _has_hatching() -> bool:
	if _settings.hatching_enabled:
		return true
	for rule: Dictionary in _active_appearances:
		if rule.transition_hatching == 1:
			return true
	return false


func _paint_stop_lines(context: Dictionary, s0: float, s1: float, ext0: Vector2, ext1: Vector2, width0: float, width1: float) -> void:
	var lane_spans: Dictionary = {}
	var inset := maxf(float(_settings.edge_inset), float(_settings.line_width) * 0.5)
	for rule: Dictionary in _active_appearances:
		var finish := minf(float(rule.end), float(_path_lengths.get(_active_path_id, INF)))
		if finish <= rule.start:
			continue
		var spans: Array[Vector2] = []
		if rule.stop_line_at_start:
			spans.append(Vector2(rule.start, minf(finish, rule.start + rule.stop_line_width)))
		if rule.stop_line_at_end and is_finite(finish):
			spans.append(Vector2(maxf(rule.start, finish - rule.stop_line_width), finish))
		var key := Vector2i(rule.side, rule.lane)
		if not lane_spans.has(key):
			lane_spans[key] = []
		for span in spans:
			var a := maxf(span.x, s0)
			var b := minf(span.y, s1)
			if b > a:
				lane_spans[key].append(Vector2(a, b))
	for key: Vector2i in lane_spans:
		var spans: Array = lane_spans[key]
		spans.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var merged: Array[Vector2] = []
		for span: Vector2 in spans:
			if not merged.is_empty() and span.x <= merged[-1].y:
				merged[-1].y = maxf(merged[-1].y, span.y)
			else:
				merged.append(span)
		var side := key.x
		var lane := key.y
		var extent0 := ext0.x if side < 0 else ext0.y
		var extent1 := ext1.x if side < 0 else ext1.y
		var polygon := _side_polygon(s0, s1, side, (lane - 1) * width0 + inset, (lane - 1) * width1 + inset,
			maxf((lane - 1) * width0 + inset, minf(lane * width0, extent0) - inset),
			maxf((lane - 1) * width1 + inset, minf(lane * width1, extent1) - inset))
		for span in merged:
			_emit(_clip_band(polygon, Vector2.RIGHT, span.x, span.y), context, 1)


func _edge_is_internal(context: Dictionary, side: int) -> bool:
	if _final_asphalt == null:
		return false
	var points: PackedVector3Array = context.points
	var hits := 0
	for t in [0.25, 0.5, 0.75]:
		var left := points[0].lerp(points[2], t)
		var right := points[1].lerp(points[3], t)
		var lateral := right - left
		lateral.y = 0.0
		if lateral.length_squared() < 0.000001:
			continue
		var edge := left if side < 0 else right
		var probe := edge + lateral.normalized() * side * 0.75
		var surface: Dictionary = _final_asphalt.nearest_height_at(probe, 0.02)
		if surface.found and absf(float(surface.height) - probe.y) < 0.75:
			hits += 1
	return hits >= 2


func _line(context: Dictionary, a: Vector2, b: Vector2, style: int, bucket: int, interior := PackedVector2Array()) -> void:
	if style == OFF:
		return
	var width := maxf(0.001, float(_settings["line_width"]))
	var offsets := [0.0]
	if style == DOUBLE_SOLID or style == DOUBLE_DASHED:
		var shift := (maxf(0.0, float(_settings["double_gap"])) + width) * 0.5
		offsets = [-shift, shift]
	for offset: float in offsets:
		var polygon := PackedVector2Array([a + Vector2(0, offset - width * 0.5), b + Vector2(0, offset - width * 0.5), b + Vector2(0, offset + width * 0.5), a + Vector2(0, offset + width * 0.5)])
		if not interior.is_empty():
			polygon = _clip_convex(polygon, interior)
		if polygon.size() < 3:
			continue
		if style == DASHED or style == DOUBLE_DASHED:
			var dash := maxf(0.01, float(_settings["dash_length"]))
			var period := dash + maxf(0.01, float(_settings["dash_gap"]))
			var phase := float(_settings["dash_offset"])
			var first := floori((a.x + phase) / period)
			var last := floori((b.x + phase) / period)
			for index in range(first, last + 1):
				var start := index * period - phase
				_emit(_clip_band(polygon, Vector2.RIGHT, start, start + dash), context, bucket)
		else:
			_emit(polygon, context, bucket)


func _hatching(context: Dictionary, s0: float, s1: float, side: int, extent0: float, extent1: float, width0: float, width1: float, layout0: Dictionary, layout1: Dictionary, inset: float) -> void:
	var prefix := "left" if side < 0 else "right"
	var active: Dictionary = {}
	for layout in [layout0, layout1]:
		var phase := float(layout.get("transition", 0.0))
		if int(layout.get(prefix + "_lanes_from", 1)) != int(layout.get(prefix + "_lanes_to", 1)) and phase > 0.00001 and phase < 0.99999:
			active = layout
			break
	if active.is_empty():
		# A very short transition may have just its two endpoint rows.
		if absf(extent1 / width1 - extent0 / width0) <= 0.00001:
			return
		active = layout1 if float(layout0.get("transition", 0.0)) >= 0.99999 else layout0
	var common_lanes := mini(int(active.get(prefix + "_lanes_from", 1)), int(active.get(prefix + "_lanes_to", 1)))
	var inner0 := common_lanes * width0 + inset
	var inner1 := common_lanes * width1 + inset
	var outer0 := maxf(inner0, extent0 - inset)
	var outer1 := maxf(inner1, extent1 - inset)
	if maxf(outer0 - inner0, outer1 - inner1) <= 0.001:
		return
	var polygon := _side_polygon(s0, s1, side, inner0, inner1, outer0, outer1)
	var slope := float(side) / tan(deg_to_rad(clampf(float(_settings["hatch_angle"]), 15.0, 75.0)))
	var axis := Vector2(1.0, -slope)
	var band_width := maxf(0.01, float(_settings["hatch_width"])) * axis.length()
	var spacing := maxf(band_width + 0.01, float(_settings["hatch_spacing"]))
	var low := INF
	var high := -INF
	for point in polygon:
		low = minf(low, axis.dot(point))
		high = maxf(high, axis.dot(point))
	for index in range(floori(low / spacing), floori(high / spacing) + 1):
		var band := _clip_band(polygon, axis, index * spacing, index * spacing + band_width)
		if _active_appearances.is_empty():
			_emit(band, context, 2)
			continue
		for lane in range(1, ceili(maxf(extent0 / width0, extent1 / width1)) + 1):
			var enabled_ := int(APPEARANCE.value_at(_active_appearances, side, lane, (s0 + s1) * 0.5,
				"transition_hatching", int(bool(_settings.hatching_enabled))))
			if enabled_ == 0:
				continue
			var lane_area := _side_polygon(s0, s1, side, (lane - 1) * width0, (lane - 1) * width1, lane * width0, lane * width1)
			_emit(_clip_convex(band, lane_area), context, 2)


func _side_polygon(s0: float, s1: float, side: int, inner0: float, inner1: float, outer0: float, outer1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(s0, side * inner0), Vector2(s1, side * inner1), Vector2(s1, side * outer1), Vector2(s0, side * outer0)])


func _emit(polygon: PackedVector2Array, context: Dictionary, bucket: int) -> void:
	if polygon.size() < 3:
		return
	var pieces: Array[PackedVector2Array] = [polygon]
	for interval: Vector2 in context["exclusions"]:
		var remaining: Array[PackedVector2Array] = []
		for piece in pieces:
			var before := _clip_half_plane(piece, Vector2.LEFT, -interval.x)
			var after := _clip_half_plane(piece, Vector2.RIGHT, interval.y)
			if before.size() >= 3:
				remaining.append(before)
			if after.size() >= 3:
				remaining.append(after)
		pieces = remaining
	var domain: PackedVector2Array = context["domain"]
	var points: PackedVector3Array = context["points"]
	for corners in [[0, 1, 2], [2, 1, 3]]:
		var triangle := PackedVector2Array([domain[corners[0]], domain[corners[1]], domain[corners[2]]])
		var surface := PackedVector3Array([points[corners[0]], points[corners[1]], points[corners[2]]])
		for piece in pieces:
			var clipped := _clip_convex(piece, triangle)
			if clipped.size() >= 3:
				_append_paint(clipped, triangle, surface, bucket, context.get("cut"))


func _append_paint(polygon: PackedVector2Array, triangle: PackedVector2Array, surface: PackedVector3Array,
		bucket_id: int, cut = null) -> void:
	var denominator := (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0])
	if absf(denominator) < 0.0000001:
		return
	var normal := (surface[1] - surface[0]).cross(surface[2] - surface[0]).normalized()
	if normal.length_squared() < 0.5:
		return
	if normal.y < 0.0:
		normal = -normal
	var mapped := PackedVector3Array()
	for point in polygon:
		var weight_b := (point - triangle[0]).cross(triangle[2] - triangle[0]) / denominator
		var weight_c := (triangle[1] - triangle[0]).cross(point - triangle[0]) / denominator
		mapped.append(surface[0] * (1.0 - weight_b - weight_c) + surface[1] * weight_b + surface[2] * weight_c + normal * float(_settings["surface_lift"]))
	var bucket: Dictionary = _buckets[bucket_id]
	var out_vertices: PackedVector3Array = bucket["vertices"]
	var out_normals: PackedVector3Array = bucket["normals"]
	var out_uvs: PackedVector2Array = bucket["uvs"]
	for i in range(1, polygon.size() - 1):
		var a := mapped[0]
		var b := mapped[i]
		var c := mapped[i + 1]
		var ab := b - a
		var ac := c - a
		var area := ab.length_squared() * ac.length_squared() - ab.dot(ac) * ab.dot(ac)
		if area < 0.000000000001:
			continue
		var uv_a := Vector2(polygon[0].y, polygon[0].x)
		var uv_b := Vector2(polygon[i].y, polygon[i].x)
		var uv_c := Vector2(polygon[i + 1].y, polygon[i + 1].x)
		var pieces: Array = cut.subtract(a, b, c) if cut != null else [PackedVector3Array([a, b, c])]
		if _final_asphalt != null:
			var on_asphalt: Array = []
			for piece: PackedVector3Array in pieces:
				on_asphalt.append_array(_final_asphalt.intersect_surface(piece[0], piece[1], piece[2]))
			pieces = on_asphalt
		for piece: PackedVector3Array in pieces:
			var cross := (piece[1] - piece[0]).cross(piece[2] - piece[0])
			if cross.length_squared() < 0.000000000001:
				continue
			var corners := [0, 2, 1] if cross.dot(normal) > 0.0 else [0, 1, 2]
			for index: int in corners:
				var point: Vector3 = piece[index]
				var offset := point - a
				var weight_b := (ac.length_squared() * offset.dot(ab) - ab.dot(ac) * offset.dot(ac)) / area
				var weight_c := (ab.length_squared() * offset.dot(ac) - ab.dot(ac) * offset.dot(ab)) / area
				out_vertices.append(point)
				out_normals.append(normal)
				out_uvs.append(uv_a * (1.0 - weight_b - weight_c) + uv_b * weight_b + uv_c * weight_c)
	bucket["vertices"] = out_vertices
	bucket["normals"] = out_normals
	bucket["uvs"] = out_uvs


func _clip_band(polygon: PackedVector2Array, axis: Vector2, start: float, end: float) -> PackedVector2Array:
	return _clip_half_plane(_clip_half_plane(polygon, axis, start), -axis, -end)


func _clip_half_plane(polygon: PackedVector2Array, axis: Vector2, limit: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	if polygon.is_empty():
		return result
	var previous := polygon[polygon.size() - 1]
	var previous_distance := axis.dot(previous) - limit
	for current in polygon:
		var distance := axis.dot(current) - limit
		if (distance >= 0.0) != (previous_distance >= 0.0):
			result.append(previous.lerp(current, previous_distance / (previous_distance - distance)))
		if distance >= 0.0:
			result.append(current)
		previous = current
		previous_distance = distance
	return result


func _clip_convex(polygon: PackedVector2Array, boundary: PackedVector2Array) -> PackedVector2Array:
	var orientation := 0.0
	for i in range(boundary.size()):
		orientation += boundary[i].cross(boundary[(i + 1) % boundary.size()])
	var result := polygon
	for i in range(boundary.size()):
		var a := boundary[i]
		var edge := boundary[(i + 1) % boundary.size()] - a
		var normal := Vector2(-edge.y, edge.x) * (1.0 if orientation >= 0.0 else -1.0)
		result = _clip_half_plane(result, normal, normal.dot(a))
		if result.size() < 3:
			break
	return result


func _material(bucket: int) -> Material:
	var custom: Material = _settings["material_override"]
	if custom != null:
		return custom
	var material := StandardMaterial3D.new()
	material.albedo_color = _settings[["center_color", "line_color", "hatch_color"][bucket]]
	material.roughness = 0.9
	return material
