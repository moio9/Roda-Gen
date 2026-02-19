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

Project includes a runtime/editor helper script for procedural roads:

- Script: `res://scripts/procedural_road_generator.gd`
- Demo scene: `res://scenes/road_generator_demo.tscn`
- Default road class preset: `res://resources/michi_default_road_class.tres`

Usage:

1. Open `scenes/road_generator_demo.tscn` and run it.
2. Select the root node and tune network params: `grid_width`, `grid_height`, `block_size`, `extra_connection_chance`, `diagonal_connection_chance`, `intersection_arm_offset`.
3. Leave `auto_regenerate_on_change` enabled to rebuild automatically when generation params change.
4. Toggle `regenerate_now` in Inspector for a manual rebuild at any time.

The script targets `addons/michi`, creates/reuses a `MichiRoadManager`, generates `RoadIntersection` nodes for degree>=3 junctions, adds connector `RoadPoint` arms, and rebuilds the network.
