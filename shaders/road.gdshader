shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Wet city asphalt: worn surface, painted lane markings, kerbside gutter grime
// and puddles that turn the street into a mirror for the orange key light.

group_uniforms Surface;
uniform sampler2D asphalt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float uv_scale : hint_range(0.01, 4.0) = 0.28;
uniform vec4 asphalt_tint : source_color = vec4(0.72, 0.72, 0.75, 1.0);

group_uniforms Markings;
uniform vec4 paint_color : source_color = vec4(0.82, 0.80, 0.74, 1.0);
uniform float lane_width : hint_range(1.0, 12.0) = 3.6;
uniform float stripe_width : hint_range(0.02, 0.6) = 0.12;
uniform float dash_length : hint_range(0.5, 8.0) = 2.4;
uniform float paint_wear : hint_range(0.0, 1.0) = 0.5;

group_uniforms Wetness;
uniform float wetness : hint_range(0.0, 1.0) = 0.55;
uniform float puddle_coverage : hint_range(0.0, 1.0) = 0.35;
uniform vec4 wet_tint : source_color = vec4(0.42, 0.43, 0.47, 1.0);

varying vec3 v_world_pos;

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 p = v_world_pos;
	vec2 uv = p.xz * uv_scale;

	vec3 base = texture(asphalt_albedo, uv).rgb * asphalt_tint.rgb;
	float rough = texture(asphalt_rough, uv).r;
	vec3 nrm = texture(asphalt_normal, uv).rgb;

	// --- lane markings -----------------------------------------------------
	float lane = abs(fract(p.x / lane_width + 0.5) - 0.5) * lane_width;
	float dash = step(0.5, fract(p.z / dash_length));
	float stripe = (1.0 - smoothstep(stripe_width * 0.5, stripe_width, lane)) * dash;
	float wear = smoothstep(0.35, 0.85, vnoise(p * 3.5));
	stripe *= mix(1.0, wear, paint_wear);
	base = mix(base, paint_color.rgb, stripe);
	rough = mix(rough, 0.62, stripe);

	// --- grime and tyre tracks --------------------------------------------
	float tracks = 1.0 - smoothstep(0.25, 0.9, abs(fract(p.x / lane_width) - 0.5) * 2.0);
	base *= mix(1.0, 0.85, tracks * 0.6);
	float grime = vnoise(p * 0.22);
	base *= 0.8 + 0.35 * grime;

	// --- puddles -----------------------------------------------------------
	float puddle_noise = vnoise(p * 0.28) * 0.65 + vnoise(p * 1.1) * 0.35;
	float puddle = smoothstep(1.0 - puddle_coverage, 1.05 - puddle_coverage * 0.6, puddle_noise) * wetness;

	ALBEDO = mix(base * mix(1.0, 0.6, wetness * 0.6), base * wet_tint.rgb * 0.55, puddle);
	ROUGHNESS = clamp(mix(rough * mix(1.0, 0.72, wetness), 0.025, puddle), 0.02, 1.0);
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 0.95, puddle);
	NORMAL_MAP = mix(nrm, vec3(0.5, 0.5, 1.0), puddle * 0.9);
	NORMAL_MAP_DEPTH = mix(1.2, 0.1, puddle);
}
