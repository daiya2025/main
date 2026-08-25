shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded;

// Orange energy volume: visor glow, projectiles, impact bursts, thruster cores.
// Additive with a soft depth fade so it never shows a hard intersection edge.

uniform vec4 core_color : source_color = vec4(1.0, 0.78, 0.35, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.30, 0.02, 1.0);
uniform float intensity : hint_range(0.0, 40.0) = 8.0;
uniform float fresnel_power : hint_range(0.1, 8.0) = 2.4;
uniform float flow_speed : hint_range(0.0, 6.0) = 1.2;
uniform float flow_scale : hint_range(0.5, 40.0) = 6.0;
uniform float soft_fade : hint_range(0.01, 4.0) = 0.4;
uniform float alpha_scale : hint_range(0.0, 2.0) = 1.0;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

varying vec3 v_object_pos;

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
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	float flow = vnoise(v_object_pos * flow_scale + vec3(0.0, TIME * flow_speed, 0.0));
	flow = 0.55 + 0.45 * flow;

	vec3 color = mix(core_color.rgb, edge_color.rgb, clamp(fres, 0.0, 1.0));
	float energy = intensity * flow * (0.35 + 0.65 * fres);

	// Soft particle style depth fade against whatever is behind the surface.
	float scene_depth = texture(depth_tex, SCREEN_UV).x;
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	view_pos.xyz /= view_pos.w;
	float behind = -view_pos.z;
	float here = -VERTEX.z;
	float fade = clamp((behind - here) / soft_fade, 0.0, 1.0);

	ALBEDO = color * energy * fade;
	ALPHA = clamp(energy * fade * alpha_scale, 0.0, 1.0);
}
