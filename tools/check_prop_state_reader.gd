extends SceneTree
## Exact typed-reader parity with native property reflection, including mutation.

const CACHE = preload("../addons/scripts/spline_road/prop_output_cache.gd")
const LIFECYCLE = preload("./fixtures/output_lifecycle_prop.gd")
const OWNER_META := &"spline_prop_array_owner_path"
var failed := false
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	if DisplayServer.get_name() != "headless":
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		scene.add_child(environment)
		scene.add_child(DirectionalLight3D.new())
	var skeleton := Skeleton3D.new()
	skeleton.name = "Rig"
	scene.add_child(skeleton)
	var visible_parent := MeshInstance3D.new()
	visible_parent.name = "VisibleParent"
	scene.add_child(visible_parent)
	var cache := CACHE.new()
	cache._owner_meta = OWNER_META
	var changes := {
		"unique_name_in_owner": true, "process_mode": Node.PROCESS_MODE_DISABLED,
		"process_priority": 7, "process_physics_priority": 9,
		"process_thread_group": Node.PROCESS_THREAD_GROUP_MAIN_THREAD,
		"physics_interpolation_mode": Node.PHYSICS_INTERPOLATION_MODE_OFF,
		"auto_translate_mode": Node.AUTO_TRANSLATE_MODE_DISABLED, "editor_description": "changed",
		"transform": Transform3D(Basis(Vector3.UP, 0.3), Vector3(2, 3, 4)),
		"rotation_edit_mode": Node3D.ROTATION_EDIT_MODE_BASIS, "rotation_order": EULER_ORDER_ZYX,
		"top_level": true, "visible": false, "visibility_parent": NodePath("../VisibleParent"),
		"layers": 2, "sorting_offset": 1.5, "sorting_use_aabb_center": false,
		"material_override": StandardMaterial3D.new(), "material_overlay": StandardMaterial3D.new(),
		"transparency": 0.2, "cast_shadow": GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"extra_cull_margin": 2.0, "custom_aabb": AABB(Vector3(-1, -2, -3), Vector3(4, 5, 6)),
		"lod_bias": 2.0, "ignore_occlusion_culling": true, "gi_mode": GeometryInstance3D.GI_MODE_DYNAMIC,
		"gi_lightmap_texel_scale": 2.0, "visibility_range_begin": 5.0, "visibility_range_begin_margin": 1.0,
		"visibility_range_end": 10.0, "visibility_range_end_margin": 2.0,
		"visibility_range_fade_mode": GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF,
		"mesh": BoxMesh.new(), "skin": Skin.new(), "skeleton": NodePath("../Rig"),
		"surface_material_override/0": StandardMaterial3D.new(), "script": LIFECYCLE,
		"metadata/spline_prop_array_owner_path": "changed-owner",
	}
	_check(changes.size() == CACHE.NATIVE_MESH_PROPERTIES.size(), "mutation suite covers every specialized property")
	for property: String in changes:
		var node := _node(scene)
		var properties: Array = cache._property_names(node)
		_check(cache._build_fast_state.MeshInstance3D, "native schema actually selects typed accessors")
		var initial: Array = cache._node_state(node, properties).duplicate(true)
		_check(cache._node_state(node, properties, true) == initial, "typed/generic initial state parity: " + property)
		node.set(property, changes[property])
		var changed: Array = cache._node_state(node, properties)
		_check(changed != initial, "mutation changes actual stored state: " + property)
		_check(cache._node_state(node, properties, true) == changed, "typed/generic changed state parity: " + property)
		_check(not cache._matches_node_state(node, properties, initial, true), "typed validator rejects mutation: " + property)
		node.free()
	var node := _node(scene)
	var properties: Array = cache._property_names(node)
	var initial: Array = cache._node_state(node, properties).duplicate(true)
	node.remove_meta(OWNER_META)
	_check(not cache._matches_node_state(node, properties, initial, true), "removed metadata rejects safely without stale property reads")
	node.set_meta(OWNER_META, "original-owner")
	node.mesh = null
	_check(not cache._matches_node_state(node, properties, initial, true), "missing mesh does not query an invalid surface override")
	node.free()
	cache.clear()
	node = _node(scene)
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# The dummy backend queries fallback materials while clearing multiple
	# instance overrides, so give each fixture surface a valid base material.
	mesh.surface_set_material(0, StandardMaterial3D.new())
	mesh.surface_set_material(1, StandardMaterial3D.new())
	node.mesh = mesh
	properties = cache._property_names(node)
	_check(not cache._build_fast_state.MeshInstance3D, "additional surfaces retain generic reflection")
	initial = cache._node_state(node, properties).duplicate(true)
	node.set_surface_override_material(1, StandardMaterial3D.new())
	_check(not cache._matches_node_state(node, properties, initial), "generic fallback validates the additional surface override")
	node.set_surface_override_material(1, null)
	node.free()
	visible_parent.free()
	skeleton.free()
	scene.free()
	print("PROP_STATE_READER_%s checks=%s" % ["FAILED" if failed else "OK", checks])
	quit(1 if failed else 0)


func _node(scene: Node) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = BoxMesh.new()
	node.set_meta(OWNER_META, "original-owner")
	scene.add_child(node)
	node.owner = scene
	return node


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)
