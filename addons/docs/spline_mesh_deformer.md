# Spline Mesh Deformer

`SplineMeshDeformer3D` bends mesh vertices continuously along a `Path3D`. It is intended for walls, fences, guard rails, curbs, pipes and other objects that must follow road curves instead of being placed as rigid props.

## Basic setup

1. Add `SplineMeshDeformer3D` as a child of the road `Path3D`/`SplinePathProfile3D`, or beside that path under `RoadNetworkCreator3D`.
2. Assign `Source Mesh`.
3. Set `Deform Axis` to the local axis along which the source asset was modeled. Walls and fence panels commonly use `Local +X`; Godot-forward assets commonly use `Local -Z`.
4. Leave `Repeat Mesh` for fences/barriers, or choose `Stretch One Mesh` for one continuous source.
5. Choose `Center`, `Left Edge`, `Right Edge` or `Both Edges` under Placement.

The output updates in the editor. Use `Regenerate Curved Mesh` to force an immediate rebuild.

## Start and end handles

`Show Span Handles` creates draggable `StartHandle` and `EndHandle` markers in the 3D editor, like `SplinePropSpan3D`.
Saved Start/End markers are removed from the runtime tree; only the authored span
values and generated mesh/collision remain. No scene resave is required.

- Drag either marker along the curve to set the generated range visually.
- The range is written back to `Start Offset` and `Span Length`; a conflicting `End Trim` is cleared.
- `Snap Span Handles To Path` keeps both markers projected onto the curve.
- By default, a heavy mesh regenerates after the mouse is released. Enable `Regenerate While Dragging Handles` only when the mesh is light enough for live rebuilding.

Sub-millimetre projection changes are ignored so stationary handles cannot cause a regeneration loop.

## Length modes

- `Stretch One Mesh` maps the complete source mesh from `Start Offset` to the end of the selected curve span.
- `Repeat Mesh` tiles the source mesh using its natural length. `Fit Repeats To Span` makes a small uniform adjustment so the last repeat meets the end without a gap.
- `Span Length` is the total fence/wall length in metres, measured from `Start Offset`. Leave it at `0` to use the entire remaining curve.
- `Start Offset` and `End Trim` can further limit the generated section without editing the source path.

`Repeat Mesh` is the default because it preserves fence and guard-rail module proportions and repeats their UVs. For a solid wall made from one continuous source, Stretch mode can be useful.

## Smooth bends

`Auto Subdivide Mesh` slices source triangles before bending them. This lets a simple box bend smoothly even if the imported source has no longitudinal subdivisions.

- Lower `Curve Subdivision Step` for tighter/smoother bends.
- Start with `0.5 m` for barriers and `0.25 m` for close-up curved walls.
- Increase it for long distant objects if generation becomes heavy.

UVs, vertex colors, normals, tangents, multiple triangle surfaces and their materials are retained. Skinned meshes and blend shapes are not intended for this generator.

## Road-edge placement

When the path belongs to `RoadNetworkCreator3D`, the deformer discovers it automatically and uses its exact banked surface frame.

- `Left Edge`/`Right Edge` include lane, shoulder and sidewalk widths.
- `Both Edges` creates one deformed mesh on each side.
- `Outward Offset` moves both outputs farther away from the road.
- `Lateral Offset` moves both outputs in the same path-relative direction.
- `Vertical Offset` adjusts the base height.
- `Add Sidewalk Height At Edges` places the base on top of the sidewalk when one exists.

Set `Road Network Source` explicitly only if automatic ancestor discovery cannot find the intended road generator.

`Follow Generated Road Edge` is enabled by default for edge placement with
`Follow Road Surface` and `Edge Uses Total Road Width`. It samples the final welded
road outline, including lateral joins, and uses the resulting height and bank.
The mesh's lateral thickness is kept outside that outline before adding the
authored offsets. Road rebuilds update the deformer in the editor and at runtime.
Small bend slices that would cut across a side-junction opening are omitted;
their collision is omitted with them. Span handles remain on the source path.

Disable this option for the original placement centered on the authored edge.
Center placement and lane-only placement retain their existing behavior. Without
a generated road surface, the deformer falls back to the source path frame.

## Collision and saving

- `Generate Collision` creates trimesh collision for every generated side.
- `Persist Generated In Scene` stores generated nodes in the scene. Leave it off for lightweight editor previews that regenerate when the scene runs.
- `Material Override` replaces every source surface material; leave it empty to retain the mesh materials.

The source mesh origin is preserved across its cross-section. If a centered wall is half underground, raise `Vertical Offset` by half its source height.

A ready-to-open example is available at `res://addons/scenes/spline_mesh_deformer_demo.tscn`.

## Regression checks

```sh
godot --headless --path . --script addons/tests/check_deformer_final_road_edge.gd
godot --headless --path . --script tools/check_span_handle_compatibility.gd
godot --headless --path . --script tools/check_road_presets.gd
```

The final-edge check covers banked lateral joins, mesh thickness, both sides,
transformed outputs, collision parity, road edits, junction openings and explicit
fallback modes. Preset checks also protect deferred lane editing and bake validity.
