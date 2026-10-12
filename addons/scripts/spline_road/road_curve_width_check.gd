@tool
extends RefCounted
## Local folding of the source asphalt ribbon, before intersection trimming.
## Corner Jacobians are relative to the center advance, so winding settings,
## mirrored paths, bank and asymmetric widths need no special-case sign flips.
const WARNING_RATIO := 0.2
const FOLD_RATIO := 0.001


static func analyze(vertices: PackedVector3Array, path_rows: Array, normals := PackedVector3Array()) -> Dictionary:
	var regions: Array[Dictionary] = []
	var segments: Array[Dictionary] = []
	for path_id in range(path_rows.size()):
		var rows: Array = path_rows[path_id]
		var active := [-1, -1]
		for i in range(rows.size() - 1):
			var row0: Dictionary = rows[i]
			var row1: Dictionary = rows[i + 1]
			var center0: Vector3 = row0.position
			var center1: Vector3 = row1.position
			var advance := center1 - center0
			var left0 := vertices[row0.row_edges[2]]
			var right0 := vertices[row0.row_edges[3]]
			var left1 := vertices[row1.row_edges[2]]
			var right1 := vertices[row1.row_edges[3]]
			var across0 := right0 - left0
			var across1 := right1 - left1
			var normal := advance.cross(across0 + across1)
			if advance.length_squared() < 0.00000001 or normal.length_squared() < 0.00000001:
				active = [-1, -1]
				continue
			normal = normal.normalized()
			var base0 := advance.cross(across0).dot(normal)
			var base1 := advance.cross(across1).dot(normal)
			if base0 <= 0.0000001 or base1 <= 0.0000001:
				active = [-1, -1]
				continue
			for side_index in range(2):
				var edge0 := left0 if side_index == 0 else right0
				var edge1 := left1 if side_index == 0 else right1
				if maxf(edge0.distance_to(center0), edge1.distance_to(center1)) < 0.001:
					active[side_index] = -1
					continue
				var edge_advance := edge1 - edge0
				var ratio := minf(edge_advance.cross(across0).dot(normal) / base0,
					edge_advance.cross(across1).dot(normal) / base1)
				if not is_finite(ratio) or ratio > WARNING_RATIO:
					active[side_index] = -1
					continue
				var folded := ratio <= FOLD_RATIO
				var side := -1 if side_index == 0 else 1
				var region_index: int = active[side_index]
				if region_index < 0:
					region_index = regions.size()
					active[side_index] = region_index
					regions.append({"path_id": path_id, "side": side,
						"start": float(row0.distance), "end": float(row1.distance),
						"folded": folded, "min_ratio": ratio})
				else:
					var region: Dictionary = regions[region_index]
					region.end = float(row1.distance)
					region.folded = region.folded or folded
					region.min_ratio = minf(region.min_ratio, ratio)
				# Keep only problem strips, not a second copy of the entire road.
				segments.append({"path_id": path_id, "side": side, "folded": folded,
					"center0": center0, "center1": center1, "edge0": edge0, "edge1": edge1,
					"up": normals[row0.row_edges[2]] if normals.size() == vertices.size() else normal})
	return {"regions": regions, "segments": segments}
