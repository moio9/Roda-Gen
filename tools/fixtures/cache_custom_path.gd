extends Path3D
## Test an arbitrary provider whose dynamic state is not part of a known schema.
var dynamic_width := 6.0
var width_queries := 0


func get_width_at_offset(_offset: float) -> float:
	width_queries += 1
	return dynamic_width
