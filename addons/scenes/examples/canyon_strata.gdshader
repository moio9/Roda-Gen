shader_type spatial;
uniform vec4 dark_rock : source_color = vec4(0.32, 0.18, 0.105, 1.0);
uniform vec4 light_rock : source_color = vec4(0.57, 0.37, 0.23, 1.0);
uniform float layer_spacing : hint_range(0.5, 20.0) = 3.5;
uniform float grain_scale : hint_range(0.1, 10.0) = 2.8;
uniform float bump_strength : hint_range(0.0, 1.0) = 0.3;
varying vec3 world_position;

float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float rock_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(cell), hash3(cell + vec3(1,0,0)), f.x),
		mix(hash3(cell + vec3(0,1,0)), hash3(cell + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash3(cell + vec3(0,0,1)), hash3(cell + vec3(1,0,1)), f.x),
		mix(hash3(cell + vec3(0,1,1)), hash3(cell + vec3(1,1,1)), f.x), f.y), f.z);
}

float relief(vec3 p) {
	float grain = rock_noise(p * grain_scale);
	float seams = sin(p.y * 6.283185 / layer_spacing + rock_noise(p * 0.12) * 2.0);
	return grain * 0.16 + seams * 0.10;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 p = world_position;
	float broad = rock_noise(p * 0.12);
	float strata = sin(p.y * 6.283185 / layer_spacing + broad * 2.0);
	float grain = rock_noise(p * grain_scale);
	float patches = rock_noise(p * 0.55);
	float footprint = max(length(dFdx(p)), length(dFdy(p))) * grain_scale;
	float fine_visibility = 1.0 - smoothstep(0.25, 1.2, footprint);
	grain = mix(0.5, grain, fine_visibility);
	ALBEDO = mix(dark_rock.rgb, light_rock.rgb,
		clamp(0.45 + strata * 0.17 + (broad - 0.5) * 0.5 + (patches - 0.5) * 0.3, 0.0, 1.0));
	ALBEDO *= 0.86 + grain * 0.28;
	// World-space relief keeps the same scale on horizontal ground and cliffs.
	float e = 0.035;
	float h = relief(p);
	vec3 gradient = vec3(relief(p + vec3(e,0,0)), relief(p + vec3(0,e,0)), relief(p + vec3(0,0,e))) - vec3(h);
	gradient = mat3(VIEW_MATRIX) * (gradient / e);
	NORMAL = normalize(NORMAL - (gradient - NORMAL * dot(gradient, NORMAL)) * bump_strength * fine_visibility);
	ROUGHNESS = 0.95;

	MESH_BLEND = 1.2;
}
