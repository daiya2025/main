shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Hero armour plating.
//
// Layered like a real automotive finish: a metal flake basecoat, a pigmented
// orange layer, then a clear coat. Edges expose bare metal where the coat has
// been ground away, which is what stops procedural armour looking like plastic.

group_uniforms Paint;
uniform vec4 paint_color : source_color = vec4(0.905, 0.318, 0.031, 1.0);
uniform vec4 paint_shadow : source_color = vec4(0.312, 0.086, 0.020, 1.0);
// Rear plates drop to gunmetal so the character reads front/back at a glance;
// front_split 0 disables the split (used by the dark and trim variants).
uniform vec4 back_paint : source_color = vec4(0.13, 0.14, 0.17, 1.0);
uniform vec4 back_shadow : source_color = vec4(0.05, 0.055, 0.07, 1.0);
uniform float front_split : hint_range(0.0, 1.0) = 1.0;
uniform vec4 flake_color : source_color = vec4(1.0, 0.72, 0.35, 1.0);
uniform float flake_amount : hint_range(0.0, 1.0) = 0.35;
uniform float paint_roughness : hint_range(0.0, 1.0) = 0.28;

group_uniforms Metal;
uniform vec4 bare_metal : source_color = vec4(0.62, 0.60, 0.58, 1.0);
uniform float edge_wear : hint_range(0.0, 1.0) = 0.45;
uniform float scratch_amount : hint_range(0.0, 1.0) = 0.35;

group_uniforms Clearcoat;
uniform float clearcoat_amount : hint_range(0.0, 1.0) = 0.85;
uniform float clearcoat_roughness : hint_range(0.0, 1.0) = 0.06;

group_uniforms Energy;
uniform vec4 energy_color : source_color = vec4(1.0, 0.48, 0.10, 1.0);
uniform float energy_emission : hint_range(0.0, 40.0) = 5.5;
uniform float energy_width : hint_range(0.001, 0.2) = 0.018;
uniform float charge : hint_range(0.0, 1.0) = 0.7;
uniform float pulse_speed : hint_range(0.0, 12.0) = 2.4;

group_uniforms Detail;
uniform sampler2D micro_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float micro_scale : hint_range(1.0, 300.0) = 64.0;
uniform float micro_depth : hint_range(0.0, 2.0) = 0.35;
uniform float cavity_strength : hint_range(0.0, 2.0) = 1.0;

varying vec3 v_object_pos;
varying vec3 v_object_normal;
varying float v_cavity;

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
	v_object_pos = VERTEX;
	v_object_normal = NORMAL;
	v_cavity = mix(1.0, COLOR.r, cavity_strength);
}

void fragment() {
	vec3 p = v_object_pos;

	// Convex edges wear first: the baked cavity term is low in creases and
	// high on ridges, and the fresnel term finds the silhouette.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.4);
	float ridge = smoothstep(0.92, 1.0, v_cavity);
	float scratches = smoothstep(0.62, 0.95, vnoise(p * vec3(140.0, 18.0, 140.0)));
	float wear = clamp(ridge * edge_wear + scratches * scratch_amount * 0.5 + fresnel * 0.15, 0.0, 1.0);

	// Metallic flake sparkle in the basecoat.
	float flake = smoothstep(0.72, 1.0, vnoise(p * 420.0));

	// Character space faces +Z; ease across the sides so the seam sits on the
	// lateral line like a two-tone racing livery.
	float front = smoothstep(-0.045, 0.055, v_object_pos.z);
	front = mix(1.0, front, front_split);
	vec3 base_col = mix(back_paint.rgb, paint_color.rgb, front);
	vec3 shadow_col = mix(back_shadow.rgb, paint_shadow.rgb, front);
	vec3 paint = mix(shadow_col, base_col, clamp(v_cavity, 0.0, 1.0));
	paint = mix(paint, flake_color.rgb, flake * flake_amount);

	ALBEDO = mix(paint, bare_metal.rgb, wear);
	METALLIC = mix(0.15, 1.0, wear);
	ROUGHNESS = clamp(mix(paint_roughness, 0.42, wear) + scratches * 0.12, 0.03, 1.0);
	SPECULAR = 0.5;

	NORMAL_MAP = texture(micro_normal, UV * micro_scale).rgb;
	NORMAL_MAP_DEPTH = micro_depth;

	CLEARCOAT = clearcoat_amount * (1.0 - wear * 0.8);
	CLEARCOAT_ROUGHNESS = clearcoat_roughness;

	// Energy channels routed along the plate seams.
	float channel = abs(fract(p.y * 4.4 + p.x * 0.6) - 0.5) * 2.0;
	float channel_mask = 1.0 - smoothstep(energy_width, energy_width * 2.6, channel);
	channel_mask *= smoothstep(0.25, 0.75, v_cavity);
	float pulse = 0.6 + 0.4 * sin(TIME * pulse_speed - p.y * 8.0);
	EMISSION = energy_color.rgb * channel_mask * energy_emission * charge * pulse;

	AO = v_cavity;
	AO_LIGHT_AFFECT = 0.8;
}
