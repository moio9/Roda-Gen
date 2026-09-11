# Editable road presets

Select `RoadNetworkCreator3D > Road Presets`, choose **Mountain**, **Urban** or
**Highway**, then press **Apply Road Preset**. Selecting a name alone changes
nothing. The preset applies once; the resulting settings, materials, per-point
lanes and curved barriers remain normal editable scene data.

| Preset | Lanes per direction | Lane width | Edges | Barrier |
| --- | --- | --- | --- | --- |
| Mountain | 1 | 3.2 m | 0.5 m gravel shoulders | Steel guardrails |
| Urban | 1 | 3.25 m | 0.15 m shoulders, 2 m sidewalks | Pedestrian railings |
| Highway | 2 | 3.75 m | 2.5 m shoulders | Concrete outer and center barriers |

Mountain/highway use restrained automatic banking; urban uses World Up. Each
preset supplies asphalt/edge materials, markings and editable transition easing.
These are starting templates, not geographically standardized road designs or
complete terrain/environment scenes.

## Preserve existing work

- **Replace Lane Layout** replaces source profiles' widths, lane counts and
  transition distances/curves at every point. Disable it to retain a hand-tuned
  lane layout, including asymmetric lanes.
- **Apply Path Settings** copies shoulder/sidewalk settings to existing
  `SplinePathProfile3D` sources and disables their orientation override, keeping
  the road generator authoritative. Disable it to preserve those source settings.
- **Replace Barriers** replaces only the `PresetBarriers` subtree created by a
  previous preset. Disable it to retain customized barriers. Unrelated sibling
  nodes are never removed; an unowned node with that reserved name blocks replacement.

Curve control-point positions, tangents, tilts and node transforms are not edited.
Existing source scripts are not replaced. Plain `Path3D` sources use the road's
default total width, but directional per-point lanes require
`SplinePathProfile3D`; see [Quick Start](../../readme.md#quick-start-procedural-road-generator).

With the Roda-Gen editor plugin enabled, application is one scene Undo/Redo
action. Undo restores the former settings/material references and barrier Nodes;
Redo restores the same new Nodes, not newly generated copies of their settings.
Source scene ownership is restored too. Normal save retains the editable barrier
scripts/modules/handles, without embedding their heavy generated meshes.

Materials and per-point easing curves are copied for each application. Editing a
road's material does not change the template or another road. External textures
may remain shared. Preset selection and a custom preset resource are not live
bindings: reapply explicitly when you want new template values.

## Barriers and export

`PresetBarriers` contains standard `SplineMeshDeformer3D` nodes. Edit their start/
end handles, placement, height, material or mesh normally. Built-in modules use
local +Z for their length; a custom module should use the same orientation and
y=0 as its contact plane. Collision is disabled by default and can be enabled on
the deformer or in a custom preset.

Initial spans leave endpoint clearance and openings around the road's actual
welded junctions, even if paint is disabled. The spans are a one-time layout:
moving/adding junctions later does not automatically rewrite manually edited
spans. Adjust the handles or reapply the preset after topology changes.

Normal road generation refreshes preset-owned barriers when their applied source
signature changes, respecting their editor auto-regeneration switch. Lane draft
editing retains the existing lightweight workflow: use **Rebuild Lane Dependents
(Slow)** after final lane edits before baking.

Road-node bake includes the final preset-owned barrier geometry and optional
collision, with no deformer scripts or handles. This does not turn bake into a
whole-map exporter: unrelated prop arrays, separate terrain builders and manually
placed deformers remain outside its scope. Bake refuses stale barrier output;
see [Runtime Output](runtime_output.md).

Preset application finishes synchronously so the road and initial junction-aware
barriers are ready together. It can take time on large roads. It refuses a new
application while a generation worker is pending; Undo safely cancels/joins a
later pending worker before restoring the state.

## Custom resources and code

Duplicate an `addons/presets/*.tres` resource, or create a `SplineRoadPreset`
resource in the Inspector. Set the selector to **Custom**, assign your `.tres`
to **Custom Preset**, then apply. Built-ins are `mountain.tres`, `urban.tres` and
`highway.tres`. They use relative addon paths and need no external asset pack.

```gdscript
# Use the selected Inspector preset:
var result: Error = road.apply_road_preset()
# Or provide a custom resource (the same preserve/replace options apply):
result = road.apply_road_preset(load("res://roads/my_road_preset.tres"))
if result != OK:
    push_error(error_string(result))
```

## Checks

Use `addons/scenes/road_markings_demo.tscn` as an editable test road and apply any
of the presets to its `Road` node.

```sh
godot --headless --path . --script tools/check_road_presets.gd
godot --headless --editor --path . addons/scenes/road_markings_demo.tscn -- --roda-preset-tests
godot --path . --rendering-method forward_plus --resolution 960x720 --script tools/render_road_presets.gd
```

The headless checks cover all built-ins, custom resource save/load, curve and
layout preservation, independent resources, editable barriers, junction openings,
optional collision and both bake output modes. The real editor check covers
single-action Undo/Redo, Node identity, ownership, source-scene save/reload and
Undo while a later generation worker is pending. Deferred-lane bake rejection is
covered by a regression that failed before the actual-layout guard was added.

The Forward+ check compares each generated road to its saved runtime scene:
all three have **0 changed pixels** at 960x720 on the tested RX 6800 XT. Hiding
barriers changes 17,053 / 10,350 / 66,106 pixels for mountain / urban / highway,
so the equality test is not comparing invisible geometry. Captures are saved as
`/tmp/roda-preset-{mountain,urban,highway}.png` and matching `-baked` images.
The custom Godot 4.7.2 build reports Compute/Shader/Sampler RID warnings on exit
with MSAA 4X, as in the marking render check; their origin remains untraced.
