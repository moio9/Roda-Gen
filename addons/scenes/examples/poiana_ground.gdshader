shader_type spatial;
render_mode cull_disabled;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

float noise(vec2 p) {
	return sin(p.x * 0.041 + sin(p.y * 0.023)) * cos(p.y * 0.037 + sin(p.x * 0.019));
}

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	return length(p - a - ab * clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0));
}

void fragment() {
	float patches = noise(world_position.xz) * 0.5 + 0.5;
	vec3 grass = mix(vec3(0.035, 0.07, 0.027), vec3(0.075, 0.115, 0.045), patches);
	float stadion = segment_distance(world_position.xz, vec2(92.0, 280.0), vec2(285.0, 326.0)) - 20.0;
	float bradul = segment_distance(world_position.xz, vec2(92.0, 190.0), vec2(270.0, 139.0)) - 15.0;
	float clearing = 1.0 - smoothstep(-1.0, 2.0, min(stadion, bradul));
	grass = mix(grass, vec3(0.16, 0.19, 0.07), clearing);
	float rock = smoothstep(0.2, 0.65, 1.0 - abs(world_normal.y));
	ALBEDO = mix(grass, vec3(0.42, 0.43, 0.38), rock);
	ROUGHNESS = 0.95;
}
