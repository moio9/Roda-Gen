@tool
extends RefCounted
## One indexed surface. Retain completed cell arrays, not mutable scene nodes.
const MAX_VERTICES := 131072
const MAX_TRIANGLES := 131072
const MAX_CELLS := 4096
const MAX_BYTES := 16 * 1024 * 1024
var stats: Dictionary = {}
var _indices := PackedInt32Array()
var _words: Array = []
var _triangle_cells: Array[Vector3i] = []
var _cells: Dictionary = {}
var _size := 0.0


func clear() -> void:
	_indices = PackedInt32Array()
	_words.clear()
	_triangle_cells.clear()
	_cells.clear()
	_size = 0.0


func partition(source: Array, cell_size: float) -> Dictionary:
	stats = {"cells_reused": 0, "cells_rebuilt": 0, "centroids_rebuilt": 0,
		"triangles_checked": 0, "payload_bound": 0, "fallback": ""}
	if source.size() != Mesh.ARRAY_MAX or not source[Mesh.ARRAY_VERTEX] is PackedVector3Array \
			or not source[Mesh.ARRAY_NORMAL] is PackedVector3Array or not source[Mesh.ARRAY_TEX_UV] is PackedVector2Array \
			or not source[Mesh.ARRAY_INDEX] is PackedInt32Array:
		return _bypass("format")
	var vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = source[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = source[Mesh.ARRAY_INDEX]
	var count := vertices.size()
	var triangles := indices.size() / 3
	# Conservative retained payload bound: input words, indices, triangle-cell
	# records and up to three distinct output vertices per triangle. Cell slots
	# add 512 bytes below. This is not a process/allocator peak-memory metric.
	var base_bound := count * 32 + triangles * 160 + (indices.size() % 3) * 4
	if count > MAX_VERTICES or triangles > MAX_TRIANGLES or base_bound > MAX_BYTES:
		return _bypass("capacity")
	if normals.size() != count or uvs.size() != count or not is_finite(cell_size) or cell_size <= 0:
		return _bypass("format")
	var words: Array = [vertices.to_byte_array().to_int32_array(), normals.to_byte_array().to_int32_array(),
		uvs.to_byte_array().to_int32_array()]
	if words[0].size() != count * 3 or words[1].size() != count * 3 or words[2].size() != count * 2:
		return _bypass("precision")
	var cold: bool = _size != cell_size or _indices != indices or _words.is_empty() or _words[0].size() != count * 3
	var dirty: Dictionary = {}
	if cold:
		for vertex in range(count):
			if not vertices[vertex].is_finite() or not normals[vertex].is_finite() or not uvs[vertex].is_finite():
				return _bypass("nonfinite")
		_triangle_cells.resize(triangles)
		for triangle in range(triangles):
			var base := triangle * 3
			var a := indices[base]
			var b := indices[base + 1]
			var c := indices[base + 2]
			if mini(a, mini(b, c)) < 0 or maxi(a, maxi(b, c)) >= count:
				return _bypass("indices")
			var center := (vertices[a] + vertices[b] + vertices[c]) / 3.0
			if not center.is_finite():
				return _bypass("nonfinite")
			var cell := _cell(center, cell_size)
			_triangle_cells[triangle] = cell
			dirty[cell] = true
		stats.centroids_rebuilt = triangles
	else:
		var changed := PackedByteArray()
		changed.resize(count)
		changed.fill(0)
		for start in range(0, count, 256):
			var end := mini(count, start + 256)
			if words[0].slice(start * 3, end * 3) == _words[0].slice(start * 3, end * 3) \
					and words[1].slice(start * 3, end * 3) == _words[1].slice(start * 3, end * 3) \
					and words[2].slice(start * 2, end * 2) == _words[2].slice(start * 2, end * 2):
				continue
			for vertex in range(start, end):
				if _different(words[0], _words[0], vertex, 3):
					changed[vertex] = 3
				elif _different(words[1], _words[1], vertex, 3) or _different(words[2], _words[2], vertex, 2):
					changed[vertex] = 1
				if changed[vertex] and (not vertices[vertex].is_finite() or not normals[vertex].is_finite() or not uvs[vertex].is_finite()):
					return _bypass("nonfinite")
		for triangle in range(triangles):
			var base := triangle * 3
			var a := indices[base]
			var b := indices[base + 1]
			var c := indices[base + 2]
			var flags := changed[a] | changed[b] | changed[c]
			if flags == 0:
				continue
			dirty[_triangle_cells[triangle]] = true
			if flags & 2:
				var center := (vertices[a] + vertices[b] + vertices[c]) / 3.0
				if not center.is_finite():
					return _bypass("nonfinite")
				_triangle_cells[triangle] = _cell(center, cell_size)
				dirty[_triangle_cells[triangle]] = true
				stats.centroids_rebuilt += 1
	stats.triangles_checked = triangles
	var result: Dictionary = {}
	var cell_triangles: Dictionary = {}
	# Preserve original cell insertion and triangle order, even when the first
	# triangle of a cell moves away or an old cell disappears completely.
	for triangle in range(triangles):
		var cell := _triangle_cells[triangle]
		if not result.has(cell):
			result[cell] = [] if dirty.has(cell) else _cells[cell]
			if result.size() > MAX_CELLS or base_bound + result.size() * 512 > MAX_BYTES:
				return _bypass("capacity")
		if dirty.has(cell):
			if not cell_triangles.has(cell):
				cell_triangles[cell] = PackedInt32Array()
			cell_triangles[cell].append(triangle)
	for cell: Vector3i in result:
		if dirty.has(cell):
			result[cell] = _build_cell(vertices, normals, uvs, indices, cell_triangles[cell])
			stats.cells_rebuilt += 1
		else:
			stats.cells_reused += 1
	_indices = indices.duplicate()
	_words = words
	_size = cell_size
	_cells = result
	stats.payload_bound = base_bound + result.size() * 512
	# Public partition results have the same independent lifetime as native output.
	return {"cells": result.duplicate(true)}


func _build_cell(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
		indices: PackedInt32Array, triangles: PackedInt32Array) -> Array:
	var remap: Dictionary = {}
	var out_vertices := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var out_uvs := PackedVector2Array()
	var out_indices := PackedInt32Array()
	for triangle in triangles:
		for corner in range(3):
			var index := indices[triangle * 3 + corner]
			if not remap.has(index):
				remap[index] = out_vertices.size()
				out_vertices.append(vertices[index])
				out_normals.append(normals[index])
				out_uvs.append(uvs[index])
			out_indices.append(remap[index])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_vertices
	arrays[Mesh.ARRAY_NORMAL] = out_normals
	arrays[Mesh.ARRAY_TEX_UV] = out_uvs
	arrays[Mesh.ARRAY_INDEX] = out_indices
	return arrays


func _different(a: PackedInt32Array, b: PackedInt32Array, vertex: int, stride: int) -> bool:
	for component in range(stride):
		if a[vertex * stride + component] != b[vertex * stride + component]:
			return true
	return false


func _cell(center: Vector3, size: float) -> Vector3i:
	return Vector3i(floori(center.x / size), floori(center.y / size), floori(center.z / size))


func _bypass(reason: String) -> Dictionary:
	clear()
	stats.fallback = reason
	return {}
