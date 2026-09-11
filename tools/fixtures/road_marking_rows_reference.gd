extends "../../addons/scripts/spline_road/road_marking_builder.gd"
## Frozen native row-pair construction, independent of cached block replay.

func _build_rows(vertices: PackedVector3Array, rows: Array, exclusions: Array) -> void:
	for i in range(rows.size() - 1):
		var row0: Dictionary = rows[i]
		var row1: Dictionary = rows[i + 1]
		if not row0.has("marking_layout") or not row1.has("marking_layout"):
			continue
		var s0 := float(row0["distance"])
		var s1 := float(row1["distance"])
		if s1 - s0 < 0.00001:
			continue
		var ext0: Vector2 = row0["lane_extents"]
		var ext1: Vector2 = row1["lane_extents"]
		var e0: Array = row0["row_edges"]
		var e1: Array = row1["row_edges"]
		var domain := PackedVector2Array([Vector2(s0, -ext0.x), Vector2(s0, ext0.y), Vector2(s1, -ext1.x), Vector2(s1, ext1.y)])
		var points := PackedVector3Array([vertices[e0[2]], vertices[e0[3]], vertices[e1[2]], vertices[e1[3]]])
		var context := {"domain": domain, "points": points, "exclusions": exclusions}
		var layout0: Dictionary = row0["marking_layout"]
		var layout1: Dictionary = row1["marking_layout"]
		# A one-way profile has no opposing center divider.
		if minf(ext0.x + ext1.x, ext0.y + ext1.y) > 0.001:
			_line(context, Vector2(s0, 0), Vector2(s1, 0), int(_settings["center_style"]), 0)
		for side in [-1, 1]:
			var extent0 := ext0.x if side < 0 else ext0.y
			var extent1 := ext1.x if side < 0 else ext1.y
			if maxf(extent0, extent1) <= 0.001:
				continue
			var inset := maxf(float(_settings["edge_inset"]), float(_settings["line_width"]) * 0.5)
			_line(context, Vector2(s0, side * maxf(0.0, extent0 - inset)), Vector2(s1, side * maxf(0.0, extent1 - inset)), int(_settings["edge_style"]), 1)
			if not bool(layout0.get("enabled", false)):
				continue
			var width0 := maxf(0.01, float(layout0.get("lane_width", 3.5)))
			var width1 := maxf(0.01, float(layout1.get("lane_width", width0)))
			var lanes := ceili(maxf(extent0 / width0, extent1 / width1))
			for lane in range(1, lanes):
				# Clip separators to the painted interior, away from the edge stripe.
				var interior := _side_polygon(s0, s1, side, 0.0, 0.0, maxf(0.0, extent0 - inset * 2.0), maxf(0.0, extent1 - inset * 2.0))
				_line(context, Vector2(s0, side * lane * width0), Vector2(s1, side * lane * width1), int(_settings["lane_style"]), 1, interior)
			if bool(_settings["hatching_enabled"]):
				_hatching(context, s0, s1, side, extent0, extent1, width0, width1, layout0, layout1, inset)
