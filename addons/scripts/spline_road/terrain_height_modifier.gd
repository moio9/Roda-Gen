@tool
extends Path3D
class_name TerrainHeightModifier3D

# Safe terrain height modifier for TerrainTopologyBuilder3D.
# It can use the Y height of the modifier curve itself as the terrain height/profile.
# It affects only vertex height, not mesh topology.
#
# It does NOT create terrain mesh and does NOT change topology directly.
# It only modifies vertex height after the stable topology mesh is generated.
# Optionally, it also asks the topology builder to place extra sample points
# around this modifier, so the terrain has more resolution/detail near it.

const GROUP_NAME := "terrain_height_modifier"
const EPS := 0.00001

enum ModifierMode {
	RAISE,
	LOWER,
	FLATTEN,
	DITCH,
	CLIFF,
	NOISE,
	TERRACE,
	CUSTOM_PROFILE,
	CURVE_Y,
}

@export_group("Main Shape")
@export var enabled := true
## Height operation applied by this path modifier.
@export var mode: ModifierMode = ModifierMode.RAISE
## Maximum distance from the modifier path affected by this modifier.
@export_range(0.1, 1000.0, 0.1) var radius := 35.0
## Full-strength inner band before falloff starts.
@export_range(0.0, 1000.0, 0.1) var inner_radius := 0.0
## Height amount used by relative modes. Custom absolute profiles may ignore it.
@export_range(-500.0, 500.0, 0.01) var strength := 8.0
## Falloff curve sharpness. Higher values make the edge steeper.
@export_range(0.1, 12.0, 0.01) var falloff_power := 1.0

@export_group("Road Protection")
## If false, the modifier fades out near road edges.
@export var affect_near_roads := false
## Distance from road edge where this modifier has no effect.
@export_range(0.0, 200.0, 0.1) var protected_road_distance := 3.0
## Fade distance after protected_road_distance. Increase to remove sharp walls.
@export_range(0.0, 200.0, 0.1) var road_protection_blend_distance := 8.0
## Sampling step used for nearest-distance checks along this modifier path.
@export_range(0.25, 100.0, 0.25) var distance_sample_step := 2.0

@export_group("Mode Settings / Flatten Terrace")
## Target height for FLATTEN mode.
@export_range(-500.0, 500.0, 0.01) var target_height := 0.0
## Blend amount toward target_height in FLATTEN mode.
@export_range(0.0, 1.0, 0.01) var flatten_blend := 1.0
## Step height used by TERRACE mode.
@export_range(0.1, 100.0, 0.1) var terrace_step := 2.0
@export_range(0.0, 1.0, 0.01) var terrace_blend := 1.0

@export_group("Mode Settings / Ditch Cliff")
## Raised lip amount for DITCH mode.
@export_range(0.0, 1.0, 0.01) var ditch_lip_strength := 0.18
@export_range(0.05, 0.95, 0.01) var ditch_lip_position := 0.72
## Normalized break position for CLIFF mode.
@export_range(0.05, 0.95, 0.01) var cliff_break_position := 0.35
## Higher values make CLIFF mode sharper.
@export_range(0.2, 16.0, 0.1) var cliff_sharpness := 5.0

@export_group("Mode Settings / Curve Y")
## Enables using the modifier curve Y value in CURVE_Y mode.
@export var curve_y_enabled_in_curve_y_mode := true
@export_enum("Absolute Builder Y", "Local Delta From Modifier Origin", "Delta From Reference") var curve_y_height_mode := 0
## Blend amount toward curve Y in CURVE_Y mode.
@export_range(0.0, 3.0, 0.01) var curve_y_blend := 1.0
@export_range(-10.0, 10.0, 0.01) var curve_y_multiplier := 1.0
@export_range(-1000.0, 1000.0, 0.01) var curve_y_offset := 0.0
@export_range(-1000.0, 1000.0, 0.01) var curve_y_reference := 0.0

@export_group("Mode Settings / Custom Profile")
## Distances from modifier path for CUSTOM_PROFILE mode.
@export var profile_distances := PackedFloat32Array([0.0, 8.0, 20.0, 35.0])
## Heights paired with profile_distances for CUSTOM_PROFILE mode.
@export var profile_heights := PackedFloat32Array([10.0, 7.0, 2.0, 0.0])
## If true, profile heights are absolute terrain heights instead of deltas.
@export var custom_profile_is_absolute_height := false

@export_group("Mode Settings / Noise")
@export var noise_seed := 4517
@export_range(0.001, 2.0, 0.001) var noise_frequency := 0.08
@export_range(1, 8, 1) var noise_octaves := 3
@export_range(0.0, 1.0, 0.01) var noise_ridged := 0.0

@export_group("Resolution Points")
## Adds extra terrain topology points around this modifier.
@export var add_resolution_points := true
## Radius covered by modifier-generated topology points.
@export_range(0.25, 500.0, 0.25) var resolution_radius := 42.0
## Cross-section point spacing. Lower values smooth the modifier but cost more.
@export_range(0.25, 100.0, 0.25) var resolution_step := 4.0
## Spacing along the modifier path for topology points.
@export_range(0.5, 100.0, 0.5) var resolution_path_step := 4.0
## Number of cross-section rings when resolution points are generated.
@export_range(0, 24, 1) var resolution_radial_rings := 6
@export_range(2, 24, 1) var resolution_circle_segments := 8
@export var add_centerline_resolution_points := true
@export var add_cross_section_resolution_points := true
## Adds circular/radial samples. Smoother broad shapes, higher point count.
@export var add_circle_resolution_points := false

var _noise := FastNoiseLite.new()


func _ready() -> void:
	add_to_group(GROUP_NAME)
	_configure_noise()


func prepare_for_terrain_builder() -> void:
	_configure_noise()


func get_modifier_signature() -> String:
	var parts: Array[String] = []
	parts.append(str(enabled))
	parts.append(str(mode))
	parts.append(str(radius))
	parts.append(str(inner_radius))
	parts.append(str(strength))
	parts.append(str(falloff_power))
	parts.append(str(affect_near_roads))
	parts.append(str(protected_road_distance))
	parts.append(str(road_protection_blend_distance))
	parts.append(str(target_height))
	parts.append(str(flatten_blend))
	parts.append(str(terrace_step))
	parts.append(str(terrace_blend))
	parts.append(str(profile_distances))
	parts.append(str(profile_heights))
	parts.append(str(custom_profile_is_absolute_height))
	parts.append(str(curve_y_enabled_in_curve_y_mode))
	parts.append(str(curve_y_height_mode))
	parts.append(str(curve_y_blend))
	parts.append(str(curve_y_multiplier))
	parts.append(str(curve_y_offset))
	parts.append(str(curve_y_reference))
	parts.append(str(add_resolution_points))
	parts.append(str(resolution_radius))
	parts.append(str(resolution_step))
	parts.append(str(resolution_path_step))
	parts.append(str(resolution_radial_rings))
	if curve != null:
		parts.append(str(curve.point_count))
		parts.append(str(curve.get_baked_length()))
	return "|".join(parts)


func modify_height(builder: Node3D, point_xz: Vector2, current_y: float, road_info: Dictionary) -> float:
	if not enabled:
		return current_y

	var road_weight := 1.0
	if not affect_near_roads and not road_info.is_empty():
		road_weight = _road_protection_weight(float(road_info.get("edge_distance", 999999.0)))
		if road_weight <= 0.0001:
			return current_y

	var info := _nearest_path_info_in_builder_space(builder, point_xz)
	if info.is_empty():
		return current_y

	var d := float(info.get("distance", INF))
	var r := maxf(0.001, radius)
	if d > r:
		return current_y

	var w := _falloff_weight(d)
	w *= road_weight
	if w <= 0.0001:
		return current_y

	match mode:
		ModifierMode.RAISE:
			return current_y + strength * w
		ModifierMode.LOWER:
			return current_y - absf(strength) * w
		ModifierMode.FLATTEN:
			return lerpf(current_y, target_height, clampf(flatten_blend * absf(strength) * w, 0.0, 1.0))
		ModifierMode.DITCH:
			return current_y + _sample_ditch_delta(d, r) * w
		ModifierMode.CLIFF:
			return current_y + _sample_cliff_delta(d, r) * w
		ModifierMode.NOISE:
			return current_y + _sample_modifier_noise(point_xz) * strength * w
		ModifierMode.TERRACE:
			var step := maxf(0.001, terrace_step)
			var terraced := roundf(current_y / step) * step
			return lerpf(current_y, terraced, clampf(terrace_blend * absf(strength) * w, 0.0, 1.0))
		ModifierMode.CUSTOM_PROFILE:
			var h := _sample_custom_profile(d)
			if custom_profile_is_absolute_height:
				return lerpf(current_y, h, w)
			return current_y + h * w
		ModifierMode.CURVE_Y:
			return _apply_curve_y_height(builder, current_y, float(info.get("y", current_y)), w)

	return current_y


func _road_protection_weight(edge_distance: float) -> float:
	var protected_d := maxf(0.0, protected_road_distance)
	if edge_distance <= protected_d:
		return 0.0
	var blend_d := maxf(0.0, road_protection_blend_distance)
	if blend_d <= 0.001:
		return 1.0
	var t := clampf((edge_distance - protected_d) / blend_d, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	return t


func get_resolution_points_in_builder_space(builder: Node3D) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not enabled or not add_resolution_points:
		return out

	var centers := _sample_centerline_points_in_builder_space(builder, maxf(0.25, resolution_path_step))
	if centers.is_empty():
		return out

	var rr := maxf(0.25, resolution_radius)
	var step := maxf(0.25, resolution_step)
	var rings := resolution_radial_rings
	if rings <= 0:
		rings = maxi(1, int(ceil(rr / step)))
	else:
		rings = maxi(1, rings)

	for data in centers:
		var center: Vector2 = data.get("p", Vector2.ZERO)
		var tangent: Vector2 = data.get("tangent", Vector2.RIGHT)
		if tangent.length() < 0.001:
			tangent = Vector2.RIGHT
		tangent = tangent.normalized()
		var right := Vector2(tangent.y, -tangent.x)

		if add_centerline_resolution_points:
			out.push_back(center)

		if add_cross_section_resolution_points:
			for i in range(1, rings + 1):
				var d := rr * float(i) / float(rings)
				out.push_back(center + right * d)
				out.push_back(center - right * d)

		if add_circle_resolution_points:
			var segs := maxi(2, resolution_circle_segments)
			for i in range(1, rings + 1):
				var d := rr * float(i) / float(rings)
				for s in range(segs):
					var a := TAU * float(s) / float(segs)
					out.push_back(center + Vector2(cos(a), sin(a)) * d)

	return out


func get_bounds_in_builder_space(builder: Node3D) -> Rect2:
	var centers := _sample_centerline_points_in_builder_space(builder, maxf(0.25, resolution_path_step))
	var has_point := false
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	var pad := maxf(radius, resolution_radius)

	for data in centers:
		var p: Vector2 = data.get("p", Vector2.ZERO)
		min_v.x = minf(min_v.x, p.x - pad)
		min_v.y = minf(min_v.y, p.y - pad)
		max_v.x = maxf(max_v.x, p.x + pad)
		max_v.y = maxf(max_v.y, p.y + pad)
		has_point = true

	if not has_point:
		var p3 := builder.global_transform.affine_inverse() * global_transform.origin
		var p2 := Vector2(p3.x, p3.z)
		return Rect2(p2 - Vector2(pad, pad), Vector2(pad * 2.0, pad * 2.0))

	return Rect2(min_v, max_v - min_v)


func _falloff_weight(d: float) -> float:
	var r := maxf(0.001, radius)
	var inner := clampf(inner_radius, 0.0, r - 0.001)
	if d <= inner:
		return 1.0
	var t := clampf((d - inner) / maxf(0.001, r - inner), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	var w := 1.0 - t
	return pow(w, maxf(0.1, falloff_power))


func _sample_ditch_delta(d: float, r: float) -> float:
	var nd := clampf(d / maxf(0.001, r), 0.0, 1.0)
	var depression := -absf(strength)
	var lip_pos := clampf(ditch_lip_position, 0.05, 0.95)
	var lip_width := 0.14
	var lip_t := 1.0 - clampf(absf(nd - lip_pos) / lip_width, 0.0, 1.0)
	lip_t = lip_t * lip_t * (3.0 - 2.0 * lip_t)
	var lip := absf(strength) * ditch_lip_strength * lip_t
	return depression + lip


func _sample_cliff_delta(d: float, r: float) -> float:
	var nd := clampf(d / maxf(0.001, r), 0.0, 1.0)
	var break_pos := clampf(cliff_break_position, 0.05, 0.95)
	var t := clampf((break_pos - nd) / maxf(0.001, break_pos), 0.0, 1.0)
	t = pow(t, maxf(0.2, cliff_sharpness))
	return strength * t


func _sample_custom_profile(d: float) -> float:
	var n := mini(profile_distances.size(), profile_heights.size())
	if n <= 0:
		return 0.0
	if n == 1 or d <= float(profile_distances[0]):
		return float(profile_heights[0])
	for i in range(n - 1):
		var d0 := float(profile_distances[i])
		var d1 := float(profile_distances[i + 1])
		if d <= d1:
			var t := clampf((d - d0) / maxf(0.0001, d1 - d0), 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			return lerpf(float(profile_heights[i]), float(profile_heights[i + 1]), t)
	return float(profile_heights[n - 1])


func _apply_curve_y_height(builder: Node3D, current_y: float, curve_y: float, weight: float) -> float:
	if not curve_y_enabled_in_curve_y_mode:
		return current_y

	var target := curve_y
	match curve_y_height_mode:
		0:
			# Absolute Builder Y: terrain follows the actual Y of the curve in builder-local space.
			target = curve_y * curve_y_multiplier + curve_y_offset
		1:
			# Local delta: moving curve points up/down from the modifier origin adds/subtracts terrain height.
			var origin_local := builder.global_transform.affine_inverse() * global_transform.origin
			target = current_y + (curve_y - origin_local.y) * curve_y_multiplier + curve_y_offset
		2:
			# Reference delta: curve_y_reference is the zero-height reference.
			target = current_y + (curve_y - curve_y_reference) * curve_y_multiplier + curve_y_offset

	return lerpf(current_y, target, clampf(curve_y_blend * weight, 0.0, 1.0))


func _sample_modifier_noise(p: Vector2) -> float:
	var v := _noise.get_noise_2d(p.x, p.y)
	if noise_ridged > 0.0001:
		var ridged := 1.0 - absf(v)
		v = lerpf(v, ridged * 2.0 - 1.0, clampf(noise_ridged, 0.0, 1.0))
	return v


func _configure_noise() -> void:
	_noise.seed = noise_seed
	_noise.frequency = noise_frequency
	_noise.fractal_octaves = maxi(1, noise_octaves)
	_noise.fractal_gain = 0.45
	_noise.fractal_lacunarity = 2.0


func _nearest_path_info_in_builder_space(builder: Node3D, point_xz: Vector2) -> Dictionary:
	var samples := _sample_centerline_points_in_builder_space(builder, maxf(0.25, distance_sample_step))
	if samples.is_empty():
		return {}

	if samples.size() == 1:
		var p0: Vector2 = samples[0].get("p", Vector2.ZERO)
		return {
			"point": p0,
			"distance": point_xz.distance_to(p0),
			"tangent": Vector2.RIGHT,
			"y": float(samples[0].get("y", 0.0)),
		}

	var best_d := INF
	var best_point := Vector2.ZERO
	var best_tangent := Vector2.RIGHT
	var best_y := 0.0
	for i in range(samples.size() - 1):
		var a: Vector2 = samples[i].get("p", Vector2.ZERO)
		var b: Vector2 = samples[i + 1].get("p", Vector2.ZERO)
		var ay := float(samples[i].get("y", 0.0))
		var by := float(samples[i + 1].get("y", 0.0))
		var ab := b - a
		var len2 := ab.length_squared()
		if len2 < 0.000001:
			continue
		var t := clampf((point_xz - a).dot(ab) / len2, 0.0, 1.0)
		var q := a + ab * t
		var d := point_xz.distance_to(q)
		if d < best_d:
			best_d = d
			best_point = q
			best_tangent = ab.normalized()
			best_y = lerpf(ay, by, t)

	return {
		"point": best_point,
		"distance": best_d,
		"tangent": best_tangent,
		"y": best_y,
	}


func _sample_centerline_points_in_builder_space(builder: Node3D, step: float) -> Array:
	var out: Array = []
	var inv := builder.global_transform.affine_inverse()

	if curve == null or curve.point_count <= 0 or curve.get_baked_length() <= 0.001:
		var p3 := inv * global_transform.origin
		out.append({
			"p": Vector2(p3.x, p3.z),
			"tangent": Vector2.RIGHT,
			"y": p3.y,
		})
		return out

	curve.bake_interval = maxf(0.05, minf(step, distance_sample_step))
	var length := curve.get_baked_length()
	var d := 0.0
	while d < length:
		out.append(_sample_centerline_at_distance(builder, d, length))
		d += maxf(0.1, step)
	out.append(_sample_centerline_at_distance(builder, length, length))
	return out


func _sample_centerline_at_distance(builder: Node3D, dist: float, length: float) -> Dictionary:
	var inv := builder.global_transform.affine_inverse()
	var p3 := inv * (global_transform * curve.sample_baked(dist, true))

	var prev_d := maxf(0.0, dist - maxf(0.05, distance_sample_step * 0.5))
	var next_d := minf(length, dist + maxf(0.05, distance_sample_step * 0.5))
	var p_prev := inv * (global_transform * curve.sample_baked(prev_d, true))
	var p_next := inv * (global_transform * curve.sample_baked(next_d, true))
	var t3 := p_next - p_prev
	var t2 := Vector2(t3.x, t3.z)
	if t2.length() < 0.001:
		t2 = Vector2.RIGHT
	else:
		t2 = t2.normalized()

	return {
		"p": Vector2(p3.x, p3.z),
		"tangent": t2,
		"y": p3.y,
	}
