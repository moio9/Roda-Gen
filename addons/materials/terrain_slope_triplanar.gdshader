shader_type spatial;
render_mode cull_back;

// Five slope layers, projected in world space. Mesh UVs and tangents are not required.
group_uniforms mapping;
uniform float triplanar_scale : hint_range(0.001, 2.0) = 0.05;
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 4.0;
uniform float resolution : hint_range(0.01, 100.0) = 1.0;
uniform float normal_depth : hint_range(0.0, 2.0) = 0.3;

group_uniforms options;
uniform bool use_height_blending = true;
uniform float height_blend_strength : hint_range(0.0, 1.0) = 0.5;

group_uniforms dynamic_settings;
uniform bool use_dynamic_scale = true;
uniform float dynamic_distance : hint_range(0.0, 500.0) = 20.0;
uniform float dynamic_blend_range : hint_range(0.0, 50.0) = 10.0;
uniform float dynamic_scale_factor : hint_range(0.01, 10.0) = 0.1;

group_uniforms albedo;
uniform sampler2D texture1 : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float albedo_strength_1 : hint_range(0.0, 5.0) = 1.0;
uniform float roughness_1 : hint_range(0.0, 1.0) = 0.9;
uniform sampler2D texture2 : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float albedo_strength_2 : hint_range(0.0, 5.0) = 1.0;
uniform float roughness_2 : hint_range(0.0, 1.0) = 0.6;
uniform sampler2D texture3 : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float albedo_strength_3 : hint_range(0.0, 5.0) = 1.0;
uniform float roughness_3 : hint_range(0.0, 1.0) = 0.4;
uniform sampler2D texture4 : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float albedo_strength_4 : hint_range(0.0, 5.0) = 1.0;
uniform float roughness_4 : hint_range(0.0, 1.0) = 0.3;
uniform sampler2D texture5 : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float albedo_strength_5 : hint_range(0.0, 5.0) = 1.0;
uniform float roughness_5 : hint_range(0.0, 1.0) = 0.1;

group_uniforms normal;
uniform sampler2D normal1 : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float normal_strength_1 : hint_range(-16.0, 16.0) = 1.0;
uniform sampler2D normal2 : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float normal_strength_2 : hint_range(-16.0, 16.0) = 1.0;
uniform sampler2D normal3 : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float normal_strength_3 : hint_range(-16.0, 16.0) = 1.0;
uniform sampler2D normal4 : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float normal_strength_4 : hint_range(-16.0, 16.0) = 1.0;
uniform sampler2D normal5 : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float normal_strength_5 : hint_range(-16.0, 16.0) = 1.0;

group_uniforms depth;
uniform sampler2D depth1 : hint_default_black, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D depth2 : hint_default_black, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D depth3 : hint_default_black, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D depth4 : hint_default_black, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D depth5 : hint_default_black, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float depth_scale_1 : hint_range(-1.0, 1.0) = 0.05;
uniform float depth_scale_2 : hint_range(-1.0, 1.0) = 0.05;
uniform float depth_scale_3 : hint_range(-1.0, 1.0) = 0.05;
uniform float depth_scale_4 : hint_range(-1.0, 1.0) = 0.05;
uniform float depth_scale_5 : hint_range(-1.0, 1.0) = 0.05;
uniform int depth_min_layers : hint_range(1, 64) = 8;
uniform int depth_max_layers : hint_range(1, 64) = 32;
uniform vec2 depth_flip = vec2(1.0);

group_uniforms uv;
uniform float uv1_level1 : hint_range(0.0001, 100.0) = 1.0;
uniform float uv1_level2 : hint_range(0.0001, 100.0) = 1.0;
uniform float uv1_level3 : hint_range(0.0001, 100.0) = 1.0;
uniform float uv1_level4 : hint_range(0.0001, 100.0) = 1.0;
uniform float uv1_level5 : hint_range(0.0001, 100.0) = 1.0;

group_uniforms levels;
uniform float blend_width : hint_range(0.001, 0.5) = 0.1;
uniform float level1 : hint_range(0.0, 1.0) = 0.9;
uniform float level2 : hint_range(0.0, 1.0) = 0.7;
uniform float level3 : hint_range(0.0, 1.0) = 0.5;
uniform float level4 : hint_range(0.0, 1.0) = 0.3;

varying vec3 terrain_world_position;
varying vec3 terrain_world_normal;

struct TerrainSample {
	vec3 color;
	vec3 normal;
	float height;
};

void vertex() {
	terrain_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	terrain_world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

vec2 parallax_uv(sampler2D depth_tex, vec2 uv, vec3 view_dir, float amount) {
	if (abs(amount) < 0.000001) {
		return uv;
	}
	float angle = clamp(abs(view_dir.z), 0.1, 1.0);
	float layers = clamp(mix(float(depth_max_layers), float(depth_min_layers), angle), 1.0, 64.0);
	float step_depth = 1.0 / layers;
	vec2 delta = view_dir.xy * depth_flip * amount / layers;
	vec2 offset = vec2(0.0);
	float current_depth = 0.0;
	float height = texture(depth_tex, uv).r;
	if (height <= 0.0) {
		return uv;
	}
	for (int i = 0; i < 64; i++) {
		if (current_depth >= height) { break; }
		offset -= delta;
		current_depth += step_depth;
		height = texture(depth_tex, uv + offset).r;
	}
	float after_depth = height - current_depth;
	float before_depth = texture(depth_tex, uv + offset + delta).r - current_depth + step_depth;
	float denominator = after_depth - before_depth;
	float weight = abs(denominator) > 0.000001 ? clamp(after_depth / denominator, 0.0, 1.0) : 0.0;
	return uv + mix(offset, offset + delta, weight);
}

TerrainSample sample_projection(sampler2D color_tex, sampler2D normal_tex, sampler2D depth_tex,
		vec2 uv, vec3 view_dir, float fade, float height_scale, float normal_strength) {
	vec2 near_uv = uv;
	if (fade < 1.0) {
		near_uv = parallax_uv(depth_tex, uv, view_dir, height_scale);
	}
	TerrainSample result;
	result.color = texture(color_tex, near_uv).rgb;
	result.normal = texture(normal_tex, near_uv).rgb * 2.0 - 1.0;
	result.height = texture(depth_tex, near_uv).r;
	if (fade > 0.0) {
		vec2 far_uv = uv * dynamic_scale_factor;
		result.color = mix(result.color, texture(color_tex, far_uv).rgb, fade);
		result.normal = mix(result.normal, texture(normal_tex, far_uv).rgb * 2.0 - 1.0, fade);
		result.height = mix(result.height, texture(depth_tex, far_uv).r, fade);
	}
	result.normal.xy *= normal_strength * normal_depth;
	result.normal.z = max(abs(result.normal.z), 0.0001);
	result.normal = normalize(result.normal);
	return result;
}

TerrainSample sample_layer(sampler2D color_tex, sampler2D normal_tex, sampler2D depth_tex,
		vec3 p, vec3 n, vec3 view_dir, vec3 weights, float fade,
		float uv_scale, float height_scale, float normal_strength, float color_strength) {
	p *= uv_scale;
	vec3 facing = mix(vec3(-1.0), vec3(1.0), step(vec3(0.0), n));
	TerrainSample result;
	result.color = vec3(0.0);
	result.normal = vec3(0.0);
	result.height = 0.0;
	if (weights.x > 0.0) {
		TerrainSample axis = sample_projection(color_tex, normal_tex, depth_tex, p.zy,
			vec3(view_dir.zy, view_dir.x * facing.x), fade, height_scale, normal_strength);
		// Whiteout blending: a neutral normal texture reproduces the surface normal.
		vec3 mapped = vec3(axis.normal.xy + n.zy, axis.normal.z * abs(n.x));
		result.normal += normalize(vec3(mapped.z * facing.x, mapped.y, mapped.x)) * weights.x;
		result.color += axis.color * weights.x;
		result.height += axis.height * weights.x;
	}
	if (weights.y > 0.0) {
		TerrainSample axis = sample_projection(color_tex, normal_tex, depth_tex, p.xz,
			vec3(view_dir.xz, view_dir.y * facing.y), fade, height_scale, normal_strength);
		vec3 mapped = vec3(axis.normal.xy + n.xz, axis.normal.z * abs(n.y));
		result.normal += normalize(vec3(mapped.x, mapped.z * facing.y, mapped.y)) * weights.y;
		result.color += axis.color * weights.y;
		result.height += axis.height * weights.y;
	}
	if (weights.z > 0.0) {
		TerrainSample axis = sample_projection(color_tex, normal_tex, depth_tex, p.xy,
			vec3(view_dir.xy, view_dir.z * facing.z), fade, height_scale, normal_strength);
		vec3 mapped = vec3(axis.normal.xy + n.xy, axis.normal.z * abs(n.z));
		result.normal += normalize(vec3(mapped.xy, mapped.z * facing.z)) * weights.z;
		result.color += axis.color * weights.z;
		result.height += axis.height * weights.z;
	}
	result.color *= color_strength;
	result.normal = normalize(result.normal);
	return result;
}

void fragment() {
	vec3 n = normalize(terrain_world_normal);
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - terrain_world_position);
	vec3 weights = pow(abs(n), vec3(triplanar_sharpness));
	// Smoothed normals at a cliff cap can point away from the actual triangle.
	// Suppress projections grazing that face so they cannot draw stretched streaks.
	vec3 face_normal = normalize(cross(dFdx(terrain_world_position), dFdy(terrain_world_position)));
	weights *= smoothstep(vec3(0.2), vec3(0.5), abs(face_normal));
	if (dot(weights, vec3(1.0)) < 0.000001) {
		weights = pow(abs(face_normal), vec3(triplanar_sharpness)) * smoothstep(vec3(0.2), vec3(0.5), abs(face_normal));
	}
	weights /= max(dot(weights, vec3(1.0)), 0.000001);
	// Do not spend parallax samples on almost edge-on projections.
	weights *= step(vec3(0.005), weights);
	weights /= dot(weights, vec3(1.0));
	float fade = use_dynamic_scale ? smoothstep(dynamic_distance,
		dynamic_distance + max(dynamic_blend_range, 0.001), length(VERTEX)) : 0.0;
	vec3 p = terrain_world_position * (triplanar_scale * resolution);
	float slope = clamp(n.y, 0.0, 1.0);
	float width = max(blend_width, 0.001);
	float b1 = smoothstep(level1 - width, level1 + width, slope);
	float b2 = smoothstep(level2 - width, level2 + width, slope) * (1.0 - b1);
	float b3 = smoothstep(level3 - width, level3 + width, slope) * (1.0 - b1 - b2);
	float b4 = smoothstep(level4 - width, level4 + width, slope) * (1.0 - b1 - b2 - b3);
	float b5 = max(1.0 - b1 - b2 - b3 - b4, 0.0);
	TerrainSample neutral;
	neutral.color = vec3(0.0);
	neutral.normal = n;
	neutral.height = 0.0;
	TerrainSample s1 = neutral;
	TerrainSample s2 = neutral;
	TerrainSample s3 = neutral;
	TerrainSample s4 = neutral;
	TerrainSample s5 = neutral;
	if (b1 > 0.0) { s1 = sample_layer(texture1, normal1, depth1, p, n, view_dir, weights, fade, uv1_level1, depth_scale_1, normal_strength_1, albedo_strength_1); }
	if (b2 > 0.0) { s2 = sample_layer(texture2, normal2, depth2, p, n, view_dir, weights, fade, uv1_level2, depth_scale_2, normal_strength_2, albedo_strength_2); }
	if (b3 > 0.0) { s3 = sample_layer(texture3, normal3, depth3, p, n, view_dir, weights, fade, uv1_level3, depth_scale_3, normal_strength_3, albedo_strength_3); }
	if (b4 > 0.0) { s4 = sample_layer(texture4, normal4, depth4, p, n, view_dir, weights, fade, uv1_level4, depth_scale_4, normal_strength_4, albedo_strength_4); }
	if (b5 > 0.0) { s5 = sample_layer(texture5, normal5, depth5, p, n, view_dir, weights, fade, uv1_level5, depth_scale_5, normal_strength_5, albedo_strength_5); }
	if (use_height_blending) {
		float base = 1.0 - height_blend_strength;
		vec4 h = vec4(b1, b2, b3, b4) * (vec4(s1.height, s2.height, s3.height, s4.height) + vec4(base));
		float h5 = b5 * (s5.height + base);
		float total = dot(h, vec4(1.0)) + h5;
		if (total > 0.000001) {
			b1 = h.x / total; b2 = h.y / total; b3 = h.z / total; b4 = h.w / total; b5 = h5 / total;
		}
	}
	ALBEDO = s1.color * b1 + s2.color * b2 + s3.color * b3 + s4.color * b4 + s5.color * b5;
	vec3 mapped_normal = normalize(s1.normal * b1 + s2.normal * b2 + s3.normal * b3 + s4.normal * b4 + s5.normal * b5);
	NORMAL = normalize(mat3(VIEW_MATRIX) * mapped_normal);
	ROUGHNESS = clamp(roughness_1 * b1 + roughness_2 * b2 + roughness_3 * b3 + roughness_4 * b4 + roughness_5 * b5, 0.0, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.2;
}
