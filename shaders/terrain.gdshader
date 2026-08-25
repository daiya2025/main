shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Three-layer world-space triplanar terrain with height-aware blending,
// slope-driven rock, and a wetness layer that fills the low ground.
//
// Height-aware blending matters: a linear cross-fade between two rock textures
// looks like a dissolve, while a height-weighted blend lets the pebbles of one
// layer poke through the other the way real ground does.

group_uniforms Layer0_Ground;
uniform sampler2D l0_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D l0_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D l0_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float l0_scale : hint_range(0.01, 4.0) = 0.35;

group_uniforms Layer1_Rock;
uniform sampler2D l1_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D l1_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D l1_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float l1_scale : hint_range(0.01, 4.0) = 0.18;

group_uniforms Layer2_Path;
uniform sampler2D l2_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D l2_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D l2_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float l2_scale : hint_range(0.01, 4.0) = 0.5;

group_uniforms Blending;
uniform float slope_start : hint_range(0.0, 1.0) = 0.62;
uniform float slope_end : hint_range(0.0, 1.0) = 0.88;
uniform float blend_sharpness : hint_range(0.5, 16.0) = 5.0;
uniform float macro_scale : hint_range(0.001, 0.5) = 0.014;
uniform float macro_contrast : hint_range(0.0, 1.0) = 0.5;
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 5.0;

group_uniforms Wetness;
uniform float wetness : hint_range(0.0, 1.0) = 0.25;
uniform float puddle_level : hint_range(-4.0, 8.0) = 0.06;
uniform vec4 wet_tint : source_color = vec4(0.55, 0.55, 0.58, 1.0);

group_uniforms Detail;
uniform float far_detail_fade : hint_range(1.0, 200.0) = 45.0;
uniform float normal_strength : hint_range(0.0, 3.0) = 1.2;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

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

vec3 triplanar_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(triplanar_sharpness));
	return w / max(w.x + w.y + w.z, 0.0001);
}

vec4 triplanar_sample(sampler2D tex, vec3 p, vec3 w, float scale) {
	return texture(tex, p.zy * scale) * w.x
		+ texture(tex, p.xz * scale) * w.y
		+ texture(tex, p.xy * scale) * w.z;
}

// Height-weighted blend: whichever layer is "taller" at this texel wins,
// softened by `sharpness`.
float height_blend(float ha, float hb, float t, float sharpness) {
	float a = ha * (1.0 - t);
	float b = hb * t;
	float m = max(a, b) - 1.0 / sharpness;
	float wa = max(a - m, 0.0);
	float wb = max(b - m, 0.0);
	return wb / max(wa + wb, 0.0001);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 w = triplanar_weights(v_world_normal);
	vec3 p = v_world_pos;

	vec4 a0 = triplanar_sample(l0_albedo, p, w, l0_scale);
	vec4 a1 = triplanar_sample(l1_albedo, p, w, l1_scale);
	vec4 a2 = triplanar_sample(l2_albedo, p, w, l2_scale);
	vec3 n0 = triplanar_sample(l0_normal, p, w, l0_scale).rgb;
	vec3 n1 = triplanar_sample(l1_normal, p, w, l1_scale).rgb;
	vec3 n2 = triplanar_sample(l2_normal, p, w, l2_scale).rgb;
	float r0 = triplanar_sample(l0_rough, p, w, l0_scale).r;
	float r1 = triplanar_sample(l1_rough, p, w, l1_scale).r;
	float r2 = triplanar_sample(l2_rough, p, w, l2_scale).r;

	// Luminance stands in for a height map when the source set has none.
	float h0 = dot(a0.rgb, vec3(0.299, 0.587, 0.114));
	float h1 = dot(a1.rgb, vec3(0.299, 0.587, 0.114));
	float h2 = dot(a2.rgb, vec3(0.299, 0.587, 0.114));

	// A large-scale noise breaks up the boundary so the terrain never shows a
	// mathematically clean transition line.
	float macro = vnoise(p * macro_scale) - 0.5;
	float slope = 1.0 - clamp(v_world_normal.y, 0.0, 1.0);
	float rock_t = smoothstep(1.0 - slope_end, 1.0 - slope_start, slope + macro * macro_contrast);
	float path_t = smoothstep(0.55, 0.85, vnoise(p * macro_scale * 3.1 + vec3(19.0)));
	path_t *= 1.0 - rock_t;

	float bg = height_blend(h0, h1, rock_t, blend_sharpness);
	vec3 albedo = mix(a0.rgb, a1.rgb, bg);
	vec3 nrm = mix(n0, n1, bg);
	float rough = mix(r0, r1, bg);
	float height = mix(h0, h1, bg);

	float pg = height_blend(height, h2, path_t, blend_sharpness);
	albedo = mix(albedo, a2.rgb, pg);
	nrm = mix(nrm, n2, pg);
	rough = mix(rough, r2, pg);

	// --- wetness ----------------------------------------------------------
	float puddle_noise = vnoise(p * 0.35) * 0.6 + vnoise(p * 1.4) * 0.4;
	float low_ground = 1.0 - smoothstep(puddle_level - 0.25, puddle_level + 0.45, p.y);
	float flatness = smoothstep(0.86, 0.99, v_world_normal.y);
	float puddle = clamp(wetness * 1.6 * low_ground * flatness * smoothstep(0.42, 0.72, puddle_noise), 0.0, 1.0);

	albedo *= mix(1.0, 0.55, wetness * 0.5 + puddle * 0.5);
	albedo = mix(albedo, albedo * wet_tint.rgb, puddle * 0.4);

	ALBEDO = albedo;
	ROUGHNESS = clamp(mix(rough, 0.04, puddle) * mix(1.0, 0.7, wetness), 0.02, 1.0);
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 0.85, puddle);

	// Fade the tangent-space detail out with distance to stop specular
	// aliasing on the horizon.
	float dist_fade = 1.0 - clamp(length(VERTEX) / far_detail_fade, 0.0, 1.0);
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), nrm, mix(0.35, 1.0, dist_fade) * (1.0 - puddle * 0.85));
	NORMAL_MAP_DEPTH = normal_strength;
}
