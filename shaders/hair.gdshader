shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Hair with a Kajiya-Kay style anisotropic highlight.
//
// Hair is one of the few surfaces where an isotropic GGX lobe is instantly
// wrong: the highlight has to smear along the strand direction, and there have
// to be two of them (a sharp white primary and a soft, tinted secondary).

uniform vec4 hair_color : source_color = vec4(0.055, 0.040, 0.032, 1.0);
uniform vec4 hair_tip : source_color = vec4(0.140, 0.090, 0.055, 1.0);
uniform vec4 specular_tint : source_color = vec4(0.75, 0.60, 0.42, 1.0);
uniform float roughness_primary : hint_range(0.0, 1.0) = 0.28;
uniform float anisotropy_amount : hint_range(-1.0, 1.0) = 0.85;
uniform float strand_scale : hint_range(1.0, 400.0) = 180.0;
uniform float strand_depth : hint_range(0.0, 3.0) = 0.9;
uniform float root_shadow : hint_range(0.0, 1.0) = 0.55;

varying float v_length_t;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(41.7, 289.1))) * 43758.5453);
}

void vertex() {
	// UV.y runs root -> tip along every strand cluster.
	v_length_t = UV.y;
}

void fragment() {
	float strand = hash21(vec2(floor(UV.x * strand_scale), 0.0));
	vec3 base = mix(hair_color.rgb, hair_tip.rgb, pow(v_length_t, 1.5));
	base *= 0.75 + 0.5 * strand;
	base *= mix(1.0 - root_shadow, 1.0, smoothstep(0.0, 0.35, v_length_t));

	ALBEDO = base;
	METALLIC = 0.0;
	ROUGHNESS = roughness_primary + strand * 0.12;
	SPECULAR = 0.6;

	// Anisotropy smears the highlight along U, which is the strand direction.
	ANISOTROPY = anisotropy_amount;
	ANISOTROPY_FLOW = vec2(1.0, 0.0);

	// Secondary, tinted lobe from light passing through the strand.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	RIM = 0.6 * fres;
	RIM_TINT = 0.2;
	BACKLIGHT = specular_tint.rgb * 0.18;

	// Micro strand normal so the cluster does not read as a solid shell.
	float ripple = sin(UV.x * strand_scale * 6.2831) * 0.5 + 0.5;
	NORMAL_MAP = vec3(0.5 + (ripple - 0.5) * 0.9, 0.5, 1.0);
	NORMAL_MAP_DEPTH = strand_depth;
}
