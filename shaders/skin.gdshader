shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Human skin.
//
// Skin does not read as skin because of its colour, it reads as skin because of
// three things: light entering and scattering back out (SSS), a dual specular
// lobe (thin oil film over a rough dermis), and micro-detail that keeps the
// highlight broken up. All three are here.

group_uniforms Base;
uniform vec4 skin_tone : source_color = vec4(0.803, 0.607, 0.503, 1.0);
uniform vec4 shadow_tone : source_color = vec4(0.505, 0.283, 0.240, 1.0);
uniform vec4 blood_tone : source_color = vec4(0.760, 0.318, 0.278, 1.0);
uniform sampler2D albedo_detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float albedo_detail_amount : hint_range(0.0, 1.0) = 0.35;
uniform float detail_uv_scale : hint_range(1.0, 64.0) = 12.0;

group_uniforms Micro;
uniform sampler2D pore_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float pore_scale : hint_range(1.0, 200.0) = 46.0;
uniform float pore_strength : hint_range(0.0, 3.0) = 0.85;
uniform float micro_roughness : hint_range(0.0, 1.0) = 0.055;

group_uniforms Specular;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.52;
uniform float roughness_variation : hint_range(0.0, 1.0) = 0.22;
uniform float specular_level : hint_range(0.0, 1.0) = 0.30;
uniform float sheen_strength : hint_range(0.0, 2.0) = 0.16;

group_uniforms Subsurface;
uniform float sss_strength : hint_range(0.0, 1.0) = 0.62;
uniform vec4 sss_transmittance : source_color = vec4(0.85, 0.34, 0.25, 1.0);
uniform float sss_depth : hint_range(0.01, 8.0) = 0.14;
uniform float sss_boost : hint_range(0.0, 1.0) = 0.35;

group_uniforms Ambient;
uniform float cavity_strength : hint_range(0.0, 2.0) = 1.0;

varying vec3 v_object_pos;
varying float v_cavity;

void vertex() {
	v_object_pos = VERTEX;
	// Vertex colour carries the baked cavity term from the generator.
	v_cavity = mix(1.0, COLOR.r, cavity_strength);
}

void fragment() {
	vec2 detail_uv = UV * detail_uv_scale;

	// --- albedo -----------------------------------------------------------
	vec3 detail = texture(albedo_detail, detail_uv).rgb;
	float mottle = detail.r;
	vec3 base = mix(skin_tone.rgb, shadow_tone.rgb, (1.0 - v_cavity) * 0.85);
	// Blood pools where the surface is thin and where cavities trap light.
	float blood_mask = smoothstep(0.35, 0.9, mottle) * 0.45 + (1.0 - v_cavity) * 0.35;
	base = mix(base, blood_tone.rgb, clamp(blood_mask, 0.0, 0.65) * 0.5);
	base = mix(base, base * (0.75 + 0.5 * mottle), albedo_detail_amount);
	ALBEDO = base;

	// --- micro normal -----------------------------------------------------
	vec3 pores = texture(pore_normal, UV * pore_scale).rgb;
	NORMAL_MAP = pores;
	NORMAL_MAP_DEPTH = pore_strength;

	// --- specular ---------------------------------------------------------
	// Oily T-zone vs. drier cheeks, driven by the same mottle so the highlight
	// never looks uniform.
	float rough = roughness_base + (mottle - 0.5) * roughness_variation;
	rough -= micro_roughness * (1.0 - v_cavity);
	ROUGHNESS = clamp(rough, 0.12, 0.95);
	SPECULAR = specular_level;
	METALLIC = 0.0;

	// Peach fuzz: a tight forward-scattering rim that shows up on silhouettes.
	// Peach fuzz: a tight, mostly-albedo-tinted rim. Kept subtle — an untinted
	// rim under several lights stacks to pure white and reads as plastic.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	RIM = sheen_strength * fresnel;
	RIM_TINT = 0.85;

	// --- subsurface -------------------------------------------------------
	SSS_STRENGTH = sss_strength * mix(0.7, 1.0, v_cavity);
	SSS_TRANSMITTANCE_COLOR = sss_transmittance;
	SSS_TRANSMITTANCE_DEPTH = sss_depth;
	SSS_TRANSMITTANCE_BOOST = sss_boost;

	AO = v_cavity;
	AO_LIGHT_AFFECT = 0.65;
}
