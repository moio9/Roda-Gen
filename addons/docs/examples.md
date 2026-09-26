# Editable example scenes

Open a scene below and press **F6** (Run Current Scene). These are small road
authoring examples, not complete driving games: no vehicle, traffic AI or
gameplay controller is included. All materials and meshes are self-contained.

| Scene | Demonstrates | Start editing here |
| --- | --- | --- |
| [Addon showcase](../scenes/examples/addon_showcase.tscn) | One connected layout with a contour intersection, crossings, lane widening, lateral join, rocky terrain, spline fence/guardrail, lamps and terrain-snapped MultiMesh trees | `Road`, `Terrain`, `FencePosts`, `FenceUpperRail`, `Guardrail`, `Trees` |
| [Urban intersection](../scenes/examples/urban_intersection.tscn) | Four arms joined by the generic Contour junction, rounded sidewalks and prop-array crossings | `Road/North`, `South`, `East`, `West`, `Crosswalks` |
| [Highway entry](../scenes/examples/highway_entry.tscn) | Straight two-lane carriageway, tangential ramp, parallel acceleration lane and gradual taper | `Road/MainApproach`, `Road/EntryRamp` |
| [Lateral join playground](../scenes/examples/lateral_join_playground.tscn) | Independent splines joined side by side with smooth endpoint tapers | `Joined/Main`, `Joined/ExtraLane` |
| [Junction playground](../scenes/examples/junction_playground.tscn) | Independent Cross, T and Oblique contour junctions | `Cross`, `T_Junction`, `Oblique` |
| [Canyon road](../scenes/examples/canyon_road.tscn) | Climbing bends, asymmetric cliff/valley terrain profiles, procedural rock strata and spline guardrail | `Road/CanyonRoute`, `Terrain`, `Guardrail` |
| [Wide chasm](../scenes/examples/wide_chasm.tscn) | One road spline with a 45 m deep right-side floor continuing to the terrain bounds | `Road/Ridge`, `Terrain` |
| [Terrain spline continuation](../scenes/examples/terrain_spline_continuation.tscn) | Closed terrain spline with the entire interior filled at -35 m, not just a local ring | `Terrain/BasinBoundary` |

For a larger, compressed mountain resort, open [Poiana Brașov](../scenes/examples/poiana_brasov.tscn).
Its editing, terrain and forest details are in [the dedicated scene notes](poiana_brasov.md).

## Navigation

- Hold right mouse and drag to orbit.
- Mouse wheel zooms; WASD pans the view; Shift moves faster.
- R restores the initial view.

## Editing and reuse

Duplicate a scene before experimenting. Select a path under `Road` and edit its
Curve3D control points. Lane counts and widths live on that path's lane profile.
These examples use scripts from `addons/scripts`; their road geometry is
configured with scene resources and Inspector properties.

### Combined showcase

Open `addon_showcase.tscn` and press **F6**. Numbered labels identify the major
features. The camera supports the navigation controls above. All curves,
profiles, materials and prop sources are editable native scene resources;
there is no scene-specific geometry script.

- `Road/North`, `South`, `West`, `Canyon`: four shared endpoints form the rounded intersection.
- `Road/North`: lane counts widen from one to two on one side through a 30 m transition.
- `Road/South` + `ExtraLane`: independent paths share the `layby` lateral join group.
- `Road/Canyon`: climbing curve with its own asymmetric terrain profile.
- `Terrain`: shared generator with Rock Detail; the reusable
  `addons/materials/rock_and_grass.gdshader` blends grass/rock by slope.
- `Terrain/TownGrade`: editable height modifier that flattens the urban area
  and softens its transition into the hills while protecting road edges.
- `Crosswalks`: stripe prop arrays on four editable transverse paths.
- `FencePosts`, `FenceLowerRail`, `FenceUpperRail`: repeated posts and continuous deformed rails.
- `GuardrailPosts`, `Guardrail`: equivalent metal barrier along the climbing road.
- `LampPoles`, `LampHeads`: matching prop arrays; decorative fixtures without dynamic lights.
- `Trees`: seeded variation, ground snapping and MultiMesh output.
- `ExhibitLabels`: optional labels; hide this node for an unobstructed view.

Terrain regenerates when the scene opens/runs. After editing, use **Rebuild Road +
Terrain**. Trees wait for terrain before placing themselves. The example uses
primitive meshes so it remains portable; replace prop meshes with your own assets.
Check it with `godot --headless --path . --script tools/check_addon_showcase.gd`;
omit `--headless` and append `-- --screenshots` for four rendered views in
`/tmp/roda-showcase-*.png`.

The urban arms meet at the origin. `Road` uses **Contour (Experimental)** with
`Junction Corner Radius = 6.0` and 1.8 m sidewalks. Move the shared endpoints together when
moving the junction, or edit the outer road points independently. `Crosswalks`
uses `SplinePropArray3D` to repeat stripe meshes along four editable transverse
paths; move those paths when relocating a crossing.

At the highway, `MainApproach` remains an uninterrupted two-lane road.
`EntryRamp` includes the acceleration lane: its last three points are at
(7.5, 0, 20), (7.5, 0, 100) and (7.5, 0, 180). Its right lane counts are
1, 1, 1, 1, 0, so the last 80 m taper through `SplinePathProfile3D`.
Both profiles use `lateral_join_group = "entry"`: the shared edge becomes a lane
separator when the asphalt edges meet. Keep the parallel section near the main
road's right edge when editing. See [lateral joins](lateral_joins.md) for controls
and limits.
This is an authored merge using ordinary lane profiles; no separate connector
mesh or scene-specific geometry code is involved. Markings come from the road
marking generator. No traffic routing or right-of-way logic is included.

After changing a curve/profile, use **Rebuild Road + Terrain** in the addon UI,
or regenerate `Road` and then `Terrain`. Terrain auto-regeneration is intentionally
off so dragging points does not continuously triangulate the surrounding land.
The terrain node uses explicit source paths and manual bounds; adjust those
bounds if you extend the roads. The urban and highway roads extend beyond the
terrain tile on purpose, as connections to an imagined larger map.

`Terrain.generate_on_ready` opts these three terrain examples into runtime
terrain generation on F6. It defaults to false for other scenes, allowing saved
terrain meshes to remain in use. Roads and props use their existing startup
behavior. `addons/scripts/orbit_camera.gd` supplies reusable navigation and an
optional `title` overlay; it does not build geometry. Local triangulation and
MultiMesh prop rendering are not enabled by these examples.

To reuse in a consuming project, copy the examples folder and shader alongside
the addon's existing `scenes` and `scripts` layout. No references to another
game's assets or installed project paths are required. Brașov examples retain
their existing scene scripts and settings.

The urban/highway terrain sits below the asphalt, with a `GroundSupport` plane
beneath it. That plane is only appropriate for these flat examples.

## Verification

From this project root:

```sh
godot --headless --path . --script tools/check_road_examples.gd
godot --headless --path . --script tools/check_junction_playground.gd
godot --path . --script tools/check_road_examples.gd -- --screenshots
```

The check loads all three scenes and requires road, marking and terrain meshes,
generic script dependencies, the contour junction, actual acceleration-lane
asphalt coverage, prop/deformer output,
and working camera zoom/reset.
The last command additionally saves previews to `/tmp/roda-example-*.png`.

## Poiana to Brașov centre

[Mapped 11.8 km road and roundabout](brasov_centru.md), with a camera tour for
inspecting curves and grades without a vehicle. Uses the normal addon generators.
