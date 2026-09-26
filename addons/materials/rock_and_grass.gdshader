shader_type spatial;

uniform vec4 grass_color : source_color = vec4(0.19, 0.26, 0.12, 1.0);
uniform vec4 rock_color : source_color = vec4(0.43, 0.32, 0.22, 1.0);
uniform float rock_slope_start : hint_range(0.0, 1.0) = 0.06;
uniform float rock_slope_end : hint_range(0.0, 1.0) = 0.3;
uniform float layer_spacing : hint_range(0.5, 20.0) = 3.5;
varying vec3 world_position;
varying vec3 world_normal;

float hash3(vec3 p) {
 p = fract(p * 0.1031);
 p += dot(p, p.yzx + 33.33);
 return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
 vec3 c = floor(p);
 vec3 f = fract(p);
 f = f * f * (3.0 - 2.0 * f);
 return mix(mix(mix(hash3(c), hash3(c + vec3(1,0,0)), f.x),
 mix(hash3(c + vec3(0,1,0)), hash3(c + vec3(1,1,0)), f.x), f.y),
 mix(mix(hash3(c + vec3(0,0,1)), hash3(c + vec3(1,0,1)), f.x),
 mix(hash3(c + vec3(0,1,1)), hash3(c + vec3(1,1,1)), f.x), f.y), f.z);
}

void vertex() {
 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
 float patches = noise3(world_position * 0.18);
 float slope = 1.0 - abs(normalize(world_normal).y);
 float rock = smoothstep(rock_slope_start, max(rock_slope_start + 0.001, rock_slope_end), slope);
 float strata = sin(world_position.y * 6.283185 / layer_spacing + patches * 1.4);
 vec3 stone = rock_color.rgb * (0.84 + strata * 0.11 + patches * 0.22);
 vec3 grass = grass_color.rgb * (0.8 + patches * 0.4);
 ALBEDO = mix(grass, stone, rock);
 ROUGHNESS = 0.95;
}
