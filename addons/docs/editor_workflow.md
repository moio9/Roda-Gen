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

## Spatial width and tilt editing

Select a road point by clicking its crossbar with the path selected, or select
`__WidthHandles/Handle_###` in the scene tree. The selected point gains two
edge handles and an orange tilt arc:

- Drag either edge dot to adjust width. On a legacy-width road this changes the
  total width symmetrically. With directional lanes enabled it changes the common
  lane width at that point and preserves left/right lane counts; a side with no
  lanes has no edge dot. Width changes apply to the road on release, including
  when live lane regeneration is disabled.
- Drag the dot above the point along the orange arc to change its tilt. This
  banks the road without rotating its curve tangents or moving the point. View
  the arc from an oblique angle; a view exactly along its plane cannot resolve
  a tilt angle reliably.
- The standard arrows still move the point. Each shape drag is one Undo/Redo
  action, tied to the original point after selection changes. Right-click during
  a drag cancels it, following Godot's native gizmo behavior.

Only the selected point has shape controls. They belong to the editor plugin;
no additional controls are stored in the scene or instantiated at runtime.
Existing Inspector values remain available for exact numerical entry. Terrain
and other dependent generators retain their existing rebuild workflow.

The existing width preview nodes are retained for saved-scene compatibility.
Without the editor plugin, scripts can still generate roads and use the legacy
handle editing workflow, but the plugin's complete history integration is absent.

## Click-to-edit road sections

Select a `SplinePathProfile3D`, one of its controls, or its road generator, then
enable **Road Sections** in the 3D toolbar. Click the asphalt on the desired side:
the selected lane interval is highlighted and a menu opens.

- **Add lane on this side** adds an outer lane; **Stopping bay on this side** adds an outer
  stopping area. Both taper smoothly into the existing road. Clicking an existing
  added lane lets you change its preset or remove it without stacking another one.
- Click near a lane boundary and choose **Solid**, **Dashed**, **No marking**,
  **Double solid** or **Inherit road style** to change that line only over the selected interval. Shared
  separators can be edited from either adjacent lane.
- Optional start/end stop lines are available in the same menu. On a new lane
  or bay they sit at the full-width ends of the tapers.

The initial interval runs between adjacent curve points; clicking an existing
appearance range uses that range instead. Adjust its length using
`__LaneAppearanceHandles/Range_###/StartHandle` and `EndHandle` in the scene tree.
Exact distances, taper length, surface material and other appearance settings
remain available on the resource in **Lane Appearance Overrides**.

Adding a lane requires a constant lane count on the selected side over that
interval. For an existing merge, select a constant section or adjust the original
point lane counts. The operation enables lane profiles automatically on legacy
roads and does not insert spline points or change tangents/tilt. Each menu action
is one Undo/Redo step; marking-only changes preserve the asphalt mesh.

Press **Escape**, or disable **Road Sections**, to return to ordinary editing and
move Start/End. Camera navigation stays available in section mode. The menu and
selection overlay are editor-only; saved section data still generates at runtime.

## Tight-curve width checks

Select a road generator, source profile or one of its controls. **Curve Check**
appears beside **Road Sections** and highlights problem intervals automatically:

- Yellow means the inside asphalt strip has less than 20% of the centerline's
  forward area growth, leaving little room before it folds.
- Red means the inside strip has collapsed or folded back. This can produce
  inverted/overlapping polygons even when the centerline looks smooth.

Hover over the button for path names, left/right sides and distance intervals.
Click it to hide/show the overlay. Reduce the inside width or open the curve
using its points and tangents to resolve the warning. The check does not alter
geometry, authored values, materials or Undo history.

The detector compares the oriented corner areas of consecutive sampled asphalt
cross-sections with their centerline advance. For a flat circle at constant
width, the ratio is `1 - inside_width / radius`; banking, asymmetric lanes and
local extra lanes/bays are included through their actual generated vertices.
It runs once per road geometry generation, before intersection/lateral-join
trimming. The editor reads its cached result and does not continually regenerate
the road. If automatic generation is disabled, regenerate to refresh the check.

This is a local asphalt-fold check at the generator's sample resolution, not a
general collision check between distant road sections, crossings, terrain,
shoulders or completed junctions. The overlays are transient, work with hidden
source paths, and neither diagnostics nor controls run during gameplay.

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

The isolated shape check exercises registered path and child-handle gizmos,
camera-ray dragging in perspective and orthographic views, asymmetric lanes,
transformed parents, cancellation, and native viewport mouse press/motion/release
with exact Undo/Redo. It never saves the fixture scene:

```sh
python3 addons/tests/check_road_shape_editor.py --godot /path/to/godot
python3 addons/tests/check_road_shape_editor.py --godot /path/to/godot --graphical
```

The graphical run uses Forward+ and captures `/tmp/roda-shape-handles.png`.

The section check exercises viewport picking on banked roads, tapered lane/bay
geometry, Start/End controls, shared separators, local paint, exact Undo/Redo,
serialization and incremental-cache invalidation:

```sh
python3 addons/tests/check_road_shape_editor.py --godot /path/to/godot --sections
python3 addons/tests/check_road_shape_editor.py --godot /path/to/godot --sections --graphical
```

The graphical section run captures `/tmp/roda-road-section.png`.

The curve-width check covers analytic safe/near/folded arcs, banking,
mirrored/nonuniform transforms, straight-road widening, a real generated bay,
cached editor overlays and cleanup. The graphical run captures
`/tmp/roda-curve-width-warning.png`:

```sh
python3 addons/tests/check_road_shape_editor.py --godot /path/to/godot --curve-checks
python3 addons/tests/check_road_shape_editor.py --godot /path/to/godot --curve-checks --graphical
```

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

Terrain startup regeneration is deferred until after the editor restores saved
node selections. Previously, opening a scene with `GeneratedTopologyTerrain`
selected freed that mesh during `_ready()`, leaving editor selection restoration
with a stale node pointer (SIGSEGV in `EditorSelection::add_node` on Termux).
Terrain still regenerates automatically; callbacks for detached/disabled builders
are skipped. The focused editor regression check is:

```sh
godot --headless --editor --path . -- --roda-terrain-startup-tests
```

It verifies that saved output survives scene-tree entry, can be selected safely,
and is retired after startup with selection cleanup. It also checks that a builder
removed from the tree before its deferred callback does not regenerate.
