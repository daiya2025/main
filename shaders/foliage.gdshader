shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx, depth_prepass_alpha;

// Foliage for the photoscanned trees and ferns: hierarchical wind (trunk sway,
// branch bend, leaf flutter) plus translucency, because backlit leaves are what
// sells vegetation at golden hour.

group_uniforms Surface;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.4;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.72;

group_uniforms Translucency;
uniform vec4 transmission : source_color = vec4(0.32, 0.52, 0.16, 1.0);
uniform float transmission_strength : hint_range(0.0, 3.0) = 1.1;

group_uniforms Wind;
uniform float wind_strength : hint_range(0.0, 3.0) = 0.5;
uniform float wind_speed : hint_range(0.0, 8.0) = 1.1;
uniform vec2 wind_direction = vec2(1.0, 0.35);
uniform float trunk_stiffness : hint_range(0.0, 8.0) = 2.4;
uniform float flutter_scale : hint_range(0.1, 20.0) = 6.0;

varying float v_ao;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 dir = normalize(wind_direction + 0.0001);
	float phase = world.x * 0.35 + world.z * 0.27;

	// Height above the instance's origin drives how much the branch bends.
	float h = max(VERTEX.y, 0.0);
	float sway = sin(TIME * wind_speed + phase) * 0.5 + sin(TIME * wind_speed * 1.7 + phase * 2.3) * 0.5;
	float bend = pow(h, trunk_stiffness) * 0.03 * wind_strength;
	// Leaf-scale flutter, using vertex colour alpha as the "leaf mask" when the
	// source model provides one (defaults to 1.0 and simply flutters more).
	float flutter = sin(TIME * wind_speed * 4.3 + (world.x + world.y + world.z) * flutter_scale);
	float leaf_mask = COLOR.a;

	VERTEX.xz += dir * (sway * bend + flutter * 0.012 * wind_strength * leaf_mask * h);
	VERTEX.y -= abs(sway) * bend * 0.25;

	v_ao = mix(0.55, 1.0, clamp(h * 0.35, 0.0, 1.0)) * COLOR.r;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	ALBEDO = tex.rgb * tint.rgb;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;

	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 0.8;

	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	SPECULAR = 0.35;

	// Light coming through the leaf from behind.
	BACKLIGHT = transmission.rgb * transmission_strength * tex.rgb;
	AO = v_ao;
	AO_LIGHT_AFFECT = 0.5;
}
