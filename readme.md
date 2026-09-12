# Procedural Road Generator Addon 道（Michi）for Godot Engine 4

A procedural road generator addon for Godot Engine 4.4 later.

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/E1E44AWTA)

## Videos

[#1](https://www.youtube.com/watch?v=wwipUz3XSag)
[#2](https://www.youtube.com/watch?v=DpbdOlNSYJo)

## Document

(WIP)

## License

MIT License

## Author

あるる（きのもと 結衣） @arlez80

## Quick Start: Procedural Road Generator

Experimental automatic corner geometry and editable profiles:
[Contour junctions](addons/docs/junction_contours.md).

New editable examples: [urban intersection](addons/scenes/examples/urban_intersection.tscn),
[highway entry](addons/scenes/examples/highway_entry.tscn), and
[canyon road](addons/scenes/examples/canyon_road.tscn).
Open one and press **F6**. See [example controls and editing notes](addons/docs/examples.md).

1. Open this project in Godot. The Roda-Gen editor plugin is enabled in
   `project.godot`; enable it under Project Settings > Plugins in a consuming project.
2. Open `addons/scenes/spline_road/spline_intersections_demo.tscn` for the road,
   intersection and prop example, or `addons/scenes/road_editing_demo.tscn` for
   a small control-point editing example.
3. To start a new road, add a Node3D using
   `addons/scripts/spline_road/road_network_creator.gd`. Add child Path3D nodes
   using `spline_path_profile.gd` from the same directory and draw their curves.
   The road discovers child paths, or you can assign `Source Paths` explicitly.
4. Edit width handles or the profile's selected-point fields. With the plugin
   enabled, selecting a width handle activates that curve point's editor
   manipulator; moving and rotating points records their actual curve data in
   the scene's Undo/Redo history.
5. Enable automatic regeneration or press **Regenerate Road**. For directional
   lanes, use **Apply Lane Changes**, then **Rebuild Road + Terrain** when ready.

The generator keeps sampling, mesh construction, junction welding and terrain
generation in separate components. Existing scene properties stay on
`RoadNetworkCreator3D`. See [`addons/docs/editor_workflow.md`](addons/docs/editor_workflow.md).

## Curved Walls, Fences and Barriers

Use `SplineMeshDeformer3D` to bend a mesh continuously along a road `Path3D`. It supports draggable start/end handles, an explicit generated span length, stretch and repeat modes, automatic triangle subdivision, banked road-edge placement, source materials and optional collision.

## Directional lane profiles

`SplinePathProfile3D` supports per-point left/right traffic-lane counts, per-point lane width, and editable Bezier easing for lanes that enter or leave the road. Width handles follow the authoritative generated road banking. Its lightweight preview updates live; `Apply Lane Changes` rebuilds only the road, `Rebuild Road + Terrain` closes the terrain against the new edges, and `Rebuild Lane Dependents (Slow)` is reserved for the final edge-prop/deformer refresh. Existing centered `point_widths` remain the default for compatibility. See `addons/docs/lane_profiles.md`.

See [`addons/docs/spline_mesh_deformer.md`](addons/docs/spline_mesh_deformer.md) for setup and tuning.

## Optional MultiMesh props

`SplinePropArray3D` keeps individual nodes by default, allowing Forward+ automatic
instancing for compatible shared meshes/materials. Its optional `Rendering > Render
Mode > MultiMesh (Item Mesh Only)` groups mesh props into spatial batches with an
adjustable cell size. Item Scene retains its normal nodes, scripts and collisions.
See [`addons/docs/prop_rendering.md`](addons/docs/prop_rendering.md).

## Road markings

Enable `RoadNetworkCreator3D > Road Markings > Enabled` for solid/dashed/double
center, lane and edge lines, plus lane-entry/exit hatching. Paint follows the
actual banked road triangles and is included in runtime bakes. Try
`addons/scenes/road_markings_demo.tscn`; see
[`addons/docs/road_markings.md`](addons/docs/road_markings.md) for controls and tests.

## Editable road presets

Choose `RoadNetworkCreator3D > Road Presets > Mountain / Urban / Highway` and press
**Apply Road Preset** for road dimensions, materials, markings and curved barriers.
The result stays editable, curve points stay in place, and application supports
one-step Undo/Redo. Options preserve existing lane layouts or customized barriers;
custom `.tres` presets are supported. See
[`addons/docs/road_presets.md`](addons/docs/road_presets.md).

## Runtime road chunks and bake

`RoadNetworkCreator3D > Runtime Output` optionally divides final geometry into
spatial chunks and retains unchanged mesh/collision resources. Single Mesh
remains the default. **Bake Runtime Scene** saves this road's final meshes and
collisions without procedural scripts, leaving the editable scene intact.
Chunking can increase draw calls. See [`addons/docs/runtime_output.md`](addons/docs/runtime_output.md)
for scope, collision settings and validation.

## Optional incremental source generation

Enable `RoadNetworkCreator3D > Workflow > Incremental Generation Enabled` to reuse
unchanged road cross-section blocks, path assembly, junction discovery, weld
geometry and indexed normals. It is off by default and works with either runtime
output mode. Spatial Chunks also reuses unchanged partition cells and avoids a
temporary whole-road upload.
Road markings reuse unchanged 32-segment construction blocks; material/color
edits retain their geometry. The final combined marking mesh is still uploaded.
Per-lane material overlays also reuse unchanged 64-row blocks and indexed normals,
while keeping material routing live and native banked surface placement.

Road-side terrain strips and compatible mesh props reuse both whole paths and
unchanged calculations inside edited paths. Ground-snapped mesh props work with
the built-in `TerrainTopologyBuilder3D`: they validate current terrain hits and
wait for pending terrain output. Separate topology has its own opt-in incremental
settings, including reuse of source queries, filtered triangles, collars and
output resources. Local triangulation remains a separate option with safe full
fallbacks; see [`addons/docs/terrain_controls.md`](addons/docs/terrain_controls.md).

Incremental does not mean every operation is local: changed-path assembly, global dependency
inspection and combined overlay/marking-mesh publication still run, and some
triangulation edits require a full rebuild. Custom callbacks/modifiers and scene
props retain their documented fallback behavior. See
[`addons/docs/source_regeneration.md`](addons/docs/source_regeneration.md) for
exact scope, counters and full-versus-incremental checks.
