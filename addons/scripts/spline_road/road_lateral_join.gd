@tool
extends RefCounted
## Joins facing asphalt edges of source splines with a shared join channel. Source rows
## remain immutable in the sampling cache; only this generation's arrays change.
const CUT = preload("./terrain_road_mesh_cut.gd")
const CELL := 16.0
const EPS := 0.00001
var groups: Array[String] = []
var layers: Array[int] = []
var gap := 0.35
var overlap := 1.0
var height := 0.15
var height_blend_width := 0.0
var alignment := 0.96
var inverted := false
var stats: Dictionary = {}
var _cuts: Dictionary = {}
var _paint_cuts: Dictionary = {}
var _band_cuts: Dictionary = {}
var _mask_seen: Dictionary = {}
var _band_owners: Dictionary = {}
var _bridges: Array = []
var merge_pairs: Dictionary = {}
var marking_cuts: Dictionary = {}
var _active_pairs: Dictionary = {}
var _source_vertices := PackedVector3Array()
var _lane_surfaces: Dictionary = {}
var _transitions := preload("./road_lateral_transition.gd").new()

func configure(road: Node, paths: Array[Path3D]) -> void:
	_transitions.configure(road,paths)
	groups.clear()
	layers.clear()
	for path in paths:
		groups.append(str(path.call("get_lateral_join_group")) if path.has_method("get_lateral_join_group") else "")
		layers.append(int(path.call("get_lateral_join_layers")) if path.has_method("get_lateral_join_layers") else 0)
	gap = road.lateral_join_max_gap
	overlap = road.lateral_join_max_overlap
	height = road.lateral_join_height_tolerance
	height_blend_width = road.lateral_join_height_blend_width
	alignment = cos(deg_to_rad(road.lateral_join_max_angle_degrees))
	inverted = road.invert_faces
	stats = {"contacts": 0, "length": 0.0, "bridge_triangles": 0, "transitions": []}
	_cuts.clear()
	_paint_cuts.clear()
	_band_cuts.clear()
	_mask_seen.clear()
	_band_owners.clear()
	_bridges.clear()
	merge_pairs.clear()
	marking_cuts.clear()
	_active_pairs.clear()
	_source_vertices = PackedVector3Array()
	_lane_surfaces.clear()

func prepare(vertices: PackedVector3Array, paths: Array) -> void:
	# Find an actual edge contact before giving a shallow merge priority over
	# junction discovery. A connected overlap may then continue into the lane.
	_scan(vertices, paths, {}, true)
	if height_blend_width > EPS and not merge_pairs.is_empty():
		_align_join_rows(vertices, paths)
		_fade_join_bank(vertices, paths)
		# The junction search and endpoint transitions must see the adjusted
		# snapshot, while the authored curve and source sampling cache stay intact.
		merge_pairs.clear()
		_scan(vertices, paths, {}, true)
	_source_vertices = vertices

func owns_junction_pair(a: Dictionary, b: Dictionary) -> bool:
	var key := Vector2i(mini(a.path_id,b.path_id),maxi(a.path_id,b.path_id))
	if not merge_pairs.has(key) or absf(a.position.y-b.position.y) > height:
		return false
	var direction := _xz(a.out_dir).normalized()
	if absf(direction.dot(_xz(b.out_dir).normalized())) < alignment:
		return false
	# Priority belongs to this local contact, not every socket on the two paths.
	var across := Vector2(direction.y,-direction.x)
	var a0 := _xz(_source_vertices[a.row_edges[2]]).dot(across)
	var a1 := _xz(_source_vertices[a.row_edges[3]]).dot(across)
	var b0 := _xz(_source_vertices[b.row_edges[2]]).dot(across)
	var b1 := _xz(_source_vertices[b.row_edges[3]]).dot(across)
	return maxf(minf(b0,b1)-maxf(a0,a1),minf(a0,a1)-maxf(b0,b1)) <= gap+EPS

func apply(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
		lane: PackedInt32Array, shoulder: PackedInt32Array, sidewalk: PackedInt32Array,
		paths: Array, exclusions: Dictionary, blocked_sides: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	_transitions.apply(vertices,normals,uvs,lane,shoulder,sidewalk,paths,groups,layers,exclusions,merge_pairs)
	stats.transitions = _transitions.reports.duplicate(true)
	var tags: Dictionary = {}
	for path_id in range(paths.size()):
		for row: Dictionary in paths[path_id]:
			for edge in range(row.row_edges.size()):
				tags[int(row.row_edges[edge])] = Vector3i(path_id, row.row_idx, edge)
	_build_lane_surfaces(vertices, lane, tags)
	_scan(vertices, paths, exclusions, false)
	if stats.contacts == 0:
		_lane_surfaces.clear()
		return
	# Built-in terrain strips must not grow into the joined interior.
	for rows: Array in paths:
		for i in range(rows.size()-1):
			for side in [-1,1]:
				if rows[i].get("lateral_left" if side < 0 else "lateral_right", []).is_empty():
					continue
				for row: Dictionary in [rows[i],rows[i+1]]:
					for edge in ([0,1] if side < 0 else [4,5]):
						blocked_sides[int(row.row_edges[edge])] = true
	_trim_surface(vertices, normals, uvs, lane, tags, _cuts)
	_trim_bands(vertices, normals, uvs, shoulder, tags, paths)
	_trim_bands(vertices, normals, uvs, sidewalk, tags, paths)
	_trim_surface(vertices, normals, uvs, shoulder, tags, _band_cuts, true)
	_trim_surface(vertices, normals, uvs, sidewalk, tags, _band_cuts, true)
	_trim_band_overlaps(vertices,normals,uvs,shoulder,sidewalk,tags)
	if height_blend_width > EPS:
		_finish_join_bank(vertices, tags, paths)
	for bridge: PackedVector3Array in _bridges:
		for ids in [[0, 1, 2], [2, 1, 3]]:
			var points := PackedVector3Array([bridge[ids[0]], bridge[ids[1]], bridge[ids[2]]])
			var cross_ := (points[1]-points[0]).cross(points[2]-points[0])
			if cross_.length_squared() < EPS*EPS:
				continue
			if (cross_.y > 0.0) == inverted:
				var swap := points[1]
				points[1] = points[2]
				points[2] = swap
			for point in points:
				lane.append(vertices.size())
				vertices.append(point)
				normals.append(Vector3.UP)
				uvs.append(_xz(point) * 0.2)
				stats.bridge_triangles += 1
	stats.build_ms = (Time.get_ticks_usec() - started) / 1000.0
	# Paint keeps the host's continuous markings over the joined asphalt. Its
	# cutout belongs to the joining path, independently of asphalt ownership.
	marking_cuts = _paint_cuts.duplicate()
	_cuts.clear()
	_paint_cuts.clear()
	_band_cuts.clear()
	_mask_seen.clear()
	_band_owners.clear()
	_bridges.clear()
	_lane_surfaces.clear()

func _build_lane_surfaces(vertices: PackedVector3Array, lane: PackedInt32Array, tags: Dictionary) -> void:
	_lane_surfaces.clear()
	for i in range(0, lane.size(), 3):
		var first: Vector3i = tags.get(lane[i], Vector3i(-1, -1, -1))
		var second: Vector3i = tags.get(lane[i + 1], Vector3i(-1, -1, -1))
		var third: Vector3i = tags.get(lane[i + 2], Vector3i(-1, -1, -1))
		if first.x < 0 or first.x != second.x or first.x != third.x:
			continue
		var row := mini(first.y, mini(second.y, third.y))
		var key := Vector2i(first.x, row)
		if not _lane_surfaces.has(key):
			_lane_surfaces[key] = PackedVector3Array()
		var points: PackedVector3Array = _lane_surfaces[key]
		for j in range(3):
			points.append(vertices[lane[i + j]])
		_lane_surfaces[key] = points

func _scan(vertices: PackedVector3Array, paths: Array, exclusions: Dictionary, discover_only: bool) -> void:
	var cells: Dictionary = {}
	var segments: Array = []
	for path_id in range(paths.size()):
		if path_id >= groups.size() or (groups[path_id].is_empty() and layers[path_id] == 0):
			continue
		var rows: Array = paths[path_id]
		for i in range(rows.size() - 1):
			# Endpoint junctions own their complete cross sections.
			var blocked := false
			for region: Vector2 in exclusions.get(path_id, []):
				if rows[i].distance < region.y and rows[i+1].distance > region.x:
					blocked = true
			if blocked:
				continue
			for side in [-1, 1]:
				var edge := 2 if side < 0 else 3
				var a: Vector3 = vertices[rows[i].row_edges[edge]]
				var b: Vector3 = vertices[rows[i+1].row_edges[edge]]
				var direction := _xz(b-a)
				if direction.length() < EPS:
					continue
				var across: Vector3 = vertices[rows[i].row_edges[3]] - vertices[rows[i].row_edges[2]]
				across += vertices[rows[i+1].row_edges[3]] - vertices[rows[i+1].row_edges[2]]
				if across.length() < EPS:
					continue
				var segment := {"path": path_id, "row": i, "side": side, "a": a, "b": b,
					"out": _xz(across).normalized() * side}
				var reach := maxf(gap, overlap) if discover_only else maxf(maxf(gap, overlap), across.length())
				var bounds := Rect2(_xz(a), Vector2.ZERO).expand(_xz(b)).grow(reach + EPS)
				var candidates: Dictionary = {}
				for x in range(floori(bounds.position.x/CELL), floori(bounds.end.x/CELL)+1):
					for z in range(floori(bounds.position.y/CELL), floori(bounds.end.y/CELL)+1):
						for id in cells.get(Vector2i(x,z), []):
							candidates[id] = true
				for id in candidates:
					var other: Dictionary = segments[id]
					if other.path == path_id or not _same_join_channel(other.path, path_id):
						continue
					_contact(other, segment, vertices, paths, discover_only)
				var id := segments.size()
				segments.append(segment)
				for x in range(floori(bounds.position.x/CELL), floori(bounds.end.x/CELL)+1):
					for z in range(floori(bounds.position.y/CELL), floori(bounds.end.y/CELL)+1):
						var key := Vector2i(x,z)
						if not cells.has(key):
							cells[key] = []
						cells[key].append(id)

func _same_join_channel(a: int, b: int) -> bool:
	return (layers[a] & layers[b]) != 0 or (not groups[a].is_empty() and groups[a] == groups[b])

func _contact(a: Dictionary, b: Dictionary, vertices: PackedVector3Array, paths: Array, discover_only: bool) -> void:
	var delta := _xz(a.b-a.a)
	var length := delta.length()
	var axis := delta/length
	var b_delta := _xz(b.b-b.a)
	if not discover_only and merge_pairs.has(Vector2i(mini(a.path,b.path),maxi(a.path,b.path))):
		var middle: Vector3 = (b.a+b.b)*0.5
		var t := clampf(_xz(middle-a.a).dot(delta)/delta.length_squared(),0,1)
		if absf(a.a.lerp(a.b,t).y-middle.y) <= height:
			_surface_mask(b,a,vertices,paths,_cuts,false)
			_surface_mask(a,b,vertices,paths,_paint_cuts,false)
			_surface_mask(b,a,vertices,paths,_band_cuts,false)
			_surface_mask(a,b,vertices,paths,_band_cuts,true)
	if absf(axis.dot(b_delta.normalized())) < alignment or a.out.dot(b.out) > -alignment:
		return
	var b0 := (_xz(b.a)-_xz(a.a)).dot(axis)
	var b1 := (_xz(b.b)-_xz(a.a)).dot(axis)
	if absf(b1-b0) < EPS:
		return
	var interval := Vector2(maxf(0.0, minf(b0,b1)), minf(length, maxf(b0,b1)))
	if interval.y-interval.x < EPS:
		return
	# Both gap and height vary linearly inside this pair of sampled edges.
	var bp0: Vector3 = b.a.lerp(b.b, -b0/(b1-b0))
	var bp1: Vector3 = b.a.lerp(b.b, (length-b0)/(b1-b0))
	var g0: float = _xz(bp0-a.a).dot(a.out)
	var g1: float = _xz(bp1-a.b).dot(a.out)
	interval = _limit(interval, bp0.y-a.a.y, bp1.y-a.b.y, length, -height, height)
	if interval.y-interval.x < EPS:
		return
	var ta := interval/length
	var tb := Vector2((interval.x-b0)/(b1-b0), (interval.y-b0)/(b1-b0))
	var ar: Array = paths[a.path]
	var br: Array = paths[b.path]
	# Do not consume an entire narrow road or cross its opposite asphalt edge.
	var aw: float = (ar[a.row].lane_extents.x + ar[a.row].lane_extents.y + ar[a.row+1].lane_extents.x + ar[a.row+1].lane_extents.y) * 0.5
	var bw: float = (br[b.row].lane_extents.x + br[b.row].lane_extents.y + br[b.row+1].lane_extents.x + br[b.row+1].lane_extents.y) * 0.5
	var key_pair := Vector2i(mini(a.path,b.path),maxi(a.path,b.path))
	var allowed_overlap := overlap if discover_only or not merge_pairs.has(key_pair) else maxf(overlap,minf(aw,bw)-EPS)
	interval = _limit(interval, g0, g1, length, -minf(allowed_overlap,minf(aw,bw)-EPS), gap)
	if interval.y-interval.x < EPS:
		return
	if discover_only:
		merge_pairs[key_pair] = true
		return
	_active_pairs[key_pair] = true
	ta = interval/length
	tb = Vector2((interval.x-b0)/(b1-b0), (interval.y-b0)/(b1-b0))
	_add_range(ar[a.row], a.side, ta, true)
	_add_range(br[b.row], b.side, Vector2(minf(tb.x,tb.y),maxf(tb.x,tb.y)), false)
	var positive := _limit(interval, g0, g1, length, 0.0, gap)
	if positive.y-positive.x > EPS:
		_bridges.append(PackedVector3Array([a.a.lerp(a.b,positive.x/length),
			b.a.lerp(b.b,(positive.x-b0)/(b1-b0)), a.a.lerp(a.b,positive.y/length),
			b.a.lerp(b.b,(positive.y-b0)/(b1-b0))]))
	stats.contacts += 1
	stats.length += interval.y-interval.x

func _surface_mask(source: Dictionary, target: Dictionary, vertices: PackedVector3Array,
		paths: Array, masks: Dictionary, bands: bool) -> void:
	var key := Vector2i(target.path,target.row)
	var stamp := [target.path,target.row,source.path,source.row,bands,
		1 if is_same(masks, _band_cuts) else (2 if is_same(masks, _paint_cuts) else 0)]
	if _mask_seen.has(stamp):
		return
	_mask_seen[stamp] = true
	if not masks.has(key):
		masks[key] = CUT.new()
	var source_key := Vector2i(source.path, source.row)
	if not _lane_surfaces.has(source_key):
		return
	if bands:
		if not _band_owners.has(key):
			_band_owners[key] = {}
		_band_owners[key][Vector2i(source.path,source.row)] = true
	masks[key].append_surface(_lane_surfaces[source_key],PackedInt32Array(),Transform3D.IDENTITY)

func _trim_band_overlaps(vertices: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, shoulder: PackedInt32Array, sidewalk: PackedInt32Array, tags: Dictionary) -> void:
	# Only the surviving bands can own an overlap. Masking against the original
	# full cross section would erase the new exterior where the old interior was removed.
	var surfaces: Dictionary = {}
	for indices in [shoulder,sidewalk]:
		for i in range(0,indices.size(),3):
			var a: Vector3i = tags.get(indices[i],Vector3i(-1,-1,-1))
			var b: Vector3i = tags.get(indices[i+1],Vector3i(-1,-1,-1))
			var c: Vector3i = tags.get(indices[i+2],Vector3i(-1,-1,-1))
			if a.x < 0 or a.x != b.x or a.x != c.x:
				continue
			var key := Vector2i(a.x,mini(a.y,mini(b.y,c.y)))
			if not surfaces.has(key):
				surfaces[key] = PackedVector3Array()
			for j in range(3):
				surfaces[key].append(vertices[indices[i+j]])
	var masks: Dictionary = {}
	for target in _band_owners:
		for source in _band_owners[target]:
			if not surfaces.has(source):
				continue
			if not masks.has(target):
				masks[target] = CUT.new()
			masks[target].append_surface(surfaces[source],PackedInt32Array(),Transform3D.IDENTITY)
	_trim_surface(vertices,normals,uvs,shoulder,tags,masks,true)
	_trim_surface(vertices,normals,uvs,sidewalk,tags,masks,true)

func _align_join_rows(vertices: PackedVector3Array, paths: Array) -> void:
	# Move each joining cross-section by one vertical offset. This follows the
	# host's grade without flattening the target's crossfall or curve banking.
	var started := Time.get_ticks_usec()
	var moved := 0
	var queried := 0
	for pair: Vector2i in merge_pairs:
		var host_rows: Array = paths[pair.x]
		var target_rows: Array = paths[pair.y]
		if host_rows.size() < 2 or target_rows.is_empty():
			continue
		var surface: RefCounted = CUT.new()
		for i in range(host_rows.size()-1):
			var first: Array = host_rows[i].row_edges
			var second: Array = host_rows[i+1].row_edges
			var quad := PackedVector3Array([vertices[first[2]],vertices[first[3]],
				vertices[second[2]],vertices[second[3]]])
			surface.append_surface(quad,PackedInt32Array([0,1,2,2,1,3]),Transform3D.IDENTITY)
		for row: Dictionary in target_rows:
			var best_distance := INF
			var best_delta := 0.0
			for edge in [2,3]:
				var point: Vector3 = vertices[row.row_edges[edge]]
				var nearest: Dictionary = surface.nearest_height_at(point,height_blend_width)
				queried += 1
				if not nearest.found:
					continue
				var distance: float = nearest.distance
				var delta: float = nearest.height-point.y
				if distance < best_distance-EPS or (absf(distance-best_distance) <= EPS and absf(delta) < absf(best_delta)):
					best_distance = distance
					best_delta = delta
			if best_distance == INF:
				continue
			var inner := minf(height_blend_width,maxf(gap,0.35))
			var t := clampf((best_distance-inner)/maxf(EPS,height_blend_width-inner),0.0,1.0)
			var offset := best_delta*(1.0-t*t*(3.0-2.0*t))
			if absf(offset) <= EPS:
				continue
			for id in row.row_edges:
				var vertex := vertices[id]
				vertex.y += offset
				vertices[id] = vertex
			row.position.y += offset
			moved += 1
		for i in range(target_rows.size()):
			var before: Vector3 = target_rows[maxi(i-1,0)].position
			var after: Vector3 = target_rows[mini(i+1,target_rows.size()-1)].position
			if (after-before).length_squared() > EPS*EPS:
				target_rows[i].out_dir = (after-before).normalized()
	stats.align_ms = (Time.get_ticks_usec()-started)/1000.0
	stats.align_rows = moved
	stats.align_queries = queried

func _fade_join_bank(vertices: PackedVector3Array, paths: Array) -> void:
	# After the longitudinal grade is aligned, match the host's crossfall at
	# overlapping asphalt and ease back to the joining road's authored bank.
	var moved := 0
	for pair: Vector2i in merge_pairs:
		var surface: RefCounted = CUT.new()
		var host_rows: Array = paths[pair.x]
		for i in range(host_rows.size()-1):
			var a: Array = host_rows[i].row_edges
			var b: Array = host_rows[i+1].row_edges
			var quad := PackedVector3Array([vertices[a[2]],vertices[a[3]],vertices[b[2]],vertices[b[3]]])
			surface.append_surface(quad,PackedInt32Array([0,1,2,2,1,3]),Transform3D.IDENTITY)
		for row: Dictionary in paths[pair.y]:
			var center_delta := 0.0
			for edge in range(row.row_edges.size()):
				var id: int = row.row_edges[edge]
				var point := vertices[id]
				var nearest: Dictionary = surface.nearest_height_at(point,height_blend_width)
				if not nearest.found:
					continue
				var t := clampf(float(nearest.distance)/height_blend_width,0.0,1.0)
				var weight := 1.0-t*t*(3.0-2.0*t)
				var delta := (float(nearest.height)-point.y)*weight
				if edge == 2 or edge == 3:
					center_delta += delta*0.5
				if absf(delta) <= EPS:
					continue
				point.y += delta
				vertices[id] = point
				moved += 1
			row.position.y += center_delta
	stats.bank_fade_vertices = moved

func _finish_join_bank(vertices: PackedVector3Array, tags: Dictionary, paths: Array) -> void:
	# Clipping creates new vertices on the common boundary. Reproject those and
	# nearby target vertices against the host surface after topology is final.
	var surfaces: Dictionary = {}
	for pair: Vector2i in _active_pairs:
		if surfaces.has(pair.y):
			continue
		var surface: RefCounted = CUT.new()
		var host_rows: Array = paths[pair.x]
		for i in range(host_rows.size()-1):
			var a: Array = host_rows[i].row_edges
			var b: Array = host_rows[i+1].row_edges
			var quad := PackedVector3Array([vertices[a[2]],vertices[a[3]],vertices[b[2]],vertices[b[3]]])
			surface.append_surface(quad,PackedInt32Array([0,1,2,2,1,3]),Transform3D.IDENTITY)
		surfaces[pair.y] = surface
	var moved := 0
	for id in range(vertices.size()):
		var tag: Vector3i = tags.get(id,Vector3i(-1,-1,-1))
		if not surfaces.has(tag.x):
			continue
		var point := vertices[id]
		var nearest: Dictionary = surfaces[tag.x].nearest_height_at(point,height_blend_width)
		if not nearest.found:
			continue
		var t := clampf(float(nearest.distance)/height_blend_width,0.0,1.0)
		var weight := 1.0-t*t*(3.0-2.0*t)
		var adjusted := lerpf(point.y,float(nearest.height),weight)
		if absf(adjusted-point.y) <= EPS:
			continue
		point.y = adjusted
		vertices[id] = point
		moved += 1
	stats.bank_finish_vertices = moved

func _limit(interval: Vector2, v0: float, v1: float, length: float, minimum: float, maximum: float) -> Vector2:
	if interval.y <= interval.x:
		return Vector2.ZERO
	if absf(v1-v0) < EPS:
		return interval if v0 >= minimum-EPS and v0 <= maximum+EPS else Vector2.ZERO
	var start := (minimum-v0)*length/(v1-v0)
	var end := (maximum-v0)*length/(v1-v0)
	return Vector2(maxf(interval.x,minf(start,end)), minf(interval.y,maxf(start,end)))

func _add_range(row: Dictionary, side: int, interval: Vector2, owner_: bool) -> void:
	var key := "lateral_left" if side < 0 else "lateral_right"
	if not row.has(key):
		row[key] = []
	row[key].append(Vector3(clampf(interval.x,0,1),clampf(interval.y,0,1),1.0 if owner_ else 0.0))

static func outside_ranges(contacts: Array) -> Array[Vector2]:
	var ranges: Array[Vector2] = []
	for contact: Vector3 in contacts:
		ranges.append(Vector2(contact.x,contact.y))
	ranges.sort_custom(func(a: Vector2,b: Vector2) -> bool: return a.x < b.x)
	var result: Array[Vector2] = []
	var start := 0.0
	for interval in ranges:
		if interval.x > start+EPS:
			result.append(Vector2(start,interval.x))
		start = maxf(start,interval.y)
	if start < 1.0-EPS:
		result.append(Vector2(start,1.0))
	return result

func _trim_bands(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
		indices: PackedInt32Array, tags: Dictionary, paths: Array) -> void:
	var output := PackedInt32Array()
	for i in range(0,indices.size(),3):
		var ids := [indices[i],indices[i+1],indices[i+2]]
		var t0: Vector3i = tags.get(ids[0],Vector3i(-1,-1,-1))
		var t1: Vector3i = tags.get(ids[1],Vector3i(-1,-1,-1))
		var t2: Vector3i = tags.get(ids[2],Vector3i(-1,-1,-1))
		var row := mini(t0.y,mini(t1.y,t2.y))
		var left := maxi(t0.z,maxi(t1.z,t2.z)) <= 2
		var right := mini(t0.z,mini(t1.z,t2.z)) >= 3
		if t0.x < 0 or t0.x != t1.x or t0.x != t2.x or not (left or right) or maxi(t0.y,maxi(t1.y,t2.y)) != row+1:
			output.append_array(ids)
			continue
		var contacts: Array = paths[t0.x][row].get("lateral_left" if left else "lateral_right",[])
		if contacts.is_empty():
			output.append_array(ids)
			continue
		var polygon: Array = []
		for id in ids:
			polygon.append({"p": vertices[id], "n": normals[id], "uv": uvs[id], "t": float(tags[id].y-row)})
		for interval in outside_ranges(contacts):
			var clipped := _clip_parameter(_clip_parameter(polygon,interval.x,true),interval.y,false)
			for j in range(1,clipped.size()-1):
				var first := vertices.size()
				_append_payload([clipped[0],clipped[j],clipped[j+1]],vertices,normals,uvs,output)
				for id in range(first,vertices.size()):
					tags[id] = Vector3i(t0.x,row,0)
	indices.clear()
	indices.append_array(output)

func _clip_parameter(polygon: Array, boundary: float, after: bool) -> Array:
	var result: Array = []
	if polygon.is_empty():
		return result
	var previous: Dictionary = polygon.back()
	for current: Dictionary in polygon:
		var was_in: bool = previous.t >= boundary if after else previous.t <= boundary
		var is_in: bool = current.t >= boundary if after else current.t <= boundary
		if was_in != is_in:
			var t: float = (boundary-previous.t)/(current.t-previous.t)
			result.append({"p": previous.p.lerp(current.p,t), "n": previous.n.lerp(current.n,t).normalized(),
				"uv": previous.uv.lerp(current.uv,t), "t": boundary})
		if is_in:
			result.append(current)
		previous = current
	return result

func _trim_surface(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
		indices: PackedInt32Array, tags: Dictionary, masks: Dictionary, keep_vertical := false) -> void:
	var output := PackedInt32Array()
	for i in range(0,indices.size(),3):
		var ids := [indices[i],indices[i+1],indices[i+2]]
		var tag: Vector3i = tags.get(ids[0],Vector3i(-1,-1,-1))
		var other1: Vector3i = tags.get(ids[1],Vector3i(-1,-1,-1))
		var other2: Vector3i = tags.get(ids[2],Vector3i(-1,-1,-1))
		var key := Vector2i(tag.x,mini(tag.y,mini(other1.y,other2.y)))
		if not masks.has(key) or tags.get(ids[1],Vector3i(-1,-1,-1)).x != tag.x or tags.get(ids[2],Vector3i(-1,-1,-1)).x != tag.x:
			output.append_array(ids)
			continue
		var a := vertices[ids[0]]
		var b := vertices[ids[1]]
		var c := vertices[ids[2]]
		var triangles: Array = masks[key].subtract(a,b,c,keep_vertical)
		if triangles.size() == 1 and triangles[0] == PackedVector3Array([a,b,c]):
			output.append_array(ids)
			continue
		var ab := b-a
		var ac := c-a
		var denominator := ab.length_squared()*ac.length_squared()-ab.dot(ac)*ab.dot(ac)
		if absf(denominator) < EPS:
			output.append_array(ids)
			continue
		for triangle: PackedVector3Array in triangles:
			var payload: Array = []
			for p in triangle:
				var wb := (ac.length_squared()*(p-a).dot(ab)-ab.dot(ac)*(p-a).dot(ac))/denominator
				var wc := (ab.length_squared()*(p-a).dot(ac)-ab.dot(ac)*(p-a).dot(ab))/denominator
				var wa := 1.0-wb-wc
				payload.append({"p": p, "n": (normals[ids[0]]*wa+normals[ids[1]]*wb+normals[ids[2]]*wc).normalized(),
					"uv": uvs[ids[0]]*wa+uvs[ids[1]]*wb+uvs[ids[2]]*wc})
			var first := vertices.size()
			_append_payload(payload,vertices,normals,uvs,output)
			for id in range(first,vertices.size()):
				tags[id] = Vector3i(key.x,key.y,0)
	indices.clear()
	indices.append_array(output)

func _append_payload(points: Array, vertices: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, indices: PackedInt32Array) -> void:
	if (points[1].p-points[0].p).cross(points[2].p-points[0].p).length_squared() < EPS*EPS:
		return
	for point: Dictionary in points:
		indices.append(vertices.size())
		vertices.append(point.p)
		normals.append(point.n)
		uvs.append(point.uv)

func _xz(point: Vector3) -> Vector2:
	return Vector2(point.x,point.z)
