@tool
extends Node3D
## CPU-side placements remain serializable even with Godot's headless renderer.
@export var tree_mesh: Mesh
## XYZ is the trunk base; W is uniform scale. Positions match the authored terrain.
@export var tree_placements := PackedVector4Array()
@export_range(20.0, 250.0, 5.0) var chunk_size := 120.0
@export_tool_button("Rebuild Forest Batches") var rebuild_action := rebuild

func _ready() -> void:
	rebuild()

func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if tree_mesh == null:
		return
	var cells: Dictionary = {}
	for placement in tree_placements:
		var key := Vector2i(floori(placement.x / chunk_size), floori(placement.z / chunk_size))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(placement)
	for key in cells:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = tree_mesh
		multi.instance_count = cells[key].size()
		var bounds := AABB()
		for i in range(multi.instance_count):
			var p: Vector4 = cells[key][i]
			var yaw := fposmod(p.x * 7.13 + p.z * 2.31, TAU)
			var transform_ := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * p.w), Vector3(p.x, p.y, p.z))
			multi.set_instance_transform(i, transform_)
			var tree_bounds := transform_ * tree_mesh.get_aabb()
			bounds = tree_bounds if i == 0 else bounds.merge(tree_bounds)
		multi.custom_aabb = bounds
		var node := MultiMeshInstance3D.new()
		node.name = "Pines_%s_%s" % [key.x, key.y]
		node.multimesh = multi
		add_child(node)
