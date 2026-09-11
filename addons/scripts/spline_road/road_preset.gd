@tool
extends Resource
class_name SplineRoadPreset
## A one-time editable road template. Applying does not bind the road to this resource.

@export var display_name := "Custom Road"
@export_group("Lane Layout")
@export_range(0, 8, 1) var lanes_left := 1
@export_range(0, 8, 1) var lanes_right := 1
@export_range(1.5, 8.0, 0.05, "suffix:m") var lane_width := 3.5
@export_range(0.0, 1000.0, 1.0, "suffix:m") var lane_transition_length := 40.0
@export var lane_transition_curve: Curve
@export_group("Road Settings")
@export_range(0.1, 10.0, 0.1) var sample_step := 0.75
@export_range(0.0, 15.0, 0.1) var shoulder_left_width := 0.5
@export_range(0.0, 15.0, 0.1) var shoulder_right_width := 0.5
@export_range(0.0, 15.0, 0.1) var sidewalk_left_width := 0.0
@export_range(0.0, 15.0, 0.1) var sidewalk_right_width := 0.0
@export_range(0.0, 2.0, 0.01) var sidewalk_height := 0.12
@export var invert_faces := true
@export_enum("Curve Up", "World Up", "Bank Into Curve") var road_orientation_mode := 0
@export_range(0.0, 45.0, 0.1) var road_bank_max_degrees := 8.0
@export_range(0.0, 4.0, 0.01) var road_bank_strength := 1.0
@export_range(0.05, 100.0, 0.05) var road_bank_sample_distance := 3.0
@export_group("Materials")
@export var road_material_override: Material
@export var shoulder_material_override: Material
@export var sidewalk_material_override: Material
@export var terrain_material_override: Material
@export var outer_wall_material_override: Material
@export_group("Markings")
@export var markings_enabled := true
@export_enum("Off", "Solid", "Dashed", "Double Solid", "Double Dashed") var markings_center_style := 3
@export_enum("Off", "Solid", "Dashed", "Double Solid", "Double Dashed") var markings_lane_style := 2
@export_enum("Off", "Solid", "Dashed", "Double Solid", "Double Dashed") var markings_edge_style := 1
@export var markings_center_color := Color(1.0, 0.8, 0.12)
@export var markings_line_color := Color(0.95, 0.95, 0.95)
@export var markings_hatch_color := Color(0.95, 0.95, 0.95)
@export var markings_hatching_enabled := true
@export_range(0.1, 30.0, 0.1) var markings_dash_length := 3.0
@export_range(0.1, 30.0, 0.1) var markings_dash_gap := 6.0
@export_group("Barriers")
@export_enum("None", "Steel Guardrail", "Concrete Barrier", "Pedestrian Railing") var barrier_style := 1
## Optional +Z-oriented replacement for the built-in modular barrier mesh.
@export var barrier_mesh: Mesh
@export var barrier_material: Material
@export var barrier_outer_edges := true
@export var barrier_center := false
@export_range(0.0, 10.0, 0.05, "suffix:m") var barrier_outward_offset := 0.15
@export_range(-5.0, 5.0, 0.01, "suffix:m") var barrier_vertical_offset := 0.0
@export_range(0.0, 50.0, 0.1, "suffix:m") var barrier_end_clearance := 2.0
@export_range(0.1, 10.0, 0.1, "suffix:m") var barrier_subdivision_step := 1.0
@export var barrier_generate_collision := false

const ROAD_PROPERTIES := [
	"sample_step", "shoulder_left_width", "shoulder_right_width", "sidewalk_left_width",
	"sidewalk_right_width", "sidewalk_height", "invert_faces", "road_orientation_mode",
	"road_bank_max_degrees", "road_bank_strength", "road_bank_sample_distance",
	"road_material_override", "shoulder_material_override", "sidewalk_material_override",
	"terrain_material_override", "outer_wall_material_override", "markings_enabled",
	"markings_center_style", "markings_lane_style", "markings_edge_style",
	"markings_center_color", "markings_line_color", "markings_hatch_color",
	"markings_hatching_enabled", "markings_dash_length", "markings_dash_gap",
]


func road_values() -> Dictionary:
	var values: Dictionary = {"road_width": float(lanes_left + lanes_right) * lane_width,
		"material_override": null, "markings_material_override": null,
		"left_lane_material_overrides": [], "right_lane_material_overrides": []}
	for property in ROAD_PROPERTIES:
		values[property] = get(property)
	return values


func is_valid() -> bool:
	for property in get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.type == TYPE_FLOAT:
			if not is_finite(float(get(property.name))):
				return false
	return lanes_left >= 0 and lanes_left <= 8 and lanes_right >= 0 and lanes_right <= 8 and lanes_left + lanes_right > 0 and lane_width >= 1.5 and sample_step >= 0.01 and barrier_end_clearance >= 0.0 and barrier_subdivision_step >= 0.05
