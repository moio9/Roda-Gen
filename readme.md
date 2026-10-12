# Roda-Gen

Procedural roads, intersections and terrain for Godot 4, with editable spline
profiles, road markings, stopping bays, fences and roadside props.

## Open the project

Open `project.godot` in Godot 4.7 with Forward+. The Roda-Gen editor plugin is
already enabled. Press **F5** for the canyon example, or open one of these scenes
and press **F6**:

- [Canyon road](addons/scenes/examples/canyon_road.tscn)
- [Urban intersection](addons/scenes/examples/urban_intersection.tscn)
- [Highway entry](addons/scenes/examples/highway_entry.tscn)

Right-drag orbits the camera, the wheel zooms, WASD pans, and R resets the view.

## Edit roads

Add a `RoadNetworkCreator3D` with child `SplinePathProfile3D` paths. Shape their
curves, then use the viewport width and tilt handles. **Road Sections** adds
extra lanes or stopping bays and changes markings along a selected span.
**Curve Check** highlights tight bends where the asphalt may fold over itself.

Use **Regenerate Road** to update geometry and **Rebuild Road + Terrain** after
changing the road footprint. Props and deformed fences can follow the final
road edge and skip portions that overlap asphalt. Editing handles are editor-only.

## Guides

- [Editor workflow](addons/docs/editor_workflow.md) and [examples](addons/docs/examples.md)
- [Lane profiles](addons/docs/lane_profiles.md) and [markings](addons/docs/road_markings.md)
- [Intersections](addons/docs/junction_contours.md) and [terrain](addons/docs/terrain_controls.md)
- [Props](addons/docs/prop_rendering.md) and [fences](addons/docs/spline_mesh_deformer.md)
- [Presets](addons/docs/road_presets.md), [runtime baking](addons/docs/runtime_output.md)
  and [incremental generation](addons/docs/source_regeneration.md)

To install in another project, copy the contents of this repository's `addons/`
directory into `addons/roda-gen/` and enable **Roda-Gen** in Project Settings >
Plugins. `tools/` and `addons/tests/` contain development checks and example
builders; they are not required for using the generator.

[Original attribution](NOTICE.md).
