shader_type spatial;
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float strata = sin(world_position.y * 0.9 + sin(world_position.x * 0.035) * 0.7);
	float fine = sin(world_position.y * 3.6) * 0.012;
	ALBEDO = mix(vec3(0.40, 0.22, 0.12), vec3(0.57, 0.34, 0.20), strata * 0.5 + 0.5) + fine;
	ROUGHNESS = 0.95;

	MESH_BLEND = 0.2;
}
