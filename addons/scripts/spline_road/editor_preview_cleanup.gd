@tool
extends RefCounted
## Saved editor proxies must leave the runtime tree before generators inspect it.
## Keep their parent nodes and authored data, which still drive generation.
static func remove_runtime_children(parent: Node, names: Array[String]) -> void:
	if Engine.is_editor_hint():
		return
	for name in names:
		var child := parent.get_node_or_null(NodePath(name))
		if child == null:
			continue
		if child is Node3D:
			child.hide()
		parent.remove_child(child)
		child.queue_free()
