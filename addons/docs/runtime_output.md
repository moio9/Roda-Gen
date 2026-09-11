# Runtime road output and baking

`RoadNetworkCreator3D > Runtime Output` provides two output modes:

- **Single Mesh** is the default and preserves `GeneratedSplineRoadWelded`.
- **Spatial Chunks** creates `GeneratedRoadChunks/Chunk_x_y_z` meshes. Adjust
  **Output Chunk Size** in the creator's local coordinates (100 by default).

Whole triangles are assigned by their centroids, not cut at cell boundaries.
Normals are calculated before partitioning, keeping continuous lighting across
cells. A chunk's actual bounds can extend beyond its nominal cell. Materials and
the existing generated mesh's transform/render settings are retained.

Chunks can be culled independently. They are not streaming or automatic LOD, and
are not a guarantee of lower draw-call counts. For the included Forward+ test
view, the single mesh used **6 draws**, while chunks used **86**. This tradeoff
must be measured on the target map and camera positions; increase cell size or
keep Single Mesh when splitting does not help.

## Reuse and current limits

Unchanged chunks retain their nodes, mesh resources and static collision shapes.
Material-only edits update materials without replacing geometry or collision.
`get_output_rebuild_stats()` reports `chunks`, `rebuilt`, `reused`, `output_ms`,
`partition_ms`, `publish_ms`, `source_surface_uploads`, `cpu_surfaces` and
`partition_surfaces` (per-surface cell reuse, centroid work and payload bounds).
These are **output-stage metrics**, not source-segment generation metrics.

The separate opt-in **Incremental Generation Enabled** workflow now skips
unchanged road cross-section construction, junction discovery, weld geometry and
stable indexed surface normals; see
`source_regeneration.md`. Terrain strips and eligible mesh prop placements
(including within-path calculations) also skip unchanged source construction.
With Spatial Chunks, this option also sends CPU arrays/materials directly to the
publisher instead of uploading a temporary complete road mesh. Only the final
chunk meshes are uploaded. Single Mesh and disabled incremental mode keep the
native mesh path. Complete CPU source assembly, global dependency validation and
lane-material overlay rebuilding remain. With stable source indices, partitioning
now reconstructs only cells touched by changed positions, normals or UVs. It
reuses other cell arrays and recalculates centroids only for position changes.
Cheap input comparison and triangle classification still traverse the source.
Changed index layouts or chunk size rebuild the partition; exceeding a cache
limit uses the native complete pass. Five surface stores each cap their estimated
retained payload at 16 MiB, with 131,072 vertices/triangles and 4,096 cells per
surface. This is not a process peak-memory limit. Clear, Single Mesh and disabled
incremental output release the stores. This construction optimization does not
reduce draw calls. Separate topology has its own incremental options and limits.

In threaded chunk mode, the previous complete output stays visible until the
worker finishes; the intermediate road-only preview is skipped to avoid
discarding and recreating unchanged terrain chunk resources.

## Collision

Enable **Output Generate Collision** to create static triangle collision, with
**Output Collision Layer/Mask** controlling generated bodies. It is disabled by
default. Turning it off removes only automatically generated bodies.

An existing manually configured
`GeneratedSplineRoadWelded/StaticBody3D/CollisionShape3D` remains user-owned.
When switching to chunks, its transform, physics settings and filters are
applied to chunk collision; its inactive original shape is cleared so it does
not collide twice. Switching back regenerates that original shape.

Baking preserves the source triangle winding; it does not repair reversed
one-sided collision. The physics test compares ray hits from both directions
before and after baking. For physics nodes, prefer unit/uniform scale: Godot
[warns against non-uniform CollisionShape3D scaling](https://docs.godotengine.org/en/stable/classes/class_collisionshape3d.html).

## Bake a runtime scene

1. Finish editing and press **Regenerate Road**; wait for generation to finish.
2. Set **Bake Output Path** to a new `.tscn` or `.scn` path.
3. Press **Bake Runtime Scene**.
4. Instance the exported scene in the game instead of this procedural generator.

Baking saves the current final road, its internal terrain/walls, lane-material
overlays, road markings, preset-owned barriers and collision into a plain scene. It does not run
regeneration, alter the editable source scene, or include control-point handles, source curves,
preview/debug meshes or generator scripts. The baked root keeps the creator's
transform relative to its parent, so place it under the same parent transform.
Meshes, materials and collision shapes are retained; referenced textures and
other external resources must remain available to the exported game.

Separate `TerrainTopologyBuilder3D`, prop arrays, manually placed mesh deformers, gameplay nodes
and sibling generators are **not included** in this road-node bake. Keep their
runtime output separately; this is not a whole-map exporter.

The owned `PresetBarriers` subtree is included as final static geometry, not as
editable deformers. After lane draft edits, finish **Rebuild Lane Dependents
(Slow)** before baking so deferred barriers match the new road edges.

Stale/in-progress output is rejected. Existing files are protected unless
**Bake Allow Overwrite** is explicitly enabled, and the generator's source scene
and ancestor scene files are never valid bake targets.

Programmatic equivalent:

```gdscript
var result: Error = road.bake_runtime_scene("res://maps/road_baked.tscn")
if result != OK:
    push_error(error_string(result))
```

The same method works outside the editor, after a complete generation. The
saved scene uses Godot's standard
[PackedScene ownership rules](https://docs.godotengine.org/en/stable/classes/class_packedscene.html).

## Regression checks

```sh
godot --headless --path . --script tools/check_road_runtime_output.gd
godot --headless --path . --script tools/check_road_runtime_output.gd -- --incremental
godot --path . --rendering-method forward_plus --resolution 640x480 --script tools/render_road_runtime_output.gd
```

The geometry check compares complete versus partitioned triangles, normals,
UVs, materials and collision faces; unchanged resource identities; local edits;
material replacement; mode changes; manual collision; and saved-scene reload.
It also compares synchronous/threaded output, refuses in-progress or source-scene
bakes, and verifies matching real physics ray hits before/after loading the bake.
The fixture has three joining arms and a distant fourth road. An unchanged
regeneration reused all **25** chunks; moving a point on the distant road rebuilt
**6** and retained **19**. This is a test-fixture result, not a game-map benchmark.

The Forward+ image check uses a fixed 640x480 render resolution, verifies visible
road pixels, and compares single/chunk/baked images. The current test view had
**15,013** foreground pixels and **0** changed pixels in both comparisons.
Temporary images/scenes are written under `/tmp/roda-runtime-*`.
