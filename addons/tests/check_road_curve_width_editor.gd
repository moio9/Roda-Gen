@tool
extends RefCounted
const CHECK = preload("../scripts/spline_road/road_curve_width_check.gd")
const ROAD = preload("../scripts/spline_road/road_network_creator.gd")
const SECTION = preload("../scripts/spline_road/road_lane_section.gd")
var tree: SceneTree
var checks := 0
var failed := false


func run(plugin: EditorPlugin) -> void:
	tree = plugin.get_tree()
	_check_analytic_strips()
	var scene := EditorInterface.get_edited_scene_root()
	var path: Path3D = scene.get_node("Route")
	path.curve = _quarter_circle(5.0)
	path.lane_profile_enabled = true
	for i in range(2):
		path.set_point_lane_count_at_index(i, true, 1)
		path.set_point_lane_count_at_index(i, false, 1)
		path.set_point_lane_width_at_index(i, 3.0)
	path.apply_lane_changes()
	var road := ROAD.new()
	road.name = "Road"
	road.source_paths.assign([NodePath("../Route")])
	road.threaded_generation_enabled = false
	road.auto_regenerate_in_editor = false
	road.debug_generation_logs = false
	road.sample_step = 0.2
	road.adaptive_sampling_enabled = false
	road.invert_faces = true
	scene.add_child(road)
	road.regenerate()
	_check(road.get_curve_width_report().regions.is_empty(), "Actual narrow generated curve is safe")
	var selected := EditorInterface.get_selection()
	selected.clear()
	selected.add_node(path)
	await _frames(3)
	var view: RefCounted = plugin.section_editor.curve_warnings
	view.refresh(true)
	_check(view.button.text == "Curve Check: OK", "Selected safe road reports OK")
	var bay := SECTION.new()
	bay.start_offset = 0.0
	bay.end_offset = 0.0
	bay.taper_length = 0.5
	bay.lane = 2
	# This path turns toward its right-hand asphalt edge.
	bay.side = 1
	path.lane_appearance_overrides.assign([bay])
	road.regenerate()
	view.refresh()
	var report: Dictionary = road.get_curve_width_report()
	_check(not report.regions.is_empty(), "A local extra lane creates a curve-width diagnostic")
	if report.regions.is_empty():
		_finish()
		return
	_check(report.regions[0].folded and report.regions[0].side == 1, "Fold is localized to the widened inside edge")
	_check(report.regions[0].start > 0.0 and report.regions[0].end < path.curve.get_baked_length(), "Taper endpoints remain outside the folded interval")
	_check(view.regions.size() == report.regions.size() and "folded" in view.button.text, "Toolbar shows generated fold count")
	_check(view.button.tooltip_text.contains("Route") and view.button.tooltip_text.contains("right"), "Tooltip identifies path, side and distance interval")
	_check(is_instance_valid(view.overlay) and view.overlay.owner == null and view.overlay.mesh.get_surface_count() == 2, "Warning has editor-only fill and outline")
	if not is_instance_valid(view.overlay):
		_finish()
		return
	path.hide()
	_check(view.overlay.is_visible_in_tree(), "Warning stays visible when the source path is hidden")
	var mesh: Mesh = road.get_node("GeneratedSplineRoadWelded").mesh
	var revision: int = road.get_curve_width_revision()
	var overlay: Object = view.overlay
	await _frames(35)
	view.refresh()
	_check(view.overlay == overlay and road.get_curve_width_revision() == revision, "Idle checks reuse the diagnostic and overlay")
	view.button.button_pressed = false
	_check(view.overlay == null and not view.regions.is_empty(), "Toggle hides the overlay but retains warning details")
	view.button.button_pressed = true
	_check(is_instance_valid(view.overlay) and road.get_node("GeneratedSplineRoadWelded").mesh == mesh, "Showing diagnostics does not regenerate or change asphalt")
	# A paint-only refresh must retain the existing geometry diagnostic.
	road.markings_enabled = true
	road.regenerate()
	_check(road.get_curve_width_revision() == revision, "Paint-only changes preserve width diagnostics")
	if DisplayServer.get_name() != "headless":
		await _capture(path, road, plugin)
	# Diagnostic storage follows generation but is never saved in the scene.
	var packed := PackedScene.new()
	_check(packed.pack(scene) == OK, "Editor fixture can be packed with diagnostic controls active")
	var state := packed.get_state()
	var saved_overlay := false
	for i in range(state.get_node_count()):
		saved_overlay = saved_overlay or str(state.get_node_name(i)) == "__RoadCurveWarnings"
	_check(not saved_overlay, "Warning nodes are excluded from saved scenes")
	path.lane_appearance_overrides.clear()
	road.regenerate()
	view.refresh()
	_check(view.regions.is_empty() and view.overlay == null and view.button.text == "Curve Check: OK", "Narrowing the road clears stale warning geometry")
	selected.clear()
	await _frames(3)
	_check(view.regions.is_empty() and view.overlay == null, "Deselecting clears selected-road diagnostics")
	_finish()


func _check_analytic_strips() -> void:
	_check(_analyze_arc(2, 25).regions.is_empty(), "Wide outside edge on a tight curve is safe")
	var near := _analyze_arc(8.5, 2)
	_check(near.regions.size() == 1 and not near.regions[0].folded, "80 percent radius threshold warns before folding")
	var fold := _analyze_arc(12, 2)
	_check(fold.regions.size() == 1 and fold.regions[0].folded and fold.regions[0].side == -1, "Width beyond radius identifies the left-side fold")
	_check(absf(fold.regions[0].min_ratio + 0.2) < 0.001, "Measured edge compression matches analytic circle")
	_check(_analyze_arc(10, 2).regions[0].folded, "Collapsed inside edge at the radius is flagged")
	_check(_analyze_arc(14, 2, PI / 3.0).regions.is_empty(), "Bank reduces horizontal reach; safe banked edge is not a false positive")
	var transform := Transform3D(Basis.from_euler(Vector3(0.4, 0.7, -0.3)).scaled(Vector3(-2, 3, 0.7)), Vector3(900, -20, 300))
	var mirrored := _analyze_arc(12, 2, 0.0, transform)
	_check(mirrored.regions.size() == 1 and mirrored.regions[0].folded, "Rotated mirrored nonuniform transform preserves fold detection")
	_check(_analyze_arc(2, 25, 0.0, transform).regions.is_empty(), "Transformed safe curve remains safe")
	var straight_vertices := PackedVector3Array([Vector3(-1,0,0), Vector3(1,0,0), Vector3(-50,0,-10), Vector3(30,0,-10)])
	var straight_rows := [{"position": Vector3.ZERO, "distance": 0.0, "row_edges": [0,0,0,1]},
		{"position": Vector3(0,0,-10), "distance": 10.0, "row_edges": [2,2,2,3]}]
	_check(CHECK.analyze(straight_vertices, [straight_rows]).regions.is_empty(), "Rapid widening on a straight road does not trigger a curve warning")
	_check(CHECK.analyze(straight_vertices, [[], [straight_rows[0]], [straight_rows[0], straight_rows[0]]]).regions.is_empty(), "Empty and repeated rows stay finite and quiet")


func _analyze_arc(left: float, right: float, bank := 0.0, transform := Transform3D.IDENTITY) -> Dictionary:
	var vertices := PackedVector3Array()
	var rows: Array = []
	for i in range(65):
		var angle := (PI * 0.5) * i / 64.0
		var radial := Vector3(sin(angle), 0, cos(angle))
		var center := radial * 10.0
		var lateral := radial * cos(bank) + Vector3.UP * sin(bank)
		vertices.append(transform * (center - lateral * left))
		vertices.append(transform * (center + lateral * right))
		rows.append({"position": transform * center, "distance": angle * 10.0,
			"row_edges": [i*2, i*2, i*2, i*2+1]})
	return CHECK.analyze(vertices, [rows])


func _quarter_circle(radius: float) -> Curve3D:
	var curve := Curve3D.new()
	curve.bake_interval = 0.05
	var k := radius * 0.55228475
	curve.add_point(Vector3(radius,0,0), Vector3.ZERO, Vector3(0,0,-k))
	curve.add_point(Vector3(0,0,-radius), Vector3(k,0,0), Vector3.ZERO)
	return curve


func _capture(path: Path3D, road: Node3D, plugin: EditorPlugin) -> void:
	EditorInterface.set_main_screen_editor("3D")
	var camera := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	var frame: Dictionary = road.get_path_surface_frame(path, path.curve.get_baked_length() * 0.5)
	var fix := func():
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 22
		camera.look_at_from_position(frame.center + Vector3(0,18,8), frame.center, Vector3.UP)
	RenderingServer.frame_pre_draw.connect(fix)
	await _frames(6)
	await RenderingServer.frame_post_draw
	EditorInterface.get_editor_viewport_3d(0).get_texture().get_image().save_png("/tmp/roda-curve-width-warning.png")
	RenderingServer.frame_pre_draw.disconnect(fix)


func _frames(count: int) -> void:
	for i in range(count):
		await tree.process_frame


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("ROAD CURVE WIDTH: " + message)


func _finish() -> void:
	print("ROAD CURVE WIDTH EDITOR %s checks=%d" % ["FAIL" if failed else "PASS", checks])
	tree.quit(1 if failed else 0)
