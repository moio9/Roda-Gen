@tool
extends "../../addons/scripts/spline_road/terrain_topology_builder.gd"
var rebuilds := 0

func regenerate() -> void:
	rebuilds += 1
	_clear_generated()
