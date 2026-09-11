@tool
extends RefCounted
## Reconcile native mesh output after placement. Scene/custom callbacks bypass
## this path; no scene-script lifecycle is suppressed by source caching.

const TRANSFORM_PROPERTIES := ["transform", "position", "rotation", "rotation_degrees",
	"quaternion", "basis", "scale", "global_transform", "global_position",
	"global_rotation", "global_rotation_degrees", "global_basis"]
const NATIVE_MESH_PROPERTIES := ["unique_name_in_owner", "process_mode", "process_priority",
	"process_physics_priority", "process_thread_group", "physics_interpolation_mode",
	"auto_translate_mode", "editor_description", "transform", "rotation_edit_mode", "rotation_order",
	"top_level", "visible", "visibility_parent", "layers", "sorting_offset", "sorting_use_aabb_center",
	"material_override", "material_overlay", "transparency", "cast_shadow", "extra_cull_margin",
	"custom_aabb", "lod_bias", "ignore_occlusion_culling", "gi_mode", "gi_lightmap_texel_scale",
	"visibility_range_begin", "visibility_range_begin_margin", "visibility_range_end",
	"visibility_range_end_margin", "visibility_range_fade_mode", "mesh", "skin", "skeleton",
	"surface_material_override/0", "script", "metadata/spline_prop_array_owner_path"]

var enabled := false
var stats: Dictionary = {}
var _entries: Dictionary = {}
var _specs: Array = []
var _root: Node3D
var _owner_path := ""
var _props: Node3D
var _scene_owner: Node
var _owner_meta: StringName
var _build_property_names: Dictionary = {}
var _build_transform_indices: Dictionary = {}
var _build_fast_state: Dictionary = {}
var _build_schemas: Dictionary = {}
var _live_schemas: Dictionary = {}
var _root_properties: Array = []
var _root_state: Array = []
var _schema_records: Dictionary = {}
var _schema_revision := 0


func clear() -> void:
	_entries.clear()
	_specs.clear()
	_build_property_names.clear()
	_build_transform_indices.clear()
	_build_fast_state.clear()
	_build_schemas.clear()
	_live_schemas.clear()
	_root_properties.clear()
	_root_state.clear()
	_schema_records.clear()
	_root = null
	_owner_path = ""
	_scene_owner = null
	enabled = false
	stats = {}


func discard_output() -> void:
	# Parent output metadata contains the old generator path after a rename or
	# reparent. Retained identities let us clean up precisely those old nodes.
	if is_instance_valid(_root) and is_instance_valid(_props):
		for entry: Dictionary in _entries.values():
			var node: Node = entry.node.get_ref()
			if node != null and node.get_parent() == _root \
					and str(node.get_meta(_props.GENERATED_OWNER_META, "")) == _owner_path:
				node.free()
	clear()


func begin_build(props: Node3D, reuse: bool) -> Node3D:
	var current_root: Node3D = props.get_parent() if props.use_parent_as_generated_root and props.get_parent() is Node3D \
		else props if props.use_parent_as_generated_root else props.get_node_or_null(props.GENERATED_ROOT_NAME)
	if not reuse or not is_instance_valid(_root) or _root != current_root or _owner_path != str(props.get_path()):
		props._clear_all_generated_nodes()
		clear()
	elif not props.use_parent_as_generated_root:
		if not _matches_node_state(_root, _root_properties, _root_state):
			props._clear_all_generated_nodes()
		else:
			for child in _root.get_children():
				if not props._is_generated_node_for_this_array(child):
					# The normal rebuild owns the entire generated container. Unexpected
					# children must not outlive it merely because source reuse is enabled.
					props._clear_all_generated_nodes()
					break
	_props = props
	_owner_meta = props.GENERATED_OWNER_META
	enabled = reuse
	_root = props._get_generation_parent_root()
	_owner_path = str(props.get_path())
	_scene_owner = null
	if Engine.is_editor_hint() and props.persist_generated_in_scene:
		var edited_root: Node = props.get_tree().edited_scene_root
		if edited_root != null and (edited_root == _root or edited_root.is_ancestor_of(_root)):
			_scene_owner = edited_root
	_specs.clear()
	_build_property_names.clear()
	_build_transform_indices.clear()
	_build_fast_state.clear()
	_build_schemas.clear()
	_live_schemas.clear()
	stats = {"output_reuse_enabled": enabled, "output_nodes_reused": 0,
		"output_nodes_updated": 0, "output_nodes_created": 0, "output_nodes_removed": 0,
		"output_buffers_reused": 0, "output_buffers_rebuilt": 0,
		"output_validate_ms": 0.0, "output_commit_ms": 0.0}
	if enabled and not props.use_parent_as_generated_root:
		if _root.transform != Transform3D.IDENTITY:
			_root.transform = Transform3D.IDENTITY
		if _root.owner != _scene_owner:
			_root.owner = _scene_owner
	return _root


func record_mesh(path: Path3D, index: int, transform_value: Transform3D) -> void:
	_specs.append({"key": "%s/node/%s" % [path.get_instance_id(), index],
		"name": "Prop_%s_%06d" % [path.name, index], "transform": transform_value, "batch": false})


func record_batch(path: Path3D, cell: Vector3i, transforms: Array, mesh_bounds: AABB) -> void:
	_specs.append({"key": "%s/batch/%s" % [path.get_instance_id(), cell],
		"name": "Props_%s_%d_%d_%d" % [path.name, cell.x, cell.y, cell.z], "batch": true,
		"transforms": transforms, "mesh_bounds": mesh_bounds})


func finish_build() -> void:
	if not enabled:
		return
	var validation_start := Time.get_ticks_usec()
	var retained: Dictionary = {}
	for spec: Dictionary in _specs:
		var old: Dictionary = _entries.get(spec.key, {})
		var node: Node = old.node.get_ref() if not old.is_empty() else null
		if node != null and node.get_parent() == _root and old.name == spec.name \
				and node.name == old.get("actual_name", &"") and node.scene_file_path.is_empty() \
				and not node.is_queued_for_deletion() \
				and node.get_script() == null and node.get_child_count() == 0 \
				and old.get("schema", -1) == _live_schema(node) \
				and _matches_node_state(node, old.properties, old.state, old.get("fast_state", false)):
			retained[node.get_instance_id()] = true
			spec["old"] = old
	# Delete obsolete nodes before creating replacements, so their names cannot
	# force Godot to auto-rename a new output node (e.g. a path replacement).
	for child in _root.get_children():
		if not retained.has(child.get_instance_id()) and _owns(child):
			child.free()
			stats.output_nodes_removed += 1
	stats.output_validate_ms = (Time.get_ticks_usec() - validation_start) / 1000.0
	var commit_start := Time.get_ticks_usec()
	var next: Dictionary = {}
	for spec: Dictionary in _specs:
		var old: Dictionary = spec.get("old", {})
		var node: Node3D = old.node.get_ref() if not old.is_empty() else null
		var created := node == null
		if created:
			node = MultiMeshInstance3D.new() if spec.batch else MeshInstance3D.new()
			node.name = spec.name
			node.set_meta(_props.GENERATED_OWNER_META, _owner_path)
			_root.add_child(node)
			retained[node.get_instance_id()] = true
			stats.output_nodes_created += 1
		var updated := created
		var transform_only: bool = not created and not spec.batch
		if spec.batch:
			var multimesh: MultiMesh = node.multimesh
			if not created and old.transforms == spec.transforms and old.mesh_bounds == spec.mesh_bounds \
					and multimesh.mesh == _props.item_mesh and _multimesh_state(multimesh) == old.buffer_state:
				stats.output_buffers_reused += 1
			else:
				multimesh = _build_multimesh(spec)
				node.multimesh = multimesh
				stats.output_buffers_rebuilt += 1
				updated = true
		else:
			if node.transform != spec.transform:
				node.transform = spec.transform
				updated = true
			if node.mesh != _props.item_mesh:
				node.mesh = _props.item_mesh
				updated = true
				transform_only = false
		if node.material_override != _props.item_material_override or node.cast_shadow != _props.mesh_cast_shadows:
			node.material_override = _props.item_material_override
			node.cast_shadow = _props.mesh_cast_shadows
			updated = true
			transform_only = false
		if node.owner != _scene_owner:
			node.owner = _scene_owner
			updated = true
			transform_only = false
		if not created:
			stats.output_nodes_updated += int(updated)
			stats.output_nodes_reused += int(not updated)
			if not updated:
				next[spec.key] = old
				continue
			if transform_only and old.has("transform_indices"):
				# All old state was validated immediately before this update. Native
				# transform setters do not change materials, ownership or metadata;
				# only resample their stored transform/derived-coordinate properties.
				var entry: Dictionary = old.duplicate()
				entry.state = old.state.duplicate(true)
				for index: int in old.transform_indices:
					entry.state[index + 2] = node.get(old.properties[index])
				next[spec.key] = entry
				continue
		var properties: Array = _property_names(node) if created or updated else old.properties
		var fast_state: bool = _build_fast_state[node.get_class()]
		var entry := {"node": weakref(node), "name": spec.name, "actual_name": node.name, "properties": properties,
			"schema": _build_schemas[node.get_class()] if created or updated else old.schema,
			"transform_indices": _build_transform_indices[node.get_class()],
			"fast_state": fast_state,
			"state": _node_state(node, properties, fast_state).duplicate(true) if created or updated else old.state}
		if spec.batch:
			entry["transforms"] = spec.transforms.duplicate()
			entry["mesh_bounds"] = spec.mesh_bounds
			entry["buffer_state"] = _multimesh_state(node.multimesh) if created or updated else old.buffer_state
		next[spec.key] = entry
	# Full generation appends owned nodes after unrelated children. Preserve that
	# order without detaching/re-entering retained native nodes.
	var first_index := 0
	for child in _root.get_children():
		if not retained.has(child.get_instance_id()):
			if child.get_index() != first_index:
				_root.move_child(child, first_index)
			first_index += 1
	for i in range(_specs.size()):
		var node: Node = next[_specs[i].key].node.get_ref()
		if node.get_index() != first_index + i:
			_root.move_child(node, first_index + i)
	_entries = next
	_specs.clear()
	if not _props.use_parent_as_generated_root:
		_root_properties = _property_names(_root)
		_root_state = _node_state(_root, _root_properties).duplicate(true)
	stats.output_commit_ms = (Time.get_ticks_usec() - commit_start) / 1000.0


func _owns(node: Node) -> bool:
	return node.get_meta(_owner_meta, "") == _owner_path


func _build_multimesh(spec: Dictionary) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _props.item_mesh
	multimesh.instance_count = spec.transforms.size()
	var bounds := AABB()
	for index in range(spec.transforms.size()):
		var transform_value: Transform3D = spec.transforms[index]
		multimesh.set_instance_transform(index, transform_value)
		var instance_bounds: AABB = transform_value * spec.mesh_bounds
		bounds = instance_bounds if index == 0 else bounds.merge(instance_bounds)
	multimesh.custom_aabb = bounds
	return multimesh


func _property_names(node: Node) -> Array:
	var kind := node.get_class()
	if _build_property_names.has(kind):
		return _build_property_names[kind]
	var names: Array = []
	for property: Dictionary in node.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_STORAGE:
			names.append(property.name)
	_build_property_names[kind] = names
	# Exact schema gate: extra surfaces, shader properties or engine additions
	# retain the generic reflection path and all of its validation.
	_build_fast_state[kind] = kind == "MeshInstance3D" and PackedStringArray(names) == PackedStringArray(NATIVE_MESH_PROPERTIES)
	var indices: Array[int] = []
	for i in range(names.size()):
		if str(names[i]) in TRANSFORM_PROPERTIES:
			indices.append(i)
	_build_transform_indices[kind] = indices
	_build_schemas[kind] = _intern_schema(kind, _schema(names))
	return names


func _schema(names: Array) -> Array:
	var result: Array = []
	for name in names:
		if not str(name).begins_with("metadata/"):
			result.append(name)
	return result


func _live_schema(node: Node) -> int:
	# Shader edits can add/remove per-instance properties without replacing the
	# shared material resource. Validate their schema once per native output type.
	var kind := node.get_class()
	if not _live_schemas.has(kind):
		var names: Array = []
		for property: Dictionary in node.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE:
				names.append(property.name)
		_live_schemas[kind] = _intern_schema(kind, _schema(names))
	return _live_schemas[kind]


func _intern_schema(kind: String, names: Array) -> int:
	var previous: Dictionary = _schema_records.get(kind, {})
	if previous.is_empty() or previous.names != names:
		_schema_revision += 1
		_schema_records[kind] = {"names": names, "revision": _schema_revision}
	return _schema_records[kind].revision


func _node_state(node: Node, properties: Array, fast_state := false) -> Array:
	# Unexpected manual changes to generated native output must not survive a
	# rebuild. Cache property names, but inspect values and added metadata live.
	if fast_state:
		return _native_mesh_state(node as MeshInstance3D)
	var state: Array = [node.get_meta_list(), node.owner]
	for property in properties:
		state.append(node.get(property))
	return state


func _matches_node_state(node: Node, properties: Array, expected: Array, fast_state := false) -> bool:
	# Validate in place instead of allocating a second snapshot for comparison.
	# Check metadata names first: a removed key must not be queried through an
	# old metadata/property name, which would log an engine error.
	if expected.size() != properties.size() + 2 or node.get_meta_list() != expected[0] or node.owner != expected[1]:
		return false
	if fast_state:
		return _native_mesh_state(node as MeshInstance3D) == expected
	for i in range(properties.size()):
		if node.get(properties[i]) != expected[i + 2]:
			return false
	return true


func _native_mesh_state(node: MeshInstance3D) -> Array:
	# Same fields/order as generic storage reflection, using typed native getters
	# for the common schema. No property or manual-state check is omitted.
	return [node.get_meta_list(), node.owner,
		node.unique_name_in_owner, node.process_mode, node.process_priority,
		node.process_physics_priority, node.process_thread_group, node.physics_interpolation_mode,
		node.auto_translate_mode, node.editor_description, node.transform, node.rotation_edit_mode,
		node.rotation_order, node.top_level, node.visible, node.visibility_parent, node.layers,
		node.sorting_offset, node.sorting_use_aabb_center, node.material_override, node.material_overlay,
		node.transparency, node.cast_shadow, node.extra_cull_margin, node.custom_aabb, node.lod_bias,
		node.ignore_occlusion_culling, node.gi_mode, node.gi_lightmap_texel_scale,
		node.visibility_range_begin, node.visibility_range_begin_margin, node.visibility_range_end,
		node.visibility_range_end_margin, node.visibility_range_fade_mode, node.mesh, node.skin,
		node.skeleton, node.get_surface_override_material(0) if node.get_surface_override_material_count() > 0 else null,
		node.get_script(), node.get_meta(_owner_meta, "")]


func _multimesh_state(multimesh: MultiMesh) -> Array:
	return [multimesh.mesh, multimesh.transform_format, multimesh.use_colors,
		multimesh.use_custom_data, multimesh.instance_count, multimesh.visible_instance_count,
		multimesh.custom_aabb, multimesh.buffer]
