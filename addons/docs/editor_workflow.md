# Editor workflow and generator components

Enable Roda-Gen under Project Settings > Plugins to use its scene Undo/Redo
integration. The addon manifest is `addons/plugin.cfg` in this project. When
installing the contents of `addons/` under a host project's `addons/roda-gen/`,
enable that installation's `plugin.cfg`; editor script references are relative.

Selecting a width handle activates the matching control-point subgizmo on its
`SplinePathProfile3D`. The standard editor move/rotate tools then edit source
curve points and tangents. A drag commits one history operation, including
multi-point edits; cancelling restores the original data. This avoids trying to
recover original tangents from a generated handle's recalculated road frame.

Inspector changes to selected-point width, tilt, lane counts, lane width and
transition properties include their underlying profile data in the same history
operation. Undo and redo target the originally edited point even if selection
has moved to another point. Transition Curve resources retain their identities
so their own editor history remains connected, including resources created when
enabling directional lanes for the first time. The first applied state is kept
for Redo; replay does not seed replacement Curve objects.

The existing width preview nodes are retained for saved-scene compatibility.
Without the editor plugin, scripts can still generate roads and use the legacy
handle editing workflow, but the plugin's complete history integration is absent.

## Generation ownership

- `road_network_creator.gd`: exported settings, scheduling, generation lifecycle,
  scene nodes, collision updates and compatibility entry points.
- `road_path_sampler.gd`: path sampling, road cross-sections and source rows.
- `road_mesh_builder.gd`: surface construction, normals and outer walls.
- `road_junction_builder.gd`: sockets, clustering, welding and edge trimming.
- `road_terrain_builder.gd`: terrain topology, clipping, heights and skirts.
- `road_terrain_influence_builder.gd`: influence strips and height blending.

Builder settings are captured before each generation job. Scene-node changes
remain with the coordinator. Typed entry points preserve consumers of the
existing road API while computations live with their owning component.

## Checks

The baseline fixture records mesh arrays from before component extraction,
including banked roads, junctions, shoulders, sidewalks, outer walls and six
terrain configurations:

```sh
godot --headless --path . --script tools/check_road_mesh_baseline.gd -- --compare res://tools/fixtures/road_mesh_baseline.json
godot --headless --path . --script tools/check_lane_profile.gd
```

The editor history check uses a separate editor process and the small demo scene.
It exercises native Inspector property controls and the resource picker's actual
signal path, native scene/resource history, and registered point gizmo callbacks:

- Selected-point legacy width, tilt, left/right lanes, lane width, incoming
  transition distance and Curve assignment. Undo/Redo changes the original point
  even after selecting another point, and preserves unrelated profile data.
- Lane enable/disable, Inspector field visibility, and first conversion from
  legacy widths with previously empty lane storage. Seeded Curve identities and
  their separate resource history survive the lane-enable Undo/Redo cycle.
- Three continuous lane-width updates merge into one action; Redo restores the
  final slider value, not an intermediate value.
- Source-point movement and tangent rotation on all axes, deselection,
  multi-point edits and cancellation.

```sh
godot --headless --editor --path . addons/scenes/road_editing_demo.tscn -- --roda-editor-tests
```

Success prints `ROAD_EDITOR_HISTORY_OK`. The native controls emit their edit
signals programmatically; this is not a claim of physical mouse/keyboard replay
or exhaustive testing of Godot's built-in Curve graph editor.

The separate span compatibility check invokes native prop/deformer handle
conversion callbacks and verifies transformed offsets, stable repeated sync,
range normalization and generated deformer mesh/collision. It is not a mouse
replay or an editor-history test:

```sh
godot --headless --path . --script tools/check_span_handle_compatibility.gd
```

The separate graphical check opens the actual editor with Forward+, selects a
control point through its legacy handle, widens the road using the Inspector,
and compares its editor viewport before/after Undo and Redo:

```sh
godot --editor --path . addons/scenes/road_editing_demo.tscn --rendering-method forward_plus --resolution 1280x900 -- --roda-editor-visual-tests
```

It prints `ROAD_EDITOR_VISUAL_OK` and writes viewport images to
`/tmp/roda-editor-{before,widened,undo,redo}.png`, plus full editor-window images
with the `roda-editor-window-` prefix. It uses temporary World Up road geometry
without saving the source scene. Native debug drawing, grid and transform
overlays are disabled for the pixel comparison; the addon's orange width preview
and cyan selected-point gizmo remain visible. The original view flags are restored.

Verified on the custom Godot 4.7.2 build, Forward+ / RX 6800 XT: widening changed
7,907 pixels, Undo and Redo each differed by 0 pixels from their reference states,
and both preview colors were visible. The custom build still logs one
`Contact shadows: no environment active` renderer diagnostic during editor
initialization; this check does not establish the cause of that engine message.
