@tool
extends RefCounted
const PROBE = preload("./fixtures/terrain_startup_probe.gd")
var failures := 0

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1

func run(plugin: EditorPlugin) -> void:
	var tree := plugin.get_tree()
	var terrain := PROBE.new()
	terrain.source_paths.assign([NodePath(".")])
	var saved_output := MeshInstance3D.new()
	saved_output.name = "GeneratedTopologyTerrain"
	saved_output.mesh = PlaneMesh.new()
	terrain.add_child(saved_output)
	# Reproduce the editor's order: resolve the saved selection, enter the tree,
	# then restore selection. Immediate _ready regeneration invalidated this node.
	plugin.add_child(terrain)
	_check(is_instance_valid(saved_output), "Saved terrain survives tree entry until selection restoration")
	if is_instance_valid(saved_output):
		EditorInterface.get_selection().add_node(saved_output)
		_check(EditorInterface.get_selection().get_selected_nodes().has(saved_output), "Restore selected output safely")
	for frame in range(3):
		await tree.process_frame
	_check(terrain.rebuilds == 1, "Terrain still rebuilds once after startup")
	_check(not is_instance_valid(saved_output), "Rebuild retires the old mesh after selection is registered")
	_check(EditorInterface.get_selection().get_selected_nodes().is_empty(), "Retiring output clears editor selection safely")
	terrain.free()
	# A scene may leave the tree before the deferred startup callback runs.
	var detached := PROBE.new()
	detached.source_paths.assign([NodePath(".")])
	plugin.add_child(detached)
	plugin.remove_child(detached)
	for frame in range(2):
		await tree.process_frame
	_check(detached.rebuilds == 0, "Detached terrain does not regenerate")
	detached.free()
	print("TERRAIN STARTUP SELECTION ", "OK" if failures == 0 else "FAILED", " failures=", failures)
	tree.quit(0 if failures == 0 else 1)
