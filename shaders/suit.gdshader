shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// DIGIHARIMAN's under-suit: a matte technical weave with a retro-reflective
// sheen, orange piping along the panel seams and energy channels that light up
// as the suit charges.

group_uniforms Fabric;
uniform vec4 fabric_color : source_color = vec4(0.045, 0.047, 0.055, 1.0);
uniform vec4 panel_color : source_color = vec4(0.086, 0.090, 0.102, 1.0);
uniform sampler2D weave_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float weave_scale : hint_range(1.0, 400.0) = 120.0;
uniform float weave_depth : hint_range(0.0, 3.0) = 1.15;
uniform float fabric_roughness : hint_range(0.0, 1.0) = 0.74;

group_uniforms Sheen;
uniform vec4 sheen_color : source_color = vec4(0.55, 0.60, 0.70, 1.0);
uniform float sheen_strength : hint_range(0.0, 3.0) = 0.85;

group_uniforms Accent;
uniform vec4 accent_color : source_color = vec4(1.0, 0.42, 0.06, 1.0);
uniform float accent_emission : hint_range(0.0, 24.0) = 3.0;
uniform float accent_width : hint_range(0.001, 0.2) = 0.022;
uniform float charge : hint_range(0.0, 1.0) = 0.55;
uniform float pulse_speed : hint_range(0.0, 8.0) = 1.6;

group_uniforms Wear;
uniform float cavity_strength : hint_range(0.0, 2.0) = 1.0;
uniform float dirt_amount : hint_range(0.0, 1.0) = 0.25;

varying vec3 v_object_pos;
varying float v_cavity;

// Cheap value noise, enough for dirt breakup on a fabric surface.
float hash13(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1, 0, 0));
	float n010 = hash13(i + vec3(0, 1, 0));
	float n110 = hash13(i + vec3(1, 1, 0));
	float n001 = hash13(i + vec3(0, 0, 1));
	float n101 = hash13(i + vec3(1, 0, 1));
	float n011 = hash13(i + vec3(0, 1, 1));
	float n111 = hash13(i + vec3(1, 1, 1));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

void vertex() {
	v_object_pos = VERTEX;
	v_cavity = mix(1.0, COLOR.r, cavity_strength);
}

void fragment() {
	vec3 p = v_object_pos;

	// --- panel layout -----------------------------------------------------
	// Horizontal bands plus a vertical centre seam, in object space so the
	// pattern follows the body rather than the UV distortion.
	float band = abs(fract(p.y * 3.1) - 0.5) * 2.0;
	float centre = abs(p.x);
	float seam = min(band, centre * 6.0);
	float seam_mask = 1.0 - smoothstep(accent_width, accent_width * 2.4, seam);

	// A second, diagonal accent line across the chest and thighs.
	float diagonal = abs(fract((p.y * 1.4 + abs(p.x) * 2.2)) - 0.5) * 2.0;
	float diagonal_mask = 1.0 - smoothstep(accent_width * 0.8, accent_width * 2.0, diagonal);
	float accent_mask = clamp(seam_mask + diagonal_mask * 0.75, 0.0, 1.0);

	float panel = step(0.5, fract(p.y * 1.55 + 0.25));
	vec3 base = mix(fabric_color.rgb, panel_color.rgb, panel);

	// --- dirt / wear ------------------------------------------------------
	float grime = vnoise(p * 9.0) * 0.6 + vnoise(p * 31.0) * 0.4;
	base *= mix(1.0, 0.62 + 0.38 * grime, dirt_amount);
	base *= mix(0.55, 1.0, v_cavity);

	ALBEDO = mix(base, accent_color.rgb * 0.35, accent_mask);

	// --- weave ------------------------------------------------------------
	NORMAL_MAP = texture(weave_normal, UV * weave_scale).rgb;
	NORMAL_MAP_DEPTH = weave_depth * (1.0 - accent_mask * 0.6);

	ROUGHNESS = clamp(fabric_roughness - accent_mask * 0.35 + (grime - 0.5) * 0.12, 0.1, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.35;

	// Retro-reflective sheen along the silhouette — the tell of technical
	// fabric under a strong key light.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.2);
	RIM = sheen_strength * fresnel;
	RIM_TINT = 0.25;
	BACKLIGHT = sheen_color.rgb * fresnel * 0.12;

	// --- energy channels --------------------------------------------------
	float pulse = 0.65 + 0.35 * sin(TIME * pulse_speed - p.y * 6.0);
	EMISSION = accent_color.rgb * accent_mask * accent_emission * charge * pulse;

	AO = v_cavity;
	AO_LIGHT_AFFECT = 0.7;
}
