# Editable example scenes

Open a scene below and press **F6** (Run Current Scene). These are small road
authoring examples, not complete driving games: no vehicle, traffic AI or
gameplay controller is included. All materials and meshes are self-contained.

| Scene | Demonstrates | Start editing here |
| --- | --- | --- |
| [Urban intersection](../scenes/examples/urban_intersection.tscn) | Four trimmed arms joined by continuous asphalt, rounded sidewalk corners and crossings | `Road/North`, `South`, `East`, `West`, `Intersection` |
| [Highway entry](../scenes/examples/highway_entry.tscn) | Straight two-lane carriageway, tangential ramp, parallel acceleration lane and gradual taper | `Road/MainApproach`, `Road/EntryRamp`, `AccelerationLane` |
| [Canyon road](../scenes/examples/canyon_road.tscn) | Climbing bends, asymmetric cliff/valley terrain profiles, procedural rock strata and spline guardrail | `Road/CanyonRoute`, `Terrain`, `Guardrail` |

For a larger, compressed mountain resort, open [Poiana Brașov](../scenes/examples/poiana_brasov.tscn).
Its editing, terrain and forest details are in [the dedicated scene notes](poiana_brasov.md).

## Navigation

- Hold right mouse and drag to orbit.
- Mouse wheel zooms; WASD pans the view; Shift moves faster.
- R restores the initial view.

## Editing and reuse

Duplicate a scene before experimenting. Select a path under `Road` and edit its
Curve3D control points. Lane counts and widths live on that path's lane profile.
The urban and highway connectors use the dedicated `example_junction.gd`
tool script, not the generic endpoint-weld fan. Urban arms stop 14 m from the
center; their connector has 6 m corner radii and 1.8 m sidewalks. Keep these
inner endpoints fixed when editing the outer road curves.

At the highway, `MainApproach` is one uninterrupted two-lane road. The ramp's
last point is (7.5, 0, 20), with a tangent along +Z. The separate
`AccelerationLane` connector adds a 3.75 m lane for 80 m, then tapers it over
another 80 m. Keep that joining point/tangent fixed when reshaping the ramp.
Press **Rebuild Connector** on the connector after editing the ramp to refresh
its edge paint. Connector dimensions are authored in the script; these are
specific layout examples, not an automatic arbitrary-junction solution.
No traffic routing or right-of-way logic is included.

After changing a curve/profile, use **Rebuild Road + Terrain** in the addon UI,
or regenerate `Road` and then `Terrain`. Terrain auto-regeneration is intentionally
off so dragging points does not continuously triangulate the surrounding land.
The terrain node uses explicit source paths and manual bounds; adjust those
bounds if you extend the roads. The urban and highway roads extend beyond the
terrain tile on purpose, as connections to an imagined larger map.

The runtime-only `example_scene.gd` rebuilds terrain on F6; roads and props rebuild
through their existing scripts. Generated meshes are not embedded in the scene
files. `example_camera.gd` only supplies navigation and the help overlay. Local
triangulation and MultiMesh prop rendering are not enabled by these examples.

To reuse in a consuming project, copy the examples folder with its shared scripts
and shader alongside the addon's existing `scenes` and `scripts` layout. No
references to another game's assets or installed project paths are required.

Urban/highway connector triangles use front-face winding; they no longer rely
on double-sided asphalt. Their flat terrain is below the asphalt, with a
`GroundSupport` plane beneath it closing terrain-mask gaps at trimmed road ends.
This support plane is only appropriate for these flat examples. Canyon is
unchanged. The generator's global welding behavior is unchanged.

## Verification

From this project root:

```sh
godot --headless --path . --script tools/check_road_examples.gd
godot --path . --script tools/check_road_examples.gd -- --screenshots
```

The check loads all three scenes and requires road, marking and terrain meshes,
the expected junction counts, acceleration-lane settings, prop/deformer output,
and working camera zoom/reset.
The second command additionally saves previews to `/tmp/roda-example-*.png`.

## Poiana to Brașov centre

[Mapped 11.8 km road and roundabout](brasov_centru.md), with a camera tour for
inspecting curves and grades without a vehicle. Uses the normal addon generators.
