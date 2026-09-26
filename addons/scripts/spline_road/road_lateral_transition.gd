@tool
extends RefCounted
## Adds sampled, curved endpoint tapers to the generation snapshot. Authoring
## curves and lane widths remain unchanged. The regular lateral pass then joins
## these rows, removes interior bands and paints the resulting lane boundary.
const EPS := 0.00001
var reports: Array = []
var _road: Node
var _sources: Array[Path3D] = []
var _merge_pairs: Dictionary = {}

func configure(road: Node, sources: Array[Path3D]) -> void:
	_road = road
	_sources = sources
	reports.clear()

func apply(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
		lane: PackedInt32Array, shoulder: PackedInt32Array, sidewalk: PackedInt32Array,
		paths: Array, groups: Array[String], layers: Array[int], exclusions: Dictionary, merge_pairs: Dictionary) -> void:
	_merge_pairs = merge_pairs
	# Discover all endpoints before appending rows: generated tips cannot become
	# host roads for subsequent endpoints in the same build.
	var plans: Array = []
	for path_id in range(paths.size()):
		var rows: Array = paths[path_id]
		if (groups[path_id].is_empty() and layers[path_id] == 0) or rows.size() < 2 or _sources[path_id].curve.closed:
			continue
		for end in [false, true]:
			var requested: float = _road.lateral_join_transition_length
			if _sources[path_id].has_method("get_lateral_transition_length"):
				var override_: float = _sources[path_id].get_lateral_transition_length(end)
				if override_ >= 0.0:
					requested = override_
			if requested <= EPS:
				continue
			var plan := _find_host(path_id, end, requested, vertices, paths, groups, layers, exclusions)
			if not plan.is_empty():
				plans.append(plan)
	if plans.is_empty():
		return
	for plan: Dictionary in plans:
		_extend(plan, vertices, normals, uvs, lane, shoulder, sidewalk, paths)
	for rows: Array in paths:
		for index in range(rows.size()):
			rows[index].row_idx = index
			if rows[index].get("lateral_transition",false):
				var before := maxi(0,index-1)
				var after := mini(rows.size()-1,index+1)
				rows[index].out_dir = (Vector3(rows[after].position)-Vector3(rows[before].position)).normalized()

func _same_join_channel(a: int, b: int, groups: Array[String], layers: Array[int]) -> bool:
	return (layers[a] & layers[b]) != 0 or (not groups[a].is_empty() and groups[a] == groups[b])

func _find_host(path_id: int, end: bool, requested: float, vertices: PackedVector3Array,
		paths: Array, groups: Array[String], layers: Array[int], exclusions: Dictionary) -> Dictionary:
	var rows: Array = paths[path_id]
	var endpoint: Dictionary = rows.back() if end else rows.front()
	var adjacent: Dictionary = rows[rows.size()-2] if end else rows[1]
	var edges: Array = endpoint.row_edges
	var width: float = endpoint.lane_extents.x + endpoint.lane_extents.y
	# A lane already authored down to zero has its own taper.
	if width <= 0.05:
		return {}
	for region: Vector2 in exclusions.get(path_id, []):
		if endpoint.distance >= region.x-EPS and endpoint.distance <= region.y+EPS:
			return {}
	var away := _xz(endpoint.position-adjacent.position).normalized()
	var right := _xz(vertices[edges[3]]-vertices[edges[2]]).normalized()
	var best: Dictionary = {}
	var best_gap := INF
	var alignment := cos(deg_to_rad(_road.lateral_join_max_angle_degrees))
	for host_id in range(paths.size()):
		if host_id == path_id or not _same_join_channel(host_id, path_id, groups, layers):
			continue
		var host: Array = paths[host_id]
		for i in range(host.size()-1):
			var h0: Dictionary = host[i]
			var h1: Dictionary = host[i+1]
			for side in [-1, 1]:
				var inner := 2 if side < 0 else 3
				var point: Vector3 = vertices[edges[inner]]
				for host_side in [-1, 1]:
					var host_edge := 2 if host_side < 0 else 3
					var a: Vector3 = vertices[h0.row_edges[host_edge]]
					var b: Vector3 = vertices[h1.row_edges[host_edge]]
					var delta := _xz(b-a)
					if delta.length_squared() < EPS:
						continue
					var direction := delta.normalized()
					if absf(away.dot(direction)) < alignment:
						continue
					var host_right := _xz(vertices[h0.row_edges[3]]-vertices[h0.row_edges[2]]).normalized()
					if (right*side).dot(host_right*host_side) > -alignment:
						continue
					var t := (_xz(point-a)).dot(delta)/delta.length_squared()
					if t < -EPS or t > 1.0+EPS:
						continue
					t = clampf(t, 0.0, 1.0)
					var foot := a.lerp(b,t)
					var separation := _xz(point-foot).dot(host_right*host_side)
					var pair := Vector2i(mini(path_id,host_id),maxi(path_id,host_id))
					var allowed_overlap: float = maxf(_road.lateral_join_max_overlap,width-EPS) if _merge_pairs.has(pair) else _road.lateral_join_max_overlap
					if separation < -allowed_overlap or separation > _road.lateral_join_max_gap:
						continue
					if absf(point.y-foot.y) > _road.lateral_join_height_tolerance or absf(separation) >= best_gap:
						continue
					var offset := lerpf(h0.distance,h1.distance,t)
					var sign_ := 1.0 if away.dot(direction) > 0.0 else -1.0
					var available: float = host.back().distance-offset if sign_ > 0 else offset-host.front().distance
					# Retain the host's final cross section outside the new taper.
					var length := minf(requested, maxf(0.0,available-0.5))
					for region: Vector2 in exclusions.get(host_id, []):
						if offset >= region.x and offset <= region.y:
							length = 0.0
						elif sign_ > 0 and region.x > offset:
							length = minf(length,maxf(0.0,region.x-offset-0.5))
						elif sign_ < 0 and region.y < offset:
							length = minf(length,maxf(0.0,offset-region.y-0.5))
					if length < 0.5:
						continue
					best_gap = absf(separation)
					best = {"path": path_id, "end": end, "host": host_id, "side": side,
						"host_side": host_side, "offset": offset, "sign": sign_, "length": length,
						"requested": requested, "endpoint": endpoint, "foot": foot,
						"host_rows": host.duplicate(), "host_right": host_right, "away": away, "host_direction": direction}
	return best

func _host_section(plan: Dictionary, distance: float, vertices: PackedVector3Array) -> Dictionary:
	var rows: Array = plan.host_rows
	for i in range(rows.size()-1):
		if distance <= rows[i+1].distance+EPS:
			var a: Dictionary = rows[i]
			var b: Dictionary = rows[i+1]
			var t := clampf((distance-float(a.distance))/maxf(EPS,b.distance-a.distance),0,1)
			var points := PackedVector3Array()
			for edge in range(6):
				points.append(vertices[a.row_edges[edge]].lerp(vertices[b.row_edges[edge]],t))
			return {"points": points, "row": a, "next": b, "weight": t}
	return {}

func _blend(t: float) -> float:
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return 1.0
	if _road.lateral_join_transition_profile != null:
		return clampf(_road.lateral_join_transition_profile.sample(t),0,1)
	return t*t*(3.0-2.0*t)

func _extend(plan: Dictionary, vertices: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, lane: PackedInt32Array, shoulder: PackedInt32Array,
		sidewalk: PackedInt32Array, paths: Array) -> void:
	var endpoint: Dictionary = plan.endpoint
	var original: Array = endpoint.row_edges
	var side: int = plan.side
	var inner := 2 if side < 0 else 3
	var outer := 3 if side < 0 else 2
	var shoulder_edge := 4 if side < 0 else 1
	var sidewalk_edge := 5 if side < 0 else 0
	var host_inner := 2 if plan.host_side < 0 else 3
	var host_shoulder := 1 if plan.host_side < 0 else 4
	var host_sidewalk := 0 if plan.host_side < 0 else 5
	var width: float = endpoint.lane_extents.x+endpoint.lane_extents.y
	var endpoint_right := _xz(vertices[original[3]]-vertices[original[2]]).normalized()
	var outward := endpoint_right * -side
	var gap_offset: Vector3 = vertices[original[inner]]-Vector3(plan.foot)
	var gap_width := _xz(gap_offset).dot(outward)
	var lane_rise: float = vertices[original[outer]].y-vertices[original[inner]].y
	var shoulder_width := _xz(vertices[original[shoulder_edge]]-vertices[original[outer]]).length()
	var sidewalk_width := _xz(vertices[original[sidewalk_edge]]-vertices[original[shoulder_edge]]).length()
	var shoulder_rise: float = vertices[original[shoulder_edge]].y-vertices[original[outer]].y
	var sidewalk_rise: float = vertices[original[sidewalk_edge]].y-vertices[original[outer]].y
	var steps := maxi(int(_road.lateral_join_transition_subdivisions),ceili(plan.length/maxf(0.1,_road.sample_step)))
	var attach_out := Vector3(plan.host_right.x,0,plan.host_right.y)*float(plan.host_side)
	var attach_inner: Vector3 = plan.foot+attach_out*gap_width+Vector3.UP*gap_offset.y
	var attach_outer := attach_inner+attach_out*width+Vector3.UP*lane_rise
	var corrections := {
		inner: vertices[original[inner]]-attach_inner,
		outer: vertices[original[outer]]-attach_outer,
		shoulder_edge: vertices[original[shoulder_edge]]-(attach_outer+attach_out*shoulder_width+Vector3.UP*shoulder_rise),
		sidewalk_edge: vertices[original[sidewalk_edge]]-(attach_outer+attach_out*(shoulder_width+sidewalk_width)+Vector3.UP*sidewalk_rise)}
	var tangent2: Vector2 = (plan.host_direction*plan.sign-plan.away)*plan.length
	var tangent := Vector3(tangent2.x,0,tangent2.y)
	var generated: Array = []
	for step in range(steps):
		# tip -> authored endpoint for starts; authored endpoint -> tip for ends.
		var u := float(step)/steps if not plan.end else float(step+1)/steps
		var fraction := u if not plan.end else 1.0-u
		var blend := _blend(fraction)
		var distance: float = plan.offset+plan.sign*plan.length*(1.0-fraction)
		var host := _host_section(plan,distance,vertices)
		var hp: PackedVector3Array = host.points
		var host_out2 := _xz(hp[3]-hp[2]).normalized()*float(plan.host_side)
		var host_out := Vector3(host_out2.x,0,host_out2.y)
		var road_inner: Vector3 = hp[host_inner]+host_out*gap_width*blend+Vector3.UP*gap_offset.y*blend
		var road_outer := road_inner+host_out*width*blend+Vector3.UP*lane_rise*blend
		var host_shoulder_width := _xz(hp[host_shoulder]-hp[host_inner]).length()
		var host_sidewalk_width := _xz(hp[host_sidewalk]-hp[host_shoulder]).length()
		var s_width := lerpf(host_shoulder_width,shoulder_width,blend)
		var w_width := lerpf(host_sidewalk_width,sidewalk_width,blend)
		var raised_shoulder := lerpf(hp[host_shoulder].y-hp[host_inner].y,shoulder_rise,blend)
		var raised_sidewalk := lerpf(hp[host_sidewalk].y-hp[host_inner].y,sidewalk_rise,blend)
		var p_shoulder := road_outer+host_out*s_width+Vector3.UP*raised_shoulder
		var p_sidewalk := road_outer+host_out*(s_width+w_width)+Vector3.UP*raised_sidewalk
		var points := [road_inner,road_inner,road_inner,road_outer,p_shoulder,p_sidewalk] if side < 0 else [p_sidewalk,p_shoulder,road_outer,road_inner,road_inner,road_inner]
		var tangent_shift := tangent*fraction*fraction*(fraction-1.0)
		for edge in [inner,outer,shoulder_edge,sidewalk_edge]:
			points[edge] += corrections[edge]*blend+tangent_shift
		for edge in ([0,1] if side < 0 else [4,5]):
			points[edge] = points[inner]
		road_inner = points[inner]
		var row: Dictionary = endpoint.duplicate(true)
		row.row_edges = []
		row.lane_extents = endpoint.lane_extents*blend
		row.distance = endpoint.distance+(1.0 if plan.end else -1.0)*plan.length*(1.0-fraction)
		row.position = road_inner+host_out*(endpoint.lane_extents.x if side < 0 else endpoint.lane_extents.y)*blend
		row.out_dir = Vector3(host_out.z,0,-host_out.x)*float(-side)
		row.width = width*blend+s_width+w_width
		row.outer_wall_height = lerpf(lerpf(host.row.outer_wall_height,host.next.outer_wall_height,host.weight),endpoint.outer_wall_height,blend)
		row.lateral_transition = true
		row.erase("lateral_left")
		row.erase("lateral_right")
		var exterior_key := "terrain_right_width" if side < 0 else "terrain_left_width"
		var host_key := "terrain_left_width" if plan.host_side < 0 else "terrain_right_width"
		row[exterior_key] = lerpf(lerpf(host.row[host_key],host.next[host_key],host.weight),endpoint[exterior_key],blend)
		row["terrain_left_width" if side < 0 else "terrain_right_width"] = 0.0
		for edge in range(6):
			row.row_edges.append(vertices.size())
			vertices.append(points[edge])
			normals.append(Vector3.UP)
			uvs.append(Vector2(uvs[original[edge]].x,row.distance*_road.uv_length_scale))
		row.row_a = row.row_edges[0]
		row.row_b = row.row_edges[5]
		generated.append(row)
	# Keep the exact original cross section at the attachment, avoiding a seam
	# from resampling its position, bank or material coordinates.
	var strip: Array = generated+[endpoint] if not plan.end else [endpoint]+generated
	for i in range(strip.size()-1):
		var a: Array = strip[i].row_edges
		var b: Array = strip[i+1].row_edges
		_quad(vertices,lane,a[2],a[3],b[2],b[3])
		_quad(vertices,shoulder,a[1 if side > 0 else 3],a[2 if side > 0 else 4],b[1 if side > 0 else 3],b[2 if side > 0 else 4])
		_quad(vertices,sidewalk,a[0 if side > 0 else 4],a[1 if side > 0 else 5],b[0 if side > 0 else 4],b[1 if side > 0 else 5])
	var rows: Array = paths[plan.path]
	paths[plan.path] = rows+generated if plan.end else generated+rows
	reports.append({"path":plan.path,"end":plan.end,"host":plan.host,"length":plan.length,
		"requested":plan.requested,"limited":plan.length < plan.requested-EPS,"rows":steps})

func _quad(vertices: PackedVector3Array, indices: PackedInt32Array, a: int, b: int, c: int, d: int) -> void:
	for triangle in [[a,b,c],[c,b,d]]:
		var cross_: Vector3 = (vertices[triangle[1]]-vertices[triangle[0]]).cross(vertices[triangle[2]]-vertices[triangle[0]])
		if cross_.length_squared() < EPS*EPS:
			continue
		if (cross_.y > 0.0) == bool(_road.invert_faces):
			indices.append_array([triangle[0],triangle[2],triangle[1]])
		else:
			indices.append_array(triangle)

func _xz(point: Vector3) -> Vector2:
	return Vector2(point.x,point.z)
